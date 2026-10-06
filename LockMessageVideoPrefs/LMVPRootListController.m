#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "LMVPVideoPickerController.h"

static NSString * const kLMVDir = @"/var/jb/var/mobile/Library/LockMessageVideo";
static NSString * const kLMVPrefs = @"/var/jb/var/mobile/Library/Preferences/com.minis.lockmessagevideo.plist";

@interface LMVPRootListController : PSListController
@end

@implementation LMVPRootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"锁屏消息视频";
}

- (PSSpecifier *)button:(NSString *)title action:(NSString *)action {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [s setProperty:action forKey:@"action"];
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

        _specifiers = @[
            [PSSpecifier groupSpecifierWithName:@"锁屏消息视频"],
            enabled,
            [PSSpecifier groupSpecifierWithName:@"外观设置"],
            opacity,
            radius,
            [PSSpecifier groupSpecifierWithName:@"消息背景"],
            [self button:@"选择消息背景视频" action:@"pickMessageVideo"],
            [self button:@"清除消息背景视频" action:@"clearMessageVideo"],
            [PSSpecifier groupSpecifierWithName:@"选项区域背景"],
            [self button:@"选择选项视频背景" action:@"pickOptionsVideo"],
            [self button:@"清除选项视频背景" action:@"clearOptionsVideo"],
            [PSSpecifier groupSpecifierWithName:@"工具"],
            [self button:@"预览效果页面" action:@"openPreview"],
            [self button:@"重新加载设置" action:@"reloadSettings"],
            [PSSpecifier groupSpecifierWithName:@"选择视频后请注销或重启 SpringBoard。"]
        ];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSMutableDictionary *prefs = [NSMutableDictionary dictionaryWithContentsOfFile:kLMVPrefs] ?: [NSMutableDictionary dictionary];
    NSString *key = [specifier propertyForKey:@"key"];
    if (key && value) [prefs setObject:value forKey:key];
    [prefs writeToFile:kLMVPrefs atomically:YES];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kLMVPrefs] ?: @{};
    id value = prefs[[specifier propertyForKey:@"key"]];
    return value ?: [specifier propertyForKey:@"default"];
}

- (void)pickMessageVideo {
    [self.navigationController pushViewController:[[LMVPVideoPickerController alloc] initWithMode:@"message"] animated:YES];
}

- (void)pickOptionsVideo {
    [self.navigationController pushViewController:[[LMVPVideoPickerController alloc] initWithMode:@"options"] animated:YES];
}

- (void)clearMessageVideo {
    [[NSFileManager defaultManager] removeItemAtPath:[kLMVDir stringByAppendingPathComponent:@"message.mov"] error:nil];
}

- (void)clearOptionsVideo {
    [[NSFileManager defaultManager] removeItemAtPath:[kLMVDir stringByAppendingPathComponent:@"options.mov"] error:nil];
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
