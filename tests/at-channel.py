#!/usr/bin/env python3
"""1.26: the AppTools (AT) pop-up channel - settings, plumbing, and (1.28) the mount.

AppTools presents its panel INTO an existing window (SBHomeScreenWindow), so it is
not a window at all and the window list never changes. 1.26 stored the settings and
added the diagnostics that found the shape; 1.28 mounts the video, so the scope guard
that pinned "no AT player yet" is now replaced by the wiring and module contracts.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
panel = (root / 'LMVEasterPanel.h').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
audio = (root / 'LMVMediaAudio.h').read_text()
delete = (root / 'LockMessageVideoPrefs/LMVMaterialDeletion.h').read_text()
desktop = (root / 'LMVDesktopVideo.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
module = (root / 'LMVATPanelVideo.h').read_text()


def body(source, anchor):
    start = source.index(anchor)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


# ---- Settings app -----------------------------------------------------------
at_group = '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"AT 背景视频"]];'
assert at_group in prefs, 'the AT group exists in Settings'
squid_group = '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"鱿鱼面板背景视频"]];'
egg_group = '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"小彩蛋"]];'
assert prefs.index(squid_group) < prefs.index(at_group) < prefs.index(egg_group), \
    'the AT group sits directly below the Squid panel group'
cv_group = '[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"CopyVault 面板背景视频"]];'
assert prefs.index(at_group) < prefs.index(cv_group) < prefs.index(egg_group), \
    'the CV group sits directly below the AT group'
at_section = prefs[prefs.index(at_group):prefs.index(cv_group)]
assert at_section.count('cell:PSSwitchCell') == 1 and at_section.count('cell:PSButtonCell') == 1
assert '[atEnabled setProperty:@"ATBackgroundEnabled" forKey:@"key"]' in at_section
assert '[atEnabled setProperty:@NO forKey:@"default"]' in at_section
assert 'atMaterial.buttonAction = @selector(switchAT:);' in at_section
assert '[self appendAudioForTarget:@"AT" title:@"播放"]' in at_section, 'sound switch + volume slider'
assert '- (void)switchAT:(PSSpecifier *)specifier { [self switchTarget:@"AT"]; }' in prefs
assert re.search(r'@"AT": @"AT 背景视频"', prefs), 'the applied-material alert names the AT channel'
assert re.search(r'@"AT": @""', prefs), 'the AT material fallback is empty (nothing selected by default)'

# ---- floating panel ---------------------------------------------------------
assert 'static NSInteger LMVEasterATSection(void) { return LMVEasterSquidPanelSection() + 1; }' in panel
assert 'static NSInteger LMVEasterCVSection(void) { return LMVEasterATSection() + 1; }' in panel
assert 'static NSInteger LMVEasterGlassSuiteSection(void) { return LMVEasterPhoneAssistSection() + 1; }' in panel
assert 'static NSInteger LMVEasterCCBorderSection(void) { return LMVEasterGlassSuiteSection() + 1; }' in panel
assert 'static NSInteger LMVEasterCopyLogXSection(void) { return LMVEasterCCBorderSection() + 1; }' in panel
assert 'static NSInteger LMVEasterDisplaySection(void) { return LMVEasterCopyLogXSection() + 1; }' in panel
assert 'if (section == LMVEasterATSection()) return 4;' in panel
assert 'if (section == LMVEasterATSection()) return @"AT 背景视频";' in panel
at_cells = panel[panel.index('if (index.section == LMVEasterATSection()) {'):panel.index('if (index.section == LMVEasterControlCenterSection()) {')]
assert 'cell.textLabel.text = @"AT 背景视频";' in at_cells and 'cell.textLabel.text = @"切换 AT 素材";' in at_cells
assert 'toggle.on = [LMVEasterRead(@"ATBackgroundEnabled") boolValue];' in at_cells
assert 'id selected = LMVEasterRead(@"ATVideo");' in at_cells, 'the panel material row reads its own key'
mapping = body(panel, 'static NSString *LMVEasterAudioTarget(')
assert '(row == 2 || row == 3)) return @"AT";' in mapping
assert 'else if (toggle.tag == LMVEasterATSection()) key = @"ATBackgroundEnabled";' in panel
selection = panel[panel.index('- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:'):]
assert 'key = @"ATVideo";' in selection and 'index.section == LMVEasterATSection()' in selection
targets = re.findall(r'@"(.*?)"', body(panel, 'static NSArray *LMVEasterAudioTargets('))
assert targets[-6:] == ['CV', 'Myrtle', 'PA', 'GS', 'CCBorder', 'CopyLogX'], 'AT, CopyVault, Myrtle, GlassSuiteX, CCBorder and CopyLogX close the list'

# ---- shared material plumbing ----------------------------------------------
assert '"SquidPanel", @"AT", @"CV", @"Myrtle", @"PA", @"GS", @"CCBorder", @"CopyLogX"] containsObject:target];' in prefs, 'AT (and the 1.43 CopyVault one) are selectable material targets'
assert 'for (NSString *target in @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu",@"SquidPanel",@"AT",@"CV"])' in delete
assert re.search(r'@"AT":@"",@"CV":@""\}', delete), 'the AT (and 1.43 CopyVault) selections are cleared when their material is deleted'
assert '"HomeMenu",@"SquidPanel",@"AT",@"CV",@"Myrtle",@"PA",@"GS",@"CCBorder",@"CopyLogX"];' in audio, 'the audio chain list carries AT and the 1.43 CopyVault channel'

# ---- 1.28: the mount is wired now ------------------------------------------
assert '#import "LMVATPanelVideo.h"' in tweak, 'the AT panel player is wired'
assert 'LMVAudioConsume(@"AT"' in tweak, 'the AT audio consumer exists'
assert (root / 'LMVATPanelVideo.h').exists(), 'the AT mount module exists'
assert '    LMVATPanelVideoRefresh(reload);' in tweak
assert tweak.count('LMVATPanelVideoSuspend();') == 2, 'suspend + resign-active'
assert '        LMVATPanelVideoInstallHooks();' in tweak

# ---- the mount module ------------------------------------------------------
# Unlike SquidGesturePro the panel owns NO window: the search starts at the window
# it presents INTO, and only TransitionView subtrees are searched (1.27: AppTools
# drops its TransitionView one or two levels BELOW the window).
assert 'if([NSStringFromClass(window.class) containsString:@"SBHomeScreen"])return window;' in module
assert 'static void LMVATPanelTransitionRoots(UIView *view,NSUInteger depth,NSMutableArray<UIView *> *found,NSUInteger *nodes) {' in module
assert 'if(!view || depth>4 || *nodes>800)return;' in module
assert 'if([NSStringFromClass(view.class) containsString:@"TransitionView"])[found addObject:view];' in module
assert 'if(!roots.count)return nil;   // no presentation on screen -> no panel' in module
# No private class of that tweak is hooked or guessed.
assert 'MSHookMessageEx' not in module and 'class_getInstanceMethod' not in module
# The card is the largest VISIBLE descendant that does NOT fill the window, so a
# panel that grows with its icons is followed by construction, not by a stored rect.
assert 'static UIView *LMVATPanelCard(UIWindow *window) {' in module
assert 'if(frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1)continue;' in module
assert 'if(frame.size.width<bounds.size.width*.5 || frame.size.height<bounds.size.height*.08)continue;' in module
assert 'static CGFloat LMVATPanelVisibleArea(CGRect frame,CGRect bounds) {' in module
assert 'return visible/total>=.5?visible:0;' in module
assert 'CGFloat visible=LMVATPanelVisibleArea(frame,bounds);' in module
assert 'if(visible<=0)continue;' in module
assert 'if(visible>bestArea){bestArea=visible;best=child;}' in module
assert 'static UIView *LMVATPanelMaterial(UIView *root,UIWindow *window) {' in module
assert 'UIView *material=LMVATPanelMaterial(card,window);' in module
assert 'if(!material)material=LMVATPanelMaterial(window,window);' in module
assert 'vis=%.0f' in module
# A UIVisualEffectView refuses direct subviews - adding one raises, and an exception
# in a run-loop callback aborts SpringBoard (the 1.25 crash). Never the container.
assert '- (BOOL)insertHostInto:(UIView *)container at:(NSUInteger)index {' in module
assert 'if(!container || [container isKindOfClass:UIVisualEffectView.class])return NO;' in module
assert '@try {[container insertSubview:self.host atIndex:index];}' in module
assert '@catch(NSException *exception) {[self.host removeFromSuperview];return NO;}' in module
# UNDER the icons but ABOVE that material - the same placement 1.24 settled.
assert 'if(![child isKindOfClass:UIVisualEffectView.class] || child.hidden || child.alpha<.01)continue;' in module
assert 'UIView *content=((UIVisualEffectView *)material).contentView;' in module
assert 'container=content;index=0;target=content.bounds;mode=@"content";' in module
assert 'index=(NSUInteger)(near+1);target=material.frame;mode=@"above-material";' in module
assert 'if(!CGRectEqualToRect(self.host.frame,target))self.host.frame=target;' in module
# Defence in depth: no failure in this channel may abort SpringBoard.
assert '@try {[LMVATPanelVideo update];}' in module
assert '@catch(NSException *exception) {[LMVATPanelVideo detach];}' in module
assert 'mode=%@' in module
assert 'UIViewAutoresizing mask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;' in module
assert 'if(self.host.layer.cornerRadius!=card.layer.cornerRadius)self.host.layer.cornerRadius=card.layer.cornerRadius;' in module
# Our own host can never be mistaken for the card while the search walks the tree.
assert 'static NSInteger const LMVATPanelHostTag=0x5A18;' in module
assert 'if(child.tag==LMVATPanelHostTag || child.hidden || child.alpha<.01)continue;' in module
assert 'self.tag=LMVATPanelHostTag;' in module
# Never interactive, never a poster substitute for a live panel background.
assert 'self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;' in module
assert 'self.playback.posterLayer.hidden=YES;' in module
assert 'BOOL live=self.playback.player && self.playback.playerLayer.readyForDisplay && !self.playback.error;' in module
# Preferences: own switch, own material, master switch respected, default off.
assert 'CFSTR("ATBackgroundEnabled")' in module
assert 'LMVATPanelPath=LMVCCSelectedPath(@"ATVideo");' in module
assert 'LMVATPanelRevision=LMVLockVideoRevision(LMVATPanelPath);' in module
assert 'LMVATPanelEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&' in module
# No player/UI while the channel is off, and a poll that never runs hot when idle.
assert 'if(!LMVATPanelEnabled || !LMVATPanelPath.length || !LMVATPanelRevision.length) {' in module
assert 'if(!LMVATPanelVideo)LMVATPanelVideo=[LMVATPanelVideoManager new];' in module
assert 'NSTimeInterval want=LMVATPanelEnabled?.1:.5;' in module
assert 'dispatch_async(dispatch_get_main_queue()' not in module  # main run loop only

# ---- 1.40: the desktop long-press menu is NOT the AppTools panel ------------
# The system context menu is presented into the very same SBHomeScreenWindow
# AppTools uses, through a *_ContextMenu*TransitionView whose name also contains
# "TransitionView". Without this guard the AT video - and its SOUND - latched onto
# the long-press menu card and played under a menu the channel has nothing to do
# with. A system menu is never the panel: its subtree is skipped, and any
# *_ContextMenu* view is rejected as a card.
assert 'static BOOL LMVATPanelSystemMenu(UIView *view) {' in module
# 2.03: system alerts (the "iPhone 通话" hand-off sheet) used to be taken for the
# AppTools panel and got a video background: card=_UIAlertControllerPhoneTVMacView.
assert 'if([name containsString:@"ContextMenu"])return YES;' in module
assert 'if([name containsString:@"Alert"])return YES;' in module
assert 'if([name containsString:@"PhoneTVMac"])return YES;' in module
# and the exclusion must cut the WHOLE subtree - the inner plain UIView won the
# area contest on the next poll
assert 'if(LMVATPanelSystemMenu(child))continue;\n                [pending addObject:child];' in module
assert 'if(LMVATPanelSystemMenu(view))return;' in module, 'menu subtrees are never AT transition roots'
assert 'if(LMVATPanelSystemMenu(child))continue;' in module, 'a *_ContextMenu* view is never the AT card'


def has(text, token, message):
    assert token in text, message


# ---- 1.26 diagnostics: find a pop-up that is NOT a window -------------------
has(desktop, 'static NSString *LMVDesktopOverlayShape(UIView *view,NSUInteger depth) {',
    'the pop-up shape printer exists')
has(desktop, 'view.frame.size.width,view.frame.size.height,view.layer.cornerRadius,',
    'the printer carries frame AND corner radius (the mount needs both)')
has(desktop, 'if (depth>=4 || view.subviews.count==0) return out;', 'the tree goes four levels deep')
has(desktop, '@"desktop-overlay %@"', 'the overlay diagnostic line exists')
has(desktop, 'static void LMVDesktopFindOverlayViews(UIView *view,NSUInteger depth,NSMutableArray<UIView *> *found,NSUInteger *nodes) {',
    'the overlay finder recurses the whole view tree (not just window.subviews)')
has(desktop, 'if ([name containsString:@"TransitionView"] || [name containsString:@"Overlay"]) [found addObject:view];',
    'presentation containers are recognised by name at any depth')
has(desktop, 'LMVDesktopFindOverlayViews(window,0,found,&nodes);',
    'the finder is called once per window, then every match is shaped')
has(desktop, 'for (UIWindow *window in everyWindow) {', 'legacy (scene-less) windows are walked too')
has(desktop, '[everyWindow containsObject:window]) [everyWindow addObject:window];',
    'scene and legacy window lists are merged without duplicates')
has(desktop, 'if (scenes.length>4000) {', 'the shape dump no longer drops whole windows at 1500 characters')
has(desktop, 'window.frame.size.width,window.frame.size.height,', 'the window list carries frames')
has(desktop, '[windowList appendFormat:@"%@@%.0f,%.0f,%.0f,%.0f ",NSStringFromClass(window.class),',
    'the window list carries the frame of every window')
assert desktop.index('static NSString *LMVDesktopOverlayShape(UIView *view') < \
    desktop.index('static CGRect LMVDesktopCoverRect('), \
    'the printer is a FILE-SCOPE function, not a nested definition inside update (the 1.26 CI failure)'

print('PASS: AT pop-up channel - settings (Settings + floating panel), material/audio plumbing, '
      'the pop-up diagnostics and the 1.28 mount (TransitionView-only search into '
      'SBHomeScreenWindow, under the icons / above the material), and the 1.40 scope '
      'guard that keeps the SYSTEM long-press menu out of the AT channel')
