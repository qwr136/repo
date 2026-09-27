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

// 找键帽 shape：fill 不透明（alpha>=0.99）且投影面积最大的 CAShapeLayer
// （键帽立体阴影层的 fill 是半透明黑，会被 alpha 条件排除）
static CAShapeLayer *RKKeycapShape(UIView *v) {
    __block CAShapeLayer *best = nil;
    __block CGFloat bestArea = 0;
    __block void (^walk)(CALayer *) = nil;
    walk = ^(CALayer *l) {
        if ([l isKindOfClass:[CAShapeLayer class]]) {
            CGColorRef f = ((CAShapeLayer *)l).fillColor;
            if (f) {
                CGFloat a = CGColorGetAlpha(f);
                if (a >= 0.99) {
                    CGFloat area = l.frame.size.width * l.frame.size.height;
                    if (area > bestArea) { bestArea = area; best = (CAShapeLayer *)l; }
                }
            }
        }
        for (CALayer *sub in l.sublayers) { walk(sub); }
    };
    walk(v.layer);
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
static void RKTintKeyboard(UIView *root) {
    if (!root || !RKEnabled()) { return; }
    @try {
        Class keyViewCls = NSClassFromString(@"UIKBKeyView");
        if (!keyViewCls) { return; }

        UIColor *funcColor = nil;
        NSMutableArray *returnKeys = [NSMutableArray array];
        int blueReturnFound = 0;

        NSMutableArray *stack = [NSMutableArray arrayWithObject:root];
        while (stack.count) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            if ([v isKindOfClass:keyViewCls]) {
                NSString *txt = RKDisplayString(v);
                if (RKIsFuncString(txt)) {
                    CAShapeLayer *cap = RKKeycapShape(v);
                    if (cap && cap.fillColor) {
                        UIColor *c = [UIColor colorWithCGColor:cap.fillColor];
                        if (!RKIsBlue(c) && !funcColor) {
                            funcColor = c;
                            RKLog([NSString stringWithFormat:@"取到功能键色: %@ (键=%@)",
                                   NSStringFromCGColor(cap.fillColor), txt]);
                        }
                    }
                } else if (RKIsReturnString(txt)) {
                    [returnKeys addObject:v];
                }
            }
            for (UIView *sub in v.subviews) { [stack addObject:sub]; }
        }

        // 文字取不到时的兜底：键帽是蓝的键也算回车键（覆盖混淆/多语言）
        if (returnKeys.count == 0) {
            NSMutableArray *stack2 = [NSMutableArray arrayWithObject:root];
            while (stack2.count) {
                UIView *v = stack2.lastObject;
                [stack2 removeLastObject];
                if ([v isKindOfClass:keyViewCls]) {
                    CAShapeLayer *cap = RKKeycapShape(v);
                    if (cap && cap.fillColor && RKIsBlue([UIColor colorWithCGColor:cap.fillColor])) {
                        [returnKeys addObject:v];
                        blueReturnFound++;
                    }
                }
                for (UIView *sub in v.subviews) { [stack2 addObject:sub]; }
            }
            if (blueReturnFound) {
                RKLog([NSString stringWithFormat:@"按蓝色键帽兜底识别到 %d 个回车键", blueReturnFound]);
            }
        }

        if (returnKeys.count == 0) { return; }

        if (!funcColor) {
            // 取不到 123 键时用系统功能键灰兜底（浅/深色动态适配）
            funcColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
                return (t.userInterfaceStyle == UIUserInterfaceStyleDark)
                    ? [UIColor colorWithRed:0.357 green:0.373 blue:0.392 alpha:1.0]   // 深色 #5B5F64
                    : [UIColor colorWithRed:0.671 green:0.690 blue:0.729 alpha:1.0]; // 浅色 #ABB0BA
            }];
            RKLog(@"未找到 123 键，使用系统功能键灰兜底");
        }

        for (UIView *rk in returnKeys) {
            RKTintBlueShapes(rk.layer, funcColor);
        }
        RKLog([NSString stringWithFormat:@"已把 %lu 个回车键染成 123 同色", (unsigned long)returnKeys.count]);
    } @catch (NSException *e) {
        RKLog([NSString stringWithFormat:@"染色异常: %@", e]);
    }
}

// 从键往上找键盘布局根，再整棵键盘处理（同一布局短时间只跑一次）
static void RKTintFromKey(UIView *key) {
    @try {
        UIView *root = key;
        for (UIView *v = key; v; v = v.superview) {
            NSString *cn = NSStringFromClass([v class]) ?: @"";
            if ([cn hasPrefix:@"UIKeyboardLayout"]) { root = v; break; }
            if (!v.superview) { root = v; break; }
        }
        NSNumber *done = objc_getAssociatedObject(root, &kRKGenKey);
        if (done.boolValue) { return; }
        objc_setAssociatedObject(root, &kRKGenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                objc_setAssociatedObject(root, &kRKGenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                RKTintKeyboard(root);
            } @catch (NSException *e) {}
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

// 按下高亮可能把键帽恢复成原色（蓝），松手后修一次
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    RKTintFromKey(self);
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    RKTintFromKey(self);
}

%end
