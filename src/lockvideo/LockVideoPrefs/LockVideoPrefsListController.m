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

// 从 prefs 读出当前播放的视频文件名（用于「当前素材」那一行）
- (NSString *)_currentVideoName {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile];
    NSString *path = prefs[@"LockVideoPath"];
    if ([path isKindOfClass:[NSString class]] && path.length) {
        return [path lastPathComponent];
    }
    // 没显式选过就用目录里第一个视频作为兜底
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:kLVVideoDir error:nil];
    for (NSString *f in files) {
        NSString *ext = [f pathExtension].lowercaseString;
        if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
            [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"]) {
            return f;
        }
    }
    return @"(未选择)";
}

// 在「选择素材」按钮右侧显示当前素材名
- (void)_refreshCurrentMaterialRow {
    @try {
        PSSpecifier *target = nil;
        for (PSSpecifier *sp in [self specifiers]) {
            if ([[sp identifier] isEqualToString:@"LockVideoMaterialButton"]) { target = sp; break; }
        }
        if (target) {
            NSString *name = [self _currentVideoName];
            [target setProperty:name forKey:@"value"];
            [target setProperty:name forKey:@"detailText"];
            [self reloadSpecifier:target];
        }
    } @catch (NSException *e) {}
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self _refreshCurrentMaterialRow];
}

// 弹出选择界面：列出 /var/mobile/通知视频 里所有视频，点选播放
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

    // 当前选中的素材
    NSMutableDictionary *prefs = [[NSMutableDictionary dictionaryWithContentsOfFile:kLVPrefsFile]
                                  mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *cur = prefs[@"LockVideoPath"];

    // 选择界面：每个视频一个选项，当前选中的打勾
    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"选择素材（%lu 个）", (unsigned long)files.count]
        message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *f in files) {
        NSString *name = [f lastPathComponent];
        NSString *title = [f isEqualToString:cur] ? [@"✓ " stringByAppendingString:name] : name;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSMutableDictionary *p = [[NSMutableDictionary dictionaryWithContentsOfFile:kLVPrefsFile]
                                      mutableCopy] ?: [NSMutableDictionary dictionary];
            p[@"LockVideoPath"] = f;
            [p writeToFile:kLVPrefsFile atomically:YES];

            // 通知 SpringBoard 立即切换
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs"), NULL, NULL, YES);

            // 立刻刷新设置面板的「当前素材」那一行
            [self _refreshCurrentMaterialRow];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
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