#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <substrate.h>

#define kLVPrefsID   @"com.xiaofei.notifybgvideo"
#define kLVNotify    CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs")

static AVPlayer      *gPlayer = nil;
static AVPlayerLayer *gLayer  = nil;
static NSString      *gPath   = nil;
static id             gLoopObserver = nil;

#pragma mark - 读取偏好设置（直接读文件，SpringBoard 里最可靠）

static NSDictionary *_lvPrefsDict(void) {
    // SpringBoard 里 CFPreferences 常被 sandbox 挡住读不到 mobile domain，
    // 所以直接读 plist 文件。roothide / rootless 路径都试一遍。
    static NSArray *candidates = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        candidates = @[
            @"/var/mobile/Library/Preferences/" kLVPrefsID @".plist",
            @"/var/jb/var/mobile/Library/Preferences/" kLVPrefsID @".plist",
            @"/var/mobile/Library/Preferences/" kLVPrefsID @".plist",
        ];
    });

    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in candidates) {
        if ([fm fileExistsAtPath:p]) {
            NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
            if (d) { return d; }
        }
    }
    return nil;
}

static BOOL _lvEnabled(void) {
    @try {
        NSDictionary *d = _lvPrefsDict();
        id v = d[@"LockVideoEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return NO;
}

static NSString *_lvPath(void) {
    @try {
        NSDictionary *d = _lvPrefsDict();
        id v = d[@"LockVideoPath"];
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
            return (NSString *)v;
        }
    } @catch (NSException *e) {}
    return nil;
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

static void _lvApplyTo(UIView *view) {
    if (!view) { return; }
    @autoreleasepool {
        @try {
            NSString *path = _lvPath();
            if (!_lvEnabled() || path.length == 0 ||
                ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                _lvTeardown();
                return;
            }

            if (!gPlayer || ![path isEqualToString:gPath]) {
                // 路径变了 -> 重建
                if (gLoopObserver) {
                    [[NSNotificationCenter defaultCenter] removeObserver:gLoopObserver];
                    gLoopObserver = nil;
                }
                if (gLayer) { [gLayer removeFromSuperlayer]; gLayer = nil; }

                AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
                if (!item) { NSLog(@"[LockVideo] 无法创建 AVPlayerItem: %@", path); return; }

                gPlayer = [AVPlayer playerWithPlayerItem:item];
                gPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
                gPath = path;

                // 循环播放：只观察当前 item，避免重复注册
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
                            completionHandler:^(BOOL finished) { [p play]; }];
                    } @catch (NSException *e) {}
                }];
            }

            if (!gLayer) {
                gLayer = [AVPlayerLayer playerLayerWithPlayer:gPlayer];
                gLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
                gLayer.frame = view.bounds;
                [view.layer insertSublayer:gLayer atIndex:0];
            } else {
                gLayer.frame = view.bounds;
                if (gLayer.superlayer != view.layer) {
                    [gLayer removeFromSuperlayer];
                    [view.layer insertSublayer:gLayer atIndex:0];
                }
            }
            [gPlayer play];
        } @catch (NSException *e) {
            NSLog(@"[LockVideo] apply: %@", e);
        }
    }
}

#pragma mark - Hook

%group LVBg

%hook SBLockScreenNotificationBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = %orig;
    @try { if (self) { _lvApplyTo((UIView *)self); } } @catch (NSException *e) {}
    return self;
}

- (void)didMoveToWindow {
    %orig;
    @try {
        UIView *v = (UIView *)self;
        if (v.window) { _lvApplyTo(v); }
    } @catch (NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        if (gLayer) { gLayer.frame = ((UIView *)self).bounds; }
    } @catch (NSException *e) {}
}

%end

%end

#pragma mark - ctor

%ctor {
    @try {
        // 类不存在就完全不 hook，避免 nil class hook 出问题
        if (objc_getClass("SBLockScreenNotificationBackgroundView") != Nil) {
            %init(LVBg);
            NSLog(@"[LockVideo] 已注入 SBLockScreenNotificationBackgroundView");
        } else {
            NSLog(@"[LockVideo] 目标类不存在，跳过注入");
        }

        // 设置改动后重建
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
