// Discovery never treats our own suppression as UIKit hiding the anchor.
// UIKit can expose CALayer.opacity through UIView.alpha; use the leased baseline.
static CGFloat LMVOriginalVisibilityAlpha(UIView *view) {
    LMVOriginalLease *lease = [LMVOriginalLeases() objectForKey:view.layer];
    return lease && !lease.retired && lease.method == LMVOriginalSuppressDrawing &&
        view.layer.opacity == 0.0f ? lease.baselineOpacity : view.alpha;
}
static BOOL LMVOriginalPureBranch(UIView *view, BOOL wallpaper, NSUInteger depth, NSUInteger *remaining) {
    if (!*remaining) return NO;
    --*remaining;
    if (!view || depth > 8 || view.subviews.count > 24 || view.layer.sublayers.count > 24 ||
        [view isKindOfClass:UIControl.class] ||
        [view isKindOfClass:UILabel.class] || [view isKindOfClass:UITextView.class] ||
        [view isKindOfClass:UIScrollView.class] || view.gestureRecognizers.count ||
        view.isAccessibilityElement) return NO;
    NSString *name = NSStringFromClass(view.class);
    BOOL known = wallpaper ? ([name containsString:@"Wallpaper"] ||
        [name containsString:@"Backdrop"] || [view isKindOfClass:UIImageView.class]) :
        ([name containsString:@"MaterialView"] || [name containsString:@"Backdrop"] ||
         [name containsString:@"VisualEffect"] || [name containsString:@"TintView"]);
    // Wallpaper scene/remote content and secure windows are never detachable.
    for (NSString *word in @[@"Window", @"Scene", @"Remote", @"Secure", @"Controller", @"Thumbnail", @"Snapshot"])
        if ([name containsString:word]) return NO;
    if (!known) return NO;
    for (UIView *child in view.subviews) if (!LMVOriginalPureBranch(child, wallpaper, depth + 1, remaining)) return NO;
    for (CALayer *layer in view.layer.sublayers) {
        if ([layer.name hasPrefix:@"com.minis.lockmessagevideo"]) return NO;
        BOOL childBacking = NO;
        for (UIView *child in view.subviews) if (child.layer == layer) { childBacking = YES; break; }
        if (childBacking) continue;
        // Entire branch suppression must not conceal text, an unknown rendering tree,
        // masks or other plugins. Unrecognised sublayers force the guarded path.
        NSString *layerName = NSStringFromClass(layer.class);
        BOOL knownDraw = [layerName containsString:@"Backdrop"] ||
            (wallpaper && [layerName containsString:@"Wallpaper"] && ![layerName containsString:@"Remote"]) ||
            (!layer.contents && layer.backgroundColor && object_getClass(layer) == CALayer.class);
        for (NSString *word in @[@"Text", @"Remote", @"Secure", @"Scene", @"Thumbnail", @"Snapshot"])
            if ([layerName containsString:word]) return NO;
        if (layer.sublayers.count || layer.mask || !knownDraw) return NO;
        if (layer.delegate && layer.delegate != view) return NO;
    }
    return YES;
}
static BOOL LMVOriginalPureView(UIView *view, BOOL wallpaper, NSUInteger depth) {
    NSUInteger remaining = 96;
    return LMVOriginalPureBranch(view, wallpaper, depth, &remaining);
}
static void LMVOriginalCandidateBranch(UIView *view, BOOL wallpaper, NSUInteger depth, NSMutableArray *candidates, NSUInteger *remaining) {
    if (!*remaining) return;
    --*remaining;
    if (!view || depth > 8 || view.subviews.count > 24 || view.layer.sublayers.count > 24 || candidates.count >= 24 ||
        [view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] ||
        [view isKindOfClass:UITextView.class] || [view isKindOfClass:UIScrollView.class]) return;
    BOOL pure = !wallpaper && LMVOriginalPureView(view, NO, 0);
    BOOL detachOnly = pure && view.subviews.count == 0 && !view.layer.contents &&
        !view.layer.backgroundColor && object_getClass(view.layer) == CALayer.class;
    // Prefer real offline detach for independent draw leaves. A UIView backing
    // layer stays attached whenever it draws or owns UIKit background subviews.
    if (pure && !detachOnly) {
        [candidates addObject:@{@"layer":view.layer, @"method":@(LMVOriginalSuppressDrawing)}];
        return;
    }
    for (CALayer *layer in view.layer.sublayers) {
        BOOL childBacking = NO;
        for (UIView *child in view.subviews) if (child.layer == layer) { childBacking = YES; break; }
        if (childBacking || layer.delegate || layer.sublayers.count || layer.mask ||
            layer.hidden || [layer.name hasPrefix:@"com.minis.lockmessagevideo"]) continue;
        NSString *name = NSStringFromClass(layer.class);
        BOOL confirmed = wallpaper ? ([name containsString:@"Wallpaper"] && ![name containsString:@"Remote"]) :
            ([name containsString:@"Backdrop"]);
        BOOL unsafe = NO;
        for (NSString *word in @[@"Text", @"Remote", @"Secure", @"Scene", @"Thumbnail", @"Snapshot"])
            if ([name containsString:word]) unsafe = YES;
        if (!confirmed || unsafe || CGRectIsEmpty(layer.bounds)) continue;
        [candidates addObject:@{@"layer":layer, @"method":@(LMVOriginalDetach)}];
    }
    for (UIView *child in view.subviews) {
        NSString *name = NSStringFromClass(child.class);
        if (wallpaper && ([name containsString:@"Remote"] || [name containsString:@"Scene"] ||
            [name containsString:@"Window"] || [name containsString:@"Snapshot"] || [name containsString:@"Thumbnail"])) continue;
        if (wallpaper && [name containsString:@"Wallpaper"] && LMVOriginalPureView(child, YES, 0)) {
            [candidates addObject:@{@"layer":child.layer, @"method":@(LMVOriginalSuppressDrawing)}];
        } else if ((!wallpaper && ([name containsString:@"Backdrop"] || [name containsString:@"MaterialView"] ||
                     [name containsString:@"VisualEffect"])) || (wallpaper && [name containsString:@"Wallpaper"])) {
            LMVOriginalCandidateBranch(child, wallpaper, depth + 1, candidates, remaining);
        }
    }
}
static void LMVOriginalCandidates(UIView *view, BOOL wallpaper, NSUInteger depth, NSMutableArray *candidates) {
    NSUInteger remaining = 96;
    LMVOriginalCandidateBranch(view, wallpaper, depth, candidates, &remaining);
}
static void LMVRestoreBackground(LMVVideoState *state) {
    LMVReleaseOriginals(state.originals, state);
    state.originals = nil; state.originalAnchor = nil; state.originalScope = nil;
}
static void LMVReplaceBackground(LMVVideoState *state, UIView *anchor, UIView *scope, NSString *target, BOOL inScope) {
    if (!state) return;
    if (!inScope || !anchor || !scope || state.originalAnchor != anchor || state.originalScope != scope) {
        LMVRestoreBackground(state);
        if (!inScope || !anchor || !scope) return;
        state.originalAnchor = anchor; state.originalScope = scope;
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    BOOL wallpaper = [target isEqualToString:@"LockScreen"] || [target isEqualToString:@"Desktop"];
    NSMutableArray *live = [NSMutableArray new];
    for (LMVOriginalLease *lease in state.originals) {
        id delegate = lease.layer.delegate;
        BOOL safe = lease.method == LMVOriginalDetach ?
            (!delegate && !lease.layer.sublayers.count && !lease.layer.mask) :
            ([delegate isKindOfClass:UIView.class] && LMVOriginalPureView(delegate, wallpaper, 0));
        if (safe && [lease maintain]) [live addObject:lease]; else [lease releaseOwner:state];
    }
    NSMutableArray *candidates = [NSMutableArray new];
    // A second consumer cannot discover a leaf already detached by the first.
    // Search the weak lease registry only at initial binding, never per frame.
    if (!state.originals.count) for (LMVOriginalLease *shared in [LMVOriginalLeases() objectEnumerator]) {
        if (!shared.retired && shared.method == LMVOriginalDetach &&
            shared.anchor == anchor.layer && shared.scope == scope.layer && [shared maintain])
            [candidates addObject:@{@"layer":shared.layer, @"method":@(LMVOriginalDetach)}];
    }
    LMVOriginalCandidates(anchor, wallpaper, 0, candidates);
    for (NSDictionary *candidate in candidates) {
        CALayer *layer = candidate[@"layer"];
        BOOL exists = NO;
        for (LMVOriginalLease *lease in live) if (lease.layer == layer) { exists = YES; break; }
        if (exists) continue;
        LMVOriginalLease *lease = LMVAcquireOriginal(layer, scope.layer, [candidate[@"method"] unsignedIntegerValue], state);
        if (lease) { lease.anchor = anchor.layer; [live addObject:lease]; }
    }
    state.originals = live;
    [CATransaction commit];
    NSUInteger detached = 0;
    for (LMVOriginalLease *lease in live) if (lease.method == LMVOriginalDetach) detached++;
    NSString *reason = live.count ? [NSString stringWithFormat:@"detach=%lu drawing-disabled=%lu", (unsigned long)detached, (unsigned long)(live.count - detached)] :
        (wallpaper ? @"guarded-no-op:no-local-pure-wallpaper; secure-window-shared-or-unidentified" : @"guarded-no-op:material-has-content-or-unidentified");
    NSString *diagnostic = [NSString stringWithFormat:@"original target=%@ %@", target, reason];
    if (![state.originalDiagnostic isEqualToString:diagnostic]) { state.originalDiagnostic = diagnostic; LMVDiagnostic(diagnostic); }
}
