#pragma once
// 1.28: the AppTools (AT) pop-up background (AT 背景视频).
//
// Shape settled by the 1.27 device diagnostics - and it is NOT the shape of the
// SquidGesture panel. AppTools has NO window of its own: it PRESENTS its panel
// INTO SBHomeScreenWindow, one or two levels below it, under a UITransitionView.
// The 1.27 desktop-overlay dump pins it exactly:
//
//   SBHomeScreenWindow@0,0,430,932
//     UITransitionView@0,0,430,932
//       UIView@0,0,430,932                      <- full-screen scrim, NOT the card
//       UIView@0,345,430,587                    <- THE CARD (bottom-anchored)
//         UIVisualEffectView@0,0,430,587(r25)   <- the material
//           _UIVisualEffectBackdropView
//           _UIVisualEffectContentView
//
// So the search starts at SBHomeScreenWindow and only ever looks INSIDE a
// TransitionView subtree; the full-screen levels are skipped by the same
// "visible, not full-screen, at least half the width" rule the Squid channel
// uses. The video attaches UNDER the icons but ABOVE the material - the placement
// 1.24 settled for the Squid panel, which is exactly what "挂在图标下面" means.
//
// Poll-based and private-class-free: nothing of AppTools is hooked or guessed,
// and when the switch is off nothing is constructed at all.
//
// Requires the shared helpers imported earlier in the translation unit
// (LMVLockVideoPlayback, LMVCCSelectedPath, LMVLockVideoRevision, LMVInitialized,
// LMVLaunchReady, LMVBlankToken, LMVLockToken, LMVDiagnosticsEnabled,
// LMVDiagnostic, kLMVPrefsID).
#import <stdbool.h>

static void LMVATPanelVideoRefresh(BOOL reload);
static void LMVATPanelVideoSuspend(void);
static BOOL LMVATPanelEnabled,LMVATPanelPrefsKnown;
static NSString *LMVATPanelPath,*LMVATPanelRevision;
static NSTimer *LMVATPanelTimer;

static BOOL LMVATPanelSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}
static BOOL LMVATPanelEnvironment(void) {
    uint64_t blank=1,locked=1;
    return LMVInitialized && LMVLaunchReady && NSThread.isMainThread && LMVATPanelSpringBoard() &&
        LMVBlankToken>=0 && LMVLockToken>=0 &&
        notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK &&
        notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK && !blank && !locked;
}
// AppTools owns no window - this is the window it presents INTO.
static UIWindow *LMVATPanelHomeWindow(void) {
    // 2.55: read the shared snapshot instead of walking every scene and window; the
    // entries are already filtered to visible, opaque-enough windows.
    for(UIWindow *window in LMVProbeVisibleWindows()) {
        if([NSStringFromClass(window.class) containsString:@"SBHomeScreen"])return window;
    }
    return nil;
}
static NSInteger const LMVATPanelHostTag=0x5A18;
// How much of this view is REALLY on screen. A card that is mostly parked off
// screen is never a candidate - scoring by raw area alone made the Squid channel
// jump onto an invisible card, and the same trap exists here.
static CGFloat LMVATPanelVisibleArea(CGRect frame,CGRect bounds) {
    if(CGRectIsEmpty(frame) || CGRectIsEmpty(bounds))return 0;
    CGRect onScreen=CGRectIntersection(frame,bounds);
    if(CGRectIsEmpty(onScreen))return 0;
    CGFloat total=frame.size.width*frame.size.height;
    if(total<=0)return 0;
    CGFloat visible=onScreen.size.width*onScreen.size.height;
    return visible/total>=.5?visible:0;
}
// 1.40: the SYSTEM long-press menu (home icon or dock icon) is presented into the
// very same SBHomeScreenWindow AppTools uses, through a *_ContextMenu*TransitionView
// (_UIContextMenuPlatterTransitionView / _UIContextMenuContainerView). That name
// contains "TransitionView" too, so the 1.27/1.28 scan claimed the menu's card as
// the AppTools panel - the AT video and, what the user hears, the AT SOUND latched
// onto the desktop long-press menu and played under a menu it has nothing to do
// with. A system context menu is never the AppTools panel, so its whole subtree is
// skipped here AND every *_ContextMenu* candidate is rejected in LMVATPanelCard.
static BOOL LMVATPanelSystemMenu(UIView *view) {
    NSString *name=NSStringFromClass(view.class);
    if([name containsString:@"ContextMenu"])return YES;
    // 2.03: A SYSTEM ALERT IS NOT THE APPTOOLS PANEL.
    // Device log (2.02):
    //   at-panel card=_UIAlertControllerPhoneTVMacView@80,175,270,607 live=1 host=270x607
    // - the "iPhone 通话" hand-off alert was getting a video background, and on the
    // next poll the winner moved to a plain UIView INSIDE it (same frame), so the
    // alert kept the video for as long as it stayed up.
    if([name containsString:@"Alert"])return YES;
    if([name containsString:@"PhoneTVMac"])return YES;
    return NO;
}
// Every UITransitionView at or below `view`. 1.27 learned the hard way that
// AppTools drops its TransitionView one or two levels BELOW the window (under
// SBHomeScreenView), so a window.subviews-only scan never sees the panel.
static void LMVATPanelTransitionRoots(UIView *view,NSUInteger depth,NSMutableArray<UIView *> *found,NSUInteger *nodes) {
    if(!view || depth>4 || *nodes>800)return;
    (*nodes)++;
    if(LMVATPanelSystemMenu(view))return;
    if([NSStringFromClass(view.class) containsString:@"TransitionView"])[found addObject:view];
    for(UIView *child in view.subviews)LMVATPanelTransitionRoots(child,depth+1,found,nodes);
}
// The card: inside the TransitionView subtrees only, the largest VISIBLE
// descendant that does NOT fill the window. That rule skips the full-screen
// scrim and the home-screen containers, and our own host is excluded by its tag.
static UIView *LMVATPanelCard(UIWindow *window) {
    if(!window)return nil;
    CGRect bounds=window.bounds;
    if(CGRectIsEmpty(bounds))return nil;

    NSMutableArray<UIView *> *roots=[NSMutableArray array];
    NSUInteger nodes=0;
    LMVATPanelTransitionRoots(window,0,roots,&nodes);
    if(!roots.count)return nil;   // no presentation on screen -> no panel

    UIView *best=nil;CGFloat bestArea=0;
    for(UIView *root in roots) {
        NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)root];
        NSUInteger budget=400;
        while(pending.count && budget) {
            UIView *node=pending.lastObject;[pending removeLastObject];
            for(UIView *child in node.subviews) {
                if(!budget--)break;
                if(child.tag==LMVATPanelHostTag || child.hidden || child.alpha<.01)continue;
                // 2.03: skip the whole subtree, not just this node. Adding the child
                // to `pending` first meant an excluded alert still had its children
                // walked - and a plain UIView inside it won the area contest.
                if(LMVATPanelSystemMenu(child))continue;
                [pending addObject:child];
                CGRect frame=[child convertRect:child.bounds toView:window];
                if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;
                if(frame.size.width<bounds.size.width*.5 || frame.size.height<bounds.size.height*.08)continue;
                CGFloat visible=LMVATPanelVisibleArea(frame,bounds);
                if(visible<=0)continue;
                if(visible>bestArea){bestArea=visible;best=child;}
            }
        }
    }
    return best;
}
// The panel's blur material. The video sits UNDER the icons but ABOVE this, so
// it has to be found first: insert below it and the material hides the video
// (the 1.25 Squid report).
static UIView *LMVATPanelMaterial(UIView *root,UIWindow *window) {
    if(!root || !window)return nil;
    CGRect bounds=window.bounds;
    UIView *best=nil;CGFloat bestArea=0;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)root];
    NSUInteger budget=300;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            [pending addObject:child];
            if(![child isKindOfClass:UIVisualEffectView.class] || child.hidden || child.alpha<.01)continue;
            CGRect frame=[child convertRect:child.bounds toView:window];
            CGFloat visible=LMVATPanelVisibleArea(frame,bounds);
            if(visible<=0)continue;
            if(visible>bestArea){bestArea=visible;best=child;}
        }
    }
    return best;
}
@interface LMVATPanelVideoHost:UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@end
@implementation LMVATPanelVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.tag=LMVATPanelHostTag;
        self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;self.accessibilityElementsHidden=YES;
        self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.clipsToBounds=YES;
    }
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
@end
@interface LMVATPanelVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVATPanelVideoHost *host;
@property(nonatomic,weak) UIView *card;
@property(nonatomic,copy) NSString *mode;
@property(nonatomic) BOOL updating;
// 2.42: per-channel show/hide delay timestamps.
@property(nonatomic) NSTimeInterval pendingShow,pendingHide;
- (void)detach;
- (void)update;
@end
static LMVATPanelVideoManager *LMVATPanelVideo;
@implementation LMVATPanelVideoManager
- (instancetype)init {
    if(!LMVATPanelEnvironment())return nil;
    if((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=YES;
        _host=[[LMVATPanelVideoHost alloc] initWithFrame:CGRectZero];_host.playback=_playback;
        _playback.renderLayer.name=@"com.minis.lockmessagevideo.at-panel.render";
        [_host.layer addSublayer:_playback.renderLayer];
    }
    return self;
}
- (void)dealloc {[_host removeFromSuperview];}
- (void)detach {
    if(self.host.superview)[self.host removeFromSuperview];
    self.host.hidden=YES;
    if(self.playback.wantsPlayback)[self.playback setVisible:NO];
    self.card=nil;self.mode=nil;
}
// A UIVisualEffectView REFUSES direct subviews - addSubview: raises, and an
// exception escaping a run-loop callback ABORTS SpringBoard (the 1.25 crash).
// The host therefore never goes into the effect view itself.
- (BOOL)insertHostInto:(UIView *)container at:(NSUInteger)index {
    if(!container || [container isKindOfClass:UIVisualEffectView.class])return NO;
    [self.host removeFromSuperview];
    @try {[container insertSubview:self.host atIndex:index];}
    @catch(NSException *exception) {[self.host removeFromSuperview];return NO;}
    return self.host.superview==container;
}
- (void)update {
    if(self.updating)return;self.updating=YES;
    UIWindow *window=LMVATPanelHomeWindow();
    UIView *card=window?LMVATPanelCard(window):nil;
    NSTimeInterval tuneNow=NSProcessInfo.processInfo.systemUptime;
    if(card && !self.card) {
        NSTimeInterval show=LMVTuneDelay(@"AT",@"ShowDelayMs");
        if(self.pendingShow<=0)self.pendingShow=tuneNow;
        if(show>0 && tuneNow-self.pendingShow<show) {self.updating=NO;return;}
        self.pendingShow=0;
    } else if(!card) {
        self.pendingShow=0;
    }

    NSTimeInterval hide=LMVTuneDelay(@"AT",@"HideDelayMs");
    if(hide>0 && self.card && self.host.superview) {
        if(self.pendingHide<=0)self.pendingHide=tuneNow;
        if(tuneNow-self.pendingHide<hide) {self.updating=NO;return;}
    }
    self.pendingHide=0;
    if(!card) {[self detach];self.updating=NO;return;}
    if(self.card!=card) {[self.host removeFromSuperview];self.card=card;}
    BOOL changed=![self.playback.path isEqualToString:LMVATPanelPath] ||
        ![self.playback.revision isEqualToString:LMVATPanelRevision];
    if(changed) {[self.host removeFromSuperview];[self.playback preparePosterForPath:LMVATPanelPath revision:LMVATPanelRevision];[self.playback selectPath:LMVATPanelPath revision:LMVATPanelRevision];}
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    // 2.59: with the persistent poster enabled the still frame is the panel's
    // first pixels - mount on it, the player covers it when decoded.
    BOOL live=self.playback.player && !self.playback.error &&
        (self.playback.posterLayer.contents!=nil || self.playback.playerLayer.readyForDisplay);
    if(!live) {[self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;return;}
    // WHERE in the panel the video belongs: UNDER the icons but ABOVE the
    // material - inside the material's contentView when there is one, otherwise
    // directly above the material in the same superview.
    UIView *material=LMVATPanelMaterial(card,window);
    if(!material)material=LMVATPanelMaterial(window,window);
    UIView *container=nil;NSUInteger index=0;CGRect target=CGRectZero;NSString *mode=@"card";
    if([material isKindOfClass:UIVisualEffectView.class]) {
        UIView *content=((UIVisualEffectView *)material).contentView;
        if(content && content.subviews.count<40) {
            container=content;index=0;target=content.bounds;mode=@"content";
        } else if(material.superview) {
            container=material.superview;
            NSInteger near=(NSInteger)[container.subviews indexOfObjectIdenticalTo:material];
            if(near==NSNotFound) {[self detach];self.updating=NO;return;}
            index=(NSUInteger)(near+1);target=material.frame;mode=@"above-material";
        }
    }
    if(!container) {container=card;index=0;target=card.bounds;}
    self.mode=mode;
    BOOL placed=self.host.superview==container &&
        (NSInteger)[container.subviews indexOfObjectIdenticalTo:self.host]==(NSInteger)index;
    if(!placed) {
        if(![self insertHostInto:container at:index]) {[self detach];self.updating=NO;return;}
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(!CGRectEqualToRect(self.host.frame,target))self.host.frame=target;
    UIViewAutoresizing mask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    if(self.host.autoresizingMask!=mask)self.host.autoresizingMask=mask;
    if(self.host.layer.cornerRadius!=card.layer.cornerRadius)self.host.layer.cornerRadius=card.layer.cornerRadius;
    self.host.layer.masksToBounds=YES;
    if(!CGRectEqualToRect(self.playback.renderLayer.frame,self.host.bounds))[self.playback layoutInBounds:self.host.bounds];
    [CATransaction commit];
    if(self.host.hidden)self.host.hidden=NO;
    if(LMVDiagnosticsEnabled.load()) {
        CGRect bounds=window.bounds,frame=[self.card convertRect:self.card.bounds toView:window];
        NSString *status=[NSString stringWithFormat:@"at-panel win=%@ %.0fx%.0f mode=%@ card=%@@%.0f,%.0f,%.0f,%.0f r%.0f vis=%.0f live=%d host=%.0fx%.0f",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            self.mode?:@"none",
            NSStringFromClass(self.card.class),frame.origin.x,frame.origin.y,frame.size.width,frame.size.height,
            self.card.layer.cornerRadius,
            LMVATPanelVisibleArea(frame,bounds),(int)live,self.host.bounds.size.width,self.host.bounds.size.height];
        static NSString *lastStatus=nil;
        if(![status isEqualToString:lastStatus]) {lastStatus=[status copy];LMVDiagnostic(status);}
    }
    self.updating=NO;
}
@end
static void LMVATPanelRetune(void) {
    NSTimeInterval want=LMVATPanelEnabled?LMVTuneProbeInterval(@"AT"):LMVTuneIdleInterval;
    if(LMVATPanelTimer && fabs(LMVATPanelTimer.timeInterval-want)<.001)return;
    [LMVATPanelTimer invalidate];
    LMVATPanelTimer=[NSTimer timerWithTimeInterval:want repeats:YES block:^(NSTimer *timer){LMVATPanelVideoRefresh(NO);}];
    [NSRunLoop.mainRunLoop addTimer:LMVATPanelTimer forMode:NSRunLoopCommonModes];
}
static void LMVATPanelVideoRefresh(BOOL reload) {
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady)return;
    if(reload || !LMVATPanelPrefsKnown) {
        LMVATPanelPrefsKnown=YES;
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("ATBackgroundEnabled"),kLMVPrefsID);
        // 0.0.114: master switch, inline (see LMVLockVideo.h).
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        LMVATPanelEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&
            [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        LMVATPanelPath=LMVCCSelectedPath(@"ATVideo");
        LMVATPanelRevision=LMVLockVideoRevision(LMVATPanelPath);
    }
    LMVATPanelRetune();
    if(!LMVATPanelEnabled || !LMVATPanelPath.length || !LMVATPanelRevision.length) {
        [LMVATPanelVideo detach];
        if(LMVATPanelVideo.playback.path)[LMVATPanelVideo.playback clear];
        return;
    }
    if(!LMVATPanelEnvironment() || !LMVATPanelHomeWindow()) {[LMVATPanelVideo detach];return;}
    // Hook install/preferences/launch alone never construct UI or a player.
    if(!LMVATPanelVideo)LMVATPanelVideo=[LMVATPanelVideoManager new];
    // A timer callback is a run-loop callback: an uncaught exception here aborts
    // SpringBoard. Every failure inside this channel stands the channel down
    // instead, and the next tick tries again.
    @try {[LMVATPanelVideo update];}
    @catch(NSException *exception) {[LMVATPanelVideo detach];}
}
static void LMVATPanelVideoSuspend(void) {
    if(!NSThread.isMainThread)return;
    [LMVATPanelVideo detach];
}
static void LMVATPanelVideoInstallHooks(void) {
    if(LMVATPanelTimer || !LMVATPanelSpringBoard())return;
    LMVATPanelRetune();
}
