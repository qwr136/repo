#pragma once
#if __has_include("LMVProbeWindows.h")
#import "LMVProbeWindows.h"
#else
// Standalone fixture: compile this header alone, no shared probe available.
static inline NSString *LMVProbeClassName(UIView *view) {
    return view ? (NSStringFromClass(view.class) ?: @"") : @"";
}
static inline NSTimeInterval LMVTuneFallbackInterval(NSTimeInterval want, BOOL mounted) {
    (void)mounted; return want;
}
#endif
#import <dlfcn.h>
// 2.30: the Control Center context-menu background (CCBorder 视频背景).
//
// The 2.29 capture showed the phone-assist channel mounting a video on a Control
// Center long-press menu by mistake:
//
//   SBControlCenterWindow@0,0,430,932
//     _UIContextMenuContainerView
//       _UIContextMenuPlatterTransitionView
//         _UIContextMenuView
//           _UIContextMenuListView
//             UIVisualEffectView
//               _UIDimmingKnockoutBackdropView
//               _UIVisualEffectContentView@164,59,250,352   <- THE CARD
//
// That menu is a real surface of its own, so it now gets its own channel instead
// of riding on PA. Detection is window-first (SBControlCenterWindow only), then the
// menu container by class, then the largest visible non-full-screen card inside it.
// The module that owns the menu is logged (`ccb-panel ... module=`) through the
// same KVC probe PA uses, so the identifier can be read from a capture.
//
// Mount: inside the card at index 0 - above its background, below every label.
// Mounting above the UIVisualEffectView would paint over the text.
//
// 2.31: THE PICK LANDED ON A SHADOW. The 2.30 device log shows the pick was
// _UICutoutShadowView@14,-91,550x652 - a _UIRoundedRectShadowView subclass, the rim
// shadow drawn BELOW the platter. The video mounted into it at index 0, decoded and
// played (rate=1.0, host=550x652) and was invisible: the platter above painted over
// it, so the user heard sound only. Shadow/cutout layers never count as a card now;
// the content card (a direct non-glass child of the UIVisualEffectView) is its own
// tier, and only when no such card exists does the pick fall back to the largest
// remaining visible view. The mount keeps content index 0 for the captured shape
// and gains the same above-material fallback the other panel channels use, plus
// ccb-stack / ccb-nocard / ccb-notready diagnostics so a covered mount is
// distinguishable from a missing target or a not-ready decoder in one capture.
//
// Requires the shared helpers imported earlier in the translation unit
// (LMVLockVideoPlayback, LMVCCSelectedPath, LMVLockVideoRevision, LMVInitialized,
// LMVLaunchReady, LMVBlankToken, LMVLockToken, LMVDiagnosticsEnabled,
// LMVDiagnostic, kLMVPrefsID, LMVPhoneAssistModuleIdentifier).

static void LMVCCBorderVideoRefresh(BOOL reload);
static void LMVCCBorderVideoSuspend(void);
static BOOL LMVCCBorderEnabled,LMVCCBorderPrefsKnown;
static NSString *LMVCCBorderPath,*LMVCCBorderRevision;
static NSTimer *LMVCCBorderTimer;

static BOOL LMVCCBorderSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}
static BOOL LMVCCBorderEnvironment(void) {
    uint64_t blank=1,locked=1;
    return LMVInitialized && LMVLaunchReady && NSThread.isMainThread && LMVCCBorderSpringBoard() &&
        LMVBlankToken>=0 && LMVLockToken>=0 &&
        notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK &&
        notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK && !blank && !locked;
}
static BOOL LMVCCBorderSpringBoardWindow(UIWindow *window) {
    if(!window)return NO;
    NSString *name=LMVProbeClassName(window);
    return [name rangeOfString:@"SBControlCenter" options:NSCaseInsensitiveSearch].location!=NSNotFound;
}
static BOOL LMVCCBorderMenuKind(UIView *view) {
    if(!view)return NO;
    NSString *name=LMVProbeClassName(view);
    return [name rangeOfString:@"UIContextMenu" options:NSCaseInsensitiveSearch].location!=NSNotFound;
}
static BOOL LMVCCBorderGlassKind(UIView *view) {
    if(!view)return NO;
    if([view isKindOfClass:UIVisualEffectView.class])return YES;
    NSString *name=LMVProbeClassName(view);
    if([name containsString:@"ContentView"])return NO;
    for(NSString *word in @[@"Blur",@"Glass",@"Vibrancy",@"Dimming",@"Backdrop",@"Effect"])
        if([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound)return YES;
    return NO;
}
// 2.31: A SHADOW IS NEVER THE CARD. _UICutoutShadowView (a _UIRoundedRectShadowView
// subclass) draws the platter rim BELOW the platter; a video mounted into it is
// covered by the platter itself - the 2.30 "sound only" capture. Shadow/cutout
// layers are never scored as cards (their children are still scanned).
static BOOL LMVCCBorderShadowKind(UIView *view) {
    if(!view)return NO;
    NSString *name=LMVProbeClassName(view);
    return [name containsString:@"Shadow"] || [name containsString:@"Cutout"];
}
static CGFloat LMVCCBorderVisibleArea(CGRect frame,CGRect bounds) {
    if(CGRectIsEmpty(frame) || CGRectIsEmpty(bounds))return 0;
    CGRect onScreen=CGRectIntersection(frame,bounds);
    if(CGRectIsEmpty(onScreen))return 0;
    CGFloat total=frame.size.width*frame.size.height;
    if(total<=0)return 0;
    CGFloat visible=onScreen.size.width*onScreen.size.height;
    return visible/total>=.5?visible:0;
}
static NSInteger const LMVCCBorderHostTag=0x5A39;
// 2.31: THE PICK USED TO BE "LARGEST VISIBLE" - and on the device the largest
// visible view inside the menu was the rim shadow below the platter (see the
// header). Two corrections, in order:
//   1. shadow/cutout layers are never scored as a card (their children still are);
//   2. the content card - a direct non-glass child of a UIVisualEffectView, the
//      _UIVisualEffectContentView of the captured shape - is its own tier, so a
//      bigger unrelated layer can never steal the pick from it. The old rule stays
//      as the fallback tier for trees that do not have one.
static UIView *LMVCCBorderCardIn(UIView *root,UIWindow *window) {
    if(!root || !window)return nil;
    CGRect bounds=window.bounds;
    // 2.62: LANDSCAPE. The card thresholds below used to be fractions of the
    // window's WIDTH/HEIGHT, so rotating turned a 430-wide window into 932 and the
    // 30% width floor went from 129 pt to 279 pt - the same 250 pt module menu that
    // passed in portrait was rejected in landscape and the channel mounted nothing
    // ("CCBorder 横屏没有视频"). Fractions of the SHORT SIDE are orientation-neutral:
    // 30% of 430 is 129 pt in both orientations and keeps rejecting full-screen
    // layers while every real menu card still clears it.
    CGFloat ref=MIN(bounds.size.width,bounds.size.height);
    UIView *bestContent=nil;CGFloat bestContentArea=0;
    UIView *bestFallback=nil;CGFloat bestFallbackArea=0;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];
    NSUInteger budget=500;
    while(pending.count && budget) {
        --budget;
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            if(child.tag==LMVCCBorderHostTag || child.hidden || child.alpha<.01)continue;
            [pending addObject:child];
            if(LMVCCBorderGlassKind(child) || LMVCCBorderShadowKind(child))continue;
            CGRect frame=[child convertRect:child.bounds toView:window];
            if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;
            if(frame.size.width<ref*.3 || frame.size.height<ref*.05)continue;
            CGFloat visible=LMVCCBorderVisibleArea(frame,bounds);
            if([child.superview isKindOfClass:UIVisualEffectView.class]) {
                if(visible>bestContentArea){bestContentArea=visible;bestContent=child;}
            } else if(visible>bestFallbackArea){bestFallbackArea=visible;bestFallback=child;}
        }
    }
    return bestContent ?: bestFallback;
}
// 2.31: THE MATERIAL UNDER THE CARD - the slot "above-material" needs when the pick
// is not itself a content view. The same search the phone-assist / AT / GS channels
// run in their own trees: the largest visible UIVisualEffectView that covers at
// least 85% of the card, restricted to the menu and rejected when its frame is far
// larger than the card - the outer platter and the full-screen CC blur must never
// qualify.
static UIView *LMVCCBorderMaterial(UIView *root,UIView *card,UIWindow *window) {
    if(!root || !card || !window)return nil;
    CGRect cardFrame=[card convertRect:card.bounds toView:window];
    CGFloat cardArea=cardFrame.size.width*cardFrame.size.height;
    if(CGRectIsEmpty(cardFrame) || cardArea<=0)return nil;
    UIView *best=nil;CGFloat bestArea=0;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];
    NSUInteger budget=300;
    while(pending.count && budget) {
        --budget;
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            [pending addObject:child];
            if(![child isKindOfClass:UIVisualEffectView.class] || child.hidden || child.alpha<.01)continue;
            CGRect frame=[child convertRect:child.bounds toView:window];
            if(frame.size.width*frame.size.height>cardArea*1.5)continue;
            CGRect cover=CGRectIntersection(frame,cardFrame);
            if(CGRectIsEmpty(cover))continue;
            CGFloat area=cover.size.width*cover.size.height;
            if(area/cardArea<.85)continue;
            if(area>bestArea){bestArea=area;best=child;}
        }
    }
    return best;
}
// 2.31: MOUNTED, PLAYING, YET INVISIBLE must be distinguishable from "no mount" in
// one capture - the contract the phone-assist stack line follows. Prints the card's
// ancestors and every sibling drawn ABOVE our host in its container, with
// hidden/alpha/opaque/background alpha.
static NSString *LMVCCBorderStackDescription(UIView *card,UIView *host) {
    NSMutableString *out=[NSMutableString stringWithFormat:@"ccb-stack card=%@",LMVProbeClassName(card)];
    NSInteger depth=0;
    for(UIView *node=card.superview;node && depth++<7;node=node.superview)
        [out appendFormat:@" < %@",LMVProbeClassName(node)];
    UIView *container=host.superview;
    if(container) {
        NSInteger index=(NSInteger)[container.subviews indexOfObjectIdenticalTo:host];
        [out appendFormat:@" container=%@ idx=%ld above=",LMVProbeClassName(container),(long)index];
        if(index>=0) {
            NSUInteger shown=0;
            for(NSUInteger i=(NSUInteger)index+1;i<container.subviews.count && shown<6;i++,shown++) {
                UIView *sibling=container.subviews[i];
                CGFloat background=sibling.backgroundColor?CGColorGetAlpha(sibling.backgroundColor.CGColor):0;
                [out appendFormat:@"[%@ h%d a%.2f op%d bg%.2f] ",LMVProbeClassName(sibling),
                    (int)sibling.hidden,sibling.alpha,(int)sibling.opaque,background];
            }
        }
    }
    return out;
}
static UIView *LMVCCBorderFindCard(UIWindow **windowOut,UIView **menuOut) {
    if(windowOut)*windowOut=nil;
    if(menuOut)*menuOut=nil;
    UIView *best=nil;UIWindow *bestWindow=nil;UIView *bestMenu=nil;
    // 2.55: shared snapshot (already filtered to visible windows).
    for(UIWindow *window in LMVProbeVisibleWindows()) {
        if(!LMVCCBorderSpringBoardWindow(window))continue;
        NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)window];
        NSUInteger budget=600;
        while(pending.count && budget) {
            --budget;
            UIView *node=pending.lastObject;[pending removeLastObject];
            for(UIView *child in node.subviews) {
                if(!budget--)break;
                if(child.tag==LMVCCBorderHostTag || child.hidden || child.alpha<.01)continue;
                [pending addObject:child];
                if(!LMVCCBorderMenuKind(child))continue;
                UIView *card=LMVCCBorderCardIn(child,window);
                if(card){best=card;bestWindow=window;bestMenu=child;break;}
            }
            if(best)break;
        }
        if(best)break;
    }
    if(best && windowOut)*windowOut=bestWindow;
    if(bestMenu && menuOut)*menuOut=bestMenu;
    return best;
}
@interface LMVCCBorderVideoHost:UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@end
@implementation LMVCCBorderVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;
        self.opaque=NO;
        self.userInteractionEnabled=NO;
        self.tag=LMVCCBorderHostTag;
    }
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
@end
@interface LMVCCBorderVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVCCBorderVideoHost *host;
@property(nonatomic,weak) UIView *card;
@property(nonatomic,copy) NSString *mode;
@property(nonatomic) BOOL updating;
// 2.42: per-channel show/hide delay timestamps.
@property(nonatomic) NSTimeInterval pendingShow,pendingHide;
- (void)detach;
- (void)update;
@end
static LMVCCBorderVideoManager *LMVCCBorderVideo;
@implementation LMVCCBorderVideoManager
- (instancetype)init {
    if(!LMVCCBorderEnvironment())return nil;
    if(([super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=NO;
        _host=[[LMVCCBorderVideoHost alloc] initWithFrame:CGRectZero];_host.playback=_playback;
        _playback.renderLayer.name=@"com.minis.lockmessagevideo.ccborder.render";
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
    NSUInteger slot=MIN(index,container.subviews.count);
    @try {[container insertSubview:self.host atIndex:slot];}
    @catch(NSException *exception) {[self.host removeFromSuperview];return NO;}
    return self.host.superview==container;
}
- (void)update {
    if(self.updating)return;self.updating=YES;
    // 2.60: PREWARM. Load the material and build the paused player while no panel
    // is on screen, so the panel's first appearance does not pay for the asset
    // load. The player stays paused (wantsPlayback is never raised here), so this
    // costs no steady CPU - it is one async load per material change.
    if(LMVCCBorderEnabled && LMVCCBorderPath.length && LMVCCBorderRevision.length &&
       (![self.playback.path isEqualToString:LMVCCBorderPath] || ![self.playback.revision isEqualToString:LMVCCBorderRevision]))
        [self.playback selectPath:LMVCCBorderPath revision:LMVCCBorderRevision];
    UIWindow *window=nil;UIView *menu=nil;
    UIView *card=LMVCCBorderFindCard(&window,&menu);
    NSTimeInterval tuneNow=NSProcessInfo.processInfo.systemUptime;
    if(card && !self.card) {
        NSTimeInterval show=LMVTuneDelay(@"CCBorder",@"ShowDelayMs");
        if(self.pendingShow<=0)self.pendingShow=tuneNow;
        if(show>0 && tuneNow-self.pendingShow<show) {self.updating=NO;return;}
        self.pendingShow=0;
    } else if(!card) {
        self.pendingShow=0;
    }
    if(!card) {
        NSTimeInterval hide=LMVTuneDelay(@"CCBorder",@"HideDelayMs");
        if(hide>0 && self.card && self.host.superview) {
            if(self.pendingHide<=0)self.pendingHide=tuneNow;
            if(tuneNow-self.pendingHide<hide) {self.updating=NO;return;}
        }
        self.pendingHide=0;
        [self detach];self.updating=NO;
        // 2.31: no silent return - name what was on screen instead, so "the menu
        // was open but nothing was found" is distinguishable from "no menu".
        if(LMVDiagnosticsEnabled.load()) {
            NSMutableString *visible=[NSMutableString new];NSUInteger shown=0;
            for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if(![scene isKindOfClass:UIWindowScene.class])continue;
                for(UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                    if(candidate.hidden || candidate.alpha<.01)continue;
                    if(shown++>=6)break;
                    [visible appendFormat:@"%@@%.0fx%.0f ",LMVProbeClassName(candidate),
                        candidate.bounds.size.width,candidate.bounds.size.height];
                }
            }
            NSString *line=[NSString stringWithFormat:@"ccb-nocard windows=%lu %@",(unsigned long)shown,visible];
            static NSString *lastNoCard=nil;
            if(![line isEqualToString:lastNoCard]) {lastNoCard=[line copy];LMVDiagnostic(line);}
        }
        return;
    }
    if(self.card!=card) {[self.host removeFromSuperview];self.card=card;}
    BOOL changed=![self.playback.path isEqualToString:LMVCCBorderPath] ||
        ![self.playback.revision isEqualToString:LMVCCBorderRevision];
    if(changed) {[self.host removeFromSuperview];[self.playback selectPath:LMVCCBorderPath revision:LMVCCBorderRevision];}
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    // 2.60: mount as soon as the (prewarmed) player exists. The render layer stays
    // hidden until the first frame is decoded (updatePresentation), so the panel is
    // covered the moment that frame arrives - no poster, no readyForDisplay wait.
    BOOL live=self.playback.player && !self.playback.error;
    if(!live) {
        [self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;
        // 2.31: the decoder/asset side of the contract (recognized but not ready) -
        // distinguishable from a covered mount and from no target.
        if(LMVDiagnosticsEnabled.load()) {
            NSString *line=[NSString stringWithFormat:@"ccb-notready player=%d error=%d ready=%d poster=%d",
                (int)(self.playback.player!=nil),(int)(self.playback.error!=nil),
                (int)self.playback.playerLayer.readyForDisplay,(int)(self.playback.posterLayer.contents!=nil)];
            static NSString *lastNotReady=nil;
            if(![line isEqualToString:lastNotReady]) {lastNotReady=[line copy];LMVDiagnostic(line);}
        }
        return;
    }
    // 2.31: THE CARD IS THE CONTENT VIEW, SO THE VIDEO GOES INSIDE IT: container=
    // card, index 0 sits above its background and below every label - the captured
    // shape. When the pick is NOT such a content view (structural fallback), the
    // channel uses the same "above the material, below the content" slot the other
    // panel channels settled on, then the card itself.
    UIView *material=LMVCCBorderMaterial(menu,card,window);
    UIView *container=nil;NSUInteger index=0;CGRect target=CGRectZero;NSString *mode=@"card";
    if([card.superview isKindOfClass:UIVisualEffectView.class]) {
        container=card;index=0;target=card.bounds;mode=@"content";
    } else if([material isKindOfClass:UIVisualEffectView.class] && material.superview &&
              ![material.superview isKindOfClass:UIVisualEffectView.class]) {
        container=material.superview;
        NSInteger near=(NSInteger)[container.subviews indexOfObjectIdenticalTo:material];
        if(near==NSNotFound) {[self detach];self.updating=NO;return;}
        NSUInteger slot=(NSUInteger)(near+1);
        // Land above any glass/effect layer slipped in after the material, still
        // below the content (the first non-glass sibling).
        for(NSUInteger i=slot;i<container.subviews.count;i++) {
            UIView *sibling=container.subviews[i];
            if(sibling.tag==LMVCCBorderHostTag)break;
            if(!LMVCCBorderGlassKind(sibling))break;
            slot=i+1;
        }
        index=slot;target=material.frame;mode=@"above-material";
    }
    if(!container) {container=card;index=0;target=card.bounds;}
    self.mode=mode;
    BOOL placed=self.host.superview==container &&
        (NSInteger)[container.subviews indexOfObjectIdenticalTo:self.host]==(NSInteger)index;
    if(!placed && ![self insertHostInto:container at:index]) {[self detach];self.updating=NO;return;}
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(!CGRectEqualToRect(self.host.frame,target))self.host.frame=target;
    UIViewAutoresizing mask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    if(self.host.autoresizingMask!=mask)self.host.autoresizingMask=mask;
    if(self.host.layer.cornerRadius!=card.layer.cornerRadius)self.host.layer.cornerRadius=card.layer.cornerRadius;
    self.host.layer.masksToBounds=YES;
    [self.playback layoutInBounds:self.host.bounds];
    [CATransaction commit];
    if(self.host.hidden)self.host.hidden=NO;
    if(LMVDiagnosticsEnabled.load()) {
        CGRect bounds=window.bounds,frame=[self.card convertRect:self.card.bounds toView:window];
        NSInteger cardIndex=self.card.superview?(NSInteger)[self.card.superview.subviews indexOfObjectIdenticalTo:self.card]:-1;
        NSString *status=[NSString stringWithFormat:@"ccb-panel win=%@ %.0fx%.0f mode=%@ module=%@ card=%@@%.0f,%.0f,%.0fx%.0f sup=%@ z=%ld r%.0f vis=%.0f live=%d host=%.0fx%.0f ready=%d poster=%d rate=%.1f size=%.0fx%.0f",
            LMVProbeClassName(window),bounds.size.width,bounds.size.height,
            self.mode?:@"none",
            LMVPhoneAssistModuleIdentifier(window,self.card),
            NSStringFromClass(self.card.class),frame.origin.x,frame.origin.y,frame.size.width,frame.size.height,
            self.card.superview?NSStringFromClass(self.card.superview.class):@"nil",(long)cardIndex,
            self.card.layer.cornerRadius,LMVCCBorderVisibleArea(frame,bounds),(int)live,
            self.host.bounds.size.width,self.host.bounds.size.height,
            (int)self.playback.playerLayer.readyForDisplay,
            (int)(self.playback.posterLayer.contents!=nil),
            self.playback.player?self.playback.player.rate:0.0,
            frame.size.width,frame.size.height];
        static NSString *lastStatus=nil;
        if(![status isEqualToString:lastStatus]) {lastStatus=[status copy];LMVDiagnostic(status);}
        NSString *stack=LMVCCBorderStackDescription(self.card,self.host);
        static NSString *lastStack=nil;
        if(![stack isEqualToString:lastStack]) {lastStack=[stack copy];LMVDiagnostic(stack);}
    }
    self.updating=NO;
}
@end
static void LMVCCBorderRetune(void) {
    NSTimeInterval want=LMVCCBorderEnabled?LMVTuneProbeInterval(@"CCBorder"):LMVTuneIdleInterval;
    want=LMVTuneFallbackInterval(want, LMVCCBorderVideo.host.superview!=nil);
    if(LMVCCBorderTimer && fabs(LMVCCBorderTimer.timeInterval-want)<.001)return;
    [LMVCCBorderTimer invalidate];
    LMVCCBorderTimer=[NSTimer timerWithTimeInterval:want repeats:YES block:^(NSTimer *timer){LMVCCBorderVideoRefresh(NO);}];
    [NSRunLoop.mainRunLoop addTimer:LMVCCBorderTimer forMode:NSRunLoopCommonModes];
}
static void LMVCCBorderVideoRefresh(BOOL reload) {
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady)return;
    if(reload || !LMVCCBorderPrefsKnown) {
        LMVCCBorderPrefsKnown=YES;
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("CCBorderBackgroundEnabled"),kLMVPrefsID);
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        LMVCCBorderEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&
            [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        LMVCCBorderPath=LMVCCSelectedPath(@"CCBorderVideo");
        LMVCCBorderRevision=LMVLockVideoRevision(LMVCCBorderPath);
    }
    LMVCCBorderRetune();
    if(!LMVCCBorderEnabled || !LMVCCBorderPath.length || !LMVCCBorderRevision.length) {
        [LMVCCBorderVideo detach];
        if(LMVCCBorderVideo.playback.path)[LMVCCBorderVideo.playback clear];
        return;
    }
    if(!LMVCCBorderEnvironment()) {[LMVCCBorderVideo detach];return;}
    if(!LMVCCBorderVideo)LMVCCBorderVideo=[LMVCCBorderVideoManager new];
    @try {[LMVCCBorderVideo update];}
    @catch(NSException *exception) {[LMVCCBorderVideo detach];}
}
static void LMVCCBorderVideoSuspend(void) {
    if(!NSThread.isMainThread)return;
    [LMVCCBorderVideo detach];
}
static void LMVCCBorderVideoInstallHooks(void) {
    if(LMVCCBorderTimer || !LMVCCBorderSpringBoard())return;
    LMVCCBorderRetune();
}
