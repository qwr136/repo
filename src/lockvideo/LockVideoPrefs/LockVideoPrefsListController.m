#import "LockVideoPrefsListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/Preferences.h>
#import <spawn.h>
#import <sys/wait.h>

#define kLVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.notifybgvideo.plist"
#define kLVVideoDir  @"/var/mobile/通知视频"

@interface LockVideoPrefsListController () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@end

@implementation LockVideoPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// 从 prefs 读出当前播放的视频文件名（用于自定义 LockVideoMaterialCell 显示）
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
            [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"] ||
            [ext isEqualToString:@"gif"] || [ext isEqualToString:@"png"] ||
            [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] ||
            [ext isEqualToString:@"heic"]) {
            return f;
        }
    }
    return @"";   // 目录里也没视频时为空，单元格显示空白
}

// 刷新「选择素材」那一行：选完素材后立即让单元格显示新文件名
- (void)_refreshCurrentMaterialRow {
    @try {
        PSSpecifier *target = nil;
        for (PSSpecifier *sp in [self specifiers]) {
            if ([[sp identifier] isEqualToString:@"LockVideoMaterialLink"]) { target = sp; break; }
        }
        if (target) {
            NSString *name = [self _currentVideoName];
            // 没选素材时显示空白（不再显示「未选择」提示字）
            NSString *display = name.length
                ? [NSString stringWithFormat:@"（%@）", name] : @"";
            [target setProperty:display forKey:@"detailText"];
            [target setProperty:display forKey:@"value"];

            // 拿到已显示的 cell 并主动刷新（reloadSpecifier 未必一定触发框架的 refreshCellContentsWithSpecifier:）
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

// 弹出选择界面：列出 /var/mobile/通知视频 里所有视频，点选播放
- (void)switchMaterial:(id)sender {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray *files = [NSMutableArray array];
    for (NSString *f in [fm contentsOfDirectoryAtPath:kLVVideoDir error:nil]) {
        NSString *ext = [f pathExtension].lowercaseString;
        if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
            [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"] ||
            [ext isEqualToString:@"gif"] || [ext isEqualToString:@"png"] ||
            [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] ||
            [ext isEqualToString:@"heic"]) {
            [files addObject:[kLVVideoDir stringByAppendingPathComponent:f]];
        }
    }
    [files sortUsingSelector:@selector(compare:)];

    if (files.count == 0) {
        UIAlertController *empty = [UIAlertController
            alertControllerWithTitle:@"没有素材"
            message:[NSString stringWithFormat:@"%@ 里没有素材。\n请先用 Filza 把 mp4/mov/gif/png 放进这个文件夹。", kLVVideoDir]
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

#pragma mark - 从相册添加素材到素材目录

- (void)addFromAlbum:(id)sender {
    @try {
        if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypePhotoLibrary]) {
            [self _showAlertTitle:@"无法访问相册" message:@"当前设备不支持相册访问。"];
            return;
        }
        UIImagePickerController *picker = [[UIImagePickerController alloc] init];
        picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
        // public.movie = 视频，public.image = 图片/GIF
        picker.mediaTypes = @[@"public.movie", @"public.image"];
        picker.videoQuality = UIImagePickerControllerQualityTypeHigh;
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } @catch (NSException *e) {
        [self _showAlertTitle:@"出错" message:[e description]];
    }
}

- (void)imagePickerController:(UIImagePickerController *)picker
    didFinishPickingMediaWithInfo:(NSDictionary *)info {
    @try {
        NSString *type = info[UIImagePickerControllerMediaType];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSString *dir = kLVVideoDir;
        if (![fm fileExistsAtPath:dir]) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }

        NSString *savedPath = nil;
        if ([type isEqualToString:@"public.movie"]) {
            NSURL *url = info[UIImagePickerControllerMediaURL];
            if (url) {
                NSString *ext = [url pathExtension].lowercaseString;
                if (ext.length == 0) { ext = @"mp4"; }
                NSString *dst = [dir stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.%@", [self _stamp], ext]];
                [fm removeItemAtPath:dst error:nil];
                if ([fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:dst] error:nil]) {
                    savedPath = dst;
                }
            }
        } else {
            UIImage *img = info[UIImagePickerControllerOriginalImage];
            if (img) {
                NSData *data = UIImageJPEGRepresentation(img, 0.9);
                NSString *ext = @"jpg";
                if (!data) { data = UIImagePNGRepresentation(img); ext = @"png"; }
                NSString *dst = [dir stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.%@", [self _stamp], ext]];
                if (data && [data writeToFile:dst atomically:YES]) { savedPath = dst; }
            }
        }

        [picker dismissViewControllerAnimated:YES completion:^{
            if (savedPath) {
                NSMutableDictionary *p = [[NSMutableDictionary dictionaryWithContentsOfFile:kLVPrefsFile]
                                          mutableCopy] ?: [NSMutableDictionary dictionary];
                p[@"LockVideoPath"] = savedPath;
                [p writeToFile:kLVPrefsFile atomically:YES];
                // 通知 SpringBoard 立即应用新素材
                CFNotificationCenterPostNotification(
                    CFNotificationCenterGetDarwinNotifyCenter(),
                    CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs"), NULL, NULL, YES);
                [self _refreshCurrentMaterialRow];
                [self _showAlertTitle:@"已添加素材"
                              message:[NSString stringWithFormat:@"已保存到素材目录：\n%@", savedPath]];
            } else {
                [self _showAlertTitle:@"添加失败" message:@"无法保存所选素材，请重试。"];
            }
        }];
    } @catch (NSException *e) {
        [picker dismissViewControllerAnimated:YES completion:^{
            [self _showAlertTitle:@"出错" message:[e description]];
        }];
    }
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

// 生成素材文件名时间戳（相册_YYYYMMDD_HHMMSS）
- (NSString *)_stamp {
    NSDateFormatter *f = [[NSDateFormatter alloc] init];
    [f setDateFormat:@"yyyyMMdd_HHmmss"];
    return [@"相册_" stringByAppendingString:[f stringFromDate:[NSDate date]]];
}

- (void)_showAlertTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title
                                                               message:msg
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
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