#pragma once
// Message-family consumption only. Never change UIKit geometry or background leases.
#import <QuartzCore/QuartzCore.h>

@interface LMVCardExposureEvidence : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic) BOOL observed, transferred, exposed;
@property(nonatomic) BOOL probeArmed;
@property(nonatomic) CFTimeInterval probeUntil;
@end
@implementation LMVCardExposureEvidence @end
static char LMVCardExposureKey;
static LMVCardExposureEvidence *LMVCardEvidence(UIView *view) {
    LMVCardExposureEvidence *e=objc_getAssociatedObject(view,&LMVCardExposureKey);
    if (!e) {
        e=[LMVCardExposureEvidence new];
        objc_setAssociatedObject(view,&LMVCardExposureKey,e,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIWindow *window=view.window;
    if (e.observed && e.window!=window) {
        // A presentation snapshot from the previous window is not admission.
        e.transferred=YES; e.exposed=NO; e.probeArmed=NO; e.probeUntil=0;
    }
    e.observed=YES; e.window=window;
    return e;
}
static BOOL LMVCardRectValid(CGRect rect) {
    return !CGRectIsNull(rect) && !CGRectIsInfinite(rect) &&
        isfinite(rect.origin.x) && isfinite(rect.origin.y) &&
        isfinite(rect.size.width) && isfinite(rect.size.height) &&
        rect.size.width>=1 && rect.size.height>=1;
}
static BOOL LMVCardAttached(UIView *view, UIWindow *window) {
    if (!view || !window || view.window!=window) return NO;
    for (UIView *node=view; node; node=node.superview) {
        if (node.window!=window) return NO;
        if (node==window) return YES;
        if (!node.superview || node.layer.superlayer!=node.superview.layer) return NO;
    }
    return NO;
}
static CGFloat LMVCardExposureAlpha(UIView *view, CALayer *layer, BOOL presentation) {
    if (!presentation) return LMVOriginalVisibilityAlpha(view);
    LMVOriginalLease *lease=[LMVOriginalLeases() objectForKey:view.layer];
    // A background-only backing layer may be opacity-zero solely because WE
    // suppressed it. Correct both trees, but not real ancestor/overlay alpha.
    if (lease && !lease.retired && lease.method==LMVOriginalSuppressDrawing &&
        view.layer.opacity==0.0f && layer.opacity==0.0f) return lease.baselineOpacity;
    return layer.opacity;
}
static BOOL LMVCardExposureInTree(UIView *view, UIWindow *window, BOOL presentation) {
    if (!LMVCardAttached(view,window)) return NO;
    CALayer *root=presentation ? window.layer.presentationLayer : window.layer;
    CALayer *space=presentation ? view.layer.presentationLayer : view.layer;
    if (!root || !space || (presentation && (root.modelLayer!=window.layer || space.modelLayer!=view.layer))) return NO;
    CGRect rect=[space convertRect:space.bounds toLayer:root];
    if (!LMVCardRectValid(rect)) return NO;
    CGFloat alpha=1;
    for (UIView *node=view; node; node=node.superview) {
        CALayer *layer=presentation ? node.layer.presentationLayer : node.layer;
        if (!layer || (presentation && layer.modelLayer!=node.layer)) return NO;
        if ((!presentation && node.hidden) || layer.hidden) return NO;
        alpha*=LMVCardExposureAlpha(node,layer,presentation);
        if (!isfinite(alpha) || alpha<0.01) return NO;
        if (node!=window) {
            CALayer *parent=presentation ? node.superview.layer.presentationLayer : node.superview.layer;
            // Do not mix model/presentation coordinates or trust stale detached trees.
            if (!parent || layer.superlayer!=parent) return NO;
        }
        if (node.clipsToBounds || layer.masksToBounds || node==window) {
            rect=CGRectIntersection(rect,[layer convertRect:layer.bounds toLayer:root]);
            if (!LMVCardRectValid(rect)) return NO;
        }
        if (node==window) break;
    }
    rect=CGRectIntersection(rect,LMVVideoWindowViewport(window));
    return LMVCardRectValid(rect);
}
static BOOL LMVCardPresentationMotion(UIView *view) {
    // Only this attached ancestor chain; no subtree/window discovery per frame.
    for (UIView *node=view; node; node=node.superview) {
        if (node.layer.animationKeys.count) return YES;
        if (node==view.window) break;
    }
    return NO;
}
static BOOL LMVCardExposed(UIView *view) {
    LMVCardExposureEvidence *e=LMVCardEvidence(view);
    UIWindow *window=view.window;
    if (!LMVCardAttached(view,window)) return NO;
    if (LMVCardExposureInTree(view,window,NO)) {
        e.transferred=NO; e.exposed=YES; e.probeArmed=NO; e.probeUntil=0;
        return YES;
    }
    if (e.transferred) return NO;
    // A withdrawn hidden window's lingering snapshot must not keep playing.
    // Hidden MODEL state is compatible only with an exposed presentation tree
    // during motion in this already attached window, not an unconditional bypass.
    if (window.hidden && (!e.exposed || !LMVCardPresentationMotion(view))) return NO;
    BOOL exposed=LMVCardExposureInTree(view,window,YES);
    if (exposed) e.exposed=YES;
    return exposed;
}
static BOOL LMVCardCanProbe(UIView *view) {
    LMVCardExposureEvidence *e=LMVCardEvidence(view);
    UIWindow *window=view.window;
    if (!LMVCardAttached(view,window) || e.transferred || window.hidden) return NO;
    BOOL moving=LMVCardPresentationMotion(view);
    if (!moving) { e.probeArmed=NO; e.probeUntil=0; return NO; }
    // A cold link can observe the next committed CA sample, but never starts a
    // decoder until actual exposure is proven. One bounded probe per animation.
    if (!e.probeArmed) { e.probeArmed=YES; e.probeUntil=CACurrentMediaTime()+0.6; }
    return CACurrentMediaTime()<e.probeUntil;
}
static BOOL LMVCardStateAttached(UIView *owner, LMVVideoState *state) {
    UIView *anchor=state.anchor, *host=state.host;
    UIWindow *window=owner.window;
    return state && LMVCardAttached(owner,window) && LMVCardAttached(anchor,window) &&
        LMVCardAttached(host,window) && [anchor isDescendantOfView:owner] &&
        (host==anchor || host==anchor.superview) && state.overlay.superview==host &&
        state.overlay.window==window && state.layer.superlayer==state.overlay.layer;
}
static BOOL LMVCardStateVisible(UIView *owner, LMVVideoState *state, NSString *target) {
    return LMVEnabled[target].boolValue && LMVPaths[target].length &&
        [state.path isEqualToString:LMVPaths[target]] && LMVCardStateAttached(owner,state) &&
        LMVVisible(owner) && LMVVisible(state.anchor) && LMVVisible(state.overlay);
}
static BOOL LMVCardColdProbe(UIView *owner, NSDictionary *states) {
    // Only a selected Message attached to its real card owner can bootstrap a
    // presentation-only transition. Options/Clear keep their existing discovery.
    LMVVideoState *state=states[@"Message"];
    return LMVMessageCell(owner) && LMVEnabled[@"Message"].boolValue &&
        LMVPaths[@"Message"].length && [state.path isEqualToString:LMVPaths[@"Message"]] &&
        LMVNotificationCenterSurface(owner) && LMVCardStateAttached(owner,state) &&
        LMVCardCanProbe(owner);
}
