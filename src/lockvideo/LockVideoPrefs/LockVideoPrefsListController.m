#import "LockVideoPrefsListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/Preferences.h>
#import <spawn.h>
#import <sys/wait.h>

#define kLVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.notifybgvideo.plist"
#define kLVVideoDir  @"/var/mobile/通知视频"

@implementation LockVideoPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// 扫描 /var/mobile/通知视频 里的视频，循环切换到下一个
- (void)switchMaterial:(id)sender {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *f in [fm contentsOfDirectoryAtPath:kLVVideoDir error:nil]) {
        NSString *ext = [f pathExtension].lowercaseString;
        if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
            [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"]) {
            [files addObject:[kLVVideoDir stringByAppendingPathComponent:f]];
        }
    }
    [files sortUsingSelector:@selector(compare:)];

    if (files.count == 0) {
        UIAlertController *empty = [UIAlertController
            alertControllerWithTitle:@"没有素材"
            message:[NSString stringWithFormat:@"%@ 里没有视频文件。\n请先用 Filza 把 mp4/mov 放进这个文件夹。", kLVVideoDir]
            preferredStyle:UIAlertControllerStyleAlert];
        [empty addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:empty animated:YES completion:nil];
        return;
    }

    // 读取当前路径，循环切到下一个
    NSMutableDictionary *prefs = [[NSMutableDictionary dictionaryWithContentsOfFile:kLVPrefsFile]
                                  mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *cur = prefs[@"LockVideoPath"];
    NSUInteger idx = cur ? [files indexOfObject:cur] : NSNotFound;
    NSString *next = files[(idx == NSNotFound) ? 0 : (idx + 1) % files.count];

    prefs[@"LockVideoPath"] = next;
    [prefs writeToFile:kLVPrefsFile atomically:YES];

    // 通知 SpringBoard 重建播放器
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs"), NULL, NULL, YES);

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:@"已切换素材"
        message:[NSString stringWithFormat:@"当前播放：\n%@", [next lastPathComponent]]
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)respring:(id)sender {
    char * const argv[] = { (char *)"sbreload", NULL };
    pid_t pid = 0;
    posix_spawn(&pid, "/var/jb/usr/bin/sbreload", NULL, NULL, argv, NULL);
    posix_spawn(&pid, "/usr/bin/sbreload", NULL, NULL, argv, NULL);
    char * const kargv[] = { (char *)"killall", (char *)"backboardd", NULL };
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, kargv, NULL);
}

@end
