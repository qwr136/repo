#pragma once
// Read existing UIKit state only. Never invoke a private scene/controller getter.
static void LMVWallpaperDiagnosticMethods(Class cls) {
    LMVWallpaperDiagnosticClass(cls, @"host-class", cls);
}
static void LMVWallpaperDiagnosticControllers(UIViewController *controller, NSUInteger depth, NSUInteger *budget) {
    if (!controller || !*budget || depth > 5) return;
    --*budget;
    UIView *view = controller.viewIfLoaded;
    NSString *className = NSStringFromClass(controller.class);
    if ([className containsString:@"Wallpaper"] || [className containsString:@"Poster"] || [className containsString:@"Scene"])
        LMVWallpaperDiagnosticMethods(controller.class);
    LMVDiagnostic([NSString stringWithFormat:@"wallpaper-controller depth=%lu class=%@ loaded=%d view=%@ attached=%d parent=%@",
        (unsigned long)depth, NSStringFromClass(controller.class), view != nil,
        view ? NSStringFromClass(view.class) : @"none", view.window != nil,
        controller.parentViewController ? NSStringFromClass(controller.parentViewController.class) : @"none"]);
    for (UIViewController *child in controller.childViewControllers)
        LMVWallpaperDiagnosticControllers(child, depth + 1, budget);
    LMVWallpaperDiagnosticControllers(controller.presentedViewController, depth + 1, budget);
}
static void LMVWallpaperDiagnosticLayers(CALayer *layer, NSUInteger depth, NSUInteger *budget) {
    if (!layer || !*budget || depth > 5) return;
    --*budget;
    CALayer *shown = layer.presentationLayer;
    LMVDiagnostic([NSString stringWithFormat:@"wallpaper-layer depth=%lu class=%@ parent=%@ hidden=%d opacity=%.3f shownOpacity=%.3f z=%.2f bounds=%@ contents=%d owned=%d children=%lu",
        (unsigned long)depth, NSStringFromClass(layer.class), layer.superlayer ? NSStringFromClass(layer.superlayer.class) : @"none",
        layer.hidden, layer.opacity, shown ? shown.opacity : layer.opacity, layer.zPosition,
        NSStringFromCGRect(layer.bounds), layer.contents != nil, [layer.name hasPrefix:@"com.minis.lockmessagevideo"],
        (unsigned long)layer.sublayers.count]);
    for (CALayer *child in layer.sublayers) LMVWallpaperDiagnosticLayers(child, depth + 1, budget);
}
static void LMVWallpaperDiagnosticViews(UIView *view, NSUInteger depth, NSUInteger *budget, NSUInteger *layerBudget) {
    if (!view || !*budget || depth > 10) return;
    --*budget;
    UIResponder *responder = view.nextResponder;
    for (NSUInteger n = 0; responder && n < 12 && ![responder isKindOfClass:UIViewController.class]; n++)
        responder = responder.nextResponder;
    CALayer *shown = view.layer.presentationLayer;
    LMVDiagnostic([NSString stringWithFormat:@"wallpaper-view depth=%lu class=%@ parent=%@ controller=%@ scene=%@ frame=%@ hidden=%d alpha=%.3f opacity=%.3f shownOpacity=%.3f layer=%@ children=%lu",
        (unsigned long)depth, NSStringFromClass(view.class), view.superview ? NSStringFromClass(view.superview.class) : @"none",
        [responder isKindOfClass:UIViewController.class] ? NSStringFromClass(responder.class) : @"none",
        view.window.windowScene ? NSStringFromClass(view.window.windowScene.class) : @"none",
        NSStringFromCGRect(view.frame), view.hidden, view.alpha, view.layer.opacity, shown ? shown.opacity : view.layer.opacity,
        NSStringFromClass(view.layer.class), (unsigned long)view.subviews.count]);
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"Wallpaper"] || [name containsString:@"Poster"] ||
        [name containsString:@"Scene"] || [name containsString:@"Remote"]) {
        LMVWallpaperDiagnosticMethods(view.class);
        LMVWallpaperDiagnosticLayers(view.layer, 0, layerBudget);
    }
    for (UIView *child in view.subviews) LMVWallpaperDiagnosticViews(child, depth + 1, budget, layerBudget);
}
static void LMVCaptureWallpaperDiagnostics(void) {
    if (!LMVDiagnosticsEnabled.load() || !LMVLaunchReady || !NSThread.isMainThread) return;
    static BOOL wasEnabled = NO;
    static unsigned long epoch = ~0UL;
    static NSUInteger retries;
    static CFTimeInterval lastRetry;
    static NSString *lastState;
    static CFTimeInterval lastCapture;
    static NSUInteger snapshots;
    // A new enabled session owns its own bounded snapshots and retry budget.
    unsigned long currentEpoch = LMVTraceEpoch();
    if (epoch != currentEpoch) {
        epoch = currentEpoch; wasEnabled = NO; lastState = nil;
        lastCapture = 0; snapshots = 0; retries = 0; lastRetry = 0;
    }
    if (snapshots >= 8) return;
    NSMutableArray<UIWindow *> *windows = [NSMutableArray new];
    BOOL coverVisible = NO, homeVisible = NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            NSString *name = NSStringFromClass(window.class);
            if ([name isEqualToString:@"SBCoverSheetWindow"] && !window.hidden && window.alpha >= .01) coverVisible = YES;
            if ([name isEqualToString:@"SBHomeScreenWindow"] && !window.hidden && window.alpha >= .01) homeVisible = YES;
            if ([name isEqualToString:@"_SBWallpaperSecureWindow"] || [name isEqualToString:@"SBCoverSheetWindow"] ||
                [name isEqualToString:@"SBHomeScreenWindow"]) [windows addObject:window];
        }
    }
    uint64_t lock = 1, blank = 1;
    BOOL lockKnown = LMVLockToken >= 0 && notify_get_state(LMVLockToken, &lock) == NOTIFY_STATUS_OK;
    BOOL blankKnown = LMVBlankToken >= 0 && notify_get_state(LMVBlankToken, &blank) == NOTIFY_STATUS_OK;
    NSString *target = coverVisible ? @"LockScreen" : (homeVisible ? @"Desktop" : @"unknown");
    NSString *state = [NSString stringWithFormat:@"%@:%d:%llu:%llu", target,
        (int)windows.count, (unsigned long long)lock, (unsigned long long)blank];
    CFTimeInterval now = CACurrentMediaTime();
    if (wasEnabled && now - lastCapture < 1.0) return;
    // Retry independently of the state string: late controller/provider classes
    // can appear without changing lock state or window count. At most 3 retries.
    BOOL retry = wasEnabled && retries < 3 && now - lastRetry >= 5.0;
    if (wasEnabled && [lastState isEqualToString:state] && !retry) return;
    if (retry) { retries++; lastRetry = now; }
    else if (!wasEnabled) lastRetry = now;
    wasEnabled = YES; lastState = state; lastCapture = now; snapshots++;
    LMVDiagnostic([NSString stringWithFormat:@"wallpaper-snapshot begin=%lu target=%@ lockKnown=%d locked=%llu blankKnown=%d blank=%llu windows=%lu",
        (unsigned long)snapshots, target, lockKnown, (unsigned long long)lock,
        blankKnown, (unsigned long long)blank, (unsigned long)windows.count]);
    NSUInteger windowBudget = 6;
    for (UIWindow *window in windows) {
        if (!windowBudget--) break;
        BOOL wall = [NSStringFromClass(window.class) isEqualToString:@"_SBWallpaperSecureWindow"];
        UIWindowScene *scene = window.windowScene;
        LMVDiagnostic([NSString stringWithFormat:@"wallpaper-window-info class=%@ hidden=%d alpha=%.3f level=%.1f scene=%@ activation=%ld role=%@ rootController=%@",
            NSStringFromClass(window.class), window.hidden, window.alpha, window.windowLevel,
            scene ? NSStringFromClass(scene.class) : @"none", (long)scene.activationState,
            scene.session.role ?: @"none", window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"none"]);
        NSUInteger controllers = wall ? 8 : 4, views = wall ? 36 : 12, layers = wall ? 20 : 4;
        LMVWallpaperDiagnosticControllers(window.rootViewController, 0, &controllers);
        LMVWallpaperDiagnosticViews(window, 0, &views, &layers);
        if (wall && layers) LMVWallpaperDiagnosticLayers(window.layer, 0, &layers);
    }
    for (NSString *target in @[@"LockScreen", @"Desktop"]) {
        NSHashTable *hosts = [target isEqualToString:@"LockScreen"] ? LMVLockHosts : LMVDesktopHosts;
        NSUInteger consumerBudget = 8;
        for (UIView *host in hosts.allObjects) {
            if (!consumerBudget--) break;
            LMVVideoState *video = objc_getAssociatedObject(host, [target isEqualToString:@"LockScreen"] ? &LMVLockStateKey : &LMVDesktopStateKey);
            LMVDiagnostic([NSString stringWithFormat:@"wallpaper-consumer target=%@ host=%@ enabled=%d selected=%d assetready=%d active=%d frame=%d attached=%d originals=%lu observed=%lu",
                target, NSStringFromClass(host.class), LMVEnabled[target].boolValue, LMVPaths[target] != nil,
                [LMVReadyAssets containsObject:LMVPaths[target] ?: @""], video.active, video.layer.contents != nil,
                video.layer.superlayer != nil, (unsigned long)video.originals.count, (unsigned long)video.wallpaperOriginals.count]);
        }
    }
    LMVDiagnostic([NSString stringWithFormat:@"wallpaper-snapshot end=%lu", (unsigned long)snapshots]);
}
