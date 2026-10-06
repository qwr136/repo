#import "LMVPRootListController.h"
#import "LMVPVideoPickerController.h"

@implementation LMVPRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)pickMessageVideo {
    LMVPVideoPickerController *picker = [[LMVPVideoPickerController alloc] initWithMode:@"message"];
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)pickOptionsVideo {
    LMVPVideoPickerController *picker = [[LMVPVideoPickerController alloc] initWithMode:@"options"];
    [self.navigationController pushViewController:picker animated:YES];
}

- (void)clearMessageVideo {
    [[NSFileManager defaultManager] removeItemAtPath:@"/var/jb/var/mobile/Library/LockMessageVideo/message.mov" error:nil];
}

- (void)clearOptionsVideo {
    [[NSFileManager defaultManager] removeItemAtPath:@"/var/jb/var/mobile/Library/LockMessageVideo/options.mov" error:nil];
}

@end
