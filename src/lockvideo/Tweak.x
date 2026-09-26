#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <ImageIO/ImageIO.h>

#define kLVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.notifybgvideo.plist"
#define kLVNotify    CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs")
#define kLVVideoDir  @"/var/mobile/通知视频"
#define kLVLogFile   @"/var/mobile/通知视频/Hook日志.txt"

// path -> AVPlayer：支持主素材/选项素材/清除素材分别播放
static NSMutableDictionary<NSString *, AVPlayer *> *gPlayerMap = nil;
static NSMutableDictionary<NSString *, id> *gObserverMap = nil;
static char kLayerKey;
static char kImgKey;
static char kPathKey;          // 记录 view 当前挂载的素材路径
static char kHideDoneKey;
static char kOrigHiddenKey;
static char kOrigAlphaKey;
static char kOrigBgColorKey;
static NSMutableArray<UIView *> *_lvAttachedViews = nil;   // 强引用：关闭插件时确保视图还在
static NSMutableSet<NSString *> *gLoggedClasses = nil;
static BOOL gWasEnabled = NO;                 // 上一次「启用」状态，用于检测开关翻转

#pragma mark - 偏好（直接读文件）

static NSArray<NSString *> *_lvSuites(void) {
    return @[@"com.xiaofei.notifybgvideo", @"com.xiaofei.notifybgvideo.prefs"];
}

static NSDictionary *_lvPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile] ?: @{};
}

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

static BOOL _lvAlphaEnabled(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoAlphaEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoAlphaEnabled"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)]) { return [val boolValue]; }
        }
    } @catch (NSException *e) {}
    return YES;
}

static CGFloat _lvAlpha(void) {
    if (!_lvAlphaEnabled()) { return 1.0; }
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

static BOOL _lvCornerEnabled(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoCornerEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoCornerEnabled"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)]) { return [val boolValue]; }
        }
    } @catch (NSException *e) {}
    return YES;
}

static CGFloat _lvCornerRadius(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoCornerRadius"];
        if ([v respondsToSelector:@selector(floatValue)]) {
            CGFloat r = [v floatValue];
            if (r >= 0) { return MIN(r, 40.0); }
        }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoCornerRadius"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(floatValue)]) {
                CGFloat r = [val floatValue];
                if (r >= 0) { return MIN(r, 40.0); }
            }
        }
    } @catch (NSException *e) {}
    return 18.0;
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
    return YES;
}

static NSArray<NSString *> *_lvScanFiles(void) {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSMutableArray *out = [NSMutableArray array];
        for (NSString *f in [fm contentsOfDirectoryAtPath:kLVVideoDir error:nil]) {
            NSString *ext = [f pathExtension].lowercaseString;
            if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] ||
                [ext isEqualToString:@"m4v"] || [ext isEqualToString:@"avi"] ||
                [ext isEqualToString:@"gif"] || [ext isEqualToString:@"png"] ||
                [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] ||
                [ext isEqualToString:@"heic"]) {
                [out addObject:[kLVVideoDir stringByAppendingPathComponent:f]];
            }
        }
        return [out sortedArrayUsingSelector:@selector(compare:)];
    } @catch (NSException *e) {}
    return @[];
}

static NSString *_lvPathForKey(NSString *key) {
    @try {
        id v = _lvPrefs()[key];
        if ([v isKindOfClass:[NSString class]] && [v length] &&
            [[NSFileManager defaultManager] fileExistsAtPath:v]) {
            return v;
        }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val isKindOfClass:[NSString class]] && [val length] &&
                [[NSFileManager defaultManager] fileExistsAtPath:val]) {
                return val;
            }
        }
    } @catch (NSException *e) {}
    return nil;
}

static NSString *_lvPath(void) {
    NSString *saved = _lvPathForKey(@"LockVideoPath");
    if (saved) return saved;
    return _lvScanFiles().firstObject;
}

static NSString *_lvOptionPath(void) { return _lvPathForKey(@"LockVideoOptionPath"); }
static NSString *_lvClearPath(void)  { return _lvPathForKey(@"LockVideoClearPath"); }

#pragma mark - 诊断日志

static void _lvLog(NSString *line) {
    @try {
        if (![[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]) { return; }
        NSString *old = [NSString stringWithContentsOfFile:kLVLogFile
                                                  encoding:NSUTF8StringEncoding
                                                     error:nil] ?: @"";
        if (old.length > 8192) { old = @""; }
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

#pragma mark - 播放器（按 path 缓存，支持多素材）

static void _lvAllowAutoLockForPlayer(AVPlayer *p) {
    @try {
        if (!p) { return; }
        SEL sel = NSSelectorFromString(@"setPreventsDisplaySleepDuringVideoPlayback:");
        if ([p respondsToSelector:sel]) {
            [p setValue:@NO forKey:@"preventsDisplaySleepDuringVideoPlayback"];
            _lvLogOnce(@"自动锁屏", @"已允许视频播放时熄屏");
        }
    } @catch (NSException *e) {}
}

static BOOL _lvPathIsImageAsset(NSString *path) {
    if (![path isKindOfClass:[NSString class]] || !path.length) { return NO; }
    NSString *ext = [path pathExtension].lowercaseString;
    return [ext isEqualToString:@"gif"] || [ext isEqualToString:@"png"] ||
           [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] ||
           [ext isEqualToString:@"heic"];
}

static UIImage *_lvAnimatedImage(NSString *path) {
    @try {
        NSURL *url = [NSURL fileURLWithPath:path];
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (!src) { return nil; }
        size_t count = CGImageSourceGetCount(src);
        if (count == 0) { CFRelease(src); return nil; }
        NSMutableArray<UIImage *> *frames = [NSMutableArray array];
        double total = 0.0;
        const double kMinF = 0.02;
        for (size_t i = 0; i < count; i++) {
            CGImageRef cg = CGImageSourceCreateImageAtIndex(src, i, NULL);
            if (!cg) { continue; }
            [frames addObject:[UIImage imageWithCGImage:cg]];
            CFRelease(cg);
            NSDictionary *props = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(src, i, NULL);
            double dur = kMinF;
            NSDictionary *gifp = props[(NSString *)kCGImagePropertyGIFDictionary];
            if (gifp) {
                NSNumber *n = gifp[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
                if (!n) { n = gifp[(NSString *)kCGImagePropertyGIFDelayTime]; }
                if (n) { dur = [n doubleValue]; }
            }
            if (!(dur > kMinF)) { dur = kMinF; }
            total += dur;
        }
        CFRelease(src);
        if (frames.count == 0) { return nil; }
        if (frames.count == 1) { return frames.firstObject; }
        return [UIImage animatedImageWithImages:frames duration:total];
    } @catch (NSException *e) { return nil; }
}

static AVPlayer *_lvPlayerForPath(NSString *path) {
    @try {
        if (_lvPathIsImageAsset(path)) { return nil; }
        if (![path isKindOfClass:[NSString class]] || !path.length) {
            _lvLogOnce(@"扫描结果", [NSString stringWithFormat:@"%@ 里没有找到视频文件", kLVVideoDir]);
            return nil;
        }
        AVPlayer *player = gPlayerMap[path];
        if (!player) {
            AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
            if (!item) { return nil; }
            player = [AVPlayer playerWithPlayerItem:item];
            player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
            player.muted = !_lvSound();
            _lvAllowAutoLockForPlayer(player);
            gPlayerMap[path] = player;

            __weak AVPlayer *wp = player;
            id observer = [[NSNotificationCenter defaultCenter]
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
            gObserverMap[path] = observer;
            _lvLog([NSString stringWithFormat:@"播放器创建: %@ 声音=%d", path, _lvSound()]);
        } else {
            player.muted = !_lvSound();
            _lvAllowAutoLockForPlayer(player);
        }
        return player;
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"player 异常: %@", e]);
        return nil;
    }
}

static void _lvResetPlayerForPath(NSString *path) {
    @try {
        id observer = gObserverMap[path];
        if (observer) {
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            [gObserverMap removeObjectForKey:path];
        }
        AVPlayer *player = gPlayerMap[path];
        if (player) { [player pause]; [gPlayerMap removeObjectForKey:path]; }
    } @catch (NSException *e) {}
}

static void _lvResetAllPlayers(void) {
    @try {
        for (NSString *path in [gPlayerMap allKeys]) {
            _lvResetPlayerForPath(path);
        }
    } @catch (NSException *e) {}
}

static void _lvPauseAllPlayers(void) {
    @try {
        for (AVPlayer *p in gPlayerMap.allValues) { [p pause]; }
    } @catch (NSException *e) {}
}

static void _lvPlayAllVisiblePlayers(void) {
    @try {
        for (NSString *path in gPlayerMap) {
            if (!_lvPathIsImageAsset(path)) { [gPlayerMap[path] play]; }
        }
    } @catch (NSException *e) {}
}

#pragma mark - 视图识别

static BOOL _lvIsActionButtonGroupView(NSString *cls) {
    if (!cls) return NO;
    NSString *low = cls.lowercaseString;
    if ([low containsString:@"buttongroup"]) return YES;       // PLCTButtonGroupView / PLPillButtonGroupView
    if ([low containsString:@"pillcontent"]) return YES;       // PLPillContentView（iOS18 动作菜单容器）
    if ([low containsString:@"actionbutton"]) return YES;        // NCNotificationListCellActionButton 容器
    if ([low containsString:@"actionview"]) return YES;        // 动作视图容器
    if ([low containsString:@"actionmenu"]) return YES;          // 长按动作菜单容器
    if ([low containsString:@"notification"] && [low containsString:@"action"]) return YES;
    return NO;
}

static BOOL _lvIsPillButtonClass(NSString *cls) {
    if (!cls) return NO;
    NSString *low = cls.lowercaseString;
    if ([low containsString:@"pillbutton"] && ![low containsString:@"group"]) return YES;
    if ([low containsString:@"ctbutton"] && ![low containsString:@"group"]) return YES;
    return NO;
}

// 单个动作按钮（非 group 容器）
static BOOL _lvIsSingleActionButtonClass(NSString *cls) {
    if (!cls) { return NO; }
    NSString *low = cls.lowercaseString;
    if ([low containsString:@"group"]) { return NO; }
    if ([low containsString:@"actionbutton"]) { return YES; }
    return _lvIsPillButtonClass(cls);
}

static void _lvRestoreBackgroundsRecursive(UIView *v);
static void _lvScanAndRestoreInView(UIView *v);
static void _lvDetach(UIView *v);

// 动作按钮组（含单个动作按钮）或通知卡片本体（shortlook/banner/longlook）
static BOOL _lvIsNotificationView(UIView *v) {
    @try {
        NSString *cls = NSStringFromClass([v class]);
        if (!cls) { return NO; }
        if (_lvIsActionButtonGroupView(cls)) return YES;
        NSString *low = cls.lowercaseString;
        if (![low containsString:@"notification"]) { return NO; }
        if ([low containsString:@"stackdimming"]) { return NO; }
        if ([low containsString:@"header"])       { return NO; }
        if ([low containsString:@"listview"])     { return NO; }
        if ([low containsString:@"sectionlist"])  { return NO; }
        if ([low containsString:@"listcell"])     { return NO; }
        if ([low containsString:@"content"])      { return NO; }
        return [low containsString:@"shortlook"] || [low containsString:@"banner"] || [low containsString:@"longlook"];
    } @catch (NSException *e) { return NO; }
}

#pragma mark - 挂载

static BOOL _lvIsBackgroundView(UIView *v) {
    NSString *cls = NSStringFromClass([v class]);
    if (!cls) return NO;
    NSString *low = cls.lowercaseString;
    if ([low containsString:@"visualeffect"]) return YES;
    if ([low containsString:@"backdrop"]) return YES;
    if ([low containsString:@"mtmaterial"]) return YES;
    if ([low containsString:@"dimming"]) return YES;
    return NO;
}

static void _lvHideBackgroundsRecursive(UIView *v) {
    if (!v) return;
    @try {
        if (objc_getAssociatedObject(v, &kHideDoneKey)) return;
        objc_setAssociatedObject(v, &kHideDoneKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        for (UIView *sv in v.subviews) {
            NSString *svCls = NSStringFromClass([sv class]);
            // 「选项/清除」按钮区不隐藏系统背景：整块区域保持系统原样，
            // 只有按钮本身（由 _lvAttachActionButtonGroup 挂载）显示素材
            if (_lvIsActionButtonGroupView(svCls) || _lvIsSingleActionButtonClass(svCls)) {
                _lvRestoreBackgroundsRecursive(sv);   // 清掉历史版本残留的隐藏标记
                continue;
            }
            if (_lvIsBackgroundView(sv)) {
                if (!objc_getAssociatedObject(sv, &kOrigHiddenKey)) {
                    objc_setAssociatedObject(sv, &kOrigHiddenKey, @(sv.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                if (!objc_getAssociatedObject(sv, &kOrigAlphaKey)) {
                    objc_setAssociatedObject(sv, &kOrigAlphaKey, @(sv.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                if (!objc_getAssociatedObject(sv, &kOrigBgColorKey)) {
                    objc_setAssociatedObject(sv, &kOrigBgColorKey, sv.backgroundColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                sv.hidden = YES;
            } else {
                _lvHideBackgroundsRecursive(sv);
            }
        }
    } @catch (NSException *e) {}
}

static void _lvScanAndRestoreInView(UIView *v);
static void _lvDetach(UIView *v);

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

static void _lvAttachWithPath(UIView *v, NSString *path);

// 几何启发：识别「包含两个并排等尺寸子视图」的容器 —— 选项/清除按钮组的通用形状特征，
// 不依赖类名，任何 iOS 版本都能命中
static BOOL _lvLooksLikeButtonGroup(UIView *v) {
    if (!v) { return NO; }
    @try {
        NSArray<UIView *> *subs = v.subviews;
        if (subs.count < 2 || subs.count > 8) { return NO; }
        for (NSUInteger i = 0; i < subs.count; i++) {
            for (NSUInteger j = i + 1; j < subs.count; j++) {
                UIView *a = subs[i];
                UIView *b = subs[j];
                if (a.hidden || b.hidden || a.alpha < 0.05 || b.alpha < 0.05) { continue; }
                CGFloat wDiff = fabs(a.bounds.size.width - b.bounds.size.width);
                CGFloat hDiff = fabs(a.bounds.size.height - b.bounds.size.height);
                CGFloat yDiff = fabs(a.frame.origin.y - b.frame.origin.y);
                CGFloat xDiff = fabs(a.frame.origin.x - b.frame.origin.x);
                if (wDiff < 12.0 && hDiff < 12.0 && yDiff < 12.0 && xDiff > 10.0 &&
                    a.bounds.size.width > 40.0 && a.bounds.size.height > 24.0) {
                    return YES;
                }
            }
        }
    } @catch (NSException *e) {}
    return NO;
}

// 计算宿主视图上素材背景层应覆盖的区域：
// 若子树里存在「选项/清除」按钮区，则背景层只覆盖按钮区上方的卡片部分，
// 按钮区露出系统原样（只有按钮本身有素材背景）；找不到按钮区时铺满整个视图。
// 检测优先级：类名匹配 → 几何特征（底部区域里两个并排等尺寸子视图）
static CGRect _lvCoverFrameForHost(UIView *v) {
    CGRect frame = v.bounds;
    if (!v) { return frame; }
    @try {
        CGFloat hostH = v.bounds.size.height;
        NSMutableArray<UIView *> *stack = [NSMutableArray array];
        for (UIView *sv in v.subviews) { [stack addObject:sv]; }
        int visited = 0;
        while (stack.count > 0 && visited < 800) {
            UIView *sv = stack.firstObject;
            [stack removeObjectAtIndex:0];
            visited++;
            NSString *cls = NSStringFromClass([sv class]);
            BOOL byClass = _lvIsActionButtonGroupView(cls) || _lvIsSingleActionButtonClass(cls) || [sv isKindOfClass:[UIButton class]];
            BOOL hit = byClass;
            if (!hit && hostH > 80.0) {
                // 几何兜底：只认位于下半部分、且内部有两个并排等尺寸子视图的容器
                CGFloat yInHost = [v convertRect:sv.bounds fromView:sv].origin.y;
                if (yInHost > hostH * 0.2 && yInHost < hostH - 20.0 && _lvLooksLikeButtonGroup(sv)) {
                    hit = YES;
                }
            }
            if (hit) {
                CGRect f = [v convertRect:sv.bounds fromView:sv];
                CGFloat bottom = f.origin.y - 6.0;
                if (bottom >= 20.0 && bottom < frame.size.height) {
                    frame.size.height = bottom;
                }
                if (byClass) {
                    _lvRestoreBackgroundsRecursive(sv);   // 清掉历史版本残留的隐藏标记
                }
                _lvLogOnce(NSStringFromClass([v class]),
                           [NSString stringWithFormat:@"背景裁剪: 按钮区 %@ y=%.0f h=%.0f 裁到 h=%.0f",
                            cls, f.origin.y, f.size.height, frame.size.height]);
                return frame;
            }
            for (UIView *c in sv.subviews) { [stack addObject:c]; }
        }
    } @catch (NSException *e) {}
    return frame;
}

// 统一刷新：每帧更新背景层尺寸，并确保系统毛玻璃/背景层处于隐藏状态
static void _lvRefresh(UIView *v) {
    @try {
        if (!_lvEnabled()) {
            _lvDetach(v);
            return;
        }
        NSString *path = objc_getAssociatedObject(v, &kPathKey);
        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        UIImageView *iv = objc_getAssociatedObject(v, &kImgKey);
        // 未挂载素材的视图（如通知卡片主体）保持系统原样，不再隐藏背景层
        if (!path.length || (!l && !iv)) {
            _lvDetach(v);
            return;
        }
        if (l && path.length) {
            AVPlayer *p = _lvPlayerForPath(path);
            if (p && l.player != p) { l.player = p; }
            _lvInsertLayer(v, l);
            l.frame = _lvCoverFrameForHost(v);
            l.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
            if (v.window && p && !_lvPathIsImageAsset(path)) { [p play]; }
        }
        if (iv) {
            if (iv.superview != v) { [v insertSubview:iv atIndex:0]; }
            iv.frame = _lvCoverFrameForHost(v);
            iv.layer.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
        }
        _lvHideBackgroundsRecursive(v);
    } @catch (NSException *e) {}
}

static void _lvAttachWithPath(UIView *v, NSString *path) {
    if (!v || !path.length || !_lvEnabled()) { return; }
    @try {
        objc_setAssociatedObject(v, &kPathKey, path, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // ===== 图片 / GIF 分支 =====
        if (_lvPathIsImageAsset(path)) {
            AVPlayerLayer *oldL = objc_getAssociatedObject(v, &kLayerKey);
            if (oldL) { [oldL removeFromSuperlayer]; objc_setAssociatedObject(v, &kLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

            UIImage *img = _lvAnimatedImage(path);
            if (!img) {
                _lvLogOnce(NSStringFromClass(v.class), @"图片/GIF 解码失败，请确认文件完整");
                return;
            }
            UIImageView *iv = objc_getAssociatedObject(v, &kImgKey);
            if (!iv) {
                iv = [[UIImageView alloc] initWithFrame:v.bounds];
                iv.contentMode = UIViewContentModeScaleAspectFill;
                iv.layer.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
                iv.layer.masksToBounds = YES;
                iv.clipsToBounds = YES;
                objc_setAssociatedObject(v, &kImgKey, iv, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [v insertSubview:iv atIndex:0];
                [_lvAttachedViews addObject:v];
                _lvLogOnce(NSStringFromClass(v.class), @"已挂载图片/GIF");
            }
            iv.image = img;
            [v insertSubview:iv atIndex:0];
            iv.frame = _lvCoverFrameForHost(v);
            iv.alpha = (float)_lvAlpha();
            iv.layer.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;

            if (_lvIsActionButtonGroupView(NSStringFromClass(v.class)) || _lvIsPillButtonClass(NSStringFromClass(v.class))) {
                v.layer.masksToBounds = YES;
                v.layer.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
            }

            _lvHideBackgroundsRecursive(v);
            CGRect coverFrame = iv.frame;
            _lvLogOnce(NSStringFromClass(v.class),
                       [NSString stringWithFormat:@"图片挂载尺寸 %.0fx%.0f 透明度 %.2f",
                        coverFrame.size.width, coverFrame.size.height, _lvAlpha()]);
            return;
        }

        // ===== 视频分支 =====
        AVPlayer *p = _lvPlayerForPath(path);
        UIImageView *oldIv = objc_getAssociatedObject(v, &kImgKey);
        if (oldIv) {
            [oldIv removeFromSuperview];
            objc_setAssociatedObject(v, &kImgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!p) {
            _lvLogOnce(NSStringFromClass(v.class), @"没找到视频文件（请检查 /var/mobile/通知视频 目录与素材路径）");
            return;
        }

        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        if (!l) {
            l = [AVPlayerLayer playerLayerWithPlayer:p];
            l.videoGravity = AVLayerVideoGravityResizeAspectFill;
            l.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
            l.masksToBounds = YES;
            objc_setAssociatedObject(v, &kLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            _lvLogOnce(NSStringFromClass(v.class), @"已挂载视频");
        }
        if (l.player != p) { l.player = p; }

        _lvInsertLayer(v, l);
        [_lvAttachedViews addObject:v];
        l.frame = _lvCoverFrameForHost(v);
        l.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
        l.opacity = (float)_lvAlpha();
        [p play];
        _lvHideBackgroundsRecursive(v);
        CGRect coverFrame = l.frame;
        _lvLogOnce(NSStringFromClass(v.class),
                   [NSString stringWithFormat:@"挂载尺寸 %.0fx%.0f 透明度 %.2f",
                    coverFrame.size.width, coverFrame.size.height, _lvAlpha()]);
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"attach 异常: %@", e]);
    }
}

__attribute__((unused)) static void _lvAttach(UIView *v) {
    _lvAttachWithPath(v, _lvPath());
}

static NSArray<UIView *> *_lvFindPillButtonsInView(UIView *v) {
    NSMutableArray<UIView *> *out = [NSMutableArray array];
    if (!v) return out;
    @try {
        for (UIView *sv in v.subviews) {
            NSString *svCls = NSStringFromClass([sv class]);
            if ([sv isKindOfClass:[UIButton class]] || _lvIsPillButtonClass(svCls)) {
                [out addObject:sv];
            } else {
                [out addObjectsFromArray:_lvFindPillButtonsInView(sv)];
            }
        }
    } @catch (NSException *e) {}
    return out;
}

// 读取按钮文字：优先 UIButton titleLabel / currentTitle，再深度遍历内部 UILabel
static NSString *_lvButtonTitle(UIView *btn) {
    if (!btn) { return nil; }
    @try {
        if ([btn isKindOfClass:[UIButton class]]) {
            NSString *t = [(UIButton *)btn currentTitle];
            if (t.length) { return t; }
            t = [(UIButton *)btn titleLabel].text;
            if (t.length) { return t; }
        }
        if ([btn respondsToSelector:@selector(titleLabel)]) {
            @try {
                UILabel *lbl = [(id)btn titleLabel];
                if ([lbl isKindOfClass:[UILabel class]] && lbl.text.length) { return lbl.text; }
            } @catch (NSException *e) {}
        }
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:btn];
        int visited = 0;
        while (queue.count > 0 && visited < 50) {
            UIView *sv = queue.firstObject;
            [queue removeObjectAtIndex:0];
            visited++;
            if ([sv isKindOfClass:[UILabel class]]) {
                NSString *t = [(UILabel *)sv text];
                if (t.length) { return t; }
            }
            [queue addObjectsFromArray:sv.subviews];
        }
    } @catch (NSException *e) {}
    return nil;
}

// 按钮组挂载策略：
//   1) v 本身就是单个动作按钮 → 按标题/位置挂对应素材（选项=OptionPath，清除=ClearPath）
//   2) v 是按钮组容器 → 找到内部每个按钮分别挂载；容器自身绝不挂背景（两按钮之间的缝隙保持系统原样）
static void _lvAttachActionButtonGroup(UIView *v) {
    if (!v) return;
    @try {
        NSString *vCls = NSStringFromClass([v class]);

        // —— 情况 1：单个动作按钮 ——
        if (_lvIsSingleActionButtonClass(vCls) || [v isKindOfClass:[UIButton class]]) {
            NSString *lowTitle = _lvButtonTitle(v).lowercaseString;
            NSString *path = nil;
            if ([lowTitle containsString:@"清除"] || [lowTitle containsString:@"clear"]) {
                path = _lvClearPath();
            } else if ([lowTitle containsString:@"选项"] || [lowTitle containsString:@"option"]) {
                path = _lvOptionPath();
            } else {
                // 无标题：按自己在兄弟按钮中的位置判断（第 1 个=选项，其余=清除）
                NSArray<UIView *> *siblings = _lvFindPillButtonsInView(v.superview);
                NSUInteger idx = [siblings indexOfObject:v];
                path = (idx == 0 || idx == NSNotFound) ? _lvOptionPath() : _lvClearPath();
            }
            if (path.length) { _lvAttachWithPath(v, path); }
            else { _lvDetach(v); }
            return;
        }

        // —— 情况 2：按钮组容器 ——
        NSArray<UIView *> *buttons = _lvFindPillButtonsInView(v);
        if (buttons.count > 0) {
            _lvDetach(v);   // 关键：清掉容器上可能残留的挂载并恢复其背景，缝隙不再显示视频
            for (NSUInteger i = 0; i < buttons.count; i++) {
                UIView *sv = buttons[i];
                NSString *lowTitle = _lvButtonTitle(sv).lowercaseString;
                NSString *path = nil;
                if ([lowTitle containsString:@"清除"] || [lowTitle containsString:@"clear"]) {
                    path = _lvClearPath();
                } else if ([lowTitle containsString:@"选项"] || [lowTitle containsString:@"option"]) {
                    path = _lvOptionPath();
                } else {
                    // 无标题按位置：左（第 1 个）=选项，右（其余）=清除
                    path = (i == 0) ? _lvOptionPath() : _lvClearPath();
                }
                if (path.length) { _lvAttachWithPath(sv, path); }
                else { _lvDetach(sv); }
            }
        } else {
            _lvDetach(v);   // 找不到单个按钮也不给容器挂背景
        }
    } @catch (NSException *e) {}
}

#pragma mark - 卸载

static void _lvRestoreBackgroundsRecursive(UIView *v) {
    if (!v) return;
    @try {
        if (!objc_getAssociatedObject(v, &kHideDoneKey)) return;
        objc_setAssociatedObject(v, &kHideDoneKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        for (UIView *sv in v.subviews) {
            NSNumber *origHidden = objc_getAssociatedObject(sv, &kOrigHiddenKey);
            if (origHidden) {
                sv.hidden = [origHidden boolValue];
                objc_setAssociatedObject(sv, &kOrigHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

                NSNumber *origAlpha = objc_getAssociatedObject(sv, &kOrigAlphaKey);
                if (origAlpha) { sv.alpha = [origAlpha floatValue]; objc_setAssociatedObject(sv, &kOrigAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

                UIColor *origBg = objc_getAssociatedObject(sv, &kOrigBgColorKey);
                if (origBg) { sv.backgroundColor = origBg; objc_setAssociatedObject(sv, &kOrigBgColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            } else {
                _lvRestoreBackgroundsRecursive(sv);
            }
        }
    } @catch (NSException *e) {}
}

static void _lvDetach(UIView *v) {
    if (!v) { return; }
    @try {
        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        if (l) { [l removeFromSuperlayer]; objc_setAssociatedObject(v, &kLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        UIImageView *iv = objc_getAssociatedObject(v, &kImgKey);
        if (iv) { [iv removeFromSuperview]; objc_setAssociatedObject(v, &kImgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        objc_setAssociatedObject(v, &kPathKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        _lvRestoreBackgroundsRecursive(v);
    } @catch (NSException *e) {}
}

static void _lvDetachAll(void) {
    @try {
        for (UIView *v in [_lvAttachedViews copy]) {
            _lvDetach(v);
        }
        [_lvAttachedViews removeAllObjects];
    } @catch (NSException *e) {}
}

static void _lvScanAndRestoreInView(UIView *v) {
    if (!v) return;
    @try {
        if (objc_getAssociatedObject(v, &kHideDoneKey)) {
            _lvRestoreBackgroundsRecursive(v);
        }
        for (UIView *sv in v.subviews) { _lvScanAndRestoreInView(sv); }
    } @catch (NSException *e) {}
}

#pragma mark - 仅限锁屏

static BOOL _lvIsLockScreenWindow(UIWindow *w) {
    if (!w) { return NO; }
    NSString *c = NSStringFromClass([w class]);
    return [c containsString:@"CoverSheet"] || [c containsString:@"LockScreen"];
}

static BOOL _lvHasLockScreenWindow(void) {
    @try {
        id app = [UIApplication sharedApplication];
        NSArray *wins = nil;
        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) {}
        for (UIWindow *w in wins) {
            if (_lvIsLockScreenWindow(w)) { return YES; }
        }
    } @catch (NSException *e) {}
    return NO;
}

static BOOL _lvIsLockScreenVisible(void) {
    @try {
        static Class lsMgr = Nil;
        static SEL sharedSel = NULL;
        static SEL visibleSel = NULL;
        static BOOL probed = NO;
        if (!probed) {
            probed = YES;
            for (NSString *cn in @[@"SBLockScreenManager", @"CSLockScreenManager"]) {
                Class c = objc_getClass(cn.UTF8String);
                if (!c) { continue; }
                if ([c instancesRespondToSelector:@selector(isLockScreenVisible)]) {
                    visibleSel = @selector(isLockScreenVisible);
                }
                SEL s = @selector(sharedInstance);
                if (![c respondsToSelector:s]) { s = @selector(mainInstance); }
                if ([c respondsToSelector:s]) { sharedSel = s; }
                if (visibleSel && sharedSel) { lsMgr = c; break; }
            }
        }
        if (lsMgr && sharedSel && visibleSel) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id inst = [lsMgr performSelector:sharedSel];
            if (inst && [inst respondsToSelector:visibleSel]) {
                return (BOOL)[inst performSelector:visibleSel];
            }
#pragma clang diagnostic pop
        }
    } @catch (NSException *e) {}
    return _lvHasLockScreenWindow();
}

static void _lvOnMatch(UIView *v) {
    _lvLogOnce(NSStringFromClass(v.class), @"命中通知视图");
    if (!_lvEnabled()) {
        _lvDetach(v);
        _lvPauseAllPlayers();
        return;
    }
    if (!_lvIsLockScreenVisible()) {
        _lvPauseAllPlayers();
        return;
    }
    NSString *cls = NSStringFromClass([v class]);
    if (_lvIsActionButtonGroupView(cls)) {
        _lvAttachActionButtonGroup(v);   // 按钮组：只给单个按钮挂素材，容器不挂
    } else {
        _lvAttach(v);                    // 通知卡片主体：挂主素材
    }
}

#pragma mark - iOS 16 锁屏通知显式 hook

%group LVNotif16
%hook NCNotificationShortLookView
- (void)didMoveToWindow {
    %orig;
    @try {
        UIView *sv = (UIView *)self;
        if (sv.window) { _lvOnMatch(sv); }
    } @catch (NSException *e) {}
}
- (void)layoutSubviews {
    %orig;
    @try { _lvRefresh((UIView *)self); } @catch (NSException *e) {}
}
%end
%end

#pragma mark - 全局 hook（UIView 级别兜底）

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
        if (_lvIsNotificationView(self) && self.window) { _lvRefresh(self); }
    } @catch (NSException *e) {}
}

#pragma mark - 壁纸 hook

%group LVWallpaper
%hook SBLockScreenWallpaperView

- (void)didMoveToWindow {
    %orig;
    @try {
        if (((UIView *)self).window) {
            UIView *v = (UIView *)self;
            NSString *path = _lvPath();
            AVPlayer *p = _lvPlayerForPath(path);
            if (p && _lvEnabled()) {
                AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
                if (!l) {
                    l = [AVPlayerLayer playerLayerWithPlayer:p];
                    l.videoGravity = AVLayerVideoGravityResizeAspectFill;
                    objc_setAssociatedObject(v, &kLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                l.frame = v.bounds;
                [v.layer addSublayer:l];
                [_lvAttachedViews addObject:v];
                [p play];
            }
        }
    } @catch (NSException *e) {}
}

%end
%end

#pragma mark - 设置变化回调

static void _lvPollTick(void);

static void _lvPrefsChanged(CFNotificationCenterRef center,
                            void *observer,
                            CFStringRef name,
                            const void *object,
                            CFDictionaryRef userInfo) {
    @try {
        BOOL nowEnabled = _lvEnabled();
        if (nowEnabled != gWasEnabled) {
            gWasEnabled = nowEnabled;
            if (!nowEnabled) {
                _lvDetachAll();
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        id app = [UIApplication sharedApplication];
                        NSArray *wins = nil;
                        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) {}
                        for (UIWindow *w in wins) { _lvScanAndRestoreInView(w); }
                    } @catch (NSException *e) {}
                });
                _lvPauseAllPlayers();
                _lvLog(@"启用=关：已即时卸载全部背景");
            } else {
                _lvLog(@"启用=开：立即重新挂载");
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try { _lvPollTick(); } @catch (NSException *e) {}
                });
            }
            return;
        }

        // 声音变化同步到所有播放器
        for (AVPlayer *p in gPlayerMap.allValues) {
            p.muted = !_lvSound();
            _lvAllowAutoLockForPlayer(p);
        }

        // 收集当前激活的 path
        NSMutableSet<NSString *> *active = [NSMutableSet set];
        NSString *main = _lvPath();
        NSString *opt = _lvOptionPath();
        NSString *clr = _lvClearPath();
        if (main.length) [active addObject:main];
        if (opt.length)  [active addObject:opt];
        if (clr.length)  [active addObject:clr];

        // 清理不再需要的播放器
        NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
        for (NSString *path in gPlayerMap) {
            if (![active containsObject:path]) { [toRemove addObject:path]; }
        }
        for (NSString *path in toRemove) { _lvResetPlayerForPath(path); }

        dispatch_async(dispatch_get_main_queue(), ^{
            @try { _lvPollTick(); } @catch (NSException *e) {}
        });
    } @catch (NSException *e) {}
}

#pragma mark - 轮询扫描

static NSTimer *gPollTimer = nil;

// 轮询扫描命中：动作按钮组 或 通知卡片本体
static BOOL _lvIsCardClass(NSString *cls) {
    if (_lvIsActionButtonGroupView(cls)) return YES;
    NSString *low = cls.lowercaseString;
    if (![low containsString:@"notif"]) { return NO; }
    if ([low containsString:@"stackdimming"]) { return NO; }
    if ([low containsString:@"header"])       { return NO; }
    if ([low containsString:@"listview"])     { return NO; }
    if ([low containsString:@"sectionlist"])  { return NO; }
    if ([low containsString:@"listcell"])     { return NO; }
    return [low containsString:@"shortlook"] ||
           [low containsString:@"banner"]     ||
           [low containsString:@"longlook"];
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
                _lvOnMatch(v);
            }
            for (UIView *c in v.subviews) { [stack addObject:c]; }
        }
    } @catch (NSException *e) {}
}

static void _lvPollTick(void) {
    @try {
        if (!_lvEnabled()) {
            _lvPauseAllPlayers();
            return;
        }
        if (!_lvIsLockScreenVisible()) {
            _lvPauseAllPlayers();
            return;
        }
        id app = [UIApplication sharedApplication];
        NSArray *wins = nil;
        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) {}
        BOOL foundAnyCard = NO;
        for (UIWindow *w in wins) {
            if (w.hidden || w.alpha <= 0.01) { continue; }
            BOOL found = NO;
            _lvScanAndAttach(w, &found);
            if (found) { foundAnyCard = YES; }
        }
        if (foundAnyCard) { _lvPlayAllVisiblePlayers(); }
        else { _lvPauseAllPlayers(); }
    } @catch (NSException *e) {}
}

#pragma mark - ctor

%ctor {
    @try {
        if (objc_getClass("NCNotificationShortLookView") != Nil) {
            %init(LVNotif16);
            _lvLog(@"NCNotificationShortLookView 显式 hook OK");
        } else {
            _lvLog(@"NCNotificationShortLookView 不存在(非 iOS16?)");
        }

        Class uiView = objc_getClass("UIView");
        if (uiView) {
            MSHookMessageEx(uiView, @selector(didMoveToWindow),
                            (IMP)_lv_didMoveToWindow, (IMP *)&_orig_didMoveToWindow);
            MSHookMessageEx(uiView, @selector(layoutSubviews),
                            (IMP)_lv_layoutSubviews, (IMP *)&_orig_layoutSubviews);
            _lvLog(@"UIView 全局 hook OK");
        }

        if (objc_getClass("SBLockScreenWallpaperView") != Nil) {
            %init(LVWallpaper);
            _lvLog(@"壁纸 hook OK");
        } else {
            _lvLog(@"SBLockScreenWallpaperView 不存在");
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            @try {
                if (gPollTimer) { [gPollTimer invalidate]; gPollTimer = nil; }
                gPollTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *t) {
                    @try { _lvPollTick(); } @catch (NSException *e) {}
                }];
                _lvLog(@"轮询扫描已启动(每1.5秒)");
            } @catch (NSException *e) {}
        });

        gPlayerMap = [NSMutableDictionary dictionary];
        gObserverMap = [NSMutableDictionary dictionary];
        if (!_lvAttachedViews) { _lvAttachedViews = [NSMutableArray array]; }

        if (_lvEnabled()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @try {
                    NSString *main = _lvPath();
                    if (main.length && !_lvPathIsImageAsset(main)) { _lvPlayerForPath(main); }
                    NSString *opt = _lvOptionPath();
                    if (opt.length && !_lvPathIsImageAsset(opt)) { _lvPlayerForPath(opt); }
                    NSString *clr = _lvClearPath();
                    if (clr.length && !_lvPathIsImageAsset(clr)) { _lvPlayerForPath(clr); }
                } @catch (NSException *e) {}
            });
        }

        gWasEnabled = _lvEnabled();

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        _lvPrefsChanged,
                                        kLVNotify,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        _lvLog([NSString stringWithFormat:@"状态: 启用=%d 声音=%d 主素材=%@ 选项=%@ 清除=%@ 目录存在=%d",
                _lvEnabled(), _lvSound(), _lvPath() ?: @"(无)", _lvOptionPath() ?: @"(无)", _lvClearPath() ?: @"(无)",
                [[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]]);
        _lvLog([NSString stringWithFormat:@"plist文件内容: %@", _lvPrefs()]);
        _lvLog(@"===== 1.0.60 加载完成（选项/清除按钮独立背景素材 + 多播放器） =====");
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"ctor 异常: %@", e]);
    }
}
