#!/usr/bin/env python3
"""2.60: the eight panel channels must show the video the moment the panel does.

Device report: after switching material, and after a respring, every panel showed
up *without* its video for a beat ("先出来面板后出来视频背景"). Two causes:

  1. the channels learned "a panel appeared" only from their ProbeHz timer - at the
     default 5 Hz a mount could wait 200 ms before it even looked at the screen;
  2. the mount gate required either a poster or `playerLayer.readyForDisplay`, and
     `readyForDisplay` only turns true once the layer is already on screen - so the
     first appearance also paid for the asset load and the player build.

2.60 fixes both without raising the poll frequency (CPU stays where the user set it)
and without any poster:

  * an appearance kick runs ONE detection pass when a window/scene appears, coalesced
    onto a single main-queue turn - no steady-state cost, the ProbeHz timers stay as
    they are and still do teardown;
  * every channel PREWARMS: while no panel is on screen it loads the material and
    builds the paused player, so the appearance only has to mount and decode;
  * the mount gate is `player && !error` - mounting no longer waits for the decoder
    or a poster; the render layer stays hidden until the first frame arrives
    (updatePresentation), so nothing blank is shown.

This test locks in the shape of all three pieces for all eight channels.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]

CHANNELS = [
    ('squid', 'LMVSquidPanelVideo.h', 'LMVSquidPanelEnabled',
     'LMVSquidPanelSlotPaths[0]', 'LMVSquidPanelSlotRevisions[0]'),
    ('at', 'LMVATPanelVideo.h', 'LMVATPanelEnabled', 'LMVATPanelPath', 'LMVATPanelRevision'),
    ('copyvault', 'LMVCopyVaultPanelVideo.h', 'LMVCVPanelEnabled', 'LMVCVPanelPath', 'LMVCVPanelRevision'),
    ('myrtle', 'LMVMyrtlePanelVideo.h', 'LMVMyrtlePanelEnabled', 'LMVMyrtlePanelPath', 'LMVMyrtlePanelRevision'),
    ('phoneassist', 'LMVPhoneAssistVideo.h', 'LMVPhoneAssistEnabled', 'LMVPhoneAssistPath', 'LMVPhoneAssistRevision'),
    ('glasssuite', 'LMVGlassSuiteVideo.h', 'LMVGlassSuiteEnabled', 'LMVGlassSuitePath', 'LMVGlassSuiteRevision'),
    ('ccborder', 'LMVCCBorderVideo.h', 'LMVCCBorderEnabled', 'LMVCCBorderPath', 'LMVCCBorderRevision'),
    ('copylogx', 'LMVCopyLogXVideo.h', 'LMVCopyLogXEnabled', 'LMVCopyLogXPath', 'LMVCopyLogXRevision'),
]

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


for name, filename, enabled, path_var, rev_var in CHANNELS:
    source = (root / filename).read_text()
    # 1. prewarm: the material is selected while the panel is still closed.
    guard = f'{enabled} && {path_var}.length && {rev_var}.length'
    check(guard in source, f'{name}: prewarm guard')
    prewarm = f'selectPath:{path_var} revision:{rev_var}]'
    check(prewarm in source, f'{name}: prewarm selects the material')
    update_start = source.index('- (void)update {')
    first_select = source.find('selectPath:', update_start)
    update_guard = source.find(guard, update_start)
    check(update_guard != -1 and update_guard < first_select,
          f'{name}: prewarm sits at the top of update, before any card work')
    # 2. no poster anywhere in the channel.
    check('preparePosterForPath' not in source, f'{name}: no poster is used')
    check('persistentPosterEnabled=NO' in source, f'{name}: persistent poster stays off')
    # 3. mount gate needs only the player.
    check('BOOL live=self.playback.player && !self.playback.error;' in source,
          f'{name}: mount gate is player-only')
    # `readyForDisplay` may still appear in the status/diagnostic line; what must
    # not exist is a gate that waits for it.
    check('readyForDisplay &&' not in source and '|| self.playback.playerLayer.readyForDisplay' not in source,
          f'{name}: no readyForDisplay mount gate')

tweak = (root / 'Tweak.xm').read_text()
# 4. event kick, coalesced, and only main-queue work.
check('static void LMVPanelAppearKick(void)' in tweak, 'kick exists')
check('LMVPanelKickQueued' in tweak, 'kick is coalesced')
check(tweak.index('static void LMVPanelAppearKick(void)') < tweak.index('%ctor {'), 'kick defined before ctor')
check('UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeKeyNotification, UISceneDidActivateNotification, UIApplicationDidBecomeActiveNotification' in tweak,
      'kick listens to window/scene appearance events')
for fn in ('LMVSquidPanelVideoRefresh', 'LMVATPanelVideoRefresh', 'LMVPhoneAssistVideoRefresh',
           'LMVGlassSuiteVideoRefresh', 'LMVCCBorderVideoRefresh', 'LMVCopyLogXVideoRefresh',
           'LMVCopyVaultPanelVideoRefresh', 'LMVMyrtlePanelVideoRefresh'):
    check(f'{fn}(NO);' in tweak, f'kick refreshes {fn}')
# 5. the poll frequency is untouched: still the user's ProbeHz, default 5.
tuning = (root / 'LMVPanelTuning.h').read_text()
check('@"ProbeHz", @"检测频率 (Hz, 1~60)", 1, 60, 5' in tuning, 'ProbeHz stays user-tunable, default 5')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: eight panel channels prewarm + event kick + player-only mount; poll rate untouched')