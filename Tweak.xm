#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

static NSString * const kLMVPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.minis.lockmessagevideo.plist";
static NSString * const kLMVVideoPath = @"/var/mobile/LockMessageVideo/message.mov";

static NSDictionary *LMVPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kLMVPrefsPath] ?: @{};
}

static BOOL LMVMessageBackgroundEnabled(void) {
    return [LMVPrefs()[@"MessageBackgroundEnabled"] boolValue];
}

static CGFloat LMVVideoOpacity(void) {
    NSNumber *value = LMVPrefs()[@"MessageBackgroundOpacity"];
    return value ? MAX(0.1, MIN(1.0, value.floatValue)) : 0.55;
}

static AVPlayerLayer *LMVFindLayer(UIView *host) {
    for (CALayer *layer in host.layer.sublayers ?: @[]) {
        if ([layer.name isEqualToString:@"com.minis.lockmessagevideo.layer"] && [layer isKindOfClass:[AVPlayerLayer class]]) {
            return (AVPlayerLayer *)layer;
        }
    }
    return nil;
}

static void LMVRemoveLayer(UIView *host) {
    AVPlayerLayer *layer = LMVFindLayer(host);
    [layer removeFromSuperlayer];
}

static void LMVInstallLayer(UIView *host) {
    if (!host || host.bounds.size.width < 20 || host.bounds.size.height < 20) return;
    if (!LMVMessageBackgroundEnabled() || ![[NSFileManager defaultManager] fileExistsAtPath:kLMVVideoPath]) {
        LMVRemoveLayer(host);
        return;
    }

    AVPlayerLayer *layer = LMVFindLayer(host);
    if (!layer) {
        AVPlayer *player = [AVPlayer playerWithURL:[NSURL fileURLWithPath:kLMVVideoPath]];
        player.muted = YES;
        player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        layer = [AVPlayerLayer playerLayerWithPlayer:player];
        layer.name = @"com.minis.lockmessagevideo.layer";
        layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        layer.zPosition = -1000.0;
        [host.layer insertSublayer:layer atIndex:0];
        [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:player.currentItem queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
            [player seekToTime:kCMTimeZero];
            [player play];
        }];
        [player play];
    }
    layer.frame = host.bounds;
    layer.opacity = LMVVideoOpacity();
    host.layer.masksToBounds = YES;
}

%hook NCNotificationListCell
- (void)layoutSubviews {
    %orig;
    LMVInstallLayer((UIView *)self);
}
%end

%hook NCNotificationListView
- (void)layoutSubviews {
    %orig;
    if (!LMVMessageBackgroundEnabled()) return;
    for (UIView *view in self.subviews ?: @[]) {
        if ([view isKindOfClass:NSClassFromString(@"NCNotificationListCell")]) LMVInstallLayer(view);
    }
}
%end

static void LMVRefreshNotifications(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in [(UIWindowScene *)scene windows]) {
                for (UIView *view in window.subviews ?: @[]) {
                    if ([view isKindOfClass:NSClassFromString(@"NCNotificationListCell")]) LMVInstallLayer(view);
                }
            }
        }
    });
}

static void LMVDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    LMVRefreshNotifications();
}

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] createDirectoryAtPath:@"/var/mobile/LockMessageVideo" withIntermediateDirectories:YES attributes:nil error:nil];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
