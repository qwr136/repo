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

// 从 prefs 读出当前播放的视频文件名（用于自定义 LockVideoMaterialCell 显示）
- (NSString *)_currentVideoName {
    return [self _videoNameForKey:@"LockVideoPath" fallback:nil];
}

// 素材文件名：优先读 key 对应的设置，没单独选过则跟随 fallbackKey（通知素材）
- (NSString *)_videoNameForKey:(NSString *)key fallback:(NSString *)fallbackKey {
    NSString *n = [self _currentVideoNameForKey:key];
    if (n.length) return n;
    if (fallbackKey.length) return [self _currentVideoNameForKey:fallbackKey];
    return @"";
}

- (NSString *)_currentVideoNameForKey:(NSString *)key {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile];
    NSString *path = prefs[key];
    if ([path isKindOfClass:[NSString class]] && path.length) {
        return [path lastPathComponent];
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *files = [fm contentsOfDirectoryAtPath:kLVVideoDir error:nil];
    for (NSString *f in files) {
        NSString *ext = [f pathExtension].lowercaseString;
        if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
            [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"]) {
            return f;
        }
    }
    return @"";
}

// 通用：刷新素材选择行（identifier 定位行，key 读文件名，没选过跟随通知素材）
- (void)_refreshMaterialRowWithIdentifier:(NSString *)ident key:(NSString *)key {
    @try {
        PSSpecifier *target = nil;
        for (PSSpecifier *sp in [self specifiers]) {
            if ([[sp identifier] isEqualToString:ident]) { target = sp; break; }
        }
        if (target) {
            NSString *name = [self _videoNameForKey:key fallback:@"LockVideoPath"];
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

- (void)_refreshCurrentMaterialRow {
    [self _refreshMaterialRowWithIdentifier:@"LockVideoMaterialLink" key:@"LockVideoPath"];
}

- (void)_refreshDesktopMaterialRow {
    [self _refreshMaterialRowWithIdentifier:@"LockVideoDesktopMaterialLink" key:@"LockVideoDesktopPath"];
}

- (void)_refreshLockBgMaterialRow {
    [self _refreshMaterialRowWithIdentifier:@"LockVideoLockBgMaterialLink" key:@"LockVideoLockBgPath"];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self _refreshCurrentMaterialRow];
    [self _refreshDesktopMaterialRow];
    [self _refreshLockBgMaterialRow];
}

// 列出 /var/mobile/通知视频 里所有视频
- (NSMutableArray *)_videoFiles {
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
    return files;
}

- (void)_showEmptyAlert {
    UIAlertController *empty = [UIAlertController
        alertControllerWithTitle:@"没有素材"
        message:[NSString stringWithFormat:@"%@ 里没有视频文件。\n请先用 Filza 把 mp4/mov 放进这个文件夹。", kLVVideoDir]
        preferredStyle:UIAlertControllerStyleAlert];
    [empty addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:empty animated:YES completion:nil];
}

// 通用素材选择：选中后写入 prefsKey，并刷新 ident 那一行
- (void)_pickMaterialForPrefsKey:(NSString *)prefsKey
                           title:(NSString *)title
                      refreshIdent:(NSString *)ident {
    NSMutableArray *files = [self _videoFiles];
    if (files.count == 0) { [self _showEmptyAlert]; return; }

    NSMutableDictionary *prefs = [[NSMutableDictionary dictionaryWithContentsOfFile:kLVPrefsFile]
                                  mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *cur = prefs[prefsKey] ?: prefs[@"LockVideoPath"];

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"%@（%lu 个）", title, (unsigned long)files.count]
        message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *f in files) {
        NSString *name = [f lastPathComponent];
        NSString *itemTitle = [f isEqualToString:cur] ? [@"✓ " stringByAppendingString:name] : name;
        [sheet addAction:[UIAlertAction actionWithTitle:itemTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSMutableDictionary *p = [[NSMutableDictionary dictionaryWithContentsOfFile:kLVPrefsFile]
                                      mutableCopy] ?: [NSMutableDictionary dictionary];
            p[prefsKey] = f;
            [p writeToFile:kLVPrefsFile atomically:YES];

            // 通知 SpringBoard 立即切换
            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs"), NULL, NULL, YES);

            // 立刻刷新设置面板对应行
            [self _refreshMaterialRowWithIdentifier:ident key:prefsKey];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

// 通知素材
- (void)switchMaterial:(id)sender {
    [self _pickMaterialForPrefsKey:@"LockVideoPath"
                             title:@"选择素材"
                      refreshIdent:@"LockVideoMaterialLink"];
}

// 桌面素材
- (void)switchDesktopMaterial:(id)sender {
    [self _pickMaterialForPrefsKey:@"LockVideoDesktopPath"
                             title:@"选择桌面素材"
                      refreshIdent:@"LockVideoDesktopMaterialLink"];
}

// 锁屏背景素材
- (void)switchLockMaterial:(id)sender {
    [self _pickMaterialForPrefsKey:@"LockVideoLockBgPath"
                             title:@"选择锁屏背景素材"
                      refreshIdent:@"LockVideoLockBgMaterialLink"];
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
