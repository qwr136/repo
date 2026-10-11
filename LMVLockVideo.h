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
static CGRect LMVLockVideoClip(UIView *content,UIView *container,UIWindow *window) {
    CALayer *space=container.layer.presentationLayer,*contentSpace=content.layer.presentationLayer,*root=window.layer.presentationLayer;
    if (!space || !contentSpace || !root) {space=container.layer;contentSpace=content.layer;root=window.layer;}
    CGRect visible=LMVLockVideoRectInTree(content,window,contentSpace,root);if(CGRectIsEmpty(visible))return CGRectZero;
    CGRect local=[space convertRect:visible fromLayer:root];local=CGRectIntersection(local,space.bounds);
    return LMVLockVideoRectValid(local)?CGRectOffset(local,-space.bounds.origin.x,-space.bounds.origin.y):CGRectZero;
}

// 0.0.92: while the CoverSheet slides, the branch that holds the panel is offset
// inside the controller's own view, so a surface parented inside that branch can
// only ever cover the panel itself. Everything the panel no longer covers showed
// the system wallpaper (the "top leaks wallpaper" report). Promotion moves the
// surface into the first non-clipping ancestor that still covers the window
// viewport, directly below the branch holding the panel and above the branch that
// draws the panel background, and widens the clip to that ancestor. Visibility is
// still decided by the slideable content, so a withdrawn panel withdraws the
// surface exactly as before.
// The promoted surface must cover the whole visible viewport, otherwise the same
// strip simply leaks again from a different parent.
// Only aboveSubview: is used for placement, so no extra UIView API is required.
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
@interface LMVLockVideoPaintLease : NSObject
@property(nonatomic,strong) NSMutableArray<UIView *> *views;
@property(nonatomic,strong) NSMutableArray<UIView *> *revealed;
@end
@implementation LMVLockVideoPaintLease @end
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
    if (!named) return NO;
    CALayer *layer=view.layer.presentationLayer ?: view.layer;
    CGRect frame=[layer convertRect:layer.bounds toLayer:content.layer];
    return frame.size.width>=content.bounds.size.width*0.5 && frame.size.height>=content.bounds.size.height*0.3;
}
static void LMVLockVideoCollectRepainters(UIView *node,UIView *content,NSMutableArray *output,NSUInteger *budget) {
    for (UIView *child in node.subviews) {
        if (!*budget) return;
        --*budget;
        if (LMVLockVideoRepaint(child,content)) [output addObject:child];
        else LMVLockVideoCollectRepainters(child,content,output,budget);
    }
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
@property(nonatomic,copy) NSString *path,*revision,*diagnostic,*coverage;
@property(nonatomic) BOOL enabled,updating,screenAllowed;
@property(nonatomic) CFTimeInterval lastRevisionCheck;
// 0.0.97: previous sampled band + its timestamp, used to lead the moving edge
// by exactly one frame of motion (see update()).
@property(nonatomic) CGRect lastClipRect;@property(nonatomic) CFTimeInterval lastClipTime;
@property(nonatomic) BOOL hasLastClip;
@property(nonatomic,strong) LMVLockVideoPaintLease *paintLease;
@property(nonatomic) CFTimeInterval paintLeaseTime;
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
    for (UIView *view in self.paintLease.revealed) view.hidden=NO;
    self.paintLease=nil;self.paintText=nil;
}
- (void)leasePaint:(UIView *)container {
    CFTimeInterval now=CACurrentMediaTime();
    if (self.paintLease) {
        BOOL attached=YES;
        for (UIView *view in self.paintLease.views) if (!view.superview) {attached=NO;break;}
        // Keep a settled lease; rescan when it went stale or every half second so
        // views the system recreates during a pull are picked up again.
        if (attached && now-self.paintLeaseTime<0.5) return;
        [self releasePaint];
    }
    NSUInteger own=[container.subviews indexOfObjectIdenticalTo:self.host];
    NSMutableArray *found=[NSMutableArray new];NSUInteger budget=240;
    for (NSUInteger index=(own==NSNotFound?0:own+1);index<container.subviews.count;index++) {
        if (!budget) break;
        LMVLockVideoCollectRepainters(container.subviews[index],container,found,&budget);
    }
    self.paintLeaseTime=now;
    if (!found.count) {self.paintText=nil;return;}
    LMVLockVideoPaintLease *lease=[LMVLockVideoPaintLease new];
    lease.views=found;lease.revealed=[NSMutableArray new];
    NSMutableString *text=[NSMutableString string];
    for (UIView *view in found) {
        if (!view.hidden) {[lease.revealed addObject:view];view.hidden=YES;}
        [text appendFormat:@"%@,",NSStringFromClass(view.class)];
    }
    self.paintLease=lease;self.paintText=text;
}
- (void)update {
    if (self.updating) return;self.updating=YES;
    CFTimeInterval coverPerf0=CACurrentMediaTime();
    UIViewController *best=nil;UIView *content=nil;CGFloat area=0;
    if (self.enabled && self.path.length && self.revision.length && self.screenAllowed) {
        for (UIViewController *candidate in LMVLockControllers.allObjects) {
            LMVLockControllerRecord *record=objc_getAssociatedObject(candidate,&LMVLockControllerRecordKey);
            UIView *root=candidate.viewIfLoaded;UIWindow *window=root.window;
            CGRect viewport=LMVVideoWindowViewport(window);
            CGFloat full=window.bounds.size.width*window.bounds.size.height;
            BOOL half=full>0 && viewport.size.width*viewport.size.height<full*.90;
            // Reachability can deliver a disappearance callback while the same
            // attached CoverSheet remains visible in its translated viewport.
            // In that case require actual sliding-content exposure below.
            if (record.lifecycleKnown && !record.visible && !half) continue;
            if (!root || !LMVLockVideoClass(window,@"SBCoverSheetWindow") || window.screen!=UIScreen.mainScreen) continue;
            UIView *sliding=LMVLockVideoContent(root);CGRect exposed=LMVLockVideoVisibleRect(sliding,window);
            CGFloat size=exposed.size.width*exposed.size.height;
            if (LMVLockVideoRectValid(exposed) && size>area) {best=candidate;content=sliding;area=size;}
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
        // 0.0.95: the revealed area follows the pull again -- "pull this much, reveal
        // this much". 0.0.92-0.0.94 promoted the surface out of the panel and widened
        // the clip to the whole window viewport, so the entire video appeared as soon
        // as the panel moved a little. The clip is the slideable content's own rect.
        CGRect clip=LMVLockVideoClip(content,container,content.window);
        CGRect sampledClip=clip;
        // 0.0.97: the panel is animated by the system at the display refresh rate
        // while this geometry is sampled on the display link, so the moving edge of
        // the revealed band trailed the panel by up to one frame. That trailing
        // strip is the original wallpaper people see while pulling Notification
        // Center down ("the video comes out slowly at the top"). Lead the edge in
        // the direction it is already moving by the previous step (one frame of
        // motion, clamped). A shrinking band gets nothing, so a withdrawing panel
        // still withdraws the surface exactly as before.
        CFTimeInterval leadNow=CACurrentMediaTime();
        CGFloat lead=0.0;
        if (self.hasLastClip && !CGRectIsEmpty(self.lastClipRect) && !CGRectIsEmpty(clip)) {
            CFTimeInterval leadDt=leadNow-self.lastClipTime;
            if (leadDt>0.0005 && leadDt<0.10) {
                CGFloat dy=clip.origin.y-self.lastClipRect.origin.y;
                CGFloat dh=clip.size.height-self.lastClipRect.size.height;
                if (dh>0.5) {
                    if (dy<-0.5) {lead=-dy;clip.origin.y-=lead;clip.size.height+=lead;}
                    else {lead=dh;clip.size.height+=lead;}
                    if (lead>60.0) {clip.size.height-=(lead-60.0);lead=60.0;}
                }
            }
        }
        self.lastClipRect=sampledClip;self.lastClipTime=leadNow;self.hasLastClip=YES;
        visible=!CGRectIsEmpty(clip);
        [CATransaction begin];[CATransaction setDisableActions:YES];
        self.host.frame=container.bounds;self.host.alpha=1;self.host.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
        [self.playback layoutInBounds:self.host.bounds];self.host.clipLayer.frame=self.host.bounds;
        if (!self.host.clipLayer.path || !CGRectEqualToRect(CGPathGetBoundingBox(self.host.clipLayer.path),clip)) {
            CGPathRef path=CGPathCreateWithRect(clip,NULL);self.host.clipLayer.path=path;CGPathRelease(path);
        }
        self.host.hidden=!visible;[CATransaction commit];
        if (visible) [self leasePaint:container];
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
        CGRect revealed=CGRectIsEmpty(coverViewport)?CGRectZero:CGRectOffset(clip,hostInWindow.origin.x,hostInWindow.origin.y);
        // What the sampled band alone would have left uncovered: this is the leak
        // that the one-frame lead above removes, so a future report can tell the two
        // apart ("geometry lag" vs "covered by something else").
        CGRect sampledRevealed=CGRectIsEmpty(coverViewport)?CGRectZero:CGRectOffset(sampledClip,hostInWindow.origin.x,hostInWindow.origin.y);
        CGFloat sampledGapTop=CGRectIsEmpty(sampledRevealed)?coverViewport.size.height:MAX(0.0,sampledRevealed.origin.y-coverViewport.origin.y);
        CGFloat sampledGapBottom=CGRectIsEmpty(sampledRevealed)?coverViewport.size.height:MAX(0.0,(coverViewport.origin.y+coverViewport.size.height)-(sampledRevealed.origin.y+sampledRevealed.size.height));
        CGFloat revealedHeight=CGRectIsEmpty(revealed)?0.0:revealed.size.height;
        CGFloat gapTop=CGRectIsEmpty(revealed)?coverViewport.size.height:MAX(0.0,revealed.origin.y-coverViewport.origin.y);
        CGFloat gapBottom=CGRectIsEmpty(revealed)?coverViewport.size.height:MAX(0.0,(coverViewport.origin.y+coverViewport.size.height)-(revealed.origin.y+revealed.size.height));
        NSString *coverKey=[NSString stringWithFormat:@"r=%.0f t=%.0f b=%.0f L=%.0f t0=%.0f b0=%.0f v=%d %@|%@|%@",floor(revealedHeight/20.0)*20.0,floor(gapTop/20.0)*20.0,floor(gapBottom/20.0)*20.0,floor(lead/10.0)*10.0,floor(sampledGapTop/20.0)*20.0,floor(sampledGapBottom/20.0)*20.0,(int)self.host.hidden,hostParent?NSStringFromClass(hostParent.class):@"none",aboveText,self.paintText?:@"-"];
        if (![coverKey isEqualToString:self.coverage]) {
            self.coverage=coverKey;
            NSString *coverLine=[NSString stringWithFormat:@"lock-video cover reveal=%.1f gapTop=%.1f gapBottom=%.1f lead=%.1f sampledGapTop=%.1f sampledGapBottom=%.1f hostHidden=%d container=%@ hostSuper=%@ above=[%@] leasedPaint=[%@] clip=%@ hostInWindow=%@",
                revealedHeight,gapTop,gapBottom,lead,sampledGapTop,sampledGapBottom,(int)self.host.hidden,
                NSStringFromClass(container.class),hostParent?NSStringFromClass(hostParent.class):@"none",aboveText,
                self.paintText?:@"-",LMVLockVideoRectText(clip),LMVLockVideoRectText(hostInWindow)];
            LMVLockVideoLog(coverLine);
        }
    } else {
        [self releasePaint];
        self.host.hidden=YES;[self.host removeFromSuperview];self.content=nil;self.controller=nil;
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
    NSString *coverPerf=LMVLockVideoPerf("lock",CACurrentMediaTime()-coverPerf0);
    if (coverPerf) LMVLockVideoLog(coverPerf);
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
