#import "LockVideoPrefsListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/Preferences.h>
#import <PhotosUI/PhotosUI.h>
#import <spawn.h>
#import <sys/wait.h>

#define kLVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.notifybgvideo.plist"
#define kLVVideoDir  @"/var/mobile/通知视频"

@interface LockVideoPrefsListController () <PHPickerViewControllerDelegate>
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

#pragma mark - 从相册添加素材到素材目录（PHPicker：支持视频 / GIF / 图片）

- (void)addFromAlbum:(id)sender {
    @try {
        PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
        // 同时支持视频与图片（含 GIF），PHPicker 会自动显示所有类型
        cfg.filter = [PHPickerFilter anyFilterMatchingSubfilters:@[
            [PHPickerFilter imagesFilter],
            [PHPickerFilter videosFilter]
        ]];
        cfg.selectionLimit = 1;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:cfg];
        picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    } @catch (NSException *e) {
        [self _showAlertTitle:@"出错" message:[e description]];
    }
}

// PHPicker 代理：选中后由系统给出 NSItemProvider，我们据此判断类型并落盘
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    if (results.count == 0) return;   // 用户取消
    PHPickerResult *result = results.firstObject;
    NSItemProvider *provider = result.itemProvider;

    // 1) 视频（含 mov/mp4/m4v 等所有 public.movie 类型）
    if ([provider hasItemConformingToTypeIdentifier:@"public.movie"]) {
        [provider loadFileRepresentationForTypeIdentifier:@"public.movie"
            completionHandler:^(NSURL *url, NSError *err) {
                [self _copyPickedFile:url fallbackExt:@"mp4"
                            completion:^(NSString *path) {
                                [self _finishAddWithPath:path];
                            }];
            }];
        return;
    }
    // 2) GIF：优先保留为 .gif 文件（保留动画）；PHPicker 会给出 com.compuserve.gif 标识
    if ([provider hasItemConformingToTypeIdentifier:@"com.compuserve.gif"]) {
        [provider loadFileRepresentationForTypeIdentifier:@"com.compuserve.gif"
            completionHandler:^(NSURL *url, NSError *err) {
                [self _copyPickedFile:url fallbackExt:@"gif"
                            completion:^(NSString *path) {
                                [self _finishAddWithPath:path];
                            }];
            }];
        return;
    }
    // 3) 普通图片（jpg/png/heic 等）
    if ([provider hasItemConformingToTypeIdentifier:@"public.image"]) {
        [provider loadObjectOfClass:[UIImage class]
            completionHandler:^(id<NSItemProviderReading> obj, NSError *err) {
                if (![obj isKindOfClass:[UIImage class]]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self _showAlertTitle:@"添加失败" message:@"无法读取所选图片。"];
                    });
                    return;
                }
                UIImage *img = (UIImage *)obj;
                NSFileManager *fm = [NSFileManager defaultManager];
                NSData *data = UIImageJPEGRepresentation(img, 0.9);
                NSString *ext = @"jpg";
                if (!data) { data = UIImagePNGRepresentation(img); ext = @"png"; }
                if (![fm fileExistsAtPath:kLVVideoDir]) {
                    [fm createDirectoryAtPath:kLVVideoDir withIntermediateDirectories:YES attributes:nil error:nil];
                }
                NSString *dst = [kLVVideoDir stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@.%@", [self _stamp], ext]];
                if (![data writeToFile:dst atomically:YES]) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self _showAlertTitle:@"添加失败" message:@"无法保存图片。"];
                    });
                    return;
                }
                [self _finishAddWithPath:dst];
            }];
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self _showAlertTitle:@"暂不支持" message:@"该素材类型暂不支持导入。"];
    });
}

// 把 PHPicker 给出的临时文件（视频/GIF）拷贝到素材目录
// 关键：loadFileRepresentation 给的 URL 只在回调内有效，必须立刻拷贝
// 修复：长视频用 NSFileCoordinator + mapped reading，避免 dataWithContentsOfURL 把整个文件读进内存导致 OOM 失败
- (void)_copyPickedFile:(NSURL *)url fallbackExt:(NSString *)fallbackExt completion:(void(^)(NSString *path))cb {
    if (!url) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _showAlertTitle:@"添加失败" message:@"无法读取所选文件。"];
        });
        return;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:kLVVideoDir]) {
        [fm createDirectoryAtPath:kLVVideoDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *ext = [url pathExtension].lowercaseString;
    if (ext.length == 0) ext = fallbackExt;
    NSString *dst = [kLVVideoDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"%@.%@", [self _stamp], ext]];
    [fm removeItemAtPath:dst error:nil];

    NSError *copyErr = nil;
    BOOL ok = NO;

    // 方案 A：直接 copyItem（iOS 上对 PHPicker 的临时 URL 通常有效，但长视频可能因后台清理失败）
    if ([fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:dst] error:&copyErr]) {
        ok = YES;
    } else {
        // 方案 B：用 NSFileCoordinator 协调读 + 流式写入（mapped reading，大文件友好）
        copyErr = nil;
        NSFileCoordinator *coord = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coord coordinateReadingItemAtURL:url
                                   options:NSFileCoordinatorReadingWithoutChanges
                            writingItemAtURL:[NSURL fileURLWithPath:dst]
                                   options:NSFileCoordinatorWritingForReplacing
                                     error:&copyErr
                                byAccessor:^(NSURL *readURL, NSURL *writeURL) {
            NSError *readErr = nil;
            // mapped reading：内核态 mmap，物理内存压力下也不会 OOM
            NSData *data = [NSData dataWithContentsOfURL:readURL
                                                  options:NSDataReadingMappedIfSafe
                                                    error:&readErr];
            if (data && data.length > 0) {
                NSError *writeErr = nil;
                if ([data writeToURL:writeURL
                             options:NSDataWritingAtomic | NSDataWritingFileProtectionCompleteUnlessOpen
                               error:&writeErr]) {
                    ok = YES;
                } else {
                    copyErr = writeErr;
                }
            } else {
                copyErr = readErr ?: [NSError errorWithDomain:@"LockVideoPrefs" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"读取文件失败"}];
            }
        }];
    }

    if (!ok) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _showAlertTitle:@"添加失败"
                          message:[NSString stringWithFormat:@"复制失败：%@", copyErr.localizedDescription ?: @"未知错误，可能是视频过大或相册未授权"]];
        });
        return;
    }
    cb(dst);
}

// 落盘后写 prefs + 通知 SpringBoard + 刷新设置面板
- (void)_finishAddWithPath:(NSString *)path {
    if (!path) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary *p = [[NSMutableDictionary dictionaryWithContentsOfFile:kLVPrefsFile]
                                  mutableCopy] ?: [NSMutableDictionary dictionary];
        p[@"LockVideoPath"] = path;
        [p writeToFile:kLVPrefsFile atomically:YES];
        // 通知 SpringBoard 立即应用新素材
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs"), NULL, NULL, YES);
        [self _refreshCurrentMaterialRow];
        [self _showAlertTitle:@"已添加素材"
                      message:[NSString stringWithFormat:@"已保存到素材目录：\n%@", path]];
    });
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