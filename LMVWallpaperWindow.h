#pragma once
// 0.0.62: the Lock/Home video IS the wallpaper. Instead of stacking a layer over
// CoverSheet/HomeScreen content, our own CALayer is placed inside the dedicated
// _SBWallpaperSecureWindow, directly above its (lease-suppressed) original
// wallpaper branches. Clock, notifications, icons, widgets and Dock live in
// higher windows and therefore draw above the video naturally.
// Nothing is deallocated: disabling detaches our layer and releases the leases.
static NSString * const LMVWallpaperLayerName = @"com.minis.lockmessagevideo.wallpaper-window";
static char LMVWallpaperWindowKey;
static NSHashTable<UIWindow *> *LMVWallpaperWindows;

@interface LMVWallpaperSurface : NSObject
@property(nonatomic, strong) CALayer *layer;
@property(nonatomic, strong) NSArray<LMVOriginalLease *> *leases;
@property(nonatomic, copy) NSString *target, *diagnostic, *path, *revision;
@property(nonatomic) CFTimeInterval lastEligibleAt;
@end
@implementation LMVWallpaperSurface
- (void)dealloc { LMVReleaseOriginals(_leases, self); [_layer removeFromSuperlayer]; }
@end

static void LMVWallpaperWindowBranches(UIWindow *window, NSMutableArray<UIView *> *branches) {
    NSMutableArray<NSString *> *guards = [NSMutableArray new];
    NSUInteger budget = 96;
    for (UIView *child in window.subviews) LMVObservedWallpaperBranches(child, window, 0, &budget, branches, guards);
}
// Which consumer currently owns the wallpaper: the visible CoverSheet (locked or
// pulled down) uses LockScreen material, the visible home screen uses Desktop.
static BOOL LMVWallpaperCoverVisible(void) {
    Class cover = NSClassFromString(@"SBCoverSheetWindow");
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows)
                if (cover && [window isKindOfClass:cover] && window.screen == UIScreen.mainScreen &&
                    !window.hidden && window.alpha >= .01) return YES;
    return NO;
}
static LMVVideoState *LMVWallpaperActiveState(NSString **target) {
    BOOL cover = LMVWallpaperCoverVisible();
    *target = cover ? @"LockScreen" : @"Desktop";
    if (!LMVEnabled[*target].boolValue || !LMVPaths[*target].length) return nil;
    NSHashTable *hosts = cover ? LMVLockHosts : LMVDesktopHosts;
    for (UIView *host in hosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, cover ? &LMVLockStateKey : &LMVDesktopStateKey);
        if (state.wallpaperEligible && host.window) return state;
    }
    return nil;
}
static id LMVWallpaperContents(LMVVideoState *state) {
    if (!state) return nil;
    if (state.source.lastImage) return (__bridge id)state.source.lastImage;
    if (state.layer.contents) return state.layer.contents;
    LMVFrameSnapshot *cached = LMVCachedFrame(state.path, state.revision);
    return cached.image ? (__bridge id)cached.image : nil;
}
static void LMVWallpaperRetire(UIWindow *window) {
    LMVWallpaperSurface *surface = objc_getAssociatedObject(window, &LMVWallpaperWindowKey);
    if (!surface) return;
    LMVReleaseOriginals(surface.leases, surface); surface.leases = nil;
    [surface.layer removeFromSuperlayer];
    objc_setAssociatedObject(window, &LMVWallpaperWindowKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LMVDiagnostic(@"wallpaper-window retired original-restored");
}
static void LMVUpdateWallpaperWindow(UIWindow *window) {
    if (!NSThread.isMainThread || !window) return;
    Class secure = NSClassFromString(@"_SBWallpaperSecureWindow");
    if (!secure || ![window isKindOfClass:secure]) return;
    BOOL anyEnabled = (LMVEnabled[@"LockScreen"].boolValue && LMVPaths[@"LockScreen"].length) ||
                      (LMVEnabled[@"Desktop"].boolValue && LMVPaths[@"Desktop"].length);
    if (!anyEnabled || window.hidden || window.alpha < 0.01) { LMVWallpaperRetire(window); return; }
    NSString *target = nil;
    LMVVideoState *state = LMVWallpaperActiveState(&target);
    id contents = LMVWallpaperContents(state);
    LMVWallpaperSurface *surface = objc_getAssociatedObject(window, &LMVWallpaperWindowKey);
    // A disabled current target restores immediately, even if the other target is enabled.
    if (!LMVEnabled[target].boolValue || !LMVPaths[target].length) { LMVWallpaperRetire(window); return; }
    if (surface && (![surface.target isEqual:target] || ![surface.path isEqual:LMVPaths[target]] ||
        ![surface.revision isEqual:LMVRevisions[LMVPaths[target]]])) {
        LMVWallpaperRetire(window); surface = nil;
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (state && surface) surface.lastEligibleAt = now;
    if (!state && surface) {
        // Screen blank keeps the replaced wallpaper. Otherwise a short grace covers
        // lock<->home transitions; after it the original wallpaper returns (e.g. a
        // target whose material is disabled).
        if (LMVPlaybackAllowed() && now - surface.lastEligibleAt > 0.6) { LMVWallpaperRetire(window); return; }
        if (LMVPlaybackAllowed()) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ LMVRequestSafeUpdate(); });
    }
    // Fail-open: no frame at all keeps the original wallpaper visible.
    if (!contents && !surface.layer.contents) { LMVWallpaperRetire(window); return; }
    if (!surface) {
        surface = [LMVWallpaperSurface new];
        surface.layer = [CALayer layer]; surface.layer.name = LMVWallpaperLayerName;
        surface.layer.contentsGravity = kCAGravityResizeAspectFill; surface.layer.masksToBounds = YES;
        surface.lastEligibleAt = now;
        objc_setAssociatedObject(window, &LMVWallpaperWindowKey, surface, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    NSMutableArray<UIView *> *branches = [NSMutableArray new];
    LMVWallpaperWindowBranches(window, branches);
    if (!branches.count) {
        // No confirmed originals means no replacement: never fall back to an overlay.
        LMVWallpaperRetire(window);
        return;
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    // Keep our layer above every original branch inside the wallpaper window root.
    CALayer *root = window.layer;
    CALayer *parent = root;
    if (surface.layer.superlayer != parent || parent.sublayers.lastObject != surface.layer) {
        [surface.layer removeFromSuperlayer]; [parent addSublayer:surface.layer];
    }
    surface.layer.frame = [parent convertRect:window.bounds fromLayer:root];
    surface.layer.zPosition = 0;
    if (contents && surface.layer.contents != contents) surface.layer.contents = contents;
    surface.layer.opacity = LMVOpacityEnabled ? LMVOpacity : 0.0;
    surface.layer.hidden = NO;
    surface.target = target;
    surface.path = LMVPaths[target];
    surface.revision = LMVRevisions[surface.path];
    // Replace the original only while our surface actually holds a frame.
    NSMutableArray *live = [NSMutableArray new];
    if (surface.layer.contents) {
        for (LMVOriginalLease *lease in surface.leases) {
            UIView *owner = [lease.layer.delegate isKindOfClass:UIView.class] ? (UIView *)lease.layer.delegate : nil;
            if (owner && [branches containsObject:owner] && [lease maintain]) [live addObject:lease]; else [lease releaseOwner:surface];
        }
        for (UIView *branch in branches) {
            BOOL held = NO;
            for (LMVOriginalLease *lease in live) if (lease.layer == branch.layer) { held = YES; break; }
            if (held || !branch.superview) continue;
            LMVOriginalLease *lease = LMVAcquireOriginal(branch.layer, branch.superview.layer, LMVOriginalSuppressDrawing, surface);
            if (lease) { lease.anchor = branch.layer; [live addObject:lease]; }
        }
    } else LMVReleaseOriginals(surface.leases, surface);
    surface.leases = live;
    [CATransaction commit];
    NSString *diagnostic = [NSString stringWithFormat:@"wallpaper-window target=%@ branches=%lu leased=%lu layer=%@ frame=%@",
        surface.target ?: @"none", (unsigned long)branches.count, (unsigned long)live.count,
        surface.layer.superlayer ? @"attached" : @"none",
        state.source.lastImage ? @"live" : (surface.layer.contents ? @"cached" : @"none")];
    if (![surface.diagnostic isEqualToString:diagnostic]) { surface.diagnostic = diagnostic; LMVDiagnostic(diagnostic); }
}
static void LMVDiscoverWallpaperHosts(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    Class home = NSClassFromString(@"SBHomeScreenView");
    Class cover = NSClassFromString(@"CSCoverSheetView");
    Class secure = NSClassFromString(@"_SBWallpaperSecureWindow");
    NSUInteger budget = 512;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.screen != UIScreen.mainScreen) continue;
            if (secure && [window isKindOfClass:secure]) [LMVWallpaperWindows addObject:window];
            NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:window];
            while (pending.count && budget) {
                --budget;
                UIView *view = pending.lastObject; [pending removeLastObject];
                if (home && object_getClass(view) == home) [LMVDesktopHosts addObject:view];
                if (cover && [view isKindOfClass:cover]) [LMVLockHosts addObject:view];
                [pending addObjectsFromArray:view.subviews];
            }
        }
    }
}
static void LMVUpdateWallpaperWindows(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    Class secure = NSClassFromString(@"_SBWallpaperSecureWindow");
    if (secure) for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if ([window isKindOfClass:secure]) [LMVWallpaperWindows addObject:window];
    }
    for (UIWindow *window in LMVWallpaperWindows.allObjects) LMVUpdateWallpaperWindow(window);
}
// Called from the frame publisher: live frames go straight into the wallpaper.
static void LMVWallpaperPublish(LMVSharedSource *source, CGImageRef image) {
    NSString *target = nil;
    LMVVideoState *state = LMVWallpaperActiveState(&target);
    if (!state || state.source != source) return;
    for (UIWindow *window in LMVWallpaperWindows.allObjects) {
        LMVWallpaperSurface *surface = objc_getAssociatedObject(window, &LMVWallpaperWindowKey);
        if (surface.layer.superlayer) surface.layer.contents = (__bridge id)image;
    }
}
