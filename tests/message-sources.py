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
static NSMutableDictionary<NSString *, LMVFrameSnapshot *> *LMVFrameCache;
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
    + function('static void LMVStartSource(LMVSharedSource *source)') + stop + retire + invalidate)
tests = r'''
@interface TrackedPlayer:AVPlayer
@property NSUInteger exactSeeks;
@end
@implementation TrackedPlayer
- (void)seekToTime:(CMTime)time toleranceBefore:(CMTime)before toleranceAfter:(CMTime)after completionHandler:(void (^)(BOOL))complete {
 self.exactSeeks++;[super seekToTime:time toleranceBefore:before toleranceAfter:after completionHandler:complete];
}
@end
static BOOL waitUntil(BOOL (^condition)(void),double seconds) {
 NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];while(!condition() && end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];return condition();
}
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
    LMVDiskPending=[NSMutableSet new];
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    assert([asset tracksWithMediaType:AVMediaTypeVideo].count==1);
    LMVAssets[path]=asset; LMVRevisions[path]=@"rev1";
    LMVFrameSnapshot *shared=[LMVFrameSnapshot new]; shared.image=poster(); shared.time=CMTimeMake(3,4); shared.rendered=YES;
    LMVFrameCache[LMVFrameKey(path,@"rev1")]=shared;
    assert(!LMVSourceForTarget(path,@"Desktop"));
    assert(!LMVSourceForTarget(path,@"LockScreen"));
    assert(!LMVSourceForTarget(path,@"unknown"));
    LMVSharedSource *message=LMVSourceForPath(path);
    assert(message && [message.ownerTarget isEqual:@"MessageFamily"]);
    assert(LMVSourceForTarget(path,@"Message")==message);
    assert(LMVSourceForTarget(path,@"Options")==message && LMVSourceForTarget(path,@"Clear")==message);
    assert(LMVSharedSources.count==1 && message.player && message.player.currentItem && message.output);
    assert(message.lastImage && CMTimeCompare(message.lastTime,shared.time)==0 && message.restoreOnStart);
    // Real AVPlayer with a seek counter executes production warm resume. Cold
    // disk restore remains an explicit one-time seek; ordinary stop/start must
    // keep the retained item's time and avoid a new buffering/seek transition.
    [message.player pause];[message.player replaceCurrentItemWithPlayerItem:nil];
    // AVFoundation detaches items asynchronously. Use a new item with the same
    // immutable asset, not an item that was already owned by the factory player.
    AVPlayerItem *warmItem=[AVPlayerItem playerItemWithAsset:message.asset];
    [message.output setDelegate:nil queue:NULL];
    message.output=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
    [warmItem addOutput:message.output];
    TrackedPlayer *warm=[TrackedPlayer playerWithPlayerItem:warmItem];message.player=warm;
    assert(waitUntil(^BOOL{return warmItem.status==AVPlayerItemStatusReadyToPlay;},10));
    message.restoreOnStart=NO;message.restoringTime=NO;message.lastTime=CMTimeMake(1,4);
    LMVStartSource(message);assert(waitUntil(^BOOL{return warm.rate>0 && CMTimeGetSeconds(warm.currentTime)>.05;},5));
    LMVStopSource(message);NSUInteger seeks=warm.exactSeeks;CMTime paused=warm.currentTime;
    assert(!message.restoreOnStart && warm.rate==0);
    LMVStartSource(message);assert(warm.exactSeeks==seeks && !message.restoringTime && warm.rate>0);
    assert(CMTimeCompare(warm.currentTime,paused)>=0);LMVStopSource(message);
    // Starting a fresh cached position still asks for one safe seek.
    message.restoreOnStart=YES;message.lastTime=CMTimeMake(1,4);LMVStartSource(message);
    assert(waitUntil(^BOOL{return !message.restoringTime && warm.exactSeeks==seeks+1;},5));LMVStopSource(message);
    checkpoints=0;message.playing=NO;
    message.reader=[[AVAssetReader alloc] initWithAsset:asset error:nil];
    AVAssetTrack *track=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    message.readerOutput=[AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:nil];
    [message.reader addOutput:message.readerOutput];assert([message.reader startReading]);
    message.pendingSample=[message.readerOutput copyNextSampleBuffer];assert(message.pendingSample);
    AVAssetReader *keptReader=message.reader;AVAssetReaderTrackOutput *keptOutput=message.readerOutput;CMSampleBufferRef keptSample=message.pendingSample;
    message.readerMode=YES;message.readerClock=CACurrentMediaTime();message.readerOffset=kCMTimeZero;
    message.playing=YES;LMVStopSource(message);CFTimeInterval clock=message.readerClock;
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    LMVStartSource(message);dispatch_sync(LMVFrameQueue,^{});
    assert(message.reader==keptReader && message.readerOutput==keptOutput && message.pendingSample==keptSample && message.readerClock>clock);
    checkpoints=0;message.generation=11;message.playing=YES;
    LMVStopSource(message);assert(!message.playing && message.generation==12 && checkpoints==1);
    LMVStopSource(message);assert(message.generation==12 && checkpoints==1);
    LMVRetireSource(message);dispatch_sync(LMVFrameQueue,^{});
    assert(!message.player && !message.output && !message.reader && !message.pendingSample);
    LMVSharedSource *rebuilt=LMVSourceForPath(path);
    assert(rebuilt!=message && rebuilt.player && rebuilt.lastImage==shared.image);
    assert(CMTimeCompare(rebuilt.lastTime,shared.time)==0 && rebuilt.restoreOnStart);
    // One path invalidation removes all current material source keys; unrelated source survives.
    NSString *other=[path stringByAppendingString:@".other"];
    LMVAssets[other]=asset; LMVRevisions[other]=@"rev-other";
    LMVSharedSource *unrelated=LMVSourceForTarget(other,@"Message"); unrelated.playing=YES;
    LMVInvalidateSourcesForPath(path); dispatch_sync(LMVFrameQueue,^{});
    assert(LMVSharedSources.count==1 && LMVSharedSources[unrelated.registryKey]==unrelated && unrelated.playing);
    for (LMVSharedSource *old in @[message,rebuilt])
        assert(!old.playing && !old.player && !old.output && !old.reader && !old.pendingSample && !old.endObserver);
    LMVInvalidateSourcesForPath(path); assert(LMVSharedSources.count==1);
    LMVInvalidateSourcesForPath(other); dispatch_sync(LMVFrameQueue,^{});
    assert(LMVSharedSources.count==0);
    puts("PASS: actual three-target notification factory/player/item/output/reader/sample, removed Lock/Desktop rejected; poster PTS separation; independent pause; target-owned resume; all-path invalidation; idempotent retirement (macOS AVFoundation, NOT device test)");
} return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'sources.m'; binary=Path(tmp)/'sources'; movie=Path(tmp)/'fixture.mov'
    src.write_text(preamble + production + tests)
    subprocess.run(['clang','-fobjc-arc','-Wno-deprecated-declarations','-framework','Foundation',
        '-framework','AVFoundation','-framework','QuartzCore','-framework','CoreMedia',
        '-framework','CoreVideo','-framework','CoreGraphics',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary),str(movie)],check=True,timeout=60)
