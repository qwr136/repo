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
static CGRect LMVLockVideoRectInTree(UIView *content,UIWindow *window,CALayer *space,CALayer *root) {
    if (!content || !window || !space || !root || window.hidden || window.alpha<.01 || !LMVLockVideoRectValid(content.bounds)) return CGRectZero;
    for (UIView *node=content;node;node=node.superview) if (node.hidden || node.alpha<.01) return CGRectZero;
    CGRect rect=[space convertRect:space.bounds toLayer:root];
    if (!LMVLockVideoRectValid(rect)) return CGRectZero;
    // Every ancestor clipping boundary is measured in the same model/presentation tree.
    for (UIView *node=content.superview;node && node!=window;node=node.superview) if (node.clipsToBounds) {
        CALayer *layer=root==window.layer?node.layer:node.layer.presentationLayer;
        if (!layer) return CGRectZero;
        rect=CGRectIntersection(rect,[layer convertRect:layer.bounds toLayer:root]);
    }
    rect=CGRectIntersection(rect,root.bounds);
    return LMVLockVideoRectValid(rect) && rect.size.width>1 && rect.size.height>1?rect:CGRectZero;
}
static CGRect LMVLockVideoVisibleRect(UIView *content,UIWindow *window) {
    CALayer *space=content.layer.presentationLayer,*root=window.layer.presentationLayer;
    if (!space || !root) {space=content.layer;root=window.layer;}
    return LMVLockVideoRectInTree(content,window,space,root);
}
static UIView *LMVLockVideoContainer(UIView *root,UIView *content,UIView *own,UIView **anchor) {
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
static CGRect LMVLockVideoClip(UIView *content,UIView *container,UIWindow *window) {
    CALayer *space=container.layer.presentationLayer,*contentSpace=content.layer.presentationLayer,*root=window.layer.presentationLayer;
    if (!space || !contentSpace || !root) {space=container.layer;contentSpace=content.layer;root=window.layer;}
    CGRect visible=LMVLockVideoRectInTree(content,window,contentSpace,root);if(CGRectIsEmpty(visible))return CGRectZero;
    CGRect local=[space convertRect:visible fromLayer:root];local=CGRectIntersection(local,space.bounds);
    return LMVLockVideoRectValid(local)?CGRectOffset(local,-space.bounds.origin.x,-space.bounds.origin.y):CGRectZero;
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
@property(nonatomic) BOOL lifecycleKnown,visible;
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
@property(nonatomic,copy) NSString *path,*revision,*diagnostic;
@property(nonatomic) BOOL enabled,updating,screenAllowed;
@property(nonatomic) CFTimeInterval lastRevisionCheck,lastTickTime,pendingHideUntil;
// 0.0.79 fix: cache the last applied geometry so the 30 Hz display link can skip
// the expensive presentation-layer coordinate math and subview reordering when
// nothing actually moved. Pulling down Notification Center animates the Cover
// Sheet every frame; recomputing the clip path + re-inserting the host on every
// tick competed with that animation on the main thread and showed up as a hitch.
@property(nonatomic) CGRect lastClip;
@property(nonatomic,weak) UIView *lastContainer;
@property(nonatomic) BOOL geometryValid;
- (void)refresh:(BOOL)reload;
- (void)update;
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
            LMVLockVideoManager *live=weakSelf;if(!live)return;
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
    [self.playback setVisible:NO];self.host.hidden=YES;
    [self.link invalidate];self.link=nil;
    self.geometryValid=NO;self.lastContainer=nil;self.lastTickTime=0;self.pendingHideUntil=0;
}
- (void)tick:(CADisplayLink *)link {
    // 0.0.79 fix: the display link runs at 30 Hz, but the full `update` does a
    // controller scan plus presentation-layer coordinate conversions. The heavy
    // part (subview reordering + clip path rebuild) is now gated on geometry
    // actually changing, so most ticks are cheap. A light rate cap still bounds how
    // often the controller scan runs while the sheet animates, without making the
    // clip edge visibly steppy.
    BOOL allowed=LMVLockVideoScreenAllowed();
    if (allowed!=self.screenAllowed) {self.screenAllowed=allowed;[self update];self.lastTickTime=CACurrentMediaTime();return;}
    CFTimeInterval now=CACurrentMediaTime();
    if (self.lastRevisionCheck>0 && now-self.lastRevisionCheck>=1) {
        self.lastRevisionCheck=now;NSString *revision=LMVLockVideoRevision(self.path);
        if ((revision || self.revision) && ![revision isEqualToString:self.revision]) {
            self.revision=revision;[self.playback selectPath:self.path revision:revision];
        }
    }
    // ~15 Hz controller scan; the per-tick geometry short-circuit keeps the visual
    // update responsive while avoiding the expensive scan on every frame.
    if (now-self.lastTickTime>=1.0/15.0 || !self.host.superview) {
        self.lastTickTime=now;
        [self update];
    }
}
- (void)update {
    if (self.updating) return;self.updating=YES;
    UIViewController *best=nil;UIView *content=nil;CGFloat area=0;
    if (self.enabled && self.path.length && self.revision.length && self.screenAllowed) {
        for (UIViewController *candidate in LMVLockControllers.allObjects) {
            LMVLockControllerRecord *record=objc_getAssociatedObject(candidate,&LMVLockControllerRecordKey);
            if (record.lifecycleKnown && !record.visible) continue;
            UIView *root=candidate.viewIfLoaded;UIWindow *window=root.window;
            if (!root || !LMVLockVideoClass(window,@"SBCoverSheetWindow") || window.screen!=UIScreen.mainScreen) continue;
            UIView *sliding=LMVLockVideoContent(root);CGRect exposed=LMVLockVideoVisibleRect(sliding,window);
            CGFloat size=exposed.size.width*exposed.size.height;
            if (LMVLockVideoRectValid(exposed) && size>area) {best=candidate;content=sliding;area=size;}
        }
    }
    UIView *anchor=nil;UIView *container=content?LMVLockVideoContainer(best.viewIfLoaded,content,self.host,&anchor):nil;
    BOOL visible=best && content && container && anchor;
    // 0.0.79 fix: "pulling down Notification Center makes the video hitch". While the
    // Cover Sheet geometry animates, the exposed rect can flicker through an empty
    // value for a frame or two even though the container is still valid. Pausing the
    // player on that flicker and resuming on the next tick makes AVPlayer re-buffer,
    // and the poster<->player flip is what reads as a stall. Such a transient
    // "container still valid but clip momentarily empty" case is debounced; a real
    // teardown (no controller/content/container, disabled, screen off) stops at once.
    BOOL transientEmpty=NO;
    if (visible) {
        self.content=content;self.controller=best;
        CGRect clip=LMVLockVideoClip(content,container,content.window);
        visible=!CGRectIsEmpty(clip);
        transientEmpty=!visible;
        // 0.0.79 fix: only touch the view/layer tree when the geometry actually
        // changed. During a Notification Center pull-down the parent animates, but
        // the clip can settle for many consecutive ticks; skipping identical work
        // keeps the main thread free for the system animation.
        BOOL geometryChanged=!self.geometryValid || self.lastContainer!=container ||
            !CGRectEqualToRect(self.lastClip,clip);
        if (geometryChanged) {
            NSArray *children=container.subviews;
            NSUInteger back=[children indexOfObjectIdenticalTo:anchor],own=[children indexOfObjectIdenticalTo:self.host];
            if (self.host.superview!=container || own!=back+1) {
                [self.host removeFromSuperview];[container insertSubview:self.host aboveSubview:anchor];
            }
            [CATransaction begin];[CATransaction setDisableActions:YES];
            self.host.frame=container.bounds;self.host.alpha=1;self.host.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
            [self.playback layoutInBounds:self.host.bounds];self.host.clipLayer.frame=self.host.bounds;
            if (!self.host.clipLayer.path || !CGRectEqualToRect(CGPathGetBoundingBox(self.host.clipLayer.path),clip)) {
                CGPathRef path=CGPathCreateWithRect(clip,NULL);self.host.clipLayer.path=path;CGPathRelease(path);
            }
            self.host.hidden=!visible;[CATransaction commit];
            self.lastClip=clip;self.lastContainer=container;self.geometryValid=YES;
        } else if (self.host.hidden!=!visible) {
            self.host.hidden=!visible;
        }
    } else {
        if (!self.host.hidden || self.host.superview) {self.host.hidden=YES;[self.host removeFromSuperview];}
        self.content=nil;self.controller=nil;self.geometryValid=NO;self.lastContainer=nil;
    }
    CFTimeInterval now=CACurrentMediaTime();
    if (visible) {
        self.pendingHideUntil=0;
        [self.playback setVisible:YES];
    } else if (transientEmpty && self.playback.wantsPlayback) {
        // Container is still valid; hold the pause briefly in case the sheet settles
        // back into view on the very next tick.
        if (self.pendingHideUntil==0) self.pendingHideUntil=now+0.3;
        if (now>=self.pendingHideUntil) {self.pendingHideUntil=0;[self.playback setVisible:NO];}
    } else {
        self.pendingHideUntil=0;
        [self.playback setVisible:NO];
    }
    // One lightweight geometry monitor only while the CoverSheet is exposed.
    // No message frame decoder, extra UIWindow, original opacity lease or source-cache write.
    if (best && content && self.screenAllowed) {
        if (!self.link) {self.link=[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
            self.link.preferredFramesPerSecond=30;[self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];}
    } else {[self.link invalidate];self.link=nil;}
    if (!self.enabled || !self.path.length || !self.revision.length) {
        if (self.playback.path || self.playback.player || self.playback.loading) [self.playback clear];
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
static void LMVLockHookLayout(id object,SEL selector) {LMVLockOriginalLayout(object,selector);LMVLockVideoLifecycle(object,-1);}
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
