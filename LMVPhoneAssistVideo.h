#pragma once
// 2.04: the PHONE-ASSIST pop-up background (电话助手弹窗背景视频).
//
// This is the sheet the phone-assistant tweak presents over the home screen. It is
// built on UIAlertController internals - the device log names it
// _UIAlertControllerPhoneTVMacView@80,175,270,607 - so 2.03's "never touch an alert"
// rule had to be undone for it. That rule stays for the AppTools channel (a real
// system alert is not the AT panel), but this channel exists precisely to give the
// phone-assistant sheet a background of its own: its own material, its own sound
// switch and volume, and its own text colour.
//
// The mount is the one 1.28 settled for AppTools: video UNDER the content but ABOVE
// the blur material, sized to the card. It is poll-based and hooks nothing of the
// plug-in, so when the switch is off nothing is constructed at all.
//
// Requires the shared helpers imported earlier in the translation unit
// (LMVLockVideoPlayback, LMVCCSelectedPath, LMVLockVideoRevision, LMVInitialized,
// LMVLaunchReady, LMVBlankToken, LMVLockToken, LMVDiagnosticsEnabled,
// LMVDiagnostic, kLMVPrefsID).

static void LMVPhoneAssistVideoRefresh(BOOL reload);
static void LMVPhoneAssistVideoSuspend(void);
static BOOL LMVPhoneAssistEnabled,LMVPhoneAssistPrefsKnown;
static NSString *LMVPhoneAssistPath,*LMVPhoneAssistRevision;
static NSTimer *LMVPhoneAssistTimer;

static BOOL LMVPhoneAssistSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}
static BOOL LMVPhoneAssistEnvironment(void) {
    uint64_t blank=1,locked=1;
    return LMVInitialized && LMVLaunchReady && NSThread.isMainThread && LMVPhoneAssistSpringBoard() &&
        LMVBlankToken>=0 && LMVLockToken>=0 &&
        notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK &&
        notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK && !blank && !locked;
}
// 2.15: WHO IS COVERING US. The device log has to answer "mounted, playing, yet
// invisible" without another round trip, so the card's ancestors and every sibling
// drawn ABOVE our host are printed with hidden/alpha/opaque/background alpha.
static NSString *LMVPhoneAssistStackDescription(UIView *card,UIView *host) {
    NSMutableString *out=[NSMutableString stringWithFormat:@"pa-stack card=%@",NSStringFromClass(card.class)];
    NSInteger depth=0;
    for(UIView *node=card.superview;node && depth++<7;node=node.superview)
        [out appendFormat:@" < %@",NSStringFromClass(node.class)];
    UIView *container=host.superview;
    if(container) {
        NSInteger index=(NSInteger)[container.subviews indexOfObjectIdenticalTo:host];
        [out appendFormat:@" container=%@ idx=%ld above=",NSStringFromClass(container.class),(long)index];
        if(index>=0) {
            NSUInteger shown=0;
            for(NSUInteger i=(NSUInteger)index+1;i<container.subviews.count && shown<6;i++,shown++) {
                UIView *sibling=container.subviews[i];
                CGFloat background=sibling.backgroundColor?CGColorGetAlpha(sibling.backgroundColor.CGColor):0;
                [out appendFormat:@"[%@ h%d a%.2f op%d bg%.2f] ",NSStringFromClass(sibling.class),
                    (int)sibling.hidden,sibling.alpha,(int)sibling.opaque,background];
            }
        }
    }
    return out;
}
static NSInteger const LMVPhoneAssistHostTag=0x5A19;
static CGFloat LMVPhoneAssistVisibleArea(CGRect frame,CGRect bounds) {
    if(CGRectIsEmpty(frame) || CGRectIsEmpty(bounds))return 0;
    CGRect onScreen=CGRectIntersection(frame,bounds);
    if(CGRectIsEmpty(onScreen))return 0;
    CGFloat total=frame.size.width*frame.size.height;
    if(total<=0)return 0;
    CGFloat visible=onScreen.size.width*onScreen.size.height;
    return visible/total>=.5?visible:0;
}
// 2.04: the sheet, by CLASS. _UIAlertControllerPhoneTVMacView is the phone-assist
// presentation; the plain _UIAlertController container around it is full-screen and
// therefore never a card. Both names are checked so a system rename of either layer
// does not silently take the channel down.
static BOOL LMVPhoneAssistSheetKind(UIView *view) {
    NSString *name=NSStringFromClass(view.class);
    if([name containsString:@"PhoneTVMac"])return YES;
    if([name containsString:@"PhoneContinuity"])return YES;
    if([name containsString:@"CallAssist"])return YES;
    return NO;
}
static UIView *LMVPhoneAssistCard(UIWindow *window) {
    if(!window)return nil;
    CGRect bounds=window.bounds;
    if(CGRectIsEmpty(bounds))return nil;
    UIView *best=nil;CGFloat bestArea=0;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)window];
    NSUInteger budget=600;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            if(child.tag==LMVPhoneAssistHostTag || child.hidden || child.alpha<.01)continue;
            [pending addObject:child];
            if(!LMVPhoneAssistSheetKind(child))continue;
            CGRect frame=[child convertRect:child.bounds toView:window];
            // The alert container fills the window; the sheet itself does not.
            if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;
            if(frame.size.width<bounds.size.width*.3 || frame.size.height<bounds.size.height*.05)continue;
            CGFloat visible=LMVPhoneAssistVisibleArea(frame,bounds);
            if(visible>bestArea){bestArea=visible;best=child;}
        }
    }
    return best;
}
// 2.15: DO NOT ASSUME THE SHEET LIVES IN SBHomeScreenWindow. A third-party tweak
// that "covers" this pop-up often re-hosts it into a window of its own (or moves
// the alert container); the old home-only scan then saw nothing and the channel
// went silent. The card is identified by CLASS anywhere on screen: the window we
// found it in last time is tried first so the common case stays one scan, and the
// home window keeps priority so nothing changes when the sheet is where it was.
static __weak UIWindow *LMVPhoneAssistLastWindow;
static UIView *LMVPhoneAssistFindCard(UIWindow **windowOut) {
    if(windowOut)*windowOut=nil;
    if(LMVPhoneAssistLastWindow && !LMVPhoneAssistLastWindow.hidden &&
       LMVPhoneAssistLastWindow.alpha>=.01) {
        UIView *card=LMVPhoneAssistCard(LMVPhoneAssistLastWindow);
        if(card) {if(windowOut)*windowOut=LMVPhoneAssistLastWindow;return card;}
    }
    UIWindow *home=nil;UIView *best=nil;UIWindow *bestWindow=nil;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(window.hidden || window.alpha<.01)continue;
            UIView *card=LMVPhoneAssistCard(window);
            if(!card)continue;
            if([NSStringFromClass(window.class) containsString:@"SBHomeScreen"])
                {home=window;best=card;bestWindow=window;break;}
            if(!best) {best=card;bestWindow=window;}
        }
        if(home)break;
    }
    if(best) {
        LMVPhoneAssistLastWindow=bestWindow;
        if(windowOut)*windowOut=bestWindow;
    }
    return best;
}
static UIView *LMVPhoneAssistMaterial(UIView *root,UIWindow *window) {
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
            if(area/cardArea<.85)continue;
            if(area>bestArea){bestArea=area;best=child;}
        }
    }
    return best;
}
// Text colour. Same contract as the CopyVault channel: remember the first colour
// seen for each label and hand it back when the sheet goes away or the switch is
// turned off, so nothing is left tinted.
static NSMapTable<UIView *,id> *LMVPhoneAssistTextOriginal;
static UIColor *LMVPhoneAssistTextColor(void) {
    NSNumber *value=(__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("PATextColor"),kLMVPrefsID);
    if(![value isKindOfClass:NSNumber.class])return nil;
    uint32_t word=value.unsignedIntValue;
    return [UIColor colorWithRed:((word>>24)&0xFF)/255.0 green:((word>>16)&0xFF)/255.0
                           blue:((word>>8)&0xFF)/255.0 alpha:(word&0xFF)/255.0];
}
static BOOL LMVPhoneAssistColorEqual(UIColor *a,UIColor *b) {
    if(!a || !b)return a==b;
    CGFloat ar=0,ag=0,ab=0,aa=0,br=0,bg=0,bb=0,ba=0;
    if(![a getRed:&ar green:&ag blue:&ab alpha:&aa] || ![b getRed:&br green:&bg blue:&bb alpha:&ba])return [a isEqual:b];
    return fabs(ar-br)<.002 && fabs(ag-bg)<.002 && fabs(ab-bb)<.002 && fabs(aa-ba)<.002;
}
static void LMVPhoneAssistApplyTextColor(UIView *root) {
    UIColor *color=LMVPhoneAssistTextColor();
    if(!root || !color)return;
    if(!LMVPhoneAssistTextOriginal)LMVPhoneAssistTextOriginal=[NSMapTable weakToStrongObjectsMapTable];
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];
    NSUInteger budget=300;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            if(child.tag==LMVPhoneAssistHostTag)continue;
            [pending addObject:child];
            if(![child isKindOfClass:UILabel.class])continue;
            UILabel *label=(UILabel *)child;
            if(label.attributedText.length) {
                UIColor *now=[label.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
                if(LMVPhoneAssistColorEqual(now,color))continue;
                if(![LMVPhoneAssistTextOriginal objectForKey:label])[LMVPhoneAssistTextOriginal setObject:label.attributedText forKey:label];
                NSMutableAttributedString *text=[label.attributedText mutableCopy];
                [text addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0,text.length)];
                label.attributedText=text;
            } else if(label.text.length) {
                if(LMVPhoneAssistColorEqual(label.textColor,color))continue;
                if(![LMVPhoneAssistTextOriginal objectForKey:label])
                    [LMVPhoneAssistTextOriginal setObject:(label.textColor?:UIColor.labelColor) forKey:label];
                label.textColor=color;
            }
        }
    }
}
static void LMVPhoneAssistRestoreTextColor(void) {
    if(!LMVPhoneAssistTextOriginal)return;
    for(UIView *view in LMVPhoneAssistTextOriginal.keyEnumerator) {
        if(![view isKindOfClass:UILabel.class])continue;
        id original=[LMVPhoneAssistTextOriginal objectForKey:view];
        UILabel *label=(UILabel *)view;
        if([original isKindOfClass:NSAttributedString.class])label.attributedText=original;
        else if([original isKindOfClass:UIColor.class])label.textColor=original;
    }
    [LMVPhoneAssistTextOriginal removeAllObjects];
}
@interface LMVPhoneAssistVideoHost:UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@end
@implementation LMVPhoneAssistVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;
        self.opaque=NO;
        self.userInteractionEnabled=NO;
        self.tag=LMVPhoneAssistHostTag;
    }
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
@end
@interface LMVPhoneAssistVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVPhoneAssistVideoHost *host;
@property(nonatomic,weak) UIView *card;
@property(nonatomic,copy) NSString *mode;
@property(nonatomic) BOOL updating;
- (void)detach;
- (void)update;
@end
static LMVPhoneAssistVideoManager *LMVPhoneAssistVideo;
@implementation LMVPhoneAssistVideoManager
- (instancetype)init {
    if(!LMVPhoneAssistEnvironment())return nil;
    if((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=NO;
        _host=[[LMVPhoneAssistVideoHost alloc] initWithFrame:CGRectZero];_host.playback=_playback;
        _playback.renderLayer.name=@"com.minis.lockmessagevideo.phoneassist.render";
        [_host.layer addSublayer:_playback.renderLayer];
    }
    return self;
}
- (void)dealloc {[_host removeFromSuperview];}
- (void)detach {
    if(self.host.superview)[self.host removeFromSuperview];
    self.host.hidden=YES;
    if(self.playback.wantsPlayback)[self.playback setVisible:NO];
    LMVPhoneAssistRestoreTextColor();
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
    UIWindow *window=nil;
    UIView *card=LMVPhoneAssistFindCard(&window);
    if(!card) {
        // 2.15: silence was the old answer here. When a covering tweak moves the
        // sheet somewhere we cannot see, the log must at least name the windows
        // that WERE on screen, so the next capture explains itself.
        if(LMVDiagnosticsEnabled.load()) {
            NSMutableString *visible=[NSMutableString new];NSUInteger shown=0;
            for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
                if(![scene isKindOfClass:UIWindowScene.class])continue;
                for(UIWindow *candidate in ((UIWindowScene *)scene).windows) {
                    if(candidate.hidden || candidate.alpha<.01)continue;
                    if(shown++>=8)break;
                    [visible appendFormat:@"%@@%.0fx%.0f ",NSStringFromClass(candidate.class),
                        candidate.bounds.size.width,candidate.bounds.size.height];
                }
            }
            NSString *line=[NSString stringWithFormat:@"pa-nocard windows=%lu %@",(unsigned long)shown,visible];
            static NSString *lastLine=nil;
            if(![line isEqualToString:lastLine]) {lastLine=[line copy];LMVDiagnostic(line);}
        }
        [self detach];self.updating=NO;return;
    }
    if(self.card!=card) {[self.host removeFromSuperview];self.card=card;}
    LMVPhoneAssistApplyTextColor(card);
    BOOL changed=![self.playback.path isEqualToString:LMVPhoneAssistPath] ||
        ![self.playback.revision isEqualToString:LMVPhoneAssistRevision];
    if(changed) {[self.host removeFromSuperview];[self.playback selectPath:LMVPhoneAssistPath revision:LMVPhoneAssistRevision];}
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    BOOL live=self.playback.player && !self.playback.error &&
        (self.playback.posterLayer.contents!=nil || self.playback.playerLayer.readyForDisplay);
    if(!live) {[self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;return;}
    UIView *material=LMVPhoneAssistMaterial(card,window);
    UIView *container=nil;NSUInteger index=0;CGRect target=CGRectZero;NSString *mode=@"card";
    // Fix: place the video ABOVE the material, not inside its contentView.
    // The device log named the failure exactly: pa-panel mode=content live=1
    // host=270x607 ready=1 poster=1 rate=1.0 - mounted, decoded and playing, yet
    // invisible. This sheet's material is _UIDimmingKnockoutBackdropView (a
    // UIVisualEffectView subclass); on this system its own effect layers paint
    // over the content view, so a subview placed at contentView index 0 is
    // covered. It is the same failure 1.93 hit on the Squid panel, whose fix was
    // to sit above the effect view and below the content. The alert group is
    // [_UIDimmingKnockoutBackdropView, content UIView], so index material+1 lands
    // between the dimming layer and the labels.
    if([material isKindOfClass:UIVisualEffectView.class] && material.superview) {
        container=material.superview;
        NSInteger near=(NSInteger)[container.subviews indexOfObjectIdenticalTo:material];
        if(near==NSNotFound) {[self detach];self.updating=NO;return;}
        index=(NSUInteger)(near+1);target=material.frame;mode=@"above-material";
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
    [self.playback layoutInBounds:self.host.bounds];
    [CATransaction commit];
    if(self.host.hidden)self.host.hidden=NO;
    if(LMVDiagnosticsEnabled.load()) {
        CGRect bounds=window.bounds,frame=[self.card convertRect:self.card.bounds toView:window];
        NSString *status=[NSString stringWithFormat:@"pa-panel win=%@ %.0fx%.0f mode=%@ card=%@@%.0f,%.0f,%.0f,%.0f r%.0f vis=%.0f live=%d host=%.0fx%.0f ready=%d poster=%d rate=%.1f text=%@",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            self.mode?:@"none",
            NSStringFromClass(self.card.class),frame.origin.x,frame.origin.y,frame.size.width,frame.size.height,
            self.card.layer.cornerRadius,
            LMVPhoneAssistVisibleArea(frame,bounds),(int)live,
            self.host.bounds.size.width,self.host.bounds.size.height,
            (int)self.playback.playerLayer.readyForDisplay,
            (int)(self.playback.posterLayer.contents!=nil),
            self.playback.player?self.playback.player.rate:0.0,
            LMVPhoneAssistTextColor()?@"on":@"off"];
        static NSString *lastStatus=nil;
        if(![status isEqualToString:lastStatus]) {lastStatus=[status copy];LMVDiagnostic(status);}
        NSString *stack=LMVPhoneAssistStackDescription(self.card,self.host);
        static NSString *lastStack=nil;
        if(![stack isEqualToString:lastStack]) {lastStack=[stack copy];LMVDiagnostic(stack);}
    }
    self.updating=NO;
}
@end
static void LMVPhoneAssistRetune(void) {
    NSTimeInterval want=LMVPhoneAssistEnabled?.1:.5;
    if(LMVPhoneAssistTimer && fabs(LMVPhoneAssistTimer.timeInterval-want)<.001)return;
    [LMVPhoneAssistTimer invalidate];
    LMVPhoneAssistTimer=[NSTimer timerWithTimeInterval:want repeats:YES block:^(NSTimer *timer){LMVPhoneAssistVideoRefresh(NO);}];
    [NSRunLoop.mainRunLoop addTimer:LMVPhoneAssistTimer forMode:NSRunLoopCommonModes];
}
static void LMVPhoneAssistVideoRefresh(BOOL reload) {
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady)return;
    if(reload || !LMVPhoneAssistPrefsKnown) {
        LMVPhoneAssistPrefsKnown=YES;
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("PABackgroundEnabled"),kLMVPrefsID);
        // 0.0.114: master switch, inline (see LMVLockVideo.h).
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        LMVPhoneAssistEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&
            [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        LMVPhoneAssistPath=LMVCCSelectedPath(@"PAVideo");
        LMVPhoneAssistRevision=LMVLockVideoRevision(LMVPhoneAssistPath);
    }
    LMVPhoneAssistRetune();
    if(!LMVPhoneAssistEnabled || !LMVPhoneAssistPath.length || !LMVPhoneAssistRevision.length) {
        [LMVPhoneAssistVideo detach];
        if(LMVPhoneAssistVideo.playback.path)[LMVPhoneAssistVideo.playback clear];
        return;
    }
    if(!LMVPhoneAssistEnvironment()) {[LMVPhoneAssistVideo detach];return;}
    if(!LMVPhoneAssistVideo)LMVPhoneAssistVideo=[LMVPhoneAssistVideoManager new];
    // A timer callback is a run-loop callback: an uncaught exception here aborts
    // SpringBoard. Every failure inside this channel stands the channel down.
    @try {[LMVPhoneAssistVideo update];}
    @catch(NSException *exception) {[LMVPhoneAssistVideo detach];}
}
static void LMVPhoneAssistVideoSuspend(void) {
    if(!NSThread.isMainThread)return;
    [LMVPhoneAssistVideo detach];
}
static void LMVPhoneAssistVideoInstallHooks(void) {
    if(LMVPhoneAssistTimer || !LMVPhoneAssistSpringBoard())return;
    LMVPhoneAssistRetune();
}
