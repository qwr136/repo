#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

// 键盘回车键同色：把原生键盘右下角的蓝色回车键（发送 / 搜索 / 前往 / 换行 / GO 等）
// 改成和「123」功能键一模一样的键帽灰。
//
// 原理：iOS 键盘键帽是私有类 UIKBKeyView，键帽背景是它 layer 树里的 CAShapeLayer。
//   ① 从同一键盘上「123 / #+=」键的键帽 layer 里实时取灰色（和 123 完全一样，深浅色自动跟随）
//   ② 把回车键（文字命中 发送/搜索/… 或键帽为系统蓝）的蓝色 shape 全部染成这个灰
//   ③ 只染"蓝"不改其他颜色，操作天然幂等；按下高亮恢复蓝色后会在 touch 结束时再修一次
//
// 日志：/var/mobile/Documents/键盘同色日志.txt（排查用，可在偏好里关）

#define kRKPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.returnkeycolor.plist"
#define kRKLogFile   @"/var/mobile/Documents/键盘同色日志.txt"

// UIKBKeyView 是 UIKit 私有键盘键帽视图：声明继承关系，否则 %hook 内
// self.window / 传参给 UIView* 都会报前向类错误
@interface UIKBKeyView : UIView
@end

static char kRKGenKey;

#pragma mark - 偏好与日志

static NSDictionary *_rkPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kRKPrefsFile] ?: @{};
}

static BOOL RKEnabled(void) {
    @try {
        id v = _rkPrefs()[@"RKEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return YES;
}

static BOOL RKLogEnabled(void) {
    @try {
        id v = _rkPrefs()[@"RKLogEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return YES;
}

static void RKLog(NSString *line) {
    if (!RKLogEnabled()) { return; }
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

#pragma mark - 判定

// 回车键的显示文字（各形态）
static BOOL RKIsReturnString(NSString *s) {
    if (s.length == 0) { return NO; }
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

// 功能键文字（取色基准）
static BOOL RKIsFuncString(NSString *s) {
    if (s.length == 0) { return NO; }
    NSString *low = s.lowercaseString;
    return [low isEqualToString:@"123"] || [low isEqualToString:@"#+="] || [low isEqualToString:@"abc"];
}

// 系统蓝键帽判定（systemBlue ≈ (0, 0.478, 1)：蓝分量显著高于红绿才判蓝，
// 普通灰键帽 b-r≈0.06、白键 b-r=0、黑键 b=0 都不会误伤）
static BOOL RKIsBlue(UIColor *c) {
    if (!c) { return NO; }
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) { return NO; }
    return (b > 0.55) && ((b - r) > 0.30) && ((b - g) > 0.15);
}

// 取键上文字：UIKBKeyView.displayString → key.displayString → key.stringRepresentation
static NSString *RKDisplayString(UIView *v) {
    @try {
        id s = nil;
        @try { s = [v valueForKey:@"displayString"]; } @catch (NSException *e) {}
        if ([s isKindOfClass:[NSString class]] && [(NSString *)s length]) { return s; }
        id k = nil;
        @try { k = [v valueForKey:@"key"]; } @catch (NSException *e) {}
        if (k) {
            @try { s = [k valueForKey:@"displayString"]; } @catch (NSException *e) {}
            if ([s isKindOfClass:[NSString class]] && [(NSString *)s length]) { return s; }
            @try { s = [k valueForKey:@"stringRepresentation"]; } @catch (NSException *e) {}
            if ([s isKindOfClass:[NSString class]] && [(NSString *)s length]) { return s; }
        }
    } @catch (NSException *e) {}
    return nil;
}

// 递归收集：fill 不透明（alpha>=0.99）且投影面积最大的 CAShapeLayer（用普通函数避免 block 递归 retain cycle）
static void RKWalkLargestShape(CALayer *l, CAShapeLayer **best, CGFloat *bestArea) {
    if ([l isKindOfClass:[CAShapeLayer class]]) {
        CGColorRef f = ((CAShapeLayer *)l).fillColor;
        if (f && CGColorGetAlpha(f) >= 0.99) {
            CGFloat area = l.frame.size.width * l.frame.size.height;
            if (area > *bestArea) { *bestArea = area; *best = (CAShapeLayer *)l; }
        }
    }
    for (CALayer *sub in l.sublayers) { RKWalkLargestShape(sub, best, bestArea); }
}

// 找键帽 shape（键帽立体阴影层的 fill 是半透明黑，会被 alpha 条件排除）
static CAShapeLayer *RKKeycapShape(UIView *v) {
    CAShapeLayer *best = nil;
    CGFloat bestArea = 0;
    RKWalkLargestShape(v.layer, &best, &bestArea);
    return best;
}

#pragma mark - 染色

// 把视图 layer 树里所有"蓝色"的 CAShapeLayer 染成 target（幂等：灰了就不再动）
static void RKTintBlueShapes(CALayer *l, UIColor *target) {
    if ([l isKindOfClass:[CAShapeLayer class]]) {
        CAShapeLayer *sh = (CAShapeLayer *)l;
        if (sh.fillColor && RKIsBlue([UIColor colorWithCGColor:sh.fillColor])) {
            sh.fillColor = target.CGColor;
        }
    }
    for (CALayer *sub in l.sublayers) { RKTintBlueShapes(sub, target); }
}

// 全键盘扫描：① 从 123 键取灰 ② 给回车键染色
// 颜色量化（用于统计键帽色众数）
static NSString *RKColorKey(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) { return @"?"; }
    return [NSString stringWithFormat:@"%d_%d_%d", (int)(r * 40), (int)(g * 40), (int)(b * 40)];
}

// 日志节流：同一 key 3 秒内只写一次（键盘每次布局都会触发，避免日志刷屏）
static void RKLogThrottled(NSString *key, NSString *line) {
    static NSMutableDictionary *last = nil;
    if (!last) { last = [NSMutableDictionary dictionary]; }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSNumber *t = last[key];
    if (t && (now - t.doubleValue) < 3.0) { return; }
    last[key] = @(now);
    RKLog(line);
}

// 收集键盘上的所有键
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

// 取「功能键灰」（要和 123 键一致）：
//   ① 直接命中 123 / #+= / ABC 键的键帽色
//   ② 取不到文字时用键帽色众数：出现最多的是字母键色（白/深灰），排除它，
//      剩下出现最多的非蓝色就是功能键灰（shift / 123 / 删除 / 地球键共用同一个灰）
static UIColor *RKPickFuncColor(NSArray<UIView *> *keys) {
    for (UIView *kv in keys) {
        NSString *txt = RKDisplayString(kv);
        if (!RKIsFuncString(txt)) { continue; }
        CAShapeLayer *cap = RKKeycapShape(kv);
        if (!cap || !cap.fillColor) { continue; }
        UIColor *c = [UIColor colorWithCGColor:cap.fillColor];
        if (!RKIsBlue(c)) {
            CGFloat r = 0, g = 0, b = 0, a = 0;
            [c getRed:&r green:&g blue:&b alpha:&a];
            RKLogThrottled(@"func123", [NSString stringWithFormat:@"命中 123 键取色 (%.3f, %.3f, %.3f)", r, g, b]);
            return c;
        }
    }

    NSMutableDictionary *freq = [NSMutableDictionary dictionary];
    NSMutableDictionary *sample = [NSMutableDictionary dictionary];
    for (UIView *kv in keys) {
        CAShapeLayer *cap = RKKeycapShape(kv);
        if (!cap || !cap.fillColor) { continue; }
        UIColor *c = [UIColor colorWithCGColor:cap.fillColor];
        if (RKIsBlue(c)) { continue; }
        NSString *k = RKColorKey(c);
        freq[k] = @([freq[k] intValue] + 1);
        if (!sample[k]) { sample[k] = c; }
    }
    NSString *mainKey = nil; int mainCount = 0;
    for (NSString *k in freq) {
        int n = [freq[k] intValue];
        if (n > mainCount) { mainCount = n; mainKey = k; }
    }
    NSString *secondKey = nil; int secondCount = 0;
    for (NSString *k in freq) {
        if ([k isEqualToString:mainKey]) { continue; }
        int n = [freq[k] intValue];
        if (n > secondCount) { secondCount = n; secondKey = k; }
    }
    if (secondKey) {
        UIColor *c = sample[secondKey];
        CGFloat r = 0, g = 0, b = 0, a = 0;
        [c getRed:&r green:&g blue:&b alpha:&a];
        RKLogThrottled(@"funcFreq", [NSString stringWithFormat:@"键帽色统计取到功能键灰 (%.3f, %.3f, %.3f)", r, g, b]);
        return c;
    }
    return nil;
}

static void RKTintKeyboard(UIView *root) {
    if (!root || !RKEnabled()) { return; }
    @try {
        NSArray *keys = RKCollectKeys(root);
        if (keys.count == 0) { return; }

        // 回车键：文字命中（发送/搜索/…）或键帽为系统蓝
        NSMutableArray *returnKeys = [NSMutableArray array];
        for (UIView *kv in keys) {
            NSString *txt = RKDisplayString(kv);
            if (RKIsReturnString(txt)) { [returnKeys addObject:kv]; continue; }
            CAShapeLayer *cap = RKKeycapShape(kv);
            if (cap && cap.fillColor && RKIsBlue([UIColor colorWithCGColor:cap.fillColor])) {
                [returnKeys addObject:kv];
            }
        }
        if (returnKeys.count == 0) { return; }

        UIColor *funcColor = RKPickFuncColor(keys);
        if (!funcColor) {
            funcColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
                return (t.userInterfaceStyle == UIUserInterfaceStyleDark)
                    ? [UIColor colorWithRed:0.357 green:0.373 blue:0.392 alpha:1.0]
                    : [UIColor colorWithRed:0.671 green:0.690 blue:0.729 alpha:1.0];
            }];
            RKLogThrottled(@"funcFallback", @"未识别到功能键灰，使用系统灰兜底");
        }

        for (UIView *rk in returnKeys) { RKTintBlueShapes(rk.layer, funcColor); }
        CGFloat r = 0, g = 0, b = 0, a = 0;
        [funcColor getRed:&r green:&g blue:&b alpha:&a];
        RKLogThrottled(@"tinted", [NSString stringWithFormat:@"已把 %lu 个回车键染成 (%.3f, %.3f, %.3f)，共扫描 %lu 个键",
                                   (unsigned long)returnKeys.count, r, g, b, (unsigned long)keys.count]);
    } @catch (NSException *e) {
        RKLog([NSString stringWithFormat:@"染色异常: %@", e]);
    }
}

// 扫描根：优先键盘布局容器；键还没挂到父视图时用它所在的 window
// （旧版在这里直接拿自己当根，导致只能看到回车键一个，找不到 123 键）
static UIView *RKKeyboardRoot(UIView *key) {
    for (UIView *v = key; v; v = v.superview) {
        NSString *cn = NSStringFromClass([v class]) ?: @"";
        if ([cn hasPrefix:@"UIKeyboardLayout"]) { return v; }
    }
    UIView *top = key;
    for (UIView *v = key; v; v = v.superview) { top = v; }
    return key.window ?: top;
}

// 触发染色：同一根 0.4 秒节流；force 用于按下高亮后立刻重染
static void RKTintFromKey(UIView *key, BOOL force) {
    @try {
        UIView *root = RKKeyboardRoot(key);
        if (!root) { return; }
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (!force) {
            NSNumber *last = objc_getAssociatedObject(root, &kRKGenKey);
            if (last && (now - last.doubleValue) < 0.4) { return; }
        }
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
    if (self.window) { RKTintFromKey(self, NO); }
}

- (void)layoutSubviews {
    %orig;
    RKTintFromKey(self, NO);
}

// 按下高亮可能把键帽恢复成原色（蓝），松手后立刻重染
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    RKTintFromKey(self, YES);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    RKTintFromKey(self, YES);
}

%end
