#import "MsgVideoPrefsListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/Preferences.h>
#import <spawn.h>
#import <sys/wait.h>

#define kMVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.msgbgvideo.plist"
#define kMVVideoDir  @"/var/mobile/信息视频"

@implementation MsgVideoPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// 从 prefs 读出当前播放的视频文件名（用于自定义 MsgVideoMaterialCell 显示）
- (NSString *)_currentVideoName {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kMVPrefsFile];
    NSString *path = prefs[@"MsgVideoPath"];
    if ([path isKindOfClass:[NSString class]] && path.length) {
        return [path lastPathComponent];
    }
    // 没显式选过就用目录里第一个视频作为兜底
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:kMVVideoDir error:nil];
    for (NSString *f in files) {
        NSString *ext = [f pathExtension].lowercaseString;
        if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
            [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"]) {
            return f;
        }
    }
    return @"";   // 目录里也没视频时为空，单元格显示空白
}

// 刷新「切换视频」那一行：选完素材后立即显示新文件名
- (void)_refreshCurrentMaterialRow {
    @try {
        PSSpecifier *target = nil;
        for (PSSpecifier *sp in [self specifiers]) {
            if ([[sp identifier] isEqualToString:@"MsgVideoMaterialLink"]) { target = sp; break; }
        }
        if (target) {
            NSString *name = [self _currentVideoName];
            NSString *display = name.length
                ? [NSString stringWithFormat:@"（%@）", name] : @"";
            [target setProperty:display forKey:@"detailText"];
            [target setProperty:display forKey:@"value"];

            @try {
                PSTableCell *cached = [self cachedCellForSpecifier:target];
                if (cached && [cached isKindOfClass:[PSTableCell class]]) {
                    [cached refreshCellContentsWithSpecifier:target];
                }
            } @catch (NSException *e) {}

            [self reloadSpecifier:target];
        }
    } @catch (NSException *e) {}
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self _refreshCurrentMaterialRow];
}

// 弹出选择界面：列出 /var/mobile/信息视频 里所有视频，点选播放
- (void)switchMaterial:(id)sender {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *f in [fm contentsOfDirectoryAtPath:kMVVideoDir error:nil]) {
        NSString *ext = [f pathExtension].lowercaseString;
        if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
            [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"]) {
            [files addObject:[kMVVideoDir stringByAppendingPathComponent:f]];
        }
    }
    [files sortUsingSelector:@selector(compare:)];

    if (files.count == 0) {
        UIAlertController *empty = [UIAlertController
            alertControllerWithTitle:@"没有素材"
            message:[NSString stringWithFormat:@"%@ 里没有视频文件。\n请先用 Filza 把 mp4/mov 放进这个文件夹。", kMVVideoDir]
            preferredStyle:UIAlertControllerStyleAlert];
        [empty addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:empty animated:YES completion:nil];
        return;
    }

    NSMutableDictionary *prefs = [[NSMutableDictionary dictionaryWithContentsOfFile:kMVPrefsFile]
                                  mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *cur = prefs[@"MsgVideoPath"];

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"切换视频（%lu 个）", (unsigned long)files.count]
        message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *f in files) {
        NSString *name = [f lastPathComponent];
        NSString *title = [f isEqualToString:cur] ? [@"✓ " stringByAppendingString:name] : name;
        [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSMutableDictionary *p = [[NSMutableDictionary dictionaryWithContentsOfFile:kMVPrefsFile]
                                      mutableCopy] ?: [NSMutableDictionary dictionary];
            p[@"MsgVideoPath"] = f;
            [p writeToFile:kMVPrefsFile atomically:YES];

            // 通知信息 App 立即切换
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFSTR("com.xiaofei.msgbgvideo/ReloadPrefs"), NULL, NULL, YES);

            [self _refreshCurrentMaterialRow];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

// 重启信息 App（让设置立即生效）
- (void)restartMessages:(id)sender {
    pid_t pid = 0;
    char * const argv[] = { (char *)"killall", (char *)"MobileSMS", NULL };
    posix_spawn(&pid, "/var/jb/usr/bin/killall", NULL, NULL, argv, NULL);
    posix_spawn(&pid, "/usr/bin/killall", NULL, NULL, argv, NULL);
}

@end
