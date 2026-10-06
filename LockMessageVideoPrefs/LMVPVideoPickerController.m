#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>

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
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] init];
    config.filter = [PHPickerFilter videosFilter];
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) { [self.navigationController popViewControllerAnimated:YES]; return; }
    NSItemProvider *provider = result.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:@"public.movie"]) { [self.navigationController popViewControllerAnimated:YES]; return; }
    [provider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
        NSString *dir = @"/var/mobile/LockMessageVideo";
        NSString *filename = [self.mode isEqualToString:@"message"] ? @"message.mov" : @"options.mov";
        NSString *dstPath = [dir stringByAppendingPathComponent:filename];
        __block NSError *copyError = error;
        if (url && !copyError) {
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&copyError];
            if (!copyError) {
                [[NSFileManager defaultManager] removeItemAtPath:dstPath error:nil];
                [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:dstPath] error:&copyError];
            }
        }
        if (!copyError) {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, NULL, YES);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *title = copyError ? @"保存失败" : @"已保存";
            NSString *message = copyError ? (copyError.localizedDescription ?: @"无法复制视频") : @"视频已保存到 /var/mobile/LockMessageVideo/，锁屏视图将即时刷新。";
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self.navigationController popViewControllerAnimated:YES]; }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }];
}

@end
