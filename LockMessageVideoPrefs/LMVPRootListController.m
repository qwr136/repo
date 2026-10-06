#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

static NSString * const kLMVPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.minis.lockmessagevideo.plist";

@interface LMVPRootListController : PSListController
@end

@implementation LMVPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用锁屏视图诊断" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [enabled setProperty:@"Enabled" forKey:@"key"];
        [enabled setProperty:@NO forKey:@"default"];
        _specifiers = [NSMutableArray arrayWithObjects:
            [PSSpecifier groupSpecifierWithName:@"锁屏消息视频 · 诊断版"],
            enabled,
            [PSSpecifier groupSpecifierWithName:@"开启后，插件会记录 SpringBoard 锁屏窗口和通知视图层级。"],
            [PSSpecifier groupSpecifierWithName:@"日志路径：/var/mobile/LockMessageVideo/view-tree.log"], nil];
    }
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSMutableDictionary *p = [NSMutableDictionary dictionaryWithContentsOfFile:kLMVPrefsPath] ?: [NSMutableDictionary dictionary];
    NSString *key = [specifier propertyForKey:@"key"];
    if (key && value) [p setObject:value forKey:key];
    [p writeToFile:kLMVPrefsPath atomically:YES];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, NULL, YES);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:kLMVPrefsPath] ?: @{};
    return p[[specifier propertyForKey:@"key"]] ?: [specifier propertyForKey:@"default"];
}

@end
