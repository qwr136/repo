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

- (PSSpecifier *)button:(NSString *)title action:(SEL)action {
    // PSButtonCell executes the selector passed through the `set` argument.
    return [PSSpecifier preferenceSpecifierNamed:title
                                           target:self
                                              set:action
                                              get:nil
                                           detail:nil
                                             cell:PSButtonCell
                                             edit:nil];
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用插件"
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil cell:PSSwitchCell edit:nil];
    [enabled setProperty:kLMVPrefsID forKey:@"defaults"];
    [enabled setProperty:@"Enabled" forKey:@"key"];
    [enabled setProperty:@NO forKey:@"default"];

    PSSpecifier *opacity = [PSSpecifier preferenceSpecifierNamed:@"视频透明度"
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil cell:PSSliderCell edit:nil];
    [opacity setProperty:kLMVPrefsID forKey:@"defaults"];
    [opacity setProperty:@"Opacity" forKey:@"key"];
    [opacity setProperty:@0.85 forKey:@"default"];
    [opacity setProperty:@0.05 forKey:@"min"];
    [opacity setProperty:@1.0 forKey:@"max"];
    [opacity setProperty:@YES forKey:@"showValue"];

    PSSpecifier *radius = [PSSpecifier preferenceSpecifierNamed:@"圆角大小"
                                                           target:self
                                                              set:@selector(setPreferenceValue:specifier:)
                                                              get:@selector(readPreferenceValue:)
                                                           detail:nil cell:PSSliderCell edit:nil];
    [radius setProperty:kLMVPrefsID forKey:@"defaults"];
    [radius setProperty:@"CornerRadius" forKey:@"key"];
    [radius setProperty:@18.0 forKey:@"default"];
    [radius setProperty:@0.0 forKey:@"min"];
    [radius setProperty:@40.0 forKey:@"max"];
    [radius setProperty:@YES forKey:@"showValue"];

    _specifiers = [NSMutableArray arrayWithObjects:
        [PSSpecifier groupSpecifierWithName:@"锁屏消息视频"], enabled,
        [PSSpecifier groupSpecifierWithName:@"外观设置"], opacity, radius,
        [PSSpecifier groupSpecifierWithName:@"消息背景"],
        [self button:@"从相册导入消息背景视频" action:@selector(pickMessageVideo)],
        [self button:@"清除消息背景视频" action:@selector(clearMessageVideo)],
        [PSSpecifier groupSpecifierWithName:@"选项区域背景"],
        [self button:@"从相册导入选项区域视频" action:@selector(pickOptionsVideo)],
        [self button:@"清除选项区域视频" action:@selector(clearOptionsVideo)],
        [PSSpecifier groupSpecifierWithName:@"工具"],
        [self button:@"重新加载设置" action:@selector(reloadSettings)],
        [PSSpecifier groupSpecifierWithName:@"视频保存在 /var/mobile/LockMessageVideo/，设置会即时生效。"], nil];
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key || !value) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                              (__bridge CFPropertyListRef)value,
                              (__bridge CFStringRef)kLMVPrefsID);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kLMVPrefsID);
    LMVPostNotification(@"com.minis.lockmessagevideo/preferencesChanged");
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                                 (__bridge CFStringRef)kLMVPrefsID);
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)presentPickerForMode:(NSString *)mode {
    LMVPVideoPickerController *picker = [[LMVPVideoPickerController alloc] initWithMode:mode];
    UIViewController *presenter = self.navigationController ?: self;
    [presenter presentViewController:picker animated:YES completion:nil];
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

- (void)reloadSettings {
    _specifiers = nil;
    [self reloadSpecifiers];
}

@end
