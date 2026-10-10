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
@end
@implementation LMVDesktopControllerRecord @end
static char LMVDesktopControllerRecordKey;
static NSHashTable<UIViewController *> *LMVDesktopControllers;
static __weak id LMVDesktopWallpaperController;
static __weak UIView *LMVDesktopExplicitWallpaper;
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
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
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
@property(nonatomic,weak) UIView *container;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,copy) NSString *path,*revision,*status,*earlyPosterAttempt;
@property(nonatomic) BOOL enabled,updating,authenticatedSession,suspended;
@property(nonatomic) CFTimeInterval lastRevisionCheck,lastDiscovery;
- (void)refresh:(BOOL)reload;
- (void)primePoster;
- (void)update;
- (void)suspend;
@end
static LMVDesktopVideoManager *LMVDesktopVideo;

static NSString *LMVDesktopSelectedPath(void) {
    id stored=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("DesktopVideo"),kLMVPrefsID);
    if (![stored isKindOfClass:NSString.class]) return nil;NSString *relative=stored;
    if (!relative.length || [relative hasPrefix:@"/"] || [relative.pathComponents containsObject:@".."] || [relative.pathComponents containsObject:@"."]) return nil;
    NSString *path=[[LMVDirectory stringByAppendingPathComponent:relative] stringByStandardizingPath];
    NSString *prefix=[LMVDirectory stringByAppendingString:@"/"];
    return [path hasPrefix:prefix] && [path.stringByResolvingSymlinksInPath hasPrefix:prefix]?path:nil;
}
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
static CGRect LMVDesktopCoverRect(UIWindow *destination,BOOL *unknown) {
    CGRect combined=CGRectZero;*unknown=NO;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!LMVLockVideoClass(window,@"SBCoverSheetWindow") || window.screen!=destination.screen || window.hidden || window.alpha<.01) continue;
            UIView *content=LMVLockVideoContent(window);
            if (!content) {*unknown=YES;continue;}
            CGRect rect=LMVLockVideoVisibleRect(content,window);if(CGRectIsEmpty(rect))continue;
            CGRect converted=[window convertRect:rect toWindow:destination];
            if (!LMVLockVideoRectValid(converted)) {*unknown=YES;continue;}
            combined=CGRectIsEmpty(combined)?converted:CGRectUnion(combined,converted);
        }
    }
    return combined;
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
@implementation LMVDesktopVideoManager
- (instancetype)init {
    if ((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=YES;
        _host=[[LMVDesktopVideoHost alloc] initWithFrame:CGRectZero];
        _host.playback=_playback;_playback.renderLayer.name=@"com.minis.lockmessagevideo.desktop.render";
        _playback.renderLayer.backgroundColor=UIColor.blackColor.CGColor;[_host.layer addSublayer:_playback.renderLayer];
        __weak typeof(self) weakSelf=self;
        _playback.didChange=^{LMVDesktopVideoManager *live=weakSelf;if(live && !live.updating && !live.suspended)[live update];};
    }
    return self;
}
- (void)dealloc {[_timer invalidate];[_lease restore];[_host removeFromSuperview];}
- (void)primePoster {
    id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("DesktopBackgroundEnabled"),kLMVPrefsID);
    self.enabled=[enabled respondsToSelector:@selector(boolValue)] && [enabled boolValue];
    NSString *path=self.enabled?LMVDesktopSelectedPath():nil,*revision=LMVLockVideoRevision(path);
    if ((self.path || path) && (![self.path isEqualToString:path] || ![self.revision isEqualToString:revision])) {
        [self.lease restore];self.lease=nil;[self.playback clear];self.earlyPosterAttempt=nil;
    }
    self.path=path;self.revision=revision;
    [self.playback preparePosterForPath:path revision:revision];
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
}
- (void)update {
    if (self.updating || self.suspended) return;self.updating=YES;
    uint64_t blank=1,locked=1;
    BOOL screenKnown=LMVBlankToken>=0 && notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK;
    BOOL lockKnown=LMVLockToken>=0 && notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK;
    if (!screenKnown || blank || !lockKnown) self.authenticatedSession=NO;
    UIView *homeRoot=nil;UIViewController *poster=nil;BOOL homeConfirmed=NO;
    for (UIViewController *controller in LMVDesktopControllers.allObjects) {
        if (!LMVDesktopControllerEligible(controller))continue;
        if (LMVLockVideoClass(controller,@"PBUIPosterHomeViewController")) {poster=controller;continue;}
        LMVDesktopControllerRecord *record=objc_getAssociatedObject(controller,&LMVDesktopControllerRecordKey);
        if (record.known && record.visible) homeConfirmed=YES;
        if (!homeRoot || LMVLockVideoClass(controller,@"SBHomeScreenViewController")) homeRoot=controller.viewIfLoaded;
    }
    UIView *wallpaper=LMVDesktopExplicitWallpaper;
    BOOL wallpaperValid=wallpaper && LMVDesktopGeometryVisible(wallpaper) && LMVDesktopWallpaperContent(wallpaper);
    if (LMVLockVideoClass(wallpaper.window,@"SBCoverSheetWindow")) wallpaperValid=NO;
    UIView *container=wallpaperValid?wallpaper:(homeRoot ?: poster.viewIfLoaded);
    UIView *content=wallpaperValid?LMVDesktopWallpaperContent(wallpaper):nil;
    // Exact PBUIPosterHome identity is a PaperBoard-compatible alternative to
    // legacy SBFWallpaperView, with the same background-only scope requirement.
    if (!wallpaperValid && poster && LMVDesktopGeometryVisible(poster.viewIfLoaded)) {
        container=poster.viewIfLoaded;content=nil;
    }
    BOOL unknownCover=NO;CGRect cover=container?LMVDesktopCoverRect(container.window,&unknownCover):CGRectZero;
    if (screenKnown && !blank && lockKnown && !locked && CGRectIsEmpty(cover) && !unknownCover) self.authenticatedSession=YES;
    NSInteger foreground=LMVDesktopForeground();
    BOOL covered=container && LMVDesktopFullyCovered(container,cover);
    BOOL environment=screenKnown && !blank && lockKnown && self.authenticatedSession && foreground>=0 &&
        (foreground==1 || homeConfirmed) && !unknownCover;
    BOOL configured=self.enabled && self.path.length && self.revision.length;
    BOOL visible=configured && container && LMVDesktopGeometryVisible(container) && environment;
    // A currently locked state outside an authenticated NC pull is a real lock.
    if (locked && CGRectIsEmpty(cover))visible=NO;
    if (visible) {
        if (self.container!=container || (self.lease && self.lease.content!=content)) {
            [self.lease restore];self.lease=nil;[self.host removeFromSuperview];
        }
        self.container=container;
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
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.host.frame=container.bounds;self.host.alpha=1;self.host.hidden=NO;
        self.host.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self.playback layoutInBounds:self.host.bounds];[CATransaction commit];
    } else {
        self.host.hidden=YES;[self.lease restore];self.lease=nil;
        [self.host removeFromSuperview];self.container=nil;
    }
    if (LMVLaunchReady) [self.playback setVisible:visible && !covered];
    else [self.playback showPreparedPoster:visible];
    if (visible && covered && self.playback.path && !self.playback.error) {
        // Retain the existing desktop frame behind NC; withdrawing NC reveals
        // that frame immediately without a flash back to the static wallpaper.
        BOOL hasPixels=self.playback.playerLayer.readyForDisplay || self.playback.posterLayer.contents!=nil;
        self.playback.renderLayer.hidden=!hasPixels;
    }
    BOOL pixels=visible && !self.playback.renderLayer.hidden && !self.playback.error;
    if (pixels && content && content.superview==container) {
        if (!self.lease) {self.lease=[LMVDesktopContentLease new];self.lease.content=content;self.lease.parent=container;self.lease.baselineHidden=content.hidden;}
        if (!self.lease.baselineHidden) {content.hidden=YES;self.lease.applied=YES;}
    } else if (self.lease) {[self.lease restore];self.lease=nil;}
    if (!configured && (self.playback.path || self.playback.player || self.playback.loading)) [self.playback clear];
    NSString *status=[NSString stringWithFormat:@"desktop-video visible=%d home=%d host=%@ path=%d layer=%d contentHidden=%d foreground=%ld cover=%d blank=%llu locked=%llu",
        visible,homeConfirmed,container?NSStringFromClass(container.class):@"none",configured,pixels,self.lease.applied,
        (long)foreground,!CGRectIsEmpty(cover),(unsigned long long)blank,(unsigned long long)locked];
    if(![status isEqualToString:self.status]){self.status=status;LMVDiagnostic(status);}
    self.updating=NO;
}
@end
static void LMVDesktopPrimeEarly(void) {
    if(!LMVInitialized || !NSThread.isMainThread)return;
    if(!LMVDesktopVideo)LMVDesktopVideo=[LMVDesktopVideoManager new];
    [LMVDesktopVideo primePoster];
}
static void LMVDesktopEarlyLayout(void) {
    if(!LMVInitialized || !NSThread.isMainThread || LMVLaunchReady || !LMVDesktopVideo.enabled)return;
    if(LMVDesktopWallpaperController)LMVDesktopDiscover();
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
    LMVDesktopDiscover();if(!LMVDesktopVideo){LMVDesktopVideo=[LMVDesktopVideoManager new];reload=YES;}
    [LMVDesktopVideo refresh:reload];
}
static void LMVDesktopVideoSuspend(void) {if(NSThread.isMainThread)[LMVDesktopVideo suspend];}
static void LMVDesktopVideoScreenBlank(void) {if(NSThread.isMainThread){LMVDesktopVideo.authenticatedSession=NO;[LMVDesktopVideo suspend];}}
static void LMVDesktopLifecycle(UIViewController *controller,NSInteger visible) {
    if(!LMVInitialized || !NSThread.isMainThread)return;
    if(!LMVDesktopControllers)LMVDesktopControllers=[NSHashTable weakObjectsHashTable];[LMVDesktopControllers addObject:controller];
    LMVDesktopControllerRecord *record=objc_getAssociatedObject(controller,&LMVDesktopControllerRecordKey);
    if(!record){record=[LMVDesktopControllerRecord new];objc_setAssociatedObject(controller,&LMVDesktopControllerRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    if(visible>=0){record.known=YES;record.visible=visible!=0;}
    if(!LMVLaunchReady)LMVDesktopEarlyLayout();
    LMVRequestSafeUpdate();
}

static void (*LMVDesktopOriginalLoad)(id,SEL),(*LMVDesktopOriginalLayout)(id,SEL);
static void (*LMVDesktopOriginalWillAppear)(id,SEL,BOOL),(*LMVDesktopOriginalDidAppear)(id,SEL,BOOL),(*LMVDesktopOriginalDidDisappear)(id,SEL,BOOL);
static void (*LMVIconOriginalLoad)(id,SEL),(*LMVIconOriginalLayout)(id,SEL);
static void (*LMVIconOriginalWillAppear)(id,SEL,BOOL),(*LMVIconOriginalDidAppear)(id,SEL,BOOL),(*LMVIconOriginalDidDisappear)(id,SEL,BOOL);
static void (*LMVPosterHomeOriginalLoad)(id,SEL),(*LMVPosterHomeOriginalLayout)(id,SEL);
static void (*LMVPosterHomeOriginalWillAppear)(id,SEL,BOOL),(*LMVPosterHomeOriginalDidAppear)(id,SEL,BOOL),(*LMVPosterHomeOriginalDidDisappear)(id,SEL,BOOL);
#define LMV_DESKTOP_CALLBACKS(prefix) \
static void prefix##HookLoad(id value,SEL selector){prefix##OriginalLoad(value,selector);LMVDesktopLifecycle(value,-1);} \
static void prefix##HookLayout(id value,SEL selector){prefix##OriginalLayout(value,selector);LMVDesktopLifecycle(value,-1);} \
static void prefix##HookWillAppear(id value,SEL selector,BOOL animated){prefix##OriginalWillAppear(value,selector,animated);LMVDesktopLifecycle(value,1);} \
static void prefix##HookDidAppear(id value,SEL selector,BOOL animated){prefix##OriginalDidAppear(value,selector,animated);LMVDesktopLifecycle(value,1);} \
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
        LMVDesktopWallpaperController=result;LMVRequestSafeUpdate();
    }
    return result;
}
static void LMVDesktopWallpaperHookLayout(id value,SEL selector) {
    LMVDesktopWallpaperOriginalLayout(value,selector);
    if(NSThread.isMainThread && LMVInitialized) {if(!LMVLaunchReady)LMVDesktopEarlyLayout();LMVRequestSafeUpdate();}
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
