#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "LMVPVideoPickerController.h"

static NSString * const kLMVDir = @"/var/mobile/LockMessageVideo";
static NSString * const kLMVPrefs = @"/var/jb/var/mobile/Library/Preferences/com.minis.lockmessagevideo.plist";

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
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [s setProperty:NSStringFromSelector(action) forKey:@"action"];
    return s;
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用插件" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [enabled setProperty:@"com.minis.lockmessagevideo" forKey:@"defaults"];
        [enabled setProperty:@"Enabled" forKey:@"key"];
        [enabled setProperty:@NO forKey:@"default"];

        PSSpecifier *opacity = [PSSpecifier preferenceSpecifierNamed:@"视频透明度" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSliderCell edit:nil];
        [opacity setProperty:@"com.minis.lockmessagevideo" forKey:@"defaults"];
        [opacity setProperty:@"Opacity" forKey:@"key"];
        [opacity setProperty:@0.85 forKey:@"default"];
        [opacity setProperty:@0.05 forKey:@"min"];
        [opacity setProperty:@1.0 forKey:@"max"];
        [opacity setProperty:@YES forKey:@"showValue"];

        PSSpecifier *radius = [PSSpecifier preferenceSpecifierNamed:@"圆角大小" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSliderCell edit:nil];
        [radius setProperty:@"com.minis.lockmessagevideo" forKey:@"defaults"];
        [radius setProperty:@"CornerRadius" forKey:@"key"];
        [radius setProperty:@18.0 forKey:@"default"];
        [radius setProperty:@0.0 forKey:@"min"];
        [radius setProperty:@40.0 forKey:@"max"];
        [radius setProperty:@YES forKey:@"showValue"];

        _specifiers = [NSMutableArray arrayWithObjects:
            [PSSpecifier groupSpecifierWithName:@"锁屏消息视频"], enabled,
            [PSSpecifier groupSpecifierWithName:@"外观设置"], opacity, radius,
            [PSSpecifier groupSpecifierWithName:@"消息背景"],
            [self button:@"选择消息背景视频" action:@selector(pickMessageVideo)],
            [self button:@"清除消息背景视频" action:@selector(clearMessageVideo)],
            [PSSpecifier groupSpecifierWithName:@"选项区域背景"],
            [self button:@"选择选项视频背景" action:@selector(pickOptionsVideo)],
            [self button:@"清除选项视频背景" action:@selector(clearOptionsVideo)],
            [PSSpecifier groupSpecifierWithName:@"工具"],
            [self button:@"预览效果页面" action:@selector(openPreview)],
            [self button:@"重新加载设置" action:@selector(reloadSettings)],
            [PSSpecifier groupSpecifierWithName:@"选择视频后会立即保存；锁屏视图会即时读取新设置。"], nil];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kLMVPrefs] ?: [NSMutableDictionary dictionary];
    NSString *key = [specifier propertyForKey:@"key"];
    if (key && value) [prefs setObject:value forKey:key];
    [prefs writeToFile:kLMVPrefs atomically:YES];
    LMVPostNotification(@"com.minis.lockmessagevideo/preferencesChanged");
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kLMVPrefs] ?: @{};
    id value = prefs[[specifier propertyForKey:@"key"]];
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)pickMessageVideo { [self.navigationController pushViewController:[[LMVPVideoPickerController alloc] initWithMode:@"message"] animated:YES]; }
- (void)pickOptionsVideo { [self.navigationController pushViewController:[[LMVPVideoPickerController alloc] initWithMode:@"options"] animated:YES]; }
- (void)clearMessageVideo {
    [[NSFileManager defaultManager] removeItemAtPath:[kLMVDir stringByAppendingPathComponent:@"message.mov"] error:nil];
    LMVPostNotification(@"com.minis.lockmessagevideo/videoChanged");
}
- (void)clearOptionsVideo {
    [[NSFileManager defaultManager] removeItemAtPath:[kLMVDir stringByAppendingPathComponent:@"options.mov"] error:nil];
    LMVPostNotification(@"com.minis.lockmessagevideo/videoChanged");
}
- (void)openPreview { UIAlertController *a = [UIAlertController alertControllerWithTitle:@"预览" message:@"视频将在锁屏通知区域循环播放。" preferredStyle:UIAlertControllerStyleAlert]; [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:a animated:YES completion:nil]; }
- (void)reloadSettings { _specifiers = nil; [self reloadSpecifiers]; }

@end
