/* WetypeToolbarPlus - 微信输入法工具栏增强
 * 注入进程:
 *   com.tencent.wetype.keyboard  (wxkb_plugin, 键盘扩展进程)
 *   com.tencent.wetype           (wxkb, 主 App 进程 —— 工具栏按钮数量上限可能在这里被限制)
 *
 * 功能:
 *   1. 解除工具栏按钮最多 7 个的限制，最多 20 个
 *   2. 自定义工具栏左右边距、按钮之间的间距
 *   3. 设置面板（设置 → 微信输入法工具栏增强, 域: com.wetypeplus）
 */

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define TP_DOMAIN CFSTR("com.wetypeplus")

static BOOL      tpEnabled     = YES;
static NSInteger tpMaxButtons  = 20;
static CGFloat   tpSpacing     = 0;   // 0 = 不修改（使用原版）
static CGFloat   tpLeftMargin  = 0;   // 0 = 不修改
static CGFloat   tpRightMargin = 0;   // 0 = 不修改
static BOOL      tpDebug       = NO;
static BOOL      tpInKeyboardProcess = NO;

static CFTimeInterval tpLastPrefLoad = 0;

#pragma mark - Preferences

static id TPPref(NSString *key, id def) {
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, TP_DOMAIN));
    return v ? v : def;
}

static void TPReloadPrefs(void) {
    tpEnabled      = [TPPref(@"enabled", @YES) boolValue];
    NSInteger mb   = [TPPref(@"maxButtons", @20) integerValue];
    tpMaxButtons   = (NSInteger)MAX(1, MIN(20, mb));
    tpSpacing      = MAX(0.f, [TPPref(@"hSpacing", @0) floatValue]);
    tpLeftMargin   = MAX(0.f, [TPPref(@"leftMargin", @0) floatValue]);
    tpRightMargin  = MAX(0.f, [TPPref(@"rightMargin", @0) floatValue]);
    tpDebug        = [TPPref(@"debugLog", @NO) boolValue];
    CFPreferencesAppSynchronize(TP_DOMAIN);
}

static void TPLoadPrefsThrottled(void) {
    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    if (now - tpLastPrefLoad > 1.5) {
        tpLastPrefLoad = now;
        TPReloadPrefs();
    }
}

#define TPLOG(fmt, ...) do { if (tpDebug) NSLog(@"[WetypeToolbarPlus] " fmt, ##__VA_ARGS__); } while (0)

#pragma mark - Heuristics

static BOOL TPInKeyboardProcess(void) {
    NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    if ([bid isEqualToString:@"com.tencent.wetype.keyboard"]) return YES;
    if ([bid hasSuffix:@".keyboard"] || [bid hasSuffix:@".extension"]) return YES;
    return NO;
}

/* 键盘工具栏判断: 顶部一排水平排列的小圆按钮 */
static BOOL TPLooksLikeToolbarStack(UIStackView *sv) {
    if (sv.axis != UILayoutConstraintAxisHorizontal) return NO;
    if (sv.arrangedSubviews.count < 2) return NO;
    CGFloat h = sv.bounds.size.height, w = sv.bounds.size.width;
    if (h < 22 || h > 96) return NO;
    if (w < 100) return NO;
    return YES;
}

static BOOL TPLooksLikeToolbarCollection(UICollectionViewFlowLayout *fl) {
    UICollectionView *cv = fl.collectionView;
    if (!cv) return NO;
    if (fl.scrollDirection != UICollectionViewScrollDirectionHorizontal) return NO;
    CGFloat h = cv.bounds.size.height;
    if (h < 22 || h > 96) return NO;
    if (cv.bounds.size.width < 100) return NO;
    return YES;
}

static void TPApplyToolbarSpacing(UIStackView *sv) {
    if (tpSpacing > 0) {
        sv.spacing = tpSpacing;
        for (UIView *sub in sv.arrangedSubviews) {
            [sv setCustomSpacing:tpSpacing afterSubview:sub];
        }
    }
    if (tpLeftMargin > 0 || tpRightMargin > 0) {
        UIEdgeInsets m = sv.layoutMargins;
        m.left  = tpLeftMargin  > 0 ? tpLeftMargin  : m.left;
        m.right = tpRightMargin > 0 ? tpRightMargin : m.right;
        sv.layoutMargins = m;
        sv.layoutMarginsFollowReadableWidth = NO;
        sv.insetsLayoutMarginsFromSafeArea = NO;
    }
    [sv setNeedsLayout];
}

#pragma mark - Hook: UIStackView (工具栏按钮间距/边距)

%hook UIStackView

- (void)layoutSubviews {
    %orig;
    if (!tpInKeyboardProcess) return;
    if (![self isKindOfClass:%c(UIStackView)]) return;
    UIStackView *sv = (UIStackView *)self;
    if (!TPLooksLikeToolbarStack(sv)) return;
    TPLoadPrefsThrottled();
    if (!tpEnabled) return;
    TPLOG(@"toolbar stackview hit: %@ arranged=%lu",
          NSStringFromClass(sv.class), (unsigned long)sv.arrangedSubviews.count);
    TPApplyToolbarSpacing(sv);
}

%end

#pragma mark - Hook: UICollectionViewFlowLayout (若工具栏由 CollectionView 实现)

%hook UICollectionViewFlowLayout

- (void)prepareLayout {
    %orig;
    if (!tpInKeyboardProcess) return;
    UICollectionViewFlowLayout *fl = (UICollectionViewFlowLayout *)self;
    if (!TPLooksLikeToolbarCollection(fl)) return;
    TPLoadPrefsThrottled();
    if (!tpEnabled) return;
    TPLOG(@"toolbar collection hit: sections=%lu",
          (unsigned long)fl.collectionView.numberOfSections);
    if (tpSpacing > 0) {
        fl.minimumInteritemSpacing = tpSpacing;
        fl.minimumLineSpacing = tpSpacing;
    }
    if (tpLeftMargin > 0 || tpRightMargin > 0) {
        UIEdgeInsets inset = fl.sectionInset;
        inset.left  = tpLeftMargin  > 0 ? tpLeftMargin  : inset.left;
        inset.right = tpRightMargin > 0 ? tpRightMargin : inset.right;
        fl.sectionInset = inset;
    }
}

%end

#pragma mark - 动态钩子: 解除按钮数量限制

/* 微信输入法内部的“工具栏最多 7 个按钮”限制, 通常表现为某个工具/配置类里
 * 返回 7 的整数型方法(max/limit...)。这里在运行时扫描类名含 tool/panel 的类,
 * 把其中“当前返回 7”的无参整型 max/limit 方法改为返回用户设置的上限(默认 20)。
 * 只改 max/limit 命名的方法, 不碰普通 count/number getter, 避免误伤数据逻辑。 */

static void TPDynamicHooks(void) {
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (!classes) return;

    int hookedLimits = 0, hookedProbes = 0;

    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        NSString *clsName = NSStringFromClass(cls);
        if (!clsName) continue;
        NSString *lower = [clsName lowercaseString];
        BOOL toolClass = [lower containsString:@"tool"] || [lower containsString:@"panel"];
        if (!toolClass) continue;

        unsigned int mCount = 0;
        Method *methods = class_copyMethodList(cls, &mCount);
        for (unsigned int j = 0; j < mCount; j++) {
            Method m = methods[j];
            SEL sel = method_getName(m);
            NSString *selName = NSStringFromSelector(sel);
            NSString *selLower = [selName lowercaseString];

            unsigned int args = method_getNumberOfArguments(m);
            if (args != 2) continue; /* 只处理无额外参数的方法 (self, _cmd) */

            char ret = *method_getReturnType(m);
            BOOL intReturn = (ret == 'q' || ret == 'l' || ret == 'i' || ret == 's' || ret == 'B' || ret == 'c');
            BOOL objReturn = (ret == '@');

            BOOL limitNamed = [selLower containsString:@"max"] || [selLower containsString:@"limit"];
            BOOL toolNamed  = [selLower containsString:@"tool"] ||
                              [selLower containsString:@"button"] ||
                              [selLower containsString:@"item"];

            /* 1) 数量上限: max/limit 命名 + 整型返回 */
            if (limitNamed && intReturn) {
                IMP orig = method_getImplementation(m);
                SEL s = sel;
                long (^blk)(id) = ^long(id selfc) {
                    long r = ((long (*)(id, SEL))orig)(selfc, s);
                    if (tpEnabled && r == 7 && tpMaxButtons > 7) {
                        TPLOG(@"unlock limit: [%@ %@] 7 -> %ld", clsName, selName, (long)tpMaxButtons);
                        return (long)tpMaxButtons;
                    }
                    return r;
                };
                method_setImplementation(m, imp_implementationWithBlock(blk));
                hookedLimits++;
                continue;
            }

            /* 2) 诊断探针: 工具项相关、返回数组的方法, 打开“诊断日志”后输出类名/方法名,
             *    便于后续精确定位内部类名(如果通用启发式没覆盖到) */
            if (tpDebug && toolNamed && objReturn) {
                IMP orig = method_getImplementation(m);
                SEL s = sel;
                id (^blk)(id) = ^id(id selfc) {
                    id r = ((id (*)(id, SEL))orig)(selfc, s);
                    if ([r isKindOfClass:NSArray.class]) {
                        TPLOG(@"probe: [%@ %@] -> %@ items", clsName, selName, @(r ? [(NSArray *)r count] : 0));
                    }
                    return r;
                };
                method_setImplementation(m, imp_implementationWithBlock(blk));
                hookedProbes++;
            }
        }
        free(methods);
    }
    free(classes);

    if (hookedLimits || hookedProbes) {
        TPLOG(@"dynamic hooks installed: limits=%d probes=%d", hookedLimits, hookedProbes);
    }
}

#pragma mark - Constructor

%ctor {
    @autoreleasepool {
        TPReloadPrefs();
        tpInKeyboardProcess = TPInKeyboardProcess();
        TPDynamicHooks();
        NSLog(@"[WetypeToolbarPlus] loaded in %@ (keyboardProcess=%d, maxButtons=%ld)",
              [[NSBundle mainBundle] bundleIdentifier] ?: @"?",
              tpInKeyboardProcess, (long)tpMaxButtons);
    }
}
