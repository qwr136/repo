#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>
#include <string.h>

// 键盘回车键同色 1.0.5（最终版）
//
// 只做一件事：把原生键盘蓝色回车键（发送 / 搜索 / 前往 / 换行 / GO…）的背景色，
// 改成和「123」功能键一模一样的键帽色。字体大小、圆角、文字颜色全部保持原生。
//
// 原理（来自 1.0.4 的实机诊断）：
//   · 键帽不是任何子图层画的：UIKBKeyView 下面挂的 _UIKBKeyViewLayer frame 全是 0x0，
//     键帽内容是 UIKBKeyView 自己 -displayLayer: 画进图层 backing store 的，
//     所以 1.0.0~1.0.2 改 CAShapeLayer 的 fillColor 完全无效（日志成功、屏幕不动）。
//   · 键盘模型 UIKBTree 的 name 字段很干净：回车键 = "Return-Key"，123 键 = "More-Key"。
//   所以本版在键帽画完之后，直接把位图里的蓝色像素换成从 123 键实时取到的颜色：
//   alpha 原样保留，圆角、白色文字、抗锯齿边缘都不受影响，排版一个字节都不动。
//   1.0.4 试过把回车键的 displayType 对齐 123 键——颜色对了，但字体会跟着功能键样式变大，已废弃。
//   只对原生键盘生效：第三方键盘跑在自己的 .appex 扩展进程里，直接跳过。

#define kRKPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.returnkeycolor.plist"

@interface UIKBKeyView : UIView
- (void)displayLayer:(CALayer *)layer;   // 键帽真正画出来的地方
@end

static char kRKGenKey;

static UIColor *gFuncColor = nil;                                    // 123 键的键帽色
static UIUserInterfaceStyle gFuncColorStyle = (UIUserInterfaceStyle)0; // 取色时的深浅色，切了就重取

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
                UIColor *c = RKVisualColorOfView(kv);
                if (c && !RKIsBlue(c)) { gFuncColor = c; gFuncColorStyle = style; break; }
            }
        }
        if (!gFuncColor) { return; }

        for (UIView *kv in keys) {
            if (RKIsReturnObj(kv)) { RKRecolorContentsIfBlue(kv.layer, gFuncColor); }
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

// 键帽画完之后：只要还是蓝色就换成 123 键的颜色；已经不是蓝色就跳过
- (void)displayLayer:(CALayer *)layer {
    %orig;
    BOOL need = NO;
    @try { need = RKEnabled() && RKIsReturnObj(self) && (gFuncColor != nil); } @catch (NSException *e) {}
    if (need) { RKRecolorContentsIfBlue(layer, gFuncColor); }
}

%end
