#pragma once
#import "LMVEasterPanel.h"
#import "LMVEasterGeometry.h"
#import <notify.h>
#import <objc/message.h>
#import <string.h>

@class LMVEasterManager;
@interface LMVEasterRoot : UIViewController
@property(nonatomic, weak) LMVEasterManager *manager;
@end
@interface LMVEasterWindow : UIWindow
@property(nonatomic, weak) UIView *bubble;
@property(nonatomic, weak) UIView *panel;
@end
@implementation LMVEasterWindow
- (BOOL)canBecomeKeyWindow { return NO; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01) return nil;
    // Only the actual bubble/panel rectangles accept touches. Navigation,
    // Photos children and contained prompts remain inside that same panel.
    for (UIView *view in @[self.panel ?: [NSNull null], self.bubble ?: [NSNull null]]) {
        if (![view isKindOfClass:UIView.class] || view.hidden || view.alpha < 0.01) continue;
        CGPoint local = [view convertPoint:point fromView:self];
        if ([view pointInside:local withEvent:event]) return [view hitTest:local withEvent:event];
    }
    return nil;
}
@end

@interface LMVEasterManager : NSObject
@property(nonatomic, strong) LMVEasterWindow *window;
@property(nonatomic, strong) UIImageView *bubble;
@property(nonatomic, strong) UINavigationController *panel;
@property(nonatomic, strong) LMVEasterImage *decoded;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *imageKey, *windowReason;
@property(nonatomic, strong) NSTimer *visibilityTimer;
@property(nonatomic) NSUInteger generation, frame;
@property(nonatomic) BOOL pending, ready;
@property(nonatomic) CGPoint normalized;
- (void)refresh;
- (void)closePanel;
- (void)reportWindow:(NSString *)reason;
- (void)layout;
@end
@implementation LMVEasterRoot
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = UIColor.clearColor; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self.manager layout]; }
@end

static BOOL LMVEasterKnownWindow(UIWindow *window, NSArray<NSString *> *names) {
    for (NSString *name in names) { Class cls = NSClassFromString(name); if (cls && [window isKindOfClass:cls]) return YES; }
    return NO;
}
// Inspect only visible bounded drawing branches, not mere persistent window existence.
static BOOL LMVEasterSecurityName(NSString *name) {
    for (NSString *word in @[@"Passcode",@"Authentication",@"Biometric",@"Permission",@"Privacy",@"Authorization",@"LocalAuth",@"Credential"])
        if ([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound) return YES;
    return NO;
}
static BOOL LMVEasterVisibleDrawing(UIView *view, UIWindow *window, NSUInteger depth, NSUInteger *budget, BOOL *security) {
    if (!view || !*budget || depth>7 || view.hidden || view.alpha<0.01) return NO;
    --*budget;
    CGRect rect=CGRectIntersection([view convertRect:view.bounds toView:window],window.bounds);
    if (CGRectIsNull(rect) || CGRectIsEmpty(rect)) return NO;
    if (LMVEasterSecurityName(NSStringFromClass(view.class))) *security=YES;
    CGFloat area=rect.size.width*rect.size.height, full=window.bounds.size.width*window.bounds.size.height;
    BOOL draws=view.layer.contents!=nil || (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor)>0.05) ||
        [view isKindOfClass:UIVisualEffectView.class];
    BOOL substantive=draws && full>0 && area/full>=0.30;
    for (UIView *child in view.subviews) if (LMVEasterVisibleDrawing(child,window,depth+1,budget,security)) substantive=YES;
    return substantive;
}
static BOOL LMVEasterBlockingWindow(UIWindow *window, CGFloat level) {
    if (window.hidden || window.alpha<0.01 || window.screen!=UIScreen.mainScreen) return NO;
    UIViewController *controller=window.rootViewController;
    while (controller.presentedViewController) controller=controller.presentedViewController;
    BOOL visibleSecurity = NO; NSUInteger budget = 96;
    BOOL substantive = LMVEasterVisibleDrawing(controller.viewIfLoaded, window, 0, &budget, &visibleSecurity);
    // Persistent camera/widget/wallpaper windows are not permission dialogs.
    // A security-named window/controller counts only if it visibly draws; a
    // visible security view found in the bounded traversal counts directly.
    BOOL classSecurity = LMVEasterSecurityName(NSStringFromClass(window.class)) ||
        (controller.viewIfLoaded.window == window && LMVEasterSecurityName(NSStringFromClass(controller.class)));
    return visibleSecurity || (classSecurity && substantive) ||
        (window.windowLevel >= UIWindowLevelAlert && substantive);
}
static void LMVEasterDarwin(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    __weak LMVEasterManager *manager = (__bridge LMVEasterManager *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{ [manager refresh]; });
}
@implementation LMVEasterManager
- (instancetype)init {
    self = [super init];
    if (self) {
        _normalized = CGPointMake(0.9, 0.35);
        id x = LMVEasterRead(@"EasterEggX"), y = LMVEasterRead(@"EasterEggY");
        if ([x isKindOfClass:NSNumber.class] && [y isKindOfClass:NSNumber.class] && isfinite([x doubleValue]) && isfinite([y doubleValue])) _normalized = CGPointMake(MAX(0, MIN(1, [x doubleValue])), MAX(0, MIN(1, [y doubleValue])));
        for (NSString *name in @[@"com.minis.lockmessagevideo/preferencesChanged", @"com.apple.springboard.hasBlankedScreen", @"com.apple.springboard.lockstate"]) CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, LMVEasterDarwin, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        for (NSString *name in @[UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeHiddenNotification, UIWindowDidBecomeKeyNotification, UISceneDidActivateNotification, UISceneWillDeactivateNotification, UIApplicationDidBecomeActiveNotification, UIApplicationDidReceiveMemoryWarningNotification]) {
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:) name:name object:nil];
        }
    }
    return self;
}
- (void)dealloc {
    [self.timer invalidate]; [self.visibilityTimer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self];
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self);
}
- (void)changed:(NSNotification *)notification {
    if (notification.object == self.window) return;
    if ([notification.name isEqualToString:UIApplicationDidReceiveMemoryWarningNotification]) {
        self.generation++; self.decoded = nil; self.imageKey = nil; self.bubble.image = nil; [self.timer invalidate]; self.timer = nil;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}
- (void)reportWindow:(NSString *)reason {
    if ([self.windowReason isEqual:reason]) return;
    self.windowReason=reason;
    LMVEasterWindowDiagnostic(reason);
}
- (void)hide {
    self.window.hidden = YES; [self.timer invalidate]; self.timer = nil;
    [self closePanel];
}
- (void)refresh {
    if (!NSThread.isMainThread || !self.ready || self.pending) return;
    self.pending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ self.pending = NO; [self apply]; });
}
- (void)apply {
    CFPreferencesAppSynchronize(LMVEasterPrefs);
    if (![LMVEasterRead(@"EasterEggEnabled") boolValue]) {
        self.generation++; [self hide]; [self.visibilityTimer invalidate]; self.visibilityTimer=nil;
        self.decoded = nil; self.imageKey = nil; self.bubble.image = nil; [self reportWindow:@"disabled"]; return;
    }
    if (!self.visibilityTimer) {
        __weak typeof(self) weakSelf=self;
        self.visibilityTimer=[NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { [weakSelf refresh]; }];
        [NSRunLoop.mainRunLoop addTimer:self.visibilityTimer forMode:NSRunLoopCommonModes];
    }
    // No private singleton construction; published lock/blank state fails closed.
    uint64_t blank = 1, locked = 1;
    BOOL blankKnown = LMVBlankToken >= 0 && notify_get_state(LMVBlankToken, &blank) == NOTIFY_STATUS_OK;
    BOOL lockKnown = LMVLockToken >= 0 && notify_get_state(LMVLockToken, &locked) == NOTIFY_STATUS_OK;
    if (!blankKnown || !lockKnown || blank || locked) {
        [self hide]; [self reportWindow:[NSString stringWithFormat:@"lock-or-screen-gate blankKnown=%d lockKnown=%d blank=%llu locked=%llu", blankKnown, lockKnown, (unsigned long long)blank, (unsigned long long)locked]]; return;
    }
    NSArray *trusted = @[@"SBHomeScreenWindow", @"SBCoverSheetWindow", @"SBControlCenterWindow", @"CCUIOverlayWindow"];
    NSMutableArray<UIWindow *> *windows = [NSMutableArray new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState!=UISceneActivationStateUnattached)
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    UIWindow *host = nil;
    for (UIWindow *window in windows) {
        if (window == self.window || window.hidden || window.alpha < 0.01 || window.screen != UIScreen.mainScreen) continue;
        if (LMVEasterKnownWindow(window, trusted) && window.windowLevel < UIWindowLevelAlert - 1 && (!host || window.windowLevel > host.windowLevel)) host = window;
    }
    if (!host || !host.windowScene) { [self hide]; [self reportWindow:@"no-trusted-main-scene"]; return; }
    // SpringBoard-owned scene above ordinary app surfaces, bounded below alerts.
    CGFloat level = MAX((CGFloat)1200, MIN(host.windowLevel + 1, UIWindowLevelAlert - 1));
    for (UIWindow *window in windows) {
        if (window == self.window || window.hidden || window.alpha < 0.01) continue;
        if (!LMVEasterKnownWindow(window,trusted) && LMVEasterBlockingWindow(window,level)) {
            [self hide]; [self reportWindow:[NSString stringWithFormat:@"blocked class=%@ level=%.0f",NSStringFromClass(window.class),window.windowLevel]]; return;
        }
    }
    if (self.window && self.window.windowScene != host.windowScene) { [self hide]; self.window = nil; self.bubble = nil; }
    if (!self.window) {
        self.window = [[LMVEasterWindow alloc] initWithWindowScene:host.windowScene];
        LMVEasterRoot *root = [LMVEasterRoot new]; root.manager = self;
        self.window.rootViewController = root; self.window.backgroundColor = UIColor.clearColor;
        self.bubble = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
        self.bubble.contentMode = UIViewContentModeScaleAspectFit; self.bubble.userInteractionEnabled = YES;
        self.bubble.isAccessibilityElement = YES; self.bubble.accessibilityLabel = @"小彩蛋"; self.bubble.accessibilityTraits = UIAccessibilityTraitButton;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPanel)]; [tap requireGestureRecognizerToFail:pan];
        [self.bubble addGestureRecognizer:pan]; [self.bubble addGestureRecognizer:tap]; [root.view addSubview:self.bubble]; self.window.bubble = self.bubble;
    }
    self.window.windowLevel = level;
    NSString *path = LMVEasterImagePath(LMVEasterRead(@"EasterEggImage"));
    struct stat info; NSString *key = nil;
    if (path && lstat(path.fileSystemRepresentation, &info) == 0) key = [NSString stringWithFormat:@"%@:%llu:%lld:%lld:%ld", path, (unsigned long long)info.st_ino, (long long)info.st_size, (long long)info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec];
    if (!key) { self.generation++; self.imageKey = nil; self.decoded = nil; self.bubble.image = nil; [self hide]; [self reportWindow:@"hide:image-selection-missing-or-invalid"]; return; }
    if (![self.imageKey isEqualToString:key]) {
        self.imageKey = key; self.decoded = nil; self.frame = 0; self.bubble.image = nil; [self hide]; [self reportWindow:@"hide:image-decode-pending"];
        NSUInteger generation = ++self.generation; __weak typeof(self) weakSelf = self;
        dispatch_async(LMVMaterialQueue(), ^{
            LMVEasterImage *decoded = LMVEasterDecode([NSURL fileURLWithPath:path], NULL);
            dispatch_async(dispatch_get_main_queue(), ^{
                LMVEasterManager *manager = weakSelf;
                if (!manager || generation != manager.generation) return;
                manager.decoded = decoded; [manager refresh];
            });
        }); return;
    }
    if (!self.decoded.frames.count) { [self hide]; [self reportWindow:@"hide:image-decode-unavailable"]; return; }
    [self reportWindow:[NSString stringWithFormat:@"host=%@ level=%.0f scene=%ld",NSStringFromClass(host.class),level,(long)host.windowScene.activationState]];
    self.window.hidden = NO; self.bubble.image = self.decoded.frames[self.frame % self.decoded.frames.count]; [self layout]; [self animateFrame];
}
- (CGRect)dragArea {
    CGRect bounds = self.window.rootViewController.view.bounds;
    UIEdgeInsets safe = self.window.rootViewController.view.safeAreaInsets;
    CGRect inset = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(safe.top + 8, safe.left + 8, safe.bottom + 8, safe.right + 8));
    LMVEasterRect safeRect = { inset.origin.x, inset.origin.y, inset.size.width, inset.size.height };
    LMVEasterRect area = LMVEasterCenterArea(safeRect, LMVEasterSize());
    return CGRectMake(area.x, area.y, area.width, area.height);
}
- (void)layout {
    if (!self.window || !self.bubble) return;
    CGFloat size = LMVEasterSize(); self.bubble.bounds = CGRectMake(0, 0, size, size);
    CGRect area = [self dragArea];
    self.bubble.center = CGPointMake(area.origin.x + area.size.width * self.normalized.x, area.origin.y + area.size.height * self.normalized.y);
    if (self.panel) {
        CGRect bounds = UIEdgeInsetsInsetRect(self.window.rootViewController.view.bounds, self.window.rootViewController.view.safeAreaInsets);
        CGFloat width = MIN(360, MAX(0, bounds.size.width - 24)), height = MIN(550, MAX(0, bounds.size.height * .65));
        self.panel.view.frame = CGRectMake(CGRectGetMidX(bounds) - width / 2, CGRectGetMidY(bounds) - height / 2, width, height);
        self.panel.view.layer.cornerRadius = 20;
        self.panel.view.layer.cornerCurve = kCACornerCurveContinuous;
        self.panel.view.clipsToBounds = YES;
    }
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.window.rootViewController.view]; CGRect area = [self dragArea];
    CGPoint point = CGPointMake(MAX(CGRectGetMinX(area), MIN(CGRectGetMaxX(area), self.bubble.center.x + translation.x)), MAX(CGRectGetMinY(area), MIN(CGRectGetMaxY(area), self.bubble.center.y + translation.y)));
    self.normalized = CGPointMake(LMVEasterNormalizedPosition(point.x, area.origin.x, area.size.width), LMVEasterNormalizedPosition(point.y, area.origin.y, area.size.height));
    self.bubble.center = point; [pan setTranslation:CGPointZero inView:self.window.rootViewController.view];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        LMVEasterSet(@"EasterEggX", @(self.normalized.x)); LMVEasterSet(@"EasterEggY", @(self.normalized.y));
    }
}
- (void)animateFrame {
    if (self.timer || self.window.hidden || self.decoded.frames.count < 2) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:self.decoded.delays[self.frame % self.decoded.delays.count].doubleValue repeats:NO block:^(NSTimer *timer) {
        LMVEasterManager *manager = weakSelf; if (!manager) return;
        manager.timer = nil;
        if (manager.window.hidden || !manager.decoded.frames.count) return;
        manager.frame = (manager.frame + 1) % manager.decoded.frames.count;
        manager.bubble.image = manager.decoded.frames[manager.frame]; [manager animateFrame];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)openPanel {
    if (self.panel || self.window.hidden) return;
    LMVEasterPanel *panel = [LMVEasterPanel new]; __weak typeof(self) weakSelf = self;
    panel.close = ^{ [weakSelf closePanel]; };
    self.panel = [[UINavigationController alloc] initWithRootViewController:panel];
    UIViewController *root = self.window.rootViewController; [root addChildViewController:self.panel]; [root.view addSubview:self.panel.view]; [self.panel didMoveToParentViewController:root];
    self.panel.view.layer.cornerRadius = 20; self.panel.view.layer.cornerCurve = kCACornerCurveContinuous; self.panel.view.clipsToBounds = YES; self.window.panel = self.panel.view; [self layout];
}
- (void)closePanel {
    if (!self.panel) return;
    [self.panel willMoveToParentViewController:nil]; [self.panel.view removeFromSuperview]; [self.panel removeFromParentViewController]; self.panel = nil; self.window.panel = nil;
}
@end
