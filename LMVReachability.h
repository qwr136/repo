#pragma once
// 0.0.118 user feature: "屏蔽桌面便捷访问" - block iOS Reachability (便捷访问 /
// 降半屏) on the DESKTOP only. Lock screen and Control Centre are NEVER blocked.
//
// Implementation notes
// --------------------
// The Reachability trigger is a bottom-edge screen pan. This file never guesses a
// private SpringBoard class name: it finds the actual UIScreenEdgePanGesture-
// Recognizer whose edges include the bottom edge (the only such recognizer in
// SpringBoard) and toggles its `enabled` flag, restoring it as soon as the
// desktop rule stops holding. Every step is public API, so a wrong guess can only
// make the feature inert - it can never permanently disable another gesture.
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
static NSMutableArray<UIWindow *> *LMVReachabilityWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        if (scene.activationState == UISceneActivationStateUnattached) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window) [windows addObject:window];
    }
    return windows;
}
static UIScreenEdgePanGestureRecognizer *LMVReachabilityEdgeRecognizerInView(UIView *view, NSUInteger depth) {
    if (!view || depth > 8) return nil;
    for (UIGestureRecognizer *recognizer in view.gestureRecognizers) {
        if (![recognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class]) continue;
        if (((UIScreenEdgePanGestureRecognizer *)recognizer).edges & UIRectEdgeBottom)
            return (UIScreenEdgePanGestureRecognizer *)recognizer;
    }
    for (UIView *child in view.subviews) {
        UIScreenEdgePanGestureRecognizer *found = LMVReachabilityEdgeRecognizerInView(child, depth + 1);
        if (found) return found;
    }
    return nil;
}
// Bottom edge only: left/right edge pans (back gestures, CC pull) stay untouched.
static UIScreenEdgePanGestureRecognizer *LMVReachabilityEdgeRecognizer(void) {
    for (UIWindow *window in LMVReachabilityWindows()) {
        UIScreenEdgePanGestureRecognizer *found = LMVReachabilityEdgeRecognizerInView(window, 0);
        if (found) return found;
    }
    return nil;
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
    static __weak UIScreenEdgePanGestureRecognizer *tracked;
    static NSInteger lastBlocked = -1;
    static BOOL reportedMissing = NO;
    BOOL enabled = LMVReachabilityEnabled();
    uint64_t blank = 1, locked = 1;
    BOOL blankKnown = LMVBlankToken >= 0 && notify_get_state(LMVBlankToken, &blank) == NOTIFY_STATUS_OK;
    BOOL lockKnown = LMVLockToken >= 0 && notify_get_state(LMVLockToken, &locked) == NOTIFY_STATUS_OK;
    BOOL nc = LMVReachabilitySurfaceUp(@[@"SBCoverSheetWindow"], @[@"CoverSheet"]);
    BOOL cc = LMVReachabilitySurfaceUp(@[@"SBControlCenterWindow"], @[@"ControlCenter"]);
    BOOL blocked = LMVReachabilityDeskBlocked(enabled, blankKnown, blank, lockKnown, locked,
        LMVReachabilityForeground(), nc, cc);
    UIScreenEdgePanGestureRecognizer *recognizer = LMVReachabilityEdgeRecognizer();
    if (recognizer) {
        tracked = recognizer;
        if (recognizer.enabled == blocked) recognizer.enabled = !blocked;
    }
    if (enabled && !recognizer && !reportedMissing) {
        reportedMissing = YES;
        LMVDiagnostic(@"reachability recognizer=missing enabled=1 (bottom-edge gesture not found; nothing changed)");
    }
    if ((NSInteger)blocked != lastBlocked) {
        lastBlocked = (NSInteger)blocked;
        LMVDiagnostic([NSString stringWithFormat:@"reachability block=%d enabled=%d recognizer=%d nc=%d cc=%d",
            blocked, enabled, recognizer != nil, nc, cc]);
    }
}
// Leaving the feature off must never leave the gesture disabled behind us.
static void LMVReachabilityRestore(void) {
    for (UIWindow *window in LMVReachabilityWindows()) {
        UIScreenEdgePanGestureRecognizer *recognizer = LMVReachabilityEdgeRecognizerInView(window, 0);
        if (recognizer && !recognizer.enabled) recognizer.enabled = YES;
    }
}
