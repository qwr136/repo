#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
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
    NSString *saved = _lvString(@"LockVideoPath");
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

#pragma mark - 挂载

// 关键：把视频插在 cell 的最底层（index 0），让 cell 自带的毛玻璃、icon、文字全部浮在视频之上。
// 这样视频作为卡片背景透出来，文字保持清晰可读。
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
            l.cornerRadius = 18.0;
            l.masksToBounds = YES;
            objc_setAssociatedObject(v, &kLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            _lvLogOnce(NSStringFromClass(v.class), @"已挂载视频");
        }
        if (l.player != p) { l.player = p; }   // 素材切换后更新引用

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

#pragma mark - 轮询扫描（不依赖任何 hook 传播：直接遍历锁屏视图树找通知卡片）

static NSTimer *gPollTimer = nil;
static CFTimeInterval gLastDump = 0;

// 只挂用户实际看到的圆角卡片本体（NCNotificationShortLookView / 横幅），
// 排除列表容器、遮罩、标题、外层 cell——它们的 bounds 远大于卡片，挂上会铺满或藏在卡片背后
static BOOL _lvIsCardClass(NSString *cls) {
    NSString *low = cls.lowercaseString;
    if (![low containsString:@"notif"]) { return NO; }
    if ([low containsString:@"stackdimming"]) { return NO; }
    if ([low containsString:@"header"])       { return NO; }
    if ([low containsString:@"listview"])     { return NO; }
    if ([low containsString:@"sectionlist"])  { return NO; }
    if ([low containsString:@"listcell"])     { return NO; }
    if ([low containsString:@"content"])      { return NO; }
    // 只挂用户实际看到的圆角卡片本体
    return [low containsString:@"shortlook"] || [low containsString:@"banner"];
}

static void _lvScanAndAttach(UIView *root, BOOL *foundAny) {
    @try {
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
        int visited = 0;
        while (stack.count > 0 && visited < 4000) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            visited++;
            NSString *cls = NSStringFromClass([v class]);
            if (_lvIsCardClass(cls)) {
                *foundAny = YES;
                _lvLogOnce(cls, @"轮询扫描命中");
                _lvOnMatch(v);          // 挂载视频（幂等）
            }
            for (UIView *c in v.subviews) { [stack addObject:c]; }
        }
    } @catch (NSException *e) {}
}

static void _lvPollTick(void) {
    @try {
        if (!_lvEnabled()) { return; }
        id app = [UIApplication sharedApplication];
        NSArray *wins = nil;
        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) {}
        for (UIWindow *w in wins) {
            NSString *c = NSStringFromClass([w class]);
            // 锁屏（CoverSheet）窗口；iOS16 起锁屏都在这个窗口里
            if (![c containsString:@"CoverSheet"] && ![c containsString:@"LockScreen"] &&
                ![c containsString:@"Banner"]) { continue; }
            if (w.hidden || w.alpha <= 0.01) { continue; }
            BOOL found = NO;
            _lvScanAndAttach(w, &found);
            if (found) {
                CFTimeInterval now = CACurrentMediaTime();
                if (now - gLastDump > 10.0) {      // 最多每 10 秒导出一次
                    gLastDump = now;
                    _lvDumpOnce();
                }
            }
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
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        _lvDumpNotifyCallback,
                                        kLVDumpNotify,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        _lvLog([NSString stringWithFormat:@"状态: 启用=%d 声音=%d 诊断=%d 视频=%@ 目录存在=%d",
                _lvEnabled(), _lvSound(), _lvDebug(), _lvPath() ?: @"(无)",
                [[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]]);
        _lvLog([NSString stringWithFormat:@"plist文件内容: %@", _lvPrefs()]);
        {
            NSMutableString *s = [NSMutableString string];
            for (NSString *suite in _lvSuites()) {
                for (NSString *k in @[@"LockVideoEnabled", @"LockVideoSound", @"LockVideoDebug"]) {
                    CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
                    CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)k, (__bridge CFStringRef)suite);
                    id val = cf ? CFBridgingRelease(cf) : nil;
                    [s appendFormat:@"%@/%@=%@ ", suite, k, val ?: @"(无)"];
                }
            }
            _lvLog([NSString stringWithFormat:@"系统偏好: %@", s]);
        }
        _lvLog(@"===== 1.0.24 加载完成 =====");
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"ctor 异常: %@", e]);
    }
}
