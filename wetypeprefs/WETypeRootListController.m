#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface WETypeRootListController : PSListController
@end

@implementation WETypeRootListController

- (instancetype)init {
    self = [super init];
    if (self) {
        self.title = @"微信输入法工具栏增强";
    }
    return self;
}

/* 立即生效: 键盘进程每次布局会重新读取偏好, 无需重启键盘 */

- (void)resetDefaults {
    CFStringRef dom = CFSTR("com.wetypeplus");
    CFPreferencesSetAppValue(CFSTR("maxButtons"),  (__bridge CFPropertyListRef)@20, dom);
    CFPreferencesSetAppValue(CFSTR("hSpacing"),   (__bridge CFPropertyListRef)@0,  dom);
    CFPreferencesSetAppValue(CFSTR("leftMargin"), (__bridge CFPropertyListRef)@0,  dom);
    CFPreferencesSetAppValue(CFSTR("rightMargin"),(__bridge CFPropertyListRef)@0,  dom);
    CFPreferencesAppSynchronize(dom);
    [self reloadSpecifiers];
}

@end
