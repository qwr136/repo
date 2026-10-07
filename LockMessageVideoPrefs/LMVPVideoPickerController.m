#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>

static const unsigned long long LMVMaxImportBytes = 5ULL * 1024ULL * 1024ULL;
static NSString * const LMVImportDomain = @"com.minis.lockmessagevideo.import";

@interface LMVPVideoPickerController : UIViewController
- (instancetype)initWithMode:(NSString *)mode;
@end

@interface LMVPVideoPickerController () <PHPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *mode;
@property (nonatomic, assign) BOOL didPresentPicker;
@end

@implementation LMVPVideoPickerController

- (instancetype)initWithMode:(NSString *)mode {
    if ((self = [super init])) {
        _mode = [mode copy];
        self.title = [mode isEqualToString:@"message"] ? @"选择消息视频" : @"选择选项视频";
    }
    return self;
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.didPresentPicker) return;
    self.didPresentPicker = YES;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    config.filter = [PHPickerFilter videosFilter];
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (NSError *)importError:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:LMVImportDomain code:code userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (void)finishWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *title = error ? @"导入失败" : @"导入成功";
        NSString *message = error ? @"原始素材已删除" : @"视频已保存，锁屏视图将即时刷新。";
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
            [self.navigationController popViewControllerAnimated:YES];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)processPickedURL:(NSURL *)url error:(NSError *)loadError {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *dir = @"/var/mobile/LockMessageVideo";
    NSString *filename = [self.mode isEqualToString:@"message"] ? @"message.mov" : @"options.mov";
    NSString *dstPath = [dir stringByAppendingPathComponent:filename];
    NSString *token = NSUUID.UUID.UUIDString;
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"LockMessageVideo-%@", token]];
    NSString *sourcePath = [tempDir stringByAppendingPathComponent:@"source.mov"];
    NSString *outputPath = [tempDir stringByAppendingPathComponent:@"optimized.mp4"];
    NSError *error = loadError;
    BOOL success = NO;
    [fm createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:&error];
    if (!error && (!url || ![fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:sourcePath] error:&error])) {
        if (!error) error = [self importError:1 description:@"无法读取视频文件"];
    }
    unsigned long long bytes = 0;
    if (!error) bytes = [fm attributesOfItemAtPath:sourcePath error:&error].fileSize;
    if (!error && bytes <= LMVMaxImportBytes) {
        // Keep the source outside the library until the final atomic move.
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error];
        if (!error) {
            [fm removeItemAtPath:dstPath error:nil];
            success = [fm moveItemAtPath:sourcePath toPath:dstPath error:&error];
        }
    } else if (!error) {
        AVAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:sourcePath] options:nil];
        AVAssetTrack *videoTrack = asset.tracks.firstObject;
        for (AVAssetTrack *track in asset.tracks) if ([track.mediaType isEqualToString:AVMediaTypeVideo]) { videoTrack = track; break; }
        NSArray<NSString *> *presets = @[AVAssetExportPresetMedium, AVAssetExportPreset1280x720, AVAssetExportPreset640x480, AVAssetExportPresetLowQuality];
        NSArray<NSString *> *compatible = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
        if (!videoTrack || CMTimeGetSeconds(asset.duration) <= 0 || !compatible.count) {
            error = [self importError:2 description:@"无法创建兼容的视频优化任务"];
        } else {
            BOOL exported = NO;
            for (NSString *preset in presets) {
                if (![compatible containsObject:preset]) continue;
                [fm removeItemAtPath:outputPath error:nil];
                AVAssetExportSession *exporter = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
                NSArray<AVFileType> *types = exporter.supportedFileTypes;
                AVFileType outputType = [types containsObject:AVFileTypeMPEG4] ? AVFileTypeMPEG4 : types.firstObject;
                if (!outputType) continue;
                exporter.outputURL = [NSURL fileURLWithPath:outputPath];
                exporter.outputFileType = outputType;
                exporter.shouldOptimizeForNetworkUse = NO;
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                [exporter exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(semaphore); }];
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                unsigned long long candidateSize = [fm attributesOfItemAtPath:outputPath error:nil].fileSize;
                if (exporter.status == AVAssetExportSessionStatusCompleted && candidateSize > 0 && candidateSize <= LMVMaxImportBytes) { exported = YES; break; }
            }
            if (!exported) error = [self importError:3 description:@"视频优化失败或仍超过5MiB"];
        }
        unsigned long long outBytes = 0;
        if (!error) outBytes = [fm attributesOfItemAtPath:outputPath error:&error].fileSize;
        if (!error) {
            AVAsset *checked = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:outputPath] options:nil];
            AVAssetTrack *checkedVideo = nil;
            for (AVAssetTrack *track in checked.tracks) if ([track.mediaType isEqualToString:AVMediaTypeVideo]) { checkedVideo = track; break; }
            if (outBytes == 0 || outBytes > LMVMaxImportBytes || !checkedVideo || CMTimeGetSeconds(checked.duration) <= 0) error = [self importError:4 description:@"优化后视频校验失败"];
        }
        if (!error) {
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error];
            if (!error) { [fm removeItemAtPath:dstPath error:nil]; success = [fm moveItemAtPath:outputPath toPath:dstPath error:&error]; }
        }
    }
    [fm removeItemAtPath:sourcePath error:nil];
    [fm removeItemAtPath:outputPath error:nil];
    [fm removeItemAtPath:tempDir error:nil];
    if (success && !error) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, NULL, YES);
    [self finishWithError:(success && !error) ? nil : (error ?: [self importError:5 description:@"导入失败"])];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) { [self.navigationController popViewControllerAnimated:YES]; return; }
    NSItemProvider *provider = result.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:@"public.movie"]) {
        [self finishWithError:[self importError:6 description:@"无法读取视频文件"]];
        return;
    }
    [provider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
        [self processPickedURL:url error:error];
    }];
}

@end
