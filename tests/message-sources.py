#!/usr/bin/env python3
"""Extract production source lifecycle; execute AVFoundation on macOS, no device claim."""
from pathlib import Path
import platform, re, subprocess, tempfile
r = Path(__file__).resolve().parents[1]
s = (r / 'Tweak.xm').read_text()
def function(signature):
    match = re.search(re.escape(signature) + r'\s*\{', s)
    assert match, 'Missing production function: ' + signature
    depth = 1
    token = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]', re.S)
    for item in token.finditer(s, match.end()):
        if item.group() == '{': depth += 1
        elif item.group() == '}':
            depth -= 1
            if not depth: return s[match.start():item.end()]
    raise AssertionError(signature)
factory = function('static LMVSharedSource *LMVSourceForTarget(NSString *path, NSString *target)')
stop = function('static void LMVStopSource(LMVSharedSource *source)')
retire = function('static void LMVRetireSource(LMVSharedSource *source)')
invalidate = function('static void LMVInvalidateSourcesForPath(NSString *path)')
registry = function('static NSString *LMVSourceRegistryKey(NSString *path, NSString *target)')
warm_sources = function('static void LMVWarmSourcesForPath(NSString *path)')
read_buffer = function('static CVPixelBufferRef LMVReadSharedBuffer(LMVSharedSource *source, CMTime *displayTime, BOOL hasPublishedImage)')
publish = function('static void LMVPublishFrame(LMVSharedSource *source, CMTime time)')
assert 'LMVSourceForPath' not in s
assert 'containsObject:target ?: @""' in registry
assert all('@"'+target+'"' in registry for target in ('Message','Options','Clear'))
assert '[target stringByAppendingFormat:@"\\n%@",path]' in registry
assert 'LMVSharedSources[registryKey]' in factory and 'source.ownerTarget=target' in factory
assert 'LMVEnabled[target].boolValue' in warm_sources and '[LMVPaths[target] isEqualToString:path]' in warm_sources
assert 'LMVSourceForTarget(path,target)' in warm_sources
assert 'source.lastImage=image; source.lastTime=workTime' in publish
assert 'LMVSharedSources[source.registryKey]!=source' in publish
state = s.split('@interface LMVVideoState : NSObject', 1)[1].split('@end', 1)[0]
assert 'AVPlayer' not in state and 'AVAssetReader' not in state
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
#import <objc/runtime.h>
#include <assert.h>
#include <math.h>
@interface UIView : NSObject @end
@implementation UIView @end
@interface LMVVideoState : NSObject
@property(nonatomic,strong) id source;
@property(nonatomic,strong) CALayer *layer;
@end
@implementation LMVVideoState @end
@class LMVSharedSource, LMVFrameSnapshot;
static NSMutableDictionary<NSString *, NSString *> *LMVPaths;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static NSHashTable<UIView *> *LMVCells;
static char LMVStatesKey;
static BOOL LMVFrameBusy;
static CIContext *LMVCIContext;
static BOOL LMVInitialized=YES,LMVLaunchReady=YES;
static NSArray<NSString *> *LMVTargets(void) { return @[@"Message",@"Options",@"Clear"]; }
static BOOL LMVPlaybackAllowed(void) { return YES; }
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
    + function('static void LMVCacheFrame(NSString *path, NSString *revision, CGImageRef image, CMTime time, BOOL rendered)')
    + registry + '@interface LMVSharedSource : NSObject' + source_class
    + factory + warm_sources + read_buffer + publish
    + function('static void LMVStartSource(LMVSharedSource *source)') + stop + retire + invalidate)
tests = r'''
// Instrument the factory-owned AVPlayers without substituting their items,
// outputs, class or clocks. Forward every seek to AVFoundation unchanged.
static char seekCountKey;
@interface AVPlayer (LMVSeekCounter)
- (void)lmv_testSeek:(CMTime)time toleranceBefore:(CMTime)before toleranceAfter:(CMTime)after completionHandler:(void (^)(BOOL))complete;
@end
@implementation AVPlayer (LMVSeekCounter)
- (void)lmv_testSeek:(CMTime)time toleranceBefore:(CMTime)before toleranceAfter:(CMTime)after completionHandler:(void (^)(BOOL))complete {
    NSUInteger n=[objc_getAssociatedObject(self,&seekCountKey) unsignedIntegerValue];
    objc_setAssociatedObject(self,&seekCountKey,@(n+1),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self lmv_testSeek:time toleranceBefore:before toleranceAfter:after completionHandler:complete];
}
@end
static NSUInteger seekCount(AVPlayer *player) {
    return [objc_getAssociatedObject(player,&seekCountKey) unsignedIntegerValue];
}
static void trackSeeks(void) {
    Method original=class_getInstanceMethod(AVPlayer.class,@selector(seekToTime:toleranceBefore:toleranceAfter:completionHandler:));
    Method tracked=class_getInstanceMethod(AVPlayer.class,@selector(lmv_testSeek:toleranceBefore:toleranceAfter:completionHandler:));
    assert(original && tracked);method_exchangeImplementations(original,tracked);
}
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
    for (int n=0; n<240; n++) {
        NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:10];
        while (!input.readyForMoreMediaData && writer.status==AVAssetWriterStatusWriting && deadline.timeIntervalSinceNow>0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        assert(input.readyForMoreMediaData);
        CVPixelBufferRef pixel=NULL;
        assert(CVPixelBufferPoolCreatePixelBuffer(NULL,adaptor.pixelBufferPool,&pixel)==kCVReturnSuccess);
        CVPixelBufferLockBaseAddress(pixel,0);
        memset(CVPixelBufferGetBaseAddress(pixel), n*50, CVPixelBufferGetBytesPerRow(pixel)*32);
        CVPixelBufferUnlockBaseAddress(pixel,0);
        assert([adaptor appendPixelBuffer:pixel withPresentationTime:CMTimeMake(n,12)]);
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
static void publishOne(LMVSharedSource *source) {
    NSUInteger before=source.published;
    assert(waitUntil(^BOOL {
        LMVPublishFrame(source,source.player.currentTime);
        return source.published>before;
    },10));
    assert(source.lastImage && CMTIME_IS_NUMERIC(source.lastTime));
}
static void readOne(LMVSharedSource *source) {
    __block CVPixelBufferRef buffer=NULL; __block CMTime pts=kCMTimeInvalid;
    dispatch_sync(LMVFrameQueue,^{buffer=LMVReadSharedBuffer(source,&pts,NO);});
    assert(buffer && CMTIME_IS_NUMERIC(pts));CVPixelBufferRelease(buffer);
}
int main(int argc, const char **argv) { @autoreleasepool {
    assert(argc==2 && NSThread.isMainThread);trackSeeks();
    NSString *path=[NSString stringWithUTF8String:argv[1]];
    makeMovie([NSURL fileURLWithPath:path]);
    LMVFrameQueue=dispatch_queue_create("test.sources",DISPATCH_QUEUE_SERIAL);
    LMVSharedSources=[NSMutableDictionary new];LMVAssets=[NSMutableDictionary new];
    LMVRevisions=[NSMutableDictionary new];LMVFrameCache=[NSMutableDictionary new];
    LMVDiskPending=[NSMutableSet new];LMVCells=[NSHashTable weakObjectsHashTable];
    LMVPaths=[NSMutableDictionary new];LMVEnabled=[NSMutableDictionary new];
    LMVCIContext=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@YES}];
    for(NSString *target in LMVTargets()){LMVPaths[target]=path;LMVEnabled[target]=@YES;}
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    assert([asset tracksWithMediaType:AVMediaTypeVideo].count==1);
    LMVRevisions[path]=@"rev1";
    LMVFrameSnapshot *shared=[LMVFrameSnapshot new];shared.image=poster();shared.time=CMTimeMake(1,4);shared.rendered=YES;
    LMVFrameCache[LMVFrameKey(path,@"rev1")]=shared;
    for(id value in @[@"Desktop",@"LockScreen",@"unknown",@"",@"message",@"Options ",NSNull.null]) {
        id target=value==NSNull.null?nil:value;
        assert(!LMVSourceRegistryKey(path,target) && !LMVSourceForTarget(path,target));
    }
    assert(!LMVSourceForTarget(nil,@"Message") && !LMVSourceForTarget(@"",@"Message"));
    // Prewarm cannot create a decoder before both asset and disk readiness.
    LMVWarmSourcesForPath(path);assert(!LMVSharedSources.count);
    LMVAssets[path]=asset;[LMVDiskPending addObject:LMVFrameKey(path,@"rev1")];
    LMVWarmSourcesForPath(path);assert(!LMVSharedSources.count);
    [LMVDiskPending removeAllObjects];LMVWarmSourcesForPath(path);assert(LMVSharedSources.count==3);
    LMVSharedSource *message=LMVSourceForTarget(path,@"Message");
    LMVSharedSource *options=LMVSourceForTarget(path,@"Options");
    LMVSharedSource *clear=LMVSourceForTarget(path,@"Clear");
    NSArray<LMVSharedSource *> *sources=@[message,options,clear];
    for(NSUInteger i=0;i<sources.count;i++) {
        LMVSharedSource *source=sources[i];NSString *target=LMVTargets()[i];
        assert([source.ownerTarget isEqual:target]);
        assert(([source.registryKey isEqual:[NSString stringWithFormat:@"%@\n%@",target,path]]));
        assert(LMVSharedSources[source.registryKey]==source && source.asset==asset);
        assert(source.player && source.player.currentItem && source.output && source.endObserver);
        assert(!source.playing && source.player.rate==0 && !source.reader && !source.pendingSample);
        assert(source.lastImage==shared.image && CMTimeCompare(source.lastTime,shared.time)==0 && source.restoreOnStart);
        for(NSUInteger j=0;j<i;j++) {
            LMVSharedSource *other=sources[j];
            assert(source!=other && source.identifier!=other.identifier);
            assert(source.player!=other.player && source.player.currentItem!=other.player.currentItem && source.output!=other.output);
        }
        // Repeated requests represent hundreds of cards, never hundreds of players.
        for(int card=0;card<200;card++)assert(LMVSourceForTarget(path,target)==source);
    }
    LMVWarmSourcesForPath(path);assert(LMVSharedSources.count==3);
    AVPlayer *messagePlayer=message.player;AVPlayerItem *messageItem=message.player.currentItem;
    AVPlayerItemVideoOutput *messageOutput=message.output;
    assert(waitUntil(^BOOL {
        for(LMVSharedSource *source in sources)if(source.player.currentItem.status!=AVPlayerItemStatusReadyToPlay)return NO;
        return YES;
    },15));
    // Three different restored positions on the three factory-owned real clocks.
    message.lastTime=CMTimeMake(1,4);options.lastTime=CMTimeMake(3,4);clear.lastTime=CMTimeMake(5,4);
    for(LMVSharedSource *source in sources)LMVStartSource(source);
    assert(waitUntil(^BOOL {
        return message.player.rate>0 && options.player.rate>0 && clear.player.rate>0 &&
            CMTimeGetSeconds(message.player.currentTime)>.30 && CMTimeGetSeconds(options.player.currentTime)>.80 && CMTimeGetSeconds(clear.player.currentTime)>1.30;
    },10));
    for(LMVSharedSource *source in sources){assert(seekCount(source.player)==1 && !source.restoringTime);publishOne(source);}
    assert(message.lastImage!=options.lastImage && message.lastImage!=clear.lastImage && options.lastImage!=clear.lastImage);
    assert(CMTimeCompare(message.lastTime,options.lastTime)!=0 && CMTimeCompare(message.lastTime,clear.lastTime)!=0);
    NSUInteger optionsEpoch=options.generation,clearEpoch=clear.generation;
    CGImageRef heldImage=message.lastImage;CMTime heldPTS=message.lastTime;
    checkpoints=0;LMVStopSource(message);assert(checkpoints==1 && !message.playing && message.player.rate==0);
    CMTime paused=message.player.currentTime,optionsBefore=options.player.currentTime,clearBefore=clear.player.currentTime;
    NSUInteger seeks=seekCount(message.player),epoch=message.generation;
    assert(waitUntil(^BOOL {
        return CMTimeGetSeconds(CMTimeSubtract(options.player.currentTime,optionsBefore))>.25 &&
            CMTimeGetSeconds(CMTimeSubtract(clear.player.currentTime,clearBefore))>.25;
    },5));
    assert(fabs(CMTimeGetSeconds(CMTimeSubtract(message.player.currentTime,paused)))<.08);
    assert(message.lastImage==heldImage && CMTimeCompare(message.lastTime,heldPTS)==0);
    assert(options.playing && clear.playing && options.generation==optionsEpoch && clear.generation==clearEpoch);
    publishOne(options);publishOne(clear);
    assert(message.lastImage==heldImage && CMTimeCompare(message.lastTime,heldPTS)==0);
    LMVStopSource(message);assert(message.generation==epoch && checkpoints==1);
    LMVStartSource(message);
    assert(message.player==messagePlayer && message.player.currentItem==messageItem && message.output==messageOutput);
    assert(!message.restoreOnStart && !message.restoringTime && seekCount(message.player)==seeks);
    assert(waitUntil(^BOOL{return CMTimeGetSeconds(CMTimeSubtract(message.player.currentTime,paused))>.2;},5));
    assert(seekCount(message.player)==seeks);publishOne(message);
    for(LMVSharedSource *source in sources)LMVStopSource(source);
    // A cold restored position still performs exactly one safe seek, unlike warm resume.
    message.restoreOnStart=YES;message.lastTime=CMTimeMake(1,4);LMVStartSource(message);
    assert(waitUntil(^BOOL{return !message.restoringTime && seekCount(message.player)==seeks+1 && message.player.rate>0;},5));
    LMVStopSource(message);
    // Execute the production AVAssetReader factory for every target as well.
    // Three real readers/outputs/held samples, not card-local decoder fixtures.
    for(NSUInteger i=0;i<sources.count;i++) {
        LMVSharedSource *source=sources[i];source.readerMode=YES;
        source.readerClock=CACurrentMediaTime();source.readerOffset=CMTimeMake((int)i*6,12);
        source.readerLastTarget=kCMTimeInvalid;readOne(source);
        if(!source.pendingSample)source.pendingSample=[source.readerOutput copyNextSampleBuffer];
        assert(source.reader && source.readerOutput && source.pendingSample);
        for(NSUInteger j=0;j<i;j++) {
            assert(source.reader!=sources[j].reader && source.readerOutput!=sources[j].readerOutput);
            assert(source.pendingSample!=sources[j].pendingSample);
        }
        LMVStartSource(source);
    }
    dispatch_sync(LMVFrameQueue,^{});
    AVAssetReader *keptReader=message.reader;AVAssetReaderTrackOutput *keptOutput=message.readerOutput;
    CMSampleBufferRef keptSample=message.pendingSample;
    CFTimeInterval optionsClock=options.readerClock,clearClock=clear.readerClock;
    CMTime optionsOffset=options.readerOffset,clearOffset=clear.readerOffset;
    heldImage=message.lastImage;heldPTS=message.lastTime;
    optionsEpoch=options.generation;clearEpoch=clear.generation;
    LMVStopSource(message);CFTimeInterval stoppedClock=message.readerClock;
    NSDate *resumeAfter=[NSDate dateWithTimeIntervalSinceNow:.15];
    assert(waitUntil(^BOOL{return resumeAfter.timeIntervalSinceNow<0;},1));
    assert(message.reader==keptReader && message.readerOutput==keptOutput && message.pendingSample==keptSample);
    assert(message.lastImage==heldImage && CMTimeCompare(message.lastTime,heldPTS)==0);
    assert(options.playing && clear.playing && options.generation==optionsEpoch && clear.generation==clearEpoch);
    assert(options.readerClock==optionsClock && clear.readerClock==clearClock);
    assert(CMTimeCompare(options.readerOffset,optionsOffset)==0 && CMTimeCompare(clear.readerOffset,clearOffset)==0);
    LMVStartSource(message);dispatch_sync(LMVFrameQueue,^{});
    assert(message.reader==keptReader && message.readerOutput==keptOutput && message.pendingSample==keptSample);
    assert(message.readerClock>stoppedClock+.1 && options.readerClock==optionsClock && clear.readerClock==clearClock);
    checkpoints=0;message.generation=11;message.playing=YES;
    LMVStopSource(message);assert(!message.playing && message.generation==12 && checkpoints==1);
    LMVStopSource(message);assert(message.generation==12 && checkpoints==1);
    LMVRetireSource(message);dispatch_sync(LMVFrameQueue,^{});
    assert(!message.player && !message.output && !message.reader && !message.readerOutput && !message.pendingSample && !message.endObserver);
    assert(LMVSharedSources.count==2 && options.playing && clear.playing);
    LMVFrameSnapshot *latest=LMVCachedFrame(path,@"rev1");assert(latest.image && latest.rendered);
    LMVSharedSource *rebuilt=LMVSourceForTarget(path,@"Message");
    assert(rebuilt!=message && rebuilt.player && rebuilt.lastImage==latest.image);
    assert(CMTimeCompare(rebuilt.lastTime,latest.time)==0 && rebuilt.restoreOnStart);
    assert(LMVSourceForTarget(path,@"Options")==options && LMVSourceForTarget(path,@"Clear")==clear);
    // Path invalidation must remove every target-owned chain, not just Message.
    NSString *other=[path stringByAppendingString:@".other"];
    LMVAssets[other]=asset;LMVRevisions[other]=@"rev-other";
    LMVSharedSource *unrelated=LMVSourceForTarget(other,@"Message");unrelated.playing=YES;
    LMVInvalidateSourcesForPath(path);dispatch_sync(LMVFrameQueue,^{});
    assert(LMVSharedSources.count==1 && LMVSharedSources[unrelated.registryKey]==unrelated && unrelated.playing);
    for(LMVSharedSource *old in @[message,options,clear,rebuilt])
        assert(!old.playing && !old.player && !old.output && !old.reader && !old.readerOutput && !old.pendingSample && !old.endObserver);
    LMVInvalidateSourcesForPath(path);LMVRetireSource(message);dispatch_sync(LMVFrameQueue,^{});
    assert(LMVSharedSources.count==1 && unrelated.playing);
    LMVInvalidateSourcesForPath(other);dispatch_sync(LMVFrameQueue,^{});assert(!LMVSharedSources.count);
    // Prewarm obeys both target enable and exact target selection.
    LMVEnabled[@"Options"]=@NO;LMVPaths[@"Clear"]=other;
    LMVWarmSourcesForPath(path);assert(LMVSharedSources.count==1);
    assert(LMVSharedSources[LMVSourceRegistryKey(path,@"Message")]);
    assert(!LMVSharedSources[LMVSourceRegistryKey(path,@"Options")] && !LMVSharedSources[LMVSourceRegistryKey(path,@"Clear")]);
    LMVEnabled[@"Options"]=@YES;LMVWarmSourcesForPath(path);assert(LMVSharedSources.count==2);
    LMVPaths[@"Clear"]=path;LMVWarmSourcesForPath(path);assert(LMVSharedSources.count==3);
    for(LMVSharedSource *source in LMVSharedSources.allValues)assert(!source.playing && source.player.rate==0);
    LMVInvalidateSourcesForPath(path);dispatch_sync(LMVFrameQueue,^{});assert(!LMVSharedSources.count);
    puts("PASS: exact production three-target factory/prewarm/player/item/output/reader/sample and frame/time isolation; 600 card requests reuse only 3 players; real AVPlayer clocks advance; Message pause preserves frame/time without pausing Options/Clear; retained warm resume has no extra seek; cold restore remains one seek; asset/disk-ready and enabled/selected prewarm; all-path invalidation; idempotent retirement (macOS AVFoundation, NOT device test)");
} return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'sources.m'; binary=Path(tmp)/'sources'; movie=Path(tmp)/'fixture.mov'
    src.write_text(preamble + production + tests)
    subprocess.run(['clang','-fobjc-arc','-Wno-deprecated-declarations','-framework','Foundation',
        '-framework','AVFoundation','-framework','QuartzCore','-framework','CoreMedia',
        '-framework','CoreVideo','-framework','CoreGraphics','-framework','CoreImage',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary),str(movie)],check=True,timeout=180)
