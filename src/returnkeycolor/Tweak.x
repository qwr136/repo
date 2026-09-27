#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

// 键盘回车键同色 1.0.8（诊断弹窗版）
//
// 目标：回车键（发送 / 搜索 / 换行 / 前往 / GO…）背景 = 123 键的灰，
//       字体大小 / 文字颜色 / 排版 100% 保持原生。
//
// 关键事实（来自实机验证）：
//   1.0.4 那套「把回车键 displayType 换成 123 键的值」确实能变色，但 displayType 是
//   「整包样式」开关——背景、字体、排版一起被换成功能键那一套，所以字体也跟着变大。
//   因此这个开关没法只改背景不动字体，本版彻底不用它。
//   1.0.5/1.0.6 试过像素改色但没命中真实绘制点（盲改）。本版在其实基础上：
//     · 回车键 displayType 保持原生 → 字体 / 文字 / 排版完全原生；
//     · 在键帽位图绘制出来的瞬间，把蓝色像素换成 123 键的灰（alpha 不动 → 圆角 / 白字 / 抗锯齿原样）；
//     · 同时堵住三个可能的绘制入口：
//        ① UIKBKeyView 的 -displayLayer:（若键帽是 contents 图）
//        ② UIKBKeyView 的 -drawLayer:inContext:（若走上下文绘制）
//        ③ 运行时动态 hook 私有键帽图层（_UIKBKeyViewLayer 等 CALayer 子类）的 -drawInContext:
//     · 诊断：在 /var/mobile/Library/Preferences/com.xiaofei.returnkeycolor.plist 加
//        RKDiagnose = true，弹一次键盘会弹窗显示命中了哪个绘制入口（不写任何日志文件）。
//   只对原生键盘生效（第三方键盘扩展进程跳过）。

#define kRKPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.returnkeycolor.plist"

@interface UIKBKeyView : UIView
- (void)displayLayer:(CALayer *)layer;
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx;
@end

// 当前正在绘制的回车键（主线程串行渲染，用一个标记即可在子层绘制时识别）
static __unsafe_unretained UIKBKeyView *gCurReturnKey = nil;

static UIColor *gFuncColor = nil;                                     // 123 键的键帽色（实时取）
static UIUserInterfaceStyle gFuncColorStyle = (UIUserInterfaceStyle)0; // 取色时的深浅色，切了就重取

// 诊断相关（仅 RKDiagnose=true 时起作用，不写文件）
static NSMutableArray *gDiag = nil;
static BOOL gDiagShown = NO;
static BOOL gLayerHooksReady = NO;
static Class gKeyViewCls = Nil;

#pragma mark - 开关

// 第三方键盘跑在自己的 App Extension 进程里（xxx.appex），一律不生效
static BOOL RKIsAppExtension(void) {
    @try {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        if (info[@"NSExtension"]) { return YES; }
        NSString *ext = [[[NSBundle mainBundle] bundlePath] pathExtension];
        if (ext.length && [ext isEqualToString:@"appex"]) { return YES; }
    } @catch (NSException *e) {}
    return NO;
}

static BOOL RKEnabled(void) {
    static BOOL checked = NO;
    static BOOL ext = NO;
    if (!checked) { ext = RKIsAppExtension(); checked = YES; }
    if (ext) { return NO; }
    @try {
        id v = [NSDictionary dictionaryWithContentsOfFile:kRKPrefsFile][@"RKEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return YES;
}

static BOOL RKPrefBool(NSString *k, BOOL def) {
    @try {
        id v = [NSDictionary dictionaryWithContentsOfFile:kRKPrefsFile][k];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return def;
}

static void RKDiag(NSString *fmt, ...) {
    if (!RKPrefBool(@"RKDiagnose", NO)) { return; }
    if (!gDiag) { gDiag = [NSMutableArray array]; }
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    [gDiag addObject:s];
}

#pragma mark - 判定

static BOOL RKHas(const char *hay, const char *needle) {
    if (!hay || !needle || !*needle) { return NO; }
    size_t nl = strlen(needle);
    for (const char *p = hay; *p; p++) {
        size_t i = 0;
        while (i < nl && p[i] && tolower((unsigned char)p[i]) == tolower((unsigned char)needle[i])) { i++; }
        if (i == nl) { return YES; }
    }
    return NO;
}

// 取对象上的显示文字：displayString → stringRepresentation → name/title/text → 递归它的 key
static NSString *RKTextOf(id obj, int depth) {
    if (!obj || depth > 3) { return nil; }
    @try {
        static NSArray *ks = nil;
        if (!ks) { ks = @[@"displayString", @"stringRepresentation", @"representedString", @"name", @"title", @"text"]; }
        for (NSString *k in ks) {
            id v = nil; BOOL got = NO;
            @try { v = [obj valueForKey:k]; got = YES; } @catch (NSException *e) {}
            if (got && [v isKindOfClass:[NSString class]] && [(NSString *)v length]) { return v; }
        }
        id sub = nil; BOOL hasSub = NO;
        @try { sub = [obj valueForKey:@"key"]; hasSub = YES; } @catch (NSException *e) {}
        if (hasSub && sub && sub != obj) { return RKTextOf(sub, depth + 1); }
    } @catch (NSException *e) {}
    return nil;
}

// UIKBTree 的 name（传 UIKBKeyView 也行，自动取它的 key）
static NSString *RKTreeName(id obj) {
    if (!obj) { return nil; }
    @try {
        id tree = obj;
        id k = nil;
        @try { k = [obj valueForKey:@"key"]; } @catch (NSException *e) {}
        if (k) { tree = k; }
        id v = nil;
        @try { v = [tree valueForKey:@"name"]; } @catch (NSException *e) {}
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length]) { return v; }
    } @catch (NSException *e) {}
    return nil;
}

// 是不是回车键：name 含 Return（"Return-Key"），中英文键盘通杀
static BOOL RKIsReturnObj(id obj) {
    if (!obj) { return NO; }
    NSString *nm = RKTreeName(obj);
    if (nm && RKHas(nm.UTF8String, "return")) { return YES; }
    NSString *t = RKTextOf(obj, 0);
    if (!t.length) { return NO; }
    static NSArray *ws = nil;
    if (!ws) {
        ws = @[@"发送", @"搜索", @"前往", @"回车", @"换行", @"确认", @"确定", @"完成", @"加入",
               @"send", @"search", @"go", @"return", @"next", @"done", @"join"];
    }
    NSString *low = t.lowercaseString;
    for (NSString *x in ws) {
        if ([low isEqualToString:x] || [low hasPrefix:x]) { return YES; }
    }
    return NO;
}

// 是不是「123」功能键（取色基准）：name = "More-Key"
static BOOL RKIsMoreObj(id obj) {
    if (!obj) { return NO; }
    NSString *nm = RKTreeName(obj);
    if (nm && [nm caseInsensitiveCompare:@"More-Key"] == NSOrderedSame) { return YES; }
    NSString *t = RKTextOf(obj, 0);
    if (!t.length) { return NO; }
    NSString *low = t.lowercaseString;
    return [low isEqualToString:@"123"] || [low isEqualToString:@"#+="] || [low isEqualToString:@"abc"];
}

// 系统蓝判定（键帽灰 / 白字 / 黑键都不会误伤）
static BOOL RKIsBluePixel(CGFloat r, CGFloat g, CGFloat b) {
    return (b > 0.45) && ((b - r) > 0.28) && ((b - g) > 0.12);
}

static BOOL RKIsBlue(UIColor *c) {
    if (!c) { return NO; }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) { return NO; }
    return RKIsBluePixel(r, g, b);
}

static NSString *RKRGBStr(UIColor *c) {
    if (!c) { return @"(nil)"; }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [c getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"(%.2f,%.2f,%.2f,%.2f)", r, g, b, a];
}

#pragma mark - 位图工具（解图 / 众数取色 / 蓝色像素换色 / 回写）

// 把 CGImage 解成 RGBA(premultiplied) 位图，调用者负责 free
static unsigned char *RKBitmapFromImage(CGImageRef img, size_t *outW, size_t *outH) {
    if (!img) { return NULL; }
    size_t w = CGImageGetWidth(img), h = CGImageGetHeight(img);
    if (w == 0 || h == 0 || w * h > 900000) { return NULL; }
    size_t bpr = w * 4;
    unsigned char *buf = (unsigned char *)calloc(bpr * h, 1);
    if (!buf) { return NULL; }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef c = NULL;
    if (cs) {
        c = CGBitmapContextCreate(buf, w, h, 8, bpr, cs,
                                  kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(cs);
    }
    if (!c) { free(buf); return NULL; }
    CGContextDrawImage(c, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), img);
    CGContextRelease(c);
    *outW = w; *outH = h;
    return buf;
}

static CGImageRef RKImageFromBitmap(const unsigned char *buf, size_t w, size_t h) {
    if (!buf || !w || !h) { return NULL; }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    if (!cs) { return NULL; }
    CGContextRef c = CGBitmapContextCreate((void *)buf, w, h, 8, w * 4, cs,
                                           kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(cs);
    if (!c) { return NULL; }
    CGImageRef img = CGBitmapContextCreateImage(c);
    CGContextRelease(c);
    return img;
}

// 位图里出现最多的颜色（键帽底色；文字只占一小部分）
static UIColor *RKModeColorOfBitmap(const unsigned char *buf, size_t n) {
    NSMutableDictionary *freq = [NSMutableDictionary dictionary];
    NSMutableDictionary *samp = [NSMutableDictionary dictionary];
    for (size_t i = 0; i < n; i++) {
        if (buf[i * 4 + 3] < 250) { continue; }
        NSString *k = [NSString stringWithFormat:@"%d_%d_%d",
                       buf[i * 4 + 0] / 8, buf[i * 4 + 1] / 8, buf[i * 4 + 2] / 8];
        freq[k] = @([freq[k] intValue] + 1);
        if (!samp[k]) { samp[k] = @[@(buf[i * 4 + 0]), @(buf[i * 4 + 1]), @(buf[i * 4 + 2])]; }
    }
    NSString *best = nil; int bn = 0;
    for (NSString *k in freq) {
        int c = [freq[k] intValue];
        if (c > bn) { bn = c; best = k; }
    }
    if (!best) { return nil; }
    NSArray *cc = samp[best];
    return [UIColor colorWithRed:[cc[0] floatValue] / 255.0
                           green:[cc[1] floatValue] / 255.0
                            blue:[cc[2] floatValue] / 255.0
                           alpha:1.0];
}

// 把位图里的蓝色像素换成 target（alpha 原样保留），返回是否改到了
static BOOL RKReplaceBlueInBitmap(unsigned char *buf, size_t n, CGFloat tr, CGFloat tg, CGFloat tb) {
    int hits = 0;
    for (size_t i = 0; i < n; i++) {
        unsigned char a = buf[i * 4 + 3];
        if (a == 0) { continue; }
        CGFloat af = (CGFloat)a / 255.0f;
        if (af <= 0.0f) { continue; }
        CGFloat r = ((CGFloat)buf[i * 4 + 0] / 255.0f) / af;   // premultiplied，先还原
        CGFloat g = ((CGFloat)buf[i * 4 + 1] / 255.0f) / af;
        CGFloat b = ((CGFloat)buf[i * 4 + 2] / 255.0f) / af;
        if (RKIsBluePixel(r, g, b)) {
            buf[i * 4 + 0] = (unsigned char)(tr * a);          // 只换颜色，alpha 不动
            buf[i * 4 + 1] = (unsigned char)(tg * a);
            buf[i * 4 + 2] = (unsigned char)(tb * a);
            hits++;
        }
    }
    return hits > 0;
}

// 绘制上下文里画完之后改色：取回位图 → 换色 → copy 模式写回（圆角 / 白字 / 抗锯齿全部保留）
static void RKRecolorContextIfBlue(CGContextRef ctx, UIColor *target) {
    if (!ctx || !target) { return; }
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    if (!img) { return; }
    size_t w = 0, h = 0;
    unsigned char *buf = RKBitmapFromImage(img, &w, &h);
    CGImageRelease(img);
    if (!buf) { return; }
    CGFloat tr = 0, tg = 0, tb = 0, ta = 0;
    BOOL changed = NO;
    if ([target getRed:&tr green:&tg blue:&tb alpha:&ta]) {
        changed = RKReplaceBlueInBitmap(buf, w * h, tr, tg, tb);
    }
    CGImageRef out = changed ? RKImageFromBitmap(buf, w, h) : NULL;
    free(buf);
    if (!out) { return; }
    CGRect user = CGContextConvertRectToUserSpace(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h));
    CGContextSaveGState(ctx);
    CGContextSetBlendMode(ctx, kCGBlendModeCopy);
    CGContextDrawImage(ctx, user, out);
    CGContextRestoreGState(ctx);
    CGImageRelease(out);
}

// 从绘制上下文里取键帽底色（123 键刚画完时最准）
static UIColor *RKModeColorOfContext(CGContextRef ctx) {
    if (!ctx) { return nil; }
    CGImageRef img = CGBitmapContextCreateImage(ctx);
    if (!img) { return nil; }
    size_t w = 0, h = 0;
    unsigned char *buf = RKBitmapFromImage(img, &w, &h);
    CGImageRelease(img);
    if (!buf) { return nil; }
    UIColor *c = RKModeColorOfBitmap(buf, w * h);
    free(buf);
    return c;
}

#pragma mark - 从 123 键实时取色

static UIColor *RKVisualColorOfView(UIView *v) {
    CGSize sz = v.bounds.size;
    if (sz.width < 6.0 || sz.height < 6.0) { return nil; }
    const int W = 8, H = 8;
    unsigned char *buf = (unsigned char *)calloc((size_t)(W * H * 4), 1);
    if (!buf) { return nil; }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = NULL;
    if (cs) {
        ctx = CGBitmapContextCreate(buf, W, H, 8, W * 4, cs,
                                    kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
        CGColorSpaceRelease(cs);
    }
    if (!ctx) { free(buf); return nil; }
    CGContextScaleCTM(ctx, (CGFloat)W / sz.width, (CGFloat)H / sz.height);
    @try { [v.layer renderInContext:ctx]; } @catch (NSException *e) {}
    CGContextRelease(ctx);

    NSMutableDictionary *freq = [NSMutableDictionary dictionary];
    NSMutableDictionary *samp = [NSMutableDictionary dictionary];
    for (int i = 0; i < W * H; i++) {
        if (buf[i * 4 + 3] < 250) { continue; }   // 跳过圆角外的透明像素
        NSString *k = [NSString stringWithFormat:@"%d_%d_%d",
                       buf[i * 4 + 0] / 8, buf[i * 4 + 1] / 8, buf[i * 4 + 2] / 8];
        freq[k] = @([freq[k] intValue] + 1);
        if (!samp[k]) { samp[k] = @[@(buf[i * 4 + 0]), @(buf[i * 4 + 1]), @(buf[i * 4 + 2])]; }
    }
    free(buf);
    NSString *best = nil; int bn = 0;
    for (NSString *k in freq) {
        int n = [freq[k] intValue];
        if (n > bn) { bn = n; best = k; }
    }
    if (!best) { return nil; }
    NSArray *c = samp[best];   // 文字只占键面一小部分，众数就是键帽底色
    return [UIColor colorWithRed:[c[0] floatValue] / 255.0
                           green:[c[1] floatValue] / 255.0
                            blue:[c[2] floatValue] / 255.0
                           alpha:1.0];
}

// 键帽画在子层的 contents 上时，直接从那张图取众数色
static UIColor *RKColorFromLayerTree(CALayer *l, int depth) {
    if (!l || depth > 4) { return nil; }
    @try {
        id contents = l.contents;
        if (contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID()) {
            CGImageRef img = (__bridge CGImageRef)contents;
            size_t w = 0, h = 0;
            unsigned char *buf = RKBitmapFromImage(img, &w, &h);
            if (buf) {
                UIColor *c = RKModeColorOfBitmap(buf, w * h);
                free(buf);
                if (c) { return c; }
            }
        }
    } @catch (NSException *e) {}
    for (CALayer *sub in l.sublayers) {
        UIColor *c = RKColorFromLayerTree(sub, depth + 1);
        if (c) { return c; }
    }
    return nil;
}

// 整棵 layer 树都扫一遍：键帽可能画在子层 _UIKBKeyViewLayer 上
static void RKRecolorLayerTree(CALayer *l, UIColor *target, int depth) {
    if (!l || depth > 5) { return; }
    @try {
        id contents = l.contents;
        if (contents && CFGetTypeID((__bridge CFTypeRef)contents) == CGImageGetTypeID()) {
            CGImageRef src = (__bridge CGImageRef)contents;
            size_t w = CGImageGetWidth(src), h = CGImageGetHeight(src);
            if (w > 0 && h > 0 && w * h <= 600000) {
                size_t bpr = w * 4;
                unsigned char *buf = (unsigned char *)calloc(bpr * h, 1);
                if (buf) {
                    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
                    CGContextRef ctx = NULL;
                    if (cs) {
                        ctx = CGBitmapContextCreate(buf, w, h, 8, bpr, cs,
                            kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
                    }
                    if (ctx) {
                        CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), src);
                        CGFloat tr = 0, tg = 0, tb = 0, ta = 0;
                        if ([target getRed:&tr green:&tg blue:&tb alpha:&ta]) {
                            if (RKReplaceBlueInBitmap(buf, w * h, tr, tg, tb)) {
                                CGContextRef ctx2 = CGBitmapContextCreate(buf, w, h, 8, bpr, cs,
                                    kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
                                CGImageRef out = ctx2 ? CGBitmapContextCreateImage(ctx2) : NULL;
                                if (ctx2) { CGContextRelease(ctx2); }
                                if (out) {
                                    @try {
                                        [CATransaction begin];
                                        [CATransaction setDisableActions:YES];
                                        l.contents = (__bridge id)out;
                                        [CATransaction commit];
                                    } @catch (NSException *e) {}
                                    CGImageRelease(out);
                                }
                            }
                        }
                        CGContextRelease(ctx);
                    }
                    if (cs) { CGColorSpaceRelease(cs); }
                    free(buf);
                }
            }
        }
    } @catch (NSException *e) {}
    for (CALayer *sub in l.sublayers) { RKRecolorLayerTree(sub, target, depth + 1); }
}

#pragma mark - 运行时 hook 私有键帽图层的绘制入口

// 对一个 CALayer 子类 hook 其 -drawInContext:，在回车键的层上把蓝色像素换成 123 键色。
// 通过 superlayer 链找到所属的 UIKBKeyView 来判断是不是回车键；绘制期间也可用 gCurReturnKey 标记。
static void RKHookDrawInContextForClass(Class c) {
    Method m = class_getInstanceMethod(c, @selector(drawInContext:));
    if (!m) { return; }
    IMP orig = method_getImplementation(m);
    if (!orig) { return; }
    NSString *ident = [NSString stringWithFormat:@"%s.drawInContext:", class_getName(c)];
    // 用关联对象避免重复（简单起见用全局 set）
    static NSMutableSet *done = nil;
    if (!done) { done = [NSMutableSet set]; }
    if ([done containsObject:ident]) { return; }
    [done addObject:ident];
    IMP ni = imp_implementationWithBlock(^(CALayer *me, CGContextRef ctx) {
        ((void (*)(CALayer *, SEL, CGContextRef))orig)(me, @selector(drawInContext:), ctx);
        @try {
            if (!RKEnabled() || !gFuncColor) { return; }
            UIKBKeyView *kv = nil;
            // 私有键帽图层（如 _UIKBKeyViewLayer）的 delegate 往往就是 UIKBKeyView 本身
            if (gKeyViewCls && me.delegate && [me.delegate isKindOfClass:gKeyViewCls]) {
                kv = (UIKBKeyView *)me.delegate;
            }
            // 退一步：沿 superlayer 链找（少数情况下 key 的 layer 直接挂上去）
            if (!kv) {
                for (CALayer *p = me; p; p = p.superlayer) {
                    if (gKeyViewCls && [p isKindOfClass:gKeyViewCls]) { kv = (UIKBKeyView *)p; break; }
                }
            }
            // 再退一步：绘制期间由 UIKBKeyView 的 displayLayer/drawLayer 标定的当前键
            if (!kv && gCurReturnKey) { kv = gCurReturnKey; }
            if (kv && RKIsReturnObj(kv)) {
                RKRecolorContextIfBlue(ctx, gFuncColor);
                RKDiag(@"命中 %s.drawInContext:", class_getName(c));
            }
        } @catch (NSException *e) {}
    });
    method_setImplementation(m, ni);
}

static void RKInstallLayerHooks(void) {
    if (gLayerHooksReady) { return; }
    gLayerHooksReady = YES;
    if (!RKEnabled()) { return; }
    gKeyViewCls = NSClassFromString(@"UIKBKeyView");
    @try {
        unsigned int cnt = 0;
        Class *cls = objc_copyClassList(&cnt);
        if (!cls) { return; }
        Class layerCls = [CALayer class];
        for (unsigned int i = 0; i < cnt; i++) {
            Class c = cls[i];
            const char *cn = class_getName(c);
            // 只 hook 名字里带 KeyView / KBKey 的 CALayer 子类（私有键帽图层），减少误伤
            if (!RKHas(cn, "KeyView") && !RKHas(cn, "KBKey")) { continue; }
            if (![c isSubclassOfClass:layerCls]) { continue; }
            if (c == layerCls) { continue; }
            if (gKeyViewCls && c == gKeyViewCls) { continue; }
            RKHookDrawInContextForClass(c);
        }
        free(cls);
    } @catch (NSException *e) {}
}

#pragma mark - 诊断弹窗（默认关闭，不写文件）

static void RKShowDiagIfNeeded(void) {
    if (gDiagShown) { return; }
    if (!RKPrefBool(@"RKDiagnose", NO)) { return; }
    gDiagShown = YES;
    NSString *msg = gDiag.count ? [gDiag componentsJoinedByString:@"\n"] : @"(无命中记录)";
    msg = [NSString stringWithFormat:@"%@\n123 键色=%@", msg, RKRGBStr(gFuncColor)];
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            UIWindow *w = nil;
            if (@available(iOS 13.0, *)) {
                for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
                    if ([s isKindOfClass:[UIWindowScene class]]) {
                        UIWindowScene *ws = (UIWindowScene *)s;
                        if (ws.windows.count) { w = ws.windows.firstObject; break; }
                    }
                }
            } else {
                w = UIApplication.sharedApplication.keyWindow;
            }
            if (!w || !w.rootViewController) { return; }
            UIAlertController *a = [UIAlertController alertControllerWithTitle:@"键盘同色诊断"
                                                                      message:msg
                                                               preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            UIViewController *rvc = w.rootViewController;
            while (rvc.presentedViewController) { rvc = rvc.presentedViewController; }
            [rvc presentViewController:a animated:YES completion:nil];
        } @catch (NSException *e) {}
    });
}

#pragma mark - 键收集

static NSArray<UIView *> *RKCollectKeys(UIView *root) {
    Class keyViewCls = NSClassFromString(@"UIKBKeyView");
    if (!root || !keyViewCls) { return @[]; }
    NSMutableArray *out = [NSMutableArray array];
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    int guard = 0;
    while (stack.count && guard++ < 4000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        if ([v isKindOfClass:keyViewCls]) { [out addObject:v]; continue; }
        for (UIView *sub in v.subviews) { [stack addObject:sub]; }
    }
    return out;
}

static UIView *RKKeyboardRoot(UIView *key) {
    for (UIView *v = key; v; v = v.superview) {
        if ([NSStringFromClass([v class]) hasPrefix:@"UIKeyboardLayout"]) { return v; }
    }
    return key.window;
}

// 接管显示只影响下一次渲染，装完要让当前键盘重画一次，当次弹出就能看到
static void RKForceRedraw(UIView *root) {
    if (!root) { return; }
    NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
    int guard = 0;
    while (stack.count && guard++ < 3000) {
        UIView *v = stack.lastObject;
        [stack removeLastObject];
        [v setNeedsDisplay];
        for (UIView *s in v.subviews) { [stack addObject:s]; }
    }
    [root setNeedsLayout];
}

#pragma mark - 主流程

static void RKTintKeyboard(UIView *root) {
    if (!root || !RKEnabled()) { return; }
    @try {
        NSArray *keys = RKCollectKeys(root);
        if (keys.count == 0) { return; }

        RKInstallLayerHooks();   // 第一次弹键盘时键盘私有类一定已加载，这时装最准

        // 深浅色切了就跟 123 键重新取一次色
        UIUserInterfaceStyle style = [UITraitCollection currentTraitCollection].userInterfaceStyle;
        if (gFuncColor && gFuncColorStyle != style) { gFuncColor = nil; }

        if (!gFuncColor) {
            for (UIView *kv in keys) {
                if (!RKIsMoreObj(kv)) { continue; }
                UIColor *c = RKVisualColorOfView(kv);          // 通道一：把键渲染成小图取众数
                if (!c) { c = RKColorFromLayerTree(kv.layer, 0); }  // 通道二：直接从子层的图取
                if (c && !RKIsBlue(c)) { gFuncColor = c; gFuncColorStyle = style; break; }
            }
        }
        if (!gFuncColor) {
            // 最后兜底：实在取不到（键还没画完）就用系统键帽灰，至少保证生效
            static int fails = 0; fails++;
            if (fails > 20) {
                gFuncColor = (style == UIUserInterfaceStyleDark)
                    ? [UIColor colorWithRed:0.357 green:0.373 blue:0.392 alpha:1.0]
                    : [UIColor colorWithRed:0.671 green:0.690 blue:0.729 alpha:1.0];
                gFuncColorStyle = style;
            } else {
                return;
            }
        }

        // 像素换色发生在各绘制入口的 hook 里，这里只负责强制重绘触发它们
        if (gFuncColor) {
            dispatch_async(dispatch_get_main_queue(), ^{ RKForceRedraw(root); });
        }
        RKShowDiagIfNeeded();
    } @catch (NSException *e) {}
}

// 同一个键盘 0.4 秒内只跑一次（键盘每次布局都会触发）
static void RKTintFromKey(UIView *key) {
    if (!key || !RKEnabled()) { return; }
    @try {
        UIView *root = RKKeyboardRoot(key);
        if (!root) { return; }
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        static char kRKGenKey;
        NSNumber *last = objc_getAssociatedObject(root, &kRKGenKey);
        if (last && (now - last.doubleValue) < 0.4) { return; }
        objc_setAssociatedObject(root, &kRKGenKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dispatch_async(dispatch_get_main_queue(), ^{
            @try { RKTintKeyboard(root); } @catch (NSException *e) {}
        });
    } @catch (NSException *e) {}
}

#pragma mark - Hook

%hook UIKBKeyView

- (void)didMoveToWindow {
    %orig;
    if (self.window) { RKTintFromKey(self); }
}

- (void)layoutSubviews {
    %orig;
    RKTintFromKey(self);
}

// ① 键帽画完后：若该层（或子层）有 CGImage 的 contents 就换色
- (void)displayLayer:(CALayer *)layer {
    %orig;
    BOOL need = NO;
    @try { need = RKEnabled() && RKIsReturnObj(self) && (gFuncColor != nil); } @catch (NSException *e) {}
    if (!need) { return; }
    @try {
        gCurReturnKey = self;
        RKRecolorLayerTree(layer, gFuncColor, 0);
        RKDiag(@"命中 UIKBKeyView.displayLayer:");
    } @catch (NSException *e) {} @finally { gCurReturnKey = nil; }
}

// ② 走上下文绘制时：直接在绘制出来的位图里改蓝色像素
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
    gCurReturnKey = self;
    %orig;
    @try {
        if (!RKEnabled()) { return; }
        if (RKIsMoreObj(self) && !gFuncColor) {   // 123 键刚画完，这时候取色最准
            UIColor *c = RKModeColorOfContext(ctx);
            if (c && !RKIsBlue(c)) {
                gFuncColor = c;
                gFuncColorStyle = [UITraitCollection currentTraitCollection].userInterfaceStyle;
            }
        }
        if (RKIsReturnObj(self) && gFuncColor) {
            RKRecolorContextIfBlue(ctx, gFuncColor);
            RKDiag(@"命中 UIKBKeyView.drawLayer:inContext:");
        }
    } @catch (NSException *e) {} @finally { gCurReturnKey = nil; }
}

%end

// ③ 兜底：任何 CALayer 的绘制入口（delegate 是回车键的 UIKBKeyView 时才处理）
%hook CALayer

- (void)drawInContext:(CGContextRef)ctx {
    %orig;
    @try {
        if (!RKEnabled() || !gFuncColor) { return; }
        id d = self.delegate;
        if (!d) { return; }
        Class kvc = NSClassFromString(@"UIKBKeyView");
        if (!kvc || ![d isKindOfClass:kvc]) { return; }
        if (!RKIsReturnObj(d)) { return; }
        RKRecolorContextIfBlue(ctx, gFuncColor);
        RKDiag(@"命中 CALayer.drawInContext:(delegate=UIKBKeyView)");
    } @catch (NSException *e) {}
}

%end
