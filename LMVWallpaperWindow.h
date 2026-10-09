#pragma once
// 0.0.66: direct wallpaper replacement. Confirmed wallpaper backing branches
// are detached from their original parents; no system object is deallocated.
// The video layer is the only background layer in _SBWallpaperSecureWindow.
static char LMVWallpaperSurfaceKey;
static NSHashTable<UIWindow *> *LMVWallpaperWindows;
@interface LMVWallpaperSurface : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) NSArray<LMVOriginalLease *> *leases;
@property(nonatomic,copy) NSString *target,*path,*revision,*diagnostic;
@property(nonatomic,weak) LMVVideoState *state;
@end
@implementation LMVWallpaperSurface
- (void)dealloc { LMVReleaseOriginals(_leases,self); [_layer removeFromSuperlayer]; }
@end
static BOOL LMVWallpaperCoverIsVisible(void) {
    Class cover=NSClassFromString(@"SBCoverSheetWindow");
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class]) for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (cover && [window isKindOfClass:cover] && !window.hidden && window.alpha>=.01) return YES;
    return NO;
}
static LMVVideoState *LMVWallpaperState(NSString **target) {
    BOOL lock=LMVWallpaperCoverIsVisible(); *target=lock?@"LockScreen":@"Desktop";
    NSHashTable *hosts=lock?LMVLockHosts:LMVDesktopHosts;
    char *key=lock?&LMVLockStateKey:&LMVDesktopStateKey;
    if (!LMVEnabled[*target].boolValue || !LMVPaths[*target].length) return nil;
    for (UIView *host in hosts.allObjects) {
        LMVVideoState *state=objc_getAssociatedObject(host,key);
        if (state && state.wallpaperEligible && host.window) return state;
    }
    return nil;
}
static void LMVWallpaperRetire(UIWindow *window, NSString *reason) {
    LMVWallpaperSurface *surface=objc_getAssociatedObject(window,&LMVWallpaperSurfaceKey);
    if (!surface) return;
    LMVReleaseOriginals(surface.leases,surface); surface.leases=nil;
    [surface.layer removeFromSuperlayer];
    objc_setAssociatedObject(window,&LMVWallpaperSurfaceKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LMVDiagnostic([NSString stringWithFormat:@"wallpaper-direct retired reason=%@ restored=1",reason]);
}
static void LMVWallpaperUpdate(UIWindow *window) {
    if (!NSThread.isMainThread || !window) return;
    Class secure=NSClassFromString(@"_SBWallpaperSecureWindow");
    if (!secure || ![window isKindOfClass:secure]) return;
    NSString *target=nil; LMVVideoState *state=LMVWallpaperState(&target);
    BOOL eligible=state!=nil;
    LMVWallpaperSurface *surface=objc_getAssociatedObject(window,&LMVWallpaperSurfaceKey);
    if (!eligible) { LMVWallpaperRetire(window,@"no-enabled-visible-target"); return; }
    if (!surface) {
        surface=[LMVWallpaperSurface new]; surface.layer=[CALayer layer];
        surface.layer.name=@"com.minis.lockmessagevideo.direct-wallpaper";
        surface.layer.contentsGravity=kCAGravityResizeAspectFill; surface.layer.masksToBounds=YES;
        objc_setAssociatedObject(window,&LMVWallpaperSurfaceKey,surface,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    surface.state=state; surface.target=target; surface.path=state.path; surface.revision=state.revision;
    NSMutableArray<UIView *> *branches=[NSMutableArray new]; NSMutableArray<NSString *> *guards=[NSMutableArray new]; NSUInteger budget=128;
    for (UIView *child in window.subviews) LMVObservedWallpaperBranches(child,window,0,&budget,branches,guards);
    if (!branches.count) {
        LMVDiagnostic([NSString stringWithFormat:@"wallpaper-direct target=%@ branches=0 action=guarded-no-op guards=%@",target,[guards componentsJoinedByString:@","]]);
        return;
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CALayer *root=window.layer;
    if (surface.layer.superlayer != root) { [surface.layer removeFromSuperlayer]; [root addSublayer:surface.layer]; }
    surface.layer.frame=window.bounds; surface.layer.hidden=NO; surface.layer.opacity=LMVOpacityEnabled?LMVOpacity:0.0;
    id contents=state.layer.contents;
    if (!contents && state.source.lastImage) contents=(__bridge id)state.source.lastImage;
    if (!contents) { LMVFrameSnapshot *cached=LMVCachedFrame(state.path,state.revision); if (cached.image) contents=(__bridge id)cached.image; }
    if (contents) surface.layer.contents=contents;
    // Detach all confirmed wallpaper branches. Their lease restores exact parent,
    // index and neighboring layers when this target is disabled or changes scope.
    NSMutableArray *live=[NSMutableArray new];
    for (LMVOriginalLease *lease in surface.leases) {
        UIView *owner=[lease.layer.delegate isKindOfClass:UIView.class]?(UIView *)lease.layer.delegate:nil;
        if (owner && [branches containsObject:owner] && [lease maintain]) [live addObject:lease];
        else [lease releaseOwner:surface];
    }
    for (UIView *branch in branches) {
        BOOL held=NO; for (LMVOriginalLease *lease in live) if (lease.layer==branch.layer) { held=YES; break; }
        if (held || !branch.superview) continue;
        LMVOriginalLease *lease=LMVAcquireOriginal(branch.layer,branch.superview.layer,LMVOriginalDetach,surface);
        if (lease) { lease.anchor=branch.layer; [live addObject:lease]; }
    }
    surface.leases=live;
    [CATransaction commit];
    NSString *frame = contents ? (state.source.lastImage ? @"live" : @"cached") : @"blank";
    NSString *diag=[NSString stringWithFormat:@"wallpaper-direct target=%@ branches=%lu detached=%lu layer=%@ frame=%@",target,(unsigned long)branches.count,(unsigned long)live.count,surface.layer.superlayer?@"attached":@"none",frame];
    if (![surface.diagnostic isEqualToString:diag]) { surface.diagnostic=diag; LMVDiagnostic(diag); }
}
static void LMVUpdateWallpaperWindows(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    Class secure=NSClassFromString(@"_SBWallpaperSecureWindow");
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class])
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (secure && [window isKindOfClass:secure]) [LMVWallpaperWindows addObject:window];
    for (UIWindow *window in LMVWallpaperWindows.allObjects) {
        if (window.hidden || window.alpha<.01) LMVWallpaperRetire(window,@"window-hidden"); else LMVWallpaperUpdate(window);
    }
}
static void LMVWallpaperPublish(LMVSharedSource *source, CGImageRef image) {
    if (!source || !image) return;
    for (UIWindow *window in LMVWallpaperWindows.allObjects) {
        LMVWallpaperSurface *surface=objc_getAssociatedObject(window,&LMVWallpaperSurfaceKey);
        if (surface && surface.state.source==source && surface.layer.superlayer) surface.layer.contents=(__bridge id)image;
    }
}
