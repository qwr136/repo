#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "LMVPVideoPickerController.h"

static NSString * const kLMVDir = @"/var/mobile/LockMessageVideo";
static NSString * const kLMVPrefsID = @"com.minis.lockmessagevideo";

static void LMVPostNotification(NSString *name) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)name, NULL, NULL, YES);
}

@interface LMVPRootListController : PSListController
@end

@implementation LMVPRootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"锁屏消息视频";
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers ?: @[];
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kLMVPrefsID);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kLMVPrefsID);
    LMVPostNotification(@"com.minis.lockmessagevideo/preferencesChanged");
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kLMVPrefsID);
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)presentPickerForMode:(NSString *)mode {
    dispatch_async(dispatch_get_main_queue(), ^{
        LMVPVideoPickerController *picker = [[LMVPVideoPickerController alloc] initWithMode:mode];
        [self presentViewController:picker animated:YES completion:nil];
    });
}

- (void)pickMessageVideo { [self presentPickerForMode:@"message"]; }
- (void)pickOptionsVideo { [self presentPickerForMode:@"options"]; }

- (void)clearMessageVideo {
    [[NSFileManager defaultManager] removeItemAtPath:[kLMVDir stringByAppendingPathComponent:@"message.mov"] error:nil];
    LMVPostNotification(@"com.minis.lockmessagevideo/videoChanged");
}

- (void)clearOptionsVideo {
    [[NSFileManager defaultManager] removeItemAtPath:[kLMVDir stringByAppendingPathComponent:@"options.mov"] error:nil];
    LMVPostNotification(@"com.minis.lockmessagevideo/videoChanged");
}

- (void)openPreview {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"预览" message:@"视频将在锁屏通知区域循环播放。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)reloadSettings {
    _specifiers = nil;
    [self reloadSpecifiers];
}

@end
