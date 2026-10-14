#pragma once
// 0.0.118 user feature: "屏蔽桌面便捷访问" - block iOS Reachability (便捷访问 /
// 降半屏) on the DESKTOP only. Lock screen and Control Centre are NEVER blocked.
//
// Implementation notes
// --------------------
// The Reachability trigger is a bottom-edge screen pan. This file never guesses a
// private SpringBoard class name: it finds the recognizer whose `edges` include
// the bottom edge - preferring a real UIScreenEdgePanGestureRecognizer, falling
// back to any private subclass that exposes `edges` - and toggles its `enabled`
// flag, restoring it as soon as the desktop rule stops holding. The search covers
// the application's complete window set, because SpringBoard's system gesture
// window is owned by the application and is absent from the window scenes.
// Every step is public API, so a wrong guess can only make the feature inert - it
// can never permanently disable another gesture.
//
// The desktop rule itself is a pure function, so it is natively testable:
// enabled AND screen known & not blank AND lock known & unlocked AND SpringBoard
// is frontmost AND no CoverSheet / Control-Centre surface is on screen.

// Include order: this header relies on LMVBlankToken / LMVLockToken / kLMVPrefsID,
// which Tweak.xm declares before importing it.
static BOOL LMVReachabilityEnabled(void) {
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("BlockDesktopReachability"), kLMVPrefsID);
    return [value isKindOfClass:NSNumber.class] && [value boolValue];
}
// Pure gate. `foreground`: 1 = SpringBoard, -1 = another app, 0 = unknown.
static BOOL LMVReachabilityDeskBlocked(BOOL enabled, BOOL blankKnown, uint64_t blank,
                                       BOOL lockKnown, uint64_t locked, NSInteger foreground,
                                       BOOL nc, BOOL cc) {
    if (!enabled) return NO;
    if (!blankKnown || blank) return NO;      // screen off: nothing to block
    if (!lockKnown || locked) return NO;      // lock screen keeps Reachability
    if (nc || cc) return NO;                  // Notification / Control Centre keep it
    return foreground == 1;                   // only when SpringBoard is frontmost
}
// Home=1, application=-1, unknown=0. Published state only.
static NSInteger LMVReachabilityForeground(void) {
    UIApplication *app = UIApplication.sharedApplication;
    BOOL known = NO, unknown = NO;
    for (NSString *name in @[@"_frontmostApplication", @"_accessibilityFrontMostApplication"]) {
        SEL selector = NSSelectorFromString(name);
        if (![app respondsToSelector:selector]) continue;
        NSMethodSignature *signature = [app methodSignatureForSelector:selector];
        if (!signature || signature.numberOfArguments != 2 || strcmp(signature.methodReturnType, @encode(id))) continue;
        known = YES;
        id object = ((id (*)(id, SEL))objc_msgSend)(app, selector);
        if (!object) continue;
        SEL bundle = NSSelectorFromString(@"bundleIdentifier");
        id identifier = [object respondsToSelector:bundle] ? ((id (*)(id, SEL))objc_msgSend)(object, bundle) : nil;
        if ([identifier isKindOfClass:NSString.class] && [identifier length])
            return [identifier isEqualToString:@"com.apple.springboard"] ? 1 : -1;
        unknown = YES;
    }
    return known && !unknown ? 1 : 0;
}
static NSArray<UIWindow *> *LMVReachabilityWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray new];
    NSMutableSet *seen = [NSMutableSet new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState == UISceneActivationStateUnattached) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window || [seen containsObject:window]) continue;
            [seen addObject:window]; [windows addObject:window];
        }
    }
    // 0.0.119 device log: `reachability block=1 enabled=1 recognizer=0` - the
    // feature was inert because the scene walk above never reached SpringBoard's
    // Reachability gesture. It lives on the SYSTEM GESTURE window, which the
    // APPLICATION owns rather than the window scene. `-windows` is deprecated for
    // apps but is exactly the complete set here; it is called through
    // objc_msgSend so no deprecation warning is raised (warnings are errors).
    SEL allWindows = NSSelectorFromString(@"windows");
    if ([UIApplication.sharedApplication respondsToSelector:allWindows]) {
        id list = ((id (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, allWindows);
        if ([list isKindOfClass:NSArray.class])
            for (UIWindow *window in (NSArray *)list) {
                if (![window isKindOfClass:UIWindow.class] || [seen containsObject:window]) continue;
                [seen addObject:window]; [windows addObject:window];
            }
    }
    // The system GESTURE window is not in either list on SpringBoard. Ask the
    // application and every scene for it directly (dynamic selectors: nothing is
    // guessed, a miss simply adds nothing).
    for (NSString *name in @[@"_systemGestureWindow", @"systemGestureWindow"]) {
        SEL selector = NSSelectorFromString(name);
        if ([UIApplication.sharedApplication respondsToSelector:selector]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, selector);
            if ([value isKindOfClass:UIWindow.class] && ![seen containsObject:value]) {
                [seen addObject:value]; [windows addObject:value];
            }
        }
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene respondsToSelector:selector]) continue;
            id value = ((id (*)(id, SEL))objc_msgSend)(scene, selector);
            if ([value isKindOfClass:UIWindow.class] && ![seen containsObject:value]) {
                [seen addObject:value]; [windows addObject:value];
            }
        }
    }
    return windows;
}
// Collects every recognizer whose `edges` includes the bottom edge. A private
// SpringBoard subclass is accepted as a FALLBACK even when it does not inherit
// UIScreenEdgePanGestureRecognizer; a real one wins when both are present.
static UIGestureRecognizer *LMVReachabilityEdgeRecognizerInView(UIView *view, NSUInteger depth,
                                                              UIGestureRecognizer **fallback) {
    if (!view || depth > 32) return nil;
    SEL edgesSelector = NSSelectorFromString(@"edges");
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer respondsToSelector:edgesSelector]) continue;
        UIRectEdge edges = ((UIRectEdge (*)(id, SEL))objc_msgSend)(recognizer, edgesSelector);
        if (!(edges & UIRectEdgeBottom)) continue;
        if ([recognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class]) return recognizer;
        if (fallback && !*fallback) *fallback = recognizer;
    }
    for (UIView *child in view.subviews) {
        UIGestureRecognizer *found = LMVReachabilityEdgeRecognizerInView(child, depth + 1, fallback);
        if (found) return found;
    }
    return nil;
}
// Bottom edge only: left/right edge pans (back gestures, CC pull) stay untouched.
static UIGestureRecognizer *LMVReachabilityEdgeRecognizer(void) {
    UIGestureRecognizer *fallback = nil;
    for (UIWindow *window in LMVReachabilityWindows()) {
        UIGestureRecognizer *found = LMVReachabilityEdgeRecognizerInView(window, 0, &fallback);
        if (found) return found;
    }
    return fallback;
}
// Only for the missing-recognizer diagnostic: which windows were even reachable.
static NSString *LMVReachabilityWindowNames(void) {
    NSMutableOrderedSet<NSString *> *names = [NSMutableOrderedSet new];
    NSArray<UIWindow *> *windows = LMVReachabilityWindows();
    for (UIWindow *window in windows) [names addObject:NSStringFromClass(window.class)];
    NSMutableArray<NSString *> *head = [NSMutableArray new];
    for (NSUInteger index = 0; index < names.count && head.count < 6; index++) [head addObject:names[index]];
    return [NSString stringWithFormat:@"windows=%lu %@", (unsigned long)windows.count,
            [head componentsJoinedByString:@","]];
}
// ---------------------------------------------------------------------------
// The desktop gate, published for the touch path below. It is recomputed once per
// pass so a touch never has to walk the window list.
static volatile BOOL LMVReachabilityDesktopBlocked = NO;
static NSInteger LMVReachabilityInSpringBoard(void) {
    static NSInteger cached = -1;
    if (cached < 0) {
        NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
        cached = [identifier isEqualToString:@"com.apple.springboard"] ? 1 : 0;
    }
    return cached;
}
static BOOL LMVReachabilitySurfaceUp(NSArray<NSString *> *windowClasses, NSArray<NSString *> *controllerClasses) {
    for (UIWindow *window in LMVReachabilityWindows()) {
        if (window.hidden || !isfinite(window.alpha) || window.alpha < .01) continue;
        NSString *windowName = NSStringFromClass(window.class);
        for (NSString *name in windowClasses)
            if ([windowName containsString:name]) return YES;
        for (UIViewController *controller = window.rootViewController; controller;
             controller = controller.presentedViewController) {
            NSString *controllerName = NSStringFromClass(controller.class);
            for (NSString *name in controllerClasses)
                if ([controllerName containsString:name]) return YES;
        }
    }
    return NO;
}
static void LMVReachabilityApply(void) {
    static NSInteger lastBlocked = -1;
    static CFTimeInterval reportedMissingAt = 0;
    BOOL enabled = LMVReachabilityEnabled();
    uint64_t blank = 1, locked = 1;
    BOOL blankKnown = LMVBlankToken >= 0 && notify_get_state(LMVBlankToken, &blank) == NOTIFY_STATUS_OK;
    BOOL lockKnown = LMVLockToken >= 0 && notify_get_state(LMVLockToken, &locked) == NOTIFY_STATUS_OK;
    BOOL nc = LMVReachabilitySurfaceUp(@[@"SBCoverSheetWindow"], @[@"CoverSheet"]);
    BOOL cc = LMVReachabilitySurfaceUp(@[@"SBControlCenterWindow"], @[@"ControlCenter"]);
    BOOL blocked = LMVReachabilityDeskBlocked(enabled, blankKnown, blank, lockKnown, locked,
        LMVReachabilityForeground(), nc, cc);
    // Publish the decision for the touch path (below). It never walks the window
    // list itself, so this must run before the guard can matter.
    LMVReachabilityDesktopBlocked = blocked;
    UIGestureRecognizer *recognizer = LMVReachabilityEdgeRecognizer();
    // Re-searched every pass: never cache a recognizer SpringBoard may rebuild.
    if (recognizer && recognizer.enabled == blocked) recognizer.enabled = !blocked;
    if (enabled && !recognizer) {
        // Rate limited to one report per 5 s, and it says WHICH windows were seen
        // so a single log pass is enough to find the surface that carries the
        // gesture (device log showed the reachable set was too narrow).
        CFTimeInterval now = CACurrentMediaTime();
        if (now - reportedMissingAt > 5.0) {
            reportedMissingAt = now;
            LMVDiagnostic([NSString stringWithFormat:
                @"reachability recognizer=missing %@ (bottom-edge gesture not found; nothing changed)",
                LMVReachabilityWindowNames()]);
        }
    }
    if ((NSInteger)blocked != lastBlocked) {
        lastBlocked = (NSInteger)blocked;
        UIRectEdge edges = 0;
        if (recognizer) {
            SEL edgesSelector = NSSelectorFromString(@"edges");
            if ([recognizer respondsToSelector:edgesSelector])
                edges = ((UIRectEdge (*)(id, SEL))objc_msgSend)(recognizer, edgesSelector);
        }
        // `target` names the exact recognizer being toggled, so a log pass proves
        // which gesture was touched (and that no unrelated edge pan was).
        LMVDiagnostic([NSString stringWithFormat:@"reachability block=%d enabled=%d recognizer=%d nc=%d cc=%d target=%@ edges=%lu",
            blocked, enabled, recognizer != nil, nc, cc,
            recognizer ? NSStringFromClass(recognizer.class) : @"none", (unsigned long)edges]);
    }
}
// Leaving the feature off must never leave the gesture disabled behind us.
static void LMVReachabilityRestore(void) {
    for (UIWindow *window in LMVReachabilityWindows()) {
        UIGestureRecognizer *fallback = nil;
        UIGestureRecognizer *recognizer = LMVReachabilityEdgeRecognizerInView(window, 0, &fallback);
        if (!recognizer) recognizer = fallback;
        if (recognizer && !recognizer.enabled) recognizer.enabled = YES;
    }
}

// ---------------------------------------------------------------------------
// 0.0.119 device log: `windows=38 SBSystemApertureWindow,_LNSceneTouchVisualizer-
// Window,UITextEffectsWindow,SBStatusBarReusePoolWindow,_SBWallpaperSecureWindow,
// SBHomeScreenWindow ... recognizer=0`. SpringBoard exposes the Reachability
// gesture through no window tree and no `edges` value reachable with public API,
// so toggling `enabled` can never work there.
//
// The feature therefore guards the gesture at its SOURCE: a bottom-edge pan -
// whatever class implements it - BEGINS inside the bottom strip of the screen.
// That identifies it by pure geometry, with no private class name and no `edges`
// guesswork. While the desktop rule holds, the touches are dropped before the
// recogniser sees them, so Reachability never starts.
//
// Scope is deliberately narrow: only bottom-strip touches, only while the desktop
// rule holds, and only in SpringBoard (this tweak's filter plist injects
// com.apple.springboard and nothing else). Left/right edge pans (back gestures,
// Control Centre) and the home-indicator swipe (a different recogniser family,
// and it does not begin in the bottom strip as an edge pan) are untouched.
static void LMVReachabilityReportSwallow(CGFloat y) {
    static NSInteger swallowed = 0;
    static CFTimeInterval lastReport = 0;
    ++swallowed;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - lastReport < 1.0) return;
    lastReport = now;
    LMVDiagnostic([NSString stringWithFormat:
        @"reachability swallow count=%ld y=%.0f (desktop Reachability stopped at the touch source)",
        (long)swallowed, y]);
}
static BOOL LMVReachabilityShouldSwallow(UIGestureRecognizer *recognizer, NSSet<UITouch *> *touches) {
    if (LMVReachabilityInSpringBoard() != 1 || !LMVReachabilityDesktopBlocked) return NO;
    if (![recognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class]) return NO;
    UIView *view = recognizer.view;
    UITouch *touch = [touches anyObject];
    if (!view || ![touch isKindOfClass:UITouch.class]) return NO;
    CGPoint point = [touch locationInView:view];
    CGRect bounds = view.bounds;
    if (!isfinite(point.y) || !isfinite(bounds.size.height)) return NO;
    // The bottom strip is what makes the pan an EDGE pan; 20 pt is the system's
    // own edge band.
    return point.y >= bounds.size.height - 20.0;
}
@interface UIScreenEdgePanGestureRecognizer (LMVReachabilityGuard)
- (void)lmv_reachabilityTouchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event;
@end
@implementation UIScreenEdgePanGestureRecognizer (LMVReachabilityGuard)
- (void)lmv_reachabilityTouchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (LMVReachabilityShouldSwallow(self, touches)) {
        UITouch *touch = [touches anyObject];
        LMVReachabilityReportSwallow(touch ? [touch locationInView:self.view].y : 0);
        return; // not calling through: the state machine never sees the touch
    }
    [self lmv_reachabilityTouchesBegan:touches withEvent:event];
}
@end
static void LMVReachabilityInstallTouchGuard(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SEL original = NSSelectorFromString(@"touchesBegan:withEvent:");
        SEL replacement = NSSelectorFromString(@"lmv_reachabilityTouchesBegan:withEvent:");
        Class cls = UIScreenEdgePanGestureRecognizer.class;
        Method existing = class_getInstanceMethod(cls, original);
        Method added = class_getInstanceMethod(cls, replacement);
        if (!existing || !added) {
            LMVDiagnostic(@"reachability touch-guard=failed selector=touchesBegan:withEvent:");
            return;
        }
        if (class_addMethod(cls, original, method_getImplementation(added), method_getTypeEncoding(added)))
            class_replaceMethod(cls, replacement, method_getImplementation(existing), method_getTypeEncoding(existing));
        else
            method_exchangeImplementations(existing, added);
        LMVDiagnostic(@"reachability touch-guard=installed selector=touchesBegan:withEvent: bottom-strip=20pt");
    });
}
