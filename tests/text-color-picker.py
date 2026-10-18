#!/usr/bin/env python3
"""1.83: CopyVault text colour.

One shared picker (Settings + Easter panel), one stored RGBA word, and a
copy-and-restore pass over the panel's labels so CopyVault's own colours come
back the moment the video goes away. These contracts are static because the
picker itself needs UIKit; the wiring is what breaks across releases.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
header = (root / 'LMVTextColorPicker.h').read_text()
picker = (root / 'LMVTextColorPicker.m').read_text()
module = (root / 'LMVCopyVaultPanelVideo.h').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
panel = (root / 'LMVEasterPanel.h').read_text()
makefile = (root / 'Makefile').read_text()

# --- one implementation, two hosts ---------------------------------------
assert 'Tweak.xm LMVTextColorPicker.m' in makefile, 'the tweak compiles the picker (Easter panel)'
assert 'LMVPRootListController.m LMVTextColorPicker.m' in makefile, 'the bundle compiles the same picker'

# --- the sheet the user asked for ----------------------------------------
assert 'title.text=@"文字颜色";' in picker, 'the sheet is titled 文字颜色, not Face ID'
assert '[@"红色",@"绿色",@"蓝色"]' in picker, 'three RGB sliders'
assert 'Hex 颜色 %@（点击复制）' in picker, 'hex readout'
assert '@"不透明度"' in picker, 'alpha slider'
assert '恢复默认颜色' in picker, 'reset row'
assert 'CAGradientLayer' in picker, 'the slider tracks are gradients'

# --- one key, and "absent" is different from white -----------------------
assert 'extern NSString *const LMVTextColorKey;' in header
assert 'NSString *const LMVTextColorKey = @"CVTextColor";' in picker
assert 'CFPreferencesCopyAppValue((__bridge CFStringRef)LMVTextColorKey' in picker
assert 'if(![value isKindOfClass:NSNumber.class])return nil;' in picker, \
    'an absent key means keep CopyVault colours'
assert 'LMVTextColorStore(nil)' in picker, 'reset removes the key'

# --- apply, then restore -------------------------------------------------
assert 'LMVCVPanelApplyTextColor(card);' in module
assert 'LMVCVPanelRestoreTextColor();' in module, 'closing the panel restores every captured colour'
assert 'weakToStrongObjectsMapTable' in module, 'labels are held weakly, colours strongly'
assert '[LMVCVPanelTextOriginal objectForKey:label]' in module, \
    'the first colour seen wins, so re-applying never loses the original'
assert 'NSForegroundColorAttributeName' in module, 'attributed labels are handled too'

# --- Settings row: round swatch on the right -----------------------------
assert 'preferenceSpecifierNamed:@"文字颜色"' in prefs
assert 'willDisplayCell:' in prefs and 'viewWithTag:0x5A2C' in prefs
assert 'dot.layer.cornerRadius = size / 2;' in prefs
assert 'LMVTextColorCurrent()' in prefs
assert 'openCVTextColor:' in prefs
assert 'picker.modalPresentationStyle = UIModalPresentationPageSheet;' in prefs

# --- Easter panel: same row, same picker ---------------------------------
assert 'if (section == LMVEasterCVSection()) return 5;' in panel
assert 'cell.textLabel.text = @"文字颜色";' in panel
assert 'LMVTextColorPicker *picker = [LMVTextColorPicker new];' in panel
assert 'picker.onChange = ^(UIColor *color) { [weakSelf.tableView reloadData]; };' in panel

print('PASS: 1.83 CopyVault text colour - shared picker, one RGBA key, restore on detach')
