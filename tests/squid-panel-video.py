#!/usr/bin/env python3
"""1.22 contracts for the SquidGesturePro panel background channel.

The channel is intentionally poll-based: no private class of that tweak is hooked
or guessed, the panel window is found by class name and the video is attached
INSIDE the card as its first subview, re-sized to the card every poll so it
follows a panel that grows with its icons. Nothing is constructed while the
switch is off.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
module = (root / 'LMVSquidPanelVideo.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
panel = (root / 'LMVEasterPanel.h').read_text()
audio = (root / 'LMVMediaAudio.h').read_text()

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
# 1.25: the panel keeps SEVERAL cards (device log: two 430x435 views, one on
# screen at y=497 and one parked at y=1459 in a 932-high window) - scoring by area
# made the choice flip and the video kept landing on the parked one.
assert 'static CGFloat LMVSquidPanelVisibleArea(CGRect frame,CGRect bounds) {' in module
assert 'return visible/total>=.5?visible:0;' in module
assert 'CGFloat visible=LMVSquidPanelVisibleArea(frame,bounds);' in module
assert 'if(visible<=0)continue;   // parked off screen - never a candidate' in module
assert 'if(visible>bestArea){bestArea=visible;best=child;}' in module
assert 'static UIView *LMVSquidPanelMaterial(UIView *root,UIWindow *window) {' in module
assert 'UIView *material=LMVSquidPanelMaterial(card,window);' in module
assert 'if(!material)material=LMVSquidPanelMaterial(window,window);' in module
assert 'vis=%.0f' in module
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
assert 'static UIView *LMVSquidPanelMaterial(UIWindow *window) {' in module
assert 'if(![child isKindOfClass:UIVisualEffectView.class] || child.hidden || child.alpha<.01)continue;' in module
assert 'UIView *content=((UIVisualEffectView *)material).contentView;' in module
assert 'container=content;index=0;target=content.bounds;mode=@"content";' in module
assert 'index=(NSUInteger)(near+1);target=material.frame;mode=@"above-material";' in module
assert 'if(!CGRectEqualToRect(self.host.frame,target))self.host.frame=target;' in module
# Defence in depth: no failure in this channel may ever abort SpringBoard.
assert '@try {[LMVSquidPanelVideo update];}' in module
assert '@catch(NSException *exception) {[LMVSquidPanelVideo detach];}' in module
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
# Preferences: own switch, own material, master switch respected, default off.
assert 'CFSTR("SquidPanelBackgroundEnabled")' in module
assert 'LMVSquidPanelPath=LMVCCSelectedPath(@"SquidPanelVideo");' in module
assert 'LMVSquidPanelRevision=LMVLockVideoRevision(LMVSquidPanelPath);' in module
assert 'LMVSquidPanelEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&' in module
# No player/UI while the channel is off, and a poll that never runs hot when idle.
assert 'if(!LMVSquidPanelEnabled || !LMVSquidPanelPath.length || !LMVSquidPanelRevision.length) {' in module
assert 'if(!LMVSquidPanelVideo)LMVSquidPanelVideo=[LMVSquidPanelVideoManager new];' in module
assert 'NSTimeInterval want=LMVSquidPanelEnabled?.1:.5;' in module
assert 'dispatch_async(dispatch_get_main_queue()' not in module  # poll on the main run loop only

# ---- wiring ---------------------------------------------------------------
assert '#import "LMVSquidPanelVideo.h"' in tweak
assert '    LMVSquidPanelVideoRefresh(reload);' in tweak
assert tweak.count('LMVSquidPanelVideoSuspend();') == 2          # suspend + resign-active
assert '        LMVSquidPanelVideoInstallHooks();' in tweak
assert 'LMVAudioConsume(@"SquidPanel",panel.path,panel.revision,panelVisible,panel.player.currentTime);' in tweak
assert 'return @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu",@"SquidPanel"];' in audio

# ---- the two settings surfaces -------------------------------------------
assert '[squidPanelEnabled setProperty:@"SquidPanelBackgroundEnabled" forKey:@"key"];' in prefs
assert '[squidPanelEnabled setProperty:@NO forKey:@"default"];' in prefs
assert 'squidPanelMaterial.buttonAction = @selector(switchSquidPanel:);' in prefs
assert '- (void)switchSquidPanel:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel"]; }' in prefs
assert '@"SquidPanel": @"鱿鱼面板背景视频"' in prefs
assert '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"鱿鱼面板背景视频"]];' in prefs
assert '鱿鱼面板背景视频' in prefs and '切换鱿鱼面板素材' in prefs
assert 'static NSInteger LMVEasterSquidPanelSection(void) { return LMVEasterHomeMenuSection() + 1; }' in panel
assert 'if (section == LMVEasterSquidPanelSection()) return 4;' in panel
assert 'if (section == LMVEasterSquidPanelSection()) return @"鱿鱼面板背景视频";' in panel
assert 'toggle.on = [LMVEasterRead(@"SquidPanelBackgroundEnabled") boolValue];' in panel
assert 'key = @"SquidPanelVideo";' in panel
assert "else if (toggle.tag == LMVEasterSquidPanelSection()) key = @\"SquidPanelBackgroundEnabled\";" in panel
print('PASS: SquidGesturePro panel channel - poll-based attach inside the growable card, own switch/material/sound, wired in both settings surfaces')
