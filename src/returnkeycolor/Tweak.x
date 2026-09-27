#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <QuartzCore/QuartzCore.h>
#include <stdlib.h>
#include <string.h>

// 键盘回车键同色 1.0.3
// 目标：把原生键盘的蓝色回车键（发送 / 搜索 / 前往 / 换行 / GO…）改成和「123」功能键一模一样的键帽色。
//
// 1.0.0~1.0.2 失败的根因：iOS 16 的键帽不是用 CAShapeLayer 的 fillColor 画的，
// 而是一整张预渲染好的位图（圆角 + 底色 + 文字在一起），所以改 fillColor 日志显示成功、屏幕上纹丝不动。
//
// 本版做法：不去猜那张位图在哪，而是让系统自己按「非蓝色键」重新渲染 —— 运行时扫一遍键盘私有类，
// 找到判定「这个键是不是蓝色键」的方法（方法名里带 blue、返回 BOOL），把回车键的判定结果改成 NO。
// 系统判定不是蓝键，就会用普通功能键的配色重画，效果和 123 键一致，且深浅色 / 键盘主题自动跟随。
// 再顺手接管「蓝色键用什么颜色」的方法，返回从 123 键实时取到的颜色做双保险。
// 万一系统里根本没有这类方法（0 命中），才退回位图层的染色兜底。

#define kRKPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.returnkeycolor.plist"
#define kRKLogFile   @"/var/mobile/Documents/键盘同色日志.txt"
#define kRKDumpFile  @"/var/mobile/Documents/键盘结构.txt"

// UIKBKeyView 是 UIKit 私有键盘键帽视图：声明继承关系，否则 %hook 内 self.window / 传 UIView* 都报前向类错误
@interface UIKBKeyView : UIView
@end

static char kRKGenKey;

static BOOL  gHooksReady = NO;   // 是否已扫过键盘私有类
static int   gHookSwitch = 0;    // 命中的「是不是蓝键」判定方法数
static int   gHookColor  = 0;    // 命中的「蓝键颜色」方法数
static UIColor *gFuncColor = nil;// 从 123 键实时取到的键帽色
static NSMutableSet *gHooked = nil;   // 已替换的方法，避免父类子类重复替换
static NSMutableArray *gHitLog = nil; // 命中清单，写进诊断文件

#pragma mark - 偏好 / 日志

static NSDictionary *_rkPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kRKPrefsFile] ?: @{};
}

static BOOL RKPrefBool(NSString *k, BOOL def) {
    @try {
        id v = _rkPrefs()[k];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return def;
}

static void RKLog(NSString *line) {
    if (!RKPrefBool(@"RKLogEnabled", NO)) { return; }
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:kRKLogFile]) {
            [@"键盘回车键同色日志\n" writeToFile:kRKLogFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:kRKLogFile];
        if (!h) { return; }
        [h seekToEndOfFile];
        static NSDateFormatter *fmt = nil;
        if (!fmt) { fmt = [[NSDateFormatter alloc] init]; fmt.dateFormat = @"MM-dd HH:mm:ss"; }
        [h writeData:[[NSString stringWithFormat:@"[%@] %@\n", [fmt stringFromDate:[NSDate date]], line]
                      dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    } @catch (NSException *e) {}
}

#pragma mark - 文字判定

// 回车键的各种显示文字
static BOOL RKIsReturnString(NSString *s) {
    if (![s isKindOfClass:[NSString class]] || s.length == 0) { return NO; }
    static NSArray *w = nil;
    if (!w) {
        w = @[@"发送", @"搜索", @"前往", @"回车", @"换行", @"确认", @"确定", @"完成", @"加入",
              @"send", @"search", @"go", @"return", @"next", @"done", @"join"];
    }
    NSString *low = s.lowercaseString;
    for (NSString *x in w) {
        if ([low isEqualToString:x] || [low hasPrefix:x]) { return YES; }
    }
    return NO;
}

// 功能键文字（取色基准：123 / #+= / ABC）
static BOOL RKIsFuncString(NSString *s) {
    if (![s isKindOfClass:[NSString class]] || s.length == 0) { return NO; }
    NSString *low = s.lowercaseString;
    return [low isEqualToString:@"123"] || [low isEqualToString:@"#+="] || [low isEqualToString:@"abc"];
}

// 大小写不敏感子串匹配（C 串）
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
            id v = nil;
            BOOL got = NO;
            @try { v = [obj valueForKey:k]; got = YES; } @catch (NSException *e) {}
            if (got && [v isKindOfClass:[NSString class]] && [(NSString *)v length]) { return v; }
        }
        id sub = nil;
        BOOL hasSub = NO;
        @try { sub = [obj valueForKey:@"key"]; hasSub = YES; } @catch (NSException *e) {}
        if (hasSub && sub && sub != obj) { return RKTextOf(sub, depth + 1); }
    } @catch (NSException *e) {}
    return nil;
}

// 这个对象是不是「回车键」（发送 / 搜索…）：先按文字判，取不到文字就问系统自己的属性
static BOOL RKIsReturnObj(id obj) {
    if (!obj) { return NO; }
    if (RKIsReturnString(RKTextOf(obj, 0))) { return YES; }
    @try {
        static NSArray *ks = nil;
        if (!ks) { ks = @[@"isReturnKey", @"isReturn", @"returnKey"]; }
        for (NSString *k in ks) {
            if (![obj respondsToSelector:NSSelectorFromString(k)]) { continue; }
            id v = nil;
            @try { v = [obj valueForKey:k]; } @catch (NSException *e) { continue; }
            if ([v respondsToSelector:@selector(boolValue)] && [v boolValue]) { return YES; }
        }
    } @catch (NSException *e) {}
    return NO;
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
        unsigned char a = buf[i * 4 + 3];
        if (a < 250) { continue; }                       // 跳过圆角外的透明像素
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
    NSArray *c = samp[best];                             // 文字只占键面一小部分，众数就是键帽底色
    return [UIColor colorWithRed:[c[0] floatValue] / 255.0
                           green:[c[1] floatValue] / 255.0
                            blue:[c[2] floatValue] / 255.0
                           alpha:1.0];
}

#pragma mark - 运行时接管「蓝键」判定（核心）

// meta = YES 时扫的是类方法（元类）；ident 用 +/- 前缀区分，避免和同名实例方法冲突
static void RKScanClass(Class c, BOOL meta) {
    unsigned n = 0;
    Method *ms = class_copyMethodList(c, &n);
    if (!ms) { return; }
    for (unsigned i = 0; i < n; i++) {
        Method m = ms[i];
        SEL sel = method_getName(m);
        const char *nm = sel_getName(sel);
        if (!RKHas(nm, "blue")) { continue; }            // 只碰名字里带 blue 的
        NSString *ident = [NSString stringWithFormat:@"%@[%s %s]", meta ? @"+" : @"-", class_getName(c), nm];
        if ([gHooked containsObject:ident]) { continue; }

        char rt[64]; rt[0] = 0;
        method_getReturnType(m, rt, sizeof rt);
        unsigned na = method_getNumberOfArguments(m);
        IMP orig = method_getImplementation(m);
        if (!orig) { continue; }

        // ① 「这个键是不是蓝色键」：返回 BOOL 且无参。回车键一律回答 NO → 系统按普通功能键配色重画
        if ((rt[0] == 'B' || rt[0] == 'c') && na == 2) {
            IMP ni = imp_implementationWithBlock(^BOOL(id me) {
                BOOL isRet = NO;
                @try { isRet = RKIsReturnObj(me); } @catch (NSException *e) {}
                if (isRet) { return NO; }
                return ((BOOL (*)(id, SEL))orig)(me, sel);
            });
            method_setImplementation(m, ni);
            [gHooked addObject:ident];
            gHookSwitch++;
            [gHitLog addObject:[NSString stringWithFormat:@"[判定] %@[%s %s] → 回车键返回 NO", meta ? @"+" : @"-", class_getName(c), nm]];
            continue;
        }

        // ② / ②b 带一个参数：- (BOOL)xxxBluexxx:(id)key 或 :(long long)state
        if ((rt[0] == 'B' || rt[0] == 'c') && na == 3) {
            char at[64]; at[0] = 0;
            method_getArgumentType(m, 2, at, sizeof at);
            if (at[0] == '@') {
                IMP ni = imp_implementationWithBlock(^BOOL(id me, id arg) {
                    BOOL isRet = NO;
                    @try { isRet = RKIsReturnObj(arg) || RKIsReturnObj(me); } @catch (NSException *e) {}
                    if (isRet) { return NO; }
                    return ((BOOL (*)(id, SEL, id))orig)(me, sel, arg);
                });
                method_setImplementation(m, ni);
                [gHooked addObject:ident];
                gHookSwitch++;
                [gHitLog addObject:[NSString stringWithFormat:@"[判定] %@[%s %s] → 回车键返回 NO", meta ? @"+" : @"-", class_getName(c), nm]];
            } else if (strchr("ilqILQScB", at[0])) {
                // 参数是 state / type 这类整数，只能按 self 判断
                IMP ni = imp_implementationWithBlock(^BOOL(id me, long long x) {
                    BOOL isRet = NO;
                    @try { isRet = RKIsReturnObj(me); } @catch (NSException *e) {}
                    if (isRet) { return NO; }
                    return ((BOOL (*)(id, SEL, long long))orig)(me, sel, x);
                });
                method_setImplementation(m, ni);
                [gHooked addObject:ident];
                gHookSwitch++;
                [gHitLog addObject:[NSString stringWithFormat:@"[判定] %@[%s %s] (int参数) → 回车键返回 NO", meta ? @"+" : @"-", class_getName(c), nm]];
            }
            continue;
        }

        // ③ 「蓝色键用什么颜色」：返回 UIColor 且无参 → 直接给从 123 键取到的颜色
        if (rt[0] == '@' && RKHas(nm, "color") && na == 2) {
            IMP ni = imp_implementationWithBlock(^id(id me) {
                UIColor *cc = nil;
                @try { cc = gFuncColor; } @catch (NSException *e) {}
                if (cc) { return cc; }
                return ((id (*)(id, SEL))orig)(me, sel);
            });
            method_setImplementation(m, ni);
            [gHooked addObject:ident];
            gHookColor++;
            [gHitLog addObject:[NSString stringWithFormat:@"[颜色] %@[%s %s] → 返回 123 键色", meta ? @"+" : @"-", class_getName(c), nm]];
        }
    }
    free(ms);
}

static int RKInstallHooks(void) {
    if (gHooksReady) { return gHookSwitch + gHookColor; }
    gHooksReady = YES;
    if (!RKPrefBool(@"RKEnabled", YES)) { return 0; }
    gHooked = [NSMutableSet set];
    gHitLog = [NSMutableArray array];
    @try {
        unsigned int cnt = 0;
        Class *cls = objc_copyClassList(&cnt);
        if (!cls) { return 0; }
        for (int i = 0; i < cnt; i++) {
            Class c = cls[i];
            const char *cn = class_getName(c);
            if (strncmp(cn, "UIKB", 4) != 0 && !RKHas(cn, "Keyboard")) { continue; }
            for (Class p = c; p && p != [NSObject class]; p = class_getSuperclass(p)) { RKScanClass(p, NO); }
            Class meta = object_getClass(c);
            if (meta && class_isMetaClass(meta)) { RKScanClass(meta, YES); }
        }
        free(cls);
        RKLog([NSString stringWithFormat:@"接管完成：判定方法 %d 个，颜色方法 %d 个", gHookSwitch, gHookColor]);
    } @catch (NSException *e) {
        RKLog([NSString stringWithFormat:@"接管异常: %@", e]);
    }
    return gHookSwitch + gHookColor;
}

#pragma mark - 兜底：直接改键帽图层（1.0.2 的老办法，仅在上面 0 命中时使用）

static BOOL RKIsBlue(UIColor *c) {
    if (!c) { return NO; }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) { return NO; }
    return (b > 0.55) && ((b - r) > 0.30) && ((b - g) > 0.15);
}

static void RKTintBlueShapes(CALayer *l, UIColor *target) {
    if ([l isKindOfClass:[CAShapeLayer class]]) {
        CAShapeLayer *sh = (CAShapeLayer *)l;
        if (sh.fillColor && RKIsBlue([UIColor colorWithCGColor:sh.fillColor])) { sh.fillColor = target.CGColor; }
    }
    for (CALayer *sub in l.sublayers) { RKTintBlueShapes(sub, target); }
}

#pragma mark - 键收集 / 强制重画

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

// 扫描根：键盘布局容器优先；键还没挂上去时用 window
static UIView *RKKeyboardRoot(UIView *key) {
    for (UIView *v = key; v; v = v.superview) {
        if ([NSStringFromClass([v class]) hasPrefix:@"UIKeyboardLayout"]) { return v; }
    }
    return key.window;
}

// 接管判定只影响「下一次渲染」，所以装完 hook 要让当前键盘重画一次，当次就能看到效果
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

#pragma mark - 诊断文件（一次；命中清单 + 候选方法，方便下次一次改准）

static NSString *RKRGBStr(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) { return @"?"; }
    return [NSString stringWithFormat:@"(%.3f,%.3f,%.3f,%.2f)", r, g, b, a];
}

static void RKDumpLayer(CALayer *l, int depth, NSMutableString *out) {
    if (depth > 6) { return; }
    NSString *pad = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSString *fill = @"-";
    if ([l isKindOfClass:[CAShapeLayer class]] && ((CAShapeLayer *)l).fillColor) {
        fill = RKRGBStr([UIColor colorWithCGColor:((CAShapeLayer *)l).fillColor]);
    }
    NSString *bg = l.backgroundColor ? RKRGBStr([UIColor colorWithCGColor:l.backgroundColor]) : @"-";
    [out appendFormat:@"%@%@ | %.0f,%.0f %.0fx%.0f | fill %@ | bg %@ | contents=%@ | op=%.2f\n",
     pad, NSStringFromClass([l class]), l.frame.origin.x, l.frame.origin.y,
     l.frame.size.width, l.frame.size.height, fill, bg, (l.contents ? @"有图" : @"无"), l.opacity];
    for (CALayer *s in l.sublayers) { RKDumpLayer(s, depth + 1, out); }
}

static BOOL gDumpDone = NO;

static void RKDumpOnce(NSArray *keys) {
    if (gDumpDone) { return; }
    gDumpDone = YES;
    @try {
        NSMutableString *o = [NSMutableString string];
        [o appendFormat:@"键盘结构诊断 v1.0.3 (共 %lu 个键)\n", (unsigned long)keys.count];
        [o appendFormat:@"命中：判定方法 %d 个 / 颜色方法 %d 个\n", gHookSwitch, gHookColor];
        for (NSString *h in gHitLog) { [o appendFormat:@"  %@\n", h]; }
        [o appendFormat:@"123 键取色：%@\n", gFuncColor ? RKRGBStr(gFuncColor) : @"(未取到)"];

        UIView *retK = nil, *funcK = nil, *norK = nil;
        for (UIView *kv in keys) {
            NSString *t = RKTextOf(kv, 0);
            if (!retK && RKIsReturnString(t)) { retK = kv; }
            else if (!funcK && RKIsFuncString(t)) { funcK = kv; }
            else if (!norK && t.length && !RKIsReturnString(t) && !RKIsFuncString(t)) { norK = kv; }
        }
        UIView *arr[3] = { retK, funcK, norK };
        NSString *tag[3] = { @"回车键(蓝)", @"123功能键(基准)", @"普通键" };
        for (int i = 0; i < 3; i++) {
            UIView *kv = arr[i];
            if (!kv) { continue; }
            [o appendFormat:@"\n===== %@ | %@ | %.0fx%.0f =====\n", tag[i],
             NSStringFromClass([kv class]), kv.frame.size.width, kv.frame.size.height];
            [o appendFormat:@"  文字: %@\n", RKTextOf(kv, 0) ?: @"(取不到)"];
            UIColor *vc = RKVisualColorOfView(kv);
            [o appendFormat:@"  视觉取色: %@\n", vc ? RKRGBStr(vc) : @"?"];
            [o appendString:@"  --- layer 树 ---\n"];
            RKDumpLayer(kv.layer, 1, o);
        }

        // 候选方法清单：万一 0 命中，从这份清单里挑真正的改色入口
        [o appendString:@"\n===== 含 blue / color 的键盘私有方法 =====\n"];
        unsigned int cnt = 0;
        Class *cls = objc_copyClassList(&cnt);
        NSArray *kws = @[@"blue", @"keycap", @"keycolor", @"keycapcolor", @"appearance"];
        if (cls) {
            for (int i = 0; i < cnt; i++) {
                Class c = cls[i];
                const char *cn = class_getName(c);
                if (strncmp(cn, "UIKB", 4) != 0 && !RKHas(cn, "Keyboard")) { continue; }
                NSMutableArray *hits = [NSMutableArray array];
                NSMutableSet *seen = [NSMutableSet set];
                for (Class p = c; p && p != [NSObject class]; p = class_getSuperclass(p)) {
                    unsigned n = 0; Method *ms = class_copyMethodList(p, &n);
                    if (!ms) { continue; }
                    for (unsigned j = 0; j < n; j++) {
                        NSString *sn = NSStringFromSelector(method_getName(ms[j]));
                        if ([seen containsObject:sn]) { continue; }
                        NSString *lo = sn.lowercaseString;
                        for (NSString *k in kws) {
                            if ([lo containsString:k]) { [seen addObject:sn]; [hits addObject:sn]; break; }
                        }
                    }
                    free(ms);
                }
                if (hits.count) {
                    [o appendFormat:@"\n%@:\n", [NSString stringWithUTF8String:cn]];
                    for (NSString *s in hits) { [o appendFormat:@"  %@\n", s]; }
                }
            }
            free(cls);
        }
        [o writeToFile:kRKDumpFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        RKLog(@"诊断已写入 键盘结构.txt");
    } @catch (NSException *e) {}
}

#pragma mark - 主流程

static void RKTintKeyboard(UIView *root) {
    if (!root) { return; }
    @try {
        NSArray *keys = RKCollectKeys(root);
        if (keys.count == 0) { return; }

        RKInstallHooks();   // 第一次弹键盘时键盘私有类一定已加载，这时扫最准

        // 从 123 键取色（供颜色类方法替换用；判定法不需要它）
        if (!gFuncColor) {
            for (UIView *kv in keys) {
                if (!RKIsFuncString(RKTextOf(kv, 0))) { continue; }
                UIColor *c = RKVisualColorOfView(kv);
                if (c && !RKIsBlue(c)) { gFuncColor = c; break; }
            }
        }

        RKDumpOnce(keys);

        // 0 命中才用老办法硬改图层，避免两套逻辑互相打架
        if (gHookSwitch == 0 && gHookColor == 0) {
            UIColor *target = gFuncColor;
            if (!target) {
                target = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
                    return (t.userInterfaceStyle == UIUserInterfaceStyleDark)
                        ? [UIColor colorWithRed:0.357 green:0.373 blue:0.392 alpha:1.0]
                        : [UIColor colorWithRed:0.671 green:0.690 blue:0.729 alpha:1.0];
                }];
            }
            int hit = 0;
            for (UIView *kv in keys) {
                if (RKIsReturnString(RKTextOf(kv, 0))) { RKTintBlueShapes(kv.layer, target); hit++; }
            }
            RKLog([NSString stringWithFormat:@"兜底染色 %d 个键（未找到系统蓝键判定入口）", hit]);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ RKForceRedraw(root); });
        }
    } @catch (NSException *e) {
        RKLog([NSString stringWithFormat:@"异常: %@", e]);
    }
}

static void RKTintFromKey(UIView *key) {
    if (!key || !RKPrefBool(@"RKEnabled", YES)) { return; }
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

// 按下 / 松手后系统可能按原色重画，这里再补一次（用局部强引用，避免 block 直接捕获 self）
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    UIKBKeyView *k = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *root = RKKeyboardRoot(k);
        if (root) { RKTintKeyboard(root); }
    });
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    UIKBKeyView *k = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *root = RKKeyboardRoot(k);
        if (root) { RKTintKeyboard(root); }
    });
}

%end

%ctor {
    @try {
        // 进程启动时键盘私有类可能还没加载；没扫到就先不标记，等键盘真的弹出来再扫一次
        if (RKPrefBool(@"RKInstallEarly", YES) && RKInstallHooks() == 0) { gHooksReady = NO; }
    } @catch (NSException *e) {}
}
