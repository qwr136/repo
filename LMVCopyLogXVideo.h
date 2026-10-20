#pragma once
#import <dlfcn.h>
// 2.32: the CopyLogX clipboard panel (CopyLogX 视频背景).
//
// The 2.31 capture showed the phone-assist channel mounting a video on this panel
// by mistake - it is NOT the phone-assist sheet, and it gets its own channel now:
//
//   UIWindow@0,0,430,932                       <- plain UIWindow, no named subclass
//     UIView
//       UIView
//         UIVisualEffectView
//           _UIVisualEffectContentView@10,462,411,470 r0   <- THE CARD
//             UIControl
//             UITableView
//
// The panel is a bottom sheet: 411pt wide on a 430pt screen (10pt insets), 470pt
// tall, its bottom edge flush with the screen bottom. Those four facts - plain
// UIWindow, a `_UIVisualEffectContentView` card, bottom-anchored, wider than 80% of
// the screen - plus "the card actually contains a table" are the signature. Nothing
// of CopyLogX is hooked or guessed by class name, so a rename cannot take the
// channel down; the table requirement is what keeps the same geometry from also
// matching an unrelated bottom sheet.
//
// Mount: index 0 inside the card - above its background, below the table. That is
// the level the 2.31 capture proved visible (pa-panel ... card=_UIVisualEffectContentView
// idx=0 live=1).
//
// Requires the shared helpers imported earlier in the translation unit
// (LMVLockVideoPlayback, LMVCCSelectedPath, LMVLockVideoRevision, LMVInitialized,
// LMVLaunchReady, LMVBlankToken, LMVLockToken, LMVDiagnosticsEnabled,
// LMVDiagnostic, kLMVPrefsID).

static void LMVCopyLogXVideoRefresh(BOOL reload);
static void LMVCopyLogXVideoSuspend(void);
static BOOL LMVCopyLogXEnabled,LMVCopyLogXPrefsKnown;
static NSString *LMVCopyLogXPath,*LMVCopyLogXRevision;
static NSTimer *LMVCopyLogXTimer;

static BOOL LMVCopyLogXSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}
static BOOL LMVCopyLogXEnvironment(void) {
    uint64_t blank=1,locked=1;
    return LMVInitialized && LMVLaunchReady && NSThread.isMainThread && LMVCopyLogXSpringBoard() &&
        LMVBlankToken>=0 && LMVLockToken>=0 &&
        notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK &&
        notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK && !blank && !locked;
}
static NSInteger const LMVCopyLogXHostTag=0x5A49;
static CGFloat LMVCopyLogXVisibleArea(CGRect frame,CGRect bounds) {
    if(CGRectIsEmpty(frame) || CGRectIsEmpty(bounds))return 0;
    CGRect onScreen=CGRectIntersection(frame,bounds);
    if(CGRectIsEmpty(onScreen))return 0;
    CGFloat total=frame.size.width*frame.size.height;
    if(total<=0)return 0;
    CGFloat visible=onScreen.size.width*onScreen.size.height;
    return visible/total>=.5?visible:0;
}
// The window CopyLogX presents the sheet in. It is a PLAIN UIWindow - there is no
// named subclass to look for - so the window is only a candidate once the card
// signature below is found inside it. A window whose root controller is named after
// the tweak is accepted as well, for the case where it later gets its own subclass.
static BOOL LMVCopyLogXWindowKind(UIWindow *window) {
    if(!window)return NO;
    NSString *name=NSStringFromClass(window.class);
    if([name containsString:@"CopyLog"] || [name containsString:@"CLX"])return YES;
    // 2.33: the 2.31 capture showed the panel in a PLAIN `UIWindow` whose root
    // controller tells us nothing (`rvc=none`). Requiring a known root class was
    // one of the reasons the channel stayed silent, so the window is judged only
    // by what it is NOT: our own floating window and the system chrome. The card
    // signature below is what actually picks the sheet.
    if([name isEqualToString:@"LMVEasterWindow"])return NO;
    // 2.35: other channels' own panels can contain the very same effect-content
    // view (CopyVault's panel does), so their windows are never candidates.
    for(NSString *word in @[@"CVPanel",@"CopyVault",@"Myrtle",@"SGPanel",@"SquidPanel"])
        if([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound)return NO;
    for(NSString *word in @[@"SystemAperture",@"TouchVisualizer",@"TextEffects",@"Wallpaper",
                            @"RecordingIndicator",@"StatusBar",@"FloatingDock",@"Switcher",
                            @"SBControlCenter",@"SBMain",@"SBHomeScreen"])
        if([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound)return NO;
    return YES;
}
// 2.36: THE PROBE THAT TELLS US WHAT TO LOOK FOR. "clx-nocard" used to print only
// window class names, which is useless when the sheet lives inside a plain
// UIWindow: there is nothing to search for. This dumps every visible window with
// its root controller and two levels of subviews, so the line can be read next to
// FLEX and the real card class can be copied straight out of it. Capped at six
// children per level; printed only when the dump changes.
static NSString *LMVCopyLogXWindowDump(void) {
    NSMutableString *out=[NSMutableString string];
    NSInteger windows=0;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(window.hidden || window.alpha<.01)continue;
            if([NSStringFromClass(window.class) isEqualToString:@"LMVEasterWindow"])continue;
            windows++;
            NSString *root=NSStringFromClass(window.rootViewController.class);
            [out appendFormat:@" [%@ %.0fx%.0f cand=%d rvc=%@]",
                NSStringFromClass(window.class),window.bounds.size.width,window.bounds.size.height,
                (int)LMVCopyLogXWindowKind(window),root.length?root:@"none"];
            NSInteger topCount=0;
            for(UIView *top in window.subviews) {
                if(topCount++>=6){[out appendString:@" ..."];break;}
                [out appendFormat:@" %@@%.0f,%.0f %.0fx%.0f%s{",NSStringFromClass(top.class),
                    top.frame.origin.x,top.frame.origin.y,top.frame.size.width,top.frame.size.height,
                    top.hidden?"(h)":""];
                NSInteger childCount=0;
                for(UIView *child in top.subviews) {
                    if(childCount++>=6){[out appendString:@"..."];break;}
                    NSString *name=NSStringFromClass(child.class);
                    if(name.length>40)name=[name substringToIndex:40];
                    [out appendFormat:@"%@%s|",name,child.hidden?"(h)":""];
                }
                [out appendString:@"}"];
            }
        }
    }
    if(!windows)[out appendString:@" none"];
    return out;
}
// 2.35: the list is the IDENTITY, not a tie-breaker. CopyVault's panel carries a
// `_UIVisualEffectContentView` of exactly the right size and position, so shape
// alone cannot tell the two apart - but its table lives OUTSIDE that content view
// (a sibling of the material), while CopyLogX's table is INSIDE the card. Any
// scroll view counts, so a switch from UITableView to a collection view (or a
// future restyle) keeps working.
static BOOL LMVCopyLogXHasList(UIView *root) {
    if(!root)return NO;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];
    NSUInteger budget=300;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            if([child isKindOfClass:UIScrollView.class])return YES;
            [pending addObject:child];
        }
    }
    return NO;
}
// The card: a `_UIVisualEffectContentView` bottom-anchored to the window, wider than
// 80% of it, at least a quarter of the screen tall, with a table inside.
static BOOL LMVCopyLogXCardKind(UIWindow *window,UIView *view) {
    if(!window || !view)return NO;
    CGRect bounds=window.bounds;
    if(CGRectIsEmpty(bounds))return NO;
    NSString *name=NSStringFromClass(view.class);
    if([name rangeOfString:@"UIVisualEffectContentView" options:NSCaseInsensitiveSearch].location==NSNotFound)return NO;
    CGRect frame=[view convertRect:view.bounds toView:window];
    // 2.33: the 2.31 numbers were 411x470 on a 430x932 screen - 95% wide, 50% tall.
    // The old 80%/25%/16pt window was needlessly tight: a one-point inset or the
    // sheet's own entrance animation was enough to miss it entirely and leave the
    // channel with nothing to mount on.
    // 2.35: RATIOS, NOT THE 411x470 NUMBERS. Resizing the panel (taller, shorter,
    // wider) keeps working as long as it stays inside these bounds; the list below
    // is what actually proves it is CopyLogX and not some other bottom sheet.
    if(frame.size.width<bounds.size.width*.6)return NO;
    if(frame.size.height<bounds.size.height*.15 || frame.size.height>bounds.size.height*.9)return NO;
    // Bottom sheet: its bottom edge sits on (or near) the screen bottom. A closed
    // panel is parked off screen, so this also keeps that copy out.
    if(fabs(CGRectGetMaxY(frame)-bounds.size.height)>60)return NO;
    return LMVCopyLogXHasList(view);
}
// The card CopyLogX is showing right now, or nil. Public to the PA channel: that one
// asked the same window for "a Dimming/Backdrop shell" and mounted a phone-assist
// video here in 2.31, so it now skips exactly this card.
static UIView *LMVCopyLogXFindCard(UIWindow **windowOut) {
    if(windowOut)*windowOut=nil;
    UIView *best=nil;UIWindow *bestWindow=nil;CGFloat bestArea=0;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(window.hidden || window.alpha<.01)continue;
            if(!LMVCopyLogXWindowKind(window))continue;
            NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)window];
            NSUInteger budget=600;
            while(pending.count && budget) {
                UIView *node=pending.lastObject;[pending removeLastObject];
                for(UIView *child in node.subviews) {
                    if(!budget--)break;
                    if(child.tag==LMVCopyLogXHostTag || child.hidden || child.alpha<.01)continue;
                    [pending addObject:child];
                    if(!LMVCopyLogXCardKind(window,child))continue;
                    CGRect frame=[child convertRect:child.bounds toView:window];
                    CGFloat visible=LMVCopyLogXVisibleArea(frame,window.bounds);
                    // A tighter fit to the sheet edges wins when several match.
                    if(LMVCopyLogXHasList(child)) visible*=2;
                    if(visible>bestArea){bestArea=visible;best=child;bestWindow=window;}
                }
            }
        }
    }
    if(best && windowOut)*windowOut=bestWindow;
    return best;
}
// Text colour, same contract as the CopyVault channel: the first colour seen for
// each label is remembered and handed back when the panel goes away or the switch
// is turned off, so nothing stays tinted.
static NSMapTable<UIView *,id> *LMVCopyLogXTextOriginal;
static UIColor *LMVCopyLogXTextColor(void) {
    NSNumber *value=(__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("CopyLogXTextColor"),kLMVPrefsID);
    if(![value isKindOfClass:NSNumber.class])return nil;
    uint32_t word=value.unsignedIntValue;
    return [UIColor colorWithRed:((word>>24)&0xFF)/255.0 green:((word>>16)&0xFF)/255.0
                           blue:((word>>8)&0xFF)/255.0 alpha:(word&0xFF)/255.0];
}
static BOOL LMVCopyLogXColorEqual(UIColor *a,UIColor *b) {
    if(!a || !b)return a==b;
    CGFloat ar=0,ag=0,ab=0,aa=0,br=0,bg=0,bb=0,ba=0;
    if(![a getRed:&ar green:&ag blue:&ab alpha:&aa] || ![b getRed:&br green:&bg blue:&bb alpha:&ba])return [a isEqual:b];
    return fabs(ar-br)<.002 && fabs(ag-bg)<.002 && fabs(ab-bb)<.002 && fabs(aa-ba)<.002;
}
static void LMVCopyLogXApplyTextColor(UIView *root) {
    UIColor *color=LMVCopyLogXTextColor();
    if(!root || !color)return;
    if(!LMVCopyLogXTextOriginal)LMVCopyLogXTextOriginal=[NSMapTable weakToStrongObjectsMapTable];
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];
    NSUInteger budget=300;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            if(child.tag==LMVCopyLogXHostTag)continue;
            [pending addObject:child];
            if(![child isKindOfClass:UILabel.class])continue;
            UILabel *label=(UILabel *)child;
            if(label.attributedText.length) {
                UIColor *now=[label.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
                if(LMVCopyLogXColorEqual(now,color))continue;
                if(![LMVCopyLogXTextOriginal objectForKey:label])[LMVCopyLogXTextOriginal setObject:label.attributedText forKey:label];
                NSMutableAttributedString *text=[label.attributedText mutableCopy];
                [text addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0,text.length)];
                label.attributedText=text;
            } else if(label.text.length) {
                if(LMVCopyLogXColorEqual(label.textColor,color))continue;
                if(![LMVCopyLogXTextOriginal objectForKey:label])
                    [LMVCopyLogXTextOriginal setObject:(label.textColor?:UIColor.labelColor) forKey:label];
                label.textColor=color;
            }
        }
    }
}
static void LMVCopyLogXRestoreTextColor(void) {
    if(!LMVCopyLogXTextOriginal)return;
    for(UIView *view in LMVCopyLogXTextOriginal.keyEnumerator) {
        if(![view isKindOfClass:UILabel.class])continue;
        id original=[LMVCopyLogXTextOriginal objectForKey:view];
        UILabel *label=(UILabel *)view;
        if([original isKindOfClass:NSAttributedString.class])label.attributedText=original;
        else if([original isKindOfClass:UIColor.class])label.textColor=original;
    }
    [LMVCopyLogXTextOriginal removeAllObjects];
}
@interface LMVCopyLogXVideoHost:UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@end
@implementation LMVCopyLogXVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;
        self.opaque=NO;
        self.userInteractionEnabled=NO;
        self.tag=LMVCopyLogXHostTag;
    }
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
@end
@interface LMVCopyLogXVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVCopyLogXVideoHost *host;
@property(nonatomic,weak) UIView *card;
@property(nonatomic,copy) NSString *mode;
@property(nonatomic) BOOL updating;
- (void)detach;
- (void)update;
@end
static LMVCopyLogXVideoManager *LMVCopyLogXVideo;
@implementation LMVCopyLogXVideoManager
- (instancetype)init {
    if(!LMVCopyLogXEnvironment())return nil;
    if(([super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=NO;
        _host=[[LMVCopyLogXVideoHost alloc] initWithFrame:CGRectZero];_host.playback=_playback;
        _playback.renderLayer.name=@"com.minis.lockmessagevideo.copylogx.render";
        [_host.layer addSublayer:_playback.renderLayer];
    }
    return self;
}
- (void)dealloc {[_host removeFromSuperview];}
- (void)detach {
    if(self.host.superview)[self.host removeFromSuperview];
    self.host.hidden=YES;
    if(self.playback.wantsPlayback)[self.playback setVisible:NO];
    LMVCopyLogXRestoreTextColor();
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
    UIWindow *window=nil;
    UIView *card=LMVCopyLogXFindCard(&window);
    if(!card) {
        // 2.33: say WHY, the way the PA channel does. Without this line "switch on,
        // material picked, still nothing" is indistinguishable from "no card".
        if(LMVDiagnosticsEnabled.load()) {
            NSString *line=[NSString stringWithFormat:@"clx-nocard windows=%@",LMVCopyLogXWindowDump()];
            static NSString *lastLine=nil;
            if(![line isEqualToString:lastLine]) {lastLine=[line copy];LMVDiagnostic(line);}
        }
        [self detach];self.updating=NO;return;
    }
    if(self.card!=card) {[self.host removeFromSuperview];self.card=card;}
    BOOL changed=![self.playback.path isEqualToString:LMVCopyLogXPath] ||
        ![self.playback.revision isEqualToString:LMVCopyLogXRevision];
    if(changed) {
        [self.host removeFromSuperview];
        [self.playback preparePosterForPath:LMVCopyLogXPath revision:LMVCopyLogXRevision];
        [self.playback selectPath:LMVCopyLogXPath revision:LMVCopyLogXRevision];
    }
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    BOOL hasPoster=self.playback.posterLayer.contents!=nil;
    BOOL live=self.playback.player && !self.playback.error &&
        (hasPoster || self.playback.playerLayer.readyForDisplay);
    if(!live) {[self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;return;}
    // Index 0 of the card: above the sheet's background, below the clipboard table.
    UIView *container=card;NSUInteger index=0;CGRect target=card.bounds;NSString *mode=@"card";
    self.mode=mode;
    BOOL placed=self.host.superview==container &&
        (NSInteger)[container.subviews indexOfObjectIdenticalTo:self.host]==(NSInteger)index;
    if(!placed && ![self insertHostInto:container at:index]) {[self detach];self.updating=NO;return;}
    CGFloat radius=card.layer.cornerRadius;
    UIView *material=card.superview;
    if([material isKindOfClass:UIVisualEffectView.class] && material.layer.cornerRadius>0)
        radius=material.layer.cornerRadius;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    if(!CGRectEqualToRect(self.host.frame,target))self.host.frame=target;
    UIViewAutoresizing mask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    if(self.host.autoresizingMask!=mask)self.host.autoresizingMask=mask;
    if(self.host.layer.cornerRadius!=radius)self.host.layer.cornerRadius=radius;
    self.host.layer.masksToBounds=YES;
    [self.playback layoutInBounds:self.host.bounds];
    [CATransaction commit];
    if(self.host.hidden)self.host.hidden=NO;
    LMVCopyLogXApplyTextColor(card);
    if(LMVDiagnosticsEnabled.load()) {
        CGRect bounds=window.bounds,frame=[card convertRect:card.bounds toView:window];
        NSString *status=[NSString stringWithFormat:@"clx-panel win=%@ %.0fx%.0f mode=%@ card=%@@%.0f,%.0f,%.0fx%.0f r%.0f vis=%.0f live=%d host=%.0fx%.0f ready=%d poster=%d rate=%.1f",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            self.mode?:@"none",
            NSStringFromClass(card.class),frame.origin.x,frame.origin.y,frame.size.width,frame.size.height,
            radius,LMVCopyLogXVisibleArea(frame,bounds),(int)live,
            self.host.bounds.size.width,self.host.bounds.size.height,
            (int)self.playback.playerLayer.readyForDisplay,
            (int)(self.playback.posterLayer.contents!=nil),
            self.playback.player?self.playback.player.rate:0.0];
        static NSString *lastStatus=nil;
        if(![status isEqualToString:lastStatus]) {lastStatus=[status copy];LMVDiagnostic(status);}
    }
    self.updating=NO;
}
@end
static void LMVCopyLogXRetune(void) {
    NSTimeInterval want=LMVCopyLogXEnabled?.1:.5;
    if(LMVCopyLogXTimer && fabs(LMVCopyLogXTimer.timeInterval-want)<.001)return;
    [LMVCopyLogXTimer invalidate];
    LMVCopyLogXTimer=[NSTimer timerWithTimeInterval:want repeats:YES block:^(NSTimer *timer){LMVCopyLogXVideoRefresh(NO);}];
    [NSRunLoop.mainRunLoop addTimer:LMVCopyLogXTimer forMode:NSRunLoopCommonModes];
}
static void LMVCopyLogXVideoRefresh(BOOL reload) {
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady)return;
    if(reload || !LMVCopyLogXPrefsKnown) {
        LMVCopyLogXPrefsKnown=YES;
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("CopyLogXBackgroundEnabled"),kLMVPrefsID);
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        LMVCopyLogXEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&
            [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        LMVCopyLogXPath=LMVCCSelectedPath(@"CopyLogXVideo");
        LMVCopyLogXRevision=LMVLockVideoRevision(LMVCopyLogXPath);
    }
    LMVCopyLogXRetune();
    if(!LMVCopyLogXEnabled || !LMVCopyLogXPath.length || !LMVCopyLogXRevision.length) {
        if(LMVDiagnosticsEnabled.load()) {
            static NSString *lastGate=nil;
            NSString *gate=[NSString stringWithFormat:@"clx-panel gate enabled=%d path=%d revision=%d (no video: switch off or no material selected)",
                (int)LMVCopyLogXEnabled,(int)(LMVCopyLogXPath.length>0),(int)(LMVCopyLogXRevision.length>0)];
            if(![gate isEqualToString:lastGate]) {lastGate=[gate copy];LMVDiagnostic(gate);}
        }
        [LMVCopyLogXVideo detach];
        if(LMVCopyLogXVideo.playback.path)[LMVCopyLogXVideo.playback clear];
        return;
    }
    if(!LMVCopyLogXEnvironment()) {[LMVCopyLogXVideo detach];return;}
    if(!LMVCopyLogXVideo)LMVCopyLogXVideo=[LMVCopyLogXVideoManager new];
    @try {[LMVCopyLogXVideo update];}
    @catch(NSException *exception) {[LMVCopyLogXVideo detach];}
}
static void LMVCopyLogXVideoSuspend(void) {
    if(!NSThread.isMainThread)return;
    [LMVCopyLogXVideo detach];
}
static void LMVCopyLogXVideoInstallHooks(void) {
    if(LMVCopyLogXTimer || !LMVCopyLogXSpringBoard())return;
    LMVCopyLogXRetune();
}
