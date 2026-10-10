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
#import "LMVConsumerPolicy.h"
#import "LMVOriginalBackground.h"

static NSString * const LMVDirectory = @"/var/mobile/LockMessageVideo";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSHashTable<UIView *> *LMVCells;
static NSHashTable<UIView *> *LMVActionPresenters;
static NSHashTable<UIView *> *LMVLockHosts;
static char LMVLockStateKey;
static NSHashTable<UIView *> *LMVDesktopHosts;
static char LMVDesktopStateKey;
static NSTimer *LMVDesktopVisibilityTimer;
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
static void LMVUpdateLockScreens(void);
static void LMVUpdateDesktops(void);
static void LMVUpdateWallpaperWindows(void);
static void LMVWallpaperPublish(LMVSharedSource *source, CGImageRef image);
static void LMVNotificationWallpaperPublish(LMVSharedSource *source, CGImageRef image);
static void LMVUpdateNotificationWallpapers(void);
static void LMVUpdateNotificationWallpaperGeometry(void);
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
            BOOL trace = [event hasPrefix:@"wallpaper-call "] || [event hasPrefix:@"wallpaper-hook "] || [event hasPrefix:@"wallpaper-coverage "];
            BOOL provider = [event hasPrefix:@"wallpaper-metadata "] || [event hasPrefix:@"wallpaper-inheritance "] || [event hasPrefix:@"wallpaper-field "] || [event hasPrefix:@"wallpaper-provider-method "];
            BOOL wallpaper = [event hasPrefix:@"wallpaper-"];
            static NSUInteger records=0, wallpaperRecords=0, traceRecords=0, providerRecords=0;
            static unsigned long lastEpoch=0;
            if (lastEpoch != epoch) {
                records=wallpaperRecords=traceRecords=providerRecords=0;
                lastEpoch=epoch;
            }
            if (trace) { if (++traceRecords > 1800) return; }
            else if (provider) { if (++providerRecords > 2400) return; }
            else if (wallpaper) { if (++wallpaperRecords > 2400) return; }
            else if (++records > 1200) return;
            NSFileManager *fm=NSFileManager.defaultManager;
            [fm createDirectoryAtPath:LMVDirectory withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *path=[LMVDirectory stringByAppendingPathComponent:trace ? @"wallpaper-call.log" : (provider ? @"wallpaper-provider.log" : (wallpaper ? @"wallpaper-structure.log" : @"shared-render.log"))];
            if ([[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue]>((trace || provider || wallpaper) ? 262144 : 65536)) {
                NSString *old=[path stringByAppendingString:@".1"];
                [fm removeItemAtPath:old error:nil]; [fm moveItemAtPath:path toPath:old error:nil];
            }
            if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}];
            NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
            @try {
                [handle seekToEndOfFile];
                NSString *line=[NSString stringWithFormat:@"%.3f version=0.0.72 session=%lu pid=%d %@\n",CACurrentMediaTime(),epoch,getpid(),event];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            } @catch (NSException *exception) { /* Diagnostics must never affect playback. */ }
            @finally { [handle closeFile]; }
        }
    });
}

static void LMVCaptureWallpaperDiagnostics(void);
#import "LMVWallpaperCallTrace.h"

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
                    LMVUpdateLockScreens();
                    LMVUpdateDesktops();
                }
                if (image) CGImageRelease(image);
            });
        }
    });
}

// Wallpaper decoders are target-owned; message-family cards keep their file key.
static NSString *LMVSourceRegistryKey(NSString *path, NSString *target) {
    if (!path.length) return nil;
    if ([target isEqualToString:@"LockScreen"] || [target isEqualToString:@"Desktop"])
        return [NSString stringWithFormat:@"wallpaper/%@|%@",target,path];
    return path;
}
// Only immutable images/PTS are retained across wallpaper decoder retirement.
static NSMutableDictionary<NSString *, LMVFrameSnapshot *> *LMVWallpaperFrameCache;
static LMVFrameSnapshot *LMVCachedWallpaperFrame(NSString *path, NSString *revision, NSString *target) {
    NSString *key=LMVFrameKey(LMVSourceRegistryKey(path,target),revision);
    return (key ? LMVWallpaperFrameCache[key] : nil) ?: LMVCachedFrame(path,revision);
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
                    LMVUpdateLockScreens(); LMVUpdateDesktops();
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
@property(nonatomic) LMVDesktopGateClock desktopClock;
@property(nonatomic, strong) CAShapeLayer *desktopDockMask;
@property(nonatomic) CGRect desktopDockRect;
@property(nonatomic, copy) NSString *desktopDockReason;
@property(nonatomic, strong) NSArray<LMVOriginalLease *> *originals, *wallpaperOriginals;
@property(nonatomic, copy) NSString *wallpaperDiagnostic;
@property(nonatomic, weak) UIView *originalAnchor, *originalScope;
@property(nonatomic, copy) NSString *originalDiagnostic;
@property(nonatomic) BOOL wallpaperEligible;
@end
@implementation LMVVideoState
- (void)dealloc {
    LMVReleaseOriginals(_originals, self);
    LMVReleaseOriginals(_wallpaperOriginals, self);
    [_overlay removeFromSuperview];
    [_layer removeFromSuperlayer];
}
@end
#import "LMVBackgroundDiscovery.h"
#import "LMVObservedWallpaper.h"
#import "LMVWallpaperWindow.h"
#import "LMVNotificationWallpaper.h"

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
    BOOL wallpaper=![registryKey isEqualToString:path];
    LMVFrameSnapshot *owned=wallpaper ? LMVWallpaperFrameCache[LMVFrameKey(registryKey,source.revision)] : nil;
    LMVFrameSnapshot *snapshot=owned ?: LMVCachedFrame(path,source.revision);
    if (snapshot.image) {
        source.lastImage=CGImageRetain(snapshot.image);
        // A shared poster never transfers another target's decoder position.
        if ((!wallpaper || owned) && snapshot.rendered && CMTIME_IS_NUMERIC(snapshot.time)) {
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
                    if (![source.registryKey isEqualToString:source.path]) {
                        if (!LMVWallpaperFrameCache) LMVWallpaperFrameCache=[NSMutableDictionary new];
                        LMVFrameSnapshot *owned=[LMVFrameSnapshot new];
                        owned.image=CGImageRetain(image); owned.time=workTime; owned.rendered=YES;
                        LMVWallpaperFrameCache[LMVFrameKey(source.registryKey,source.revision)]=owned;
                    }
                    [CATransaction begin]; [CATransaction setDisableActions:YES];
                    for (UIView *cell in LMVCells.allObjects) {
                        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
                        for (LMVVideoState *state in states.allValues) if (state.source==source) state.layer.contents=(__bridge id)image;
                    }
                    for (UIView *host in LMVLockHosts.allObjects) {
                        LMVVideoState *state = objc_getAssociatedObject(host, &LMVLockStateKey);
                        if (state.source == source && state.active) state.layer.contents = (__bridge id)image;
                    }
                    for (UIView *host in LMVDesktopHosts.allObjects) {
                        LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
                        if (state.source == source && state.active) state.layer.contents = (__bridge id)image;
                    }
                    LMVWallpaperPublish(source, image);
                    LMVNotificationWallpaperPublish(source, image);
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
    for (UIView *host in LMVLockHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVLockStateKey);
        if (state.source == source && state.active && host.window) return YES;
    }
    for (UIView *host in LMVDesktopHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
        if (state.source == source && state.active && host.window) return YES;
    }
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
    for (NSString *target in @[@"LockScreen",@"Desktop"]) {
        NSString *prefix=[LMVSourceRegistryKey(path,target) stringByAppendingString:@"|"];
        for (NSString *key in LMVWallpaperFrameCache.allKeys)
            if ([key hasPrefix:prefix]) [LMVWallpaperFrameCache removeObjectForKey:key];
    }
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
                    LMVUpdateLockScreens();
                    LMVUpdateDesktops();
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
        LMVDiagnostic(@"version=0.0.72 diagnostics-enabled");
        LMVReportWallpaperTrace();
        LMVStartWallpaperTraceReports();
    }
    LMVPaths = [NSMutableDictionary new];
    // These are semantic source names, kept independent from UIKit private class names.
    LMVMaterialSources = @{
        @"Message": @"message.mov",
        @"Options": @"options.mov",
        @"Clear": @"clear.mov"
    };
    LMVEnabled = [NSMutableDictionary new];
    for (NSString *target in @[@"Message", @"Options", @"Clear", @"LockScreen", @"Desktop"]) {
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
        if (cached.image) state.layer.contents=(__bridge id)cached.image;
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
// CoverSheet owns its video layer; replacement is scoped to confirmed local wallpaper drawing.
static BOOL LMVLockHostVisible(UIView *host) {
    Class cover = NSClassFromString(@"CSCoverSheetView");
    Class windowClass = NSClassFromString(@"SBCoverSheetWindow");
    return LMVLockConsumerAllowed(cover && [host isKindOfClass:cover], windowClass && [host.window isKindOfClass:windowClass], LMVVisible(host) || LMVNotificationWallpaperVisible(), LMVPlaybackAllowed());
}
static __attribute__((unused)) BOOL LMVBranchHasWallpaper(UIView *view, NSUInteger depth) {
    if ([NSStringFromClass(view.class) containsString:@"Wallpaper"]) return LMVOriginalPureView(view, YES, 0);
    if (depth >= 4) return NO;
    // A mixed page/container can own clock or notifications as well: placing
    // above that whole branch would cover content. Only follow one-child wrappers.
    return view.subviews.count == 1 && LMVBranchHasWallpaper(view.subviews.firstObject, depth + 1);
}
static void LMVUpdateLockScreen(UIView *host) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread || !host) return;
    LMVVideoState *state = objc_getAssociatedObject(host, &LMVLockStateKey);
    NSString *path = LMVPaths[@"LockScreen"];
    BOOL enabled = LMVEnabled[@"LockScreen"].boolValue && path.length;
    if (state && (!enabled || ![state.path isEqualToString:path] || (LMVRevisions[path] && ![state.revision isEqualToString:LMVRevisions[path]]))) {
        LMVRestoreBackground(state);
        LMVReleasePlayer(state);
        [state.layer removeFromSuperlayer];
        objc_setAssociatedObject(host, &LMVLockStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state = nil;
    }
    if (!enabled) { LMVUpdateWallpaperWindows(); return; }
    if (!state) {
        state = [LMVVideoState new];
        state.path = path;
        state.revision = LMVRevisions[path];
        state.layer = [CALayer layer];
        state.layer.name = @"com.minis.lockmessagevideo.lockscreen";
        state.layer.contentsGravity = kCAGravityResizeAspectFill;
        state.layer.masksToBounds = YES;
        state.host = host;
        objc_setAssociatedObject(host, &LMVLockStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    // Frame holder only. LMVWallpaperWindow.h renders the sole visible layer.
    state.layer.frame = host.bounds; state.layer.hidden = YES;
    state.layer.opacity = LMVOpacityEnabled ? LMVOpacity : 0.0;
    LMVFrameSnapshot *cached = LMVCachedWallpaperFrame(path, state.revision, @"LockScreen");
    if (!state.layer.contents && cached.image) state.layer.contents = (__bridge id)cached.image;
    BOOL active = LMVLockHostVisible(host);
    if (state.source && LMVSharedSources[LMVSourceRegistryKey(path,@"LockScreen")] != state.source) LMVReleasePlayer(state);
    BOOL originalInScope = active || (!LMVPlaybackAllowed() && (state.originals.count || state.wallpaperOriginals.count) && host.window);
    // Direct wallpaper replacement owns the original branch and restores it on scope loss.
    LMVRestoreBackground(state);
    state.wallpaperEligible = originalInScope;
    if (active && [LMVReadyAssets containsObject:path]) {
        if (!state.source) state.source = LMVSourceForTarget(path,@"LockScreen");
        if (state.source.lastImage) state.layer.contents = (__bridge id)state.source.lastImage;
    }
    state.active = active && state.source != nil;
    LMVUpdateWallpaperWindows();
    [CATransaction commit];
    if (!state.active && !LMVSourceHasConsumer(state.source)) LMVStopSource(state.source);
}
static void LMVUpdateLockScreens(void) {
    for (UIView *host in LMVLockHosts.allObjects) LMVUpdateLockScreen(host);
}
static BOOL LMVLockScreenNeedsFrames(void) {
    if (!LMVEnabled[@"LockScreen"].boolValue || !LMVPaths[@"LockScreen"]) return NO;
    for (UIView *host in LMVLockHosts.allObjects) if (LMVLockHostVisible(host)) return YES;
    return NO;
}
// Desktop owns a separate layer/state; frame retention is independent of decoding.
static BOOL LMVDesktopGeometryVisible(UIView *host) {
    if (!host.window || host.window.hidden || CGRectIsEmpty(host.bounds)) return NO;
    for (UIView *view = host; view; view = view.superview)
        if (view.hidden || view.alpha < 0.01) return NO;
    return CGRectIntersectsRect([host convertRect:host.bounds toView:host.window], host.window.bounds);
}
static BOOL LMVDesktopMethod(id object, SEL selector, const char *returnType) {
    if (![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments == 2 && strcmp(signature.methodReturnType, returnType) == 0;
}
static LMVWindowRole LMVDesktopRole(id object) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        LMVWindowRole role = LMVDesktopWindowRole(class_getName(cls));
        if (role != LMVWindowOther) return role;
        if (strcmp(class_getName(cls), "SBFloatingDockController") == 0) return LMVWindowFloatingDock;
    }
    return LMVWindowOther;
}
static BOOL LMVDesktopHomeController(id object) {
    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls))
        if (!strcmp(class_getName(cls), "SBHomeScreenViewController") || !strcmp(class_getName(cls), "SBIconController")) return YES;
    return NO;
}
static LMVDesktopRect LMVDesktopPolicyRect(CGRect rect) {
    return (LMVDesktopRect){rect.origin.x, rect.origin.y, rect.size.width, rect.size.height};
}
static BOOL LMVDesktopCoverFullyObscures(UIView *host) {
    for (UIView *cover in LMVLockHosts.allObjects) {
        if (!LMVVisible(cover) || cover.window.screen != host.window.screen) continue;
        // Compare model with model and presentation with presentation. A full-size
        // window alone says nothing about its sliding CoverSheet content.
        // CSCoverSheetView is a full-screen transparent shell during pulls.
        // Its guarded slideableContentView/contentView carries the actual offset.
        UIView *content = nil;
        for (NSString *name in @[@"slideableContentView", @"contentView"]) {
            SEL getter = NSSelectorFromString(name);
            if (!LMVDesktopMethod(cover, getter, @encode(id))) continue;
            id candidate = ((id (*)(id, SEL))objc_msgSend)(cover, getter);
            if ([candidate isKindOfClass:UIView.class] && candidate != cover &&
                [candidate isDescendantOfView:cover] && LMVVisible(candidate)) { content = candidate; break; }
        }
        if (!content) continue; // No proven content extent: do not infer from UIWindow.bounds.
        CALayer *shown = content.layer.presentationLayer ?: content.layer;
        CALayer *home = host.layer.presentationLayer ?: host.layer;
        // Window coordinate spaces must be stable before claiming full occlusion.
        if (cover.window.layer.animationKeys.count || host.window.layer.animationKeys.count) continue;
        CALayer *coverRoot = cover.window.layer.presentationLayer ?: cover.window.layer;
        CALayer *homeRoot = host.window.layer.presentationLayer ?: host.window.layer;
        CGRect modelRect = [content convertRect:content.bounds toCoordinateSpace:cover.window.screen.coordinateSpace];
        CGRect shownLocal = [shown convertRect:shown.bounds toLayer:coverRoot];
        CGRect shownRect = [cover.window convertRect:shownLocal toCoordinateSpace:cover.window.screen.coordinateSpace];
        CGRect homeRect = [host convertRect:host.bounds toCoordinateSpace:host.window.screen.coordinateSpace];
        CGRect homeLocal = [home convertRect:home.bounds toLayer:homeRoot];
        CGRect shownHome = [host.window convertRect:homeLocal toCoordinateSpace:host.window.screen.coordinateSpace];
        BOOL opaque = cover.alpha >= 0.99 && cover.window.alpha >= 0.99 && shown.opacity >= 0.99;
        if (LMVDesktopFullyCovered(LMVDesktopPolicyRect(modelRect), LMVDesktopPolicyRect(shownRect), LMVDesktopPolicyRect(homeRect), opaque) &&
            LMVDesktopRectCovers(LMVDesktopPolicyRect(shownRect), LMVDesktopPolicyRect(shownHome))) return YES;
    }
    return NO;
}
@interface LMVDesktopSnapshot : NSObject
@property(nonatomic, copy) NSArray<UIWindow *> *windows;
@property(nonatomic) BOOL screenOn, lockKnown, locked, notificationTransition;
@property(nonatomic) LMVForeground foreground;
@property(nonatomic, copy) NSString *foregroundClass;
@property(nonatomic) CFTimeInterval now;
@end
@implementation LMVDesktopSnapshot @end
static LMVDesktopSnapshot *LMVDesktopCapture(void) {
    LMVDesktopSnapshot *snapshot = [LMVDesktopSnapshot new];
    snapshot.now = CACurrentMediaTime(); snapshot.screenOn = LMVPlaybackAllowed(); snapshot.locked = YES;
    if (!LMVInitialized || !LMVLaunchReady) return snapshot;
    NSMutableArray *windows = [NSMutableArray new];
    UIApplication *app = UIApplication.sharedApplication;
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class]) [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    snapshot.windows = windows;
    Class coverWindow = NSClassFromString(@"SBCoverSheetWindow");
    for (UIWindow *window in windows) if (coverWindow && [window isKindOfClass:coverWindow] &&
        !window.hidden && window.alpha >= 0.01) snapshot.notificationTransition = YES;
    // Read SpringBoard's published state; this never creates a system manager.
    // Unknown state stays fail-closed until the publisher supplies lock state.
    uint64_t lockState = 1;
    snapshot.lockKnown = LMVLockToken >= 0 && notify_get_state(LMVLockToken, &lockState) == NOTIFY_STATUS_OK;
    if (snapshot.lockKnown) snapshot.locked = lockState != 0;
    // Guard both selector and object-return ABI. Prefer an actual application ID;
    // an accessibility proxy/controller without one is only a transition hint.
    id foreground = nil, identifier = nil;
    BOOL frontKnown = NO;
    SEL bundle = NSSelectorFromString(@"bundleIdentifier");
    for (NSString *name in @[@"_accessibilityFrontMostApplication", @"_frontmostApplication"]) {
        SEL front = NSSelectorFromString(name);
        if (!LMVDesktopMethod(app, front, @encode(id))) continue;
        frontKnown = YES;
        id candidate = ((id (*)(id, SEL))objc_msgSend)(app, front);
        id candidateID = LMVDesktopMethod(candidate, bundle, @encode(id)) ? ((id (*)(id, SEL))objc_msgSend)(candidate, bundle) : nil;
        if ([candidateID isKindOfClass:NSString.class] && [candidateID length]) {
            foreground = candidate; identifier = candidateID; break;
        }
        if (!foreground) foreground = candidate;
    }
    snapshot.foregroundClass = foreground ? NSStringFromClass([foreground class]) : @"nil";
    LMVWindowRole role = LMVDesktopRole(foreground), windowRole = LMVWindowOther;
    if ([foreground isKindOfClass:UIView.class]) windowRole = LMVDesktopRole(((UIView *)foreground).window);
    else if ([foreground isKindOfClass:UIViewController.class]) windowRole = LMVDesktopRole(((UIViewController *)foreground).viewIfLoaded.window);
    if (windowRole != LMVWindowOther) role = windowRole;
    if (!foreground && frontKnown) for (UIWindow *window in snapshot.windows)
        if (window.isKeyWindow && !window.hidden && window.alpha >= 0.01) role = LMVDesktopRole(window);
    snapshot.foreground = LMVDesktopResolveForeground(identifier != nil, [identifier isEqual:@"com.apple.springboard"],
        frontKnown && !foreground, role, NO);
    if (!identifier && role != LMVWindowFloatingDock && LMVDesktopHomeController(foreground)) snapshot.foreground = LMVForegroundHome;
    // Preserve 0.53's nil-frontmost home behavior when the guarded API exists.
    // For an unknown object, only an actual visible key HomeScreenWindow is a
    // return signal; a real bundle ID above always wins.
    if (!identifier && frontKnown && !foreground && role != LMVWindowFloatingDock) snapshot.foreground = LMVForegroundHome;
    return snapshot;
}
static LMVDesktopActivity LMVDesktopHostActivity(UIView *host, LMVVideoState *state, LMVDesktopSnapshot *snapshot) {
    Class home = NSClassFromString(@"SBHomeScreenView"), homeWindow = NSClassFromString(@"SBHomeScreenWindow");
    BOOL homeHost = home && object_getClass(host) == home;
    BOOL inHomeWindow = homeWindow && [host.window isKindOfClass:homeWindow];
    BOOL visible = LMVDesktopGeometryVisible(host);
    BOOL covered = inHomeWindow && LMVDesktopCoverFullyObscures(host);
    BOOL context = snapshot.foreground == LMVForegroundOverlay;
    UIViewController *controller = host.window.rootViewController;
    for (NSUInteger depth = 0; controller && depth < 8; depth++, controller = controller.presentedViewController)
        if ([NSStringFromClass(controller.class) containsString:@"ContextMenu"]) context = YES;
    BOOL dockBelow = NO;
    if (inHomeWindow) for (UIWindow *window in snapshot.windows) {
        if (LMVDesktopRole(window) != LMVWindowFloatingDock) continue;
        dockBelow |= LMVDesktopDockBelow(window.screen == host.window.screen,
            !window.hidden && window.alpha >= 0.01, window.windowLevel, host.window.windowLevel,
            YES); // Window is a level signal only; concrete content is measured below.
    }
    LMVForeground foreground = snapshot.foreground;
    // Preserve normal 0.53 foreground behavior. During NC, an unknown UI proxy
    // must not pause partially exposed home; an actual app bundle still wins.
    if (snapshot.notificationTransition && foreground == LMVForegroundUnknown) foreground = LMVForegroundHome;
    LMVDesktopDecision decision = LMVDesktopDecide(homeHost, inHomeWindow, host.window != nil, visible,
        snapshot.screenOn, snapshot.lockKnown, snapshot.locked, foreground, covered, context);
    LMVDesktopGateClock clock = state ? state.desktopClock : (LMVDesktopGateClock){0,0};
    LMVDesktopActivity activity = LMVDesktopGate(decision, foreground, host.window.isKeyWindow,
        visible, covered, context, dockBelow, state.active, snapshot.now, &clock);
    if (state) state.desktopClock = clock;
    return activity;
}
// Read-only, bounded discovery. A full-screen Dock window is only an owner/level
// signal, never the exclusion geometry. No icon or generic backdrop is a region.
static BOOL LMVDesktopDockContainer(UIView *view) {
    for (Class cls = object_getClass(view); cls; cls = class_getSuperclass(cls)) {
        const char *name = class_getName(cls);
        if (!strcmp(name, "SBFloatingDockView") || !strcmp(name, "SBFloatingDockPlatterView")) return YES;
    }
    // Only already-loaded concrete Dock content controllers; no view getter or
    // private singleton can create a system object here.
    UIResponder *next = view.nextResponder;
    if (![next isKindOfClass:UIViewController.class] || ((UIViewController *)next).viewIfLoaded != view) return NO;
    for (Class cls = object_getClass(next); cls; cls = class_getSuperclass(cls)) {
        const char *name = class_getName(cls);
        if (!strcmp(name, "SBFloatingDockViewController") || !strcmp(name, "SBFloatingDockIconListViewController")) return YES;
    }
    return NO;
}
static BOOL LMVDesktopDockVisible(UIView *view, UIWindow *window) {
    NSUInteger depth = 0;
    for (UIView *node = view; node && depth++ < 24; node = node.superview) {
        CALayer *shown = node.layer.presentationLayer ?: node.layer;
        if (node.hidden || node.alpha < 0.01 || shown.hidden || shown.opacity < 0.01) return NO;
        if (node == window) return YES;
    }
    return NO;
}
static BOOL LMVDesktopStableWindow(UIWindow *window) {
    CALayer *shown = window.layer.presentationLayer;
    // Public screen-coordinate conversion is safe only while the window bridge
    // itself is stable. Descendant animations use one coherent presentation tree.
    return !shown || (CGRectEqualToRect(shown.bounds, window.layer.bounds) &&
        CGPointEqualToPoint(shown.position, window.layer.position) &&
        CATransform3DEqualToTransform(shown.transform, window.layer.transform));
}
static BOOL LMVDesktopDockPoint(CGPoint point, CALayer *dockLayer, UIWindow *dockWindow,
    UIView *host, BOOL presentation, CGPoint *result) {
    CALayer *dockRoot = presentation ? dockWindow.layer.presentationLayer : dockWindow.layer;
    CALayer *homeRoot = presentation ? host.window.layer.presentationLayer : host.window.layer;
    CALayer *homeLayer = presentation ? host.layer.presentationLayer : host.layer;
    if (!dockRoot || !homeRoot || !homeLayer) return NO;
    CGPoint inWindow = [dockLayer convertPoint:point toLayer:dockRoot];
    CGPoint inScreen = [dockWindow convertPoint:inWindow toCoordinateSpace:dockWindow.screen.coordinateSpace];
    CGPoint inHome = [host.window.screen.coordinateSpace convertPoint:inScreen toCoordinateSpace:host.window];
    *result = [homeLayer convertPoint:inHome fromLayer:homeRoot];
    return isfinite(result->x) && isfinite(result->y);
}
typedef struct { NSUInteger moves, closes; } LMVDockPathCount;
static void LMVDesktopDockCountPath(void *info, const CGPathElement *element) {
    LMVDockPathCount *count = (LMVDockPathCount *)info;
    if (element->type == kCGPathElementMoveToPoint) count->moves++;
    if (element->type == kCGPathElementCloseSubpath) count->closes++;
}
static CGPathRef LMVDesktopDockPath(UIView *node, UIWindow *window, UIView *host, CGRect *region) {
    if (!LMVDesktopDockVisible(node, window) || !LMVDesktopStableWindow(window) || !LMVDesktopStableWindow(host.window)) return NULL;
    CALayer *shown = node.layer.presentationLayer;
    BOOL presentation = shown != nil;
    if (!shown) shown = node.layer;
    // Do not mix a descendant's model tree with the host's presentation tree.
    if (presentation != (host.layer.presentationLayer != nil)) return NULL;
    CGRect bounds = shown.bounds;
    if (!isfinite(bounds.origin.x) || !isfinite(bounds.origin.y) || !isfinite(bounds.size.width) || !isfinite(bounds.size.height) || CGRectIsEmpty(bounds)) return NULL;
    CGPoint origin, right, bottom, opposite;
    if (!LMVDesktopDockPoint(bounds.origin, shown, window, host, presentation, &origin) ||
        !LMVDesktopDockPoint(CGPointMake(CGRectGetMaxX(bounds), CGRectGetMinY(bounds)), shown, window, host, presentation, &right) ||
        !LMVDesktopDockPoint(CGPointMake(CGRectGetMinX(bounds), CGRectGetMaxY(bounds)), shown, window, host, presentation, &bottom) ||
        !LMVDesktopDockPoint(CGPointMake(CGRectGetMaxX(bounds), CGRectGetMaxY(bounds)), shown, window, host, presentation, &opposite)) return NULL;
    // Rotated/sheared/perspective content is ambiguous: leave the video visible.
    if (fabs(right.y-origin.y) > 0.5 || fabs(bottom.x-origin.x) > 0.5 || right.x <= origin.x || bottom.y <= origin.y ||
        fabs(opposite.x-right.x) > 0.5 || fabs(opposite.y-bottom.y) > 0.5) return NULL;
    CGFloat sx = (right.x-origin.x)/bounds.size.width, sy = (bottom.y-origin.y)/bounds.size.height;
    CGRect rect = CGRectMake(origin.x, origin.y, right.x-origin.x, bottom.y-origin.y);
    if (!LMVDesktopDockRegionSafe(LMVDesktopPolicyRect(rect), LMVDesktopPolicyRect(host.bounds))) return NULL;
    CGAffineTransform mapping = CGAffineTransformMake(sx,0,0,sy,origin.x-bounds.origin.x*sx,origin.y-bounds.origin.y*sy);
    CGPathRef path = NULL;
    CALayer *mask = shown.mask;
    if ([mask isKindOfClass:CAShapeLayer.class] && ((CAShapeLayer *)mask).path &&
        CGRectEqualToRect(mask.frame, bounds) && CGRectEqualToRect(mask.bounds, bounds) &&
        CATransform3DIsIdentity(mask.transform)) {
        CGPathRef actual = ((CAShapeLayer *)mask).path;
        LMVDockPathCount count = {0,0}; CGPathApply(actual, &count, LMVDesktopDockCountPath);
        // Require a single complete outline, never icon holes or an arbitrary mask.
        if (count.moves == 1 && count.closes == 1 && CGRectEqualToRect(CGPathGetPathBoundingBox(actual), bounds))
            path = CGPathCreateCopyByTransformingPath(actual, &mapping);
    } else if (!mask && [shown.cornerCurve isEqualToString:kCACornerCurveCircular] && isfinite(shown.cornerRadius) && shown.cornerRadius > 0 &&
        shown.maskedCorners == (kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner | kCALayerMinXMaxYCorner | kCALayerMaxXMaxYCorner)) {
        CGFloat margin = shown.shadowOpacity > 0 && isfinite(shown.shadowRadius) ? MIN(6.0, MAX(0.0, shown.shadowRadius)) : 0;
        CGRect expanded = CGRectInset(rect, -margin, -margin);
        if (!LMVDesktopDockRegionSafe(LMVDesktopPolicyRect(expanded), LMVDesktopPolicyRect(host.bounds))) return NULL;
        CGFloat rx = MIN(shown.cornerRadius*sx+margin, expanded.size.width/2);
        CGFloat ry = MIN(shown.cornerRadius*sy+margin, expanded.size.height/2);
        path = CGPathCreateWithRoundedRect(expanded, rx, ry, NULL);
        rect = expanded;
    }
    if (!path) return NULL; // No measured corner/mask: no invented Dock rectangle.
    *region = CGRectIntersection(rect, host.bounds);
    return path;
}
static __attribute__((unused)) void LMVDesktopApplyDockMask(UIView *host, LMVVideoState *state, LMVDesktopActivity activity, LMVDesktopSnapshot *snapshot) {
    CGRect region = CGRectZero;
    CGPathRef hole = NULL;
    NSString *reason = @"dock-not-below-home";
    if (activity.dockFallback) {
        reason = @"no-safe-dock-region";
        NSUInteger windows = 0, visited = 0;
        for (UIWindow *window in snapshot.windows) {
            if (++windows > 16 || visited >= 96) break;
            if (LMVDesktopRole(window) != LMVWindowFloatingDock ||
                !LMVDesktopDockBelow(window.screen == host.window.screen, !window.hidden && window.alpha >= 0.01,
                    window.windowLevel, host.window.windowLevel, YES)) continue;
            NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:window];
            while (pending.count && visited++ < 96) {
                UIView *node = pending.firstObject; [pending removeObjectAtIndex:0];
                if (node != window && LMVDesktopDockContainer(node)) {
                    CGRect measured;
                    CGPathRef candidate = LMVDesktopDockPath(node, window, host, &measured);
                    if (candidate) {
                        // Prefer the smallest reliable concrete outline (platter
                        // over wrapper), retaining just one mask/path per host.
                        if (!hole || measured.size.width*measured.size.height < region.size.width*region.size.height) {
                            if (hole) CGPathRelease(hole);
                            hole = candidate; region = measured;
                        } else CGPathRelease(candidate);
                    }
                }
                for (UIView *child in node.subviews) { if (pending.count >= 96) break; [pending addObject:child]; }
            }
        }
        if (hole) reason = @"scoped-dock-region";
    }
    if (hole) {
        CGMutablePathRef full = CGPathCreateMutable();
        CGPathAddRect(full, NULL, state.layer.bounds);
        CGAffineTransform local = CGAffineTransformMakeTranslation(state.layer.bounds.origin.x-host.bounds.origin.x, state.layer.bounds.origin.y-host.bounds.origin.y);
        CGPathAddPath(full, &local, hole);
        if (!state.desktopDockMask) {
            state.desktopDockMask = [CAShapeLayer layer];
            state.desktopDockMask.name = @"com.minis.lockmessagevideo.desktop.dock-mask";
            state.desktopDockMask.fillRule = kCAFillRuleEvenOdd;
        }
        // Geometry can change without allocating another layer. An identical
        // layout does not rewrite the path or append a second mask.
        if (!CGRectEqualToRect(state.desktopDockMask.frame, state.layer.bounds) ||
            !state.desktopDockMask.path || !CGPathEqualToPath(state.desktopDockMask.path, full)) {
            state.desktopDockMask.frame = state.layer.bounds; state.desktopDockMask.path = full;
        }
        state.layer.mask = state.desktopDockMask;
        CGPathRelease(full); CGPathRelease(hole);
    } else state.layer.mask = nil;
    state.desktopDockRect = region; state.desktopDockReason = reason;
}

// Opt-in bounded structural diagnostics; never log labels, app identifiers or message text.
static void LMVDesktopDiagnostics(UIView *host, LMVVideoState *state, LMVDesktopActivity activity, LMVDesktopSnapshot *snapshot) {
    if (!LMVDiagnosticsEnabled.load()) return;
    static CFTimeInterval last = 0;
    static NSUInteger samples = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 2.0 || samples >= 30) return;
    last = now; samples++;
    LMVDiagnostic([NSString stringWithFormat:@"desktop draw=%d decode=%d release=%d dockFallback=%d mask=%d maskrect=%@ sourcecount=%lu foreground=%d object=%@ parent=%@ reason=%@", activity.draw, activity.decode, activity.releaseSource, activity.dockFallback, state.layer.mask != nil, NSStringFromCGRect(state.desktopDockRect), (unsigned long)LMVSharedSources.count, snapshot.foreground, snapshot.foregroundClass, NSStringFromClass(host.superview.class), activity.dockFallback ? (state.desktopDockReason ?: @"no-safe-dock-region") : (activity.decode ? @"home-playing" : @"paused-retained-frame")]);
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:host];
    NSUInteger count = 0;
    for (UIWindow *window in snapshot.windows) {
        if (count++ >= 16) break;
        LMVDiagnostic([NSString stringWithFormat:@"desktop-window class=%@ level=%.1f hidden=%d alpha=%.3f key=%d", NSStringFromClass(window.class), window.windowLevel, window.hidden, window.alpha, window.isKeyWindow]);
        if (pending.count < 16) [pending addObject:window];
        if (LMVDesktopRole(window) == LMVWindowFloatingDock) {
            // Prioritize Dock children: the old shared BFS budget never reached
            // these descendants. Bound both traversal and enqueued nodes.
            NSMutableArray<UIView *> *dockNodes = [NSMutableArray arrayWithObject:window];
            for (NSUInteger visitedDock = 0; dockNodes.count && visitedDock < 12; visitedDock++) {
                UIView *node = dockNodes.firstObject; [dockNodes removeObjectAtIndex:0];
                CALayer *shown = node.layer.presentationLayer ?: node.layer;
                LMVDiagnostic([NSString stringWithFormat:@"desktop-dock-child class=%@ parent=%@ hidden=%d alpha=%.3f opacity=%.3f z=%.2f frame=%@", NSStringFromClass(node.class), NSStringFromClass(node.superview.class), node.hidden, node.alpha, shown.opacity, node.layer.zPosition, NSStringFromCGRect(node.frame)]);
                NSUInteger layers = 0;
                for (CALayer *layer in node.layer.sublayers) {
                    if (layers++ >= 4) break;
                    LMVDiagnostic([NSString stringWithFormat:@"desktop-dock-layer class=%@ hidden=%d opacity=%.3f z=%.2f frame=%@", NSStringFromClass(layer.class), layer.hidden, layer.opacity, layer.zPosition, NSStringFromCGRect(layer.frame)]);
                }
                for (UIView *child in node.subviews) { if (dockNodes.count >= 12) break; [dockNodes addObject:child]; }
            }
        }
    }
    // Shallow bounded inspection of backdrop parents, including independent Dock hosts.
    NSUInteger visited = 0;
    while (pending.count && visited++ < 32) {
        UIView *view = pending.firstObject; [pending removeObjectAtIndex:0];
        if ([NSStringFromClass(view.class) containsString:@"Backdrop"])
            LMVDiagnostic([NSString stringWithFormat:@"desktop-backdrop class=%@ parent=%@ hidden=%d alpha=%.3f parentHidden=%d parentAlpha=%.3f", NSStringFromClass(view.class), NSStringFromClass(view.superview.class), view.hidden, view.alpha, view.superview.hidden, view.superview.alpha]);
        if (pending.count < 32) [pending addObjectsFromArray:view.subviews];
    }
}
static void LMVReleaseDesktopSource(LMVVideoState *state) {
    LMVSharedSource *source = state.source;
    LMVReleasePlayer(state);
    if (!source || LMVSourceHasConsumer(source)) return;
    // Preserve cached last frame/time while fully releasing the unused decoder.
    // Clear inactive references so other consumers reacquire the current registry entry.
    for (UIView *host in LMVLockHosts.allObjects) {
        LMVVideoState *other = objc_getAssociatedObject(host, &LMVLockStateKey);
        if (other.source == source && !other.active) other.source = nil;
    }
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
        for (LMVVideoState *other in states.allValues)
            if (other.source == source && !other.active) other.source = nil;
    }
    for (UIView *host in LMVDesktopHosts.allObjects) {
        LMVVideoState *other = objc_getAssociatedObject(host, &LMVDesktopStateKey);
        if (other.source == source && !other.active) other.source = nil;
    }
    LMVRetireSource(source);
    LMVDiagnostic(@"desktop=decoder-released");
}
// A concrete application/locked/screen-off home is outside this replacement
// scope even if the retained plugin frame remains attached behind other windows.
static BOOL LMVDesktopOriginalInScope(UIView *host, LMVDesktopSnapshot *snapshot, LMVDesktopActivity activity) {
    return activity.draw && snapshot.screenOn && snapshot.lockKnown && !snapshot.locked &&
        snapshot.foreground != LMVForegroundApp && LMVDesktopGeometryVisible(host);
}
static void LMVUpdateDesktop(UIView *host, LMVDesktopSnapshot *snapshot) {
    if (!NSThread.isMainThread) return;
    Class home = NSClassFromString(@"SBHomeScreenView");
    if (!home || object_getClass(host) != home) return;
    LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
    NSString *path = LMVPaths[@"Desktop"];
    BOOL enabled = LMVEnabled[@"Desktop"].boolValue && path.length;
    if (state && (!enabled || ![state.path isEqualToString:path] || (LMVRevisions[path] && ![state.revision isEqualToString:LMVRevisions[path]]))) {
        LMVRestoreBackground(state);
        LMVReleaseDesktopSource(state); [state.layer removeFromSuperlayer];
        objc_setAssociatedObject(host, &LMVDesktopStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); state = nil;
    }
    if (!enabled) return;
    // Same 0.53 home renderer/source; only drawing and pausing are separated.
    // One immutable foreground/window snapshot drives this update and the tick.
    LMVDesktopActivity activity = LMVDesktopHostActivity(host, state, snapshot);
    if (!activity.draw) {
        LMVRestoreBackground(state);
        if (state) { state.wallpaperEligible = NO; state.layer.hidden = YES; LMVReleaseDesktopSource(state); }
        LMVUpdateWallpaperWindows();
        return;
    }
    if (!state) {
        state = [LMVVideoState new]; state.host = host; state.path = path; state.revision = LMVRevisions[path];
        state.desktopClock = (LMVDesktopGateClock){snapshot.now, 0};
        state.layer = [CALayer layer]; state.layer.name = @"com.minis.lockmessagevideo.desktop";
        state.layer.contentsGravity = kCAGravityResizeAspectFill; state.layer.masksToBounds = YES;
        objc_setAssociatedObject(host, &LMVDesktopStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LMVDiagnostic(@"desktop=guarded-home-host");
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    // Frame holder only. Icons and Dock remain in their own higher windows.
    state.layer.frame = host.bounds; state.layer.hidden = YES;
    state.layer.opacity = LMVOpacityEnabled ? LMVOpacity : 0.0;
    LMVFrameSnapshot *cached = LMVCachedWallpaperFrame(path, state.revision, @"Desktop");
    if (!state.layer.contents && cached.image) state.layer.contents = (__bridge id)cached.image;
    if (activity.decode && [LMVReadyAssets containsObject:path]) {
        if (!state.source || LMVSharedSources[LMVSourceRegistryKey(path,@"Desktop")] != state.source) state.source = LMVSourceForTarget(path,@"Desktop");
        if (state.source.lastImage) state.layer.contents = (__bridge id)state.source.lastImage;
    }
    BOOL directScope = LMVDesktopOriginalInScope(host, snapshot, activity);
    LMVRestoreBackground(state);
    state.wallpaperEligible = directScope;
    state.active = activity.decode && state.source != nil;
    LMVUpdateWallpaperWindows();
    [CATransaction commit];
    LMVDesktopDiagnostics(host, state, activity, snapshot);
    if (state.active) LMVStartSource(state.source);
    else if (activity.releaseSource) LMVReleaseDesktopSource(state);
    else if (!LMVSourceHasConsumer(state.source)) {
        LMVStopSource(state.source);
        // A live paused AVPlayer already owns its exact position. Cold rebuilds
        // still restore the cached timestamp in LMVSourceForPath as before.
        state.source.restoreOnStart = NO;
    }
}
static void LMVUpdateDesktops(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    BOOL enabled = LMVEnabled[@"Desktop"].boolValue && LMVPaths[@"Desktop"].length;
    if (!enabled) {
        // Retirement needs no system snapshot; LMVUpdateDesktop returns before
        // evaluating activity when the feature is disabled.
        for (UIView *host in LMVDesktopHosts.allObjects) LMVUpdateDesktop(host, nil);
        [LMVDesktopVisibilityTimer invalidate]; LMVDesktopVisibilityTimer = nil; return;
    }
    LMVDesktopSnapshot *snapshot = LMVDesktopCapture();
    for (UIView *host in LMVDesktopHosts.allObjects) LMVUpdateDesktop(host, snapshot);
    if (!LMVDesktopVisibilityTimer) {
        // No decoding here. Watch visibility even while the display link is stopped,
        // including app return / Notification Center dismissal without home relayout.
        LMVDesktopVisibilityTimer = [NSTimer timerWithTimeInterval:0.35 repeats:YES block:^(NSTimer *timer) {
            LMVRequestSafeUpdate();
        }];
        [NSRunLoop.mainRunLoop addTimer:LMVDesktopVisibilityTimer forMode:NSRunLoopCommonModes];
    }
    static BOOL reportedMissing = NO;
    if (!LMVDesktopHosts.count && !reportedMissing) {
        reportedMissing = YES; LMVDiagnostic(@"desktop=no-safe-home-host; guarded-no-op");
    }
}
static BOOL LMVDesktopNeedsFrames(void) {
    if (!LMVEnabled[@"Desktop"].boolValue || !LMVPaths[@"Desktop"]) return NO;
    for (UIView *host in LMVDesktopHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
        if (state.active) return YES;
    }
    return NO;
}
static void LMVDesktopHostChanged(UIView *view) {
    if (!LMVInitialized || !NSThread.isMainThread) return;
    Class home = NSClassFromString(@"SBHomeScreenView");
    if (home && object_getClass(view) == home) [LMVDesktopHosts addObject:view];
    LMVRequestSafeUpdate();
}
%group LMVDesktopViewHooks
%hook SBHomeScreenView
- (void)layoutSubviews {
    %orig;
    LMVDesktopHostChanged((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    LMVDesktopHostChanged((UIView *)self);
}
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVDesktopHostChanged((UIView *)self);
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    LMVDesktopHostChanged((UIView *)self);
}
%end
%end
%group LMVDesktopWindowHooks
%hook SBHomeScreenWindow
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVDesktopHostChanged((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    LMVDesktopHostChanged((UIView *)self);
}
%end
%end
%group LMVDesktopControllerHooks
%hook SBHomeScreenViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    LMVRequestSafeUpdate();
}
%end
%end
%group LMVDesktopCoverProgressHooks
%hook CSCoverSheetViewController
- (void)overlayController:(id)controller didChangePresentationProgress:(double)oldProgress newPresentationProgress:(double)newProgress fromLeading:(BOOL)leading {
    %orig;
    // Concrete CoverSheet transition callback; never use its full-screen window
    // bounds as cover evidence. Re-evaluate actual content geometry after orig.
    LMVRequestSafeUpdate();
}
%end
%end
%group LMVDesktopDockObserverHooks
%hook SBFloatingDockWindow
- (void)setWindowLevel:(UIWindowLevel)level {
    %orig;
    // Observe the original level; only our desktop layer may be partially masked.
    LMVRequestSafeUpdate();
}
- (void)layoutSubviews {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    LMVRequestSafeUpdate();
}
%end
%end
%group LMVDesktopDockContentHooks
%hook SBFloatingDockView
- (void)layoutSubviews {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)didMoveToWindow {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    LMVRequestSafeUpdate();
}
%end
%end
%group LMVDesktopDockPlatterHooks
%hook SBFloatingDockPlatterView
- (void)layoutSubviews {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)didMoveToWindow {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    LMVRequestSafeUpdate();
}
%end
%end
%group LMVWallpaperWindowHooks
%hook _SBWallpaperSecureWindow
- (void)setHidden:(BOOL)hidden {
    %orig;
    if (LMVWallpaperWindows) [LMVWallpaperWindows addObject:(UIWindow *)self];
    LMVDesktopHostChanged((UIView *)self);
}
- (void)layoutSubviews {
    %orig;
    if (LMVWallpaperWindows) [LMVWallpaperWindows addObject:(UIWindow *)self];
    LMVDesktopHostChanged((UIView *)self);
}
%end
%end

static void LMVLockHostChanged(UIView *view) {
    if (!LMVInitialized || !NSThread.isMainThread) return;
    [LMVLockHosts addObject:view];
    LMVRequestSafeUpdate();
}
%group LMVLockScreenHooks
%hook CSCoverSheetView
- (void)layoutSubviews {
    %orig;
    LMVLockHostChanged((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    LMVLockHostChanged((UIView *)self);
}
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVLockHostChanged((UIView *)self);
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    LMVLockHostChanged((UIView *)self);
}
%end
%end

static void LMVCoverSheetVisibilityChanged(UIView *view) {
    if (!LMVInitialized || !NSThread.isMainThread) return;
    // Visibility is evaluated after UIKit finishes the current lifecycle call.
    // Cells/lock hosts already own retained frames; no policy runs in a setter.
    LMVRequestSafeUpdate();
}
%group LMVNotificationPanelHooks
%hook SBCoverSheetPanelBackgroundContainerView
- (void)layoutSubviews {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)didMoveToWindow {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVRequestSafeUpdate();
}
- (void)setFrame:(CGRect)frame {
    %orig;
    LMVRequestSafeUpdate();
}
%end
%end
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
    for (UIView *host in LMVLockHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVLockStateKey);
        state.active = NO;
    }
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
        for (LMVVideoState *state in states.allValues) state.active=NO;
    }
    BOOL desktopEnabled = LMVEnabled[@"Desktop"].boolValue && LMVPaths[@"Desktop"].length;
    LMVDesktopSnapshot *snapshot = desktopEnabled ? LMVDesktopCapture() : nil;
    for (UIView *host in LMVDesktopHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
        LMVDesktopActivity activity = LMVDesktopHostActivity(host, state, snapshot);
        state.layer.hidden = YES; state.active = NO;
        if (!LMVDesktopOriginalInScope(host, snapshot, activity)) LMVRestoreBackground(state);
        if (activity.releaseSource) LMVReleaseDesktopSource(state);
    }
}
#import "LMVWallpaperDiagnostics.h"
static void LMVRefresh(BOOL reload) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    if (reload) {
        // Revision-aware preparation preserves matching players, clocks and layers.
        // Unrelated imports must not tear down a working selected shared source.
        LMVLoadPreferences();
    }
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
    LMVUpdateLockScreens();
    LMVUpdateDesktops();
    LMVUpdateWallpaperWindows();
    LMVUpdateNotificationWallpapers();
    LMVReportWallpaperTrace();
    LMVCaptureWallpaperDiagnostics();
    LMVSyncDisplayLink();
}
// Tracking mode suppresses default-mode timers and scrolling does not relayout every cell.
// Only visibility/readiness/host identity transitions invoke the heavier layout path.
@interface LMVDisplayLinkTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end
static void LMVSuspend(void) {
    LMVReleaseAllPlayers();
}
static void LMVSyncDisplayLink(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    BOOL needed=LMVLockScreenNeedsFrames() || LMVDesktopNeedsFrames();
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
        // Desktop update owns retirement. Stopping frame scheduling is a pause,
        // never evidence that NC/menu/unknown transitions require decoder teardown.
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
    // Update only plugin-owned clip geometry on every interactive tracking tick.
    LMVUpdateNotificationWallpaperGeometry();
    // Only the actual visible CoverSheet host consumes lockscreen frames.
    for (UIView *host in LMVLockHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVLockStateKey);
        BOOL active = LMVLockHostVisible(host);
        if (discover || active != state.active) LMVUpdateLockScreen(host);
        if (state.active && state.source) { [visible addObject:state.source]; consumers++; }
    }
    BOOL desktopEnabled = LMVEnabled[@"Desktop"].boolValue && LMVPaths[@"Desktop"].length;
    LMVDesktopSnapshot *desktopSnapshot = discover && desktopEnabled ? LMVDesktopCapture() : nil;
    for (UIView *host in LMVDesktopHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
        if (discover) LMVUpdateDesktop(host, desktopSnapshot);
        if (state.active && state.source) { [visible addObject:state.source]; consumers++; }
    }
    if (discover) { LMVUpdateWallpaperWindows(); LMVUpdateNotificationWallpapers(); }
    LMVUpdateNotificationWallpaperGeometry();
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
        LMVLockHosts = [NSHashTable weakObjectsHashTable];
        LMVDesktopHosts = [NSHashTable weakObjectsHashTable];
        LMVWallpaperWindows = [NSHashTable weakObjectsHashTable];
        LMVNCWallpaperWindows = [NSHashTable weakObjectsHashTable];
        LMVFrameCache = [NSMutableDictionary new]; LMVPreviewPending = [NSMutableSet new];
        LMVDiskQueue=dispatch_queue_create("com.minis.lockmessagevideo.last-frame",DISPATCH_QUEUE_SERIAL);
        LMVDiskPending=[NSMutableSet new]; LMVDiskAttempted=[NSMutableSet new]; LMVDiskWriting=[NSMutableSet new];
        LMVDiskEpochs=[NSMutableDictionary new]; LMVDiskSavedTimes=[NSMutableDictionary new];
        LMVRevisions = [NSMutableDictionary new];
        LMVPaths = [NSMutableDictionary new]; LMVEnabled = [NSMutableDictionary new];
        LMVSources = [NSMutableDictionary new]; LMVAssets = [NSMutableDictionary new];  LMVReadyAssets = [NSMutableSet new]; LMVSharedSources = [NSMutableDictionary new];
        LMVInitialized = YES;
        // Capture calls during initial wallpaper construction if diagnostics was
        // already enabled before respring; no system manager is constructed.
        NSNumber *traceEnabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("DiagnosticsEnabled"), kLMVPrefsID);
        LMVDiagnosticsEnabled.store([traceEnabled respondsToSelector:@selector(boolValue)] && traceEnabled.boolValue);
        if (LMVDiagnosticsEnabled.load()) LMVDiagnosticEpoch.fetch_add(1);
        LMVInstallWallpaperTrace();
        LMVReportWallpaperTrace();
        LMVStartWallpaperTraceReports();
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
        Class lockHost = NSClassFromString(@"CSCoverSheetView");
        Class lockWindow = NSClassFromString(@"SBCoverSheetWindow");
        Class notificationPanel = NSClassFromString(@"SBCoverSheetPanelBackgroundContainerView");
        if (notificationPanel && [notificationPanel isSubclassOfClass:UIView.class] &&
            class_getInstanceMethod(notificationPanel,@selector(layoutSubviews)) &&
            class_getInstanceMethod(notificationPanel,@selector(didMoveToWindow)) &&
            class_getInstanceMethod(notificationPanel,@selector(setFrame:))) {
            %init(LMVNotificationPanelHooks);
        }
        if (lockWindow && [lockWindow isSubclassOfClass:UIWindow.class]) {
            %init(LMVCoverWindowHooks);
        }
        if (lockHost && lockWindow && [lockHost isSubclassOfClass:UIView.class] && [lockWindow isSubclassOfClass:UIWindow.class]) {
            %init(LMVLockScreenHooks);
        }
        Class homeView = NSClassFromString(@"SBHomeScreenView");
        Class homeWindow = NSClassFromString(@"SBHomeScreenWindow");
        Class wallpaperWindow = NSClassFromString(@"_SBWallpaperSecureWindow");
        if (homeView && homeWindow && [homeView isSubclassOfClass:UIView.class] && [homeWindow isSubclassOfClass:UIWindow.class] &&
            class_getInstanceMethod(homeView, @selector(layoutSubviews)) && class_getInstanceMethod(homeView, @selector(didMoveToWindow))) {
            %init(LMVDesktopViewHooks);
            %init(LMVDesktopWindowHooks);
        }
        Class desktopController = NSClassFromString(@"SBHomeScreenViewController");
        if (desktopController && [desktopController isSubclassOfClass:UIViewController.class] &&
            class_getInstanceMethod(desktopController, @selector(viewDidAppear:)) &&
            class_getInstanceMethod(desktopController, @selector(viewDidDisappear:))) {
            %init(LMVDesktopControllerHooks);
        }
        Class coverController = NSClassFromString(@"CSCoverSheetViewController");
        SEL progress = NSSelectorFromString(@"overlayController:didChangePresentationProgress:newPresentationProgress:fromLeading:");
        Method progressMethod = class_getInstanceMethod(coverController, progress);
        NSMethodSignature *progressSignature = progressMethod ? [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(progressMethod)] : nil;
        if (progressSignature && progressSignature.numberOfArguments == 6 &&
            !strcmp(progressSignature.methodReturnType, @encode(void)) &&
            !strcmp([progressSignature getArgumentTypeAtIndex:2], @encode(id)) &&
            !strcmp([progressSignature getArgumentTypeAtIndex:3], @encode(double)) &&
            !strcmp([progressSignature getArgumentTypeAtIndex:4], @encode(double)) &&
            !strcmp([progressSignature getArgumentTypeAtIndex:5], @encode(BOOL))) {
            %init(LMVDesktopCoverProgressHooks);
        }
        Class dockWindow = NSClassFromString(@"SBFloatingDockWindow");
        if (dockWindow && [dockWindow isSubclassOfClass:UIWindow.class] &&
            class_getInstanceMethod(dockWindow, @selector(setWindowLevel:)) &&
            class_getInstanceMethod(dockWindow, @selector(layoutSubviews)) &&
            class_getInstanceMethod(dockWindow, @selector(setHidden:)) && class_getInstanceMethod(dockWindow, @selector(setAlpha:))) {
            %init(LMVDesktopDockObserverHooks);
        }
        Class dockContent = NSClassFromString(@"SBFloatingDockView");
        if (dockContent && [dockContent isSubclassOfClass:UIView.class] &&
            class_getInstanceMethod(dockContent, @selector(layoutSubviews)) && class_getInstanceMethod(dockContent, @selector(didMoveToWindow)) &&
            class_getInstanceMethod(dockContent, @selector(setHidden:)) && class_getInstanceMethod(dockContent, @selector(setAlpha:))) {
            %init(LMVDesktopDockContentHooks);
        }
        Class dockPlatter = NSClassFromString(@"SBFloatingDockPlatterView");
        if (dockPlatter && [dockPlatter isSubclassOfClass:UIView.class] &&
            class_getInstanceMethod(dockPlatter, @selector(layoutSubviews)) && class_getInstanceMethod(dockPlatter, @selector(didMoveToWindow)) &&
            class_getInstanceMethod(dockPlatter, @selector(setHidden:)) && class_getInstanceMethod(dockPlatter, @selector(setAlpha:))) {
            %init(LMVDesktopDockPlatterHooks);
        }
        if (wallpaperWindow && [wallpaperWindow isSubclassOfClass:UIWindow.class] && class_getInstanceMethod(wallpaperWindow, @selector(layoutSubviews))) {
            %init(LMVWallpaperWindowHooks);
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UIApplicationDidBecomeActiveNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{ LMVEasterStartIfReady(); });
            }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ dispatch_async(dispatch_get_main_queue(), ^{ LMVEasterStartIfReady(); }); });
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
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
