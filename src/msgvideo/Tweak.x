// 信息 App 视频背景 (com.xiaofei.msgbgvideo)
// 把视频铺到「信息」App 的窗口最底层作为背景，并让界面背景透明化。
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <sys/sysctl.h>
#import <string.h>

// 前向声明：定义见文件末尾 %ctor 之前，供 _mvPollTick 等调用
static BOOL _mvProcRunning(const char *substr);

#define kMVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.msgbgvideo.plist"
#define kMVNotify    CFSTR("com.xiaofei.msgbgvideo/ReloadPrefs")
#define kMVVideoDir  @"/var/mobile/信息视频"
#define kMVLogFile   @"/var/mobile/信息视频/Hook日志.txt"
// 兜底日志：无论素材目录存不存在都写，用来确认插件到底有没有注入
#define kMVLogFile2  @"/var/mobile/Library/Preferences/msgvideo_hook.log"

static AVPlayer *gPlayer = nil;
static NSString *gCurrentPath = nil;
static id gLoopObserver = nil;
static char kLayerKey;
static char kViewLayerKey;
static char kOrigBGKey;
static BOOL gTargetMounted = NO;   // 是否已挂到会话列表/聊天页视图上
static NSMutableSet<NSString *> *gLoggedClasses = nil;
static BOOL gAppActive = YES;
static int gUpdateCount = 0;
static int gPollCount = 0;
static BOOL gInMessages = NO;   // 注入到「信息」App 时才干活（其它进程只写一行探针，不干活）

#pragma mark - 偏好（直接读文件 + 系统偏好双保险）

static NSArray<NSString *> *_mvSuites(void) {
    return @[@"com.xiaofei.msgbgvideo", @"com.xiaofei.msgbgvideo.prefs"];
}

static NSDictionary *_mvPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kMVPrefsFile] ?: @{};
}

// 同时读 plist 文件 + 系统偏好，任一为 YES 即 YES
static BOOL _mvBool(NSString *key) {
    @try {
        id v = _mvPrefs()[key];
        if ([v respondsToSelector:@selector(boolValue)] && [v boolValue]) { return YES; }
        for (NSString *suite in _mvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)] && [val boolValue]) { return YES; }
        }
    } @catch (NSException *e) {}
    return NO;
}

// 值是否存在（用于区分「没设过」和「显式关掉」）
static BOOL _mvHas(NSString *key) {
    @try {
        if (_mvPrefs()[key]) { return YES; }
        for (NSString *suite in _mvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)suite);
            if (cf) { CFRelease(cf); return YES; }
        }
    } @catch (NSException *e) {}
    return NO;
}

// 没设过时默认开启（设置面板里开关也是默认开）
static BOOL _mvEnabled(void) {
    if (!_mvHas(@"MsgVideoEnabled")) { return YES; }
    return _mvBool(@"MsgVideoEnabled");
}

// 声音默认开启：只有用户显式设为 NO 才静音
static BOOL _mvSound(void) {
    if (!_mvHas(@"MsgVideoSound")) { return YES; }
    return _mvBool(@"MsgVideoSound");
}

// 透明度（默认 1.0：完整显示视频）
static CGFloat _mvAlpha(void) {
    @try {
        id v = _mvPrefs()[@"MsgVideoAlpha"];
        if ([v respondsToSelector:@selector(floatValue)]) {
            CGFloat a = [v floatValue];
            if (a > 0.05) { return MIN(a, 1.0); }
        }
        for (NSString *suite in _mvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("MsgVideoAlpha"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(floatValue)]) {
                CGFloat a = [val floatValue];
                if (a > 0.05) { return MIN(a, 1.0); }
            }
        }
    } @catch (NSException *e) {}
    return 1.0;
}

static NSString *_mvString(NSString *key) {
    @try {
        id v = _mvPrefs()[key];
        if ([v isKindOfClass:[NSString class]] && [v length]) { return v; }
        for (NSString *suite in _mvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val isKindOfClass:[NSString class]] && [val length]) { return val; }
        }
    } @catch (NSException *e) {}
    return nil;
}

static NSArray<NSString *> *_mvScanFiles(void) {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *f in [fm contentsOfDirectoryAtPath:kMVVideoDir error:nil]) {
            NSString *ext = [f pathExtension].lowercaseString;
            if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
                [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"]) {
                [out addObject:[kMVVideoDir stringByAppendingPathComponent:f]];
            }
        }
        return [out sortedArrayUsingSelector:@selector(compare:)];
    } @catch (NSException *e) {}
    return @[];
}

static NSString *_mvPath(void) {
    NSString *saved = _mvString(@"MsgVideoPath");
    if ([saved isKindOfClass:[NSString class]] &&
        [[NSFileManager defaultManager] fileExistsAtPath:saved]) {
        return saved;
    }
    return _mvScanFiles().firstObject;
}

#pragma mark - 日志（每个类只记一次，防刷屏）

static void _mvLog(NSString *line) {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        // 目录不存在就建一个（顺便帮用户把素材目录准备好）
        if (![fm fileExistsAtPath:kMVVideoDir]) {
            [fm createDirectoryAtPath:kMVVideoDir
          withIntermediateDirectories:YES
                           attributes:nil
                                error:nil];
        }
        for (NSString *path in @[kMVLogFile, kMVLogFile2]) {
            NSString *old = [NSString stringWithContentsOfFile:path
                                                      encoding:NSUTF8StringEncoding
                                                         error:nil] ?: @"";
            if (old.length > 32768) { old = @""; }
            NSString *full = [old stringByAppendingFormat:@"%@\n", line];
            [full writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
    } @catch (NSException *e) {}
}

static void _mvLogOnce(NSString *cls, NSString *action) {
    @try {
        if (!gLoggedClasses) { gLoggedClasses = [NSMutableSet set]; }
        NSString *key = [cls stringByAppendingString:action];
        if ([gLoggedClasses containsObject:key]) { return; }
        [gLoggedClasses addObject:key];
        _mvLog([NSString stringWithFormat:@"%@ -> %@", cls, action]);
    } @catch (NSException *e) {}
}

#pragma mark - 播放器

static AVPlayer *_mvPlayer(void) {
    @try {
        if (!gPlayer) {
            NSString *path = _mvPath();
            if (!path) {
                _mvLogOnce(@"扫描结果", [NSString stringWithFormat:@"%@ 里没有找到视频文件", kMVVideoDir]);
                return nil;
            }
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
            if (!item) { return nil; }
            gPlayer = [AVPlayer playerWithPlayerItem:item];
            gPlayer.actionAtItemEnd = AVPlayerActionAtItemEndNone;
            gPlayer.muted = !_mvSound();
            // 不让视频播放阻止屏幕自动熄屏
            @try {
                if ([gPlayer respondsToSelector:NSSelectorFromString(@"setPreventsDisplaySleepDuringVideoPlayback:")]) {
                    [gPlayer setValue:@NO forKey:@"preventsDisplaySleepDuringVideoPlayback"];
                }
            } @catch (NSException *e) {}
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
            _mvLog([NSString stringWithFormat:@"播放器创建: %@ 声音=%d", path, _mvSound()]);
        }
        return gPlayer;
    } @catch (NSException *e) {
        _mvLog([NSString stringWithFormat:@"player 异常: %@", e]);
        return nil;
    }
}

static void _mvResetPlayer(void) {
    @try {
        if (gLoopObserver) {
            [[NSNotificationCenter defaultCenter] removeObserver:gLoopObserver];
            gLoopObserver = nil;
        }
        if (gPlayer) { [gPlayer pause]; gPlayer = nil; }
        gCurrentPath = nil;
    } @catch (NSException *e) {}
}

#pragma mark - 透明化（让窗口底层的视频透出来）

// 记录原色，方便关闭开关时还原
static void _mvMakeClear(UIView *v) {
    @try {
        if (!v) { return; }
        UIColor *c = v.backgroundColor;
        if (!c) { return; }
        CGFloat a = 1.0;
        @try { a = CGColorGetAlpha(c.CGColor); } @catch (NSException *e) {}
        if (a < 0.05) { return; }
        if (!objc_getAssociatedObject(v, &kOrigBGKey)) {
            objc_setAssociatedObject(v, &kOrigBGKey, c, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        v.backgroundColor = [UIColor clearColor];
    } @catch (NSException *e) {}
}

static void _mvRestore(UIView *v) {
    @try {
        UIColor *orig = objc_getAssociatedObject(v, &kOrigBGKey);
        if (orig) {
            v.backgroundColor = orig;
            objc_setAssociatedObject(v, &kOrigBGKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    } @catch (NSException *e) {}
}

// 递归处理：table/collection 本身、cell、以及全屏纯色 UIView
static void _mvTransparentTree(UIView *root, BOOL restore) {
    if (!root) { return; }
    @try {
        CGSize screen = [UIScreen mainScreen].bounds.size;
        CGFloat screenArea = MAX(screen.width * screen.height, 1.0);
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
        int visited = 0;
        while (stack.count > 0 && visited < 1500) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            visited++;

            if (restore) {
                _mvRestore(v);
            } else {
                NSString *cls = NSStringFromClass(v.class);
                BOOL isTable  = [v isKindOfClass:[UITableView class]];
                BOOL isColl   = [v isKindOfClass:[UICollectionView class]];
                BOOL isCell   = [v isKindOfClass:[UITableViewCell class]] ||
                                [v isKindOfClass:[UICollectionViewCell class]];
                if (isTable || isColl) {
                    _mvMakeClear(v);
                    UIView *bg = nil;
                    @try { bg = [v valueForKey:@"backgroundView"]; } @catch (NSException *e) {}
                    if (bg) { bg.hidden = YES; }
                } else if (isCell) {
                    // 只清 cell 自身背景，气泡/文字是子视图，不受影响
                    _mvMakeClear(v);
                } else if ([cls isEqualToString:@"UIView"]) {
                    // 全屏纯色容器（信息 App 的白色底）也清掉
                    CGSize sz = v.bounds.size;
                    if (sz.width * sz.height >= screenArea * 0.7) { _mvMakeClear(v); }
                }
            }

            for (UIView *c in v.subviews) { [stack addObject:c]; }
        }
    } @catch (NSException *e) {}
}

#pragma mark - 挂载到具体界面视图（CKConversationListCollectionView / 聊天页）

// 会话列表：CKConversationListCollectionView（CKConversationListController 的根视图）
// 聊天页：CKTranscript* 系列
static BOOL _mvIsTargetClass(NSString *cls) {
    if (!cls) { return NO; }
    NSString *low = cls.lowercaseString;
    if ([low containsString:@"conversationlist"])  { return YES; }
    if ([low containsString:@"cktranscript"])      { return YES; }
    if ([low containsString:@"messagetranscript"]) { return YES; }
    return NO;
}

// 把视频层插到目标视图自身 layer 的最底层，并清掉它自己的背景色。
// 滚动时用 contentOffset 修正 frame，保证视频固定在屏幕上不跟着滚。
static void _mvAttachToView(UIView *v) {
    @try {
        if (!gInMessages) { return; }
        if (!v || !_mvEnabled()) { return; }
        AVPlayer *p = _mvPlayer();
        if (!p) { return; }

        _mvMakeClear(v);   // 不清背景，视频永远被它自己的白底挡住

        AVPlayerLayer *l = objc_getAssociatedObject(v, &kViewLayerKey);
        BOOL isNew = (l == nil);
        if (!l) {
            l = [AVPlayerLayer playerLayerWithPlayer:p];
            l.videoGravity = AVLayerVideoGravityResizeAspectFill;
            l.masksToBounds = YES;
            objc_setAssociatedObject(v, &kViewLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [v.layer insertSublayer:l atIndex:0];
            _mvLog([NSString stringWithFormat:@"已挂到界面视图: %@ %.0fx%.0f",
                    NSStringFromClass(v.class), v.bounds.size.width, v.bounds.size.height]);
        }
        if (l.superlayer != v.layer) {
            [l removeFromSuperlayer];
            [v.layer insertSublayer:l atIndex:0];
        }
        if (l.player != p) { l.player = p; }

        CGRect f = v.bounds;
        if ([v isKindOfClass:[UIScrollView class]]) {
            CGPoint off = ((UIScrollView *)v).contentOffset;
            f = CGRectMake(off.x, off.y, f.size.width, f.size.height);
        }
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        l.frame = f;
        l.opacity = (float)_mvAlpha();
        [CATransaction commit];
        l.hidden = NO;

        gUpdateCount++;
        if (isNew || (gUpdateCount % 10 == 0)) {
            _mvTransparentTree(v, NO);
        }

        gTargetMounted = YES;
        if (gAppActive) { [p play]; } else { [p pause]; }
    } @catch (NSException *e) {
        _mvLog([NSString stringWithFormat:@"view attach 异常: %@", e]);
    }
}

static void _mvScanTargets(UIView *root) {
    @try {
        if (!gInMessages) { return; }
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
        int visited = 0;
        while (stack.count > 0 && visited < 1500) {
            UIView *v = stack.lastObject;
            [stack removeLastObject];
            visited++;
            if (_mvIsTargetClass(NSStringFromClass(v.class))) {
                _mvAttachToView(v);
            }
            for (UIView *c in v.subviews) { [stack addObject:c]; }
        }
    } @catch (NSException *e) {}
}

// 诊断：把窗口的视图树打出来（深度 4、最多 60 行），用来确认真实类名
static void _mvDumpRec(UIView *v, int depth, NSMutableString *s, int *lines) {
    if (depth > 4 || *lines > 60) { return; }
    @try {
        NSMutableString *pad = [NSMutableString string];
        for (int i = 0; i < depth; i++) { [pad appendString:@"  "]; }
        [s appendFormat:@"%@%@ %.0fx%.0f\n", pad, NSStringFromClass(v.class),
         v.bounds.size.width, v.bounds.size.height];
        (*lines)++;
        for (UIView *c in v.subviews) { _mvDumpRec(c, depth + 1, s, lines); }
    } @catch (NSException *e) {}
}

static void _mvDumpWindow(UIWindow *w) {
    @try {
        NSMutableString *s = [NSMutableString string];
        int lines = 0;
        [s appendFormat:@"--- 窗口 %@ ---\n", NSStringFromClass(w.class)];
        _mvDumpRec(w, 0, s, &lines);
        _mvLog(s);
    } @catch (NSException *e) {}
}

#pragma mark - 挂载到窗口

static void _mvUpdateWindow(UIWindow *w) {
    @try {
        if (!gInMessages) { return; }
        if (!w) { return; }
        if (w.hidden || w.alpha <= 0.01) { return; }

        if (!_mvEnabled()) {
            AVPlayerLayer *ex = objc_getAssociatedObject(w, &kLayerKey);
            if (ex) { ex.hidden = YES; }
            _mvTransparentTree(w, YES);
            return;
        }

        AVPlayer *p = _mvPlayer();
        if (!p) { return; }

        AVPlayerLayer *l = objc_getAssociatedObject(w, &kLayerKey);
        BOOL isNew = (l == nil);
        if (!l) {
            l = [AVPlayerLayer playerLayerWithPlayer:p];
            l.videoGravity = AVLayerVideoGravityResizeAspectFill;
            l.masksToBounds = YES;
            objc_setAssociatedObject(w, &kLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [w.layer insertSublayer:l atIndex:0];
            _mvLog([NSString stringWithFormat:@"已挂载: %@ %.0fx%.0f",
                    NSStringFromClass(w.class), w.bounds.size.width, w.bounds.size.height]);
        }
        if (l.superlayer != w.layer) {
            [l removeFromSuperlayer];
            [w.layer insertSublayer:l atIndex:0];
        }
        if (l.player != p) { l.player = p; }
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        l.frame = w.bounds;
        l.opacity = (float)_mvAlpha();
        [CATransaction commit];
        // 已经挂到会话列表/聊天页视图上时，窗口这一层就藏起来，避免两层叠加
        l.hidden = gTargetMounted;
        _mvMakeClear(w);   // 窗口自身若是不透明底色也会挡住视频

        // 让界面背景透明，视频才透得出来。
        // 全树遍历有开销，首次挂载立刻做，之后每 10 次才做一次（新 cell 由 hook 补）。
        gUpdateCount++;
        if (isNew || (gUpdateCount % 10 == 0)) {
            _mvTransparentTree(w, NO);
        }
        if (w.rootViewController && w.rootViewController.view) {
            _mvMakeClear(w.rootViewController.view);
        }

        if (gAppActive) { [p play]; } else { [p pause]; }
    } @catch (NSException *e) {
        _mvLog([NSString stringWithFormat:@"window attach 异常: %@", e]);
    }
}

#pragma mark - 轮询（兜底，保证任何界面都能挂上）

static void _mvPollTick(void) {
    @try {
        if (!gInMessages) {
            // 非信息App进程（如 SpringBoard）：周期性探测 MobileSMS 是否在运行，绝不动界面。
            // 用来客观区分「用户没冷启动信息App」与「注入层排除了MobileSMS」。
            gPollCount++;
            if (gPollCount % 20 == 1) {
                BOOL ms = _mvProcRunning("MobileSMS");
                _mvLog([NSString stringWithFormat:
                    @"探针: MobileSMS 进程=%@ | 本插件现运行于 %@（未被注入到 MobileSMS）%@",
                    ms ? @"运行中" : @"未运行",
                    [[NSProcessInfo processInfo] processName],
                    ms ? @"→ 疑似注入层排除了MobileSMS，请检查 Choicy/TweakRestrict/Dopamine 设置"
                       : @"→ 请冷启动「信息」App 后再看本日志"]);
            }
            return;
        }
        if (!_mvEnabled()) {
            if (gPlayer) { [gPlayer pause]; }
            return;
        }
        id app = [UIApplication sharedApplication];
        NSArray *wins = nil;
        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) {}

        // 先找会话列表 / 聊天页视图并挂上（优先），再更新窗口兜底层
        gTargetMounted = NO;
        for (UIWindow *w in wins) {
            if (![w isKindOfClass:[UIWindow class]]) { continue; }
            if ([NSStringFromClass(w.class) containsString:@"TextEffects"]) { continue; }
            _mvScanTargets(w);
        }

        for (UIWindow *w in wins) {
            if (![w isKindOfClass:[UIWindow class]]) { continue; }
            if ([NSStringFromClass(w.class) containsString:@"TextEffects"]) { continue; }
            _mvUpdateWindow(w);
        }

        if (!gTargetMounted) {
            _mvLogOnce(@"扫描结果", @"没找到会话列表视图(CKConversationList*/CKTranscript*)");
        }

        // 心跳：每 30 秒一行，确认插件活着；没挂上时顺便打一次视图树
        gPollCount++;
        if (gPollCount % 20 == 1) {
            _mvLog([NSString stringWithFormat:@"心跳: 启用=%d 播放器=%d 挂到列表=%d 窗口=%lu",
                    _mvEnabled(), (gPlayer != nil), gTargetMounted, (unsigned long)wins.count]);
            if (!gTargetMounted) {
                for (UIWindow *w in wins) {
                    if (![w isKindOfClass:[UIWindow class]]) { continue; }
                    if ([NSStringFromClass(w.class) containsString:@"TextEffects"]) { continue; }
                    _mvDumpWindow(w);
                }
            }
        }
    } @catch (NSException *e) {}
}

static void _mvReloadPrefs(void) {
    @try {
        NSString *np = _mvPath();
        if (![np isEqualToString:gCurrentPath]) {
            _mvResetPlayer();
        } else if (gPlayer) {
            gPlayer.muted = !_mvSound();
        }
    } @catch (NSException *e) {}
}

#pragma mark - hooks

%hook UIWindow

- (void)layoutSubviews {
    %orig;
    @try { _mvUpdateWindow(self); } @catch (NSException *e) {}
}

%end

// 会话列表 / 聊天页：直接挂到这个滚动视图上
%hook UIScrollView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (_mvEnabled() && _mvIsTargetClass(NSStringFromClass(self.class))) {
            _mvAttachToView(self);
        }
    } @catch (NSException *e) {}
}

- (void)layoutSubviews {
    %orig;
    @try {
        if (_mvEnabled() && _mvIsTargetClass(NSStringFromClass(self.class))) {
            _mvAttachToView(self);
        }
    } @catch (NSException *e) {}
}

%end

// cell 复用时会重新创建，这里补一次透明
%hook UITableViewCell
- (void)didMoveToWindow {
    %orig;
    @try { if (_mvEnabled()) { _mvMakeClear(self); } } @catch (NSException *e) {}
}
%end

%hook UICollectionViewCell
- (void)didMoveToWindow {
    %orig;
    @try { if (_mvEnabled()) { _mvMakeClear(self); } } @catch (NSException *e) {}
}
%end

#pragma mark - ctor

static void _mvPrefsChanged(CFNotificationCenterRef center, void *observer,
                            CFStringRef name, const void *object, CFDictionaryRef info) {
    @try { _mvReloadPrefs(); _mvPollTick(); } @catch (NSException *e) {}
}

#pragma mark - 进程探测（SpringBoard 探针用）

// 用 sysctl(KERN_PROC_ALL) 枚举进程，判断某个名字的进程是否在运行。
// 目的：客观确认到底是「用户没冷启动信息App（MobileSMS 根本没运行）」，
// 还是「MobileSMS 在运行但本插件没被注入到它（注入层问题）」。
static BOOL _mvProcRunning(const char *substr) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) != 0) { return NO; }
    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(size);
    if (!procs) { return NO; }
    if (sysctl(mib, 4, procs, &size, NULL, 0) != 0) { free(procs); return NO; }
    int count = (int)(size / sizeof(struct kinfo_proc));
    BOOL found = NO;
    for (int i = 0; i < count; i++) {
        if (strstr(procs[i].kp_proc.p_comm, substr) != NULL) { found = YES; break; }
    }
    free(procs);
    return found;
}

%ctor {
    @try {
        // 判断当前进程：只要进程名或 bundle 含 "mobilesms" 就当作信息App。
        // 用宽松匹配而非精确 isEqualToString，避免早期注入时 mainBundle 未就绪，
        // 导致 bundleIdentifier 返回非预期值而被误判为「非信息App」从而被静默。
        NSString *bid = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSString *pname = [[NSProcessInfo processInfo] processName] ?: @"";
        NSString *tag = [[NSString stringWithFormat:@"%@ %@", bid, pname] lowercaseString];
        gInMessages = ([tag containsString:@"mobilesms"]);
        BOOL isSB = [bid isEqualToString:@"com.apple.springboard"];

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL, _mvPrefsChanged, kMVNotify, NULL,
                                        CFNotificationSuspensionBehaviorCoalesce);
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) { gAppActive = YES; }];
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationWillResignActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *n) {
                gAppActive = NO;
                @try { if (gPlayer) { [gPlayer pause]; } } @catch (NSException *e) {}
            }];

        // 全局探针：dylib 一旦被任意进程加载就写一行（进程名 + bundle），方便确认落点。
        _mvLog([NSString stringWithFormat:@"dylib 已加载: 进程=%@ bundle=%@ 信息App=%d",
                pname, bid ?: @"(无)", gInMessages]);
        if (!gInMessages) {
            BOOL ms = _mvProcRunning("MobileSMS");
            _mvLog([NSString stringWithFormat:@"探针: 当前是%@，不是信息App，只记录不干活；MobileSMS 进程=%@",
                    isSB ? @"SpringBoard" : (bid.length ? bid : pname),
                    ms ? @"运行中" : @"未运行"]);
        } else {
            _mvLog([NSString stringWithFormat:@"状态: 启用=%d 声音=%d 透明度=%.2f 视频=%@ 目录存在=%d",
                    _mvEnabled(), _mvSound(), _mvAlpha(), _mvPath() ?: @"(无)",
                    [[NSFileManager defaultManager] fileExistsAtPath:kMVVideoDir]]);
        }
        _mvLog(@"===== 1.0.6 信息视频背景 加载完成 =====");

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            _mvPollTick();
        });
        [NSTimer scheduledTimerWithTimeInterval:1.5
                                        repeats:YES
                                          block:^(NSTimer *t) { _mvPollTick(); }];
    } @catch (NSException *e) {}
}
