#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>

@interface LMVPVideoPickerController : UIViewController
- (instancetype)initWithMode:(NSString *)mode;
@end

@interface LMVPVideoPickerController () <PHPickerViewControllerDelegate>
@property(nonatomic,copy) NSString *mode;
@property(nonatomic) BOOL didPresentPicker;
@end

@implementation LMVPVideoPickerController
static NSString * const LMVRoot = @"/var/mobile/LockMessageVideo";
static NSString * const LMVOriginals = @"/var/mobile/LockMessageVideo/原素材";

static BOOL LMVValidMovie(NSURL *url) {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    if ([attrs[NSFileSize] unsignedLongLongValue] == 0) return NO;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
    dispatch_semaphore_t ready = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:@[@"playable", @"duration", @"tracks"] completionHandler:^{ dispatch_semaphore_signal(ready); }];
    dispatch_semaphore_wait(ready, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    NSError *error = nil;
    AVKeyValueStatus status = [asset statusOfValueForKey:@"playable" error:&error];
    if (status != AVKeyValueStatusLoaded || !asset.playable) return NO;
    status = [asset statusOfValueForKey:@"duration" error:&error];
    return status == AVKeyValueStatusLoaded && CMTIME_IS_NUMERIC(asset.duration) && CMTimeGetSeconds(asset.duration) > 0 && [asset tracksWithMediaType:AVMediaTypeVideo].count > 0;
}

static void LMVExport(NSURL *source, NSURL *destination, void (^completion)(NSError *)) {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:source options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
    NSArray *presets = @[AVAssetExportPreset1280x720, AVAssetExportPreset960x540, AVAssetExportPreset640x480];
    __block void (^attempt)(NSUInteger);
    attempt = ^(NSUInteger index) {
        if (index >= presets.count) { completion([NSError errorWithDomain:@"LockMessageVideo" code:2 userInfo:@{NSLocalizedDescriptionKey:@"系统无法生成可播放的压缩视频"}]); return; }
        AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:presets[index]];
        AVFileType type = AVFileTypeQuickTimeMovie;
        if (!session || ![session.supportedFileTypes containsObject:type]) { attempt(index + 1); return; }
        [[NSFileManager defaultManager] removeItemAtURL:destination error:nil];
        session.outputURL = destination; session.outputFileType = type; session.shouldOptimizeForNetworkUse = YES;
        [session exportAsynchronouslyWithCompletionHandler:^{
            BOOL valid = session.status == AVAssetExportSessionStatusCompleted && LMVValidMovie(destination);
            if (valid) completion(nil); else { [[NSFileManager defaultManager] removeItemAtURL:destination error:nil]; attempt(index + 1); }
        }];
    };
    attempt(0);
}

- (instancetype)initWithMode:(NSString *)mode { if ((self = [super init])) { _mode = [mode copy]; self.title = [mode isEqualToString:@"message"] ? @"选择消息视频" : @"选择选项视频"; } return self; }
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; if (self.didPresentPicker) return; self.didPresentPicker = YES;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary]; config.filter = [PHPickerFilter videosFilter]; config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil]; PHPickerResult *result = results.firstObject;
    if (!result || ![result.itemProvider hasItemConformingToTypeIdentifier:@"public.movie"]) { [self.navigationController popViewControllerAnimated:YES]; return; }
    [result.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
        NSString *filename = [self.mode isEqualToString:@"message"] ? @"message.mov" : @"options.mov";
        NSString *dstPath = [LMVRoot stringByAppendingPathComponent:filename];
        NSString *originalPath = [LMVOriginals stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.mov", filename.stringByDeletingPathExtension, NSUUID.UUID.UUIDString]];
        __block NSError *saveError = error;
        if (url && !saveError) {
            NSFileManager *fm = NSFileManager.defaultManager;
            [fm createDirectoryAtPath:LMVRoot withIntermediateDirectories:YES attributes:nil error:&saveError];
            if (!saveError) [fm createDirectoryAtPath:LMVOriginals withIntermediateDirectories:YES attributes:nil error:&saveError];
            if (!saveError) [fm copyItemAtURL:url toURL:[NSURL fileURLWithPath:originalPath] error:&saveError];
            if (!saveError) {
                unsigned long long size = [[fm attributesOfItemAtPath:originalPath error:nil][NSFileSize] unsignedLongLongValue];
                if (size <= 5ULL * 1024ULL * 1024ULL) { [fm removeItemAtPath:dstPath error:nil]; [fm copyItemAtPath:originalPath toPath:dstPath error:&saveError]; }
                else { dispatch_semaphore_t sem = dispatch_semaphore_create(0); LMVExport([NSURL fileURLWithPath:originalPath], [NSURL fileURLWithPath:dstPath], ^(NSError *e) { saveError = e; dispatch_semaphore_signal(sem); }); dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER); }
            }
        }
        if (!saveError) CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, NULL, YES);
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *message = saveError ? [NSString stringWithFormat:@"%@\n原素材仍保留在 %@", saveError.localizedDescription ?: @"无法生成可播放视频", originalPath] : [NSString stringWithFormat:@"视频已保存到 %@\n原素材保留在 %@", dstPath, originalPath];
            UIAlertController *a = [UIAlertController alertControllerWithTitle:saveError ? @"保存失败" : @"已保存" message:message preferredStyle:UIAlertControllerStyleAlert];
            [a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *x) { [self.navigationController popViewControllerAnimated:YES]; }]]; [self presentViewController:a animated:YES completion:nil];
        });
    }];
}
@end
