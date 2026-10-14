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
static char LMVLockVideoPaintEntryKey;
static BOOL LMVLockVideoPaintHidden(UIView *view);
static BOOL LMVLockVideoRepaintPure(UIView *view);
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
// Final mask stage, not the earlier exposure union. A currently verified
// content-owned host must retain at least its container; physical clipping
// remains an intersection. Root fallback/withdrawn/unknown hosts get no union.
static CGRect LMVLockVideoFinalMask(CGRect local,CGRect container,CGRect physical,BOOL owned) {
    if(!LMVLockVideoRectValid(container) || !LMVLockVideoRectValid(physical))return CGRectZero;
    CGRect mask=local;
    if(owned)mask=LMVLockVideoRectValid(local)?CGRectUnion(local,container):container;
    if(!LMVLockVideoRectValid(mask))return CGRectZero;
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
    // boundary or for the root-owned wallpaper fallback. The container and
    // recognized backdrop must both be actually on screen right now.
    if (ownsBackdrop && !content.hidden && content.alpha>.01 && !LMVLockVideoPaintHidden(backdrop) && backdrop.alpha>.01) {
        CGRect exposure=LMVLockVideoRectInTree(backdrop,window,paint,root);
        if (LMVLockVideoRectValid(CGRectIntersection(containerRect,exposure))) {
            CGRect owned=LMVLockVideoOwnedPaintRect(containerRect,exposure,panelRect,viewport);
            if (LMVLockVideoRectValid(owned)) admitted=owned;
        }
    }
    NSUInteger backdropBudget=64;
    BOOL rootBackdrop=!ownsBackdrop && backdrop && backdrop.superview==container &&
        LMVLockVideoBackground(backdrop,0,&backdropBudget);
    BOOL owned=(ownsBackdrop || rootBackdrop) && !content.hidden && content.alpha>.01 &&
        !LMVLockVideoPaintHidden(backdrop) && backdrop.alpha>.01 && LMVLockVideoRectValid(containerRect);
    if(!LMVLockVideoRectValid(admitted) && !owned)return CGRectZero;
    // Union is applied to the FINAL owned-host mask, not just the earlier
    // backdrop exposure calculation. A transient empty derived region can use
    // the still-exposed attached container; physical offscreen still rejects.
    CGRect local=LMVLockVideoRectValid(admitted)?[space convertRect:admitted fromLayer:root]:CGRectZero;
    if (!LMVLockVideoRectValid(space.bounds)) return CGRectZero;
    // This is the final mask operation discussed in the supplied patch notes.
    // The container's own currently exposed bounds may extend farther than the
    // calculated local mask. Preserve that owned paint instead of intersecting
    // it away a second time. Do not grant a whole-window fallback.
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
    CGRect mask=LMVLockVideoFinalMask(local,space.bounds,physicalLocal,owned);
    if(!LMVLockVideoRectValid(mask))return CGRectZero;
    CGRect frame=CGRectUnion(space.bounds,mask);
    if(hostFrame)*hostFrame=frame;
    return CGRectOffset(mask,-frame.origin.x,-frame.origin.y);
}
// Attached content-owned paint follows the original layer's animation itself.
// Never bake a sampled viewport edge into this model child: by the next commit
// that edge is stale. Screen/window and real ancestor clips already apply in
// the SAME layer tree. This exception is not used by a promoted/root host.
static CGRect LMVLockVideoAttachedPaint(CGRect bounds,CGRect backdrop,CGRect panel) {
    if(!LMVLockVideoRectValid(bounds) || !LMVLockVideoRectValid(backdrop) ||
       !LMVLockVideoRectValid(panel) || !LMVLockVideoRectValid(CGRectIntersection(bounds,backdrop)))return CGRectZero;
    return LMVLockVideoOwnedPaintRect(bounds,backdrop,panel,CGRectUnion(bounds,backdrop));
}
static BOOL LMVLockVideoAttachedGeometry(UIView *content,UIView *container,UIView *panel,UIView *anchor,CGRect *frame,CGRect *clip) {
    if(container!=content || anchor.superview!=content || anchor!=LMVLockVideoContentBackdrop(content) ||
       !LMVLockVideoRepaintPure(anchor) || ![content isDescendantOfView:panel] || content.window!=panel.window)return NO;
    // Unsupported transforms cannot turn a rectangular envelope into a guessed
    // bounding box. Keep the original conservative geometry in those cases.
    for(UIView *node=content;node;node=node.superview) {
        CATransform3D t=node.layer.transform;
        if(!CATransform3DIsAffine(t))return NO;
        CGAffineTransform a=CATransform3DGetAffineTransform(t);
        if(fabs(a.a-1)>.0001 || fabs(a.d-1)>.0001 || fabs(a.b)>.0001 || fabs(a.c)>.0001)return NO;
        if(node==panel)break;
    }
    CALayer *space=content.layer;
    CGRect backdrop=[space convertRect:anchor.layer.bounds fromLayer:anchor.layer];
    CGRect boundary=[space convertRect:panel.layer.bounds fromLayer:panel.layer];
    // Preserve .102's already-admitted same-owner zero/non-clipping layout.
    if(!LMVLockVideoRectValid(boundary) && !panel.clipsToBounds && !panel.layer.masksToBounds)boundary=space.bounds;
    CGRect paint=LMVLockVideoAttachedPaint(space.bounds,backdrop,boundary);
    // Only real MODEL clipping boundaries, never the sampled presentation
    // viewport edge. Preserve the established content/ancestor clips exactly.
    NSUInteger depth=0;
    for(UIView *node=content;node && node!=content.window && ++depth<=24;node=node.superview) {
        if(node.clipsToBounds || node.layer.masksToBounds)
            paint=CGRectIntersection(paint,[space convertRect:node.layer.bounds fromLayer:node.layer]);
    }
    if(!LMVLockVideoRectValid(paint))return NO;
    CGRect extent=CGRectUnion(space.bounds,paint);
    if(frame)*frame=extent;
    if(clip)*clip=CGRectOffset(paint,-extent.origin.x,-extent.origin.y);
    return YES;
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
@interface LMVLockVideoPaintMarker:NSObject
@property(nonatomic,weak) LMVLockVideoPaintEntry *entry;
@end
@implementation LMVLockVideoPaintMarker @end
static BOOL LMVLockVideoPaintHidden(UIView *view) {
    LMVLockVideoPaintMarker *marker=objc_getAssociatedObject(view,&LMVLockVideoPaintEntryKey);
    LMVLockVideoPaintEntry *entry=marker.entry;
    if(entry.view==view && entry.ownsHidden && view.superview==entry.parent && view.hidden &&
       [view isDescendantOfView:entry.scope])return entry.baselineHidden;
    return view.hidden;
}
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
    LMVLockVideoPaintMarker *marker=objc_getAssociatedObject(view,&LMVLockVideoPaintEntryKey);
    if(marker.entry==entry)objc_setAssociatedObject(view,&LMVLockVideoPaintEntryKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
// .105: host.alpha=1 does not defeat a fading ancestor. Move only our SAME
// video host out of that fade, below the existing foreground branch. Admission
// is still the original panel's physical clip; no new window/fullscreen union,
// and no system alpha/mask/transform is rewritten.
static BOOL LMVLockVideoOpaqueChain(UIView *view,UIWindow *window) {
    NSUInteger depth=0;
    for(UIView *node=view;node && ++depth<=16;node=node.superview) {
        CALayer *model=node.layer,*shown=model.presentationLayer;
        if(node.hidden || model.hidden || node.alpha<.999 || model.opacity<.999 ||
           (shown && (shown.hidden || shown.opacity<.999)) || model.mask || model.compositingFilter)return NO;
        if(node==window)return YES;
    }
    return NO;
}
static UIView *LMVLockVideoOpaqueSlot(UIView *container,UIView *anchor,UIView *own,UIView **foreground) {
    if(foreground)*foreground=nil;
    UIWindow *window=container.window;
    if(!LMVLockVideoClass(window,@"SBCoverSheetWindow") || LMVLockVideoOpaqueChain(container,window) ||
       !anchor || anchor.superview!=container || !LMVLockVideoRepaintPure(anchor))return nil;
    NSUInteger budget=64;
    if(!LMVLockVideoBackground(anchor,0,&budget))return nil;
    // Do not bypass an arbitrary system mask/filter or a genuinely hidden owner.
    for(UIView *node=container;node;node=node.superview) {
        if(node.hidden || node.layer.hidden || node.layer.mask || node.layer.compositingFilter)return nil;
        if(node==window)break;
    }
    UIView *branch=container;NSUInteger depth=0;
    for(UIView *parent=container.superview;parent && ++depth<=16;branch=parent,parent=parent.superview) {
        BOOL found=NO;NSUInteger left=64;
        for(UIView *sibling in parent.subviews) {
            if(!left--)return nil;
            if(sibling==own)continue;
            if(sibling==branch){found=YES;break;}
            if(!LMVLockVideoBackgroundPaint(sibling) || !LMVLockVideoRepaintPure(sibling))return nil;
        }
        if(!found || branch.layer.superlayer!=parent.layer)return nil;
        if(LMVLockVideoOpaqueChain(parent,window)) {
            if(foreground)*foreground=branch;
            return parent;
        }
        if(parent==window)break;
    }
    return nil;
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
    if(!container || !host.superview || content.window!=container.window || host.window!=content.window)return;
    UIView *branch=host;UIWindow *window=content.window;NSUInteger depth=0;
    for(UIView *scope=host.superview;scope && depth++<16 && *budget;branch=scope,scope=scope.superview) {
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
@property(nonatomic,weak) UIView *extentContainer,*extentForeground,*extentAnchor;
@property(nonatomic,copy) NSString *compositeState;
@property(nonatomic) CFTimeInterval lastCompositeAt;
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
        // 0.0.114: master switch, read inline so a sliced test fixture needs no
        // extra symbol. An absent (or non-number) value means ENABLED.
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        BOOL globalOn=![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue];
        self.enabled=globalOn && [enabled respondsToSelector:@selector(boolValue)] && [enabled boolValue];
        self.path=self.enabled?LMVLockVideoSelectedPath():nil;
        self.revision=LMVLockVideoRevision(self.path);self.lastRevisionCheck=CACurrentMediaTime();
        [self.playback selectPath:self.path revision:self.revision];
    }
    self.screenAllowed=LMVLockVideoScreenAllowed();[self update];
}
- (void)suspend {
    [self releasePaint];
    [self.playback setVisible:NO];self.host.hidden=YES;
    self.extentContainer=nil;self.extentForeground=nil;self.extentAnchor=nil;
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
        if(self.extentContainer==container && self.extentAnchor.superview==container &&
           LMVLockVideoAboveHostTree(self.extentAnchor,self.host,self.content) &&
           LMVLockVideoRepaintPure(self.extentAnchor) && ![found containsObject:self.extentAnchor])
            [found addObject:self.extentAnchor];
        self.paintLeaseTime=now;
        for (UIView *view in found) {
            BOOL known=NO;for (LMVLockVideoPaintEntry *entry in entries) if (entry.view==view) {known=YES;break;}
            if (known) continue;
            LMVLockVideoPaintEntry *entry=[LMVLockVideoPaintEntry new];entry.view=view;entry.parent=view.superview;entry.scope=self.content.window;
            entry.baselineHidden=view.hidden;entry.ownsHidden=!view.hidden;
            if(entry.ownsHidden){LMVLockVideoPaintMarker *marker=[LMVLockVideoPaintMarker new];marker.entry=entry;
                objc_setAssociatedObject(view,&LMVLockVideoPaintEntryKey,marker,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
            [entries addObject:entry];
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
    if (self.enabled && self.path.length && self.revision.length && self.screenAllowed) {
        for (UIViewController *candidate in LMVLockControllers.allObjects) {
            UIView *root=candidate.viewIfLoaded;UIWindow *window=root.window;
            if (!root || !LMVLockVideoClass(window,@"SBCoverSheetWindow") || window.screen!=UIScreen.mainScreen) continue;
            LMVLockControllerRecord *record=objc_getAssociatedObject(candidate,&LMVLockControllerRecordKey);
            if (!record) {record=[LMVLockControllerRecord new];objc_setAssociatedObject(candidate,&LMVLockControllerRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
            UIView *sliding=LMVLockVideoContent(root);CGRect contentRect=LMVLockVideoVisibleRect(sliding,window);
            CGRect viewport=LMVVideoWindowViewport(window),panel=LMVLockVideoVisibleRect(root,window);
            CGRect exposed=CGRectIntersection(contentRect,panel);
            UIView *backdrop=LMVLockVideoContentBackdrop(sliding);
            BOOL ownedActive=sliding && !sliding.hidden && sliding.alpha>.01 && backdrop && !LMVLockVideoPaintHidden(backdrop) && backdrop.alpha>.01 &&
                LMVLockVideoRectValid(CGRectIntersection(contentRect,LMVLockVideoVisibleRect(backdrop,window)));
            // A non-clipping root can momentarily have empty layout bounds while
            // this SAME attached owner/background still occupies the screen.
            // Never cache its previous mask or grant this exception to a new,
            // detached, unknown, withdrawn or genuinely off-screen content.
            BOOL sameOwner=record.wasExposed && record.exposedContent==sliding && self.content==sliding &&
                self.controller==candidate && (self.host.superview==sliding ||
                (self.extentContainer==sliding && self.host.superview==self.extentForeground.superview));
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
    BOOL visible=best && content && container && anchor,panelAttached=NO;
    if (visible) {
        self.content=content;self.controller=best;
        // Resolve geometry in the original owned background space FIRST. Any
        // promotion keeps exactly this clip, including Reachability/partial bottom.
        CGRect hostFrame=CGRectZero;
        CGRect clip=LMVLockVideoGeometry(content,container,best.viewIfLoaded,anchor,content.window,&hostFrame);
        CGRect sampledClip=clip;CGFloat lead=0;
        visible=LMVLockVideoRectValid(clip);
        UIView *oldExtent=self.extentContainer,*oldForeground=self.extentForeground;
        UIView *foreground=nil;
        UIView *promoted=visible?LMVLockVideoOpaqueSlot(container,anchor,self.host,&foreground):nil;
        UIView *renderParent=container;
        if(promoted && foreground) {
            CALayer *from=container.layer.presentationLayer,*to=promoted.layer.presentationLayer;
            if(!from || !to){from=container.layer;to=promoted.layer;}
            CGRect admitted=CGRectOffset(clip,hostFrame.origin.x,hostFrame.origin.y);
            CGRect frame=[to convertRect:hostFrame fromLayer:from];
            CGRect exposed=[to convertRect:admitted fromLayer:from];
            if(LMVLockVideoRectValid(frame) && LMVLockVideoRectValid(exposed)) {
                renderParent=promoted;hostFrame=frame;
                clip=CGRectOffset(exposed,-frame.origin.x,-frame.origin.y);
                // A promoted host must not leave an original wallpaper branch
                // ABOVE it. Suppress only the already-verified pure anchor.
                self.extentContainer=container;self.extentForeground=foreground;self.extentAnchor=anchor;
            }
        }
        sampledClip=clip;
        if(renderParent==container) {
            self.extentContainer=nil;self.extentForeground=nil;self.extentAnchor=nil;
            // Visibility is still gated by current observed exposure above.
            // The admitted background itself stays in the original MODEL panel
            // space, so its full image and leading edge move as one subtree.
            if(visible)panelAttached=LMVLockVideoAttachedGeometry(content,container,best.viewIfLoaded,anchor,&hostFrame,&clip);
        }
        if(oldExtent!=self.extentContainer || oldForeground!=self.extentForeground)self.paintLeaseDirty=YES;
        [CATransaction begin];[CATransaction setDisableActions:YES];
        NSArray *children=renderParent.subviews;
        NSUInteger own=[children indexOfObjectIdenticalTo:self.host];
        if(renderParent==container) {
            NSUInteger back=[children indexOfObjectIdenticalTo:anchor];
            if(self.host.superview!=container || own!=back+1) {
                [self.host removeFromSuperview];[container insertSubview:self.host aboveSubview:anchor];
            }
        } else {
            NSUInteger front=[children indexOfObjectIdenticalTo:foreground];
            if(self.host.superview!=renderParent || own==NSNotFound || front!=own+1) {
                [self.host removeFromSuperview];
                front=[renderParent.subviews indexOfObjectIdenticalTo:foreground];
                [renderParent insertSubview:self.host atIndex:front];
            }
        }
        self.host.frame=hostFrame;self.host.alpha=1;self.host.autoresizingMask=panelAttached?0:UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self.playback layoutInBounds:self.host.bounds];self.host.clipLayer.frame=self.host.bounds;
        if (!self.host.clipLayer.path || !CGRectEqualToRect(CGPathGetBoundingBox(self.host.clipLayer.path),clip)) {
            CGPathRef path=CGPathCreateWithRect(clip,NULL);self.host.clipLayer.path=path;CGPathRelease(path);
        }
        self.host.hidden=!visible;
        // Owned surface/order/mask and background leases become visible in the
        // same commit; no one-frame wallpaper hand-off during promotion.
        if (visible) [self leasePaint:container];else [self releasePaint];
        [CATransaction commit];
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
        self.extentContainer=nil;self.extentForeground=nil;self.extentAnchor=nil;
    }
    [self.playback setVisible:visible];
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
    if(diagnostics && visible && CACurrentMediaTime()-self.lastCompositeAt>=.10) {
        self.lastCompositeAt=CACurrentMediaTime();
        NSMutableString *chain=[NSMutableString string];CGFloat effective=1;NSUInteger depth=0;
        for(UIView *node=self.host;node && depth++<16;node=node.superview) {
            CALayer *layer=node.layer,*shown=layer.presentationLayer ?: layer;
            effective*=shown.hidden?0:shown.opacity;
            [chain appendFormat:@"%@:%p a=%.3f o=%.3f p=%.3f h=%d/%d mask=%d filter=%d;",
                NSStringFromClass(node.class),(__bridge void *)node,node.alpha,layer.opacity,shown.opacity,
                layer.hidden,shown.hidden,layer.mask!=nil,layer.compositingFilter!=nil];
            if(node==content.window)break;
        }
        NSMutableString *paint=[NSMutableString string];NSUInteger left=8;
        for(LMVLockVideoPaintEntry *entry in self.paintLease.entries) {
            if(!left--)break;UIView *view=entry.view;if(!view)continue;
            CALayer *shown=view.layer.presentationLayer ?: view.layer;
            [paint appendFormat:@"%@:%p h=%d/%d o=%.3f/%.3f;",NSStringFromClass(view.class),
                (__bridge void *)view,view.hidden,shown.hidden,view.layer.opacity,shown.opacity];
        }
        // Actual committed MODEL versus actually available PRESENTATION tree.
        // Old coverage mixed a newly-written path with an older host position;
        // gapTop=0 therefore did not establish a zero-gap rendered frame.
        UIWindow *window=content.window;
        CALayer *shownHost=self.host.layer.presentationLayer,*shownWindow=window.layer.presentationLayer;
        CALayer *shownOwner=content.layer.presentationLayer;
        CAShapeLayer *shownMask=(CAShapeLayer *)self.host.clipLayer.presentationLayer;
        CGRect modelHost=[self.host.layer convertRect:CGPathGetBoundingBox(self.host.clipLayer.path) toLayer:window.layer];
        modelHost=CGRectIntersection(modelHost,LMVLockVideoRectInTree(self.host,window,self.host.layer,window.layer));
        CGRect shownHostRect=CGRectZero,shownOwnerRect=CGRectZero;
        BOOL actualShown=shownHost && shownWindow && shownOwner && shownMask.path;
        if(actualShown) {
            shownHostRect=[shownHost convertRect:CGPathGetBoundingBox(shownMask.path) toLayer:shownWindow];
            shownHostRect=CGRectIntersection(shownHostRect,LMVLockVideoRectInTree(self.host,window,shownHost,shownWindow));
            shownOwnerRect=LMVLockVideoRectInTree(content,window,shownOwner,shownWindow);
        }
        CGFloat actualGap=actualShown && LMVLockVideoRectValid(shownHostRect) && LMVLockVideoRectValid(shownOwnerRect)?
            MAX(0,CGRectGetMinY(shownHostRect)-CGRectGetMinY(shownOwnerRect)):-1;
        NSString *actualGeometry=[NSString stringWithFormat:@"lock-actualgeometry t=%.6f attached=%d shownAvailable=%d modelHost=%@ shownHost=%@ shownOwner=%@ actualGapTop=%.2f actualBottom=%.2f ownerY=%.2f/%.2f hostY=%.2f/%.2f source=%p player=%p leases=%lu",
            self.lastCompositeAt,panelAttached,actualShown,LMVLockVideoRectText(modelHost),LMVLockVideoRectText(shownHostRect),
            LMVLockVideoRectText(shownOwnerRect),actualGap,LMVLockVideoRectValid(shownHostRect)?CGRectGetMaxY(shownHostRect):-1,
            content.layer.position.y,shownOwner?shownOwner.position.y:-1,self.host.layer.position.y,shownHost?shownHost.position.y:-1,
            (__bridge void *)container,(__bridge void *)self.playback.player,(unsigned long)self.paintLease.entries.count];
        LMVLockVideoLog(actualGeometry);
        CAShapeLayer *mask=(CAShapeLayer *)(self.host.clipLayer.presentationLayer ?: self.host.clipLayer);
        NSString *state=[NSString stringWithFormat:@"lock-composite promoted=%d effective=%.3f chain=[%@] paint=[%@] maskModel=%@ maskShown=%@ render=h%d/o%.3f/p%.3f player=h%d/o%.3f/p%.3f",
            self.extentContainer!=nil,effective,chain,paint,
            LMVLockVideoRectText(self.host.clipLayer.path?CGPathGetBoundingBox(self.host.clipLayer.path):CGRectZero),
            LMVLockVideoRectText(mask.path?CGPathGetBoundingBox(mask.path):CGRectZero),
            self.playback.renderLayer.hidden,self.playback.renderLayer.opacity,
            (self.playback.renderLayer.presentationLayer ?: self.playback.renderLayer).opacity,
            self.playback.playerLayer.hidden,self.playback.playerLayer.opacity,
            (self.playback.playerLayer.presentationLayer ?: self.playback.playerLayer).opacity];
        if(![state isEqualToString:self.compositeState]){self.compositeState=state;LMVLockVideoLog(state);}
    } else if(!diagnostics){self.compositeState=nil;self.lastCompositeAt=0;}
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
