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

static AVPlayer *gPlayer = nil;
static NSString *gCurrentPath = nil;
static id gLoopObserver = nil;
static char kLayerKey;
static char kImgKey;
static char kHideDoneKey;
static char kOrigHiddenKey;
static char kOrigAlphaKey;
static char kOrigBgColorKey;
static NSMutableArray<UIView *> *_lvAttachedViews = nil;   // 强引用：关闭插件时确保视图还在，避免弱引用丢失导致卸载失败
static NSMutableSet<NSString *> *gLoggedClasses = nil;
static BOOL gWasEnabled = NO;                 // 上一次「启用」状态，用于检测开关翻转

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

// 是否启用透明度调节
static BOOL _lvAlphaEnabled(void) {
    // 默认开启透明度调节；关闭时素材完全不透明（alpha=1.0）
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

// 视频透明度：默认 0.5（视频淡一些，文字才看得清）
// 若关闭「启用透明度调节」，则返回 1.0（完全不透明）
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

// 是否启用视频/图片背景圆角
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

// 视频/图片背景圆角半径：默认 18.0，范围 0~40
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

#pragma mark - 共享播放器（多视图可同时显示同一视频）

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

// 判断当前素材是否为图片/GIF（而非视频）
static BOOL _lvIsImageAsset(void) {
    NSString *path = _lvPath();
    if (![path isKindOfClass:[NSString class]] || !path.length) { return NO; }
    NSString *ext = [path pathExtension].lowercaseString;
    return [ext isEqualToString:@"gif"] || [ext isEqualToString:@"png"] ||
           [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"] ||
           [ext isEqualToString:@"heic"];
}

// 用 ImageIO 拆帧生成动画 UIImage（GIF 用）；静态图直接返回单帧。
// 注意：animatedImage 不会随视图生命周期停止，对通知卡片这种短命视图影响很小。
static UIImage *_lvAnimatedImage(NSString *path) {
    @try {
        NSURL *url = [NSURL fileURLWithPath:path];
        CGImageSourceRef src = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (!src) { return nil; }
        size_t count = CGImageSourceGetCount(src);
        if (count == 0) { CFRelease(src); return nil; }
        NSMutableArray<UIImage *> *frames = [NSMutableArray array];
        double total = 0.0;
        const double kMinF = 0.02;   // 每帧最小 20ms，避免 GIF 里 0 延迟导致不播
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

static AVPlayer *_lvPlayer(void) {
    @try {
        // 当前素材若为图片/GIF，则不创建视频播放器（交给图片分支处理；壁纸视频模式也跳过）
        if (_lvIsImageAsset()) {
            _lvLogOnce(@"素材", [NSString stringWithFormat:@"当前为图片/GIF，跳过视频模式: %@", _lvPath()]);
            return nil;
        }
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
            _lvAllowAutoLockForPlayer(gPlayer);
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

// 判断是否为通知卡片的「选项」「清除」动作按钮组容器（PLCTButtonGroupView / PLPillButtonGroupView 等）
static BOOL _lvIsActionButtonGroupView(NSString *cls) {
    if (!cls) return NO;
    NSString *low = cls.lowercaseString;
    if ([low containsString:@"plctbuttongroup"]) return YES;       // PLCTButtonGroupView
    if ([low containsString:@"plpillbuttongroup"]) return YES;     // PLPillButtonGroupView
    if ([low containsString:@"plpillcontent"]) return YES;       // PLPillContentView
    if ([low containsString:@"ncnotificationlistcellactionbutton"]) return YES;
    if ([low containsString:@"csnotificationlistcellactionbutton"]) return YES;
    return NO;
}

static BOOL _lvIsNotificationView(UIView *v) {
    @try {
        NSString *cls = NSStringFromClass([v class]);
        if (!cls) { return NO; }
        // 选项/清除动作按钮组：类名不含 notification，单独识别
        if (_lvIsActionButtonGroupView(cls)) return YES;
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
        return [low containsString:@"shortlook"] || [low containsString:@"banner"] || [low containsString:@"longlook"];
    } @catch (NSException *e) { return NO; }
}

#pragma mark - 挂载

// 判断一个 view 是否为系统通知卡片的毛玻璃/背景层
static BOOL _lvIsBackgroundView(UIView *v) {
    NSString *cls = NSStringFromClass([v class]);
    if (!cls) return NO;
    NSString *low = cls.lowercaseString;
    // UIVisualEffectView：iOS 通用毛玻璃背景
    // MTMaterialView / MTBackdropView 等：iOS 18+ 锁屏通知卡片的私有材质层
    if ([low containsString:@"visualeffect"]) return YES;
    if ([low containsString:@"backdrop"]) return YES;
    if ([low containsString:@"mtmaterial"]) return YES;
    if ([low containsString:@"dimming"]) return YES;
    return NO;
}

// 递归隐藏卡片里所有系统背景/模糊子视图，让素材层真正可见
// 并记录每个视图的原始 hidden / alpha / backgroundColor，关闭插件时 1:1 还原
static void _lvHideBackgroundsRecursive(UIView *v) {
    if (!v) return;
    @try {
        if (objc_getAssociatedObject(v, &kHideDoneKey)) return;   // 本卡片已处理过
        objc_setAssociatedObject(v, &kHideDoneKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        for (UIView *sv in v.subviews) {
            if (_lvIsBackgroundView(sv)) {
                // 只保存一次原始状态，避免重复 hide 把隐藏态/0alpha 覆盖掉
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
                // 继续递归，但只处理一层背景层即可；避免误伤内容子视图
                _lvHideBackgroundsRecursive(sv);
            }
        }
    } @catch (NSException *e) {}
}

// 恢复卡片原始背景：还原被隐藏的系统背景/模糊子视图
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

// _lvRefresh 关闭时会调用 _lvDetach，先声明
static void _lvDetach(UIView *v);

// 统一刷新：每帧更新背景层尺寸，并确保系统毛玻璃/背景层处于隐藏状态
static void _lvRefresh(UIView *v) {
    @try {
        // 如果开关被关闭，任何已挂载的视图都要立即卸载并恢复原始外观，
        // 防止 layoutSubviews 每帧再次隐藏背景导致卡片保持透明。
        if (!_lvEnabled()) {
            _lvDetach(v);
            return;
        }
        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        if (l) {
            _lvInsertLayer(v, l);
            l.frame = v.bounds;
            l.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
            if (v.window && gPlayer && !_lvIsImageAsset()) { [gPlayer play]; }
        }
        UIImageView *iv = objc_getAssociatedObject(v, &kImgKey);
        if (iv) {
            if (iv.superview != v) { [v insertSubview:iv atIndex:0]; }
            iv.frame = v.bounds;
            iv.layer.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
        }
        // v1.0.55 起：为了让素材可见，隐藏系统自带的毛玻璃/背景层（幂等，已处理则跳过）
        _lvHideBackgroundsRecursive(v);
    } @catch (NSException *e) {}
}

static void _lvAttach(UIView *v) {
    if (!v || !_lvEnabled()) { return; }
    @try {
        // ===== 图片 / GIF 分支 =====
        if (_lvIsImageAsset()) {
            // 若之前挂过视频层，先清理，避免两种背景叠加
            AVPlayerLayer *oldL = objc_getAssociatedObject(v, &kLayerKey);
            if (oldL) { [oldL removeFromSuperlayer]; objc_setAssociatedObject(v, &kLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            if (gPlayer) { [gPlayer pause]; }

            UIImage *img = _lvAnimatedImage(_lvPath());
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
            [v insertSubview:iv atIndex:0];   // 确保在最底层
            iv.frame = v.bounds;
            iv.alpha = (float)_lvAlpha();
            iv.layer.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
            // 隐藏系统毛玻璃/背景层，让图片素材可见；关闭时还原
            _lvHideBackgroundsRecursive(v);
            _lvLogOnce(NSStringFromClass(v.class),
                       [NSString stringWithFormat:@"图片挂载尺寸 %.0fx%.0f 透明度 %.2f",
                        v.bounds.size.width, v.bounds.size.height, _lvAlpha()]);
            return;
        }

        // ===== 视频分支（原有逻辑） =====
        AVPlayer *p = _lvPlayer();

        // 若之前挂过图片/GIF 层，先清理，避免图片盖在视频上面（图片↔视频切换即时生效）
        UIImageView *oldIv = objc_getAssociatedObject(v, &kImgKey);
        if (oldIv) {
            [oldIv removeFromSuperview];
            objc_setAssociatedObject(v, &kImgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        if (!p) {
            // 找不到视频文件：直接记一行日志退出，不再做绿色诊断层
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
        if (l.player != p) { l.player = p; }   // 素材切换后更新引用

        // v1.0.55：视频层插入最底层，并隐藏系统自带的毛玻璃/背景层，让视频真正可见；
        // 关闭插件时恢复这些背景层，卡片原貌还原。
        _lvInsertLayer(v, l);
        [_lvAttachedViews addObject:v];
        l.frame = v.bounds;
        l.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
        l.opacity = (float)_lvAlpha();   // 视频淡一点，文字才看得清
        [p play];
        _lvHideBackgroundsRecursive(v);
        _lvLogOnce(NSStringFromClass(v.class),
                   [NSString stringWithFormat:@"挂载尺寸 %.0fx%.0f 透明度 %.2f",
                    v.bounds.size.width, v.bounds.size.height, _lvAlpha()]);
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"attach 异常: %@", e]);
    }
}

#pragma mark - 卸载（关闭「启用」时即时移除背景，无需注销）

// 前向声明：恢复函数（detached 时调用）
static void _lvRestoreBackgroundsRecursive(UIView *v);
static void _lvScanAndRestoreInView(UIView *v);

// 把视频层 + 图片层从某个视图上卸掉，并恢复其原生外观
static void _lvDetach(UIView *v) {
    if (!v) { return; }
    @try {
        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        if (l) { [l removeFromSuperlayer]; objc_setAssociatedObject(v, &kLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        UIImageView *iv = objc_getAssociatedObject(v, &kImgKey);
        if (iv) { [iv removeFromSuperview]; objc_setAssociatedObject(v, &kImgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        // v1.0.56：恢复被隐藏的系统毛玻璃/背景层（hidden/alpha/backgroundColor 一并还原），
        // 让卡片回到插件开启前状态，而不是保持透明。
        _lvRestoreBackgroundsRecursive(v);
    } @catch (NSException *e) {}
}

// 卸载所有已挂载视图（关闭「启用」时调用）。
static void _lvDetachAll(void) {
    @try {
        for (UIView *v in [_lvAttachedViews copy]) {
            _lvDetach(v);
        }
        [_lvAttachedViews removeAllObjects];
    } @catch (NSException *e) {}
}

// 在一棵视图树里递归找任何带 kHideDoneKey 标记的视图并恢复其原始外观
static void _lvScanAndRestoreInView(UIView *v) {
    if (!v) return;
    @try {
        if (objc_getAssociatedObject(v, &kHideDoneKey)) {
            _lvRestoreBackgroundsRecursive(v);
        }
        for (UIView *sv in v.subviews) { _lvScanAndRestoreInView(sv); }
    } @catch (NSException *e) {}
}

#pragma mark - 仅限锁屏（灵动岛/前台横幅不挂载、不出声）

// 判断某个 window 是否为锁屏（CoverSheet）窗口
static BOOL _lvIsLockScreenWindow(UIWindow *w) {
    if (!w) { return NO; }
    NSString *c = NSStringFromClass([w class]);
    return [c containsString:@"CoverSheet"] || [c containsString:@"LockScreen"];
}

// 当前是否存在锁屏窗口（窗口类名兜底判断）
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

// 真实锁屏可见性：优先用系统锁屏管理器（比窗口类名更可靠，能正确排除解锁后的桌面横幅/灵动岛）
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
    return _lvHasLockScreenWindow();   // 兜底：看是否存在锁屏窗口
}

static void _lvOnMatch(UIView *v) {
    _lvLogOnce(NSStringFromClass(v.class), @"命中通知视图");   // 不再依赖诊断模式，必记
    if (!_lvEnabled()) {
        _lvDetach(v);                 // 关闭时立即恢复卡片原貌
        if (gPlayer) { [gPlayer pause]; }
        return;
    }
    // 仅当设备处于锁屏（通知应显示视频+声音）才挂载；
    // 解锁后的桌面横幅/灵动岛一律不挂载、不出声
    if (!_lvIsLockScreenVisible()) {
        if (gPlayer) { [gPlayer pause]; }
        return;
    }
    _lvAttach(v);
}

#pragma mark - iOS 16 锁屏通知显式 hook（直接挂用户可见的卡片本体 NCNotificationShortLookView）

%group LVNotif16
%hook NCNotificationShortLookView
- (void)didMoveToWindow {
    %orig;
    @try {
        UIView *sv = (UIView *)self;
        if (sv.window) { _lvOnMatch(sv); }   // 内部已做锁屏判断：锁屏才挂，否则停声
    } @catch (NSException *e) {}
}
- (void)layoutSubviews {
    %orig;
    @try { _lvRefresh((UIView *)self); } @catch (NSException *e) {}
}
%end
%end

#pragma mark - 全局 hook（UIView 级别兜底，自动匹配所有通知视图）

static void (*_orig_didMoveToWindow)(UIView *, SEL);
static void _lv_didMoveToWindow(UIView *self, SEL _cmd) {
    _orig_didMoveToWindow(self, _cmd);
    @try {
        if (self.window && _lvIsNotificationView(self)) { _lvOnMatch(self); }   // 内部已做锁屏判断
    } @catch (NSException *e) {}
}

static void (*_orig_layoutSubviews)(UIView *, SEL);
static void _lv_layoutSubviews(UIView *self, SEL _cmd) {
    _orig_layoutSubviews(self, _cmd);
    @try {
        if (_lvIsNotificationView(self) && self.window) { _lvRefresh(self); }
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
                // 复用同一 AVPlayerLayer（通过 kLayerKey 关联），关闭插件时 _lvDetachAll 会一并卸掉
                AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
                if (!l) {
                    l = [AVPlayerLayer playerLayerWithPlayer:p];
                    l.videoGravity = AVLayerVideoGravityResizeAspectFill;
                    objc_setAssociatedObject(v, &kLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                l.frame = v.bounds;
                [v.layer addSublayer:l];
                [_lvAttachedViews addObject:v];   // 加入集合，关闭「启用」时一并卸载恢复原图
                [p play];
            }
        }
    } @catch (NSException *e) {}
}

%end
%end

#pragma mark - 设置变化回调（C 函数，ARC 下 block 不能转 CFNotificationCallback）

static void _lvPollTick(void);   // 前向声明：供偏好变更回调立即重扫描使用

static void _lvPrefsChanged(CFNotificationCenterRef center,
                            void *observer,
                            CFStringRef name,
                            const void *object,
                            CFDictionaryRef userInfo) {
    @try {
        // 检测「启用」开关翻转：关闭时立即卸载全部背景（无需注销），打开时立即重新挂载
        BOOL nowEnabled = _lvEnabled();
        if (nowEnabled != gWasEnabled) {
            gWasEnabled = nowEnabled;
            if (!nowEnabled) {
                _lvDetachAll();                 // 立即移除所有已挂的视频/图片层并恢复卡片原貌
                // 再扫描所有 UIWindow，确保漏网之鱼也被恢复
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        id app = [UIApplication sharedApplication];
                        NSArray *wins = nil;
                        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) {}
                        for (UIWindow *w in wins) { _lvScanAndRestoreInView(w); }
                    } @catch (NSException *e) {}
                });
                if (gPlayer) { [gPlayer pause]; }
                _lvLog(@"启用=关：已即时卸载全部背景");
            } else {
                _lvLog(@"启用=开：立即重新挂载");
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try { _lvPollTick(); } @catch (NSException *e) {}
                });
            }
            return;
        }

        NSString *np = _lvPath();
        if (![np isEqualToString:gCurrentPath]) {
            _lvResetPlayer();          // 素材变了 -> 重建播放器
        } else if (gPlayer) {
            gPlayer.muted = !_lvSound();   // 只改了声音 -> 即时生效
            _lvAllowAutoLockForPlayer(gPlayer);
        }
        // 设置变化后立刻重新扫描并挂载，避免等轮询(1.5s)才生效
        dispatch_async(dispatch_get_main_queue(), ^{
            @try { _lvPollTick(); } @catch (NSException *e) {}
        });
    } @catch (NSException *e) {}
}

#pragma mark - 轮询扫描（不依赖任何 hook 传播：直接遍历锁屏视图树找通知卡片）

static NSTimer *gPollTimer = nil;

// 只挂用户实际看到的通知视图本体（短按卡片 / 横幅 / 长按展开视图），
// 排除列表容器、遮罩、标题、外层 cell——它们的 bounds 远大于卡片，挂上会铺满或藏在卡片背后
static BOOL _lvIsCardClass(NSString *cls) {
    // 选项/清除动作按钮组：类名不含 notif，优先识别
    if (_lvIsActionButtonGroupView(cls)) return YES;
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
        if (!_lvEnabled()) {
            if (gPlayer) { [gPlayer pause]; }
            return;
        }
        // 仅在锁屏时挂载/播放；解锁状态（桌面横幅/灵动岛）直接停声返回
        if (!_lvIsLockScreenVisible()) {
            if (gPlayer) { [gPlayer pause]; }
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
        // 没有通知卡片可见 → 暂停视频播放，避免空闲时也在循环
        // 有卡片 → 确保继续播放（attach 也会 play，这里再保一次）
        if (gPlayer) {
            if (foundAnyCard && !_lvIsImageAsset()) { [gPlayer play]; }
            else { [gPlayer pause]; }
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

        // 预创建播放器：锁屏出现前先把 AVPlayer 建好，避免下滑锁屏消息时因首次创建播放器而卡顿
        if (_lvEnabled() && !_lvIsImageAsset()) {
            dispatch_async(dispatch_get_main_queue(), ^{
                @try { _lvPlayer(); } @catch (NSException *e) {}
            });
        }

        // 记录初始「启用」状态 + 初始化已挂载视图集合（强引用，避免关闭插件时视图已释放）
        gWasEnabled = _lvEnabled();
        if (!_lvAttachedViews) { _lvAttachedViews = [NSMutableArray array]; }

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        _lvPrefsChanged,
                                        kLVNotify,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        _lvLog([NSString stringWithFormat:@"状态: 启用=%d 声音=%d 视频=%@ 目录存在=%d",
                _lvEnabled(), _lvSound(), _lvPath() ?: @"(无)",
                [[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]]);
        _lvLog([NSString stringWithFormat:@"plist文件内容: %@", _lvPrefs()]);
        {
            NSMutableString *s = [NSMutableString string];
            for (NSString *suite in _lvSuites()) {
                for (NSString *k in @[@"LockVideoEnabled", @"LockVideoSound"]) {
                    CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
                    CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)k, (__bridge CFStringRef)suite);
                    id val = cf ? CFBridgingRelease(cf) : nil;
                    [s appendFormat:@"%@/%@=%@ ", suite, k, val ?: @"(无)"];
                }
            }
            _lvLog([NSString stringWithFormat:@"系统偏好: %@", s]);
        }
        _lvLog(@"===== 1.0.49 加载完成（仅锁屏出视频/声音 + 防卡顿） =====");
    } @catch (NSException *e) {
        _lvLog([NSString stringWithFormat:@"ctor 异常: %@", e]);
    }
}
