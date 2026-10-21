#!/usr/bin/env python3
"""2.59: the eight panel channels must show the video the moment the panel does.

Device report: after switching material, and after a respring, every panel popped
up *without* its video for a beat ("先出来面板后出来视频背景"). Root cause: all
eight panel channels created their playback with `persistentPosterEnabled=NO`, so
`preparePosterForPath:` returned immediately, `posterLayer.contents` stayed nil,
and the mount gate `hasPoster || readyForDisplay` degraded to "wait for the
decoder". The first decoded frame is exactly the delay the user saw.

The fix turns the persistent poster on for these eight channels and makes every
one of them seed the poster before selecting, so the still frame is enough to
mount: the panel appears with pixels already on it and the player covers them
when the decoder is ready.

This test locks in:
  1. every panel channel enables the persistent poster,
  2. every channel seeds it (preparePosterForPath) BEFORE selectPath,
  3. every mount gate accepts the poster as proof of life,
  4. the Home-menu channel is untouched (it intentionally stays posterless),
  5. the 2.59 dead-code removal in LMVPaths.h stays removed.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]

CHANNELS = [
    ('squid', 'LMVSquidPanelVideo.h', 'SLOT', 'SLOT'),
    ('at', 'LMVATPanelVideo.h', 'LMVATPanelPath', 'LMVATPanelRevision'),
    ('copyvault', 'LMVCopyVaultPanelVideo.h', 'LMVCVPanelPath', 'LMVCVPanelRevision'),
    ('myrtle', 'LMVMyrtlePanelVideo.h', 'LMVMyrtlePanelPath', 'LMVMyrtlePanelRevision'),
    ('phoneassist', 'LMVPhoneAssistVideo.h', 'LMVPhoneAssistPath', 'LMVPhoneAssistRevision'),
    ('glasssuite', 'LMVGlassSuiteVideo.h', 'LMVGlassSuitePath', 'LMVGlassSuiteRevision'),
    ('ccborder', 'LMVCCBorderVideo.h', 'LMVCCBorderPath', 'LMVCCBorderRevision'),
    ('copylogx', 'LMVCopyLogXVideo.h', 'LMVCopyLogXPath', 'LMVCopyLogXRevision'),
]

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


for name, filename, path_var, rev_var in CHANNELS:
    source = (root / filename).read_text()
    check(f'_playback.persistentPosterEnabled=YES' in source,
          f'{name}: persistent poster is enabled')
    # The Squid channel resolves its material through the per-slot arrays.
    if path_var == 'SLOT':
        seed = '[self.playback preparePosterForPath:wantPath revision:wantRevision]'
        select = '[self.playback selectPath:wantPath revision:wantRevision]'
    else:
        seed = f'[self.playback preparePosterForPath:{path_var} revision:{rev_var}]'
        select = f'[self.playback selectPath:{path_var} revision:{rev_var}]'
    check(seed in source, f'{name}: poster is seeded')
    check(select in source, f'{name}: material is selected')
    if seed in source and select in source:
        check(source.index(seed) < source.index(select),
              f'{name}: poster is seeded BEFORE selecting (first frame has pixels)')
    check('posterLayer.contents!=nil || self.playback.playerLayer.readyForDisplay' in source
          or 'hasPoster || self.playback.playerLayer.readyForDisplay' in source,
          f'{name}: mount gate accepts the poster as proof of life')

# The AT channel used to force the poster hidden and gate purely on the decoder;
# both were the reported delay. Keep the corrected shape.
at = (root / 'LMVATPanelVideo.h').read_text()
check('self.playback.posterLayer.hidden=YES;' not in at,
      'at: the poster is no longer forced hidden')
check('BOOL live=self.playback.player && self.playback.playerLayer.readyForDisplay' not in at,
      'at: no decoder-only mount gate left')

# Home-menu is not one of the eight panels and stays posterless on purpose.
home = (root / 'LMVHomeMenuVideo.h').read_text()
check('_playback.persistentPosterEnabled=NO' in home,
      'home-menu: intentionally left posterless')

# 2.59 dead-code removal: these helpers had zero callers in the whole tree.
paths = (root / 'LMVPaths.h').read_text()
check('LMVInstalledPath' not in paths, 'dead code: LMVInstalledPath removed')
check('LMVPreferenceBundlePath' not in paths, 'dead code: LMVPreferenceBundlePath removed')
check('/var/mobile/LockMessageVideo' in paths, 'user-data root still declared')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: eight panel channels mount on a seeded poster; dead path helpers stay removed')