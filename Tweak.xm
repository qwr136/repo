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
#import "LMVPaths.h"

#define LMVDirectory LMVUserStorageRoot()
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
// 1.76.4: the gate is GLOBAL - one conversion at a time across every channel - and
// it is cleared from a main-queue block that only runs after the frame queue has
// finished. If that conversion never returns (slow file, software CIContext
// fallback on a large frame), the gate stays YES forever: every source returns at
// the top of LMVPublishFrame, all surfaces freeze on their last image, AVPlayer
// keeps playing on its own thread, and the audio continues. That is the reported
// "picture stuck, sound still there". Carry the moment it was taken plus a token,
// so an overrun can be evicted without letting its late callback clear a newer one.
static CFTimeInterval LMVFrameBusySince;
static NSUInteger LMVFrameBusyToken;
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
static LMVSharedSource *LMVSourceForTarget(NSString *path, NSString *target);
static void LMVWarmSourcesForPath(NSString *path);
static CGFloat LMVOpacity = 0.55;
static BOOL LMVOpacityEnabled = YES;
static CGFloat LMVCardOpacity(void) {
    // This switch controls CUSTOM alpha, not whether the video background exists.
    // Off -> full opacity. BackgroundEnabled owns overlay existence separately.
    return LMVOpacityEnabled && isfinite(LMVOpacity)?MAX(0.0,MIN(1.0,LMVOpacity)):1.0;
}
static int LMVBlankToken = -1;
static char LMVStatesKey, LMVHostsKey, LMVDiscoveryKey, LMVRetryKey, LMVOwnershipKey, LMVMaintenanceKey;
static NSArray<NSString *> *LMVTargets(void) { return @[@"Message", @"Options", @"Clear"]; }
static void LMVUpdate(UIView *cell);
static void LMVSyncDisplayLink(void);
static void LMVReleaseAllPlayers(void);
static void LMVRefresh(BOOL reload);
static void LMVRefreshChannel(NSString *target, BOOL reload);
static BOOL LMVVisible(UIView *view);
static CADisplayLink *LMVLink;
static int LMVLockToken = -1;
// Collections are initialized before any observer or hook can register a host.
// Launch readiness is independent: a system initializer must never run policy.
static BOOL LMVInitialized, LMVLaunchReady, LMVSafeUpdatePending, LMVSafeUpdateApplying;
static BOOL LMVPreferencesDirty = YES;
static void LMVDiagnostic(NSString *event);
static void LMVPanelPresenceStart(void);
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
#import "LMVCardUpdates.h"

static void LMVMarkLaunchReady(void) {
    if (!LMVInitialized || !NSThread.isMainThread) return;
    LMVLaunchReady = YES;
    LMVRequestSafeUpdate();
    LMVPanelPresenceStart();
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
// 1.76.2: main-thread stopwatch. Only a call that exceeds the threshold is
// written, and it is exempt from the record budget. Two CACurrentMediaTime()
// calls cost nothing even on the per-frame path, so this can stay in.
static void LMVPerfProbe(const char *label, CFTimeInterval started) {
    if (!LMVDiagnosticsEnabled.load()) return;
    CFTimeInterval ms=(CACurrentMediaTime()-started)*1000.0;
    if (ms<50.0) return;
    LMVDiagnostic([NSString stringWithFormat:@"perf-long %s %.1fms",label,ms]);
}
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
            // 0.0.123: the card and lock channels emit ~10-150 records per second,
            // so a fixed per-epoch budget silently dropped the rare floating-ball
            // decisions (no easter-window line ever reached the log, which made
            // "the ball disappeared" undiagnosable). Easter decisions are tiny and
            // rate limited by their own change detection: never count them here.
            // 1.76.2: switch-time events are rare and decisive; a 1200-record
            // budget must not swallow them (the last two captures lost every
            // loadsource= line exactly when the freeze happened).
            // 1.76.7: every per-channel state line is exempt from the 1200-record
            // budget. The Squid panel capture contained 797 card-pipeline and 198
            // card-exposure lines and ZERO squid-* lines - the panel's own log was
            // pushed out by the notification cards, so the report had no evidence at
            // all. A bug report about one channel must never lose that channel's lines.
            BOOL priority = [event hasPrefix:@"easter-window "] || [event hasPrefix:@"perf-long "] ||
                [event hasPrefix:@"loadsource="] || [event hasPrefix:@"asset-ready="] ||
                [event hasPrefix:@"squid-"] || [event hasPrefix:@"cv-panel "] || [event hasPrefix:@"desktop-panel"] ||
                [event hasPrefix:@"window-owner "] || [event hasPrefix:@"frame-gate-timeout"] ||
                [event hasPrefix:@"desktop-stage "];
            if (!priority && ++records > 1200) return;
            NSFileManager *fm=NSFileManager.defaultManager;
            [fm createDirectoryAtPath:LMVDirectory withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *path=[LMVDirectory stringByAppendingPathComponent:@"shared-render.log"];
            if ([[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue]>2097152) {
                NSString *old=[path stringByAppendingString:@".1"];
                [fm removeItemAtPath:old error:nil]; [fm moveItemAtPath:path toPath:old error:nil];
            }
            if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}];
            NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
            @try {
                [handle seekToEndOfFile];
                NSString *line=[NSString stringWithFormat:@"%.3f version=%@ session=%lu pid=%d %@\n",CACurrentMediaTime(),LMV_VERSION_STRING,epoch,getpid(),event];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            } @catch (NSException *exception) { /* Diagnostics must never affect playback. */ }
            @finally { [handle closeFile]; }
        }
    });
}

#import "LMVLockVideo.h"
// 2.55: the shared visible-window snapshot every panel channel probes through.
#import "LMVProbeWindows.h"
#import "LMVDesktopVideo.h"
#import "LMVControlCenterVideo.h"
#import "LMVHomeMenuVideo.h"
#import "LMVSquidPanelVideo.h"
#import "LMVATPanelVideo.h"
#import "LMVCopyLogXVideo.h"
#import "LMVPhoneAssistVideo.h"
#import "LMVGlassSuiteVideo.h"
#import "LMVCCBorderVideo.h"
#include "LMVCopyVaultPanelVideo.h"
#include "LMVMyrtlePanelVideo.h"
#import "LMVMediaAudio.h"

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

// One playback chain per SELECTED FILE, never per card.
// 0.0.123 user policy: when Message/Options/Clear select the SAME video they
// share one player, clock, output and retained frame; a category whose selected
// video differs keeps its own independent chain. The target is still validated
// (only the three card categories may register here) but it no longer
// participates in the key, so identical selections collapse onto one decoder.
static NSString *LMVSourceRegistryKey(NSString *path, NSString *target) {
    if (!path.length || ![@[@"Message",@"Options",@"Clear"] containsObject:target ?: @""]) return nil;
    // 1.76.1: one source per CHANNEL, not per file. The key used to be the path
    // alone, so Message/Options/Clear that happened to select the SAME clip shared
    // one AVPlayer, one decoder session and one frame gate - a single stalled
    // source froze all three surfaces at once. Cards inside one channel still
    // share that channel's source, which is the intended behaviour; the three
    // channels no longer share anything.
    return [NSString stringWithFormat:@"%@|%@", path, target];
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
@property(nonatomic) CFTimeInterval startedAt, pausedAt;
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
// 1.76.5: declared here because the output delegate below is the earliest caller;
// the definition sits next to LMVSyncDisplayLink.
static void LMVRequestSyncDisplayLink(void);
@implementation LMVSharedSource
- (void)outputMediaDataWillChange:(AVPlayerItemOutput *)output {
    if (output!=_output) return;
    _outputAwake=YES;
    LMVDiagnostic([NSString stringWithFormat:@"source=%lu output-ready requested=%d",(unsigned long)_identifier,_playing]);
    // Delegate queue is main; no UIKit work is performed by the decoding queue.
    LMVRequestSyncDisplayLink();
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
                    if (LMVAssets[path]) LMVWarmSourcesForPath(path);
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
@property(nonatomic) CFTimeInterval exposureDiagnosticAt;
@property(nonatomic,copy) NSString *exposureDiagnostic;
@end
@implementation LMVVideoState
- (void)dealloc {
    LMVReleaseOriginals(_originals, self);
    [_overlay removeFromSuperview];
    [_layer removeFromSuperlayer];
}
@end
static BOOL LMVCardStateVisible(UIView *owner, LMVVideoState *state, NSString *target);
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
    source.ownerTarget=target;
    source.revision=LMVRevisions[path];
    LMVFrameSnapshot *snapshot=LMVCachedFrame(path,source.revision);
    if (snapshot.image) {
        source.lastImage=CGImageRetain(snapshot.image);
        // 1.76.6: do NOT restore the position. A cached frame with rendered=YES is
        // the frame we PAUSED at, and its time is where playback had got to.
        // Restoring it made every material switch resume mid-clip - the user picks a
        // background and expects it to start from the beginning, not from second 8 of
        // the last audition. The still is kept ONLY as a placeholder so the surface
        // is not blank while the decoder warms up; playback always starts at zero.
        // The other case that used this path - hiding and revealing the same surface -
        // is the SAME LMVSharedSource, and AVPlayer keeps its own time across
        // pause/play, so it never needed a disk restore either.
    }
    source.pausedAt=CACurrentMediaTime();
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
static void LMVWarmSourcesForPath(NSString *path) {
    if(!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread)return;
    for(NSString *target in LMVTargets())
        if(LMVEnabled[target].boolValue && [LMVPaths[target] isEqualToString:path])
            LMVSourceForTarget(path,target);
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
    if (!source || source.restoringTime || !source.playing) return;
    if (LMVFrameBusy) {
        CFTimeInterval held=CACurrentMediaTime()-LMVFrameBusySince;
        if (held<2.0) return;
        // 1.76.4: evict only the conversion that overran.
        LMVDiagnostic([NSString stringWithFormat:@"frame-gate-timeout held=%.0fms",held*1000.0]);
        LMVFrameBusyToken++;
        LMVFrameBusy=NO; LMVFrameBusySince=0;
    }
    if (source.frameBusy) return;
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
    LMVFrameBusySince=CACurrentMediaTime();
    NSUInteger frameToken=++LMVFrameBusyToken;
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
                source.frameBusy=NO;
                if (LMVFrameBusyToken==frameToken) { LMVFrameBusy=NO; LMVFrameBusySince=0; }
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
        // 1.76.4: `playing` is our INTENT, not the player's state. When the system
        // pauses the player underneath us - an audio interruption, the frame pipeline
        // falling behind, a key-window transition while the easter panel closes -
        // `playing` stays YES. The early return then keeps it paused forever,
        // lastProgressAt stops advancing, and three seconds later
        // LMVSourceNeedsReaderRecovery drops the channel onto the AVAssetReader path,
        // where every frame costs a decode + CIContext pass on top of playback.
        // The measured end state was a healthy player that nobody was restarting:
        //   playerstatus=1 itemstatus=1 ready=1 rate=0.00 mode=shared-reader
        if (!source.readerMode && source.player.rate<0.01 &&
            source.player.currentItem.status==AVPlayerItemStatusReadyToPlay &&
            source.player.timeControlStatus!=AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) {
            [source.player playImmediatelyAtRate:1.0];
            source.lastProgressAt=CACurrentMediaTime();
            return;
        }
        if (!source.readerMode && source.restoreOnStart && !source.restoringTime &&
            source.player.currentItem.status==AVPlayerItemStatusReadyToPlay) source.playing=NO;
        else return;
    }
    if (!source.player.currentItem && !source.readerMode) { LMVDiagnostic([NSString stringWithFormat:@"source=%lu start=no-currentItem",(unsigned long)source.identifier]); return; }
    source.playing=YES; source.startedAt=CACurrentMediaTime(); source.lastProgressAt=source.startedAt; source.lastRequestAt=0;
    if (source.readerMode) {
        // Keep the existing reader/pending sample on ordinary hide/show. Move
        // its host clock forward by the paused duration instead of reopening it.
        CFTimeInterval pause=source.pausedAt>0?MAX(0.0,CACurrentMediaTime()-source.pausedAt):0;
        CMTime resume=CMTIME_IS_NUMERIC(source.lastTime) ? source.lastTime : kCMTimeZero;
        dispatch_async(LMVFrameQueue, ^{
            if (source.reader) source.readerClock+=pause;
            else {source.readerClock=CACurrentMediaTime();source.readerOffset=resume;source.readerLastTarget=kCMTimeInvalid;}
        });
    } else {
        [source.output requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03];
        if (source.restoreOnStart && source.player.currentItem.status!=AVPlayerItemStatusReadyToPlay) return;
        if (!source.restoringTime && source.restoreOnStart && CMTIME_IS_NUMERIC(source.lastTime)) {
            source.restoreOnStart=NO; source.restoringTime=YES;
            NSUInteger epoch=source.generation;
            [source.player seekToTime:source.lastTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (source.generation!=epoch) {source.restoringTime=NO;return;}
                    source.restoringTime=NO;
                    if (finished && source.generation==epoch && source.playing && !source.readerMode && LMVSharedSources[source.registryKey]==source) {
                        source.restoreOnStart=NO; [source.player play];
                    } else source.restoreOnStart=CMTIME_IS_NUMERIC(source.lastTime);
                });
            }];
        } else if (!source.restoringTime) [source.player playImmediatelyAtRate:1.0];
    }
}
static void LMVStopSource(LMVSharedSource *source) {
    if (source && source.playing) {
        [source.player pause]; source.playing=NO; source.generation++;
        source.pausedAt=CACurrentMediaTime();
        if (source.restoringTime) source.restoreOnStart=CMTIME_IS_NUMERIC(source.lastTime);
        // A retained AVPlayer already keeps its current time when paused. Only
        // a cold/new player restoring a disk checkpoint needs an exact seek.
        LMVCheckpointFrame(source.path,source.revision);
        // Do not launch asynchronous pause-seeks that can flush the next startup.
    }
}
// 1.76: pause WITHOUT the checkpoint/generation churn of LMVStopSource. The
// retained AVPlayer already remembers its position, so a card that goes out of
// sight and comes back costs one play call instead of a checkpoint plus a
// restoring seek - which is the restart the user heard as a delay.
static void LMVSourcePause(LMVSharedSource *source) {
    if (!source || !source.playing) return;
    [source.player pause];
    source.playing=NO;
    source.pausedAt=CACurrentMediaTime();
    // The retained player keeps its exact position; a pending restore flag from
    // an older stop path must not turn the resume into a seek.
    source.restoreOnStart=NO;
}
static BOOL LMVSourceHasConsumer(LMVSharedSource *source) {    if (!source) return NO;
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
        for (NSString *target in states) {
            LMVVideoState *state=states[target];
            if (state.source==source && state.active && state.overlay.superview &&
                LMVCardStateVisible(cell,state,target)) return YES;
        }
    }
    return NO;
}
static void LMVReleasePlayer(LMVVideoState *state) {
    if (!state) return;
    LMVSharedSource *source=state.source;
    // Hiding/offscreen pauses consumption, NEVER clears the exact displayed frame.
    // This retained layer also survives source/property refresh without a blank gap.
    state.source=nil; state.active=NO;
    if (!LMVSourceHasConsumer(source)) LMVSourcePause(source);
}
static BOOL LMVSourceNeedsReaderRecovery(LMVSharedSource *source,CFTimeInterval now) {
    if(!source || !source.playing || source.readerMode || source.frameBusy)return NO;
    // 1.76.4: a cold source needs longer than 0.75 s for its first frame; firing the
    // reader fallback that early forced a decoder switch on every single open.
    CFTimeInterval limit=source.published?3.0:1.5;
    return source.player.currentItem.status==AVPlayerItemStatusFailed || now-source.lastProgressAt>=limit;
}
static void LMVRetireSource(LMVSharedSource *source) {
    if (!source) return;
    LMVStopSource(source); source.generation++;
    [source.output setDelegate:nil queue:NULL];
    // 1.76.5: -replaceCurrentItemWithPlayerItem: stops the item synchronously and
    // waits for the player to let go of it. On a material switch that call sat on the
    // main thread inside LMVPrepareAssets, right when the new file was being wired
    // up - the "switch stalls" moment. Hand the player over and tear it down one
    // runloop later, so the switch path no longer waits for it.
    AVPlayer *retiredPlayer=source.player;
    source.player=nil; source.output=nil;
    if (retiredPlayer) dispatch_async(dispatch_get_main_queue(), ^{
        [retiredPlayer replaceCurrentItemWithPlayerItem:nil];
    });
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
    for(LMVSharedSource *source in LMVSharedSources.allValues) {
        // 0.0.123: a shared source stays while ANY enabled category still
        // selects this exact file; retirement follows real demand, not the
        // category that happened to create it first.
        BOOL wanted=NO;
        for(NSString *candidate in LMVTargets()) {
            if(!LMVEnabled[candidate].boolValue) continue;
            if(![LMVPaths[candidate] isEqualToString:source.path]) continue;
            // 1.76.1: the key carries the channel now, so a source is wanted only
            // while THIS channel still selects the file. Matching the path alone
            // kept the previous channel's player alive after a switch - it was
            // wanted by a neighbour and never returned to service.
            NSString *key=LMVSourceRegistryKey(source.path,candidate);
            if([key isEqualToString:source.registryKey]){wanted=YES;break;}
        }
        if(!wanted) LMVRetireSource(source);
    }
    for (NSString *path in LMVSources.allKeys) {
        if (![wanted containsObject:path]) { [LMVSources removeObjectForKey:path]; [LMVAssets removeObjectForKey:path];  [LMVReadyAssets removeObject:path]; LMVInvalidateSourcesForPath(path); [LMVRevisions removeObjectForKey:path]; }
    }
    for (NSString *path in wanted) {
        NSString *revision = LMVFileRevision(path);
        if (LMVSources[path] && [LMVRevisions[path] isEqualToString:revision]) {
            LMVWarmSourcesForPath(path);continue;
        }
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
                LMVWarmSourcesForPath(path); // paused independent category chains prepared off the swipe event
                for (UIView *cell in LMVCells.allObjects) LMVUpdate(cell);
            });
            });
        }];
    }
}
static void LMVLoadPreferences(void) {
    CFTimeInterval probePrefs=CACurrentMediaTime();
    CFPreferencesAppSynchronize(kLMVPrefsID);
    NSNumber *diagnostics = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("DiagnosticsEnabled"), kLMVPrefsID);
    BOOL diagnosticsEnabled = [diagnostics respondsToSelector:@selector(boolValue)] && diagnostics.boolValue;
    BOOL wasEnabled = LMVDiagnosticsEnabled.exchange(diagnosticsEnabled);
    if (diagnosticsEnabled && !wasEnabled) {
        LMVDiagnosticEpoch.fetch_add(1);
        LMVDiagnostic([NSString stringWithFormat:@"version=%@ diagnostics-enabled",LMV_VERSION_STRING]);
    }
    LMVPaths = [NSMutableDictionary new];
    // These are semantic source names, kept independent from UIKit private class names.
    LMVMaterialSources = @{
        @"Message": @"message.mov",
        @"Options": @"options.mov",
        @"Clear": @"clear.mov"
    };
    LMVEnabled = [NSMutableDictionary new];
    // 0.0.123: master switch for the whole tweak, read inline so sliced test
    // fixtures need no extra symbol. Absent or non-number means ENABLED, so an
    // upgrade never changes an existing configuration; only an explicit NO
    // stops every channel.
    id globalValue = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"), kLMVPrefsID);
    BOOL globalOn = ![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue];
    for (NSString *target in LMVTargets()) {
        NSString *enabledKey = [target stringByAppendingString:@"BackgroundEnabled"];
        NSNumber *enabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue((__bridge CFStringRef)enabledKey, kLMVPrefsID);
        LMVEnabled[target] = @(globalOn && [enabled respondsToSelector:@selector(boolValue)] && enabled.boolValue);
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
    // Custom-alpha OFF means the video uses full opacity; BackgroundEnabled
    // separately controls whether its owned overlay exists at all.
    LMVOpacity = [opacity respondsToSelector:@selector(floatValue)] ? MAX(0.0, MIN(1.0, opacity.floatValue)) : 0.55;
    LMVPrepareAssets();
    LMVPerfProbe("prefs",probePrefs);
}
static BOOL LMVMessageCell(UIView *cell);
static BOOL LMVNotificationCenterSurface(UIView *view) {
    // Scope is attached model ownership, not a model hidden visibility veto.
    // Exposure (including window/ancestor presentation state) is checked below.
    if (!view.window || !([view isDescendantOfView:view.window] || view==view.window)) return NO;
    NSString *attachedWindowName=NSStringFromClass(view.window.class);
    if ([attachedWindowName containsString:@"ControlCenter"] || [attachedWindowName containsString:@"Secure"]) return NO;
    for (UIView *node = view; node; node = node.superview) {
        NSString *name = NSStringFromClass(node.class);
        Class card=NSClassFromString(@"NCNotificationListCell");
        if((card && [node isKindOfClass:card]) || [name containsString:@"NotificationCenter"] || [name containsString:@"CoverSheet"]) return YES;
    }
    NSString *windowName = NSStringFromClass(view.window.class);
    if ([windowName containsString:@"CoverSheet"] || [windowName containsString:@"NotificationCenter"]) return YES;
    for (UIViewController *controller = view.window.rootViewController; controller; controller = controller.presentedViewController) {
        NSString *name = NSStringFromClass(controller.class);
        if ([name containsString:@"CoverSheet"] || [name containsString:@"NotificationCenter"]) return YES;
    }
    return NO;
}
#import "LMVCardPresentation.h"
static BOOL LMVVisible(UIView *view) {
    if (!LMVPlaybackAllowed() || !LMVNotificationCenterSurface(view)) return NO;
    return LMVCardExposed(view);
}
static char LMVCardPipelineAuditKey;
static void LMVCardPipelineAudit(UIView *owner,LMVVideoState *state,NSString *target,UIView *anchor,NSString *stage) {
    if(!LMVDiagnosticsEnabled.load())return;
    NSMutableDictionary *records=objc_getAssociatedObject(owner,&LMVCardPipelineAuditKey);
    if(!records){records=[NSMutableDictionary new];objc_setAssociatedObject(owner,&LMVCardPipelineAuditKey,records,OBJC_ASSOCIATION_RETAIN_NONATOMIC);}
    NSString *key=[target stringByAppendingString:stage];CFTimeInterval now=CACurrentMediaTime();
    unsigned long epoch=LMVDiagnosticEpoch.load();NSArray *old=records[key];
    if(old && [old[0] unsignedLongValue]==epoch && now-[old[1] doubleValue]<.5)return;
    records[key]=@[@(epoch),@(now)];UIView *surface=state.overlay;UIWindow *window=owner.window;
    uint64_t blank=1;int blankStatus=LMVBlankToken<0?-1:notify_get_state(LMVBlankToken,&blank);
    BOOL ownerModel=LMVCardExposureInTree(owner,window,NO),surfaceModel=LMVCardExposureInTree(surface,window,NO);
    BOOL surfaceShown=LMVCardExposureInTree(surface,window,YES);
    NSString *line=[NSString stringWithFormat:@"card-pipeline target=%@ stage=%@ owner=%p anchor=%p state=%d scope=%d gate=%d blankStatus=%d blank=%llu alphaEnabled=%d alpha=%.3f ownerVisible=%d ownerCAWindow=%d ownerModel=%d ownerShown=%d anchorParent=%d attached=%d surfaceModel=%d surfaceShown=%d surfaceVisible=%d surfaceCAWindow=%d surfaceHidden=%d surfaceOpacity=%.3f surfaceSize=%.1fx%.1f active=%d source=%lu requested=%d published=%lu",
        target,stage,(__bridge void *)owner,(__bridge void *)anchor,state!=nil,LMVNotificationCenterSurface(owner),LMVPlaybackAllowed(),blankStatus,(unsigned long long)blank,LMVOpacityEnabled,LMVOpacity,LMVVisible(owner),LMVCardLayerAttached(owner.layer,window.layer),ownerModel,LMVCardExposureInTree(owner,window,YES),anchor.superview!=nil,LMVCardStateAttached(owner,state),surfaceModel,surfaceShown,LMVVisible(surface),LMVCardLayerAttached(surface.layer,window.layer),surface.hidden,surface.alpha,surface.bounds.size.width,surface.bounds.size.height,state.active,(unsigned long)state.source.identifier,state.source.playing,(unsigned long)state.source.published];
    LMVDiagnostic(line);
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
static UIView *LMVMessageMaterialCandidate(UIView *view, NSUInteger depth, BOOL visibleOnly) {
    if (depth > 12 || LMVActionBranch(view) || objc_getAssociatedObject(view, &LMVOwnershipKey)) return nil;
    if (visibleOnly && (view.hidden || LMVOriginalVisibilityAlpha(view) < 0.01)) return nil;
    if ([NSStringFromClass(view.class) containsString:@"MaterialView"] && view.bounds.size.width > 20 && view.bounds.size.height > 20) return view;
    for (UIView *child in view.subviews) {
        if (LMVIsClassOrSubclass(child, @"NCNotificationListCell")) continue;
        UIView *material = LMVMessageMaterialCandidate(child, depth + 1, visibleOnly);
        if (material) return material;
    }
    return nil;
}
static UIView *LMVMessageMaterial(UIView *view, NSUInteger depth) {
    // Visible replacement first; structural fallback seeds an alpha-zero or
    // hidden incoming card before its animation begins. Never enter our surface
    // or another notification card when searching this card's model ownership.
    UIView *visible=LMVMessageMaterialCandidate(view,depth,YES);
    return visible ?: LMVMessageMaterialCandidate(view,depth,NO);
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

static BOOL LMVCardHostsReady(UIView *cell) {
    NSMapTable *hosts=objc_getAssociatedObject(cell,&LMVHostsKey);
    for(NSString *target in LMVTargets()) {
        if(!LMVEnabled[target].boolValue || !LMVPaths[target])continue;
        if([target isEqualToString:@"Message"] && !LMVMessageCell(cell))continue;
        UIView *anchor=[hosts objectForKey:target];
        if(!anchor || !anchor.superview || !([anchor isDescendantOfView:cell] || anchor==cell))return NO;
    }
    return YES;
}
static void LMVRetryDiscovery(UIView *cell) {
    if (LMVCardHostsReady(cell) || objc_getAssociatedObject(cell, &LMVRetryKey)) return;
    NSObject *token=[NSObject new];
    objc_setAssociatedObject(cell, &LMVRetryKey, token, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakCell = cell;
    for (NSUInteger attempt = 1; attempt <= 4; attempt++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(attempt * 0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *owner = weakCell;
            if (!owner || objc_getAssociatedObject(owner,&LMVRetryKey)!=token) return;
            if (LMVCardHostsReady(owner)) {
                objc_setAssociatedObject(owner,&LMVRetryKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);return;
            }
            if (owner.window && LMVPlaybackAllowed()) LMVUpdate(owner);
        });
    }
}
static void LMVLayoutCardSurface(LMVVideoState *state, UIView *anchor, UIView *host) {
    // Synchronise only plugin geometry during the system's layout transaction.
    // No discovery, decoding, global refresh or changes to UIKit's card geometry.
    if (!state.layer || !anchor || !host || state.overlay.superview != host) return;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CGRect desiredFrame=[anchor convertRect:anchor.bounds toView:host];
    if (!CGAffineTransformIsIdentity(state.overlay.transform)) state.overlay.transform=CGAffineTransformIdentity;
    if (!CGRectEqualToRect(state.overlay.frame,desiredFrame)) state.overlay.frame=desiredFrame;
    state.overlay.autoresizingMask=UIViewAutoresizingNone;
    CGFloat radius=anchor.layer.cornerRadius;
    if (radius<=0) radius=MIN(20.0,MIN(anchor.bounds.size.width,anchor.bounds.size.height)*0.5);
    if (state.overlay.layer.cornerRadius!=radius) state.overlay.layer.cornerRadius=radius;
    state.overlay.layer.cornerCurve=kCACornerCurveContinuous;
    state.overlay.layer.maskedCorners=kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner|kCALayerMinXMaxYCorner|kCALayerMaxXMaxYCorner;
    state.overlay.layer.mask=nil;
    if (!CGRectEqualToRect(state.layer.frame,state.overlay.bounds)) state.layer.frame=state.overlay.bounds;
    if (state.layer.hidden) state.layer.hidden=NO;
    CGFloat desiredOpacity=LMVCardOpacity();
    if (state.overlay.alpha!=desiredOpacity) state.overlay.alpha=desiredOpacity;
    [CATransaction commit];
}

static void LMVUpdate(UIView *cell) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    CFTimeInterval probeUpdate=CACurrentMediaTime();
    NSMutableDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
    if (!states) { states = [NSMutableDictionary new]; objc_setAssociatedObject(cell, &LMVStatesKey, states, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    BOOL playbackAllowed=LMVPlaybackAllowed();
    if (!playbackAllowed) for (LMVVideoState *state in states.allValues) LMVReleasePlayer(state);
    // Display cached content even before the playback/screen visibility gate opens.
    BOOL visible = LMVVisible(cell);
    CFTimeInterval now = CACurrentMediaTime();
    objc_setAssociatedObject(cell,&LMVMaintenanceKey,@(now),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
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
        if (host && (!host.superview || !([host isDescendantOfView:cell] || host == cell))) {
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
    UIView *messageHost=[hosts objectForKey:@"Message"];
    if (messageEligible && messageHost && (messageHost.hidden || LMVOriginalVisibilityAlpha(messageHost)<0.01)) {
        UIView *incoming=LMVMessageMaterialCandidate(cell,0,YES);
        if (incoming && incoming!=messageHost) [hosts setObject:incoming forKey:@"Message"];
    }
    NSNumber *last = objc_getAssociatedObject(cell, &LMVDiscoveryKey);
    BOOL actionsSelected=(LMVEnabled[@"Options"].boolValue && LMVPaths[@"Options"]) ||
        (LMVEnabled[@"Clear"].boolValue && LMVPaths[@"Clear"]);
    BOOL refreshActions = actionsSelected && (!last || now - last.doubleValue >= 0.1);
    if (refreshActions) {
        [hosts removeObjectForKey:@"Options"]; [hosts removeObjectForKey:@"Clear"];
    }
    if ((missing || refreshActions) && (!last || now - last.doubleValue >= 0.1)) {
        objc_setAssociatedObject(cell, &LMVDiscoveryKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(actionsSelected) LMVActionHosts(cell, hosts, 0);
        for(NSString *target in @[@"Options",@"Clear"]) {
            LMVVideoState *bound=states[target];
            // Discovery can see model-hidden original material while the owned
            // sibling video is still presented. Do not throw away that live,
            // exact owner binding just because the material search found none.
            if(![hosts objectForKey:target] && LMVCardStateVisible(cell,bound,target))
                [hosts setObject:bound.anchor forKey:target];
        }
    }
    // Expansion can replace the message material just after the last action
    // search. A missing message binding must not wait for that 100ms throttle.
    if (messageEligible && LMVEnabled[@"Message"].boolValue && LMVPaths[@"Message"] && ![hosts objectForKey:@"Message"]) {
        UIView *material = LMVMessageMaterial(cell, 0);
        if (material) [hosts setObject:material forKey:@"Message"];
    }
    if (LMVDiagnosticsEnabled.load()) {
    static char discoveryDiagnosticKey;
    NSMutableString *discovery=[NSMutableString stringWithFormat:@"discovery visible=%d scope=%d ownerClass=%@ windowClass=%@",visible,LMVNotificationCenterSurface(cell),NSStringFromClass(cell.class),cell.window?NSStringFromClass(cell.window.class):@"none"];
    for (NSString *target in LMVTargets()) [discovery appendFormat:@" %@ enabled=%d selected=%d assetready=%d host=%d",target,LMVEnabled[target].boolValue,LMVPaths[target]!=nil,LMVReadyAssets && [LMVReadyAssets containsObject:LMVPaths[target] ?: @""],[hosts objectForKey:target]!=nil];
    NSString *previous=objc_getAssociatedObject(cell,&discoveryDiagnosticKey);
    if (![previous isEqualToString:discovery]) { objc_setAssociatedObject(cell,&discoveryDiagnosticKey,[discovery copy],OBJC_ASSOCIATION_RETAIN_NONATOMIC); LMVDiagnostic(discovery); }
    }
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
            LMVCardPipelineAudit(cell,state,target,anchor,@"no-anchor-parent");
            if (state && !state.detachedSince) state.detachedSince = now;
            if (state && state.overlay.superview && state.detachedSince && now - state.detachedSince < 0.18) continue;
            LMVPause(state); [state.overlay removeFromSuperview]; state.anchor = nil; continue;
        }
        state.detachedSince = 0;
        BOOL anchorVisible = visible && LMVVisible(anchor);
        if (anchorVisible) state.visibilityLossSince = 0;
        else if (state && !state.visibilityLossSince) state.visibilityLossSince = now;
        BOOL surfaceVisible=state && LMVCardStateVisible(cell,state,target);
        if (!anchorVisible && !surfaceVisible && (!state.visibilityLossSince || now - state.visibilityLossSince >= 0.18)) LMVReleasePlayer(state);
        if (!state) {
            // The material remains underneath until a real decoded frame is available.
            state = [LMVVideoState new]; state.path = path;
            state.revision = LMVRevisions[path];
            state.overlay = [UIView new]; state.overlay.userInteractionEnabled = NO;
            state.overlay.clipsToBounds = YES;
                    states[target] = state;
        }
        if (state.source && LMVSharedSources[LMVSourceRegistryKey(path,target)] != state.source) LMVReleasePlayer(state);
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
            // 0.0.90: stable layer names make this surface identifiable from a
            // hierarchy dump. Names are diagnostic only and never affect
            // rendering; without them a dump cannot tell the card overlay apart
            // from the other UIViews in SpringBoard.
            state.overlay.layer.name=@"com.minis.lockmessagevideo.card.surface";
            state.layer.name=@"com.minis.lockmessagevideo.card.render";
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
        LMVLayoutCardSurface(state,anchor,host);
        [CATransaction commit];
        // Lease depends on enabled + selected + target scope, never decoder,
        // first frame, alpha or active consumption. Cold absence stays transparent.
        // Enabled+selected replacement follows the attached target owner, not
        // video opacity or action-scroll visibility during an animation.
        BOOL originalInScope = LMVOriginalTargetInScope(cell,anchor,host);
        if ([target isEqualToString:@"Message"]) {
            // A stack animation changes alpha/hidden before presentation ends.
            // Keep only this attached card's model-owned background replaced;
            // visibility still gates frame consumption, never its lease.
            originalInScope = LMVNotificationCenterSurface(cell) && anchor.superview &&
                [anchor isDescendantOfView:cell] && (host == anchor || host == anchor.superview);
        }
        // Screen blank pauses frames but does not change an attached target lease.
        if (!playbackAllowed && state.originals.count && cell.window &&
            state.originalAnchor == anchor && state.originalScope == host) originalInScope = YES;
        LMVReplaceBackground(state, anchor, host, target, originalInScope);
        state.active=playbackAllowed && LMVCardOpacity()>0.0 &&
            LMVCardStateVisible(cell,state,target);
        if (anchorVisible) state.lastVisible = now;
        // Owned content, geometry, opacity and corners are assigned before startup.
        if (!state.source && state.active) { state.source=LMVSourceForTarget(path,target); reportGeometry=state.source!=nil; }
        if (reportGeometry) LMVDiagnostic([NSString stringWithFormat:@"bind source=%lu target=%@ visible=%d active=%d anchor=%.1fx%.1f overlay=%.1fx%.1f",(unsigned long)state.source.identifier,target,anchorVisible,state.active,anchor.bounds.size.width,anchor.bounds.size.height,state.overlay.bounds.size.width,state.overlay.bounds.size.height]);
        // Use this category's retained live frame, not another category's latest
        // same-file cache position, whenever a card joins its shared source.
        if(state.source.lastImage && state.layer.contents!=(__bridge id)state.source.lastImage) {
            [CATransaction begin];[CATransaction setDisableActions:YES];
            state.layer.contents=(__bridge id)state.source.lastImage;[CATransaction commit];
        }
        if (state.active && state.source) LMVStartSource(state.source);
        else if (state.source && !LMVSourceHasConsumer(state.source)) LMVStopSource(state.source);
        LMVCardPipelineAudit(cell,state,target,anchor,@"bound");
    }
    LMVPerfProbe("update",probeUpdate);
    LMVRequestSyncDisplayLink();
}
// O(existing bindings): visibility transitions do not wait for a default-mode
// timer, full preference refresh, or material-discovery maintenance interval.
static void LMVReconcileCardSources(UIView *cell) {
    if(!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread)return;
    NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
    BOOL changed=NO,allowed=LMVPlaybackAllowed() && LMVCardOpacity()>0;
    for(NSString *target in states) {
        LMVVideoState *state=states[target];
        BOOL active=allowed && LMVCardStateVisible(cell,state,target);
        if(state.active!=active){changed=YES;state.active=active;}
        if(active) {
            if(!state.source){state.source=LMVSourceForTarget(state.path,target);changed=YES;}
            if(state.source)LMVStartSource(state.source);
            state.lastVisible=CACurrentMediaTime();
        } else if(state.source && !LMVSourceHasConsumer(state.source))LMVSourcePause(state.source);
    }
    if(changed)LMVRequestSyncDisplayLink();
}
static BOOL LMVPrimeMessageCard(UIView *cell) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread || LMVPreferencesDirty ||
        !LMVMessageCell(cell) || !LMVEnabled[@"Message"].boolValue || !LMVPaths[@"Message"]) return NO;
    static BOOL priming=NO;
    if (priming) return NO;
    NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
    NSMapTable *hosts=objc_getAssociatedObject(cell,&LMVHostsKey);
    LMVVideoState *state=states[@"Message"];
    UIView *anchor=[hosts objectForKey:@"Message"];
    BOOL attached=anchor && anchor.superview && [anchor isDescendantOfView:cell];
    BOOL needsBinding=!attached || !state.layer || state.anchor!=anchor || !state.host ||
        !(state.host==anchor || state.host==anchor.superview) || state.overlay.superview!=state.host ||
        ![state.path isEqualToString:LMVPaths[@"Message"]];
    // UIKit may write the material's opacity at the start/end of the stack
    // animation. Revalidate through the guarded replacement path before commit.
    if (LMVOriginalBackgroundNeedsMaintenance(state)) needsBinding=YES;
    if (anchor && (anchor.hidden || LMVOriginalVisibilityAlpha(anchor)<0.01)) {
        UIView *incoming=LMVMessageMaterialCandidate(cell,0,YES);
        if (incoming && incoming!=anchor) needsBinding=YES;
    }
    priming=YES;
    @try {
        if (needsBinding) LMVUpdate(cell);
        else {LMVLayoutCardSurface(state,anchor,state.host);LMVReconcileCardSources(cell);}
    } @finally { priming=NO; }
    return needsBinding;
}
%hook NCNotificationListCell
- (void)layoutSubviews {
    %orig;
    if (!LMVInitialized) return;
    [LMVCells addObject:(UIView *)self];
    LMVPrimeMessageCard((UIView *)self);
    LMVRequestCardUpdate((UIView *)self,NO);
}
- (void)didMoveToWindow {
    %orig;
    if (!LMVInitialized) return;
    [LMVCells addObject:(UIView *)self];
    LMVPrimeMessageCard((UIView *)self);
    LMVRequestCardUpdate((UIView *)self,NO);
}
- (void)prepareForReuse {
    LMVForgetCardUpdate((UIView *)self);
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
static void LMVPrimeActionBackgrounds(UIView *presenter) {
    if(!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread || LMVPreferencesDirty)return;
    UIView *owner=presenter.superview;Class cellClass=NSClassFromString(@"NCNotificationListCell");
    while(owner && (!cellClass || ![owner isKindOfClass:cellClass]))owner=owner.superview;
    owner=owner ?: presenter;
    NSDictionary *states=objc_getAssociatedObject(owner,&LMVStatesKey);
    for(NSString *target in @[@"Options",@"Clear"]) {
        LMVVideoState *state=states[target];
        BOOL selected=LMVEnabled[target].boolValue && LMVPaths[target] && [state.path isEqualToString:LMVPaths[target]];
        LMVMaintainOriginalBackground(state,owner,target,selected);
    }
    LMVReconcileCardSources(owner);
}
%hook PLActionButtonsPresentingView
- (void)layoutSubviews {
    %orig;
    if (!LMVInitialized || !NSThread.isMainThread) return;
    [LMVActionPresenters addObject:(UIView *)self];
    LMVPrimeActionBackgrounds((UIView *)self);
    LMVRequestCardUpdate((UIView *)self,YES);
}
- (void)didMoveToWindow {
    %orig;
    if (!LMVInitialized || !NSThread.isMainThread) return;
    [LMVActionPresenters addObject:(UIView *)self];
    LMVPrimeActionBackgrounds((UIView *)self);
    LMVRequestCardUpdate((UIView *)self,YES);
}
%end
static NSTimer *LMVAudioTimer;
static BOOL LMVAudioLayerExposed(CALayer *layer,UIWindow *window) {
    if(!layer || !window || window.hidden || !layer.superlayer || layer.hidden)return NO;
    CALayer *paint=layer.presentationLayer ?: layer,*root=window.layer.presentationLayer ?: window.layer;
    CGRect rect=[paint convertRect:paint.bounds toLayer:root];CGFloat opacity=1;NSUInteger depth=0;
    for(CALayer *node=paint;node && ++depth<=48;node=node.superlayer) {
        if(node.hidden)return NO;opacity*=node.opacity;if(!isfinite(opacity) || opacity<.01)return NO;
        if(node.masksToBounds)rect=CGRectIntersection(rect,[node convertRect:node.bounds toLayer:root]);
        if(node==root)break;
    }
    return !CGRectIsEmpty(CGRectIntersection(rect,LMVVideoWindowViewport(window)));
}
static void LMVSyncAudioVisibility(void) {
    if(!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread)return;
    if(!LMVPlaybackAllowed()){LMVAudioPauseAll();return;}
    for(NSString *target in LMVTargets()) {
        LMVSharedSource *source=nil;BOOL exposed=NO;
        for(UIView *cell in LMVCells.allObjects) {
            LMVVideoState *state=((NSDictionary *)objc_getAssociatedObject(cell,&LMVStatesKey))[target];
            if(state.active && state.source && state.layer.contents && LMVCardStateVisible(cell,state,target))
                {source=state.source;exposed=YES;break;}
        }
        LMVAudioConsume(target,source.path,source.revision,exposed,source?source.lastTime:kCMTimeZero);
    }
    LMVLockVideoPlayback *lock=LMVLockVideo.playback;
    BOOL lockVisible=lock.wantsPlayback && !lock.frozen && !LMVLockVideo.host.hidden &&
        LMVAudioLayerExposed(lock.renderLayer,LMVLockVideo.host.window);
    LMVAudioConsume(@"LockScreen",lock.path,lock.revision,lockVisible,lock.player.currentTime);
    LMVLockVideoPlayback *desktop=LMVDesktopVideo.playback;
    // 0.0.133: the video may keep PLAYING under a translucent cover at fg==1
    // (the instant-reveal feel), but the sound follows the COVER, not the
    // player state - off whenever anything covers the desktop.
    // 2.74: THE SWITCH IS PART OF VISIBILITY. The player keeps wantsPlayback after a
    // switch-off (its state is intentionally preserved), so the old test left the
    // separate audio player running - the reported "关掉开关还漏一下声音".
    id desktopPref=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("DesktopBackgroundEnabled"),kLMVPrefsID);
    id globalPref=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
    BOOL desktopOn=(![globalPref isKindOfClass:NSNumber.class] || [globalPref boolValue]) &&
        [desktopPref isKindOfClass:NSNumber.class] && [desktopPref boolValue];
    BOOL desktopVisible=desktopOn && desktop.wantsPlayback && !desktop.frozen && !LMVDesktopVideo.host.hidden &&
        !LMVDesktopVideo.coveredNow && LMVAudioLayerExposed(desktop.renderLayer,LMVDesktopVideo.host.window);
    LMVAudioConsume(@"Desktop",desktop.path,desktop.revision,desktopVisible,desktop.player.currentTime);
    LMVLockVideoPlayback *cc=LMVControlCenterVideo.playback;
    BOOL ccVisible=LMVControlCenterVideo.presented && cc.wantsPlayback && !cc.frozen &&
        LMVAudioLayerExposed(cc.renderLayer,LMVControlCenterVideo.material.window);
    BOOL dark=LMVControlCenterVideo.style==UIUserInterfaceStyleDark;
    LMVAudioConsume(@"ControlCenterDark",cc.path,cc.revision,ccVisible && dark,cc.player.currentTime);
    LMVAudioConsume(@"ControlCenterLight",cc.path,cc.revision,ccVisible && !dark,cc.player.currentTime);
    LMVLockVideoPlayback *menu=LMVHomeMenuVideo.playback;
    BOOL menuVisible=menu.wantsPlayback && !LMVHomeMenuVideo.host.hidden &&
        LMVAudioLayerExposed(menu.renderLayer,LMVHomeMenuVideo.host.window);
    LMVAudioConsume(@"HomeMenu",menu.path,menu.revision,menuVisible,menu.player.currentTime);
    LMVLockVideoPlayback *panel=LMVSquidPanelVideo.playback;
    BOOL panelVisible=panel.wantsPlayback && !LMVSquidPanelVideo.host.hidden &&
        LMVAudioLayerExposed(panel.renderLayer,LMVSquidPanelVideo.host.window);
    LMVAudioConsume(@"SquidPanel",panel.path,panel.revision,panelVisible,panel.player.currentTime);
    LMVLockVideoPlayback *atPanel=LMVATPanelVideo.playback;
    BOOL atPanelVisible=atPanel.wantsPlayback && !LMVATPanelVideo.host.hidden &&
        LMVAudioLayerExposed(atPanel.renderLayer,LMVATPanelVideo.host.window);
    LMVAudioConsume(@"AT",atPanel.path,atPanel.revision,atPanelVisible,atPanel.player.currentTime);
    LMVLockVideoPlayback *paPanel=LMVPhoneAssistVideo.playback;
    BOOL paPanelVisible=paPanel.wantsPlayback && !LMVPhoneAssistVideo.host.hidden &&
        LMVAudioLayerExposed(paPanel.renderLayer,LMVPhoneAssistVideo.host.window);
    LMVAudioConsume(@"PA",paPanel.path,paPanel.revision,paPanelVisible,paPanel.player.currentTime);
    LMVLockVideoPlayback *gsPanel=LMVGlassSuiteVideo.playback;
    BOOL gsPanelVisible=gsPanel.wantsPlayback && !LMVGlassSuiteVideo.host.hidden &&
        LMVAudioLayerExposed(gsPanel.renderLayer,LMVGlassSuiteVideo.host.window);
    LMVAudioConsume(@"GS",gsPanel.path,gsPanel.revision,gsPanelVisible,gsPanel.player.currentTime);
    LMVLockVideoPlayback *ccbPanel=LMVCCBorderVideo.playback;
    BOOL ccbPanelVisible=ccbPanel.wantsPlayback && !LMVCCBorderVideo.host.hidden &&
        LMVAudioLayerExposed(ccbPanel.renderLayer,LMVCCBorderVideo.host.window);
    LMVAudioConsume(@"CCBorder",ccbPanel.path,ccbPanel.revision,ccbPanelVisible,ccbPanel.player.currentTime);
    LMVLockVideoPlayback *clxPanel=LMVCopyLogXVideo.playback;
    BOOL clxPanelVisible=clxPanel.wantsPlayback && !LMVCopyLogXVideo.host.hidden &&
        LMVAudioLayerExposed(clxPanel.renderLayer,LMVCopyLogXVideo.host.window);
    LMVAudioConsume(@"CopyLogX",clxPanel.path,clxPanel.revision,clxPanelVisible,clxPanel.player.currentTime);
    LMVLockVideoPlayback *myrtle=LMVMyrtlePanelVideo.playback;
    BOOL myrtleVisible=myrtle.wantsPlayback && !LMVMyrtlePanelVideo.host.hidden &&
        LMVAudioLayerExposed(myrtle.renderLayer,LMVMyrtlePanelVideo.host.window);
    LMVAudioConsume(@"Myrtle",myrtle.path,myrtle.revision,myrtleVisible,myrtle.player.currentTime);
    LMVLockVideoPlayback *cvPanel=LMVCopyVaultPanelVideo.playback;
    BOOL cvPanelVisible=cvPanel.wantsPlayback && !LMVCopyVaultPanelVideo.host.hidden &&
        LMVAudioLayerExposed(cvPanel.renderLayer,LMVCopyVaultPanelVideo.host.window);
    LMVAudioConsume(@"CV",cvPanel.path,cvPanel.revision,cvPanelVisible,cvPanel.player.currentTime);
}
static void LMVReloadAudioControls(void) {
    LMVAudioReload();
    if(LMVAudioAnyEnabled() && !LMVAudioTimer) {
        // 1.32: 10 Hz -> 4 Hz. This timer is the STEADY-STATE audio sync: it walks
        // every target, then every cell for every target, and touches AVPlayer
        // state for each enabled channel. It is NOT what makes a resume fast - the
        // direct pause/resume hooks and the coveredNow flip do that, with no timer
        // beat in either direction. It only reconciles drift and visibility, so at
        // 4 Hz it still corrects a stale channel well inside a quarter second while
        // removing 60% of the calls, the associated-object lookups and the player
        // property traffic from every second the tweak is loaded.
        LMVAudioTimer=[NSTimer timerWithTimeInterval:.25 repeats:YES block:^(NSTimer *timer){LMVSyncAudioVisibility();}];
        [NSRunLoop.mainRunLoop addTimer:LMVAudioTimer forMode:NSRunLoopCommonModes];
    } else if(!LMVAudioAnyEnabled()) {[LMVAudioTimer invalidate];LMVAudioTimer=nil;LMVAudioPauseAll();}
}
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
        LMVLoadPreferences();LMVReloadAudioControls();
    }
    [LMVDirtyCards removeAllObjects];[LMVDirtyPresenters removeAllObjects];
    LMVLockVideoRefresh(reload);
    LMVDesktopVideoRefresh(reload);
    LMVCCRefresh(reload);
    LMVHomeMenuVideoRefresh(reload);
    LMVSquidPanelVideoRefresh(reload);
    LMVATPanelVideoRefresh(reload);
    // 2.33: CopyLogX refreshes FIRST, so the PA channel already knows whether this
    // channel is able to paint before it decides to stand down on that card.
    LMVCopyLogXVideoRefresh(reload);
    LMVPhoneAssistVideoRefresh(reload);
    LMVGlassSuiteVideoRefresh(reload);
    LMVCCBorderVideoRefresh(reload);
    LMVCopyVaultPanelVideoRefresh(reload);
    LMVMyrtlePanelVideoRefresh(reload);
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
    LMVRequestSyncDisplayLink();
}
// 3.05: refresh ONE channel. Every branch above is a full sweep; a per-channel
// notification must not pay for the other twelve. Unknown targets fall back to the
// full refresh, so a name that is not mapped here can never go stale.
static void LMVRefreshChannel(NSString *target, BOOL reload) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    if (reload) { LMVLoadPreferences(); LMVReloadAudioControls(); }
    if ([target isEqualToString:@"LockNC"] || [target isEqualToString:@"LockScreen"]) LMVLockVideoRefresh(reload);
    else if ([target isEqualToString:@"Desktop"]) LMVDesktopVideoRefresh(reload);
    else if ([target isEqualToString:@"CC"] || [target isEqualToString:@"ControlCenterDark"] || [target isEqualToString:@"ControlCenterLight"]) LMVCCRefresh(reload);
    else if ([target isEqualToString:@"HomeMenu"]) LMVHomeMenuVideoRefresh(reload);
    else if ([target isEqualToString:@"SquidPanel"]) LMVSquidPanelVideoRefresh(reload);
    else if ([target isEqualToString:@"AT"]) LMVATPanelVideoRefresh(reload);
    else if ([target isEqualToString:@"CopyLogX"]) LMVCopyLogXVideoRefresh(reload);
    else if ([target isEqualToString:@"PA"]) LMVPhoneAssistVideoRefresh(reload);
    else if ([target isEqualToString:@"GS"]) LMVGlassSuiteVideoRefresh(reload);
    else if ([target isEqualToString:@"CCBorder"]) LMVCCBorderVideoRefresh(reload);
    else if ([target isEqualToString:@"CV"]) LMVCopyVaultPanelVideoRefresh(reload);
    else if ([target isEqualToString:@"Myrtle"]) LMVMyrtlePanelVideoRefresh(reload);
    else if ([target isEqualToString:@"Bubble"]) { if (LMVEaster) [LMVEaster refresh]; }
    else { LMVRefresh(reload); return; }
    LMVRequestSyncDisplayLink();
}
// Tracking mode suppresses default-mode timers and scrolling does not relayout every cell.
// Only visibility/readiness/host identity transitions invoke the heavier layout path.
@interface LMVDisplayLinkTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end
static void LMVSuspend(void) {
    LMVAudioPauseAll();
    LMVLockVideoSuspend();
    LMVDesktopVideoSuspend();
    LMVCCSuspend();
    LMVHomeMenuVideoSuspend();
    LMVSquidPanelVideoSuspend();
    LMVATPanelVideoSuspend();
    LMVPhoneAssistVideoSuspend();
    LMVGlassSuiteVideoSuspend();
    LMVCCBorderVideoSuspend();
    LMVCopyLogXVideoSuspend();
    LMVCopyVaultPanelVideoSuspend();
    LMVMyrtlePanelVideoSuspend();
    LMVReleaseAllPlayers();
}
// 1.76.5: LMVUpdate ends by calling LMVSyncDisplayLink, and LMVUpdate is itself
// called in a `for (cell in LMVCells)` loop - six cards meant six full "do we need
// a display link" sweeps of every cell and every target for one user action. Fold
// them into one pass per runloop: the link is created at most one frame later,
// which is invisible, and the sweep count drops from O(cells^2) to O(1) per batch.
static BOOL LMVSyncCheckScheduled;
static void LMVSyncDisplayLink(void);   // defined below; the request trampoline needs it
static void LMVRequestSyncDisplayLink(void) {
    if (LMVSyncCheckScheduled) return;
    LMVSyncCheckScheduled=YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        LMVSyncCheckScheduled=NO;
        LMVSyncDisplayLink();
    });
}
static void LMVSyncDisplayLink(void) {
    if (!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread) return;
    BOOL needed=NO;
    if (LMVPlaybackAllowed() && LMVCardOpacity()>0) {
        for (UIView *cell in LMVCells.allObjects) {
            NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
            BOOL exposed=LMVVisible(cell);
            for(NSString *target in states) if(LMVCardStateVisible(cell,states[target],target)){exposed=YES;break;}
            if (!exposed && !LMVCardColdProbe(cell,states)) continue;
            // Observe readiness even before a source/overlay/frame exists.
            for (NSString *target in LMVTargets()) {
                if (LMVEnabled[target].boolValue && LMVPaths[target]) { needed=YES; break; }
            }
            if (needed) break;
        }
    }
    static NSInteger lastNeeded=-1;static unsigned long lastAuditEpoch=0;
    unsigned long epoch=LMVDiagnosticEpoch.load();
    if (lastNeeded!=(NSInteger)needed || (LMVDiagnosticsEnabled.load() && lastAuditEpoch!=epoch)) {
        lastNeeded=needed;lastAuditEpoch=epoch;
        LMVDiagnostic([NSString stringWithFormat:@"displaylink-needed=%d cells=%lu alpha-enabled=%d alpha=%.3f link=%d",needed,(unsigned long)LMVCells.count,LMVOpacityEnabled,LMVOpacity,LMVLink!=nil]);
    }
    if (!needed) {
        // Stopping frame scheduling pauses sources and retains exact displayed frames.
        for (LMVSharedSource *source in LMVSharedSources.allValues) LMVStopSource(source); [LMVLink invalidate]; LMVLink=nil; return; }
    if (LMVLink) return;
    LMVDisplayLinkTarget *target=[LMVDisplayLinkTarget new];
    LMVLink=[CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
    // 2.48: the card link's cadence is a setting now (设置 → 自定义参数 → 通知卡片).
    NSInteger cardFPS=LMVTuneValue(@"Cards",@"FPS");
    // 2.99: the floor is 1 Hz now (was 15), matching the row's range.
    if (cardFPS<1) cardFPS=1;
    if (cardFPS>60) cardFPS=60;
    LMVTuneReport(@"Cards",@"FPS",cardFPS);
    LMVLink.preferredFramesPerSecond=cardFPS;
    LMVDiagnostic([NSString stringWithFormat:@"cards-cadence setting=%ld link=%ld",
        (long)cardFPS,(long)LMVLink.preferredFramesPerSecond]);
    [LMVLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
#import "LMVCardMaintenance.h"

@implementation LMVDisplayLinkTarget
- (void)tick:(CADisplayLink *)link {
    if (!LMVPlaybackAllowed()) { LMVSuspend(); return; }
    // Visibility is separate from frame conversion; never rediscover/layout every card per frame.
    NSMutableSet<LMVSharedSource *> *visible=[NSMutableSet new];
    NSUInteger consumers=0;
    CFTimeInterval now=CACurrentMediaTime();
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
        BOOL cellVisible=LMVVisible(cell), changed=NO;
        for (NSString *target in states) {
            LMVVideoState *state=states[target];
            BOOL active=LMVCardOpacity()>0.0 &&
                LMVCardStateVisible(cell,state,target);
            if (LMVDiagnosticsEnabled.load() && now-state.exposureDiagnosticAt>=.5) {
                state.exposureDiagnosticAt=now;
                NSString *status=[NSString stringWithFormat:@"card-exposure target=%@ active=%d scope=%d attached=%d owner=%d anchor=%d overlay=%d layerAttached=%d source=%lu playing=%d published=%lu",
                    target,active,LMVNotificationCenterSurface(cell),LMVCardStateAttached(cell,state),
                    LMVVisible(cell),LMVVisible(state.anchor),LMVVisible(state.overlay),
                    LMVCardLayerAttached(state.overlay.layer,cell.window.layer),
                    (unsigned long)state.source.identifier,state.source.playing,(unsigned long)state.source.published];
                if(![status isEqualToString:state.exposureDiagnostic]){state.exposureDiagnostic=status;LMVDiagnostic(status);}
            }
            if (active!=state.active) changed=YES;
            state.active=active;
        }
        if (changed || (cellVisible && LMVCardNeedsUpdate(cell,now))) LMVUpdate(cell);
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
        // 1.76.4: a busy global gate means the FRAME QUEUE is occupied, not that this
        // source stalled. Without this, one slow conversion starves the other
        // channels for three seconds and demotes all of them to the reader path at
        // once - the exact "all three froze together" pattern in the device log.
        if (!LMVFrameBusy && LMVSourceNeedsReaderRecovery(source,now)) {
            // Cached restore must not veto recovery forever on failed/not-ready
            // items or a seek completion that never arrives. Preserve its PTS for reader.
            source.restoreOnStart=NO;source.restoringTime=NO;
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
        if (LMVDiagnosticsEnabled.load()) {
        NSString *phase=[NSString stringWithFormat:@"owner=%@ mode=%@ requested=%d playerstatus=%ld itemstatus=%ld ready=%d timestatus=%ld rate=%.2f item=%d outputawake=%d mappedvalid=%d timevalid=%d",source.ownerTarget,source.readerMode?@"shared-reader":@"shared-output",source.playing,(long)source.player.status,(long)item.status,item.status==AVPlayerItemStatusReadyToPlay,(long)source.player.timeControlStatus,source.player.rate,item!=nil,source.outputAwake,mappedTimeValid,CMTIME_IS_NUMERIC(time)];
        BOOL transition=![source.diagnosticState isEqualToString:phase];
        if (transition || (now-source.lastDiagnosticAt>=2 && now-source.startedAt<30)) {
            source.diagnosticState=phase; source.lastDiagnosticAt=now;
            LMVDiagnostic([NSString stringWithFormat:@"source=%lu %@ newframes=%lu buffers=%lu conversion=%lu conversionerrors=%lu published=%lu discard=%lu errorcode=%ld",(unsigned long)source.identifier,phase,(unsigned long)source.newFrames,(unsigned long)source.buffers,(unsigned long)source.conversions,(unsigned long)source.conversionErrors,(unsigned long)source.published,(unsigned long)source.drops,(long)item.error.code]);
        }
        }
    }
    nextSource++;
    LMVRequestSyncDisplayLink();
}
@end
static void LMVDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // 3.05: a suffixed name means "only this channel changed". The unsuffixed one is a
    // genuinely global write and still refreshes everything. videoChanged has no
    // channel in its name (it is the shared import path) and keeps the full refresh.
    NSString *note=name ? (__bridge NSString *)name : @"";
    NSString *channelPrefix=@"com.minis.lockmessagevideo/preferencesChanged.";
    NSString *changedTarget=[note hasPrefix:channelPrefix] ? [note substringFromIndex:channelPrefix.length] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!LMVInitialized) return;
        // 2.74: SILENCE ON THE SAME RUN-LOOP TURN. The audio channel is a SEPARATE
        // player and used to stop only on its next sync pass, so flipping either
        // switch let a moment of sound through ("关闭的一瞬间漏一下"). Reading the two
        // switches here is two CFPreferences lookups - cheaper than one frame - and
        // the pause is immediate.
        id globalPref=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        BOOL globalOn=![globalPref isKindOfClass:NSNumber.class] || [globalPref boolValue];
        if (!globalOn) {
            LMVAudioPauseAll();
        } else {
            id desktopPref=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("DesktopBackgroundEnabled"),kLMVPrefsID);
            BOOL desktopOn=[desktopPref isKindOfClass:NSNumber.class] && [desktopPref boolValue];
            if (!desktopOn) LMVAudioPauseTarget(@"Desktop");
        }
        if (changedTarget.length) {
            // One channel: skip the global sweep entirely.
            LMVRefreshChannel(changedTarget, YES);
        } else {
            LMVPreferencesDirty = YES;
            LMVRequestSafeUpdate();
        }
    });
}
static void LMVScreenNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!LMVInitialized || !LMVLaunchReady) return;
        // A blank notification can be queued immediately before unlock. Read
        // the CURRENT state on the UI turn; never apply an obsolete blank value
        // that would hide Home just as it is being revealed.
        uint64_t blank=1;
        BOOL blanked=LMVBlankToken>=0 && notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK && blank;
        if (blanked) LMVDesktopVideoScreenBlank();
        if (!LMVPlaybackAllowed()) LMVSuspend();
        else {LMVDesktopVideoScreenChanged();LMVPrepareAssets();}
        LMVRequestSafeUpdate();
    });
}
// 2.60: event-driven detection for the eight panel channels. They used to learn
// "a panel just appeared" only from their ProbeHz timers, so a mount could wait a
// whole beat (200 ms at the default 5 Hz) before it even looked at the screen - the
// "面板先出来、视频后出来" half-beat. This adds no steady-state CPU: the timers are
// untouched and still do all teardown; only a window/scene appearance event runs
// one extra pass. Those events arrive in bursts, so the pass is coalesced onto a
// single main-queue turn (eight Refresh calls per notification would be waste).
static BOOL LMVPanelKickQueued = NO;
static void LMVPanelAppearKick(void) {
    if (!LMVInitialized || !LMVLaunchReady) return;
    if (LMVPanelKickQueued) return;
    LMVPanelKickQueued = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        LMVPanelKickQueued = NO;
        // Diagnostic-first: one line per process, so a device log proves the event
        // path fired at all (versus everything still riding the 5 Hz timer).
        static BOOL kickLoggedOnce = NO;
        if (!kickLoggedOnce) { kickLoggedOnce = YES; LMVDiagnostic(@"event-kick: panel-appearance pass dispatched"); }
        LMVSquidPanelVideoRefresh(NO);
        LMVATPanelVideoRefresh(NO);
        LMVPhoneAssistVideoRefresh(NO);
        LMVGlassSuiteVideoRefresh(NO);
        LMVCCBorderVideoRefresh(NO);
        LMVCopyLogXVideoRefresh(NO);
        LMVCopyVaultPanelVideoRefresh(NO);
        LMVMyrtlePanelVideoRefresh(NO);
        LMVHomeMenuVideoRefresh(NO);
    });
}
// 3.07: CHEAP CHANGE PROBE for the channels that carry no hook. 鱿鱼/AT/CopyVault/
// Myrtle/电话助手/CCBorder have a hard project rule against runtime method hooks
// (tests forbid class_getInstanceMethod there - previous attempts destabilised
// SpringBoard), so instead a 30 Hz display link computes a SIGNATURE of the window
// layer that only costs "windows x subview count" - no tree walk, no class checks.
// When the signature changes, the existing coalesced pass runs at once. That is the
// moment a panel is added, so the video mounts immediately and ProbeHz can stay low.
static CADisplayLink *LMVPanelPresenceLink;
static NSUInteger LMVPanelPresenceSignature;

static NSInteger LMVPanelPresenceHz(void) {
    NSInteger hz = LMVTuneValue(@"Global", @"PresenceHz");
    if (hz < 5) hz = 5;
    if (hz > 60) hz = 60;
    // 3.09: report the value that is actually driving the display link, so the row
    // shows 当前生效 instead of “未上报”; one line per change, like the other cadence
    // rows.
    static NSInteger reportedHz = -1;
    if (reportedHz != hz) {
        reportedHz = hz;
        LMVTuneReport(@"Global", @"PresenceHz", hz);
    }
    return hz;
}

// 3.08: DEPTH MATTERS. CopyVault's panel is a card nested inside CVPanelWindow
// (window -> transition view -> card), so counting only a window's DIRECT subviews
// missed it entirely - that channel still looked slow. Depth 3 with a hard budget
// keeps the cost at roughly "windows x 3" reads.
static void LMVPanelSignatureIn(UIView *view, NSInteger depth, NSInteger *budget, NSUInteger *signature) {
    if (!view || depth > 3 || *budget <= 0) return;
    (*budget)--;
    *signature = *signature * 31 + (NSUInteger)(uintptr_t)(__bridge void *)view;
    *signature = *signature * 31 + view.subviews.count;
    *signature = *signature * 31 + (view.hidden ? 1u : 0u);
    *signature = *signature * 31 + ((NSUInteger)(view.alpha * 100) & 0xffu);
    for (UIView *child in view.subviews)
        LMVPanelSignatureIn(child, depth + 1, budget, signature);
}

static NSUInteger LMVPanelComputeSignature(void) {
    NSUInteger signature = 0;
    NSInteger budget = 600;   // hard ceiling: a pathological tree costs at most this
    // Shared snapshot (80 ms default): the enumeration is amortised across all callers.
    for (UIWindow *window in LMVProbeAllWindows()) {
        LMVPanelSignatureIn(window, 0, &budget, &signature);
        if (budget <= 0) break;
    }
    return signature;
}

static void LMVPanelPresenceTick(CADisplayLink *link) {
    if (!LMVInitialized || !LMVLaunchReady) return;
    // 3.08: the rate is a setting now - apply it without waiting for a respring.
    static CFTimeInterval lastRateCheck;
    CFTimeInterval rateNow = CACurrentMediaTime();
    if (rateNow - lastRateCheck >= 1) {
        lastRateCheck = rateNow;
        NSInteger wanted = LMVPanelPresenceHz();
        if (LMVPanelPresenceLink.preferredFramesPerSecond != wanted)
            LMVPanelPresenceLink.preferredFramesPerSecond = wanted;
    }
    NSUInteger signature = LMVPanelComputeSignature();
    if (signature == LMVPanelPresenceSignature) return;
    LMVPanelPresenceSignature = signature;
    LMVPanelAppearKick();
}

static void LMVPanelPresenceStart(void) {
    if (LMVPanelPresenceLink || !NSThread.isMainThread) return;
    LMVPanelPresenceSignature = LMVPanelComputeSignature();
    LMVPanelPresenceLink = [CADisplayLink displayLinkWithTarget:[NSBlockOperation blockOperationWithBlock:^{
        LMVPanelPresenceTick(nil);
    }] selector:@selector(main)];
    LMVPanelPresenceLink.preferredFramesPerSecond = LMVPanelPresenceHz();
    [LMVPanelPresenceLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}

// 2.65: the Settings app is a SEPARATE process. Only the settings-video channel
// runs there; every SpringBoard path below must stay untouched.
static BOOL LMVSettingsAppProcess(void) {
    NSString *identifier = NSBundle.mainBundle.bundleIdentifier;
    return [identifier isEqualToString:@"com.apple.Preferences"];
}
%ctor {
    @autoreleasepool {
        // 2.95: the Settings-app video background was removed; nothing runs there.
        if (LMVSettingsAppProcess()) return;
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
        LMVDesktopPrimeEarly();
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
                if (!LMVInitialized || !LMVLaunchReady) return;
                if (!LMVPlaybackAllowed()) LMVSuspend();
                else {
                    // SpringBoard becoming inactive does not mean an exposed
                    // NC/CC/Home surface vanished. Let each channel's scope and
                    // current screen state decide, not an application-state latch.
                    LMVHomeMenuVideoSuspend();
                    LMVSquidPanelVideoSuspend();
                    LMVATPanelVideoSuspend();
                    LMVPhoneAssistVideoSuspend();
                    LMVGlassSuiteVideoSuspend();
                    LMVCCBorderVideoSuspend();
                    LMVCopyLogXVideoSuspend();
                    LMVCopyVaultPanelVideoSuspend();
                    LMVMyrtlePanelVideoSuspend();
                    LMVRequestSyncDisplayLink();LMVRequestSafeUpdate();
                }
            });
        }];
        %init;
        LMVLockVideoInstallHooks();
        LMVDesktopVideoInstallHooks();
        // 0.0.131/0.0.135: the desktop freeze pauses the Desktop audio channel
        // directly instead of waiting for the 10 Hz audio timer to re-read the
        // state; the coveredNow flip (any cover appearing or leaving) pauses or
        // resumes it the same way - no timer beat in either direction.
        LMVDesktopAudioPauseHook=^{ LMVAudioPauseTarget(@"Desktop"); if(LMVDiagnosticsEnabled.load()) LMVDiagnostic(@"desktop-audio pause (cover/off)"); };
        LMVDesktopAudioCoverHook=^(BOOL covered){
            if (covered) LMVAudioPauseTarget(@"Desktop");
            else LMVAudioResumeTarget(@"Desktop",LMVDesktopVideo.playback.player?LMVDesktopVideo.playback.player.currentTime:kCMTimeZero);
        };
        LMVCCInstallHooks();
        LMVHomeMenuVideoInstallHooks();
        LMVSquidPanelVideoInstallHooks();
        LMVATPanelVideoInstallHooks();
        LMVPhoneAssistVideoInstallHooks();
        LMVGlassSuiteVideoInstallHooks();
        LMVCCBorderVideoInstallHooks();
        LMVCopyLogXVideoInstallHooks();
        LMVCopyVaultPanelVideoInstallHooks();
        Class coverWindow = NSClassFromString(@"SBCoverSheetWindow");
        if (coverWindow && [coverWindow isSubclassOfClass:UIWindow.class]) %init(LMVCoverWindowHooks);
        for (NSString *name in @[UIApplicationDidFinishLaunchingNotification, UIApplicationDidBecomeActiveNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{ LMVEasterStartIfReady(); });
            }];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ dispatch_async(dispatch_get_main_queue(), ^{ LMVEasterStartIfReady(); }); });
        // 2.60: panel-appearance events feed the kick. Visible/Key fire when a
        // panel window (or an alert, or a keyboard) joins the hierarchy; scene
        // activation covers the transitions where the window list itself did not
        // change. Teardown stays on the ProbeHz timers on purpose - a hidden
        // notification burst would only add work, and this costs nothing when no
        // panel is appearing.
        for (NSString *name in @[UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeKeyNotification, UISceneDidActivateNotification, UIApplicationDidBecomeActiveNotification]) {
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil usingBlock:^(NSNotification *note) {
                dispatch_async(dispatch_get_main_queue(), ^{ LMVPanelAppearKick(); });
            }];
        }
        // 3.05: Darwin notifications have no wildcards, so every channel name is
        // registered explicitly. A name missing here would leave that channel deaf -
        // the one failure mode this change introduces, hence the full list below.
        NSMutableArray<NSString *> *notes=[NSMutableArray arrayWithObject:@"com.minis.lockmessagevideo/videoChanged"];
        [notes addObject:@"com.minis.lockmessagevideo/preferencesChanged"];
        for (NSString *channel in @[@"LockNC",@"LockScreen",@"Desktop",@"CC",@"ControlCenterDark",@"ControlCenterLight",
                                    @"HomeMenu",@"SquidPanel",@"AT",@"CopyLogX",@"PA",@"GS",@"CCBorder",@"CV",@"Myrtle",@"Bubble",@"Cards"]) {
            [notes addObject:[NSString stringWithFormat:@"com.minis.lockmessagevideo/preferencesChanged.%@",channel]];
        }
        for (NSString *name in notes) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        for (NSString *name in @[@"com.apple.springboard.hasBlankedScreen", @"com.apple.springboard.lockstate"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVScreenNotification, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            // No arbitrary delay and no creating private singleton. For a normal
            // startup, only did-finish/active evidence opens the readiness gate.
            if (LMVAlreadyLaunched(UIApplication.sharedApplication)) LMVMarkLaunchReady();
            // 1.34: warm the material thumbnails here, NOT inside LMVMarkLaunchReady
            // - the startup-reentry contract keeps that function minimal, and this
            // call belongs to the main-queue turn after readiness anyway. Background
            // queue, no UI, read-only sidecar records; see
            // +[LMVMaterialPicker prewarmThumbnailCache]. It only matters after a
            // respring, where the in-memory cache starts empty while the on-disk
            // posters are still good.
            [LMVMaterialPicker prewarmThumbnailCache];
        });
    }
}
