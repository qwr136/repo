#!/usr/bin/env python3
"""1.26: the AppTools (AT) pop-up channel.

This release stores the AT settings and adds the diagnostics needed to FIND the
pop-up - AppTools presents its panel INTO an existing window (SBHomeScreenWindow),
so it is not a window at all and the window list never changes. The video mount
is the next release, so this file also pins that no AT player/wiring exists yet.
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
at_section = prefs[prefs.index(at_group):prefs.index(egg_group)]
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
assert 'static NSInteger LMVEasterDisplaySection(void) { return LMVEasterATSection() + 1; }' in panel
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
assert re.findall(r'@"(.*?)"', body(panel, 'static NSArray *LMVEasterAudioTargets('))[-1] == 'AT', \
    'the AT sound channel is the last audio target'

# ---- shared material plumbing ----------------------------------------------
assert '"SquidPanel", @"AT"] containsObject:target];' in prefs, 'AT is a selectable material target'
assert 'for (NSString *target in @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu",@"SquidPanel",@"AT"])' in delete
assert re.search(r'@"AT":@""\}', delete), 'the AT selection is cleared when its material is deleted'
assert '"HomeMenu",@"SquidPanel",@"AT"];' in audio, 'the audio chain list carries AT'

# ---- this release only STORES the settings ---------------------------------
assert 'ATVideo.h' not in tweak, 'no AT player is wired yet'
assert 'LMVAudioConsume(@"AT"' not in tweak, 'no AT audio consumer yet'
assert not (root / 'LMVATVideo.h').exists(), 'the AT mount module belongs to the next release'


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

print('PASS: AT pop-up channel settings (Settings + floating panel), material/audio plumbing, '
      'release-scope guard (settings only) and the pop-up diagnostics')
