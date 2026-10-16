#pragma once
// 1.43: the CopyVault clipboard panel background (CopyVault 面板背景视频).
//
// Shape settled by the 1.42 device diagnostics (`desktop-panel-tree` /
// `desktop-window-meta`), and it is the SAME shape as SquidGesturePro's panel:
// CopyVault owns a real window, so this channel can be scoped to that window
// alone and can never latch onto an unrelated presentation the way the AT channel
// once did with the system long-press menu.
//
//   CVPanelWindow@0,0,430,932 lvl=10000010 rvc=CVPanelViewController
//     UIView@0,0,430,932
//       CVPanelView@0,0,430,932
//         UIControl@0,0,430,932
//           CopyVaultView@5,497,420,430        <- THE CARD (bottom-anchored)
//             UIVisualEffectView@0,0,420,430 r55  <- the blur material
//               _UIVisualEffectBackdropView
//               _UIVisualEffectSubview
//             UIView@0,0,420,430 r55           <- the content container
//               UIView@0,0,420,67
//               CopyVaultHistoryTableView / CopyVaultArchiveTableView / ...
//
// Two device facts drive the rules below:
//
// 1. The card's material and its content are SIBLINGS, not nested: the material
//    is child #0 and the content child #1 of `CopyVaultView`. Putting the video
//    into the material's own contentView therefore lands it ABOVE the blur and
//    BELOW the content - exactly the "under the icons but above the material"
//    level 1.24 settled for Squid, with no index arithmetic on the card.
// 2. When the panel is CLOSED the very same card is parked OFF SCREEN at y=1454
//    (the window is full screen, so nothing else gives it away). The shared
//    "at least half of it is really on screen" rule is what keeps the video off
//    that parked copy.
//
// The card is r0 while the material and the content container are r55, so the
// corner radius comes from the material (the surface the video actually sits in),
// not from the card.
//
// Poll-based and private-class-free: nothing of CopyVault is hooked or guessed,
// and when the switch is off nothing is constructed at all.
//
// Requires the shared helpers imported earlier in the translation unit
// (LMVLockVideoPlayback, LMVCCSelectedPath, LMVLockVideoRevision, LMVInitialized,
// LMVLaunchReady, LMVBlankToken, LMVLockToken, LMVDiagnosticsEnabled,
// LMVDiagnostic, kLMVPrefsID).
#import <stdbool.h>

static void LMVCopyVaultPanelVideoRefresh(BOOL reload);
static void LMVCopyVaultPanelVideoSuspend(void);
static BOOL LMVCVPanelEnabled,LMVCVPanelPrefsKnown;
static NSString *LMVCVPanelPath,*LMVCVPanelRevision;
static NSTimer *LMVCVPanelTimer;
static BOOL LMVCVPanelSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}
static BOOL LMVCVPanelEnvironment(void) {
    uint64_t blank=1,locked=1;
    return LMVInitialized && LMVLaunchReady && NSThread.isMainThread && LMVCVPanelSpringBoard() &&
        LMVBlankToken>=0 && LMVLockToken>=0 &&
        notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK &&
        notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK && !blank && !locked;
}
// The window CopyVault owns. The 1.42 desktop-window-meta line named it:
// CVPanelWindow with root view controller CVPanelViewController.
static UIWindow *LMVCVPanelWindow(void) {
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(window.hidden || window.alpha<.01)continue;
            NSString *name=NSStringFromClass(window.class);
            if([name containsString:@"CVPanel"] || [name containsString:@"CopyVault"])return window;
        }
    }
    return nil;
}
static NSInteger const LMVCVPanelHostTag=0x5A19;
// How much of this view is REALLY on screen. The card is parked at y=1454 while the
// panel is closed, and scoring by raw area alone would happily mount there.
static CGFloat LMVCVPanelVisibleArea(CGRect frame,CGRect bounds) {
    if(CGRectIsEmpty(frame) || CGRectIsEmpty(bounds))return 0;
    CGRect onScreen=CGRectIntersection(frame,bounds);
    if(CGRectIsEmpty(onScreen))return 0;
    CGFloat total=frame.size.width*frame.size.height;
    if(total<=0)return 0;
    CGFloat visible=onScreen.size.width*onScreen.size.height;
    return visible/total>=.5?visible:0;
}
// How much of `inner` lies inside `outer`.
static CGFloat LMVCVPanelCoverage(CGRect inner,CGRect outer) {
    if(CGRectIsEmpty(inner) || CGRectIsEmpty(outer))return 0;
    CGRect inside=CGRectIntersection(inner,outer);
    if(CGRectIsEmpty(inside))return 0;
    CGFloat total=inner.size.width*inner.size.height;
    if(total<=0)return 0;
    return (inside.size.width*inside.size.height)/total;
}
// 1.49: THE CARD IS NAMED. 1.43-1.48 picked "the largest visible surface in the
// window", and the 2026-10-17 logs show exactly what that costs: the moment a
// TALLER surface is pushed into the same CVPanelWindow the clipboard panel ends
// up sharing - CopyVault's own preview/toolbar sheet (portrait: the 498pt
// UIDropShadowView outranks the 430pt card) - the area race is lost and the video
// is dragged up over that sheet. Landscape loses the same race to a 916x722
// _UIRoundedRectShadowView and parks the video on the wrong surface altogether.
// One failure, both orientations, so identity instead of size: the card is the
// view the plugin calls CopyVaultView, whatever else is on screen.
static BOOL LMVCVPanelVaultClass(UIView *view) {
    NSString *name=NSStringFromClass(view.class);
    if([name isEqualToString:@"CopyVaultView"])return YES;
    // Any other CopyVault surface, but never the list content inside the card.
    return [name containsString:@"CopyVault"] &&
        ![name containsString:@"Table"] && ![name containsString:@"Cell"] && ![name containsString:@"Scroll"];
}
// The named card, best (most visible) first. `existsOut` separates "the plugin is
// not in the hierarchy / was renamed" from "the card is parked off screen because
// the panel is closed" - the two need opposite answers (fall back vs stand down).
static UIView *LMVCVPanelVaultView(UIWindow *window,BOOL *existsOut) {
    CGRect bounds=window.bounds;
    if(existsOut)*existsOut=NO;
    if(CGRectIsEmpty(bounds))return nil;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)window];
    NSUInteger budget=400;
    UIView *best=nil;CGFloat bestArea=0;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            [pending addObject:child];
            if(child.tag==LMVCVPanelHostTag)continue;
            if(!LMVCVPanelVaultClass(child))continue;
            if(existsOut)*existsOut=YES;
            if(child.hidden || child.alpha<.01)continue;
            CGRect frame=[child convertRect:child.bounds toView:window];
            CGFloat visible=LMVCVPanelVisibleArea(frame,bounds);
            if(visible>bestArea){bestArea=visible;best=child;}
        }
    }
    return best;
}
// The card: the largest visible descendant that does NOT fill the window. That
// rule skips the full-screen containers above it (CVPanelView, the UIControl) and
// our own host is excluded by its tag, so what remains is the panel surface.
// 1.49: only consulted when the plugin names nothing at all - see
// LMVCVPanelVaultView above for why size alone cannot pick the card any more.
static UIView *LMVCVPanelCard(UIWindow *window) {
    CGRect bounds=window.bounds;
    if(CGRectIsEmpty(bounds))return nil;
    BOOL named=NO;
    UIView *vault=LMVCVPanelVaultView(window,&named);
    if(named)return vault;   // nil = parked off screen, i.e. the panel is closed
    NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)window];
    NSUInteger budget=300;
    UIView *best=nil;CGFloat bestArea=0;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            [pending addObject:child];
            if(child.tag==LMVCVPanelHostTag || child.hidden || child.alpha<.01)continue;
            CGRect frame=[child convertRect:child.bounds toView:window];
            if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;
            if(frame.size.width<bounds.size.width*.5 || frame.size.height<bounds.size.height*.08)continue;
            CGFloat visible=LMVCVPanelVisibleArea(frame,bounds);
            if(visible<=0)continue;   // parked off screen - never a candidate
            if(visible>bestArea){bestArea=visible;best=child;}
        }
    }
    return best;
}
// The panel's blur material - the effect view that gives the card its background.
// The video has to sit ABOVE it (otherwise the material hides the video, the 1.25
// Squid report) and BELOW the content container that is its sibling.
// 1.49: `clip` is the card, and the material has to actually BELONG to it (>=90%
// of it inside the card). Without that clamp the window-wide fallback could take a
// full-screen backdrop that merely overlaps the clipboard and stretch the video
// over the whole screen - the "video runs up over the panel" report.
static UIView *LMVCVPanelMaterial(UIView *root,UIWindow *window,CGRect clip) {
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
            CGFloat visible=LMVCVPanelVisibleArea(frame,bounds);
            if(visible<=0)continue;
            if(LMVCVPanelCoverage(frame,clip)<.9)continue;
            if(visible>bestArea){bestArea=visible;best=child;}
        }
    }
    return best;
}
@interface LMVCopyVaultPanelVideoHost:UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@end
@implementation LMVCopyVaultPanelVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.tag=LMVCVPanelHostTag;
        self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;self.accessibilityElementsHidden=YES;
        self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.clipsToBounds=YES;
    }
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
@end
@interface LMVCopyVaultPanelVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVCopyVaultPanelVideoHost *host;
@property(nonatomic,weak) UIView *card;
@property(nonatomic,copy) NSString *mode;
@property(nonatomic) BOOL updating;
- (void)detach;
- (void)update;
@end
static LMVCopyVaultPanelVideoManager *LMVCopyVaultPanelVideo;
@implementation LMVCopyVaultPanelVideoManager
- (instancetype)init {
    if(!LMVCVPanelEnvironment())return nil;
    if((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=NO;
        _host=[[LMVCopyVaultPanelVideoHost alloc] initWithFrame:CGRectZero];_host.playback=_playback;
        _playback.renderLayer.name=@"com.minis.lockmessagevideo.cv-panel.render";
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
// exception escaping a run-loop callback ABORTS SpringBoard (the 1.23 crash).
// Only the effect view's contentView is ever used as a container.
- (BOOL)insertHostInto:(UIView *)container at:(NSUInteger)index {
    if(!container || [container isKindOfClass:UIVisualEffectView.class])return NO;
    [self.host removeFromSuperview];
    @try {[container insertSubview:self.host atIndex:index];}
    @catch(NSException *exception) {[self.host removeFromSuperview];return NO;}
    return self.host.superview==container;
}
- (void)update {
    if(self.updating)return;self.updating=YES;
    UIWindow *window=LMVCVPanelWindow();
    UIView *card=window?LMVCVPanelCard(window):nil;
    if(!card) {[self detach];self.updating=NO;return;}
    // 1.49: a card parked off screen (the closed panel, y=1454) is not a target,
    // whichever way it was found.
    CGRect cardFrame=[card convertRect:card.bounds toView:window];
    if(LMVCVPanelVisibleArea(cardFrame,window.bounds)<=0) {[self detach];self.updating=NO;return;}
    if(self.card!=card) {[self.host removeFromSuperview];self.card=card;}
    BOOL changed=![self.playback.path isEqualToString:LMVCVPanelPath] ||
        ![self.playback.revision isEqualToString:LMVCVPanelRevision];
    if(changed) {[self.host removeFromSuperview];[self.playback selectPath:LMVCVPanelPath revision:LMVCVPanelRevision];}
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    // A still poster is not a panel background: wait for the decoder and leave the
    // panel alone until then.
    self.playback.posterLayer.hidden=YES;
    BOOL live=self.playback.player && self.playback.playerLayer.readyForDisplay && !self.playback.error;
    if(!live) {[self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;return;}
    // WHERE in the panel the video belongs: ABOVE the material, BELOW the content.
    // Into the material's contentView when it has room (that is above the blur and,
    // because the content container is the material's SIBLING, still below the
    // content); otherwise directly above the material in the same superview.
    UIView *material=LMVCVPanelMaterial(card,window,cardFrame);
    if(!material)material=LMVCVPanelMaterial(window,window,cardFrame);
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
    // 1.43: the CARD is r0 here - the rounding lives on the material and on the
    // content container (both r55). Take the radius from the surface the video sits
    // in, otherwise the panel would show square corners over a rounded card.
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
        NSString *status=[NSString stringWithFormat:@"cv-panel win=%@ %.0fx%.0f mode=%@ why=%@ card=%@@%.0f,%.0f,%.0f,%.0f r%.0f vis=%.0f live=%d host=%.0fx%.0f",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            self.mode?:@"none",
            LMVCVPanelVaultClass(self.card)?@"vault":@"generic",
            NSStringFromClass(self.card.class),cardFrame.origin.x,cardFrame.origin.y,cardFrame.size.width,cardFrame.size.height,
            radius,LMVCVPanelVisibleArea(cardFrame,bounds),(int)live,self.host.bounds.size.width,self.host.bounds.size.height];
        static NSString *lastStatus=nil;
        if(![status isEqualToString:lastStatus]) {lastStatus=[status copy];LMVDiagnostic(status);}
    }
    self.updating=NO;
}
@end
static void LMVCVPanelRetune(void) {
    NSTimeInterval want=LMVCVPanelEnabled?.1:.5;
    if(LMVCVPanelTimer && fabs(LMVCVPanelTimer.timeInterval-want)<.001)return;
    [LMVCVPanelTimer invalidate];
    LMVCVPanelTimer=[NSTimer timerWithTimeInterval:want repeats:YES block:^(NSTimer *timer){LMVCopyVaultPanelVideoRefresh(NO);}];
    [NSRunLoop.mainRunLoop addTimer:LMVCVPanelTimer forMode:NSRunLoopCommonModes];
}
static void LMVCopyVaultPanelVideoRefresh(BOOL reload) {
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady)return;
    if(reload || !LMVCVPanelPrefsKnown) {
        LMVCVPanelPrefsKnown=YES;
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("CVBackgroundEnabled"),kLMVPrefsID);
        // 0.0.114: master switch, inline (see LMVLockVideo.h).
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        LMVCVPanelEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&
            [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        LMVCVPanelPath=LMVCCSelectedPath(@"CVVideo");
        LMVCVPanelRevision=LMVLockVideoRevision(LMVCVPanelPath);
    }
    LMVCVPanelRetune();
    if(!LMVCVPanelEnabled || !LMVCVPanelPath.length || !LMVCVPanelRevision.length) {
        [LMVCopyVaultPanelVideo detach];
        if(LMVCopyVaultPanelVideo.playback.path)[LMVCopyVaultPanelVideo.playback clear];
        return;
    }
    if(!LMVCVPanelEnvironment() || !LMVCVPanelWindow()) {[LMVCopyVaultPanelVideo detach];return;}
    // Hook install/preferences/launch alone never construct UI or a player.
    if(!LMVCopyVaultPanelVideo)LMVCopyVaultPanelVideo=[LMVCopyVaultPanelVideoManager new];
    // A timer callback is a run-loop callback: an uncaught exception here aborts
    // SpringBoard. Every failure inside this channel stands the channel down
    // instead, and the next tick tries again.
    @try {[LMVCopyVaultPanelVideo update];}
    @catch(NSException *exception) {[LMVCopyVaultPanelVideo detach];}
}
static void LMVCopyVaultPanelVideoSuspend(void) {
    if(!NSThread.isMainThread)return;
    [LMVCopyVaultPanelVideo detach];
}
static void LMVCopyVaultPanelVideoInstallHooks(void) {
    if(LMVCVPanelTimer || !LMVCVPanelSpringBoard())return;
    LMVCVPanelRetune();
}
