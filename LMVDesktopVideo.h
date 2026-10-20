#pragma once
#import "LMVPanelTuning.h"
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
// 1.31: the surface the desktop video belongs on. The device log pins the tree:
//
//   SBHomeScreenWindow
//     SBHomeScreenView [ SBFStatusBarLegibilityView, SBIconContentView,
//                        SBHomeScreenBackdropView>MTMaterialView, UIImageView ]
//
// The wallpaper view the channel attached to until 1.30 lives a whole window BELOW
// this one, in _SBWallpaperSecureWindow - so SBHomeScreenWindow covered the video
// completely ("开始桌面视频 不在桌面"). The video now goes into the Home window
// itself, directly UNDER the icon container: on the desktop, under the icons,
// above the wallpaper.
static UIWindow *LMVDesktopHomeViewWindow(void) {
    // Scenes only. UIApplication.windows is deprecated AND absent from some host
    // harnesses, and the Home window always has a scene on iOS 13+ - the double on
    // this path is the same one LMVCoverRect already walks.
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (!window.hidden && window.alpha>=.01 && LMVDesktopHomeWindow(window)) return window;
    }
    return nil;
}
// The Home view plus the icon container the video must sit under. Only a DIRECT
// subview is ever returned as the anchor: insertSubview:belowSubview: raises on a
// descendant, and an exception escaping this path would abort SpringBoard.
static UIView *LMVDesktopHomeHostView(UIView **iconsOut) {
    if (iconsOut) *iconsOut = nil;
    UIWindow *window = LMVDesktopHomeViewWindow();
    if (!window) return nil;
    // Found by class name, never through rootViewController: only the coverage probe
    // touches that property, so the harness for this path cannot be assumed to
    // double it. The Home view is a direct subview of its own window either way.
    UIView *home = nil;
    for (UIView *child in window.subviews) {
        if ([NSStringFromClass(child.class) containsString:@"HomeScreenView"]) { home = child; break; }
    }
    if (!home && window.subviews.count) home = window.subviews.firstObject;
    if (!home || !LMVLockVideoRectValid(home.bounds)) return nil;
    for (UIView *child in home.subviews) {
        if ([NSStringFromClass(child.class) containsString:@"IconContentView"]) {
            if (iconsOut) *iconsOut = child;
            return home;
        }
    }
    return nil;
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
@property(nonatomic) BOOL sheetPreexisting,lastSheetCover;
// 1.25: the pixels decide when the desktop comes back. SpringBoard's
// presentation flags flip only AFTER the dismiss animation, so the desktop
// video waited a whole animation for a state the screen had already released
// (device report: 控制中心收回 / App 退出到桌面 后视频和声音太慢). The probe is
// believed only once it has actually seen a cover, so a device whose window
// classes do not match keeps the old state-driven freeze.
@property(nonatomic) BOOL geometryCoverSeen,switcherSawCover,ccSawCover;
// 1.25: an application has been frontmost. From the moment it stops being
// frontmost the desktop is what the user is looking at - the user asked for
// ZERO delay, so nothing is allowed to hold the freeze through the exit
// animation (the device log shows the app surface and the switcher shell
// lingering for 0.1-1.8 s after the app was gone).
@property(nonatomic) BOOL appAway;
// The instant the app left, for the short unconditional release window.
@property(nonatomic) CFTimeInterval appLeftAt;
@property(nonatomic) BOOL effectiveSwitcherPresented,effectiveControlCenterPresented;
@property(nonatomic) NSUInteger teardowns;
// 0.0.128: while the video layer is hidden behind an opaque app, updates only
// run on the ~0.4 s hook/tick cadence - the exit cross-fade could therefore
// show the visible wallpaper content through the fading app for up to a full
// tick (the reported occasional flash). This watcher runs ONLY while the layer
// is hidden and re-checks the cheap cover geometry every frame; the moment the
// fade starts revealing the desktop it requests one full update, so the layer
// is back within ~16 ms - imperceptible.
@property(nonatomic,strong) CADisplayLink *coverWatch;
// 1.32: the cheap gate for -coverWatchTick:. `probeWindowCount` is the number of
// VISIBLE windows seen by the last full probe, `probeFullAt` is when that probe
// ran. While neither moves, the tick has nothing new to measure - see the gate
// in -coverWatchTick: for why that is safe in both directions.
@property(nonatomic) NSUInteger probeWindowCount;
@property(nonatomic) CFTimeInterval probeFullAt;
// 2.07: when the window count was last read. See the gate in -coverWatchTick:.
@property(nonatomic) CFTimeInterval probeCountAt;
// 2.08: key-window changes are the one signal every app launch / exit produces.
// While the desktop is covered the watcher runs at a 10 Hz heartbeat; a key change
// opens a one second 60 Hz burst so the reveal is caught on the frame it happens.
@property(nonatomic) CFTimeInterval probeBurstUntil;
@property(nonatomic) BOOL keyWindowObserver;
// 1.33: whether the surface is currently on the Home host. It decides whether the
// geometry stops above the dock strip (see LMVDesktopVideoBoundsFor); -syncGeometry
// reads it, so it has to be part of the manager rather than a local.
@property(nonatomic) BOOL homeHostGeometry;
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
// 1.25: how much of the window's visible CONTENT is still on screen (0..1).
// A window keeps its full-screen frame while the content inside shrinks away -
// that is exactly what an app exit and a Control Center dismiss look like, and
// a frame-based probe cannot see it (device log: the cover stayed 1 for 1.25 s
// after the app had gone, so the desktop waited for the window to vanish).
// -1 means "cannot be measured" and the caller must fall back to the frame.
static CGFloat LMVDesktopContentCoverage(UIWindow *window,UIView *root,UIWindow *destination) {
    if (!window || !root || !destination) return -1;
    CALayer *space=window.layer.presentationLayer;if (!space) space=window.layer;
    BOOL measurable=NO;CGRect content=CGRectZero;
    for (UIView *child in root.subviews) {
        if (child.hidden || child.alpha<.01) continue;
        CALayer *paint=child.layer.presentationLayer;if (!paint) paint=child.layer;if (!paint) continue;
        CGRect piece=[paint convertRect:paint.bounds toLayer:space];
        if (!LMVLockVideoRectValid(piece)) continue;
        measurable=YES;content=CGRectIsEmpty(content)?piece:CGRectUnion(content,piece);
    }
    if (!measurable) return -1;
    CGFloat full=destination.bounds.size.width*destination.bounds.size.height;
    if (full<=0) return -1;
    // Content that has left the screen entirely is GONE, not unmeasurable: the
    // screen rect is carried into the window, so nothing crosses layer trees.
    CGRect screenInWindow=[destination convertRect:destination.bounds toWindow:window];
    CGRect onScreen=CGRectIntersection(content,screenInWindow);
    return (CGRectIsEmpty(onScreen)?0:onScreen.size.width*onScreen.size.height)/full;
}
// 1.26: the shape of a pop-up that is NOT a window. AppTools (and most panel
// tweaks) present their panel INTO an existing window, so the window list never
// changes and a class-name-only dump cannot tell where the card is, how big it
// is or which level the video would have to sit on. This prints one view and its
// descendants with everything a mount decision needs: class, frame, corner
// radius, alpha and hidden state. Diagnostics only - never touches the view.
static NSString *LMVDesktopOverlayShape(UIView *view,NSUInteger depth) {
    if (!view) return @"";
    NSMutableString *out=[NSMutableString new];
    [out appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f(r%.0f,a%.2f,h%d)",
        NSStringFromClass(view.class),view.frame.origin.x,view.frame.origin.y,
        view.frame.size.width,view.frame.size.height,view.layer.cornerRadius,
        view.alpha,(int)view.hidden];
    if (depth>=4 || view.subviews.count==0) return out;
    [out appendString:@"{"];
    NSUInteger n=0;
    for (UIView *child in view.subviews) {
        if (n++>=6) {[out appendString:@"…"];break;}
        [out appendString:LMVDesktopOverlayShape(child,depth+1)];
        [out appendString:@","];
    }
    [out appendString:@"}"];
    return out;
}
// 1.27: the overlay scan must walk the WHOLE view tree, not just the window's
// direct subviews. AppTools (and most iOS presentations) drop their
// UITransitionView one or two levels BELOW the window - under SBHomeScreenView,
// for example - so a window.subviews-only scan never sees it and the diagnostic
// stays stuck on "none" even while the pop-up is on screen. This gathers every
// TransitionView/Overlay descendant, bounded so it cannot stall the tick.
static void LMVDesktopFindOverlayViews(UIView *view,NSUInteger depth,NSMutableArray<UIView *> *found,NSUInteger *nodes) {
    // 1.76.4: 1500 nodes PER WINDOW was the most expensive thing this channel did -
    // with a full notification list SBHomeScreenWindow alone offers thousands of
    // descendants, and every hit then gets its own LMVDesktopOverlayShape dump
    // (depth 4, up to 6 children a level). The device log measured one update at
    // 1317 ms. Presentation containers sit near the top; 400 nodes still finds them.
    if (!view || depth>4 || *nodes>400) return;
    (*nodes)++;
    NSString *name=NSStringFromClass(view.class);
    if ([name containsString:@"TransitionView"] || [name containsString:@"Overlay"]) [found addObject:view];
    for (UIView *child in view.subviews) LMVDesktopFindOverlayViews(child,depth+1,found,nodes);
}
// 1.42: which windows are PANEL-like. Same name test the 1.25 geometry uses
// (Panel/Menu/Platter) plus Clipboard, so a clipboard manager such as CopyVault
// (CVPanelWindow) is covered by the existing "Panel" rule.
static BOOL LMVDesktopPanelName(NSString *name) {
    // 1.65: VLBYCK is CopyLogX's obfuscated panel host. It carries no
    // Panel/Menu/Platter/Clipboard word, so the deep subtree walk used to skip
    // it and the log only ever showed the empty shell `{FJLOLX[]}`.
    return [name containsString:@"Panel"] || [name containsString:@"Menu"] ||
        [name containsString:@"Platter"] || [name containsString:@"Clipboard"] ||
        [name isEqualToString:@"VLBYCK"];
}
// 1.42: the WHOLE subtree of a panel-like window, six levels deep, with frame,
// hidden, alpha and corner radius on every node.
// Why the 1.25 panel geometry is not enough: it stops at three levels, prints
// only up to six children per level, and is built from the same window list that
// skips hidden windows - which is exactly how CVPanelWindow could read as a
// permanent empty shell `{UIView[]}` while CopyVault's panel was somewhere the
// log could not see. This walks deeper and is also called for windows that are
// currently hidden, so a panel window that only exists while it is open still
// shows its shape (the panel-open report can then name its card and mount level
// without another round trip).
static void LMVDesktopPanelTree(UIView *view,NSUInteger depth,NSMutableString *out,NSUInteger *nodes) {
    if (!view || *nodes>240) return;
    (*nodes)++;
    [out appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f(h%d,a%.2f,r%.0f)",
        NSStringFromClass(view.class),view.frame.origin.x,view.frame.origin.y,
        view.frame.size.width,view.frame.size.height,(int)view.hidden,view.alpha,view.layer.cornerRadius];
    if (depth>=6 || view.subviews.count==0) return;
    [out appendString:@"{"];
    NSUInteger n=0;
    for (UIView *child in view.subviews) {
        if (n++>=8) {[out appendString:@"…"];break;}
        LMVDesktopPanelTree(child,depth+1,out,nodes);
        [out appendString:@","];
    }
    [out appendString:@"}"];
}
// 1.67: view + layer.name tree, for the Control Centre layer whose name we
// cannot guess when it is presented over Notification Centre.
static void LMVDesktopLayerTree(UIView *view,NSUInteger depth,NSMutableString *out,NSUInteger *nodes) {
    if (!view || *nodes>120 || depth>4) return;
    (*nodes)++;
    [out appendFormat:@"%@|%@ ",NSStringFromClass(view.class),view.layer.name?:@"-"];
    for (UIView *child in view.subviews) LMVDesktopLayerTree(child,depth+1,out,nodes);
}
static CGRect LMVDesktopCoverRect(UIWindow *destination,BOOL *unknown,BOOL *appWindowCover,BOOL *switcherCover,BOOL *ccCover,BOOL *sheetCover,BOOL *sheetFullCover) {
    CGRect combined=CGRectZero;*unknown=NO;*appWindowCover=NO;*switcherCover=NO;*ccCover=NO;*sheetCover=NO;*sheetFullCover=NO;
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
                // 1.25: the Control Center module tracks the CC content as it
                // slides away, which is up to 0.74 s before this window leaves
                // (device log). It is compiled separately, so it is reached
                // through the RUNTIME, not through a header symbol; when the
                // module is not configured the call is simply not answered and
                // the frame-based answer below stands.
                Class ccModule=NSClassFromString(@"LMVControlCenterVideoManager");
                SEL ccEmpty=NSSelectorFromString(@"controlCenterWindowIsEmpty");
                if (ccModule && [ccModule respondsToSelector:ccEmpty] &&
                    ((BOOL(*)(id,SEL))objc_msgSend)(ccModule,ccEmpty)) continue;
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
                // 1.25: the window frame alone is not a cover. On dismiss the
                // Control Center root stays FULL-SCREEN while the modules (and the
                // blur material with them) slide away inside it, so a frame-based
                // probe kept the desktop frozen for the whole animation - the
                // device log pins it: the CC's own probe reported the content gone
                // at 71756.836 and the desktop only resumed at 71757.572, 0.73 s
                // later. Measure the visible CONTENT instead; when it cannot be
                // measured at all the frame-based answer below still stands.
                CGFloat ccContent=LMVDesktopContentCoverage(window,root,destination);
                if (ccContent>=0 && ccContent<0.6) continue; // the content has left
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
                // 1.25: SBWindow is the surface that carries the application on
                // the user's device (the device log shows it appear/disappear with
                // the app and with the app CARD inside the switcher). Without it
                // the app was invisible to the probe (appc=0 throughout) and only
                // the empty switcher shell held the desktop - for up to 1.8 s.
                if (window==destination || LMVDesktopHomeWindow(window) ||
                    (![name containsString:@"AppWindow"] && ![name containsString:@"Switcher"] &&
                     ![name isEqualToString:@"SBWindow"])) continue;
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
                // 1.25: the frame is not enough here either. An app (and the
                // switcher surface that carries it) keeps its full-screen frame
                // while its content shrinks away on exit, so the desktop stayed
                // frozen until the window itself disappeared. The threshold is
                // deliberately low: a switcher that is genuinely open must keep
                // holding the freeze.
                CGFloat appContent=LMVDesktopContentCoverage(window,window.rootViewController.viewIfLoaded,destination);
                if (appContent>=0 && appContent<0.4) continue;
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
            if (!CGRectIsEmpty(converted)) {
                combined=CGRectIsEmpty(combined)?converted:CGRectUnion(combined,converted);*sheetCover=YES;
                // 1.25: a pull is FULL only once the sheet actually covers the
                // SCREEN. A HALF-pulled sheet leaves the desktop visible underneath
                // and must NOT hide the layer or release the suppress-lease - doing
                // that put the original wallpaper where the video is still supposed
                // to be playing (the reported "下拉通知中心一半，桌面视频变成原壁纸").
                // The rect is clipped to the destination bounds first: while the
                // sheet animates out, its frame is still full-height but partly
                // off-screen, which would otherwise read as a full cover. The
                // tolerance matches LMVDesktopFullyCovered exactly, so the pull
                // freezes/hides on precisely the frame it covers the screen.
                CGRect onScreen=CGRectIntersection(converted,destination.bounds);
                if (!CGRectIsEmpty(onScreen) &&
                    onScreen.size.width>=destination.bounds.size.width-1 &&
                    onScreen.size.height>=destination.bounds.size.height-1) *sheetFullCover=YES;
            }
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
// 1.32: the CHEAP half of the cover probe - how many windows are on screen right
// now. Every transition the cover watch cares about moves this number: an app
// window appears (launch) or disappears (exit), the Control Center window is
// unhidden (open) or hidden (dismiss), the switcher shell comes and goes.
// Reading it costs one property per window - no class lookup, no layer query, no
// rect conversion - so it is affordable on every frame as a gate in front of the
// expensive measurement that used to run there. A HALF-pulled notification sheet
// deliberately does not move it, which matches the rule that a partial pull is
// not a cover at all.
static NSUInteger LMVDesktopVisibleWindowCount(void) {
    NSUInteger count=0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (!window.hidden && window.alpha>=.01) count++;
    }
    return count;
}
// 1.38: back to ONE answer - the surface is always the full container (1.32).
// 1.33 made the Home path stop above the dock strip so the dock's own backdrop could
// not sample the video; 1.35/1.36/1.37 only narrowed WHEN that happened. The
// concession always cost something visible (no video in the strip) and never removed
// the cause, only stepped around it. It is gone.
// 1.39: the cause is removed by WHERE the surface lives, not by anything done to it.
// The dock's floating blur captures its OWN window (per-window backdrop), so when the
// video rode in the Home window (1.31+) the dock sampled it and its look tracked the
// video - the reported "dock vanishes during a long-press menu". 1.30 put the video in
// _SBWallpaperSecureWindow (via the wallpaper lease) and the dock was fine there,
// because the secure window is a DIFFERENT window the dock's backdrop does not capture.
// The Home window is otherwise transparent, so the secure-window video shows through
// with no extra view-hiding. The 1.38 private backdrop-group attempt
// (the 1.38 private backdrop-group attempt) was measured on-device and did NOT stop the dock, so
// this reverts to the 1.30 window, which was confirmed good.
static CGRect LMVDesktopVideoBoundsFor(UIView *geometryTarget,BOOL homeHost) {
    (void)homeHost;
    return geometryTarget.bounds;
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
// 1.76.5: the channel-level `perf desktop` line reported a single update at
// 1657 ms while the other four calls in the same window took 2 ms. Reading the
// code cannot tell which stage that was, so mark the three stages that can be
// expensive. Only a stage over 50 ms is written, so this costs nothing in normal
// operation and cannot itself become the stall.
static void LMVDesktopStage(const char *name,CFTimeInterval started) {
    if (!LMVDiagnosticsEnabled.load()) return;
    CFTimeInterval ms=(CACurrentMediaTime()-started)*1000.0;
    if (ms<50.0) return;
    LMVDiagnostic([NSString stringWithFormat:@"desktop-stage %s %.0fms",name,ms]);
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
        // 2.08: every app launch and every return to the desktop changes the key
        // window. That is the "wake up now" edge a 10 Hz heartbeat cannot give on
        // its own, and it is why the watcher can idle so slowly while an app is up.
        // Registered by name, not by the UIKit constant: the runtime value is the
        // string, and this header is also compiled by fixtures that do not link the
        // symbol.
        _keyWindowObserver=YES;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyWindowBecameKey:)
            name:@"UIWindowDidBecomeKeyNotification" object:nil];
    }
    return self;
}
- (void)dealloc {
    if(_keyWindowObserver)[NSNotificationCenter.defaultCenter removeObserver:self name:@"UIWindowDidBecomeKeyNotification" object:nil];
    [_timer invalidate];[_coverWatch invalidate];[_lease restore];[_host removeFromSuperview];
}
// 2.08: the wake-up edge. Only meaningful while the watcher is idling because the
// desktop is covered; while the video is live the 60 Hz path is already running.
- (void)keyWindowBecameKey:(NSNotification *)note {
    if(!self.coverWatch)return;
    if(!self.playback.frozen && !self.appAway)return;
    self.probeBurstUntil=CACurrentMediaTime()+1.0;
    self.probeCountAt=0;
    if(!self.updating && !self.suspended)[self update];
}
- (void)syncGeometry {
    // 1.32: the live superview, never `container` - on the Home path the surface
    // hangs off the Home view, which is also the geometry target. When the host
    // is not attached, `container` is the wallpaper and the bounds would be the
    // wrong size; keep the retained frame and let the next -update repair it.
    if(self.updating || self.suspended || self.host.hidden)return;
    UIView *container=self.host.superview;if(!container || !LMVLockVideoRectValid(container.bounds))return;
    // 1.33: the same size rule the update path uses - on the Home host this stops
    // above the dock strip, so a layout pass cannot quietly grow it back over the
    // dock and reintroduce the dock problem.
    CGRect geometry=LMVDesktopVideoBoundsFor(container,self.homeHostGeometry);
    // Already-owned local repair only. Never discover windows/scan pure-content
    // trees, change playback intent or enqueue global refresh from layout.
    if(!CGRectEqualToRect(self.host.frame,geometry)) {
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.host.frame=geometry;[self.playback layoutInBounds:self.host.bounds];
        [CATransaction commit];
    }
    // The suppress-lease only ever lives on the wallpaper branch. `held` is nil
    // on the Home path (no lease is taken there), so this is already a no-op.
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
            // 1.32: 1 s -> 2 s. This walks every window's whole controller tree
            // (budget 160 nodes) and it is a DISCOVERY pass, not a per-frame
            // signal: the controllers it looks for are created once at Home
            // setup and survive. Halving the rate removes a periodic full-tree
            // walk from the steady state with no effect on the cover decisions,
            // which never read this list.
            if(now-live.lastDiscovery>=2){live.lastDiscovery=now;LMVDesktopDiscover();}
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
    // A sheet that was ALREADY up when we suspended is the withdrawal case too
    // (wake with the CoverSheet still half open): the warm video must bind.
    self.sheetPreexisting=self.lastSheetCover;self.sheetWallpaperShown=NO;
}
// 1.25: mark a presentation as still holding the desktop ONLY while the cover
// probe can still see it. `...SawCover` is set the moment the presented surface
// is really on screen during THIS presentation, so:
//   - switcher/CC actually visible -> opening freezes, closing resumes on the
//     first frame the surface leaves (no wait for the SpringBoard flag);
//   - probe cannot see them (the pre-0.0.138 regression) -> no cover was ever
//     recorded, the raw flag keeps holding the freeze exactly as before.
- (void)classifyPresentationForCoverOnScreen:(BOOL)coverOnScreen {
    if (coverOnScreen) self.geometryCoverSeen=YES;
    BOOL switcher=LMVDesktopSwitcherPresented(),cc=LMVDesktopControlCenterPresented();
    if (switcher) {if (coverOnScreen) self.switcherSawCover=YES;} else self.switcherSawCover=NO;
    if (cc) {if (coverOnScreen) self.ccSawCover=YES;} else self.ccSawCover=NO;
    self.effectiveSwitcherPresented=switcher && !(self.switcherSawCover && !coverOnScreen);
    self.effectiveControlCenterPresented=cc && !(self.ccSawCover && !coverOnScreen);
}
// 0.0.128: see the coverWatch property. The tick deliberately repeats only the
// CHEAP half of -update (window enumeration + geometry + frontmost probe); the
// moment the reveal starts it hands over to one full update.
- (void)startCoverWatch {
    if (self.coverWatch || self.suspended || !LMVLaunchReady) return;
    self.coverWatch=[CADisplayLink displayLinkWithTarget:self selector:@selector(coverWatchTick:)];
    // 1.32: cap the watcher at 60 Hz. Left unset, ProMotion hardware runs this at
    // 120 Hz - double the probe rate for a signal whose fastest meaningful change
    // (the app-exit cross-fade) is one frame wide at 60 Hz anyway, and two frames
    // of extra latency at worst on the reveal.
    self.coverWatch.preferredFramesPerSecond=60;
    [self.coverWatch addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)stopCoverWatch {
    [self.coverWatch invalidate];self.coverWatch=nil;
}
// 2.46: the desktop cadence is user-tunable now (设置 → 自定义参数 → 桌面背景视频).
// The read is cached for a second on purpose: this runs up to 60 times a second, and
// a preferences lookup per frame would be exactly the cost these knobs exist to remove.
static NSInteger LMVDesktopCadence(NSString *key) {
    static CFTimeInterval lastRead;
    static NSInteger idleFPS=30, coveredFPS=5;
    CFTimeInterval now=CACurrentMediaTime();
    if (now-lastRead>=1.0) {
        lastRead=now;
        idleFPS=LMVTuneValue(@"Desktop",@"IdleFPS");
        coveredFPS=LMVTuneValue(@"Desktop",@"CoveredFPS");
    }
    NSInteger value=[key isEqualToString:@"IdleFPS"]?idleFPS:coveredFPS;
    NSInteger lo=[key isEqualToString:@"IdleFPS"]?10:1;
    NSInteger hi=[key isEqualToString:@"IdleFPS"]?60:30;
    if (value<lo) value=lo;
    if (value>hi) value=hi;
    return value;
}
- (void)coverWatchTick:(CADisplayLink *)link {
    if (self.suspended || self.host.superview==nil || self.container==nil) {[self stopCoverWatch];return;}
    // 2.07: A COVERED DESKTOP IS A WATCHDOG, NOT A RENDERER.
    // While an app is in front the player is frozen, yet this tick kept running at
    // 60 Hz and - because the frozen branch deliberately skips the cheap gate -
    // ran the FULL probe every frame: cover rect, coverage test, foreground probe.
    // That is the whole time the user is inside any app, and it is why a phone
    // sitting in an app still burned several percent with nothing on screen.
    // 20 Hz costs at most 50 ms on the reveal, which is far below the ~300 ms
    // cross-fade it has to be caught inside, and removes two thirds of the cost.
    // 2.08: 10 Hz heartbeat while covered (was 20), 60 Hz while the desktop can be
    // seen, and a one second 60 Hz burst right after a key-window change so the
    // reveal is still caught on the frame it happens. Pure 0 Hz was tempting but a
    // stolen scene (app switcher, Control Center dismissal) does not always change
    // the key window, and a watchdog that can miss that would leave the video off.
    CFTimeInterval tickNow=CACurrentMediaTime();
    BOOL burst=tickNow<self.probeBurstUntil;
    // 2.10: with the key-window edge doing the waking, the heartbeat only has to be a
    // backstop for transitions that do not change the key window. 5 Hz is enough for
    // that and costs half of the 10 Hz version.
    // 2.46: the VISIBLE state was still 60 Hz, which is one main-thread wake per
    // frame for as long as the desktop video exists - even when the tick returns at
    // its cheap gate. A reveal can only be late by one interval, and the cross-fade
    // itself lasts 200-400 ms, so 30 Hz halves that wake traffic with no visible
    // difference; the 1 s burst after a key-window change stays at 60 Hz to catch the
    // exact frame the desktop is uncovered.
    NSInteger wantFPS=(self.playback.frozen || self.appAway)?
        (burst?60:LMVDesktopCadence(@"CoveredFPS")):LMVDesktopCadence(@"IdleFPS");
    if (link.preferredFramesPerSecond!=wantFPS) link.preferredFramesPerSecond=wantFPS;
    // 1.32: the CHEAP GATE, before anything expensive. This tick used to run the
    // full cover measurement - window enumeration, a class match per window, a
    // subview walk and presentation-layer conversions inside it - on EVERY frame,
    // 60-120 times a second, forever, on SpringBoard's main thread. On the steady
    // state it always reached the same conclusion: the desktop is exposed, nothing
    // is held. That repeat is the measurable cost of simply "desktop video is on",
    // and it is what made SpringBoard's CPU high while the video was playing.
    //   - FROZEN (or hidden) runs the full probe every frame, exactly as before.
    //     This is the state that must catch a REVEAL on the exact frame, and a
    //     frozen player costs no decode - this is the cheap side of the trade, and
    //     it is what keeps the app-exit and Control-Center-dismiss resume at zero
    //     delay.
    //   - PLAYING re-measures only when the visible-window count moved or a full
    //     probe has not run for a second. The count is the one cheap signal every
    //     transition produces; the ceiling means nothing can be missed for longer
    //     than that, so every edge case keeps a bounded lateness while the steady
    //     state stops paying for a probe whose answer cannot change.
    //   - `appAway` bypasses the gate: the exit release is evaluated per frame on
    //     purpose and must never be starved by it.
    if (!self.host.hidden && !self.playback.frozen && !self.appAway) {
        CFTimeInterval gateNow=CACurrentMediaTime();
        // 2.07: THE WINDOW COUNT IS CHEAP, BUT NOT FREE AT 60 Hz.
        // LMVDesktopVisibleWindowCount walks every scene and every window, and this
        // tick runs up to 60 times a second for as long as the desktop video plays.
        // On a phone with a dozen windows that is the largest steady-state cost of
        // simply "desktop video is on" - the decoder is not the only one working.
        // 20 Hz is three times cheaper and still spots a reveal within 50 ms, which
        // is under the cross-fade's own duration.
        // 2.46: 10 Hz instead of 20 Hz. The count only decides whether a FULL probe
        // is worth running; the reveal itself is still evaluated on every tick.
        if (gateNow-self.probeCountAt < .1) return;
        self.probeCountAt=gateNow;
        NSUInteger visibleWindows=LMVDesktopVisibleWindowCount();
        if (visibleWindows==self.probeWindowCount && gateNow-self.probeFullAt<1.0) return;
        self.probeWindowCount=visibleWindows;self.probeFullAt=gateNow;
    }
    BOOL unknown=NO,appCover=NO,switcherCover=NO,ccCover=NO,sheetCover=NO,sheetFullCover=NO;
    CGRect cover=LMVDesktopCoverRect(self.container.window,&unknown,&appCover,&switcherCover,&ccCover,&sheetCover,&sheetFullCover);
    if (unknown) return;
    BOOL fullyCovered=LMVDesktopFullyCovered(self.container,cover);
    NSInteger fg=LMVDesktopForeground();
    [self classifyPresentationForCoverOnScreen:switcherCover||ccCover||sheetCover||appCover||!CGRectIsEmpty(cover)];
    // 1.25: the same zero-delay app-exit release, evaluated EVERY frame - the
    // 0.2 s update cadence would otherwise be the delay floor.
    if (fg==-1) {self.appAway=YES;self.appLeftAt=0;}
    else if (self.appAway) {
        CFTimeInterval appNow=CACurrentMediaTime();
        if (self.appLeftAt<=0) self.appLeftAt=appNow;
        BOOL appSurfaceUp=appCover;
        BOOL appReleaseWindow=(appNow-self.appLeftAt<=0.8);
        if (appSurfaceUp && !appReleaseWindow) self.appAway=NO;
        if ((appReleaseWindow || !appSurfaceUp) && (appSurfaceUp || switcherCover)) {
            fullyCovered=NO;
            appCover=NO;
            switcherCover=NO;
        }
    }
    BOOL presented=self.effectiveSwitcherPresented||self.effectiveControlCenterPresented;
    // 1.25: the tick must be silent for exactly as long as the state the update
    // produced still HOLDS, and fire the frame that state ends. Listing the
    // reasons one by one left the GEOMETRY cover out: with a switcher/CC/app
    // surface on screen at fg==1 the tick matched none of the listed reasons,
    // fired EVERY frame and ran a full update each time - the device log shows
    // 89 updates in 2 s (up to 4.24 ms each) with cover-watch-reveal every
    // 8-17 ms while the switcher was up, and that stutter is what made the
    // reveal feel slow. One condition, evaluated in both directions, cannot
    // drift from the update's freeze rule again.
    BOOL held=presented || sheetFullCover ||
        (fullyCovered && (fg!=1 || switcherCover || ccCover || appCover));
    if (self.host.hidden || self.playback.frozen) {
        if (held) return;                            // still exactly what we froze on
    } else if (!held) return;                        // still exactly what we play on
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
    LMVDesktopStage("find",coverPerf0);
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
    BOOL appWindowCover=NO,switcherCover=NO,ccCover=NO,sheetCover=NO,sheetFullCover=NO;
    CFTimeInterval stageCover=CACurrentMediaTime();
    BOOL unknownCover=NO;CGRect cover=container?LMVDesktopCoverRect(container.window,&unknownCover,&appWindowCover,&switcherCover,&ccCover,&sheetCover,&sheetFullCover):CGRectZero;
    LMVDesktopStage("cover",stageCover);
    // 1.25: ZERO delay on an app exit. The frontmost probe is the earliest true
    // signal - it flips the moment the app stops being frontmost, while its
    // surface (and the switcher shell behind it) stay on screen for the whole
    // exit animation. For a short window after that flip nothing counts as a
    // cover, so the resume lands on the very frame the probe changes. A switcher
    // opened FROM an app therefore plays for that window and freezes again when
    // its card (the same SBWindow surface) is on screen - accepted trade-off.
    NSInteger foreground=LMVDesktopForeground();
    BOOL appExitRelease=NO;
    if (foreground==-1) {self.appAway=YES;self.appLeftAt=0;}
    else if (self.appAway) {
        CFTimeInterval appNow=CACurrentMediaTime();
        if (self.appLeftAt<=0) self.appLeftAt=appNow;
        BOOL appSurfaceUp=appWindowCover;                          // read BEFORE clearing
        BOOL appReleaseWindow=(appNow-self.appLeftAt<=0.8);
        // 1.25: the release does NOT expire while the app is off screen. The
        // remnant switcher shell keeps hanging around and, with a time-bounded
        // release, froze the desktop again 0.44 s after the resume - the video
        // played, stopped, played: the reported "卡一下". Only a real switcher
        // CARD (the app surface coming back) ends the release.
        if (appSurfaceUp && !appReleaseWindow) self.appAway=NO;
        // The release only has something to release when the app surface or the
        // remnant switcher shell is actually there - otherwise it must not touch
        // the geometry at all (the notification sheet and the Control Center are
        // judged entirely by their own rules).
        if ((appReleaseWindow || !appSurfaceUp) && (appSurfaceUp || switcherCover)) {
            appExitRelease=YES;
            appWindowCover=NO;                                     // the app surface never holds
            switcherCover=NO;                                      // ...nor the remnant shell
        }
    }
    // A fresh authenticated unlock is authoritative even while CoverSheet is
    // still withdrawing. Waiting for cover==empty makes Home's first exposed
    // transaction show the original wallpaper before the warm video attaches.
    if (screenKnown && !blank && lockKnown && !locked && !unknownCover &&
        (foreground==1 || homeConfirmed)) self.authenticatedSession=YES;
    // 1.25: the release window is not a cover at all. Clearing only the cover
    // FLAGS left `covered` true, so `play` stayed false and the layer was hidden
    // for the release (device log: layer=0 on the exit tick, which is the
    // wallpaper showing through before the video comes back).
    BOOL covered=container && LMVDesktopFullyCovered(container,cover) && !appExitRelease;
    // 0.0.138: SpringBoard's own presentation state, OR-ed with the geometry.
    // It is the authority for the switcher and the Control Center: while either
    // is presented the desktop is not what the user is looking at, so the video
    // freezes and the audio stops even when no covering window matched.
    // 1.25: classified against what the pixels show (see the method): the flag
    // keeps a freeze only while its surface is still on screen.
    BOOL coverOnScreen=switcherCover||ccCover||sheetCover||appWindowCover||!CGRectIsEmpty(cover);
    [self classifyPresentationForCoverOnScreen:coverOnScreen];
    BOOL switcherPresented=self.effectiveSwitcherPresented;
    BOOL ccPresented=self.effectiveControlCenterPresented;
    // 1.25: a desktop with NOTHING covering it is proof enough that the desktop
    // is what is on screen - the frontmost probe and the Home lifecycle callbacks
    // both lag the app-exit animation, and waiting for them was the reported
    // "App 退出到桌面后视频和声音太慢". Guarded by geometryCoverSeen, so a device
    // whose probe never sees a cover cannot reach this by accident.
    BOOL desktopExposed=self.geometryCoverSeen && !coverOnScreen && !unknownCover;
    // 0.0.123: opening an app made the desktop video fall back to the system
    // wallpaper for a moment. `home=1` (the Home view is still on screen) held
    // steady while `foreground` flipped to -1 for the launch, so `env` dropped and
    // the surface was torn down to its poster. A confirmed Home view is DIRECT
    // evidence that the desktop is on display - the frontmost probe is only
    // circumstantial and must not be able to veto it. `foreground>=0` was
    // redundant on top of `(foreground==1 || homeConfirmed)` and turned a
    // transient probe reading into a visible teardown.
    BOOL environment=screenKnown && !blank && lockKnown && self.authenticatedSession &&
        (foreground==1 || homeConfirmed || desktopExposed) && !unknownCover;
    BOOL configured=self.enabled && self.path.length && self.revision.length;
    LMVDesktopControllerRecord *ownerRecord=objc_getAssociatedObject(self.attachmentController,&LMVDesktopControllerRecordKey);
    // 1.25: an exposed desktop outranks a stale Home lifecycle record as well.
    // The app-exit transition reports the Home controller back only at the very
    // end of the animation, so the record said "away" while the desktop was
    // already on screen - the video stayed frozen into an exposed desktop.
    BOOL lifecycleAway=!locked && container==self.container && ownerRecord.known &&
        !ownerRecord.visible && !desktopExposed;
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
    // 0.0.137: the switcher, the Control Center and a FULL notification pull hide
    // the layer at fg==1 too (the user asked for freeze+HIDE). Hiding behind a
    // translucent surface is safe now: the suppress-lease STAYS applied while
    // the layer is hidden, so the wallpaper content can never show through the
    // blur - only a pull that has covered the screen restores it on purpose.
    // 1.25: a HALF-pulled sheet is not a cover at all - the desktop is still
    // on display underneath, so it neither counts here nor hides the layer.
    if (covered && (foreground!=1 || switcherCover || ccCover || sheetFullCover)) {
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
        // 1.39: 回到 1.30 的挂载位置 —— 视频挂在 _SBWallpaperSecureWindow 的壁纸
        // 内容里，而不是主屏窗口。依据是实锤的：安全窗口的内容不参与系统毛玻璃的
        // 背面采集，dock 在 1.30 因此完全正常；1.31 搬进主屏窗口后 dock 就开始采样
        // 这块视频。1.38 试过用私有的 backdrop 分组名把这一层摘出去，用户实测无效，
        // 所以回到唯一被验证过「dock 正常」的位置 —— 安全窗口里靠已有的壁纸
        // 承租显隐，主屏窗口本就透明透出这一层，不需要额外的遮蔽。
        // 1.39: the surface lives ONLY in the secure wallpaper window now (the 1.30
        // position). The Home-host path that 1.31 added - and 1.33-1.38 kept
        // narrowing with dock-strip concessions - is gone, because that path is what
        // put the video INSIDE the Home window where the dock's backdrop could sample
        // it (the reported dock vanishing during a long-press menu). With no Home
        // branch to take, there is nothing here but the secure-window mount.
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
        // 1.25: the long-press context menu can hide the whole wallpaper branch,
        // and our layer goes with it - the menu then shows its own empty
        // background ("菜单白的一下"). When the host container itself is hidden
        // or faded out, borrow ITS parent for as long as that lasts: the layer
        // stays right above the wallpaper view, under the icons, so the menu
        // blurs the video instead of nothing.
        UIView *hostParent=container;
        if ((container.hidden || container.alpha<0.01) && container.superview!=nil) hostParent=container.superview;
        if (hostParent!=container) {
            // 1.32: identical rule to the Home branch - park the surface at the
            // bottom of the borrowed parent rather than right above the wallpaper
            // view, so no existing sibling index is ever disturbed.
            if(self.host.superview!=hostParent ||
               [hostParent.subviews indexOfObjectIdenticalTo:self.host]!=0) {
                [self.host removeFromSuperview];
                [hostParent insertSubview:self.host atIndex:0];
            }
        }
        UIView *geometryTarget=container;
        // 1.39: the surface is the full container (1.32) and lives in the secure
        // wallpaper window, so homeHostGeometry is always NO here. The dock's
        // floating blur samples only its OWN window, and the secure window is a
        // different one - that is why the dock no longer tracks the video.
        self.homeHostGeometry=NO;
        CGRect videoBounds=LMVDesktopVideoBoundsFor(geometryTarget,NO);
        BOOL geometryChanged=!CGRectEqualToRect(self.host.frame,videoBounds);
        [CATransaction begin];[CATransaction setDisableActions:YES];
        if(geometryChanged)self.host.frame=videoBounds;
        if(self.host.alpha!=1)self.host.alpha=1;
        // 0.0.124: do not composite a layer that nothing can see. The layer stays
        // attached to the same superview, so it is back the instant the cover goes
        // away; this only removes wasted work and cannot hide the desktop.
        // 0.0.139: hide ONLY behind an opaque APP cover or under a notification
        // pull. Behind the translucent switcher/Control Center the frozen video
        // frame must stay VISIBLE (the user asked for exactly that, and the
        // suppress-lease stays applied so no wallpaper can show through).
        BOOL opaqueAppCover=opaqueCover && !(switcherCover || ccCover);
        BOOL hostHidden=opaqueAppCover || (sheetFullCover && !self.sheetPreexisting);
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
        BOOL hostHidden=opaqueAppCover || (sheetFullCover && !self.sheetPreexisting);
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
    if (!sheetFullCover) self.sheetWallpaperShown=NO;
    // 1.25: a notification pull no longer silences the desktop - the user asked
    // for sound whenever the video is still playing (下拉/收回通知中心 视频有声).
    // A pull that has COVERED the screen still freezes and silences (below).
    BOOL audioCovered=appForeground || (visible && (switcherPresented || ccPresented)) ||
        (visible && covered && (sheetFullCover || switcherCover || ccCover || foreground!=1));
    BOOL wasCovered=self.coveredNow;
    self.coveredNow=audioCovered;
    // 1.75: pause DECODING the moment the desktop is not visible (app in front,
    // switcher, Control Centre, full sheet). The player is only paused, never
    // torn down, and an AVPlayerLayer keeps its last frame - so the resume is a
    // single play call and the next frame appears immediately. The old model
    // kept decoding behind the app for the "instant reveal" feel, which is what
    // kept the CPU busy.
    if (LMVLaunchReady && self.playback.player) {
        SEL pauseSel=NSSelectorFromString(@"pause"), playSel=NSSelectorFromString(@"play");
        if (audioCovered) {
            if ([self.playback.player respondsToSelector:pauseSel])
                ((void(*)(id,SEL))objc_msgSend)(self.playback.player,pauseSel);
        } else if (self.playback.wantsPlayback) {
            if ([self.playback.player respondsToSelector:playSel])
                ((void(*)(id,SEL))objc_msgSend)(self.playback.player,playSel);
        }
    }
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
    self.lastSheetCover=sheetCover;
    if (!sheetCover) self.sheetPreexisting=NO;
    // 1.25: only a pull that has COVERED the screen shows the original
    // wallpaper behind the sheet (the layer is hidden above and the lease is
    // released). A partial pull is not a cover: the desktop is still visible
    // underneath and must keep showing the video - restoring the wallpaper
    // there is exactly the reported "下拉一半，桌面视频变成原壁纸".
        // Only over a LIVE desktop: on the lock screen the sheet is up with no
        // surface, and flagging it there suppressed the lease re-acquisition at
        // the following unlock tick - the wallpaper then stayed exposed.
        if (visible && sheetFullCover && !self.sheetPreexisting) {
            if (self.lease) {[self.lease restore];self.lease=nil;}
            self.sheetWallpaperShown=YES;
        }
        // 0.0.140/1.25: the notification sheet is a cover until the pull
        // reaches the bottom. Pulled HALF way it is not a cover at all - the
        // desktop is on display underneath, so the video keeps playing AND stays
        // VISIBLE (no hide, no wallpaper). Only a pull that has covered the
        // screen freezes; the layer is hidden and the wallpaper restored on the
        // same tick. The switcher and the Control Center freeze as soon as they
        // are presented, and any full cover freezes.
        BOOL freeze=appForeground || (visible && (switcherPresented || ccPresented)) ||
            (visible && covered && (sheetFullCover || switcherCover || ccCover || foreground!=1)),
            play=visible && !covered && !switcherPresented && !ccPresented && !(sheetFullCover && !self.sheetPreexisting);
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
            // 0.0.137/1.25: a FULL pull shows the original wallpaper on
            // purpose ("下滑到底才出现原壁纸"); a partial pull keeps the video
            // VISIBLE and PLAYING, because the desktop it is drawn on is still
            // exposed. The lease re-acquires as soon as the sheet slides back.
        } else if(play) {
            if(self.playback.frozen)[self.playback holdCurrentFrame:NO];
            else if(!self.playback.wantsPlayback || self.playback.posterOnlyVisible)
                [self.playback setVisible:YES];
            else [self.playback resumeIfNeeded];
        } else if(!(sheetFullCover && !self.sheetPreexisting) && (self.playback.wantsPlayback || self.playback.frozen || self.playback.posterOnlyVisible))
            // 0.0.140: while a COVERING sheet is up the layer is hidden on
            // purpose but the player must KEEP RUNNING - stopping it here is what
            // made the release feel slow (a stopped player restarts from scratch).
            // 1.25: a partial pull never gets here - the layer is visible and
            // the video must not be stopped.
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
        // 1.30: the lines below (visual / surfaces / panel / overlay) each rebuild a
        // 3000+ character serialisation of the WHOLE view tree, and they build it on
        // the main thread - the file write is async, the string is not. That is what
        // the desktop channel's perf line has been reporting (slow=10, max=6.99 ms
        // against the CC channel's 0.51 ms). Throttled to 2 s: state changes are
        // still recorded, but a tick no longer serialises the tree every pass.
        static NSTimeInterval lastShapeDump=0;
        NSTimeInterval shapeNow=CACurrentMediaTime();
        // 1.76.4: was 2.0. A measured dump costs ~1.3 s with a full notification
        // list, so sampling every two seconds had the observer eating two thirds of
        // the main thread - manufacturing the very stall it was meant to record.
        // Ten seconds still catches every change that matters (they are change-only).
        BOOL shapeDump=(shapeNow-lastShapeDump>=10.0);
        if(shapeDump)lastShapeDump=shapeNow;
    // 0.0.124: `composited` is the layer that backboardd actually has to composite
    // and `decode` is whether the decoder is running - together they tell apart
    // "paused but still on screen" (CPU wasted on compositing) from "still decoding
    // while invisible" (CPU wasted on decode).
    // 1.30: the format string asked for frozen first but the argument list passed
    // appForeground there, so every diagnostic line printed appfg under the name
    // "frozen" - the field that decides whether the decoder is stopped was the one
    // field the log got wrong. Both are printed now.
    NSString *status=[NSString stringWithFormat:@"desktop-video visible=%d frozen=%d appfg=%d home=%d host=%@ path=%d layer=%d contentHidden=%d foreground=%ld cover=%d blank=%llu locked=%llu session=%d covered=%d env=%d geo=%d held=%.2f teardown=%lu hostHidden=%d poster=%d shown=%d composited=%d decode=%d opaque=%d sheet=%d sheetFull=%d appc=%d sw=%d cc=%d swEff=%d ccEff=%d geoSeen=%d",
        visible,(int)self.playback.frozen,(int)appForeground,homeConfirmed,container?NSStringFromClass(container.class):@"none",configured,pixels,self.lease.applied,
        (long)foreground,!CGRectIsEmpty(cover),(unsigned long long)blank,(unsigned long long)locked,
        (int)self.authenticatedSession,(int)covered,(int)environment,(int)(container && LMVDesktopGeometryVisible(container)),
        (self.holdSince>0?holdNow-self.holdSince:0.0),(unsigned long)self.teardowns,
        (int)self.host.hidden,(int)(self.playback.posterLayer.contents!=nil),(int)(!self.playback.renderLayer.hidden),
        (int)(self.host.superview!=nil && !self.host.hidden),
        (int)(self.playback.wantsPlayback && !self.playback.frozen),(int)opaqueCover,
        (int)sheetCover,(int)sheetFullCover,(int)appWindowCover,(int)switcherCover,(int)ccCover,
        (int)self.effectiveSwitcherPresented,(int)self.effectiveControlCenterPresented,(int)self.geometryCoverSeen];
    if(![status isEqualToString:self.status]){self.status=status;LMVDiagnostic(status);}
    // 1.25: the host chain - proves whether the wallpaper branch (our layer's
    // parent) was hidden or faded by a system overlay, which is what made the
    // video vanish behind the long-press menu.
    if (container) {
        NSString *hostStatus=[NSString stringWithFormat:@"desktop-host container=%@ hidden=%d alpha=%.2f super=%@ superIdx=%ld hostSuper=%@ hostIdx=%ld",
            NSStringFromClass(container.class),(int)container.hidden,container.alpha,
            container.superview?NSStringFromClass(container.superview.class):@"none",
            container.superview?(long)[container.superview.subviews indexOfObjectIdenticalTo:container]:-1,
            self.host.superview?NSStringFromClass(self.host.superview.class):@"none",
            self.host.superview?(long)[self.host.superview.subviews indexOfObjectIdenticalTo:self.host]:-1];
        static NSString *lastHostStatus=nil;
        if (![hostStatus isEqualToString:lastHostStatus]) {lastHostStatus=[hostStatus copy];LMVDiagnostic(hostStatus);}
        // 1.31: where the surface actually landed on the Home window. One line tells
        // "the video is not on the desktop" apart from "it went to another window":
        // our own view is marked with *, next to the icon container's index.
        {
            UIView *homeIcons=nil;
            UIView *home=LMVDesktopHomeHostView(&homeIcons);
            if (home) {
                NSMutableString *order=[NSMutableString new];
                NSUInteger i=0;
                for (UIView *child in home.subviews) {
                    if (i++>=8) {[order appendString:@"…"];break;}
                    [order appendFormat:@"%@%@ ",child==self.host?@"*":@"",NSStringFromClass(child.class)];
                }
                NSString *homeStatus=[NSString stringWithFormat:@"desktop-home win=%@ subviews=[%@] icons=%ld host=%ld attached=%d %.0fx%.0f",
                    NSStringFromClass(home.window.class),order,
                    (long)[home.subviews indexOfObjectIdenticalTo:homeIcons],
                    (long)[home.subviews indexOfObjectIdenticalTo:self.host],
                    (int)(self.host.superview!=nil),home.bounds.size.width,home.bounds.size.height];
                static NSString *lastHomeStatus=nil;
                if (![homeStatus isEqualToString:lastHomeStatus]) {lastHomeStatus=[homeStatus copy];LMVDiagnostic(homeStatus);}
            }
        }
    }
    // 1.25: WHY the video cannot be seen while a system overlay is up (the
    // long-press context menu reads as blank behind it). Everything else in this
    // log proves what the PLUGIN did - and the 1.25 device log showed all of it
    // staying correct through the whole press (layer=1, hostHidden=0, decode=1)
    // while the menu background still read as empty. The remaining suspects are
    // all in the SYSTEM's own hierarchy, which the plugin never looks at:
    //   - which WINDOW our layer lives in (a "secure" wallpaper window is excluded
    //     from system backdrop capture, which would explain a menu whose blur
    //     cannot see the video at all),
    //   - which windows sit ABOVE ours (the only things that can cover us),
    //   - what the menu overlay window is actually built from.
    // Printed whenever any of it changes; diagnostics only, no behaviour.
    if (self.host.superview!=nil) {
        NSMutableString *chain=[NSMutableString new];
        UIView *walk=self.host;
        NSInteger steps=0;
        BOOL chainVisible=YES;
        while (walk && steps++<24) {
            if (walk.hidden || walk.layer.hidden || walk.alpha<0.01) chainVisible=NO;
            [chain appendFormat:@"%@(h%d/l%d/a%.2f)>",NSStringFromClass(walk.class),
                (int)walk.hidden,(int)walk.layer.hidden,walk.alpha];
            if ([walk isKindOfClass:UIWindow.class]) break;
            walk=walk.superview;
        }
        UIWindow *hostWindow=self.host.window;
        NSArray *wins=nil;
        NSInteger hostIdx=-1;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            NSArray *candidate=((UIWindowScene *)scene).windows;
            for (NSUInteger i=0;i<candidate.count;i++) {
                if (candidate[i]==hostWindow) {hostIdx=(NSInteger)i;break;}
            }
            if (hostIdx>=0) {wins=candidate;break;}
        }
        NSMutableString *above=[NSMutableString new];
        NSMutableString *menus=[NSMutableString new];
        for (NSUInteger i=0;wins && i<wins.count;i++) {
            UIWindow *window=wins[i];
            if (window.hidden || window.alpha<.01) continue;
            NSString *name=NSStringFromClass(window.class);
            if ([name containsString:@"Platter"] || [name containsString:@"Menu"] ||
                [name containsString:@"Context"] || [name containsString:@"Snapper"] ||
                [name containsString:@"Portal"] || [name containsString:@"FloatingDock"])
                [menus appendFormat:@"%@@%lu ",name,(unsigned long)i];
            if (hostIdx>=0 && (NSInteger)i>(NSInteger)hostIdx && above.length<200)
                [above appendFormat:@"%@@%lu(a%.2f) ",name,(unsigned long)i,window.alpha];
        }
        // The top-most menu-like window, two levels deep: enough to reveal the
        // backdrop/material views its background is actually made of.
        NSString *menuShape=@"none";
        for (NSInteger i=(NSInteger)(wins?wins.count:0)-1;i>=0;i--) {
            UIWindow *window=wins[(NSUInteger)i];
            if (window.hidden || window.alpha<.01) continue;
            NSString *name=NSStringFromClass(window.class);
            if (!([name containsString:@"Platter"] || [name containsString:@"Menu"] || [name containsString:@"Context"])) continue;
            NSMutableString *shape=[NSMutableString new];
            for (UIView *child in window.subviews) {
                if (shape.length>200) break;
                [shape appendFormat:@"%@[",NSStringFromClass(child.class)];
                NSUInteger n=0;
                for (UIView *grand in child.subviews) {
                    if (n++>=6) break;
                    [shape appendFormat:@"%@,",NSStringFromClass(grand.class)];
                }
                [shape appendString:@"] "];
            }
            menuShape=[NSString stringWithFormat:@"%@:%@",name,shape.length?shape:@"empty"];
            break;
        }
        NSString *visual=nil;
        if(shapeDump)visual=[NSString stringWithFormat:@"desktop-visual win=%@ idx=%ld/%lu vis=%d chain=%@ above=%@ menus=%@ menuShape=%@",
            hostWindow?NSStringFromClass(hostWindow.class):@"none",(long)hostIdx,
            (unsigned long)(wins?wins.count:0),(int)(chainVisible && !self.host.hidden),chain,
            above.length?above:@"none",menus.length?menus:@"none",menuShape];
        static NSString *lastVisual=nil;
        if (visual && ![visual isEqualToString:lastVisual]) {lastVisual=[visual copy];LMVDiagnostic(visual);}
    }
    // 1.25/1.25: the blind spots of the window list above. A third-party gesture
    // tweak (SquidGesturePro) keeps its panel in SGPanelWindow, and the window list
    // alone cannot show when that panel is up: the window exists the whole time, and
    // the panel is a VIEW inside it (the 1.25 device log: SGPanelWindow(h0/a1.00) in
    // every sample, and it belongs to a different UIWindowScene than the video, so no
    // other line of this log ever looked inside it).
    // This line therefore walks EVERY scene, prints each visible window's shape THREE
    // levels deep, marks which scene a window belongs to, and lists only the windows
    // that belong to no scene at all. Diagnostics only, change-only.
    {
        NSMutableString *scenes=[NSMutableString new];
        NSMutableArray *allSceneWins=[NSMutableArray new];
        NSInteger sceneIdx=0;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            NSArray *wins=((UIWindowScene *)scene).windows;
            [scenes appendFormat:@"s%ld[",(long)sceneIdx++];
            for (UIWindow *window in wins) {
                if (window && ![allSceneWins containsObject:window]) [allSceneWins addObject:window];
                if (window.hidden || window.alpha<.01) continue;
                // 1.26: the budget is per WINDOW, not for the whole line. The old
                // hard break dropped every window after the first ~1500 characters
                // (SBHomeScreenWindow alone eats most of it), which is why a panel
                // window could be missing from one sample and present in the next.
                if (scenes.length>4000) {[scenes appendFormat:@"%@(a%.2f){…} ",NSStringFromClass(window.class),window.alpha];continue;}
                [scenes appendFormat:@"%@(a%.2f){",NSStringFromClass(window.class),window.alpha];
                NSUInteger n=0;
                for (UIView *child in window.subviews) {
                    if (n++>=6) break;
                    [scenes appendFormat:@"%@[",NSStringFromClass(child.class)];
                    NSUInteger m=0;
                    for (UIView *grand in child.subviews) {
                        if (m++>=5) break;
                        [scenes appendFormat:@"%@^",NSStringFromClass(grand.class)];
                        NSUInteger k=0;
                        for (UIView *great in grand.subviews) {
                            if (k++>=3) break;
                            [scenes appendFormat:@"%@,",NSStringFromClass(great.class)];
                        }
                    }
                    [scenes appendString:@"]"];
                }
                [scenes appendString:@"}"];
            }
            [scenes appendString:@"] "];
        }
        NSMutableString *legacy=[NSMutableString new];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if ([allSceneWins containsObject:window]) continue;
            [legacy appendFormat:@"%@(h%d/a%.2f) ",NSStringFromClass(window.class),(int)window.hidden,window.alpha];
        }
#pragma clang diagnostic pop
        NSString *shape=nil;
        if(shapeDump)shape=[NSString stringWithFormat:@"desktop-surfaces %@legacy=%@",scenes,legacy.length?legacy:@"none"];
        static NSString *lastShape=nil;
        if (shape && ![shape isEqualToString:lastShape]) {lastShape=[shape copy];LMVDiagnostic(shape);}
    }
    // 1.25: the GEOMETRY the panel feature needs. The SquidGesture panel is a
    // rounded card in the lower part of the screen (the user's screenshot: it does
    // not fill the screen), so a video background behind it has to be laid out to
    // that exact rect - a class-name list cannot show it. Change-only: every
    // panel-like window three levels deep WITH FRAMES, plus our own layer.
    {
        NSMutableString *panels=[NSMutableString new];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha<.01) continue;
                NSString *name=NSStringFromClass(window.class);
                if (!([name containsString:@"Panel"] || [name containsString:@"Menu"] || [name containsString:@"Platter"])) continue;
                [panels appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f{",name,
                    window.frame.origin.x,window.frame.origin.y,window.frame.size.width,window.frame.size.height];
                NSUInteger n=0;
                for (UIView *child in window.subviews) {
                    if (n++>=6) break;
                    [panels appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f[",NSStringFromClass(child.class),
                        child.frame.origin.x,child.frame.origin.y,child.frame.size.width,child.frame.size.height];
                    NSUInteger m=0;
                    for (UIView *grand in child.subviews) {
                        if (m++>=6) break;
                        [panels appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f,",NSStringFromClass(grand.class),
                            grand.frame.origin.x,grand.frame.origin.y,grand.frame.size.width,grand.frame.size.height];
                    }
                    [panels appendString:@"]"];
                }
                [panels appendString:@"} "];
            }
        }
        if (self.host.superview!=nil) {
            UIWindow *hostWindow=self.host.window;
            [panels appendFormat:@"host=%@@%.0f,%.0f,%.0f,%.0f hidden=%d win=%@",
                NSStringFromClass(self.host.class),self.host.frame.origin.x,self.host.frame.origin.y,
                self.host.frame.size.width,self.host.frame.size.height,(int)self.host.hidden,
                hostWindow?NSStringFromClass(hostWindow.class):@"none"];
        }
        NSString *geometry=nil;
        if(shapeDump)geometry=[NSString stringWithFormat:@"desktop-panel %@",panels.length?panels:@"none"];
        static NSString *lastGeometry=nil;
        if (geometry && ![geometry isEqualToString:lastGeometry]) {lastGeometry=[geometry copy];LMVDiagnostic(geometry);}
    }
    // 1.42: every window with its LEVEL, hidden state and root-view-controller
    // class. CopyVault keeps a permanent CVPanelWindow and only fills it while its
    // panel is up, so a class-name list alone cannot say which window a panel
    // belongs to, nor whether a brand-new window appeared for it. Hidden windows
    // are listed ON PURPOSE - a window that exists only while its panel is open is
    // precisely what has to be visible here.
    {
        NSMutableString *meta=[NSMutableString new];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                UIViewController *rvc=window.rootViewController;
                [meta appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f lvl=%.0f hid=%d a=%.2f rvc=%@ ",
                    NSStringFromClass(window.class),window.frame.origin.x,window.frame.origin.y,
                    window.frame.size.width,window.frame.size.height,window.windowLevel,
                    (int)window.hidden,window.alpha,rvc?NSStringFromClass(rvc.class):@"none"];
            }
        }
        static NSString *lastMeta=nil;
        if (meta.length && ![meta isEqualToString:lastMeta]) {
            lastMeta=[meta copy];
            LMVDiagnostic([NSString stringWithFormat:@"desktop-window-meta %@",meta]);
            // 1.65: attribute every panel/suspect class to the dylib that
            // defines it. An obfuscated window class (VLBYCK) and its
            // controller (BBTTIO) can then be named as CopyLogX or cleared,
            // instead of being inferred from "looks like the other panels".
            NSMutableString *owners=[NSMutableString new];
            for (NSString *name in @[@"VLBYCK",@"FJLOLX",@"BBTTIO",@"blq_sRvRsJzPulGq",
                                     @"blq_drXrlngjfxKW",@"SGPanelWindow",@"SGPanelViewController",
                                     @"CVPanelWindow",@"CVPanelViewController"]) {
                Class cls=NSClassFromString(name);
                const char *image=cls?class_getImageName(cls):NULL;
                NSString *imageName=image?[NSString stringWithUTF8String:image].lastPathComponent:@"?";
                [owners appendFormat:@"%@=%@ ",name,imageName];
            }
            LMVDiagnostic([NSString stringWithFormat:@"window-owner %@",owners]);
        }
    }
    // 1.69: CopyLogX never appears as a window we can name, and the panel is
    // gone by the time a log is exported. Its dylib is injected into SpringBoard
    // though, so enumerate the classes that image defines - the window/view
    // class names are then known without ever catching the panel open. Runs
    // ONCE per process: objc_getClassList walks every class in SpringBoard.
    {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            int total=objc_getClassList(NULL,0);
            if (total<=0) return;
            Class *classes=(Class *)calloc((size_t)total,sizeof(Class));
            if (!classes) return;
            total=objc_getClassList(classes,total);
            NSMutableString *owned=[NSMutableString new];
            for (int i=0;i<total;i++) {
                Class cls=classes[i];
                const char *image=class_getImageName(cls);
                if (!image) continue;
                NSString *path=[NSString stringWithUTF8String:image];
                NSString *leaf=path.lastPathComponent;
                if (![leaf containsString:@"CopyLog"] && ![leaf containsString:@"copylog"]) continue;
                [owned appendFormat:@"%@(%@) ",NSStringFromClass(cls),leaf];
                if (owned.length>2400) {[owned appendString:@"…"];break;}
            }
            free(classes);
            LMVDiagnostic([NSString stringWithFormat:@"copylog-classes %@",owned.length?owned:@"none"]);
        });
    }
    // 1.42: the deep subtree of every panel-like window (see LMVDesktopPanelName).
    // Six levels, including windows that are not currently visible, so the shape of
    // a clipboard panel is captured even when the shallow three-level geometry only
    // shows an empty shell.
    {
        NSMutableString *trees=[NSMutableString new];
        NSMutableArray<UIWindow *> *panelWindows=[NSMutableArray new];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            [panelWindows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
        // 1.68: legacy windows (not attached to any scene) were never opened up.
        // A keyboard-side clipboard panel can be one of these, which explains a
        // panel that is visibly above the keyboard yet absent from every list.
        NSMutableArray<UIWindow *> *legacyWindows=[NSMutableArray new];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in UIApplication.sharedApplication.windows)
            if (window && ![panelWindows containsObject:window]) { [panelWindows addObject:window]; [legacyWindows addObject:window]; }
#pragma clang diagnostic pop
        for (UIWindow *window in panelWindows) {
            NSString *windowName=NSStringFromClass(window.class);
            BOOL legacy=[legacyWindows containsObject:window];
            // 1.67: a bare window parked at plugin level can still be the
            // real host. CopyLogX keeps two hidden UIWindows with no root
            // controller; neither carries Panel/Menu/Platter/Clipboard, so
            // the name test alone left them as unexplained lines.
            BOOL deep=LMVDesktopPanelName(windowName) ||
                (window.windowLevel>=1000000 && window.rootViewController==nil) || legacy;
            if (!deep || window.alpha<.01) continue;
            if (trees.length>3000) {[trees appendString:@"…"];break;}
            NSUInteger nodes=0;
            [trees appendFormat:@"%@%@|",legacy?@"legacy:":@"",windowName];
            LMVDesktopPanelTree(window,0,trees,&nodes);
            [trees appendString:@" "];
        }
        static NSString *lastTrees=nil;
        if (trees.length && ![trees isEqualToString:lastTrees]) {
            lastTrees=[trees copy];
            LMVDiagnostic([NSString stringWithFormat:@"desktop-panel-tree %@",trees]);
        }
    }
    // 1.66: CopyLogX is injected into SpringBoard (its Filter names
    // com.apple.springboard) but owns NO window - its clipboard panel is a view
    // above the keyboard, inside UITextEffectsWindow / SBMedusaHostedKeyboardWindow.
    // The window list can never name it, so dump those subtrees whenever they
    // change: the panel class and its user-set height appear right here.
    {
        NSMutableString *trees=[NSMutableString new];
        NSMutableArray<UIWindow *> *keyboardWindows=[NSMutableArray new];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            [keyboardWindows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in UIApplication.sharedApplication.windows)
            if (window && ![keyboardWindows containsObject:window]) [keyboardWindows addObject:window];
#pragma clang diagnostic pop
        for (UIWindow *window in keyboardWindows) {
            NSString *name=NSStringFromClass(window.class);
            if (![name isEqualToString:@"UITextEffectsWindow"] &&
                ![name isEqualToString:@"SBMedusaHostedKeyboardWindow"]) continue;
            if (window.hidden || window.alpha<.01) continue;
            if (trees.length>6000) break;
            NSUInteger nodes=0;
            [trees appendFormat:@"%@|",name];
            LMVDesktopPanelTree(window.rootViewController.viewIfLoaded,0,trees,&nodes);
            [trees appendString:@" "];
        }
        static NSString *lastKeyboard=nil;
        if (trees.length && ![trees isEqualToString:lastKeyboard]) {
            lastKeyboard=[trees copy];
            LMVDiagnostic([NSString stringWithFormat:@"keyboard-tree %@",trees]);
        }
    }
    // 1.67: name the Control Centre overlay EXACTLY as presented. Pulled down
    // over Notification Centre it can carry a different layer name than the one
    // the floating egg looks for, which is why the ball stayed hidden there.
    {
        BOOL coverUp=NO;
        NSMutableArray<UIWindow *> *ccWindows=[NSMutableArray new];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                NSString *name=NSStringFromClass(window.class);
                if ([name isEqualToString:@"SBCoverSheetWindow"] && !window.hidden && window.alpha>=.01) coverUp=YES;
                if ([name isEqualToString:@"SBControlCenterWindow"] && !window.hidden && window.alpha>=.01)
                    [ccWindows addObject:window];
            }
        }
        if (coverUp && ccWindows.count) {
            NSMutableString *cc=[NSMutableString new];
            for (UIWindow *window in ccWindows) {
                NSUInteger nodes=0;
                [cc appendFormat:@"%@{",NSStringFromClass(window.class)];
                LMVDesktopLayerTree(window.rootViewController.viewIfLoaded,0,cc,&nodes);
                [cc appendString:@"} "];
            }
            static NSString *lastCoverCC=nil;
            if (cc.length && ![cc isEqualToString:lastCoverCC]) {
                lastCoverCC=[cc copy];
                LMVDiagnostic([NSString stringWithFormat:@"cc-over-nc-tree %@",cc]);
            }
        }
    }
    // 1.26: the pop-ups that are NOT windows (AppTools and friends). A panel that
    // is PRESENTED into an existing window changes no window class, so neither the
    // window list nor the panel geometry above can see it - the device log only
    // ever showed it as an extra UITransitionView inside SBHomeScreenWindow. This
    // walks EVERY window (scene-borne AND legacy), finds the presentation
    // containers and prints their whole shape with frames, corner radii, alpha and
    // hidden state, so the mount level can be decided from the log alone.
    {
        NSMutableArray<UIWindow *> *everyWindow=[NSMutableArray new];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows)
                if (window && ![everyWindow containsObject:window]) [everyWindow addObject:window];
        }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in UIApplication.sharedApplication.windows)
            if (window && ![everyWindow containsObject:window]) [everyWindow addObject:window];
#pragma clang diagnostic pop
        NSMutableString *overlays=[NSMutableString new];
        for (UIWindow *window in everyWindow) {
            if (window.hidden || window.alpha<.01) continue;
            NSMutableArray<UIView *> *found=[NSMutableArray new];
            NSUInteger nodes=0;
            LMVDesktopFindOverlayViews(window,0,found,&nodes);
            NSUInteger shaped=0;
            for (UIView *v in found) {
                if (overlays.length>3000 || shaped++>=12) break;
                [overlays appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f{%@} ",
                    NSStringFromClass(window.class),window.frame.origin.x,window.frame.origin.y,
                    window.frame.size.width,window.frame.size.height,LMVDesktopOverlayShape(v,0)];
            }
        }
        NSString *overlayShape=nil;
        if(shapeDump)overlayShape=[NSString stringWithFormat:@"desktop-overlay %@",overlays.length?overlays:@"none"];
        static NSString *lastOverlay=nil;
        if (overlayShape && ![overlayShape isEqualToString:lastOverlay]) {lastOverlay=[overlayShape copy];LMVDiagnostic(overlayShape);}
    }
    // 1.25: WHICH whitelisted surface currently holds the cover, with its content
    // coverage - so an app-exit log names the window instead of leaving it to
    // inference (the 1.25 log carried an unexplained switcher window).
    {
        NSMutableString *owners=[NSMutableString new];
        UIWindow *target=container?container.window:nil;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha<.01) continue;
                NSString *className=NSStringFromClass(window.class);
                BOOL recognised=[className containsString:@"AppWindow"] || [className containsString:@"Switcher"] ||
                    [className containsString:@"ControlCenterWindow"] || [className containsString:@"CoverSheetWindow"];
                if (!recognised) continue;
                CGFloat coverage=LMVDesktopContentCoverage(window,window.rootViewController.viewIfLoaded,target);
                [owners appendFormat:@"%@(content=%.2f,alpha=%.2f) ",className,coverage,window.alpha];
            }
        }
        static NSString *lastOwners=nil;
        if (owners.length && ![owners isEqualToString:lastOwners]) {
            lastOwners=[owners copy];
            LMVDiagnostic([NSString stringWithFormat:@"desktop-cover-owner %@",owners]);
        }
    }
    // 1.25: which FULL-SCREEN windows the cover probe deliberately skips - the
    // discovery aid for an app window whose class name is not in the whitelist
    // (device log: an unexplained SBWindow and appc=0 throughout, i.e. the
    // desktop never saw the application at all).
    {
        NSMutableString *skipped=[NSMutableString new];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha<.01) continue;
                NSString *className=NSStringFromClass(window.class);
                if (window==container || LMVDesktopHomeWindow(window)) continue;
                if ([className containsString:@"AppWindow"] || [className containsString:@"Switcher"] ||
                    [className containsString:@"ControlCenterWindow"] || [className containsString:@"CoverSheetWindow"]) continue;
                CALayer *paint=window.layer.presentationLayer;
                CGRect frame=paint?paint.frame:window.frame;
                if (container && (frame.size.width<container.bounds.size.width*0.9 ||
                                  frame.size.height<container.bounds.size.height*0.9)) continue;
                [skipped appendFormat:@"%@ ",className];
            }
        }
        static NSString *lastSkipped=nil;
        if (skipped.length && ![skipped isEqualToString:lastSkipped]) {
            lastSkipped=[skipped copy];
            LMVDiagnostic([NSString stringWithFormat:@"desktop-windows-skipped %@",skipped]);
        }
    }
    // 0.0.129: which windows are on screen (class names, changes-only) - the
    // discovery aid for sheet presenters (e.g. the search pull-down) whose host
    // window class the cover probe does not know yet.
    {
        NSMutableString *windowList=[NSMutableString new];
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.hidden || window.alpha<.01) continue;
                [windowList appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f ",NSStringFromClass(window.class),
                    window.frame.origin.x,window.frame.origin.y,window.frame.size.width,window.frame.size.height];
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
    LMVDesktopStage("rest",stageCover);
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
