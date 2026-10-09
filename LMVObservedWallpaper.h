#pragma once
// This is deliberately NOT universal secure/remote scene suppression. A concrete
// wallpaper window may contain a locally hosted pure drawing branch on some iOS
// variants. Lease that branch only; leave every window/container/content intact.
static void LMVObservedWallpaperBranches(UIView *view, UIWindow *window, NSUInteger depth, NSUInteger *budget, NSMutableArray<UIView *> *branches, NSMutableArray<NSString *> *guards) {
    if (!view || !*budget || depth > 8 || view.hidden || LMVOriginalVisibilityAlpha(view) < .01) return;
    --*budget;
    NSString *name = NSStringFromClass(view.class);
    CGRect rect = [view convertRect:view.bounds toView:window];
    if (!CGRectIntersectsRect(rect, window.bounds)) return;
    for (NSString *unsafe in @[@"Remote", @"Scene", @"Secure", @"Snapshot", @"Thumbnail", @"Passcode", @"Authentication"]) {
        if ([name containsString:unsafe]) { if (guards.count < 6) [guards addObject:name]; return; }
    }
    if ([name containsString:@"Wallpaper"] && LMVOriginalPureView(view, YES, 0)) {
        CGFloat area = window.bounds.size.width * window.bounds.size.height;
        CGRect overlap = CGRectIntersection(rect, window.bounds);
        if (area > 0 && overlap.size.width * overlap.size.height / area >= .85) [branches addObject:view];
        else if (guards.count < 6) [guards addObject:[name stringByAppendingString:@":partial-bounds"]];
        return;
    }
    // A mixed class never becomes the suppressed branch, and text/control trees
    // are not traversed. No whole-scene, global layer, clock or icon mutation.
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class] ||
        [view isKindOfClass:UIScrollView.class] || [view isKindOfClass:UITextView.class] || view.subviews.count > 24) return;
    for (UIView *child in view.subviews) LMVObservedWallpaperBranches(child, window, depth + 1, budget, branches, guards);
}
static void LMVReplaceObservedWallpaper(LMVVideoState *state, UIView *host, NSString *target, BOOL inScope) {
    if (!state) return;
    if (!inScope || !host.window || state.originals.count) {
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
    // Multiple visible full background branches have ambiguous target ownership.
    UIView *confirmed = branches.count == 1 ? branches.firstObject : nil;
    NSMutableArray *live = [NSMutableArray new];
    for (LMVOriginalLease *lease in state.wallpaperOriginals) {
        if (lease.layer == confirmed.layer && lease.scope == confirmed.superview.layer &&
            LMVOriginalPureView(confirmed, YES, 0) && [lease maintain]) [live addObject:lease];
        else [lease releaseOwner:state];
    }
    if (confirmed && !live.count) {
        LMVOriginalLease *lease = LMVAcquireOriginal(confirmed.layer, confirmed.superview.layer, LMVOriginalSuppressDrawing, state);
        if (lease) { lease.anchor = confirmed.layer; [live addObject:lease]; }
    }
    state.wallpaperOriginals = live;
    NSString *reason = live.count ? [NSString stringWithFormat:@"confirmed=%@ bounds=%@", NSStringFromClass(confirmed.class), NSStringFromCGRect(confirmed.bounds)] :
        [NSString stringWithFormat:@"guarded-no-op:full-local-branches=%lu guarded=%@ budget=%lu", (unsigned long)branches.count, [guards componentsJoinedByString:@","], (unsigned long)budget];
    NSString *diagnostic = [NSString stringWithFormat:@"original observed target=%@ host=%@ %@", target, NSStringFromClass(host.class), reason];
    if (![state.wallpaperDiagnostic isEqual:diagnostic]) { state.wallpaperDiagnostic = diagnostic; LMVDiagnostic(diagnostic); }
}
