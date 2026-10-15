#!/usr/bin/env python3
"""Verify entry metadata and execute the actual selection method with Foundation doubles on macOS."""
from pathlib import Path
import plistlib, re, platform, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root/'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
entry = plistlib.loads((root/'layout/Library/PreferenceLoader/Preferences/LockMessageVideoPrefs.plist').read_bytes())['entry']
info = plistlib.loads((root/'LockMessageVideoPrefs/Info.plist').read_bytes())
assert entry['bundle'] == info['CFBundleExecutable'] == 'LockMessageVideoPrefs'
assert entry['detail'] == info['NSPrincipalClass'] == 'LMVPRootListController'
assert entry['cell'] == 'PSLinkCell' and entry['isController'] is True
assert not {'action', 'buttonAction', 'loadAction', 'controller'} & entry.keys()
assert re.search(r'@interface LMVPRootListController : PSListController', source)
assert 'loadSpecifiersFromPlistName' not in source
assert 'Resources/Root.plist' not in (root/'Makefile').read_text()
assert not (root/'Resources/Root.plist').exists()  # Theos also copies Resources automatically.
control = dict(line.split(': ',1) for line in (root/'control').read_text().splitlines() if ': ' in line)
assert info['CFBundleVersion'] == info['CFBundleShortVersionString'] == control['Version']
actions = set(re.findall(r'@selector\(((?:switch\w+|chooseVideo|openMaterialPath|openEaster|clearOriginals):)\)', source))
assert actions == {'switchMessage:', 'switchOptions:', 'switchClear:', 'switchLockScreen:', 'switchDesktop:', 'switchControlCenterDark:', 'switchControlCenterLight:', 'switchHomeMenu:', 'switchSquidPanel:', 'switchAT:', 'chooseVideo:', 'openMaterialPath:', 'openEaster:'}
assert len(actions) == 13
assert 'static NSArray<NSString *> *LMVTargets(void) { return @[@"Message", @"Options", @"Clear", @"LockScreen", @"Desktop"]; }' in source
assert '@[@"消息", @"选项", @"清除", @"锁屏", @"桌面"]' in source
assert '@[@"切换背景素材", @"切换选项素材", @"切换清除素材", @"切换锁屏素材", @"切换桌面素材"]' in source
for target, title in [('LockScreen', '锁屏背景'), ('Desktop', '桌面背景'), ('ControlCenterDark', '控制中心深色背景'), ('ControlCenterLight', '控制中心浅色背景'), ('HomeMenu', '桌面长按菜单视频背景'), ('SquidPanel', '鱿鱼面板背景视频'), ('AT', 'AT 背景视频')]:
    assert f'@"{target}": @"{title}"' in source
    assert f'- (void)switch{target}:(PSSpecifier *)specifier {{ [self switchTarget:@"{target}"]; }}' in source
    assert f'@"{target}": @""' in source
    assert target + 'Opacity' not in source
assert '[enabled setProperty:@NO forKey:@"default"]' in source
assert '[LMVTargets()[i] stringByAppendingString:@"BackgroundEnabled"]' in source
cc_start = source.index('PSSpecifier *controlCenter = [PSSpecifier groupSpecifierWithName:@"控制中心背景"];')
cc_end = source.index('[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"桌面长按菜单视频背景"]];', cc_start)
cc_section = source[cc_start:cc_end]
assert cc_start > source.index('for (NSUInteger i = 0; i < LMVTargets().count; i++)')
assert cc_section.count('cell:PSSwitchCell') == 1 and cc_section.count('cell:PSButtonCell') == 2
assert '[controlCenterEnabled setProperty:@"ControlCenterBackgroundEnabled" forKey:@"key"]' in cc_section
assert '[controlCenterEnabled setProperty:@NO forKey:@"default"]' in cc_section
assert '按系统深浅色模式自动选择素材；未选择对应模式素材时保留系统背景。' in cc_section
assert 'forKey:@"footerText"' in cc_section
for mode, title in [('Dark', '深色'), ('Light', '浅色')]:
    assert f'@"切换{title}模式素材"' in cc_section
    assert f'controlCenter{mode}.buttonAction = @selector(switchControlCenter{mode}:);' in cc_section
for forbidden in ('Opacity', 'Blur', 'PSSliderCell', 'ControlCenterDarkBackgroundEnabled', 'ControlCenterLightBackgroundEnabled'):
    assert forbidden not in cc_section
for mode in ('Dark', 'Light'):
    assert f'[self appendAudioForTarget:@"ControlCenter{mode}"' in cc_section
assert '[self appendAudioForTarget:@"HomeMenu"' in source
import_callback = source[source.index('- (void)picker:(PHPickerViewController *)picker didFinishPicking:'):]
import_targets = re.findall(r'@"([^"]+)"', re.search(r'for \(NSString \*target in @\[(.*?)\]\)', import_callback).group(1))
assert import_targets == ['Message', 'Options', 'Clear']
assert 'ControlCenter' not in import_callback and 'LockScreen' not in import_callback and 'Desktop' not in import_callback and 'HomeMenu' not in import_callback
home_start=source.index('[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"桌面长按菜单视频背景"]];')
display_start=source.index('[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"小彩蛋显示设置"]];')
egg_start=source.index('[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"小彩蛋"]];')
# 1.22: the SquidGesturePro panel group sits between the menu group and the egg.
squid_start=source.index('[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"鱿鱼面板背景视频"]];')
# 1.26: the AppTools (AT) pop-up group sits directly below the Squid panel one.
at_start=source.index('[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"AT 背景视频"]];')
assert home_start < squid_start < at_start < egg_start < display_start
home_section = source[home_start:squid_start]
assert cc_start < home_start < display_start
assert home_section.count('cell:PSSwitchCell') == 1 and home_section.count('cell:PSButtonCell') == 1
assert '[homeMenuEnabled setProperty:@"HomeMenuBackgroundEnabled" forKey:@"key"]' in home_section
assert '[homeMenuEnabled setProperty:@NO forKey:@"default"]' in home_section
assert 'homeMenuMaterial.buttonAction = @selector(switchHomeMenu:);' in home_section
assert '桌面长按菜单视频背景' in home_section and '切换长按菜单素材' in home_section
squid_section = source[squid_start:at_start]
assert squid_section.count('cell:PSSwitchCell') == 1 and squid_section.count('cell:PSButtonCell') == 1
assert '[squidPanelEnabled setProperty:@"SquidPanelBackgroundEnabled" forKey:@"key"]' in squid_section
assert '[squidPanelEnabled setProperty:@NO forKey:@"default"]' in squid_section
assert 'squidPanelMaterial.buttonAction = @selector(switchSquidPanel:);' in squid_section
assert '鱿鱼面板背景视频' in squid_section and '切换鱿鱼面板素材' in squid_section
# 1.26: the AT (AppTools pop-up) group - same switch/material/sound layout.
at_section = source[at_start:egg_start]
assert at_section.count('cell:PSSwitchCell') == 1 and at_section.count('cell:PSButtonCell') == 1
assert '[atEnabled setProperty:@"ATBackgroundEnabled" forKey:@"key"]' in at_section
assert '[atEnabled setProperty:@NO forKey:@"default"]' in at_section
assert 'atMaterial.buttonAction = @selector(switchAT:);' in at_section
assert 'AT 背景视频' in at_section and '切换 AT 素材' in at_section
assert '[self appendAudioForTarget:@"AT" title:@"播放"]' in at_section
display_section=source[display_start:source.index('[_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"素材库"]];')]
assert '显示场景与图片旋转' in display_section and 'openEaster:' in display_section
assert 'EasterEggImageSettings' in display_section
assert 'forKey:@"buttonAction"' not in source and 'forKey:@"action"' not in source
assert 'if (!selected && !legacyMessage) CFPreferencesSetAppValue' in import_callback
for controller in ['LMVPRootListController.m', 'LMVPVideoPickerController.m']:
    representation=(root/'LockMessageVideoPrefs'/controller).read_text()
    assert 'config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;' in representation
    assert 'loadFileRepresentationForTypeIdentifier:@"public.movie"' in representation
assert '消息、选项、清除视频透明度' in source
assert 'return [LMVTargets() containsObject:target] || [@[@"ControlCenterDark", @"ControlCenterLight", @"HomeMenu", @"SquidPanel", @"AT"] containsObject:target];' in source
assert 'if (![target isKindOfClass:NSString.class] || !target.length) return NO;' in source
allowed_target = source[source.index('static BOOL LMVMaterialTargetAllowed('):source.index('static void LMVNotify(')]
assert re.findall(r'@"([^\"]+)"', allowed_target) == ['ControlCenterDark', 'ControlCenterLight', 'HomeMenu', 'SquidPanel', 'AT']
assert 'if (!LMVMaterialTargetAllowed(target)) return;' in source
assert 'if (self.presentedViewController || !LMVMaterialTargetAllowed(target)) return;' in source
selection = source[source.index('- (void)selectFile:'):source.index('- (void)switchMessage:')]
assert selection.count('CFPreferencesSetAppValue(') == 1
assert 'NSString *key = [target stringByAppendingString:@"Video"];' in selection
assert 'if (![selected isKindOfClass:NSString.class]) selected = legacy[target] ?: @"";' in selection
assert 'picker.selected = selected;' in selection and 'target:target' in selection
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
preamble = preamble.replace('@TARGET_FUNCTIONS@', re.search(r'static NSArray<NSString \*> \*LMVTargets\(void\) \{[^\n]+\}', source).group(0) + '\n' + allowed_target)
# Compile the actual switch wrappers too, so each selector must reach its own target.
switch_actions = sorted(action for action in actions if action.startswith('switch'))
switch_handlers = [re.search(r'- \(void\)' + re.escape(action) + r'\(PSSpecifier \*\)specifier \{ \[self switchTarget:@"\w+"\]; \}', source).group(0) for action in switch_actions]
other_handlers = ['- (void)%s(PSSpecifier *)specifier { self.calls++; self.lastRow = specifier; self.lastTarget = nil; }' % action for action in sorted(actions) if action not in switch_actions]
handlers = '\n'.join(['- (void)switchTarget:(NSString *)target { self.calls++; self.lastRow = self.testRow; self.lastTarget = target; }', '- (void)badScalar:(NSInteger)value { self.calls++; }'] + switch_handlers + other_handlers)
tests = r'''
@end
int main(void) { @autoreleasepool {
    for (NSString *target in @[@"Message", @"Options", @"Clear", @"LockScreen", @"Desktop", @"ControlCenterDark", @"ControlCenterLight", @"HomeMenu", @"SquidPanel", @"AT"]) assert(LMVMaterialTargetAllowed(target));
    for (id bad in @[@"", @"Unknown", @"HomeMenuVideo", @"HomeMenuBackgroundEnabled", @"homemenu", @"../HomeMenu", @42, NSNull.null]) assert(!LMVMaterialTargetAllowed(bad));
    assert(!LMVMaterialTargetAllowed(nil));
    LMVPRootListController *controller = [LMVPRootListController new];
    UITableView *table = [UITableView new];
    PSSpecifier *row = [PSSpecifier new];
    row.cellType = PSButtonCell; row.target = controller; row.properties = [NSMutableDictionary new];
    controller.testRow = row;
    NSArray *selectors = @SELECTORS@;
    NSDictionary *targets = @{@"switchMessage:":@"Message", @"switchOptions:":@"Options", @"switchClear:":@"Clear", @"switchLockScreen:":@"LockScreen", @"switchDesktop:":@"Desktop", @"switchControlCenterDark:":@"ControlCenterDark", @"switchControlCenterLight:":@"ControlCenterLight", @"switchHomeMenu:":@"HomeMenu", @"switchSquidPanel:":@"SquidPanel", @"switchAT:":@"AT"};
    for (NSString *selector in selectors) {
        row.buttonAction = NSSelectorFromString(selector);
        [controller tableView:table didSelectRowAtIndexPath:nil];
        if (targets[selector]) assert([controller.lastTarget isEqualToString:targets[selector]]);
        else assert(controller.lastTarget == nil);
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
    puts("PASS: actual button routing method, all thirteen actions and ten actual switch wrappers including switchControlCenterDark:/switchControlCenterLight:/switchHomeMenu:/switchSquidPanel:/switchAT:, allowed/invalid material targets, disabled/wrong target/stale/wrong signature/nil routes, superclass control handling (Foundation doubles, not UIKit)");
} return 0; }
'''.replace('@SELECTORS@', '@[' + ','.join('@"'+action+'"' for action in sorted(actions)) + ']')
with tempfile.TemporaryDirectory() as tmp:
    src = Path(tmp)/'routing.m'; binary = Path(tmp)/'routing'
    src.write_text(preamble + method + '\n' + handlers + tests)
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
