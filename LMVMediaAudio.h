#pragma once
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <math.h>
// Separate audio-only chains: visual video-only compositions and success masks
// are not changed. Default OFF; no session/category work while every switch is OFF.
static NSArray<NSString *> *LMVAudioTargets(void) {
    return @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu"];
}
static double LMVAudioVolumeValue(id value) {
    double v=[value isKindOfClass:NSNumber.class]?[value doubleValue]:.5;
    return isfinite(v)?fmax(0,fmin(1,v)):.5;
}
@interface LMVAudioChannel:NSObject
@property(nonatomic,copy) NSString *path,*revision;
@property(nonatomic,strong) AVQueuePlayer *player;
@property(nonatomic,strong) AVPlayerLooper *looper;
@property(nonatomic) BOOL enabled,visible,loading;
@property(nonatomic) float volume;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) CMTime desiredTime;
@property(nonatomic) CFTimeInterval lastSync;
- (void)clear;
@end
@implementation LMVAudioChannel
- (void)clear {
    self.generation++;[self.player pause];[self.looper disableLooping];[self.player removeAllItems];
    self.player=nil;self.looper=nil;self.path=nil;self.revision=nil;self.loading=NO;self.visible=NO;
}
- (void)dealloc {[_player pause];[_looper disableLooping];[_player removeAllItems];}
@end
static NSMutableDictionary<NSString *,LMVAudioChannel *> *LMVAudioChannels;
static BOOL LMVAudioSessionReady;
static BOOL LMVAudioActivateMixing(void) {
    if(LMVAudioSessionReady)return YES;
    NSError *error=nil;AVAudioSession *session=AVAudioSession.sharedInstance;
    // No exclusive playback/ducking/remote-command ownership; other apps' music
    // keeps playing. Never deactivate SpringBoard's shared session on pause.
    BOOL ok=[session setCategory:AVAudioSessionCategoryAmbient withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
    if(ok)ok=[session setActive:YES error:&error];
    LMVAudioSessionReady=ok;return ok;
}
static void LMVAudioReload(void) {
    if(!LMVAudioChannels)LMVAudioChannels=[NSMutableDictionary new];
    for(NSString *target in LMVAudioTargets()) {
        LMVAudioChannel *c=LMVAudioChannels[target];if(!c){c=[LMVAudioChannel new];LMVAudioChannels[target]=c;}
        NSString *key=[target stringByAppendingString:@"SoundEnabled"];
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key,kLMVPrefsID);
        NSString *volume=[target stringByAppendingString:@"Volume"];
        id raw=(__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)volume,kLMVPrefsID);
        c.enabled=[enabled isKindOfClass:NSNumber.class] && [enabled boolValue];c.volume=LMVAudioVolumeValue(raw);
        if(!c.enabled || c.volume<=0)[c clear];else c.player.volume=c.volume;
    }
}
static BOOL LMVAudioAnyEnabled(void) {
    for(LMVAudioChannel *c in LMVAudioChannels.allValues)if(c.enabled && c.volume>0)return YES;
    return NO;
}
static void LMVAudioPauseAll(void) {
    for(LMVAudioChannel *c in LMVAudioChannels.allValues){c.visible=NO;[c.player pause];}
}
static void LMVAudioConsume(NSString *target,NSString *path,NSString *revision,BOOL visible,CMTime time) {
    LMVAudioChannel *c=LMVAudioChannels[target];if(!c)return;
    visible=visible && c.enabled && c.volume>0 && path.length && revision.length;
    if(!c.enabled || c.volume<=0){if(c.player || c.loading)[c clear];return;}
    if(!visible){c.visible=NO;[c.player pause];return;}
    BOOL changed=![c.path isEqualToString:path] || ![c.revision isEqualToString:revision];
    if(changed){[c clear];c.path=path;c.revision=revision;c.loading=YES;}
    c.visible=YES;c.desiredTime=CMTIME_IS_NUMERIC(time)?time:kCMTimeZero;
    if(changed) {
        NSUInteger epoch=c.generation;__weak LMVAudioChannel *weak=c;
        AVURLAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        [asset loadValuesAsynchronouslyForKeys:@[@"tracks",@"duration"] completionHandler:^{
            NSError *error=nil;AVMutableComposition *audio=nil;
            if([asset statusOfValueForKey:@"tracks" error:&error]==AVKeyValueStatusLoaded) {
                AVAssetTrack *track=[asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
                CMTimeRange range=track.timeRange;
                if(track && CMTIMERANGE_IS_VALID(range) && CMTIME_IS_NUMERIC(range.duration) && CMTimeCompare(range.duration,kCMTimeZero)>0) {
                    audio=[AVMutableComposition composition];
                    AVMutableCompositionTrack *out=[audio addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
                    if(![out insertTimeRange:range ofTrack:track atTime:range.start error:&error])audio=nil;
                }
            }
            dispatch_async(dispatch_get_main_queue(),^{
                LMVAudioChannel *live=weak;if(!live || live.generation!=epoch || ![live.path isEqualToString:path] || ![live.revision isEqualToString:revision])return;
                live.loading=NO;if(!audio || error || !live.enabled)return;
                AVPlayerItem *item=[AVPlayerItem playerItemWithAsset:audio];
                live.player=[AVQueuePlayer queuePlayerWithItems:@[]];live.player.volume=live.volume;
                live.player.automaticallyWaitsToMinimizeStalling=NO;live.player.allowsExternalPlayback=NO;
                live.looper=[AVPlayerLooper playerLooperWithPlayer:live.player templateItem:item];
                if(live.visible && live.volume>0 && LMVAudioActivateMixing()) {
                    [live.player seekToTime:live.desiredTime toleranceBefore:CMTimeMakeWithSeconds(.1,600) toleranceAfter:CMTimeMakeWithSeconds(.1,600)];
                    [live.player playImmediatelyAtRate:1];live.lastSync=CACurrentMediaTime();
                }
            });
        }];
    } else if(c.player && LMVAudioActivateMixing()) {
        c.player.volume=c.volume;
        if(c.player.rate==0) {
            if(CMTIME_IS_NUMERIC(time))[c.player seekToTime:time toleranceBefore:CMTimeMakeWithSeconds(.1,600) toleranceAfter:CMTimeMakeWithSeconds(.1,600)];
            [c.player playImmediatelyAtRate:1];c.lastSync=CACurrentMediaTime();
        }
        CFTimeInterval now=CACurrentMediaTime();
        CMTime current=c.player.currentTime;
        if(now-c.lastSync>=2 && CMTIME_IS_NUMERIC(current) && CMTIME_IS_NUMERIC(time) &&
           fabs(CMTimeGetSeconds(CMTimeSubtract(current,time)))>.4) {
            c.lastSync=now;[c.player seekToTime:time toleranceBefore:CMTimeMakeWithSeconds(.1,600) toleranceAfter:CMTimeMakeWithSeconds(.1,600)];
        }
    }
}
