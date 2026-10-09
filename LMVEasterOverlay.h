#pragma once
#import "LMVEasterPanel.h"
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
    // Our presented picker/alert is part of the panel, never a system window.
    UIViewController *modal = self.rootViewController;
    while (modal.presentedViewController) modal = modal.presentedViewController;
    if (modal != self.rootViewController && modal.viewIfLoaded.window == self) {
        CGPoint local = [modal.view convertPoint:point fromView:self];
        if ([modal.view pointInside:local withEvent:event]) return [modal.view hitTest:local withEvent:event];
        return nil;
    }
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
@property(nonatomic, copy) NSString *imageKey;
@property(nonatomic) NSUInteger generation, frame;
@property(nonatomic) BOOL pending, ready;
@property(nonatomic) CGPoint normalized;
- (void)refresh;
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
    [self.timer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self];
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self);
}
- (void)changed:(NSNotification *)notification {
    if (notification.object == self.window) return;
    if ([notification.name isEqualToString:UIApplicationDidReceiveMemoryWarningNotification]) {
        self.generation++; self.decoded = nil; self.imageKey = nil; self.bubble.image = nil; [self.timer invalidate]; self.timer = nil;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
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
        self.generation++; [self hide]; self.decoded = nil; self.imageKey = nil; self.bubble.image = nil; return;
    }
    // No private singleton construction; published lock/blank state fails closed.
    uint64_t blank = 1, locked = 1;
    if (LMVBlankToken < 0 || LMVLockToken < 0 || notify_get_state(LMVBlankToken, &blank) != NOTIFY_STATUS_OK || notify_get_state(LMVLockToken, &locked) != NOTIFY_STATUS_OK || blank || locked) { [self hide]; return; }
    NSArray *trusted = @[@"SBHomeScreenWindow", @"SBCoverSheetWindow", @"SBControlCenterWindow", @"CCUIOverlayWindow"];
    NSMutableArray<UIWindow *> *windows = [NSMutableArray new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState == UISceneActivationStateForegroundActive) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    UIWindow *host = nil;
    for (UIWindow *window in windows) {
        if (window == self.window || window.hidden || window.alpha < 0.01 || window.screen != UIScreen.mainScreen) continue;
        if (LMVEasterKnownWindow(window, trusted) && window.windowLevel < UIWindowLevelAlert - 1 && (!host || window.windowLevel > host.windowLevel)) host = window;
    }
    if (!host || !host.windowScene) { [self hide]; return; }
    CGFloat level = MAX(UIWindowLevelNormal + 1, MIN(host.windowLevel + 1, UIWindowLevelAlert - 1));
    // Unknown high-level windows include permission/authentication UI: hide, not outrank.
    for (UIWindow *window in windows) {
        if (window == self.window || window.hidden || window.alpha < 0.01) continue;
        if (window.windowLevel >= level && !LMVEasterKnownWindow(window, trusted)) { [self hide]; return; }
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
    if (!key) { self.generation++; self.imageKey = nil; self.decoded = nil; self.bubble.image = nil; [self hide]; return; }
    if (![self.imageKey isEqualToString:key]) {
        self.imageKey = key; self.decoded = nil; self.frame = 0; self.bubble.image = nil; [self hide];
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
    if (!self.decoded.frames.count) { [self hide]; return; }
    self.window.hidden = NO; self.bubble.image = self.decoded.frames[self.frame % self.decoded.frames.count]; [self layout]; [self animateFrame];
}
- (CGRect)dragArea {
    CGRect bounds = self.window.rootViewController.view.bounds;
    UIEdgeInsets safe = self.window.rootViewController.view.safeAreaInsets;
    CGRect inset = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(safe.top + 8, safe.left + 8, safe.bottom + 8, safe.right + 8));
    return CGRectMake(CGRectGetMinX(inset) + 32, CGRectGetMinY(inset) + 32, MAX(0, inset.size.width - 64), MAX(0, inset.size.height - 64));
}
- (void)layout {
    if (!self.window || !self.bubble) return;
    CGRect area = [self dragArea];
    self.bubble.center = CGPointMake(area.origin.x + area.size.width * self.normalized.x, area.origin.y + area.size.height * self.normalized.y);
    if (self.panel) {
        CGRect bounds = UIEdgeInsetsInsetRect(self.window.rootViewController.view.bounds, self.window.rootViewController.view.safeAreaInsets);
        CGFloat width = MIN(360, MAX(0, bounds.size.width - 24)), height = MIN(550, MAX(0, bounds.size.height - 24));
        self.panel.view.frame = CGRectMake(CGRectGetMidX(bounds) - width / 2, CGRectGetMidY(bounds) - height / 2, width, height);
    }
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.window.rootViewController.view]; CGRect area = [self dragArea];
    CGPoint point = CGPointMake(MAX(CGRectGetMinX(area), MIN(CGRectGetMaxX(area), self.bubble.center.x + translation.x)), MAX(CGRectGetMinY(area), MIN(CGRectGetMaxY(area), self.bubble.center.y + translation.y)));
    self.normalized = CGPointMake(area.size.width ? (point.x - area.origin.x) / area.size.width : 0.5, area.size.height ? (point.y - area.origin.y) / area.size.height : 0.5);
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
    self.panel.view.layer.cornerRadius = 8; self.panel.view.clipsToBounds = YES; self.window.panel = self.panel.view; [self layout];
}
- (void)closePanel {
    if (!self.panel) return;
    [self.panel dismissViewControllerAnimated:NO completion:nil];
    [self.panel willMoveToParentViewController:nil]; [self.panel.view removeFromSuperview]; [self.panel removeFromParentViewController]; self.panel = nil; self.window.panel = nil;
}
@end
