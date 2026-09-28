// 微信输入法工具栏
// 纯 Objective-C / Logos，无 Swift。
// 功能：
//   1. 自定义工具栏按钮数量（突破原版 7 个限制）；
//   2. 自定义工具栏左右边距；
//   3. 数值范围保护，防止 UI 崩溃；
//   4. 配套系统设置面板（PreferenceBundle）。
//
// 注入目标：com.tencent.wetype / com.tencent.wetype.keyboard

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#define WK_DOMAIN CFSTR("com.xiaofei.wxkeyboardtoolbar")
#define WK_NOTI   CFSTR("com.xiaofei.wxkeyboardtoolbar/preferences.changed")

// MARK: - 全局配置（已在 tweak 内钳制）
static NSInteger gCount  = 7;     // 1..30
static CGFloat   gMargin = 0.0f;  // 0..200
static BOOL      gDebug  = NO;
static BOOL      gEnableCount = YES;

// 数量覆盖相关
typedef NSInteger (*WKCountIMP)(id, SEL, UICollectionView *, NSInteger);
static WKCountIMP gOrigCountIMP = NULL;
static __weak UICollectionView *gToolbarCV = nil;
static BOOL gDidOverride = NO;

// MARK: - 前向声明
static void wkReloadPrefs(void);
static void wkPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    wkReloadPrefs();
}

// MARK: - 偏好读取（rootless：CFPreferences 自动走 /var/jb/var/mobile/Library/Preferences）
static NSInteger wkPrefInt(NSString *key, NSInteger def) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, WK_DOMAIN);
    if (!v) return def;
    NSInteger r = def;
    if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        r = [(__bridge_transfer NSNumber *)v integerValue];
    } else if (CFGetTypeID(v) == CFStringGetTypeID()) {
        NSString *s = (__bridge_transfer NSString *)v;
        r = [s integerValue];
    } else {
        CFRelease(v);
    }
    return r;
}

static BOOL wkPrefBool(NSString *key, BOOL def) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, WK_DOMAIN);
    if (!v) return def;
    BOOL r = def;
    if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        r = [(__bridge_transfer NSNumber *)v boolValue];
    } else {
        CFRelease(v);
    }
    return r;
}

static NSString *wkPrefString(NSString *key, NSString *def) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, WK_DOMAIN);
    if (!v) return def;
    if (CFGetTypeID(v) == CFStringGetTypeID()) {
        return (__bridge_transfer NSString *)v;
    }
    CFRelease(v);
    return def;
}

// MARK: - 数值校验 / 钳制
static NSInteger wkClampCount(NSInteger raw) {
    return MAX(1, MIN(30, raw));
}

static CGFloat wkClampMargin(CGFloat raw) {
    return MAX(0.0f, MIN(200.0f, raw));
}

static void wkReloadPrefs(void) {
    gCount        = wkClampCount(wkPrefInt(@"ToolbarButtonCount", 7));
    gMargin       = wkClampMargin((CGFloat)wkPrefInt(@"ToolbarMargin", 0));
    gDebug        = wkPrefBool(@"DebugLog", NO);
    gEnableCount  = wkPrefBool(@"EnableCountOverride", YES);
}

// MARK: - 视图树查找
static UIView *wkDeepFirst(UIView *view, BOOL(^pred)(UIView *)) {
    if (!view) return nil;
    if (pred(view)) return view;
    for (UIView *sub in view.subviews) {
        UIView *r = wkDeepFirst(sub, pred);
        if (r) return r;
    }
    return nil;
}

static UIView *wkFindToolbar(UIView *root) {
    NSString *exact = [wkPrefString(@"ToolbarClassName", @"") stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (exact.length > 0) {
        UIView *f = wkDeepFirst(root, ^BOOL(UIView *v) {
            return [NSStringFromClass([v class]) isEqualToString:exact];
        });
        if (f) return f;
    }

    NSArray *patterns = @[@"Toolbar", @"ToolBar", @"CandidateBar", @"AccessoryBar", @"TopBar"];
    for (NSString *p in patterns) {
        UIView *f = wkDeepFirst(root, ^BOOL(UIView *v) {
            return [NSStringFromClass([v class]) containsString:p];
        });
        if (f) return f;
    }
    return nil;
}

// MARK: - 功能 2：左右边距
static void wkApplyMargin(UIView *tb) {
    CGFloat m = gMargin;

    UIEdgeInsets lm = tb.layoutMargins;
    lm.left = m;
    lm.right = m;
    tb.layoutMargins = lm;

    if (@available(iOS 11.0, *)) {
        NSDirectionalEdgeInsets dlm = tb.directionalLayoutMargins;
        dlm.leading = m;
        dlm.trailing = m;
        tb.directionalLayoutMargins = dlm;
    }

    // 内部滚动视图同步 contentInset
    UIScrollView *scroll = (UIScrollView *)wkDeepFirst(tb, ^BOOL(UIView *v) {
        return [v isKindOfClass:[UIScrollView class]];
    });
    if (scroll) {
        UIEdgeInsets ins = scroll.contentInset;
        ins.left = m;
        ins.right = m;
        scroll.contentInset = ins;
        scroll.scrollIndicatorInsets = ins;
    }

    [tb setNeedsLayout];
    [tb layoutIfNeeded];

    if (gDebug) {
        NSLog(@"[WKTB] 已应用左右边距=%@pt -> %@", @(m), NSStringFromClass([tb class]));
    }
}

// MARK: - 功能 1：按钮数量覆盖
static NSInteger wkNewCount(id self, SEL _cmd, UICollectionView *cv, NSInteger section) {
    // 只对记录到的工具栏 collectionView 的 section 0 生效，其余走原实现
    if (gToolbarCV && cv == gToolbarCV && section == 0) {
        return gCount;
    }
    return gOrigCountIMP ? gOrigCountIMP(self, _cmd, cv, section) : 0;
}

static void wkTryOverrideCount(UIView *tb) {
    if (gDidOverride || !gEnableCount) return;

    UICollectionView *cv = (UICollectionView *)wkDeepFirst(tb, ^BOOL(UIView *v) {
        return [v isKindOfClass:[UICollectionView class]];
    });
    if (!cv || !cv.dataSource) return;

    Class cls = object_getClass(cv.dataSource);
    SEL sel = @selector(collectionView:numberOfItemsInSection:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;

    gOrigCountIMP = (WKCountIMP)method_getImplementation(m);
    IMP newImp = imp_implementationWithBlock(^NSInteger(id self, UICollectionView *collectionView, NSInteger section) {
        return wkNewCount(self, sel, collectionView, section);
    });

    // 优先尝试在 dataSource 自身类添加 override，避免污染父类
    BOOL added = class_addMethod(cls, sel, newImp, method_getTypeEncoding(m));
    if (!added) {
        method_setImplementation(m, newImp);
    }

    gToolbarCV = cv;
    gDidOverride = YES;

    if (gDebug) {
        NSLog(@"[WKTB] 已覆盖 %s 的 collectionView:numberOfItemsInSection: count=%@", class_getName(cls), @(gCount));
    }
}

// MARK: - 调试日志
static void wkDumpHierarchy(UIView *view, NSString *indent) {
    if (!view) return;
    NSLog(@"[WKTB] %@%@ frame=%@", indent, NSStringFromClass([view class]), NSStringFromCGRect(view.frame));
    for (UIView *sub in view.subviews) {
        wkDumpHierarchy(sub, [indent stringByAppendingString:@"  "]);
    }
}

// MARK: - 主 hook
%hook UIInputViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig; // 必须调用，否则键盘 UI 不出现

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIView *root = self.view;
        if (gDebug) wkDumpHierarchy(root, @"");

        UIView *tb = wkFindToolbar(root);
        if (tb) {
            wkApplyMargin(tb);
            wkTryOverrideCount(tb);
        } else if (gDebug) {
            NSLog(@"[WKTB] 未找到工具栏视图（可在设置里填写精确类名）");
        }
    });
}

%end

// MARK: - 构造器
%ctor {
    wkReloadPrefs();
    NSLog(@"[WKTB] 已加载，bundle=%@ Debug=%d Count=%ld Margin=%.0f",
          [NSBundle mainBundle].bundleIdentifier, gDebug, (long)gCount, gMargin);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    wkPrefsChangedCallback,
                                    WK_NOTI,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}
