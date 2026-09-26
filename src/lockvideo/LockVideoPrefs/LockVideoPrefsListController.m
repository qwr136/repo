#import "LockVideoPrefsListController.h"
#import <UIKit/UIKit.h>
#import <Preferences/Preferences.h>
#import <PhotosUI/PhotosUI.h>
#import <spawn.h>
#import <sys/wait.h>

#define kLVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.notifybgvideo.plist"
#define kLVVideoDir  @"/var/mobile/通知视频"

@interface LockVideoPrefsListController () <PHPickerViewControllerDelegate> {
    NSString *_currentSelectKey;   // 记录当前打开的是哪个素材选择器
}
@end

@implementation LockVideoPrefsListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

// 从 prefs 读出指定 key 的素材文件名
- (NSString *)_currentVideoNameForKey:(NSString *)key {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile];
    NSString *path = prefs[key];
    if ([path isKindOfClass:[NSString class]] && path.length) {
        return [path lastPathComponent];
    }
    return @"";
}

// 刷新指定 identifier 的素材选择行
- (void)_refreshMaterialRow:(NSString *)identifier prefsKey:(NSString *)key {
    @try {
        PSSpecifier *target = nil;
        for (PSSpecifier *sp in [self specifiers]) {
            if ([[sp identifier] isEqualToString:identifier]) { target = sp; break; }
        }
        if (target) {
            NSString *name = [self _currentVideoNameForKey:key];
            NSString *display = name.length ? [NSString stringWithFormat:@"（%@）", name] : @"";
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
    [self _refreshMaterialRow:@"LockVideoMaterialLink" prefsKey:@"LockVideoPath"];
    [self _refreshMaterialRow:@"LockVideoOptionMaterialLink" prefsKey:@"LockVideoOptionPath"];
    [self _refreshMaterialRow:@"LockVideoClearMaterialLink" prefsKey:@"LockVideoClearPath"];
}

// 通用素材选择器：把 key 对应的 prefs 项设为用户选中的文件
- (void)_switchMaterialForKey:(NSString *)key title:(NSString *)title sender:(id)sender {
    _currentSelectKey = key;

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
            message:[NSString stringWithFormat:@"%@ 里没有素材。\n请先用 Filza 把 mp4/mov/gif/png 放进这个文件夹，或用「从相册添加素材」。", kLVVideoDir]
            preferredStyle:UIAlertControllerStyleAlert];
        [empty addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:empty animated:YES completion:nil];
        return;
    }

    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile] ?: @{};
    NSString *cur = prefs[key];

    UIAlertController *sheet = [UIAlertController
        alertControllerWithTitle:title
        message:nil
        preferredStyle:UIAlertControllerStyleActionSheet];

    for (NSString *f in files) {
        NSString *name = [f lastPathComponent];
        NSString *actionTitle = [f isEqualToString:cur] ? [@"✓ " stringByAppendingString:name] : name;
        [sheet addAction:[UIAlertAction actionWithTitle:actionTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            NSMutableDictionary *p = [[NSMutableDictionary dictionaryWithContentsOfFile:kLVPrefsFile]
                                      mutableCopy] ?: [NSMutableDictionary dictionary];
            p[key] = f;
            [p writeToFile:kLVPrefsFile atomically:YES];

            CFNotificationCenterPostNotification(
                CFNotificationCenterGetDarwinNotifyCenter(),
                CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs"), NULL, NULL, YES);

            // 刷新对应行
            if ([key isEqualToString:@"LockVideoPath"]) {
                [self _refreshMaterialRow:@"LockVideoMaterialLink" prefsKey:key];
            } else if ([key isEqualToString:@"LockVideoOptionPath"]) {
                [self _refreshMaterialRow:@"LockVideoOptionMaterialLink" prefsKey:key];
            } else if ([key isEqualToString:@"LockVideoClearPath"]) {
                [self _refreshMaterialRow:@"LockVideoClearMaterialLink" prefsKey:key];
            }
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)switchMaterial:(id)sender {
    [self _switchMaterialForKey:@"LockVideoPath" title:@"选择当前素材" sender:sender];
}

- (void)switchOptionMaterial:(id)sender {
    [self _switchMaterialForKey:@"LockVideoOptionPath" title:@"选择选项按钮素材" sender:sender];
}

- (void)switchClearMaterial:(id)sender {
    [self _switchMaterialForKey:@"LockVideoClearPath" title:@"选择清除按钮素材" sender:sender];
}

#pragma mark - 从相册添加素材到素材目录（PHPicker：支持视频 / GIF / 图片）

- (void)addFromAlbum:(id)sender {
    @try {
        PHPickerConfiguration *cfg = [[PHPickerConfiguration alloc] init];
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
    if (results.count == 0) return;
    PHPickerResult *result = results.firstObject;
    NSItemProvider *provider = result.itemProvider;

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

    __block NSError *copyErr = nil;
    __block BOOL ok = NO;

    if ([fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:dst] error:&copyErr]) {
        ok = YES;
    } else {
        copyErr = nil;
        NSFileCoordinator *coord = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
        [coord coordinateReadingItemAtURL:url
                                   options:NSFileCoordinatorReadingWithoutChanges
                            writingItemAtURL:[NSURL fileURLWithPath:dst]
                                   options:NSFileCoordinatorWritingForReplacing
                                     error:&copyErr
                                byAccessor:^(NSURL *readURL, NSURL *writeURL) {
            if ([fm copyItemAtURL:readURL toURL:writeURL error:&copyErr]) {
                ok = YES;
            } else {
                NSError *streamErr = nil;
                if ([self _lvStreamCopyFromURL:readURL toURL:writeURL error:&streamErr]) {
                    ok = YES;
                } else {
                    copyErr = streamErr ?: [NSError errorWithDomain:@"LockVideoPrefs" code:-2 userInfo:@{NSLocalizedDescriptionKey: @"流式拷贝失败"}];
                }
            }
        }];
    }

    if (ok) {
        [fm setAttributes:@{NSFileProtectionKey: NSFileProtectionNone} ofItemAtPath:dst error:nil];
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _showAlertTitle:@"添加失败"
                          message:[NSString stringWithFormat:@"复制失败：%@", copyErr.localizedDescription ?: @"未知错误，可能是视频过大或相册未授权"]];
        });
        return;
    }
    cb(dst);
}

// POSIX 分块流式拷贝：适合大视频/GIF，不一次性映射或加载整文件
- (BOOL)_lvStreamCopyFromURL:(NSURL *)srcURL toURL:(NSURL *)dstURL error:(NSError **)outErr {
    const char *srcPath = [srcURL.path UTF8String];
    const char *dstPath = [dstURL.path UTF8String];
    int srcFD = open(srcPath, O_RDONLY);
    if (srcFD < 0) {
        if (outErr) *outErr = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: @"无法打开源文件"}];
        return NO;
    }
    int dstFD = open(dstPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (dstFD < 0) {
        close(srcFD);
        if (outErr) *outErr = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: @"无法创建目标文件"}];
        return NO;
    }

    char buffer[256 * 1024];
    BOOL success = NO;
    while (1) {
        ssize_t n = read(srcFD, buffer, sizeof(buffer));
        if (n == 0) { success = YES; break; }
        if (n < 0) {
            if (errno == EINTR) continue;
            if (outErr) *outErr = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: @"读取源文件失败"}];
            break;
        }
        size_t written = 0;
        while (written < (size_t)n) {
            ssize_t w = write(dstFD, buffer + written, (size_t)n - written);
            if (w < 0) {
                if (errno == EINTR) continue;
                if (outErr) *outErr = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{NSLocalizedDescriptionKey: @"写入目标文件失败"}];
                break;
            }
            written += w;
        }
        if (written < (size_t)n) break;
    }

    close(srcFD);
    close(dstFD);
    return success;
}

// 落盘后写 prefs + 通知 SpringBoard + 刷新设置面板
// 相册导入默认写入当前正在选择的 key；如果没有打开选择器，则默认写入主素材
- (void)_finishAddWithPath:(NSString *)path {
    if (!path) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        NSMutableDictionary *p = [[NSMutableDictionary dictionaryWithContentsOfFile:kLVPrefsFile]
                                  mutableCopy] ?: [NSMutableDictionary dictionary];
        NSString *key = _currentSelectKey ?: @"LockVideoPath";
        p[key] = path;
        [p writeToFile:kLVPrefsFile atomically:YES];

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs"), NULL, NULL, YES);

        if ([key isEqualToString:@"LockVideoPath"]) {
            [self _refreshMaterialRow:@"LockVideoMaterialLink" prefsKey:key];
        } else if ([key isEqualToString:@"LockVideoOptionPath"]) {
            [self _refreshMaterialRow:@"LockVideoOptionMaterialLink" prefsKey:key];
        } else if ([key isEqualToString:@"LockVideoClearPath"]) {
            [self _refreshMaterialRow:@"LockVideoClearMaterialLink" prefsKey:key];
        }
        [self _showAlertTitle:@"已添加素材"
                      message:[NSString stringWithFormat:@"已保存到素材目录：\n%@\n并设为「%@」", path, [self _titleForKey:key]]];
    });
}

- (NSString *)_titleForKey:(NSString *)key {
    if ([key isEqualToString:@"LockVideoOptionPath"]) return @"选项按钮素材";
    if ([key isEqualToString:@"LockVideoClearPath"]) return @"清除按钮素材";
    return @"当前素材";
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