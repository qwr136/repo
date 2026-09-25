#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>

#define kLVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.notifybgvideo.plist"
#define kLVNotify    CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs")
#define kLVVideoDir  @"/var/mobile/通知视频"
#define kLVLogFile   @"/var/mobile/通知视频/Hook日志.txt"

static AVPlayer *gPlayer = nil;
static NSString *gCurrentPath = nil;
static id gLoopObserver = nil;
static AVPlayer *gPlayerPlayer = nil;
static NSString *gCurrentPlayerPath = nil;
static id gPlayerLoopObserver = nil;
static char kLayerKey;
static char kPlayerLayerKey;
static char kTrackedKey;
static int gActiveNotifCount = 0;
static int gActivePlayerCount = 0;
static NSMutableSet<NSString *> *gLoggedClasses = nil;

#pragma mark - 偏好（直接读文件）

static NSArray<NSString *> *_lvSuites(void) {
    return @[@"com.xiaofei.notifybgvideo", @"com.xiaofei.notifybgvideo.prefs"];
}

static NSDictionary *_lvPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile] ?: @{};
}

// 同时读：plist 文件 + 系统偏好存储（两个 suite），任一为 YES 即 YES。
// 设置面板写入位置和插件读取位置可能不一致，这样保证不会漏。
static BOOL _lvBool(NSString *key) {
    @try {
        id v = _lvPrefs()[key];
        if ([v respondsToSelector:@selector(boolValue)] && [v boolValue]) { return YES; }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)] && [val boolValue]) { return YES; }
        }
    } @catch (NSException *e) {}
    return NO;
}

// 视频透明度：默认 0.5（视频淡一些，文字才看得清）
static CGFloat _lvAlpha(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoAlpha"];
        if ([v respondsToSelector:@selector(floatValue)]) {
            CGFloat a = [v floatValue];
            if (a > 0.05) { return MIN(a, 1.0); }
        }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoAlpha"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(floatValue)]) {
                CGFloat a = [val floatValue];
                if (a > 0.05) { return MIN(a, 1.0); }
            }
        }
    } @catch (NSException *e) {}
    return 0.5;
}

static NSString *_lvString(NSString *key) {
    @try {
        id v = _lvPrefs()[key];
        if ([v isKindOfClass:[NSString class]] && [v length]) { return v; }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val isKindOfClass:[NSString class]] && [val length]) { return val; }
        }
    } @catch (NSException *e) {}
    return nil;
}

static BOOL _lvEnabled(void) { return _lvBool(@"LockVideoEnabled"); }

// 播放器视频背景：独立开关，默认关闭
static BOOL _lvPlayerEnabled(void) { return _lvBool(@"LockVideoPlayerEnabled"); }

// 视频声音默认开启（用户没设过时直接出声）；用户显式设为 NO 时尊重选择。
static BOOL _lvSound(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoSound"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoSound"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)]) { return [val boolValue]; }
        }
    } @catch (NSException *e) {}
    return YES;   // 默认出声
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

// 锁屏播放器的独立透明度（默认 0.5）
static CGFloat _lvPlayerAlpha(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoPlayerAlpha"];
        if ([v respondsToSelector:@selector(floatValue)]) {
            CGFloat a = [v floatValue];
            if (a > 0.05) { return MIN(a, 1.0); }
        }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoPlayerAlpha"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(floatValue)]) {
                CGFloat a = [val floatValue];
                if (a > 0.05) { return MIN(a, 1.0); }
            }
        }
    } @catch (NSException *e) {}
    return 0.5;
}

static NSString *_lvPath(void) {
    NSString *saved = _lvString(@"LockVideoPath");
    if ([saved isKindOfClass:[NSString class]] &&
        [[NSFileManager defaultManager] fileExistsAtPath:saved]) {
        return saved;
    }
    return _lvScanFiles().firstObject;
}

// 锁屏播放器的独立路径（没单独选过则跟随 LockVideoPath）
static NSString *_lvPlayerPath(void) {
    NSString *saved = _lvString(@"LockVideoPlayerPath");
    if ([saved isKindOfClass:[NSString class]] &&
        [[NSFileManager defaultManager] fileExistsAtPath:saved]) {
        return saved;
    }
    return _lvPath();
}

#pragma mark - 诊断日志（只记录"每个类第一次出现"，防刷屏）

static void _lvLog(NSString *line) {
    @try {
        if (![[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]) { return; }
        NSString *old = [NSString stringWithContentsOfFile:kLVLogFile
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil] ?: @"";
        if (old.length > 65536) { old = @""; }   // 防止无限增长（64KB）
        NSString *full = [old stringByAppendingFormat:@"%@\n", line];
        [full writeToFile:kLVLogFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (NSException *e) {}
}

static void _lvLogOnce(NSString *cls, NSString *action) {
    @try {
        if (!gLoggedClasses) { gLoggedClasses = [NSMutableSet set]; }
        NSString *key = [cls stringByAppendingString:action];
        if ([gLoggedClasses containsObject:key]) { return; }
        [gLoggedClasses addObject:key];
        _lvLog([NSString stringWithFormat:@"%@ -> %@", cls, action]);
    } @catch (NSException *e) {}
}

#pragma mark - 共享播放器（多视图可同时显示同一视频）

static AVPlayer *_lvPlayer(void) {
    @try {
        if (!gPlayer) {
            NSString *path = _lvPath();
            if (!path) {
                _lvLogOnce(@"扫描结果", [NSString stringWithFormat:@"%@ 里没有找到视频文件", kLVVideoDir]);
                return nil;
            }
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
            _lvLog([NSString stringWithFormat:@"播放器创建: %@ 声音=%d", path, _lvSound()]);
        }
        return gPlayer;
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"player 异常: %@", e]);
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

#pragma mark - player-player

static AVPlayer *_lvPlayerPlayer(void) {
    @try {
        if (!gPlayerPlayer) {
            NSString *path = _lvPlayerPath();
            if (!path) { return nil; }
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
            if (!item) { return nil; }
            gPlayerPlayer = [AVPlayer playerWithPlayerItem:item];
            gPlayerPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
            gPlayerPlayer.muted = !_lvSound();
            gCurrentPlayerPath = path;
            __weak AVPlayer *wp = gPlayerPlayer;
            gPlayerLoopObserver = [[NSNotificationCenter defaultCenter]
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
            _lvLog([NSString stringWithFormat:@"player-player create: %@", path]);
        }
        return gPlayerPlayer;
    } @catch (NSException *e) { return nil; }
}

static void _lvResetPlayerPlayer(void) {
    @try {
        if (gPlayerLoopObserver) {
            [[NSNotificationCenter defaultCenter] removeObserver:gPlayerLoopObserver];
            gPlayerLoopObserver = nil;
        }
        if (gPlayerPlayer) { [gPlayerPlayer pause]; gPlayerPlayer = nil; }
        gCurrentPlayerPath = nil;
    } @catch (NSException *e) {}
}

#pragma mark - 视图识别（大小写不敏感）

static BOOL _lvIsNotificationView(UIView *v) {
    @try {
        NSString *cls = NSStringFromClass([v class]);
        if (!cls) { return NO; }
        NSString *low = cls.lowercaseString;
        if (![low containsString:@"notification"]) { return NO; }
        // 排除一切容器/遮罩/标题/列表——它们的 bounds 远大于卡片，挂上会铺满或藏在卡片背后看不见
        if ([low containsString:@"stackdimming"]) { return NO; }
        if ([low containsString:@"header"])       { return NO; }
        if ([low containsString:@"listview"])     { return NO; }   // 整个列表容器（全屏）
        if ([low containsString:@"sectionlist"])  { return NO; }
        if ([low containsString:@"listcell"])     { return NO; }   // 卡片外层容器，视频会被内部卡片盖住看不见
        if ([low containsString:@"content"])      { return NO; }   // 内容视图，交给 shortlook 统一处理
        // 只挂用户实际看到的圆角卡片本体
        return [low containsString:@"shortlook"] || [low containsString:@"banner"];
    } @catch (NSException *e) { return NO; }
}

// 锁屏底部播放器视图（识别类名，避免挂到容器/SB 命名空间过宽的类）
static BOOL _lvIsPlayerClassName(NSString *cls) {
    if (!cls) return NO;
    NSString *low = cls.lowercaseString;
    if ([low containsString:@"notification"]) return NO;
    // iOS 14-15
    if ([low containsString:@"sblockscreennowplaying"]) return YES;
    if ([low containsString:@"sbnowplayingcard"])       return YES;
    if ([low containsString:@"nowplayingcard"])         return YES;
    // iOS 16 (CoverSheet 框架)
    if ([low containsString:@"csnowplaying"])           return YES;
    if ([low containsString:@"csmediacontrol"])         return YES;
    if ([low containsString:@"csmedialock"])            return YES;
    if ([low containsString:@"cslockscreenmedia"])      return YES;
    // iOS 17+ (SpringBoard 框架 + CoverSheet 框架混合)
    if ([low containsString:@"sbmediacontrol"])         return YES;
    if ([low containsString:@"sbmedialock"])            return YES;
    if ([low containsString:@"sblockscreenmediacont"])  return YES;
    if ([low containsString:@"sblockscreenmedia"])      return YES;
    if ([low containsString:@"sblockscreenmusic"])      return YES;
    // 通配：lockview + media / media + control
    if ([low containsString:@"lockview"] && [low containsString:@"media"]) return YES;
    if ([low containsString:@"mediaplatter"])           return YES;
    return NO;
}

#pragma mark - 挂载

// 递归隐藏卡片里所有模糊/背景子视图（UIVisualEffectView 等），让视频能直接当卡片背景，
// 不再被任何灰色/模糊层挡在下面。文字/icon 等内容子视图不动。
static void _lvHideBackgroundsRecursive(UIView *v) {
    @try {
        // 清掉卡片自身的背景色
        if (v.backgroundColor && ![v.backgroundColor isEqual:[UIColor clearColor]]) {
            v.backgroundColor = [UIColor clearColor];
        }
        for (UIView *s in v.subviews) {
            NSString *cls = NSStringFromClass(s.class);
            NSString *low = cls.lowercaseString;
            BOOL isBlur = [s isKindOfClass:[UIVisualEffectView class]] ||
                          [low containsString:@"blur"]   || [low containsString:@"effect"] ||
                          [low containsString:@"backdrop"] || [low containsString:@"material"] ||
                          [low containsString:@"vibrancy"] || [low containsString:@"backgroundview"];
            if (isBlur && !s.hidden) {
                s.hidden = YES;
                _lvLogOnce(cls, @"隐藏卡片背景");
            }
            // 递归处理子视图（背景可能嵌套）
            if (s.subviews.count > 0 && s.subviews.count < 20) {
                _lvHideBackgroundsRecursive(s);
            }
        }
    } @catch (NSException *e) {}
}

// 视频插到卡片最底层（index 0）——卡片自己的背景层已隐藏，所以视频直接可见，
// 文字/icon 等内容子视图（位于更高 index）自然浮在视频之上。
static void _lvInsertLayer(UIView *v, AVPlayerLayer *l) {
    if (l.superlayer == v.layer) {
        if (v.layer.sublayers.firstObject != l) {
            [l removeFromSuperlayer];
            [v.layer insertSublayer:l atIndex:0];
        }
        return;
    }
    [v.layer insertSublayer:l atIndex:0];
}

static void _lvAttach(UIView *v) {
    if (!v || !_lvEnabled()) { return; }
    @try {
        AVPlayer *p = _lvPlayer();

        if (!p) {
            // 找不到视频文件：直接记一行日志退出，不再做绿色诊断层
            _lvLogOnce(NSStringFromClass(v.class), @"没找到视频文件（请检查 /var/mobile/通知视频 目录与素材路径）");
            return;
        }

        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        if (!l) {
            l = [AVPlayerLayer playerLayerWithPlayer:p];
            l.videoGravity = AVLayerVideoGravityResizeAspectFill;
            l.cornerRadius = 18.0;
            l.masksToBounds = YES;
            objc_setAssociatedObject(v, &kLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            _lvLogOnce(NSStringFromClass(v.class), @"已挂载视频");
        }
        if (l.player != p) { l.player = p; }   // 素材切换后更新引用

        // 先把卡片里所有模糊/背景子视图隐藏掉，避免视频被灰底盖住
        _lvHideBackgroundsRecursive(v);
        _lvInsertLayer(v, l);
        l.frame = v.bounds;
        l.opacity = (float)_lvAlpha();   // 视频淡一点，文字才看得清
        [p play];
        _lvLogOnce(NSStringFromClass(v.class),
                   [NSString stringWithFormat:@"挂载尺寸 %.0fx%.0f 透明度 %.2f",
                    v.bounds.size.width, v.bounds.size.height, _lvAlpha()]);
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"attach 异常: %@", e]);
    }
}

static void _lvOnMatch(UIView *v) {
    _lvLogOnce(NSStringFromClass(v.class), @"命中通知视图");   // 不再依赖诊断模式，必记
    if (!_lvEnabled()) {
        _lvLogOnce(@"状态", @"开关「启用」是关闭的，跳过挂载");
        return;
    }
    _lvAttach(v);
}

// 给锁屏底部播放器视图挂视频背景（共用 gPlayer，但用独立 associated layer key）
static void _lvAttachPlayerView(UIView *v) {
    if (!v) return;
    @try {
        if (!_lvPlayerEnabled()) {
            _lvLogOnce(@"状态", @"开关「播放器视频背景」是关闭的，跳过挂载");
            return;
        }
        AVPlayer *p = _lvPlayerPlayer();
        if (!p) return;

        AVPlayerLayer *l = objc_getAssociatedObject(v, &kPlayerLayerKey);
        if (!l) {
            l = [AVPlayerLayer playerLayerWithPlayer:p];
            l.videoGravity = AVLayerVideoGravityResizeAspectFill;
            l.cornerRadius = 18.0;
            l.masksToBounds = YES;
            objc_setAssociatedObject(v, &kPlayerLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            _lvLogOnce(NSStringFromClass(v.class), @"已挂载播放器视频");
        }
        if (l.player != p) { l.player = p; }

        // 隐藏播放器卡片自身的模糊背景层（跟通知一样处理）
        _lvHideBackgroundsRecursive(v);
        if (l.superlayer != v.layer) {
            [v.layer insertSublayer:l atIndex:0];
        }
        l.frame = v.bounds;
        l.opacity = (float)_lvPlayerAlpha();
        if (v.window) { [p play]; }
        _lvLogOnce(NSStringFromClass(v.class),
                   [NSString stringWithFormat:@"播放器挂载尺寸 %.0fx%.0f 透明度 %.2f",
                    v.bounds.size.width, v.bounds.size.height, _lvPlayerAlpha()]);
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"attach player 异常: %@", e]);
    }
}

#pragma mark - iOS 16 锁屏通知显式 hook（直接挂用户可见的卡片本体 NCNotificationShortLookView）

%group LVNotif16
%hook NCNotificationShortLookView
- (void)didMoveToWindow {
    %orig;
    @try { if (((UIView *)self).window) { _lvOnMatch((UIView *)self); } } @catch (NSException *e) {}
}
- (void)layoutSubviews {
    %orig;
    @try {
        UIView *v = (UIView *)self;
        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        if (l) {
            _lvHideBackgroundsRecursive(v);   // 重新隐藏背景
            _lvInsertLayer(v, l);
            l.frame = v.bounds;
            if (v.window && gPlayer) { [gPlayer play]; }
        }
    } @catch (NSException *e) {}
}
%end
%end

#pragma mark - 全局 hook（UIView 级别兜底，自动匹配所有通知视图 / 播放器视图）

// 给视图打"已跟踪"标记，防止 didMoveToWindow 重复计数
static inline void _lvMarkTracked(UIView *v) {
    objc_setAssociatedObject(v, &kTrackedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static inline BOOL _lvIsTracked(UIView *v) {
    id f = objc_getAssociatedObject(v, &kTrackedKey);
    return [f respondsToSelector:@selector(boolValue)] && [f boolValue];
}

static void (*_orig_didMoveToWindow)(UIView *, SEL);
static void _lv_didMoveToWindow(UIView *self, SEL _cmd) {
    BOOL wasInWindow = (self.window != nil);
    _orig_didMoveToWindow(self, _cmd);
    BOOL nowInWindow = (self.window != nil);
    @try {
        // 识别：通知卡片 OR 播放器视图
        BOOL isNotif  = _lvIsNotificationView(self);
        BOOL isPlayer = !isNotif && _lvIsPlayerClassName(NSStringFromClass(self.class));
        if (!isNotif && !isPlayer) {
            // 诊断：锁屏窗口下其它视图类名（每个类只打一次），便于发现真实播放器类
            if (nowInWindow) {
                UIWindow *w = self.window;
                NSString *wcls = NSStringFromClass(w.class);
                NSString *wlow = wcls.lowercaseString;
                if ([wlow containsString:@"coversheet"] || [wlow containsString:@"lockscreen"]) {
                    _lvLogOnce(NSStringFromClass(self.class), @"未匹配(锁屏窗口)");
                }
            }
            return;
        }

        BOOL wasTracked = _lvIsTracked(self);
        if (!wasInWindow && nowInWindow) {
            if (!wasTracked) {
                _lvMarkTracked(self);
                if (isNotif) {
                    gActiveNotifCount++;
                    _lvOnMatch(self);
                } else if (isPlayer) {
                    gActivePlayerCount++;
                    _lvAttachPlayerView(self);
                }
            }
        } else if (wasInWindow && !nowInWindow) {
            if (wasTracked) {
                objc_setAssociatedObject(self, &kTrackedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                if (isNotif) {
                    if (gActiveNotifCount > 0) gActiveNotifCount--;
                } else if (isPlayer) {
                    if (gActivePlayerCount > 0) gActivePlayerCount--;
                }
            }
        }
        // 各自播放/暂停（独立 player、独立计数）
        if (gPlayer) {
            if (gActiveNotifCount > 0) { [gPlayer play]; }
            else                         { [gPlayer pause]; }
        }
        if (gPlayerPlayer) {
            if (gActivePlayerCount > 0) { [gPlayerPlayer play]; }
            else                         { [gPlayerPlayer pause]; }
        }
    } @catch (NSException *e) {}
}

static void (*_orig_layoutSubviews)(UIView *, SEL);
static void _lv_layoutSubviews(UIView *self, SEL _cmd) {
    _orig_layoutSubviews(self, _cmd);
    @try {
        if (_lvIsNotificationView(self)) {
            AVPlayerLayer *l = objc_getAssociatedObject(self, &kLayerKey);
            if (l) {
                _lvHideBackgroundsRecursive(self);   // 每次布局都重新隐藏背景
                _lvInsertLayer(self, l);
                l.frame = self.bounds;
                if (self.window && gPlayer) { [gPlayer play]; }
            }
        } else if (_lvIsPlayerClassName(NSStringFromClass(self.class))) {
            AVPlayerLayer *l = objc_getAssociatedObject(self, &kPlayerLayerKey);
            if (l) {
                _lvHideBackgroundsRecursive(self);
                if (l.superlayer != self.layer) {
                    [self.layer insertSublayer:l atIndex:0];
                }
                l.frame = self.bounds;
                l.opacity = (float)_lvPlayerAlpha();
                if (self.window && gPlayerPlayer) { [gPlayerPlayer play]; }
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

#pragma mark - 设置变化回调（C 函数，ARC 下 block 不能转 CFNotificationCallback）

static void _lvPrefsChanged(CFNotificationCenterRef center,
                            void *observer,
                            CFStringRef name,
                            const void *object,
                            CFDictionaryRef userInfo) {
    @try {
        NSString *np = _lvPath();
        if (![np isEqualToString:gCurrentPath]) {
            _lvResetPlayer();
        } else if (gPlayer) {
            gPlayer.muted = !_lvSound();
        }
        NSString *npp = _lvPlayerPath();
        if (![npp isEqualToString:gCurrentPlayerPath]) {
            _lvResetPlayerPlayer();
        } else if (gPlayerPlayer) {
            gPlayerPlayer.muted = !_lvSound();
        }
    } @catch (NSException *e) {}
}

#pragma mark - 轮询扫描（不依赖任何 hook 传播：直接遍历锁屏视图树找通知卡片）

static NSTimer *gPollTimer = nil;

// 只挂用户实际看到的通知视图本体（短按卡片 / 横幅 / 长按展开视图），
// 排除列表容器、遮罩、标题、外层 cell——它们的 bounds 远大于卡片，挂上会铺满或藏在卡片背后
static BOOL _lvIsCardClass(NSString *cls) {
    NSString *low = cls.lowercaseString;
    if (![low containsString:@"notif"]) { return NO; }
    if ([low containsString:@"stackdimming"]) { return NO; }
    if ([low containsString:@"header"])       { return NO; }
    if ([low containsString:@"listview"])     { return NO; }
    if ([low containsString:@"sectionlist"])  { return NO; }
    if ([low containsString:@"listcell"])     { return NO; }
    // 短按：可见圆角卡片本体（NCNotificationShortLookView）
    // 横幅：锁屏顶部悬浮通知（NCNotificationBannerView / ...）
    // 长按展开：长按通知后弹出的完整视图（NCNotificationLongLookView / NCNotificationLongLookContentView / ...）
    return [low containsString:@"shortlook"] ||
           [low containsString:@"banner"]     ||
           [low containsString:@"longlook"];
}

static void _lvScanAndAttach(UIView *root, BOOL *foundNotif, BOOL *foundPlayer) {
    @try {
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
        int visited = 0;
        while (stack.count > 0 && visited < 4000) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            visited++;
            NSString *cls = NSStringFromClass([v class]);
            if (_lvIsCardClass(cls)) {
                if (foundNotif) *foundNotif = YES;
                _lvLogOnce(cls, @"轮询扫描命中通知");
                _lvOnMatch(v);
            } else if (_lvIsPlayerClassName(cls)) {
                if (foundPlayer) *foundPlayer = YES;
                _lvLogOnce(cls, @"轮询扫描命中播放器");
                _lvAttachPlayerView(v);
            } else {
                // 诊断：把扫描到的类名记下来（每个类只记一次），
                // 这样即使播放器是常驻视图（不触发 didMoveToWindow）也能被发现
                NSString *low = cls.lowercaseString;
                BOOL suspicious =
                    [low containsString:@"media"]   || [low containsString:@"playing"] ||
                    [low containsString:@"music"]   || [low containsString:@"audio"]   ||
                    [low containsString:@"nowplay"] || [low containsString:@"radio"]   ||
                    [low containsString:@"album"]   || [low containsString:@"artwork"];
                if (suspicious) {
                    _lvLogOnce(cls, @"【疑似播放器】请反馈此行");
                } else {
                    _lvLogOnce(cls, @"扫描时发现的类");
                }
            }
            for (UIView *c in v.subviews) { [stack addObject:c]; }
        }
    } @catch (NSException *e) {}
}

static void _lvPollTick(void) {
    @try {
        if (!_lvEnabled() && !_lvPlayerEnabled()) {
            if (gPlayer) { [gPlayer pause]; }
            if (gPlayerPlayer) { [gPlayerPlayer pause]; }
            return;
        }
        id app = [UIApplication sharedApplication];
        NSArray *wins = nil;
        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) {}
        BOOL foundAnyCard = NO;
        BOOL foundAnyPlayer = NO;
        for (UIWindow *w in wins) {
            NSString *c = NSStringFromClass([w class]);
            if (![c containsString:@"CoverSheet"] && ![c containsString:@"LockScreen"] &&
                ![c containsString:@"Banner"]) { continue; }
            if (w.hidden || w.alpha <= 0.01) { continue; }
            BOOL foundNotif = NO, foundPlayer = NO;
            _lvScanAndAttach(w, &foundNotif, &foundPlayer);
            if (foundNotif) foundAnyCard = YES;
            if (foundPlayer) foundAnyPlayer = YES;
        }
        if (gPlayer) {
            if (foundAnyCard) { [gPlayer play]; } else { [gPlayer pause]; }
        }
        if (gPlayerPlayer) {
            if (foundAnyPlayer) { [gPlayerPlayer play]; } else { [gPlayerPlayer pause]; }
        }
    } @catch (NSException *e) {}
}

#pragma mark - ctor

%ctor {
    @try {
        // 1) iOS 16 锁屏通知：显式 hook 用户实际看到的卡片本体 NCNotificationShortLookView
        if (objc_getClass("NCNotificationShortLookView") != Nil) {
            %init(LVNotif16);
            _lvLog(@"NCNotificationShortLookView 显式 hook OK");
        } else {
            _lvLog(@"NCNotificationShortLookView 不存在(非 iOS16?)");
        }

        // 2) 全局 swizzle UIView 兜底：自动匹配所有类名含 notification 的视图
        Class uiView = objc_getClass("UIView");
        if (uiView) {
            MSHookMessageEx(uiView, @selector(didMoveToWindow),
                            (IMP)_lv_didMoveToWindow, (IMP *)&_orig_didMoveToWindow);
            MSHookMessageEx(uiView, @selector(layoutSubviews),
                            (IMP)_lv_layoutSubviews, (IMP *)&_orig_layoutSubviews);
            _lvLog(@"UIView 全局 hook OK");
        }

        // 3) 壁纸 hook（类存在才装）
        if (objc_getClass("SBLockScreenWallpaperView") != Nil) {
            %init(LVWallpaper);
            _lvLog(@"壁纸 hook OK");
        } else {
            _lvLog(@"SBLockScreenWallpaperView 不存在");
        }

        // 4) 设置变化：声音即时生效；素材变化重建播放器
        // 5) 轮询扫描：每 1.5 秒遍历一次锁屏视图树，直接找通知卡片并挂视频
        //    这样即使目标类不调用 super、hook 传播不到，也一定能命中
        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                if (gPollTimer) { [gPollTimer invalidate]; gPollTimer = nil; }
                gPollTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *t) {
                    @try { _lvPollTick(); } @catch (NSException *e) {}
                }];
                _lvLog(@"轮询扫描已启动(每1.5秒)");
            } @catch (NSException *e) {}
        });

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        _lvPrefsChanged,
                                        kLVNotify,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        _lvLog([NSString stringWithFormat:@"状态: 启用=%d 声音=%d 视频=%@ 目录存在=%d",
                _lvEnabled(), _lvSound(), _lvPath() ?: @"(无)",
                [[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]]);
        _lvLog([NSString stringWithFormat:@"播放器: 开关=%d 视频=%@ 透明度=%.2f",
                _lvPlayerEnabled(), _lvPlayerPath() ?: @"(无)", _lvPlayerAlpha()]);
        _lvLog([NSString stringWithFormat:@"plist文件内容: %@", _lvPrefs()]);
        {
            NSMutableString *s = [NSMutableString string];
            for (NSString *suite in _lvSuites()) {
                for (NSString *k in @[@"LockVideoEnabled", @"LockVideoSound", @"LockVideoPlayerEnabled"]) {
                    CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
                    CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)k, (__bridge CFStringRef)suite);
                    id val = cf ? CFBridgingRelease(cf) : nil;
                    [s appendFormat:@"%@/%@=%@ ", suite, k, val ?: @"(无)"];
                }
            }
            _lvLog([NSString stringWithFormat:@"系统偏好: %@", s]);
        }
        _lvLog(@"===== 1.0.39 加载完成 =====");
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"ctor 异常: %@", e]);
    }
}
