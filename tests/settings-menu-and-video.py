#!/usr/bin/env python3
"""2.95: the two-folder menu and the Settings-app video background are GONE.

What the user asked for:
  * 「设置视频背景」 - delete the row, the page and the whole channel (code included)
  * 「桌面视频背景」 - delete the second-level row, keep every feature it held

So the entry controller must now BE the settings page, and none of the removed
classes may exist, compile, or start anything in the Settings process.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
old = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
tweak = (root / 'Tweak.xm').read_text()
makefile = (root / 'Makefile').read_text()

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


# 1) the entry IS the page - no routing layer, no second level
check('self.title = @"锁屏背景视频";' in old, 'entry keeps the title the user taps')
check('self.title = @"桌面视频背景";' not in old, 'no leftover second-level title')
check('- (NSArray *)specifiers {' in old, 'the page still owns every row')
check('openDesktop:' not in old and 'openSettingsVideo:' not in old, 'no routing left')

# 2) everything removed must really be gone from the tree
for name in ('LockMessageVideoPrefs/LMVMenuListController.h',
             'LockMessageVideoPrefs/LMVMenuListController.m',
             'LockMessageVideoPrefs/LMVSettingsVideoController.h',
             'LockMessageVideoPrefs/LMVSettingsVideoController.m',
             'LockMessageVideoPrefs/LMVSettingsVideo.h',
             'LockMessageVideoPrefs/LMVSettingsVideo.m',
             'LMVSettingsVideoChannel.h',
             'LMVSettingsVideoChannel.m'):
    check(not (root / name).exists(), 'removed: ' + name)

# 3) nothing references or builds them any more
check('LMVSettingsVideo' not in tweak, 'tweak does not reference the settings channel')
check('if (LMVSettingsAppProcess()) return;' in tweak, 'the Settings process exits immediately')
check('LMVMenuListController' not in makefile, 'menu no longer compiles')
check('LMVSettingsVideoController.m' not in makefile, 'settings page no longer compiles')
check('LMVSettingsVideoChannel.m' not in makefile, 'settings channel no longer compiles')

# 4) the remaining page is still complete
check('LMVPRootListController' in makefile, 'the page still compiles')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 2.95 - menu layer removed, Settings-app video background deleted (page + channel + build), entry is the desktop page itself')
