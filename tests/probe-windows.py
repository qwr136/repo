#!/usr/bin/env python3
"""2.55: the eight panel channels share one window snapshot, and idle ones stop polling.

Two separate costs were removed together, so they are guarded together:

A. A DISABLED channel used to keep a 0.5 s (GS/CopyLogX: 2 s) timer, purely to notice
   its switch being turned on - even though every switch write posts
   com.minis.lockmessagevideo/preferencesChanged and that re-creates the timer. Eight
   idle channels were 16 wakeups a second that could never find anything.
   They now use LMVTuneIdleInterval (30 s) as a backstop.

B. Each tick walked every scene and every window, two or three times per tick (env
   check, home-window lookup, the update). The visible-window list only changes when a
   window is added or removed, so an 80 ms shared snapshot cannot hide a state a 200 ms
   probe would have seen.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
probe = (root / 'LMVProbeWindows.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
tuning = (root / 'LMVPanelTuning.h').read_text()

# ---- A) idle gear ------------------------------------------------------------
assert 'static const NSTimeInterval LMVTuneIdleInterval = 30.0;' in tuning
channels = ['LMVATPanelVideo.h', 'LMVSquidPanelVideo.h', 'LMVCopyVaultPanelVideo.h',
            'LMVMyrtlePanelVideo.h', 'LMVPhoneAssistVideo.h', 'LMVGlassSuiteVideo.h',
            'LMVCCBorderVideo.h']
for name in channels:
    src = (root / name).read_text()
    assert 'LMVTuneIdleInterval' in src, name
    # The old idle values must be gone: a channel that still polls at 0.5 s or 2 s
    # while switched off is exactly the cost this version removes.
    assert 'LMVTuneProbeInterval(@"' in src, name
    for stale in (':.5;', 'Enabled)return 2.0;'):
        assert stale not in src, (name, stale)

# ---- B) shared snapshot ------------------------------------------------------
assert 'static NSArray<UIWindow *> *LMVProbeAllWindows(void)' in probe
assert 'static NSArray<UIWindow *> *LMVProbeVisibleWindows(void)' in probe
assert 'CFTimeInterval ttl=LMVProbeSnapshotTTL();' in probe and 'now - cachedAt < ttl' in probe
assert 'now - cachedAt < 0.08' not in probe, '2.98: the TTL is a parameter now'
assert 'LMVTuneValue(@"Global",@"SnapshotMs")' in probe
# An empty list must never be cached: launch and scene reconnection are briefly empty,
# and a cached empty answer would stand every channel down for the whole TTL.
assert 'if (!list.count) return cache ?: @[];' in probe
# The visible list is derived from the all-windows list, not a second scene walk.
assert 'for (UIWindow *window in LMVProbeAllWindows())' in probe
for name in channels:
    src = (root / name).read_text()
    assert 'LMVProbeVisibleWindows()' in src, name
# 3.04: CopyLogX presents in a NEW window, the only channel where the shared TTL is a
# visible delay, so it runs its own list and its own row.
clx_src = (root / 'LMVCopyLogXVideo.h').read_text()
assert 'LMVProbeVisibleWindowsFast()' in clx_src
assert 'LMVProbeAllWindowsFast()' in clx_src
assert 'LMVTuneValue(@"CopyLogX",@"ProbeSnapshotMs")' in probe
# CopyLogX needs hidden windows too: "identity window present but hidden" is what stops
# it from running the expensive structural scan.
clx = (root / 'LMVCopyLogXVideo.h').read_text()
assert 'for(UIWindow *window in LMVProbeAllWindowsFast())' in clx
assert 'identityPresent=YES;' in clx
# The header has to be included before the first channel that uses it.
assert tweak.index('#import "LMVProbeWindows.h"') < tweak.index('#import "LMVDesktopVideo.h"')

# ---- no channel may walk scenes on its probe path ---------------------------
# Remaining `connectedScenes` uses are diagnostics: they are behind
# LMVDiagnosticsEnabled and rate-limited, so they never run per tick.
limits = {'LMVATPanelVideo.h': 0, 'LMVGlassSuiteVideo.h': 0, 'LMVSquidPanelVideo.h': 2,
          'LMVPhoneAssistVideo.h': 2, 'LMVCopyVaultPanelVideo.h': 1,
          'LMVMyrtlePanelVideo.h': 1, 'LMVCCBorderVideo.h': 1, 'LMVCopyLogXVideo.h': 1}
for name, limit in limits.items():
    src = (root / name).read_text()
    assert src.count('connectedScenes') <= limit, (name, src.count('connectedScenes'))

print('PASS: seven panel channels share one snapshot (TTL is a parameter), CopyLogX keeps its own; idle gear is 30 s, '
      'not 0.5 s; no probe path walks scenes per tick')

# 3.07: the six channels with no hook get an EVENT source that costs only
# windows x subview-count: a 30 Hz display link compares a signature and runs the
# existing coalesced pass the moment it changes. Two guards matter:
#   * no runtime method hooks in those channels (the project forbids them), and
#   * the probe must never walk the view tree (that is the CPU cost 2.55 removed).
tweak = (root / 'Tweak.xm').read_text()
assert 'LMVPanelComputeSignature' in tweak and 'LMVPanelPresenceLink' in tweak, 'presence probe'
assert 'preferredFramesPerSecond = LMVPanelPresenceHz()' in tweak, 'probe rate comes from the setting'
assert 'LMVTuneParam(@"PresenceHz", @"变化探针频率 (Hz, 5~60)", 5, 60, 30)' in (root/'LMVPanelTuning.h').read_text(), 'probe rate row'
assert 'LMVPanelPresenceLink.preferredFramesPerSecond = wanted' in tweak, 'rate change applies live'
assert 'LMVTuneReport(@"Global", @"PresenceHz", hz)' in tweak, 'applied rate is reported (row shows 当前生效)'
assert 'LMVPanelSignatureIn' in tweak and 'depth > 3' in tweak, 'signature looks 3 levels deep (CopyVault card)'
assert 'budget = 600' in tweak, 'signature has a hard node budget'
assert 'LMVPanelPresenceStart();' in tweak, 'probe started at launch'
