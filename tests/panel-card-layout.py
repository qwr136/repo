#!/usr/bin/env python3
"""5.28/5.29/5.31: the settings list is a two-line card list.

The redesign is presentation only, and this test pins that claim down:

  * every row that is not a group gets a control kind and (where it makes
    sense) a subtitle - there is no row left on the stock 44pt cell;
  * the row is built by the controller's own data source, not by handing a
    cellClass to PSListController: Preferences sends -setValue: / -control to
    switch and slider rows, and an unguarded send to a plain PSTableCell
    subclass aborts the Preferences process (5.28 crashed exactly there);
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
check('LMVPPanelTallRowHeight' in height_body and 'LMVPPanelRowHeight' in height_body,
      'height must switch between the tall and the plain row constant')
check('LMVPPanelSliderTallRowHeight' not in height_body,
      'a stepper row is the same height as any other row')
check('self.' not in height_body.replace('+ (CGFloat)', ''), 'height must not read an instance')

# 3) the presentation pass covers every row and stamps all three properties
check('[self applyPanelAppearance];' in controller, 'specifiers must run the presentation pass')
apply_body = controller[controller.index('- (void)applyPanelAppearance {'):]
apply_body = apply_body[:apply_body.index('\n}\n')]
check('if (row.cellType == PSGroupCell) continue;' in apply_body, 'group cells must be skipped')
check('forKey:@"cellClass"' not in apply_body,
      'cellClass must stay out of the specifier - PSListController would then set the row up itself')
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
for control in ('UISwitch', 'LMVStepperControl'):
    check(control in cell_m, control + ' missing from the card cell')
check('UISlider' not in cell_m, 'the numeric row must be a stepper, not a slider')
check('performSetterWithValue:' in cell_m, 'the switch and stepper must write through the specifier')
check('performGetter' in cell_m, 'the switch and stepper must read the stored value')
check('lmvp_applyEnabled' in cell_m, 'an enabled=NO row must grey out its control')

# 6b) 5.29: the cell answers what Preferences sends at a switch/slider row, and
# the controller builds those rows itself. Both halves are required: with either
# one missing the page crashes on open instead of rendering.
for selector in ('- (id)value {', '- (void)setValue:(id)value {', '- (UIControl *)control {'):
    check(selector in cell_m, 'the card cell must implement ' + selector.strip())
for fragment in ('tableView:(UITableView *)tableView cellForRowAtIndexPath:',
                 '[cell setSpecifier:row];', '[cell setValue:[row performGetter]];',
                 'cell.type = row.cellType;'):
    check(fragment in controller, 'the data source must build the card row: ' + fragment)
check('dequeueReusableCellWithIdentifier:kLMVPPanelCellIdentifier' in controller,
      'card rows must be dequeued, not allocated per scroll')
check('return [super tableView:tableView cellForRowAtIndexPath:indexPath];' in controller,
      'rows that are not card rows must fall through to Preferences')

# 7) the colour row keeps its swatch column, the callout row keeps its name
check('lmvp_trailingReservedWidth' in cell_h, 'the cell must report its reserved column')
check('LMVPPanelColorWidth' in cell_m and 'textWidth = 82.0' in cell_m,
      'the colour row title must stop before the hex text')
check('(self.accessoryView != nil)' in cell_m,
      'a row carrying the material name must not also draw a chevron')

# 8) geometry lives in one header
for constant in ('LMVPPanelTallRowHeight', 'LMVPPanelRowHeight',
                 'LMVPStepperWidth', 'LMVPStepperHeight'):
    check(constant in style, 'geometry constant missing: ' + constant)
check(re.search(r'LMVPPanelTallRowHeight = 66', style) is not None, 'tall rows are 66pt')
check(re.search(r'LMVPStepperWidth = 132', style) is not None, 'the stepper column is 132pt')
check(re.search(r'LMVPStepperHeight = 32', style) is not None, 'the stepper is 32pt tall')
check('LMVPPanelSliderTallRowHeight' not in style, 'the slider row heights must be gone')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 5.31 - card rows built by the data source, cell answers value/setValue/control, numeric rows are steppers')
