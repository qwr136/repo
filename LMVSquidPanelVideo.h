#pragma once
// 1.25: the SquidGesturePro panel background (鱿鱼面板背景视频).
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
static BOOL LMVSquidPanelEnabled,LMVSquidPanelPrefsKnown,LMVSquidPanelSwapShapes;
// 1.44: the panel has two shapes, so it has two material slots - slot 1 for the
// tall ("swipe up") panel, slot 2 for the short ("swipe up twice") one. The sound
// switch and volume stay shared: only one of the two is ever on screen.
static NSString *LMVSquidPanelPath,*LMVSquidPanelRevision,*LMVSquidPanelPath2,*LMVSquidPanelRevision2;
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
// 1.25: how much of this view is REALLY on screen. The panel keeps SEVERAL activity
// panel views - the device log shows two of them, both 430x435, one on screen at
// y=497 and one parked at y=1459 in a 932-high window. Scoring by raw area alone
// made the choice flip between them as the tree order changed, so the video kept
// jumping onto the parked (invisible) card - which is what "看不到视频背景" was.
// A candidate now only qualifies while at least half of it is inside the window,
// and the one with the largest visible area wins.
static CGFloat LMVSquidPanelVisibleArea(CGRect frame,CGRect bounds) {
    if(CGRectIsEmpty(frame) || CGRectIsEmpty(bounds))return 0;
    CGRect onScreen=CGRectIntersection(frame,bounds);
    if(CGRectIsEmpty(onScreen))return 0;
    CGFloat total=frame.size.width*frame.size.height;
    if(total<=0)return 0;
    CGFloat visible=onScreen.size.width*onScreen.size.height;
    return visible/total>=.5?visible:0;
}
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
            CGFloat visible=LMVSquidPanelVisibleArea(frame,bounds);
            if(visible<=0)continue;   // parked off screen - never a candidate
            if(visible>bestArea){bestArea=visible;best=child;}
        }
    }
    return best;
}
// 1.25: the panel's blur material - the effect view that gives the card its
// background. It is what the video has to sit ABOVE (otherwise the material hides
// it: the 1.25 report) and what the icons sit above.
// 1.44: the panel keeps TWO shapes - the "swipe up" one and the "swipe up twice"
// one - and in BOTH of them the blur material is sized to the SCREEN, not to the
// card (landscape: 932x435 of material behind a 814x180 card). Scoring the material
// with the CARD rule ("at least half of ITSELF on screen", the rule that skips the
// parked copies) therefore dropped it to 36% and the material was mistaken for a
// parked copy: the short landscape panel lost its material, the video fell back to
// the card's first subview - UNDER the material - and became invisible.
//
// The material is not a card: it is searched INSIDE the card that was already
// chosen, so the parked copies are unreachable from here by construction. The only
// question worth asking is whether it COVERS that card, which is also what the
// video needs; anything covering >=90% of the card qualifies.
static UIView *LMVSquidPanelMaterial(UIView *root,UIWindow *window) {
    if(!root || !window)return nil;
    CGRect cardFrame=[root convertRect:root.bounds toView:window];
    if(CGRectIsEmpty(cardFrame))return nil;
    CGFloat cardArea=cardFrame.size.width*cardFrame.size.height;
    if(cardArea<=0)return nil;
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
            CGRect cover=CGRectIntersection(frame,cardFrame);
            if(CGRectIsEmpty(cover))continue;
            CGFloat area=cover.size.width*cover.size.height;
            if(area/cardArea<.9)continue;   // must actually cover the card it serves
            if(area>bestArea){bestArea=area;best=child;}
        }
    }
    return best;
}
// 1.44: which of the two panels is on screen - the tall one ("swipe up") or the
// short one ("swipe up twice"). They are separate objects: each keeps an on-screen
// and a parked copy of its own SFActivityPanelView, and they differ in height
// (portrait 435 vs 350, landscape 340 vs 180). Height alone is a fragile test (the
// short landscape panel is 41.9% of the screen while the tall portrait one is
// 46.7%), so the shape is read from the page control, which belongs to exactly one
// of them, sits 20pt above ITS OWN card in every orientation, and is hidden (h1) on
// the short panel while the tall one keeps it (h0) - the same in landscape and in
// portrait, in all four copies the device log showed.
// 1.46: WHAT was classified, not what it looks like.
//
// The two panels are two separate, long-lived objects. A card that has been
// classified once keeps that classification for as long as the object lives, so
// editing a panel - adding icons, making it taller, giving it a page control it did
// not have before - can never flip it. That is exactly what broke: the short panel
// was made taller and started borrowing the tall panel's material, because the test
// below looks at the panel's CONTENT and the content had changed.
//
// The content test now runs ONLY for a card that has never been seen before; from
// then on the identity decides. (If a panel is ever re-created, the new object gets
// one fresh content test, and the settings app has a "对调" row for the case where
// that one test guesses wrong.)
static __weak UIView *LMVSquidPanelTallCard,*LMVSquidPanelShortCard;
static NSString *LMVSquidPanelShapeReason=@"none";
static BOOL LMVSquidPanelCardIsShort(UIView *card,UIWindow *window) {
    if(card && card==LMVSquidPanelShortCard){LMVSquidPanelShapeReason=@"remembered";return YES;}
    if(card && card==LMVSquidPanelTallCard){LMVSquidPanelShapeReason=@"remembered";return NO;}
    CGRect cardFrame=[card convertRect:card.bounds toView:window];
    UIPageControl *page=nil;CGFloat bestGap=CGFLOAT_MAX;
    for(UIView *host=card.superview;host;host=host.superview) {
        for(UIView *node in host.subviews) {
            if(![node isKindOfClass:UIPageControl.class])continue;
            CGRect f=[node convertRect:node.bounds toView:window];
            CGFloat gap=fabs(CGRectGetMaxY(f)-CGRectGetMinY(cardFrame));
            if(gap<bestGap){bestGap=gap;page=(UIPageControl *)node;}
        }
        if(page && bestGap<40)break;
    }
    BOOL shortPanel;
    if(page && bestGap<40) {                            // the reliable signal
        shortPanel=page.hidden;
        LMVSquidPanelShapeReason=[NSString stringWithFormat:@"page.hidden=%d/gap=%.0f",(int)page.hidden,bestGap];
    } else {                                            // fallback: measured heights
        CGFloat height=window.bounds.size.height;
        shortPanel=(height>0 && cardFrame.size.height<height*.45);
        LMVSquidPanelShapeReason=[NSString stringWithFormat:@"height=%.0f/%.0f",cardFrame.size.height,height];
    }
    if(card) {if(shortPanel)LMVSquidPanelShortCard=card; else LMVSquidPanelTallCard=card;}
    return shortPanel;
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
@property(nonatomic,copy) NSString *mode;
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
    self.card=nil;self.mode=nil;
}
// 1.25: a UIVisualEffectView REFUSES direct subviews - addSubview: raises, and an
// exception escaping a run-loop callback ABORTS SpringBoard (the 1.25 safe-mode
// crash: UIVisualEffectView _addSubview:positioned:relativeTo: thrown from this
// module's timer). So the effect view is never used as the container: the host
// goes into its superview directly BELOW it, which keeps the blur sampling the
// video (the look we want) and cannot raise. Anything unexpected is caught here
// and simply leaves the panel alone.
- (BOOL)insertHostInto:(UIView *)container at:(NSUInteger)index {
    if(!container || [container isKindOfClass:UIVisualEffectView.class])return NO;
    [self.host removeFromSuperview];
    @try {[container insertSubview:self.host atIndex:index];}
    @catch(NSException *exception) {[self.host removeFromSuperview];return NO;}
    return self.host.superview==container;
}
- (void)update {
    if(self.updating)return;self.updating=YES;
    UIWindow *window=LMVSquidPanelWindow();
    UIView *card=window?LMVSquidPanelCard(window):nil;
    if(!card) {[self detach];self.updating=NO;return;}
    if(self.card!=card) {[self.host removeFromSuperview];self.card=card;}
    // 1.44/1.45: two panels, two slots, and they are INDEPENDENT - there is no
    // fallback between them. The tall one ("swipe up") plays slot 1, the short one
    // ("swipe up twice") plays slot 2, and a slot left empty means that panel simply
    // gets no video: it keeps its original look and stays silent (detach also stands
    // the shared audio channel down, so nothing is heard). The shape does not depend
    // on the orientation, so slot 1 is the tall panel in landscape too.
    BOOL shortPanel=LMVSquidPanelCardIsShort(card,window);
    // 1.46: "对调" - for the case where the very first content test guessed the two
    // panels the other way round. It flips which slot each shape plays, and it does
    // not touch the identity memory above (that records the shape, this picks the
    // material).
    BOOL useSecond=LMVSquidPanelSwapShapes?!shortPanel:shortPanel;
    NSString *wantPath=useSecond?LMVSquidPanelPath2:LMVSquidPanelPath;
    NSString *wantRevision=useSecond?LMVSquidPanelRevision2:LMVSquidPanelRevision;
    if(!wantPath.length || !wantRevision.length) {
        // 1.45: say so out loud, once per state change - "this panel has no material"
        // is otherwise indistinguishable from "the channel is broken" in a log.
        if(LMVDiagnosticsEnabled.load()) {
            NSString *empty=[NSString stringWithFormat:@"squid-panel shape=%@ slot=empty (no video, by design)",
                shortPanel?@"short":@"tall"];
            static NSString *lastEmpty=nil;
            if(![empty isEqualToString:lastEmpty]) {lastEmpty=[empty copy];LMVDiagnostic(empty);}
        }
        [self detach];self.updating=NO;return;
    }
    BOOL changed=![self.playback.path isEqualToString:wantPath] ||
        ![self.playback.revision isEqualToString:wantRevision];
    if(changed) {[self.host removeFromSuperview];[self.playback selectPath:wantPath revision:wantRevision];}
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    // A still poster is not a panel background: wait for the decoder, exactly like
    // the menu channel does, and simply leave the panel alone until then.
    self.playback.posterLayer.hidden=YES;
    BOOL live=self.playback.player && self.playback.playerLayer.readyForDisplay && !self.playback.error;
    if(!live) {[self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;return;}
    // 1.25: WHERE in the panel the video belongs. 1.25 put it directly BELOW the
    // panel's blur material, and the material simply hid it (device report: 视频太
    // 靠下面 / 看不到视频背景). The video belongs UNDER the icons but ABOVE the
    // material: inside the material's contentView when there is one (that is above
    // the blur and below anything the material draws), otherwise directly above the
    // material in the same superview. Either way it keeps the material's exact
    // frame, so a panel that grows with its icons moves the video with it.
    UIView *material=LMVSquidPanelMaterial(card,window);
    if(!material)material=LMVSquidPanelMaterial(window,window);
    UIView *container=nil;NSUInteger index=0;NSString *mode=@"card";
    if([material isKindOfClass:UIVisualEffectView.class]) {
        UIView *content=((UIVisualEffectView *)material).contentView;
        if(content && content.subviews.count<40) {
            container=content;index=0;mode=@"content";
        } else if(material.superview) {
            container=material.superview;
            NSInteger near=(NSInteger)[container.subviews indexOfObjectIdenticalTo:material];
            if(near==NSNotFound) {[self detach];self.updating=NO;return;}
            index=(NSUInteger)(near+1);mode=@"above-material";
        }
    }
    if(!container) {container=card;index=0;}
    // 1.44: the video fills the CARD - the surface the user actually sees - not the
    // container it happens to be inserted into. The material is a full-screen view
    // in landscape (932x435 against the 814x180 card) and the content view inherits
    // that size, so sizing the video to the container made it overflow the panel
    // instead of filling it. Intersecting container and card keeps every shape and
    // both orientations exact.
    CGRect cardInContainer=[card convertRect:card.bounds toView:container];
    CGRect target=CGRectIntersection(container.bounds,cardInContainer);
    if(CGRectIsEmpty(target))target=cardInContainer;
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
        NSString *status=[NSString stringWithFormat:@"squid-panel win=%@ %.0fx%.0f shape=%@ slot=%d why=%@ mode=%@ card=%@@%.0f,%.0f,%.0f,%.0f ptr=%p vis=%.0f live=%d host=%.0fx%.0f",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            shortPanel?@"short":@"tall",useSecond?2:1,LMVSquidPanelShapeReason,
            self.mode?:@"none",
            NSStringFromClass(self.card.class),frame.origin.x,frame.origin.y,frame.size.width,frame.size.height,
            (void *)self.card,
            LMVSquidPanelVisibleArea(frame,bounds),(int)live,self.host.bounds.size.width,self.host.bounds.size.height];
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
        // 1.44: the second slot, for the short ("swipe up twice") panel.
        LMVSquidPanelPath2=LMVCCSelectedPath(@"SquidPanel2Video");
        LMVSquidPanelRevision2=LMVLockVideoRevision(LMVSquidPanelPath2);
        // 1.46: "对调上滑 / 上上滑素材" - see useSecond in -update.
        id swap=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("SquidPanelSwapShapes"),kLMVPrefsID);
        LMVSquidPanelSwapShapes=[swap isKindOfClass:NSNumber.class] && [swap boolValue];
    }
    LMVSquidPanelRetune();
    BOOL anySlot=(LMVSquidPanelPath.length && LMVSquidPanelRevision.length) ||
        (LMVSquidPanelPath2.length && LMVSquidPanelRevision2.length);
    if(!LMVSquidPanelEnabled || !anySlot) {
        [LMVSquidPanelVideo detach];
        if(LMVSquidPanelVideo.playback.path)[LMVSquidPanelVideo.playback clear];
        return;
    }
    if(!LMVSquidPanelEnvironment() || !LMVSquidPanelWindow()) {[LMVSquidPanelVideo detach];return;}
    // Hook install/preferences/launch alone never construct UI or a player.
    if(!LMVSquidPanelVideo)LMVSquidPanelVideo=[LMVSquidPanelVideoManager new];
    // A timer callback is a run-loop callback: an uncaught exception here aborts
    // SpringBoard. Every failure inside this channel stands the channel down
    // instead, and the next tick tries again.
    @try {[LMVSquidPanelVideo update];}
    @catch(NSException *exception) {[LMVSquidPanelVideo detach];}
}
static void LMVSquidPanelVideoSuspend(void) {
    if(!NSThread.isMainThread)return;
    [LMVSquidPanelVideo detach];
}
static void LMVSquidPanelVideoInstallHooks(void) {
    if(LMVSquidPanelTimer || !LMVSquidPanelSpringBoard())return;
    LMVSquidPanelRetune();
}
