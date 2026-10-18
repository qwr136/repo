#!/usr/bin/env python3
"""Source invariants + reader-clock model; NOT an on-device AVFoundation test."""
from pathlib import Path
import math, plistlib, re
root=Path(__file__).resolve().parents[1]
s=(root/'Tweak.xm').read_text()
# 1.29: the version lives in `control` alone - the assertions FOLLOW it instead
# of repeating the literal. A release bump used to turn these two lines red even
# though nothing was wrong with the build (it cost two CI runs at 1.28).
control=(root/'control').read_text()
lmv_version=re.search(r'^Version:\s*(\S+)\s*$',control,re.M).group(1)
assert control.count('Version: '+lmv_version)==1
info=plistlib.loads((root/'LockMessageVideoPrefs/Info.plist').read_bytes())
assert info['CFBundleVersion']==info['CFBundleShortVersionString']==lmv_version
assert 'LMVCoverHidden' not in s
assert '<AVPlayerItemOutputPullDelegate>' in s
assert 'requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03' in s
assert 'link.targetTimestamp' in s and 'time=current' in s
assert 'static CVPixelBufferRef LMVReadSharedBuffer' in s
assert 'fallback=shared-reader' in s
# 1.76.4: the gate is released through a token, so a conversion that was evicted
# for overrunning cannot clear a newer one - and the gate itself is evicted after
# 2 s so a single stuck conversion can never freeze every channel forever.
assert 'source.frameBusy=NO;' in s
assert 'if (LMVFrameBusyToken==frameToken) { LMVFrameBusy=NO; LMVFrameBusySince=0; }' in s
assert 'NSUInteger frameToken=++LMVFrameBusyToken;' in s
assert 'CFTimeInterval held=CACurrentMediaTime()-LMVFrameBusySince;' in s
assert 'if (held<2.0) return;' in s
assert 'frame-gate-timeout held=%.0fms' in s
# A busy gate is the frame queue, not this source: it must not demote the other
# channels to the reader path.
assert 'if (!LMVFrameBusy && LMVSourceNeedsReaderRecovery(source,now)) {' in s
# A healthy player that was paused underneath us has to be restarted; otherwise
# `playing` stays YES and the source is demoted three seconds later.
assert '[source.player playImmediatelyAtRate:1.0];' in s
assert 'source.player.rate<0.01' in s
assert 'CFTimeInterval limit=source.published?3.0:1.5;' in s
# 1.76.6: a newly created chain must NOT restore the cached position. The still is
# a placeholder only; every material switch starts at zero.
assert 'source.lastTime=snapshot.time' not in s
assert 'source.restoreOnStart=YES' not in s
assert 'source.lastImage=CGImageRetain(snapshot.image);' in s
# 1.76.5: one display-link sweep per runloop instead of one per card, and the
# retired player is torn down a runloop later so the switch path stops waiting for
# it. Both were measured on device, not guessed.
assert 'static void LMVRequestSyncDisplayLink(void) {' in s
assert 'if (LMVSyncCheckScheduled) return;' in s
assert 'AVPlayer *retiredPlayer=source.player;' in s
assert '[retiredPlayer replaceCurrentItemWithPlayerItem:nil];' in s
d=(root/'LMVDesktopVideo.h').read_text()
assert 'static void LMVDesktopStage(const char *name,CFTimeInterval started) {' in d
assert 'LMVDesktopStage("find",coverPerf0);' in d
assert 'LMVDesktopStage("cover",stageCover);' in d
assert 'LMVDesktopStage("rest",stageCover);' in d
assert '@finally { if (workBuffer) CVPixelBufferRelease(workBuffer); }' in s
assert 'state.layer.contents=(__bridge id)image' in s
assert 'CGRect desiredFrame=[anchor convertRect:anchor.bounds toView:host]' in s
assert 'if (!CGRectEqualToRect(state.overlay.frame,desiredFrame))' in s
assert 'CGFloat desiredOpacity=LMVCardOpacity()' in s
assert 'LMVOpacityEnabled && isfinite(LMVOpacity)' in s
assert 'LMVPlaybackAllowed() && LMVOpacityEnabled && LMVOpacity>0' not in s
for forbidden in ['[AVPlayerLayer','AVAudioSession','prerollAtRate','idleTimerDisabled','CFPreferencesSetAppValue']:
    assert forbidden not in s, forbidden
# One chain per (target,path), shared immutable assets; no card-local player/reader.
state=s.split('@interface LMVVideoState : NSObject',1)[1].split('@end',1)[0]
assert 'AVPlayer' not in state and 'AVAssetReader' not in state
assert 'LMVSharedSources[registryKey]=source' in s
assert 'LMVSourceForPath' not in s
assert 'source.ownerTarget=target' in s
assert 'LMVLayoutLockOverlay' not in s
# Independent audio channels do not put LockScreen into the card visual registry.
assert '#import "LMVDesktopVideo.h"' in s
registry=s.split('static NSString *LMVSourceRegistryKey',1)[1].split('@interface LMVSharedSource',1)[0]
assert 'Desktop' not in registry  # Desktop has its own player instance, never the message source cache.
assert 'containsObject:target ?: @""' in registry
assert all('@"'+target+'"' in registry for target in ('Message','Options','Clear'))
# 1.76.1 user policy: one source per CHANNEL, not per file. The key used to be the
# bare path, so Message/Options/Clear selecting the same clip shared one AVPlayer and
# one frame gate - a single stalled source froze all three. Cards inside one channel
# still share that channel's source.
assert 'return [NSString stringWithFormat:@"%@|%@", path, target];' in registry
assert 'return path;' not in registry
assert 'ownerTarget]' not in registry
assert not (root/'LMVLockBackground.h').exists()
assert 'LMVWallpaperFrameCache' not in s
consumer=s.split('static BOOL LMVSourceHasConsumer',1)[1].split('static void LMVReleasePlayer',1)[0]
assert consumer.count('state.active && host.window')==0
assert 'state.overlay.superview' in consumer
assert 'state.layer.superlayer' not in consumer
assert 'LMVSharedSources[source.path]' not in s
invalidate=s.split('static void LMVInvalidateSourcesForPath',1)[1].split('static void LMVPrepareAssets',1)[0]
assert 'LMVSharedSources.allValues' in invalidate and '[source.path isEqualToString:path]' in invalidate
assert 'LMVRetireSource(source)' in invalidate
prepare=s.split('static void LMVPrepareAssets(void) {',1)[1].split('static ',1)[0]
assert prepare.count('LMVInvalidateSourcesForPath(path)')==2
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
# Last frame content survives hide and can bind while source/gate is not ready.
release=s.split('static void LMVReleasePlayer(LMVVideoState *state) {',1)[1].split('static void LMVPrepareAssets',1)[0]
assert 'contents=nil' not in release and 'removeFromSuperlayer' not in release
update=s.split('static void LMVUpdate(UIView *cell) {',1)[1].split('%hook NCNotificationListCell',1)[0]
assert update.index('state.layer.contents=(__bridge id)cached.image') < update.index('state.source=LMVSourceForTarget(path,target)') < update.index('LMVStartSource(state.source)')
assert 'cached.image && (!state.layer.contents || revisionChanged)' in update
assert 'if (!rendered && old.image) return;' in s
assert 'LMVPreparePreview(path,revision,playbackAsset)' in s
assert 'cold-no-frame-0.75s' in s and 'source.restoreOnStart' in s
refresh=s.split('static void LMVRefresh(BOOL reload) {',1)[1].split('// Tracking mode',1)[0]
assert 'LMVSharedSources removeAllObjects' not in refresh and 'LMVFrameCache removeAllObjects' not in refresh
assert 'LMVDirtyCards removeAllObjects' in refresh  # A full pass subsumes only local work lists.
# Both Photos paths request Current and use the same byte-preserving importer.
imp=(root/'LockMessageVideoPrefs/LMVImport.h').read_text()
for name in ['LMVPRootListController.m','LMVPVideoPickerController.m']:
    text=(root/'LockMessageVideoPrefs'/name).read_text()
    assert 'LMVImportMovie(url, &copyError)' in text or 'LMVImportMovie(url, &error)' in text
    assert 'PHPickerConfigurationAssetRepresentationModeCurrent' in text
transaction=imp.split('static NSString *LMVImportMovieOnMaterialQueue(',1)[1]
assert transaction.index('LMVImportCopyBytes(') < transaction.index('LMVValidateMovie(') < transaction.index('LMVImportPublish(') < transaction.index('LMVImportRegisterName(')
for token in ['NSUnderlyingErrorKey','LMVImportUnlinkOwned','O_NOFOLLOW','AT_SYMLINK_NOFOLLOW','512ULL * 1024ULL * 1024ULL','CMSampleBufferGetImageBuffer(sample)']:
    assert token in imp, token
for token in ['AVAssetWriter','LMVCompressMovie','LMVEncodePlan','AVMutableVideoComposition','临时原素材已清理']:
    assert token not in imp, token
# State model: cold preview may fill a miss but not overwrite a rendered frame.
cache={}
def put(key,image,rendered):
    if not rendered and key in cache: return
    cache[key]=(image,rendered)
put('path|rev1','preview',False); put('path|rev1','last',True); put('path|rev1','first',False)
assert cache['path|rev1']==('last',True) and 'path|rev2' not in cache
# 0.0.123: the floating-ball decision lines must survive the high-rate card/lock
# traffic, which used to eat the whole per-epoch record budget (no easter-window
# line ever reached the log).
# 1.76.2: switch-time events are exempt from the 1200-record budget, so a capture
# taken during a freeze still contains loadsource=/asset-ready= and the stopwatch.
assert 'BOOL priority = [event hasPrefix:@"easter-window "] || [event hasPrefix:@"perf-long "] ||' in s
assert '[event hasPrefix:@"loadsource="] || [event hasPrefix:@"asset-ready="]' in s
assert 'if (!priority && ++records > 1200) return;' in s
print('PASS: 1.25 version, retained layer/cache-before-source, cold-preview priority, shared pipeline, reader resume, preserve-first original-byte import/validation invariants (not device runtime tests)')
