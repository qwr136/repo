#pragma once
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

// 2.65: SETTINGS-APP VIDEO BACKGROUND - now actually injected into the Settings
// process (com.apple.Preferences), not the preference bundle.
//
// The bundle route could not work: it only loads after the user opens our page,
// and it cannot make the Settings window transparent. This channel loads with the
// app, installs one host view under the navigation controller's view and loops the
// selected material.
//
// Materials: /var/mobile/LockMessageVideo/设置视频背景
static NSString *const LMVSettingsVideoRoot = @"/var/mobile/LockMessageVideo/设置视频背景";
static NSString *const LMVSettingsVideoEnabledKey = @"SettingsVideoBackgroundEnabled";
static NSString *const LMVSettingsVideoFileKey = @"SettingsVideo";
static NSString *const LMVSettingsVideoSoundKey = @"SettingsVideoSoundEnabled";
static NSString *const LMVSettingsVideoVolumeKey = @"SettingsVideoVolume";

static CFStringRef const LMVSettingsVideoPrefsID = CFSTR("com.minis.lockmessagevideo");
static inline id LMVSettingsVideoRead(NSString *key) {
    return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, LMVSettingsVideoPrefsID);
}
static inline BOOL LMVSettingsVideoEnabled(void) {
    return [LMVSettingsVideoRead(LMVSettingsVideoEnabledKey) boolValue];
}

@interface LMVSettingsVideoChannel : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, strong) UIView *host;
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLooper *looper;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, strong) NSTimer *timer;
+ (instancetype)shared;
- (void)start;
- (void)refresh;
- (void)stop;
@end

static void LMVSettingsVideoStart(void) {
    [[LMVSettingsVideoChannel shared] start];
}