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
static BOOL LMVCardLayerAttached(CALayer *layer,CALayer *root) {
    NSUInteger depth=0;
    for(CALayer *node=layer;node && ++depth<=48;node=node.superlayer)if(node==root)return YES;
    return NO;
}
static BOOL LMVCardAttached(UIView *view, UIWindow *window) {
    if (!view || !window || view.window!=window || !LMVCardLayerAttached(view.layer,window.layer)) return NO;
    NSUInteger depth=0;
    // UIKit can insert transform/material containers between two UIView backing
    // layers. Equality to superview.layer was never a UIKit attachment contract.
    // Verify BOTH the attached UIView owner and the actual same-window CA ancestry.
    for (UIView *node=view; node && ++depth<=32; node=node.superview) {
        if (node.window!=window) return NO;
        if (node==window) return YES;
        if (!node.superview) return NO;
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
    CALayer *space=presentation ? view.layer.presentationLayer : view.layer;
    if (!space || (presentation && space.modelLayer!=view.layer)) return NO;
    CALayer *root=window.layer;
    if(presentation) {
        // Stay within ONE actual snapshot tree. Repeated presentationLayer calls
        // need not return pointer-identical parent snapshots during UIKit updates.
        root=nil;NSUInteger depth=0;
        for(CALayer *node=space;node && ++depth<=48;node=node.superlayer)
            if(node.modelLayer==window.layer){root=node;break;}
    }
    if(!root || !LMVCardLayerAttached(space,root))return NO;
    CGRect rect=[space convertRect:space.bounds toLayer:root];
    if (!LMVCardRectValid(rect)) return NO;
    CGFloat alpha=1;NSUInteger depth=0;
    for (CALayer *layer=space; layer && ++depth<=48; layer=layer.superlayer) {
        CALayer *model=presentation?layer.modelLayer:layer;
        UIView *backing=nil;
        for(UIView *node=view;node;node=node.superview) {
            if(node.layer==model){backing=node;break;}
            if(node==window)break;
        }
        if(layer.hidden || (!presentation && backing.hidden))return NO;
        alpha*=backing?LMVCardExposureAlpha(backing,layer,presentation):layer.opacity;
        if (!isfinite(alpha) || alpha<0.01) return NO;
        if (layer.masksToBounds || backing.clipsToBounds || layer==root) {
            rect=CGRectIntersection(rect,[layer convertRect:layer.bounds toLayer:root]);
            if (!LMVCardRectValid(rect)) return NO;
        }
        if(layer==root)break;
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
    BOOL modelExposed=LMVCardExposureInTree(view,window,NO);
    if(e.transferred && !modelExposed)return NO;
    if(modelExposed)e.transferred=NO;
    // The actually committed child snapshot, when present, is the authority:
    // model bounds may already be on screen before entrance, or remain there
    // while the panel is visibly being withdrawn. Do not OR those two states.
    CALayer *sample=view.layer.presentationLayer;BOOL hasSample=NO;NSUInteger depth=0;
    if(sample && sample.modelLayer==view.layer)for(CALayer *node=sample;node && ++depth<=48;node=node.superlayer)
        if(node.modelLayer==window.layer){hasSample=YES;break;}
    BOOL exposed;
    if(hasSample) {
        if(window.hidden && !LMVCardPresentationMotion(view))return NO;
        exposed=LMVCardExposureInTree(view,window,YES);
    } else exposed=modelExposed;
    if(exposed){e.exposed=YES;e.probeArmed=NO;e.probeUntil=0;}
    return exposed;
}
static BOOL LMVCardCanProbe(UIView *view) {
    LMVCardExposureEvidence *e=LMVCardEvidence(view);
    UIWindow *window=view.window;
    if (!LMVCardAttached(view,window) || e.transferred) return NO;
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
        LMVNotificationCenterSurface(owner) && LMVVisible(state.overlay);
}
static BOOL LMVCardColdProbe(UIView *owner, NSDictionary *states) {
    if(!LMVNotificationCenterSurface(owner))return NO;
    for(NSString *target in @[@"Message",@"Options",@"Clear"]) {
        LMVVideoState *state=states[target];
        if(LMVEnabled[target].boolValue && LMVPaths[target].length &&
           [state.path isEqualToString:LMVPaths[target]] && LMVCardStateAttached(owner,state) &&
           LMVCardCanProbe(state.overlay))return YES;
    }
    return NO;
}
