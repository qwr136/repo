#!/usr/bin/env python3
"""Source invariants + reader-clock model; NOT an on-device AVFoundation test."""
from pathlib import Path
import math, plistlib
root=Path(__file__).resolve().parents[1]
s=(root/'Tweak.xm').read_text()
assert (root/'control').read_text().count('Version: 0.0.46')==1
info=plistlib.loads((root/'LockMessageVideoPrefs/Info.plist').read_bytes())
assert info['CFBundleVersion']==info['CFBundleShortVersionString']=='0.0.46'
assert 'LMVCoverHidden' not in s
assert '<AVPlayerItemOutputPullDelegate>' in s
assert 'requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03' in s
assert 'link.targetTimestamp' in s and 'time=current' in s
assert 'static CVPixelBufferRef LMVReadSharedBuffer' in s
assert 'fallback=shared-reader' in s
assert 'source.frameBusy=NO; LMVFrameBusy=NO;' in s
assert '@finally { if (workBuffer) CVPixelBufferRelease(workBuffer); }' in s
assert 'state.layer.contents=(__bridge id)image' in s
assert 'state.overlay.frame = [anchor convertRect:anchor.bounds toView:host]' in s
assert 'state.overlay.alpha = LMVOpacityEnabled ? LMVOpacity : 0.0' in s
for forbidden in ['[AVPlayerLayer','AVAudioSession','prerollAtRate','idleTimerDisabled','CFPreferencesSetAppValue']:
    assert forbidden not in s, forbidden
# Unique-path source creation is unchanged; no player/reader on LMVVideoState.
state=s.split('@interface LMVVideoState : NSObject',1)[1].split('@end',1)[0]
assert 'AVPlayer' not in state and 'AVAssetReader' not in state
assert 'LMVSharedSources[path]=source' in s
# Source readiness/discovery polling cannot require the first frame or an active source.
sync=s.split('static void LMVSyncDisplayLink(void) {',1)[1].split('@implementation LMVDisplayLinkTarget',1)[0]
assert 'LMVPaths[target]' in sync and 'state.active' not in sync
# Completion isn't a loop trigger: AVAssetReader can finish with a future held sample.
condition=s.split('if (source.reader && (',1)[1].split(')) {',1)[0]
assert 'AVAssetReaderStatusCompleted' not in condition
# Resume, wrap and normal clock models.
def target(elapsed,offset,duration): return math.fmod(max(0,elapsed)+offset,duration)
assert target(0,2,5)==2
assert target(.1,2,5)==2.1
assert target(3.2,2,5)<2
assert target(4.9,0,5)>target(5.1,0,5)
assert target(0,0,5)==0
print('PASS: version/source invariants, cold startup, shared fallback, cleanup, geometry, reader-clock boundary models')
