#pragma once
// 0.0.67: preserve the system's Lock/Home variant roots and transition/mirror
// ownership. Never draw a shared root-window video or select it by CoverSheet
// visibility. Each observed variant controller owns its own background surface.
static char LMVWallpaperSurfaceKey;
static NSHashTable<UIWindow *> *LMVWallpaperWindows;
static BOOL LMVWallpaperUpdating;
@interface LMVWallpaperSurface : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) NSArray<LMVOriginalLease *> *leases;
@property(nonatomic,copy) NSString *target,*path,*revision,*diagnostic;
@property(nonatomic,weak) UIView *host;
@end
@implementation LMVWallpaperSurface
- (void)dealloc {
    [_layer removeFromSuperlayer];
    for (LMVOriginalLease *lease in _leases.reverseObjectEnumerator) [lease releaseOwner:self];
}
@end
static NSString *LMVWallpaperVariantTarget(UIViewController *controller) {
    Class lock=NSClassFromString(@"PBUIPosterLockViewController");
    Class home=NSClassFromString(@"PBUIPosterHomeViewController");
    if (lock && [controller isKindOfClass:lock]) return @"LockScreen";
    if (home && [controller isKindOfClass:home]) return @"Desktop";
    return nil;
}
static void LMVWallpaperFindVariants(UIViewController *controller, UIWindow *window,
                                     NSMutableDictionary<NSString *, UIView *> *variants,
                                     NSUInteger depth, NSUInteger *budget) {
    if (!controller || !*budget || depth>8) return;
    --*budget;
    NSString *target=LMVWallpaperVariantTarget(controller);
    UIView *view=controller.viewIfLoaded;
    if (target && view && view.window==window && !CGRectIsEmpty(view.bounds)) {
        // Only actual loaded Lock/Home controller roots are eligible. Unknown or
        // duplicate roots stay fail-open instead of borrowing another target.
        if (variants[target] && variants[target]!=view) variants[target]=(id)NSNull.null;
        else if (!variants[target]) variants[target]=view;
    }
    for (UIViewController *child in controller.childViewControllers)
        LMVWallpaperFindVariants(child,window,variants,depth+1,budget);
}
static BOOL LMVWallpaperTargetConsumes(NSString *target, LMVSharedSource *source) {
    NSHashTable *hosts=[target isEqualToString:@"LockScreen"]?LMVLockHosts:LMVDesktopHosts;
    char *key=[target isEqualToString:@"LockScreen"]?&LMVLockStateKey:&LMVDesktopStateKey;
    for (UIView *host in hosts.allObjects) {
        LMVVideoState *state=objc_getAssociatedObject(host,key);
        if (state.active && state.source==source && [state.path isEqual:source.path] && [state.revision isEqual:source.revision]) return YES;
    }
    return NO;
}
static id LMVWallpaperFrameForTarget(NSString *target, NSString *path, NSString *revision) {
    LMVSharedSource *source=LMVSharedSources[LMVSourceRegistryKey(path,target)];
    if ([source.revision isEqualToString:revision] && source.lastImage) return (__bridge id)source.lastImage;
    LMVFrameSnapshot *cached=LMVCachedWallpaperFrame(path,revision,target);
    if (cached.image) return (__bridge id)cached.image;
    NSHashTable *hosts=[target isEqualToString:@"LockScreen"]?LMVLockHosts:LMVDesktopHosts;
    char *key=[target isEqualToString:@"LockScreen"]?&LMVLockStateKey:&LMVDesktopStateKey;
    for (UIView *host in hosts.allObjects) {
        LMVVideoState *state=objc_getAssociatedObject(host,key);
        if ([state.path isEqualToString:path] && [state.revision isEqualToString:revision] && state.layer.contents)
            return state.layer.contents;
    }
    return nil;
}
static void LMVWallpaperRetireSurface(LMVWallpaperSurface *surface) {
    if (!surface) return;
    // Remove our drawing before reinserting the same system layers. Restoring a
    // hidden/transitioning root never changes its alpha, transform or position.
    [surface.layer removeFromSuperlayer];
    for (LMVOriginalLease *lease in surface.leases.reverseObjectEnumerator) [lease releaseOwner:surface];
    surface.leases=nil;
}
static void LMVWallpaperRetire(UIWindow *window, NSString *reason) {
    NSDictionary *surfaces=objc_getAssociatedObject(window,&LMVWallpaperSurfaceKey);
    if (!surfaces.count) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    objc_setAssociatedObject(window,&LMVWallpaperSurfaceKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (LMVWallpaperSurface *surface in surfaces.allValues) LMVWallpaperRetireSurface(surface);
    [CATransaction commit];
    LMVDiagnostic([NSString stringWithFormat:@"wallpaper-variant retired reason=%@ restored=1",reason]);
}
static BOOL LMVWallpaperHasRenderer(UIView *view, NSUInteger depth, NSUInteger *budget) {
    if (!view || !*budget || depth>10) return NO;
    --*budget;
    for (NSString *name in @[@"PBUISnapshotReplicaView", @"_UIScenePresentationView", @"_UIContextLayerHostView", @"PBUIEffectTrackingReplicaView", @"PBUIPosterFloatingLayerReplica"]) {
        Class cls=NSClassFromString(name);
        if (cls && [view isKindOfClass:cls]) return YES;
    }
    for (UIView *child in view.subviews) if (LMVWallpaperHasRenderer(child,depth+1,budget)) return YES;
    return NO;
}
static BOOL LMVWallpaperDrawingBranch(UIView *branch, UIView *host) {
    if (!branch || branch.superview!=host || !LMVBackgroundOnlyView(branch) || CGRectIsEmpty(branch.bounds)) return NO;
    NSUInteger budget=128;
    if (!LMVWallpaperHasRenderer(branch,0,&budget)) return NO;
    CGRect rect=[branch convertRect:branch.bounds toView:host];
    CGRect overlap=CGRectIntersection(rect,host.bounds);
    CGFloat full=host.bounds.size.width*host.bounds.size.height;
    return full>0 && !CGRectIsNull(overlap) && overlap.size.width*overlap.size.height/full>=.85;
}
static BOOL LMVWallpaperUpdateVariant(UIView *host, NSString *target, LMVWallpaperSurface *surface) {
    NSString *path=LMVPaths[target];
    if (!LMVEnabled[target].boolValue || !path.length || !host) return NO;
    NSString *revision=LMVRevisions[path];
    if (!revision.length) return NO;
    if (surface.host!=host || ![surface.path isEqualToString:path] || ![surface.revision isEqualToString:revision]) {
        LMVWallpaperRetireSurface(surface);
        surface.host=host; surface.path=path; surface.revision=revision;
        surface.layer.contents=nil; surface.diagnostic=nil;
    }
    surface.target=target;
    CALayer *parent=host.layer;
    // Retain Lock/Home roots: system transitions and portals keep their original
    // source layer identities. Only their confirmed wallpaper drawing children
    // detach, so replacing Lock cannot change the exposed Home wallpaper.
    NSMutableArray<UIView *> *branches=[NSMutableArray new];
    for (UIView *branch in host.subviews) if (LMVWallpaperDrawingBranch(branch,host)) [branches addObject:branch];
    NSMutableArray<LMVOriginalLease *> *live=[NSMutableArray new];
    for (LMVOriginalLease *lease in surface.leases) {
        UIView *view=[lease.layer.delegate isKindOfClass:UIView.class]?(UIView *)lease.layer.delegate:nil;
        if (lease.parent==parent && view && [branches containsObject:view] && [lease maintain]) [live addObject:lease];
        else [lease releaseOwner:surface];
    }
    for (UIView *branch in branches) {
        BOOL held=NO;
        for (LMVOriginalLease *lease in live) if (lease.layer==branch.layer) { held=YES; break; }
        if (held) continue;
        LMVOriginalLease *lease=LMVAcquireOriginal(branch.layer,parent,LMVOriginalDetach,surface);
        if (lease) { lease.anchor=host.layer; [live addObject:lease]; }
    }
    surface.leases=live;
    if (!live.count) {
        [surface.layer removeFromSuperlayer];
        NSString *message=[NSString stringWithFormat:@"wallpaper-variant target=%@ controller-root=%@ branches=%lu detached=0 action=guarded-no-op",target,NSStringFromClass(host.class),(unsigned long)branches.count];
        if (![surface.diagnostic isEqual:message]) { surface.diagnostic=message; LMVDiagnostic(message); }
        return YES;
    }
    if (!surface.layer) {
        surface.layer=[CALayer layer];
        surface.layer.name=[@"com.minis.lockmessagevideo.variant." stringByAppendingString:target];
        surface.layer.contentsGravity=kCAGravityResizeAspectFill;
        surface.layer.masksToBounds=YES;
    }
    if (surface.layer.superlayer!=parent) { [surface.layer removeFromSuperlayer]; [parent insertSublayer:surface.layer atIndex:0]; }
    surface.layer.frame=host.bounds;
    surface.layer.opacity=LMVOpacityEnabled?LMVOpacity:0.0;
    surface.layer.hidden=NO;
    if (!surface.layer.contents || LMVWallpaperTargetConsumes(target,LMVSharedSources[LMVSourceRegistryKey(path,target)])) {
        id contents=LMVWallpaperFrameForTarget(target,path,revision);
        if (contents) surface.layer.contents=contents;
    }
    NSString *message=[NSString stringWithFormat:@"wallpaper-variant target=%@ parent=%@ branches=%lu detached=%lu frame=%@ root-preserved=1 window-root-video=0",target,NSStringFromClass(host.class),(unsigned long)branches.count,(unsigned long)live.count,surface.layer.contents?@"ready":@"blank"];
    if (![surface.diagnostic isEqual:message]) { surface.diagnostic=message; LMVDiagnostic(message); }
    return YES;
}
static void LMVWallpaperUpdate(UIWindow *window) {
    NSMutableDictionary *surfaces=objc_getAssociatedObject(window,&LMVWallpaperSurfaceKey);
    if (!surfaces) { surfaces=[NSMutableDictionary new]; objc_setAssociatedObject(window,&LMVWallpaperSurfaceKey,surfaces,OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    NSMutableDictionary *variants=[NSMutableDictionary new]; NSUInteger budget=48;
    LMVWallpaperFindVariants(window.rootViewController,window,variants,0,&budget);
    if (!budget) { LMVDiagnostic(@"wallpaper-variant controller-scan-budget-exhausted update-deferred"); return; }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (NSString *target in @[@"LockScreen",@"Desktop"]) {
        id candidate=variants[target]; UIView *host=[candidate isKindOfClass:UIView.class]?candidate:nil;
        LMVWallpaperSurface *surface=surfaces[target];
        if (!host || !LMVEnabled[target].boolValue || !LMVPaths[target].length) {
            if (surface) { [surfaces removeObjectForKey:target]; LMVWallpaperRetireSurface(surface); }
            continue;
        }
        if (!surface) { surface=[LMVWallpaperSurface new]; surfaces[target]=surface; }
        if (!LMVWallpaperUpdateVariant(host,target,surface)) {
            [surfaces removeObjectForKey:target]; LMVWallpaperRetireSurface(surface);
        }
    }
    [CATransaction commit];
}
static void LMVUpdateWallpaperWindows(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread || LMVWallpaperUpdating) return;
    LMVWallpaperUpdating=YES;
    @try {
        Class secure=NSClassFromString(@"_SBWallpaperSecureWindow");
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
            if ([scene isKindOfClass:UIWindowScene.class]) for (UIWindow *window in ((UIWindowScene *)scene).windows)
                if (secure && [window isKindOfClass:secure] && window.screen==UIScreen.mainScreen) [LMVWallpaperWindows addObject:window];
        for (UIWindow *window in LMVWallpaperWindows.allObjects) {
            if (window.hidden || window.screen!=UIScreen.mainScreen) LMVWallpaperRetire(window,@"window-unavailable");
            else LMVWallpaperUpdate(window);
        }
    } @finally { LMVWallpaperUpdating=NO; }
}
static void LMVWallpaperPublish(LMVSharedSource *source, CGImageRef image) {
    if (!source || !image) return;
    for (UIWindow *window in LMVWallpaperWindows.allObjects) {
        NSDictionary *surfaces=objc_getAssociatedObject(window,&LMVWallpaperSurfaceKey);
        for (LMVWallpaperSurface *surface in surfaces.allValues) {
            if ([surface.path isEqualToString:source.path] && [surface.revision isEqualToString:source.revision] &&
                [surface.path isEqualToString:LMVPaths[surface.target]] && LMVEnabled[surface.target].boolValue &&
                surface.layer.superlayer==surface.host.layer && surface.leases.count && LMVWallpaperTargetConsumes(surface.target,source))
                surface.layer.contents=(__bridge id)image;
        }
    }
}
