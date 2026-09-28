#import <UIKit/UIKit.h>
#import "PSListController.h"

@interface WXKeyboardToolbarPrefsRootListController : PSListController
@end

@implementation WXKeyboardToolbarPrefsRootListController

#define kPrefsFileName @"com.xiaofei.wxkeyboardtoolbar.plist"
#define kPrefsChanged  CFSTR("com.xiaofei.wxkeyboardtoolbar/preferences.changed")

// rootless 下不同进程看到的 Preferences 路径可能不同，同时写两处，读时优先存在的那处
static NSArray<NSString *> *wkPrefsPaths(void) {
    static NSArray<NSString *> *paths = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        paths = @[
            [@"/var/mobile/Library/Preferences" stringByAppendingPathComponent:kPrefsFileName],
            [@"/var/jb/var/mobile/Library/Preferences" stringByAppendingPathComponent:kPrefsFileName]
        ];
    });
    return paths;
}

static NSMutableDictionary *wkLoadPrefs(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in wkPrefsPaths()) {
        if ([fm fileExistsAtPath:path]) {
            NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:path];
            if ([d isKindOfClass:[NSDictionary class]]) {
                return [d mutableCopy];
            }
        }
    }
    return [NSMutableDictionary dictionary];
}

static void wkSavePrefs(NSDictionary *prefs) {
    if (!prefs) return;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *path in wkPrefsPaths()) {
        NSString *dir = [path stringByDeletingLastPathComponent];
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:@{NSFileOwnerAccountName:@"mobile", NSFileGroupOwnerAccountName:@"mobile"} error:nil];
        }
        [prefs writeToFile:path atomically:YES];
        // 确保 mobile 用户可读写
        [fm setAttributes:@{NSFileOwnerAccountName:@"mobile", NSFileGroupOwnerAccountName:@"mobile", NSFilePosixPermissions:@(0644)} ofItemAtPath:path error:nil];
    }
}

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    id def = [specifier propertyForKey:@"default"];
    if (!key) return def;

    NSMutableDictionary *prefs = wkLoadPrefs();
    id value = prefs[key];
    if (value == nil) {
        // 首次使用：把默认值写进去
        if (def) {
            prefs[key] = def;
            wkSavePrefs(prefs);
        }
        return def;
    }

    // 统一转成 Settings 期望的类型
    NSString *cell = [specifier propertyForKey:@"cell"];
    if ([cell isEqualToString:@"PSEditTextCell"] || [cell isEqualToString:@"PSTextFieldCell"]) {
        if ([value isKindOfClass:[NSNumber class]]) {
            return [value stringValue];
        }
        return value;
    }
    if ([cell isEqualToString:@"PSSwitchCell"]) {
        if ([value isKindOfClass:[NSNumber class]]) {
            return value;
        }
        if ([value isKindOfClass:[NSString class]]) {
            return @([value integerValue] != 0);
        }
        return def ?: @NO;
    }
    return value;
}

- (void)setPreferenceValue:(id)value forKey:(NSString *)key {
    if (!key) return;

    NSMutableDictionary *prefs = wkLoadPrefs();
    prefs[key] = value ?: @"";
    wkSavePrefs(prefs);

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         kPrefsChanged, NULL, NULL, YES);
}

@end
