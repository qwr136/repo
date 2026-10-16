#pragma once
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <math.h>
// Separate audio-only chains: visual video-only compositions and success masks
// are not changed. Default OFF; no session/category work while every switch is OFF.
static NSArray<NSString *> *LMVAudioTargets(void) {
    return @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop",@"ControlCenterDark",@"ControlCenterLight",@"HomeMenu",@"SquidPanel",@"AT",@"CV"];
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
// 0.0.131: direct pause for a channel whose owning manager already KNOWS the
// surface froze or hid. The desktop freeze happens on the ~0.4 s update tick
// while the audio timer runs at 10 Hz - the timer alone let the desktop sound
// keep playing for up to half a second after an app covered the desktop.
static void LMVAudioPauseTarget(NSString *target) {
    if(!LMVAudioChannels)return;
    LMVAudioChannel *c=LMVAudioChannels[target];if(!c)return;
    c.visible=NO;[c.player pause];
}
// 0.0.135: direct resume mirroring the consume() visible path - seek to the
// video player's current time, then play. The 10 Hz audio sync alone made the
// sound return up to one timer beat late after the cover left the desktop.
// 1.29: the UNCONDITIONAL seek here was the remaining "sound comes back half a
// beat late" cost. A pause leaves currentTime exactly where it was, so that seek
// only made the decoder and its buffers restart for nothing - which is precisely
// the gap the user hears when an app exits or the Control Center slides back.
// Seek now happens only on a real drift (>0.25 s); otherwise the paused player
// simply plays, so the resume costs one play call on both paths.
static void LMVAudioResumeTarget(NSString *target,CMTime time) {
    if(!LMVAudioChannels)return;
    LMVAudioChannel *c=LMVAudioChannels[target];if(!c || !c.enabled || c.volume<=0 || c.loading)return;
    if(!c.player)return; // nothing loaded yet; the regular sync builds and starts it
    c.visible=YES;
    if(LMVAudioActivateMixing()) {
        c.player.volume=c.volume;
        if(c.player.rate==0) {
            BOOL drift=NO;
            if(CMTIME_IS_NUMERIC(time)) {
                CMTime now=c.player.currentTime;
                if(CMTIME_IS_NUMERIC(now))
                    drift=fabs(CMTimeGetSeconds(now)-CMTimeGetSeconds(time))>0.25;
            }
            if(drift)[c.player seekToTime:time toleranceBefore:CMTimeMakeWithSeconds(.2,600) toleranceAfter:CMTimeMakeWithSeconds(.2,600)];
            [c.player playImmediatelyAtRate:1];c.lastSync=CACurrentMediaTime();
        }
    }
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
        // 1.32: a property WRITE and a `currentTime` READ both reach into the
        // media daemon, and this branch runs for every enabled channel on every
        // sync beat - it is the steady-state cost of having any sound on. The
        // volume is now value-compared, and the drift measurement (the only real
        // reason to read `currentTime` at all) is throttled to one check per 2 s
        // by stamping `lastSync` on the CHECK rather than only on the seek. The
        // seek itself still happens exactly when the measured drift exceeds the
        // threshold, so playback stays in step with the video.
        if(c.player.volume!=c.volume)c.player.volume=c.volume;
        if(c.player.rate==0) {
            if(CMTIME_IS_NUMERIC(time))[c.player seekToTime:time toleranceBefore:CMTimeMakeWithSeconds(.1,600) toleranceAfter:CMTimeMakeWithSeconds(.1,600)];
            [c.player playImmediatelyAtRate:1];c.lastSync=CACurrentMediaTime();
        }
        CFTimeInterval now=CACurrentMediaTime();
        if(now-c.lastSync>=2) {
            c.lastSync=now;
            CMTime current=c.player.currentTime;
            if(CMTIME_IS_NUMERIC(current) && CMTIME_IS_NUMERIC(time) &&
               fabs(CMTimeGetSeconds(CMTimeSubtract(current,time)))>.4)
                [c.player seekToTime:time toleranceBefore:CMTimeMakeWithSeconds(.1,600) toleranceAfter:CMTimeMakeWithSeconds(.1,600)];
        }
    }
}
