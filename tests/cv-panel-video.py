#!/usr/bin/env python3
"""1.43 contracts for the CopyVault clipboard-panel background channel.

The shape was settled by the 1.42 device diagnostics (desktop-panel-tree /
desktop-window-meta): CopyVault owns a real window (CVPanelWindow, root view
controller CVPanelViewController), its card is CopyVaultView (420x430 at y=497,
parked at y=1454 while closed) and the blur material + content container are
SIBLINGS inside that card, both rounded r55 while the card itself is r0.

Like the Squid channel this one is scoped to its OWN window, so it can never latch
onto an unrelated presentation; like the Squid channel it is poll-based and
private-class-free.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
module = (root / 'LMVCopyVaultPanelVideo.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
panel = (root / 'LMVEasterPanel.h').read_text()
audio = (root / 'LMVMediaAudio.h').read_text()
delete = (root / 'LockMessageVideoPrefs/LMVMaterialDeletion.h').read_text()

# ---- the module -----------------------------------------------------------
assert 'static void LMVCopyVaultPanelVideoRefresh(BOOL reload);' in module
assert 'static void LMVCopyVaultPanelVideoSuspend(void);' in module
# The panel window is located by CLASS NAME, never by hooking the tweak.
assert 'containsString:@"CVPanel"' in module and 'containsString:@"CopyVault"' in module
assert 'MSHookMessageEx' not in module and 'class_getInstanceMethod' not in module
# 1.42 device fact: CVPanelWindow is FULL SCREEN, so - exactly like the Squid panel -
# the card is the largest visible descendant that does NOT fill the window.
assert 'static UIView *LMVCVPanelCard(UIWindow *window) {' in module
assert 'if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;' in module
assert 'if(frame.size.width<bounds.size.width*.5 || frame.size.height<bounds.size.height*.08)continue;' in module
# 1.42 device fact: while the panel is CLOSED the same card sits OFF SCREEN at
# y=1454. The shared "at least half of it is really on screen" rule is what keeps
# the video off that parked copy.
assert 'static CGFloat LMVCVPanelVisibleArea(CGRect frame,CGRect bounds) {' in module
assert 'return visible/total>=.5?visible:0;' in module
assert 'CGFloat visible=LMVCVPanelVisibleArea(frame,bounds);' in module
assert 'if(visible<=0)continue;   // parked off screen - never a candidate' in module
assert 'if(visible>bestArea){bestArea=visible;best=child;}' in module
assert 'static UIView *LMVCVPanelMaterial(UIView *root,UIWindow *window) {' in module
assert 'UIView *material=LMVCVPanelMaterial(card,window);' in module
assert 'if(!material)material=LMVCVPanelMaterial(window,window);' in module
assert 'vis=%.0f' in module
# A UIVisualEffectView refuses direct subviews - adding one raises, and an exception
# in a run-loop callback aborts SpringBoard (the 1.23 crash). Never the container.
assert '- (BOOL)insertHostInto:(UIView *)container at:(NSUInteger)index {' in module
assert 'if(!container || [container isKindOfClass:UIVisualEffectView.class])return NO;' in module
assert '@try {[container insertSubview:self.host atIndex:index];}' in module
assert '@catch(NSException *exception) {[self.host removeFromSuperview];return NO;}' in module
# 1.42 device fact: the material and the CONTENT CONTAINER are siblings inside the
# card, so the material's own contentView is above the blur and still below the
# content - the "under the content but above the material" level 1.24 settled.
assert 'if(![child isKindOfClass:UIVisualEffectView.class] || child.hidden || child.alpha<.01)continue;' in module
assert 'UIView *content=((UIVisualEffectView *)material).contentView;' in module
assert 'container=content;index=0;target=content.bounds;mode=@"content";' in module
assert 'index=(NSUInteger)(near+1);target=material.frame;mode=@"above-material";' in module
assert 'if(!CGRectEqualToRect(self.host.frame,target))self.host.frame=target;' in module
# 1.43: the CARD is r0 while the material and the content container are r55, so the
# rounding must come from the surface the video actually sits in.
assert 'CGFloat radius=material.layer.cornerRadius;' in module
assert 'if(!(radius>0))radius=card.layer.cornerRadius;' in module
assert 'if(self.host.layer.cornerRadius!=radius)self.host.layer.cornerRadius=radius;' in module
assert 'self.host.layer.masksToBounds=YES;' in module
# Defence in depth: no failure in this channel may ever abort SpringBoard.
assert '@try {[LMVCopyVaultPanelVideo update];}' in module
assert '@catch(NSException *exception) {[LMVCopyVaultPanelVideo detach];}' in module
assert 'mode=%@' in module
assert 'UIViewAutoresizing mask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;' in module
# Our own host can never be mistaken for the card while the search walks the tree.
assert 'static NSInteger const LMVCVPanelHostTag=0x5A19;' in module
assert 'if(child.tag==LMVCVPanelHostTag || child.hidden || child.alpha<.01)continue;' in module
assert 'self.tag=LMVCVPanelHostTag;' in module
# Never interactive, never a poster substitute for a live panel background.
assert 'self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;' in module
assert 'self.playback.posterLayer.hidden=YES;' in module
assert 'BOOL live=self.playback.player && self.playback.playerLayer.readyForDisplay && !self.playback.error;' in module
# Preferences: own switch, own material, master switch respected, default off.
assert 'CFSTR("CVBackgroundEnabled")' in module
assert 'LMVCVPanelPath=LMVCCSelectedPath(@"CVVideo");' in module
assert 'LMVCVPanelRevision=LMVLockVideoRevision(LMVCVPanelPath);' in module
assert 'LMVCVPanelEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&' in module
# No player/UI while the channel is off, and a poll that never runs hot when idle.
assert 'if(!LMVCVPanelEnabled || !LMVCVPanelPath.length || !LMVCVPanelRevision.length) {' in module
assert 'if(!LMVCopyVaultPanelVideo)LMVCopyVaultPanelVideo=[LMVCopyVaultPanelVideoManager new];' in module
assert 'NSTimeInterval want=LMVCVPanelEnabled?.1:.5;' in module
assert 'dispatch_async(dispatch_get_main_queue()' not in module  # poll on the main run loop only

# ---- wiring ---------------------------------------------------------------
assert '#include "LMVCopyVaultPanelVideo.h"' in tweak
assert '    LMVCopyVaultPanelVideoRefresh(reload);' in tweak
assert tweak.count('LMVCopyVaultPanelVideoSuspend();') == 2          # suspend + resign-active
assert '        LMVCopyVaultPanelVideoInstallHooks();' in tweak
assert 'LMVAudioConsume(@"CV",cvPanel.path,cvPanel.revision,cvPanelVisible,cvPanel.player.currentTime);' in tweak
assert 'return @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu",@"SquidPanel",@"AT",@"CV"];' in audio

# ---- the two settings surfaces -------------------------------------------
assert '[cvEnabled setProperty:@"CVBackgroundEnabled" forKey:@"key"];' in prefs
assert '[cvEnabled setProperty:@NO forKey:@"default"];' in prefs
assert 'cvMaterial.buttonAction = @selector(switchCV:);' in prefs
assert '- (void)switchCV:(PSSpecifier *)specifier { [self switchTarget:@"CV"]; }' in prefs
assert '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"CopyVault 面板背景视频"]];' in prefs
assert '"SquidPanel", @"AT", @"CV"] containsObject:target];' in prefs, 'CV is a selectable material target'
assert '[self appendAudioForTarget:@"CV" title:@"播放"];' in prefs
import re
at_group = '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"AT 背景视频"]];'
cv_group = '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"CopyVault 面板背景视频"]];'
egg_group = '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"小彩蛋"]];'
assert prefs.index(at_group) < prefs.index(cv_group) < prefs.index(egg_group), \
    'the CV group sits directly below the AT group'
assert re.search(r'@"CV": @"CopyVault 面板背景视频"', prefs), 'the applied-material alert names the CV channel'
assert re.search(r'@"CV": @""', prefs), 'the CV material fallback is empty (nothing selected by default)'

# ---- floating panel -------------------------------------------------------
assert 'static NSInteger LMVEasterCVSection(void) { return LMVEasterATSection() + 1; }' in panel
assert 'static NSInteger LMVEasterDisplaySection(void) { return LMVEasterCVSection() + 1; }' in panel
assert 'if (section == LMVEasterCVSection()) return 4;' in panel
assert 'if (section == LMVEasterCVSection()) return @"CopyVault 面板背景视频";' in panel
cv_cells = panel[panel.index('if (index.section == LMVEasterCVSection()) {'):panel.index('if (index.section == LMVEasterControlCenterSection()) {')]
assert 'cell.textLabel.text = @"CopyVault 面板背景视频";' in cv_cells and 'cell.textLabel.text = @"切换 CopyVault 素材";' in cv_cells
assert 'toggle.on = [LMVEasterRead(@"CVBackgroundEnabled") boolValue];' in cv_cells
assert 'id selected = LMVEasterRead(@"CVVideo");' in cv_cells, 'the panel material row reads its own key'
assert '(row == 2 || row == 3)) return @"CV";' in panel
assert 'else if (toggle.tag == LMVEasterCVSection()) key = @"CVBackgroundEnabled";' in panel
selection = panel[panel.index('- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:'):]
assert 'key = @"CVVideo";' in selection and 'index.section == LMVEasterCVSection()' in selection
assert re.findall(r'@"(.*?)"', panel[panel.index('static NSArray *LMVEasterAudioTargets('):panel.index('static NSString *LMVEasterAudioTarget(')])[-2:] == ['AT', 'CV'], \
    'the CV sound channel closes the panel audio list'

# ---- shared material plumbing ----------------------------------------------
assert 'for (NSString *target in @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu",@"SquidPanel",@"AT",@"CV"])' in delete
assert re.search(r'@"AT":@"",@"CV":@""\}', delete), 'the CV selection is cleared when its material is deleted'

print('PASS: CopyVault clipboard-panel channel - settings (Settings + floating panel), '
      'material/audio plumbing, and the 1.43 mount (own-window search, parked-card '
      'rejection, material-derived corner radius, above-blur / below-content placement)')
