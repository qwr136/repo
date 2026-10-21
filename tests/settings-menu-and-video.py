#!/usr/bin/env python3
"""2.63: two second-level folders, and the Settings-app video background.

The user asked for exactly two entry pages:
  * 桌面视频背景  - every existing setting (lock/home/CC/panels/egg/...), unchanged
  * 设置视频背景  - a new channel: the Settings app's own video background, with
                    an enable switch, a material picker that shows previews, a
                    sound switch, a volume slider and import into its own folder
                    /var/mobile/LockMessageVideo/设置视频背景

This test locks the shape: the entry controller routes only, the old settings
page still owns every row, and the new page/player use their own keys and folder.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
menu = (root / 'LockMessageVideoPrefs/LMVMenuListController.m').read_text()
menu_h = (root / 'LockMessageVideoPrefs/LMVMenuListController.h').read_text()
old = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
settings = (root / 'LockMessageVideoPrefs/LMVSettingsVideoController.m').read_text()
player = (root / 'LMVSettingsVideoChannel.h').read_text()
player_impl = (root / 'LMVSettingsVideoChannel.m').read_text()
makefile = (root / 'Makefile').read_text()

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


# 1) the menu has exactly the two entries the user named
check('@"桌面视频背景"' in menu, 'menu: 桌面视频背景 entry')
check('@"设置视频背景"' in menu, 'menu: 设置视频背景 entry')
check(menu.count('PSButtonCell') == 2, 'menu: exactly two buttons')
check('openDesktop:' in menu and 'openSettingsVideo:' in menu, 'menu: pushes both pages')
check('LMVPRootListController' in menu, 'menu: desktop page is the old root list')
check('LMVSettingsVideoController' in menu, 'menu: settings page is the new controller')
# the old page keeps every row: it must not have lost its specifier builder
check('- (NSArray *)specifiers {' in old, 'desktop page still owns its rows')
check('self.title = @"桌面视频背景";' in old, 'desktop page title')

# 2) the new page: enable / material / sound / volume / import
for token in ('启用设置视频背景', '切换视频', '声音开关', '声音大小（%）', '导入素材', '打开素材路径'):
    check(f'@"{token}"' in settings or token in settings, f'page row: {token}')
check('PSButtonCell' in settings and 'PSSwitchCell' in settings and 'PSSliderCell' in settings,
      'page row cell types')
check(LMV := 'LMVSettingsVideoEnabledKey' in settings, 'page writes the enable key')
check('LMVSettingsVideoSoundKey' in settings, 'sound switch key')
check('LMVSettingsVideoVolumeKey' in settings, 'volume key')

# 3) its own folder, its own keys - never the shared library
check('设置视频背景' in player, 'material folder is 设置视频背景')
check('SettingsVideoBackgroundEnabled' in player, 'enable key name')
check('SettingsVideoSoundEnabled' in player, 'sound key name')
check('SettingsVideoVolume' in player, 'volume key name')
check('"library"' not in player and 'library/' not in player, 'no shared library path')
check('AVQueuePlayer' in player and 'AVPlayerLooper' in player, 'looping player')
check('AVLayerVideoGravityResizeAspectFill' in player_impl, 'fills the window')
# 2.75: the host goes directly BELOW the list (the Settings app keeps an opaque
# UITransitionView between the window and the table, so a window-level host never
# shows), and the list/cell backgrounds are cleared so the text sits on the video.
check('insertSubview:self.host atIndex:(NSUInteger)wantIndex' in player_impl, 'background sits under the list')
check('exchangeSubviewAtIndex' in player_impl, 'a one-slot drift is an exchange, not a re-insert (no flicker)')
check('tableIn:' in player_impl and 'clearCellBackgroundsIn:' in player_impl, 'list/cell transparency')
check('LMV_VERSION_STRING' in player_impl, 'diagnostic line carries the real version')
check('CMTimeMake(1, 10)' in settings or 'copyCGImageAtTime' in settings, 'picker shows a preview frame')

# 4) build wiring
check('LMVMenuListController.m' in makefile, 'menu compiles')
check('LMVSettingsVideoController.m' in makefile, 'page compiles')
check('LMVSettingsVideoChannel.m' in makefile, 'player compiles in the tweak')
check('com.apple.Preferences' in (root/'LockMessageVideo.plist').read_text(), 'injected into the Settings process')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: two-level menu (桌面视频背景 / 设置视频背景) and the Settings-app video background page/player')