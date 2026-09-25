#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <substrate.h>

#define kLVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.notifybgvideo.plist"
#define kLVNotify    CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs")
#define kLVVideoDir  @"/var/mobile/通知视频"
#define kLVLogFile   @"/var/mobile/通知视频/Hook日志.txt"
#define kLVDumpFile  @"/var/mobile/通知视频/视图树.txt"
#define kLVDumpNotify CFSTR("com.xiaofei.notifybgvideo/DumpHierarchy")

static AVPlayer *gPlayer = nil;
static NSString *gCurrentPath = nil;
static id gLoopObserver = nil;
static char kLayerKey;
static char kFallbackKey;
static NSMutableSet<NSString *> *gLoggedClasses = nil;

#pragma mark - 偏好（直接读文件）

static NSDictionary *_lvPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile];
}

static BOOL _lvBool(NSString *key) {
    @try {
        id v = _lvPrefs()[key];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return NO;
}

static BOOL _lvEnabled(void) { return _lvBool(@"LockVideoEnabled"); }
static BOOL _lvSound(void)   { return _lvBool(@"LockVideoSound"); }   // 默认静音
static BOOL _lvDebug(void)   { return _lvBool(@"LockVideoDebug"); }   // 诊断模式

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

#pragma mark - 诊断日志（只记录"每个类第一次出现"，防刷屏）

static void _lvLog(NSString *line) {
    @try {
        if (![[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]) { return; }
        NSString *old = [NSString stringWithContentsOfFile:kLVLogFile
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil] ?: @"";
        if (old.length > 8192) { old = @""; }   // 防止无限增长
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

#pragma mark - 锁屏视图树扫描（排查用：把整个窗口层级导出到文件）

static NSTimer *gDumpTimer = nil;
static int gDumpTicks = 0;

static void _lvDumpView(UIView *v, int depth, NSMutableString *s, int *lines) {
    if (!v || depth > 14 || *lines > 4000) { return; }
    @try {
        NSString *cls = NSStringFromClass([v class]);
        NSString *mark = ([cls.lowercaseString containsString:@"notification"] ||
                          [cls.lowercaseString containsString:@"notif"]) ? @" <<< 通知相关" : @"";
        CGRect f = v.frame;
        [s appendFormat:@"%@%@ (%.0f,%.0f %.0fx%.0f)%@\n",
            [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
            cls, f.origin.x, f.origin.y, f.size.width, f.size.height, mark];
        (*lines)++;
        for (UIView *c in v.subviews) { _lvDumpView(c, depth + 1, s, lines); }
    } @catch (NSException *e) {}
}

static void _lvDumpOnce(void) {
    @try {
        if (![[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]) { return; }
        NSMutableString *s = [NSMutableString string];
        [s appendFormat:@"== 第 %d 次扫描 ==\n", gDumpTicks];
        int lines = 0;
        id app = [UIApplication sharedApplication];
        NSArray *wins = nil;
        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) {}
        for (UIWindow *w in wins) {
            [s appendFormat:@"\n[WINDOW] %@\n", NSStringFromClass([w class])];
            _lvDumpView(w, 0, s, &lines);
        }
        if (wins.count == 0) { [s appendString:@"(取不到 windows)\n"]; }
        [s writeToFile:kLVDumpFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (NSException *e) {}
}

static void _lvStartDump(void) {
    @try {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (gDumpTimer) { [gDumpTimer invalidate]; gDumpTimer = nil; }
            gDumpTicks = 0;
            _lvLog(@"开始扫描视图树（90 秒）");
            gDumpTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(NSTimer *t) {
                gDumpTicks++;
                _lvDumpOnce();
                if (gDumpTicks >= 45) {
                    [t invalidate];
                    gDumpTimer = nil;
                    _lvLog(@"扫描结束，请查看 视图树.txt");
                }
            }];
        });
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

#pragma mark - 视图识别（大小写不敏感）

static BOOL _lvIsNotificationView(UIView *v) {
    @try {
        NSString *cls = NSStringFromClass([v class]);
        if (!cls) { return NO; }
        NSString *low = cls.lowercaseString;
        if (![low containsString:@"notification"]) { return NO; }
        return [low containsString:@"cell"]    || [low containsString:@"list"]       ||
               [low containsString:@"background"] || [low containsString:@"banner"]  ||
               [low containsString:@"stack"]   || [low containsString:@"controller"] ||
               [low containsString:@"content"] || [low containsString:@"view"];
    } @catch (NSException *e) { return NO; }
}

#pragma mark - 挂载

static void _lvInsertLayer(UIView *v, AVPlayerLayer *l) {
    // 找到最上层的毛玻璃/背景视图，把视频插在它上面、文字内容之下
    UIView *bg = nil;
    for (UIView *s in v.subviews) {
        NSString *c = NSStringFromClass(s.class);
        BOOL isBg = [s isKindOfClass:[UIVisualEffectView class]] ||
                    [c containsString:@"Effect"] || [c containsString:@"Material"] ||
                    [c containsString:@"Background"] || [c containsString:@"Backdrop"] ||
                    [c containsString:@"Blur"];
        if (isBg) { bg = s; }
    }
    if (bg && bg.layer != l.superlayer) {
        [v.layer insertSublayer:l above:bg.layer];
    } else if (v.subviews.count > 0 && v.layer != l.superlayer) {
        [v.layer insertSublayer:l above:((UIView *)v.subviews[0]).layer];
    } else if (l.superlayer != v.layer) {
        [v.layer addSublayer:l];
    }
}

static void _lvAttach(UIView *v) {
    if (!v || !_lvEnabled()) { return; }
    @try {
        AVPlayer *p = _lvPlayer();

        if (!p) {
            // 找不到视频：诊断模式下盖绿色层，证明 tweak 已经命中通知卡片
            if (_lvDebug()) {
                CALayer *f = objc_getAssociatedObject(v, &kFallbackKey);
                if (!f) {
                    f = [CALayer layer];
                    f.backgroundColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.0 alpha:0.45].CGColor;
                    objc_setAssociatedObject(v, &kFallbackKey, f, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                    [v.layer addSublayer:f];
                    _lvLogOnce(NSStringFromClass(v.class), @"绿色诊断层(没找到视频文件)");
                }
                f.frame = v.bounds;
            }
            return;
        }

        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        if (!l) {
            l = [AVPlayerLayer playerLayerWithPlayer:p];
            l.videoGravity = AVLayerVideoGravityResizeAspectFill;
            objc_setAssociatedObject(v, &kLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            _lvLogOnce(NSStringFromClass(v.class), @"已挂载视频");
        }
        if (l.player != p) { l.player = p; }   // 素材切换后更新引用

        _lvInsertLayer(v, l);
        l.frame = v.bounds;
        [p play];
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

#pragma mark - iOS 16 锁屏通知显式 hook（NCNotificationContentView 是通知卡片内容视图）

%group LVNotif16
%hook NCNotificationContentView
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
            _lvInsertLayer(v, l);
            l.frame = v.bounds;
            if (v.window && gPlayer) { [gPlayer play]; }
        }
        if (_lvDebug()) {
            CALayer *f = objc_getAssociatedObject(v, &kFallbackKey);
            if (f) { f.frame = v.bounds; }
        }
    } @catch (NSException *e) {}
}
%end
%end

#pragma mark - 全局 hook（UIView 级别兜底，自动匹配所有通知视图）

static void (*_orig_didMoveToWindow)(UIView *, SEL);
static void _lv_didMoveToWindow(UIView *self, SEL _cmd) {
    _orig_didMoveToWindow(self, _cmd);
    @try {
        if (self.window && _lvIsNotificationView(self)) { _lvOnMatch(self); }
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

#pragma mark - 设置变化回调（C 函数，ARC 下 block 不能转 CFNotificationCallback）

static void _lvPrefsChanged(CFNotificationCenterRef center,
                            void *observer,
                            CFStringRef name,
                            const void *object,
                            CFDictionaryRef userInfo) {
    @try {
        NSString *np = _lvPath();
        if (![np isEqualToString:gCurrentPath]) {
            _lvResetPlayer();          // 素材变了 -> 重建播放器
        } else if (gPlayer) {
            gPlayer.muted = !_lvSound();   // 只改了声音 -> 即时生效
        }
        if (_lvDebug()) { gLoggedClasses = nil; }   // 重新记日志
    } @catch (NSException *e) {}
}

static void _lvDumpNotifyCallback(CFNotificationCenterRef center,
                                  void *observer,
                                  CFStringRef name,
                                  const void *object,
                                  CFDictionaryRef userInfo) {
    @try { _lvStartDump(); } @catch (NSException *e) {}
}

#pragma mark - ctor

%ctor {
    @try {
        // 1) iOS 16 锁屏通知：显式 hook NCNotificationContentView（不依赖子类调用 super）
        if (objc_getClass("NCNotificationContentView") != Nil) {
            %init(LVNotif16);
            _lvLog(@"NCNotificationContentView 显式 hook OK");
        } else {
            _lvLog(@"NCNotificationContentView 不存在(非 iOS16?)");
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
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        _lvPrefsChanged,
                                        kLVNotify,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        _lvDumpNotifyCallback,
                                        kLVDumpNotify,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        _lvLog([NSString stringWithFormat:@"状态: 启用=%d 声音=%d 诊断=%d 视频=%@ 目录存在=%d",
                _lvEnabled(), _lvSound(), _lvDebug(), _lvPath() ?: @"(无)",
                [[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]]);
        _lvLog(@"===== 1.0.18 加载完成 =====");
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"ctor 异常: %@", e]);
    }
}
