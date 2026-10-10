#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <float.h>
#import <string.h>
#import <math.h>
#import <sys/stat.h>
#import <atomic>
#import "LMVOriginalBackground.h"

static NSString * const LMVDirectory = @"/var/mobile/LockMessageVideo";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSHashTable<UIView *> *LMVCells;
static NSHashTable<UIView *> *LMVActionPresenters;
static NSMutableDictionary<NSString *, NSString *> *LMVPaths;
// Stable semantic names prevent nil hosts when private MaterialView subclasses change.
static NSDictionary<NSString *, NSString *> *LMVMaterialSources;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *, AVURLAsset *> *LMVSources;
static NSMutableDictionary<NSString *, AVAsset *> *LMVAssets;
static NSMutableSet<NSString *> *LMVReadyAssets;
@class LMVSharedSource;
static NSMutableDictionary<NSString *, LMVSharedSource *> *LMVSharedSources;
static NSMutableDictionary<NSString *, NSString *> *LMVRevisions;
static dispatch_queue_t LMVFrameQueue;
static BOOL LMVFrameBusy;
static CIContext *LMVCIContext;
// Main-thread cache ownership; decoding is confined to the serial frame queue.
@class LMVFrameSnapshot;
static NSMutableDictionary<NSString *, LMVFrameSnapshot *> *LMVFrameCache;
static NSMutableSet<NSString *> *LMVPreviewPending;
#import "LMVFrameDisk.h"
static dispatch_queue_t LMVDiskQueue;
static NSMutableSet<NSString *> *LMVDiskPending, *LMVDiskAttempted, *LMVDiskWriting;
static NSMutableDictionary<NSString *, NSNumber *> *LMVDiskEpochs, *LMVDiskSavedTimes;
static void LMVPreparePreview(NSString *path, NSString *revision, AVAsset *asset);
static CGFloat LMVOpacity = 0.55;
static BOOL LMVOpacityEnabled = YES;
static int LMVBlankToken = -1;
static char LMVStatesKey, LMVHostsKey, LMVDiscoveryKey, LMVRetryKey, LMVOwnershipKey;
static NSArray<NSString *> *LMVTargets(void) { return @[@"Message", @"Options", @"Clear"]; }
static void LMVUpdate(UIView *cell);
static void LMVSyncDisplayLink(void);
static void LMVReleaseAllPlayers(void);
static void LMVRefresh(BOOL reload);
static BOOL LMVVisible(UIView *view);
static CADisplayLink *LMVLink;
static int LMVLockToken = -1;
// Collections are initialized before any observer or hook can register a host.
// Launch readiness is independent: a system initializer must never run policy.
static BOOL LMVInitialized, LMVLaunchReady, LMVSafeUpdatePending, LMVSafeUpdateApplying;
static BOOL LMVPreferencesDirty = YES;
static void LMVDiagnostic(NSString *event);
#define LMVEasterWindowDiagnostic(reason) LMVDiagnostic([@"easter-window " stringByAppendingString:(reason)])
#import "LMVEasterOverlay.h"
static LMVEasterManager *LMVEaster;
static void LMVLoadPreferences(void);
static void LMVRetryDiscovery(UIView *cell);
static void LMVRequestSafeUpdate(void) {
    if (!LMVInitialized || !NSThread.isMainThread || !LMVLaunchReady ||
        LMVSafeUpdatePending || LMVSafeUpdateApplying) return;
    LMVSafeUpdatePending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!LMVInitialized || !LMVLaunchReady) { LMVSafeUpdatePending = NO; return; }
        LMVSafeUpdateApplying = YES;
        BOOL reload = LMVPreferencesDirty;
        LMVPreferencesDirty = NO;
        LMVRefresh(reload);
        for (UIView *cell in LMVCells.allObjects) LMVRetryDiscovery(cell);
        LMVSafeUpdateApplying = NO;
        LMVSafeUpdatePending = NO;
        // A preference notification can arrive while the refresh is applying.
        if (LMVPreferencesDirty) LMVRequestSafeUpdate();
    });
}
static void LMVMarkLaunchReady(void) {
    if (!LMVInitialized || !NSThread.isMainThread) return;
    LMVLaunchReady = YES;
    LMVRequestSafeUpdate();
}
static void LMVEasterStartIfReady(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    if (!LMVEaster) LMVEaster = [LMVEasterManager new];
    LMVEaster.ready = YES;
    [LMVEaster refresh];
}
// Public, already-existing scene state is evidence for late injection. Inactive
// scenes alone are NOT evidence: they also exist during wallpaper construction.
static BOOL LMVAlreadyLaunched(UIApplication *app) {
    if (!app || app.applicationState == UIApplicationStateInactive) return NO;
    for (UIScene *scene in app.connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive ||
            scene.activationState == UISceneActivationStateBackground) return YES;
    }
    return NO;
}

// Diagnostics intentionally contain no notification text, labels or filenames.
static dispatch_queue_t LMVDiagnosticQueue;
static std::atomic_bool LMVDiagnosticsEnabled(false);
static std::atomic<unsigned long> LMVDiagnosticEpoch(0);
static void LMVDiagnostic(NSString *event) {
    if (!LMVDiagnosticsEnabled.load() || !event.length || !LMVDiagnosticQueue) return;
    unsigned long epoch = LMVDiagnosticEpoch.load();
    dispatch_async(LMVDiagnosticQueue, ^{
        @autoreleasepool {
            // Drop queued records after the switch is turned off, too.
            if (!LMVDiagnosticsEnabled.load() || epoch != LMVDiagnosticEpoch.load()) return;
            static NSUInteger records=0;
            static unsigned long lastEpoch=0;
            if (lastEpoch != epoch) { records=0; lastEpoch=epoch; }
            if (++records > 1200) return;
            NSFileManager *fm=NSFileManager.defaultManager;
            [fm createDirectoryAtPath:LMVDirectory withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *path=[LMVDirectory stringByAppendingPathComponent:@"shared-render.log"];
            if ([[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue]>65536) {
                NSString *old=[path stringByAppendingString:@".1"];
                [fm removeItemAtPath:old error:nil]; [fm moveItemAtPath:path toPath:old error:nil];
            }
            if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}];
            NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
            @try {
                [handle seekToEndOfFile];
                NSString *line=[NSString stringWithFormat:@"%.3f version=0.0.75 session=%lu pid=%d %@\n",CACurrentMediaTime(),epoch,getpid(),event];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            } @catch (NSException *exception) { /* Diagnostics must never affect playback. */ }
            @finally { [handle closeFile]; }
        }
    });
}

#import "LMVLockVideo.h"

@interface LMVFrameSnapshot : NSObject
@property(nonatomic, assign) CGImageRef image;
@property(nonatomic) CMTime time;
@property(nonatomic) BOOL rendered;
@end
@implementation LMVFrameSnapshot
- (void)dealloc { if (_image) CGImageRelease(_image); }
@end
static NSString *LMVFrameKey(NSString *path, NSString *revision) {
    return path.length && revision.length ? [NSString stringWithFormat:@"%@|%@",path,revision] : nil;
}
static LMVFrameSnapshot *LMVCachedFrame(NSString *path, NSString *revision) {
    NSString *key=LMVFrameKey(path,revision);
    return key ? LMVFrameCache[key] : nil;
}
static void LMVCacheFrame(NSString *path, NSString *revision, CGImageRef image, CMTime time, BOOL rendered) {
    NSString *key=LMVFrameKey(path,revision);
    if (!key || !image) return;
    LMVFrameSnapshot *old=LMVFrameCache[key];
    // A prepared first frame must NEVER replace a real last rendered frame.
    if (!rendered && old.image) return;
    LMVFrameSnapshot *snapshot=[LMVFrameSnapshot new];
    snapshot.image=CGImageRetain(image); snapshot.time=time; snapshot.rendered=rendered;
    LMVFrameCache[key]=snapshot;
    // Bounded by selected materials plus a small history, not notification count.
    if (LMVFrameCache.count>12) {
        for (NSString *candidate in LMVFrameCache.allKeys) {
            BOOL selected=NO;
            for (NSString *p in LMVPaths.allValues) if ([candidate isEqualToString:LMVFrameKey(p,LMVRevisions[p])]) { selected=YES; break; }
            if (!selected) { [LMVFrameCache removeObjectForKey:candidate]; if (LMVFrameCache.count<=12) break; }
        }
    }
}
static void LMVPreparePreview(NSString *path, NSString *revision, AVAsset *asset) {
    NSString *key=LMVFrameKey(path,revision);
    if (!key || LMVFrameCache[key].image || [LMVDiskPending containsObject:key] || [LMVPreviewPending containsObject:key]) return;
    [LMVPreviewPending addObject:key];
    dispatch_async(LMVFrameQueue, ^{
        @autoreleasepool {
            AVAssetImageGenerator *generator=[[AVAssetImageGenerator alloc] initWithAsset:asset];
            generator.appliesPreferredTrackTransform=YES; generator.maximumSize=CGSizeMake(960,960);
            NSError *error=nil; CMTime actual=kCMTimeInvalid;
            // Background-only cold preview, not playback preroll or layout decoding.
            CGImageRef image=[generator copyCGImageAtTime:kCMTimeZero actualTime:&actual error:&error];
            dispatch_async(dispatch_get_main_queue(), ^{
                [LMVPreviewPending removeObject:key];
                if ([LMVRevisions[path] isEqualToString:revision]) {
                    if (image) LMVCacheFrame(path,revision,image,actual,NO);
                    LMVDiagnostic([NSString stringWithFormat:@"cold-preview=%d errorcode=%ld",image!=NULL,(long)error.code]);
                    for (UIView *cell in LMVCells.allObjects) LMVUpdate(cell);
                }
                if (image) CGImageRelease(image);
            });
        }
    });
}

// Remaining notification/action sources share one immutable file asset and
// one playback chain per selected path; removed background targets are rejected.
static NSString *LMVSourceRegistryKey(NSString *path, NSString *target) {
    if (!path.length || (target && ![@[@"Message",@"Options",@"Clear"] containsObject:target])) return nil;
    return path;
}
@interface LMVSharedSource : NSObject <AVPlayerItemOutputPullDelegate>
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItemVideoOutput *output;
@property(nonatomic, assign) CGImageRef lastImage;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *registryKey;
@property(nonatomic, copy) NSString *ownerTarget;
@property(nonatomic, copy) NSString *revision;
// playing means requested by visible consumers, not AVPlayer's actual status.
@property(nonatomic) BOOL playing;
@property(nonatomic) BOOL frameBusy;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) CGAffineTransform imageTransform;
@property(nonatomic) CMTime lastTime;
@property(nonatomic, strong) id endObserver;
@property(nonatomic) NSUInteger identifier;
@property(nonatomic) BOOL outputAwake;
@property(nonatomic) BOOL restoringTime;
@property(nonatomic) BOOL restoreOnStart;
@property(nonatomic) CFTimeInterval startedAt;
@property(nonatomic) CFTimeInterval lastRequestAt;
@property(nonatomic) CFTimeInterval lastProgressAt;
@property(nonatomic) CFTimeInterval lastDiagnosticAt;
@property(nonatomic, copy) NSString *diagnosticState;
@property(nonatomic) NSUInteger newFrames, buffers, conversions, conversionErrors, published, drops;
// One decoder per registry entry; message-family cards still share by file.
@property(nonatomic) BOOL readerMode;
@property(nonatomic, strong) AVAsset *asset;
@property(nonatomic, strong) AVAssetReader *reader;
@property(nonatomic, strong) AVAssetReaderTrackOutput *readerOutput;
@property(nonatomic, assign) CMSampleBufferRef pendingSample;
@property(nonatomic) CFTimeInterval readerClock;
@property(nonatomic) CMTime readerOffset;
@property(nonatomic) CMTime readerLastTarget;
@property(nonatomic) CFTimeInterval readerRetryAt;
@end
@implementation LMVSharedSource
- (void)outputMediaDataWillChange:(AVPlayerItemOutput *)output {
    if (output!=_output) return;
    _outputAwake=YES;
    LMVDiagnostic([NSString stringWithFormat:@"source=%lu output-ready requested=%d",(unsigned long)_identifier,_playing]);
    // Delegate queue is main; no UIKit work is performed by the decoding queue.
    LMVSyncDisplayLink();
}
- (void)outputSequenceWasFlushed:(AVPlayerItemOutput *)output {
    if (output!=_output) return;
    _outputAwake=NO;
    if (_playing && !_readerMode) [_output requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03];
}
- (void)dealloc {
    [_player pause]; [_output setDelegate:nil queue:NULL];
    if (_lastImage) CGImageRelease(_lastImage);
    if (_pendingSample) CFRelease(_pendingSample);
    [_reader cancelReading];
    if (_endObserver) [NSNotificationCenter.defaultCenter removeObserver:_endObserver];
}
@end
// Main thread coordinates epochs; all disk encode/read/write happens serially off-main.
static void LMVCheckpointFrame(NSString *path, NSString *revision) {
    NSString *key=LMVFrameKey(path,revision);
    LMVFrameSnapshot *snapshot=LMVCachedFrame(path,revision);
    if (!LMVLaunchReady || !key || !snapshot.rendered || !snapshot.image ||
        !CMTIME_IS_NUMERIC(snapshot.time) || [LMVDiskWriting containsObject:key]) return;
    NSNumber *seconds=@(CMTimeGetSeconds(snapshot.time));
    if ([LMVDiskSavedTimes[key] isEqual:seconds]) return;
    [LMVDiskWriting addObject:key];
    dispatch_async(LMVDiskQueue, ^{
        @autoreleasepool {
            BOOL saved=LMVDiskWrite(path,revision,snapshot.image,snapshot.time);
            dispatch_async(dispatch_get_main_queue(), ^{
                [LMVDiskWriting removeObject:key];
                if (saved && [LMVRevisions[path] isEqualToString:revision]) LMVDiskSavedTimes[key]=seconds;
                // A new pause during the write is coalesced to the newest displayed frame.
                LMVFrameSnapshot *latest=LMVCachedFrame(path,revision);
                if (latest != snapshot) {
                    for (LMVSharedSource *source in LMVSharedSources.allValues)
                        if ([source.path isEqualToString:path] && !source.playing) {
                            LMVCheckpointFrame(path,revision); break;
                        }
                }
            });
        }
    });
}
static void LMVLoadDiskFrame(NSString *path, NSString *revision) {
    NSString *key=LMVFrameKey(path,revision);
    if (!LMVLaunchReady || !key || LMVFrameCache[key].image || [LMVDiskAttempted containsObject:key]) return;
    [LMVDiskAttempted addObject:key]; [LMVDiskPending addObject:key];
    NSUInteger epoch=[LMVDiskEpochs[path] unsignedIntegerValue]+1; LMVDiskEpochs[path]=@(epoch);
    dispatch_async(LMVDiskQueue, ^{
        @autoreleasepool {
            CMTime time=kCMTimeInvalid; CGImageRef image=LMVDiskRead(path,revision,&time);
            dispatch_async(dispatch_get_main_queue(), ^{
                [LMVDiskPending removeObject:key];
                if ([LMVDiskEpochs[path] unsignedIntegerValue]==epoch && [LMVRevisions[path] isEqualToString:revision]) {
                    // A late disk response cannot replace a newer live published frame.
                    if (image && !LMVFrameCache[key].rendered) LMVCacheFrame(path,revision,image,time,YES);
                    if (!LMVFrameCache[key].image && LMVAssets[path]) LMVPreparePreview(path,revision,LMVAssets[path]);
                    for (UIView *cell in LMVCells.allObjects) LMVUpdate(cell);
                }
                if (image) CGImageRelease(image);
            });
        }
    });
}

@interface LMVVideoState : NSObject
@property(nonatomic, strong) UIView *overlay;
@property(nonatomic, strong) CALayer *layer;
@property(nonatomic, strong) LMVSharedSource *source;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *revision;
@property(nonatomic, weak) UIView *anchor;
@property(nonatomic, weak) UIView *host;
@property(nonatomic) BOOL active;
@property(nonatomic) CFTimeInterval lastVisible;
@property(nonatomic) CFTimeInterval visibilityLossSince;
@property(nonatomic) CFTimeInterval detachedSince;
@property(nonatomic, strong) NSArray<LMVOriginalLease *> *originals;
@property(nonatomic, weak) UIView *originalAnchor, *originalScope;
@property(nonatomic, copy) NSString *originalDiagnostic;
@end
@implementation LMVVideoState
- (void)dealloc {
    LMVReleaseOriginals(_originals, self);
    [_overlay removeFromSuperview];
    [_layer removeFromSuperlayer];
}
@end
#import "LMVBackgroundDiscovery.h"

static BOOL LMVPlaybackAllowed(void) {
    if (!LMVInitialized || !LMVLaunchReady) return NO;
    uint64_t blank=1;
    int status=LMVBlankToken<0 ? -1 : notify_get_state(LMVBlankToken,&blank);
    // CoverSheet callbacks are not a global visibility oracle. A hidden sibling
    // must not suppress a still-visible notification surface in another window.
    NSString *reason=status!=NOTIFY_STATUS_OK ? @"blank-state-unavailable" : (blank ? @"screen-blank" : @"allowed");
    static NSString *lastReason;
    if (![lastReason isEqualToString:reason]) { lastReason=reason; LMVDiagnostic([@"gate=" stringByAppendingString:reason]); }
    return status==NOTIFY_STATUS_OK && !blank;
}

static NSString *LMVFileRevision(NSString *path) {
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) != 0 || !S_ISREG(info.st_mode)) return nil;
    return [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%ld:%lld:%ld",
        (unsigned long long)info.st_dev, (unsigned long long)info.st_ino,
        (long long)info.st_size, (long long)info.st_mtimespec.tv_sec,
        info.st_mtimespec.tv_nsec, (long long)info.st_ctimespec.tv_sec,
        info.st_ctimespec.tv_nsec];
}

static LMVSharedSource *LMVSourceForTarget(NSString *path, NSString *target) {
    NSString *registryKey=LMVSourceRegistryKey(path,target);
    if (!registryKey) return nil;
    LMVSharedSource *source=LMVSharedSources[registryKey];
    if (source || !LMVAssets[path] || [LMVDiskPending containsObject:LMVFrameKey(path,LMVRevisions[path])]) return source;
    AVPlayerItem *item=[AVPlayerItem playerItemWithAsset:LMVAssets[path]];
    item.preferredForwardBufferDuration=1;
    AVPlayerItemVideoOutput *output=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA), (id)kCVPixelBufferIOSurfacePropertiesKey:@{}}];
    output.suppressesPlayerRendering=YES;
    [item addOutput:output];
    AVPlayer *player=[AVPlayer playerWithPlayerItem:item];
    player.preventsDisplaySleepDuringVideoPlayback=NO; player.muted=YES; player.volume=0; player.automaticallyWaitsToMinimizeStalling=NO;
    source=[LMVSharedSource new]; source.player=player; source.output=output; source.path=path; source.asset=LMVAssets[path];
    source.imageTransform=[[source.asset tracksWithMediaType:AVMediaTypeVideo] firstObject].preferredTransform;
    source.lastTime=kCMTimeInvalid; source.readerOffset=kCMTimeZero; source.readerLastTarget=kCMTimeInvalid;
    static NSUInteger nextIdentifier=0; source.identifier=++nextIdentifier;
    source.registryKey=registryKey;
    source.ownerTarget=[registryKey isEqualToString:path] ? @"MessageFamily" : target;
    source.revision=LMVRevisions[path];
    LMVFrameSnapshot *snapshot=LMVCachedFrame(path,source.revision);
    if (snapshot.image) {
        source.lastImage=CGImageRetain(snapshot.image);
        if (snapshot.rendered && CMTIME_IS_NUMERIC(snapshot.time)) {
            source.lastTime=snapshot.time; source.restoreOnStart=YES;
            // Wait for ready-to-play before restoring. Cached image is already local.
        }
    }
    LMVSharedSources[registryKey]=source;
    [output setDelegate:source queue:dispatch_get_main_queue()];
    [output requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03];
    LMVDiagnostic([NSString stringWithFormat:@"loadsource=%lu owner=%@ currentItem=%d tracks=%lu",(unsigned long)source.identifier,source.ownerTarget,player.currentItem!=nil,(unsigned long)[source.asset tracksWithMediaType:AVMediaTypeVideo].count]);
    __weak LMVSharedSource *weakSource=source;
    source.endObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        LMVSharedSource *live=weakSource;
        if (!live || !live.playing || live.readerMode) return;
        NSUInteger epoch=live.generation;
        [live.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (finished && live.playing && !live.readerMode && live.generation==epoch && LMVSharedSources[live.registryKey]==live) {
                    [live.output requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03]; [live.player play];
                }
            });
        }];
    }];
    return source;
}
static LMVSharedSource *LMVSourceForPath(NSString *path) {
    return LMVSourceForTarget(path,nil);
}
// This helper runs only on the one serial frame queue. Owns exactly one held sample.
static CVPixelBufferRef LMVReadSharedBuffer(LMVSharedSource *source, CMTime *displayTime, BOOL hasPublishedImage) {
    CFTimeInterval now=CACurrentMediaTime();
    CMTime duration=source.asset.duration;
    if (!CMTIME_IS_NUMERIC(duration) || CMTimeGetSeconds(duration)<=0) return NULL;
    double seconds=fmod(MAX(0.0,now-source.readerClock)+CMTimeGetSeconds(source.readerOffset),CMTimeGetSeconds(duration));
    CMTime target=CMTimeMakeWithSeconds(seconds,600);
    if (source.reader && (source.reader.status==AVAssetReaderStatusFailed || source.reader.status==AVAssetReaderStatusCancelled || (CMTIME_IS_NUMERIC(source.readerLastTarget) && CMTimeCompare(target,source.readerLastTarget)<0))) {
        [source.reader cancelReading]; source.reader=nil; source.readerOutput=nil;
        if (source.pendingSample) { CFRelease(source.pendingSample); source.pendingSample=NULL; }
        source.readerClock=now; source.readerOffset=kCMTimeZero; target=kCMTimeZero;
    }
    source.readerLastTarget=target;
    if (!source.reader) {
        if (now<source.readerRetryAt) return NULL;
        NSError *error=nil;
        AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:source.asset error:&error];
        AVAssetTrack *track=[[source.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
        AVAssetReaderTrackOutput *output=track ? [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}] : nil;
        output.alwaysCopiesSampleData=NO;
        if (!reader || !output || ![reader canAddOutput:output]) { source.readerRetryAt=now+2; LMVDiagnostic([NSString stringWithFormat:@"source=%lu reader-create-failed code=%ld",(unsigned long)source.identifier,(long)error.code]); return NULL; }
        [reader addOutput:output];
        reader.timeRange=CMTimeRangeMake(target,CMTimeSubtract(duration,target));
        if (![reader startReading]) { source.readerRetryAt=now+2; LMVDiagnostic([NSString stringWithFormat:@"source=%lu reader-start-failed code=%ld",(unsigned long)source.identifier,(long)reader.error.code]); return NULL; }
        source.reader=reader; source.readerOutput=output;
    }
    CMSampleBufferRef selected=NULL;
    // Bounded catch-up: never enqueue work for every card or scan a whole video.
    for (NSUInteger n=0;n<8;n++) {
        CMSampleBufferRef sample=source.pendingSample;
        source.pendingSample=NULL;
        if (!sample) sample=[source.readerOutput copyNextSampleBuffer];
        if (!sample) break;
        CMTime pts=CMSampleBufferGetPresentationTimeStamp(sample);
        if (selected && CMTIME_IS_NUMERIC(pts) && CMTimeCompare(pts,target)>0) { source.pendingSample=sample; break; }
        if (!selected && CMTIME_IS_NUMERIC(pts) && CMTimeCompare(pts,target)>0 && hasPublishedImage) { source.pendingSample=sample; break; }
        if (selected) CFRelease(selected);
        selected=sample; *displayTime=pts;
        if (CMTIME_IS_NUMERIC(pts) && CMTimeCompare(pts,target)>=0) break;
    }
    CVPixelBufferRef buffer=selected ? CMSampleBufferGetImageBuffer(selected) : NULL;
    if (buffer) CVPixelBufferRetain(buffer);
    if (selected) CFRelease(selected);
    return buffer;
}
static void LMVPublishFrame(LMVSharedSource *source, CMTime time) {
    if (!source || source.restoringTime || LMVFrameBusy || source.frameBusy || !source.playing) return;
    CVPixelBufferRef buffer=NULL;
    CMTime itemTime=kCMTimeInvalid;
    BOOL readerMode=source.readerMode;
    if (!readerMode) {
        if (source.player.currentItem.status!=AVPlayerItemStatusReadyToPlay || !CMTIME_IS_NUMERIC(time)) return;
        if (![source.output hasNewPixelBufferForItemTime:time]) return;
        source.newFrames++;
        buffer=[source.output copyPixelBufferForItemTime:time itemTimeForDisplay:&itemTime];
        if (!buffer) return;
    }
    source.frameBusy=YES; LMVFrameBusy=YES;
    NSUInteger generation=source.generation;
    CGAffineTransform transform=source.imageTransform;
    BOOL hasPublishedImage=source.lastImage!=NULL;
    dispatch_async(LMVFrameQueue, ^{
        @autoreleasepool {
            CVPixelBufferRef workBuffer=buffer;
            CMTime workTime=itemTime;
            CGImageRef image=NULL;
            BOOL conversionFailed=NO;
            @try {
                if (readerMode) workBuffer=LMVReadSharedBuffer(source,&workTime,hasPublishedImage);
                if (workBuffer) {
                    CIImage *ci=[[CIImage imageWithCVPixelBuffer:workBuffer] imageByApplyingTransform:transform];
                    CGRect extent=ci.extent;
                    CGFloat largest=MAX(extent.size.width,extent.size.height);
                    if (!CGRectIsEmpty(extent) && !CGRectIsInfinite(extent) && isfinite(largest) && largest>0) {
                        // Normalize transformed extents (portrait videos can have negative origins).
                        ci=[ci imageByApplyingTransform:CGAffineTransformMakeTranslation(-extent.origin.x,-extent.origin.y)];
                        if (largest>960.0) ci=[ci imageByApplyingTransform:CGAffineTransformMakeScale(960.0/largest,960.0/largest)];
                        image=[LMVCIContext createCGImage:ci fromRect:ci.extent];
                        if (!image) {
                            // Hardware CI may be unavailable in a SpringBoard render context.
                            static CIContext *software;
                            if (!software) software=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@YES}];
                            image=[software createCGImage:ci fromRect:ci.extent];
                        }
                    }
                    conversionFailed=image==NULL;
                }
            } @catch (NSException *exception) { conversionFailed=YES; }
            @finally { if (workBuffer) CVPixelBufferRelease(workBuffer); }
            BOOL hadBuffer=workBuffer!=NULL;
            dispatch_async(dispatch_get_main_queue(), ^{
                // Clear both busy flags on every exit, including conversion failure/discard.
                source.frameBusy=NO; LMVFrameBusy=NO;
                if (hadBuffer) source.buffers++;
                if (conversionFailed) source.conversionErrors++;
                if (image) source.conversions++;
                NSString *drop=nil;
                if (source.generation!=generation) drop=@"generation";
                else if (![source.revision isEqualToString:LMVRevisions[source.path]]) drop=@"revision";
                else if (LMVSharedSources[source.registryKey]!=source) drop=@"replaced";
                else if (!source.playing) drop=@"not-requested";
                else if (!LMVPlaybackAllowed()) drop=@"gate";
                if (image && !drop) {
                    if (source.lastImage) CGImageRelease(source.lastImage);
                    source.lastImage=image; source.lastTime=workTime; source.published++; source.lastProgressAt=CACurrentMediaTime();
                    LMVCacheFrame(source.path,source.revision,image,workTime,YES);
                    [CATransaction begin]; [CATransaction setDisableActions:YES];
                    for (UIView *cell in LMVCells.allObjects) {
                        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
                        for (LMVVideoState *state in states.allValues) if (state.source==source) state.layer.contents=(__bridge id)image;
                    }
                    [CATransaction commit];
                    if (source.published==1) LMVDiagnostic([NSString stringWithFormat:@"source=%lu first-published mode=%@ size=%zux%zu",(unsigned long)source.identifier,readerMode?@"shared-reader":@"shared-output",CGImageGetWidth(image),CGImageGetHeight(image)]);
                } else if (image) {
                    CGImageRelease(image); source.drops++;
                    if (source.drops<=8) LMVDiagnostic([NSString stringWithFormat:@"source=%lu discard=%@",(unsigned long)source.identifier,drop]);
                }
            });
        }
    });
}
static void LMVStartSource(LMVSharedSource *source) {
    if (!source || LMVSharedSources[source.registryKey]!=source) return;
    if (source.playing) {
        if (!source.readerMode && source.restoreOnStart && !source.restoringTime &&
            source.player.currentItem.status==AVPlayerItemStatusReadyToPlay) source.playing=NO;
        else return;
    }
    if (!source.player.currentItem && !source.readerMode) { LMVDiagnostic([NSString stringWithFormat:@"source=%lu start=no-currentItem",(unsigned long)source.identifier]); return; }
    source.playing=YES; source.startedAt=CACurrentMediaTime(); source.lastProgressAt=source.startedAt; source.lastRequestAt=0;
    if (source.readerMode) {
        // Reader state is queue-confined; this reset is ordered before subsequent pulls.
        CMTime resume=CMTIME_IS_NUMERIC(source.lastTime) ? source.lastTime : kCMTimeZero;
        dispatch_async(LMVFrameQueue, ^{
            [source.reader cancelReading]; source.reader=nil; source.readerOutput=nil;
            if (source.pendingSample) { CFRelease(source.pendingSample); source.pendingSample=NULL; }
            source.readerClock=CACurrentMediaTime(); source.readerOffset=resume; source.readerLastTarget=kCMTimeInvalid;
        });
    } else {
        [source.output requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03];
        if (source.restoreOnStart && source.player.currentItem.status!=AVPlayerItemStatusReadyToPlay) return;
        if (!source.restoringTime && source.restoreOnStart && CMTIME_IS_NUMERIC(source.lastTime)) {
            source.restoreOnStart=NO; source.restoringTime=YES;
            NSUInteger epoch=source.generation;
            [source.player seekToTime:source.lastTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    source.restoringTime=NO;
                    if (finished && source.generation==epoch && source.playing && !source.readerMode && LMVSharedSources[source.registryKey]==source) {
                        source.restoreOnStart=NO; [source.player play];
                    } else source.restoreOnStart=CMTIME_IS_NUMERIC(source.lastTime);
                });
            }];
        } else if (!source.restoringTime) [source.player play];
    }
}
static void LMVStopSource(LMVSharedSource *source) {
    if (source && source.playing) {
        [source.player pause]; source.playing=NO; source.generation++;
        source.restoreOnStart=CMTIME_IS_NUMERIC(source.lastTime);
        LMVCheckpointFrame(source.path,source.revision);
        // Do not launch asynchronous pause-seeks that can flush the next startup.
    }
}
static BOOL LMVSourceHasConsumer(LMVSharedSource *source) {
    if (!source) return NO;
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
        for (LMVVideoState *state in states.allValues) if (state.source==source && state.active && state.overlay.superview) return YES;
    }
    return NO;
}
static void LMVReleasePlayer(LMVVideoState *state) {
    if (!state) return;
    LMVSharedSource *source=state.source;
    // Hiding/offscreen pauses consumption, NEVER clears the exact displayed frame.
    // This retained layer also survives source/property refresh without a blank gap.
    state.source=nil; state.active=NO;
    if (!LMVSourceHasConsumer(source)) LMVStopSource(source);
}
static void LMVRetireSource(LMVSharedSource *source) {
    if (!source) return;
    LMVStopSource(source); source.generation++;
    [source.output setDelegate:nil queue:NULL];
    [source.player replaceCurrentItemWithPlayerItem:nil]; source.player=nil; source.output=nil;
    if (source.endObserver) { [NSNotificationCenter.defaultCenter removeObserver:source.endObserver]; source.endObserver=nil; }
    // Ordered after any pending conversion; its publication is rejected by epoch/key.
    dispatch_async(LMVFrameQueue, ^{
        [source.reader cancelReading]; source.reader=nil; source.readerOutput=nil;
        if (source.pendingSample) { CFRelease(source.pendingSample); source.pendingSample=NULL; }
    });
    if (LMVSharedSources[source.registryKey]==source) [LMVSharedSources removeObjectForKey:source.registryKey];
}
static void LMVInvalidateSourcesForPath(NSString *path) {
    for (LMVSharedSource *source in LMVSharedSources.allValues)
        if ([source.path isEqualToString:path]) LMVRetireSource(source);

}
static void LMVPrepareAssets(void) {
    if (!LMVInitialized || !LMVLaunchReady) return;
    NSSet *wanted = [NSSet setWithArray:LMVPaths.allValues];
    for (NSString *path in LMVSources.allKeys) {
        if (![wanted containsObject:path]) { [LMVSources removeObjectForKey:path]; [LMVAssets removeObjectForKey:path];  [LMVReadyAssets removeObject:path]; LMVInvalidateSourcesForPath(path); [LMVRevisions removeObjectForKey:path]; }
    }
    for (NSString *path in wanted) {
        NSString *revision = LMVFileRevision(path);
        if (LMVSources[path] && [LMVRevisions[path] isEqualToString:revision]) continue;
        // Same URL does not imply the same file. Invalidate composition,
        // prewarm decoder and time epoch together.
                [LMVSources removeObjectForKey:path]; [LMVAssets removeObjectForKey:path];
        [LMVReadyAssets removeObject:path];
        LMVInvalidateSourcesForPath(path);
        if (!revision) { [LMVRevisions removeObjectForKey:path]; continue; }
        LMVRevisions[path] = revision;
        // Drop old memory revisions and supersede pending loads before rebuilding.
        NSString *keep=LMVFrameKey(path,revision);
        for (NSString *key in LMVFrameCache.allKeys)
            if ([key hasPrefix:[path stringByAppendingString:@"|"]] && ![key isEqual:keep]) [LMVFrameCache removeObjectForKey:key];
        LMVLoadDiskFrame(path,revision);
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
        LMVSources[path] = asset;
        [asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"playable", @"duration"] completionHandler:^{
            // Composition work stays off the scrolling/main thread and is cached per file.
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            BOOL ready = [asset statusOfValueForKey:@"tracks" error:&error] == AVKeyValueStatusLoaded && [asset statusOfValueForKey:@"playable" error:&error] == AVKeyValueStatusLoaded && [asset statusOfValueForKey:@"duration" error:&error] == AVKeyValueStatusLoaded && asset.playable;
            CMTime duration = ready ? asset.duration : kCMTimeInvalid;
            ready = ready && CMTIME_IS_NUMERIC(duration) && CMTimeCompare(duration, kCMTimeZero) > 0;
            AVMutableComposition *video = ready ? [AVMutableComposition composition] : nil;
            CMTimeRange fullRange = CMTimeRangeMake(kCMTimeZero, duration);
            NSUInteger videoTrackCount = 0;
            if (ready) {
                for (AVAssetTrack *source in [asset tracksWithMediaType:AVMediaTypeVideo]) {
                    CMTimeRange range = CMTimeRangeGetIntersection(source.timeRange, fullRange);
                    if (!CMTIMERANGE_IS_VALID(range) || CMTimeCompare(range.duration, kCMTimeZero) <= 0) continue;
                    AVMutableCompositionTrack *track = [video addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
                    if (!track || ![track insertTimeRange:range ofTrack:source atTime:range.start error:&error]) {
                        ready = NO;
                        break;
                    }
                    track.preferredTransform = source.preferredTransform;
                    videoTrackCount++;
                }
                ready = ready && videoTrackCount > 0;
                if (ready && CMTimeCompare(video.duration, duration) < 0) {
                    [video insertEmptyTimeRange:CMTimeRangeMake(video.duration, CMTimeSubtract(duration, video.duration))];
                }
            }
            // No fallback to an audio-bearing asset, even if preparation fails.
            LMVDiagnostic([NSString stringWithFormat:@"asset-ready=%d videoTracks=%lu errorcode=%ld",ready,(unsigned long)videoTrackCount,(long)error.code]);
            AVAsset *playbackAsset = ready ? [video copy] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (LMVSources[path] != asset || !ready) return;
                LMVAssets[path] = playbackAsset;
                [LMVReadyAssets addObject:path];
                LMVPreparePreview(path,revision,playbackAsset);
                for (UIView *cell in LMVCells.allObjects) LMVUpdate(cell);
            });
            });
        }];
    }
}
static void LMVLoadPreferences(void) {
    CFPreferencesAppSynchronize(kLMVPrefsID);
    NSNumber *diagnostics = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("DiagnosticsEnabled"), kLMVPrefsID);
    BOOL diagnosticsEnabled = [diagnostics respondsToSelector:@selector(boolValue)] && diagnostics.boolValue;
    BOOL wasEnabled = LMVDiagnosticsEnabled.exchange(diagnosticsEnabled);
    if (diagnosticsEnabled && !wasEnabled) {
        LMVDiagnosticEpoch.fetch_add(1);
        LMVDiagnostic(@"version=0.0.75 diagnostics-enabled");
    }
    LMVPaths = [NSMutableDictionary new];
    // These are semantic source names, kept independent from UIKit private class names.
    LMVMaterialSources = @{
        @"Message": @"message.mov",
        @"Options": @"options.mov",
        @"Clear": @"clear.mov"
    };
    LMVEnabled = [NSMutableDictionary new];
    for (NSString *target in LMVTargets()) {
        NSString *enabledKey = [target stringByAppendingString:@"BackgroundEnabled"];
        NSNumber *enabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue((__bridge CFStringRef)enabledKey, kLMVPrefsID);
        LMVEnabled[target] = @([enabled respondsToSelector:@selector(boolValue)] && enabled.boolValue);
        NSString *videoKey = [target stringByAppendingString:@"Video"];
        NSString *relative = (__bridge_transfer NSString *)CFPreferencesCopyAppValue((__bridge CFStringRef)videoKey, kLMVPrefsID);
        // Always resolve through the semantic source table; never pass a nil source name.
        BOOL explicitSelection = [relative isKindOfClass:NSString.class];
        if (!explicitSelection) relative = LMVMaterialSources[target];
        if (![relative isKindOfClass:NSString.class] || !relative.length) continue;
        NSString *path = [[LMVDirectory stringByAppendingPathComponent:relative] stringByStandardizingPath];
        if (!explicitSelection && ![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
        // A persisted selection survives unreadable/missing files. Empty selection
        // (including successful material deletion) alone restores the original.
        if ([path hasPrefix:[LMVDirectory stringByAppendingString:@"/"]]) LMVPaths[target] = path;
    }
    NSNumber *opacityEnabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("VideoOpacityEnabled"), kLMVPrefsID);
    LMVOpacityEnabled = !opacityEnabled || opacityEnabled.boolValue;
    NSNumber *opacity = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("VideoOpacity"), kLMVPrefsID);
    if (!opacity) opacity = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("MessageBackgroundOpacity"), kLMVPrefsID);
    // Off means fully transparent; keep the historical enabled default.
    LMVOpacity = [opacity respondsToSelector:@selector(floatValue)] ? MAX(0.0, MIN(1.0, opacity.floatValue)) : 0.55;
    LMVPrepareAssets();
}
static CGRect LMVRectInView(UIView *view, UIView *ancestor) {
    CALayer *source = view.layer.presentationLayer;
    CALayer *destination = ancestor.layer.presentationLayer;
    if (source && destination) return [source convertRect:source.bounds toLayer:destination];
    return [view convertRect:view.bounds toView:ancestor];
}
static BOOL LMVNotificationCenterSurface(UIView *view) {
    if (!view.window || view.window.hidden) return NO;
    for (UIView *node = view; node; node = node.superview) {
        NSString *name = NSStringFromClass(node.class);
        if ([name containsString:@"SBCoverSheet"] || [name containsString:@"NCNotification"] ||
            [name containsString:@"NotificationCenter"] || [name containsString:@"CoverSheet"]) return YES;
    }
    NSString *windowName = NSStringFromClass(view.window.class);
    if ([windowName containsString:@"CoverSheet"] || [windowName containsString:@"NotificationCenter"]) return YES;
    for (UIViewController *controller = view.window.rootViewController; controller; controller = controller.presentedViewController) {
        NSString *name = NSStringFromClass(controller.class);
        if ([name containsString:@"CoverSheet"] || [name containsString:@"NotificationCenter"]) return YES;
    }
    return NO;
}
static BOOL LMVVisible(UIView *view) {
    if (!LMVNotificationCenterSurface(view)) return NO;
    if (!view.window || view.window.hidden || view.bounds.size.width < 1 || view.bounds.size.height < 1) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (ancestor.hidden || LMVOriginalVisibilityAlpha(ancestor) < 0.01) return NO;
        if (ancestor.clipsToBounds && !CGRectIntersectsRect(LMVRectInView(view, ancestor), (ancestor.layer.presentationLayer ?: ancestor.layer).bounds)) return NO;
    }
    uint64_t blank = 0;
    if (LMVBlankToken >= 0 && notify_get_state(LMVBlankToken, &blank) == NOTIFY_STATUS_OK && blank) return NO;
    return CGRectIntersectsRect(LMVRectInView(view, view.window), (view.window.layer.presentationLayer ?: view.window.layer).bounds);
}
static BOOL LMVActionBranch(UIView *view) {
    // Grouped notification actions use this presenter even when the concrete
    // private subclass no longer contains "ActionButtons" in its name.
    Class presenter = NSClassFromString(@"PLActionButtonsPresentingView");
    return [NSStringFromClass(view.class) containsString:@"ActionButtons"] || (presenter && [view isKindOfClass:presenter]);
}
static BOOL LMVIsClassOrSubclass(UIView *view, NSString *name) {
    Class cls = NSClassFromString(name);
    return cls && [view isKindOfClass:cls];
}
static UIView *LMVMessageMaterial(UIView *view, NSUInteger depth) {
    if (depth > 12 || LMVActionBranch(view) || view.hidden || LMVOriginalVisibilityAlpha(view) < 0.01) return nil;
    if ([NSStringFromClass(view.class) containsString:@"MaterialView"] && view.bounds.size.width > 20 && view.bounds.size.height > 20) return view;
    for (UIView *child in view.subviews) {
        if (LMVIsClassOrSubclass(child, @"NCNotificationListCell")) continue;
        UIView *material = LMVMessageMaterial(child, depth + 1);
        if (material) return material;
    }
    return nil;
}
static BOOL LMVMessageCell(UIView *cell) {
    return LMVIsClassOrSubclass(cell, @"NCNotificationListCell");
}
static NSString *LMVSemanticTarget(UIView *view) {
    NSString *title = nil;
    if ([view isKindOfClass:UIButton.class]) title = [(UIButton *)view currentTitle];
    if ([view isKindOfClass:UILabel.class]) title = [(UILabel *)view text];
    for (NSString *label in @[(title ?: @""), (view.accessibilityLabel ?: @"")]) {
        NSString *text = [[label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
        // Exact labels only: never classify an unlabeled header close control.
        if ([@[@"clear", @"clear all", @"清除", @"清除全部", @"全部清除", @"清除所有", @"清除所有通知"] containsObject:text]) return @"Clear";
        if ([@[@"options", @"manage", @"选项", @"管理"] containsObject:text]) return @"Options";
    }
    return nil;
}
#import "LMVActionDiscovery.h"
static void LMVActionHosts(UIView *view, NSMapTable *hosts, NSUInteger depth) {
    if (depth > 12) return;
    // Platter containers are discovery boundaries only after exact Clear/Options
    // semantics are found; they never become a suppression/overlay target.
    BOOL platter = [NSStringFromClass(view.class) containsString:@"Platter"];
    if (LMVActionBranch(view) || platter) { LMVFindActions(view, view, hosts, 0); return; }
    for (UIView *child in view.subviews) LMVActionHosts(child, hosts, depth + 1);
}
static void LMVPause(LMVVideoState *state) {
    LMVRestoreBackground(state);
    LMVReleasePlayer(state);
}

static void LMVRetryDiscovery(UIView *cell) {
    if (objc_getAssociatedObject(cell, &LMVRetryKey)) return;
    objc_setAssociatedObject(cell, &LMVRetryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakCell = cell;
    for (NSUInteger attempt = 1; attempt <= 4; attempt++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(attempt * 0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *owner = weakCell;
            if (!owner) return;
            if (owner.window && LMVPlaybackAllowed()) {
                objc_setAssociatedObject(owner, &LMVDiscoveryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                LMVUpdate(owner);
            }
        });
    }
}
static void LMVUpdate(UIView *cell) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    NSMutableDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
    if (!states) { states = [NSMutableDictionary new]; objc_setAssociatedObject(cell, &LMVStatesKey, states, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    BOOL playbackAllowed=LMVPlaybackAllowed();
    if (!playbackAllowed) for (LMVVideoState *state in states.allValues) LMVReleasePlayer(state);
    // Display cached content even before the playback/screen visibility gate opens.
    BOOL visible = LMVVisible(cell);
    CFTimeInterval now = CACurrentMediaTime();
    if (!cell.window) {
        for (LMVVideoState *state in states.allValues) {
            if (!state.detachedSince) state.detachedSince = now;
            if (now - state.detachedSince > 0.35) LMVReleasePlayer(state);
        }
        // No return: known model hosts can receive cached imagery before entering a window.
    }
    NSMapTable *hosts = objc_getAssociatedObject(cell, &LMVHostsKey);
    if (!hosts) { hosts = [NSMapTable strongToStrongObjectsMapTable]; objc_setAssociatedObject(cell, &LMVHostsKey, hosts, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    // UIKit briefly hides or detaches notification materials while collapsing a stack.
    // Keep our cached host and decoder through that transient window.
    BOOL messageEligible = LMVMessageCell(cell);
    if (!messageEligible) {
        [hosts removeObjectForKey:@"Message"];
        LMVVideoState *old = states[@"Message"];
        LMVPause(old); [old.overlay removeFromSuperview];
        [states removeObjectForKey:@"Message"];
    }
    BOOL missing = NO;
    for (NSString *target in LMVTargets()) {
        UIView *host = [hosts objectForKey:target];
        if ([target isEqualToString:@"Message"] && !messageEligible) host = nil;
        if (host && !([host isDescendantOfView:cell] || host == cell)) {
            [hosts removeObjectForKey:target]; host = nil;
            // An invalid boundary is not a transient detach: remove only our
            // owned overlay immediately, before discovery binds a new host.
            LMVVideoState *old = states[target];
            LMVPause(old); [old.overlay removeFromSuperview];
            objc_setAssociatedObject(old.overlay, &LMVOwnershipKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            old.anchor = nil; old.host = nil;
        }
        if (LMVEnabled[target].boolValue && LMVPaths[target] && !host) missing = YES;
    }
    NSNumber *last = objc_getAssociatedObject(cell, &LMVDiscoveryKey);
    BOOL refreshActions = (!last || now - last.doubleValue >= 0.1);
    if (refreshActions) {
        [hosts removeObjectForKey:@"Options"]; [hosts removeObjectForKey:@"Clear"];
    }
    if ((missing || refreshActions) && (!last || now - last.doubleValue >= 0.1)) {
        objc_setAssociatedObject(cell, &LMVDiscoveryKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LMVActionHosts(cell, hosts, 0);
        if (messageEligible) {
            UIView *material = LMVMessageMaterial(cell, 0);
            if (material) [hosts setObject:material forKey:@"Message"];
        }
    }
    static char discoveryDiagnosticKey;
    NSMutableString *discovery=[NSMutableString stringWithFormat:@"discovery visible=%d",visible];
    for (NSString *target in LMVTargets()) [discovery appendFormat:@" %@ enabled=%d selected=%d assetready=%d host=%d",target,LMVEnabled[target].boolValue,LMVPaths[target]!=nil,LMVReadyAssets && [LMVReadyAssets containsObject:LMVPaths[target] ?: @""],[hosts objectForKey:target]!=nil];
    NSString *previous=objc_getAssociatedObject(cell,&discoveryDiagnosticKey);
    if (![previous isEqualToString:discovery]) { objc_setAssociatedObject(cell,&discoveryDiagnosticKey,[discovery copy],OBJC_ASSOCIATION_RETAIN_NONATOMIC); LMVDiagnostic(discovery); }
    for (NSString *target in LMVTargets()) {
        UIView *anchor = [hosts objectForKey:target];
        BOOL reportGeometry=NO;
        NSString *path = LMVPaths[target];
        LMVVideoState *state = states[target];
        if (!LMVEnabled[target].boolValue || !path || (state && ![state.path isEqualToString:path])) {
            LMVPause(state); [state.overlay removeFromSuperview]; [states removeObjectForKey:target]; state = nil;
            if (!LMVEnabled[target].boolValue || !path) continue;
        }
        if (!anchor || !anchor.superview) {
            if (state && !state.detachedSince) state.detachedSince = now;
            if (state && state.overlay.superview && state.detachedSince && now - state.detachedSince < 0.18) continue;
            LMVPause(state); [state.overlay removeFromSuperview]; state.anchor = nil; continue;
        }
        state.detachedSince = 0;
        BOOL anchorVisible = visible && LMVVisible(anchor);
        if (anchorVisible) state.visibilityLossSince = 0;
        else if (state && !state.visibilityLossSince) state.visibilityLossSince = now;
        if (!anchorVisible && (!state.visibilityLossSince || now - state.visibilityLossSince >= 0.18)) LMVReleasePlayer(state);
        if (!state) {
            // The material remains underneath until a real decoded frame is available.
            state = [LMVVideoState new]; state.path = path;
            state.revision = LMVRevisions[path];
            state.overlay = [UIView new]; state.overlay.userInteractionEnabled = NO;
            state.overlay.clipsToBounds = YES;
                    states[target] = state;
        }
        if (state.source && LMVSharedSources[path] != state.source) LMVReleasePlayer(state);
        BOOL revisionChanged=LMVRevisions[path] && ![state.revision isEqualToString:LMVRevisions[path]];
        if (revisionChanged) {
            LMVReleasePlayer(state);
            state.revision = LMVRevisions[path];
        }
        // Attach content BEFORE creating/starting a source, even for inactive hosts.
        // No output-ready/state.active gate; retained contents are not a nil fallback.
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        if (!state.layer) {
            state.layer=[CALayer layer]; state.layer.contentsGravity=kCAGravityResizeAspectFill;
            [state.overlay.layer addSublayer:state.layer];
        }
        LMVFrameSnapshot *cached=LMVCachedFrame(path,state.revision);
        if (cached.image && (!state.layer.contents || revisionChanged)) state.layer.contents=(__bridge id)cached.image;
        else if (revisionChanged) state.layer.contents=nil; // changed media is not its old revision
        [CATransaction commit];
        // A material with text/content is a container: put our surface below its
        // children, never above the whole material. Only pure drawing anchors
        // permit a sibling overlay and backing-branch suppression.
        BOOL material = LMVOriginalPureView(anchor, NO, 0) ||
            (([target isEqualToString:@"Clear"] || [target isEqualToString:@"Options"]) && LMVActionBackgroundMaterial(anchor));
        UIView *host = material ? anchor.superview : anchor;
        // Host identity is part of ownership. Never retain an overlay under a
        // reused parent when UIKit swaps the notification content host.
        if (state.host && (state.host != host || state.anchor != anchor)) {
            LMVRestoreBackground(state);
            [state.overlay removeFromSuperview];
            state.anchor = nil;
        }
        NSDictionary *ownership = @{ @"target": target, @"host": [NSValue valueWithNonretainedObject:host] };
        objc_setAssociatedObject(state.overlay, &LMVOwnershipKey, ownership, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state.host = host;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (state.overlay.superview != host || state.anchor != anchor) {
            if (material) [host insertSubview:state.overlay aboveSubview:anchor];
            else [host insertSubview:state.overlay atIndex:0];
            state.anchor = anchor;
        }
        // Model geometry into the model host, never presentation-to-model coordinates.
        // Only the plugin-owned surface participates in clipping; parent size is unchanged.
        CALayer *clip=anchor.layer;
        state.overlay.transform = CGAffineTransformIdentity;
        state.overlay.frame = [anchor convertRect:anchor.bounds toView:host];
        state.overlay.autoresizingMask = UIViewAutoresizingNone;
        CGFloat radius=clip.cornerRadius;
        if (radius<=0) radius=MIN(20.0, MIN(anchor.bounds.size.width,anchor.bounds.size.height)*0.5);
        state.overlay.layer.cornerRadius = radius;
        state.overlay.layer.cornerCurve = kCACornerCurveContinuous;
        state.overlay.layer.maskedCorners = kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner|kCALayerMinXMaxYCorner|kCALayerMaxXMaxYCorner;
        state.overlay.layer.mask = nil;
        state.layer.frame = state.overlay.bounds;
        state.layer.hidden = NO;
        state.overlay.alpha = LMVOpacityEnabled ? LMVOpacity : 0.0;
        [CATransaction commit];
        // Lease depends on enabled + selected + target scope, never decoder,
        // first frame, alpha or active consumption. Cold absence stays transparent.
        BOOL originalInScope = cell.window && anchorVisible;
        // Screen blank pauses frames but does not change an attached target lease.
        if (!playbackAllowed && state.originals.count && cell.window &&
            state.originalAnchor == anchor && state.originalScope == host) originalInScope = YES;
        LMVReplaceBackground(state, anchor, host, target, originalInScope);
        state.active=playbackAllowed && anchorVisible && LMVOpacityEnabled && LMVOpacity>0.0;
        if (reportGeometry) LMVDiagnostic([NSString stringWithFormat:@"bind source=%lu target=%@ visible=%d active=%d anchor=%.1fx%.1f overlay=%.1fx%.1f",(unsigned long)state.source.identifier,target,anchorVisible,state.active,anchor.bounds.size.width,anchor.bounds.size.height,state.overlay.bounds.size.width,state.overlay.bounds.size.height]);
        if (anchorVisible) state.lastVisible = now;
        // Owned content, geometry, opacity and corners are assigned before startup.
        if (!state.source && state.active) { state.source=LMVSourceForPath(path); reportGeometry=state.source!=nil; }
        if (state.active && state.source) LMVStartSource(state.source);
        else if (state.source && !LMVSourceHasConsumer(state.source)) LMVStopSource(state.source);
    }
    LMVSyncDisplayLink();
}
%hook NCNotificationListCell
- (void)layoutSubviews {
    %orig;
    if (!LMVInitialized) return;
    [LMVCells addObject:(UIView *)self];
    LMVRequestSafeUpdate();
}
- (void)didMoveToWindow {
    %orig;
    if (!LMVInitialized) return;
    [LMVCells addObject:(UIView *)self];
    LMVRequestSafeUpdate();
}
- (void)prepareForReuse {
    objc_setAssociatedObject(self, &LMVRetryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDictionary *states = objc_getAssociatedObject(self, &LMVStatesKey);
    for (LMVVideoState *state in states.allValues) { LMVPause(state); [state.overlay removeFromSuperview]; objc_setAssociatedObject(state.overlay, &LMVOwnershipKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); state.anchor = nil; state.host = nil; }
    objc_setAssociatedObject(self, &LMVStatesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &LMVHostsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &LMVDiscoveryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end
static void LMVCoverSheetVisibilityChanged(UIView *view) {
    if (!LMVInitialized || !NSThread.isMainThread) return;
    // Visibility is evaluated after UIKit finishes the current lifecycle call.
    // Cards own retained frames; no playback policy runs in a system setter.
    [LMVEaster refresh];
    LMVRequestSafeUpdate();
}
%group LMVCoverWindowHooks
%hook SBCoverSheetWindow
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVCoverSheetVisibilityChanged((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    LMVCoverSheetVisibilityChanged((UIView *)self);
}
%end
%end
%hook CoverSheet
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVCoverSheetVisibilityChanged((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    LMVCoverSheetVisibilityChanged((UIView *)self);
}
%end
static void LMVUpdateActionPresenter(UIView *presenter) {
    UIView *ancestor = presenter.superview;
    Class cellClass = NSClassFromString(@"NCNotificationListCell");
    while (ancestor && (!cellClass || ![ancestor isKindOfClass:cellClass])) ancestor = ancestor.superview;
    // A grouped swipe presenter can live outside NCNotificationListCell.
    // Track only the dedicated action presenter, not a notification header.
    UIView *owner = ancestor ?: presenter;
    [LMVCells addObject:owner];
    objc_setAssociatedObject(owner, &LMVDiscoveryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LMVUpdate(owner);
}
%hook PLActionButtonsPresentingView
- (void)layoutSubviews {
    %orig;
    if (!LMVInitialized || !NSThread.isMainThread) return;
    [LMVActionPresenters addObject:(UIView *)self];
    LMVRequestSafeUpdate();
}
- (void)didMoveToWindow {
    %orig;
    if (!LMVInitialized || !NSThread.isMainThread) return;
    [LMVActionPresenters addObject:(UIView *)self];
    LMVRequestSafeUpdate();
}
%end
static void LMVReleaseAllPlayers(void) {
    // Keep one paused player/time and one last decoded CGImage per file, not per card.
    [LMVLink invalidate]; LMVLink=nil;
    for (LMVSharedSource *source in LMVSharedSources.allValues) LMVStopSource(source);
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
        for (LMVVideoState *state in states.allValues) state.active=NO;
    }

}
static void LMVRefresh(BOOL reload) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    if (reload) {
        // Revision-aware preparation preserves matching players, clocks and layers.
        // Unrelated imports must not tear down a working selected shared source.
        LMVLoadPreferences();
    }
    LMVLockVideoRefresh(reload);
    for (UIView *presenter in LMVActionPresenters.allObjects) LMVUpdateActionPresenter(presenter);
    for (UIView *cell in LMVCells.allObjects) {
        NSMutableDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
        for (NSString *target in states.allKeys) {
            LMVVideoState *state = states[target];
            if (!LMVVisible(cell) && CACurrentMediaTime() - state.lastVisible > 8) LMVReleasePlayer(state);
            if (!LMVEnabled[target].boolValue || ![state.path isEqualToString:LMVPaths[target]]) {
                LMVPause(state); [state.overlay removeFromSuperview]; [states removeObjectForKey:target];
            }
        }
        LMVUpdate(cell);
    }
    LMVSyncDisplayLink();
}
// Tracking mode suppresses default-mode timers and scrolling does not relayout every cell.
// Only visibility/readiness/host identity transitions invoke the heavier layout path.
@interface LMVDisplayLinkTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end
static void LMVSuspend(void) {
    LMVLockVideoSuspend();
    LMVReleaseAllPlayers();
}
static void LMVSyncDisplayLink(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    BOOL needed=NO;
    if (LMVPlaybackAllowed() && LMVOpacityEnabled && LMVOpacity>0) {
        for (UIView *cell in LMVCells.allObjects) {
            if (!LMVVisible(cell)) continue;
            // Observe readiness even before a source/overlay/frame exists.
            for (NSString *target in LMVTargets()) {
                if (LMVEnabled[target].boolValue && LMVPaths[target]) { needed=YES; break; }
            }
            if (needed) break;
        }
    }
    static NSInteger lastNeeded=-1;
    if (lastNeeded!=(NSInteger)needed) { lastNeeded=needed; LMVDiagnostic([NSString stringWithFormat:@"displaylink-needed=%d cells=%lu alpha-enabled=%d alpha=%.3f",needed,(unsigned long)LMVCells.count,LMVOpacityEnabled,LMVOpacity]); }
    if (!needed) {
        // Stopping frame scheduling pauses sources and retains exact displayed frames.
        for (LMVSharedSource *source in LMVSharedSources.allValues) LMVStopSource(source); [LMVLink invalidate]; LMVLink=nil; return; }
    if (LMVLink) return;
    LMVDisplayLinkTarget *target=[LMVDisplayLinkTarget new];
    LMVLink=[CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
    LMVLink.preferredFramesPerSecond=30;
    [LMVLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
@implementation LMVDisplayLinkTarget
- (void)tick:(CADisplayLink *)link {
    if (!LMVPlaybackAllowed()) { LMVSuspend(); return; }
    // Visibility is separate from frame conversion; never rediscover/layout every card per frame.
    NSMutableSet<LMVSharedSource *> *visible=[NSMutableSet new];
    NSUInteger consumers=0;
    static CFTimeInterval lastDiscovery=0;
    BOOL discover=link.timestamp-lastDiscovery>=0.20;
    if (discover) lastDiscovery=link.timestamp;
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
        BOOL cellVisible=LMVVisible(cell), changed=NO;
        for (LMVVideoState *state in states.allValues) {
            BOOL active=cellVisible && state.anchor && LMVVisible(state.anchor) && state.overlay.superview && LMVOpacityEnabled && LMVOpacity>0.0;
            if (active!=state.active) changed=YES;
            state.active=active;
        }
        if (changed || (discover && cellVisible)) LMVUpdate(cell);
        for (LMVVideoState *state in states.allValues) if (state.active && state.source) { [visible addObject:state.source]; consumers++; }
    }
    for (LMVSharedSource *source in LMVSharedSources.allValues) {
        if ([visible containsObject:source]) LMVStartSource(source); else LMVStopSource(source);
    }
    static NSUInteger lastSources=NSUIntegerMax,lastConsumers=NSUIntegerMax,nextSource=0;
    if (lastSources!=visible.count || lastConsumers!=consumers) {
        LMVDiagnostic([NSString stringWithFormat:@"sourcecounts total=%lu visible=%lu consumers=%lu",(unsigned long)LMVSharedSources.count,(unsigned long)visible.count,(unsigned long)consumers]);
        lastSources=visible.count; lastConsumers=consumers;
    }
    NSArray *sources=visible.allObjects;
    // Rotate priority when multiple materials compete for the single in-flight conversion.
    for (NSUInteger n=0;n<sources.count;n++) {
        LMVSharedSource *source=sources[(n+nextSource)%sources.count];
        CFTimeInterval now=CACurrentMediaTime();
        AVPlayerItem *item=source.player.currentItem;
        if (!source.readerMode && now-source.lastRequestAt>=1.0) {
            source.lastRequestAt=now;
            [source.output requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03];
            if (!source.restoringTime && !source.restoreOnStart && item.status==AVPlayerItemStatusReadyToPlay && source.player.rate==0 && source.playing) [source.player play];
        }
        // A persistent AVPlayer-output stall switches explicitly to a shared,
        // video-only AVAssetReader. Never attach an AVPlayerLayer to a card.
        CFTimeInterval stallLimit=source.published ? 3.0 : 0.75;
        if (!source.readerMode && !source.restoringTime && !source.restoreOnStart && !source.frameBusy && (item.status==AVPlayerItemStatusFailed || now-source.lastProgressAt>=stallLimit)) {
            source.readerMode=YES; [source.player pause]; source.generation++;
            CMTime resume=CMTIME_IS_NUMERIC(source.lastTime)?source.lastTime:kCMTimeZero;
            dispatch_async(LMVFrameQueue, ^{ source.readerClock=CACurrentMediaTime(); source.readerOffset=resume; source.readerLastTarget=kCMTimeInvalid; });
            LMVDiagnostic([NSString stringWithFormat:@"source=%lu fallback=shared-reader reason=%@",(unsigned long)source.identifier,item.status==AVPlayerItemStatusFailed?@"item-failed":(source.published?@"no-progress-3s":@"cold-no-frame-0.75s")]);
        }
        CFTimeInterval hostTime=link.targetTimestamp>0 ? link.targetTimestamp : link.timestamp+link.duration;
        CMTime time=[source.output itemTimeForHostTime:hostTime];
        BOOL mappedTimeValid=CMTIME_IS_NUMERIC(time) && CMTimeCompare(time,kCMTimeZero)>=0;
        CMTime current=source.player.currentTime;
        BOOL valid=CMTIME_IS_NUMERIC(time) && CMTimeCompare(time,kCMTimeZero)>=0;
        // currentTime is already item time; never feed an uninitialized host mapping.
        if (!valid || (CMTIME_IS_NUMERIC(current) && fabs(CMTimeGetSeconds(time)-CMTimeGetSeconds(current))>0.5)) time=current;
        if (!source.readerMode && CMTIME_IS_NUMERIC(time) && ![source.output hasNewPixelBufferForItemTime:time] && CMTIME_IS_NUMERIC(current) && [source.output hasNewPixelBufferForItemTime:current]) time=current;
        LMVPublishFrame(source,time);
        NSString *phase=[NSString stringWithFormat:@"owner=%@ mode=%@ requested=%d playerstatus=%ld itemstatus=%ld ready=%d timestatus=%ld rate=%.2f item=%d outputawake=%d mappedvalid=%d timevalid=%d",source.ownerTarget,source.readerMode?@"shared-reader":@"shared-output",source.playing,(long)source.player.status,(long)item.status,item.status==AVPlayerItemStatusReadyToPlay,(long)source.player.timeControlStatus,source.player.rate,item!=nil,source.outputAwake,mappedTimeValid,CMTIME_IS_NUMERIC(time)];
        BOOL transition=![source.diagnosticState isEqualToString:phase];
        if (transition || (now-source.lastDiagnosticAt>=2 && now-source.startedAt<30)) {
            source.diagnosticState=phase; source.lastDiagnosticAt=now;
            LMVDiagnostic([NSString stringWithFormat:@"source=%lu %@ newframes=%lu buffers=%lu conversion=%lu conversionerrors=%lu published=%lu discard=%lu errorcode=%ld",(unsigned long)source.identifier,phase,(unsigned long)source.newFrames,(unsigned long)source.buffers,(unsigned long)source.conversions,(unsigned long)source.conversionErrors,(unsigned long)source.published,(unsigned long)source.drops,(long)item.error.code]);
        }
    }
    nextSource++;
    LMVSyncDisplayLink();
}
@end
static void LMVDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!LMVInitialized) return;
        LMVPreferencesDirty = YES;
        LMVRequestSafeUpdate();
    });
}
static void LMVScreenNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!LMVInitialized || !LMVLaunchReady) return;
        if (!LMVPlaybackAllowed()) LMVSuspend();
        else LMVPrepareAssets();
        LMVRequestSafeUpdate();
    });
}
%ctor {
    @autoreleasepool {
        LMVDiagnosticQueue=dispatch_queue_create("com.minis.lockmessagevideo.diagnostics",DISPATCH_QUEUE_SERIAL);
        LMVFrameQueue=dispatch_queue_create("com.minis.lockmessagevideo.frames",DISPATCH_QUEUE_SERIAL);
        LMVCIContext=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO}];
        LMVCells = [NSHashTable weakObjectsHashTable];
        LMVActionPresenters = [NSHashTable weakObjectsHashTable];
        LMVFrameCache = [NSMutableDictionary new]; LMVPreviewPending = [NSMutableSet new];
        LMVDiskQueue=dispatch_queue_create("com.minis.lockmessagevideo.last-frame",DISPATCH_QUEUE_SERIAL);
        LMVDiskPending=[NSMutableSet new]; LMVDiskAttempted=[NSMutableSet new]; LMVDiskWriting=[NSMutableSet new];
        LMVDiskEpochs=[NSMutableDictionary new]; LMVDiskSavedTimes=[NSMutableDictionary new];
        LMVRevisions = [NSMutableDictionary new];
        LMVPaths = [NSMutableDictionary new]; LMVEnabled = [NSMutableDictionary new];
        LMVSources = [NSMutableDictionary new]; LMVAssets = [NSMutableDictionary new];  LMVReadyAssets = [NSMutableSet new]; LMVSharedSources = [NSMutableDictionary new];
        LMVInitialized = YES;
        NSNumber *diagnostics = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("DiagnosticsEnabled"), kLMVPrefsID);
        LMVDiagnosticsEnabled.store([diagnostics respondsToSelector:@selector(boolValue)] && diagnostics.boolValue);
        if (LMVDiagnosticsEnabled.load()) LMVDiagnosticEpoch.fetch_add(1);
        notify_register_check("com.apple.springboard.hasBlankedScreen", &LMVBlankToken);
        notify_register_check("com.apple.springboard.lockstate", &LMVLockToken);
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            // Always leave the notification/system launch stack before policy.
            dispatch_async(dispatch_get_main_queue(), ^{ LMVMarkLaunchReady(); });
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // An actual active transition is also evidence for late injection.
                if (LMVAlreadyLaunched(UIApplication.sharedApplication)) LMVMarkLaunchReady();
                else LMVRequestSafeUpdate();
            });
        }];
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (LMVInitialized && LMVLaunchReady) LMVSuspend();
            });
        }];
        %init;
        LMVLockVideoInstallHooks();
        Class coverWindow = NSClassFromString(@"SBCoverSheetWindow");
        if (coverWindow && [coverWindow isSubclassOfClass:UIWindow.class]) %init(LMVCoverWindowHooks);
        for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UIApplicationDidBecomeActiveNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{ LMVEasterStartIfReady(); });
            }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ dispatch_async(dispatch_get_main_queue(), ^{ LMVEasterStartIfReady(); }); });
        for (NSString *name in @[@"com.minis.lockmessagevideo/videoChanged", @"com.minis.lockmessagevideo/preferencesChanged"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        for (NSString *name in @[@"com.apple.springboard.hasBlankedScreen", @"com.apple.springboard.lockstate"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVScreenNotification, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            // No arbitrary delay and no creating private singleton. For a normal
            // startup, only did-finish/active evidence opens the readiness gate.
            if (LMVAlreadyLaunched(UIApplication.sharedApplication)) LMVMarkLaunchReady();
        });
    }
}
