#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

static NSString * const kLMVPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.minis.lockmessagevideo.plist";
static NSString * const kLMVBaseDir = @"/var/mobile/LockMessageVideo";
static NSString * const kLMVMessageVideo = @"/var/mobile/LockMessageVideo/message.mov";
static NSString * const kLMVOptionsVideo = @"/var/mobile/LockMessageVideo/options.mov";
static void LMVAttachToCandidates(UIView *root);

static NSDictionary *LMVPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kLMVPrefsPath] ?: @{};
}

static BOOL LMVEnabled(void) {
    return [LMVPrefs()[@"Enabled"] boolValue];
}

static CGFloat LMVOpacity(void) {
    id v = LMVPrefs()[@"Opacity"];
    return v ? MAX(0.05, MIN(1.0, [v floatValue])) : 0.85;
}

static CGFloat LMVCornerRadius(void) {
    id v = LMVPrefs()[@"CornerRadius"];
    return v ? MAX(0.0, MIN(40.0, [v floatValue])) : 18.0;
}

static BOOL LMVShouldUseMessageView(NSString *cls) {
    NSArray *keys = @[@"Notification", @"ShortLook", @"Platter", @"CombinedList", @"ListCell", @"ContentView", @"HeaderContent", @"MaterialView"];
    for (NSString *k in keys) if ([cls containsString:k]) return YES;
    return NO;
}

static BOOL LMVShouldUseOptionsView(NSString *cls) {
    NSArray *keys = @[@"Action", @"Button", @"Reveal", @"Option", @"Clear", @"Swipe", @"Utility"];
    for (NSString *k in keys) if ([cls containsString:k]) return YES;
    return NO;
}

static AVPlayerLayer *LMVExistingLayer(UIView *host, NSString *name) {
    NSString *tag = [@"lmv." stringByAppendingString:name];
    for (CALayer *layer in host.layer.sublayers ?: @[]) {
        if ([layer.name isEqualToString:tag] && [layer isKindOfClass:[AVPlayerLayer class]]) {
            return (AVPlayerLayer *)layer;
        }
    }
    return nil;
}

static void LMVApplyHostStyle(UIView *host) {
    host.clipsToBounds = YES;
    host.layer.cornerRadius = LMVCornerRadius();
}

static AVPlayerLayer *LMVEnsureVideoLayer(UIView *host, NSString *name, NSString *path) {
    if (!host || host.bounds.size.width < 20 || host.bounds.size.height < 20) return nil;
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) return nil;

    AVPlayerLayer *existing = LMVExistingLayer(host, name);
    if (existing) {
        existing.frame = host.bounds;
        existing.opacity = LMVOpacity();
        LMVApplyHostStyle(host);
        return existing;
    }

    NSURL *url = [NSURL fileURLWithPath:path];
    AVPlayer *player = [AVPlayer playerWithURL:url];
    player.muted = YES;
    player.actionAtItemEnd = AVPlayerActionAtItemEndNone;

    [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:player.currentItem queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
        [player seekToTime:kCMTimeZero];
        [player play];
    }];

    AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
    layer.name = [@"lmv." stringByAppendingString:name];
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    layer.frame = host.bounds;
    layer.opacity = LMVOpacity();
    layer.zPosition = -999;
    [host.layer insertSublayer:layer atIndex:0];
    LMVApplyHostStyle(host);
    [player play];
    return layer;
}

static void LMVRemoveLayersIfNeeded(UIView *view) {
    if (LMVEnabled()) return;
    NSMutableArray *toRemove = [NSMutableArray array];
    for (CALayer *layer in view.layer.sublayers ?: @[]) {
        if ([layer.name hasPrefix:@"lmv."]) [toRemove addObject:layer];
    }
    for (CALayer *layer in toRemove) [layer removeFromSuperlayer];
}

static void LMVAttachToCandidates(UIView *root) {
    if (!root) return;
    if (!LMVEnabled()) {
        LMVRemoveLayersIfNeeded(root);
        for (UIView *v in root.subviews ?: @[]) LMVAttachToCandidates(v);
        return;
    }

    for (UIView *v in root.subviews ?: @[]) {
        NSString *cls = NSStringFromClass([v class]);
        if (LMVShouldUseMessageView(cls)) {
            LMVEnsureVideoLayer(v, @"message", kLMVMessageVideo);
        }
        if (LMVShouldUseOptionsView(cls)) {
            LMVEnsureVideoLayer(v, @"options", kLMVOptionsVideo);
        }
        if (v.subviews.count) LMVAttachToCandidates(v);
    }
}

%hook CSCoverSheetViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    LMVAttachToCandidates([(UIViewController *)self view]);
}
- (void)viewDidLayoutSubviews {
    %orig;
    LMVAttachToCandidates([(UIViewController *)self view]);
}
%end

%hook NCNotificationShortLookView
- (void)layoutSubviews {
    %orig;
    if (LMVEnabled()) {
        LMVEnsureVideoLayer((UIView *)self, @"message", kLMVMessageVideo);
    } else {
        LMVRemoveLayersIfNeeded((UIView *)self);
    }
}
%end

%hook NCNotificationListCell
- (void)layoutSubviews {
    %orig;
    if (LMVEnabled()) {
        LMVEnsureVideoLayer((UIView *)self, @"message", kLMVMessageVideo);
    } else {
        LMVRemoveLayersIfNeeded((UIView *)self);
    }
}
%end

%hook UIView
- (void)layoutSubviews {
    %orig;
    NSString *cls = NSStringFromClass([self class]);
    if (LMVShouldUseOptionsView(cls)) {
        if (LMVEnabled()) {
            LMVEnsureVideoLayer((UIView *)self, @"options", kLMVOptionsVideo);
        } else {
            LMVRemoveLayersIfNeeded((UIView *)self);
        }
    }
}
%end

static void LMVRefreshAll(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIWindow *candidate in [UIApplication sharedApplication].windows) {
            if (candidate.isKeyWindow) { window = candidate; break; }
        }
        if (!window) window = [UIApplication sharedApplication].windows.firstObject;
        if (window) LMVAttachToCandidates(window);
    });
}

static void LMVDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    LMVRefreshAll();
}

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] createDirectoryAtPath:kLMVBaseDir withIntermediateDirectories:YES attributes:nil error:nil];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    }
}
