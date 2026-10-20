#pragma once
#import <dlfcn.h>
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
static BOOL LMVGlassSuiteEnabled,LMVGlassSuitePrefsKnown,LMVGlassSuiteDebugSize;
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
static NSString *LMVGlassSuiteImageName(Class cls) {
    if(!cls)return nil;
    Dl_info info;
    if(dladdr((__bridge const void *)cls,&info)==0 || !info.dli_fname)return nil;
    return [NSString stringWithUTF8String:info.dli_fname];
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
// names it GAXAlertOverlayView. Owner second: whatever class it uses next, if the
// dylib that owns it is GlassSuiteX, the same window is still ours.
static BOOL LMVGlassSuiteContainerKind(UIView *view) {
    if(!view)return NO;
    NSString *name=NSStringFromClass(view.class);
    if([name rangeOfString:@"GAX" options:NSCaseInsensitiveSearch].location!=NSNotFound)return YES;
    NSString *owner=LMVGlassSuiteImageName(view.class);
    return owner && [owner rangeOfString:@"GlassSuiteX" options:NSCaseInsensitiveSearch].location!=NSNotFound;
}
static BOOL LMVGlassSuiteShellKind(UIView *view) {
    NSString *name=NSStringFromClass(view.class);
    return [name containsString:@"Dimming"] || [name containsString:@"Backdrop"];
}
static BOOL LMVGlassSuiteGlassKind(UIView *view) {
    if(!view)return NO;
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
static UIView *LMVGlassSuiteCard(UIWindow *window) {
    if(!window)return nil;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)window];
    NSUInteger budget=600;
    while(pending.count && budget) {
        --budget;
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            if(child.tag==LMVGlassSuiteHostTag || child.hidden || child.alpha<.01)continue;
            if(LMVGlassSuiteContainerKind(child)) {
                UIView *card=LMVGlassSuiteCardIn(child,window);
                if(card)return card;
            }
            if(child.subviews.count&&budget)[pending addObject:child];
        }
    }
    // Renamed container: a window owned by GlassSuiteX is searched structurally -
    // the sheet always carries a Dimming/Backdrop material.
    NSString *owner=LMVGlassSuiteImageName(window.class);
    if(!owner || [owner rangeOfString:@"GlassSuiteX" options:NSCaseInsensitiveSearch].location==NSNotFound)return nil;
    pending=[NSMutableArray arrayWithObject:(id)window];budget=600;
    while(pending.count && budget) {
        --budget;
        UIView *node=pending.lastObject;[pending removeLastObject];
        BOOL shell=NO;
        for(UIView *child in node.subviews) {
            if(child.tag==LMVGlassSuiteHostTag)continue;
            if(LMVGlassSuiteShellKind(child))shell=YES;
            if(child.subviews.count&&budget)[pending addObject:child];
        }
        if(!shell)continue;
        return LMVGlassSuiteCardIn(node,window);
    }
    return nil;
}
static __weak UIWindow *LMVGlassSuiteLastWindow;
static UIView *LMVGlassSuiteFindCard(UIWindow **windowOut) {
    if(windowOut)*windowOut=nil;
    if(LMVGlassSuiteLastWindow && !LMVGlassSuiteLastWindow.hidden &&
       LMVGlassSuiteLastWindow.alpha>=.01) {
        UIView *card=LMVGlassSuiteCard(LMVGlassSuiteLastWindow);
        if(card) {if(windowOut)*windowOut=LMVGlassSuiteLastWindow;return card;}
    }
    UIView *best=nil;UIWindow *bestWindow=nil;
    for(UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if(![scene isKindOfClass:UIWindowScene.class])continue;
        for(UIWindow *window in ((UIWindowScene *)scene).windows) {
            if(window.hidden || window.alpha<.01)continue;
            UIWindow *home=[NSStringFromClass(window.class) containsString:@"SBHomeScreen"]?window:nil;
            UIView *card=LMVGlassSuiteCard(window);
            if(!card)continue;
            if(home) {best=card;bestWindow=window;break;}
            if(!best) {best=card;bestWindow=window;}
        }
        if(best && [NSStringFromClass(bestWindow.class) containsString:@"SBHomeScreen"])break;
    }
    if(best) {
        LMVGlassSuiteLastWindow=bestWindow;
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
    UIView *card=LMVGlassSuiteFindCard(&window);
    if(!card) {[self detach];self.updating=NO;return;}
    if(self.card!=card) {[self.host removeFromSuperview];self.card=card;}
    LMVGlassSuiteApplyTextColor(card);
    BOOL changed=![self.playback.path isEqualToString:LMVGlassSuitePath] ||
        ![self.playback.revision isEqualToString:LMVGlassSuiteRevision];
    if(changed) {[self.host removeFromSuperview];[self.playback selectPath:LMVGlassSuitePath revision:LMVGlassSuiteRevision];}
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    BOOL live=self.playback.player && !self.playback.error &&
        (self.playback.posterLayer.contents!=nil || self.playback.playerLayer.readyForDisplay);
    if(!live) {[self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;return;}
    UIView *material=LMVGlassSuiteMaterial(card,window);
    UIView *container=nil;NSUInteger index=0;CGRect target=CGRectZero;NSString *mode=@"card";
    // 2.29: THE CARD IS THE CONTENT VIEW, SO THE VIDEO GOES INSIDE IT.
    // Device hierarchy: UIVisualEffectView { _UIDimmingKnockoutBackdropView,
    // _UIVisualEffectContentView { background, scroll, stack(labels) } }. Mounting
    // above the UIVisualEffectView (the old path) put the video over the labels.
    // Index 0 of the content view is above its background and below every label.
    if([card.superview isKindOfClass:UIVisualEffectView.class]) {
        container=card;index=0;target=card.bounds;mode=@"content";
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
        NSString *status=[NSString stringWithFormat:@"gs-panel win=%@ %.0fx%.0f mode=%@ card=%@@%.0f,%.0f,%.0fx%.0f r%.0f vis=%.0f live=%d host=%.0fx%.0f ready=%d poster=%d rate=%.1f text=%@ size=%.0fx%.0f",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            self.mode?:@"none",
            NSStringFromClass(self.card.class),frame.origin.x,frame.origin.y,frame.size.width,frame.size.height,
            self.card.layer.cornerRadius,LMVGlassSuiteVisibleArea(frame,bounds),(int)live,
            self.host.bounds.size.width,self.host.bounds.size.height,
            (int)self.playback.playerLayer.readyForDisplay,
            (int)(self.playback.posterLayer.contents!=nil),
            self.playback.player?self.playback.player.rate:0.0,
            LMVGlassSuiteTextColor()?@"on":@"off",
            frame.size.width,frame.size.height];
        static NSString *lastStatus=nil;
        if(![status isEqualToString:lastStatus]) {lastStatus=[status copy];LMVDiagnostic(status);}
        if(LMVGlassSuiteDebugSize) LMVDiagnostic([NSString stringWithFormat:@"gs-size card=%.0fx%.0f win=%@",
            frame.size.width,frame.size.height,NSStringFromClass(window.class)]);
    }
    self.updating=NO;
}
@end
static void LMVGlassSuiteRetune(void) {
    NSTimeInterval want=LMVGlassSuiteEnabled?.1:.5;
    if(LMVGlassSuiteTimer && fabs(LMVGlassSuiteTimer.timeInterval-want)<.001)return;
    [LMVGlassSuiteTimer invalidate];
    LMVGlassSuiteTimer=[NSTimer timerWithTimeInterval:want repeats:YES block:^(NSTimer *timer){LMVGlassSuiteVideoRefresh(NO);}];
    [NSRunLoop.mainRunLoop addTimer:LMVGlassSuiteTimer forMode:NSRunLoopCommonModes];
}
static void LMVGlassSuiteVideoRefresh(BOOL reload) {
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady)return;
    if(reload || !LMVGlassSuitePrefsKnown) {
        LMVGlassSuitePrefsKnown=YES;
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GSBackgroundEnabled"),kLMVPrefsID);
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        id debug=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GSDebugSize"),kLMVPrefsID);
        LMVGlassSuiteEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&
            [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        LMVGlassSuiteDebugSize=[debug isKindOfClass:NSNumber.class] && [debug boolValue];
        LMVGlassSuitePath=LMVCCSelectedPath(@"GSVideo");
        LMVGlassSuiteRevision=LMVLockVideoRevision(LMVGlassSuitePath);
    }
    LMVGlassSuiteRetune();
    if(!LMVGlassSuiteEnabled || !LMVGlassSuitePath.length || !LMVGlassSuiteRevision.length) {
        [LMVGlassSuiteVideo detach];
        if(LMVGlassSuiteVideo.playback.path)[LMVGlassSuiteVideo.playback clear];
        return;
    }
    if(!LMVGlassSuiteEnvironment()) {[LMVGlassSuiteVideo detach];return;}
    if(!LMVGlassSuiteVideo)LMVGlassSuiteVideo=[LMVGlassSuiteVideoManager new];
    @try {[LMVGlassSuiteVideo update];}
    @catch(NSException *exception) {[LMVGlassSuiteVideo detach];}
}
static void LMVGlassSuiteVideoSuspend(void) {
    if(!NSThread.isMainThread)return;
    [LMVGlassSuiteVideo detach];
}
static void LMVGlassSuiteVideoInstallHooks(void) {
    if(LMVGlassSuiteTimer || !LMVGlassSuiteSpringBoard())return;
    LMVGlassSuiteRetune();
}
