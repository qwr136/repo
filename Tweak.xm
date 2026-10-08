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

static NSString * const LMVDirectory = @"/var/mobile/LockMessageVideo";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSHashTable<UIView *> *LMVCells;
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
static CGFloat LMVOpacity = 0.55;
static BOOL LMVOpacityEnabled = YES;
static int LMVBlankToken = -1;
static char LMVStatesKey, LMVHostsKey, LMVDiscoveryKey, LMVRetryKey, LMVOwnershipKey;
static NSArray<NSString *> *LMVTargets(void) { return @[@"Message", @"Options", @"Clear"]; }
static void LMVUpdate(UIView *cell);
static void LMVUpdateLockScreens(void);
static void LMVUpdateDesktops(void);
static void LMVSyncDisplayLink(void);
static void LMVReleaseAllPlayers(void);
static void LMVRefresh(BOOL reload);
static BOOL LMVVisible(UIView *view);
static CADisplayLink *LMVLink;

// Diagnostics intentionally contain no notification text, labels or filenames.
static dispatch_queue_t LMVDiagnosticQueue;
static std::atomic_bool LMVDiagnosticsEnabled(false);
static void LMVDiagnostic(NSString *event) {
    if (!LMVDiagnosticsEnabled.load() || !event.length || !LMVDiagnosticQueue) return;
    dispatch_async(LMVDiagnosticQueue, ^{
        @autoreleasepool {
            // Drop queued records after the switch is turned off, too.
            if (!LMVDiagnosticsEnabled.load()) return;
            static NSUInteger records=0;
            if (++records>1200) return;
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
                NSString *line=[NSString stringWithFormat:@"%.3f %@\n",CACurrentMediaTime(),event];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            } @catch (NSException *exception) { /* Diagnostics must never affect playback. */ }
            @finally { [handle closeFile]; }
        }
    });
}

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
    if (!key || LMVFrameCache[key].image || [LMVPreviewPending containsObject:key]) return;
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

@interface LMVSharedSource : NSObject <AVPlayerItemOutputPullDelegate>
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItemVideoOutput *output;
@property(nonatomic, assign) CGImageRef lastImage;
@property(nonatomic, copy) NSString *path;
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
// Explicit fallback remains ONE decoder per file, never one player per card.
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
@end
@implementation LMVVideoState
- (void)dealloc { [_overlay removeFromSuperview]; }
@end
@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end
static BOOL LMVPlaybackAllowed(void) {
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

static LMVSharedSource *LMVSourceForPath(NSString *path) {
    LMVSharedSource *source=LMVSharedSources[path];
    if (source || !LMVAssets[path]) return source;
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
    source.revision=LMVRevisions[path];
    LMVFrameSnapshot *snapshot=LMVCachedFrame(path,source.revision);
    if (snapshot.image) {
        source.lastImage=CGImageRetain(snapshot.image);
        if (snapshot.rendered && CMTIME_IS_NUMERIC(snapshot.time)) {
            source.lastTime=snapshot.time; source.restoringTime=YES;
            [player seekToTime:snapshot.time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    source.restoringTime=NO;
                    if (source.playing && !source.readerMode && LMVSharedSources[path]==source) [source.player play];
                });
            }];
        }
    }
    LMVSharedSources[path]=source;
    [output setDelegate:source queue:dispatch_get_main_queue()];
    [output requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03];
    LMVDiagnostic([NSString stringWithFormat:@"loadsource=%lu currentItem=%d tracks=%lu",(unsigned long)source.identifier,player.currentItem!=nil,(unsigned long)[source.asset tracksWithMediaType:AVMediaTypeVideo].count]);
    __weak LMVSharedSource *weakSource=source;
    source.endObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        LMVSharedSource *live=weakSource;
        if (!live || !live.playing || live.readerMode) return;
        NSUInteger epoch=live.generation;
        [live.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (finished && live.playing && !live.readerMode && live.generation==epoch) {
                    [live.output requestNotificationOfMediaDataChangeWithAdvanceInterval:0.03]; [live.player play];
                }
            });
        }];
    }];
    return source;
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
                else if (LMVSharedSources[source.path]!=source) drop=@"replaced";
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
                    for (UIView *host in LMVLockHosts.allObjects) {
                        LMVVideoState *state = objc_getAssociatedObject(host, &LMVLockStateKey);
                        if (state.source == source && state.active) state.layer.contents = (__bridge id)image;
                    }
                    for (UIView *host in LMVDesktopHosts.allObjects) {
                        LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
                        if (state.source == source && state.active) state.layer.contents = (__bridge id)image;
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
    if (!source || source.playing) return;
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
        if (!source.restoringTime && source.restoreOnStart && CMTIME_IS_NUMERIC(source.lastTime)) {
            source.restoreOnStart=NO; source.restoringTime=YES;
            [source.player seekToTime:source.lastTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    source.restoringTime=NO; source.restoreOnStart=NO;
                    if (source.playing && !source.readerMode) [source.player play];
                });
            }];
        } else if (!source.restoringTime) [source.player play];
    }
}
static void LMVStopSource(LMVSharedSource *source) {
    if (source && source.playing) {
        [source.player pause]; source.playing=NO; source.generation++;
        source.restoreOnStart=CMTIME_IS_NUMERIC(source.lastTime);
        // Do not launch asynchronous pause-seeks that can flush the next startup.
    }
}
static BOOL LMVSourceHasConsumer(LMVSharedSource *source) {
    if (!source) return NO;
    for (UIView *host in LMVLockHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVLockStateKey);
        if (state.source == source && state.active && state.layer.superlayer) return YES;
    }
    for (UIView *host in LMVDesktopHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
        if (state.source == source && state.active && state.layer.superlayer) return YES;
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
static void LMVPrepareAssets(void) {
    NSSet *wanted = [NSSet setWithArray:LMVPaths.allValues];
    for (NSString *path in LMVSources.allKeys) {
        if (![wanted containsObject:path]) { [LMVSources removeObjectForKey:path]; [LMVAssets removeObjectForKey:path];  [LMVReadyAssets removeObject:path]; LMVStopSource(LMVSharedSources[path]); [LMVSharedSources removeObjectForKey:path]; [LMVRevisions removeObjectForKey:path]; }
    }
    for (NSString *path in wanted) {
        NSString *revision = LMVFileRevision(path);
        if (LMVSources[path] && [LMVRevisions[path] isEqualToString:revision]) continue;
        // Same URL does not imply the same file. Invalidate composition,
        // prewarm decoder and time epoch together.
                [LMVSources removeObjectForKey:path]; [LMVAssets removeObjectForKey:path];
        [LMVReadyAssets removeObject:path];
        LMVStopSource(LMVSharedSources[path]); [LMVSharedSources removeObjectForKey:path];
        if (!revision) { [LMVRevisions removeObjectForKey:path]; continue; }
        LMVRevisions[path] = revision;
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
    if (diagnosticsEnabled && !wasEnabled) LMVDiagnostic(@"version=0.0.54 diagnostics-enabled");
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
        if (![relative isKindOfClass:NSString.class]) relative = LMVMaterialSources[target];
        if (![relative isKindOfClass:NSString.class] || !relative.length) continue;
        NSString *path = [[LMVDirectory stringByAppendingPathComponent:relative] stringByStandardizingPath];
        if ([path hasPrefix:[LMVDirectory stringByAppendingString:@"/"]] && [[NSFileManager defaultManager] fileExistsAtPath:path]) LMVPaths[target] = path;
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
        if (ancestor.hidden || ancestor.alpha < 0.01) return NO;
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
    if (depth > 12 || LMVActionBranch(view) || view.hidden || view.alpha < 0.01) return nil;
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
static void LMVFindActions(UIView *view, UIView *root, NSMapTable *hosts, NSUInteger depth) {
    if (depth > 10) return;
    NSString *target = LMVSemanticTarget(view);
    if (target) {
        UIView *host = view;
        while (host && host != root && ![host isKindOfClass:UIControl.class]) host = host.superview;
        if (host && host != root) {
            UIView *material = LMVMessageMaterial(host, 0);
            [hosts setObject:(material ?: host) forKey:target];
        }
    }
    for (UIView *child in view.subviews) LMVFindActions(child, root, hosts, depth + 1);
}
static void LMVActionHosts(UIView *view, NSMapTable *hosts, NSUInteger depth) {
    if (depth > 12) return;
    if (LMVActionBranch(view)) { LMVFindActions(view, view, hosts, 0); return; }
    for (UIView *child in view.subviews) LMVActionHosts(child, hosts, depth + 1);
}
static void LMVPause(LMVVideoState *state) { LMVReleasePlayer(state); }

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
    if (missing && (!last || now - last.doubleValue >= 0.1)) {
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
        BOOL revisionChanged=![state.revision isEqualToString:LMVRevisions[path]];
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
        BOOL material = [NSStringFromClass(anchor.class) containsString:@"MaterialView"];
        UIView *host = material ? anchor.superview : anchor;
        // Host identity is part of ownership. Never retain an overlay under a
        // reused parent when UIKit swaps the notification content host.
        if (state.host && state.host != host) {
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
    [LMVCells addObject:(UIView *)self];
    LMVUpdate((UIView *)self);
    LMVRetryDiscovery((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    [LMVCells addObject:(UIView *)self];
    LMVUpdate((UIView *)self);
    LMVRetryDiscovery((UIView *)self);
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
// CoverSheet's own background consumer; it never edits system material views.
static BOOL LMVLockHostVisible(UIView *host) {
    Class cover = NSClassFromString(@"CSCoverSheetView");
    Class windowClass = NSClassFromString(@"SBCoverSheetWindow");
    return LMVLockConsumerAllowed(cover && [host isKindOfClass:cover], windowClass && [host.window isKindOfClass:windowClass], LMVVisible(host), LMVPlaybackAllowed());
}
static BOOL LMVBranchHasWallpaper(UIView *view, NSUInteger depth) {
    if ([NSStringFromClass(view.class) containsString:@"Wallpaper"]) return YES;
    if (depth >= 4) return NO;
    // A mixed page/container can own clock or notifications as well: placing
    // above that whole branch would cover content. Only follow one-child wrappers.
    return view.subviews.count == 1 && LMVBranchHasWallpaper(view.subviews.firstObject, depth + 1);
}
static void LMVUpdateLockScreen(UIView *host) {
    if (!host) return;
    LMVVideoState *state = objc_getAssociatedObject(host, &LMVLockStateKey);
    NSString *path = LMVPaths[@"LockScreen"];
    BOOL enabled = LMVEnabled[@"LockScreen"].boolValue && path.length;
    if (state && (!enabled || ![state.path isEqualToString:path] || ![state.revision isEqualToString:LMVRevisions[path]])) {
        LMVReleasePlayer(state);
        [state.layer removeFromSuperlayer];
        objc_setAssociatedObject(host, &LMVLockStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state = nil;
    }
    if (!enabled) return;
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
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    // Insert above the existing wallpaper branch, below CoverSheet content.
    // UIKit remains untouched: no view insertion, material/opacity mutation or hit testing.
    CALayer *wallpaper = nil;
    for (UIView *child in host.subviews) if (LMVBranchHasWallpaper(child, 0)) { wallpaper = child.layer; break; }
    NSArray *layers = host.layer.sublayers;
    NSUInteger ownIndex = [layers indexOfObjectIdenticalTo:state.layer];
    NSUInteger wallpaperIndex = wallpaper ? [layers indexOfObjectIdenticalTo:wallpaper] : NSNotFound;
    BOOL ordered = ownIndex != NSNotFound && (wallpaperIndex == NSNotFound ? ownIndex == 0 : ownIndex == wallpaperIndex + 1);
    if (!ordered) {
        [state.layer removeFromSuperlayer];
        if (wallpaper && wallpaper.superlayer == host.layer) [host.layer insertSublayer:state.layer above:wallpaper];
        else [host.layer insertSublayer:state.layer atIndex:0];
    }
    state.layer.frame = host.bounds;
    state.layer.hidden = NO;
    LMVFrameSnapshot *cached = LMVCachedFrame(path, state.revision);
    if (!state.layer.contents && cached.image) state.layer.contents = (__bridge id)cached.image;
    BOOL active = LMVLockHostVisible(host);
    if (active && [LMVReadyAssets containsObject:path]) {
        if (!state.source) state.source = LMVSourceForPath(path);
        if (state.source.lastImage) state.layer.contents = (__bridge id)state.source.lastImage;
    }
    state.active = active && state.source != nil;
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
        CALayer *shown = cover.layer.presentationLayer ?: cover.layer;
        CALayer *home = host.layer.presentationLayer ?: host.layer;
        // Window coordinate spaces must be stable before claiming full occlusion.
        if (cover.window.layer.animationKeys.count || host.window.layer.animationKeys.count) continue;
        CALayer *coverRoot = cover.window.layer.presentationLayer ?: cover.window.layer;
        CALayer *homeRoot = host.window.layer.presentationLayer ?: host.window.layer;
        CGRect modelRect = [cover convertRect:cover.bounds toCoordinateSpace:cover.window.screen.coordinateSpace];
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
static LMVDesktopDecision LMVDesktopHostDecision(UIView *host) {
    Class home = NSClassFromString(@"SBHomeScreenView");
    Class homeWindow = NSClassFromString(@"SBHomeScreenWindow");
    BOOL homeHost = home && object_getClass(host) == home;
    BOOL inHomeWindow = homeWindow && [host.window isKindOfClass:homeWindow];
    BOOL lockKnown = NO, isLocked = YES;
    Class lockClass = NSClassFromString(@"SBLockScreenManager");
    SEL shared = NSSelectorFromString(@"sharedInstance"), locked = NSSelectorFromString(@"isUILocked");
    if (LMVDesktopMethod(lockClass, shared, @encode(id))) {
        id manager = ((id (*)(id, SEL))objc_msgSend)(lockClass, shared);
        lockKnown = LMVDesktopMethod(manager, locked, @encode(BOOL));
        if (lockKnown) isLocked = ((BOOL (*)(id, SEL))objc_msgSend)(manager, locked);
    }
    UIApplication *app = UIApplication.sharedApplication;
    SEL front = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    BOOL frontKnown = LMVDesktopMethod(app, front, @encode(id));
    id foreground = frontKnown ? ((id (*)(id, SEL))objc_msgSend)(app, front) : nil;
    SEL bundle = NSSelectorFromString(@"bundleIdentifier");
    id identifier = LMVDesktopMethod(foreground, bundle, @encode(id)) ? ((id (*)(id, SEL))objc_msgSend)(foreground, bundle) : nil;
    BOOL bundleKnown = [identifier isKindOfClass:NSString.class] && [identifier length] > 0;
    LMVWindowRole role = LMVDesktopRole(foreground);
    LMVWindowRole windowRole = LMVWindowOther;
    if ([foreground isKindOfClass:UIView.class]) windowRole = LMVDesktopRole(((UIView *)foreground).window);
    else if ([foreground isKindOfClass:UIViewController.class]) windowRole = LMVDesktopRole(((UIViewController *)foreground).viewIfLoaded.window);
    if (windowRole != LMVWindowOther) role = windowRole;
    BOOL ownController = LMVDesktopHomeController(foreground);
    if (!foreground && frontKnown && role == LMVWindowOther) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows)
                if (window.isKeyWindow && !window.hidden) role = LMVDesktopRole(window);
        }
    }
    LMVForeground frontState = LMVDesktopResolveForeground(bundleKnown, [identifier isEqual:@"com.apple.springboard"],
        frontKnown && !foreground, role, ownController);
    BOOL contextOverlay = frontState == LMVForegroundOverlay;
    UIViewController *controller = host.window.rootViewController;
    // Observe UIKit presentation only. No SBIconContentView or floating Dock layout hooks.
    for (NSUInteger depth = 0; controller && depth < 8; depth++, controller = controller.presentedViewController)
        if ([NSStringFromClass(controller.class) containsString:@"ContextMenu"]) contextOverlay = YES;
    return LMVDesktopDecide(homeHost, inHomeWindow, host.window != nil, LMVDesktopGeometryVisible(host),
        LMVPlaybackAllowed(), lockKnown, isLocked, frontState, LMVDesktopCoverFullyObscures(host), contextOverlay);
}
static BOOL LMVDesktopHostAllowed(UIView *host) { return LMVDesktopHostDecision(host).decode; }
// Opt-in bounded structural diagnostics; never log labels, app identifiers or message text.
static void LMVDesktopDiagnostics(UIView *host, LMVDesktopDecision decision) {
    if (!LMVDiagnosticsEnabled.load()) return;
    static CFTimeInterval last = 0;
    static NSUInteger samples = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < 2.0 || samples >= 30) return;
    last = now; samples++;
    LMVDiagnostic([NSString stringWithFormat:@"desktop retain=%d decode=%d parent=%@", decision.retainFrame, decision.decode, NSStringFromClass(host.superview.class)]);
    NSMutableArray<UIView *> *pending = [NSMutableArray arrayWithObject:host];
    NSUInteger count = 0;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (count++ >= 16) break;
            LMVDiagnostic([NSString stringWithFormat:@"desktop-window class=%@ level=%.1f hidden=%d alpha=%.3f key=%d", NSStringFromClass(window.class), window.windowLevel, window.hidden, window.alpha, window.isKeyWindow]);
            if (pending.count < 16) [pending addObject:window];
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
    LMVStopSource(source); source.generation++;
    [source.output setDelegate:nil queue:NULL];
    [source.player replaceCurrentItemWithPlayerItem:nil]; source.player = nil; source.output = nil;
    if (source.endObserver) { [NSNotificationCenter.defaultCenter removeObserver:source.endObserver]; source.endObserver = nil; }
    dispatch_async(LMVFrameQueue, ^{
        [source.reader cancelReading]; source.reader = nil; source.readerOutput = nil;
        if (source.pendingSample) { CFRelease(source.pendingSample); source.pendingSample = NULL; }
    });
    if (LMVSharedSources[source.path] == source) [LMVSharedSources removeObjectForKey:source.path];
    LMVDiagnostic(@"desktop=decoder-released");
}
static void LMVUpdateDesktop(UIView *host) {
    if (!NSThread.isMainThread) return;
    Class home = NSClassFromString(@"SBHomeScreenView");
    if (!home || object_getClass(host) != home) return;
    LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
    NSString *path = LMVPaths[@"Desktop"];
    BOOL enabled = LMVEnabled[@"Desktop"].boolValue && path.length;
    if (state && (!enabled || ![state.path isEqualToString:path] || ![state.revision isEqualToString:LMVRevisions[path]])) {
        LMVReleaseDesktopSource(state); [state.layer removeFromSuperlayer];
        objc_setAssociatedObject(host, &LMVDesktopStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); state = nil;
    }
    if (!enabled) return;
    LMVDesktopDecision decision = LMVDesktopHostDecision(host);
    LMVDesktopDiagnostics(host, decision);
    if (!decision.retainFrame) {
        if (state) { state.layer.hidden = YES; LMVReleaseDesktopSource(state); }
        return;
    }
    // Unknown/transient foreground freezes existing real pixels; never starts a decoder.
    if (!state && !decision.decode) return;
    if (!state) {
        state = [LMVVideoState new]; state.host = host; state.path = path; state.revision = LMVRevisions[path];
        state.layer = [CALayer layer]; state.layer.name = @"com.minis.lockmessagevideo.desktop";
        state.layer.contentsGravity = kCAGravityResizeAspectFill; state.layer.masksToBounds = YES;
        objc_setAssociatedObject(host, &LMVDesktopStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LMVDiagnostic(@"desktop=guarded-home-host");
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    CALayer *wallpaper = nil;
    for (UIView *child in host.subviews) if (LMVBranchHasWallpaper(child, 0)) { wallpaper = child.layer; break; }
    // Own CALayer has no hit testing. Place below home content/icons, never above their branch.
    if (LMVDesktopShouldAttach(state.layer.superlayer == host.layer)) {
        if (wallpaper && wallpaper.superlayer == host.layer) [host.layer insertSublayer:state.layer above:wallpaper];
        else [host.layer insertSublayer:state.layer atIndex:0];
    }
    state.layer.frame = host.bounds; state.layer.hidden = NO;
    LMVFrameSnapshot *cached = LMVCachedFrame(path, state.revision);
    if (!state.layer.contents && cached.image) state.layer.contents = (__bridge id)cached.image;
    if (decision.decode && [LMVReadyAssets containsObject:path]) {
        if (!state.source || LMVSharedSources[path] != state.source) state.source = LMVSourceForPath(path);
        if (state.source.lastImage) state.layer.contents = (__bridge id)state.source.lastImage;
    }
    state.active = decision.decode && state.source != nil;
    [CATransaction commit];
    if (!state.active) LMVReleaseDesktopSource(state);
}
static void LMVUpdateDesktops(void) {
    if (!NSThread.isMainThread) return;
    BOOL enabled = LMVEnabled[@"Desktop"].boolValue && LMVPaths[@"Desktop"].length;
    for (UIView *host in LMVDesktopHosts.allObjects) LMVUpdateDesktop(host);
    if (!enabled) { [LMVDesktopVisibilityTimer invalidate]; LMVDesktopVisibilityTimer = nil; return; }
    if (!LMVDesktopVisibilityTimer) {
        // No decoding here. Watch visibility even while the display link is stopped,
        // including app return / Notification Center dismissal without home relayout.
        LMVDesktopVisibilityTimer = [NSTimer timerWithTimeInterval:0.35 repeats:YES block:^(NSTimer *timer) {
            LMVUpdateDesktops(); LMVSyncDisplayLink();
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
    for (UIView *host in LMVDesktopHosts.allObjects) if (LMVDesktopHostAllowed(host)) return YES;
    return NO;
}
static void LMVDesktopHostChanged(UIView *view) {
    if (!NSThread.isMainThread) return;
    Class home = NSClassFromString(@"SBHomeScreenView");
    if (home && object_getClass(view) == home) [LMVDesktopHosts addObject:view];
    LMVUpdateDesktops(); LMVSyncDisplayLink();
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
%group LMVWallpaperWindowHooks
%hook _SBWallpaperSecureWindow
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

%group LMVLockScreenHooks
%hook CSCoverSheetView
- (void)layoutSubviews {
    %orig;
    [LMVLockHosts addObject:(UIView *)self];
    LMVUpdateLockScreen((UIView *)self);
    LMVSyncDisplayLink();
}
- (void)didMoveToWindow {
    %orig;
    [LMVLockHosts addObject:(UIView *)self];
    LMVUpdateLockScreen((UIView *)self);
    LMVSyncDisplayLink();
}
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVUpdateLockScreen((UIView *)self);
    LMVSyncDisplayLink();
}
- (void)setAlpha:(CGFloat)alpha {
    %orig;
    LMVUpdateLockScreen((UIView *)self);
    LMVSyncDisplayLink();
}
%end
%end

static void LMVCoverSheetVisibilityChanged(UIView *view) {
    // A root window has no superview. A callback from a hidden/detached sibling
    // is not evidence that every notification surface is hidden.
    static NSMapTable *surfaceStates;
    if (!surfaceStates) surfaceStates=[NSMapTable weakToStrongObjectsMapTable];
    NSString *state=[NSString stringWithFormat:@"window=%d hidden=%d attached=%d",[view isKindOfClass:UIWindow.class],view.hidden,view.window!=nil];
    if (![[surfaceStates objectForKey:view] isEqualToString:state]) { [surfaceStates setObject:state forKey:view]; LMVDiagnostic([@"surface " stringByAppendingString:state]); }
    LMVUpdateLockScreens();
    LMVUpdateDesktops();
    if (!LMVPlaybackAllowed()) LMVReleaseAllPlayers(); else LMVRefresh(NO);
}
%group LMVCoverWindowHooks
%hook SBCoverSheetWindow
- (void)setHidden:(BOOL)hidden {
    // Bind retained frames while still hidden, before UIKit exposes the surface.
    if (!hidden) for (UIView *cell in LMVCells.allObjects) LMVUpdate(cell);
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
    // Bind retained frames while still hidden, before UIKit exposes the surface.
    if (!hidden) for (UIView *cell in LMVCells.allObjects) LMVUpdate(cell);
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
    LMVUpdateActionPresenter((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    LMVUpdateActionPresenter((UIView *)self);
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
    for (UIView *host in LMVDesktopHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
        if (!LMVDesktopHostDecision(host).retainFrame) state.layer.hidden = YES;
        LMVReleaseDesktopSource(state);
    }
}
static void LMVRefresh(BOOL reload) {
    if (reload) {
        // Revision-aware preparation preserves matching players, clocks and layers.
        // Unrelated imports must not tear down a working selected shared source.
        LMVLoadPreferences();
    }
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
        for (UIView *host in LMVDesktopHosts.allObjects) {
            LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
            LMVReleaseDesktopSource(state);
        }
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
    // Only the actual visible CoverSheet host consumes lockscreen frames.
    for (UIView *host in LMVLockHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVLockStateKey);
        BOOL active = LMVLockHostVisible(host);
        if (discover || active != state.active) LMVUpdateLockScreen(host);
        if (state.active && state.source) { [visible addObject:state.source]; consumers++; }
    }
    for (UIView *host in LMVDesktopHosts.allObjects) {
        LMVVideoState *state = objc_getAssociatedObject(host, &LMVDesktopStateKey);
        BOOL active = LMVDesktopHostAllowed(host);
        if (discover || active != state.active) LMVUpdateDesktop(host);
        if (state.active && state.source) { [visible addObject:state.source]; consumers++; }
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
            if (!source.restoringTime && item.status==AVPlayerItemStatusReadyToPlay && source.player.rate==0 && source.playing) [source.player play];
        }
        // A persistent AVPlayer-output stall switches explicitly to a shared,
        // video-only AVAssetReader. Never attach an AVPlayerLayer to a card.
        CFTimeInterval stallLimit=source.published ? 3.0 : 0.75;
        if (!source.readerMode && !source.restoringTime && !source.frameBusy && (item.status==AVPlayerItemStatusFailed || now-source.lastProgressAt>=stallLimit)) {
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
        NSString *phase=[NSString stringWithFormat:@"mode=%@ requested=%d playerstatus=%ld itemstatus=%ld ready=%d timestatus=%ld rate=%.2f item=%d outputawake=%d mappedvalid=%d timevalid=%d",source.readerMode?@"shared-reader":@"shared-output",source.playing,(long)source.player.status,(long)item.status,item.status==AVPlayerItemStatusReadyToPlay,(long)source.player.timeControlStatus,source.player.rate,item!=nil,source.outputAwake,mappedTimeValid,CMTIME_IS_NUMERIC(time)];
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
        BOOL media = CFEqual(name, CFSTR("com.minis.lockmessagevideo/videoChanged"));
        if (media) LMVRefresh(YES);
        else {
            LMVLoadPreferences();
            for (UIView *cell in LMVCells.allObjects) {
                NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
                for (LMVVideoState *state in states.allValues) state.overlay.alpha = LMVOpacityEnabled ? LMVOpacity : 0.0;
            }
            LMVRefresh(NO);
        }
    });
}
static void LMVScreenNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!LMVPlaybackAllowed()) LMVSuspend();
        else { LMVPrepareAssets();  LMVRefresh(NO); }
    });
}
%ctor {
    @autoreleasepool {
        LMVDiagnosticQueue=dispatch_queue_create("com.minis.lockmessagevideo.diagnostics",DISPATCH_QUEUE_SERIAL);
        LMVFrameQueue=dispatch_queue_create("com.minis.lockmessagevideo.frames",DISPATCH_QUEUE_SERIAL);
        LMVCIContext=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO}];
        LMVCells = [NSHashTable weakObjectsHashTable];
        LMVLockHosts = [NSHashTable weakObjectsHashTable];
        LMVDesktopHosts = [NSHashTable weakObjectsHashTable];
        LMVFrameCache = [NSMutableDictionary new]; LMVPreviewPending = [NSMutableSet new];
        LMVRevisions = [NSMutableDictionary new];
        LMVSources = [NSMutableDictionary new]; LMVAssets = [NSMutableDictionary new];  LMVReadyAssets = [NSMutableSet new]; LMVSharedSources = [NSMutableDictionary new];
        LMVLoadPreferences();
        %init;
        Class lockHost = NSClassFromString(@"CSCoverSheetView");
        Class lockWindow = NSClassFromString(@"SBCoverSheetWindow");
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
        if (wallpaperWindow && [wallpaperWindow isSubclassOfClass:UIWindow.class] && class_getInstanceMethod(wallpaperWindow, @selector(layoutSubviews))) {
            %init(LMVWallpaperWindowHooks);
        }
        notify_register_check("com.apple.springboard.hasBlankedScreen", &LMVBlankToken);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        for (NSString *name in @[@"com.apple.springboard.hasBlankedScreen", @"com.apple.springboard.lockstate"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVScreenNotification, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                LMVRefresh(NO);
            }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                LMVSuspend();
            }];
            LMVRefresh(NO);
        });
    }
}
