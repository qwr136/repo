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
assert actions == {'switchMessage:', 'switchLockScreen:', 'switchOptions:', 'switchClear:', 'chooseVideo:', 'openMaterialPath:', 'openEaster:'}
assert len(actions) == 7
assert 'Desktop' not in source and '桌面' not in source
assert '@[@"Message", @"LockScreen", @"Options", @"Clear"]' in source
assert '@[@"消息", @"锁屏", @"选项", @"清除"]' in source
assert 'for (NSString *target in LMVTargets())' in source
assert 'if (![LMVTargets() containsObject:target]) return;' in source
assert 'if (self.presentedViewController || ![LMVTargets() containsObject:target]) return;' in source
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
print('PASS: entry/principal class, version, programmatic-only rows, seven action selectors and stale route cleanup')
if platform.system() != 'Darwin':
    print('Foundation runtime routing test requires macOS; runs in GitHub Actions')
    raise SystemExit(0)
preamble = r'''
#import <Foundation/Foundation.h>
#include <assert.h>
#include <string.h>
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
@end
@implementation LMVPRootListController
'''
handlers = '\n'.join('- (void)%s(PSSpecifier *)specifier { self.calls++; self.lastRow = specifier; }' % action for action in sorted(actions))
tests = r'''
@end
int main(void) { @autoreleasepool {
    LMVPRootListController *controller = [LMVPRootListController new];
    UITableView *table = [UITableView new];
    PSSpecifier *row = [PSSpecifier new];
    row.cellType = PSButtonCell; row.target = controller; row.properties = [NSMutableDictionary new];
    controller.testRow = row;
    NSArray *selectors = @SELECTORS@;
    for (NSString *selector in selectors) {
        row.buttonAction = NSSelectorFromString(selector);
        [controller tableView:table didSelectRowAtIndexPath:nil];
    }
    NSInteger expectedCalls = selectors.count;
    assert(controller.calls == expectedCalls && controller.lastRow == row && controller.superSelections == 0 && table.deselections == expectedCalls);
    row.properties[@"enabled"] = @NO;
    [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.calls == expectedCalls);
    [row.properties removeObjectForKey:@"enabled"];
    row.target = [NSObject new];
    [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.calls == expectedCalls);
    row.target = controller;
    for (NSString *selector in @[@"staleControllerAction:", @"switchDesktop:"]) {
        row.buttonAction = NSSelectorFromString(selector);
        [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.calls == expectedCalls);
    }
    row.buttonAction = @selector(description);
    [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.calls == expectedCalls);
    row.buttonAction = NULL;
    [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.calls == expectedCalls && controller.superSelections == 0);
    row.cellType = PSSwitchCell;
    [controller tableView:table didSelectRowAtIndexPath:nil]; assert(controller.superSelections == 1);
    puts("PASS: actual button routing method, all seven actions, disabled/wrong target/stale/wrong signature/nil routes, superclass control handling (Foundation doubles, not UIKit)");
} return 0; }
'''.replace('@SELECTORS@', '@[' + ','.join('@"'+action+'"' for action in sorted(actions)) + ']')
with tempfile.TemporaryDirectory() as tmp:
    src = Path(tmp)/'routing.m'; binary = Path(tmp)/'routing'
    src.write_text(preamble + method + '\n' + handlers + tests)
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
