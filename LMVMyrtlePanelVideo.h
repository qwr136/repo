// 1.77: the Myrtle panel background video (Myrtle 面板背景视频).
// The panel is the one that appears under the App Library / search surface: the
// window list from the device carries two visible Myrtle windows,
//   MyrtleWindow       level 1035
//   MyrtleHostWindow   level 1033
// (MyrtleKeyboardWindow, level 1034, is hidden with alpha 0 and is never a target).
// Both are full-screen containers, so - exactly like the Squid and CopyVault
// channels - the video does not go into the window: it goes into the rounded CARD
// the window presents, above its blur material and below its content.
// The card is located by geometry (largest visible rounded subview), because the
// expanded hierarchy has not been captured yet; a class-name test cannot be written
// against a structure nobody has seen.
//
// Two mistakes already paid for on the other channels are not repeated here:
//   * never require playerLayer.readyForDisplay BEFORE mounting (1.76.7) - it only
//     turns true once the layer is on screen, so that is a deadlock;
//   * never require an UNLOCKED device (1.76.9) - the panel lives over Notification
//     Center, which is on the Lock Screen.
// Depends on: LMVLockVideoPlayback, LMVCCSelectedPath, LMVLockVideoRevision,
// LMVInitialized, LMVLaunchReady, LMVBlankToken, LMVLockToken, LMVDiagnostic.
static void LMVMyrtlePanelVideoRefresh(BOOL reload);
static void LMVMyrtlePanelVideoSuspend(void);
static BOOL LMVMyrtlePanelEnabled,LMVMyrtlePanelPrefsKnown;
static NSString *LMVMyrtlePanelPath,*LMVMyrtlePanelRevision;
static NSTimer *LMVMyrtlePanelTimer;

static BOOL LMVMyrtlePanelSpringBoard(void) {
    return NSClassFromString(@"MyrtleWindow")!=nil || NSClassFromString(@"MyrtleHostWindow")!=nil;
}
static BOOL LMVMyrtlePanelEnvironment(void) {
    uint64_t blank=1,locked=1;
    // 1.77: nine conditions, evaluated separately and printed when they fail - the
    // Squid channel lost three captures to a silent `return` here.
    BOOL init=LMVInitialized, ready=LMVLaunchReady, main=NSThread.isMainThread;
    BOOL sb=LMVMyrtlePanelSpringBoard();
    BOOL haveTokens=(LMVBlankToken>=0 && LMVLockToken>=0);
    BOOL blankOK=haveTokens && notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK;
    BOOL lockOK=haveTokens && notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK;
    // `locked` is deliberately NOT required: see the header note.
    BOOL ok=init && ready && main && sb && haveTokens && blankOK && lockOK && !blank;
    if(!ok && LMVDiagnosticsEnabled.load()) {
        static NSString *last=nil;
        NSString *line=[NSString stringWithFormat:@"myrtle-panel env init=%d ready=%d main=%d sb=%d tok=%d blankOK=%d lockOK=%d blank=%llu locked=%llu",
            (int)init,(int)ready,(int)main,(int)sb,(int)haveTokens,(int)blankOK,(int)lockOK,
            (unsigned long long)blank,(unsigned long long)locked];
        if(![line isEqualToString:last]) {last=[line copy];LMVDiagnostic(line);}
    }
    return ok;
}
static NSString *LMVMyrtleWindowReport(void) {
    NSMutableString *out=[NSMutableString new];
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(out.length>900)break;
            [out appendFormat:@"%@(h%d,a%.2f,%.0fx%.0f,lv%.0f,sub%lu) ",
                NSStringFromClass(window.class),(int)window.hidden,window.alpha,
                window.frame.size.width,window.frame.size.height,window.windowLevel,
                (unsigned long)window.subviews.count];
        }
    }
    return out.length?out:@"none";
}
// 1.82: only the App Library panel window. `MyrtleHostWindow` is the floating-app
// surface (the WeChat chat list card) and `MyrtleKeyboardWindow` is a sibling at a
// lower level; neither may carry this channel.
static BOOL LMVMyrtleWindowName(NSString *name) {
    return [name isEqualToString:@"MyrtleWindow"];
}
static UIWindow *LMVMyrtlePanelWindow(NSUInteger skip) {
    UIWindow *best=nil;
    NSUInteger seen=0;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(window.hidden || window.alpha<.01)continue;
            if(!LMVMyrtleWindowName(NSStringFromClass(window.class)))continue;
            if(seen++<skip)continue;
            if(!best || window.windowLevel>best.windowLevel) best=window;
        }
    }
    return best;
}
static NSInteger const LMVMyrtlePanelHostTag=0x5A1B;

static CGFloat LMVMyrtlePanelVisibleArea(CGRect frame,CGRect bounds) {
    if(CGRectIsEmpty(frame) || CGRectIsEmpty(bounds))return 0;
    CGRect clip=CGRectIntersection(frame,bounds);
    if(CGRectIsEmpty(clip))return 0;
    return clip.size.width*clip.size.height;
}
static CGFloat LMVMyrtlePanelCoverage(CGRect inner,CGRect outer) {
    if(CGRectIsEmpty(inner) || CGRectIsEmpty(outer))return 0;
    CGFloat area=outer.size.width*outer.size.height;
    if(area<=0)return 0;
    CGRect clip=CGRectIntersection(inner,outer);
    if(CGRectIsEmpty(clip))return 0;
    return (clip.size.width*clip.size.height)/area;
}
// The panel card: the largest visible rounded subview that is smaller than the
// window itself. Skipped: our own host, hidden/transparent nodes, full-window nodes
// (those are containers, not cards) and anything parked off screen.
static UIView *LMVMyrtlePanelCard(UIWindow *window) {
    CGRect bounds=window.bounds;
    if(CGRectIsEmpty(bounds))return nil;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)window];
    NSUInteger budget=400;
    UIView *best=nil;CGFloat bestArea=0;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            [pending addObject:child];
            if(child.tag==LMVMyrtlePanelHostTag || child.hidden || child.alpha<.01)continue;
            CGRect frame=[child convertRect:child.bounds toView:window];
            if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;
            if(frame.size.width<bounds.size.width*.5 || frame.size.height<bounds.size.height*.08)continue;
            // 1.82: only the App Library LIST page. The icon grid is a centred
            // MyrtleSelectorView (320 pt on a 430 pt screen); the list spans the
            // window minus its 12 pt side inset (~406 pt). The selector also owns
            // narrower list children, so both its class and the width are checked.
            if([NSStringFromClass(child.class) isEqualToString:@"MyrtleSelectorView"])continue;
            if(frame.size.width<bounds.size.width*.85)continue;
            CGFloat visible=LMVMyrtlePanelVisibleArea(frame,bounds);
            if(visible<=0)continue;
            if(visible>bestArea){bestArea=visible;best=child;}
        }
    }
    return best;
}
// The blur material serving that card: a UIVisualEffectView covering at least 90%
// of it. Only the material's contentView is ever used as a container (a
// UIVisualEffectView refuses direct subviews and raises).
static UIView *LMVMyrtlePanelMaterial(UIView *root,UIWindow *window,CGRect clip) {
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
            if(LMVMyrtlePanelVisibleArea(frame,bounds)<=0)continue;
            if(LMVMyrtlePanelCoverage(frame,clip)<.9)continue;
            CGFloat area=frame.size.width*frame.size.height;
            if(area>bestArea){bestArea=area;best=child;}
        }
    }
    return best;
}
@interface LMVMyrtlePanelVideoHost:UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@end
@implementation LMVMyrtlePanelVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.tag=LMVMyrtlePanelHostTag;
        self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;self.accessibilityElementsHidden=YES;
        self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.clipsToBounds=YES;
    }
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
@end
@interface LMVMyrtlePanelVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVMyrtlePanelVideoHost *host;
@property(nonatomic,weak) UIView *card;
@property(nonatomic,copy) NSString *mode;
@property(nonatomic) BOOL updating;
- (void)detach;
- (void)update;
@end
static LMVMyrtlePanelVideoManager *LMVMyrtlePanelVideo;
@implementation LMVMyrtlePanelVideoManager
- (instancetype)init {
    if(!LMVMyrtlePanelEnvironment())return nil;
    if((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=NO;
        _host=[[LMVMyrtlePanelVideoHost alloc] initWithFrame:CGRectZero];_host.playback=_playback;
        _playback.renderLayer.name=@"com.minis.lockmessagevideo.myrtle-panel.render";
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
- (BOOL)insertHostInto:(UIView *)container at:(NSUInteger)index {
    if(!container || [container isKindOfClass:UIVisualEffectView.class])return NO;
    [self.host removeFromSuperview];
    @try {[container insertSubview:self.host atIndex:index];}
    @catch(NSException *exception) {[self.host removeFromSuperview];return NO;}
    return self.host.superview==container;
}
- (void)update {
    if(self.updating)return;self.updating=YES;
    // Two candidate windows (1035 / 1033): whichever one currently carries a card wins.
    UIWindow *window=nil;UIView *card=nil;CGRect cardFrame=CGRectZero;
    for(NSUInteger i=0;i<2;i++) {
        UIWindow *candidate=LMVMyrtlePanelWindow(i);
        if(!candidate)continue;
        UIView *found=LMVMyrtlePanelCard(candidate);
        if(!found)continue;
        CGRect frame=[found convertRect:found.bounds toView:candidate];
        if(LMVMyrtlePanelVisibleArea(frame,candidate.bounds)<=0)continue;
        window=candidate;card=found;cardFrame=frame;break;
    }
    if(!card) {
        if(LMVDiagnosticsEnabled.load()) {
            static NSString *lastWindows=nil;
            NSString *line=[NSString stringWithFormat:@"myrtle-panel windows win=%d %@",
                (int)(LMVMyrtlePanelWindow(0)!=nil),LMVMyrtleWindowReport()];
            if(![line isEqualToString:lastWindows]) {lastWindows=[line copy];LMVDiagnostic(line);}
        }
        [self detach];self.updating=NO;return;
    }
    if(self.card!=card) {[self.host removeFromSuperview];self.card=card;}
    BOOL changed=![self.playback.path isEqualToString:LMVMyrtlePanelPath] ||
        ![self.playback.revision isEqualToString:LMVMyrtlePanelRevision];
    if(changed) {
        [self.host removeFromSuperview];
        // Poster first, so the layer has pixels on the very first frame.
        [self.playback preparePosterForPath:LMVMyrtlePanelPath revision:LMVMyrtlePanelRevision];
        [self.playback selectPath:LMVMyrtlePanelPath revision:LMVMyrtlePanelRevision];
    }
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    // Mount as soon as there are real pixels; the player covers them when ready.
    BOOL hasPoster=self.playback.posterLayer.contents!=nil;
    BOOL live=self.playback.player && !self.playback.error &&
        (hasPoster || self.playback.playerLayer.readyForDisplay);
    if(!live) {[self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;return;}
    UIView *material=LMVMyrtlePanelMaterial(card,window,cardFrame);
    if(!material)material=LMVMyrtlePanelMaterial(window,window,cardFrame);
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
    if(!container) {container=card;index=0;target=card.bounds;mode=@"card-only";}
    self.mode=mode;
    BOOL placed=self.host.superview==container &&
        (NSInteger)[container.subviews indexOfObjectIdenticalTo:self.host]==(NSInteger)index;
    if(!placed) {
        if(![self insertHostInto:container at:index]) {[self detach];self.updating=NO;return;}
    }
    CGFloat radius=material.layer.cornerRadius;
    if(!(radius>0))radius=card.layer.cornerRadius;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(!CGRectEqualToRect(self.host.frame,target))self.host.frame=target;
    UIViewAutoresizing mask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    if(self.host.autoresizingMask!=mask)self.host.autoresizingMask=mask;
    if(self.host.layer.cornerRadius!=radius)self.host.layer.cornerRadius=radius;
    self.host.layer.masksToBounds=YES;
    if(!CGRectEqualToRect(self.playback.renderLayer.frame,self.host.bounds))[self.playback layoutInBounds:self.host.bounds];
    [CATransaction commit];
    if(self.host.hidden)self.host.hidden=NO;
    if(LMVDiagnosticsEnabled.load()) {
        CGRect bounds=window.bounds;
        NSString *status=[NSString stringWithFormat:@"myrtle-panel win=%@ %.0fx%.0f mode=%@ card=%@@%.0f,%.0f,%.0f,%.0f r%.0f vis=%.0f live=%d host=%.0fx%.0f",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            self.mode?:@"none",
            NSStringFromClass(self.card.class),cardFrame.origin.x,cardFrame.origin.y,
            cardFrame.size.width,cardFrame.size.height,
            radius,LMVMyrtlePanelVisibleArea(cardFrame,bounds),(int)live,
            self.host.bounds.size.width,self.host.bounds.size.height];
        static NSString *lastStatus=nil;
        if(![status isEqualToString:lastStatus]) {lastStatus=[status copy];LMVDiagnostic(status);}
    }
    self.updating=NO;
}
@end
static void LMVMyrtlePanelRetune(void) {
    NSTimeInterval want=LMVMyrtlePanelEnabled?.1:.5;
    if(LMVMyrtlePanelTimer && fabs(LMVMyrtlePanelTimer.timeInterval-want)<.001)return;
    [LMVMyrtlePanelTimer invalidate];
    LMVMyrtlePanelTimer=[NSTimer timerWithTimeInterval:want repeats:YES block:^(NSTimer *timer){LMVMyrtlePanelVideoRefresh(NO);}];
    [NSRunLoop.mainRunLoop addTimer:LMVMyrtlePanelTimer forMode:NSRunLoopCommonModes];
}
static void LMVMyrtlePanelVideoRefresh(BOOL reload) {
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady)return;
    if(reload || !LMVMyrtlePanelPrefsKnown) {
        LMVMyrtlePanelPrefsKnown=YES;
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("MyrtleBackgroundEnabled"),kLMVPrefsID);
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        LMVMyrtlePanelEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&
            [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        LMVMyrtlePanelPath=LMVCCSelectedPath(@"MyrtleVideo");
        LMVMyrtlePanelRevision=LMVLockVideoRevision(LMVMyrtlePanelPath);
    }
    LMVMyrtlePanelRetune();
    if(!LMVMyrtlePanelEnabled || !LMVMyrtlePanelPath.length || !LMVMyrtlePanelRevision.length) {
        // Say which one it was - "switch off" and "no material" are different reports.
        if(LMVDiagnosticsEnabled.load()) {
            static NSString *lastGate=nil;
            NSString *gate=[NSString stringWithFormat:@"myrtle-panel gate enabled=%d path=%d revision=%d (no video: switch off or no material selected)",
                (int)LMVMyrtlePanelEnabled,(int)(LMVMyrtlePanelPath.length>0),(int)(LMVMyrtlePanelRevision.length>0)];
            if(![gate isEqualToString:lastGate]) {lastGate=[gate copy];LMVDiagnostic(gate);}
        }
        [LMVMyrtlePanelVideo detach];
        if(LMVMyrtlePanelVideo.playback.path)[LMVMyrtlePanelVideo.playback clear];
        return;
    }
    if(!LMVMyrtlePanelEnvironment() || !LMVMyrtlePanelWindow(0)) {
        if(LMVDiagnosticsEnabled.load()) {
            static NSString *lastWindows=nil;
            NSString *line=[NSString stringWithFormat:@"myrtle-panel windows env=%d win=%d %@",
                (int)LMVMyrtlePanelEnvironment(),(int)(LMVMyrtlePanelWindow(0)!=nil),LMVMyrtleWindowReport()];
            if(![line isEqualToString:lastWindows]) {lastWindows=[line copy];LMVDiagnostic(line);}
        }
        [LMVMyrtlePanelVideo detach];return;
    }
    if(!LMVMyrtlePanelVideo)LMVMyrtlePanelVideo=[LMVMyrtlePanelVideoManager new];
    @try {[LMVMyrtlePanelVideo update];}
    @catch(NSException *exception) {[LMVMyrtlePanelVideo detach];}
}
static void LMVMyrtlePanelVideoSuspend(void) {
    [LMVMyrtlePanelTimer invalidate];LMVMyrtlePanelTimer=nil;
    [LMVMyrtlePanelVideo detach];
    if(LMVMyrtlePanelVideo.playback.path)[LMVMyrtlePanelVideo.playback clear];
}
