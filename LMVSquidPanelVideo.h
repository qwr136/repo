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
// 1.44: the panel has two shapes; 1.50: each shape exists on BOTH gesture sides, so
// there are FOUR materials in all. 0 = 右边上滑 (right, "swipe up"), 1 = 右边上上滑
// (right, "swipe up twice"), 2 = 左边上滑, 3 = 左边上上滑. Even slots are the tall
// "上滑" panel, odd slots the short "上上滑" one; 0/1 are the right-hand gestures and
// 2/3 the left-hand ones. The sound switch and volume stay shared: only one of the
// four can be on screen at a time.
#define LMVSquidPanelSlotCount 4
static NSString *LMVSquidPanelSlotPaths[LMVSquidPanelSlotCount];
static NSString *LMVSquidPanelSlotRevisions[LMVSquidPanelSlotCount];
// The content signature each slot was last seen as - the 1.47/1.48 identity memory,
// now one entry per slot instead of one per shape.
static NSString *LMVSquidPanelSlotSigs[LMVSquidPanelSlotCount];
static NSTimeInterval LMVSquidPanelLastSeen;
static NSString *LMVSquidPanelClaimToken;
static NSTimer *LMVSquidPanelTimer;
// The user's material selection, by slot.
static NSArray *LMVSquidPanelSlotKeys(void) {
    return @[@"SquidPanelVideo",@"SquidPanel2Video",@"SquidPanel3Video",@"SquidPanel4Video"];
}
static NSArray *LMVSquidPanelSlotSigKeys(void) {
    return @[@"SquidPanelSlot1Sig",@"SquidPanelSlot2Sig",@"SquidPanelSlot3Sig",@"SquidPanelSlot4Sig"];
}
// The gesture each slot belongs to, for the diagnostics and the claim sheet.
static NSArray *LMVSquidPanelSlotTitles(void) {
    return @[@"右边上滑",@"右边上上滑",@"左边上滑",@"左边上上滑"];
}
static BOOL LMVSquidPanelSlotIsShort(NSInteger slot) {
    return slot>=0 && slot<LMVSquidPanelSlotCount && (slot&1)!=0;
}
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
// 1.44: which of the panels is on screen. Height alone is a fragile test (the short
// landscape panel is 41.9% of the screen while the tall portrait one is 46.7%), so
// the shape is read from the page control, which belongs to exactly one of them,
// sits 20pt above ITS OWN card in every orientation, and is hidden on the short
// panel while the tall one keeps it - the same in landscape and in portrait.
// 1.46: WHAT was classified, not what it looks like: a card that has been classified
// once keeps that classification. 1.47 replaced the object pair with CONTENT
// SIGNATURES, because the device log showed the card object being re-created on
// every open. 1.48 made the chain survive an edited panel.
// 1.50: the same chain now reports one of FOUR slots, and it is no longer the only
// answer: the two sides cannot be told apart from the content, so an unknown panel
// is claimed by the first free slot of its shape and the user can always re-bind it
// by hand (see LMVSquidPanelResolveSlot and the "认领刚用过的面板" row).
static NSString *LMVSquidPanelShapeSig;
static NSString *LMVSquidPanelShapeReason=@"none";
// 1.47: a CONTENT signature that does not contain the panel's height or width.
//
// Neither of the two obvious keys survives the device: the card object is re-created
// on every open (one 34-second log showed four different tall-card pointers), and the
// height is exactly what the user changes ("I made the short panel as tall as the
// tall one"). What DOES stay put is the content - how many icons the panel carries
// and how many dots its page control has - and those are the same in landscape and in
// portrait. The signature is remembered together with the slot it was seen as, so a
// panel that only grew taller keeps the material it had.
static NSUInteger LMVSquidPanelIconCount(UIView *card) {
    NSUInteger count=0;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:(id)card];
    NSUInteger budget=1200;
    while(pending.count && budget) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        for(UIView *child in node.subviews) {
            if(!budget--)break;
            if(child.tag==LMVSquidPanelHostTag)continue;
            if([child isKindOfClass:UIButton.class])count++;
            [pending addObject:child];
        }
    }
    return count;
}
// The page control of THIS card - the one pinned to its top edge.
static UIPageControl *LMVSquidPanelPageControl(UIView *card,UIWindow *window) {
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
    return (page && bestGap<40)?page:nil;
}
static NSString *LMVSquidPanelContentSignature(UIView *card,UIWindow *window) {
    if(!card)return @"none";
    NSUInteger icons=LMVSquidPanelIconCount(card);
    UIPageControl *page=LMVSquidPanelPageControl(card,window);
    CGFloat dots=0;
    if(page) {
        for(UIView *sub in page.subviews) {
            if([NSStringFromClass(sub.class) containsString:@"PageControlContentView"]) {
                dots=MAX(sub.bounds.size.width,sub.bounds.size.height);
                break;
            }
        }
    }
    return [NSString stringWithFormat:@"icons%lu|pc%d|dots%.0f",(unsigned long)icons,page?1:0,dots];
}
static NSUInteger LMVSquidPanelSignatureIcons(NSString *sig) {
    if(![sig isKindOfClass:NSString.class] || ![sig hasPrefix:@"icons"])return NSNotFound;
    return (NSUInteger)[[sig substringFromIndex:5] integerValue];
}
static NSUInteger LMVSquidPanelSignatureDistance(NSUInteger icons,NSString *sig) {
    NSUInteger other=LMVSquidPanelSignatureIcons(sig);
    if(icons==NSNotFound || other==NSNotFound)return NSNotFound;
    return (icons>other)?icons-other:other-icons;
}
// 1.50: bind a signature to a slot - and, because a signature only ever names ONE
// panel, drop it from whichever slot claimed it before. The auto chain does this on
// first sight; the "认领" row does it on the user's word (see LMVSquidPanelClaimSlot).
static void LMVSquidPanelRememberSlot(NSInteger slot,NSString *sig) {
    if(slot<0 || slot>=LMVSquidPanelSlotCount)return;
    if(![sig isKindOfClass:NSString.class] || !sig.length || [sig isEqualToString:@"none"])return;
    NSArray *keys=LMVSquidPanelSlotSigKeys();
    for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
        if(i==slot || !LMVSquidPanelSlotSigs[i].length)continue;
        if(![sig isEqualToString:LMVSquidPanelSlotSigs[i]])continue;
        CFPreferencesSetAppValue((__bridge CFStringRef)keys[i],NULL,kLMVPrefsID);
        LMVSquidPanelSlotSigs[i]=nil;
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)keys[slot],(__bridge CFStringRef)sig,kLMVPrefsID);
    CFPreferencesAppSynchronize(kLMVPrefsID);
    LMVSquidPanelSlotSigs[slot]=[sig copy];
}
// 1.50: which of the four materials this panel plays.
//
// (a) A signature seen before settles it outright - this is the whole point of the
//     identity memory: the panel keeps its material when the user edits it.
// (b) Otherwise the SHAPE decides first: "上上滑" is the short one. Both shapes
//     learned -> closest by icon count (the 1.48 rule), else the page control, else
//     the height.
// (c) The SIDE cannot be read from the content - the left and right gestures open
//     panels that differ only in what the user put in them. So an unknown panel is
//     bound to the slot of its shape that nothing has claimed yet (the right-hand one
//     first, because that is the pair that exists first on a device), and if both are
//     taken, to the closer of the two. (d) The user can always overrule that: the
//     "认领刚用过的面板" row re-binds the panel they just used to the slot they pick.
static NSInteger LMVSquidPanelResolveSlot(UIView *card,UIWindow *window) {
    if(!card)return 0;
    NSString *sig=LMVSquidPanelContentSignature(card,window);
    LMVSquidPanelShapeSig=sig;
    for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
        if(!LMVSquidPanelSlotSigs[i].length)continue;
        if(![sig isEqualToString:LMVSquidPanelSlotSigs[i]])continue;
        LMVSquidPanelShapeReason=[NSString stringWithFormat:@"sig-slot%d",(int)i+1];
        return i;
    }
    BOOL haveTall=NO,haveShort=NO;
    for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
        if(!LMVSquidPanelSlotSigs[i].length)continue;
        if(LMVSquidPanelSlotIsShort(i))haveShort=YES; else haveTall=YES;
    }
    BOOL shortPanel=NO;NSString *reason=nil;
    if(haveTall && haveShort) {
        NSUInteger icons=LMVSquidPanelSignatureIcons(sig);
        NSUInteger best=NSNotFound;BOOL bestShort=NO;
        for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
            if(!LMVSquidPanelSlotSigs[i].length)continue;
            NSUInteger d=LMVSquidPanelSignatureDistance(icons,LMVSquidPanelSlotSigs[i]);
            if(d==NSNotFound)continue;
            if(best==NSNotFound || d<best){best=d;bestShort=LMVSquidPanelSlotIsShort(i);}
        }
        if(best!=NSNotFound){shortPanel=bestShort;reason=bestShort?@"nearest-short":@"nearest-tall";}
    }
    if(!reason) {
        UIPageControl *page=LMVSquidPanelPageControl(card,window);
        if(page) {
            shortPanel=page.hidden;
            reason=[NSString stringWithFormat:@"page.hidden=%d",(int)page.hidden];
        } else {
            CGRect cardFrame=[card convertRect:card.bounds toView:window];
            CGFloat height=window.bounds.size.height;
            shortPanel=(height>0 && cardFrame.size.height<height*.45);
            reason=[NSString stringWithFormat:@"height=%.0f/%.0f",cardFrame.size.height,height];
        }
    }
    NSInteger right=shortPanel?1:0, left=shortPanel?3:2;
    NSInteger slot=right;
    if(!LMVSquidPanelSlotSigs[left].length) {
        slot=left;reason=[reason stringByAppendingString:@"@claim-left"];
    } else if(!LMVSquidPanelSlotSigs[right].length) {
        slot=right;reason=[reason stringByAppendingString:@"@claim-right"];
    } else {
        NSUInteger icons=LMVSquidPanelSignatureIcons(sig);
        NSUInteger dr=LMVSquidPanelSignatureDistance(icons,LMVSquidPanelSlotSigs[right]);
        NSUInteger dl=LMVSquidPanelSignatureDistance(icons,LMVSquidPanelSlotSigs[left]);
        slot=(dl!=NSNotFound && dr!=NSNotFound && dl<dr)?left:right;
        reason=[reason stringByAppendingFormat:@"@nearest-of-%d-%d",(int)right+1,(int)left+1];
    }
    LMVSquidPanelShapeReason=reason;
    // Never a signature taken while the panel is still assembling (no icons yet).
    if(LMVSquidPanelSignatureIcons(sig)!=NSNotFound && LMVSquidPanelSignatureIcons(sig)>0)
        LMVSquidPanelRememberSlot(slot,sig);
    return slot;
}
// 1.50: the manual half of the identity memory - "认领刚用过的面板". Nothing in the
// content says which gesture opened a panel, so the user gets the last word: the
// panel they were just looking at (and not one from too long ago to be what they
// mean) is bound to the slot they pick, and the signature's old binding is dropped
// in the same move, so a wrong automatic claim is corrected rather than shadowed.
static void LMVSquidPanelBindLastSeen(NSInteger slot) {
    if(slot<0 || slot>=LMVSquidPanelSlotCount)return;
    NSTimeInterval age=LMVSquidPanelLastSeen>0?(CACurrentMediaTime()-LMVSquidPanelLastSeen):-1;
    BOOL fresh=age>=0 && age<900;
    NSString *sig=LMVSquidPanelShapeSig;
    if(fresh && [sig isKindOfClass:NSString.class] && sig.length && ![sig isEqualToString:@"none"])
        LMVSquidPanelRememberSlot(slot,sig);
    if(LMVDiagnosticsEnabled.load()) {
        NSString *line=[NSString stringWithFormat:@"squid-panel-claim slot=%d gesture=%@ sig=%@ age=%.0fs applied=%d",
            (int)slot+1,LMVSquidPanelSlotTitles()[slot],sig.length?sig:@"none",age<0?0:age,(int)fresh];
        LMVDiagnostic(line);
    }
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
    // 1.44/1.45: the panels are INDEPENDENT - there is no fallback between them. A
    // slot left empty means that panel simply gets no video: it keeps its original
    // look and stays silent (detach also stands the shared audio channel down, so
    // nothing is heard). 1.50: four slots, one per gesture side/shape.
    NSInteger slot=LMVSquidPanelResolveSlot(card,window);
    // A live panel is also the one the "认领刚用过的面板" row binds later on, so keep
    // its signature (and when it was last seen) around.
    LMVSquidPanelLastSeen=CACurrentMediaTime();
    // 1.46/1.50: "对调上滑 / 上上滑素材" - for the case where the very first content test
    // guessed the two panels of a side the other way round. It flips which material
    // each shape plays WITHIN its side (0<->1, 2<->3) and leaves the identity memory
    // above untouched (that records the panel, this picks the material).
    NSInteger wantSlot=slot;
    if(LMVSquidPanelSwapShapes)wantSlot=slot^1;
    NSString *wantPath=LMVSquidPanelSlotPaths[wantSlot];
    NSString *wantRevision=LMVSquidPanelSlotRevisions[wantSlot];
    if(!wantPath.length || !wantRevision.length) {
        // 1.45: say so out loud, once per state change - "this panel has no material"
        // is otherwise indistinguishable from "the channel is broken" in a log.
        if(LMVDiagnosticsEnabled.load()) {
            NSString *empty=[NSString stringWithFormat:@"squid-panel slot=%d empty=%@ (no video, by design)",
                (int)wantSlot+1,LMVSquidPanelSlotTitles()[wantSlot]];
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
        NSString *status=[NSString stringWithFormat:@"squid-panel win=%@ %.0fx%.0f slot=%d gesture=%@ play=%@ why=%@ sig=%@ mode=%@ card=%@@%.0f,%.0f,%.0f,%.0f ptr=%p vis=%.0f live=%d host=%.0fx%.0f",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            (int)slot+1,LMVSquidPanelSlotTitles()[slot],LMVSquidPanelSlotTitles()[wantSlot],
            LMVSquidPanelShapeReason,LMVSquidPanelShapeSig,
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
        // 1.50: four slots - right 上滑/上上滑 and left 上滑/上上滑 - each with its own
        // material, plus the 对调 switch and the claim the user asked for in Settings.
        NSArray *keys=LMVSquidPanelSlotKeys();
        for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
            LMVSquidPanelSlotPaths[i]=LMVCCSelectedPath(keys[i]);
            LMVSquidPanelSlotRevisions[i]=LMVLockVideoRevision(LMVSquidPanelSlotPaths[i]);
        }
        // 1.46/1.50: "对调上滑 / 上上滑素材" - see wantSlot in -update.
        id swap=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("SquidPanelSwapShapes"),kLMVPrefsID);
        LMVSquidPanelSwapShapes=[swap isKindOfClass:NSNumber.class] && [swap boolValue];
        // 1.47: the content signature each slot was last seen as. 1.50: one key per
        // SLOT; the 1.48 pair (SquidPanelTallSig2/SquidPanelShortSig2) seeds the two
        // right-hand slots so a device that already knew its right panels keeps that
        // knowledge instead of starting from scratch.
        NSArray *sigKeys=LMVSquidPanelSlotSigKeys();
        NSArray *seeds=@[@"SquidPanelTallSig2",@"SquidPanelShortSig2"];
        for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
            id value=(__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)sigKeys[i],kLMVPrefsID);
            if(![value isKindOfClass:NSString.class] && i<seeds.count)
                value=(__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)seeds[i],kLMVPrefsID);
            LMVSquidPanelSlotSigs[i]=[value isKindOfClass:NSString.class]?value:nil;
        }
        // 1.50: "认领刚用过的面板" - both settings surfaces write the slot (1-4) plus a
        // token; the first refresh that sees a new token binds the panel the user was
        // just looking at to that slot. That is the one thing the runtime cannot work
        // out by itself (nothing in the content says which gesture opened the panel).
        id claim=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("SquidPanelClaimSlot"),kLMVPrefsID);
        id token=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("SquidPanelClaimToken"),kLMVPrefsID);
        NSString *tokenText=[token isKindOfClass:NSString.class]?token:(token?[token description]:nil);
        if(tokenText.length && ![tokenText isEqualToString:LMVSquidPanelClaimToken]) {
            LMVSquidPanelClaimToken=[tokenText copy];
            NSInteger claimed=[claim isKindOfClass:NSNumber.class]?[claim integerValue]-1:NSNotFound;
            if(claimed>=0 && claimed<LMVSquidPanelSlotCount) LMVSquidPanelBindLastSeen(claimed);
        }
    }
    LMVSquidPanelRetune();
    BOOL anySlot=NO;
    for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++)
        if(LMVSquidPanelSlotPaths[i].length && LMVSquidPanelSlotRevisions[i].length)anySlot=YES;
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
