#!/usr/bin/env python3
"""每个视频背景一套自定义参数的契约（2.39）。

设置页在「CopyLogX 视频背景」下面有一个「自定义参数」分组，点进去是 13 个通道；
每个通道再点进去，是该通道自己的探测 / 播放 / 可见性 / 性能参数，互不共用。

本测试锁住：
1. 13 个通道、每个通道四个分组、参数键前缀 Tune.<target>.<key>；
2. 悬浮球有自己的一组（没有视频参数）；
3. 设置页入口位置正确，并有独立的子控制器；
4. 探测频率 / 钩子节流 / 出现延迟 / 关闭延迟真的被各通道读取；
5. 播放层的 gravity / 速率 / 循环 / 不可见策略 / 低电量 / 过热读同一套参数；
6. 每个通道都设置了自己的 target。
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tuning = (root / 'LMVPanelTuning.h').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
tune_controller = (root / 'LockMessageVideoPrefs/LMVTuneController.m').read_text()
playback = (root / 'LMVLockVideoPlayback.h').read_text()
makefile = (root / 'Makefile').read_text()
workflow = (root / '.github/workflows/build.yml').read_text()

targets = ['Lock', 'Desktop', 'ControlCenter', 'HomeMenu', 'SquidPanel', 'AT', 'CV',
           'Myrtle', 'PA', 'GS', 'CCBorder', 'CopyLogX', 'Bubble']
for target in targets:
    assert f'@"{target}"' in tuning, target
assert len(targets) == 13

# ---- 1) 参数表 --------------------------------------------------------------
for key in ('ProbeHz', 'ShowDelayMs', 'HideDelayMs', 'HookThrottleMs',
            'MaxFPS', 'RatePercent', 'Gravity', 'Loop',
            'HiddenAction', 'OccludedAction', 'LockedAction', 'ForegroundAction',
            'LowPowerAction', 'ThermalAction'):
    assert f'LMVTuneParam(@"{key}"' in tuning, key
for group in ('@"探测"', '@"播放"', '@"可见性"', '@"性能"'):
    assert group in tuning, group

# 悬浮球只有自己的一组，不出现视频参数
bubble = tuning[tuning.index('LMVTuneBubbleGroups'):tuning.index('LMVTuneGroupsForTarget(NSString *target)')]
assert 'BubbleSize' in bubble and 'BubbleAlpha' in bubble and 'BubbleSnap' in bubble
assert 'MaxFPS' not in bubble and 'HiddenAction' not in bubble

# ---- 2) 存储：每个通道独立 ---------------------------------------------------
assert '[NSString stringWithFormat:@"Tune.%@.%@", target, key]' in tuning
assert 'CFPreferencesSetAppValue(full' in tuning
assert 'CFNotificationCenterPostNotification' in tuning
assert 'LMVTuneProbeInterval(NSString *target)' in tuning
assert 'return 1.0 / (NSTimeInterval)hz;' in tuning
assert 'LMVTuneDelay(NSString *target, NSString *key)' in tuning

# ---- 3) 设置页入口 -----------------------------------------------------------
assert 'groupSpecifierWithName:@"自定义参数"' in prefs
copy_start = prefs.index('groupSpecifierWithName:@"CopyLogX 视频背景"')
tune_start = prefs.index('groupSpecifierWithName:@"自定义参数"')
egg_start = prefs.index('groupSpecifierWithName:@"小彩蛋"')
assert copy_start < tune_start < egg_start, 'the tuning group sits below CopyLogX'
assert 'for (NSDictionary *item in LMVTuneTargets())' in prefs
assert 'row.buttonAction = @selector(openTune:);' in prefs
assert 'initWithTarget:target' in prefs
assert 'LMVTuneController.m' in makefile

# ---- 4) 子控制器：滑块 + 枚举 ------------------------------------------------
assert 'cell:PSSliderCell' in tune_controller
assert 'cell:PSButtonCell' in tune_controller
assert 'cycleEnum:' in tune_controller
assert 'LMVTuneGroupsForTarget(self.target)' in tune_controller
assert 'LMVTuneSetValue(self.target' in tune_controller

# ---- 5) 探测参数被各通道读取 -------------------------------------------------
channels = [
    ('LMVATPanelVideo.h', 'AT'),
    ('LMVCCBorderVideo.h', 'CCBorder'),
    ('LMVCopyVaultPanelVideo.h', 'CV'),
    ('LMVMyrtlePanelVideo.h', 'Myrtle'),
    ('LMVPhoneAssistVideo.h', 'PA'),
    ('LMVSquidPanelVideo.h', 'SquidPanel'),
    ('LMVGlassSuiteVideo.h', 'GS'),
    ('LMVCopyLogXVideo.h', 'CopyLogX'),
    ('LMVLockVideo.h', 'Lock'),
    ('LMVDesktopVideo.h', 'Desktop'),
    ('LMVControlCenterVideo.h', 'ControlCenter'),
    ('LMVHomeMenuVideo.h', 'HomeMenu'),
]
for file, target in channels:
    src = (root / file).read_text()
    assert f'_playback.target=@"{target}";' in src, f'{file}: target'

for file, target in channels[:8]:
    src = (root / file).read_text()
    assert f'LMVTuneProbeInterval(@"{target}")' in src, f'{file}: probe'

# ---- 6) 钩子节流与延迟 -------------------------------------------------------
gs = (root / 'LMVGlassSuiteVideo.h').read_text()
clx = (root / 'LMVCopyLogXVideo.h').read_text()
assert 'NSTimeInterval limit=LMVTuneDelay(@"GS",@"HookThrottleMs");' in gs
assert 'LMVTuneDelay(@"GS",@"ShowDelayMs")' in gs
assert 'LMVTuneDelay(@"GS",@"HideDelayMs")' in gs
assert 'NSTimeInterval limit=LMVTuneDelay(@"CopyLogX",@"HookThrottleMs");' in clx
assert 'LMVTuneDelay(@"CopyLogX",@"ShowDelayMs")' in clx
assert 'LMVTuneDelay(@"CopyLogX",@"HideDelayMs")' in clx

# ---- 7) 播放层 ---------------------------------------------------------------
assert 'LMVTuneValue(self.target,@"Gravity")' in playback
assert 'LMVTuneValue(self.target,@"RatePercent")' in playback
assert 'LMVTuneValue(live.target,@"Loop")' in playback
assert 'LMVTuneValue(self.target,@"HiddenAction")' in playback
assert 'LMVTuneValue(self.target,@"LowPowerAction")' in playback
assert 'LMVTuneValue(self.target,@"ThermalAction")' in playback
assert 'AVPlayerActionAtItemEndPause' in playback

# ---- 8) CI ------------------------------------------------------------------
assert 'check python3 tests/tuning.py' in workflow

print('PASS: per-channel tuning - 13 channels (incl. bubble), four groups with '
      'Tune.<target>.<key> storage, settings page below CopyLogX, dedicated '
      'PSListController with sliders/enums, probe Hz + hook throttle + show/hide '
      'delay wired in GS/CopyLogX, playback gravity/rate/loop/visibility/'
      'low-power/thermal, CI wired')
