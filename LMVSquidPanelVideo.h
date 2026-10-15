#pragma once
// 1.22: the SquidGesturePro panel background (鱿鱼面板背景视频).
//
// Device diagnostics settled the shape of that panel: it lives in SGPanelWindow,
// a FULL-SCREEN window (430x932) whose first two levels are full-screen as well,
// and the surface the user sees inside it is a rounded card in the lower part of
// the screen that GROWS with the number of icons. There is therefore no geometry
// worth storing: the video is attached INSIDE the card as its first subview (under
// everything the card itself draws) and re-sized to the card on every poll, so it
// follows the panel exactly - the panel grows, the video grows with it.
//
// Poll-based on purpose: no private class of that tweak is hooked or guessed, and
// when the switch is off nothing is constructed at all.
#import <stdbool.h>

static void LMVSquidPanelVideoRefresh(BOOL reload);
static void LMVSquidPanelVideoSuspend(void);
static BOOL LMVSquidPanelEnabled,LMVSquidPanelPrefsKnown;
static NSString *LMVSquidPanelPath,*LMVSquidPanelRevision;
static NSTimer *LMVSquidPanelTimer;
static BOOL LMVSquidPanelSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}
static BOOL LMVSquidPanelEnvironment(void) {
    uint64_t blank=1,locked=1;
    return LMVInitialized && LMVLaunchReady && NSThread.isMainThread && LMVSquidPanelSpringBoard() &&
        LMVBlankToken>=0 && LMVLockToken>=0 &&
        notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK &&
        notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK && !blank && !locked;
}
// The panel window: the class name the device log named. Nothing else is assumed.
static UIWindow *LMVSquidPanelWindow(void) {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(window.hidden || window.alpha<.01)continue;
            if([NSStringFromClass(window.class) containsString:@"SGPanel"])return window;
        }
    }
    return nil;
}
static NSInteger const LMVSquidPanelHostTag=0x5A17;
// The card: the largest visible descendant that does NOT fill the window (at least
// half its width and an eighth of its height). That rule skips the full-screen
// containers - the window content and the tweak's activity container - and our own
// host is excluded by its tag, so what remains is the rounded panel surface.
static UIView *LMVSquidPanelCard(UIWindow *window) {
    CGRect bounds=window.bounds;
    if(CGRectIsEmpty(bounds))return nil;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)window];
    NSUInteger budget=300;
    UIView *best=nil;CGFloat bestArea=0;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            [pending addObject:child];
            if(child.tag==LMVSquidPanelHostTag || child.hidden || child.alpha<.01)continue;
            CGRect frame=[child convertRect:child.bounds toView:window];
            if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;
            if(frame.size.width<bounds.size.width*.5 || frame.size.height<bounds.size.height*.08)continue;
            CGFloat area=frame.size.width*frame.size.height;
            if(area>bestArea){bestArea=area;best=child;}
        }
    }
    return best;
}
@interface LMVSquidPanelVideoHost:UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@end
@implementation LMVSquidPanelVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.tag=LMVSquidPanelHostTag;
        self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;self.accessibilityElementsHidden=YES;
        self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.clipsToBounds=YES;
    }
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
@end
@interface LMVSquidPanelVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVSquidPanelVideoHost *host;
@property(nonatomic,weak) UIView *card;
@property(nonatomic) BOOL updating;
- (void)detach;
- (void)update;
@end
static LMVSquidPanelVideoManager *LMVSquidPanelVideo;
@implementation LMVSquidPanelVideoManager
- (instancetype)init {
    if(!LMVSquidPanelEnvironment())return nil;
    if((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=NO;
        _host=[[LMVSquidPanelVideoHost alloc] initWithFrame:CGRectZero];_host.playback=_playback;
        _playback.renderLayer.name=@"com.minis.lockmessagevideo.squid-panel.render";
        [_host.layer addSublayer:_playback.renderLayer];
    }
    return self;
}
- (void)dealloc {[_host removeFromSuperview];}
- (void)detach {
    if(self.host.superview)[self.host removeFromSuperview];
    self.host.hidden=YES;
    if(self.playback.wantsPlayback)[self.playback setVisible:NO];
    self.card=nil;
}
- (void)update {
    if(self.updating)return;self.updating=YES;
    UIWindow *window=LMVSquidPanelWindow();
    UIView *card=window?LMVSquidPanelCard(window):nil;
    if(!card) {[self detach];self.updating=NO;return;}
    if(self.card!=card) {[self.host removeFromSuperview];self.card=card;}
    BOOL changed=![self.playback.path isEqualToString:LMVSquidPanelPath] ||
        ![self.playback.revision isEqualToString:LMVSquidPanelRevision];
    if(changed) {[self.host removeFromSuperview];[self.playback selectPath:LMVSquidPanelPath revision:LMVSquidPanelRevision];}
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    // A still poster is not a panel background: wait for the decoder, exactly like
    // the menu channel does, and simply leave the panel alone until then.
    self.playback.posterLayer.hidden=YES;
    BOOL live=self.playback.player && self.playback.playerLayer.readyForDisplay && !self.playback.error;
    if(!live) {[self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;return;}
    if(self.host.superview!=card || card.subviews.firstObject!=self.host) {
        [self.host removeFromSuperview];[card insertSubview:self.host atIndex:0];
    }
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(!CGRectEqualToRect(self.host.frame,card.bounds))self.host.frame=card.bounds;
    UIViewAutoresizing mask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    if(self.host.autoresizingMask!=mask)self.host.autoresizingMask=mask;
    if(self.host.layer.cornerRadius!=card.layer.cornerRadius)self.host.layer.cornerRadius=card.layer.cornerRadius;
    self.host.layer.masksToBounds=YES;
    if(!CGRectEqualToRect(self.playback.renderLayer.frame,self.host.bounds))[self.playback layoutInBounds:self.host.bounds];
    [CATransaction commit];
    if(self.host.hidden)self.host.hidden=NO;
    if(LMVDiagnosticsEnabled.load()) {
        CGRect bounds=window.bounds,frame=[self.card convertRect:self.card.bounds toView:window];
        NSString *status=[NSString stringWithFormat:@"squid-panel win=%@ %.0fx%.0f card=%@@%.0f,%.0f,%.0f,%.0f live=%d host=%.0fx%.0f",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            NSStringFromClass(self.card.class),frame.origin.x,frame.origin.y,frame.size.width,frame.size.height,
            (int)live,self.host.bounds.size.width,self.host.bounds.size.height];
        static NSString *lastStatus=nil;
        if(![status isEqualToString:lastStatus]) {lastStatus=[status copy];LMVDiagnostic(status);}
    }
    self.updating=NO;
}
@end
static void LMVSquidPanelRetune(void) {
    NSTimeInterval want=LMVSquidPanelEnabled?.1:.5;
    if(LMVSquidPanelTimer && fabs(LMVSquidPanelTimer.timeInterval-want)<.001)return;
    [LMVSquidPanelTimer invalidate];
    LMVSquidPanelTimer=[NSTimer timerWithTimeInterval:want repeats:YES block:^(NSTimer *timer){LMVSquidPanelVideoRefresh(NO);}];
    [NSRunLoop.mainRunLoop addTimer:LMVSquidPanelTimer forMode:NSRunLoopCommonModes];
}
static void LMVSquidPanelVideoRefresh(BOOL reload) {
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady)return;
    if(reload || !LMVSquidPanelPrefsKnown) {
        LMVSquidPanelPrefsKnown=YES;
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("SquidPanelBackgroundEnabled"),kLMVPrefsID);
        // 0.0.114: master switch, inline (see LMVLockVideo.h).
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        LMVSquidPanelEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&
            [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        LMVSquidPanelPath=LMVCCSelectedPath(@"SquidPanelVideo");
        LMVSquidPanelRevision=LMVLockVideoRevision(LMVSquidPanelPath);
    }
    LMVSquidPanelRetune();
    if(!LMVSquidPanelEnabled || !LMVSquidPanelPath.length || !LMVSquidPanelRevision.length) {
        [LMVSquidPanelVideo detach];
        if(LMVSquidPanelVideo.playback.path)[LMVSquidPanelVideo.playback clear];
        return;
    }
    if(!LMVSquidPanelEnvironment() || !LMVSquidPanelWindow()) {[LMVSquidPanelVideo detach];return;}
    // Hook install/preferences/launch alone never construct UI or a player.
    if(!LMVSquidPanelVideo)LMVSquidPanelVideo=[LMVSquidPanelVideoManager new];
    [LMVSquidPanelVideo update];
}
static void LMVSquidPanelVideoSuspend(void) {
    if(!NSThread.isMainThread)return;
    [LMVSquidPanelVideo detach];
}
static void LMVSquidPanelVideoInstallHooks(void) {
    if(LMVSquidPanelTimer || !LMVSquidPanelSpringBoard())return;
    LMVSquidPanelRetune();
}
