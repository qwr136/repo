#pragma once
// Independent from Desktop/Lock/message players; no Control Center module or
// CCSupport dependency is needed to render the existing panel's background.
static NSString *LMVCCSelectedPath(NSString *key) {
    id stored=(__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key,kLMVPrefsID);
    if (![stored isKindOfClass:NSString.class])return nil;NSString *relative=stored;
    if (!relative.length || [relative hasPrefix:@"/"] || [relative.pathComponents containsObject:@".."] || [relative.pathComponents containsObject:@"."])return nil;
    NSString *path=[[LMVDirectory stringByAppendingPathComponent:relative] stringByStandardizingPath];
    NSString *prefix=[LMVDirectory stringByAppendingString:@"/"];
    return [path hasPrefix:prefix] && [path.stringByResolvingSymlinksInPath hasPrefix:prefix]?path:nil;
}
static UIUserInterfaceStyle LMVCCStyle(UIViewController *controller) {
    // 0.0.79 fix: resolution order was inverted. UIScreen.traitCollection reports
    // the *system* appearance and in SpringBoard it keeps serving Light long after
    // the user switched to Dark, so probing the screen first pinned every Control
    // Center video to the light asset. The controller/scene trait is the one that
    // actually flips, so it is authoritative; the screen is only a last resort.
    UIUserInterfaceStyle style=UIUserInterfaceStyleUnspecified;
    if(controller) style=controller.traitCollection.userInterfaceStyle;
    if(style==UIUserInterfaceStyleUnspecified && controller.viewIfLoaded.window)
        style=controller.viewIfLoaded.window.traitCollection.userInterfaceStyle;
    if(style==UIUserInterfaceStyleUnspecified && controller.viewIfLoaded.window.windowScene)
        style=controller.viewIfLoaded.window.windowScene.traitCollection.userInterfaceStyle;
    if(style==UIUserInterfaceStyleUnspecified) style=UIScreen.mainScreen.traitCollection.userInterfaceStyle;
    return style==UIUserInterfaceStyleDark?UIUserInterfaceStyleDark:UIUserInterfaceStyleLight;
}
// 0.0.79 fix: the previous "pure background" probe walked the material view's
// whole subtree and rejected it whenever any descendant class name contained
// Module/Slider/Button/Header. MTMaterialView's internal backing view does
// contain such names, so the real Control Center backdrop was ALWAYS rejected and
// LMVCCMaterial returned nil - the video had nowhere to attach. Depth is now
// bounded to the material view's own layer host, and the check is about visual
// content, not about class-name vocabulary.
static BOOL LMVCCPureBackground(UIView *view) {
    if(!view)return NO;
    // Only the material view's DIRECT children are inspected. Anything deeper is
    // an implementation detail of Material Kit and must never disqualify the
    // backdrop - that is precisely the false rejection this fixes.
    if(view.subviews.count>24)return NO;
    for(UIView *child in view.subviews) {
        if([child isKindOfClass:UIControl.class])return NO;
        if(child.gestureRecognizers.count)return NO;
        NSString *name=NSStringFromClass(child.class);
        // Only unambiguous Control Center furniture disqualifies the backdrop.
        for(NSString *word in @[@"ModuleContainer",@"ContentCollection",@"StatusBar_Modern"])
            if([name containsString:word])return NO;
        // A direct child that is itself a scrollable collection is CC content.
        if([child isKindOfClass:UIScrollView.class])return NO;
    }
    return YES;
}
// When a short clipping CC root cuts the live video, the SAME video layer is
// promoted below that root's foreground branch. Hide only its proven pure
// material during that ownership interval; never detach a UIKit backing layer.
@interface LMVCCMaterialLease:NSObject
@property(nonatomic,weak) UIView *view,*parent;
@property(nonatomic) BOOL baselineHidden,applied;
- (void)restore;
@end
static char LMVCCMaterialLeaseKey;
@implementation LMVCCMaterialLease
- (void)restore {
    UIView *view=self.view;
    if(view && objc_getAssociatedObject(view,&LMVCCMaterialLeaseKey)==self) {
        if(self.applied && view.hidden)view.hidden=self.baselineHidden;
        objc_setAssociatedObject(view,&LMVCCMaterialLeaseKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    self.applied=NO;
}
- (void)dealloc {[self restore];}
@end
static BOOL LMVCCBackgroundHidden(UIView *view) {
    if(!view.hidden)return NO;
    LMVCCMaterialLease *lease=objc_getAssociatedObject(view,&LMVCCMaterialLeaseKey);
    return !(lease.applied && lease.view==view && lease.parent==view.superview && !lease.baselineHidden);
}
static BOOL LMVCCSuppressibleMaterial(UIView *view) {
    NSMutableArray *pending=[NSMutableArray arrayWithObject:view];NSUInteger budget=128;
    while(pending.count && budget--) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        if(LMVLockVideoForeground(node) || node.gestureRecognizers.count)return NO;
        if(node.subviews.count>32)return NO;
        [pending addObjectsFromArray:node.subviews];
    }
    return !pending.count;
}
// Reachability can translate either the overlay or its window below the screen.
// Measure the root's exposed viewport in root coordinates using public APIs;
// window.bounds alone does not account for a translated window.
static CGRect LMVCCVisibleViewport(UIView *root) {
    if(!root || !LMVLockVideoRectValid(root.bounds))return CGRectZero;
    // 0.0.84 fix: the ancestor hidden/faded short-circuit that used to sit here
    // returned CGRectZero whenever SBControlCenterWindow.hidden==1, which is
    // exactly what 降半屏/收起 leaves behind (16 of 40 observed layouts). That
    // made LMVCCMaterial bail out on its first line and the video layer was
    // detached, so the background vanished as soon as the panel stopped being
    // full-screen. Visibility is no longer a veto; the exposed window viewport
    // below is the only geometric authority.
    CGRect viewport=root.bounds;UIWindow *window=root.window;
    if(window) {
        CGRect exposed=LMVVideoWindowViewport(window);
        if(!LMVLockVideoRectValid(exposed))return CGRectZero;
        viewport=CGRectIntersection(viewport,[root convertRect:exposed fromView:window]);
        for(UIView *node=root.superview;node && node!=window;node=node.superview)
            if(node.clipsToBounds)viewport=CGRectIntersection(viewport,[root convertRect:node.bounds fromView:node]);
    }
    return LMVLockVideoRectValid(viewport) && viewport.size.width>1 && viewport.size.height>1?viewport:CGRectZero;
}
// Only a validated pure backdrop may enlarge a short, non-clipping overlay
// root. Its actual model/presentation exposure is authoritative, not an
// arbitrary window-sized fallback. Convert every presentation rect within the
// same tree, then back to the model root; never mix presentation/model layers.
static CGRect LMVCCBackgroundViewport(UIView *root,UIView *material) {
    CGRect viewport=LMVCCVisibleViewport(root);UIWindow *window=root.window;
    if(!window || !material || !LMVCCPureBackground(material))return viewport;
    CGRect exposed=LMVVideoWindowViewport(window);
    if(!LMVLockVideoRectValid(exposed))return CGRectZero;
    CGRect region=[material convertRect:material.bounds toView:window];
    CALayer *surface=material.layer.presentationLayer,*screen=window.layer.presentationLayer;
    CALayer *animatedRoot=root.layer.presentationLayer;
    CGRect animatedLocal=CGRectZero;
    if(surface && screen && animatedRoot) {
        CGRect animated=[surface convertRect:surface.bounds toLayer:screen];
        animated=CGRectIntersection(animated,exposed);
        NSUInteger animatedDepth=0;
        for(UIView *node=material.superview;node && node!=window;node=node.superview) {
            if(++animatedDepth>16){animated=CGRectZero;break;}
            if(node.clipsToBounds || node.layer.masksToBounds) {
                CALayer *clip=node.layer.presentationLayer;
                if(!clip){animated=CGRectZero;break;}
                animated=CGRectIntersection(animated,[clip convertRect:clip.bounds toLayer:screen]);
            }
        }
        if(LMVLockVideoRectValid(animated))animatedLocal=[animatedRoot convertRect:animated fromLayer:screen];
        CGRect presentedViewport=CGRectIntersection(animatedRoot.bounds,[animatedRoot convertRect:exposed fromLayer:screen]);
        if(LMVLockVideoRectValid(presentedViewport))
            animatedLocal=LMVLockVideoRectValid(animatedLocal)?CGRectUnion(animatedLocal,presentedViewport):presentedViewport;
    }
    region=CGRectIntersection(region,exposed);
    NSUInteger depth=0;
    for(UIView *node=material.superview;node && node!=window;node=node.superview) {
        if(++depth>16)return CGRectZero;
        if(node.clipsToBounds || node.layer.masksToBounds)
            region=CGRectIntersection(region,[node convertRect:node.bounds toView:window]);
    }
    if(LMVLockVideoRectValid(region)) {
        CGRect local=[root convertRect:region fromView:window];
        viewport=LMVLockVideoRectValid(viewport)?CGRectUnion(viewport,local):local;
    }
    if(LMVLockVideoRectValid(animatedLocal))
        viewport=LMVLockVideoRectValid(viewport)?CGRectUnion(viewport,animatedLocal):animatedLocal;
    return LMVLockVideoRectValid(viewport)?viewport:CGRectZero;
}
// The observed overlay has a direct MTMaterialView before CCUIScrollView.
// A Reachability backdrop can cover only the visible half of the full root:
// require full root width, but compare height with the exposed viewport. The
// material must still be below the content and pass the direct-child purity test.
static UIView *LMVCCMaterial(UIView *root) {
    CGRect viewport=LMVCCVisibleViewport(root);
    if(!LMVLockVideoRectValid(viewport))return nil;
    CGRect bounds=root.bounds;Class materialClass=NSClassFromString(@"MTMaterialView");
    NSUInteger contentIndex=NSNotFound;
    for(NSUInteger i=0;i<root.subviews.count;i++)
        if(LMVLockVideoClass(root.subviews[i],@"CCUIScrollView")){contentIndex=i;break;}
    for(NSUInteger i=0;i<root.subviews.count;i++) {
        if(contentIndex!=NSNotFound && i>=contentIndex)break;
        UIView *child=root.subviews[i];
        if(![child isKindOfClass:materialClass] || LMVCCBackgroundHidden(child) || child.alpha<.01)continue;
        CGRect rect=[child convertRect:child.bounds toView:root];
        CGRect clipped=CGRectIntersection(rect,viewport);
        CGRect rootClip=CGRectIntersection(rect,bounds);
        if(!LMVLockVideoRectValid(clipped) || !LMVLockVideoRectValid(rootClip))continue;
        if(clipped.size.width>1 && clipped.size.height>1 &&
           rootClip.size.width>=bounds.size.width*.98 &&
           clipped.size.width>=viewport.size.width*.98 &&
           // 0.0.84 fix: compare against the smaller of viewport/material height.
           // Requiring the material to cover the full viewport height rejected a
           // half-height backdrop whenever the viewport was still full-size
           // (screenOffset==0), which is the other half of the 降半屏 failure.
           clipped.size.height>=MIN(viewport.size.height,rect.size.height)*.98 && LMVCCPureBackground(child))return child;
    }
    // Seed actual children: starting at root and immediately skipping it made
    // the old fallback unreachable. Only nested full-root backgrounds qualify;
    // a rejected direct candidate cannot bypass the viewport/ordering checks.
    NSUInteger budget=64;
    NSMutableArray *pending=[NSMutableArray new];
    for(NSUInteger i=0;i<root.subviews.count && (contentIndex==NSNotFound || i<contentIndex);i++)
        [pending addObject:root.subviews[i]];
    while(pending.count && budget) {
        --budget;UIView *view=pending.lastObject;[pending removeLastObject];
        // Prune hidden ancestors and foreground branches before adding children.
        if(view.hidden || view.alpha<.01 || [view isKindOfClass:UIControl.class] || [view isKindOfClass:UIScrollView.class])continue;
        if(view.superview!=root && [view isKindOfClass:materialClass]) {
            CGRect rect=[view convertRect:view.bounds toView:root];
            CGRect clipped=CGRectIntersection(rect,bounds),visible=CGRectIntersection(rect,viewport);
            CGFloat full=bounds.size.width*bounds.size.height;
            if(full>0 && LMVLockVideoRectValid(clipped) && LMVLockVideoRectValid(visible) &&
               visible.size.width>1 && visible.size.height>1 &&
               (clipped.size.width*clipped.size.height)/full>=.90 && LMVCCPureBackground(view))return view;
        }
        // A rejected material is not a container in which to seek another backdrop.
        if(![view isKindOfClass:materialClass] && view.subviews.count<=24)[pending addObjectsFromArray:view.subviews];
    }
    return nil;
}
// A pure material is the anchor, not the geometric authority. In Reachability
// its bounds can end ABOVE the exposed viewport (the old MIN(height) acceptance
// allowed that). Extend only our render layer; never detach UIKit's backing.
// If the direct backdrop clips the extension, use its root-owned layer slot
// immediately above that backdrop and still below Control Center furniture.
static UIView *LMVCCRenderHost(UIView *root,UIView *material,CGRect *renderBounds) {
    if(renderBounds)*renderBounds=CGRectZero;
    CGRect viewport=LMVCCBackgroundViewport(root,material);
    if(!material || !LMVLockVideoRectValid(viewport))return nil;
    CGRect target=[material convertRect:viewport fromView:root];
    BOOL clipped=NO;NSUInteger depth=0;
    for(UIView *node=material;node && node!=root;node=node.superview) {
        if(++depth>16)return nil;
        if(node.clipsToBounds || node.layer.masksToBounds) {
            CGRect limit=[material convertRect:node.bounds fromView:node];
            if(!CGRectContainsRect(limit,target)){clipped=YES;break;}
        }
    }
    if(clipped) {
        if(material.superview!=root)return nil;
        if(renderBounds)*renderBounds=viewport;
        return root;
    }
    if(renderBounds)*renderBounds=CGRectUnion(material.bounds,target);
    return material;
}
// Effective paint, not a bounding-box union: every real clipping/masked
// ancestor is part of the admission test. A nonrectangular system mask is not
// ours to interpret or remove; reject it instead of bypassing a security scope.
static CGRect LMVCCEffectiveCoverage(UIView *host,CGRect local,UIWindow *window,BOOL presented) {
    if(!host || !window || host.window!=window)return CGRectZero;
    CALayer *space=presented?window.layer.presentationLayer:window.layer;
    CALayer *paint=presented?host.layer.presentationLayer:host.layer;
    if(!space || !paint)return CGRectZero;
    CGRect rect=[paint convertRect:local toLayer:space];NSUInteger depth=0;
    for(UIView *node=host;node;node=node.superview) {
        if(++depth>16 || node.layer.mask)return CGRectZero;
        CALayer *clip=presented?node.layer.presentationLayer:node.layer;
        if(!clip)return CGRectZero;
        if(node.clipsToBounds || node.layer.masksToBounds || node==window)
            rect=CGRectIntersection(rect,[clip convertRect:clip.bounds toLayer:space]);
        if(node==window)return CGRectIntersection(rect,LMVVideoWindowViewport(window));
    }
    return CGRectZero;
}
// Only the already observed SBControlCenterWindow, never a new overlay window
// or an application window. Walk the existing CC root ancestry, not class-name
// guesses or global window discovery. The slot is ABOVE preceding pure backing
// siblings and BELOW the branch carrying this same CC's foreground. In a mixed
// root the material remains in that foreground branch and is never suppressed.
static UIView *LMVCCAncestorSlot(UIView *root,CGRect *bounds,UIView **foreground) {
    UIWindow *window=root.window;
    if(!LMVLockVideoClass(window,@"SBControlCenterWindow"))return nil;
    CGRect exposed=LMVVideoWindowViewport(window);if(!LMVLockVideoRectValid(exposed))return nil;
    UIView *branch=root;NSUInteger depth=0;
    for(UIView *parent=root.superview;parent && ++depth<=16;branch=parent,parent=parent.superview) {
        BOOL reached=NO;NSUInteger budget=32;
        for(UIView *sibling in parent.subviews) {
            if(!budget--)return nil;
            if(sibling==branch){reached=YES;break;}
            if(sibling.layer==nil || [sibling isKindOfClass:UIControl.class] || [sibling isKindOfClass:UIScrollView.class] ||
               [sibling isKindOfClass:UILabel.class] || [sibling isKindOfClass:UITextView.class] || sibling.isAccessibilityElement ||
               sibling.gestureRecognizers.count || !LMVCCPureBackground(sibling))return nil;
        }
        if(!reached || branch.layer.superlayer!=parent.layer)return nil;
        CGRect local=[parent convertRect:exposed fromView:window];
        // At least the admitted owned container; actual ancestor clips are still
        // authoritative. No model/presentation cross-tree conversions.
        local=CGRectUnion(local,parent.bounds);
        CGRect effective=LMVCCEffectiveCoverage(parent,local,window,NO);
        BOOL covers=CGRectContainsRect(effective,exposed);
        CALayer *paint=parent.layer.presentationLayer,*screen=window.layer.presentationLayer;
        if(covers && paint && screen) {
            CGRect animated=[paint convertRect:exposed fromLayer:screen];
            local=CGRectUnion(local,animated);
            covers=CGRectContainsRect(LMVCCEffectiveCoverage(parent,local,window,YES),exposed);
        }
        if(covers) {if(bounds)*bounds=local;if(foreground)*foreground=branch;return parent;}
        if(parent==window)break;
    }
    return nil;
}
// Revalidate the known anchor without walking unrelated module/scroll trees.
// Direct-child purity and sibling order remain live checks (not stale cache data).
static BOOL LMVCCMaterialStillValid(UIView *root,UIView *material) {
    if(!root || !material || ![material isDescendantOfView:root] ||
       ![material isKindOfClass:NSClassFromString(@"MTMaterialView")] || !LMVCCPureBackground(material))return NO;
    UIView *branch=material;NSUInteger depth=0;
    for(UIView *node=material;node && node!=root;node=node.superview) {
        if(++depth>16 || LMVCCBackgroundHidden(node) || node.alpha<.01 || [node isKindOfClass:UIControl.class] || [node isKindOfClass:UIScrollView.class])return NO;
        branch=node;
    }
    BOOL reached=NO;NSUInteger budget=64;
    for(UIView *child in root.subviews) {
        if(!budget--)return NO;
        if(LMVLockVideoClass(child,@"CCUIScrollView"))break;
        if(child==branch)reached=YES;
    }
    if(!reached)return NO;
    CGRect viewport=LMVCCVisibleViewport(root),rect=[material convertRect:material.bounds toView:root];
    CGRect visible=CGRectIntersection(rect,viewport),rootClip=CGRectIntersection(rect,root.bounds);
    if(!LMVLockVideoRectValid(visible) || visible.size.width<=1 || visible.size.height<=1)return NO;
    if(material.superview==root) return rootClip.size.width>=root.bounds.size.width*.98 &&
        visible.size.width>=viewport.size.width*.98 && visible.size.height>=MIN(viewport.size.height,rect.size.height)*.98;
    CGFloat full=root.bounds.size.width*root.bounds.size.height;
    return full>0 && LMVLockVideoRectValid(rootClip) && rootClip.size.width*rootClip.size.height/full>=.90;
}
@interface LMVCCRecord:NSObject
@property(nonatomic) BOOL visible,closing,known,progressKnown;
@property(nonatomic) CGFloat progress;
@property(nonatomic) NSUInteger epoch;
@property(nonatomic,weak) UIView *materialRoot,*cachedMaterial;
@property(nonatomic) CFTimeInterval lastMaterialSearch;
@end
@implementation LMVCCRecord @end
static BOOL LMVCCPresentationAllows(LMVCCRecord *record) {
    // A short/translated persistent root is not evidence that CC is open.
    // Keep the established one-turn zero-close semantics, and closing frames
    // while positive progress is still known. Fully disappeared never qualifies.
    return record && record.known && (record.visible || (record.progressKnown && record.progress>.0001));
}
static char LMVCCRecordKey;
static NSHashTable<UIViewController *> *LMVCCControllers;
@interface LMVControlCenterVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,weak) UIViewController *controller;
@property(nonatomic,weak) UIView *material;
@property(nonatomic,copy) NSString *darkPath,*lightPath,*path,*revision,*status,*coverage;
@property(nonatomic) BOOL enabled,updating,suspended,presented;
@property(nonatomic) UIUserInterfaceStyle style;
@property(nonatomic) CFTimeInterval lastRevisionCheck;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) CADisplayLink *geometryLink;
// Promotion uses the SAME live video/player, never a second player layer.
@property(nonatomic,strong) LMVCCMaterialLease *materialLease;
@property(nonatomic,weak) UIView *extentContainer;
- (void)withdrawExtent;
- (void)refresh:(BOOL)reload;
- (void)update;
- (void)layoutMaterial:(UIView *)material inRoot:(UIView *)root;
- (void)syncGeometry;
- (void)geometryTick:(CADisplayLink *)link;
- (void)suspend;
@end
static LMVControlCenterVideoManager *LMVControlCenterVideo;
static void LMVCCDiscover(void) {
    if(!LMVCCControllers)LMVCCControllers=[NSHashTable weakObjectsHashTable];NSUInteger budget=128;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(window.screen!=UIScreen.mainScreen)continue;
            NSMutableArray *pending=[NSMutableArray new];if(window.rootViewController)[pending addObject:window.rootViewController];
            while(pending.count && budget) {--budget;UIViewController *controller=pending.lastObject;[pending removeLastObject];
                if(LMVLockVideoClass(controller,@"CCUIModularControlCenterOverlayViewController"))[LMVCCControllers addObject:controller];
                [pending addObjectsFromArray:controller.childViewControllers];if(controller.presentedViewController)[pending addObject:controller.presentedViewController];
            }
            // 0.0.79 fix: the overlay controller is not always reachable through
            // the child/presented chain (SpringBoard can host it through a private
            // affordance controller). Fall back to the next responder of the view
            // whose layer carries the overlay VC's own layer name, which is exactly
            // what the hierarchy dump records.
            if(!LMVCCControllers.count) {
                NSUInteger viewBudget=64;
                NSMutableArray *views=[NSMutableArray new];
                UIView *root=window.rootViewController.view ?: window.subviews.firstObject;
                if(root)[views addObject:root];
                while(views.count && viewBudget) {
                    --viewBudget;UIView *view=views.lastObject;[views removeLastObject];
                    if([view.layer.name hasSuffix:@"CCUIModularControlCenterOverlayViewController"]) {
                        UIViewController *owner=(UIViewController *)view.nextResponder;
                        if([owner isKindOfClass:UIViewController.class] &&
                           LMVLockVideoClass(owner,@"CCUIModularControlCenterOverlayViewController"))
                            [LMVCCControllers addObject:owner];
                    }
                    if(view.subviews.count<=32)[views addObjectsFromArray:view.subviews];
                }
            }
        }
    }
}
static NSString *LMVCCPerf(const char *channel,CFTimeInterval seconds) {
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
@implementation LMVControlCenterVideoManager
- (instancetype)init {
    if((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=YES;
        _playback.renderLayer.name=@"com.minis.lockmessagevideo.control-center.render";
        // 0.0.79 fix: an opaque black backing colour made the Control Center show a
        // black slab for as long as the first frame had not arrived yet - and with
        // no poster prepared, that was permanent. Leaving it clear means the
        // original material backdrop stays visible until real video pixels exist.
        _playback.renderLayer.backgroundColor=UIColor.clearColor.CGColor;
        __weak typeof(self) weakSelf=self;
        _playback.didChange=^{LMVControlCenterVideoManager *live=weakSelf;if(live && !live.updating && !live.suspended)[live update];};
    }return self;
}
- (void)dealloc {[_timer invalidate];[_geometryLink invalidate];[_materialLease restore];[_playback.renderLayer removeFromSuperlayer];}
- (void)withdrawExtent {
    [self.materialLease restore];self.materialLease=nil;self.extentContainer=nil;
}
- (void)refresh:(BOOL)reload {
    self.suspended=NO;
    if(reload) {
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("ControlCenterBackgroundEnabled"),kLMVPrefsID);
        // 0.0.114: master switch, inline (see LMVLockVideo.h).
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        BOOL globalOn=![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue];
        self.enabled=globalOn && [enabled respondsToSelector:@selector(boolValue)] && [enabled boolValue];
        self.darkPath=LMVCCSelectedPath(@"ControlCenterDarkVideo");self.lightPath=LMVCCSelectedPath(@"ControlCenterLightVideo");
    }
    [self update];
}- (void)suspend {
    self.suspended=YES;self.presented=NO;[self withdrawExtent];[self.playback setVisible:NO];[self.playback.renderLayer removeFromSuperlayer];
    self.material=nil;[self.timer invalidate];self.timer=nil;[self.geometryLink invalidate];self.geometryLink=nil;
}
- (void)layoutMaterial:(UIView *)material inRoot:(UIView *)root {
    CGRect renderBounds=CGRectZero;UIView *renderHost=LMVCCRenderHost(root,material,&renderBounds);
    if(!renderHost || !LMVLockVideoRectValid(renderBounds)){[self withdrawExtent];return;}
    LMVCCRecord *record=objc_getAssociatedObject(self.controller,&LMVCCRecordKey);
    UIWindow *window=root.window;CGRect exposed=LMVVideoWindowViewport(window);
    BOOL missing=!CGRectContainsRect(LMVCCEffectiveCoverage(renderHost,renderBounds,window,NO),exposed);
    if(!missing && renderHost.layer.presentationLayer && window.layer.presentationLayer)
        missing=!CGRectContainsRect(LMVCCEffectiveCoverage(renderHost,renderBounds,window,YES),exposed);
    UIView *foreground=nil;CGRect extent=CGRectZero;
    UIView *container=missing && LMVCCPresentationAllows(record)?LMVCCAncestorSlot(root,&extent,&foreground):nil;
    BOOL pixels=!self.playback.renderLayer.hidden && !self.playback.error;
    if(container && pixels && (self.updating || self.materialLease.view!=material) && !LMVCCSuppressibleMaterial(material))container=nil;
    if(container) {
        // SAME live video output, promoted to the existing CC-only background
        // slot. Suppress only verified pure material which otherwise paints over
        // the promoted video; never hide its foreground/root or detach backing.
        if(self.materialLease && (self.materialLease.view!=material || self.materialLease.parent!=material.superview))
            [self withdrawExtent];
        if(pixels && container && !self.materialLease) {
            LMVCCMaterialLease *lease=[LMVCCMaterialLease new];lease.view=material;lease.parent=material.superview;
            lease.baselineHidden=material.hidden;lease.applied=!material.hidden;
            self.materialLease=lease;objc_setAssociatedObject(material,&LMVCCMaterialLeaseKey,lease,OBJC_ASSOCIATION_ASSIGN);
        }
        if(pixels && self.materialLease.applied && !material.hidden)material.hidden=YES;
        else if(!pixels)[self withdrawExtent];
        renderHost=container;renderBounds=extent;self.extentContainer=container;
    } else [self withdrawExtent];
    CALayer *parent=renderHost.layer,*video=self.playback.renderLayer;
    BOOL reparent=video.superlayer!=parent,promoted=container!=nil,rootSlot=!promoted && renderHost!=material;
    BOOL reorder=promoted?([parent.sublayers indexOfObjectIdenticalTo:video]+1!=[parent.sublayers indexOfObjectIdenticalTo:foreground.layer]):
        (rootSlot && [parent.sublayers indexOfObjectIdenticalTo:video]!=[parent.sublayers indexOfObjectIdenticalTo:material.layer]+1);
    BOOL relayout=!CGRectEqualToRect(video.frame,renderBounds);
    if(!reparent && !reorder && !relayout && video.opacity==1)return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(reparent) {
        [video removeFromSuperlayer];
        for(CALayer *sibling in [parent.sublayers copy])
            if(sibling!=video && [sibling.name isEqualToString:@"com.minis.lockmessagevideo.control-center.render"])[sibling removeFromSuperlayer];
    }
    if(promoted && (reparent || reorder))[parent insertSublayer:video below:foreground.layer];
    else if(rootSlot && (reparent || reorder))[parent insertSublayer:video above:material.layer];
    else if(reparent)[parent addSublayer:video];
    if(relayout)[self.playback layoutInBounds:renderBounds];
    if(video.opacity!=1)video.opacity=1;
    [CATransaction commit];
}
- (void)syncGeometry {
    if(self.updating || self.suspended || !self.presented || !LMVLockVideoScreenAllowed())return;
    UIView *root=self.controller.viewIfLoaded,*material=self.material;
    if(!LMVCCMaterialStillValid(root,material))return;
    // No preference reads, revision stat, material discovery or player writes.
    // Geometry only: the 100 ms maintenance poll cannot follow a 60 Hz move.
    [self layoutMaterial:material inRoot:root];
}
- (void)geometryTick:(CADisplayLink *)link {(void)link;[self syncGeometry];}
- (void)update {
    if(self.updating || self.suspended)return;self.updating=YES;
    BOOL diagnostics=LMVDiagnosticsEnabled.load();
    CFTimeInterval now=CACurrentMediaTime(),coverPerf0=diagnostics?now:0;
    UIViewController *best=nil;UIView *material=nil;
    if(self.enabled && LMVLockVideoScreenAllowed())for(UIViewController *candidate in LMVCCControllers.allObjects) {
        LMVCCRecord *record=objc_getAssociatedObject(candidate,&LMVCCRecordKey);
        if(!record || !record.known)continue;
        UIView *root=candidate.viewIfLoaded;
        // 0.0.84 fix: never gate on LMVDesktopGeometryVisible here. That helper
        // vetoes on window.hidden and hidden/faded ancestors, and the Control
        // Center window is hidden=1 during 降半屏, so the candidate was skipped
        // before any geometry ran and the video layer stayed detached. Bounds
        // validity is the precondition that actually matters for this channel.
        if(!root || !LMVLockVideoRectValid(root.bounds))continue;
        if(!LMVCCPresentationAllows(record))continue;
        UIView *found=record.materialRoot==root && LMVCCMaterialStillValid(root,record.cachedMaterial)?record.cachedMaterial:nil;
        // Scrolling changes furniture geometry, not the identity of the pure
        // backdrop. Reuse its bounded live validation; refresh discovery once a
        // second or immediately when root/material ownership or purity changed.
        if(!found || now-record.lastMaterialSearch>=1) {
            record.lastMaterialSearch=now;
            found=LMVCCMaterial(root);
            record.materialRoot=root;record.cachedMaterial=found;
        }
        if(!found)continue;
        best=candidate;material=found;break;
    }
    self.controller=best;
    UIUserInterfaceStyle style=best?LMVCCStyle(best):self.style;
    NSString *path=self.enabled?(style==UIUserInterfaceStyleDark?self.darkPath:self.lightPath):nil;
    BOOL changed=(path || self.path) && ![path isEqualToString:self.path];
    BOOL revisionDue=changed || CACurrentMediaTime()-self.lastRevisionCheck>1;
    NSString *revision=revisionDue?LMVLockVideoRevision(path):self.revision;
    if(revisionDue)self.lastRevisionCheck=CACurrentMediaTime();
    BOOL revisionChanged=(revision || self.revision) && ![revision isEqualToString:self.revision];
    self.style=style;
    // 0.0.79 fix: "open once, close, reopen shows nothing". The poster used to be
    // prepared only when the path/revision CHANGED, so a reopen with the same
    // asset skipped that block entirely. By then the player had been paused and
    // detached, so playerLayer.readyForDisplay was NO and the poster was the only
    // thing that could keep renderLayer visible - and it had been dropped on the
    // close pass. Re-seed the poster on every hidden->visible transition so a
    // reopen always has real pixels to show immediately.
    BOOL becomingVisible=path.length>0 && !self.presented;
    if(changed || revisionChanged) {
        self.path=path;self.revision=revision;
        // 0.0.79 fix: prepare the poster frame BEFORE selecting the path. Without a
        // poster, LMVLockVideoPlayback keeps renderLayer.hidden=YES until
        // playerLayer.readyForDisplay turns true, which never happens while the
        // Control Center is closed - so nothing was ever displayed. Seeding the
        // poster gives the layer real pixels to show from the first frame.
        [self.playback preparePosterForPath:path revision:revision];
        [self.playback selectPath:path revision:revision];
    } else if(becomingVisible) {
        // Same asset as last time, but we are re-opening: the player was paused and
        // detached on close, so playerLayer.readyForDisplay is NO on the frame the
        // Control Center reappears and the poster is the only thing that can keep
        // renderLayer visible. `preparePosterForPath:` early-returns when the
        // prepared path/revision already match, so use the synchronous cache read
        // (same helper the Desktop channel relies on) to re-seat poster contents
        // immediately, with no decoder work on the hook path.
        if(self.playback.posterLayer.contents==nil)
            [self.playback loadCachedPosterNowForPath:path revision:revision];
    }
    CGRect renderBounds=CGRectZero;UIView *renderHost=best?LMVCCRenderHost(best.viewIfLoaded,material,&renderBounds):nil;
    BOOL visible=best && material && renderHost && LMVLockVideoRectValid(renderBounds) && path.length && revision.length;
    if(visible!=self.presented || self.playback.wantsPlayback!=visible)[self.playback setVisible:visible];
    else if(visible)[self.playback resumeIfNeeded];
    if(visible) {
        [self layoutMaterial:material inRoot:best.viewIfLoaded];
        self.material=material;
    } else { [self withdrawExtent];if(self.playback.renderLayer.superlayer)[self.playback.renderLayer removeFromSuperlayer];self.material=nil; }
    // Track the presentation state so the next update can detect a hidden->visible
    // transition and re-seed the poster (see the 0.0.79 note above).
    self.presented=visible;
    if(visible && !self.geometryLink) {
        self.geometryLink=[CADisplayLink displayLinkWithTarget:self selector:@selector(geometryTick:)];
        self.geometryLink.preferredFramesPerSecond=60;
        [self.geometryLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    } else if(!visible) {[self.geometryLink invalidate];self.geometryLink=nil;}
    // 0.0.79 fix: the poll timer used to require a resolved controller AND an open
    // Control Center, so a run where the first discovery pass found nothing could
    // never recover - the poster arriving later had nobody to report to. The timer
    // now runs whenever the feature is enabled and simply re-resolves everything.
    if(self.enabled && !self.timer) {
        __weak typeof(self) weakSelf=self;
        self.timer=[NSTimer timerWithTimeInterval:.1 repeats:YES block:^(NSTimer *timer){[weakSelf update];}];
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    } else if(!self.enabled) {[self.timer invalidate];self.timer=nil;}
    if(!self.enabled && (self.playback.path || self.playback.player || self.playback.loading)) [self.playback clear];
    if(diagnostics) {
    NSString *status=[NSString stringWithFormat:@"control-center-video visible=%d enabled=%d presented=%d style=%ld selected=%d layer-ready=%d poster=%d material=%@ error=%ld",
        visible,self.enabled,self.presented,(long)style,path.length>0,self.playback.playerLayer.readyForDisplay,self.playback.posterLayer.contents!=nil,
        material?NSStringFromClass(material.class):@"none",(long)self.playback.error.code];
    if(![status isEqualToString:self.status]){self.status=status;LMVDiagnostic(status);}
    // 0.0.95 diagnostics: how much of the visible screen the Control Center surface
    // covers and where the uncovered band is ("background dropped / leaked").
    {
        UIView *coverSurface=renderHost;
        UIWindow *coverWindow=coverSurface.window;
        CGRect coverViewport=LMVVideoWindowViewport(coverWindow);
        BOOL attached=coverSurface!=nil && coverSurface.superview!=nil && coverWindow!=nil;
        CALayer *coverRoot=coverWindow.layer.presentationLayer ?: coverWindow.layer;
        CALayer *render=self.playback.renderLayer;
        CALayer *coverSpace=render.presentationLayer ?: render;
        attached=attached && render.superlayer!=nil;
        CGRect surfaceInWindow=attached?[coverSpace convertRect:coverSpace.bounds toLayer:coverRoot]:CGRectZero;
        CGRect revealed=CGRectIsEmpty(coverViewport)?CGRectZero:CGRectIntersection(surfaceInWindow,coverViewport);
        CGFloat revealedHeight=CGRectIsEmpty(revealed)?0.0:revealed.size.height;
        CGFloat coverGapTop=CGRectIsEmpty(coverViewport)?0.0:MAX(0.0,surfaceInWindow.origin.y-coverViewport.origin.y);
        CGFloat coverGapBottom=CGRectIsEmpty(coverViewport)?0.0:MAX(0.0,(coverViewport.origin.y+coverViewport.size.height)-(surfaceInWindow.origin.y+surfaceInWindow.size.height));
        NSString *coverKey=[NSString stringWithFormat:@"a=%d r=%.0f t=%.0f b=%.0f",(int)attached,floor(revealedHeight/20.0)*20.0,floor(coverGapTop/20.0)*20.0,floor(coverGapBottom/20.0)*20.0];
        if (![coverKey isEqualToString:self.coverage]) {
            self.coverage=coverKey;
            LMVDiagnostic([NSString stringWithFormat:@"cc-cover attached=%d revealed=%.1f gapTop=%.1f gapBottom=%.1f visible=%d material=%@ window=%@",
                (int)attached,revealedHeight,coverGapTop,coverGapBottom,visible,
                coverSurface?NSStringFromClass(coverSurface.class):@"none",
                coverWindow?NSStringFromClass(coverWindow.class):@"none"]);
        }
    }
    NSString *coverPerf=LMVCCPerf("cc",CACurrentMediaTime()-coverPerf0);
    if (coverPerf) LMVDiagnostic(coverPerf);
    } else {self.status=nil;self.coverage=nil;}
    self.updating=NO;
}
@end
// 1.13: publish the CC presentation to the Desktop probe (see the note there).
static BOOL LMVCCDesktopPresentedBridge(void);
static void LMVCCRefresh(BOOL reload) {
    if(!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread)return;
    LMVDesktopControlCenterPresentedHook=LMVCCDesktopPresentedBridge;
    static CFTimeInterval lastDiscovery=0;CFTimeInterval now=CACurrentMediaTime();
    if(!LMVCCControllers.count && (reload || !lastDiscovery || now-lastDiscovery>=.5)){LMVCCDiscover();lastDiscovery=now;}
    if(!LMVControlCenterVideo){LMVControlCenterVideo=[LMVControlCenterVideoManager new];reload=YES;}
    [LMVControlCenterVideo refresh:reload];
}
static void LMVCCSuspend(void) {if(NSThread.isMainThread)[LMVControlCenterVideo suspend];}
static LMVCCRecord *LMVCCTrack(UIViewController *controller) {
    if(!LMVInitialized || !NSThread.isMainThread || !controller)return nil;
    if(!LMVCCControllers)LMVCCControllers=[NSHashTable weakObjectsHashTable];[LMVCCControllers addObject:controller];
    LMVCCRecord *record=objc_getAssociatedObject(controller,&LMVCCRecordKey);
    if(!record){record=[LMVCCRecord new];objc_setAssociatedObject(controller,&LMVCCRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    return record;
}
static void LMVCCRequestUpdate(void) {
    if(!LMVLaunchReady || !NSThread.isMainThread)return;
    static BOOL pending=NO;if(pending)return;pending=YES;
    dispatch_async(dispatch_get_main_queue(),^{pending=NO;
        // A local event must wake the suspended manager, but may never bypass
        // the freshly checked screen-blank/lock policy or reload preferences.
        if(!LMVLockVideoScreenAllowed())return;
        if(LMVControlCenterVideo)[LMVControlCenterVideo refresh:NO];else LMVCCRefresh(YES);
    });
}
static void LMVCCLifecycle(UIViewController *controller,NSInteger state) {
    LMVCCRecord *record=LMVCCTrack(controller);if(!record)return;
    // 1 appearing, 2 appeared, 3 closing, 0 fully disappeared, -1 layout.
    if(state==1 || state==2){record.known=YES;record.visible=YES;record.closing=NO;record.progress=.5;record.progressKnown=YES;record.epoch++;if(state==2){record.progress=1;}}
    if(state==3){record.closing=YES;record.epoch++;}
    if(state==0){record.known=YES;record.visible=NO;record.closing=NO;record.progress=0;record.progressKnown=YES;record.epoch++;}
    LMVCCRequestUpdate();
}
static void LMVCCProgress(UIViewController *controller,CGFloat progress) {
    if(!isfinite(progress))return;
    LMVCCRecord *record=LMVCCTrack(controller);if(!record)return;
    record.progress=MAX(0,MIN(1,progress));record.progressKnown=YES;record.known=YES;
    NSUInteger epoch=++record.epoch;
    if(progress>.0001){record.visible=YES;record.closing=NO;LMVCCRequestUpdate();return;}
    // A zero may be sent before willAppear during an interactive opening. Give
    // that lifecycle one main-queue turn; a later positive progress invalidates
    // this close. No arbitrary sleep and no mid-gesture decoder rebuild.
    __weak UIViewController *weakController=controller;
    dispatch_async(dispatch_get_main_queue(),^{
        UIViewController *live=weakController;LMVCCRecord *current=live?objc_getAssociatedObject(live,&LMVCCRecordKey):nil;
        if(!current || current.epoch!=epoch || current.progress>.0001)return;
        current.visible=NO;current.closing=NO;LMVCCRequestUpdate();
    });
}
static BOOL LMVCCHookMatches(Class cls,SEL selector,const char *const *args,unsigned count) {
    Method method=class_getInstanceMethod(cls,selector);if(!method || method_getNumberOfArguments(method)!=count+2)return NO;
    char *ret=method_copyReturnType(method);BOOL matches=ret && !strcmp(ret,@encode(void));free(ret);
    for(unsigned n=0;matches && n<count;n++){char *type=method_copyArgumentType(method,n+2);matches=type && !strcmp(type,args[n]);free(type);}
    char *selfType=method_copyArgumentType(method,0),*cmd=method_copyArgumentType(method,1);
    matches=matches && selfType && cmd && !strcmp(selfType,@encode(id)) && !strcmp(cmd,@encode(SEL));free(selfType);free(cmd);
    return matches;
}
static void (*LMVCCOrigLoad)(id,SEL),(*LMVCCOrigLayout)(id,SEL);
static void (*LMVCCOrigWillAppear)(id,SEL,BOOL),(*LMVCCOrigDidAppear)(id,SEL,BOOL),(*LMVCCOrigWillDisappear)(id,SEL,BOOL),(*LMVCCOrigDidDisappear)(id,SEL,BOOL);
static void (*LMVCCOrigTrait)(id,SEL,id);
static void (*LMVCCOrigProgress)(id,SEL,double),(*LMVCCOrigInteractive)(id,SEL,double,BOOL),(*LMVCCOrigPrivateInteractive)(id,SEL,double,BOOL);
static void (*LMVCCOrigSignificant)(id,SEL,id,double);
static void LMVCCHookLoad(id value,SEL selector){LMVCCOrigLoad(value,selector);LMVCCLifecycle(value,-1);}
static void LMVCCHookLayout(id value,SEL selector){LMVCCOrigLayout(value,selector);LMVCCLifecycle(value,-1);
    if(LMVControlCenterVideo.controller==value)[LMVControlCenterVideo syncGeometry];}
static void LMVCCHookWillAppear(id value,SEL selector,BOOL animated){LMVCCOrigWillAppear(value,selector,animated);LMVCCLifecycle(value,1);}
static void LMVCCHookDidAppear(id value,SEL selector,BOOL animated){LMVCCOrigDidAppear(value,selector,animated);LMVCCLifecycle(value,2);}
static void LMVCCHookWillDisappear(id value,SEL selector,BOOL animated){LMVCCOrigWillDisappear(value,selector,animated);LMVCCLifecycle(value,3);}
static void LMVCCHookDidDisappear(id value,SEL selector,BOOL animated){LMVCCOrigDidDisappear(value,selector,animated);LMVCCLifecycle(value,0);}
static void LMVCCHookTrait(id value,SEL selector,id previous){LMVCCOrigTrait(value,selector,previous);LMVCCLifecycle(value,-1);}
static void LMVCCHookProgress(id value,SEL selector,double progress){LMVCCOrigProgress(value,selector,progress);LMVCCProgress(value,progress);}
static void LMVCCHookInteractive(id value,SEL selector,double progress,BOOL interactive){LMVCCOrigInteractive(value,selector,progress,interactive);LMVCCProgress(value,progress);}
static void LMVCCHookPrivateInteractive(id value,SEL selector,double progress,BOOL interactive){LMVCCOrigPrivateInteractive(value,selector,progress,interactive);LMVCCProgress(value,progress);}
static void LMVCCHookSignificant(id value,SEL selector,id overlay,double progress){LMVCCOrigSignificant(value,selector,overlay,progress);
    if(LMVLockVideoClass(overlay,@"CCUIModularControlCenterOverlayViewController"))LMVCCProgress(overlay,progress);
}
static void LMVCCInstallHooks(void) {
    Class cls=NSClassFromString(@"CCUIModularControlCenterOverlayViewController");
    if(!cls || ![cls isSubclassOfClass:UIViewController.class])return;
    const char *boolean[]={@encode(BOOL)},*object[]={@encode(id)},*progress[]={@encode(double)},*interactive[]={@encode(double),@encode(BOOL)},*significant[]={@encode(id),@encode(double)};
#define LMV_CC_INSTALL(target,name,types,count,callback,original) do { \
    SEL selector=NSSelectorFromString(name); \
    if(LMVCCHookMatches(target,selector,types,count))MSHookMessageEx(target,selector,(IMP)callback,(IMP *)&original); \
} while(0)
    LMV_CC_INSTALL(cls,@"viewDidLoad",NULL,0,LMVCCHookLoad,LMVCCOrigLoad);
    LMV_CC_INSTALL(cls,@"viewDidLayoutSubviews",NULL,0,LMVCCHookLayout,LMVCCOrigLayout);
    LMV_CC_INSTALL(cls,@"viewWillAppear:",boolean,1,LMVCCHookWillAppear,LMVCCOrigWillAppear);
    LMV_CC_INSTALL(cls,@"viewDidAppear:",boolean,1,LMVCCHookDidAppear,LMVCCOrigDidAppear);
    LMV_CC_INSTALL(cls,@"viewWillDisappear:",boolean,1,LMVCCHookWillDisappear,LMVCCOrigWillDisappear);
    LMV_CC_INSTALL(cls,@"viewDidDisappear:",boolean,1,LMVCCHookDidDisappear,LMVCCOrigDidDisappear);
    LMV_CC_INSTALL(cls,@"traitCollectionDidChange:",object,1,LMVCCHookTrait,LMVCCOrigTrait);
    LMV_CC_INSTALL(cls,@"setTransitionProgress:",progress,1,LMVCCHookProgress,LMVCCOrigProgress);
    LMV_CC_INSTALL(cls,@"setTransitionProgress:interactive:",interactive,2,LMVCCHookInteractive,LMVCCOrigInteractive);
    LMV_CC_INSTALL(cls,@"_setTransitionProgress:interactive:",interactive,2,LMVCCHookPrivateInteractive,LMVCCOrigPrivateInteractive);
    Class owner=NSClassFromString(@"SBControlCenterController");
    if(owner)LMV_CC_INSTALL(owner,@"controlCenterViewController:significantPresentationProgressChange:",significant,2,LMVCCHookSignificant,LMVCCOrigSignificant);
#undef LMV_CC_INSTALL
}

// 1.13: publish the Control Center presentation to the Desktop probe. The CC
// module knows the content is gone as soon as its material/geometry leaves,
// which is up to 0.74 s before the SBControlCenterWindow itself disappears.
static BOOL LMVCCDesktopPresentedBridge(void) {return LMVControlCenterVideo.presented;}
