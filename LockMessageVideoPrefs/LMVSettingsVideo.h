#pragma once
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>

// 2.63: THE SETTINGS-APP VIDEO BACKGROUND.
//
// This runs INSIDE the Settings app, in the preference bundle (which is already
// loaded there) - no extra injection target and no tweak filter change. The
// bundle cannot touch SpringBoard's playback engine, so this is a small,
// self-contained player: one AVQueuePlayer + AVPlayerLooper behind the app's
// content, driven by its own preference keys.
//
// Materials live in their own folder, as the user asked:
//   /var/mobile/LockMessageVideo/设置视频背景
#ifndef LMVSettingsVideoPrefsID
#define LMVSettingsVideoPrefsID
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
#endif
static NSString *const LMVSettingsVideoRoot = @"/var/mobile/LockMessageVideo/设置视频背景";
static NSString *const LMVSettingsVideoEnabledKey = @"SettingsVideoBackgroundEnabled";
static NSString *const LMVSettingsVideoFileKey = @"SettingsVideo";
static NSString *const LMVSettingsVideoSoundKey = @"SettingsVideoSoundEnabled";
static NSString *const LMVSettingsVideoVolumeKey = @"SettingsVideoVolume";

static inline id LMVSettingsRead(NSString *key) {
    return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kLMVPrefsID);
}
static inline void LMVSettingsWrite(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kLMVPrefsID);
    CFPreferencesAppSynchronize(kLMVPrefsID);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, NULL, YES);
}

// The window the background sits in. `window.rootViewController.view` is the
// app's whole UI, so the host goes at index 0 and every table/bar draws above it.
@interface LMVSettingsVideoBackground : NSObject
@property(nonatomic, weak) UIWindow *window;
@property(nonatomic, strong) UIView *host;
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLooper *looper;
@property(nonatomic, copy) NSString *path;
@property(nonatomic) BOOL active;
+ (instancetype)shared;
- (BOOL)enabled;
- (NSString *)selectedPath;
- (UIWindow *)currentWindow;
- (void)installInWindow:(UIWindow *)window;
- (void)applyTransparency:(BOOL)transparent;
- (void)buildPlayerForPath:(NSString *)path;
- (void)updateAudio;
- (void)refresh;
- (void)stop;
@end