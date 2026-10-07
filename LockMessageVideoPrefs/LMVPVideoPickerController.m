#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>

static const unsigned long long LMVMaxImportBytes = 5ULL * 1024ULL * 1024ULL;

@interface LMVPVideoPickerController : UIViewController
- (instancetype)initWithMode:(NSString *)mode;
@end

@interface LMVPVideoPickerController () <PHPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *mode;
@property (nonatomic, assign) BOOL didPresentPicker;
@end

@implementation LMVPVideoPickerController

- (instancetype)initWithMode:(NSString *)mode {
    if ((self = [super init])) { _mode = [mode copy]; self.title = [mode isEqualToString:@"message"] ? @"选择消息视频" : @"选择选项视频"; }
    return self;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.didPresentPicker) return;
    self.didPresentPicker = YES;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    config.filter = [PHPickerFilter videosFilter]; config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)finishWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *title = error ? @"保存失败" : @"已保存";
        NSString *message = error ? (error.localizedDescription ?: @"无法导入视频") : @"视频已保存到 /var/mobile/LockMessageVideo/，锁屏视图将即时刷新。";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self.navigationController popViewControllerAnimated:YES]; }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) { [self.navigationController popViewControllerAnimated:YES]; return; }
    NSItemProvider *provider = result.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:@"public.movie"]) { [self.navigationController popViewControllerAnimated:YES]; return; }
    [provider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
        if (!url || error) { [self finishWithError:error ?: [NSError errorWithDomain:@"LockMessageVideo" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法读取视频文件"}]]; return; }
        NSString *dir = @"/var/mobile/LockMessageVideo";
        NSString *filename = [self.mode isEqualToString:@"message"] ? @"message.mov" : @"options.mov";
        NSString *dstPath = [dir stringByAppendingPathComponent:filename];
        NSString *tempPath = [dir stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.import-%@.tmp", filename, NSUUID.UUID.UUIDString]];
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error];
        if (error) { [self finishWithError:error]; return; }
        unsigned long long bytes = [[fm attributesOfItemAtPath:url.path error:&error].fileSize unsignedLongLongValue];
        if (error) { [self finishWithError:error]; return; }
        if (bytes <= LMVMaxImportBytes) {
            [fm removeItemAtPath:dstPath error:nil];
            [fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:dstPath] error:&error];
        } else {
            AVAsset *asset = [AVAsset URLAssetWithURL:url options:nil];
            AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:asset presetName:AVAssetExportPresetLowQuality];
            if (!exporter) { error = [NSError errorWithDomain:@"LockMessageVideo" code:2 userInfo:@{NSLocalizedDescriptionKey:@"无法创建视频优化任务"}]; }
            if (!error) {
                exporter.outputURL = [NSURL fileURLWithPath:tempPath]; exporter.outputFileType = AVFileTypeMPEG4; exporter.shouldOptimizeForNetworkUse = NO;
                dispatch_semaphore_t sem = dispatch_semaphore_create(0);
                [exporter exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(sem); }];
                dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
                if (exporter.status != AVAssetExportSessionStatusCompleted) error = exporter.error ?: [NSError errorWithDomain:@"LockMessageVideo" code:3 userInfo:@{NSLocalizedDescriptionKey:@"视频优化失败"}];
            }
            if (!error) {
                unsigned long long outBytes = [[fm attributesOfItemAtPath:tempPath error:&error].fileSize unsignedLongLongValue];
                AVAsset *check = [AVAsset URLAssetWithURL:[NSURL fileURLWithPath:tempPath] options:nil];
                if (outBytes > LMVMaxImportBytes || !check.isPlayable || !check.tracks.count) error = [NSError errorWithDomain:@"LockMessageVideo" code:4 userInfo:@{NSLocalizedDescriptionKey:@"优化后视频校验失败"}];
            }
            if (!error) { [fm removeItemAtPath:dstPath error:nil]; [fm moveItemAtPath:tempPath toPath:dstPath error:&error]; }
            [fm removeItemAtPath:tempPath error:nil];
        }
        if (!error) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, NULL, YES);
        [self finishWithError:error];
    }];
}
@end
