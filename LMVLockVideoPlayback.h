#pragma once
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <sys/stat.h>
#import <math.h>

#ifndef LMVLockVideoLog
#define LMVLockVideoLog(message) ((void)0)
#endif
// This playback chain never publishes to the message-family image/PTS caches.
static NSString *LMVLockVideoRevision(NSString *path) {
    if (!path.length) return nil;
    struct stat s;
    if (lstat(path.fileSystemRepresentation,&s) || !S_ISREG(s.st_mode) || s.st_size<=0) return nil;
#ifdef __APPLE__
    struct timespec modified=s.st_mtimespec,changed=s.st_ctimespec;
#else
    struct timespec modified=s.st_mtim,changed=s.st_ctim;
#endif
    return [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%ld:%lld:%ld",
        (unsigned long long)s.st_dev,(unsigned long long)s.st_ino,(long long)s.st_size,
        (long long)modified.tv_sec,modified.tv_nsec,(long long)changed.tv_sec,changed.tv_nsec];
}
static AVMutableComposition *LMVLockVideoComposition(AVAsset *asset,NSError **error) {
    AVAssetTrack *source=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    CMTimeRange range=source.timeRange;
    if (!source || !CMTIMERANGE_IS_VALID(range) || !CMTIME_IS_NUMERIC(range.start) ||
        !CMTIME_IS_NUMERIC(range.duration) || CMTimeCompare(range.duration,kCMTimeZero)<=0) {
        if (error) *error=[NSError errorWithDomain:@"com.minis.lockmessagevideo.lock" code:1 userInfo:nil];
        return nil;
    }
    // A real video-only composition, not merely volume=0 on an audio-bearing asset.
    AVMutableComposition *composition=[AVMutableComposition composition];
    AVMutableCompositionTrack *track=[composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    if (![track insertTimeRange:range ofTrack:source atTime:kCMTimeZero error:error]) return nil;
    track.preferredTransform=source.preferredTransform;
    return composition;
}

@interface LMVLockVideoPlayback : NSObject
@property(nonatomic,readonly,strong) CALayer *renderLayer,*posterLayer;
@property(nonatomic,readonly,strong) AVPlayerLayer *playerLayer;
@property(nonatomic,readonly,strong) AVQueuePlayer *player;
@property(nonatomic,readonly,strong) AVPlayerLooper *looper;
@property(nonatomic,readonly,strong) AVPlayerItem *templateItem;
@property(nonatomic,readonly,copy) NSString *path,*revision;
@property(nonatomic,readonly,strong) NSError *error;
@property(nonatomic,readonly) BOOL loading,wantsPlayback;
@property(nonatomic,readonly) NSUInteger generation,buildCount;
@property(nonatomic,copy) void (^didChange)(void);
- (void)selectPath:(NSString *)path revision:(NSString *)revision;
- (void)setVisible:(BOOL)visible;
- (void)layoutInBounds:(CGRect)bounds;
- (void)clear;
@end

@interface LMVLockVideoPlayback ()
@property(nonatomic,strong) CALayer *renderLayer,*posterLayer;
@property(nonatomic,strong) AVPlayerLayer *playerLayer;
@property(nonatomic,strong) AVQueuePlayer *player;
@property(nonatomic,strong) AVPlayerLooper *looper;
@property(nonatomic,strong) AVPlayerItem *templateItem;
@property(nonatomic,copy) NSString *path,*revision;
@property(nonatomic,strong) NSError *error;
@property(nonatomic) BOOL loading,wantsPlayback,observingLayer,observingPlayer;
@property(nonatomic) NSUInteger generation,buildCount;
@property(nonatomic,strong) AVAssetImageGenerator *generator;
@property(nonatomic,strong) id failedObserver;
- (void)updatePresentation;
- (void)replacePlayerLayer;
@end
static char LMVLockLayerReadyContext,LMVLockPlayerStatusContext;
@implementation LMVLockVideoPlayback
- (instancetype)init {
    if ((self=[super init])) {
        _renderLayer=[CALayer layer];_renderLayer.name=@"com.minis.lockmessagevideo.lock.render";
        _renderLayer.masksToBounds=YES;_renderLayer.hidden=YES;
        _posterLayer=[CALayer layer];_posterLayer.name=@"com.minis.lockmessagevideo.lock.poster";
        _posterLayer.contentsGravity=kCAGravityResizeAspectFill;
        [self replacePlayerLayer];
    }
    return self;
}
- (void)replacePlayerLayer {
    if (self.observingLayer) [self.playerLayer removeObserver:self forKeyPath:@"readyForDisplay" context:&LMVLockLayerReadyContext];
    self.observingLayer=NO;self.playerLayer.player=nil;[self.playerLayer removeFromSuperlayer];
    self.playerLayer=[AVPlayerLayer layer];self.playerLayer.name=@"com.minis.lockmessagevideo.lock.player";
    self.playerLayer.videoGravity=AVLayerVideoGravityResizeAspectFill;self.playerLayer.hidden=YES;
    [self.renderLayer addSublayer:self.posterLayer];[self.renderLayer addSublayer:self.playerLayer];
    [self.playerLayer addObserver:self forKeyPath:@"readyForDisplay" options:0 context:&LMVLockLayerReadyContext];self.observingLayer=YES;
    [self layoutInBounds:self.renderLayer.frame];
}
- (void)dealloc {
    if (_observingLayer) [_playerLayer removeObserver:self forKeyPath:@"readyForDisplay" context:&LMVLockLayerReadyContext];
    if (_observingPlayer) [_player removeObserver:self forKeyPath:@"status" context:&LMVLockPlayerStatusContext];
    if (_failedObserver) [NSNotificationCenter.defaultCenter removeObserver:_failedObserver];
    [_generator cancelAllCGImageGeneration];[_player pause];[_looper disableLooping];
    _playerLayer.player=nil;[_player removeAllItems];[_renderLayer removeFromSuperlayer];
}
- (void)clear {
    NSCAssert(NSThread.isMainThread,@"Lock playback must be coordinated on main");
    self.generation++;self.loading=NO;self.wantsPlayback=NO;
    [self.generator cancelAllCGImageGeneration];self.generator=nil;
    if (self.failedObserver) [NSNotificationCenter.defaultCenter removeObserver:self.failedObserver];self.failedObserver=nil;
    if (self.observingPlayer) [self.player removeObserver:self forKeyPath:@"status" context:&LMVLockPlayerStatusContext];
    self.observingPlayer=NO;
    [self.player pause];[self.looper disableLooping];self.playerLayer.player=nil;
    [self.player removeAllItems];self.looper=nil;self.player=nil;self.templateItem=nil;
    [self replacePlayerLayer];
    self.path=nil;self.revision=nil;self.error=nil;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    self.posterLayer.contents=nil;self.posterLayer.hidden=YES;self.playerLayer.hidden=YES;self.renderLayer.hidden=YES;
    [CATransaction commit];
}
- (void)layoutInBounds:(CGRect)bounds {
    [CATransaction begin];[CATransaction setDisableActions:YES];
    self.renderLayer.frame=bounds;self.posterLayer.frame=self.renderLayer.bounds;self.playerLayer.frame=self.renderLayer.bounds;
    [CATransaction commit];
}
- (void)setVisible:(BOOL)visible {
    self.wantsPlayback=visible;
    if (visible && self.player && !self.error && self.player.status!=AVPlayerStatusFailed) {
        if (self.player.rate==0) [self.player playImmediatelyAtRate:1.0];
    } else [self.player pause];
    [self updatePresentation];
}
- (void)updatePresentation {
    BOOL ready=self.player && self.playerLayer.readyForDisplay && !self.error;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    self.playerLayer.hidden=!ready;
    self.posterLayer.hidden=ready || !self.posterLayer.contents || self.error!=nil;
    self.renderLayer.hidden=!self.wantsPlayback || self.error!=nil || (!ready && !self.posterLayer.contents);
    [CATransaction commit];
    if (self.didChange) self.didChange();
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context!=&LMVLockLayerReadyContext && context!=&LMVLockPlayerStatusContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];return;
    }
    __weak typeof(self) weakSelf=self;
    dispatch_async(dispatch_get_main_queue(),^{
        LMVLockVideoPlayback *live=weakSelf;
        if (!live || (object!=live.playerLayer && object!=live.player)) return;
        if (live.player.status==AVPlayerStatusFailed) {live.error=live.player.error ?: [NSError errorWithDomain:@"com.minis.lockmessagevideo.lock" code:2 userInfo:nil];[live.player pause];}
        [live updatePresentation];
    });
}
- (void)selectPath:(NSString *)path revision:(NSString *)revision {
    NSCAssert(NSThread.isMainThread,@"Lock selection must be coordinated on main");
    if ([self.path isEqualToString:path] && [self.revision isEqualToString:revision]) return;
    BOOL visible=self.wantsPlayback;[self clear];self.wantsPlayback=visible;
    if (!path.length || !revision.length) return;
    self.path=path;self.revision=revision;self.loading=YES;
    NSUInteger generation=self.generation;__weak typeof(self) weakSelf=self;
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    [asset loadValuesAsynchronouslyForKeys:@[@"tracks",@"playable"] completionHandler:^{
        NSError *error=nil;
        BOOL loaded=[asset statusOfValueForKey:@"tracks" error:&error]==AVKeyValueStatusLoaded &&
            [asset statusOfValueForKey:@"playable" error:&error]==AVKeyValueStatusLoaded && asset.playable;
        AVMutableComposition *composition=loaded?LMVLockVideoComposition(asset,&error):nil;
        if (!composition && !error) error=[NSError errorWithDomain:@"com.minis.lockmessagevideo.lock" code:3 userInfo:nil];
        dispatch_async(dispatch_get_main_queue(),^{
            LMVLockVideoPlayback *live=weakSelf;
            if (!live || live.generation!=generation || ![live.path isEqualToString:path] || ![live.revision isEqualToString:revision]) return;
            live.loading=NO;
            if (![[LMVLockVideoRevision(path) description] isEqualToString:revision]) {
                live.error=[NSError errorWithDomain:@"com.minis.lockmessagevideo.lock" code:4 userInfo:nil];[live updatePresentation];return;
            }
            if (!composition || error) {live.error=error;[live updatePresentation];return;}
            live.templateItem=[AVPlayerItem playerItemWithAsset:composition];
            live.templateItem.preferredForwardBufferDuration=1;
            live.player=[AVQueuePlayer queuePlayerWithItems:@[]];live.player.muted=YES;live.player.volume=0;
            live.player.allowsExternalPlayback=NO;
            if ([live.player respondsToSelector:@selector(setPreventsDisplaySleepDuringVideoPlayback:)])
                live.player.preventsDisplaySleepDuringVideoPlayback=NO;
            live.player.automaticallyWaitsToMinimizeStalling=NO;
            live.looper=[AVPlayerLooper playerLooperWithPlayer:live.player templateItem:live.templateItem];
            live.playerLayer.player=live.player;live.buildCount++;
            [live.player addObserver:live forKeyPath:@"status" options:NSKeyValueObservingOptionInitial context:&LMVLockPlayerStatusContext];live.observingPlayer=YES;
            live.failedObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){
                LMVLockVideoPlayback *current=weakSelf;
                if (!current || current.generation!=generation || ![current.player.items containsObject:note.object]) return;
                current.error=note.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey] ?: [NSError errorWithDomain:@"com.minis.lockmessagevideo.lock" code:5 userInfo:nil];
                [current.player pause];[current updatePresentation];
            }];
            AVAssetImageGenerator *generator=[[AVAssetImageGenerator alloc] initWithAsset:composition];
            generator.appliesPreferredTrackTransform=YES;generator.maximumSize=CGSizeMake(1280,1280);
            live.generator=generator;
            [generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:kCMTimeZero]] completionHandler:^(CMTime requested,CGImageRef image,CMTime actual,AVAssetImageGeneratorResult result,NSError *imageError){
                CGImageRef held=image?CGImageRetain(image):NULL;
                dispatch_async(dispatch_get_main_queue(),^{
                    LMVLockVideoPlayback *current=weakSelf;
                    if (current && current.generation==generation && current.generator==generator) {
                        current.generator=nil;
                        if (held && result==AVAssetImageGeneratorSucceeded) {
                            [CATransaction begin];[CATransaction setDisableActions:YES];current.posterLayer.contents=(__bridge id)held;[CATransaction commit];
                        }
                        [current updatePresentation];
                    }
                    if (held) CGImageRelease(held);
                });
            }];
            [live setVisible:live.wantsPlayback];
            LMVLockVideoLog(@"lock-video player-built independent=1 video-only=1 muted=1");
        });
    }];
}
@end
