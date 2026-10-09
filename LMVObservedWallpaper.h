#pragma once
// This is deliberately NOT universal secure/remote scene suppression. A concrete
// wallpaper window may contain a locally hosted pure drawing branch on some iOS
// variants. Lease that branch only; leave every window/container/content intact.
// 0.0.61: iOS 16 wallpaper is hosted Remote/Scene content inside the dedicated
// _SBWallpaperSecureWindow. That window draws only wallpaper (no clock, icons,
// Dock or notifications), so its full-screen background-only child views are
// suppressed by restorable opacity lease; the window and every object stay alive.
static void LMVObservedWallpaperBranches(UIView *view, UIWindow *window, NSUInteger depth, NSUInteger *budget, NSMutableArray<UIView *> *branches, NSMutableArray<NSString *> *guards) {
    if (!view || !*budget || depth > 8 || view.hidden || LMVOriginalVisibilityAlpha(view) < .01) return;
    --*budget;
    NSString *name = NSStringFromClass(view.class);
    CGRect rect = [view convertRect:view.bounds toView:window];
    if (!CGRectIntersectsRect(rect, window.bounds)) return;
    for (NSString *unsafe in @[@"Passcode", @"Authentication", @"Biometric"]) {
        if ([name containsString:unsafe]) { if (guards.count < 6) [guards addObject:name]; return; }
    }
    CGFloat area = window.bounds.size.width * window.bounds.size.height;
    CGRect overlap = CGRectIntersection(rect, window.bounds);
    BOOL full = area > 0 && overlap.size.width * overlap.size.height / area >= .85;
    if (full && LMVBackgroundOnlyView(view)) { [branches addObject:view]; return; }
    if (!full) { if (guards.count < 6) [guards addObject:[name stringByAppendingString:@":partial-bounds"]]; return; }
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class] ||
        [view isKindOfClass:UIScrollView.class] || [view isKindOfClass:UITextView.class] || view.subviews.count > 24) {
        if (guards.count < 6) [guards addObject:[name stringByAppendingString:@":content"]]; return;
    }
    for (UIView *child in view.subviews) LMVObservedWallpaperBranches(child, window, depth + 1, budget, branches, guards);
}
static void LMVReplaceObservedWallpaper(LMVVideoState *state, UIView *host, NSString *target, BOOL inScope) {
    if (!state) return;
    // Host-local leases no longer short-circuit: the separate wallpaper window still draws.
    if (!inScope || !host.window) {
        LMVReleaseOriginals(state.wallpaperOriginals, state); state.wallpaperOriginals = nil; return;
    }
    Class wallpaperWindow = NSClassFromString(@"_SBWallpaperSecureWindow");
    NSMutableArray<UIView *> *branches = [NSMutableArray new];
    NSMutableArray<NSString *> *guards = [NSMutableArray new];
    NSUInteger windows = 0, budget = 96;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState == UISceneActivationStateUnattached) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (++windows > 24 || !budget) break;
            if (!wallpaperWindow || ![window isKindOfClass:wallpaperWindow] || window.hidden ||
                window.alpha < .01 || window.screen != host.window.screen) continue;
            // Enumerate the window's direct children but never acquire its backing layer.
            for (UIView *child in window.subviews) LMVObservedWallpaperBranches(child, window, 0, &budget, branches, guards);
        }
    }
    // Every full background-only branch of the wallpaper window is wallpaper.
    NSMutableArray *live = [NSMutableArray new];
    for (LMVOriginalLease *lease in state.wallpaperOriginals) {
        UIView *owner = [lease.layer.delegate isKindOfClass:UIView.class] ? (UIView *)lease.layer.delegate : nil;
        if (owner && [branches containsObject:owner] && lease.scope == owner.superview.layer && [lease maintain]) [live addObject:lease];
        else [lease releaseOwner:state];
    }
    for (UIView *branch in branches) {
        BOOL held = NO;
        for (LMVOriginalLease *lease in live) if (lease.layer == branch.layer) { held = YES; break; }
        if (held || !branch.superview) continue;
        LMVOriginalLease *lease = LMVAcquireOriginal(branch.layer, branch.superview.layer, LMVOriginalSuppressDrawing, state);
        if (lease) { lease.anchor = branch.layer; [live addObject:lease]; }
    }
    UIView *confirmed = branches.firstObject;
    state.wallpaperOriginals = live;
    NSString *reason = live.count ? [NSString stringWithFormat:@"confirmed=%@ count=%lu bounds=%@", NSStringFromClass(confirmed.class), (unsigned long)live.count, NSStringFromCGRect(confirmed.bounds)] :
        [NSString stringWithFormat:@"guarded-no-op:full-local-branches=%lu guarded=%@ budget=%lu", (unsigned long)branches.count, [guards componentsJoinedByString:@","], (unsigned long)budget];
    NSString *diagnostic = [NSString stringWithFormat:@"original observed target=%@ host=%@ %@", target, NSStringFromClass(host.class), reason];
    if (![state.wallpaperDiagnostic isEqual:diagnostic]) { state.wallpaperDiagnostic = diagnostic; LMVDiagnostic(diagnostic); }
}
