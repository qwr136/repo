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
tune_list = (root / 'LockMessageVideoPrefs/LMVTuneListController.m').read_text()
playback = (root / 'LMVLockVideoPlayback.h').read_text()
makefile = (root / 'Makefile').read_text()
workflow = (root / '.github/workflows/build.yml').read_text()

# ---- 1) 目标：只剩 8 个面板通道 ------------------------------------------------
targets = ['SquidPanel', 'AT', 'CV', 'Myrtle', 'PA', 'GS', 'CCBorder', 'CopyLogX', 'HomeMenu']
for target in targets:
    assert f'@"{target}"' in tuning, target
# 2.46: the user asked for the desktop's cadence to be tunable (it is the only
# non-panel channel running a display link all the time), so Desktop is back in the
# list with its own 刷新 group. Lock/ControlCenter/HomeMenu/Bubble stay out.
assert '@"Desktop"' in tuning
# 2.48: the ball and the notification-card link are tunable too, and the list is split
# into two sections (panel / other) so nine+ rows are not one wall of text.
assert '@"Bubble"' in tuning and '@"Cards"' in tuning
assert '@"group":@"panel"' in tuning and '@"group":@"other"' in tuning
# 2.61: the desktop long-press menu is a panel channel too now (user request), so it
# is back in the list with the same three rows. Lock and ControlCenter stay out.
for gone in ('Lock', 'ControlCenter'):
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
# 2.47: a change of cadence must leave one diagnostic line, so "did my value take
# effect?" is answerable from a capture instead of from feel.
assert 'desktop-cadence want=%ld idle=%ld covered=%ld' in desktop
# 2.48: the two new cadences and the runtime report that makes "当前生效" possible.
assert 'LMVTuneParam(@"TickHz"' in tuning and 'LMVTuneParam(@"FPS"' in tuning
assert 'LMVTuneReport(NSString *target, NSString *key, NSInteger value)' in tuning
assert '"Runtime.%@.%@"' in tuning
overlay = (root / 'LMVEasterOverlay.h').read_text()
assert 'LMVTuneValue(@"Bubble",@"TickHz")' in overlay
assert 'LMVTuneReport(@"Bubble",@"TickHz",tickHz)' in overlay
tweak = (root / 'Tweak.xm').read_text()
assert 'LMVTuneValue(@"Cards",@"FPS")' in tweak
# every applied value goes through the two readers below, so a page can always show it
assert 'LMVTuneReport(target, @"ProbeHz", hz)' in tuning
assert 'LMVTuneReport(target, key, ms)' in tuning
assert 'LMVDesktopCadence(@"IdleFPS")' in desktop

# ---- 3) 写入必须广播，常驻通道才知道值变了 --------------------------------------
assert 'CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter()' in tuning
assert 'com.minis.lockmessagevideo/preferencesChanged' in tuning
assert 'if (hz > 60) hz = 60;' in tuning
assert '[NSString stringWithFormat:@"Tune.%@.%@", target, key]' in tuning
# 2.50: the runtime report MUST use its own domain. Writing Runtime.* into the
# settings domain and synchronising from SpringBoard flushed that process's stale
# snapshot back to disk and silently reverted the saved value (device log: idle=30
# after the user set 10). Guard the separation so it cannot come back.
assert 'LMVTuneRuntimeDomain = @"com.minis.lockmessagevideo.runtime"' in tuning
report_body = tuning[tuning.index('LMVTuneReport(NSString *target'):]
report_body = report_body[:report_body.index('\n}')]
assert 'LMVTuneRuntimeDomain' in report_body
assert 'LMVTuneDomain)' not in report_body, 'runtime report must not touch the settings domain'
assert 'LMVTuneRuntimeAge' in tuning and '当前生效' in (root / 'LockMessageVideoPrefs/LMVTuneController.m').read_text()
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
# 2.48: one 自定义参数 block became two sections (面板 / 其他).
# 2.52: back to ONE section, 功能面板参数, as the user asked.
# 2.54: two-level menu - the root list keeps ONE entry, the channel rows live in
# LMVTuneListController, and each of those pushes the per-channel page.
assert 'preferenceSpecifierNamed:@"功能面板参数"' in prefs
assert 'buttonAction = @selector(openTuneList:);' in prefs
assert 'for (NSDictionary *item in LMVTuneTargets())' in tune_list
assert 'row.buttonAction = @selector(openTune:);' in tune_list
assert 'initWithTarget:value' in tune_list
assert 'groupSpecifierWithName:@"功能面板参数"' in tune_list
assert 'LMVTuneListController.m' in makefile
assert 'LMVTuneController.m' in makefile
assert 'cell:PSButtonCell' in tune_controller
assert 'LMVTuneGroupsForTarget(self.target)' in tune_controller
assert 'LMVTuneSetValue(self.target' in tune_controller
# 2.52: the visible-state value must carry its OWN age (the shared stamp moves with the
# 2 Hz heartbeat, which made a minutes-old value look freshly measured), and when it
# disagrees with the saved setting the page has to say when it will apply.
assert '"Runtime.%@.%@.At"' in tuning
assert 'LMVTuneRuntimeKeyAge(NSString *target, NSString *key)' in tuning
assert 'LMVTuneRuntimeKeyAge(self.target, @"IdleApplied")' in tune_controller
assert '回桌面后按 %ld 生效' in tune_controller
# ...and the observation itself has to be stamped, or "3 分钟前" would really mean
# "the value has not changed for 3 minutes" (the report returns early on no change).
assert 'LMVTuneTouch(NSString *target, NSString *key)' in tuning
assert 'LMVTuneTouch(@"Desktop",@"IdleApplied")' in desktop
# 2.54: the measured rate is COUNTED from the display-link callbacks and reported, so
# 设定 20 / 实测 19 is a real comparison instead of two names for the same number.
assert 'LMVTuneReport(@"Desktop", @"MeasuredFPS", measured)' in desktop
assert 'self.measuredTicks += 1;' in desktop
assert 'LMVTuneTouch(@"Desktop", @"MeasuredFPS")' in desktop
assert '实测 %ld（%@）' in tune_controller

# ---- 6) 运行时不再读被删掉的键 -------------------------------------------------
assert 'LMVTune' not in playback, '播放引擎不应再读任何调参键'
assert 'loopRemaining' not in playback and 'policyHidden' not in playback
assert 'AVPlayerLooper playerLooperWithPlayer' in playback

bubble_media = (root / 'LMVEasterMedia.h').read_text()
bubble_overlay = (root / 'LMVEasterOverlay.h').read_text()
assert 'BubbleSize' not in bubble_media and 'BubbleAlpha' not in bubble_overlay

# ---- 7) 探测参数仍被八个通道读取 -----------------------------------------------
channels = [
    ('LMVHomeMenuVideo.h', 'HomeMenu'),
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
assert 'NSDictionary *names = [self materialNames];' in prefs and 'name = names[path];' in prefs, 'material row must use the catalog name (through the shared copy, 4.1.1)'
assert 'self.materialNamesCache = LMVReadMaterialNames();' in prefs, 'the shared copy still comes from the catalog'
assert '[value lastPathComponent]' not in prefs, 'file name is the last resort only'

# ---- 8.5) 4.4.0: the two poll timers honour a row -----------------------------
# Both were literals (desktop .2 s = 5 Hz, Control Center .1 s = 10 Hz), so the
# expensive full probe ran at those rates no matter what the frequency rows said.
# The rows below exist so the rate can be changed without a rebuild.
cc = (root / 'LMVControlCenterVideo.h').read_text()

assert 'LMVTuneParam(@"UpdateIntervalMs", @"完整探测间隔 (ms, 0~2000)", 0, 2000, 200)' in tuning, \
    'desktop full-probe interval row missing (default 200 ms = the old 0.2 s)'
assert 'LMVTuneParam(@"UpdateIntervalMs", @"完整探测间隔 (ms, 0~2000)", 0, 2000, 100)' in tuning, \
    'control-centre full-probe interval row missing (default 100 ms = the old 0.1 s)'

# The wake interval stays at the old value on purpose: it is the response floor,
# the row only decides how often the expensive probe behind it runs.
assert 'timerWithTimeInterval:.2 repeats:YES' in desktop, 'desktop wake interval changed'
assert 'timerWithTimeInterval:.1 repeats:YES' in cc, 'control-centre wake interval changed'

# Reading it is not enough - the value must gate the probe, and the gate must be
# on the path to [update], otherwise the row is decoration.
assert 'LMVTuneValue(@"Desktop",@"UpdateIntervalMs")' in desktop, 'desktop does not read the row'
assert 'LMVTuneValue(@"CC",@"UpdateIntervalMs")' in cc, 'control centre does not read the row'
# 4.4.2: the timer and the cover watcher both drive the desktop, so the effective
# rate is the SLOWER of 「可见刷新率」 and 「完整探测间隔」 - that is what makes the
# FPS row mean what it says instead of being overridden by the interval row.
assert 'NSTimeInterval interval=1.0/(NSTimeInterval)MAX((NSInteger)1,targetFPS);' in desktop, \
    'desktop effective rate is not derived from the FPS row'
assert 'if (interval < updateMs/1000.0) interval = updateMs/1000.0;' in desktop, \
    'desktop interval row is not treated as a floor'
assert 'if(!forced && now-live.lastFullUpdate < interval) return;' in desktop, \
    'desktop probe is not gated by the effective interval'
assert 'targetFPS=(live.playback.frozen || live.appAway)' in desktop, \
    'desktop gate ignores frozen/away'
assert 'if(now-live.lastFullUpdate < updateMs/1000.0) return;' in cc, \
    'control-centre probe is not gated by the row'

# A material change must still apply on the tick it arrives, not up to one
# interval later - the gate may never delay a revision.
assert 'forced=YES' in desktop, 'desktop material change is gated away'

# The classic list and the gallery page render the same table, so one row reaches
# both entries; this pins the classic entry that used to be the only one.
assert 'pushViewController:[LMVTuneListController new]' in prefs, 'classic entry missing'

# ---- 8.6) 4.4.1: the lock screen's row must actually reach 1 Hz ---------------
# A CADisplayLink cannot be slower than its own divisor (4 Hz on a 120 Hz panel),
# so a row set to 1 used to run at 4. The gate is what makes the number honest.
lock = (root / 'LMVLockVideo.h').read_text()
assert 'LMVTuneValue(@"LockNC",@"ProbeHz")' in lock, 'lock screen ignores its row'
assert 'if (gateNow-self.lastFullProbe < 1.0/probeHz) return;' in lock, \
    'lock screen tick is not gated by the row'
assert 'probeHz>0 && !lockAllowedChanged' in lock, \
    'lock screen edge is gated away (screen off/on would be late)'
assert 'lockAllowedChanged=(lockAllowed!=self.screenAllowed)' in lock, \
    'lock screen no longer detects the screen-state edge'

# ---- 8.7) 4.4.1: every channel that claims a cadence must be measurable -------
# cards and bubble had no perf line, so "刷新率 = 45" could only be proven as
# written. Both now sample, and the sampler buckets by channel name because they
# share Tweak.xm as one translation unit.
common = (root / 'LMVPanelCommon.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
easier = (root / 'LMVEasterOverlay.h').read_text()
assert 'LMVPerfSample("cards"' in tweak, 'cards has no perf sample'
assert 'LMVPerfSample("bubble"' in easier, 'bubble has no perf sample'
assert 'strcmp(names[i], channel)' in common, 'perf counters still share one bucket'
# 4.4.3: Tweak.xm hosts eleven channels; 8 slots silently dropped pa/cards/bubble.
assert 'names[24]' in common, 'perf bucket table too small for eleven channels'
assert 'dropped=%lu' in common, 'dropped channels are not reported'
assert 'LMVPerfSample("desktop"' in desktop and 'LMVPerfSample("cc"' in cc
assert 'LMVPerfSample("lock"' in lock

# ---- 8.8) 4.4.2: cards must honour the exact value ---------------------------
# A display link rounds 45 Hz down to 30, so the row was only honoured on divisors
# of the panel rate. The gate makes the number exact.
tweak_src = (root / 'Tweak.xm').read_text()
assert 'lastCardTick' in tweak_src, 'cards have no gate stamp'
assert 'if (self.lastCardTick>0 && cardsNow-self.lastCardTick < 1.0/(NSTimeInterval)cardsHz) return;' in tweak_src, \
    'cards tick is not gated by the row'

# ---- 8.9) every panel channel reports its own cadence ------------------------
for fn, short in (('LMVSquidPanelVideo.h','squid'), ('LMVATPanelVideo.h','at'),
                  ('LMVCopyVaultPanelVideo.h','cv'), ('LMVMyrtlePanelVideo.h','myrtle'),
                  ('LMVPhoneAssistVideo.h','pa'), ('LMVGlassSuiteVideo.h','gs'),
                  ('LMVCCBorderVideo.h','ccb'), ('LMVCopyLogXVideo.h','clx'),
                  ('LMVHomeMenuVideo.h','homemenu')):
    body = (root / fn).read_text()
    assert f'LMVPerfSample("{short}"' in body, f'{fn} has no perf sample'

# ---- 9) 本测试已接入 CI --------------------------------------------------------
assert 'tests/tuning.py' in workflow

print('PASS: 8 panel channels x probe group only (frequency/delays/hook throttle); '
      'playback/visibility/perf and the bubble knobs are gone from both the UI and the '
      'playback engine; material rows resolve their catalog name')
