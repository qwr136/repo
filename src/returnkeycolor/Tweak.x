#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>
#include <string.h>

// 键盘回车键同色 1.0.6
//
// 只做一件事：把原生键盘蓝色回车键（发送 / 搜索 / 前往 / 换行 / GO…）的背景色，
// 改成和「123」功能键一模一样的键帽色。字体大小、圆角、文字颜色全部保持原生。
//
// 前几版的坑（都来自实机诊断）：
//   · 1.0.0~1.0.2 改 CAShapeLayer 的 fillColor —— 键帽根本不是 shape 画的，日志成功、屏幕不动。
//   · 1.0.3 扫系统「蓝键」判定 —— 没找到入口，0 命中。
//   · 1.0.4 把回车键的 displayType 对齐 123 键 —— 颜色对了，但排版跟着功能键样式走，字体变大，已废弃。
//   · 1.0.5 在 displayLayer 之后改 layer.contents —— 诊断文件里 layer 树全是 contents=无，
//     说明键帽是画进图层 backing store 的，contents 是 nil，改了个寂寞，所以又失效了。
//
// 本版：堵住 UIKit 绘制的两个入口，并在「画完之后」直接改像素：
//   ① -drawLayer:inContext:  —— 从上下文取回位图，蓝色像素换色后用 copy 模式写回；
//   ② -displayLayer:          —— 若该 layer（含子层 _UIKBKeyViewLayer）有 CGImage contents 就换色。
//   换色只动蓝色像素、alpha 原样保留，所以圆角、白色文字、抗锯齿边缘都不受影响，排版一个字节都不动。
//   只对原生键盘生效：第三方键盘跑在自己的 .appex 扩展进程里，直接跳过。

#define kRKPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.returnkeycolor.plist"

@interface UIKBKeyView : UIView
- (void)displayLayer:(CALayer *)layer;
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx;
@end

static char kRKGenKey;

static UIColor *gFuncColor = nil;                                    // 123 键的键帽色
static UIUserInterfaceStyle gFuncColorStyle = (UIUserInterfaceStyle)0; // 取色时的深浅色，切了就重取
static int gColorFails = 0;                                          // 取色失败次数，兜底用

#pragma mark - 开关

// 第三方键盘跑在自己的 App Extension 进程里（xxx.appex），一律不生效
static BOOL RKIsAppExtension(void) {
    @try {
        NSDictionary *info = [[NSBundle mainBundle] infoDictionary];
        if (info[@"NSExtension"]) { return YES; }
        if ([[[NSBundle mainBundle] bundlePath] pathExtension].length &&
            [[[[NSBundle mainBundle] bundlePath] pathExtension] isEqualToString:@"appex"]) { return YES; }
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

#pragma mark - 从 123 键实时取色（把键渲染成 8x8 位图，取出现最多的颜色）

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

#pragma mark - 改色：把键帽位图里的蓝色像素换成 123 键的颜色

static void RKRecolorContentsIfBlue(CALayer *layer, UIColor *target) {
    if (!layer || !target) { return; }
    CGImageRef src = NULL;
    @try {
        id contents = layer.contents;
        if (!contents) { return; }
        if (CFGetTypeID((__bridge CFTypeRef)contents) != CGImageGetTypeID()) { return; }
        src = (__bridge CGImageRef)contents;
    } @catch (NSException *e) { return; }

    size_t w = CGImageGetWidth(src), h = CGImageGetHeight(src);
    if (w == 0 || h == 0 || w * h > 600000) { return; }
    size_t bpr = w * 4;
    unsigned char *buf = (unsigned char *)calloc(bpr * h, 1);
    if (!buf) { return; }
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = NULL;
    if (cs) {
        ctx = CGBitmapContextCreate(buf, w, h, 8, bpr, cs,
                                    kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    }
    if (!ctx) { if (cs) { CGColorSpaceRelease(cs); } free(buf); return; }
    CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), src);
    CGContextRelease(ctx);

    CGFloat tr = 0, tg = 0, tb = 0, ta = 0;
    if (![target getRed:&tr green:&tg blue:&tb alpha:&ta]) { if (cs) { CGColorSpaceRelease(cs); } free(buf); return; }

    int hits = 0;
    for (size_t i = 0; i < w * h; i++) {
        unsigned char a = buf[i * 4 + 3];
        if (a == 0) { continue; }
        CGFloat af = (CGFloat)a / 255.0f;
        if (af <= 0.0f) { continue; }
        CGFloat r = ((CGFloat)buf[i * 4 + 0] / 255.0f) / af;   // 位图是 premultiplied，先还原
        CGFloat g = ((CGFloat)buf[i * 4 + 1] / 255.0f) / af;
        CGFloat b = ((CGFloat)buf[i * 4 + 2] / 255.0f) / af;
        if (RKIsBluePixel(r, g, b)) {
            buf[i * 4 + 0] = (unsigned char)(tr * a);          // 只换颜色，alpha 原样保留
            buf[i * 4 + 1] = (unsigned char)(tg * a);
            buf[i * 4 + 2] = (unsigned char)(tb * a);
            hits++;
        }
    }
    if (hits == 0) { if (cs) { CGColorSpaceRelease(cs); } free(buf); return; }

    CGContextRef ctx2 = CGBitmapContextCreate(buf, w, h, 8, bpr, cs,
                                              kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGImageRef out = ctx2 ? CGBitmapContextCreateImage(ctx2) : NULL;
    if (ctx2) { CGContextRelease(ctx2); }
    if (cs) { CGColorSpaceRelease(cs); }
    free(buf);
    if (!out) { return; }
    @try {
        [CATransaction begin];
        [CATransaction setDisableActions:YES];    // 别让换图触发隐式淡入动画
        layer.contents = (__bridge id)out;
        [CATransaction commit];
    } @catch (NSException *e) {}
    CGImageRelease(out);
}

// 整棵 layer 树都扫一遍：键帽可能画在子层 _UIKBKeyViewLayer 上
static void RKRecolorLayerTree(CALayer *l, UIColor *target, int depth) {
    if (!l || depth > 5) { return; }
    RKRecolorContentsIfBlue(l, target);
    for (CALayer *sub in l.sublayers) { RKRecolorLayerTree(sub, target, depth + 1); }
}

// 备用取色通道：键帽画在子层的 contents 上时，直接从那张图取众数色
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

#pragma mark - 主流程

static void RKTintKeyboard(UIView *root) {
    if (!root || !RKEnabled()) { return; }
    @try {
        NSArray *keys = RKCollectKeys(root);
        if (keys.count == 0) { return; }

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
            gColorFails++;
            if (gColorFails > 20) {
                gFuncColor = (style == UIUserInterfaceStyleDark)
                    ? [UIColor colorWithRed:0.357 green:0.373 blue:0.392 alpha:1.0]
                    : [UIColor colorWithRed:0.671 green:0.690 blue:0.729 alpha:1.0];
                gFuncColorStyle = style;
            } else {
                return;
            }
        }

        for (UIView *kv in keys) {
            if (RKIsReturnObj(kv)) { RKRecolorLayerTree(kv.layer, gFuncColor, 0); }
        }
    } @catch (NSException *e) {}
}

// 同一个键盘 0.4 秒内只跑一次（键盘每次布局都会触发）
static void RKTintFromKey(UIView *key) {
    if (!key || !RKEnabled()) { return; }
    @try {
        UIView *root = RKKeyboardRoot(key);
        if (!root) { return; }
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
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

// ① 键帽画完后：该层（或子层 _UIKBKeyViewLayer）若是有 CGImage 的 contents 就换色
- (void)displayLayer:(CALayer *)layer {
    %orig;
    BOOL need = NO;
    @try { need = RKEnabled() && RKIsReturnObj(self) && (gFuncColor != nil); } @catch (NSException *e) {}
    if (!need) { return; }
    @try {
        RKRecolorContentsIfBlue(layer, gFuncColor);
        for (CALayer *sub in layer.sublayers) { RKRecolorContentsIfBlue(sub, gFuncColor); }
    } @catch (NSException *e) {}
}

// ② 走 backing store 绘制时（layer.contents 为 nil 的那条路）：直接在上下文里改像素
- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
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
        }
    } @catch (NSException *e) {}
}

%end
