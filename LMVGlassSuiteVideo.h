#pragma once
#import <dlfcn.h>
#import <objc/runtime.h>
// 2.29: the GlassSuiteX pop-up background (GlassSuiteX 弹窗背景视频).
//
// GlassSuiteX re-hosts the phone-assist sheet into its own hierarchy and renames
// the presentation view; the device log (2.26) shows the shape it presents:
//
//   SBHomeScreenWindow@0,0,430,932
//     UITransitionView@0,0,430,932
//       GAXAlertOverlayView@0,0,430,932
//         UIVisualEffectView
//           _UIDimmingKnockoutBackdropView
//           _UIVisualEffectContentView@51,172,328,589   <- THE CARD
//
// So this channel looks for the GlassSuiteX container BY NAME ("GAX") and then
// takes the largest visible, non-full-screen view inside it - that is the card the
// user sees, whatever the internal class names become. If GlassSuiteX ever renames
// the container too, the fallback is the window owned by GlassSuiteX.dylib (asked
// through dladdr), searched structurally for a Dimming/Backdrop material.
//
// Mount: UNDER the content but ABOVE the material, skipping any Blur/Glass/Effect
// sibling GlassSuiteX slipped in above the material - otherwise the glass paints
// over the video while the status line still says "playing".
//
// Requires the shared helpers imported earlier in the translation unit
// (LMVLockVideoPlayback, LMVCCSelectedPath, LMVLockVideoRevision, LMVInitialized,
// LMVLaunchReady, LMVBlankToken, LMVLockToken, LMVDiagnosticsEnabled,
// LMVDiagnostic, kLMVPrefsID).

static void LMVGlassSuiteVideoRefresh(BOOL reload);
static void LMVGlassSuiteVideoSuspend(void);
static void LMVGlassSuiteInstallContainerHook(void);
static BOOL LMVGlassSuiteEnabled,LMVGlassSuitePrefsKnown;
static NSString *LMVGlassSuitePath,*LMVGlassSuiteRevision;
static NSTimer *LMVGlassSuiteTimer;

static BOOL LMVGlassSuiteSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}
static BOOL LMVGlassSuiteEnvironment(void) {
    uint64_t blank=1,locked=1;
    return LMVInitialized && LMVLaunchReady && NSThread.isMainThread && LMVGlassSuiteSpringBoard() &&
        LMVBlankToken>=0 && LMVLockToken>=0 &&
        notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK &&
        notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK && !blank && !locked;
}
// 2.36: the class chain from the card up to its window, so the line can be matched
// one-to-one against FLEX instead of guessing which view was picked.
static NSString *LMVGlassSuiteChain(UIView *view) {
    NSMutableArray *names=[NSMutableArray array];
    UIView *node=view;NSInteger depth=0;
    while(node && depth++<8) {
        [names insertObject:NSStringFromClass(node.class) atIndex:0];
        node=node.superview;
    }
    return [names componentsJoinedByString:@">"];
}
static NSInteger const LMVGlassSuiteHostTag=0x5A29;
static CGFloat LMVGlassSuiteVisibleArea(CGRect frame,CGRect bounds) {
    if(CGRectIsEmpty(frame) || CGRectIsEmpty(bounds))return 0;
    CGRect onScreen=CGRectIntersection(frame,bounds);
    if(CGRectIsEmpty(onScreen))return 0;
    CGFloat total=frame.size.width*frame.size.height;
    if(total<=0)return 0;
    CGFloat visible=onScreen.size.width*onScreen.size.height;
    return visible/total>=.5?visible:0;
}
// The container GlassSuiteX presents the sheet through. Name first: the 2.26 log
// names it GAXAlertOverlayView, and the 2.35 capture shows it at depth 2 under
// SBHomeScreenWindow (SBHomeScreenWindow > UITransitionView > GAXAlertOverlayView).
// 2.95b: THE GAX NAME IS NOW THE ONLY ACCEPTED CONTAINER.
// The old fallback accepted any Overlay/Alert/Panel/Sheet class whose image was
// GlassSuiteX.dylib. That dylib also ships the OTHER sheets (wossiddy and friends),
// so "belongs to the same dylib" was never the same question as "is the GlassSuiteX
// pop-up" - the video was mounted into somebody else's card and that is exactly the
// reported "GlassSuiteX 弹窗把视频挂到别的弹窗上". If GlassSuiteX ever renames the
// container the channel stops mounting, which is the intended trade: never mount
// outside our own sheet.
static BOOL LMVGlassSuiteContainerKind(UIView *view) {
    if(!view)return NO;
    NSString *name=NSStringFromClass(view.class);
    return [name rangeOfString:@"GAX" options:NSCaseInsensitiveSearch].location!=NSNotFound;
}
static BOOL LMVGlassSuiteGlassKind(UIView *view) {    if(!view)return NO;
    if([view isKindOfClass:UIVisualEffectView.class])return YES;
    NSString *name=NSStringFromClass(view.class);
    // 2.29: the CARD itself is _UIVisualEffectContentView - its name contains
    // "Effect" but it is the content container, not a glass layer. Treating it as
    // glass skipped the real card and mounted the video above the whole sheet.
    if([name containsString:@"ContentView"])return NO;
    for(NSString *word in @[@"Blur",@"Glass",@"Vibrancy",@"Dimming",@"Backdrop",@"Effect"])
        if([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound)return YES;
    return NO;
}
// Largest visible, non-full-screen view inside `root` (root itself allowed). This
// is the card: the 328x589 content view in the 2.26 capture.
static UIView *LMVGlassSuiteCardIn(UIView *root,UIWindow *window) {
    if(!root || !window)return nil;
    CGRect bounds=window.bounds;
    if(CGRectIsEmpty(bounds))return nil;
    UIView *best=nil;CGFloat bestArea=0;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];
    NSUInteger budget=500;
    while(pending.count && budget) {
        --budget;
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            if(child.tag==LMVGlassSuiteHostTag || child.hidden || child.alpha<.01)continue;
            [pending addObject:child];
            if(LMVGlassSuiteGlassKind(child))continue;
            CGRect frame=[child convertRect:child.bounds toView:window];
            if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;
            if(frame.size.width<bounds.size.width*.3 || frame.size.height<bounds.size.height*.05)continue;
            CGFloat visible=LMVGlassSuiteVisibleArea(frame,bounds);
            if(visible>bestArea){bestArea=visible;best=child;}
        }
    }
    return best;
}
// 2.36: the home screen window carries the entire icon grid. Nothing in it can
// hold the sheet, and walking it was over 90% of every 0.1s probe.
static BOOL LMVGlassSuiteSkipSubtree(UIView *view) {
    if(!view)return NO;
    NSString *name=NSStringFromClass(view.class);
    for(NSString *word in @[@"SBIcon",@"SBRecycled",@"SBFolder",@"Backdrop",@"Wallpaper",
                            @"StatusBar",@"Dock",@"Switcher"])
        if([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound)return YES;
    return NO;
}
// 2.36: cache the CARD, not the window. The old cache stored SBHomeScreenWindow,
// so every probe re-walked the whole home screen even while the sheet was up.
static __weak UIView *LMVGlassSuiteCardRef;
static UIView *LMVGlassSuiteCachedCard(UIWindow **windowOut) {
    UIView *card=LMVGlassSuiteCardRef;
    if(!card || !card.superview || card.hidden || card.alpha<.01)return nil;
    UIWindow *window=(UIWindow *)card.window;
    if(!window || window.hidden || window.alpha<.01)return nil;
    if(windowOut)*windowOut=window;
    return card;
}
// 2.36: two levels, no deep scan. The 2.35 capture puts GAXAlertOverlayView at
// depth 2 under SBHomeScreenWindow, so a few dozen comparisons find it.
static UIView *LMVGlassSuiteShallowCard(UIWindow *window) {
    if(!window)return nil;
    for(UIView *layer in window.subviews) {
        if(layer.tag==LMVGlassSuiteHostTag || layer.hidden || layer.alpha<.01)continue;
        if(LMVGlassSuiteSkipSubtree(layer))continue;
        if(LMVGlassSuiteContainerKind(layer)) {
            UIView *card=LMVGlassSuiteCardIn(layer,window);
            if(card)return card;
        }
        for(UIView *child in layer.subviews) {
            if(child.tag==LMVGlassSuiteHostTag || child.hidden || child.alpha<.01)continue;
            if(LMVGlassSuiteSkipSubtree(child))continue;
            if(LMVGlassSuiteContainerKind(child)) {
                UIView *card=LMVGlassSuiteCardIn(child,window);
                if(card)return card;
            }
        }
    }
    return nil;
}
static UIView *LMVGlassSuiteFindCard(UIWindow **windowOut) {
    if(windowOut)*windowOut=nil;
    UIView *cached=LMVGlassSuiteCachedCard(windowOut);
    if(cached)return cached;
    LMVGlassSuiteCardRef=nil;
    UIView *best=nil;UIWindow *bestWindow=nil;
    // 2.55: shared snapshot (already filtered to visible windows).
    for(UIWindow *window in LMVProbeVisibleWindows()) {
        NSString *name=NSStringFromClass(window.class);
        BOOL skipWindow=NO;
        for(NSString *word in @[@"SystemAperture",@"TouchVisualizer",@"TextEffects",@"RecordingIndicator"])
            if([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound){skipWindow=YES;break;}
        if(skipWindow)continue;
        UIView *card=LMVGlassSuiteShallowCard(window);
        if(!card)continue;
        if([name containsString:@"SBHomeScreen"]) {best=card;bestWindow=window;break;}
        if(!best) {best=card;bestWindow=window;}
    }
    if(best) {
        LMVGlassSuiteCardRef=best;
        if(windowOut)*windowOut=bestWindow;
    }
    return best;
}
static UIView *LMVGlassSuiteMaterial(UIView *root,UIWindow *window) {
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
// Text colour: independent from every other channel (`GSTextColor`). Remembers the
// first colour seen per label and restores it when the sheet closes.
static NSMapTable<UIView *,id> *LMVGlassSuiteTextOriginal;
static UIColor *LMVGlassSuiteTextColor(void) {
    NSNumber *value=(__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("GSTextColor"),kLMVPrefsID);
    if(![value isKindOfClass:NSNumber.class])return nil;
    uint32_t word=value.unsignedIntValue;
    return [UIColor colorWithRed:((word>>24)&0xFF)/255.0 green:((word>>16)&0xFF)/255.0
                           blue:((word>>8)&0xFF)/255.0 alpha:(word&0xFF)/255.0];
}
static BOOL LMVGlassSuiteColorEqual(UIColor *a,UIColor *b) {
    if(!a || !b)return a==b;
    CGFloat ar=0,ag=0,ab=0,aa=0,br=0,bg=0,bb=0,ba=0;
    if(![a getRed:&ar green:&ag blue:&ab alpha:&aa] || ![b getRed:&br green:&bg blue:&bb alpha:&ba])return [a isEqual:b];
    return fabs(ar-br)<.002 && fabs(ag-bg)<.002 && fabs(ab-bb)<.002 && fabs(aa-ba)<.002;
}
static void LMVGlassSuiteApplyTextColor(UIView *root) {
    UIColor *color=LMVGlassSuiteTextColor();
    if(!root || !color)return;
    if(!LMVGlassSuiteTextOriginal)LMVGlassSuiteTextOriginal=[NSMapTable weakToStrongObjectsMapTable];
    NSMutableArray *pending=[NSMutableArray arrayWithObject:root];
    NSUInteger budget=300;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            if(child.tag==LMVGlassSuiteHostTag)continue;
            [pending addObject:child];
            if(![child isKindOfClass:UILabel.class])continue;
            UILabel *label=(UILabel *)child;
            if(label.attributedText.length) {
                UIColor *now=[label.attributedText attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
                if(LMVGlassSuiteColorEqual(now,color))continue;
                if(![LMVGlassSuiteTextOriginal objectForKey:label])[LMVGlassSuiteTextOriginal setObject:label.attributedText forKey:label];
                NSMutableAttributedString *text=[label.attributedText mutableCopy];
                [text addAttribute:NSForegroundColorAttributeName value:color range:NSMakeRange(0,text.length)];
                label.attributedText=text;
            } else if(label.text.length) {
                if(LMVGlassSuiteColorEqual(label.textColor,color))continue;
                if(![LMVGlassSuiteTextOriginal objectForKey:label])
                    [LMVGlassSuiteTextOriginal setObject:(label.textColor?:UIColor.labelColor) forKey:label];
                label.textColor=color;
            }
        }
    }
}
static void LMVGlassSuiteRestoreTextColor(void) {
    if(!LMVGlassSuiteTextOriginal)return;
    for(UIView *view in LMVGlassSuiteTextOriginal.keyEnumerator) {
        if(![view isKindOfClass:UILabel.class])continue;
        id original=[LMVGlassSuiteTextOriginal objectForKey:view];
        UILabel *label=(UILabel *)view;
        if([original isKindOfClass:NSAttributedString.class])label.attributedText=original;
        else if([original isKindOfClass:UIColor.class])label.textColor=original;
    }
    [LMVGlassSuiteTextOriginal removeAllObjects];
}
@interface LMVGlassSuiteVideoHost:UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@end
@implementation LMVGlassSuiteVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.backgroundColor=UIColor.clearColor;
        self.opaque=NO;
        self.userInteractionEnabled=NO;
        self.tag=LMVGlassSuiteHostTag;
    }
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
@end
@interface LMVGlassSuiteVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVGlassSuiteVideoHost *host;
@property(nonatomic,weak) UIView *card;
@property(nonatomic,copy) NSString *mode;
@property(nonatomic) BOOL updating;
// 2.39: show/hide delay timestamps (0 = not pending).
@property(nonatomic) NSTimeInterval pendingShow,pendingHide;
- (void)detach;
- (void)update;
@end
static LMVGlassSuiteVideoManager *LMVGlassSuiteVideo;
@implementation LMVGlassSuiteVideoManager
- (instancetype)init {
    if(!LMVGlassSuiteEnvironment())return nil;
    if((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.persistentPosterEnabled=NO;
        _host=[[LMVGlassSuiteVideoHost alloc] initWithFrame:CGRectZero];_host.playback=_playback;
        _playback.renderLayer.name=@"com.minis.lockmessagevideo.glasssuite.render";
        [_host.layer addSublayer:_playback.renderLayer];
    }
    return self;
}
- (void)dealloc {[_host removeFromSuperview];}
- (void)detach {
    if(self.host.superview)[self.host removeFromSuperview];
    self.host.hidden=YES;
    if(self.playback.wantsPlayback)[self.playback setVisible:NO];
    LMVGlassSuiteRestoreTextColor();
    LMVGlassSuiteCardRef=nil;
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
    if(LMVGlassSuiteEnabled && LMVGlassSuitePath.length && LMVGlassSuiteRevision.length &&
       (![self.playback.path isEqualToString:LMVGlassSuitePath] || ![self.playback.revision isEqualToString:LMVGlassSuiteRevision]))
        [self.playback selectPath:LMVGlassSuitePath revision:LMVGlassSuiteRevision];
    UIWindow *window=nil;
    UIView *card=LMVGlassSuiteFindCard(&window);
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    // 2.39: 出现延迟 - hold the sheet's first frame for N ms before mounting, so the
    // video lands mid-animation instead of before it.
    if(card && !self.card) {
        NSTimeInterval show=LMVTuneDelay(@"GS",@"ShowDelayMs");
        if(self.pendingShow<=0)self.pendingShow=now;
        if(show>0 && now-self.pendingShow<show) {self.updating=NO;return;}
        self.pendingShow=0;
    } else if(!card) {
        self.pendingShow=0;
    }
    if(!card) {
        // 2.39: 关闭延迟 - keep the surface for N ms after the sheet goes away.
        NSTimeInterval hide=LMVTuneDelay(@"GS",@"HideDelayMs");
        if(hide>0 && self.card && self.host.superview) {
            if(self.pendingHide<=0)self.pendingHide=now;
            if(now-self.pendingHide<hide) {self.updating=NO;return;}
        }
        self.pendingHide=0;
        [self detach];self.updating=NO;return;
    }
    self.pendingHide=0;
    if(self.card!=card) {[self.host removeFromSuperview];self.card=card;}
    LMVGlassSuiteApplyTextColor(card);
    BOOL changed=![self.playback.path isEqualToString:LMVGlassSuitePath] ||
        ![self.playback.revision isEqualToString:LMVGlassSuiteRevision];
    if(changed) {[self.host removeFromSuperview];[self.playback selectPath:LMVGlassSuitePath revision:LMVGlassSuiteRevision];}
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    // 2.60: mount as soon as the (prewarmed) player exists. The render layer stays
    // hidden until the first frame is decoded (updatePresentation), so the panel is
    // covered the moment that frame arrives - no poster, no readyForDisplay wait.
    BOOL live=self.playback.player && !self.playback.error;
    if(!live) {[self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;return;}
    UIView *material=LMVGlassSuiteMaterial(card,window);
    UIView *container=nil;NSUInteger index=0;CGRect target=CGRectZero;NSString *mode=@"card";
    // 2.95: ALWAYS THE CARD'S CURRENT SIZE, NEVER THE MATERIAL'S FRAME.
    // The material is the full-screen UIVisualEffectView; the card is its
    // _UIVisualEffectContentView child. Sizing the host from material.frame painted
    // the video across the whole sheet - and, because the sheet shares
    // SBHomeScreenWindow>UITransitionView with other pop-ups, it showed up under
    // them too. The presentation layer is used so the host tracks the open/close
    // animation instead of staying at the previous (bigger) size.
    CALayer *cardLayer=(CALayer *)card.layer.presentationLayer;
    CGRect liveBounds=cardLayer?cardLayer.bounds:card.bounds;
    if(CGRectIsEmpty(liveBounds)) liveBounds=card.bounds;
    // 2.29: THE CARD IS THE CONTENT VIEW, SO THE VIDEO GOES INSIDE IT.
    // Device hierarchy: UIVisualEffectView { _UIDimmingKnockoutBackdropView,
    // _UIVisualEffectContentView { background, scroll, stack(labels) } }. Mounting
    // above the UIVisualEffectView (the old path) put the video over the labels.
    // Index 0 of the content view is above its background and below every label.
    if([card.superview isKindOfClass:UIVisualEffectView.class]) {
        container=card;index=0;target=liveBounds;mode=@"content";
    } else if([material isKindOfClass:UIVisualEffectView.class] && material.superview) {
        container=material.superview;
        NSInteger near=(NSInteger)[container.subviews indexOfObjectIdenticalTo:material];
        if(near==NSNotFound) {[self detach];self.updating=NO;return;}
        NSUInteger slot=(NSUInteger)(near+1);
        // Land ABOVE any glass/effect layer GlassSuiteX slipped in after the
        // material, still below the labels (the first non-glass sibling).
        for(NSUInteger i=slot;i<container.subviews.count;i++) {
            UIView *sibling=container.subviews[i];
            if(sibling.tag==LMVGlassSuiteHostTag)break;
            if(!LMVGlassSuiteGlassKind(sibling))break;
            slot=i+1;
        }
        // 2.95: the CARD's rect in the container, not material.frame (full screen).
        index=slot;target=[card convertRect:liveBounds toView:container];mode=@"above-material";
    }
    if(!container) {container=card;index=0;target=liveBounds;}
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
        NSString *status=[NSString stringWithFormat:@"gs-panel win=%@ %.0fx%.0f mode=%@ card=%@@%.0f,%.0f,%.0fx%.0f r%.0f vis=%.0f live=%d host=%.0fx%.0f ready=%d poster=%d rate=%.1f text=%@ size=%.0fx%.0f chain=%@",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            self.mode?:@"none",
            NSStringFromClass(self.card.class),frame.origin.x,frame.origin.y,frame.size.width,frame.size.height,
            self.card.layer.cornerRadius,LMVGlassSuiteVisibleArea(frame,bounds),(int)live,
            self.host.bounds.size.width,self.host.bounds.size.height,
            (int)self.playback.playerLayer.readyForDisplay,
            (int)(self.playback.posterLayer.contents!=nil),
            self.playback.player?self.playback.player.rate:0.0,
            LMVGlassSuiteTextColor()?@"on":@"off",
            frame.size.width,frame.size.height,
            LMVGlassSuiteChain(self.card)];
        static NSString *lastStatus=nil;
        if(![status isEqualToString:lastStatus]) {lastStatus=[status copy];LMVDiagnostic(status);}
    }
    self.updating=NO;
}
@end
// 2.36: THE PROBE IS THE COST. 0.1s meant ten full home-screen walks a second even
// with no sheet on screen. Three gears now: sheet cached -> 0.25s (just babysit it),
// no sheet -> 0.75s (wait for it), switch off -> 2s (nothing to do but stay alive,
// so a missed preference notification cannot leave the channel dead). `tolerance`
// lets the system coalesce the wake-ups.
static NSTimeInterval LMVGlassSuiteInterval(void) {
    if(!LMVGlassSuiteEnabled)return LMVTuneIdleInterval;
    // 2.39: the waiting gear is the channel's own ProbeHz (default 5Hz = 0.2s).
    NSTimeInterval base=LMVTuneProbeInterval(@"GS");
    // With the sheet up we only babysit it, so never slower than 4Hz.
    if(LMVGlassSuiteCardRef)return MIN(base,.25);
    return base;
}
static void LMVGlassSuiteRetune(void) {
    NSTimeInterval want=LMVGlassSuiteInterval();
    if(LMVGlassSuiteTimer && fabs(LMVGlassSuiteTimer.timeInterval-want)<.001)return;
    [LMVGlassSuiteTimer invalidate];
    LMVGlassSuiteTimer=[NSTimer timerWithTimeInterval:want repeats:YES block:^(NSTimer *timer){LMVGlassSuiteVideoRefresh(NO);}];
    LMVGlassSuiteTimer.tolerance=want*.3;
    [NSRunLoop.mainRunLoop addTimer:LMVGlassSuiteTimer forMode:NSRunLoopCommonModes];
}
static void LMVGlassSuiteVideoRefresh(BOOL reload) {
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady)return;
    LMVGlassSuiteInstallContainerHook();
    if(reload || !LMVGlassSuitePrefsKnown) {
        LMVGlassSuitePrefsKnown=YES;
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GSBackgroundEnabled"),kLMVPrefsID);
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        LMVGlassSuiteEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&
            [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        LMVGlassSuitePath=LMVCCSelectedPath(@"GSVideo");
        LMVGlassSuiteRevision=LMVLockVideoRevision(LMVGlassSuitePath);
    }
    if(!LMVGlassSuiteEnabled || !LMVGlassSuitePath.length || !LMVGlassSuiteRevision.length) {
        [LMVGlassSuiteVideo detach];
        if(LMVGlassSuiteVideo.playback.path)[LMVGlassSuiteVideo.playback clear];
        LMVGlassSuiteRetune();
        return;
    }
    if(!LMVGlassSuiteEnvironment()) {[LMVGlassSuiteVideo detach];LMVGlassSuiteRetune();return;}
    if(!LMVGlassSuiteVideo)LMVGlassSuiteVideo=[LMVGlassSuiteVideoManager new];
    @try {[LMVGlassSuiteVideo update];}
    @catch(NSException *exception) {[LMVGlassSuiteVideo detach];}
    LMVGlassSuiteRetune();
}
static void LMVGlassSuiteVideoSuspend(void) {
    if(!NSThread.isMainThread)return;
    [LMVGlassSuiteVideo detach];
}
// 2.37: THE SHEET IS NOT IN OUR WINDOW, SO THERE IS NO WINDOW NOTIFICATION.
// GlassSuiteX adds GAXAlertOverlayView to SBHomeScreenWindow's UITransitionView;
// waiting for the next probe is what made the video show up a second after the
// sheet. Hooking the container's own didMoveToSuperview fires the moment it enters
// the hierarchy - i.e. at the start of the presentation animation. The probe timer
// stays as a fallback, so a missed hook only costs one interval.
// Adding the method to the subclass first is essential: setting the inherited IMP
// would replace UIView's didMoveToSuperview for every view on the system.
static IMP LMVGlassSuiteContainerMovedOriginal;
static BOOL LMVGlassSuiteContainerHooked;
static NSTimeInterval LMVGlassSuiteLastHookRefresh;
static void LMVGlassSuiteContainerMoved(id self,SEL _cmd) {
    if(LMVGlassSuiteContainerMovedOriginal)
        ((void(*)(id,SEL))LMVGlassSuiteContainerMovedOriginal)(self,_cmd);
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;
    NSTimeInterval limit=LMVTuneDelay(@"GS",@"HookThrottleMs");
    if(now-LMVGlassSuiteLastHookRefresh<limit)return;
    LMVGlassSuiteLastHookRefresh=now;
    LMVGlassSuiteVideoRefresh(NO);
}
static void LMVGlassSuiteInstallContainerHook(void) {
    if(LMVGlassSuiteContainerHooked)return;
    Class cls=NSClassFromString(@"GAXAlertOverlayView");
    if(!cls)return;
    SEL sel=@selector(didMoveToSuperview);
    Method inherited=class_getInstanceMethod(cls,sel);
    if(!inherited)return;
    IMP original=method_getImplementation(inherited);
    const char *types=method_getTypeEncoding(inherited);
    if(class_addMethod(cls,sel,(IMP)LMVGlassSuiteContainerMoved,types)) {
        LMVGlassSuiteContainerMovedOriginal=original;
    } else {
        Method own=class_getInstanceMethod(cls,sel);
        LMVGlassSuiteContainerMovedOriginal=method_getImplementation(own);
        method_setImplementation(own,(IMP)LMVGlassSuiteContainerMoved);
    }
    LMVGlassSuiteContainerHooked=YES;
}
static void LMVGlassSuiteVideoInstallHooks(void) {
    if(!LMVGlassSuiteSpringBoard())return;
    LMVGlassSuiteInstallContainerHook();
    if(LMVGlassSuiteTimer)return;
    LMVGlassSuiteRetune();
}
