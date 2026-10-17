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
// 1.54: how the four slots are FILLED. Bumped whenever the rule that decides which
// slot a brand-new panel belongs to changes, so a device upgrades by forgetting the
// slots it wrote under the old rule instead of trusting an order that is now wrong.
#define LMVSquidPanelLearnGeneration 3
static NSString *LMVSquidPanelSlotPaths[LMVSquidPanelSlotCount];
static NSString *LMVSquidPanelSlotRevisions[LMVSquidPanelSlotCount];
// The content signature each slot was last seen as - the 1.47/1.48 identity memory,
// now one entry per slot instead of one per shape.
static NSString *LMVSquidPanelSlotSigs[LMVSquidPanelSlotCount];
// 1.55: and EVERY signature that slot has ever been seen as, newest last, at most
// LMVSquidPanelSlotSignatureMemory of them. A slot that only remembered one signature
// lost the panel the moment the user changed its LAYOUT - the report that started this
// release: editing a panel changes its icon count, the signature no longer matched, and
// the panel was treated as a stranger from then on. Keeping the older signatures means a
// panel that has been edited is still itself, and an edit that is undone is recognised
// too. The set is what identifies a slot; LMVSquidPanelSlotSigs[] stays the NEWEST one,
// which is what the comparisons below use.
#define LMVSquidPanelSlotSignatureMemory 4
static NSArray *LMVSquidPanelSlotSigSets[LMVSquidPanelSlotCount];
// 1.53: and how tall each of them was - the pair's own ordering evidence (see
// LMVSquidPanelOrderPair) - kept SEPARATELY FOR EACH ORIENTATION, because a card is
// 435pt tall in portrait and 340pt in landscape: comparing a portrait height against a
// landscape one is what produced `pair=350/340` in the 1.52 log and swapped a correct
// pair. Never part of the signature: a panel the user edits keeps the slot it owns.
// Index 0 = portrait, index 1 = landscape; 0 means "not seen in that orientation yet".
static CGFloat LMVSquidPanelSlotHeights[LMVSquidPanelSlotCount][2];
// 1.54: when BOTH sides hold exactly one panel, the unknown one is the partner of the
// side that was seen most recently - a user sets a side up in one go (右一 then 右二),
// so the pair that is still open is the one that was touched last.
static NSTimeInterval LMVSquidPanelSlotSeen[LMVSquidPanelSlotCount];
// 1.52: the one repair the runtime cannot do by itself - see LMVSquidPanelForgetAll.
static NSString *LMVSquidPanelResetToken;
static NSTimer *LMVSquidPanelTimer;
// The user's material selection, by slot.
static NSArray *LMVSquidPanelSlotKeys(void) {
    return @[@"SquidPanelVideo",@"SquidPanel2Video",@"SquidPanel3Video",@"SquidPanel4Video"];
}
static NSArray *LMVSquidPanelSlotSigKeys(void) {
    return @[@"SquidPanelSlot1Sig",@"SquidPanelSlot2Sig",@"SquidPanelSlot3Sig",@"SquidPanelSlot4Sig"];
}
static NSArray *LMVSquidPanelSlotHeightKeys(void) {
    return @[@"SquidPanelSlot1H",@"SquidPanelSlot2H",@"SquidPanelSlot3H",@"SquidPanelSlot4H"];
}
// The gesture each slot belongs to, for the diagnostics and the claim sheet.
static NSArray *LMVSquidPanelSlotTitles(void) {
    return @[@"右一·右上滑",@"右二·右上上滑",@"左一·左上滑",@"左二·左上上滑"];
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
// 1.53: the signature is `icons{n}|pc{0/1}` - the page-control width is GONE.
//
// The 1.52 log killed it: the SAME right 上滑 panel signed `icons44|pc1|dots55` in
// portrait and `icons44|pc1|dots38` in landscape, so every rotation looked like a
// brand-new panel, and "上滑 in landscape" promptly got parked on 上上滑. Only the
// things that are the same in both orientations may be in the signature: how many
// icons the panel carries, and whether it has a page control at all.
static NSString *LMVSquidPanelContentSignature(UIView *card,UIWindow *window) {
    if(!card)return @"none";
    NSUInteger icons=LMVSquidPanelIconCount(card);
    UIPageControl *page=LMVSquidPanelPageControl(card,window);
    return [NSString stringWithFormat:@"icons%lu|pc%d",(unsigned long)icons,page?1:0];
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
// first sight, and a pair that was written wrong is cleared by "重置面板识别".
// Write a slot's signature set out, and keep the newest signature at the front of the
// comparisons. The stored order is newest-last, so the array is trimmed from the front.
static void LMVSquidPanelStoreSlot(NSInteger slot,NSArray *set) {
    NSArray *keys=LMVSquidPanelSlotSigKeys();
    if(!set.count) {
        CFPreferencesSetAppValue((__bridge CFStringRef)keys[slot],NULL,kLMVPrefsID);
        LMVSquidPanelSlotSigSets[slot]=nil;LMVSquidPanelSlotSigs[slot]=nil;
        return;
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)keys[slot],(__bridge CFArrayRef)set,kLMVPrefsID);
    LMVSquidPanelSlotSigSets[slot]=[set copy];
    LMVSquidPanelSlotSigs[slot]=set.lastObject;
}
// 1.55: drop every signature a slot knew - used by 重置面板识别 and by the upgrade.
static void LMVSquidPanelSigSetsClear(NSInteger slot) {
    if(slot<0 || slot>=LMVSquidPanelSlotCount)return;
    CFPreferencesSetAppValue((__bridge CFStringRef)LMVSquidPanelSlotSigKeys()[slot],NULL,kLMVPrefsID);
    LMVSquidPanelSlotSigSets[slot]=nil;LMVSquidPanelSlotSigs[slot]=nil;
}
// 1.55: a signature joins the slot it was seen as - it does NOT push the older ones out,
// unless another slot still claims it (one signature can only belong to one panel).
static void LMVSquidPanelRememberSlot(NSInteger slot,NSString *sig) {
    if(slot<0 || slot>=LMVSquidPanelSlotCount)return;
    if(![sig isKindOfClass:NSString.class] || !sig.length || [sig isEqualToString:@"none"])return;
    for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
        if(i==slot)continue;
        NSMutableArray *set=[(LMVSquidPanelSlotSigSets[i]?:@[]) mutableCopy];
        if(![set containsObject:sig])continue;
        [set removeObject:sig];
        LMVSquidPanelStoreSlot(i,set);
        if(!set.count) {
            CFPreferencesSetAppValue((__bridge CFStringRef)LMVSquidPanelSlotHeightKeys()[i],NULL,kLMVPrefsID);
            LMVSquidPanelSlotSeen[i]=0;
            LMVSquidPanelSlotHeights[i][0]=0;LMVSquidPanelSlotHeights[i][1]=0;
        }
    }
    NSMutableArray *set=[(LMVSquidPanelSlotSigSets[slot]?:@[]) mutableCopy];
    [set removeObject:sig];
    [set addObject:sig];
    while(set.count>(NSUInteger)LMVSquidPanelSlotSignatureMemory)[set removeObjectAtIndex:0];
    LMVSquidPanelStoreSlot(slot,set);
    CFPreferencesAppSynchronize(kLMVPrefsID);
}
// 1.51: which of the four materials this panel plays - no user step required.
//
// (a) A signature seen before settles it outright: the panel keeps its material when
//     the user edits it, because the record is keyed on a signature that carries no
//     height and no width.
// (b) A signature not seen before belongs to the side that has learned NOTHING yet.
//     The right-hand pair is configured first on every device so far (it is the one
//     the user set up before asking for the left), so an unknown panel goes to the
//     left, and the mirror case goes to the right. Both sides learned -> the panel
//     was edited, and the closest icon count decides (the 1.48 rule).
// (c) WITHIN a side the two panels order THEMSELVES, which is what makes this
//     automatic: 上滑 is the taller panel of the pair, icon count breaking a tie (the
//     device logs: left 上滑 icons8/180pt against left 上上滑 icons4/95pt, right
//     上滑 icons50/435pt against right 上上滑 icons29/350pt). So the first of the two
//     to be seen only needs a rough guess - the second one corrects the pair, and a
//     pair whose recorded heights contradict its slots is swapped on sight. The user
//     editing a panel's height (they did: "我把上上滑改成一样高") cannot break this,
//     because equal heights fall through to the icon count and an already-learned
//     signature never re-enters this rule at all.
// (d) Nothing to compare yet (the very first panel of a side): the page control, then
//     the absolute height, then "tall".
static BOOL LMVSquidPanelLandscape(UIWindow *window) {
    CGRect bounds=window.bounds;
    return CGRectGetWidth(bounds)>CGRectGetHeight(bounds);
}
// The recorded height of a slot in the orientation the panel is currently being seen in.
static CGFloat LMVSquidPanelHeightInOrientation(NSInteger slot,BOOL landscape) {
    if(slot<0 || slot>=LMVSquidPanelSlotCount)return 0;
    return LMVSquidPanelSlotHeights[slot][landscape?1:0];
}
static void LMVSquidPanelNoteHeight(NSInteger slot,CGFloat height,BOOL landscape) {
    if(slot<0 || slot>=LMVSquidPanelSlotCount || !(height>0))return;
    NSUInteger axis=landscape?1:0;
    if(fabs(LMVSquidPanelSlotHeights[slot][axis]-height)<1)return;
    LMVSquidPanelSlotHeights[slot][axis]=height;
    NSArray *pair=@[@(LMVSquidPanelSlotHeights[slot][0]),@(LMVSquidPanelSlotHeights[slot][1])];
    CFPreferencesSetAppValue((__bridge CFStringRef)LMVSquidPanelSlotHeightKeys()[slot],(__bridge CFArrayRef)pair,kLMVPrefsID);
    CFPreferencesAppSynchronize(kLMVPrefsID);
}
// Move a remembered panel to the other slot of its pair, heights included.
static void LMVSquidPanelMoveSlot(NSInteger from,NSInteger to) {
    if(from==to || from<0 || from>=LMVSquidPanelSlotCount || to<0 || to>=LMVSquidPanelSlotCount)return;
    NSArray *set=LMVSquidPanelSlotSigSets[from];
    if(!set.count)return;
    CGFloat portrait=LMVSquidPanelSlotHeights[from][0],landscape=LMVSquidPanelSlotHeights[from][1];
    CFPreferencesSetAppValue((__bridge CFStringRef)LMVSquidPanelSlotSigKeys()[from],NULL,kLMVPrefsID);
    CFPreferencesSetAppValue((__bridge CFStringRef)LMVSquidPanelSlotHeightKeys()[from],NULL,kLMVPrefsID);
    NSTimeInterval seen=LMVSquidPanelSlotSeen[from];
    LMVSquidPanelStoreSlot(from,nil);LMVSquidPanelSlotSeen[from]=0;
    LMVSquidPanelSlotHeights[from][0]=0;LMVSquidPanelSlotHeights[from][1]=0;
    for(NSString *sig in set)LMVSquidPanelRememberSlot(to,sig);
    LMVSquidPanelSlotSeen[to]=seen;
    if(portrait>0)LMVSquidPanelNoteHeight(to,portrait,NO);
    if(landscape>0)LMVSquidPanelNoteHeight(to,landscape,YES);
}
// 上滑 must be the taller of a side's two panels, IN THE SAME ORIENTATION. Returns 0
// when the record agrees (or cannot say), 1 when it had to swap them.
static int LMVSquidPanelOrderPair(NSInteger tallSlot,NSInteger shortSlot,BOOL landscape) {
    if(!LMVSquidPanelSlotSigs[tallSlot].length || !LMVSquidPanelSlotSigs[shortSlot].length)return 0;
    CGFloat tallHeight=LMVSquidPanelHeightInOrientation(tallSlot,landscape);
    CGFloat shortHeight=LMVSquidPanelHeightInOrientation(shortSlot,landscape);
    int order=0;
    if(tallHeight>0 && shortHeight>0 && fabs(tallHeight-shortHeight)>4) order=(shortHeight>tallHeight)?-1:1;
    else {
        // Different orientations (or a tie): the icon count is orientation-proof, so it
        // is the only thing left that may decide - and it only decides when it is a
        // clear call, never on a coin flip.
        NSUInteger ti=LMVSquidPanelSignatureIcons(LMVSquidPanelSlotSigs[tallSlot]);
        NSUInteger si=LMVSquidPanelSignatureIcons(LMVSquidPanelSlotSigs[shortSlot]);
        if(ti!=NSNotFound && si!=NSNotFound && ti!=si) order=(si>ti)?-1:1;
    }
    if(order>=0)return 0;                 // tall slot holds the taller (or a tie): fine
    NSString *sig=LMVSquidPanelSlotSigs[tallSlot];
    CGFloat portrait=LMVSquidPanelSlotHeights[tallSlot][0],landscapeHeight=LMVSquidPanelSlotHeights[tallSlot][1];
    CFPreferencesSetAppValue((__bridge CFStringRef)LMVSquidPanelSlotSigKeys()[tallSlot],NULL,kLMVPrefsID);
    CFPreferencesSetAppValue((__bridge CFStringRef)LMVSquidPanelSlotHeightKeys()[tallSlot],NULL,kLMVPrefsID);
    LMVSquidPanelSlotSigs[tallSlot]=nil;
    LMVSquidPanelSlotHeights[tallSlot][0]=0;LMVSquidPanelSlotHeights[tallSlot][1]=0;
    LMVSquidPanelMoveSlot(shortSlot,tallSlot);
    LMVSquidPanelRememberSlot(shortSlot,sig);
    if(portrait>0)LMVSquidPanelNoteHeight(shortSlot,portrait,NO);
    if(landscapeHeight>0)LMVSquidPanelNoteHeight(shortSlot,landscapeHeight,YES);
    return 1;
}
static NSInteger LMVSquidPanelResolveSlot(UIView *card,UIWindow *window) {
    if(!card)return 0;
    NSString *sig=LMVSquidPanelContentSignature(card,window);
    LMVSquidPanelShapeSig=sig;
    CGRect cardFrame=[card convertRect:card.bounds toView:window];
    CGFloat height=cardFrame.size.height;
    BOOL landscape=LMVSquidPanelLandscape(window);
    for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
        // 1.55: ANY signature this slot has ever been seen as identifies it, so an edited
        // layout does not turn the panel into a stranger.
        if(![LMVSquidPanelSlotSigSets[i] containsObject:sig])continue;
        LMVSquidPanelSlotSeen[i]=CACurrentMediaTime();
        if(![sig isEqualToString:LMVSquidPanelSlotSigs[i]]) {
            LMVSquidPanelRememberSlot(i,sig);   // keep the newest one at the front
            LMVSquidPanelSlotSeen[i]=CACurrentMediaTime();
        }
        LMVSquidPanelNoteHeight(i,height,landscape);
        // (c) the pair self-heals: an inverted record is swapped where it is noticed.
        NSInteger tallOfPair=(i<2)?0:2, shortOfPair=(i<2)?1:3;
        NSString *reason=[NSString stringWithFormat:@"sig-slot%d",(int)i+1];
        if(LMVSquidPanelOrderPair(tallOfPair,shortOfPair,landscape)>0) {
            LMVSquidPanelShapeReason=[reason stringByAppendingString:@"+pair-swapped"];
            return ([sig isEqualToString:LMVSquidPanelSlotSigs[tallOfPair]] || [sig isEqualToString:LMVSquidPanelSlotSigs[shortOfPair]])?
                (LMVSquidPanelSlotSigs[tallOfPair].length && [sig isEqualToString:LMVSquidPanelSlotSigs[tallOfPair]]?tallOfPair:shortOfPair):i;
        }
        LMVSquidPanelShapeReason=reason;
        return i;
    }
    // 1.54: an unknown panel takes the NEXT EMPTY SLOT, in 右一 → 右二 → 左一 → 左二
    // order, and the PAIR it lands in then orders ITSELF - the taller one is 上滑, in
    // the orientation it was seen in. Nothing guesses which SIDE a panel is on.
    //
    // Guessing the side is what kept breaking this. 1.53 sent an unknown panel to "the
    // side that has learned nothing yet", so 右二 - arriving while the left side was
    // still empty - was recorded as 左二, and from then on every later panel was placed
    // relative to that wrong record, which is why 右二 and 左一 came out swapped. A
    // fixed slot order puts the first four panels the user opens exactly where they
    // belong, and a pair that is opened the other way round (右二 before 右一) sorts
    // itself out the moment the second one appears.
    // 1.55: before a new signature is allowed to take an empty slot, check whether it is
    // a KNOWN panel whose layout was edited. An edit changes the icon count - which IS the
    // signature - but usually leaves the panel's HEIGHT alone, and two of the four panels
    // rarely share a height to within 2pt. Without this, editing one of three learned
    // panels made it look like the fourth one, which was still empty.
    NSInteger match=NSNotFound; NSUInteger matches=0;
    for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
        if(!LMVSquidPanelSlotSigs[i].length)continue;
        CGFloat recorded=LMVSquidPanelHeightInOrientation(i,landscape);
        if(recorded>0 && height>0 && fabs(height-recorded)<=2) { if(!matches)match=i; matches++; }
    }
    if(matches==1) {
        LMVSquidPanelShapeReason=[NSString stringWithFormat:@"edited-height-slot%d",(int)match+1];
        LMVSquidPanelRememberSlot(match,sig);
        LMVSquidPanelSlotSeen[match]=CACurrentMediaTime();
        LMVSquidPanelNoteHeight(match,height,landscape);
        return match;
    }
    NSInteger freeSlot=NSNotFound;
    for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
        if(!LMVSquidPanelSlotSigs[i].length){freeSlot=i;break;}
    }
    if(freeSlot==NSNotFound) {
        // 1.55: every slot is taken and this matched none of them, so the panel was
        // EDITED - most often its layout, which is exactly what changes the icon count
        // the signature is built on. Which slot it is has to be read off what an edit
        // does NOT usually change: the panel's HEIGHT in this orientation first, then
        // the icon count, both as one score.
        //
        // Scoring beats the old "closest icon count" rule, because a layout edit can
        // move the icon count a long way (右一 carries 44 icons, 左二 only 4) while the
        // height stays put - and an edit that changes the height alone leaves the icon
        // count alone. Only when the winner is CLEAR is the new signature remembered;
        // a coin flip is played but not stored, so a wrong guess cannot poison a slot.
        NSUInteger icons=LMVSquidPanelSignatureIcons(sig);
        NSInteger best=NSNotFound,second=NSNotFound;
        CGFloat bestScore=CGFLOAT_MAX,secondScore=CGFLOAT_MAX;
        for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
            if(!LMVSquidPanelSlotSigs[i].length)continue;
            NSUInteger d=LMVSquidPanelSignatureDistance(icons,LMVSquidPanelSlotSigs[i]);
            if(d==NSNotFound)continue;
            CGFloat recorded=LMVSquidPanelHeightInOrientation(i,landscape);
            CGFloat gap=(recorded>0 && height>0)?fabs(height-recorded):220;
            CGFloat score=gap+(CGFloat)d*6;
            if(score<bestScore){secondScore=bestScore;second=best;bestScore=score;best=i;}
            else if(score<secondScore){secondScore=score;second=i;}
        }
        if(best!=NSNotFound) {
            BOOL clear=(second==NSNotFound) || (secondScore-bestScore>20);
            LMVSquidPanelShapeReason=[NSString stringWithFormat:@"edited-%@-slot%d",clear?@"adopted":@"unclear",(int)best+1];
            if(clear)LMVSquidPanelRememberSlot(best,sig);
            LMVSquidPanelSlotSeen[best]=CACurrentMediaTime();
            LMVSquidPanelNoteHeight(best,height,landscape);
            return best;
        }
        freeSlot=0;
    }
    NSString *reason=[NSString stringWithFormat:@"new@slot%d",(int)freeSlot+1];
    // Never a signature taken while the panel is still assembling (no icons yet).
    if(LMVSquidPanelSignatureIcons(sig)!=NSNotFound && LMVSquidPanelSignatureIcons(sig)>0)
        LMVSquidPanelRememberSlot(freeSlot,sig);
    LMVSquidPanelNoteHeight(freeSlot,height,landscape);
    NSInteger tallOfPair=(freeSlot<2)?0:2, shortOfPair=(freeSlot<2)?1:3;
    if(LMVSquidPanelOrderPair(tallOfPair,shortOfPair,landscape)>0)
        reason=[reason stringByAppendingString:@"+pair-swapped"];
    NSInteger finalSlot=freeSlot;
    for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
        if([LMVSquidPanelSlotSigSets[i] containsObject:sig]){finalSlot=i;break;}
    }
    LMVSquidPanelSlotSeen[finalSlot]=CACurrentMediaTime();
    LMVSquidPanelShapeReason=reason;
    return finalSlot;
}

// 1.56: the panel's own subtree, printed with the things a plugin uses to name its own
// views - tag, accessibilityIdentifier, restorationIdentifier and any label text.
//
// Why this exists: every identity tried so far was DERIVED FROM THE PANEL'S CONTENT, and
// the user changes the content (adding an icon, swapping an app), so every one of them
// broke the moment they edited a panel. A fixed name has to come from something the plugin
// wrote itself and the user cannot touch, and this log is how it gets found: the next
// device log will show, node by node, whether such a name is on the card at all.
static void LMVSquidPanelIdentityTree(UIView *view,NSUInteger depth,NSMutableString *out,NSUInteger *nodes) {
    if(!view || *nodes>160)return;
    (*nodes)++;
    CGRect frame=view.frame;
    [out appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f",NSStringFromClass(view.class),
        frame.origin.x,frame.origin.y,frame.size.width,frame.size.height];
    if(view.tag)[out appendFormat:@"#%ld",(long)view.tag];
    // accessibilityIdentifier and restorationIdentifier are UIView's own public
    // properties; `text` is not, so it is asked for only where it really exists.
    if(view.accessibilityIdentifier.length)[out appendFormat:@"aid=%@",view.accessibilityIdentifier];
    if(view.restorationIdentifier.length)[out appendFormat:@"rid=%@",view.restorationIdentifier];
    if([view respondsToSelector:NSSelectorFromString(@"text")]) {
        id text=[view valueForKey:@"text"];
        if([text isKindOfClass:NSString.class] && [text length])[out appendFormat:@"txt=%@",text];
    }
    if(depth>=6 || view.subviews.count==0)return;
    [out appendString:@"{"];
    NSUInteger n=0;
    for(UIView *child in view.subviews) {
        if(n++>=8){[out appendString:@"…"];break;}
        LMVSquidPanelIdentityTree(child,depth+1,out,nodes);
        [out appendString:@","];
    }
    [out appendString:@"}"];
}
// 1.56: where the gesture plugin itself keeps its configuration.
//
// A panel's content is the user's to change, so no identity derived from it can hold. The
// one thing that cannot change is the plugin's OWN record of its four gestures, which is
// a plist somewhere in the preferences directory. This looks for it: read-only, once per
// session, file names and top-level keys only, so no gesture data is logged. The report
// tells us where to read a fixed gesture name from - the 1.57 rule.
static void LMVSquidPanelScanGesturePrefs(void) {
    static BOOL done=NO;
    if(done)return;
    done=YES;
    if(!LMVDiagnosticsEnabled.load())return;
    // 1.60: the plugin is SquidForce - the 1.59 log showed the panel being built with
    // initWithActivityItems:applicationActivities:imageSize:location:, and the only
    // SquidForce file 1.56 turned up was com.squidforce.hammerit.clip. Guessing at file
    // NAMES was the mistake: it matched a pile of Apple plists (duetactivityscheduler,
    // activityawardsd) and missed the plugin's own. Every com.squidforce.* file is listed
    // now, each with a peek at its structure, because that file is the one place a fixed
    // gesture number can live - the plugin writes it, and it follows the user's edits
    // instead of breaking on them.
    // 1.61: the roots carry a tag now, so a file that turns up also says WHERE it was
    // found (jbprefs present means a rootless device) - and the tweak's own bundle prefix
    // joins the needles: the gesture tweak is SquidGesture Pro (com.lclrc.squidgesturepro,
    // by SquidForce - the SF in SFActivityPanelView), so its settings file would be
    // com.lclrc.squidgesturepro.plist.
    NSArray *roots=@[@[@"prefs",@"/var/mobile/Library/Preferences"],
                     @[@"jbprefs",@"/var/jb/var/mobile/Library/Preferences"],
                     @[@"lib",@"/var/mobile/Library"],
                     @[@"userprefs",@"/User/Library/Preferences"]];
    NSMutableString *report=[NSMutableString new];
    NSUInteger files=0;
    for(NSArray *pair in roots) {
        NSString *root=pair[1];
        NSArray *names=[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil];
        if(!names.count)continue;
        for(NSString *name in names) {
            if(files>=12)break;
            NSString *lower=name.lowercaseString;
            if(![lower containsString:@".plist"])continue;
            if(![lower hasPrefix:@"com.squidforce."] && ![lower containsString:@"squid"] &&
               ![lower containsString:@"lclrc"] &&
               ![lower containsString:@"sfactivity"] && ![lower containsString:@"sgpanel"])continue;
            files++;
            id plist=[NSDictionary dictionaryWithContentsOfFile:[root stringByAppendingPathComponent:name]];
            if(![plist isKindOfClass:NSDictionary.class]) {
                [report appendFormat:@" %@(unreadable)",name];
                continue;
            }
            NSArray *keys=[plist allKeys];
            NSMutableString *peek=[NSMutableString new];
            NSUInteger shown=0;
            for(NSString *key in keys) {
                if(shown++>=8)break;
                id value=plist[key];
                NSString *shape=nil;
                if([value isKindOfClass:NSArray.class]) {
                    NSArray *array=(NSArray *)value;
                    id first=array.firstObject;
                    NSArray *sub=[first isKindOfClass:NSDictionary.class]?[first allKeys]:@[];
                    shape=[NSString stringWithFormat:@"[%lu:%@]",(unsigned long)array.count,
                        [[sub subarrayWithRange:NSMakeRange(0,MIN(sub.count,6))] componentsJoinedByString:@"|"]];
                } else if([value isKindOfClass:NSDictionary.class]) {
                    NSArray *sub=[value allKeys];
                    shape=[NSString stringWithFormat:@"{%lu:%@}",(unsigned long)sub.count,
                        [[sub subarrayWithRange:NSMakeRange(0,MIN(sub.count,6))] componentsJoinedByString:@"|"]];
                } else if([value isKindOfClass:NSString.class]) {
                    shape=[value length]>24?[value substringToIndex:24]:value;
                } else {
                    shape=NSStringFromClass([value class]);
                }
                [peek appendFormat:@" %@=%@",key,shape];
            }
            [report appendFormat:@" %@=%@(%lu)%@",pair[0],name,(unsigned long)keys.count,peek];
        }
    }
    LMVDiagnostic([NSString stringWithFormat:@"squid-gesture-prefs%@",report.length?report:@" none-found"]);
}
// 1.62: WHERE the plugin keeps its data. The 1.60/1.61 scans proved the gesture config is
// NOT a plist in Preferences (com.lclrc.squidgesturepro.plist is not there - it would sort
// between com.junzai and com.lenglengyu and does not) and NOT a directory under
// /var/mobile/Library (nothing between SpringBoard/ and StatusKit/). The device is rootful
// (no /var/jb entries ever showed). So the listing is widened to the remaining places a
// tweak keeps data - /Library itself, the tweak defaults' own folder, Caches, SpringBoard's
// folder - and the caps go up, because the 1.61 prefs listing stopped at com.simon and
// everything after it (where com.squidforce.* lives) was never shown.
static void LMVSquidPanelListPaths(void) {
    static BOOL done=NO;
    if(done)return;
    done=YES;
    if(!LMVDiagnosticsEnabled.load())return;
    NSArray *roots=@[
        @[@"lib",@"/var/mobile/Library",@(80)],
        @[@"prefs",@"/var/mobile/Library/Preferences",@(100)],
        @[@"appsup",@"/var/mobile/Library/Application Support",@(30)],
        @[@"caches",@"/var/mobile/Library/Caches",@(30)],
        @[@"sb",@"/var/mobile/Library/SpringBoard",@(30)],
        @[@"rootlib",@"/Library",@(40)],
        @[@"plroot",@"/Library/PreferenceLoader/Preferences",@(20)],
    ];
    NSMutableString *report=[NSMutableString new];
    for(NSArray *entry in roots) {
        NSString *root=entry[1];
        NSUInteger cap=[entry[2] unsignedIntegerValue];
        NSArray *names=[NSFileManager.defaultManager contentsOfDirectoryAtPath:root error:nil];
        if(!names.count)continue;
        NSMutableArray *kept=[NSMutableArray array];
        for(NSString *name in names) {
            if(kept.count>=cap)break;
            if([name hasPrefix:@"."])continue;
            if([name.lowercaseString containsString:@"apple"])continue;
            BOOL dir=NO;
            NSString *entryName=name;
            if([NSFileManager.defaultManager fileExistsAtPath:[root stringByAppendingPathComponent:name] isDirectory:&dir] && dir)
                entryName=[entryName stringByAppendingString:@"/"];
            [kept addObject:entryName];
        }
        if(kept.count) {
            NSArray *sorted=[kept sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
            [report appendFormat:@" %@=%@",entry[0],[sorted componentsJoinedByString:@","]];
        }
    }
    LMVDiagnostic([NSString stringWithFormat:@"squid-paths%@",report.length?report:@" none-found"]);
}
// 1.62: the plugin's OWN image and every class in it. The 1.61 prefix listing proved the
// prefix idea useless: SG is shared with Apple's Mail intelligence classes (SGSuggestions*,
// SGMail*) and with SquidExtender's JS classes (SquidExtender.SKJS*), the cap filled with
// those, and the plugin's own classes - SGPanelWindow, SFActivityPanelView, both known from
// the panel chain - never even made the list. A class knows which image it was loaded from,
// and the image IS the plugin's own binary: so the image is found through a class that is
// certainly the plugin's, and then every class in that image is listed - the plugin's
// complete vocabulary, nothing from Apple, nothing from another tweak. Whichever class
// looks like the gesture model (or the preference manager) is what the next round reads.
static NSString *LMVSquidPanelPluginImage(void) {
    NSArray *known=@[@"SFActivityAction",@"SFActivityPanelView",@"SGPanelWindow"];
    for(NSString *name in known) {
        Class cls=NSClassFromString(name);
        if(!cls)continue;
        const char *image=class_getImageName(cls);
        if(image)return @(image);
    }
    return nil;
}
static void LMVSquidPanelListPluginClasses(void) {
    static BOOL done=NO;
    if(done)return;
    done=YES;
    if(!LMVDiagnosticsEnabled.load())return;
    NSString *image=LMVSquidPanelPluginImage();
    if(!image.length) {
        LMVDiagnostic(@"squid-plugin image=none classes=none");
        return;
    }
    unsigned total=0;
    Class *classes=objc_copyClassList(&total);
    NSMutableArray *own=[NSMutableArray array];
    if(classes) {
        for(unsigned i=0;i<total && own.count<60;i++) {
            const char *img=class_getImageName(classes[i]);
            if(img && [@(img) isEqualToString:image])[own addObject:@(class_getName(classes[i]))];
        }
        free(classes);
    }
    LMVDiagnostic([NSString stringWithFormat:@"squid-plugin image=%@ classes(%lu):%@",
        image,(unsigned long)own.count,own.count?[own componentsJoinedByString:@","]:@"none"]);
}
// case-insensitive substring search over a raw byte run - the pre-filter, so no string is
// built for the thousands of runs in a binary that hold nothing interesting.
static BOOL LMVRunContains(const uint8_t *p,NSUInteger n,const char *needle,BOOL fold) {
    NSUInteger m=strlen(needle);
    if(m>n)return NO;
    for(NSUInteger i=0;i+m<=n;i++) {
        BOOL ok=YES;
        for(NSUInteger j=0;j<m;j++) {
            int a=p[i+j],b=(uint8_t)needle[j];
            if(fold) { if(a>='A'&&a<='Z')a+=32; if(b>='A'&&b<='Z')b+=32; }
            if(a!=b) { ok=NO; break; }
        }
        if(ok)return YES;
    }
    return NO;
}
// 1.62: and the STRINGS of that image. The tweak has to name its storage somewhere, and a
// tweak's own binary is where that path is written down - the file scans cannot see a
// custom store, but the store's NAME is a literal in the code. The image is read once and
// every printable run that looks like a path (/var, .plist, /Library outside /System,
// Preferences, Documents, Caches) is printed: that is where the next round looks. Short
// runs naming the plugin itself (squid / gesture) are printed as well - they give the
// storage file's name and the config's key names. Read-only: the file is only ever read.
static void LMVSquidPanelPluginStrings(void) {
    static BOOL done=NO;
    if(done)return;
    done=YES;
    if(!LMVDiagnosticsEnabled.load())return;
    NSString *image=LMVSquidPanelPluginImage();
    NSData *data=image.length?[NSData dataWithContentsOfFile:image]:nil;
    if(!data.length) {
        LMVDiagnostic(@"squid-plugin-strings unreadable");
        return;
    }
    const uint8_t *bytes=(const uint8_t *)data.bytes;
    NSUInteger len=data.length;
    NSMutableArray *paths=[NSMutableArray array];
    NSMutableArray *keys=[NSMutableArray array];
    NSUInteger run=0;
    for(NSUInteger i=0;i<=len;i++) {
        uint8_t c=i<len?bytes[i]:0;
        if(c>=0x20 && c<0x7F) { run++; continue; }
        if(run>=6) {
            const uint8_t *p=bytes+i-run;
            BOOL system=LMVRunContains(p,run,"/System",NO)||LMVRunContains(p,run,"/usr/",NO);
            BOOL path=!system && paths.count<24 &&
                (LMVRunContains(p,run,"/var",NO)||LMVRunContains(p,run,".plist",NO)||
                 LMVRunContains(p,run,"/Library",NO)||LMVRunContains(p,run,"Preferences",NO)||
                 LMVRunContains(p,run,"Documents",NO)||LMVRunContains(p,run,"Caches",NO));
            BOOL key=keys.count<20 && run<=40 &&
                (LMVRunContains(p,run,"squid",YES)||LMVRunContains(p,run,"gesture",YES));
            if(path||key) {
                NSMutableString *text=[NSMutableString stringWithCapacity:run];
                for(NSUInteger k=0;k<run;k++)[text appendFormat:@"%c",p[k]];
                if(path)[paths addObject:text.length>90?[text substringToIndex:90]:text];
                else [keys addObject:text];
            }
        }
        run=0;
    }
    LMVDiagnostic([NSString stringWithFormat:@"squid-plugin-strings paths(%lu):%@",
        (unsigned long)paths.count,[paths componentsJoinedByString:@" ~ "]]);
    LMVDiagnostic([NSString stringWithFormat:@"squid-plugin-keys(%lu):%@",
        (unsigned long)keys.count,[keys componentsJoinedByString:@" ~ "]]);
}
// 1.57: what the panel's own objects say about themselves.
//
// The 1.56 device log gave the chain SFActivityPanelView > UIControl > SFActivityAction
// > UIView > SGPanelWindow. SFActivityAction is the gesture plugin's own object - the one
// place a FIXED name for the gesture could live, because the plugin creates it and the
// user never edits it (unlike the buttons inside, whose labels the user rewrites at
// will). This reads only identifier-shaped properties, and only where the getter really
// exists, so nothing with a side effect is ever called and no valueForKey is unguarded.
static void LMVSquidPanelDescribeIdentity(UIView *view,NSMutableString *out) {
    if(!view)return;
    Class cls=view.class;
    NSString *className=NSStringFromClass(cls);
    [out appendFormat:@" %@",className];
    // 1.58: UIKit's own layers (UIControl, UIView) carry dozens of properties that other
    // tweaks bolt on - adPrivacyData, pointerInteraction, cardSectionViewIdentifier, a
    // shared UUID every panel reports identically. They drown the two lines that matter,
    // so only the plugin's own classes are asked anything.
    if([className hasPrefix:@"UI"])return;
    [out appendString:@"["];
    unsigned count=0;
    objc_property_t *properties=class_copyPropertyList(cls,&count);
    NSMutableArray *names=[NSMutableArray array];
    for(unsigned i=0;i<count && names.count<24;i++)
        [names addObject:@(property_getName(properties[i]))];
    [out appendFormat:@"%@]",[names componentsJoinedByString:@","]];
    // 1.58: read EVERY property a layer has, not only the ones whose names look like
    // identifiers. The 1.57 log proved why: SFActivityAction carries `location` and
    // `title`, and `location` matched none of the guessed names, so it was never read -
    // the one field that looked most like a fixed gesture name stayed invisible. The
    // identifier-shaped ones are printed first so they survive the cap, then the rest.
    NSArray *interesting=@[@"ident",@"name",@"title",@"key",@"type",@"index",@"kind",
                           @"action",@"activity",@"gesture",@"panel",@"uuid",@"tag",
                           @"direction",@"edge",@"side",@"location",@"row",@"showing"];
    NSArray *skip=@[@"hash",@"superclass",@"description",@"debugDescription"];
    NSUInteger shown=0;
    for(NSUInteger pass=0;pass<2;pass++) {
        NSUInteger limit=pass?14:10;
        for(unsigned i=0;i<count && shown<limit;i++) {
            NSString *name=@(property_getName(properties[i]));
            if([skip containsObject:name])continue;
            NSString *lower=name.lowercaseString;
            BOOL hit=NO;
            for(NSString *needle in interesting)if([lower containsString:needle])hit=YES;
            if(pass ? hit : !hit)continue;          // pass 0: the likely ones, pass 1: the rest
            if(![view respondsToSelector:NSSelectorFromString(name)])continue;
            id value=[view valueForKey:name];
            NSString *text=nil;
            if([value isKindOfClass:NSString.class])text=value;
            else if([value isKindOfClass:NSNumber.class])text=[value stringValue];
            else if(!value)text=@"nil";
            else text=[NSString stringWithFormat:@"<%@>",NSStringFromClass([value class])];
            if(text.length>40)text=[text substringToIndex:40];
            shown++;
            [out appendFormat:@" %@=%@",name,text];
        }
    }
    free(properties);
    // 1.59: the properties were not enough - the 1.58 log shows location=2 on every one
    // of the four panels, so it is a constant, not a gesture number, and title is nil.
    // What a class keeps WITHOUT publishing it is next: the instance variables, and the
    // methods whose names look like they answer "which gesture is this?".
    unsigned ivarCount=0;
    Ivar *ivars=class_copyIvarList(cls,&ivarCount);
    if(ivars) {
        NSMutableArray *names=[NSMutableArray array];
        for(unsigned i=0;i<ivarCount && names.count<24;i++)
            [names addObject:@(ivar_getName(ivars[i]))];
        [out appendFormat:@"{i:%@}",[names componentsJoinedByString:@","]];
        // KVC finds the ivar behind a name even when there is no getter, so the private
        // fields can be read too - again only the identifier-shaped ones, and only the
        // values that come back as a string or a number.
        NSUInteger extra=0;
        for(unsigned i=0;i<ivarCount && extra<6;i++) {
            NSString *name=@(ivar_getName(ivars[i]));
            if(![name hasPrefix:@"_"])continue;
            NSString *bare=[name substringFromIndex:1];
            NSString *lower=bare.lowercaseString;
            BOOL hit=NO;
            for(NSString *needle in interesting)if([lower containsString:needle])hit=YES;
            if(!hit)continue;
            if(![view respondsToSelector:NSSelectorFromString(bare)] &&
               ![view respondsToSelector:NSSelectorFromString(name)])continue;
            id value=[view valueForKey:bare];
            NSString *text=nil;
            if([value isKindOfClass:NSString.class])text=value;
            else if([value isKindOfClass:NSNumber.class])text=[value stringValue];
            else if(!value)text=@"nil";
            else continue;
            if(text.length>40)text=[text substringToIndex:40];
            extra++;
            [out appendFormat:@" ~%@=%@",bare,text];
        }
        free(ivars);
    }
    // 1.61: the ACTIONS this panel is showing. The icon count was the signature so far
    // and it collides the moment two gestures carry the same number of actions; the
    // actions themselves are the finer signature - and SFActivityAction keeps them in
    // the _activityItems ivar the 1.59 log listed. Read straight through the ivar: no
    // getter is called, no KVC, nothing can throw, and the values are only printed.
    Ivar itemsIvar=class_getInstanceVariable(cls,"_activityItems");
    if(itemsIvar && ivar_getTypeEncoding(itemsIvar)[0]=='@') {
        id items=object_getIvar(view,itemsIvar);
        if([items isKindOfClass:NSArray.class] && [items count]) {
            NSMutableString *list=[NSMutableString new];
            NSUInteger shown=0;
            for(id item in items) {
                if(shown++>=8)break;
                NSString *text=nil;
                if([item isKindOfClass:NSDictionary.class]) {
                    NSDictionary *dict=(NSDictionary *)item;
                    NSMutableArray *pairs=[NSMutableArray array];
                    for(NSString *key in dict.allKeys) {
                        if(pairs.count>=6)break;
                        id value=dict[key];
                        NSString *piece=nil;
                        if([value isKindOfClass:NSString.class])piece=value;
                        else if([value isKindOfClass:NSNumber.class])piece=[value stringValue];
                        else piece=NSStringFromClass([value class]);
                        if(piece.length>16)piece=[piece substringToIndex:16];
                        [pairs addObject:[NSString stringWithFormat:@"%@=%@",key,piece]];
                    }
                    text=[pairs componentsJoinedByString:@"|"];
                } else {
                    text=[item description];
                    if(text.length>56)text=[text substringToIndex:56];
                }
                [list appendFormat:@" %@:%@",NSStringFromClass([item class]),text];
            }
            [out appendFormat:@"{a:%lu%@}",(unsigned long)[items count],list];
        }
    }
    unsigned methodCount=0;
    Method *methods=class_copyMethodList(cls,&methodCount);
    if(methods) {
        NSMutableArray *names=[NSMutableArray array];
        for(unsigned i=0;i<methodCount && names.count<12;i++) {
            NSString *name=@(sel_getName(method_getName(methods[i])));
            NSString *lower=name.lowercaseString;
            BOOL hit=NO;
            for(NSString *needle in interesting)if([lower containsString:needle])hit=YES;
            if(hit)[names addObject:name];
        }
        if(names.count)[out appendFormat:@"{m:%@}",[names componentsJoinedByString:@","]];
        free(methods);
    }
}
// 1.59: WHERE this panel sits. If the gesture plugin keeps all four of its panels alive
// under one parent - which is what a 1.44 device log suggested, each gesture carrying an
// on-screen and a parked copy of its own view - then the ORDER under that parent IS the
// gesture number: a fixed name that editing a layout can never touch. This prints the
// index, how many siblings there are, and the frame of each, so a parked copy (its y is
// past the bottom of the screen) can be told from the one on screen.
static void LMVSquidPanelDescribeSiblings(UIView *card,UIWindow *window,NSMutableString *out) {
    UIView *action=nil;
    for(UIView *node=card;node && node!=window;node=node.superview)
        if([NSStringFromClass(node.class) isEqualToString:@"SFActivityAction"]){action=node;break;}
    if(!action || !action.superview)return;
    NSArray *siblings=action.superview.subviews;
    NSUInteger index=[siblings indexOfObjectIdenticalTo:action];
    [out appendFormat:@" action=%p idx=%lu/%lu",(void *)action,(unsigned long)index,(unsigned long)siblings.count];
    NSUInteger shown=0;
    for(UIView *sib in siblings) {
        if(shown++>=8)break;
        CGRect frame=sib.frame;
        [out appendFormat:@" %@#%ld@%.0f,%.0f,%.0f,%.0f",NSStringFromClass(sib.class),(long)sib.tag,
            frame.origin.x,frame.origin.y,frame.size.width,frame.size.height];
    }
}
// The chain of class names from the window down to the card - short, so it can always be
// printed, and it is where a gesture-owned container would show up.
static NSString *LMVSquidPanelCardChain(UIView *card,UIWindow *window) {
    NSMutableArray *names=[NSMutableArray array];
    for(UIView *node=card;node && node!=window;node=node.superview)
        [names addObject:NSStringFromClass(node.class)];
    [names addObject:NSStringFromClass(window.class)];
    return [names componentsJoinedByString:@">"];
}
// 1.52: forget everything learned here - the four signatures and their heights.
//
// The pair ordering above can only sort a side while that side is HALF unknown, so a
// pair that was written wrong cannot be untangled by it. And a wrong pair really did
// happen: the 1.50 manual claim binds "the panel the user was last looking at", and
// the device log then showed the RIGHT 435pt panel recorded under 左边上上滑 - after
// which every new panel went through "both sides learned", i.e. the edited-panel rule,
// and the two real left panels were parked on 右边上上滑. One tap clears all four and
// the automatic rules take over again.
static void LMVSquidPanelForgetAll(void) {
    NSArray *heightKeys=LMVSquidPanelSlotHeightKeys();
    for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
        CFPreferencesSetAppValue((__bridge CFStringRef)heightKeys[i],NULL,kLMVPrefsID);
        LMVSquidPanelSigSetsClear(i);
        LMVSquidPanelSlotSeen[i]=0;
        LMVSquidPanelSlotHeights[i][0]=0;LMVSquidPanelSlotHeights[i][1]=0;
    }
    CFPreferencesAppSynchronize(kLMVPrefsID);
    LMVSquidPanelShapeSig=nil;LMVSquidPanelShapeReason=@"reset";
    if(LMVDiagnosticsEnabled.load())LMVDiagnostic(@"squid-panel-reset slots=4 (all four will be re-learned)");
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
        UIPageControl *pageControl=LMVSquidPanelPageControl(self.card,window);
        CGFloat dots=0;
        for(UIView *sub in pageControl.subviews) {
            if([NSStringFromClass(sub.class) containsString:@"PageControlContentView"]) {
                dots=MAX(sub.bounds.size.width,sub.bounds.size.height);break;
            }
        }
        BOOL landscapeNow=LMVSquidPanelLandscape(window);
        // 1.54: `slots=` is the whole memory in four digits - which of the four slots has
        // been learned - so a log line says on its own whether the next panel is going to
        // be matched (`sig-slotN`) or placed (`new@slotN`).
        // 1.56: the card's own subtree, once per card that really shows. This is the raw
        // material for a fixed identity - see LMVSquidPanelIdentityTree.
        if(live)LMVSquidPanelScanGesturePrefs();
        if(live)LMVSquidPanelListPaths();
        if(live)LMVSquidPanelListPluginClasses();
        if(live)LMVSquidPanelPluginStrings();
        static __weak UIView *lastTreeCard=nil;
        if(live && self.card && lastTreeCard!=self.card) {
            lastTreeCard=self.card;
            NSMutableString *tree=[NSMutableString new];NSUInteger nodes=0;
            LMVSquidPanelIdentityTree(self.card,0,tree,&nodes);
            LMVDiagnostic([NSString stringWithFormat:@"squid-panel-tree ptr=%p chain=%@ %@",
                (void *)self.card,LMVSquidPanelCardChain(self.card,window),tree]);
            // 1.57: the same chain, asked what it calls itself - see above.
            NSMutableString *identity=[NSMutableString new];
            NSUInteger level=0;
            for(UIView *node=self.card;node && node!=window && level<4;node=node.superview,level++)
                LMVSquidPanelDescribeIdentity(node,identity);
            LMVSquidPanelDescribeSiblings(self.card,window,identity);
            LMVDiagnostic([NSString stringWithFormat:@"squid-panel-identity ptr=%p%@",
                (void *)self.card,identity]);
        }
        NSString *status=[NSString stringWithFormat:@"squid-panel win=%@ %.0fx%.0f slot=%d gesture=%@ play=%@ why=%@ sig=%@ pc=%d dots=%.0f pair=%.0f/%.0f slots=%d%d%d%d seen=%.0fs mode=%@ card=%@@%.0f,%.0f,%.0f,%.0f ptr=%p vis=%.0f live=%d host=%.0fx%.0f",
            NSStringFromClass(window.class),bounds.size.width,bounds.size.height,
            (int)slot+1,LMVSquidPanelSlotTitles()[slot],LMVSquidPanelSlotTitles()[wantSlot],
            LMVSquidPanelShapeReason,LMVSquidPanelShapeSig,
            pageControl?(int)pageControl.hidden:-1,dots,
            LMVSquidPanelHeightInOrientation(slot<2?0:2,landscapeNow),
            LMVSquidPanelHeightInOrientation(slot<2?1:3,landscapeNow),
            (int)(LMVSquidPanelSlotSigs[0].length>0),(int)(LMVSquidPanelSlotSigs[1].length>0),
            (int)(LMVSquidPanelSlotSigs[2].length>0),(int)(LMVSquidPanelSlotSigs[3].length>0),
            (slot>=0 && slot<LMVSquidPanelSlotCount && LMVSquidPanelSlotSeen[slot]>0)?CACurrentMediaTime()-LMVSquidPanelSlotSeen[slot]:-1,
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
        // 1.55: a slot is a SET of signatures now (newest last), so a panel that was
        // edited is still itself. A 1.54 device stored one plain string under the same
        // key and an older one stored nothing at all, which is what the seed pair covers.
        NSArray *sigKeys=LMVSquidPanelSlotSigKeys();
        NSArray *seeds=@[@"SquidPanelTallSig2",@"SquidPanelShortSig2"];
        for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
            id value=(__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)sigKeys[i],kLMVPrefsID);
            NSMutableArray *set=[NSMutableArray array];
            if([value isKindOfClass:NSArray.class]) {
                for(id item in (NSArray *)value) {
                    if([item isKindOfClass:NSString.class] && [item length])[set addObject:item];
                }
            } else if([value isKindOfClass:NSString.class] && [value length]) {
                [set addObject:value];
            } else if(i<seeds.count) {
                id seed=(__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)seeds[i],kLMVPrefsID);
                if([seed isKindOfClass:NSString.class] && [seed length])[set addObject:seed];
            }
            LMVSquidPanelSlotSigSets[i]=[set copy];
            LMVSquidPanelSlotSigs[i]=set.lastObject;
        }
        // 1.53: a 1.52-era signature carries `|dots`, whose value changes with the
        // orientation - so it names a panel only half of the time and can never be
        // trusted again. Forgetting them is the migration: every panel is re-learned
        // the next time the user opens it, with a signature that survives a rotation.
        BOOL stale=NO;
        for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
            NSMutableArray *set=[(LMVSquidPanelSlotSigSets[i]?:@[]) mutableCopy];
            NSUInteger before=set.count;
            for(NSString *item in [set copy])
                if([item rangeOfString:@"|dots"].location!=NSNotFound)[set removeObject:item];
            if(set.count==before)continue;
            LMVSquidPanelStoreSlot(i,set);
            if(!set.count) {
                CFPreferencesSetAppValue((__bridge CFStringRef)LMVSquidPanelSlotHeightKeys()[i],NULL,kLMVPrefsID);
                LMVSquidPanelSlotHeights[i][0]=0;LMVSquidPanelSlotHeights[i][1]=0;
            }
            stale=YES;
        }
        if(stale) {
            CFPreferencesAppSynchronize(kLMVPrefsID);
            if(LMVDiagnosticsEnabled.load())LMVDiagnostic(@"squid-panel-migrate slots=4 (signatures now carry no dots, so a rotation keeps the panel)");
        }
        // 1.54: the way a brand-new panel is placed CHANGED (1.53 guessed which side it
        // was on), so the slots a 1.53 device wrote are not trustworthy - the report that
        // started this release is exactly that: 右二 had been recorded where 左一 belongs
        // and the other way round. Upgrading forgets all four and re-learns them on the
        // next four opens, which also means the user never has to tap 重置面板识别.
        id learned=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("SquidPanelLearnVersion"),kLMVPrefsID);
        NSInteger generation=[learned isKindOfClass:NSNumber.class]?[learned integerValue]:0;
        if(generation<LMVSquidPanelLearnGeneration) {
            CFPreferencesSetAppValue(CFSTR("SquidPanelLearnVersion"),(__bridge CFNumberRef)@(LMVSquidPanelLearnGeneration),kLMVPrefsID);
            LMVSquidPanelForgetAll();
            if(LMVDiagnosticsEnabled.load())
                LMVDiagnostic([NSString stringWithFormat:@"squid-panel-migrate slots=4 (rule v%d: a slot remembers every signature it was seen as, so editing a layout keeps the panel)",(int)LMVSquidPanelLearnGeneration]);
        }
        NSArray *heightKeys=LMVSquidPanelSlotHeightKeys();
        for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++) {
            id value=(__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)heightKeys[i],kLMVPrefsID);
            NSArray *pair=[value isKindOfClass:NSArray.class]?(NSArray *)value:nil;
            if(pair && pair.count==2) {
                CGFloat portrait=[pair[0] isKindOfClass:NSNumber.class]?[pair[0] doubleValue]:0;
                CGFloat landscape=[pair[1] isKindOfClass:NSNumber.class]?[pair[1] doubleValue]:0;
                LMVSquidPanelSlotHeights[i][0]=(portrait>0)?portrait:0;
                LMVSquidPanelSlotHeights[i][1]=(landscape>0)?landscape:0;
            } else if([value isKindOfClass:NSNumber.class]) {
                // a 1.52 number, taken in one orientation only: keep it as the portrait
                // value rather than throwing the evidence away.
                CGFloat height=[value doubleValue];
                LMVSquidPanelSlotHeights[i][0]=(height>0)?height:0;
                LMVSquidPanelSlotHeights[i][1]=0;
            } else {
                LMVSquidPanelSlotHeights[i][0]=0;LMVSquidPanelSlotHeights[i][1]=0;
            }
        }
        id reset=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("SquidPanelResetToken"),kLMVPrefsID);
        NSString *resetText=[reset isKindOfClass:NSString.class]?reset:(reset?[reset description]:nil);
        if(resetText.length && ![resetText isEqualToString:LMVSquidPanelResetToken]) {
            LMVSquidPanelResetToken=[resetText copy];
            // before the signatures are read below, so the cleared keys win.
            LMVSquidPanelForgetAll();
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
