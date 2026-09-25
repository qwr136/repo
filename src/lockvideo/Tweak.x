#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <substrate.h>

#define kLVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.notifybgvideo.plist"
#define kLVNotify    CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs")
#define kLVVideoDir  @"/var/mobile/通知视频"

static AVPlayer *gPlayer = nil;
static NSString *gCurrentPath = nil;
static id gLoopObserver = nil;
static char kLayerKey;

#pragma mark - 偏好（直接读文件）

static NSDictionary *_lvPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile];
}

static BOOL _lvEnabled(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return NO;
}

static BOOL _lvSound(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoSound"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return NO;   // 默认静音
}

static NSArray<NSString *> *_lvScanFiles(void) {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *f in [fm contentsOfDirectoryAtPath:kLVVideoDir error:nil]) {
            NSString *ext = [f pathExtension].lowercaseString;
            if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
                [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"]) {
                [out addObject:[kLVVideoDir stringByAppendingPathComponent:f]];
            }
        }
        return [out sortedArrayUsingSelector:@selector(compare:)];
    } @catch (NSException *e) {}
    return @[];
}

static NSString *_lvPath(void) {
    NSString *saved = _lvPrefs()[@"LockVideoPath"];
    if ([saved isKindOfClass:[NSString class]] &&
        [[NSFileManager defaultManager] fileExistsAtPath:saved]) {
        return saved;
    }
    return _lvScanFiles().firstObject;
}

#pragma mark - 共享播放器（多视图可同时显示同一视频）

static AVPlayer *_lvPlayer(void) {
    @try {
        if (!gPlayer) {
            NSString *path = _lvPath();
            if (!path) { return nil; }
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
            if (!item) { return nil; }
            gPlayer = [AVPlayer playerWithPlayerItem:item];
            gPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
            gPlayer.muted = !_lvSound();
            gCurrentPath = path;

            __weak AVPlayer *wp = gPlayer;
            gLoopObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                            object:item
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *n) {
                @try {
                    AVPlayer *p = wp;
                    if (!p) { return; }
                    [p seekToTime:kCMTimeZero
                  toleranceBefore:kCMTimeZero
                   toleranceAfter:kCMTimeZero
                        completionHandler:^(BOOL d) { [p play]; }];
                } @catch (NSException *e) {}
            }];
            NSLog(@"[LockVideo] 播放: %@ 声音=%d", path, _lvSound());
        }
        return gPlayer;
    } @catch (NSException *e) {
        NSLog(@"[LockVideo] player: %@", e);
        return nil;
    }
}

static void _lvResetPlayer(void) {
    @try {
        if (gLoopObserver) {
            [[NSNotificationCenter defaultCenter] removeObserver:gLoopObserver];
            gLoopObserver = nil;
        }
        if (gPlayer) { [gPlayer pause]; gPlayer = nil; }
        gCurrentPath = nil;
    } @catch (NSException *e) {}
}

#pragma mark - 视图识别：所有类名带 Notification 的通知视图

static BOOL _lvIsNotificationView(UIView *v) {
    NSString *cls = NSStringFromClass([v class]);
    if (![cls containsString:@"Notification"]) { return NO; }
    return [cls containsString:@"Cell"]    || [cls containsString:@"List"]       ||
           [cls containsString:@"Background"] || [cls containsString:@"Banner"] ||
           [cls containsString:@"Stack"]   || [cls containsString:@"Controller"] ||
           [cls containsString:@"View"];
}

static void _lvAttach(UIView *v) {
    if (!v || !_lvEnabled()) { return; }
    @try {
        AVPlayer *p = _lvPlayer();
        if (!p) { return; }

        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        if (!l) {
            l = [AVPlayerLayer playerLayerWithPlayer:p];
            l.videoGravity = AVLayerVideoGravityResizeAspectFill;
            objc_setAssociatedObject(v, &kLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (l.player != p) { l.player = p; }   // 素材切换后更新引用

        if (l.superlayer != v.layer) {
            if (v.subviews.count > 0) {
                // 插到第一个子视图（一般是毛玻璃背景）之上、内容之下
                [v.layer insertSublayer:l above:((UIView *)v.subviews[0]).layer];
            } else {
                [v.layer addSublayer:l];
            }
        }
        l.frame = v.bounds;
        [p play];
    } @catch (NSException *e) {
        NSLog(@"[LockVideo] attach: %@", e);
    }
}

#pragma mark - 全局 hook（UIView 级别，运行时自动匹配通知视图）

static void (*_orig_didMoveToWindow)(UIView *, SEL);
static void _lv_didMoveToWindow(UIView *self, SEL _cmd) {
    _orig_didMoveToWindow(self, _cmd);
    @try {
        if (self.window && _lvIsNotificationView(self)) { _lvAttach(self); }
    } @catch (NSException *e) {}
}

static void (*_orig_layoutSubviews)(UIView *, SEL);
static void _lv_layoutSubviews(UIView *self, SEL _cmd) {
    _orig_layoutSubviews(self, _cmd);
    @try {
        if (_lvIsNotificationView(self)) {
            AVPlayerLayer *l = objc_getAssociatedObject(self, &kLayerKey);
            if (l) {
                l.frame = self.bounds;
                if (self.window && gPlayer) { [gPlayer play]; }
            }
        }
    } @catch (NSException *e) {}
}

#pragma mark - 壁纸 hook（保留：锁屏整体背景也放视频）

%group LVWallpaper
%hook SBLockScreenWallpaperView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (((UIView *)self).window) {
            UIView *v = (UIView *)self;
            AVPlayer *p = _lvPlayer();
            if (p && _lvEnabled()) {
                AVPlayerLayer *l = [AVPlayerLayer playerLayerWithPlayer:p];
                l.videoGravity = AVLayerVideoGravityResizeAspectFill;
                l.frame = v.bounds;
                [v.layer addSublayer:l];
                [p play];
            }
        }
    } @catch (NSException *e) {}
}

%end
%end

#pragma mark - ctor

%ctor {
    @try {
        // 1) 全局 swizzle UIView：运行时自动匹配所有通知视图（保证命中）
        Class uiView = objc_getClass("UIView");
        if (uiView) {
            MSHookMessageEx(uiView, @selector(didMoveToWindow),
                            (IMP)_lv_didMoveToWindow, (IMP *)&_orig_didMoveToWindow);
            MSHookMessageEx(uiView, @selector(layoutSubviews),
                            (IMP)_lv_layoutSubviews, (IMP *)&_orig_layoutSubviews);
            NSLog(@"[LockVideo] UIView 全局 hook OK");
        }

        // 2) 壁纸 hook（类存在才装）
        if (objc_getClass("SBLockScreenWallpaperView") != Nil) {
            %init(LVWallpaper);
            NSLog(@"[LockVideo] 壁纸 hook OK");
        }

        // 3) 设置变化：声音即时生效；素材变化重建播放器
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        (CFNotificationCallback)^(void) {
                                            @try {
                                                NSString *np = _lvPath();
                                                if (![np isEqualToString:gCurrentPath]) {
                                                    _lvResetPlayer();
                                                } else if (gPlayer) {
                                                    gPlayer.muted = !_lvSound();
                                                }
                                            } @catch (NSException *e) {}
                                        },
                                        kLVNotify,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    } @catch (NSException *e) {
        NSLog(@"[LockVideo] ctor: %@", e);
    }
}
