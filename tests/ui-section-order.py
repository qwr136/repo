#!/usr/bin/env python3
"""Static production-source contracts for the Settings/panel UI reorder.
No UIKit execution claim: hashes freeze pre-reorder cells, handlers and deletion.
"""
from pathlib import Path
import hashlib
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PANEL = (ROOT / 'LMVEasterPanel.h').read_text()
SETTINGS = (ROOT / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
PICKER = (ROOT / 'LockMessageVideoPrefs/LMVMaterialPicker.h').read_text()
DELETION = (ROOT / 'LockMessageVideoPrefs/LMVMaterialDeletion.h').read_text()
SPECIFIERS = SETTINGS[SETTINGS.index('- (NSArray *)specifiers {'):SETTINGS.index('- (void)tableView:')]
TARGETS = ['Message', 'Options', 'Clear', 'LockScreen', 'Desktop']


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def section(name):
    """Resolve the actual production helper expression, not a copied index map."""
    expr = re.search(r'static NSInteger ' + name + r'\(void\) \{ return (.*?); \}', PANEL).group(1)
    if expr == 'LMVEasterTargets().count':
        values = re.search(r'LMVEasterTargets\(void\) \{ return @\[(.*?)\]; \}', PANEL).group(1)
        assert re.findall(r'@"(.*?)"', values) == TARGETS
        return len(TARGETS)
    parent = re.fullmatch(r'(LMVEaster\w+Section)\(\) \+ 1', expr).group(1)
    return section(parent) + 1


class UISectionOrder(unittest.TestCase):
    def test_panel_sections_and_row_counts(self):
        names = ['ControlCenter', 'HomeMenu', 'SquidPanel', 'AT', 'Display', 'Opacity', 'Import']
        actual = [section('LMVEaster' + name + 'Section') for name in names]
        self.assertEqual(actual, [5, 6, 7, 8, 9, 10, 11])
        total = re.search(r'numberOfSectionsInTableView:.*?\{ return (LMVEaster\w+Section)\(\) \+ 1;', PANEL).group(1)
        self.assertEqual(section(total) + 1, 12)
        for line in ['if (section >= 0 && section < LMVEasterTargets().count) return 4;',
                     'if (section == LMVEasterControlCenterSection()) return 7;',
                     'if (section == LMVEasterHomeMenuSection()) return 4;',
                     'if (section == LMVEasterSquidPanelSection()) return 4;',
                     'if (section == LMVEasterATSection()) return 4;',
                     'return section == LMVEasterImportSection() || section == LMVEasterDisplaySection() ? 1 : 2;']:
            self.assertIn(line, PANEL)
        rows = [4 if i < 5 or i in (actual[1], actual[2], actual[3]) else 7 if i == actual[0] else 1 if i in (actual[4], actual[6]) else 2 for i in range(12)]
        self.assertEqual(rows, [4, 4, 4, 4, 4, 7, 4, 4, 4, 1, 2, 1])
        self.assertEqual(sum(rows), 43)

    def test_panel_toggle_tags_and_boundary(self):
        body = PANEL[PANEL.index('- (void)toggle:'):PANEL.index('- (void)opacityChanged:')]
        bound = re.search(r'toggle.tag > (LMVEaster\w+Section)\(\)', body).group(1)
        routes = dict(re.findall(r'toggle.tag == (LMVEaster\w+Section)\(\)\) key = @"(.*?)";', body))
        self.assertEqual(routes, {'LMVEasterControlCenterSection': 'ControlCenterBackgroundEnabled',
                                 'LMVEasterHomeMenuSection': 'HomeMenuBackgroundEnabled',
                                 'LMVEasterSquidPanelSection': 'SquidPanelBackgroundEnabled',
                                 'LMVEasterATSection': 'ATBackgroundEnabled',
                                 'LMVEasterOpacitySection': 'VideoOpacityEnabled'})
        self.assertIn('toggle.tag < 0', body)
        self.assertIn('else return;', body)
        self.assertIn('LMVEasterSet(key, @(toggle.on));', body)
        self.assertIn('else if (toggle.tag < LMVEasterTargets().count)', body)
        resolved = {section(name): key for name, key in routes.items()}
        for name in routes:
            self.assertIn('toggle.tag = ' + name + '();', PANEL)
        resolved.update({i: target + 'BackgroundEnabled' for i, target in enumerate(TARGETS)})
        def key_for(tag):
            return None if tag < 0 or tag > section(bound) else resolved.get(tag)
        self.assertEqual([key_for(i) for i in range(12)],
                         [t + 'BackgroundEnabled' for t in TARGETS] +
                         ['ControlCenterBackgroundEnabled', 'HomeMenuBackgroundEnabled', 'SquidPanelBackgroundEnabled',
                          'ATBackgroundEnabled', None, 'VideoOpacityEnabled', None])
        self.assertIsNone(key_for(-1))
        self.assertIsNone(key_for(12))

    def test_panel_selection_cells_import_defaults_unchanged(self):
        cells = PANEL[PANEL.index('- (UITableViewCell *)tableView:'):PANEL.index('- (void)toggle:')]
        selection = PANEL[PANEL.index('- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:'):]
        # Remove only the newly inserted audio block and normalize the moved CC
        # light material's display index; all original cells retain their hash.
        audio_start = cells.index('    NSString *audioTarget = LMVEasterAudioTarget(')
        audio_end = cells.index('    if (index.section == LMVEasterImportSection())', audio_start)
        old_cells = cells[:audio_start] + cells[audio_end:]
        # 1.26: the AT pop-up block sits between the Squid panel block and the CC
        # block; remove it the same way, so the frozen hash still proves that every
        # ORIGINAL cell is byte-identical after the insertion.
        at_start = old_cells.index('    if (index.section == LMVEasterATSection()) {')
        at_end = old_cells.index('    if (index.section == LMVEasterControlCenterSection()) {', at_start)
        old_cells = old_cells[:at_start] + old_cells[at_end:]
        old_cells = old_cells.replace('index.row == 1 ? 0 : 1)', 'index.row - 1)')
        self.assertEqual(digest(old_cells), '7e0a52923e482473468c9523f0b4cff4d28c296318d5f7eee1f2c92b830064fb')
        # Same for the routing: the AT branch is dropped before hashing.
        selection_for_digest = selection.replace('''    } else if (index.section == LMVEasterATSection()) {
        if (index.row != 1) return;
        key = @"ATVideo";
''', '')
        self.assertEqual(digest(selection_for_digest), 'f49b774c5fc80a7200d0c2bebea00126722d21fa89c41ae98571a663c9180349')
        self.assertIn('row == 1 ? @"ControlCenterDarkVideo" : (row == 4 ? @"ControlCenterLightVideo" : nil)', PANEL)
        for text in ['key = LMVEasterControlCenterKey(index.row);', 'if (!key) return;',
                     'if (index.row != 1) return;\n        key = @"HomeMenuVideo";',
                     'picker.apply = ^(NSString *relative, NSString *name) { LMVEasterSet(key, relative);',
                     'if (index.section == LMVEasterImportSection()) { if (index.row == 0) [self importVideo]; return; }',
                     'if (index.section == LMVEasterDisplaySection()) {\n        if (index.row != 0) return;']:
            self.assertIn(text, selection)
        # The frozen handlers use helpers, so relocated 6/7/8/9 cannot alias CC or targets.
        self.assertEqual(len({section('LMVEaster' + n + 'Section') for n in
                             ['ControlCenter', 'HomeMenu', 'SquidPanel', 'AT', 'Display', 'Opacity', 'Import']}), 7)

    def test_settings_top_group_is_the_global_master_switch(self):
        # 0.0.114: the master switch is the FIRST row and defaults to ON, so an
        # absent key keeps every channel enabled after an upgrade.
        self.assertTrue(SPECIFIERS.startswith('- (NSArray *)specifiers {'))
        self.assertIn('[_specifiers addObject:globalGroup];\n    PSSpecifier *global =', SPECIFIERS)
        self.assertIn('[global setProperty:@"GlobalEnabled" forKey:@"key"];', SPECIFIERS)
        self.assertIn('[global setProperty:@YES forKey:@"default"];', SPECIFIERS)
        self.assertIn('set:@selector(setEnabled:specifier:) get:@selector(enabled:)', SPECIFIERS)
        global_index = SPECIFIERS.index('GlobalEnabled')
        self.assertLess(global_index, SPECIFIERS.index('LMVNames()[i]'))
        # Every reading site must gate inline on the same key with absent=enabled,
        # so a sliced native fixture needs no extra symbol.
        inline = 'CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID)'
        for f in ['LMVLockVideo.h', 'LMVControlCenterVideo.h', 'LMVHomeMenuVideo.h']:
            self.assertIn(inline, (ROOT / f).read_text())
            self.assertIn('![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]',
                          (ROOT / f).read_text())
        self.assertEqual((ROOT / 'LMVDesktopVideo.h').read_text().count(inline), 2)
        tweak = (ROOT / 'Tweak.xm').read_text()
        self.assertIn('CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"), kLMVPrefsID)', tweak)
        self.assertIn('BOOL globalOn = ![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue];', tweak)
        self.assertNotIn('LMVGlobalEnabled()', tweak + (ROOT / 'LMVLockVideo.h').read_text())
        self.assertIn('globalOn?LMVEasterRead(@"EasterEggEnabled"):@NO', (ROOT / 'LMVEasterOverlay.h').read_text())

    def test_settings_appends_group_counts_and_routes(self):
        appends = re.findall(r'\[_specifiers addObject:(.+)\];', SPECIFIERS)
        sequence = []
        for item in appends:
            group = re.search(r'groupSpecifierWithName:@"(.*?)"', item)
            sequence.append('group:' + group.group(1) if group else 'targets-group' if 'LMVNames()[i]' in item else item)
        self.assertEqual(sequence, ['globalGroup', 'global',
            'targets-group', 'enabled', 'choose',
            'controlCenter', 'controlCenterEnabled', 'controlCenterDark', 'controlCenterLight',
            'group:桌面长按菜单视频背景', 'homeMenuEnabled', 'homeMenuMaterial',
            'group:鱿鱼面板背景视频', 'squidPanelEnabled', 'squidPanelMaterial',
            'group:AT 背景视频', 'atEnabled', 'atMaterial',
            'group:小彩蛋', 'eggEnabled', 'group:小彩蛋显示设置', 'eggImage', 'group:素材库', 'import',
            'group:消息、选项、清除视频透明度', 'opacityEnabled', 'opacity',
            'group:素材路径', 'open', 'group:诊断', 'diagnostics',
            'group:默认关闭，仅开启后写入 shared-render.log；关闭不会删除已有日志'])
        # One three-specifier target loop is repeated five times; no rows removed/duplicated.
        self.assertIn('for (NSUInteger i = 0; i < LMVTargets().count; i++)', SPECIFIERS)
        self.assertEqual(len(appends) + (len(TARGETS) - 1) * 3, 44)
        self.assertIn('[_specifiers addObject:choose];\n        [self appendAudioForTarget:LMVTargets()[i]', SPECIFIERS)
        for item, target in [('controlCenterDark', 'ControlCenterDark'), ('controlCenterLight', 'ControlCenterLight'), ('homeMenuMaterial', 'HomeMenu'), ('squidPanelMaterial', 'SquidPanel'), ('atMaterial', 'AT')]:
            self.assertIn(f'[_specifiers addObject:{item}];\n    [self appendAudioForTarget:@"{target}"', SPECIFIERS)
        self.assertEqual(SPECIFIERS.count('appendAudioForTarget:'), 6)
        self.assertEqual(44 + (len(TARGETS) + 5) * 2, 64)  # 44 non-audio rows + 10 audio channels x 2
        self.assertEqual(sum(x.startswith('group:') or x in ('targets-group', 'controlCenter') for x in sequence) + 4, 16)
        self.assertIn('preferenceSpecifierNamed:@"显示场景与图片旋转"', SPECIFIERS)
        props = sorted(x.strip() for x in SPECIFIERS.splitlines()
                       if ('setProperty:' in x or '.buttonAction =' in x)
                       and 'atEnabled' not in x and 'atMaterial' not in x)
        self.assertEqual(digest('\n'.join(props)), 'bf399a42225ee674df0e19bc44010d03a474e0af16cb2b19a76501c245c73469')
        handlers = SETTINGS[SETTINGS.index('- (void)tableView:'):]
        volume_start = handlers.index('- (id)volume:')
        volume_end = handlers.index('- (id)opacity:', volume_start)
        old_handlers = handlers[:volume_start] + handlers[volume_end:]
        old_handlers = old_handlers.replace(': [specifier propertyForKey:@"audioVolumeKey"];', ': nil;')
        old_handlers = old_handlers.replace('- (void)switchAT:(PSSpecifier *)specifier { [self switchTarget:@"AT"]; }\n', '')
        # ...and the two AT entries added to the titles / legacy maps.
        old_handlers = old_handlers.replace(', @"AT": @"AT 背景视频"', '').replace(', @"AT": @""', '')
        self.assertEqual(digest(old_handlers), 'cfadd58904dcbcd374640f2b02aa23fee338c1c26bdfe5ec71062566a8f5798a')
        for action, target in [('switchControlCenterDark', 'ControlCenterDark'),
                               ('switchControlCenterLight', 'ControlCenterLight'), ('switchHomeMenu', 'HomeMenu'),
                               ('switchSquidPanel', 'SquidPanel'), ('switchAT', 'AT')]:
            self.assertIn(f'- (void){action}:(PSSpecifier *)specifier {{ [self switchTarget:@"{target}"]; }}', handlers)
        self.assertIn('PSSpecifier *row = [self specifierAtIndexPath:indexPath];', handlers)
        self.assertIn('invoke(self, action, row);', handlers)
        self.assertIn('eggImage.buttonAction = @selector(openEaster:);', SPECIFIERS)

    def test_shared_picker_delete_routing_unchanged(self):
        # 0.0.117: orientation support is added to the picker (rotation follow).
        # 1.32: a watchdog for the shared `pending` set is added. A stalled worker
        # (the synchronous frame grab had no timeout) used to strand a row on 生成中
        # forever, because the key never left `pending`. Nothing about the delete
        # routing changed.
        self.assertEqual(digest(PICKER), '8893116cbbabc51be107f866be50cd244c68cb891c00ca1de047f87bd7bbab6b')
        # 1.26: the AT target is added to both the defaults map and the sweep list;
        # strip it before hashing so the frozen digest still covers everything else.
        deletion_for_digest = DELETION.replace('@"SquidPanel":@"",@"AT":@""', '@"SquidPanel":@""')
        deletion_for_digest = deletion_for_digest.replace('@"SquidPanel",@"AT"]', '@"SquidPanel"]')
        self.assertEqual(digest(deletion_for_digest), 'b6a7b64b5c62a05698a3a03d7ca5feda863e4a441740db1eb1f3c0310382c2da')
        self.assertIn('if (self.pushed) { [self deleteContained:row]; return; }', PICKER)
        self.assertIn('LMVDeleteMaterial(row[@"path"], &deleted)', PICKER)
        self.assertIn('LMVDeleteMaterial(relative,&deleted)', PICKER)
        self.assertIn('for (NSString *target in @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu",@"SquidPanel",@"AT"])', DELETION)
        self.assertIn('[target stringByAppendingString:@"Video"]', DELETION)


if __name__ == '__main__':
    unittest.main(verbosity=2)
