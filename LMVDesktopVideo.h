#pragma once
// Included after LMVLockVideo.h: use its proven video-only playback class as a
// separate instance. No player/item/looper/position/poster is shared with Lock.
static BOOL LMVDesktopObjectGetter(id object,SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature=[object methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments==2 && !strcmp(signature.methodReturnType,@encode(id));
}
static id LMVDesktopGet(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    return LMVDesktopObjectGetter(object,selector)?((id(*)(id,SEL))objc_msgSend)(object,selector):nil;
}
static BOOL LMVDesktopWallpaperClass(UIView *view) {
    if (![view isKindOfClass:UIView.class]) return NO;
    NSString *name=NSStringFromClass(view.class);
    return (LMVLockVideoClass(view,@"SBFWallpaperView") || [name containsString:@"WallpaperView"]) &&
        ![name containsString:@"Effect"] && ![name containsString:@"Snapshot"] && ![name containsString:@"Lock"];
}
static BOOL LMVDesktopPureContent(UIView *view,UIView *own) {
    if (!view || [view isKindOfClass:UIWindow.class]) return NO;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:view];NSUInteger budget=128;
    while (pending.count && budget) {
        --budget;UIView *node=pending.lastObject;[pending removeLastObject];if(node==own)continue;
        if (LMVLockVideoForeground(node)) return NO;
        NSString *name=NSStringFromClass(node.class);
        for (NSString *word in @[@"Icon",@"Dock",@"HomeScreen",@"CoverSheet",@"ControlCenter"])
            if ([name containsString:word]) return NO;
        if (node.gestureRecognizers.count || node.subviews.count>32) return NO;
        [pending addObjectsFromArray:node.subviews];
    }
    return !pending.count;
}
static BOOL LMVDesktopHomeWindow(UIWindow *window) {
    return LMVLockVideoClass(window,@"SBHomeScreenWindow") && window.screen==UIScreen.mainScreen;
}
static BOOL LMVDesktopGeometryVisible(UIView *view) {
    UIWindow *window=view.window;
    if (!window || window.hidden || window.alpha<.01 || !LMVLockVideoRectValid(view.bounds)) return NO;
    for (UIView *node=view;node;node=node.superview) if (node.hidden || node.alpha<.01) return NO;
    return !CGRectIsEmpty(LMVLockVideoVisibleRect(view,window));
}
// 1 = existing SpringBoard/Home evidence; -1 = application; 0 = unavailable.
// Only use the existing UIApplication publisher, never create a private manager.
static NSInteger LMVDesktopForeground(void) {
    UIApplication *app=UIApplication.sharedApplication;
    BOOL observed=NO,unknownObject=NO;
    for (NSString *name in @[@"_frontmostApplication",@"_accessibilityFrontMostApplication"]) {
        SEL selector=NSSelectorFromString(name);if(!LMVDesktopObjectGetter(app,selector))continue;
        observed=YES;id object=((id(*)(id,SEL))objc_msgSend)(app,selector);if(!object)continue;
        id bundle=LMVDesktopGet(object,@"bundleIdentifier");
        if ([bundle isKindOfClass:NSString.class] && [bundle length]) return [bundle isEqualToString:@"com.apple.springboard"]?1:-1;
        unknownObject=YES;
    }
    return observed && !unknownObject?1:0;
}
@interface LMVDesktopControllerRecord:NSObject
@property(nonatomic) BOOL known,visible;
@property(nonatomic,weak) UIView *root;
@end
@implementation LMVDesktopControllerRecord @end
static char LMVDesktopControllerRecordKey;
static NSHashTable<UIViewController *> *LMVDesktopControllers;
static __weak id LMVDesktopWallpaperController;
static __weak UIView *LMVDesktopExplicitWallpaper;
// A loader initializer is not UIKit readiness. Only an already initialized,
// attached Home view or the launch notification can open this UI creation gate.
static BOOL LMVDesktopUIAvailable,LMVDesktopCreatingManager;
@class LMVDesktopPosterSeed;
static LMVDesktopPosterSeed *LMVDesktopSeed;
static void LMVDesktopVideoRefresh(BOOL reload);
static void LMVDesktopVideoSuspend(void);

@interface LMVDesktopVideoHost:UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@end
@implementation LMVDesktopVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;
        self.accessibilityElementsHidden=YES;self.opaque=NO;self.clipsToBounds=YES;self.backgroundColor=UIColor.clearColor;}
    return self;
}
- (void)setFrame:(CGRect)frame {
    if(self.superview && !LMVLockVideoRectValid(frame) && LMVLockVideoRectValid(self.frame))return;
    [super setFrame:frame];
}
- (void)setBounds:(CGRect)bounds {
    if(self.superview && !LMVLockVideoRectValid(bounds) && LMVLockVideoRectValid(self.bounds))return;
    [super setBounds:bounds];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // UIKit can deliver zero bounds between reparent/layout transactions. Do
    // not collapse the retained render surface; the next valid layout repairs it.
    if(LMVLockVideoRectValid(self.bounds) && !CGRectEqualToRect(self.playback.renderLayer.frame,self.bounds))
        [self.playback layoutInBounds:self.bounds];
}
@end
// Mirror the reference's contentView hiding only for an explicit Home target.
// Backing layers always stay attached; only restore an attribute we own.
@interface LMVDesktopContentLease:NSObject
@property(nonatomic,weak) UIView *content,*parent;
@property(nonatomic) BOOL baselineHidden,applied;
- (void)restore;
@end
@implementation LMVDesktopContentLease
- (void)restore {
    UIView *content=self.content;
    if (self.applied && content && content.hidden) content.hidden=self.baselineHidden;
    self.applied=NO;
}
- (void)dealloc {[self restore];}
@end
@interface LMVDesktopVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVDesktopVideoHost *host;
@property(nonatomic,strong) LMVDesktopContentLease *lease;
@property(nonatomic,weak) UIView *container,*attachedContent,*explicitSource;
@property(nonatomic,weak) UIWindow *attachmentWindow,*explicitWindow;
@property(nonatomic,weak) UIViewController *attachmentController;
@property(nonatomic) BOOL wallpaperAttachment;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) NSString *path,*revision,*status,*earlyPosterAttempt,*coverage,*windowListStatus;
@property(nonatomic) BOOL enabled,updating,authenticatedSession,suspended;
@property(nonatomic) CFTimeInterval lastRevisionCheck,lastDiscovery;
// 0.0.97: how long the surface has been held (attached, frozen) through a
// transient loss of visibility, and how many real teardowns have happened. Both
// are diagnostics for the "hitches when opening/leaving an app" report.
@property(nonatomic) CFTimeInterval holdSince;
// 0.0.124: how long the desktop has been BOTH fully covered by an opaque surface
// and not flagged as foreground. While that holds, compositing the video layer is
// pure waste; the short grace absorbs the app-launch transition, during which the
// cover probe flaps for a frame or two.
@property(nonatomic) CFTimeInterval coveredSince;
// 0.0.133: anything covering the desktop (app, switcher, Control Center,
// notification sheet). Gates the Desktop AUDIO channel - the video may keep
// playing under a translucent sheet at fg==1, but the sound follows the cover,
// not the player state.
@property(nonatomic) BOOL coveredNow;
// 0.0.137: the FULL notification pull restored the wallpaper on purpose - the
// suppress-lease must NOT be re-acquired while the sheet stays fully up, or
// the same update would undo the restore (the lease block runs right after
// the freeze branch). Cleared as soon as the sheet slides back.
@property(nonatomic) BOOL sheetWallpaperShown;
// 0.0.138: a sheet that was ALREADY up when the desktop became visible is the
// unlock/withdrawal case - the warm video must bind there (waiting for the sheet
// to clear flashes the wallpaper). Only a sheet the user pulled down onto an
// already-visible desktop shows the original wallpaper.
@property(nonatomic) BOOL sheetPreexisting;
@property(nonatomic) NSUInteger teardowns;
// 0.0.128: while the video layer is hidden behind an opaque app, updates only
// run on the ~0.4 s hook/tick cadence - the exit cross-fade could therefore
// show the visible wallpaper content through the fading app for up to a full
// tick (the reported occasional flash). This watcher runs ONLY while the layer
// is hidden and re-checks the cheap cover geometry every frame; the moment the
// fade starts revealing the desktop it requests one full update, so the layer
// is back within ~16 ms - imperceptible.
@property(nonatomic,strong) CADisplayLink *coverWatch;
- (void)refresh:(BOOL)reload;
- (void)primePoster;
- (void)update;
- (void)syncGeometry;
- (void)suspend;
// 0.0.128: per-frame cover watcher active only while the layer is hidden.
- (void)startCoverWatch;
- (void)stopCoverWatch;
- (void)coverWatchTick:(CADisplayLink *)link;
@end
static LMVDesktopVideoManager *LMVDesktopVideo;
static BOOL LMVDesktopUpdatePending;
// 0.0.131: wired by Tweak.xm to LMVAudioPauseTarget(@"Desktop"). The freeze is
// applied on this manager's update tick, but the audio sync runs on its own
// 10 Hz timer - without the hook the desktop sound kept playing for up to half
// a second after an app covered the desktop.
static void (^LMVDesktopAudioPauseHook)(void);
// 0.0.135: fired when coveredNow FLIPS - covered=YES pauses the Desktop channel
// the instant anything covers the desktop, covered=NO resumes it the instant
// the cover leaves (the wiring seeks to the video player's current time). The
// 10 Hz audio sync alone added up to one timer beat to both directions.
static void (^LMVDesktopAudioCoverHook)(BOOL covered);
static void LMVDesktopRequestUpdate(void) {
    if(!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread || LMVDesktopUpdatePending)return;
    LMVDesktopUpdatePending=YES;
    dispatch_async(dispatch_get_main_queue(),^{
        LMVDesktopUpdatePending=NO;
        if(!LMVInitialized || !LMVLaunchReady)return;
        // Desktop-only policy; no card/presenter/CC/source refresh cascade.
        if(LMVDesktopVideo)[LMVDesktopVideo update];else LMVDesktopVideoRefresh(NO);
    });
}

static NSString *LMVDesktopSelectedPath(void) {
    id stored=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("DesktopVideo"),kLMVPrefsID);
    if (![stored isKindOfClass:NSString.class]) return nil;NSString *relative=stored;
    if (!relative.length || [relative hasPrefix:@"/"] || [relative.pathComponents containsObject:@".."] || [relative.pathComponents containsObject:@"."]) return nil;
    NSString *path=[[LMVDirectory stringByAppendingPathComponent:relative] stringByStandardizingPath];
    NSString *prefix=[LMVDirectory stringByAppendingString:@"/"];
    return [path hasPrefix:prefix] && [path.stringByResolvingSymlinksInPath hasPrefix:prefix]?path:nil;
}
// Foundation/ImageIO state only. This object may be created by the dylib
// initializer: it must not own a view, layer, player or screen object.
@interface LMVDesktopPosterSeed:NSObject
@property(nonatomic,copy) NSString *path,*revision;
@property(nonatomic,assign) CGImageRef image;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL primed;
@end
@implementation LMVDesktopPosterSeed
- (void)setImage:(CGImageRef)image {
    CGImageRef held=image?CGImageRetain(image):NULL;
    if(_image)CGImageRelease(_image);_image=held;
}
- (void)dealloc {if(_image)CGImageRelease(_image);}
@end
static UIView *LMVDesktopWallpaperContent(UIView *wallpaper) {
    if (!LMVDesktopWallpaperClass(wallpaper)) return nil;
    UIView *content=LMVLockVideoObjectView(wallpaper,@"contentView",wallpaper);
    return content && content.superview==wallpaper && LMVDesktopPureContent(content,nil)?content:nil;
}
static void LMVDesktopDiscover(void) {
    if (!LMVDesktopControllers) LMVDesktopControllers=[NSHashTable weakObjectsHashTable];
    NSUInteger budget=160;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.screen!=UIScreen.mainScreen || LMVLockVideoClass(window,@"SBCoverSheetWindow")) continue;
            NSMutableArray *pending=[NSMutableArray new];if(window.rootViewController)[pending addObject:window.rootViewController];
            while (pending.count && budget) {
                --budget;UIViewController *controller=pending.lastObject;[pending removeLastObject];
                if (LMVLockVideoClass(controller,@"SBHomeScreenViewController") || LMVLockVideoClass(controller,@"SBIconController") ||
                    LMVLockVideoClass(controller,@"PBUIPosterHomeViewController")) [LMVDesktopControllers addObject:controller];
                [pending addObjectsFromArray:controller.childViewControllers];
                if (controller.presentedViewController) [pending addObject:controller.presentedViewController];
            }
        }
    }
    // Read only an already captured controller; sharedInstance is NOT called by
    // a hook or refresh, avoiding recursive wallpaper singleton construction.
    id controller=LMVDesktopWallpaperController;
    if (!controller) {LMVDesktopExplicitWallpaper=nil;return;}
    LMVDesktopExplicitWallpaper=nil;
    id nested=LMVDesktopGet(controller,@"_wallpaperViewController");
    for (id object in @[nested ?: NSNull.null,controller ?: NSNull.null]) {
        id candidate=LMVDesktopGet(object,@"homescreenWallpaperView");
        if ([candidate isKindOfClass:UIView.class] && LMVDesktopWallpaperClass(candidate) && !LMVLockVideoClass(((UIView *)candidate).window,@"SBCoverSheetWindow")) {
            id lock=LMVDesktopGet(object,@"lockscreenWallpaperView");
            if (lock==candidate) continue; // A shared Lock/Home view is not a Home-only target.
            LMVDesktopExplicitWallpaper=candidate;return;
        }
    }
}
static CGRect LMVDesktopCoverRect(UIWindow *destination,BOOL *unknown,BOOL *appWindowCover,BOOL *switcherCover,BOOL *ccCover,BOOL *sheetCover) {
    CGRect combined=CGRectZero;*unknown=NO;*appWindowCover=NO;*switcherCover=NO;*ccCover=NO;*sheetCover=NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.screen!=destination.screen || window.hidden || window.alpha<.01) continue;
            NSString *name=NSStringFromClass(window.class);
            if (LMVLockVideoClass(window,@"SBControlCenterWindow")) {
                // 0.0.130: the Control Center sheet is probed EXACTLY, by class -
                // a 0.0.129 attempt at a generalized "any full-screen root is a
                // sheet" probe froze the desktop video for good, because real
                // SpringBoards carry PERMANENTLY visible full-screen windows
                // (UITextEffectsWindow, the SystemAperture host, Myrtle / Snapper /
                // FloatingView panels - see the desktop-windows diagnostic). The
                // CC window disappears from the list while closed (window goes
                // hidden), and while open its ROOT slides in and out - the same
                // semantics the floating ball's CC probe has used on device.
                // Closed: window hidden -> skipped. Open: root frame on screen ->
                // sheet cover -> freeze under the blur (never hide, fg==1).
                UIView *root=window.rootViewController.viewIfLoaded;
                if (!root || root.hidden || root.alpha<.01) continue;
                // 0.0.132: a FADING Control Center window is closing - the root
                // stays full-screen through the fade, so without this gate the
                // cover (and the freeze) outlived the visible sheet by the whole
                // fade and the resume waited for the next update tick.
                if (window.alpha<0.99) continue;
                CALayer *rootPresentation=root.layer.presentationLayer;
                if (rootPresentation && rootPresentation.opacity<0.99) continue;
                CGRect rect=rootPresentation?rootPresentation.frame:root.frame;
                if (!LMVLockVideoRectValid(rect)) continue;
                CGRect converted=CGRectIntersection([window convertRect:rect toWindow:destination],destination.bounds);
                if (!LMVLockVideoRectValid(converted)) continue;
                CGFloat area=converted.size.width*converted.size.height,
                    full=destination.bounds.size.width*destination.bounds.size.height;
                if (full<=0 || area/full<0.9) continue;
                combined=CGRectIsEmpty(combined)?converted:CGRectUnion(combined,converted);
                *ccCover=YES;
                continue;
            }
            if (!LMVLockVideoClass(window,@"SBCoverSheetWindow")) {
                // 0.0.125: the old probe only ever saw CoverSheet windows, so the
                // COMMON case of a covered desktop - a foreground application - was
                // invisible to it: the video kept compositing AND decoding behind
                // the app for as long as it stayed open, which is the backboardd
                // CPU burn. Whitelist only window classes that are always fully
                // opaque and always sit above Home (app / app-switcher); every
                // other class (status bar, snapshots, this tweak's own floating
                // surfaces, keyboard, tweak panels) stays excluded, so a small or
                // translucent surface can never hide the desktop on its own.
                // Reachability is still safe: a shrunk app window no longer covers
                // the Home rect. Conversion failures are skipped SILENTLY (never
                // *unknown=YES - that tears the desktop down and flashes the
                // wallpaper). 0.0.129: no generalized probe - permanent full-screen
                // tweak/system windows made it freeze the desktop for good.
                if (window==destination || LMVDesktopHomeWindow(window) ||
                    (![name containsString:@"AppWindow"] && ![name containsString:@"Switcher"])) continue;
                // 0.0.126: measure the ANIMATED frame - the model frame stays
                // full-screen for the whole open/close zoom.
                // 0.0.127: a FADING app window is already revealing the desktop.
                // Device log: the exit cross-fade keeps the window model frame
                // full-screen until removal (~1.2 s), so the frozen video layer
                // stayed hidden behind a translucent app - the visible wallpaper
                // content showed through and read as a wallpaper flash, and the
                // player stayed paused until the window was finally removed.
                // Presentation opacity < 0.99 (or a model alpha mid-fade) means
                // the desktop is being revealed: the window is NOT a cover.
                CALayer *presentation=window.layer.presentationLayer;
                if ((presentation && presentation.opacity<0.99) || window.alpha<0.99) continue;
                CGRect converted=[window convertRect:(presentation?presentation.frame:window.frame) toWindow:destination];
                if (!LMVLockVideoRectValid(converted)) continue;
                if (!CGRectIsEmpty(converted)) {
                    combined=CGRectIsEmpty(combined)?converted:CGRectUnion(combined,converted);
                    // 0.0.132: the app switcher is NOT an app exit - covering the
                    // desktop with the switcher is "the desktop went into the
                    // background": the video must freeze and the audio must stop,
                    // exactly like an app cover. Only a REAL app window keeps the
                    // 0.0.127 exit-transition play rule.
                    if ([name containsString:@"Switcher"]) *switcherCover=YES;
                    else *appWindowCover=YES;
                }
                continue;
            }
            UIView *content=LMVLockVideoContent(window);
            if (!content) {*unknown=YES;continue;}
            CGRect rect=LMVLockVideoVisibleRect(content,window);if(CGRectIsEmpty(rect))continue;
            CGRect converted=[window convertRect:rect toWindow:destination];
            // 0.0.137: a transient invalid rect (the geometry flaps for a frame
            // during the app -> switcher transition) is skipped SILENTLY. Only a
            // genuinely missing content view sets *unknown (fail closed).
            if (!LMVLockVideoRectValid(converted)) continue;
            if (!CGRectIsEmpty(converted)) {combined=CGRectIsEmpty(combined)?converted:CGRectUnion(combined,converted);*sheetCover=YES;}
        }
    }
    return combined;
}
// 0.0.138: the switcher and the Control Center are detected through
// SpringBoard's OWN state, not only through window class names - on the user's
// device the window classes did not match, so neither the video nor the audio
// paused while the switcher/CC was up. Every call is guarded: a missing class
// or selector simply reports NO and the window probe stays the fallback.
static id LMVDesktopSharedInstance(NSString *className) {
    Class cls=NSClassFromString(className); if (!cls) return nil;
    for (NSString *name in @[@"sharedInstance",@"sharedInstanceIfExists",@"sharedInstanceCoordinatorIfExists"]) {
        SEL selector=NSSelectorFromString(name);
        if ([cls respondsToSelector:selector]) return ((id(*)(id,SEL))objc_msgSend)(cls,selector);
    }
    return nil;
}
static BOOL LMVDesktopBoolSelector(id object,NSString *selectorName) {
    if (!object) return NO;
    SEL selector=NSSelectorFromString(selectorName);
    if (![object respondsToSelector:selector]) return NO;
    return ((BOOL(*)(id,SEL))objc_msgSend)(object,selector);
}
static BOOL LMVDesktopSwitcherPresented(void) {
    for (NSString *className in @[@"SBMainSwitcherControllerCoordinator",@"SBAppSwitcherController"]) {
        id shared=LMVDesktopSharedInstance(className);
        if (LMVDesktopBoolSelector(shared,@"isAnySwitcherVisible") ||
            LMVDesktopBoolSelector(shared,@"isSwitcherVisible")) return YES;
    }
    return NO;
}
static BOOL LMVDesktopControlCenterPresented(void) {
    id shared=LMVDesktopSharedInstance(@"SBControlCenterController");
    return LMVDesktopBoolSelector(shared,@"isVisible") || LMVDesktopBoolSelector(shared,@"isPresented");
}
static BOOL LMVDesktopFullyCovered(UIView *view,CGRect cover) {
    CGRect target=LMVLockVideoVisibleRect(view,view.window);if(CGRectIsEmpty(target))return YES;
    CGRect overlap=CGRectIntersection(target,cover);
    return LMVLockVideoRectValid(overlap) && overlap.size.width>=target.size.width-1 && overlap.size.height>=target.size.height-1;
}
static BOOL LMVDesktopControllerEligible(UIViewController *controller) {
    UIView *root=controller.viewIfLoaded;
    if (!root || !LMVDesktopGeometryVisible(root)) return NO;
    LMVDesktopControllerRecord *record=objc_getAssociatedObject(controller,&LMVDesktopControllerRecordKey);
    if (record.known && !record.visible) return NO;
    if (LMVLockVideoClass(controller,@"PBUIPosterHomeViewController")) {
        // Exact controller identity supplies the Home variant; no anonymous
        // shared wallpaper window root or Lock branch can become a candidate.
        return LMVDesktopPureContent(root,nil);
    }
    return LMVDesktopHomeWindow(root.window);
}
static NSString *LMVDesktopVideoPerf(const char *channel,CFTimeInterval seconds) {
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
// Retention is not discovery: only an exact, still-attached Home ownership
// acquired while visible may survive a lifecycle/geometry transition.
static BOOL LMVDesktopOwnedAttachment(LMVDesktopVideoManager *manager) {
    UIView *container=manager.container;UIWindow *window=container.window;
    if(!container || manager.host.superview!=container || !window || window.screen!=UIScreen.mainScreen ||
       LMVLockVideoClass(window,@"SBCoverSheetWindow"))return NO;
    if(manager.wallpaperAttachment) {
        if((window!=manager.attachmentWindow && !LMVDesktopHomeWindow(window)) || LMVDesktopExplicitWallpaper!=container ||
           LMVDesktopWallpaperContent(container)!=manager.attachedContent)return NO;
    } else {
        UIViewController *owner=manager.attachmentController;
        if(!owner || owner.viewIfLoaded!=container)return NO;
        if(LMVLockVideoClass(owner,@"PBUIPosterHomeViewController")) {
            if(window!=manager.attachmentWindow || !LMVDesktopPureContent(container,manager.host))return NO;
        } else if(!LMVDesktopHomeWindow(window))return NO;
    }
    return !manager.lease || (manager.lease.parent==container && manager.lease.content==manager.attachedContent &&
        manager.lease.content.superview==container);
}
@implementation LMVDesktopVideoManager
- (instancetype)init {
    if (!NSThread.isMainThread || (!LMVLaunchReady && !LMVDesktopUIAvailable)) return nil;
    if ((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=YES;
        _host=[[LMVDesktopVideoHost alloc] initWithFrame:CGRectZero];
        _host.playback=_playback;_playback.renderLayer.name=@"com.minis.lockmessagevideo.desktop.render";
        _playback.renderLayer.backgroundColor=UIColor.blackColor.CGColor;[_host.layer addSublayer:_playback.renderLayer];
        __weak typeof(self) weakSelf=self;
        _playback.didChange=^{LMVDesktopVideoManager *live=weakSelf;if(live && !live.updating && !live.suspended)LMVDesktopRequestUpdate();};
    }
    return self;
}
- (void)dealloc {[_timer invalidate];[_coverWatch invalidate];[_lease restore];[_host removeFromSuperview];}
- (void)syncGeometry {
    if(self.updating || self.suspended || self.host.hidden || self.host.superview!=self.container)return;
    UIView *container=self.container;if(!container || !LMVLockVideoRectValid(container.bounds))return;
    // Already-owned local repair only. Never discover windows/scan pure-content
    // trees, change playback intent or enqueue global refresh from layout.
    if(!CGRectEqualToRect(self.host.frame,container.bounds)) {
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.host.frame=container.bounds;[self.playback layoutInBounds:self.host.bounds];
        [CATransaction commit];
    }
    UIView *held=self.lease.content;
    if(self.lease.parent==container && held.superview==container && self.lease.applied &&
       !self.lease.baselineHidden && !held.hidden)held.hidden=YES;
}
- (void)primePoster {
    id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("DesktopBackgroundEnabled"),kLMVPrefsID);
    // 0.0.114: master switch, inline (see LMVLockVideo.h).
    id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
    BOOL globalOn=![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue];
    self.enabled=globalOn && [enabled respondsToSelector:@selector(boolValue)] && [enabled boolValue];
    NSString *path=self.enabled?LMVDesktopSelectedPath():nil,*revision=LMVLockVideoRevision(path);
    if ((self.path || path) && (![self.path isEqualToString:path] || ![self.revision isEqualToString:revision])) {
        [self.lease restore];self.lease=nil;[self.playback clear];self.earlyPosterAttempt=nil;
    }
    self.path=path;self.revision=revision;
    [self.playback preparePosterForPath:path revision:revision];
    // The initializer may have pre-read a still image without constructing UI.
    // Adopt it only after this manager passes the attached-Home/launch gate.
    LMVDesktopPosterSeed *seed=LMVDesktopSeed;
    if (seed.image && [seed.path isEqualToString:path] && [seed.revision isEqualToString:revision]) {
        [self.playback applyPreparedPoster:seed.image path:path revision:revision];
        seed.image=NULL;
    }
}
- (void)refresh:(BOOL)reload {
    self.suspended=NO;
    if (reload) {
        [self primePoster];
        self.lastRevisionCheck=CACurrentMediaTime();[self.playback selectPath:self.path revision:self.revision];
    }
    if (self.enabled && self.path.length && !self.timer) {
        __weak typeof(self) weakSelf=self;
        self.timer=[NSTimer timerWithTimeInterval:.2 repeats:YES block:^(NSTimer *timer){
            LMVDesktopVideoManager *live=weakSelf;if(!live)return;
            CFTimeInterval now=CACurrentMediaTime();
            if (now-live.lastRevisionCheck>=1) {live.lastRevisionCheck=now;NSString *revision=LMVLockVideoRevision(live.path);
                if((revision || live.revision) && ![revision isEqualToString:live.revision]) {live.revision=revision;[live.playback selectPath:live.path revision:revision];}}
            if(now-live.lastDiscovery>=1){live.lastDiscovery=now;LMVDesktopDiscover();}
            [live update];
        }];[NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    } else if (!self.enabled || !self.path.length) {[self.timer invalidate];self.timer=nil;}
    [self update];
}
- (void)suspend {
    self.suspended=YES;[self.playback setVisible:NO];self.host.hidden=YES;
    [self.lease restore];self.lease=nil;[self.timer invalidate];self.timer=nil;
    [self stopCoverWatch];
    // 0.0.138: the suspended updates never reach the sheet classification, so
    // forget it here - the next update after a wake with the CoverSheet still
    // up must classify that sheet as pre-existing (the warm video binds and the
    // unlock does not flash the wallpaper).
    self.sheetPreexisting=NO;self.sheetWallpaperShown=NO;
}
// 0.0.128: see the coverWatch property. The tick deliberately repeats only the
// CHEAP half of -update (window enumeration + geometry + frontmost probe); the
// moment the reveal starts it hands over to one full update.
- (void)startCoverWatch {
    if (self.coverWatch || self.suspended || !LMVLaunchReady) return;
    self.coverWatch=[CADisplayLink displayLinkWithTarget:self selector:@selector(coverWatchTick:)];
    [self.coverWatch addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)stopCoverWatch {
    [self.coverWatch invalidate];self.coverWatch=nil;
}
- (void)coverWatchTick:(CADisplayLink *)link {
    if (self.suspended || self.host.superview==nil || self.container==nil) {[self stopCoverWatch];return;}
    BOOL unknown=NO,appCover=NO,switcherCover=NO,ccCover=NO,sheetCover=NO;
    CGRect cover=LMVDesktopCoverRect(self.container.window,&unknown,&appCover,&switcherCover,&ccCover,&sheetCover);
    if (unknown) return;
    BOOL fullyCovered=LMVDesktopFullyCovered(self.container,cover);
    NSInteger fg=LMVDesktopForeground();
    BOOL presented=LMVDesktopSwitcherPresented()||LMVDesktopControlCenterPresented();
    if (self.host.hidden || self.playback.frozen) {
        // waiting for the visible state: fire the moment the cover drops OR the
        // switcher/CC stops being presented (whichever releases first), so the
        // resume is one frame instead of one update tick.
        if (fullyCovered && (presented || fg!=1)) return;
    } else {
        // playing: fire only when the video really must freeze - a presented
        // switcher/CC, or a FULL cover with no desktop evidence. A sheet that is
        // still being pulled is NOT a freeze (0.0.140), so it must not fire.
        if (!(presented || (fullyCovered && (fg!=1 || switcherCover || ccCover || sheetCover)))) return;
    }
    [self stopCoverWatch];
    LMVDiagnostic(@"desktop-video cover-watch-reveal");
    LMVDesktopRequestUpdate();
}
- (void)update {
    if (self.updating || self.suspended) return;self.updating=YES;
    BOOL diagnostics=LMVDiagnosticsEnabled.load();
    CFTimeInterval coverPerf0=diagnostics?CACurrentMediaTime():0;
    uint64_t blank=1,locked=1;
    BOOL screenKnown=LMVBlankToken>=0 && notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK;
    BOOL lockKnown=LMVLockToken>=0 && notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK;
    if (!screenKnown || blank || !lockKnown) self.authenticatedSession=NO;
    UIView *homeRoot=nil;UIViewController *poster=nil,*homeOwner=nil;BOOL homeConfirmed=NO;
    for (UIViewController *controller in LMVDesktopControllers.allObjects) {
        if (!LMVDesktopControllerEligible(controller))continue;
        if (LMVLockVideoClass(controller,@"PBUIPosterHomeViewController")) {poster=controller;continue;}
        LMVDesktopControllerRecord *record=objc_getAssociatedObject(controller,&LMVDesktopControllerRecordKey);
        if (record.known && record.visible) homeConfirmed=YES;
        if (!homeRoot || LMVLockVideoClass(controller,@"SBHomeScreenViewController")) {homeRoot=controller.viewIfLoaded;homeOwner=controller;}
    }
    UIView *wallpaper=LMVDesktopExplicitWallpaper;
    BOOL displacedWallpaper=wallpaper && wallpaper==self.explicitSource && wallpaper.window!=self.explicitWindow &&
        !LMVDesktopHomeWindow(wallpaper.window);
    if(displacedWallpaper)wallpaper=nil; // Do not reacquire the same background in an app window.
    UIView *content=wallpaper && LMVDesktopGeometryVisible(wallpaper)?LMVDesktopWallpaperContent(wallpaper):nil;
    BOOL wallpaperValid=content!=nil;
    if (LMVLockVideoClass(wallpaper.window,@"SBCoverSheetWindow")) {wallpaperValid=NO;content=nil;}
    UIView *container=wallpaperValid?wallpaper:(homeRoot ?: poster.viewIfLoaded);
    // Exact PBUIPosterHome identity is a PaperBoard-compatible alternative to
    // legacy SBFWallpaperView, with the same background-only scope requirement.
    if (!wallpaperValid && poster && LMVDesktopGeometryVisible(poster.viewIfLoaded)) {
        container=poster.viewIfLoaded;content=nil;
    }
    // A zero-size/hidden wallpaper during app landing is not evidence that the
    // fallback Home root replaced it. Keep the exact owned target and its lease;
    // only a real identity/content replacement may switch the host.
    if(!wallpaperValid && self.wallpaperAttachment && LMVDesktopOwnedAttachment(self)) {
        container=self.container;content=self.attachedContent;wallpaperValid=YES;
    }
    BOOL appWindowCover=NO,switcherCover=NO,ccCover=NO,sheetCover=NO;
    BOOL unknownCover=NO;CGRect cover=container?LMVDesktopCoverRect(container.window,&unknownCover,&appWindowCover,&switcherCover,&ccCover,&sheetCover):CGRectZero;
    NSInteger foreground=LMVDesktopForeground();
    // A fresh authenticated unlock is authoritative even while CoverSheet is
    // still withdrawing. Waiting for cover==empty makes Home's first exposed
    // transaction show the original wallpaper before the warm video attaches.
    if (screenKnown && !blank && lockKnown && !locked && !unknownCover &&
        (foreground==1 || homeConfirmed)) self.authenticatedSession=YES;
    BOOL covered=container && LMVDesktopFullyCovered(container,cover);
    // 0.0.138: SpringBoard's own presentation state, OR-ed with the geometry.
    // It is the authority for the switcher and the Control Center: while either
    // is presented the desktop is not what the user is looking at, so the video
    // freezes and the audio stops even when no covering window matched.
    BOOL switcherPresented=LMVDesktopSwitcherPresented();
    BOOL ccPresented=LMVDesktopControlCenterPresented();
    // 0.0.123: opening an app made the desktop video fall back to the system
    // wallpaper for a moment. `home=1` (the Home view is still on screen) held
    // steady while `foreground` flipped to -1 for the launch, so `env` dropped and
    // the surface was torn down to its poster. A confirmed Home view is DIRECT
    // evidence that the desktop is on display - the frontmost probe is only
    // circumstantial and must not be able to veto it. `foreground>=0` was
    // redundant on top of `(foreground==1 || homeConfirmed)` and turned a
    // transient probe reading into a visible teardown.
    BOOL environment=screenKnown && !blank && lockKnown && self.authenticatedSession &&
        (foreground==1 || homeConfirmed) && !unknownCover;
    BOOL configured=self.enabled && self.path.length && self.revision.length;
    LMVDesktopControllerRecord *ownerRecord=objc_getAssociatedObject(self.attachmentController,&LMVDesktopControllerRecordKey);
    BOOL lifecycleAway=!locked && container==self.container && ownerRecord.known && !ownerRecord.visible;
    BOOL visible=configured && !self.playback.error && !lifecycleAway && container && LMVDesktopGeometryVisible(container) && environment;
    // A currently locked state outside an authenticated NC pull is a real lock.
    if (locked && CGRectIsEmpty(cover))visible=NO;
    // 0.0.91: an application reaching the foreground must NOT tear the surface
    // down. Removing it at that instant dropped the lease and the layer, so the
    // whole app-launch transition showed the static system wallpaper. Keep the
    // surface and the last displayed frame where they are and freeze instead;
    // every app window sits above the Home/wallpaper window, so a frozen frame
    // stays hidden and a paused player costs nothing.
    // 0.0.97: hold for ANY transient loss of visibility, not only a clean -1.
    // While an app is being launched or left, the frontmost-application probe can
    // report 0 (unavailable) for a frame and the Home geometry flaps while the app
    // window animates away. The old test tore the surface down at that instant,
    // restored the wallpaper and re-attached a frame later -- the visible hitch on
    // "quickly open an app, then leave it". Definitive reasons (screen off, locked,
    // unknown cover, feature off, decode error) still tear down immediately.
    // 0.0.137: a GENUINE unknown cover (the CoverSheet has no content to
    // measure) still fails closed. What no longer tears the desktop down is a
    // transient geometry flap: the CoverSheet conversion dropping invalid for a
    // frame during the in-app swipe-up used to restore the wallpaper lease, and
    // the original wallpaper showed through the translucent switcher - the
    // reported leak. That case is now a silent skip in the probe.
    BOOL definitiveAway=!configured || !screenKnown || blank || !lockKnown || locked ||
        unknownCover || self.playback.error!=nil;
    CFTimeInterval holdNow=CACurrentMediaTime();
    if (!visible && self.host.superview!=nil && !definitiveAway) {
        if (self.holdSince<=0) self.holdSince=holdNow;
    } else self.holdSince=0;
    // 0.0.124: geometry proof that an opaque surface really covers the desktop.
    // `foreground!=1` is required as well, so a noisy frontmost probe alone can
    // never drive this, and `covered` alone (which flaps during an app launch)
    // cannot either - both must hold for the whole grace period.
    // 0.0.137: the switcher, the Control Center and the notification sheet hide
    // the layer at fg==1 too (the user asked for freeze+HIDE). Hiding behind a
    // translucent surface is safe now: the suppress-lease STAYS applied while
    // the layer is hidden, so the wallpaper content can never show through the
    // blur - only the full notification pull restores it on purpose.
    if (covered && (foreground!=1 || switcherCover || ccCover || sheetCover)) {
        if (self.coveredSince<=0) self.coveredSince=holdNow;
    }
    else self.coveredSince=0;
    BOOL opaqueCover=covered && self.coveredSince>0 && holdNow-self.coveredSince>=0.3;
    BOOL retainedAttachment=LMVDesktopOwnedAttachment(self);
    // An owned explicit wallpaper moved to an unrelated window is not a new
    // acquisition. Home-root reparenting is permitted only to another real Home.
    if(container==self.container && self.wallpaperAttachment && container.window!=self.attachmentWindow &&
       !LMVDesktopHomeWindow(container.window))visible=NO;
    // The existing Home-only attachment is the scope proof. A fixed 0.6 s
    // expiry could restore the wallpaper before a long app-return/Reachability
    // transition finished. Hold it paused until exposure returns or a definitive
    // teardown occurs; do not acquire a new host while this evidence is missing.
    // 0.0.138: while a cover or a SpringBoard presentation is up, the surface is
    // only HIDDEN, never torn down - a teardown restores the wallpaper lease and
    // the original wallpaper showed through the translucent switcher (the
    // reported leak). The switcher/CC/NC states are all "the desktop is behind
    // something", not "the desktop is gone".
    BOOL appForeground=!definitiveAway && !visible &&
        (retainedAttachment || switcherPresented || ccPresented || sheetCover);
    BOOL attachedBefore= self.host.superview!=nil;
    if (visible) {
        if (self.container!=container || (self.lease && self.lease.content!=content)) {
            [self.lease restore];self.lease=nil;[self.host removeFromSuperview];
        }
        self.container=container;self.attachedContent=content;self.attachmentWindow=container.window;
        if(wallpaperValid){self.explicitSource=container;self.explicitWindow=container.window;}
        self.wallpaperAttachment=wallpaperValid;
        self.attachmentController=homeOwner ?: poster;
        if (content && content.superview==container) {
            NSUInteger back=[container.subviews indexOfObjectIdenticalTo:content],own=[container.subviews indexOfObjectIdenticalTo:self.host];
            if(self.host.superview!=container || own!=back+1){[self.host removeFromSuperview];[container insertSubview:self.host aboveSubview:content];}
        } else if (poster && container==poster.viewIfLoaded) {
            // This exact Home variant contains only background pixels, including
            // scene hosts and snapshot replicas. Put our UIView above them while
            // preserving the system order and attachment of every original view.
            if(self.host.superview!=container || container.subviews.lastObject!=self.host) {
                [self.host removeFromSuperview];[container addSubview:self.host];
            }
        } else {
            UIView *anchor=LMVLockVideoBackgroundAnchor(container,self.host);
            NSUInteger expected=anchor?[container.subviews indexOfObjectIdenticalTo:anchor]+1:0;
            NSUInteger own=[container.subviews indexOfObjectIdenticalTo:self.host];
            if(self.host.superview!=container || own!=expected){[self.host removeFromSuperview];[container insertSubview:self.host atIndex:expected];}
        }
        BOOL geometryChanged=!CGRectEqualToRect(self.host.frame,container.bounds);
        [CATransaction begin];[CATransaction setDisableActions:YES];
        if(geometryChanged)self.host.frame=container.bounds;
        if(self.host.alpha!=1)self.host.alpha=1;
        // 0.0.124: do not composite a layer that nothing can see. The layer stays
        // attached to the same superview, so it is back the instant the cover goes
        // away; this only removes wasted work and cannot hide the desktop.
        // 0.0.139: hide ONLY behind an opaque APP cover or under a notification
        // pull. Behind the translucent switcher/Control Center the frozen video
        // frame must stay VISIBLE (the user asked for exactly that, and the
        // suppress-lease stays applied so no wallpaper can show through).
        BOOL opaqueAppCover=opaqueCover && !(switcherCover || ccCover);
        BOOL hostHidden=opaqueAppCover || (sheetCover && !self.sheetPreexisting);
        if(self.host.hidden!=hostHidden)self.host.hidden=hostHidden;
        NSUInteger mask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        if(self.host.autoresizingMask!=mask)self.host.autoresizingMask=mask;
        if(geometryChanged || !CGRectEqualToRect(self.playback.renderLayer.frame,self.host.bounds))
            [self.playback layoutInBounds:self.host.bounds];
        [CATransaction commit];
    } else if (appForeground) {
        // Hold the attachment, the displayed frame and the suppress-lease: the
        // background stays a video still instead of flashing to the wallpaper.
        // 0.0.124: while something OPAQUE fully covers the desktop there is nothing
        // to show, yet a visible layer is still composited by backboardd for every
        // frame - measurable CPU burn on a video background. Hide the LAYER only
        // (it stays in the same superview, so recovery is instant and the wallpaper
        // can never flash); `covered` is the geometry proof that hiding it cannot
        // be seen. Without that proof the layer stays visible, i.e. unchanged.
        // 0.0.139: same rule on the held-surface path - a translucent cover
        // keeps the frozen frame visible.
        BOOL opaqueAppCover=opaqueCover && !(switcherCover || ccCover);
        BOOL hostHidden=opaqueAppCover || (sheetCover && !self.sheetPreexisting);
        if(self.host.hidden!=hostHidden)self.host.hidden=hostHidden;
    } else {
        if (self.host.superview!=nil) self.teardowns++;
        self.host.hidden=YES;[self.lease restore];self.lease=nil;
        [self.host removeFromSuperview];self.container=nil;self.holdSince=0;
    }
    // 0.0.135/0.0.136: coveredNow means "the video is not audible" - it follows
    // the SAME condition as the freeze, not the raw geometry, so the audio and
    // the video never disagree. The flip syncs the Desktop audio directly (no
    // timer beat in either direction): pausing the instant the desktop becomes
    // invisible, resuming the instant it is back.
    if (!sheetCover) self.sheetWallpaperShown=NO;
    BOOL audioCovered=appForeground || (visible && (switcherPresented || ccPresented || (sheetCover && !self.sheetPreexisting))) ||
        (visible && covered && (switcherCover || ccCover || foreground!=1));
    BOOL wasCovered=self.coveredNow;
    self.coveredNow=audioCovered;
    if (audioCovered!=wasCovered && LMVDesktopAudioCoverHook) LMVDesktopAudioCoverHook(audioCovered);
    if (LMVLaunchReady) {
        // 0.0.137: the model the user asked for. ANY full cover - the app
        // window, the switcher, the Control Center, the notification sheet -
        // freezes the video AND the audio immediately; the layer hides after
        // the 0.3 s transition grace with the suppress-lease kept (the
        // wallpaper can never show through a translucent blur). The video
        // resumes the instant the desktop is visible again - the per-frame
        // watcher catches the reveal within ~16 ms. Only a FULL notification
        // pull shows the original wallpaper on purpose (the lease restores).
        // 0.0.140: a surface that ATTACHED while the sheet was already up is the
    // unlock/resume withdrawal - the warm video binds there instead of the
    // wallpaper. A sheet pulled onto an already-attached surface stays a normal
    // pull. Measured across the whole branch chain so every attach site counts.
    if (sheetCover && !attachedBefore && self.host.superview!=nil) self.sheetPreexisting=YES;
    if (!sheetCover) self.sheetPreexisting=NO;
    // 0.0.140: ANY notification pull shows the original wallpaper behind the
        // sheet (the layer is hidden above and the lease is released) - this must
        // run whenever the sheet is up, NOT only while frozen, or a partial pull
        // would keep the wallpaper suppressed with no way to see it.
        if (sheetCover && !self.sheetPreexisting) {
            if (self.lease) {[self.lease restore];self.lease=nil;}
            self.sheetWallpaperShown=YES;
        }
        // 0.0.140: the notification sheet only FREEZES at the bottom of the pull
        // (`covered`); while it is still being pulled the player keeps RUNNING
        // (the layer is hidden above so the sheet shows the wallpaper, but the
        // video is not paused - that is what makes the release resume with zero
        // delay). The switcher and the Control Center freeze as soon as they are
        // presented, and a full cover of any kind freezes.
        BOOL freeze=appForeground || (visible && (switcherPresented || ccPresented)) ||
            (visible && covered && (sheetCover || switcherCover || ccCover || foreground!=1)),
            play=visible && !covered && !switcherPresented && !ccPresented && !(sheetCover && !self.sheetPreexisting);
        // Transition-only state changes. Calling setVisible:NO on every frozen
        // tick cleared frozen then re-applied it, hiding/showing layers each pass.
        if(freeze) {
            if(self.playback.wantsPlayback || !self.playback.frozen) {
                [self.playback holdCurrentFrame:YES];
            }
            // 0.0.131/0.0.138: the freeze IS the audio-off moment, and it is
            // re-asserted on every frozen tick - a resume from any other path
            // (source change, the 10 Hz sync) can never leave the sound playing
            // under a cover.
            if(LMVDesktopAudioPauseHook)LMVDesktopAudioPauseHook();
            // 0.0.137: a FULL notification-sheet pull shows the original
            // wallpaper on purpose ("下滑到底才出现原壁纸"); a partial pull keeps
            // the video visible through the blur. The lease re-acquires as soon
            // as the sheet slides back and the desktop is exposed again.
        } else if(play) {
            if(self.playback.frozen)[self.playback holdCurrentFrame:NO];
            else if(!self.playback.wantsPlayback || self.playback.posterOnlyVisible)
                [self.playback setVisible:YES];
            else [self.playback resumeIfNeeded];
        } else if(!(sheetCover && !self.sheetPreexisting) && (self.playback.wantsPlayback || self.playback.frozen || self.playback.posterOnlyVisible))
            // 0.0.140: while the sheet is up the layer is hidden on purpose but
            // the player must KEEP RUNNING - stopping it here is what made the
            // release feel slow (a stopped player has to restart from scratch).
            [self.playback setVisible:NO];
    }
    else if(self.playback.posterOnlyVisible!=visible)[self.playback showPreparedPoster:visible];
    BOOL pixels=(visible || appForeground) && !self.playback.renderLayer.hidden && !self.playback.error;
    if (pixels && visible && content && content.superview==container) {
        if (!self.lease && !self.sheetWallpaperShown) {self.lease=[LMVDesktopContentLease new];self.lease.content=content;self.lease.parent=container;self.lease.baselineHidden=content.hidden;}
        // 0.0.137: nil guard - with the full-sheet wallpaper shown the lease is
        // intentionally nil, and messaging nil made this guard pass, hiding the
        // wallpaper again the same update the restore had revealed it.
        if (self.lease && !self.lease.baselineHidden) {if(!content.hidden)content.hidden=YES;self.lease.applied=YES;}
    } else if (pixels && appForeground && retainedAttachment && self.lease) {
        // Geometry/lifecycle discovery may transiently return no wallpaper while
        // the exact already-owned parent is still attached. Do not release that
        // lease merely because this update has no newly discovered `content`.
        UIView *held=self.lease.content;
        if (held && !self.lease.baselineHidden) {if(!held.hidden)held.hidden=YES;self.lease.applied=YES;}
    } else if (self.lease) {[self.lease restore];self.lease=nil;}
    // 0.0.128/0.0.134: watch every frame in BOTH waiting states - the layer
    // hidden behind an opaque app (exit reveal), AND the layer visible but
    // frozen under a sheet (the NC/CC close is caught within ~16 ms instead of
    // the ~0.4 s update cadence). The switcher never freezes at fg==1 anymore.
    // 0.0.137: the watcher runs while the surface exists and watches BOTH
    // directions - the playing state (a cover appearing freezes within ~16 ms)
    // and the hidden/frozen state (the desktop being revealed resumes within
    // ~16 ms). The permanent cost is a few microseconds of window enumeration
    // per frame.
    if (self.host.superview!=nil) [self startCoverWatch];
    else [self stopCoverWatch];
    if (!configured && (self.playback.path || self.playback.player || self.playback.loading)) [self.playback clear];
    if (diagnostics) {
    // 0.0.124: `composited` is the layer that backboardd actually has to composite
    // and `decode` is whether the decoder is running - together they tell apart
    // "paused but still on screen" (CPU wasted on compositing) from "still decoding
    // while invisible" (CPU wasted on decode).
    NSString *status=[NSString stringWithFormat:@"desktop-video visible=%d frozen=%d home=%d host=%@ path=%d layer=%d contentHidden=%d foreground=%ld cover=%d blank=%llu locked=%llu session=%d covered=%d env=%d geo=%d held=%.2f teardown=%lu hostHidden=%d poster=%d shown=%d composited=%d decode=%d opaque=%d sheet=%d appc=%d sw=%d cc=%d",
        visible,(int)appForeground,homeConfirmed,container?NSStringFromClass(container.class):@"none",configured,pixels,self.lease.applied,
        (long)foreground,!CGRectIsEmpty(cover),(unsigned long long)blank,(unsigned long long)locked,
        (int)self.authenticatedSession,(int)covered,(int)environment,(int)(container && LMVDesktopGeometryVisible(container)),
        (self.holdSince>0?holdNow-self.holdSince:0.0),(unsigned long)self.teardowns,
        (int)self.host.hidden,(int)(self.playback.posterLayer.contents!=nil),(int)(!self.playback.renderLayer.hidden),
        (int)(self.host.superview!=nil && !self.host.hidden),
        (int)(self.playback.wantsPlayback && !self.playback.frozen),(int)opaqueCover,
        (int)sheetCover,(int)appWindowCover,(int)switcherCover,(int)ccCover];
    if(![status isEqualToString:self.status]){self.status=status;LMVDiagnostic(status);}
    // 0.0.129: which windows are on screen (class names, changes-only) - the
    // discovery aid for sheet presenters (e.g. the search pull-down) whose host
    // window class the cover probe does not know yet.
    {
        NSMutableString *windowList=[NSMutableString new];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha<.01) continue;
                [windowList appendFormat:@"%@ ",NSStringFromClass(window.class)];
            }
        }
        if (![windowList isEqualToString:self.windowListStatus]) {
            self.windowListStatus=windowList;
            LMVDiagnostic([NSString stringWithFormat:@"desktop-windows %@",windowList]);
        }
    }
    // 0.0.95 diagnostics: how much of the visible screen the Desktop surface covers
    // and where the uncovered band is ("background dropped / leaked").
    {
        UIWindow *coverWindow=self.host.window;
        CGRect coverViewport=LMVVideoWindowViewport(coverWindow);
        BOOL attached=self.host.superview!=nil && coverWindow!=nil;
        CALayer *coverRoot=coverWindow.layer.presentationLayer ?: coverWindow.layer;
        CALayer *coverSpace=self.host.layer.presentationLayer ?: self.host.layer;
        CGRect hostInWindow=attached?[coverSpace convertRect:coverSpace.bounds toLayer:coverRoot]:CGRectZero;
        CGRect revealed=CGRectIsEmpty(coverViewport)?CGRectZero:CGRectIntersection(hostInWindow,coverViewport);
        CGFloat revealedHeight=CGRectIsEmpty(revealed)?0.0:revealed.size.height;
        CGFloat coverGapTop=CGRectIsEmpty(coverViewport)?0.0:MAX(0.0,hostInWindow.origin.y-coverViewport.origin.y);
        CGFloat coverGapBottom=CGRectIsEmpty(coverViewport)?0.0:MAX(0.0,(coverViewport.origin.y+coverViewport.size.height)-(hostInWindow.origin.y+hostInWindow.size.height));
        NSString *coverKey=[NSString stringWithFormat:@"a=%d r=%.0f t=%.0f b=%.0f",(int)attached,floor(revealedHeight/20.0)*20.0,floor(coverGapTop/20.0)*20.0,floor(coverGapBottom/20.0)*20.0];
        if (![coverKey isEqualToString:self.coverage]) {
            self.coverage=coverKey;
            LMVDiagnostic([NSString stringWithFormat:@"desktop-cover attached=%d revealed=%.1f gapTop=%.1f gapBottom=%.1f visible=%d frozen=%d hostHidden=%d container=%@",
                (int)attached,revealedHeight,coverGapTop,coverGapBottom,visible,(int)appForeground,(int)self.host.hidden,
                self.container?NSStringFromClass(self.container.class):@"none"]);
        }
    }
    NSString *coverPerf=LMVDesktopVideoPerf("desktop",CACurrentMediaTime()-coverPerf0);
    if (coverPerf) LMVDiagnostic(coverPerf);
    }
    self.updating=NO;
}
@end
static void LMVDesktopPrimeEarly(void) {
    if(!LMVInitialized || !NSThread.isMainThread)return;
    // dyld initializer: Foundation preferences and a queued ImageIO cache read
    // only. Never create the desktop manager/view/player or query UIKit here.
    if(!LMVDesktopSeed)LMVDesktopSeed=[LMVDesktopPosterSeed new];
    LMVDesktopPosterSeed *seed=LMVDesktopSeed;
    id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("DesktopBackgroundEnabled"),kLMVPrefsID);
    id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
    BOOL globalOn=![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue];
    NSString *path=(globalOn && [enabled respondsToSelector:@selector(boolValue)] && [enabled boolValue])?LMVDesktopSelectedPath():nil;
    NSString *revision=LMVLockVideoRevision(path);
    BOOL samePath=seed.path==path || [seed.path isEqualToString:path];
    BOOL sameRevision=seed.revision==revision || [seed.revision isEqualToString:revision];
    if(seed.primed && samePath && sameRevision)return;
    seed.primed=YES;seed.path=path;seed.revision=revision;seed.image=NULL;
    NSUInteger generation=++seed.generation;
    if(!path.length || !revision.length)return;
    dispatch_async(LMVVideoPosterQueue(),^{
        @autoreleasepool {
            CGImageRef image=LMVVideoPosterRead(path,revision);
            dispatch_async(dispatch_get_main_queue(),^{
                if(seed==LMVDesktopSeed && seed.generation==generation && [LMVLockVideoRevision(path) isEqualToString:revision]) {
                    seed.image=image;
                    if(LMVDesktopVideo && (LMVLaunchReady || LMVDesktopUIAvailable) && !LMVDesktopVideo.suspended) {
                        [LMVDesktopVideo primePoster];[LMVDesktopVideo update];
                    }
                }
                if(image)CGImageRelease(image);
            });
        }
    });
}
static BOOL LMVDesktopEnsureManager(void) {
    if(!LMVInitialized || !NSThread.isMainThread || (!LMVLaunchReady && !LMVDesktopUIAvailable) || LMVDesktopCreatingManager)return NO;
    if(LMVDesktopVideo)return YES;
    LMVDesktopCreatingManager=YES;
    @try {LMVDesktopVideo=[LMVDesktopVideoManager new];}
    @finally {LMVDesktopCreatingManager=NO;}
    if(!LMVDesktopVideo)return NO;
    [LMVDesktopVideo primePoster];return YES;
}
static void LMVDesktopEarlyLayout(void) {
    if(!LMVInitialized || !NSThread.isMainThread || LMVLaunchReady || !LMVDesktopUIAvailable)return;
    if(!LMVDesktopSeed.primed)LMVDesktopPrimeEarly();
    if(!LMVDesktopSeed.path.length || !LMVDesktopSeed.revision.length)return;
    if(!LMVDesktopEnsureManager() || !LMVDesktopVideo.enabled)return;
    // Prelaunch hooks already recorded an attached Home controller. Avoid
    // traversing private wallpaper getters during their initialization stack.
    LMVDesktopVideoManager *manager=LMVDesktopVideo;
    NSString *key=manager.path && manager.revision?[manager.path stringByAppendingFormat:@"|%@",manager.revision]:nil;
    if(key && ![manager.earlyPosterAttempt isEqualToString:key]) {
        manager.earlyPosterAttempt=key;
        [manager.playback loadCachedPosterNowForPath:manager.path revision:manager.revision];
    }
    [manager update];
}
static void LMVDesktopVideoRefresh(BOOL reload) {
    if(!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread)return;
    LMVDesktopDiscover();BOOL created=LMVDesktopVideo==nil;
    if(!LMVDesktopEnsureManager())return;
    [LMVDesktopVideo refresh:reload || created];
}
static void LMVDesktopVideoSuspend(void) {if(NSThread.isMainThread)[LMVDesktopVideo suspend];}
static void LMVDesktopVideoScreenBlank(void) {if(NSThread.isMainThread){LMVDesktopVideo.authenticatedSession=NO;[LMVDesktopVideo suspend];}}
static void LMVDesktopVideoScreenChanged(void) {
    if(!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread || !LMVDesktopVideo)return;
    uint64_t blank=1,locked=1;
    if(LMVBlankToken<0 || LMVLockToken<0 || notify_get_state(LMVBlankToken,&blank)!=NOTIFY_STATUS_OK ||
       notify_get_state(LMVLockToken,&locked)!=NOTIFY_STATUS_OK || blank || locked)return;
    // Current notify state, not a previously queued blank value. Reattach the
    // already prepared Home frame on the unlock turn, before the global refresh.
    LMVDesktopDiscover();LMVDesktopVideo.suspended=NO;[LMVDesktopVideo update];
}
static void LMVDesktopHostReady(UIViewController *controller) {
    if(!LMVInitialized || !NSThread.isMainThread || LMVDesktopCreatingManager)return;
    if(!LMVLockVideoClass(controller,@"SBHomeScreenViewController") && !LMVLockVideoClass(controller,@"SBIconController") &&
       !LMVLockVideoClass(controller,@"PBUIPosterHomeViewController"))return;
    UIView *view=controller.viewIfLoaded;UIWindow *window=view.window;
    // Read only already-existing view/window state after the original layout.
    // Mere class discovery or a detached view cannot enable UIKit construction.
    if(!view || !window || ![window isKindOfClass:UIWindow.class] || !LMVLockVideoRectValid(view.bounds) ||
       LMVLockVideoClass(window,@"SBCoverSheetWindow"))return;
    BOOL homeWindow=LMVLockVideoClass(window,@"SBHomeScreenWindow");
    BOOL poster=LMVLockVideoClass(controller,@"PBUIPosterHomeViewController");
    if(!homeWindow && !poster)return;
    LMVDesktopUIAvailable=YES;
    if(!LMVLaunchReady)LMVDesktopEarlyLayout();
    else if(LMVDesktopVideo) {
        uint64_t blank=1,locked=1;
        BOOL unlocked=LMVBlankToken>=0 && LMVLockToken>=0 &&
            notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK &&
            notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK && !blank && !locked;
        // After-original Home willAppear/layout is an exact target, not a late
        // global timer. Resume only that existing prepared manager on unlock.
        BOOL wake=LMVDesktopVideo.suspended && unlocked;
        if(wake)LMVDesktopVideo.suspended=NO;
        if(wake || (!LMVDesktopVideo.host.superview && unlocked)) [LMVDesktopVideo update];
        else if(!LMVDesktopVideo.suspended)[LMVDesktopVideo syncGeometry];
    }
}
static void LMVDesktopLifecycle(UIViewController *controller,NSInteger visible) {
    if(!LMVInitialized || !NSThread.isMainThread)return;
    if(!LMVDesktopControllers)LMVDesktopControllers=[NSHashTable weakObjectsHashTable];[LMVDesktopControllers addObject:controller];
    LMVDesktopControllerRecord *record=objc_getAssociatedObject(controller,&LMVDesktopControllerRecordKey);
    if(!record){record=[LMVDesktopControllerRecord new];objc_setAssociatedObject(controller,&LMVDesktopControllerRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    UIView *root=controller.viewIfLoaded;
    BOOL changed=record.root!=root;record.root=root;
    if(visible>=0){changed|=!record.known || record.visible!=(visible!=0);record.known=YES;record.visible=visible!=0;}
    if(changed) {
        // Pause/resume the already-owned Home surface on the lifecycle turn,
        // not one maintenance tick later. The coalesced callback still reads
        // current records/foreground; it never captures an obsolete visible bit.
        if(visible>=0 && LMVLaunchReady && LMVDesktopVideo && !LMVDesktopVideo.suspended &&
           LMVDesktopVideo.attachmentController==controller)[LMVDesktopVideo update];
        LMVDesktopRequestUpdate();
    }
}

static void (*LMVDesktopOriginalLoad)(id,SEL),(*LMVDesktopOriginalLayout)(id,SEL);
static void (*LMVDesktopOriginalWillAppear)(id,SEL,BOOL),(*LMVDesktopOriginalDidAppear)(id,SEL,BOOL),(*LMVDesktopOriginalWillDisappear)(id,SEL,BOOL),(*LMVDesktopOriginalDidDisappear)(id,SEL,BOOL);
static void (*LMVIconOriginalLoad)(id,SEL),(*LMVIconOriginalLayout)(id,SEL);
static void (*LMVIconOriginalWillAppear)(id,SEL,BOOL),(*LMVIconOriginalDidAppear)(id,SEL,BOOL),(*LMVIconOriginalWillDisappear)(id,SEL,BOOL),(*LMVIconOriginalDidDisappear)(id,SEL,BOOL);
static void (*LMVPosterHomeOriginalLoad)(id,SEL),(*LMVPosterHomeOriginalLayout)(id,SEL);
static void (*LMVPosterHomeOriginalWillAppear)(id,SEL,BOOL),(*LMVPosterHomeOriginalDidAppear)(id,SEL,BOOL),(*LMVPosterHomeOriginalWillDisappear)(id,SEL,BOOL),(*LMVPosterHomeOriginalDidDisappear)(id,SEL,BOOL);
#define LMV_DESKTOP_CALLBACKS(prefix) \
static void prefix##HookLoad(id value,SEL selector){prefix##OriginalLoad(value,selector);LMVDesktopLifecycle(value,-1);} \
static void prefix##HookLayout(id value,SEL selector){prefix##OriginalLayout(value,selector);LMVDesktopLifecycle(value,-1);LMVDesktopHostReady(value);} \
static void prefix##HookWillAppear(id value,SEL selector,BOOL animated){prefix##OriginalWillAppear(value,selector,animated);LMVDesktopLifecycle(value,1);LMVDesktopHostReady(value);} \
static void prefix##HookDidAppear(id value,SEL selector,BOOL animated){prefix##OriginalDidAppear(value,selector,animated);LMVDesktopLifecycle(value,1);LMVDesktopHostReady(value);} \
static void prefix##HookWillDisappear(id value,SEL selector,BOOL animated){prefix##OriginalWillDisappear(value,selector,animated);LMVDesktopLifecycle(value,0);} \
static void prefix##HookDidDisappear(id value,SEL selector,BOOL animated){prefix##OriginalDidDisappear(value,selector,animated);LMVDesktopLifecycle(value,0);}
LMV_DESKTOP_CALLBACKS(LMVDesktop)
LMV_DESKTOP_CALLBACKS(LMVIcon)
LMV_DESKTOP_CALLBACKS(LMVPosterHome)
#undef LMV_DESKTOP_CALLBACKS
static id (*LMVDesktopWallpaperOriginalShared)(id,SEL);
static void (*LMVDesktopWallpaperOriginalLayout)(id,SEL);
static id LMVDesktopWallpaperHookShared(id value,SEL selector) {
    id result=LMVDesktopWallpaperOriginalShared(value,selector);
    if (NSThread.isMainThread && LMVInitialized) {
        BOOL changed=LMVDesktopWallpaperController!=result;
        LMVDesktopWallpaperController=result;if(changed)LMVDesktopRequestUpdate();
    }
    return result;
}
static void LMVDesktopWallpaperHookLayout(id value,SEL selector) {
    LMVDesktopWallpaperOriginalLayout(value,selector);
    // Wallpaper layout can run inside system initialization. It never creates
    // Desktop UI or evaluates screen/application state synchronously.
    if(NSThread.isMainThread && LMVInitialized && LMVLaunchReady && LMVDesktopVideo &&
       !LMVDesktopVideo.suspended && (value==LMVDesktopExplicitWallpaper || value==LMVDesktopVideo.container))
        [LMVDesktopVideo syncGeometry];
    // Stable wallpaper layouts are never global policy refresh triggers. Real
    // preferences/screen transitions and bounded maintenance still run policy.
}
static void LMVDesktopVideoInstallHooks(void) {
#define LMV_DESKTOP_INSTALL(cls,name,animated,replacement,original) do { \
    SEL selector=NSSelectorFromString(name); \
    if(LMVLockVideoHookMatches(cls,selector,animated))MSHookMessageEx(cls,selector,(IMP)replacement,(IMP *)&original); \
} while(0)
#define LMV_DESKTOP_CONTROLLER(classname,prefix) do { \
    Class cls=NSClassFromString(classname);if(cls && [cls isSubclassOfClass:UIViewController.class]) { \
        LMV_DESKTOP_INSTALL(cls,@"viewDidLoad",NO,prefix##HookLoad,prefix##OriginalLoad); \
        LMV_DESKTOP_INSTALL(cls,@"viewDidLayoutSubviews",NO,prefix##HookLayout,prefix##OriginalLayout); \
        LMV_DESKTOP_INSTALL(cls,@"viewWillAppear:",YES,prefix##HookWillAppear,prefix##OriginalWillAppear); \
        LMV_DESKTOP_INSTALL(cls,@"viewDidAppear:",YES,prefix##HookDidAppear,prefix##OriginalDidAppear); \
        LMV_DESKTOP_INSTALL(cls,@"viewWillDisappear:",YES,prefix##HookWillDisappear,prefix##OriginalWillDisappear); \
        LMV_DESKTOP_INSTALL(cls,@"viewDidDisappear:",YES,prefix##HookDidDisappear,prefix##OriginalDidDisappear); \
    } \
} while(0)
    LMV_DESKTOP_CONTROLLER(@"SBHomeScreenViewController",LMVDesktop);
    LMV_DESKTOP_CONTROLLER(@"SBIconController",LMVIcon);
    LMV_DESKTOP_CONTROLLER(@"PBUIPosterHomeViewController",LMVPosterHome);
    Class wallpaper=NSClassFromString(@"SBFWallpaperView");
    if(wallpaper && [wallpaper isSubclassOfClass:UIView.class])LMV_DESKTOP_INSTALL(wallpaper,@"layoutSubviews",NO,LMVDesktopWallpaperHookLayout,LMVDesktopWallpaperOriginalLayout);
    Class controller=NSClassFromString(@"SBWallpaperController");SEL shared=NSSelectorFromString(@"sharedInstance");
    Method method=controller?class_getClassMethod(controller,shared):NULL;
    if(method && method_getNumberOfArguments(method)==2) {
        char *type=method_copyReturnType(method);BOOL matches=type && !strcmp(type,@encode(id));free(type);
        if(matches)MSHookMessageEx(object_getClass(controller),shared,(IMP)LMVDesktopWallpaperHookShared,(IMP *)&LMVDesktopWallpaperOriginalShared);
    }
#undef LMV_DESKTOP_CONTROLLER
#undef LMV_DESKTOP_INSTALL
}
