#import "QWRNetSpeedRootListController.h"
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>

@implementation QWRNetSpeedRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (NSString *)prefsPath {
    NSString *rootful = @"/var/mobile/Library/Preferences/cn.qwr136.netspeed.plist";
    NSString *rootless = @"/var/jb/var/mobile/Library/Preferences/cn.qwr136.netspeed.plist";
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:rootful]) return rootful;
    if ([fm fileExistsAtPath:rootless]) return rootless;
    return rootless;
}

- (void)resetPosition {
    NSString *path = [self prefsPath];
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:path];
    if (!d) d = [NSMutableDictionary dictionary];
    [d removeObjectForKey:@"posX"];
    [d removeObjectForKey:@"posY"];
    [d writeToFile:path atomically:YES];

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("cn.qwr136.netspeed/relayout"),
                                         NULL, NULL, YES);

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"悬浮网速"
                                                                   message:@"悬浮窗位置已重置"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
