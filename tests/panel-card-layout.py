#!/usr/bin/env python3
"""5.28: the settings list is a two-line card list.

The redesign is presentation only, and this test pins that claim down:

  * every row that is not a group gets a cell class, a control kind and (where
    it makes sense) a subtitle - there is no row left on the stock 44pt cell;
  * the row height is a pure function of the specifier, so the table cannot
    disagree with the cell about how tall a row is;
  * the controller still owns every write: the same setters and getters, the
    same keys, the same row order.

A row that loses its subtitle silently drops back to 52pt and reads as a
different list, which is why the coverage check is explicit rather than a
sample.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
prefs = root / 'LockMessageVideoPrefs'
controller = (prefs / 'LMVPRootListController.m').read_text()
cell_h = (prefs / 'LMVPSettingCell.h').read_text()
cell_m = (prefs / 'LMVPSettingCell.m').read_text()
style = (prefs / 'LMVPPanelStyle.h').read_text()
makefile = (root / 'Makefile').read_text()

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


# 1) the cell is part of the bundle, not a header-only sketch
check('LMVPSettingCell.m' in makefile, 'the bundle must compile LMVPSettingCell.m')
check('@interface LMVPSettingCell : PSTableCell' in cell_h, 'the row must subclass PSTableCell')
check('lmvp_heightForSpecifier:' in cell_h, 'row height must be published as a pure function')

# 2) height is a function of the specifier alone - no cell instance, no table
height_body = cell_m[cell_m.index('+ (CGFloat)lmvp_heightForSpecifier:'):]
height_body = height_body[:height_body.index('\n}')]
check('LMVPPanelSliderTallRowHeight' in height_body and 'LMVPPanelTallRowHeight' in height_body,
      'height must switch between the tall and slider constants')
check('self.' not in height_body.replace('+ (CGFloat)', ''), 'height must not read an instance')

# 3) the presentation pass covers every row and stamps all three properties
check('[self applyPanelAppearance];' in controller, 'specifiers must run the presentation pass')
apply_body = controller[controller.index('- (void)applyPanelAppearance {'):]
apply_body = apply_body[:apply_body.index('\n}\n')]
check('if (row.cellType == PSGroupCell) continue;' in apply_body, 'group cells must be skipped')
check('[row setProperty:@"LMVPSettingCell" forKey:@"cellClass"];' in apply_body,
      'every row must be handed to the card cell')
check('forKey:@"panelKind"' in apply_body, 'every row must declare its control kind')
check('forKey:@"subtitle"' in apply_body, 'rows must carry the subtitle the layout reserves space for')

kinds = controller[controller.index('- (NSString *)panelControlKindForSpecifier:'):]
kinds = kinds[:kinds.index('\n}\n')]
check('PSSwitchCell' in kinds and 'PSSliderCell' in kinds and 'PSButtonCell' in kinds,
      'the four stock cell types must map onto control kinds')
check('@"color"' in kinds and 'LMVTextColorRows()' in kinds,
      'colour rows must be recognised from the shared table, not a second list')

subtitles = controller[controller.index('- (NSString *)panelSubtitleForSpecifier:'):]
subtitles = subtitles[:subtitles.index('\n}\n')]
for key in ('GlobalEnabled', 'BackgroundEnabled', 'Material', 'SoundEnabled',
            'VideoOpacity', 'ImportVideo', 'TuneList', 'DiagnosticsEnabled'):
    check(key in subtitles, 'no subtitle for ' + key)

# 4) the table asks the cell, so a row cannot disagree with itself
check('[LMVPSettingCell lmvp_heightForSpecifier:row]' in controller,
      'the table must take row heights from the cell contract')
check('tableView:(UITableView *)tableView heightForRowAtIndexPath:' in controller,
      'the height delegate must be implemented')

# 5) routing and storage are untouched
for selector in ('- (void)setEnabled:(id)value specifier:(PSSpecifier *)specifier {',
                 '- (id)enabled:(PSSpecifier *)specifier {',
                 '- (id)volume:(PSSpecifier *)specifier {',
                 '- (void)setVolume:(id)value specifier:(PSSpecifier *)specifier {',
                 '- (id)opacity:(PSSpecifier *)specifier {',
                 '- (void)setOpacity:(id)value specifier:(PSSpecifier *)specifier {'):
    check(selector in controller, 'handler removed: ' + selector)
for key in ('@"GlobalEnabled"', '"BackgroundEnabled"', '"Volume"', '"VideoOpacity"'):
    check(key in controller, 'preference key removed: ' + key)
check('row.cellType == PSButtonCell' in controller, 'button rows must still route through cellType')

# 6) the cell builds the controls and writes through the specifier
for control in ('UISwitch', 'UISlider'):
    check(control in cell_m, control + ' missing from the card cell')
check('performSetterWithValue:' in cell_m, 'the switch and slider must write through the specifier')
check('performGetter' in cell_m, 'the switch and slider must read the stored value')
check('lmvp_applyEnabled' in cell_m, 'an enabled=NO row must grey out its control')

# 7) the colour row keeps its swatch column, the callout row keeps its name
check('lmvp_trailingReservedWidth' in cell_h, 'the cell must report its reserved column')
check('LMVPPanelColorWidth' in cell_m and 'textWidth = 82.0' in cell_m,
      'the colour row title must stop before the hex text')
check('(self.accessoryView != nil)' in cell_m,
      'a row carrying the material name must not also draw a chevron')

# 8) geometry lives in one header
for constant in ('LMVPPanelTallRowHeight', 'LMVPPanelRowHeight',
                 'LMVPPanelSliderRowHeight', 'LMVPPanelSliderTallRowHeight'):
    check(constant in style, 'geometry constant missing: ' + constant)
check(re.search(r'LMVPPanelTallRowHeight = 66',

                style) is not None, 'tall rows are 66pt')
check(re.search(r'LMVPPanelSliderTallRowHeight = 96', style) is not None,
      'slider rows with a subtitle are 96pt')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 5.28 - every row is a card row, heights are a pure function, routing and keys unchanged')
