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
        names = ['ControlCenter', 'HomeMenu', 'Display', 'Opacity', 'Import']
        actual = [section('LMVEaster' + name + 'Section') for name in names]
        self.assertEqual(actual, [5, 6, 7, 8, 9])
        total = re.search(r'numberOfSectionsInTableView:.*?\{ return (LMVEaster\w+Section)\(\) \+ 1;', PANEL).group(1)
        self.assertEqual(section(total) + 1, 10)
        for line in ['if (section == LMVEasterControlCenterSection()) return 3;',
                     'if (section == LMVEasterHomeMenuSection()) return 2;',
                     'return section == LMVEasterImportSection() || section == LMVEasterDisplaySection() ? 1 : 2;']:
            self.assertIn(line, PANEL)
        rows = [3 if i == actual[0] else 1 if i in (actual[2], actual[4]) else 2 for i in range(10)]
        self.assertEqual(rows, [2, 2, 2, 2, 2, 3, 2, 1, 2, 1])
        self.assertEqual(sum(rows), 19)

    def test_panel_toggle_tags_and_boundary(self):
        body = PANEL[PANEL.index('- (void)toggle:'):PANEL.index('- (void)opacityChanged:')]
        bound = re.search(r'toggle.tag > (LMVEaster\w+Section)\(\)', body).group(1)
        routes = dict(re.findall(r'toggle.tag == (LMVEaster\w+Section)\(\)\) key = @"(.*?)";', body))
        self.assertEqual(routes, {'LMVEasterControlCenterSection': 'ControlCenterBackgroundEnabled',
                                 'LMVEasterHomeMenuSection': 'HomeMenuBackgroundEnabled',
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
        self.assertEqual([key_for(i) for i in range(10)],
                         [t + 'BackgroundEnabled' for t in TARGETS] +
                         ['ControlCenterBackgroundEnabled', 'HomeMenuBackgroundEnabled', None, 'VideoOpacityEnabled', None])
        self.assertIsNone(key_for(-1))
        self.assertIsNone(key_for(10))

    def test_panel_selection_cells_import_defaults_unchanged(self):
        cells = PANEL[PANEL.index('- (UITableViewCell *)tableView:'):PANEL.index('- (void)toggle:')]
        selection = PANEL[PANEL.index('- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:'):]
        self.assertEqual(digest(cells), '9fe3724d491aea26e6e818db22d0bc23b4946422660d4bfe009d0a3447cd71c4')
        self.assertEqual(digest(selection), 'e694bb5e12fb3a1209f893373ee1bb3ae820b2a3b8e740264d72d2608f88e119')
        self.assertIn('row == 1 ? @"ControlCenterDarkVideo" : (row == 2 ? @"ControlCenterLightVideo" : nil)', PANEL)
        for text in ['key = LMVEasterControlCenterKey(index.row);', 'if (!key) return;',
                     'if (index.row != 1) return;\n        key = @"HomeMenuVideo";',
                     'picker.apply = ^(NSString *relative, NSString *name) { LMVEasterSet(key, relative);',
                     'if (index.section == LMVEasterImportSection()) { if (index.row == 0) [self importVideo]; return; }',
                     'if (index.section == LMVEasterDisplaySection()) {\n        if (index.row != 0) return;']:
            self.assertIn(text, selection)
        # The frozen handlers use helpers, so relocated 6/7/8/9 cannot alias CC or targets.
        self.assertEqual(len({section('LMVEaster' + n + 'Section') for n in
                             ['ControlCenter', 'HomeMenu', 'Display', 'Opacity', 'Import']}), 5)

    def test_settings_appends_group_counts_and_routes(self):
        appends = re.findall(r'\[_specifiers addObject:(.+)\];', SPECIFIERS)
        sequence = []
        for item in appends:
            group = re.search(r'groupSpecifierWithName:@"(.*?)"', item)
            sequence.append('group:' + group.group(1) if group else 'targets-group' if 'LMVNames()[i]' in item else item)
        self.assertEqual(sequence, ['targets-group', 'enabled', 'choose',
            'controlCenter', 'controlCenterEnabled', 'controlCenterDark', 'controlCenterLight',
            'group:桌面长按菜单视频背景', 'homeMenuEnabled', 'homeMenuMaterial',
            'group:小彩蛋', 'eggEnabled', 'group:小彩蛋显示设置', 'eggImage', 'group:素材库', 'import',
            'group:消息、选项、清除视频透明度', 'opacityEnabled', 'opacity',
            'group:素材路径', 'open', 'group:诊断', 'diagnostics',
            'group:默认关闭，仅开启后写入 shared-render.log；关闭不会删除已有日志'])
        # One three-specifier target loop is repeated five times; no rows removed/duplicated.
        self.assertIn('for (NSUInteger i = 0; i < LMVTargets().count; i++)', SPECIFIERS)
        self.assertEqual(len(appends) + (len(TARGETS) - 1) * 3, 36)
        self.assertEqual(sum(x.startswith('group:') or x in ('targets-group', 'controlCenter') for x in sequence) + 4, 14)
        self.assertIn('preferenceSpecifierNamed:@"显示场景与图片旋转"', SPECIFIERS)
        props = sorted(x.strip() for x in SPECIFIERS.splitlines() if 'setProperty:' in x or '.buttonAction =' in x)
        self.assertEqual(digest('\n'.join(props)), '6a8316248f720d7bfeacf41f76828b56ca6dfe62c488dca50445a9ebdc560626')
        handlers = SETTINGS[SETTINGS.index('- (void)tableView:'):]
        self.assertEqual(digest(handlers), '00c0c8d02105a428ccde4072426beeebc5b825bee4952a10e3e66a6cafd360df')
        for action, target in [('switchControlCenterDark', 'ControlCenterDark'),
                               ('switchControlCenterLight', 'ControlCenterLight'), ('switchHomeMenu', 'HomeMenu')]:
            self.assertIn(f'- (void){action}:(PSSpecifier *)specifier {{ [self switchTarget:@"{target}"]; }}', handlers)
        self.assertIn('PSSpecifier *row = [self specifierAtIndexPath:indexPath];', handlers)
        self.assertIn('invoke(self, action, row);', handlers)
        self.assertIn('eggImage.buttonAction = @selector(openEaster:);', SPECIFIERS)

    def test_shared_picker_delete_routing_unchanged(self):
        self.assertEqual(digest(PICKER), 'e722efe1f11c5b993514208602bde7d970edd79bc2008c9912d5fc8890cc122e')
        self.assertEqual(digest(DELETION), '03f620c758b6a5099b20ce02a56c981ec030df979fb663171931ffe6f24117db')
        self.assertIn('if (self.pushed) { [self deleteContained:row]; return; }', PICKER)
        self.assertIn('LMVDeleteMaterial(row[@"path"], &deleted)', PICKER)
        self.assertIn('LMVDeleteMaterial(relative,&deleted)', PICKER)
        self.assertIn('for (NSString *target in @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu"])', DELETION)
        self.assertIn('[target stringByAppendingString:@"Video"]', DELETION)


if __name__ == '__main__':
    unittest.main(verbosity=2)
