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
// The Control Center backdrop, resolved from the on-device hierarchy dump:
//
//   UIView  layerName=VC:CCUIModularControlCenterOverlayViewController
//     MTMaterialView frame={{0,0},{430,932}} layer=MTMaterialLayer parent=UIView
//     CCUIScrollView frame={{0,0},{430,932}}
//
// The overlay view's direct child that is a full-screen MTMaterialView IS the
// backdrop. Matching on class + geometry + direct parenthood removes every guess
// the old scoring heuristic made, and it can never select a module card's own
// material view because those are small and nested far deeper.
static UIView *LMVCCMaterial(UIView *root) {
    if(!root || !LMVLockVideoRectValid(root.bounds))return nil;
    CGRect bounds=root.bounds;
    UIView *fallback=nil;
    for(UIView *child in root.subviews) {
        if(![child isKindOfClass:NSClassFromString(@"MTMaterialView")])continue;
        if(child.hidden || child.alpha<.01)continue;
        CGRect rect=[child convertRect:child.bounds toView:root];
        CGRect clipped=CGRectIntersection(rect,bounds);
        if(!LMVLockVideoRectValid(clipped))continue;
        CGFloat full=bounds.size.width*bounds.size.height;
        if(full<=0)continue;
        CGFloat ratio=(clipped.size.width*clipped.size.height)/full;
        // Full-window (within a sub-point inset) is the Control Center backdrop.
        if(ratio>=.98 && LMVCCPureBackground(child)) {
            if(child.superview==root)return child;   // direct child wins outright
            if(!fallback)fallback=child;
        }
    }
    if(fallback)return fallback;
    // Last resort: a bounded search for a full-window material view anywhere in
    // the overlay, still preferring the one closest to the root.
    NSUInteger budget=64;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];
    while(pending.count && budget) {
        --budget;UIView *view=pending.lastObject;[pending removeLastObject];
        if(view==root)continue;
        if(view.hidden || view.alpha<.01)continue;
        if([view isKindOfClass:NSClassFromString(@"MTMaterialView")]) {
            CGRect rect=[view convertRect:view.bounds toView:root];
            CGRect clipped=CGRectIntersection(rect,bounds);
            CGFloat full=bounds.size.width*bounds.size.height;
            if(full>0 && LMVLockVideoRectValid(clipped) &&
               (clipped.size.width*clipped.size.height)/full>=.90 && LMVCCPureBackground(view)) return view;
        }
        if(view.subviews.count<=24)[pending addObjectsFromArray:view.subviews];
    }
    return nil;
}
@interface LMVCCRecord:NSObject
@property(nonatomic) BOOL visible,closing,known,progressKnown;
@property(nonatomic) CGFloat progress;
@property(nonatomic) NSUInteger epoch;
@end
@implementation LMVCCRecord @end
static char LMVCCRecordKey;
static NSHashTable<UIViewController *> *LMVCCControllers;
@interface LMVControlCenterVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,weak) UIViewController *controller;
@property(nonatomic,weak) UIView *material;
@property(nonatomic,copy) NSString *darkPath,*lightPath,*path,*revision,*status;
@property(nonatomic) BOOL enabled,updating,suspended,presented;
@property(nonatomic) UIUserInterfaceStyle style;
@property(nonatomic) CFTimeInterval lastRevisionCheck;
@property(nonatomic,strong) NSTimer *timer;
- (void)refresh:(BOOL)reload;
- (void)update;
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
- (void)dealloc {[_timer invalidate];[_playback.renderLayer removeFromSuperlayer];}
- (void)refresh:(BOOL)reload {
    self.suspended=NO;
    if(reload) {
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("ControlCenterBackgroundEnabled"),kLMVPrefsID);
        self.enabled=[enabled respondsToSelector:@selector(boolValue)] && [enabled boolValue];
        self.darkPath=LMVCCSelectedPath(@"ControlCenterDarkVideo");self.lightPath=LMVCCSelectedPath(@"ControlCenterLightVideo");
    }
    [self update];
}- (void)suspend {
    self.suspended=YES;self.presented=NO;[self.playback setVisible:NO];[self.playback.renderLayer removeFromSuperlayer];
    self.material=nil;[self.timer invalidate];self.timer=nil;
}
- (void)update {
    if(self.updating || self.suspended)return;self.updating=YES;
    UIViewController *best=nil;UIView *material=nil;
    if(self.enabled && LMVLockVideoScreenAllowed())for(UIViewController *candidate in LMVCCControllers.allObjects) {
        LMVCCRecord *record=objc_getAssociatedObject(candidate,&LMVCCRecordKey);
        if(!record || !record.known || !record.visible)continue;
        UIView *root=candidate.viewIfLoaded;
        if(!root || !LMVDesktopGeometryVisible(root))continue;
        UIView *found=LMVCCMaterial(root);if(!found)continue;
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
    BOOL visible=best && material && path.length && revision.length;
    if(visible) {
        CALayer *parent=material.layer,*video=self.playback.renderLayer;
        [CATransaction begin];[CATransaction setDisableActions:YES];
        // 0.0.79 fix: the video layer is attached INSIDE the backdrop's own layer,
        // so it can only ever replace the backdrop itself and can never rise above
        // a sibling view's layer. Ordering therefore becomes a property of the tree
        // instead of a property of insertion timing.
        if(video.superlayer!=parent) { [video removeFromSuperlayer];[parent addSublayer:video]; }
        // Keep exactly one video layer per material view.
        for(CALayer *sibling in parent.sublayers) {
            if(sibling==video)continue;
            if([sibling.name isEqualToString:@"com.minis.lockmessagevideo.control-center.render"])
                [sibling removeFromSuperlayer];
        }
        [self.playback layoutInBounds:material.bounds];video.opacity=1;
        [CATransaction commit];self.material=material;
    } else { [self.playback.renderLayer removeFromSuperlayer];self.material=nil; }
    [self.playback setVisible:visible];
    // Track the presentation state so the next update can detect a hidden->visible
    // transition and re-seed the poster (see the 0.0.79 note above).
    self.presented=visible;
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
    NSString *status=[NSString stringWithFormat:@"control-center-video visible=%d enabled=%d presented=%d style=%ld selected=%d layer-ready=%d poster=%d material=%@ error=%ld",
        visible,self.enabled,self.presented,(long)style,path.length>0,self.playback.playerLayer.readyForDisplay,self.playback.posterLayer.contents!=nil,
        material?NSStringFromClass(material.class):@"none",(long)self.playback.error.code];
    if(![status isEqualToString:self.status]){self.status=status;LMVDiagnostic(status);}
    self.updating=NO;
}
@end
static void LMVCCRefresh(BOOL reload) {
    if(!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread)return;
    LMVCCDiscover();if(!LMVControlCenterVideo){LMVControlCenterVideo=[LMVControlCenterVideoManager new];reload=YES;}
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
static void LMVCCLifecycle(UIViewController *controller,NSInteger state) {
    LMVCCRecord *record=LMVCCTrack(controller);if(!record)return;
    // 1 appearing, 2 appeared, 3 closing, 0 fully disappeared, -1 layout.
    if(state==1 || state==2){record.known=YES;record.visible=YES;record.closing=NO;record.progress=.5;record.progressKnown=YES;record.epoch++;if(state==2){record.progress=1;}}
    if(state==3){record.closing=YES;record.epoch++;}
    if(state==0){record.known=YES;record.visible=NO;record.closing=NO;record.progress=0;record.progressKnown=YES;record.epoch++;}
    LMVRequestSafeUpdate();
}
static void LMVCCProgress(UIViewController *controller,CGFloat progress) {
    if(!isfinite(progress))return;
    LMVCCRecord *record=LMVCCTrack(controller);if(!record)return;
    record.progress=MAX(0,MIN(1,progress));record.progressKnown=YES;record.known=YES;
    NSUInteger epoch=++record.epoch;
    if(progress>.0001){record.visible=YES;record.closing=NO;LMVRequestSafeUpdate();return;}
    // A zero may be sent before willAppear during an interactive opening. Give
    // that lifecycle one main-queue turn; a later positive progress invalidates
    // this close. No arbitrary sleep and no mid-gesture decoder rebuild.
    __weak UIViewController *weakController=controller;
    dispatch_async(dispatch_get_main_queue(),^{
        UIViewController *live=weakController;LMVCCRecord *current=live?objc_getAssociatedObject(live,&LMVCCRecordKey):nil;
        if(!current || current.epoch!=epoch || current.progress>.0001)return;
        current.visible=NO;current.closing=NO;LMVRequestSafeUpdate();
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
static void LMVCCHookLayout(id value,SEL selector){LMVCCOrigLayout(value,selector);LMVCCLifecycle(value,-1);}
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
