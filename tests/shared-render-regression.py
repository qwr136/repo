#!/usr/bin/env python3
"""Source invariants + reader-clock model; NOT an on-device AVFoundation test."""
from pathlib import Path
import math, plistlib
root=Path(__file__).resolve().parents[1]
s=(root/'Tweak.xm').read_text()
assert (root/'control').read_text().count('Version: 1.25')==1
info=plistlib.loads((root/'LockMessageVideoPrefs/Info.plist').read_bytes())
assert info['CFBundleVersion']==info['CFBundleShortVersionString']=='1.25'
assert 'LMVCoverHidden' not in s
assert '<AVPlayerItemOutputPullDelegate>' in s
assert 'requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03' in s
assert 'link.targetTimestamp' in s and 'time=current' in s
assert 'static CVPixelBufferRef LMVReadSharedBuffer' in s
assert 'fallback=shared-reader' in s
assert 'source.frameBusy=NO; LMVFrameBusy=NO;' in s
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
# 0.0.123 user policy: the registry key is the SELECTED FILE, so the three card
# categories share one chain while they select the same video and stay
# independent when they select different ones.
assert 'return path;' in registry
assert 'stringByAppendingFormat' not in registry
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
assert 'BOOL priority = [event hasPrefix:@"easter-window "];' in s
assert 'if (!priority && ++records > 1200) return;' in s
print('PASS: 1.25 version, retained layer/cache-before-source, cold-preview priority, shared pipeline, reader resume, preserve-first original-byte import/validation invariants (not device runtime tests)')
