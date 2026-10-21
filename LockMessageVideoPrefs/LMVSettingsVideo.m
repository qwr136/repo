#import "LMVSettingsVideo.h"
#import <objc/runtime.h>

// 2.63: one background player for the Settings app. It never touches SpringBoard
// state: the material, sound switch and volume are read from its own keys, and
// the same keys are what the new 「设置视频背景」 page writes.
@implementation LMVSettingsVideoBackground

+ (instancetype)shared {
    static LMVSettingsVideoBackground *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [LMVSettingsVideoBackground new]; });
    return shared;
}

- (BOOL)enabled { return [LMVSettingsRead(LMVSettingsVideoEnabledKey) boolValue]; }

- (NSString *)selectedPath {
    id relative = LMVSettingsRead(LMVSettingsVideoFileKey);
    if (![relative isKindOfClass:NSString.class] || ![(NSString *)relative length]) return nil;
    NSString *name = [(NSString *)relative lastPathComponent];
    if (!name.length || [name isEqualToString:@".."] || [name isEqualToString:@"."]) return nil;
    NSString *path = [LMVSettingsVideoRoot stringByAppendingPathComponent:name];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return nil;
    return path;
}

- (UIWindow *)currentWindow {
    // The Settings app has one foreground-active scene; the key window is the one
    // the table view lives in.
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *candidate in windowScene.windows) {
            if (candidate.hidden || candidate.alpha < .01) continue;
            if (candidate.windowLevel != UIWindowLevelNormal) continue;
            return candidate;
        }
    }
    return nil;
}

- (void)installInWindow:(UIWindow *)window {
    if (!window) return;
    UIView *root = window.rootViewController.view;
    if (!root) return;
    if (!self.host) {
        self.host = [[UIView alloc] initWithFrame:root.bounds];
        self.host.userInteractionEnabled = NO;
        self.host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.host.backgroundColor = UIColor.blackColor;
    }
    self.window = window;
    if (self.host.superview != root) [root insertSubview:self.host atIndex:0];
    if (!CGRectEqualToRect(self.host.frame, root.bounds)) self.host.frame = root.bounds;
    // The app's own views are opaque; asking the table/window to be clear is what
    // actually lets the video show through, and it is undone in -stop.
    [self applyTransparency:YES];
}

// Only view-level transparency is touched, and every change is remembered so
// -stop restores exactly what was there.
- (void)applyTransparency:(BOOL)transparent {
    UIWindow *window = self.window;
    if (!window) return;
    UIViewController *controller = window.rootViewController;
    NSMutableArray *views = [NSMutableArray array];
    if (controller.view) [views addObject:controller.view];
    if ([controller isKindOfClass:UINavigationController.class])
        [views addObject:[(UINavigationController *)controller topViewController].view];
    for (UIView *view in views) {
        if (!view || ![view isKindOfClass:UIView.class]) continue;
        if (transparent) {
            if (!objc_getAssociatedObject(view, @selector(applyTransparency:))) {
                objc_setAssociatedObject(view, @selector(applyTransparency:), view.backgroundColor ?: [UIColor whiteColor], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            view.backgroundColor = UIColor.clearColor;
        } else {
            UIColor *original = objc_getAssociatedObject(view, @selector(applyTransparency:));
            if (original) { view.backgroundColor = original; objc_setAssociatedObject(view, @selector(applyTransparency:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        }
    }
}

- (void)buildPlayerForPath:(NSString *)path {
    [self.player pause];
    [self.looper disableLooping];
    self.player = nil; self.looper = nil;
    if (!path) return;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    item.preferredForwardBufferDuration = 1;
    AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[]];
    player.muted = YES;                       // sound is decided per refresh below
    player.allowsExternalPlayback = NO;
    player.automaticallyWaitsToMinimizeStalling = NO;
    if ([player respondsToSelector:@selector(setPreventsDisplaySleepDuringVideoPlayback:)])
        player.preventsDisplaySleepDuringVideoPlayback = NO;
    AVPlayerLooper *looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:item];
    AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    layer.frame = self.host.bounds;
    [self.host.layer addSublayer:layer];
    self.player = player; self.looper = looper;
    [layer setName:@"com.minis.lockmessagevideo.settings-video"];
    [player play];
}

- (void)updateAudio {
    if (!self.player) return;
    BOOL sound = [LMVSettingsRead(LMVSettingsVideoSoundKey) boolValue];
    NSNumber *volumeValue = LMVSettingsRead(LMVSettingsVideoVolumeKey);
    float volume = volumeValue ? [volumeValue floatValue] : .5f;
    if (volume < 0) volume = 0; if (volume > 1) volume = 1;
    self.player.muted = !sound;
    self.player.volume = sound ? volume : 0;
}

- (void)refresh {
    if (![self enabled]) { [self stop]; return; }
    NSString *path = [self selectedPath];
    if (!path) { [self stop]; return; }
    UIWindow *window = [self currentWindow];
    if (!window) { [self stop]; return; }
    [self installInWindow:window];
    if (![self.path isEqualToString:path] || !self.player) {
        self.path = path;
        [self buildPlayerForPath:path];
    }
    [self updateAudio];
    // The layer follows the host when the window resizes (rotation, split view).
    for (CALayer *layer in self.host.layer.sublayers) {
        if ([layer isKindOfClass:AVPlayerLayer.class] && !CGRectEqualToRect(layer.frame, self.host.bounds))
            layer.frame = self.host.bounds;
    }
    self.active = YES;
}

- (void)stop {
    self.active = NO;
    [self.player pause];
    [self.looper disableLooping];
    self.player = nil; self.looper = nil; self.path = nil;
    for (CALayer *layer in [self.host.layer.sublayers copy]) if ([layer isKindOfClass:AVPlayerLayer.class]) [layer removeFromSuperlayer];
    [self.host removeFromSuperview];
    [self applyTransparency:NO];
}

@end