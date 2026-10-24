#!/usr/bin/env python3
"""4.0.1: the material row must not lie.

Three user-reported defects, all in the settings list:

  1. the name was truncated in the MIDDLE ("相册原…音图层") instead of at the end;
  2. an empty library showed "视频素材 1" on every row instead of 未选择;
  3. deleting the last material left the Message background on screen, because a
     persisted path was trusted even after its file was gone.

The row label, the preference loader and the version chain are all checked here.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
row = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
tweak = (root / 'Tweak.xm').read_text()
makefile = (root / 'Makefile').read_text()
control = (root / 'control').read_text()
info = (root / 'LockMessageVideoPrefs/Info.plist').read_text()
paths = (root / 'LMVPaths.h').read_text()

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


# 1) tail truncation, never middle truncation
check('NSLineBreakByTruncatingTail' in row, 'the material label must truncate at the tail')
check('NSLineBreakByTruncatingMiddle' not in row, 'middle truncation cut words in half')
check('adjustsFontSizeToFitWidth = NO' in row,
      'the label must keep one font size on every row (4.0.3: autoshrink made equal names differ)')
check('adjustsFontSizeToFitWidth = YES' not in row, 'auto-shrink is forbidden')
check('minimumScaleFactor = 1.0' in row, 'no scaling below 1.0')

# 2) a missing file is 未选择, never a generated "视频素材 N"
check('fileExistsAtPath:[LMV_CATALOG_ROOT stringByAppendingPathComponent:path]' in row,
      'the row must verify the selected file before naming it')
check('@"未选择"' in row, 'an empty / missing selection reads 未选择')

# 4.0.4: deleting or renaming inside the picker happens AFTER it dismisses, so the
# page must be told to repaint, and the delete must clear every channel's key.
picker = (root / 'LockMessageVideoPrefs/LMVMaterialPicker.h').read_text()
deletion = (root / 'LockMessageVideoPrefs/LMVMaterialDeletion.h').read_text()
check('void (^libraryChanged)(void)' in picker, 'the picker needs a library-changed hook')
check(picker.count('live.libraryChanged()') >= 3, 'delete (both flows) and rename must fire the hook')
check('picker.libraryChanged = ^{ [weakSelf refreshMaterialRows]; };' in row,
      'the settings page must repaint when the library changes')
check('@"CopyLogX"' in deletion and '@"Myrtle"' in deletion,
      'deleting a material must clear every channel, not just the 1.x ones')

# 3) the tweak must not trust a persisted path whose file is gone
check('if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;' in tweak,
      'preferences must require the selected file to exist')
check('!explicitSelection && ![[NSFileManager' not in tweak,
      'existence must be checked for explicit selections too')

# 4) version chain: Makefile == control == Info.plist == runtime string
version = re.search(r'^LMV_VERSION = (\S+)$', makefile, re.M)
check(version is not None, 'Makefile must declare LMV_VERSION')
if version:
    ver = version.group(1)
    check(re.search(r'^Version: (\S+)$', control, re.M).group(1) == ver, 'control version mismatch')
    check(info.count('<string>%s</string>' % ver) >= 2, 'Info.plist version mismatch (need both keys)')
    check('LMV_VERSION_STRING @"%s"' % ver in paths, 'runtime version string mismatch')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 4.0.5 - one font size, tail truncation, 未选择 on empty library, missing-file selection rejected, version chain consistent')
