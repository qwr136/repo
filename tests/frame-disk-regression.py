#!/usr/bin/env python3
from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text(); h=(r/'LMVFrameDisk.h').read_text()
def function(signature):
    start=s.index(signature+' {'); depth=0
    for i in range(start+len(signature)+1,len(s)):
        if s[i]=='{': depth+=1
        elif s[i]=='}':
            depth-=1
            if depth==0:return s[start:i+1]
    raise AssertionError(signature)
publish=function('static void LMVPublishFrame(LMVSharedSource *source, CMTime time)')
assert 'LMVCacheFrame(source.path,source.revision,image,workTime,YES)' in publish
assert 'LMVDiskWrite' not in publish and 'LMVCheckpointFrame' not in publish
stop=function('static void LMVStopSource(LMVSharedSource *source)')
assert 'LMVCheckpointFrame(source.path,source.revision)' in stop
checkpoint=function('static void LMVCheckpointFrame(NSString *path, NSString *revision)')
assert '!snapshot.rendered' in checkpoint and 'LMVDiskWriting' in checkpoint
assert checkpoint.index('dispatch_async(LMVDiskQueue') < checkpoint.index('LMVDiskWrite')
load=function('static void LMVLoadDiskFrame(NSString *path, NSString *revision)')
assert '!LMVLaunchReady' in load and 'LMVDiskEpochs[path]' in load
assert '[LMVRevisions[path] isEqualToString:revision]' in load
assert '!LMVFrameCache[key].rendered' in load
assert load.index('LMVCacheFrame(path,revision,image,time,YES)') < load.index('LMVUpdate(cell)')
preview=function('static void LMVPreparePreview(NSString *path, NSString *revision, AVAsset *asset)')
assert 'LMVDiskPending containsObject:key' in preview
source=function('static LMVSharedSource *LMVSourceForTarget(NSString *path, NSString *target)')
assert 'LMVDiskPending' in source and 'source.lastTime=snapshot.time' in source
assert '(!wallpaper || owned)' in source  # shared poster must not borrow another target's PTS
assert 'LMVWallpaperFrameCache[LMVFrameKey(source.registryKey,source.revision)]' in publish
assert 'LMVSharedSources[source.registryKey]==source' in function('static void LMVRetireSource(LMVSharedSource *source)')
initial=source.split('LMVSharedSources[registryKey]=source',1)[0]
assert 'seekToTime:' not in initial  # end-of-movie observer retains its existing loop seek
start=function('static void LMVStartSource(LMVSharedSource *source)')
assert start.index('AVPlayerItemStatusReadyToPlay')<start.index('seekToTime:source.lastTime')
assert 'finished && source.generation==epoch' in start
assert 'prerollAtRate' not in s and 'cancelPendingSeeks' not in s
for token in ['stringByResolvingSymlinksInPath','NSDataWritingAtomic','@"rendered":@YES','time.value','time.timescale','time.epoch','32ULL*1024*1024','count<=12','width<=960','0600','0700']:
    assert token in h,token
assert h.count('[LMVDiskRevision(path) isEqualToString:revision]')>=3
print('PASS: checkpoint only displayed frames on pause, serial atomic bounded disk image+PTS, launch/revision/epoch gates, disk before preview/source, ready-only generation-safe resume')
