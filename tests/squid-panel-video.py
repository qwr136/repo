#!/usr/bin/env python3
"""1.22-1.44 contracts for the SquidGesturePro panel background channel.

The channel is intentionally poll-based: no private class of that tweak is hooked
or guessed, the panel window is found by class name and the video is attached
INSIDE the card, re-sized to the card every poll so it follows a panel that grows
with its icons. Nothing is constructed while the switch is off.

1.44: that panel has TWO shapes - the one a swipe-up opens (tall) and the shorter
one a swipe-up-twice opens - and each gets its own material slot, while the sound
switch and volume stay shared (only one of the two is ever on screen). The shape is
read from the page control (hidden on the short panel, shown on the tall one, the
same in landscape and in portrait), and the video always fills the CARD rather than
the full-screen blur material behind it.
"""
from pathlib import Path

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
# 1.44: which shape is up. The page control belongs to exactly one of them, sits
# 20pt above ITS own card in every orientation, and is hidden on the short one.
assert 'static BOOL LMVSquidPanelCardIsShort(UIView *card,UIWindow *window) {' in module
assert 'if(![node isKindOfClass:UIPageControl.class])continue;' in module
assert 'CGFloat gap=fabs(CGRectGetMaxY(f)-CGRectGetMinY(cardFrame));' in module
assert 'if(page && bestGap<40) {                            // the reliable signal' in module
assert 'shortPanel=page.hidden;' in module
assert 'shortPanel=(height>0 && cardFrame.size.height<height*.45);' in module
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
assert 'shape=%@' in module and 'shortPanel?@"short":@"tall"' in module
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
# Preferences: own switch, two material slots, master switch respected, default off.
assert 'CFSTR("SquidPanelBackgroundEnabled")' in module
assert 'LMVSquidPanelPath=LMVCCSelectedPath(@"SquidPanelVideo");' in module
assert 'LMVSquidPanelRevision=LMVLockVideoRevision(LMVSquidPanelPath);' in module
assert 'LMVSquidPanelPath2=LMVCCSelectedPath(@"SquidPanel2Video");' in module
assert 'LMVSquidPanelRevision2=LMVLockVideoRevision(LMVSquidPanelPath2);' in module
assert 'LMVSquidPanelEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&' in module
# 1.46: the shape is decided by IDENTITY, not by what the panel looks like. A card
# that was classified once keeps its classification while the object lives, so
# editing a panel (adding icons, making it taller, giving it a page control it never
# had) cannot flip it - that was the "made the short panel taller and it started
# using the tall panel's material" report. The content test runs only on first
# sighting, and its verdict is written into the object memory below.
assert 'static __weak UIView *LMVSquidPanelTallCard,*LMVSquidPanelShortCard;' in module
assert 'if(card && card==LMVSquidPanelShortCard){LMVSquidPanelShapeReason=@"remembered";return YES;}' in module
assert 'if(card && card==LMVSquidPanelTallCard){LMVSquidPanelShapeReason=@"remembered";return NO;}' in module
assert 'if(card) {if(shortPanel)LMVSquidPanelShortCard=card; else LMVSquidPanelTallCard=card;}' in module
assert 'static NSString *LMVSquidPanelShapeReason=@"none";' in module
assert 'LMVSquidPanelShapeReason=[NSString stringWithFormat:@"page.hidden=%d/gap=%.0f",(int)page.hidden,bestGap];' in module
assert 'LMVSquidPanelShapeReason=[NSString stringWithFormat:@"height=%.0f/%.0f",cardFrame.size.height,height];' in module
# 1.44/1.45: the shape picks the slot, and the two slots are INDEPENDENT - there is
# no fallback between them, by request: a panel whose slot is empty gets no video
# (and no sound) at all, rather than borrowing the other panel's material.
assert 'BOOL shortPanel=LMVSquidPanelCardIsShort(card,window);' in module
assert '?LMVSquidPanelPath:LMVSquidPanelPath2' not in module        # never crosses over
assert 'if(!wantPath.length || !wantRevision.length) {' in module
assert 'squid-panel shape=%@ slot=empty (no video, by design)' in module
# 1.46: the manual override, for the one case identity cannot fix - the very first
# content test guessing the two panels the other way round.
assert 'static BOOL LMVSquidPanelEnabled,LMVSquidPanelPrefsKnown,LMVSquidPanelSwapShapes;' in module
assert 'CFSTR("SquidPanelSwapShapes")' in module
assert 'BOOL useSecond=LMVSquidPanelSwapShapes?!shortPanel:shortPanel;' in module
assert 'NSString *wantPath=useSecond?LMVSquidPanelPath2:LMVSquidPanelPath;' in module
assert 'NSString *wantRevision=useSecond?LMVSquidPanelRevision2:LMVSquidPanelRevision;' in module
# 1.46: the log names the slot, the reason for the verdict and the card object, so a
# wrong pick is one line away from being explained.
assert 'shape=%@ slot=%d why=%@ mode=%@' in module
assert 'shortPanel?@"short":@"tall",useSecond?2:1,LMVSquidPanelShapeReason,' in module
assert 'ptr=%p' in module and '(void *)self.card,' in module
assert 'if(changed) {[self.host removeFromSuperview];[self.playback selectPath:wantPath revision:wantRevision];}' in module
# No player/UI while the channel is off (either slot may be the only one set), and a
# poll that never runs hot when idle.
assert 'BOOL anySlot=(LMVSquidPanelPath.length && LMVSquidPanelRevision.length) ||' in module
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
assert '@"SquidPanel2":@"",@"AT":@""' in delete
assert '@"SquidPanel2",@"AT",@"CV"]' in delete
assert '@"SquidPanel": @"上滑面板背景视频"' in prefs
assert '@"SquidPanel2": @"上上滑面板背景视频"' in prefs
assert '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"鱿鱼面板背景视频"]];' in prefs
assert '切换上滑素材' in prefs and '切换上上滑素材' in prefs
assert 'static NSInteger LMVEasterSquidPanelSection(void) { return LMVEasterHomeMenuSection() + 1; }' in panel
# 1.44: five rows - switch, swipe-up material, swipe-up-twice material, sound, volume.
assert 'if (section == LMVEasterSquidPanelSection()) return 6;' in panel
assert 'if (section == LMVEasterSquidPanelSection()) return @"鱿鱼面板背景视频";' in panel
assert 'if (section == LMVEasterSquidPanelSection() && (row == 4 || row == 5)) return @"SquidPanel";' in panel
assert 'toggle.on = [LMVEasterRead(@"SquidPanelBackgroundEnabled") boolValue];' in panel
assert 'cell.textLabel.text = index.row == 1 ? @"切换上滑素材" : @"切换上上滑素材";' in panel
assert 'id selected = LMVEasterRead(index.row == 1 ? @"SquidPanelVideo" : @"SquidPanel2Video");' in panel
# 1.46: the swap row, in Settings (a switch, keyed) and in the floating panel (a
# button - the panel's switches are told apart by tag and every tag is a section).
assert '[squidPanelSwap setProperty:@"SquidPanelSwapShapes" forKey:@"key"];' in prefs
assert 'squidPanelSwap.buttonAction' not in prefs
assert 'cell.textLabel.text = @"对调上滑 / 上上滑素材";' in panel
assert 'cell.detailTextLabel.text = [LMVEasterRead(@"SquidPanelSwapShapes") boolValue] ? @"已对调" : @"正常";' in panel
assert 'LMVEasterSet(@"SquidPanelSwapShapes", @(!now));' in panel
assert 'if (index.row != 1 && index.row != 2) return;\n        key = index.row == 1 ? @"SquidPanelVideo" : @"SquidPanel2Video";' in panel
assert "else if (toggle.tag == LMVEasterSquidPanelSection()) key = @\"SquidPanelBackgroundEnabled\";" in panel
print('PASS: SquidGesturePro panel channel - poll-based attach that fills the card, two shapes '
      '(swipe-up / swipe-up-twice) told apart by OBJECT identity (so editing a panel cannot flip '
      'them), independent materials with a manual swap override, one shared sound pair, wired in '
      'both settings surfaces')
