#pragma once
// Notification Center has a separate sliding wallpaper replica. Replacing only
// the Poster Lock root does not replace that replica during an interactive pull.
// Preserve the panel/container transform and foreground children; put video in
// its exact background branch, using the existing independent LockScreen source.
static char LMVNCWallpaperKey;
static NSHashTable<UIWindow *> *LMVNCWallpaperWindows;
static BOOL LMVNCWallpaperUpdating;
static UIView *LMVNCWallpaperFindEffect(UIView *panel) {
    Class effect=NSClassFromString(@"SBWallpaperEffectView");
    for (UIView *child in panel.subviews)
        if (effect && [child isKindOfClass:effect] && LMVBackgroundOnlyView(child)) return child;
    return nil;
}
static void LMVNCWallpaperFindPanels(UIView *view, NSMutableArray<UIView *> *panels,
                                   NSUInteger depth, NSUInteger *budget) {
    if (!view || !*budget || depth>10) return;
    --*budget;
    Class panel=NSClassFromString(@"SBCoverSheetPanelBackgroundContainerView");
    if (panel && [view isKindOfClass:panel]) {
        if (panels.count<4) [panels addObject:view];
        return;
    }
    for (UIView *child in view.subviews) LMVNCWallpaperFindPanels(child,panels,depth+1,budget);
}
static BOOL LMVNCWallpaperPanelVisible(UIView *panel) {
    UIWindow *window=panel.window;
    if (!window || window.hidden || window.alpha<.01 || CGRectIsEmpty(panel.bounds)) return NO;
    for (UIView *node=panel;node;node=node.superview)
        if (node.hidden || node.alpha<.01) return NO;
    CGRect rect=[panel convertRect:panel.bounds toView:window];
    CGRect overlap=CGRectIntersection(rect,window.bounds);
    // Any real exposed strip is eligible, not only the full-screen final state.
    return !CGRectIsNull(overlap) && !CGRectIsEmpty(overlap) && overlap.size.height>1 && overlap.size.width>1;
}
static BOOL LMVNotificationWallpaperVisible(void) {
    Class cover=NSClassFromString(@"SBCoverSheetWindow");
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!cover || ![window isKindOfClass:cover] || window.screen!=UIScreen.mainScreen || window.hidden) continue;
            NSMutableArray<UIView *> *panels=[NSMutableArray new];NSUInteger budget=128;
            LMVNCWallpaperFindPanels(window,panels,0,&budget);
            for (UIView *panel in panels) if (LMVNCWallpaperPanelVisible(panel)) return YES;
        }
    }
    return NO;
}
static void LMVNCRetireWindow(UIWindow *window) {
    NSArray<LMVWallpaperSurface *> *surfaces=objc_getAssociatedObject(window,&LMVNCWallpaperKey);
    objc_setAssociatedObject(window,&LMVNCWallpaperKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    for (LMVWallpaperSurface *surface in surfaces) LMVWallpaperRetireSurface(surface);
}
static void LMVNCWallpaperUpdatePanel(UIView *panel, LMVWallpaperSurface *surface) {
    NSString *path=LMVPaths[@"LockScreen"],*revision=path.length?LMVRevisions[path]:nil;
    if (!revision.length) { LMVWallpaperRetireSurface(surface); return; }
    if (surface.host!=panel || ![surface.path isEqual:path] || ![surface.revision isEqual:revision]) {
        LMVWallpaperRetireSurface(surface);surface.host=panel;surface.path=path;surface.revision=revision;
        surface.layer.contents=nil;surface.diagnostic=nil;
    }
    surface.target=@"LockScreen";
    if (!surface.originalViews) surface.originalViews=[NSMapTable weakToWeakObjectsMapTable];
    NSMutableArray<LMVOriginalLease *> *live=[NSMutableArray new];
    for (LMVOriginalLease *lease in surface.leases) {
        if (LMVWallpaperLeaseBelongs(lease,surface) && [lease maintain]) [live addObject:lease];
        else LMVWallpaperReleaseLease(lease,surface);
    }
    UIView *effect=LMVNCWallpaperFindEffect(panel);
    if (effect) {
        BOOL held=NO;for (LMVOriginalLease *lease in live) if (lease.layer==effect.layer) {held=YES;break;}
        // A fresh unowned effect must belong to this exact panel, cover its
        // background and include the observed PBUIWallpaperView replica.
        if (!held && effect.superview==panel && !CGRectIsEmpty(effect.bounds)) {
            Class replica=NSClassFromString(@"PBUIWallpaperView");
            NSMutableArray<UIView *> *pending=[NSMutableArray arrayWithObject:effect];BOOL confirmed=NO;NSUInteger budget=64;
            while (pending.count && budget--) {
                UIView *node=pending.lastObject;[pending removeLastObject];
                if (replica && [node isKindOfClass:replica]) {confirmed=YES;break;}
                [pending addObjectsFromArray:node.subviews];
            }
            CGRect rect=[effect convertRect:effect.bounds toView:panel];
            CGRect overlap=CGRectIntersection(rect,panel.bounds);CGFloat full=panel.bounds.size.width*panel.bounds.size.height;
            if (confirmed && full>0 && !CGRectIsNull(overlap) && overlap.size.width*overlap.size.height/full>=.85) {
                LMVOriginalLease *lease=LMVAcquireOriginal(effect.layer,panel.layer,LMVOriginalDetach,surface);
                if (lease) {lease.anchor=panel.layer;[surface.originalViews setObject:effect forKey:lease.layer];[live addObject:lease];}
            }
        }
    }
    surface.leases=live;
    if (!live.count) { [surface.layer removeFromSuperlayer];return; }
    if (!surface.layer) {
        surface.layer=[CALayer layer];surface.layer.name=@"com.minis.lockmessagevideo.notification-wallpaper";
        surface.layer.contentsGravity=kCAGravityResizeAspectFill;surface.layer.masksToBounds=YES;
    }
    if (surface.layer.superlayer!=panel.layer) {
        [surface.layer removeFromSuperlayer];[panel.layer insertSublayer:surface.layer atIndex:0];
    }
    surface.layer.frame=panel.bounds;surface.layer.hidden=NO;surface.layer.opacity=LMVOpacityEnabled?LMVOpacity:0;
    LMVSharedSource *source=LMVSharedSources[LMVSourceRegistryKey(path,@"LockScreen")];
    if (!surface.layer.contents || LMVWallpaperTargetConsumes(@"LockScreen",source)) {
        id contents=LMVWallpaperFrameForTarget(@"LockScreen",path,revision);
        if (contents) surface.layer.contents=contents;
    }
    NSString *message=[NSString stringWithFormat:@"wallpaper-notification exposed=%d frame=%@ detached=%lu parent=%@ panelFrame=%@ independentLockSource=1",LMVNCWallpaperPanelVisible(panel),surface.layer.contents?@"ready":@"blank",(unsigned long)live.count,NSStringFromClass(panel.class),NSStringFromCGRect(panel.frame)];
    if (![surface.diagnostic isEqual:message]) {surface.diagnostic=message;LMVDiagnostic(message);}
}
static void LMVUpdateNotificationWallpapers(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread || LMVNCWallpaperUpdating) return;
    LMVNCWallpaperUpdating=YES;
    @try {
        Class cover=NSClassFromString(@"SBCoverSheetWindow");
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
            if ([scene isKindOfClass:UIWindowScene.class]) for (UIWindow *window in ((UIWindowScene *)scene).windows)
                if (cover && [window isKindOfClass:cover] && window.screen==UIScreen.mainScreen) [LMVNCWallpaperWindows addObject:window];
        [CATransaction begin];[CATransaction setDisableActions:YES];
        for (UIWindow *window in LMVNCWallpaperWindows.allObjects) {
            if (window.hidden || !LMVEnabled[@"LockScreen"].boolValue || !LMVPaths[@"LockScreen"].length) {
                LMVNCRetireWindow(window);continue;
            }
            NSMutableArray<UIView *> *panels=[NSMutableArray new];NSUInteger budget=128;
            LMVNCWallpaperFindPanels(window,panels,0,&budget);
            if (!budget) continue;
            NSArray<LMVWallpaperSurface *> *old=objc_getAssociatedObject(window,&LMVNCWallpaperKey);
            NSMutableArray *surfaces=[NSMutableArray new];
            for (UIView *panel in panels) {
                LMVWallpaperSurface *surface=nil;
                for (LMVWallpaperSurface *previous in old) if (previous.host==panel) {surface=previous;break;}
                if (!surface) surface=[LMVWallpaperSurface new];
                LMVNCWallpaperUpdatePanel(panel,surface);[surfaces addObject:surface];
            }
            for (LMVWallpaperSurface *previous in old) if (![surfaces containsObject:previous]) LMVWallpaperRetireSurface(previous);
            objc_setAssociatedObject(window,&LMVNCWallpaperKey,surfaces,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [CATransaction commit];
    } @finally {LMVNCWallpaperUpdating=NO;}
}
static void LMVNotificationWallpaperPublish(LMVSharedSource *source, CGImageRef image) {
    if (!source || !image || ![source.ownerTarget isEqual:@"LockScreen"]) return;
    for (UIWindow *window in LMVNCWallpaperWindows.allObjects) {
        NSArray<LMVWallpaperSurface *> *surfaces=objc_getAssociatedObject(window,&LMVNCWallpaperKey);
        for (LMVWallpaperSurface *surface in surfaces)
            if (surface.leases.count && surface.layer.superlayer==surface.host.layer &&
                [surface.path isEqual:source.path] && [surface.revision isEqual:source.revision] &&
                [surface.path isEqual:LMVPaths[@"LockScreen"]] && LMVEnabled[@"LockScreen"].boolValue)
                surface.layer.contents=(__bridge id)image;
    }
}
