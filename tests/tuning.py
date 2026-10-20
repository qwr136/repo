#!/usr/bin/env python3
"""自定义参数的契约（2.44 精简后）。

2.39 给 13 个通道各做了一套参数，2.44 按用户要求只保留“探测”一组：

* 目标从 13 个减到 8 个面板通道（删掉 锁屏 / 桌面 / 控制中心 / 主屏菜单 / 悬浮球）；
* 每组只留 探测：检测频率、出现延迟、关闭延迟、钩子节流；
* 播放（帧率上限 / 播放速度 / 填充方式 / 循环次数）、可见性（面板不可见）、
  性能（低电量 / 过热）整组删除，运行时也不再读取这些键。

本测试锁住精简后的形状，防止旧参数或旧读取路径被悄悄加回来。
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tuning = (root / 'LMVPanelTuning.h').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
tune_controller = (root / 'LockMessageVideoPrefs/LMVTuneController.m').read_text()
playback = (root / 'LMVLockVideoPlayback.h').read_text()
makefile = (root / 'Makefile').read_text()
workflow = (root / '.github/workflows/build.yml').read_text()

# ---- 1) 目标：只剩 8 个面板通道 ------------------------------------------------
targets = ['SquidPanel', 'AT', 'CV', 'Myrtle', 'PA', 'GS', 'CCBorder', 'CopyLogX']
for target in targets:
    assert f'@"{target}"' in tuning, target
# 2.46: the user asked for the desktop's cadence to be tunable (it is the only
# non-panel channel running a display link all the time), so Desktop is back in the
# list with its own 刷新 group. Lock/ControlCenter/HomeMenu/Bubble stay out.
assert '@"Desktop"' in tuning
for gone in ('Lock', 'ControlCenter', 'HomeMenu', 'Bubble'):
    assert f'@"{gone}"' not in tuning, f'{gone} must be gone from the tuning targets'

# ---- 2) 参数表：只有探测组 ------------------------------------------------------
for key in ('ProbeHz', 'ShowDelayMs', 'HideDelayMs', 'HookThrottleMs'):
    assert f'LMVTuneParam(@"{key}"' in tuning, key
for gone in ('MaxFPS', 'RatePercent', 'Gravity', 'LoopCount',
             'HiddenAction', 'LowPowerAction', 'ThermalAction',
             'BubbleSize', 'BubbleAlpha'):
    assert f'LMVTuneParam(@"{gone}"' not in tuning, gone
assert '@"探测"' in tuning
for gone in ('@"播放"', '@"可见性"', '@"性能"'):
    assert gone not in tuning, gone
assert 'LMVTuneBubbleGroups' not in tuning
# desktop cadence rows, and the runtime must actually read them
assert 'LMVTuneParam(@"IdleFPS"' in tuning and 'LMVTuneParam(@"CoveredFPS"' in tuning
assert '@"刷新"' in tuning
desktop = (root / 'LMVDesktopVideo.h').read_text()
assert 'LMVTuneValue(@"Desktop",@"IdleFPS")' in desktop
assert 'LMVTuneValue(@"Desktop",@"CoveredFPS")' in desktop
assert 'burst?60:LMVDesktopCadence(@"CoveredFPS")' in desktop
assert 'LMVDesktopCadence(@"IdleFPS")' in desktop

# ---- 3) 写入必须广播，常驻通道才知道值变了 --------------------------------------
assert 'CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter()' in tuning
assert 'com.minis.lockmessagevideo/preferencesChanged' in tuning
assert 'if (hz > 60) hz = 60;' in tuning
assert '[NSString stringWithFormat:@"Tune.%@.%@", target, key]' in tuning
assert 'LMVTuneProbeInterval(NSString *target)' in tuning
assert 'LMVTuneDelay(NSString *target, NSString *key)' in tuning

# ---- 4) 八个面板通道仍然能设 出现/关闭 延迟 -----------------------------------
sheet_delay = tuning[tuning.index('LMVTuneHasSheetDelay(NSString *target)'):tuning.index('LMVTuneHasHook(NSString *target)')]
for target in targets:
    assert f'@"{target}"' in sheet_delay, f'{target} missing from sheet-delay list'
hook = tuning[tuning.index('LMVTuneHasHook(NSString *target)'):]
hook = hook[:hook.index('}')]
assert '@"GS"' in hook and '@"CopyLogX"' in hook
for target in targets:
    if target not in ('GS', 'CopyLogX'):
        assert f'@"{target}"' not in hook, target

# ---- 5) 设置页入口与子控制器 ---------------------------------------------------
assert 'groupSpecifierWithName:@"自定义参数"' in prefs
assert 'for (NSDictionary *item in LMVTuneTargets())' in prefs
assert 'row.buttonAction = @selector(openTune:);' in prefs
assert 'initWithTarget:target' in prefs
assert 'LMVTuneController.m' in makefile
assert 'cell:PSButtonCell' in tune_controller
assert 'LMVTuneGroupsForTarget(self.target)' in tune_controller
assert 'LMVTuneSetValue(self.target' in tune_controller

# ---- 6) 运行时不再读被删掉的键 -------------------------------------------------
assert 'LMVTune' not in playback, '播放引擎不应再读任何调参键'
assert 'loopRemaining' not in playback and 'policyHidden' not in playback
assert 'AVPlayerLooper playerLooperWithPlayer' in playback

bubble_media = (root / 'LMVEasterMedia.h').read_text()
bubble_overlay = (root / 'LMVEasterOverlay.h').read_text()
assert 'BubbleSize' not in bubble_media and 'BubbleAlpha' not in bubble_overlay

# ---- 7) 探测参数仍被八个通道读取 -----------------------------------------------
channels = [
    ('LMVATPanelVideo.h', 'AT'),
    ('LMVCCBorderVideo.h', 'CCBorder'),
    ('LMVCopyVaultPanelVideo.h', 'CV'),
    ('LMVMyrtlePanelVideo.h', 'Myrtle'),
    ('LMVPhoneAssistVideo.h', 'PA'),
    ('LMVSquidPanelVideo.h', 'SquidPanel'),
    ('LMVGlassSuiteVideo.h', 'GS'),
    ('LMVCopyLogXVideo.h', 'CopyLogX'),
]
for file, target in channels:
    src = (root / file).read_text()
    # 2.45: LMVLockVideoPlayback.target existed only to look up Tune.<target>.* at
    # playback time. 2.44 removed every key it could look up, which left it as a
    # write-only property; it is now deleted outright, so the per-channel assertion
    # that required the assignment is gone (behaviour is unchanged - the probe
    # interval below is still read per channel).
    assert '_playback.target' not in src, f'{file}: target assignment must be gone'
    assert f'LMVTuneProbeInterval(@"{target}")' in src, f'{file}: probe'

# ---- 8) 素材显示：设置行必须查目录里的显示名，而不是文件 UUID -------------------
assert 'LMVReadMaterialNames()[path]' in prefs, 'material row must use the catalog name'
assert '[value lastPathComponent]' not in prefs, 'file name is the last resort only'

# ---- 9) 本测试已接入 CI --------------------------------------------------------
assert 'tests/tuning.py' in workflow

print('PASS: 8 panel channels x probe group only (frequency/delays/hook throttle); '
      'playback/visibility/perf and the bubble knobs are gone from both the UI and the '
      'playback engine; material rows resolve their catalog name')
