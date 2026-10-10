#!/usr/bin/env python3
"""Extract production source lifecycle; execute AVFoundation on macOS, no device claim."""
from pathlib import Path
import platform, subprocess, tempfile
r = Path(__file__).resolve().parents[1]
s = (r / 'Tweak.xm').read_text()
def function(signature):
    start = s.index(signature + ' {')
    depth = 0
    for i in range(start + len(signature) + 1, len(s)):
        if s[i] == '{': depth += 1
        elif s[i] == '}':
            depth -= 1
            if depth == 0: return s[start:i + 1]
    raise AssertionError(signature)
factory = function('static LMVSharedSource *LMVSourceForTarget(NSString *path, NSString *target)')
stop = function('static void LMVStopSource(LMVSharedSource *source)')
retire = function('static void LMVRetireSource(LMVSharedSource *source)')
invalidate = function('static void LMVInvalidateSourcesForPath(NSString *path)')
assert 'LMVSharedSources[registryKey]' in factory
for token in ['playerItemWithAsset:', 'initWithPixelBufferAttributes:', 'playerWithPlayerItem:', 'source=[LMVSharedSource new]']:
    assert token in factory
assert 'LMVSharedSources[live.registryKey]==live' in factory
assert 'source.generation++' in stop and 'LMVCheckpointFrame' in stop
assert 'source.registryKey' in retire and 'source.pendingSample=NULL' in retire
assert 'LMVSharedSources.allValues' in invalidate and '[source.path isEqualToString:path]' in invalidate
if platform.system() != 'Darwin':
    print('PASS: production factory/lifecycle constraints; AVFoundation isolation execution deferred to macOS')
    raise SystemExit(0)
preamble = r'''
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreImage/CoreImage.h>
#include <assert.h>
@class LMVSharedSource, LMVFrameSnapshot;
static NSMutableDictionary<NSString *, LMVSharedSource *> *LMVSharedSources;
static NSMutableDictionary<NSString *, AVAsset *> *LMVAssets;
static NSMutableDictionary<NSString *, NSString *> *LMVRevisions;
static NSMutableDictionary<NSString *, LMVFrameSnapshot *> *LMVFrameCache, *LMVWallpaperFrameCache;
static NSMutableSet *LMVDiskPending;
static dispatch_queue_t LMVFrameQueue;
static NSUInteger checkpoints;
static void LMVSyncDisplayLink(void) {}
static void LMVDiagnostic(NSString *event) {}
static void LMVCheckpointFrame(NSString *path, NSString *revision) { checkpoints++; }
'''
snapshot = s.split('@interface LMVFrameSnapshot : NSObject', 1)[1].split('static NSString *LMVFrameKey', 1)[0]
source_class = s.split('@interface LMVSharedSource : NSObject', 1)[1].split('// Main thread coordinates epochs;', 1)[0]
production = ('@interface LMVFrameSnapshot : NSObject' + snapshot
    + function('static NSString *LMVFrameKey(NSString *path, NSString *revision)')
    + function('static LMVFrameSnapshot *LMVCachedFrame(NSString *path, NSString *revision)')
    + function('static NSString *LMVSourceRegistryKey(NSString *path, NSString *target)')
    + '@interface LMVSharedSource : NSObject' + source_class
    + factory + function('static LMVSharedSource *LMVSourceForPath(NSString *path)')
    + stop + retire + invalidate)
tests = r'''
static void makeMovie(NSURL *url) {
    NSError *error=nil;
    AVAssetWriter *writer=[[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error];
    assert(writer && !error);
    AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{
        AVVideoCodecKey:AVVideoCodecTypeH264, AVVideoWidthKey:@32, AVVideoHeightKey:@32}];
    AVAssetWriterInputPixelBufferAdaptor *adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{
        (id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),
        (id)kCVPixelBufferWidthKey:@32, (id)kCVPixelBufferHeightKey:@32,
        (id)kCVPixelBufferIOSurfacePropertiesKey:@{}}];
    [writer addInput:input]; assert([writer startWriting]); [writer startSessionAtSourceTime:kCMTimeZero];
    for (int n=0; n<4; n++) {
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
        while (!input.readyForMoreMediaData && writer.status==AVAssetWriterStatusWriting && deadline.timeIntervalSinceNow>0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        assert(input.readyForMoreMediaData);
        CVPixelBufferRef pixel=NULL;
        assert(CVPixelBufferPoolCreatePixelBuffer(NULL,adaptor.pixelBufferPool,&pixel)==kCVReturnSuccess);
        CVPixelBufferLockBaseAddress(pixel,0);
        memset(CVPixelBufferGetBaseAddress(pixel), n*50, CVPixelBufferGetBytesPerRow(pixel)*32);
        CVPixelBufferUnlockBaseAddress(pixel,0);
        assert([adaptor appendPixelBuffer:pixel withPresentationTime:CMTimeMake(n,4)]);
        CVPixelBufferRelease(pixel);
    }
    [input markAsFinished]; dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC))==0);
    assert(writer.status==AVAssetWriterStatusCompleted);
}
static CGImageRef poster(void) {
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,2,2,8,0,color,kCGImageAlphaPremultipliedLast);
    assert(context); CGImageRef image=CGBitmapContextCreateImage(context);
    CGContextRelease(context); CGColorSpaceRelease(color); return image;
}
int main(int argc, const char **argv) { @autoreleasepool {
    assert(argc==2); NSString *path=[NSString stringWithUTF8String:argv[1]];
    makeMovie([NSURL fileURLWithPath:path]);
    LMVFrameQueue=dispatch_queue_create("test.sources",DISPATCH_QUEUE_SERIAL);
    LMVSharedSources=[NSMutableDictionary new]; LMVAssets=[NSMutableDictionary new];
    LMVRevisions=[NSMutableDictionary new]; LMVFrameCache=[NSMutableDictionary new];
    LMVWallpaperFrameCache=[NSMutableDictionary new]; LMVDiskPending=[NSMutableSet new];
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    assert([asset tracksWithMediaType:AVMediaTypeVideo].count==1);
    LMVAssets[path]=asset; LMVRevisions[path]=@"rev1";
    LMVFrameSnapshot *shared=[LMVFrameSnapshot new]; shared.image=poster(); shared.time=CMTimeMake(3,4); shared.rendered=YES;
    LMVFrameCache[LMVFrameKey(path,@"rev1")]=shared;
    LMVSharedSource *lock=LMVSourceForTarget(path,@"LockScreen");
    LMVSharedSource *home=LMVSourceForTarget(path,@"Desktop");
    LMVSharedSource *message=LMVSourceForPath(path);
    assert(lock && home && message && lock!=home && message!=lock && message!=home);
    assert(lock.player!=home.player && lock.player.currentItem!=home.player.currentItem && lock.output!=home.output);
    assert(lock.asset==home.asset && home.asset==message.asset);
    assert([lock.ownerTarget isEqual:@"LockScreen"] && [home.ownerTarget isEqual:@"Desktop"]);
    assert(LMVSourceForTarget(path,@"LockScreen")==lock && LMVSourceForTarget(path,@"Desktop")==home);
    assert(LMVSourceForTarget(path,@"Message")==message && LMVSourceForTarget(path,@"Options")==message && LMVSourceForTarget(path,@"Clear")==message);
    // Shared poster is immutable; its PTS never starts either wallpaper decoder.
    assert(lock.lastImage && home.lastImage && !CMTIME_IS_NUMERIC(lock.lastTime) && !CMTIME_IS_NUMERIC(home.lastTime));
    assert(CMTimeCompare(message.lastTime,shared.time)==0);
    lock.reader=[[AVAssetReader alloc] initWithAsset:asset error:nil];
    home.reader=[[AVAssetReader alloc] initWithAsset:asset error:nil];
    assert(lock.reader && home.reader && lock.reader!=home.reader);
    AVAssetTrack *track=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    lock.readerOutput=[AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
    home.readerOutput=[AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
    [lock.reader addOutput:lock.readerOutput]; [home.reader addOutput:home.readerOutput];
    assert(lock.readerOutput!=home.readerOutput && [lock.reader startReading] && [home.reader startReading]);
    lock.pendingSample=[lock.readerOutput copyNextSampleBuffer]; home.pendingSample=[home.readerOutput copyNextSampleBuffer];
    assert(lock.pendingSample && home.pendingSample && lock.pendingSample!=home.pendingSample);
    lock.lastTime=CMTimeMake(1,4); home.lastTime=CMTimeMake(2,4);
    lock.generation=11; home.generation=21; lock.playing=home.playing=YES;
    AVPlayer *homePlayer=home.player; AVAssetReader *homeReader=home.reader;
    LMVStopSource(lock);
    assert(!lock.playing && lock.generation==12 && home.playing && home.generation==21);
    assert(CMTimeCompare(home.lastTime,CMTimeMake(2,4))==0 && home.player==homePlayer && home.reader==homeReader && home.pendingSample);
    assert(checkpoints==1);
    LMVStopSource(lock); assert(lock.generation==12 && checkpoints==1); // idempotent pause
    // Model publisher-owned snapshot: a retirement must resume this target only.
    LMVFrameSnapshot *owned=[LMVFrameSnapshot new]; owned.image=poster(); owned.time=CMTimeMake(1,4); owned.rendered=YES;
    LMVWallpaperFrameCache[LMVFrameKey(lock.registryKey,@"rev1")]=owned;
    LMVRetireSource(lock); dispatch_sync(LMVFrameQueue,^{});
    assert(!lock.player && !lock.output && !lock.reader && !lock.pendingSample);
    assert(LMVSharedSources[home.registryKey]==home && home.playing && home.player==homePlayer);
    LMVSharedSource *rebuilt=LMVSourceForTarget(path,@"LockScreen");
    assert(rebuilt!=lock && rebuilt.player!=home.player && rebuilt.lastImage==owned.image);
    assert(CMTimeCompare(rebuilt.lastTime,owned.time)==0 && rebuilt.restoreOnStart);
    assert(CMTimeCompare(home.lastTime,CMTimeMake(2,4))==0);
    // One path invalidation removes message + both wallpaper keys; unrelated survives.
    NSString *other=[path stringByAppendingString:@".other"];
    LMVAssets[other]=asset; LMVRevisions[other]=@"rev-other";
    LMVSharedSource *unrelated=LMVSourceForTarget(other,@"Desktop"); unrelated.playing=YES;
    LMVInvalidateSourcesForPath(path); dispatch_sync(LMVFrameQueue,^{});
    assert(LMVSharedSources.count==1 && LMVSharedSources[unrelated.registryKey]==unrelated && unrelated.playing);
    for (LMVSharedSource *old in @[lock,home,message,rebuilt])
        assert(!old.playing && !old.player && !old.output && !old.reader && !old.pendingSample && !old.endObserver);
    assert(LMVWallpaperFrameCache.count==0);
    LMVInvalidateSourcesForPath(path); assert(LMVSharedSources.count==1);
    LMVInvalidateSourcesForPath(other); dispatch_sync(LMVFrameQueue,^{});
    assert(LMVSharedSources.count==0);
    puts("PASS: actual target factory/player/item/output/reader/sample isolation; poster PTS separation; independent pause; target-owned resume; all-path invalidation; idempotent retirement (macOS AVFoundation, NOT device test)");
} return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'sources.m'; binary=Path(tmp)/'sources'; movie=Path(tmp)/'fixture.mov'
    src.write_text(preamble + production + tests)
    subprocess.run(['clang','-fobjc-arc','-Wno-deprecated-declarations','-framework','Foundation',
        '-framework','AVFoundation','-framework','QuartzCore','-framework','CoreMedia',
        '-framework','CoreVideo','-framework','CoreGraphics',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary),str(movie)],check=True,timeout=60)
