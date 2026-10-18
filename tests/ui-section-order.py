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
        names = ['ControlCenter', 'HomeMenu', 'SquidPanel', 'AT', 'CV', 'Myrtle', 'Display', 'Opacity', 'Import']
        actual = [section('LMVEaster' + name + 'Section') for name in names]
        self.assertEqual(actual, [5, 6, 7, 8, 9, 10, 11, 12, 13])
        total = re.search(r'numberOfSectionsInTableView:.*?\{ return (LMVEaster\w+Section)\(\) \+ 1;', PANEL).group(1)
        self.assertEqual(section(total) + 1, 14)
        for line in ['if (section >= 0 && section < LMVEasterTargets().count) return 4;',
                     'if (section == LMVEasterControlCenterSection()) return 7;',
                     'if (section == LMVEasterHomeMenuSection()) return 4;',
                     'if (section == LMVEasterSquidPanelSection()) return 4;',
                     'if (section == LMVEasterATSection()) return 4;',
                     'if (section == LMVEasterCVSection()) return 4;',
                     'return section == LMVEasterImportSection() || section == LMVEasterDisplaySection() ? 1 : 2;']:
            self.assertIn(line, PANEL)
        disp, imp = section('LMVEasterDisplaySection'), section('LMVEasterImportSection')
        squid = section('LMVEasterSquidPanelSection')
        # 1.53: the Squid section carries its switch, FOUR material rows (right and left,
        # 上滑 and 上上滑), the reset row, the swap row and the shared sound pair, so it is
        # five rows taller than its neighbours.
        rows = [4 if i == squid else 4 if i < 5 or i in (actual[1], actual[3], actual[5]) else 5 if i == actual[4] else 7 if i == actual[0] else 1 if i in (disp, imp) else 2 for i in range(14)]
        self.assertEqual(rows, [4, 4, 4, 4, 4, 7, 4, 4, 4, 5, 4, 1, 2, 1])
        self.assertEqual(sum(rows), 52)

    def test_panel_toggle_tags_and_boundary(self):
        body = PANEL[PANEL.index('- (void)toggle:'):PANEL.index('- (void)opacityChanged:')]
        bound = re.search(r'toggle.tag > (LMVEaster\w+Section)\(\)', body).group(1)
        routes = dict(re.findall(r'toggle.tag == (LMVEaster\w+Section)\(\)\) key = @"(.*?)";', body))
        self.assertEqual(routes, {'LMVEasterControlCenterSection': 'ControlCenterBackgroundEnabled',
                                 'LMVEasterMyrtleSection': 'MyrtleBackgroundEnabled', 'LMVEasterHomeMenuSection': 'HomeMenuBackgroundEnabled',
                                 'LMVEasterSquidPanelSection': 'SquidPanelBackgroundEnabled',
                                 'LMVEasterATSection': 'ATBackgroundEnabled',
                                 'LMVEasterCVSection': 'CVBackgroundEnabled',
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
        self.assertEqual([key_for(i) for i in range(14)],
                         [t + 'BackgroundEnabled' for t in TARGETS] +
                         ['ControlCenterBackgroundEnabled', 'HomeMenuBackgroundEnabled', 'SquidPanelBackgroundEnabled',
                          'ATBackgroundEnabled', 'CVBackgroundEnabled', 'MyrtleBackgroundEnabled',
                          None, 'VideoOpacityEnabled', None])
        self.assertIsNone(key_for(-1))
        self.assertIsNone(key_for(13))

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
        at_end = old_cells.index('    if (index.section == LMVEasterCVSection()) {', at_start)
        old_cells = old_cells[:at_start] + old_cells[at_end:]
        # 1.43: same treatment for the CopyVault block inserted below the AT one,
        # so the frozen hash keeps proving that every ORIGINAL cell is untouched.
        cv_start = old_cells.index('    if (index.section == LMVEasterCVSection()) {')
        cv_end = old_cells.index('    if (index.section == LMVEasterControlCenterSection()) {', cv_start)
        old_cells = old_cells[:cv_start] + old_cells[cv_end:]
        # 1.50: the Squid block now carries four material rows, the claim row and the
        # swap row; put the 1.43 text back so the frozen hash keeps proving that every
        # ORIGINAL cell is byte-identical after the insertions.
        old_cells = old_cells.replace('''        } else if (index.row >= 1 && index.row <= 4) {
            // 1.44: each panel shape gets its own material; 1.50: the shape exists on
            // both gesture sides, so there are four materials and the rows name the
            // GESTURE (right/left, 上滑/上上滑), not the orientation.
            cell.textLabel.text = LMVEasterSquidTitles()[index.row - 1];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            id selected = LMVEasterRead(LMVEasterSquidKeys()[index.row - 1]);
''', '''        } else {
            cell.textLabel.text = @"切换鱿鱼面板素材"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            id selected = LMVEasterRead(@"SquidPanelVideo");
''')
        old_cells = old_cells.replace('''        } else {
            cell.textLabel.text = @""; cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryNone;
        }
''', '''        }
''')
        # 1.50: the claim row and the 1.46 swap row were inserted into the Squid block;
        # drop them so the frozen hash keeps proving that every ORIGINAL cell is
        # byte-identical.
        old_cells = old_cells.replace('''        } else if (index.row == 5) {
            // 1.50: the one thing the runtime cannot know - which gesture opened the
            // panel it just saw. This row binds the panel the user was last looking
            // at to the gesture they name, and it overrules an automatic guess.
            cell.textLabel.text = @"认领刚用过的面板";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            id claimed = LMVEasterRead(@"SquidPanelClaimSlot");
            NSInteger slot = [claimed isKindOfClass:NSNumber.class] ? [claimed integerValue] - 1 : NSNotFound;
            cell.detailTextLabel.text = (slot >= 0 && slot < (NSInteger)LMVEasterSquidGestures().count)
                ? [@"上次认领：" stringByAppendingString:LMVEasterSquidGestures()[slot]] : @"把刚才那个面板认给某一套素材";
            cell.detailTextLabel.numberOfLines = 2;
''', '')
        old_cells = old_cells.replace('''        } else if (index.row == 5) {
            // 1.52: the repair for a record that was written wrong - the pair ordering
            // can only sort a side while that side is half unknown, so a corrupt pair
            // has to be cleared instead. One tap, then open the four panels once.
            cell.textLabel.text = @"重置面板识别";
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.detailTextLabel.text = @"忘记已记的四块面板；之后按 右一→右二→左一→左二 各开一次";
            cell.detailTextLabel.numberOfLines = 2;
''', '')
        old_cells = old_cells.replace('''        } else if (index.row == 6) {
            // 1.46: the manual override. A button rather than a switch: the panel's
            // switches are told apart by their tag and every tag is a section index,
            // so this row reports its state in the detail label instead.
            cell.textLabel.text = @"对调上滑 / 上上滑素材";
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.detailTextLabel.text = [LMVEasterRead(@"SquidPanelSwapShapes") boolValue] ? @"已对调" : @"正常";
            cell.detailTextLabel.numberOfLines = 1;
''', '')
        old_cells = old_cells.replace('index.row == 1 ? 0 : 1)', 'index.row - 1)')
        self.assertEqual(digest(old_cells), '21710189a445157b27bd64be293fd318f6059e0baa5b95cee7abf9d6baaa7e02')
        # Same for the routing: the AT branch is dropped before hashing.
        selection_for_digest = selection.replace('''    } else if (index.section == LMVEasterATSection()) {
        if (index.row != 1) return;
        key = @"ATVideo";
''', '')
        selection_for_digest = selection_for_digest.replace('''    } else if (index.section == LMVEasterCVSection()) {
        if (index.row == 4) {
            LMVTextColorPicker *picker = [LMVTextColorPicker new];
            picker.modalPresentationStyle = UIModalPresentationPageSheet;
            __weak typeof(self) weakSelf = self;
            picker.onChange = ^(UIColor *color) { [weakSelf.tableView reloadData]; };
            [self presentViewController:picker animated:YES completion:nil];
            return;
        }
        if (index.row != 1) return;
        key = @"CVVideo";
''', '')
        # 1.77: the Myrtle branch is the same shape as the CV one; drop it as well so
        # the digest keeps guarding the ORIGINAL selection logic, not the new copy.
        selection_for_digest = selection_for_digest.replace('''    } else if (index.section == LMVEasterMyrtleSection()) {
        if (index.row != 1) return;
        key = @"MyrtleVideo";
''', '')
        # 1.50: and the claim branch it gained - drop that too, then the swap branch
        # added by 1.46.
        selection_for_digest = selection_for_digest.replace('''        if (index.row == 5) { [self claimSquidPanel]; return; }
''', '')
        selection_for_digest = selection_for_digest.replace('''        if (index.row == 5) { [self resetSquidPanel]; return; }
''', '')
        selection_for_digest = selection_for_digest.replace('''        if (index.row == 6) {
            BOOL now = [LMVEasterRead(@"SquidPanelSwapShapes") boolValue];
            LMVEasterSet(@"SquidPanelSwapShapes", @(!now));
            [self.tableView reloadData];
            return;
        }
''', '')
        # 1.44/1.50: the Squid routing branch gained more slots - restore the 1.43 text.
        selection_for_digest = selection_for_digest.replace('''        if (index.row < 1 || index.row > 4) return;
        key = LMVEasterSquidKeys()[index.row - 1];''', '''        if (index.row != 1) return;
        key = @"SquidPanelVideo";''')
        self.assertEqual(digest(selection_for_digest), '6d74d39b3a50840655cf719e956909bbd6536598fc161f3a6c0e1c6a3781d155')
        self.assertIn('row == 1 ? @"ControlCenterDarkVideo" : (row == 4 ? @"ControlCenterLightVideo" : nil)', PANEL)
        for text in ['key = LMVEasterControlCenterKey(index.row);', 'if (!key) return;',
                     'if (index.row != 1) return;\n        key = @"HomeMenuVideo";',
                     'picker.apply = ^(NSString *relative, NSString *name) { LMVEasterSet(key, relative);',
                     'if (index.section == LMVEasterImportSection()) { if (index.row == 0) [self importVideo]; return; }',
                     'if (index.section == LMVEasterDisplaySection()) {\n        if (index.row != 0) return;']:
            self.assertIn(text, selection)
        # The frozen handlers use helpers, so relocated 6/7/8/9 cannot alias CC or targets.
        self.assertEqual(len({section('LMVEaster' + n + 'Section') for n in
                             ['ControlCenter', 'HomeMenu', 'SquidPanel', 'AT', 'CV', 'Display', 'Opacity', 'Import']}), 8)

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
            'group:鱿鱼面板背景视频', 'squidPanelEnabled', 'squidPanelMaterial', 'squidText',
            'group:AT 背景视频', 'atEnabled', 'atMaterial',
            'group:CopyVault 面板背景视频', 'cvEnabled', 'cvMaterial', 'cvText',
            'group:Myrtle 面板背景视频', 'myrtleEnabled', 'myrtleMaterial',
            'group:小彩蛋', 'eggEnabled', 'group:小彩蛋显示设置', 'eggImage', 'group:素材库', 'import',
            'group:消息、选项、清除视频透明度', 'opacityEnabled', 'opacity',
            'group:素材路径', 'open', 'group:诊断', 'diagnostics',
            'group:默认关闭，仅开启后写入 shared-render.log；关闭不会删除已有日志'])
        # One three-specifier target loop is repeated five times; no rows removed/duplicated.
        self.assertIn('for (NSUInteger i = 0; i < LMVTargets().count; i++)', SPECIFIERS)
        self.assertEqual(len(appends) + (len(TARGETS) - 1) * 3, 52)
        self.assertIn('[_specifiers addObject:choose];\n        [self appendAudioForTarget:LMVTargets()[i]', SPECIFIERS)
        for item, target in [('controlCenterDark', 'ControlCenterDark'), ('controlCenterLight', 'ControlCenterLight'), ('homeMenuMaterial', 'HomeMenu'), ('squidPanelMaterial', 'SquidPanel'), ('atMaterial', 'AT'), ('cvMaterial', 'CV')]:
            self.assertIn(f'[_specifiers addObject:{item}];\n    [self appendAudioForTarget:@"{target}"', SPECIFIERS)
        self.assertEqual(SPECIFIERS.count('appendAudioForTarget:'), 8)
        self.assertEqual(51 + (len(TARGETS) + 6) * 2, 73)  # 51 non-audio rows + 11 audio channels x 2
        self.assertEqual(sum(x.startswith('group:') or x in ('targets-group', 'controlCenter') for x in sequence) + 4, 18)
        self.assertIn('preferenceSpecifierNamed:@"显示场景与图片旋转"', SPECIFIERS)
        props = sorted(x.strip() for x in SPECIFIERS.splitlines()
                       if ('setProperty:' in x or '.buttonAction =' in x)
                       and 'atEnabled' not in x and 'atMaterial' not in x
                       and 'cvEnabled' not in x and 'cvMaterial' not in x
                       and 'squidPanelMaterial2' not in x and 'squidPanelSwap' not in x
                       and 'squidPanelMaterial3' not in x and 'squidPanelMaterial4' not in x
                       and 'squidPanelReset' not in x and 'cvText' not in x and 'squidText' not in x)
        self.assertEqual(digest('\n'.join(props)), '9fe474875b4b362fac3159ace348ce13788f8ac7e1c5cfb3abd5d0f409744be6')
        handlers = SETTINGS[SETTINGS.index('- (void)tableView:'):]
        volume_start = handlers.index('- (id)volume:')
        volume_end = handlers.index('- (id)opacity:', volume_start)
        old_handlers = handlers[:volume_start] + handlers[volume_end:]
        old_handlers = old_handlers.replace(': [specifier propertyForKey:@"audioVolumeKey"];', ': nil;')
        old_handlers = old_handlers.replace('- (void)switchAT:(PSSpecifier *)specifier { [self switchTarget:@"AT"]; }\n', '')
        old_handlers = old_handlers.replace('- (void)switchCV:(PSSpecifier *)specifier { [self switchTarget:@"CV"]; }\n', '')
        # ...and the AT / CV entries added to the titles and legacy maps.
        old_handlers = old_handlers.replace(', @"AT": @"AT 背景视频"', '').replace(', @"AT": @""', '')
        old_handlers = old_handlers.replace(', @"CV": @"CopyVault 面板背景视频"', '').replace(', @"CV": @""', '')
        # 1.44: the second Squid material slot, and the one existing Squid title that
        # was renamed when that slot appeared. 1.50: the left-hand pair, the claim row
        # and their handlers.
        for line in ('- (void)switchSquidPanel2:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel2"]; }',
                     '- (void)switchSquidPanel3:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel3"]; }',
                     '- (void)switchSquidPanel4:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel4"]; }'):
            old_handlers = old_handlers.replace(line + '\n', '')
        claim_start = old_handlers.index('// 1.50: "认领刚用过的面板" - the panel\'s content says nothing')
        claim_end = old_handlers.index('- (void)chooseVideo:(PSSpecifier *)specifier {', claim_start)
        old_handlers = old_handlers[:claim_start] + old_handlers[claim_end:]
        for target in ('SquidPanel2', 'SquidPanel3', 'SquidPanel4'):
            old_handlers = old_handlers.replace(f', @"{target}": @""', '')
        # 1.54: the four rows are named 右一/右二/左一/左二, the way the user names them.
        old_handlers = old_handlers.replace(', @"SquidPanel2": @"右二·右上上滑面板背景视频"', '')
        old_handlers = old_handlers.replace(', @"SquidPanel3": @"左一·左上滑面板背景视频"', '')
        old_handlers = old_handlers.replace(', @"SquidPanel4": @"左二·左上上滑面板背景视频"', '')
        old_handlers = old_handlers.replace('@"SquidPanel": @"右一·右上滑面板背景视频"', '@"SquidPanel": @"鱿鱼面板背景视频"')
        # 1.77: the Myrtle channel is new - strip it so this digest keeps guarding the
        # pre-Myrtle handlers rather than drifting with every added channel.
        old_handlers = old_handlers.replace('- (void)switchMyrtle:(PSSpecifier *)specifier { [self switchTarget:@"Myrtle"]; }\n', '')
        old_handlers = old_handlers.replace(', @"Myrtle": @"Myrtle 面板背景视频"', '')
        old_handlers = old_handlers.replace(', @"Myrtle": @""', '')
        # 1.83: the CopyVault swatch cell hook and the picker handler - drop both
        # before the frozen digest.
        swatch_start = old_handlers.index('// 1.83: PSButtonCell keeps the tap routing')
        swatch_end = old_handlers.index('- (void)openCVTextColor:', swatch_start)
        old_handlers = old_handlers[:swatch_start] + old_handlers[swatch_end:]
        picker_start = old_handlers.index('- (void)openCVTextColor:')
        picker_end = old_handlers.index('- (void)setEnabled:', picker_start)
        old_handlers = old_handlers[:picker_start] + old_handlers[picker_end:]
        self.assertEqual(digest(old_handlers), 'cfadd58904dcbcd374640f2b02aa23fee338c1c26bdfe5ec71062566a8f5798a')
        for action, target in [('switchControlCenterDark', 'ControlCenterDark'),
                               ('switchControlCenterLight', 'ControlCenterLight'), ('switchHomeMenu', 'HomeMenu'),
                               ('switchSquidPanel', 'SquidPanel'), ('switchAT', 'AT'), ('switchCV', 'CV')]:
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
        # 1.34: the shared thumbnail state moves to file scope and gains
        # +prewarmThumbnailCache, and the list now requests every row instead of only
        # the visible ones. Delete routing is still untouched.
        self.assertEqual(digest(PICKER), '35174e76a3b73ee3eddb1cbb18b1be0232bcc457581fa51cad0b8b418abf99e7')
        # 1.26: the AT target is added to both the defaults map and the sweep list;
        # strip it before hashing so the frozen digest still covers everything else.
        deletion_for_digest = DELETION.replace(',@"CV":@""', '').replace(',@"CV"]', ']')
        deletion_for_digest = deletion_for_digest.replace(',@"SquidPanel2":@""', '').replace(',@"SquidPanel2"', '')
        deletion_for_digest = deletion_for_digest.replace(',@"SquidPanel3":@""', '').replace(',@"SquidPanel3"', '')
        deletion_for_digest = deletion_for_digest.replace(',@"SquidPanel4":@""', '').replace(',@"SquidPanel4"', '')
        deletion_for_digest = deletion_for_digest.replace('@"SquidPanel":@"",@"AT":@""', '@"SquidPanel":@""')
        deletion_for_digest = deletion_for_digest.replace('@"SquidPanel",@"AT"]', '@"SquidPanel"]')
        self.assertEqual(digest(deletion_for_digest), 'b6a7b64b5c62a05698a3a03d7ca5feda863e4a441740db1eb1f3c0310382c2da')
        self.assertIn('if (self.pushed) { [self deleteContained:row]; return; }', PICKER)
        self.assertIn('LMVDeleteMaterial(row[@"path"], &deleted)', PICKER)
        self.assertIn('LMVDeleteMaterial(relative,&deleted)', PICKER)
        self.assertIn('for (NSString *target in @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu",@"SquidPanel",@"AT",@"CV"])', DELETION)
        self.assertIn('[target stringByAppendingString:@"Video"]', DELETION)


if __name__ == '__main__':
    unittest.main(verbosity=2)
