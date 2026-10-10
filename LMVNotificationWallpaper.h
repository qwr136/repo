#pragma once
// Notification Center has a separate sliding wallpaper replica. Replacing only
// the Poster Lock root does not replace that replica during an interactive pull.
// Preserve the panel/container transform and foreground children; put video in
// its exact background branch, using the existing independent LockScreen source.
static char LMVNCWallpaperKey;
static NSHashTable<UIWindow *> *LMVNCWallpaperWindows;
static BOOL LMVNCWallpaperUpdating;
static UIView *LMVNCWallpaperFindEffect(UIView *panel, LMVWallpaperSurface *surface) {
    Class effect=NSClassFromString(@"SBWallpaperEffectView");
    for (UIView *child in panel.subviews) {
        if (!effect || ![child isKindOfClass:effect]) continue;
        BOOL owned=NO;
        for (LMVOriginalLease *lease in surface.leases)
            if ([surface.originalViews objectForKey:lease.layer]==child) { owned=YES; break; }
        // Leased background drawing is maintained through saved layer ownership.
        // Its UIView backing layer stays attached; no offline UIKit subtree.
        if (owned) continue;
        if (child.superview==panel && LMVBackgroundOnlyView(child)) return child;
    }
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
// The wallpaper panel and CoverSheet content do NOT necessarily slide together.
// Measure the actual loaded content's exposed rectangle, not panel/window bounds.
static UIView *LMVNCContentView(UIWindow *window) {
    for (UIView *cover in LMVLockHosts.allObjects) {
        if (cover.window!=window) continue;
        for (NSString *name in @[@"slideableContentView",@"contentView"]) {
            SEL selector=NSSelectorFromString(name);
            Method method=class_getInstanceMethod(cover.class,selector);
            NSMethodSignature *sig=method?[NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)]:nil;
            if (!sig || sig.numberOfArguments!=2 || strcmp(sig.methodReturnType,@encode(id))) continue;
            id candidate=((id (*)(id,SEL))objc_msgSend)(cover,selector);
            if ([candidate isKindOfClass:UIView.class] && candidate!=cover &&
                [candidate isDescendantOfView:cover]) return candidate;
        }
    }
    return nil; // Unknown geometry must not expose lock video over Home.
}
static CGRect LMVNCExposedRect(UIWindow *window) {
    if (!window || window.hidden || window.alpha<.01) return CGRectZero;
    UIView *content=LMVNCContentView(window);
    if (!content || CGRectIsEmpty(content.bounds)) return CGRectZero;
    for (UIView *node=content;node;node=node.superview)
        if (node.hidden || node.alpha<.01) return CGRectZero;
    CALayer *shown=content.layer.presentationLayer;
    CALayer *rootShown=window.layer.presentationLayer;
    CGRect rect=(shown && rootShown) ? [shown convertRect:shown.bounds toLayer:rootShown] : [content convertRect:content.bounds toView:window];
    CGRect intersection=CGRectIntersection(rect,window.bounds);
    if (CGRectIsNull(intersection) || CGRectIsInfinite(intersection) || CGRectIsEmpty(intersection)) return CGRectZero;
    return intersection;
}
static BOOL LMVNCWallpaperPanelVisible(UIView *panel) {
    UIWindow *window=panel.window;
    CGRect content=LMVNCExposedRect(window);
    if (CGRectIsEmpty(content) || !panel || CGRectIsEmpty(panel.bounds)) return NO;
    for (UIView *node=panel;node;node=node.superview)
        if (node.hidden || node.alpha<.01) return NO;
    CGRect overlap=CGRectIntersection([panel convertRect:panel.bounds toView:window],content);
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
static void LMVNCUpdateSurfaceGeometry(LMVWallpaperSurface *surface, UIWindow *window) {
    UIView *panel=surface.host;
    if (!panel || surface.layer.superlayer!=panel.layer) return;
    CGRect exposed=LMVNCExposedRect(window);
    CALayer *panelSpace=panel.layer.presentationLayer;
    CALayer *windowSpace=window.layer.presentationLayer;
    if (!panelSpace || !windowSpace) { panelSpace=panel.layer; windowSpace=window.layer; }
    // Map through the CURRENT parent presentation, so a model jump during
    // completion/cancellation cannot move the clip into the exposed Home area.
    CGRect local=CGRectIsEmpty(exposed)?CGRectZero:[panelSpace convertRect:exposed fromLayer:windowSpace];
    if (CGRectIsNull(local) || CGRectIsInfinite(local)) local=CGRectZero;
    // Keep video framing stable in window coordinates while clipping to the
    // actual content strip. This prevents both overdraw and double-scaled seams.
    CGRect full=[panelSpace convertRect:window.bounds fromLayer:windowSpace];
    if (CGRectIsNull(full) || CGRectIsInfinite(full) || CGRectIsEmpty(full)) {
        surface.layer.hidden=YES; return;
    }
    surface.layer.frame=full;
    surface.layer.opacity=LMVOpacityEnabled?LMVOpacity:0;
    CAShapeLayer *mask=[surface.layer.mask isKindOfClass:CAShapeLayer.class]?(CAShapeLayer *)surface.layer.mask:nil;
    if (!mask) {mask=[CAShapeLayer layer];surface.layer.mask=mask;}
    mask.frame=surface.layer.bounds;
    CGRect clip=CGRectOffset(local,-full.origin.x,-full.origin.y);
    if (!mask.path || !CGRectEqualToRect(CGPathGetBoundingBox(mask.path),clip)) {
        CGPathRef path=CGPathCreateWithRect(clip,NULL);mask.path=path;CGPathRelease(path);
    }
    surface.layer.hidden=CGRectIsEmpty(local);
    NSString *message=[NSString stringWithFormat:@"wallpaper-notification geometry content=%@ clip=%@ videoFrame=%@ target=LockScreen home-overdraw=blocked",NSStringFromCGRect(exposed),NSStringFromCGRect(local),NSStringFromCGRect(full)];
    if (![surface.diagnostic isEqual:message] && CACurrentMediaTime()-surface.geometryDiagnosticAt>=.25) {surface.diagnostic=message;surface.geometryDiagnosticAt=CACurrentMediaTime();LMVDiagnostic(message);}
}
static void LMVNCSetPosterLockHidden(BOOL hidden) {
    LMVLockWallpaperReplicaOwnsDisplay=hidden;
    // The Poster Lock root is behind the home window in some interactive pulls.
    // NC's explicitly clipped replica is the ONLY Lock video during presentation.
    // Leave the actual system Lock root, Home root and Home video untouched.
    for (UIWindow *window in LMVWallpaperWindows.allObjects) {
        NSDictionary *surfaces=objc_getAssociatedObject(window,&LMVWallpaperSurfaceKey);
        LMVWallpaperSurface *lock=surfaces[@"LockScreen"];
        if (lock.layer.superlayer) lock.layer.hidden=hidden;
    }
}
static void LMVUpdateNotificationWallpaperGeometry(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    BOOL ownsReplica=NO;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    for (UIWindow *window in LMVNCWallpaperWindows.allObjects) {
        NSArray *surfaces=objc_getAssociatedObject(window,&LMVNCWallpaperKey);
        for (LMVWallpaperSurface *surface in surfaces) {
            if (window.hidden || !surface.leases.count || surface.layer.superlayer!=surface.host.layer) {
                surface.layer.hidden=YES;continue;
            }
            ownsReplica=YES;
            LMVNCUpdateSurfaceGeometry(surface,window);
        }
    }
    LMVNCSetPosterLockHidden(ownsReplica);
    [CATransaction commit];
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
    surface.leases=live;
    UIView *effect=LMVNCWallpaperFindEffect(panel,surface);
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
                LMVOriginalLease *lease=LMVAcquireOriginal(effect.layer,panel.layer,LMVOriginalSuppressDrawing,surface);
                if (lease) {
                    lease.anchor=panel.layer;[surface.originalViews setObject:effect forKey:lease.layer];[live addObject:lease];
                }
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
    LMVNCUpdateSurfaceGeometry(surface,panel.window);
    LMVSharedSource *source=LMVSharedSources[LMVSourceRegistryKey(path,@"LockScreen")];
    if (!surface.layer.contents || LMVWallpaperTargetConsumes(@"LockScreen",source)) {
        id contents=LMVWallpaperFrameForTarget(@"LockScreen",path,revision);
        if (contents) surface.layer.contents=contents;
    }

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
        LMVUpdateNotificationWallpaperGeometry();
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
