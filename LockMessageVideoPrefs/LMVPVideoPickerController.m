#import "LMVPVideoPickerController.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>

@interface LMVPVideoPickerController () <PHPickerViewControllerDelegate>
@property (nonatomic, copy) NSString *mode;
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
    if (!result) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    NSItemProvider *provider = result.itemProvider;
    if (![provider hasItemConformingToTypeIdentifier:@"public.movie"]) {
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    [provider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
        if (!url) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.navigationController popViewControllerAnimated:YES];
            });
            return;
        }
        NSString *dir = @"/var/jb/var/mobile/Library/LockMessageVideo";
        [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *dst = [dir stringByAppendingPathComponent:[self.mode isEqualToString:@"message"] ? @"message.mov" : @"options.mov"];
        [[NSFileManager defaultManager] removeItemAtPath:dst error:nil];
        [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:dst] error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已保存" message:@"视频已复制，建议注销或重启 SpringBoard 生效。" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self.navigationController popViewControllerAnimated:YES];
            }]];
            [self presentViewController:alert animated:YES completion:nil];
        });
    }];
}

@end
