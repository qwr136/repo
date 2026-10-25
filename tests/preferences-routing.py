#!/usr/bin/env python3
"""Verify entry metadata and execute the actual selection method with Foundation doubles on macOS."""
from pathlib import Path
import plistlib, re, platform, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root/'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
entry = plistlib.loads((root/'layout/Library/PreferenceLoader/Preferences/LockMessageVideoPrefs.plist').read_bytes())['entry']
info = plistlib.loads((root/'LockMessageVideoPrefs/Info.plist').read_bytes())
assert entry['bundle'] == info['CFBundleExecutable'] == 'LockMessageVideoPrefs'
# 2.95: the two-level menu is gone. 「设置视频背景」was removed outright and
# 「桌面视频背景」no longer has its own level - the entry IS that page, so the
# detail class and NSPrincipalClass must both point at it, and the old menu plus
# the settings-video page must not exist at all.
assert entry['detail'] == info['NSPrincipalClass'] == 'LMVPRootListController'
assert not (root/'LockMessageVideoPrefs/LMVMenuListController.h').exists()
assert not (root/'LockMessageVideoPrefs/LMVMenuListController.m').exists()
assert not (root/'LockMessageVideoPrefs/LMVSettingsVideoController.h').exists()
assert not (root/'LockMessageVideoPrefs/LMVSettingsVideo.h').exists()
assert not (root/'LMVSettingsVideoChannel.h').exists()
assert 'openSettingsVideo:' not in source and 'openDesktop:' not in source
assert entry['cell'] == 'PSLinkCell' and entry['isController'] is True
assert not {'action', 'buttonAction', 'loadAction', 'controller'} & entry.keys()
assert re.search(r'@interface LMVPRootListController : PSListController', source)
assert 'loadSpecifiersFromPlistName' not in source
assert 'Resources/Root.plist' not in (root/'Makefile').read_text()
assert not (root/'Resources/Root.plist').exists()  # Theos also copies Resources automatically.
control = dict(line.split(': ',1) for line in (root/'control').read_text().splitlines() if ': ' in line)
assert info['CFBundleVersion'] == info['CFBundleShortVersionString'] == control['Version']
# 4.2.0: the sixteen per-channel switch actions collapsed into one that reads the
# channel from the row id, and the five colour actions into one that reads the key
# from LMVTextColorRows(). The page still owns every button.
actions = set(re.findall(r'@selector\((switch\w+:|open\w+:|chooseVideo:|openMaterialPath:|openEaster:|openTuneList:)\)', source))
assert actions == {'switchTargetFromRow:', 'openTextColorFromRow:', 'chooseVideo:', 'openMaterialPath:', 'openEaster:', 'openTuneList:'}, actions
assert len(actions) == 6, actions
assert 'static NSArray<NSString *> *LMVSectionTargets(void) { return LMVSectionChannelIDs(); }' in source
assert 'LMVChannelTitles()[target]' in source and 'hasSuffix:@"背景"' in source
assert '@[@"切换素材", @"切换素材", @"切换素材", @"切换素材", @"切换素材"]' in source
CHANNELS = (root / 'LockMessageVideoPrefs/LMVChannels.h').read_text()
for target, title in [('LockScreen', '锁屏背景'), ('Desktop', '桌面背景'), ('ControlCenterDark', '控制中心深色背景'), ('ControlCenterLight', '控制中心浅色背景'), ('HomeMenu', '长按菜单背景'), ('SquidPanel', 'SquidGesture Pro背景'), ('AT', 'AppTools背景'), ('CV', 'CopyVault背景')]:
    assert f'@"id": @"{target}"' in CHANNELS and f'@"title": @"{title}"' in CHANNELS
    # 4.2.0: one action serves every channel; it reads the target from the row id.
    assert '- (void)switchTargetFromRow:(PSSpecifier *)specifier {' in source
    assert 'LMVChannelLegacyDefaults()' in source
    assert target + 'Opacity' not in source
assert '[enabled setProperty:@NO forKey:@"default"]' in source
assert '[LMVSectionTargets()[i] stringByAppendingString:@"BackgroundEnabled"]' in source
cc_start = source.index('PSSpecifier *controlCenter = [PSSpecifier groupSpecifierWithName:@"控制中心背景"];')
# 4.2.0: the panel sections that follow are generated, so the block ends where the
# generated loop begins.
cc_end = source.index('for (NSDictionary *row in LMVStandaloneChannelRows()) {', cc_start)
cc_section = source[cc_start:cc_end]
assert cc_start > source.index('for (NSUInteger i = 0; i < LMVSectionTargets().count; i++)')
assert cc_section.count('cell:PSSwitchCell') == 1 and cc_section.count('cell:PSButtonCell') == 2
assert '[controlCenterEnabled setProperty:@"ControlCenterBackgroundEnabled" forKey:@"key"]' in cc_section
assert '[controlCenterEnabled setProperty:@NO forKey:@"default"]' in cc_section
assert '按系统深浅色模式自动选择素材；未选择对应模式素材时保留系统背景。' in cc_section
assert 'forKey:@"footerText"' in cc_section
for mode, title in [('Dark', '深色'), ('Light', '浅色')]:
    assert "@\"切换素材\"" in cc_section
    assert f'controlCenter{mode}.buttonAction = @selector(switchTargetFromRow:);' in cc_section
for forbidden in ('Opacity', 'Blur', 'PSSliderCell', 'ControlCenterDarkBackgroundEnabled', 'ControlCenterLightBackgroundEnabled'):
    assert forbidden not in cc_section
for mode in ('Dark', 'Light'):
    assert f'[self appendAudioForTarget:@"ControlCenter{mode}"' in cc_section
import_callback = source[source.index('- (void)picker:(PHPickerViewController *)picker didFinishPicking:'):]
import_targets = re.findall(r'@"([^"]+)"', re.search(r'for \(NSString \*target in @\[(.*?)\]\)', import_callback).group(1))
assert import_targets == ['Message', 'Options', 'Clear']
assert 'ControlCenter' not in import_callback and 'LockScreen' not in import_callback and 'Desktop' not in import_callback and 'HomeMenu' not in import_callback
# 4.2.0: the nine panel sections below the control-centre block are generated from
# the channel table, so a section exists if and only if its row says so. The contract
# is now the table columns plus the one generated block, instead of nine hand-written
# blocks that had to agree with each other.
loop_start = source.index('for (NSDictionary *row in LMVStandaloneChannelRows()) {')
loop_end = source.index('PSSpecifier *tuneGroup', loop_start)
generated = source[loop_start:loop_end]
assert 'groupSpecifierWithName:title' in generated
assert '[enabled setProperty:[target stringByAppendingString:@"BackgroundEnabled"] forKey:@"key"]' in generated
assert '[enabled setProperty:@NO forKey:@"default"]' in generated
assert '[self materialRowForTarget:target]' in generated
assert '[self appendAudioForTarget:target title:@"播放"]' in generated
assert '[self textColorRowWithID:colourID]' in generated
assert 'setProperty:footer forKey:@"footerText"' in generated
panel_rows = [('HomeMenu',   '长按菜单背景',       ''),
              ('SquidPanel', 'SquidGesture Pro背景',           'SquidTextColor'),
              ('AT',         'AppTools背景',                ''),
              ('CV',         'CopyVault背景',      'CVTextColor'),
              ('Myrtle',     'Myrtle背景',         ''),
              ('PA',         '电话助手背景',        'PATextColor'),
              ('GS',         'GlassSuiteX背景',    'GSTextColor'),
              ('CCBorder',   'CCBorder背景',           ''),
              ('CopyLogX',   'CopyLogX背景',           'CopyLogXTextColor')]
standalone = re.findall(r'@"id": @"(\w+)"[^}]*@"standalone": @YES', CHANNELS)
assert standalone == [row[0] for row in panel_rows], standalone
for ident, title, colour in panel_rows:
    row = re.search(r'@"id": @"' + ident + r'".*', CHANNELS).group(0)
    assert f'@"title": @"{title}"' in row, ident
    assert '@"audio": @YES' in row, ident
    assert (f'@"textColor": @"{colour}"' if colour else '@"textColor": @""') in row, ident
# the debug size switches the 2.29 / 2.30 builds carried are gone
assert 'GSDebugSize' not in source and 'CCBorderDebugSize' not in source
assert '调试：记录弹窗尺寸' not in source
for footer in ('开启诊断日志后，挂载状态会写入 shared-render.log（gs-panel 行）。',
               '控制中心长按菜单的背景视频；诊断日志会带 module= 标识。',
               '剪贴板面板（411×470 底部卡片）的背景视频；诊断日志会写入 clx-panel。'):
    assert footer in CHANNELS, footer
display_start = source.index('[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"小彩蛋显示设置"]];')
egg_start = source.index('[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"小彩蛋"]];')
display_section=source[display_start:source.index('[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"素材库"]];')]
assert '显示场景与图片旋转' in display_section and 'openEaster:' in display_section
assert 'EasterEggImageSettings' in display_section
assert 'forKey:@"buttonAction"' not in source and 'forKey:@"action"' not in source
assert 'if (!selected && !legacyMessage) CFPreferencesSetAppValue' in import_callback
for controller in ['LMVPRootListController.m']:
    representation=(root/'LockMessageVideoPrefs'/controller).read_text()
    assert 'config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;' in representation
    assert 'loadFileRepresentationForTypeIdentifier:@"public.movie"' in representation
assert '消息、选项、清除视频透明度' in source
assert 'return [LMVChannelIDs() containsObject:target];' in source
assert 'if (![target isKindOfClass:NSString.class] || !target.length) return NO;' in source
allowed_target = source[source.index('static BOOL LMVMaterialTargetAllowed('):source.index('static void LMVNotifyFor(')]
assert 'return [LMVChannelIDs() containsObject:target];' in allowed_target
assert 'if (!LMVMaterialTargetAllowed(target)) return;' in source
assert 'if (self.presentedViewController || !LMVMaterialTargetAllowed(target)) return;' in source
selection = source[source.index('- (void)selectFile:'):source.index('- (void)chooseVideo:')]
assert selection.count('CFPreferencesSetAppValue(') == 1
assert 'NSString *key = [target stringByAppendingString:@"Video"];' in selection
assert 'if (![selected isKindOfClass:NSString.class]) selected = legacy[target] ?: @"";' in selection
assert 'LMVCreateMaterialPicker(selected, YES' in selection and 'target:target' in selection
assert 'picker.showsThumbnails = NO' not in selection and 'picker.pushed = YES' not in selection
assert 'clearOriginals' not in source and '清空原素材' not in source
for action in actions:
    assert re.search(r'- \(void\)' + re.escape(action) + r'\(PSSpecifier \*\)specifier', source), action
assert 'row.target = self;' in source and 'row.detailControllerClass = Nil;' in source
assert 'row.controllerLoadAction = NULL;' in source and '[row removePropertyForKey:key];' in source
assert 'row->action' not in source  # Private ivar is absent from the framework linker stub.
start = source.index('- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:')
end = source.index('\n- (id)enabled:', start)
method = source[start:end]
assert 'invoke(self, action, row);' in method
assert method.index('invoke(self, action, row);') < method.index('[super tableView:')
assert '[signature getArgumentTypeAtIndex:2][0] != \'@\'' in method
print('PASS: entry/principal class, version, programmatic-only rows, five targets/eleven action selectors, independent CC and HomeMenu sections with empty/off defaults, imports limited to Message/Options/Clear and stale route cleanup')
if platform.system() != 'Darwin':
    print('Foundation runtime routing test requires macOS; runs in GitHub Actions')
    raise SystemExit(0)
preamble = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#include <string.h>
@TARGET_FUNCTIONS@
enum { PSButtonCell = 13, PSSwitchCell = 6 };
@interface PSSpecifier : NSObject
@property NSInteger cellType;
@property id target;
@property SEL buttonAction;
@property NSMutableDictionary *properties;
- (id)propertyForKey:(NSString *)key;
@end
@implementation PSSpecifier
- (id)propertyForKey:(NSString *)key { return self.properties[key]; }
@end
@interface UITableView : NSObject
@property NSInteger deselections;
- (void)deselectRowAtIndexPath:(NSIndexPath *)path animated:(BOOL)animated;
@end
@implementation UITableView
- (void)deselectRowAtIndexPath:(NSIndexPath *)path animated:(BOOL)animated { self.deselections++; }
@end
@interface PSListController : NSObject
@property PSSpecifier *testRow;
@property NSInteger superSelections;
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)path;
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path;
@end
@implementation PSListController
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)path { return self.testRow; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path { self.superSelections++; }
@end
@interface LMVPRootListController : PSListController
@property NSInteger calls;
@property PSSpecifier *lastRow;
@property(copy) NSString *lastTarget;
@end
@implementation LMVPRootListController
'''
channels = '\n'.join(line for line in (root / 'LockMessageVideoPrefs/LMVChannels.h').read_text().splitlines()
                     if not line.startswith('#import') and not line.startswith('#pragma'))
preamble = preamble.replace('@TARGET_FUNCTIONS@', channels + '\n' + re.search(r'static NSArray<NSString \*> \*LMVSectionTargets\(void\) \{[^\n]+\}', source).group(0) + '\n' + allowed_target)
# 4.2.0: the sixteen per-channel switch methods collapsed into one data-driven
# dispatcher, so the old "each selector reaches its own @\"xxx\" target" extraction
# no longer applies. Keep a plain stub for the dispatch loop (records the call), and
# compile the REAL switchTargetFromRow: body under a renamed selector so the runtime
# test can verify the material-row id strips back to its target.
real_switch = re.search(r'- \(void\)switchTargetFromRow:\(PSSpecifier \*\)specifier \{[\s\S]*?\n\}', source).group(0).replace('- (void)switchTargetFromRow:', '- (void)realSwitchTargetFromRow:')
switch_actions = sorted(action for action in actions if action.startswith('switch'))
switch_handlers = ['- (void)%s(PSSpecifier *)specifier { self.calls++; self.lastRow = specifier; self.lastTarget = nil; }' % action for action in switch_actions]
other_handlers = ['- (void)%s(PSSpecifier *)specifier { self.calls++; self.lastRow = specifier; self.lastTarget = nil; }' % action for action in sorted(actions) if action not in switch_actions]
handlers = '\n'.join(['- (void)switchTarget:(NSString *)target { self.calls++; self.lastRow = self.testRow; self.lastTarget = target; }', '- (void)badScalar:(NSInteger)value { self.calls++; }', real_switch] + switch_handlers + other_handlers)
tests = r'''
@end
int main(void) { @autoreleasepool {
    for (NSString *target in @[@"Message", @"Options", @"Clear", @"LockScreen", @"Desktop", @"ControlCenterDark", @"ControlCenterLight", @"HomeMenu", @"SquidPanel", @"AT", @"CV", @"Myrtle"]) assert(LMVMaterialTargetAllowed(target));
    for (id bad in @[@"", @"Unknown", @"HomeMenuVideo", @"HomeMenuBackgroundEnabled", @"homemenu", @"../HomeMenu", @42, NSNull.null]) assert(!LMVMaterialTargetAllowed(bad));
    assert(!LMVMaterialTargetAllowed(nil));
    LMVPRootListController *controller = [LMVPRootListController new];
    UITableView *table = [UITableView new];
    PSSpecifier *row = [PSSpecifier new];
    row.cellType = PSButtonCell; row.target = controller; row.properties = [NSMutableDictionary new];
    controller.testRow = row;
    NSArray *selectors = @SELECTORS@;
    for (NSString *selector in selectors) {
        row.buttonAction = NSSelectorFromString(selector);
        [controller tableView:table didSelectRowAtIndexPath:nil];
        assert(controller.lastTarget == nil);
    }
    NSInteger expectedCalls = selectors.count;
    assert(controller.calls == expectedCalls && controller.lastRow == row && controller.superSelections == 0 && table.deselections == expectedCalls);
    row.properties[@"enabled"] = @NO;
    [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.calls == expectedCalls);
    [row.properties removeObjectForKey:@"enabled"];
    row.target = [NSObject new];
    [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.calls == expectedCalls);
    row.target = controller;
    for (NSString *selector in @[@"staleControllerAction:", @"switchUnknownTarget:", @"badScalar:"]) {
        row.buttonAction = NSSelectorFromString(selector);
        [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.calls == expectedCalls);
    }
    row.buttonAction = @selector(description);
    [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.calls == expectedCalls);
    row.buttonAction = NULL;
    [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.calls == expectedCalls && controller.superSelections == 0);
    row.cellType = PSSwitchCell;
    [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.superSelections == 1);
    // 4.2.0: one data-driven switch dispatcher. The material row id is the target
    // plus "Material"; the dispatcher must strip it and reach switchTarget:target,
    // and must ignore ids without that suffix. Kept after the dispatch-safety
    // checks above so the calls count they assert stays at the six shared actions.
    for (NSString *target in @[@"HomeMenu", @"SquidPanel", @"AT", @"CV", @"Myrtle", @"PA", @"GS", @"CCBorder", @"CopyLogX"]) {
        row.buttonAction = @selector(realSwitchTargetFromRow:);
        row.properties[@"id"] = [target stringByAppendingString:@"Material"];
        [controller realSwitchTargetFromRow:row];
        assert([controller.lastTarget isEqualToString:target]);
    }
    row.buttonAction = @selector(realSwitchTargetFromRow:);
    row.properties[@"id"] = @"HomeMenu";  // suffix missing -> must not route
    NSInteger callsBeforeUnknown = controller.calls;
    [controller realSwitchTargetFromRow:row];
    assert(controller.calls == callsBeforeUnknown);
    [row.properties removeObjectForKey:@"id"];
    puts("PASS: actual button routing method, six shared action selectors (one data-driven switch dispatcher + one data-driven text-colour dispatcher), material-row id strips to its target, disabled/wrong target/stale/wrong signature/nil routes, superclass control handling (Foundation doubles, not UIKit)");
} return 0; }
'''.replace('@SELECTORS@', '@[' + ','.join('@"'+action+'"' for action in sorted(actions)) + ']')
with tempfile.TemporaryDirectory() as tmp:
    Path(tmp).joinpath('LMVPanelCommon.h').write_text(Path(__file__).resolve().parents[1].joinpath('LMVPanelCommon.h').read_text())
    src = Path(tmp)/'routing.m'; binary = Path(tmp)/'routing'
    src.write_text('#import "LMVPanelCommon.h"\n'+preamble + method + '\n' + handlers + tests)
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
