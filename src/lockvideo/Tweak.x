#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <substrate.h>

#define kLVNotify    CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs")
#define kLVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.notifybgvideo.plist"
#define kLVVideoDir  @"/var/mobile/通知视频"

static AVPlayer      *gPlayer = nil;
static AVPlayerLayer *gLayer  = nil;
static NSString      *gPath   = nil;
static id             gLoopObserver = nil;

#pragma mark - 偏好读取（直接读文件，绕开 cfprefsd 缓存）

static NSString *_lvPrefsString(NSString *key) {
    @try {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile];
        id v = d[key];
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
            return (NSString *)v;
        }
    } @catch (NSException *e) {}
    return nil;
}

static BOOL _lvEnabled(void) {
    @try {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile];
        id v = d[@"LockVideoEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return NO;
}

#pragma mark - 素材解析：目录扫描 + 偏好里的路径

static NSArray<NSString *> *_lvVideoFiles(void) {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *out = [NSMutableArray array];
        NSArray *items = [fm contentsOfDirectoryAtPath:kLVVideoDir error:nil];
        for (NSString *f in items) {
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

static NSString *_lvResolveVideoPath(void) {
    // 优先用设置里已选的路径；路径失效则按目录排序取第一个
    NSString *saved = _lvPrefsString(@"LockVideoPath");
    if (saved && [[NSFileManager defaultManager] fileExistsAtPath:saved]) {
        return saved;
    }
    return _lvVideoFiles().firstObject;
}

#pragma mark - 播放器管理

static void _lvTeardown(void) {
    @try {
        if (gLoopObserver) {
            [[NSNotificationCenter defaultCenter] removeObserver:gLoopObserver];
            gLoopObserver = nil;
        }
        if (gPlayer) { [gPlayer pause]; gPlayer = nil; }
        if (gLayer)  { [gLayer removeFromSuperlayer]; gLayer = nil; }
        gPath = nil;
    } @catch (NSException *e) {
        NSLog(@"[LockVideo] teardown: %@", e);
    }
}

static void _lvAttachTo(UIView *view) {
    if (!view) { return; }
    @autoreleasepool {
        @try {
            NSString *path = _lvResolveVideoPath();
            if (!_lvEnabled() || path.length == 0) {
                if (gLayer) { _lvTeardown(); }
                return;
            }

            if (!gPlayer || ![path isEqualToString:gPath]) {
                if (gLoopObserver) {
                    [[NSNotificationCenter defaultCenter] removeObserver:gLoopObserver];
                    gLoopObserver = nil;
                }
                if (gLayer) { [gLayer removeFromSuperlayer]; gLayer = nil; }

                AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
                if (!item) { return; }
                gPlayer = [AVPlayer playerWithPlayerItem:item];
                gPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
                gPath = path;
                NSLog(@"[LockVideo] 播放: %@", path);

                __weak AVPlayer *weakPlayer = gPlayer;
                gLoopObserver = [[NSNotificationCenter defaultCenter]
                    addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                object:item
                                 queue:[NSOperationQueue mainQueue]
                            usingBlock:^(NSNotification *note) {
                    @try {
                        AVPlayer *p = weakPlayer;
                        if (!p) { return; }
                        [p seekToTime:kCMTimeZero
                      toleranceBefore:kCMTimeZero
                       toleranceAfter:kCMTimeZero
                            completionHandler:^(BOOL done) { [p play]; }];
                    } @catch (NSException *e) {}
                }];
            }

            if (!gLayer) {
                gLayer = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
                gLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            }
            gLayer.frame = view.bounds;
            if (gLayer.superlayer != view.layer) {
                [gLayer removeFromSuperlayer];
                // 插到最底层：盖住壁纸，但不挡时间/通知等控件
                [view.layer insertSublayer:gLayer atIndex:0];
            }
            [gPlayer play];
        } @catch (NSException *e) {
            NSLog(@"[LockVideo] attach: %@", e);
        }
    }
}

#pragma mark - Hooks

// iOS 15/16 锁屏壁纸视图 —— 视频替换壁纸（效果最直观）
%group LVWallpaper
%hook SBLockScreenWallpaperView

- (void)didMoveToWindow {
    %orig;
    @try { if (self.window) { _lvAttachTo((UIView *)self); } } @catch (NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        if (gLayer && gLayer.superlayer == ((UIView *)self).layer) {
            gLayer.frame = ((UIView *)self).bounds;
        }
    } @catch (NSException *e) {}
}

%end
%end

// 通知背景视图 —— 兜底
%group LVNotifBg
%hook SBLockScreenNotificationBackgroundView

- (void)didMoveToWindow {
    %orig;
    @try { if (self.window) { _lvAttachTo((UIView *)self); } } @catch (NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        if (gLayer && gLayer.superlayer == ((UIView *)self).layer) {
            gLayer.frame = ((UIView *)self).bounds;
        }
    } @catch (NSException *e) {}
}

%end
%end

#pragma mark - ctor

%ctor {
    @try {
        if (!_lvEnabled()) {
            NSLog(@"[LockVideo] 当前未启用");
        }

        BOOL hooked = NO;
        if (objc_getClass("SBLockScreenWallpaperView") != Nil) {
            %init(LVWallpaper);
            hooked = YES;
            NSLog(@"[LockVideo] hook SBLockScreenWallpaperView OK");
        }
        if (objc_getClass("SBLockScreenNotificationBackgroundView") != Nil) {
            %init(LVNotifBg);
            hooked = YES;
            NSLog(@"[LockVideo] hook SBLockScreenNotificationBackgroundView OK");
        }
        if (!hooked) {
            NSLog(@"[LockVideo] 没有找到目标类，未注入");
        }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        (CFNotificationCallback)_lvTeardown,
                                        kLVNotify,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    } @catch (NSException *e) {
        NSLog(@"[LockVideo] ctor: %@", e);
    }
}
