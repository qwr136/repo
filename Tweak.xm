#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

static NSString * const kLMVPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.minis.lockmessagevideo.plist";
static NSString * const kLMVBaseDir = @"/var/jb/var/mobile/Library/LockMessageVideo";
static NSString * const kLMVMessageVideo = @"/var/jb/var/mobile/Library/LockMessageVideo/message.mov";
static NSString * const kLMVOptionsVideo = @"/var/jb/var/mobile/Library/LockMessageVideo/options.mov";

static BOOL LMVEnabled(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kLMVPrefsPath] ?: @{};
    return [prefs[@"Enabled"] boolValue];
}

static AVPlayerLayer *LMVEnsureVideoLayer(UIView *host, NSString *name, NSString *path) {
    if (!host || ![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;
    NSString *tag = [@"lmv." stringByAppendingString:name];
    for (CALayer *layer in host.layer.sublayers ?: @[]) {
        if ([layer.name isEqualToString:tag] && [layer isKindOfClass:[AVPlayerLayer class]]) {
            layer.frame = host.bounds;
            return (AVPlayerLayer *)layer;
        }
    }
    NSURL *url = [NSURL fileURLWithPath:path];
    AVPlayer *player = [AVPlayer playerWithURL:url];
    player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:player.currentItem queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
        [player seekToTime:kCMTimeZero];
        [player play];
    }];
    AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
    layer.name = tag;
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    layer.frame = host.bounds;
    layer.zPosition = -999;
    [host.layer insertSublayer:layer atIndex:0];
    [player play];
    return layer;
}

static void LMVAttachToCandidates(UIView *root) {
    if (!LMVEnabled() || !root) return;
    NSArray<UIView *> *subs = root.subviews ?: @[];
    for (UIView *v in subs) {
        NSString *cls = NSStringFromClass([v class]);
        if ([cls containsString:@"Notification"] || [cls containsString:@"ShortLook"] || [cls containsString:@"Platter"]) {
            LMVEnsureVideoLayer(v, @"message", kLMVMessageVideo);
        }
        if ([cls containsString:@"Action"] || [cls containsString:@"Button"] || [cls containsString:@"Reveal"] || [cls containsString:@"Option"]) {
            LMVEnsureVideoLayer(v, @"options", kLMVOptionsVideo);
        }
        if (v.subviews.count) LMVAttachToCandidates(v);
    }
}

%hook CSCoverSheetViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    LMVAttachToCandidates(self.view);
}
- (void)viewDidLayoutSubviews {
    %orig;
    LMVAttachToCandidates(self.view);
}
%end

%hook NCNotificationShortLookView
- (void)layoutSubviews {
    %orig;
    if (LMVEnabled()) {
        LMVEnsureVideoLayer((UIView *)self, @"message", kLMVMessageVideo);
    }
}
%end

%hook UIView
- (void)layoutSubviews {
    %orig;
    if (!LMVEnabled()) return;
    NSString *cls = NSStringFromClass([self class]);
    if ([cls containsString:@"Action"] || [cls containsString:@"Option"] || [cls containsString:@"ClearButton"]) {
        LMVEnsureVideoLayer((UIView *)self, @"options", kLMVOptionsVideo);
    }
}
%end

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] createDirectoryAtPath:kLMVBaseDir withIntermediateDirectories:YES attributes:nil error:nil];
    }
}
