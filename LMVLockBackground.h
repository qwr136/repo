#pragma once
// One lock source and one noninteractive layer per CoverSheet. Original views,
// backing layers and wallpaper effects remain untouched. The layer sits above
// the observed background child, but below clock, notifications and controls.
static BOOL LMVLockObjectGetter(id value, SEL selector) {
    if (![value respondsToSelector:selector]) return NO;
    NSMethodSignature *signature=[value methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments==2 && !strcmp(signature.methodReturnType,@encode(id));
}
static BOOL LMVLockRectValid(CGRect rect) {
    return !CGRectIsNull(rect) && !CGRectIsInfinite(rect) &&
        isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
        isfinite(rect.size.width) && isfinite(rect.size.height) && !CGRectIsEmpty(rect);
}
static UIView *LMVLockContentView(UIView *cover) {
    // Only getters already observed on the actual CoverSheet host are called.
    for (NSString *name in @[@"slideableContentView",@"contentView"]) {
        SEL selector=NSSelectorFromString(name);
        if (!LMVLockObjectGetter(cover,selector)) continue;
        id candidate=((id (*)(id,SEL))objc_msgSend)(cover,selector);
        if ([candidate isKindOfClass:UIView.class] && candidate!=cover &&
            [candidate isDescendantOfView:cover]) return candidate;
    }
    // Some versions move the CoverSheet itself through PositionView. Do not
    // infer a full-screen region from the window alone.
    return cover;
}
static UIView *LMVLockBackgroundChild(UIView *host) {
    Class background=NSClassFromString(@"SBUIBackgroundView");
    for (UIView *view in host.subviews)
        if (background && [view isKindOfClass:background]) return view;
    return nil;
}
static CGRect LMVLockRectInSpace(UIView *cover,UIView *content,CALayer *contentSpace,CALayer *windowSpace) {
    UIWindow *window=cover.window;
    if (!content || !window || window.hidden || window.alpha<.01 || !LMVLockRectValid(content.bounds)) return CGRectZero;
    for (UIView *view=content;view;view=view.superview)
        if (view.hidden || view.alpha<.01) return CGRectZero;
    if (!contentSpace || !windowSpace) return CGRectZero;
    CGRect rect=[contentSpace convertRect:contentSpace.bounds toLayer:windowSpace];
    if (!LMVLockRectValid(rect)) return CGRectZero;
    CGRect intersection=CGRectIntersection(rect,window.bounds);
    return LMVLockRectValid(intersection)?intersection:CGRectZero;
}
static CGRect LMVLockExposedRect(UIView *cover,UIView *content) {
    CALayer *contentSpace=content.layer.presentationLayer;
    CALayer *windowSpace=cover.window.layer.presentationLayer;
    if (!contentSpace || !windowSpace) {contentSpace=content.layer;windowSpace=cover.window.layer;}
    return LMVLockRectInSpace(cover,content,contentSpace,windowSpace);
}
static BOOL LMVLockOverlayVisible(UIView *cover) {
    Class host=NSClassFromString(@"CSCoverSheetView");
    Class window=NSClassFromString(@"SBCoverSheetWindow");
    if (!host || ![cover isKindOfClass:host] || !window || ![cover.window isKindOfClass:window]) return NO;
    CGRect rect=LMVLockExposedRect(cover,LMVLockContentView(cover));
    return !CGRectIsEmpty(rect) && rect.size.height>1 && rect.size.width>1;
}
static void LMVLayoutLockOverlay(UIView *cover, LMVVideoState *state) {
    if (!cover || !state.layer) return;
    if (!LMVEnabled[@"LockScreen"].boolValue || ![state.path isEqualToString:LMVPaths[@"LockScreen"]]) {
        [state.layer removeFromSuperlayer];state.displayHost=nil;return;
    }
    UIView *content=LMVLockContentView(cover);
    UIView *host=LMVLockBackgroundChild(content) ? content : cover;
    UIView *background=LMVLockBackgroundChild(host);
    CALayer *parent=host.layer;
    CALayer *video=state.layer;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    // Insert only our own leaf layer. No removal/suppression of system layers.
    NSArray *children=parent.sublayers;
    NSUInteger own=[children indexOfObjectIdenticalTo:video];
    NSUInteger back=background ? [children indexOfObjectIdenticalTo:background.layer] : NSNotFound;
    BOOL ordered=video.superlayer==parent && (back==NSNotFound ? own==0 : own==back+1);
    if (!ordered) {
        [video removeFromSuperlayer];
        if (background && background.layer.superlayer==parent) [parent insertSublayer:video above:background.layer];
        else [parent insertSublayer:video atIndex:0];
    }
    state.displayHost=host;
    video.frame=host.bounds;
    video.opacity=1.0f;
    video.backgroundColor=UIColor.blackColor.CGColor;
    video.contentsGravity=kCAGravityResizeAspectFill;
    video.masksToBounds=YES;
    CALayer *hostSpace=parent.presentationLayer;
    CALayer *contentSpace=content.layer.presentationLayer;
    CALayer *windowSpace=cover.window.layer.presentationLayer;
    if (!hostSpace || !contentSpace || !windowSpace) {
        hostSpace=parent;contentSpace=content.layer;windowSpace=cover.window.layer;
    }
    // All three participants use the same tree for measurement and inverse mapping.
    CGRect exposed=LMVLockRectInSpace(cover,content,contentSpace,windowSpace);
    CGRect local=CGRectIsEmpty(exposed)?CGRectZero:[hostSpace convertRect:exposed fromLayer:windowSpace];
    if (!LMVLockRectValid(local)) local=CGRectZero;
    local=CGRectIntersection(local,host.bounds);
    if (!LMVLockRectValid(local)) local=CGRectZero;
    CGRect clip=CGRectOffset(local,-host.bounds.origin.x,-host.bounds.origin.y);
    CAShapeLayer *mask=[video.mask isKindOfClass:CAShapeLayer.class]?(CAShapeLayer *)video.mask:nil;
    if (!mask) {mask=[CAShapeLayer layer];video.mask=mask;}
    mask.frame=video.bounds;
    if (!mask.path || !CGRectEqualToRect(CGPathGetBoundingBox(mask.path),clip)) {
        CGPathRef path=CGPathCreateWithRect(clip,NULL);mask.path=path;CGPathRelease(path);
    }
    video.hidden=!video.contents || CGRectIsEmpty(local) || !LMVEnabled[@"LockScreen"].boolValue;
    NSString *mode=background?@"above-system-background":@"under-foreground-fallback";
    NSString *message=[NSString stringWithFormat:@"lock-overlay mode=%@ parent=%@ opaque=1 frame=%d exposed=%@ originalHierarchy=intact opacityControl=excluded",
        mode,NSStringFromClass(host.class),video.contents!=nil,NSStringFromCGRect(exposed)];
    if (![state.displayDiagnostic isEqual:message] && CACurrentMediaTime()-state.displayDiagnosticAt>.25) {
        state.displayDiagnostic=message;state.displayDiagnosticAt=CACurrentMediaTime();LMVDiagnostic(message);
    }
    [CATransaction commit];
}
static void LMVDiscoverLockHosts(void) {
    Class windowClass=NSClassFromString(@"SBCoverSheetWindow");
    Class hostClass=NSClassFromString(@"CSCoverSheetView");
    NSUInteger budget=256;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!windowClass || ![window isKindOfClass:windowClass] || window.screen!=UIScreen.mainScreen) continue;
            NSMutableArray<UIView *> *pending=[NSMutableArray arrayWithObject:window];
            while (pending.count && budget) {
                --budget;UIView *view=pending.lastObject;[pending removeLastObject];
                if (hostClass && [view isKindOfClass:hostClass]) [LMVLockHosts addObject:view];
                [pending addObjectsFromArray:view.subviews];
            }
        }
    }
}
