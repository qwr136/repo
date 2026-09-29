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
    CFPreferencesSetAppValue(CFSTR("maxButtons"), @20, CFSTR("com.wetypeplus"));
    CFPreferencesSetAppValue(CFSTR("hSpacing"), @0, CFSTR("com.wetypeplus"));
    CFPreferencesSetAppValue(CFSTR("leftMargin"), @0, CFSTR("com.wetypeplus"));
    CFPreferencesSetAppValue(CFSTR("rightMargin"), @0, CFSTR("com.wetypeplus"));
    CFPreferencesAppSynchronize(CFSTR("com.wetypeplus"));
    [self reloadSpecifiers];
}

@end
