#pragma once
// Read existing UIKit state only. Never invoke a private scene/controller getter.
static void LMVWallpaperDiagnosticMethods(Class cls) {
    static NSMutableSet<NSString *> *seen;
    if (!seen) seen = [NSMutableSet new];
    NSString *name = NSStringFromClass(cls);
    if (!cls || seen.count >= 8 || [seen containsObject:name]) return;
    [seen addObject:name];
    NSUInteger emitted = 0;
    for (Class current = cls; current && current != NSObject.class && emitted < 10; current = class_getSuperclass(current)) {
        unsigned int count = 0; Method *methods = class_copyMethodList(current, &count);
        for (unsigned int i = 0; i < count && emitted < 10; i++) {
            NSString *selector = NSStringFromSelector(method_getName(methods[i]));
            NSString *lower = selector.lowercaseString;
            if (![lower containsString:@"wallpaper"] && ![lower containsString:@"poster"] &&
                ![lower containsString:@"image"] && ![lower containsString:@"scene"] &&
                ![lower containsString:@"render"] && ![lower containsString:@"asset"]) continue;
            const char *types = method_getTypeEncoding(methods[i]);
            LMVDiagnostic([NSString stringWithFormat:@"wallpaper-method class=%@ declaredBy=%@ selector=%@ types=%s",
                name, NSStringFromClass(current), selector, types ?: "?"]);
            emitted++;
        }
        free(methods);
    }
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
        // Declared ivar names/types reveal scene/renderer ownership without reading
        // object values or accidentally constructing private framework singletons.
        NSMutableArray *fields = [NSMutableArray new];
        for (Class cls = view.class; cls && cls != UIView.class && fields.count < 8; cls = class_getSuperclass(cls)) {
            unsigned int count = 0; Ivar *ivars = class_copyIvarList(cls, &count);
            for (unsigned int i = 0; i < count && fields.count < 8; i++) {
                NSString *key = [NSString stringWithUTF8String:ivar_getName(ivars[i])];
                NSString *lower = key.lowercaseString;
                if ([lower containsString:@"scene"] || [lower containsString:@"controller"] ||
                    [lower containsString:@"renderer"] || [lower containsString:@"poster"]) {
                    const char *type = ivar_getTypeEncoding(ivars[i]);
                    [fields addObject:[NSString stringWithFormat:@"%@:%s", key, type ?: "?"]];
                }
            }
            free(ivars);
        }
        LMVDiagnostic([NSString stringWithFormat:@"wallpaper-scene-host class=%@ declaredFields=%@", name, [fields componentsJoinedByString:@","]]);
        LMVWallpaperDiagnosticLayers(view.layer, 0, layerBudget);
    }
    for (UIView *child in view.subviews) LMVWallpaperDiagnosticViews(child, depth + 1, budget, layerBudget);
}
static void LMVCaptureWallpaperDiagnostics(void) {
    if (!LMVDiagnosticsEnabled.load() || !LMVLaunchReady || !NSThread.isMainThread) return;
    static BOOL wasEnabled = NO;
    static NSString *lastState;
    static CFTimeInterval lastCapture;
    static NSUInteger snapshots;
    // At most four bounded snapshots per SpringBoard process; the regular render
    // log still records source/target changes between snapshots.
    if (snapshots >= 4) return;
    NSMutableArray<UIWindow *> *windows = [NSMutableArray new];
    BOOL coverVisible = NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            NSString *name = NSStringFromClass(window.class);
            if ([name isEqualToString:@"SBCoverSheetWindow"] && !window.hidden && window.alpha >= .01) coverVisible = YES;
            if ([name isEqualToString:@"_SBWallpaperSecureWindow"] || [name isEqualToString:@"SBCoverSheetWindow"] ||
                [name isEqualToString:@"SBHomeScreenWindow"]) [windows addObject:window];
        }
    }
    uint64_t lock = 1, blank = 1;
    BOOL lockKnown = LMVLockToken >= 0 && notify_get_state(LMVLockToken, &lock) == NOTIFY_STATUS_OK;
    BOOL blankKnown = LMVBlankToken >= 0 && notify_get_state(LMVBlankToken, &blank) == NOTIFY_STATUS_OK;
    NSString *state = [NSString stringWithFormat:@"%@:%d:%llu:%llu", coverVisible ? @"LockScreen" : @"Desktop",
        (int)windows.count, (unsigned long long)lock, (unsigned long long)blank];
    CFTimeInterval now = CACurrentMediaTime();
    if (wasEnabled && [lastState isEqualToString:state]) return;
    if (wasEnabled && now - lastCapture < 1.0) return;
    wasEnabled = YES; lastState = state; lastCapture = now; snapshots++;
    LMVDiagnostic([NSString stringWithFormat:@"wallpaper-snapshot begin=%lu target=%@ lockKnown=%d locked=%llu blankKnown=%d blank=%llu windows=%lu",
        (unsigned long)snapshots, coverVisible ? @"LockScreen" : @"Desktop", lockKnown, (unsigned long long)lock,
        blankKnown, (unsigned long long)blank, (unsigned long)windows.count]);
    for (UIWindow *window in windows) {
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
        for (UIView *host in hosts.allObjects) {
            LMVVideoState *video = objc_getAssociatedObject(host, [target isEqualToString:@"LockScreen"] ? &LMVLockStateKey : &LMVDesktopStateKey);
            LMVDiagnostic([NSString stringWithFormat:@"wallpaper-consumer target=%@ host=%@ enabled=%d selected=%d assetready=%d active=%d frame=%d attached=%d originals=%lu observed=%lu",
                target, NSStringFromClass(host.class), LMVEnabled[target].boolValue, LMVPaths[target] != nil,
                [LMVReadyAssets containsObject:LMVPaths[target] ?: @""], video.active, video.layer.contents != nil,
                video.layer.superlayer != nil, (unsigned long)video.originals.count, (unsigned long)video.wallpaperOriginals.count]);
        }
    }
    LMVDiagnostic([NSString stringWithFormat:@"wallpaper-snapshot end=%lu", (unsigned long)snapshots]);
}
