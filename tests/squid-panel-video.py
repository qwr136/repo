#!/usr/bin/env python3
"""1.22-1.44 contracts for the SquidGesturePro panel background channel.

The channel is intentionally poll-based: no private class of that tweak is hooked
or guessed, the panel window is found by class name and the video is attached
INSIDE the card, re-sized to the card every poll so it follows a panel that grows
with its icons. Nothing is constructed while the switch is off.

1.44: that panel has TWO shapes - the one a swipe-up opens (tall) and the shorter
one a swipe-up-twice opens. 1.50: the plugin lets both gestures be configured on the
LEFT as well, so the channel carries FOUR material slots - right 上滑/上上滑 and left
上滑/上上滑 - while the sound switch and volume stay shared (only one of the four is
ever on screen). The shape is read from the page control (hidden on the short panel,
shown on the tall one, the same in landscape and in portrait), the SIDE cannot be read
from the content at all (the left and right panels differ only in what the user put in
them) and is therefore claimed automatically and can be re-bound by hand, and the
video always fills the CARD rather than the full-screen blur material behind it.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
module = (root / 'LMVSquidPanelVideo.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
panel = (root / 'LMVEasterPanel.h').read_text()
audio = (root / 'LMVMediaAudio.h').read_text()
delete = (root / 'LockMessageVideoPrefs/LMVMaterialDeletion.h').read_text()

# ---- the module -----------------------------------------------------------
assert 'static void LMVSquidPanelVideoRefresh(BOOL reload);' in module
assert 'static void LMVSquidPanelVideoSuspend(void);' in module
# The panel window is located by CLASS NAME, never by hooking the tweak.
assert "containsString:@\"SGPanel\"" in module
assert 'MSHookMessageEx' not in module and 'class_getInstanceMethod' not in module
# The card is the largest visible descendant that does NOT fill the window, so a
# panel that grows with its icons is followed by construction, not by a stored rect.
assert 'static UIView *LMVSquidPanelCard(UIWindow *window) {' in module
assert 'if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;' in module
assert 'if(frame.size.width<bounds.size.width*.5 || frame.size.height<bounds.size.height*.08)continue;' in module
# 1.25: each shape keeps SEVERAL cards (device log: two 430x435 views, one on
# screen at y=497 and one parked at y=1459 in a 932-high window) - scoring by area
# made the choice flip and the video kept landing on the parked one.
assert 'static CGFloat LMVSquidPanelVisibleArea(CGRect frame,CGRect bounds) {' in module
assert 'return visible/total>=.5?visible:0;' in module
assert 'CGFloat visible=LMVSquidPanelVisibleArea(frame,bounds);' in module
assert 'if(visible<=0)continue;   // parked off screen - never a candidate' in module
assert 'if(visible>bestArea){bestArea=visible;best=child;}' in module
# 1.44: the material is NOT scored with the card rule. It is searched inside the
# already-chosen card, so a parked copy is unreachable; what matters is that it
# covers the card, because in BOTH shapes it is sized to the SCREEN (landscape:
# 932x435 behind a 814x180 card). Scoring it by its own visibility dropped it to
# 36% and the short landscape panel lost its material - the video then fell back to
# the card's first subview, i.e. UNDER the blur, and became invisible.
assert 'static UIView *LMVSquidPanelMaterial(UIView *root,UIWindow *window) {' in module
assert 'CGRect cardFrame=[root convertRect:root.bounds toView:window];' in module
assert 'if(area/cardArea<.9)continue;   // must actually cover the card it serves' in module
assert 'UIView *material=LMVSquidPanelMaterial(card,window);' in module
assert 'if(!material)material=LMVSquidPanelMaterial(window,window);' in module
assert 'vis=%.0f' in module
# 1.50: FOUR slots, and the shape half of the verdict still comes from the page
# control / height test below.
assert 'static UIPageControl *LMVSquidPanelPageControl(UIView *card,UIWindow *window) {' in module
assert 'if(![node isKindOfClass:UIPageControl.class])continue;' in module
assert 'CGFloat gap=fabs(CGRectGetMaxY(f)-CGRectGetMinY(cardFrame));' in module
assert 'return (page && bestGap<40)?page:nil;' in module
assert 'shortPanel=page.hidden;' in module
assert 'shortPanel=(screen>0 && height<screen*.45);' in module
# The slot table itself: four materials, four remembered signatures, four gesture names.
assert '#define LMVSquidPanelSlotCount 4' in module
assert 'static NSString *LMVSquidPanelSlotPaths[LMVSquidPanelSlotCount];' in module
assert 'static NSString *LMVSquidPanelSlotRevisions[LMVSquidPanelSlotCount];' in module
assert 'static NSString *LMVSquidPanelSlotSigs[LMVSquidPanelSlotCount];' in module
assert 'return @[@"SquidPanelVideo",@"SquidPanel2Video",@"SquidPanel3Video",@"SquidPanel4Video"];' in module
assert 'return @[@"SquidPanelSlot1Sig",@"SquidPanelSlot2Sig",@"SquidPanelSlot3Sig",@"SquidPanelSlot4Sig"];' in module
assert 'return @[@"右边上滑",@"右边上上滑",@"左边上滑",@"左边上上滑"];' in module
# Even slot = the tall "上滑" panel, odd = the short "上上滑" one; which of the two a
# panel is comes out of the pair ordering below, never from a helper that could go
# unused (the build is -Werror, and an unused static in this header fails it).
assert 'LMVSquidPanelSlotIsShort' not in module
for name in re.findall(r'^static [\w \*]+?(LMVSquidPanel\w+)\(', module, re.M):
    assert module.count(name) + tweak.count(name) > 1, f'unused static {name} (the build is -Werror)'
# 1.47/1.48 identity, now per slot: a CONTENT signature that carries no height and no
# width - icon count and page-control dots - because the device log killed both earlier
# keys (the card object is re-created on every open; the height is what the user edits).
assert 'static __weak UIView *LMVSquidPanelTallCard' not in module    # object memory is gone
assert 'static NSString *LMVSquidPanelSlotSigs[LMVSquidPanelSlotCount];' in module
assert 'static NSString *LMVSquidPanelShapeSig;' in module
assert 'static NSString *LMVSquidPanelShapeReason=@"none";' in module
assert 'static NSUInteger LMVSquidPanelIconCount(UIView *card) {' in module
assert 'if([child isKindOfClass:UIButton.class])count++;' in module
assert 'static NSString *LMVSquidPanelContentSignature(UIView *card,UIWindow *window) {' in module
assert 'return [NSString stringWithFormat:@"icons%lu|pc%d|dots%.0f",(unsigned long)icons,page?1:0,dots];' in module
assert 'if([NSStringFromClass(sub.class) containsCaseInsensitiveString:@"PageControlContentView"' if False else 'if([NSStringFromClass(sub.class) containsString:@"PageControlContentView"])' in module
assert 'static NSUInteger LMVSquidPanelSignatureIcons(NSString *sig) {' in module
assert 'static NSUInteger LMVSquidPanelSignatureDistance(NSUInteger icons,NSString *sig) {' in module
# (a) a signature seen before settles it outright.
assert 'static NSInteger LMVSquidPanelResolveSlot(UIView *card,UIWindow *window) {' in module
assert 'NSString *sig=LMVSquidPanelContentSignature(card,window);' in module
assert 'NSString *reason=[NSString stringWithFormat:@"sig-slot%d",(int)i+1];' in module
# (b) shape first: both shapes learned -> closest icon count; else page control, else height.
assert 'NSUInteger d=LMVSquidPanelSignatureDistance(icons,LMVSquidPanelSlotSigs[i]);' in module

assert 'reason=[NSString stringWithFormat:@"page.hidden=%d",(int)page.hidden];' in module
# (c) 1.51: the SIDE is inferred - a signature belongs to the side that learned it,
# and an unknown one belongs to the side that has learned nothing yet.
assert 'BOOL knownRight=LMVSquidPanelSlotSigs[0].length>0 || LMVSquidPanelSlotSigs[1].length>0;' in module
assert 'BOOL knownLeft=LMVSquidPanelSlotSigs[2].length>0 || LMVSquidPanelSlotSigs[3].length>0;' in module
assert 'BOOL leftSide=!knownLeft && knownRight;' in module
assert 'NSInteger tallSlot=leftSide?2:0, shortSlot=leftSide?3:1;' in module
# ...and WITHIN a side the two panels order themselves, which is what makes the whole
# thing automatic: 上滑 is the taller one of the pair (device logs: left 上滑
# icons8/180pt against left 上上滑 icons4/95pt, right 50/435 against 29/350), with the
# icon count breaking a tie so a user who made them the same height still sorts out.
assert 'static CGFloat LMVSquidPanelSlotHeights[LMVSquidPanelSlotCount];' in module
assert 'return @[@"SquidPanelSlot1H",@"SquidPanelSlot2H",@"SquidPanelSlot3H",@"SquidPanelSlot4H"];' in module
assert 'static void LMVSquidPanelNoteHeight(NSInteger slot,CGFloat height) {' in module
assert 'static void LMVSquidPanelMoveSlot(NSInteger from,NSInteger to) {' in module
assert 'static int LMVSquidPanelOrderPair(NSInteger tallSlot,NSInteger shortSlot) {' in module
assert 'if(knownHeight>0 && height>0 && fabs(height-knownHeight)>4) {order=(height>knownHeight)?1:-1;by=@"height";}' in module
assert 'else if(icons!=NSNotFound && knownIcons!=NSNotFound && icons!=knownIcons) {order=(icons>knownIcons)?1:-1;by=@"icons";}' in module
assert 'LMVSquidPanelShapeReason=[NSString stringWithFormat:@"pair-by-%@-%@@slot%d",by,sideTag,(int)wantSlot+1];' in module
# An already-recorded pair that contradicts its slots swaps itself on sight, and an
# edited panel keeps the slot it owns (closest icon count, nothing moves).
assert 'NSInteger tallOfPair=(i<2)?0:2, shortOfPair=(i<2)?1:3;' in module
assert 'if(LMVSquidPanelOrderPair(tallOfPair,shortOfPair)>0) {' in module
assert 'LMVSquidPanelShapeReason=[reason stringByAppendingString:@"+pair-swapped"];' in module
assert 'LMVSquidPanelShapeReason=[NSString stringWithFormat:@"edited-nearest-slot%d",(int)best+1];' in module
# Nothing to compare yet: the page control, then the absolute height - and never a
# signature taken while the panel is still assembling (no icons yet).
assert 'LMVSquidPanelShapeReason=[NSString stringWithFormat:@"%@@first-%@@slot%d",reason,sideTag,(int)slot+1];' in module
# (d) and the user can always overrule both: "认领刚用过的面板".
assert 'static void LMVSquidPanelBindLastSeen(NSInteger slot) {' in module
assert 'LMVSquidPanelLastSeen=CACurrentMediaTime();' in module
assert 'squid-panel-claim slot=%d gesture=%@ sig=%@ age=%.0fs applied=%d' in module
assert 'CFSTR("SquidPanelClaimSlot")' in module and 'CFSTR("SquidPanelClaimToken")' in module
# 1.48's pair seeds the two right-hand slots, so a device that already knew its right
# panels keeps that knowledge; the 1.47 key generation itself is gone.
assert 'NSArray *seeds=@[@"SquidPanelTallSig2",@"SquidPanelShortSig2"];' in module
assert 'CFSTR("SquidPanelTallSig")' not in module and 'CFSTR("SquidPanelShortSig")' not in module
# Attached under everything the card draws, and re-sized to the card every poll.
# 1.23: the card may BE the panel's blur material, and a UIVisualEffectView refuses
# direct subviews - adding one raises, and an exception in a run-loop callback
# aborts SpringBoard (the 1.22 safe-mode crash). The effect view is therefore never
# the container: the host goes into its superview directly below it.
assert '- (BOOL)insertHostInto:(UIView *)container at:(NSUInteger)index {' in module
assert 'if(!container || [container isKindOfClass:UIVisualEffectView.class])return NO;' in module
assert '@try {[container insertSubview:self.host atIndex:index];}' in module
assert '@catch(NSException *exception) {[self.host removeFromSuperview];return NO;}' in module
# 1.24: and it must sit UNDER the icons but ABOVE that material - 1.23 placed it
# below the material, which hid it (device report: 看不到视频背景).
assert 'if(![child isKindOfClass:UIVisualEffectView.class] || child.hidden || child.alpha<.01)continue;' in module
assert 'UIView *content=((UIVisualEffectView *)material).contentView;' in module
assert 'container=content;index=0;mode=@"content";' in module
assert 'index=(NSUInteger)(near+1);mode=@"above-material";' in module
assert 'if(!container) {container=card;index=0;}' in module
# 1.44: the host fills the CARD, not the container it happens to live in. In
# landscape the material (and the content view inside it) is a full-screen
# 932x435 view while the card is 814x180, so container-sized video overflowed the
# panel instead of filling it.
assert 'CGRect cardInContainer=[card convertRect:card.bounds toView:container];' in module
assert 'CGRect target=CGRectIntersection(container.bounds,cardInContainer);' in module
assert 'if(!CGRectEqualToRect(self.host.frame,target))self.host.frame=target;' in module
# Defence in depth: no failure in this channel may ever abort SpringBoard.
assert '@try {[LMVSquidPanelVideo update];}' in module
assert '@catch(NSException *exception) {[LMVSquidPanelVideo detach];}' in module
assert 'slot=%d gesture=%@ play=%@' in module
assert 'mode=%@' in module
assert 'UIViewAutoresizing mask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;' in module
assert 'if(self.host.layer.cornerRadius!=card.layer.cornerRadius)self.host.layer.cornerRadius=card.layer.cornerRadius;' in module
# Our own host can never be mistaken for the card while the search walks the tree.
assert 'static NSInteger const LMVSquidPanelHostTag=0x5A17;' in module
assert 'if(child.tag==LMVSquidPanelHostTag || child.hidden || child.alpha<.01)continue;' in module
assert 'self.tag=LMVSquidPanelHostTag;' in module
# Never interactive, never a poster substitute for a live panel background.
assert 'self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;' in module
assert 'self.playback.posterLayer.hidden=YES;' in module
assert 'BOOL live=self.playback.player && self.playback.playerLayer.readyForDisplay && !self.playback.error;' in module
# Preferences: own switch, four material slots, master switch respected, default off.
assert 'CFSTR("SquidPanelBackgroundEnabled")' in module
assert 'LMVSquidPanelSlotPaths[i]=LMVCCSelectedPath(keys[i]);' in module
assert 'LMVSquidPanelSlotRevisions[i]=LMVLockVideoRevision(LMVSquidPanelSlotPaths[i]);' in module
assert 'LMVSquidPanelEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&' in module
# 1.44/1.45/1.50: the verdict picks the slot, and the four slots are INDEPENDENT - there
# is no fallback between them, by request: a panel whose slot is empty gets no video
# (and no sound) at all, rather than borrowing another panel's material.
assert 'NSInteger slot=LMVSquidPanelResolveSlot(card,window);' in module
assert '?LMVSquidPanelPath:LMVSquidPanelPath2' not in module        # never crosses over
assert 'if(!wantPath.length || !wantRevision.length) {' in module
assert '"squid-panel slot=%d empty=%@ (no video, by design)"' in module
# 1.46: the manual override, for the one case identity cannot fix - the very first
# content test guessing the two panels the other way round.
assert 'static BOOL LMVSquidPanelEnabled,LMVSquidPanelPrefsKnown,LMVSquidPanelSwapShapes;' in module
assert 'CFSTR("SquidPanelSwapShapes")' in module
# 1.50: "对调" now swaps the two shapes WITHIN a side (0<->1, 2<->3), so it can never
# mix up the left and right materials.
assert 'NSInteger wantSlot=slot;' in module
assert 'if(LMVSquidPanelSwapShapes)wantSlot=slot^1;' in module
assert 'NSString *wantPath=LMVSquidPanelSlotPaths[wantSlot];' in module
assert 'NSString *wantRevision=LMVSquidPanelSlotRevisions[wantSlot];' in module
# 1.46: the log names the slot, the reason for the verdict and the card object, so a
# wrong pick is one line away from being explained.
assert 'slot=%d gesture=%@ play=%@ why=%@ sig=%@ pair=%.0f/%.0f mode=%@' in module
assert 'slot<2?LMVSquidPanelSlotHeights[0]:LMVSquidPanelSlotHeights[2],' in module
assert '(int)slot+1,LMVSquidPanelSlotTitles()[slot],LMVSquidPanelSlotTitles()[wantSlot],' in module
assert 'LMVSquidPanelShapeReason,LMVSquidPanelShapeSig,' in module
assert 'ptr=%p' in module and '(void *)self.card,' in module
assert 'if(changed) {[self.host removeFromSuperview];[self.playback selectPath:wantPath revision:wantRevision];}' in module
# No player/UI while the channel is off (any single slot may be the only one set), and a
# poll that never runs hot when idle.
assert 'for(NSInteger i=0;i<LMVSquidPanelSlotCount;i++)' in module
assert 'if(LMVSquidPanelSlotPaths[i].length && LMVSquidPanelSlotRevisions[i].length)anySlot=YES;' in module
assert 'if(!LMVSquidPanelEnabled || !anySlot) {' in module
assert 'if(!LMVSquidPanelVideo)LMVSquidPanelVideo=[LMVSquidPanelVideoManager new];' in module
assert 'NSTimeInterval want=LMVSquidPanelEnabled?.1:.5;' in module
assert 'dispatch_async(dispatch_get_main_queue()' not in module  # poll on the main run loop only

# ---- wiring ---------------------------------------------------------------
assert '#import "LMVSquidPanelVideo.h"' in tweak
assert '    LMVSquidPanelVideoRefresh(reload);' in tweak
assert tweak.count('LMVSquidPanelVideoSuspend();') == 2          # suspend + resign-active
assert '        LMVSquidPanelVideoInstallHooks();' in tweak
assert 'LMVAudioConsume(@"SquidPanel",panel.path,panel.revision,panelVisible,panel.player.currentTime);' in tweak
assert 'return @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu",@"SquidPanel",@"AT",@"CV"];' in audio

# ---- the two settings surfaces -------------------------------------------
assert '[squidPanelEnabled setProperty:@"SquidPanelBackgroundEnabled" forKey:@"key"];' in prefs
assert '[squidPanelEnabled setProperty:@NO forKey:@"default"];' in prefs
assert 'squidPanelMaterial.buttonAction = @selector(switchSquidPanel:);' in prefs
assert '- (void)switchSquidPanel:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel"]; }' in prefs
# 1.44: the second slot, named after the gesture (the shape is the same in both
# orientations), and it is routed exactly like the first one.
assert 'squidPanelMaterial2.buttonAction = @selector(switchSquidPanel2:);' in prefs
assert '[squidPanelMaterial2 setProperty:@"SquidPanel2Material" forKey:@"id"];' in prefs
assert '- (void)switchSquidPanel2:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel2"]; }' in prefs
# 1.50: the left-hand pair, plus the row that settles which gesture owns a panel.
assert 'squidPanelMaterial3.buttonAction = @selector(switchSquidPanel3:);' in prefs
assert '[squidPanelMaterial3 setProperty:@"SquidPanel3Material" forKey:@"id"];' in prefs
assert '- (void)switchSquidPanel3:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel3"]; }' in prefs
assert 'squidPanelMaterial4.buttonAction = @selector(switchSquidPanel4:);' in prefs
assert '[squidPanelMaterial4 setProperty:@"SquidPanel4Material" forKey:@"id"];' in prefs
assert '- (void)switchSquidPanel4:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel4"]; }' in prefs
assert 'squidPanelClaim.buttonAction = @selector(claimSquidPanel:);' in prefs
assert '- (void)claimSquidPanel:(PSSpecifier *)specifier {' in prefs
assert 'CFPreferencesSetAppValue(CFSTR("SquidPanelClaimSlot"), (__bridge CFPropertyListRef)@(slot), kLMVPrefsID);' in prefs
assert '@"SquidPanel3":@"",@"SquidPanel4":@"",@"AT":@""' in delete
assert '@"SquidPanel3",@"SquidPanel4",@"AT",@"CV"]' in delete
assert '@"SquidPanel": @"右边上滑面板背景视频"' in prefs
assert '@"SquidPanel2": @"右边上上滑面板背景视频"' in prefs
assert '@"SquidPanel3": @"左边上滑面板背景视频"' in prefs
assert '@"SquidPanel4": @"左边上上滑面板背景视频"' in prefs
assert '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"鱿鱼面板背景视频"]];' in prefs
assert '切换右边上滑素材' in prefs and '切换右边上上滑素材' in prefs
assert '切换左边上滑素材' in prefs and '切换左边上上滑素材' in prefs and '认领刚用过的面板' in prefs
assert 'static NSInteger LMVEasterSquidPanelSection(void) { return LMVEasterHomeMenuSection() + 1; }' in panel
# 1.50: nine rows - switch, four materials, the claim row, the swap row, sound, volume.
# The sound pair moved to 7/8, which is also what stops the volume row from rendering
# as a second "播放声音" switch (the report that started this release).
assert 'if (section == LMVEasterSquidPanelSection()) return 9;' in panel
assert 'if (section == LMVEasterSquidPanelSection()) return @"鱿鱼面板背景视频";' in panel
assert 'if (section == LMVEasterSquidPanelSection() && (row == 7 || row == 8)) return @"SquidPanel";' in panel
assert 'if (section == LMVEasterSquidPanelSection()) return row == 8;' in panel
assert 'static NSArray *LMVEasterSquidKeys(void) {' in panel
assert 'return @[@"SquidPanelVideo", @"SquidPanel2Video", @"SquidPanel3Video", @"SquidPanel4Video"];' in panel
assert 'return @[@"切换右边上滑素材", @"切换右边上上滑素材", @"切换左边上滑素材", @"切换左边上上滑素材"];' in panel
assert 'return @[@"右边上滑", @"右边上上滑", @"左边上滑", @"左边上上滑"];' in panel
assert 'toggle.on = [LMVEasterRead(@"SquidPanelBackgroundEnabled") boolValue];' in panel
assert 'cell.textLabel.text = LMVEasterSquidTitles()[index.row - 1];' in panel
assert 'id selected = LMVEasterRead(LMVEasterSquidKeys()[index.row - 1]);' in panel
# 1.46: the swap row, in Settings (a switch, keyed) and in the floating panel (a
# button - the panel's switches are told apart by tag and every tag is a section).
assert '[squidPanelSwap setProperty:@"SquidPanelSwapShapes" forKey:@"key"];' in prefs
assert 'squidPanelSwap.buttonAction' not in prefs
assert 'cell.textLabel.text = @"对调上滑 / 上上滑素材";' in panel
assert 'cell.detailTextLabel.text = [LMVEasterRead(@"SquidPanelSwapShapes") boolValue] ? @"已对调" : @"正常";' in panel
assert 'LMVEasterSet(@"SquidPanelSwapShapes", @(!now));' in panel
assert 'if (index.row < 1 || index.row > 4) return;\n        key = LMVEasterSquidKeys()[index.row - 1];' in panel
# 1.50: the claim row is a PUSHED chooser, never a presented sheet (the floating panel
# owns no presentation role - see tests/panel-roles.py), and it writes the slot + token.
assert 'if (index.row == 5) { [self claimSquidPanel]; return; }' in panel
assert 'LMVEasterChoice *choice = [LMVEasterChoice new];' in panel
assert 'choice.options = LMVEasterSquidGestures();' in panel
assert 'LMVEasterSet(@"SquidPanelClaimSlot", @(index + 1));' in panel
assert 'LMVEasterSet(@"SquidPanelClaimToken", [NSString stringWithFormat:@"%.3f", NSDate.date.timeIntervalSince1970]);' in panel
assert '[self.navigationController pushViewController:choice animated:YES];' in panel
assert 'presentViewController:' not in panel
choice = (root / 'LMVEasterChoice.h').read_text()
assert '#import "LMVEasterChoice.h"' in panel
assert '@interface LMVEasterChoice:UITableViewController' in choice
assert 'if (self.pick) self.pick(index.row);' in choice
assert '[self.navigationController popViewControllerAnimated:YES];' in choice
assert "else if (toggle.tag == LMVEasterSquidPanelSection()) key = @\"SquidPanelBackgroundEnabled\";" in panel
print('PASS: SquidGesturePro panel channel - poll-based attach that fills the card, FOUR material '
      'slots (right and left 上滑/上上滑): a height-independent CONTENT SIGNATURE (icons + '
      'page-control dots) identifies a panel the user has edited, an unknown one belongs to the side '
      'that learned nothing yet, and the two panels of that side ORDER THEMSELVES by height (icon '
      'count as the tiebreak) - so no manual step is needed and an inverted record swaps itself; '
      'a pushed claim chooser remains as the last resort, one shared sound pair, both surfaces')
