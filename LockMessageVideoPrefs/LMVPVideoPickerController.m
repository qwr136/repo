#import <UIKit/UIKit.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import "LMVImport.h"

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
    if ((self = [super init])) { _mode = [mode copy]; self.title = [mode isEqualToString:@"message"] ? @"选择消息视频" : @"选择选项视频"; }
    return self;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.didPresentPicker) return;
    self.didPresentPicker = YES;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    config.filter = [PHPickerFilter videosFilter]; config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (NSError *)importError:(NSInteger)code description:(NSString *)description { return [NSError errorWithDomain:LMVImportDomain code:code userInfo:@{NSLocalizedDescriptionKey: description}]; }
- (void)finishWithError:(NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:(error ? @"导入失败" : @"导入成功") message:(error ? error.localizedDescription : @"视频已保存，锁屏视图将即时刷新。") preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [self.navigationController popViewControllerAnimated:YES]; }]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}
- (void)processPickedURL:(NSURL *)url error:(NSError *)loadError {
    NSError *error = loadError;
    if (!error && !url) error = [self importError:1 description:@"无法读取视频文件"];
    NSString *relative = !error ? LMVImportMovie(url, &error) : nil;
    if (relative && !error) {
        NSString *key=[self.mode isEqualToString:@"message"] ? @"MessageVideo" : @"OptionsVideo";
        CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)relative,CFSTR("com.minis.lockmessagevideo"));
        CFPreferencesAppSynchronize(CFSTR("com.minis.lockmessagevideo"));
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, NULL, YES);
    }
    [self finishWithError:(relative && !error) ? nil : (error ?: [self importError:2 description:@"导入失败"])];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil]; PHPickerResult *result = results.firstObject;
    if (!result) { [self.navigationController popViewControllerAnimated:YES]; return; }
    NSItemProvider *provider = result.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:@"public.movie"]) { [self finishWithError:[self importError:3 description:@"无法读取视频文件"]]; return; }
    [provider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) { [self processPickedURL:url error:error]; }];
}
@end
