#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import <notify.h>
#import <string.h>
#define LMVLockVideoLog(message) LMVDiagnostic(message)
#import "LMVLockVideoPlayback.h"

static BOOL LMVLockVideoRectValid(CGRect rect) {
    return !CGRectIsNull(rect) && !CGRectIsInfinite(rect) && !CGRectIsEmpty(rect) &&
        isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width) && isfinite(rect.size.height);
}
static BOOL LMVLockVideoClass(id object,NSString *name) {
    Class cls=NSClassFromString(name);return cls && [object isKindOfClass:cls];
}
static UIView *LMVLockVideoObjectView(id object,NSString *name,UIView *root) {
    SEL selector=NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature=[object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments!=2 || strcmp(signature.methodReturnType,@encode(id))) return nil;
    id result=((id(*)(id,SEL))objc_msgSend)(object,selector);
    return [result isKindOfClass:UIView.class] && result!=root && [result isDescendantOfView:root]?result:nil;
}
static UIView *LMVLockVideoFindCover(UIView *view,NSUInteger depth,NSUInteger *budget) {
    if (!view || !*budget || depth>10) return nil;--*budget;
    if (LMVLockVideoClass(view,@"CSCoverSheetView")) return view;
    for (UIView *child in view.subviews) {UIView *cover=LMVLockVideoFindCover(child,depth+1,budget);if(cover)return cover;}
    return nil;
}
static UIView *LMVLockVideoContent(UIView *root) {
    NSUInteger budget=128;UIView *cover=LMVLockVideoFindCover(root,0,&budget);
    if (!cover) return nil;
    for (NSString *name in @[@"slideableContentView",@"contentView"]) {
        UIView *content=LMVLockVideoObjectView(cover,name,cover);if(content)return content;
    }
    // A persistent controller/window is not an exposed LockScreen. Unknown
    // slideable content is never replaced with a full-window fallback.
    return nil;
}
static BOOL LMVLockVideoForeground(UIView *view) {
    if ([view isKindOfClass:UIControl.class] || [view isKindOfClass:UILabel.class] || [view isKindOfClass:UITextView.class] ||
        [view isKindOfClass:UIScrollView.class] || view.isAccessibilityElement) return YES;
    NSString *name=NSStringFromClass(view.class);
    for (NSString *word in @[@"Clock",@"Date",@"Notification",@"ListView",@"Widget",@"Complication",@"Button",@"Passcode",@"Authentication"])
        if ([name containsString:word]) return YES;
    return NO;
}
static BOOL LMVLockVideoBackground(UIView *view,NSUInteger depth,NSUInteger *budget) {
    if (!view || !*budget || depth>8 || LMVLockVideoForeground(view)) return NO;--*budget;
    NSString *name=NSStringFromClass(view.class);
    BOOL known=LMVLockVideoClass(view,@"SBUIBackgroundView") || LMVLockVideoClass(view,@"SBWallpaperEffectView") ||
        [name containsString:@"Background"] || [name containsString:@"Wallpaper"] ||
        [name containsString:@"MaterialView"] || [name containsString:@"VisualEffect"] || [name containsString:@"Backdrop"];
    if (!known) return NO;
    for (UIView *child in view.subviews) {
        if (LMVLockVideoForeground(child)) return NO;
        // Unknown container children are allowed only when bounded descendants
        // contain no foreground; the branch is observed but never suppressed.
        NSMutableArray *pending=[NSMutableArray arrayWithObject:child];NSUInteger left=64;
        while (pending.count && left) {--left;UIView *node=pending.lastObject;[pending removeLastObject];
            if (LMVLockVideoForeground(node)) return NO;[pending addObjectsFromArray:node.subviews];}
        if (pending.count) return NO;
    }
    return YES;
}
// Match the observed pattern: own UIView directly in CoverSheet's content,
// above the recognized background/dimming branch and below other foreground.
static UIView *LMVLockVideoBackgroundAnchor(UIView *container,UIView *own) {
    UIView *anchor=nil;BOOL foregroundPassed=NO;NSUInteger budget=64;
    for (UIView *child in container.subviews) {
        if (child==own) continue;
        if (LMVLockVideoBackground(child,0,&budget)) {
            if (foregroundPassed) return nil;
            anchor=child;
        } else if (!child.hidden && child.alpha>.01) foregroundPassed=YES;
    }
    return anchor;
}
static CGRect LMVVideoWindowViewport(UIWindow *window) {
    if (!window || !window.screen) return CGRectZero;
    // Reachability translates the window while its bounds can stay full size.
    // Convert the physical screen into window coordinates instead of assuming
    // every point in window.bounds is currently on screen.
    CGRect screen=[window convertRect:window.screen.bounds fromCoordinateSpace:window.screen.coordinateSpace];
    CGRect visible=CGRectIntersection(screen,window.bounds);
    return LMVLockVideoRectValid(visible)?visible:CGRectZero;
}
static CGRect LMVLockVideoRectInTree(UIView *content,UIWindow *window,CALayer *space,CALayer *root) {
    if (!content || !window || !space || !root || !LMVLockVideoRectValid(content.bounds)) return CGRectZero;
    // 0.0.84 fix: window/ancestor `hidden` no longer vetoes the geometry.
    // Notification Center 降半屏 keeps SBCoverSheetWindow.hidden=1 (30 of 40
    // observed layouts) while the window still occupies the full screen, and
    // Control Center does the same with SBControlCenterWindow. The old
    // short-circuit collapsed this rect to zero, so the video layer was skipped
    // and the background disappeared exactly when the panel stopped being
    // full-screen. The window viewport is the geometric authority instead: it
    // returns zero only when the window is genuinely off-screen (Reachability).
    if (!LMVLockVideoRectValid(LMVVideoWindowViewport(window))) return CGRectZero;
    CGRect rect=[space convertRect:space.bounds toLayer:root];
    if (!LMVLockVideoRectValid(rect)) return CGRectZero;
    // Every ancestor clipping boundary is measured in the same model/presentation tree.
    for (UIView *node=content.superview;node && node!=window;node=node.superview) if (node.clipsToBounds) {
        CALayer *layer=root==window.layer?node.layer:node.layer.presentationLayer;
        if (!layer) return CGRectZero;
        rect=CGRectIntersection(rect,[layer convertRect:layer.bounds toLayer:root]);
    }
    rect=CGRectIntersection(rect,root.bounds);
    rect=CGRectIntersection(rect,LMVVideoWindowViewport(window));
    return LMVLockVideoRectValid(rect) && rect.size.width>1 && rect.size.height>1?rect:CGRectZero;
}
static CGRect LMVLockVideoVisibleRect(UIView *content,UIWindow *window) {
    CALayer *space=content.layer.presentationLayer,*root=window.layer.presentationLayer;
    if (!space || !root) {space=content.layer;root=window.layer;}
    return LMVLockVideoRectInTree(content,window,space,root);
}
// 0.0.98: the slideable content paints the panel's background itself -- its child
// list leads with SBDashBoardWallpaperEffectView / UIVisualEffectView -- and those
// siblings sit ABOVE controller.view in z order. A surface parented in
// controller.view therefore cannot cover them: that is the ORIGINAL wallpaper still
// showing while the panel is pulled down (gapTop is 0.0 in every device sample, so
// it is paint order, not geometry).
static BOOL LMVLockVideoBackgroundPaint(UIView *view) {
    NSString *name=view?NSStringFromClass(view.class):@"";
    return [name containsString:@"Background"] || [name containsString:@"Wallpaper"] ||
           [name containsString:@"Material"] || [name containsString:@"Backdrop"] ||
           [name containsString:@"VisualEffect"] || [name containsString:@"Effect"];
}
// The last member of the LEADING run of background-paint children: the surface goes
// directly above it, i.e. above the wallpaper paint and still below the clock and
// the notification list. nil when the content has no such run, in which case the
// previous controller.view placement is kept unchanged.
static UIView *LMVLockVideoContentBackdrop(UIView *content) {
    UIView *last=nil;
    for (UIView *child in content.subviews) {
        // Our inserted host must not terminate the leading background run on the
        // next layout; otherwise backdrop/host ordering oscillates every tick.
        if ([NSStringFromClass(child.class) isEqualToString:@"LMVLockVideoHost"]) continue;
        if (!LMVLockVideoBackgroundPaint(child)) break;
        last=child;
    }
    return last;
}
static UIView *LMVLockVideoContainer(UIView *root,UIView *content,UIView *own,UIView **anchor) {
    // Prefer the content itself when it owns the panel's background paint.
    if (content && content!=root && [content isDescendantOfView:root]) {
        UIView *backdrop=LMVLockVideoContentBackdrop(content);
        if (backdrop) {if (anchor) *anchor=backdrop;return content;}
    }
    // The reference places its own video UIView in controller.view. Preserve
    // every system sibling's order; use nested content only if root has no
    // separated background branch. A known sliding content is always required.
    for (UIView *candidate in @[root,content]) {
        UIView *background=LMVLockVideoBackgroundAnchor(candidate,own);
        if (background && (candidate==root || [candidate isDescendantOfView:root])) {
            if (anchor) *anchor=background;return candidate;
        }
    }
    if (anchor) *anchor=nil;return nil;
}
// Only owned paint may bypass a non-clipping root's layout inset. Physical
// viewport/ancestor clipping remain intersections; the observed panel bottom
// still bounds the .100 half-screen path. No cached/full-root exposure is used.
static CGRect LMVLockVideoOwnedPaintRect(CGRect containerRect,CGRect exposure,CGRect panel,CGRect viewport) {
    if (!LMVLockVideoRectValid(containerRect) || !LMVLockVideoRectValid(exposure)) return CGRectZero;
    CGFloat bottom=MIN(CGRectGetMaxY(exposure),CGRectGetMaxY(containerRect));
    exposure.size.height=MAX(0,bottom-CGRectGetMinY(exposure));
    CGRect owned=containerRect;
    // A rectangular containing/contiguous band is safe; an L-shaped bounding
    // box would invent paint beside the panel and must not be admitted.
    if (LMVLockVideoRectValid(exposure) && (CGRectContainsRect(exposure,containerRect) ||
        (fabs(CGRectGetMinX(exposure)-CGRectGetMinX(containerRect))<.01 &&
         fabs(CGRectGetMaxX(exposure)-CGRectGetMaxX(containerRect))<.01 && !CGRectIsEmpty(CGRectIntersection(exposure,containerRect)))))
        owned=CGRectUnion(containerRect,exposure);
    if (LMVLockVideoRectValid(panel)) owned.size.height=MAX(0,MIN(CGRectGetMaxY(owned),CGRectGetMaxY(panel))-CGRectGetMinY(owned));
    owned=CGRectIntersection(owned,viewport);
    return LMVLockVideoRectValid(owned)?owned:CGRectZero;
}
// Final mask stage, not the earlier exposure union. The host mask NEVER
// shrinks below the attached container's own bounds, whatever the system is
// doing to the background paint this frame: pulling Notification Center down
// hides, re-orders and re-lays-out that paint (and the derived rect with it),
// and gating this union on that momentary state opened a hole in the mask
// that showed the ORIGINAL wallpaper behind the host -- the top strip. The
// 0.1.3 reference closes it with a plain container-bounds union, and it must
// hold on the ROOT-owned fallback too: this device's slideable content owns
// no leading background run, so the container is controller.view and the old
// root path still required a currently visible backdrop (104/105 leaked).
// Physical still bounds the result -- window viewport, real ancestor clipping
// and the panel bottom -- so a withdrawn panel never paints the uncovered
// application below, and offscreen stays fail-closed.
static CGRect LMVLockVideoFinalMask(CGRect local,CGRect container,CGRect physical) {
    if(!LMVLockVideoRectValid(container) || !LMVLockVideoRectValid(physical))return CGRectZero;
    CGRect mask=LMVLockVideoRectValid(local)?CGRectUnion(local,container):container;
    mask=CGRectIntersection(mask,physical);
    return LMVLockVideoRectValid(mask)?mask:CGRectZero;
}
static CGRect LMVLockVideoGeometry(UIView *content,UIView *container,UIView *controllerRoot,UIView *backdrop,UIWindow *window,CGRect *hostFrame) {
    if (hostFrame) *hostFrame=CGRectZero;
    if (!content || !container || !controllerRoot || !window || ![content isDescendantOfView:controllerRoot]) return CGRectZero;
    CALayer *space=container.layer.presentationLayer,*contentSpace=content.layer.presentationLayer;
    CALayer *root=window.layer.presentationLayer,*panel=controllerRoot.layer.presentationLayer;
    BOOL ownsBackdrop=container==content && backdrop && backdrop.superview==content && backdrop==LMVLockVideoContentBackdrop(content);
    CALayer *paint=ownsBackdrop?backdrop.layer.presentationLayer:nil;
    BOOL presented=space && contentSpace && root && panel && (!ownsBackdrop || paint);
    if (!presented) {space=container.layer;contentSpace=content.layer;root=window.layer;panel=controllerRoot.layer;paint=ownsBackdrop?backdrop.layer:nil;}
    CGRect viewport=LMVVideoWindowViewport(window);
    CGRect panelRect=LMVLockVideoRectInTree(controllerRoot,window,panel,root);
    CGRect containerRect=LMVLockVideoRectInTree(content,window,contentSpace,root);
    CGRect admitted=CGRectIntersection(containerRect,CGRectIntersection(viewport,panelRect));
    // .102: union in CONTENT-OWNED paint space, never at a real clipping
    // boundary or for the root-owned wallpaper fallback.
    // 0.0.105: a content-owned backdrop is confirmed by IDENTITY here, not by
    // its momentary hidden/alpha. Pulling down Notification Center hides or
    // zero-alphas that backdrop while the same attached slideable content still
    // paints the panel; requiring current visibility dropped this exposure union
    // in exactly that transient, leaving the band above the (inset) slideable
    // content -- the top strip -- showing the original wallpaper.
    if (ownsBackdrop && !content.hidden && content.alpha>.01) {
        CGRect exposure=LMVLockVideoRectInTree(backdrop,window,paint,root);
        if (LMVLockVideoRectValid(CGRectIntersection(containerRect,exposure))) {
            CGRect owned=LMVLockVideoOwnedPaintRect(containerRect,exposure,panelRect,viewport);
            if (LMVLockVideoRectValid(owned)) admitted=owned;
        }
    }
    NSUInteger backdropBudget=64;
    BOOL rootBackdrop=!ownsBackdrop && backdrop && backdrop.superview==container &&
        LMVLockVideoBackground(backdrop,0,&backdropBudget);
    // 0.0.105: the ROOT-owned fallback still requires a currently visible
    // backdrop; a CONTENT-owned backdrop (identity check, not visibility) does
    // not. Gating the final union on the backdrop's momentary hidden/alpha made
    // the union vanish during the pull-down transient, which is exactly where
    // the top strip leaked the original wallpaper (104 shipped that way).
    BOOL backdropOn=backdrop && !backdrop.hidden && backdrop.alpha>.01;
    BOOL owned=(ownsBackdrop || (rootBackdrop && backdropOn)) && !content.hidden && content.alpha>.01 &&
        LMVLockVideoRectValid(containerRect);
    if(!LMVLockVideoRectValid(admitted) && !owned)return CGRectZero;
    // Union is applied to the FINAL host mask, not just the earlier backdrop
    // exposure calculation, and it is no longer gated on the backdrop's
    // momentary visibility: a transient empty/inset derived region falls back
    // to the still-attached container bounds. Physical offscreen still rejects.
    CGRect local=LMVLockVideoRectValid(admitted)?[space convertRect:admitted fromLayer:root]:CGRectZero;
    if (!LMVLockVideoRectValid(space.bounds)) return CGRectZero;
    // This is the final mask operation discussed in the supplied patch notes.
    // The container's own currently exposed bounds may extend farther than the
    // calculated local mask. The mask keeps at least that container paint
    // instead of intersecting it away; physical (viewport, real ancestor
    // clips, panel bottom) is what bounds it, so this grants no whole-window
    // fallback for a withdrawn or partial panel.
    CGRect physical=LMVVideoWindowViewport(window);
    for(UIView *node=container;node && node!=window;node=node.superview) {
        if(node.clipsToBounds || node.layer.masksToBounds) {
            CALayer *clip=presented?node.layer.presentationLayer:node.layer;
            if(!clip){physical=CGRectZero;break;}
            physical=CGRectIntersection(physical,[clip convertRect:clip.bounds toLayer:root]);
        }
    }
    // Retain the working half-screen/panel bottom. Only the top inset can be
    // closed; a withdrawn panel must not paint the uncovered application below.
    if(LMVLockVideoRectValid(panelRect) && LMVLockVideoRectValid(physical))
        physical.size.height=MAX(0,MIN(CGRectGetMaxY(physical),CGRectGetMaxY(panelRect))-CGRectGetMinY(physical));
    CGRect physicalLocal=LMVLockVideoRectValid(physical)?[space convertRect:physical fromLayer:root]:CGRectZero;
    if(rootBackdrop && LMVLockVideoRectValid(containerRect) && LMVLockVideoRectValid(physicalLocal)) {
        CGRect shown=[space convertRect:containerRect fromLayer:root];
        physicalLocal.size.height=MAX(0,MIN(CGRectGetMaxY(physicalLocal),CGRectGetMaxY(shown))-CGRectGetMinY(physicalLocal));
    }
    CGRect mask=LMVLockVideoFinalMask(local,space.bounds,physicalLocal);
    if(!LMVLockVideoRectValid(mask))return CGRectZero;
    CGRect frame=CGRectUnion(space.bounds,mask);
    if(hostFrame)*hostFrame=frame;
    return CGRectOffset(mask,-frame.origin.x,-frame.origin.y);
}
static inline CGRect LMVLockVideoClip(UIView *content,UIView *container,UIWindow *window) {
    UIView *root=window.rootViewController.viewIfLoaded ?: container;
    UIView *backdrop=container==content?LMVLockVideoContentBackdrop(content):LMVLockVideoBackgroundAnchor(container,nil);
    return LMVLockVideoGeometry(content,container,root,backdrop,window,NULL);
}

// .104 changes the final owned-container mask union as observed in the user
// supplied0.1.3 binary, without new video/decoder/window. The .103 bounded paint
// checks remain for separate z-order/system-redraw issues.
static NSString *LMVLockVideoRectText(CGRect rect) {
    return LMVLockVideoRectValid(rect)?[NSString stringWithFormat:@"{{%.0f,%.0f},{%.0f,%.0f}}",rect.origin.x,rect.origin.y,rect.size.width,rect.size.height]:@"(none)";
}
static NSString *LMVLockVideoPerf(const char *channel,CFTimeInterval seconds) {
    static NSUInteger calls=0,slow=0;static CFTimeInterval maxSeconds=0,windowStart=0;
    CFTimeInterval now=CACurrentMediaTime();
    if (windowStart<=0) windowStart=now;
    calls++;if (seconds>maxSeconds)maxSeconds=seconds;if (seconds>0.004)slow++;
    if (now-windowStart<2.0) return nil;
    NSString *report=[NSString stringWithFormat:@"perf %s calls=%lu max=%.2fms slow=%lu",
        channel,(unsigned long)calls,maxSeconds*1000.0,(unsigned long)slow];
    calls=0;slow=0;maxSeconds=0;windowStart=now;
    return report;
}
// 0.0.99: views the panel paints ABOVE our surface that repaint the ORIGINAL
// wallpaper. Device hierarchy (SBCoverSheetWindow -> ... -> CSCoverSheetView ->
// slideable content) shows two of them sitting on top of the content's background
// run: PBUIPosterFloatingLayerReplica (a live portal of the wallpaper's floating
// layer) and NCMaterialDisplayingCaptureOnlyViewControllerView (the Notification
// Center's captured-wallpaper backdrop). Covering them geometrically is impossible
// from below, so they are LEASED: hidden while our video is on screen and restored
// exactly as found afterwards. Nothing is detached, so the system keeps owning them.
@interface LMVLockVideoPaintEntry : NSObject
@property(nonatomic,weak) UIView *view,*parent,*scope;
@property(nonatomic) BOOL baselineHidden,ownsHidden;
@end
@implementation LMVLockVideoPaintEntry @end
@interface LMVLockVideoPaintLease : NSObject
@property(nonatomic,weak) UIView *container;
@property(nonatomic,copy) NSArray<LMVLockVideoPaintEntry *> *entries;
@end
@implementation LMVLockVideoPaintLease @end
static void LMVLockVideoRestorePaint(LMVLockVideoPaintEntry *entry,UIView *container) {
    UIView *view=entry.view;
    // A reparented/reused system view is no longer ours to restore. Do not undo a
    // newer visible state either; restore only the hidden value this lease owns.
    UIView *scope=entry.scope ?: container;
    if (entry.ownsHidden && view.hidden && view.superview==entry.parent && [view isDescendantOfView:scope])
        view.hidden=entry.baselineHidden;
}
static BOOL LMVLockVideoPaintAbove(UIView *view,UIView *container,UIView *host) {
    UIView *branch=view;
    while (branch && branch.superview!=container) branch=branch.superview;
    if (!branch || branch==host || host.superview!=container) return NO;
    NSUInteger own=[container.subviews indexOfObjectIdenticalTo:host],index=[container.subviews indexOfObjectIdenticalTo:branch];
    return own!=NSNotFound && index!=NSNotFound && index>own;
}
static BOOL LMVLockVideoRepaintPure(UIView *view) {
    if(!view)return NO;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:view];NSUInteger budget=96;
    while(pending.count && budget--) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        if([node isKindOfClass:UIControl.class] || [node isKindOfClass:UILabel.class] ||
           [node isKindOfClass:UITextView.class] || [node isKindOfClass:UIScrollView.class] ||
           node.isAccessibilityElement || node.gestureRecognizers.count || node.subviews.count>24)return NO;
        for(CALayer *layer in node.layer.sublayers) {
            BOOL backing=NO;for(UIView *child in node.subviews)if(child.layer==layer){backing=YES;break;}
            if(backing)continue;
            if([layer isKindOfClass:CATextLayer.class] || [layer.name hasPrefix:@"com.minis.lockmessagevideo"] ||
               (layer.delegate && layer.delegate!=node))return NO;
        }
        [pending addObjectsFromArray:node.subviews];
    }
    return !pending.count;
}
static BOOL LMVLockVideoRepaint(UIView *view,UIView *content) {
    if (!view || !content) return NO;
    NSString *name=NSStringFromClass(view.class);
    BOOL named=[name containsString:@"NCMaterialDisplayingCaptureOnly"] ||
               [name containsString:@"PBUIPosterFloatingLayerReplica"] ||
               [name containsString:@"PBUIPosterFloatingView"] ||
               [name containsString:@"PBUISnapshotReplica"] ||
               [name containsString:@"SBDashBoardWallpaper"] ||
               [name containsString:@"WallpaperEffectView"] ||
               [name containsString:@"PBUIWallpaperView"];
    if (!named || !LMVLockVideoRepaintPure(view) || view.window!=content.window) return NO;
    UIWindow *window=content.window;
    CALayer *layer=view.layer.presentationLayer,*space=window.layer.presentationLayer;
    CALayer *owner=content.layer.presentationLayer;
    if(!layer || !space || !owner){layer=view.layer;space=window.layer;owner=content.layer;}
    CGRect frame=LMVLockVideoRectInTree(view,window,layer,space);
    CGRect exposed=LMVLockVideoRectInTree(content,window,owner,space);
    if(!LMVLockVideoRectValid(frame) || !LMVLockVideoRectValid(exposed))return NO;
    // Captured wallpaper can be just a few-point top strip. A 30% minimum
    // height discarded exactly those strips even when their z-order was above
    // the video. Test actual finite on-screen overlap/adjacency instead.
    CGRect adjacent=CGRectInset(exposed,-1,-1);
    return frame.size.width>=exposed.size.width*0.5 && frame.size.height>.5 && CGRectIntersectsRect(frame,adjacent);
}
static void LMVLockVideoCollectRepainters(UIView *node,UIView *content,NSMutableArray *output,NSUInteger *budget) {
    if (!node || !*budget) return;
    --*budget;
    // Evaluate the above sibling ITSELF before traversing its descendants: a
    // direct capture-only backdrop/replica has no children and used to be missed.
    if (LMVLockVideoRepaint(node,content)) {[output addObject:node];return;}
    for (UIView *child in node.subviews) {
        if (!*budget) return;
        LMVLockVideoCollectRepainters(child,content,output,budget);
    }
}
static void LMVLockVideoFindAbovePaint(UIView *container,UIView *host,UIView *content,NSMutableArray *found,NSUInteger *budget) {
    if(!container || host.superview!=container || content.window!=container.window)return;
    UIView *branch=host;UIWindow *window=content.window;NSUInteger depth=0;
    for(UIView *scope=container;scope && depth++<16 && *budget;branch=scope,scope=scope.superview) {
        if(scope.window!=window || ![content isDescendantOfView:scope])break;
        NSUInteger own=[scope.subviews indexOfObjectIdenticalTo:branch];
        if(own==NSNotFound)break;
        for(NSUInteger index=own+1;index<scope.subviews.count && *budget;index++) {
            if(scope.subviews[index]==host)continue;
            // The owned host includes the admitted top paint which can lie just
            // outside content's inset bounds. Compare a capture to that actual
            // video host, not the inset content rectangle that caused the gap.
            LMVLockVideoCollectRepainters(scope.subviews[index],host,found,budget);
        }
        if(scope==window)break;
    }
}
static BOOL LMVLockVideoAboveHostTree(UIView *view,UIView *host,UIView *content) {
    if(!view || !host || view.window!=content.window || host.window!=content.window)return NO;
    UIView *branch=host;NSUInteger depth=0;
    for(UIView *scope=host.superview;scope && depth++<16;branch=scope,scope=scope.superview) {
        if(scope.window!=content.window || ![content isDescendantOfView:scope])return NO;
        if(LMVLockVideoPaintAbove(view,scope,branch))return YES;
        if(scope==content.window)break;
    }
    return NO;
}
@interface LMVLockVideoHost : UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) CAShapeLayer *clipLayer;
@end
@implementation LMVLockVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;self.accessibilityElementsHidden=YES;
        self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.clipsToBounds=YES;
        _clipLayer=[CAShapeLayer layer];self.layer.mask=_clipLayer;
    }
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
@end

@interface LMVLockControllerRecord : NSObject
@property(nonatomic) BOOL lifecycleKnown,visible,wasExposed;
@property(nonatomic,weak) UIView *exposedContent;
@end
@implementation LMVLockControllerRecord @end
static char LMVLockControllerRecordKey;
static NSHashTable<UIViewController *> *LMVLockControllers;
static void LMVLockVideoRefresh(BOOL reload);
static void LMVLockVideoSuspend(void);
@interface LMVLockVideoManager : NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVLockVideoHost *host;
@property(nonatomic,weak) UIViewController *controller;
@property(nonatomic,weak) UIView *content;
@property(nonatomic,strong) CADisplayLink *link;
@property(nonatomic,copy) NSString *path,*revision,*diagnostic,*coverage;
@property(nonatomic) BOOL enabled,updating,screenAllowed;
@property(nonatomic) CFTimeInterval lastRevisionCheck;
// 0.0.97: previous sampled band + its timestamp, used to lead the moving edge
// by exactly one frame of motion (see update()).
@property(nonatomic) CGRect lastClipRect;@property(nonatomic) CFTimeInterval lastClipTime;
@property(nonatomic) BOOL hasLastClip;
@property(nonatomic,strong) LMVLockVideoPaintLease *paintLease;
@property(nonatomic) CFTimeInterval paintLeaseTime;
@property(nonatomic) BOOL paintLeaseDirty;
@property(nonatomic,copy) NSString *paintText;
- (void)refresh:(BOOL)reload;
- (void)update;
- (void)leasePaint:(UIView *)container;
- (void)releasePaint;
- (void)suspend;
@end
static LMVLockVideoManager *LMVLockVideo;

static NSString *LMVLockVideoSelectedPath(void) {
    id stored=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("LockScreenVideo"),kLMVPrefsID);
    if (![stored isKindOfClass:NSString.class]) return nil;
    NSString *relative=(NSString *)stored;
    if (!relative.length || [relative hasPrefix:@"/"] ||
        [relative.pathComponents containsObject:@".."] || [relative.pathComponents containsObject:@"."]) return nil;
    NSString *path=[[LMVDirectory stringByAppendingPathComponent:relative] stringByStandardizingPath];
    if (![path hasPrefix:[LMVDirectory stringByAppendingString:@"/"]]) return nil;
    NSString *resolved=path.stringByResolvingSymlinksInPath;
    return [resolved hasPrefix:[LMVDirectory stringByAppendingString:@"/"]]?path:nil;
}
static BOOL LMVLockVideoScreenAllowed(void) {
    uint64_t blank=1;
    return LMVBlankToken>=0 && notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK && !blank;
}
@implementation LMVLockVideoManager
- (instancetype)init {
    if ((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_host=[[LMVLockVideoHost alloc] initWithFrame:CGRectZero];
        _host.playback=_playback;_playback.renderLayer.backgroundColor=UIColor.blackColor.CGColor;
        [_host.layer addSublayer:_playback.renderLayer];
        __weak typeof(self) weakSelf=self;
        _playback.didChange=^{
            LMVLockVideoManager *live=weakSelf;if(!live || !LMVDiagnosticsEnabled.load())return;
            NSString *status=[NSString stringWithFormat:@"lock-video phase loading=%d player=%ld layer-ready=%d poster=%d active=%d error=%ld",
                live.playback.loading,(long)live.playback.player.status,live.playback.playerLayer.readyForDisplay,
                live.playback.posterLayer.contents!=nil,live.playback.wantsPlayback,(long)live.playback.error.code];
            if (![status isEqualToString:live.diagnostic]) {live.diagnostic=status;LMVLockVideoLog(status);}
        };
    }
    return self;
}
- (void)refresh:(BOOL)reload {
    if (reload) {
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("LockScreenBackgroundEnabled"),kLMVPrefsID);
        self.enabled=[enabled respondsToSelector:@selector(boolValue)] && [enabled boolValue];
        self.path=self.enabled?LMVLockVideoSelectedPath():nil;
        self.revision=LMVLockVideoRevision(self.path);self.lastRevisionCheck=CACurrentMediaTime();
        [self.playback selectPath:self.path revision:self.revision];
    }
    self.screenAllowed=LMVLockVideoScreenAllowed();[self update];
}
- (void)suspend {
    [self releasePaint];
    [self.playback setVisible:NO];self.host.hidden=YES;
    [self.link invalidate];self.link=nil;
}
- (void)tick:(CADisplayLink *)link {
    self.screenAllowed=LMVLockVideoScreenAllowed();
    if (CACurrentMediaTime()-self.lastRevisionCheck>=1) {
        self.lastRevisionCheck=CACurrentMediaTime();NSString *revision=LMVLockVideoRevision(self.path);
        if ((revision || self.revision) && ![revision isEqualToString:self.revision]) {
            self.revision=revision;[self.playback selectPath:self.path revision:revision];
        }
    }
    [self update];
}
- (void)releasePaint {
    for (LMVLockVideoPaintEntry *entry in self.paintLease.entries) LMVLockVideoRestorePaint(entry,self.paintLease.container);
    self.paintLease=nil;self.paintText=nil;self.paintLeaseTime=0;
}
- (void)leasePaint:(UIView *)container {
    CFTimeInterval now=CACurrentMediaTime();BOOL diagnostics=LMVDiagnosticsEnabled.load();
    if (self.paintLease && self.paintLease.container!=container) [self releasePaint];
    NSMutableArray *entries=[NSMutableArray arrayWithArray:self.paintLease.entries ?: @[]];
    // Keep valid entries continuously hidden, even when new views are discovered.
    // Staleness is exact parent/container/above-host ownership, not just attached.
    BOOL stale=NO,audit=self.paintLeaseDirty || now-self.paintLeaseTime>=.5;
    for (LMVLockVideoPaintEntry *entry in entries.copy) {
        UIView *view=entry.view;
        if (!view || view.superview!=entry.parent || view.window!=self.content.window ||
            !LMVLockVideoAboveHostTree(view,self.host,self.content) || (audit && !LMVLockVideoRepaintPure(view))) {
            LMVLockVideoRestorePaint(entry,container);[entries removeObjectIdenticalTo:entry];stale=YES;
        }
    }
    BOOL scan=!self.paintLease || self.paintLeaseDirty || stale || now-self.paintLeaseTime>=.5;
    self.paintLeaseDirty=NO;
    if (scan) {
        NSMutableArray *found=[NSMutableArray new];NSUInteger budget=240;
        LMVLockVideoFindAbovePaint(container,self.host,self.content,found,&budget);
        self.paintLeaseTime=now;
        for (UIView *view in found) {
            BOOL known=NO;for (LMVLockVideoPaintEntry *entry in entries) if (entry.view==view) {known=YES;break;}
            if (known) continue;
            LMVLockVideoPaintEntry *entry=[LMVLockVideoPaintEntry new];entry.view=view;entry.parent=view.superview;entry.scope=self.content.window;
            entry.baselineHidden=view.hidden;entry.ownsHidden=!view.hidden;[entries addObject:entry];
        }
    }
    if (!self.paintLease) {self.paintLease=[LMVLockVideoPaintLease new];self.paintLease.container=container;}
    if (scan) self.paintLease.entries=entries;
    for (LMVLockVideoPaintEntry *entry in self.paintLease.entries) if (entry.ownsHidden && !entry.view.hidden) entry.view.hidden=YES;
    if (diagnostics && (scan || !self.paintText)) {
        NSMutableString *text=[NSMutableString string];
        for (LMVLockVideoPaintEntry *entry in self.paintLease.entries) if (entry.view) [text appendFormat:@"%@,",NSStringFromClass(entry.view.class)];
        self.paintText=text;
    } else if (!diagnostics) self.paintText=nil;
}
- (void)update {
    if (self.updating) return;self.updating=YES;
    BOOL diagnostics=LMVDiagnosticsEnabled.load();
    CFTimeInterval coverPerf0=diagnostics?CACurrentMediaTime():0;
    UIViewController *best=nil;UIView *content=nil;CGFloat area=0;
    // 0.0.106: a lifecycle-visible CoverSheet keeps the decoder running even
    // when this frame's derived geometry momentarily fails (see setVisible:).
    BOOL coverPresented=NO;
    if (self.enabled && self.path.length && self.revision.length && self.screenAllowed) {
        for (UIViewController *candidate in LMVLockControllers.allObjects) {
            UIView *root=candidate.viewIfLoaded;UIWindow *window=root.window;
            if (!root || !LMVLockVideoClass(window,@"SBCoverSheetWindow") || window.screen!=UIScreen.mainScreen) continue;
            LMVLockControllerRecord *record=objc_getAssociatedObject(candidate,&LMVLockControllerRecordKey);
            if (!record) {record=[LMVLockControllerRecord new];objc_setAssociatedObject(candidate,&LMVLockControllerRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
            UIView *sliding=LMVLockVideoContent(root);CGRect contentRect=LMVLockVideoVisibleRect(sliding,window);
            CGRect viewport=LMVVideoWindowViewport(window),panel=LMVLockVideoVisibleRect(root,window);
            // 0.0.106: a genuinely presented CoverSheet -- lifecycle-visible, with
            // a live slideable content and panel -- keeps the decoder running even
            // when this frame's derived exposure/clip momentarily fails (the NC
            // pull-down hides and re-lays-out the system background paint). A
            // degenerate content/panel (zero-size, withdrawn, no content at all)
            // is NOT presented and still pauses.
            if (record.lifecycleKnown && record.visible && sliding &&
                LMVLockVideoRectValid(contentRect) && LMVLockVideoRectValid(panel)) coverPresented=YES;
            CGRect exposed=CGRectIntersection(contentRect,panel);
            UIView *backdrop=LMVLockVideoContentBackdrop(sliding);
            BOOL ownedActive=sliding && !sliding.hidden && sliding.alpha>.01 && backdrop && !backdrop.hidden && backdrop.alpha>.01 &&
                LMVLockVideoRectValid(CGRectIntersection(contentRect,LMVLockVideoVisibleRect(backdrop,window)));
            // A non-clipping root can momentarily have empty layout bounds while
            // this SAME attached owner/background still occupies the screen.
            // Never cache its previous mask or grant this exception to a new,
            // detached, unknown, withdrawn or genuinely off-screen content.
            BOOL sameOwner=record.wasExposed && record.exposedContent==sliding && self.content==sliding &&
                self.controller==candidate && self.host.superview==sliding;
            if (ownedActive && (LMVLockVideoRectValid(exposed) || (sameOwner && !root.clipsToBounds)))
                exposed=LMVLockVideoOwnedPaintRect(contentRect,LMVLockVideoVisibleRect(backdrop,window),panel,viewport);
            BOOL trueExposure=sliding && !sliding.hidden && sliding.alpha>.01 && LMVLockVideoRectValid(exposed);
            if (!trueExposure || record.exposedContent!=sliding) {record.wasExposed=NO;record.exposedContent=nil;}
            if (!trueExposure) continue;
            CGFloat size=exposed.size.width*exposed.size.height;
            // Both Reachability window translation and an unchanged full-size
            // window with a shortened/translated panel are credible half-screen
            // geometry. Narrow slivers and lifecycle callbacks alone are not.
            CGFloat height=window.bounds.size.height;
            BOOL half=height>1 && exposed.size.width>=viewport.size.width*.90 && exposed.size.height>=height*.15 &&
                (viewport.size.height<=height*.85 || (LMVLockVideoRectValid(panel) && panel.size.height<=height*.85) || exposed.size.height<=height*.85);
            if (record.lifecycleKnown && !record.visible && !(record.wasExposed && record.exposedContent==sliding && half)) continue;
            record.wasExposed=YES;record.exposedContent=sliding;
            if (size>area) {best=candidate;content=sliding;area=size;}
        }
    }
    UIView *anchor=nil;UIView *container=content?LMVLockVideoContainer(best.viewIfLoaded,content,self.host,&anchor):nil;
    BOOL visible=best && content && container && anchor;
    if (visible) {
        NSArray *children=container.subviews;
        NSUInteger back=[children indexOfObjectIdenticalTo:anchor],own=[children indexOfObjectIdenticalTo:self.host];
        if (self.host.superview!=container || own!=back+1) {
            [self.host removeFromSuperview];[container insertSubview:self.host aboveSubview:anchor];
        }
        self.content=content;self.controller=best;
        // Geometry and host use the same parent presentation space. The admitted
        // rectangle is the observed panel/backdrop intersected with root+viewport;
        // no one-frame lead may paint desktop below a partially opened panel.
        CGRect hostFrame=CGRectZero;
        CGRect clip=LMVLockVideoGeometry(content,container,best.viewIfLoaded,anchor,content.window,&hostFrame);
        CGRect sampledClip=clip;CGFloat lead=0;
        visible=LMVLockVideoRectValid(clip);
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.host.frame=hostFrame;self.host.alpha=1;self.host.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self.playback layoutInBounds:self.host.bounds];self.host.clipLayer.frame=self.host.bounds;
        if (!self.host.clipLayer.path || !CGRectEqualToRect(CGPathGetBoundingBox(self.host.clipLayer.path),clip)) {
            CGPathRef path=CGPathCreateWithRect(clip,NULL);self.host.clipLayer.path=path;CGPathRelease(path);
        }
        self.host.hidden=!visible;[CATransaction commit];
        if (visible) [self leasePaint:container];else [self releasePaint];
        if (diagnostics) {
        // Which parent the surface ended up in, and every visible sibling painted
        // above it: if wallpaper still shows through, this names the culprit.
        NSMutableString *aboveText=[NSMutableString string];
        UIView *hostParent=self.host.superview;
        if (hostParent) {
            NSArray *siblings=hostParent.subviews;
            NSUInteger hostIndex=[siblings indexOfObjectIdenticalTo:self.host];
            for (NSUInteger index=(hostIndex==NSNotFound?0:hostIndex+1);index<siblings.count;index++) {
                UIView *sibling=siblings[index];
                if (sibling.hidden || sibling.alpha<0.05) continue;
                if (aboveText.length>140) {[aboveText appendString:@"..."];break;}
                [aboveText appendFormat:@"%@ ",NSStringFromClass(sibling.class)];
            }
        }
        // Diagnostics: where the revealed band sits on screen and how much of the
        // viewport stays uncovered (the "background dropped / wallpaper leaked"
        // measurement). Numbers only, so every harness can compile it.
        UIWindow *coverWindow=content.window;
        CGRect coverViewport=LMVVideoWindowViewport(coverWindow);
        CALayer *coverRoot=coverWindow.layer.presentationLayer ?: coverWindow.layer;
        CALayer *coverSpace=self.host.layer.presentationLayer ?: self.host.layer;
        CGRect hostInWindow=[coverSpace convertRect:coverSpace.bounds toLayer:coverRoot];
        CGRect revealed=CGRectIsEmpty(coverViewport)?CGRectZero:[coverSpace convertRect:clip toLayer:coverRoot];
        // What the sampled band alone would have left uncovered: this is the leak
        // that the one-frame lead above removes, so a future report can tell the two
        // apart ("geometry lag" vs "covered by something else").
        CGRect sampledRevealed=CGRectIsEmpty(coverViewport)?CGRectZero:[coverSpace convertRect:sampledClip toLayer:coverRoot];
        CGFloat sampledGapTop=CGRectIsEmpty(sampledRevealed)?coverViewport.size.height:MAX(0.0,sampledRevealed.origin.y-coverViewport.origin.y);
        CGFloat sampledGapBottom=CGRectIsEmpty(sampledRevealed)?coverViewport.size.height:MAX(0.0,(coverViewport.origin.y+coverViewport.size.height)-(sampledRevealed.origin.y+sampledRevealed.size.height));
        CGFloat revealedHeight=CGRectIsEmpty(revealed)?0.0:revealed.size.height;
        CGFloat gapTop=CGRectIsEmpty(revealed)?coverViewport.size.height:MAX(0.0,revealed.origin.y-coverViewport.origin.y);
        CGFloat gapBottom=CGRectIsEmpty(revealed)?coverViewport.size.height:MAX(0.0,(coverViewport.origin.y+coverViewport.size.height)-(revealed.origin.y+revealed.size.height));
        NSString *coverKey=[NSString stringWithFormat:@"r=%.0f t=%.0f b=%.0f L=%.0f t0=%.0f b0=%.0f v=%d %@|%@|%@",floor(revealedHeight/20.0)*20.0,floor(gapTop*2.0)/2.0,floor(gapBottom*2.0)/2.0,floor(lead/10.0)*10.0,floor(sampledGapTop/20.0)*20.0,floor(sampledGapBottom/20.0)*20.0,(int)self.host.hidden,hostParent?NSStringFromClass(hostParent.class):@"none",aboveText,self.paintText?:@"-"];
        if (![coverKey isEqualToString:self.coverage]) {
            self.coverage=coverKey;
            NSString *coverLine=[NSString stringWithFormat:@"lock-video cover reveal=%.1f gapTop=%.1f gapBottom=%.1f lead=%.1f sampledGapTop=%.1f sampledGapBottom=%.1f hostHidden=%d container=%@ hostSuper=%@ above=[%@] leasedPaint=[%@] clip=%@ hostInWindow=%@",
                revealedHeight,gapTop,gapBottom,lead,sampledGapTop,sampledGapBottom,(int)self.host.hidden,
                NSStringFromClass(container.class),hostParent?NSStringFromClass(hostParent.class):@"none",aboveText,
                self.paintText?:@"-",LMVLockVideoRectText(clip),LMVLockVideoRectText(hostInWindow)];
            LMVLockVideoLog(coverLine);
        }
        }
    } else {
        [self releasePaint];
        self.host.hidden=YES;[self.host removeFromSuperview];self.content=nil;self.controller=nil;
    }
    // 0.0.106: playback intent is decoupled from the per-frame host geometry.
    // Pulling Notification Center down transiently invalidates the derived
    // exposure/clip -- the system hides and re-lays-out the background paint
    // and the presentation layers are mid-animation -- and pausing the decoder
    // on every such frame froze the video for the whole gesture: it only
    // resumed once the panel settled ("frozen while pulling, plays at the
    // bottom"). The decoder now runs whenever the CoverSheet is genuinely
    // presented (a lifecycle-visible controller or an exposed host), while the
    // host itself still follows the geometry frame by frame. Unlocking,
    // screen-off, suspend and disable pause immediately via the lifecycle
    // record, screenAllowed and enabled.
    BOOL playbackWanted=self.enabled && self.path.length && self.revision.length && self.screenAllowed && (best || coverPresented);
    [self.playback setVisible:playbackWanted];
    // One lightweight geometry monitor only while the CoverSheet is exposed.
    // No message frame decoder, extra UIWindow, original opacity lease or source-cache write.
    if (best && content && self.screenAllowed) {
        if (!self.link) {self.link=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
            // 0.0.96: 30fps lagged the panel animation by up to a frame, so the
            // leading edge of the video band exposed wallpaper while dragging.
            self.link.preferredFramesPerSecond=60;[self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];}
    } else {[self.link invalidate];self.link=nil;}
    if (!self.enabled || !self.path.length || !self.revision.length) {
        if (self.playback.path || self.playback.player || self.playback.loading) [self.playback clear];
    }
    if(diagnostics) {
        NSString *coverPerf=LMVLockVideoPerf("lock",CACurrentMediaTime()-coverPerf0);
        if (coverPerf) LMVLockVideoLog(coverPerf);
    }
    self.updating=NO;
}
@end

static void LMVLockVideoDiscover(void) {
    if (!LMVLockControllers) LMVLockControllers=[NSHashTable weakObjectsHashTable];
    NSUInteger budget=96;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!LMVLockVideoClass(window,@"SBCoverSheetWindow")) continue;
            NSMutableArray *pending=[NSMutableArray new];if(window.rootViewController)[pending addObject:window.rootViewController];
            while (pending.count && budget) {
                --budget;UIViewController *controller=pending.lastObject;[pending removeLastObject];
                if (LMVLockVideoClass(controller,@"CSCoverSheetViewController")) [LMVLockControllers addObject:controller];
                [pending addObjectsFromArray:controller.childViewControllers];
                if (controller.presentedViewController) [pending addObject:controller.presentedViewController];
            }
        }
    }
}
static void LMVLockVideoRefresh(BOOL reload) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    LMVLockVideoDiscover();
    if (!LMVLockVideo) {LMVLockVideo=[LMVLockVideoManager new];reload=YES;}
    [LMVLockVideo refresh:reload];
}
static void LMVLockVideoSuspend(void) {if(NSThread.isMainThread)[LMVLockVideo suspend];}
static void LMVLockVideoLifecycle(UIViewController *controller,NSInteger visible) {
    if (!LMVInitialized || !NSThread.isMainThread) return;
    if (!LMVLockControllers) LMVLockControllers=[NSHashTable weakObjectsHashTable];
    [LMVLockControllers addObject:controller];
    LMVLockControllerRecord *record=objc_getAssociatedObject(controller,&LMVLockControllerRecordKey);
    if (!record) {record=[LMVLockControllerRecord new];objc_setAssociatedObject(controller,&LMVLockControllerRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    if (visible>=0) {record.lifecycleKnown=YES;record.visible=visible!=0;}
    LMVRequestSafeUpdate();
}
static void (*LMVLockOriginalLoadView)(id,SEL);
static void (*LMVLockOriginalDidLoad)(id,SEL);
static void (*LMVLockOriginalLayout)(id,SEL);
static void (*LMVLockOriginalWillAppear)(id,SEL,BOOL);
static void (*LMVLockOriginalDidAppear)(id,SEL,BOOL);
static void (*LMVLockOriginalDidDisappear)(id,SEL,BOOL);
static void LMVLockHookLoadView(id object,SEL selector) {LMVLockOriginalLoadView(object,selector);LMVLockVideoLifecycle(object,-1);}
static void LMVLockHookDidLoad(id object,SEL selector) {LMVLockOriginalDidLoad(object,selector);LMVLockVideoLifecycle(object,-1);}
static void LMVLockHookLayout(id object,SEL selector) {
    LMVLockOriginalLayout(object,selector);
    // The system just changed geometry/z-order. Repair the existing active NC
    // host in this same transaction, rather than leaving a stale mask/capture
    // visible until the queued global refresh or the next display-link tick.
    if(LMVInitialized && LMVLaunchReady && NSThread.isMainThread && LMVLockVideo &&
       LMVLockVideo.controller==object && !LMVLockVideo.updating && LMVLockVideo.enabled && LMVLockVideoScreenAllowed()) {
        LMVLockVideo.paintLeaseDirty=YES;[LMVLockVideo update];
        return; // this local pass subsumes the layout event, not a global cascade
    }
    LMVLockVideoLifecycle(object,-1);
}
static void LMVLockHookWillAppear(id object,SEL selector,BOOL animated) {LMVLockOriginalWillAppear(object,selector,animated);LMVLockVideoLifecycle(object,1);}
static void LMVLockHookDidAppear(id object,SEL selector,BOOL animated) {LMVLockOriginalDidAppear(object,selector,animated);LMVLockVideoLifecycle(object,1);}
static void LMVLockHookDidDisappear(id object,SEL selector,BOOL animated) {LMVLockOriginalDidDisappear(object,selector,animated);LMVLockVideoLifecycle(object,0);}
// Runtime encodings and UIKit base-class identity are checked before typed IMPs
// are installed. No generic UIView/CALayer hooks or private singleton creation.
static BOOL LMVLockVideoHookMatches(Class cls,SEL selector,BOOL animated) {
    Method method=class_getInstanceMethod(cls,selector);
    if (!method || method_getNumberOfArguments(method)!=(animated?3U:2U)) return NO;
    char *result=method_copyReturnType(method);BOOL okay=result && !strcmp(result,@encode(void));free(result);
    char *selfType=method_copyArgumentType(method,0),*cmdType=method_copyArgumentType(method,1);
    okay=okay && selfType && !strcmp(selfType,@encode(id)) && cmdType && !strcmp(cmdType,@encode(SEL));free(selfType);free(cmdType);
    if (animated) {char *type=method_copyArgumentType(method,2);okay=okay && type && !strcmp(type,@encode(BOOL));free(type);}
    return okay;
}
static void LMVLockVideoInstallHooks(void) {
    Class cls=NSClassFromString(@"CSCoverSheetViewController");
    if (!cls || ![cls isSubclassOfClass:UIViewController.class]) {LMVLockVideoLog(@"lock-video hook-controller-unavailable");return;}
#define LMV_INSTALL_LOCK_HOOK(name,animate,replacement,original) do { \
    SEL selector=NSSelectorFromString(name); \
    if (LMVLockVideoHookMatches(cls,selector,animate)) { \
        MSHookMessageEx(cls,selector,(IMP)replacement,(IMP *)&original); \
        LMVLockVideoLog([@"lock-video hook-installed " stringByAppendingString:name]); \
    } else LMVLockVideoLog([@"lock-video hook-rejected " stringByAppendingString:name]); \
} while(0)
    LMV_INSTALL_LOCK_HOOK(@"loadView",NO,LMVLockHookLoadView,LMVLockOriginalLoadView);
    LMV_INSTALL_LOCK_HOOK(@"viewDidLoad",NO,LMVLockHookDidLoad,LMVLockOriginalDidLoad);
    LMV_INSTALL_LOCK_HOOK(@"viewDidLayoutSubviews",NO,LMVLockHookLayout,LMVLockOriginalLayout);
    LMV_INSTALL_LOCK_HOOK(@"viewWillAppear:",YES,LMVLockHookWillAppear,LMVLockOriginalWillAppear);
    LMV_INSTALL_LOCK_HOOK(@"viewDidAppear:",YES,LMVLockHookDidAppear,LMVLockOriginalDidAppear);
    LMV_INSTALL_LOCK_HOOK(@"viewDidDisappear:",YES,LMVLockHookDidDisappear,LMVLockOriginalDidDisappear);
#undef LMV_INSTALL_LOCK_HOOK
}
