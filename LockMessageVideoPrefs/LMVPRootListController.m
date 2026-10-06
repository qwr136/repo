#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "LMVPRootListController.h"
#import "LMVPVideoPickerController.h"
#import <stdlib.h>

static NSString * const kLMVDir = @"/var/jb/var/mobile/Library/LockMessageVideo";
static NSString * const kLMVPrefs = @"/var/jb/var/mobile/Library/Preferences/com.minis.lockmessagevideo.plist";

@implementation LMVPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)pickMessageVideo {
    [self.navigationController pushViewController:[[LMVPVideoPickerController alloc] initWithMode:@"message"] animated:YES];
}

- (void)pickOptionsVideo {
    [self.navigationController pushViewController:[[LMVPVideoPickerController alloc] initWithMode:@"options"] animated:YES];
}

- (void)clearMessageVideo {
    [[NSFileManager defaultManager] removeItemAtPath:[kLMVDir stringByAppendingPathComponent:@"message.mov"] error:nil];
    [self reloadSpecifiers];
}

- (void)clearOptionsVideo {
    [[NSFileManager defaultManager] removeItemAtPath:[kLMVDir stringByAppendingPathComponent:@"options.mov"] error:nil];
    [self reloadSpecifiers];
}

- (void)openPreview {
    if (![self respondsToSelector:@selector(presentViewController:animated:completion:)]) return;
    UIViewController *preview = [[UIViewController alloc] init];
    preview.view.backgroundColor = [UIColor systemBackgroundColor];
    preview.title = @"视频预览";
    NSArray *items = @[@"message.mov", @"options.mov"];
    CGFloat y = 120;
    for (NSString *file in items) {
        NSString *path = [kLMVDir stringByAppendingPathComponent:file];
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) continue;
        AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:path]];
        AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
        layer.frame = CGRectMake(20, y, preview.view.bounds.size.width - 40, 160);
        layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [preview.view.layer addSublayer:layer];
        [player play];
        y += 180;
    }
    [self.navigationController pushViewController:preview animated:YES];
}

- (void)respring {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认注销" message:@"将重新加载锁屏界面。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"注销" style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) {
        system("killall -9 SpringBoard");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
