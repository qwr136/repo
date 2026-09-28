#import <UIKit/UIKit.h>
#import "PSListController.h"

@interface WXKeyboardToolbarPrefsRootListController : PSListController
@end

@implementation WXKeyboardToolbarPrefsRootListController

#define kPrefsDomain CFSTR("com.xiaofei.wxkeyboardtoolbar")
#define kPrefsChanged CFSTR("com.xiaofei.wxkeyboardtoolbar/preferences.changed")

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// 读取持久化值（若不存在则返回 default）
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (!key) return [specifier propertyForKey:@"default"];

    id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key, kPrefsDomain));
    if (!value) {
        value = [specifier propertyForKey:@"default"];
    }
    return value;
}

// 写入持久化值并通知 tweak 实时刷新
- (void)setPreferenceValue:(id)value forKey:(NSString *)key {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kPrefsDomain);
    CFPreferencesAppSynchronize(kPrefsDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kPrefsChanged, NULL, NULL, YES);
}

@end
