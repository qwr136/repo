#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <stdio.h>
#import <errno.h>

static NSString * const kLMVVideoPath = @"/var/mobile/LockMessageVideo/message.mov";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static CFStringRef const kLMVChanged = CFSTR("com.minis.lockmessagevideo/preferencesChanged");

@interface LMVPRootListController : PSListController <PHPickerViewControllerDelegate>
@end

@implementation LMVPRootListController

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"消息通知背景"];
    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用消息背景" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [enabled setProperty:@"MessageBackgroundEnabled" forKey:@"key"];
    [enabled setProperty:@NO forKey:@"default"];
    PSSpecifier *videoGroup = [PSSpecifier groupSpecifierWithName:@"视频"];
    PSSpecifier *choose = [PSSpecifier preferenceSpecifierNamed:@"选择消息背景视频" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    choose.buttonAction = @selector(chooseVideo:);
    PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:@"清除消息背景视频" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    clear.buttonAction = @selector(clearVideo:);
    PSSpecifier *info = [PSSpecifier preferenceSpecifierNamed:@"路径：/var/mobile/LockMessageVideo/message.mov" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    _specifiers = [[NSMutableArray alloc] initWithObjects:group, enabled, videoGroup, choose, clear, info, nil];
    return _specifiers;
}

- (id)enabled:(PSSpecifier *)specifier {
    NSNumber *value = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("MessageBackgroundEnabled"), kLMVPrefsID);
    return value ?: @NO;
}

- (void)setEnabled:(id)value specifier:(PSSpecifier *)specifier {
    CFPreferencesSetAppValue(CFSTR("MessageBackgroundEnabled"), (__bridge CFPropertyListRef)@([value boolValue]), kLMVPrefsID);
    CFPreferencesAppSynchronize(kLMVPrefsID);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kLMVChanged, NULL, NULL, YES);
}

- (void)chooseVideo:(PSSpecifier *)specifier {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    config.filter = [PHPickerFilter videosFilter];
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)clearVideo:(PSSpecifier *)specifier {
    [[NSFileManager defaultManager] removeItemAtPath:kLMVVideoPath error:nil];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kLMVChanged, NULL, NULL, YES);
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result || ![result.itemProvider hasItemConformingToTypeIdentifier:@"public.movie"]) return;
    [result.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
        NSError *copyError = error;
        if (url && !copyError) {
            NSString *dir = [kLMVVideoPath stringByDeletingLastPathComponent];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&copyError];
            NSString *temp = [dir stringByAppendingPathComponent:@".message.mov.tmp"];
            if (!copyError) {
                [[NSFileManager defaultManager] removeItemAtPath:temp error:nil];
                [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:temp] error:&copyError];
                if (!copyError) {
                    [[NSFileManager defaultManager] removeItemAtPath:kLMVVideoPath error:nil];
                    if (![[NSFileManager defaultManager] moveItemAtPath:temp toPath:kLMVVideoPath error:&copyError]) {
                        [[NSFileManager defaultManager] removeItemAtPath:temp error:nil];
                    }
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (copyError) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败" message:copyError.localizedDescription ?: @"无法复制视频" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            } else {
                CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), kLMVChanged, NULL, NULL, YES);
            }
        });
    }];
}
@end
