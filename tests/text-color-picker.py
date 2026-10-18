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
assert 'Hex 颜色 %@（点击复制）' not in picker, 'the old copy-only readout is gone'
assert 'UITextField *_hex;' in picker and 'hexEdited:' in picker, 'the value readout is an input field'
assert 'LMVColorTextParse' in picker, 'typed #RRGGBB / #RRGGBBAA / percent alpha is parsed'
assert '@"#RRGGBB 100%"' in picker, 'the field advertises hex plus opacity'
assert 'LMVTextColorHex(current)' in picker and '_a*100' in picker, 'value and opacity are shown together'
# 1.89: preview vs commit - dragging must not hit the disk on every event.
assert '- (void)preview {' in picker and '- (void)commit {' in picker
assert 'LMVTextColorStoreColor(color,[self colorKey]);' in picker
assert '@property(nonatomic,copy) NSString *preferenceKey;' in header, 'one picker, key per panel'
assert 'NSString *const LMVSquidTextColorKey = @"SquidTextColor";' in picker
assert 'sliderCommitted:' in picker
# 1.89: the selected swatch is ringed, and the spectrum ring is bigger.
assert 'showRed:' in picker and '_ring.borderWidth=3' in picker
assert '_marker.bounds=CGRectMake(0,0,40,40);' in picker
assert '@"不透明度"' in picker, 'alpha slider'
assert '恢复默认颜色' in picker, 'reset row'
assert 'CAGradientLayer' in picker, 'the slider tracks are gradients'

# --- one key, and "absent" is different from white -----------------------
assert 'extern NSString *const LMVTextColorKey;' in header
assert 'NSString *const LMVTextColorKey = @"CVTextColor";' in picker
assert 'CFPreferencesCopyAppValue((__bridge CFStringRef)key,kLMVColorPrefsID)' in picker, 'keyed read'
assert 'UIColor *LMVTextColorCurrent(void) {\n    return LMVTextColorForKey(LMVTextColorKey);' in picker
assert 'if(![value isKindOfClass:NSNumber.class])return nil;' in picker, \
    'an absent key means keep CopyVault colours'
assert 'LMVTextColorStoreColor(nil,[self colorKey]);' in picker, 'reset removes the key'

# --- apply, then restore -------------------------------------------------
assert 'LMVCVPanelApplyTextColor(card);' in module
assert 'LMVCVPanelRestoreTextColor();' in module, 'closing the panel restores every captured colour'
assert 'weakToStrongObjectsMapTable' in module, 'labels are held weakly, colours strongly'
assert '[LMVCVPanelTextOriginal objectForKey:label]' in module, \
    'the first colour seen wins, so re-applying never loses the original'
assert 'NSForegroundColorAttributeName' in module, 'attributed labels are handled too'

# --- Settings row: round swatch on the right -----------------------------
assert 'preferenceSpecifierNamed:@"文字颜色"' in prefs
assert 'willDisplayCell:' in prefs and 'dot.tag = dotTag;' in prefs and '@(0x5A2C)' in prefs
assert 'dot.layer.cornerRadius = size / 2;' in prefs
assert 'LMVTextColorForKey(row[@"key"])' in prefs, 'each row reads its own key'
assert 'openSquidTextColor:' in prefs, 'the Squid row opens the same picker'
assert 'openCVTextColor:' in prefs
assert 'picker.modalPresentationStyle = UIModalPresentationPageSheet;' in prefs

# --- Easter panel: the row is GONE (1.84) --------------------------------
# The user asked for text colour to disappear from the floating panel, so the
# picker lives only in Settings now.
assert 'cell.textLabel.text = @"文字颜色";' not in panel, 'the Easter panel no longer lists text colour'
assert 'LMVTextColorPicker *picker' not in panel, 'the Easter panel no longer presents the picker'
assert 'if (section == LMVEasterCVSection()) return 4;' in panel

# --- Squid panel gets the same treatment (1.90), Settings only --------------
squid = (root / 'LMVSquidPanelVideo.h').read_text()
assert 'CFSTR("SquidTextColor")' in squid, 'the Squid panel reads its own key'
assert 'LMVSquidPanelApplyTextColor(card);' in squid, 'applied on every poll'
assert 'LMVSquidPanelRestoreTextColor();' in squid, 'restored when the channel stands down'
assert 'LMVSquidPanelTextOriginal' in squid
assert 'cell.textLabel.text = @"文字颜色";' not in panel and 'LMVTextColorPicker *picker' not in panel
print('PASS: 1.83/1.90 text colour - shared picker with per-panel keys, one RGBA word, restore on detach, Squid recolour in Settings only')
