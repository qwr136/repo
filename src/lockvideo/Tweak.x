#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <ImageIO/ImageIO.h>

#define kLVPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.notifybgvideo.plist"
#define kLVNotify    CFSTR("com.xiaofei.notifybgvideo/ReloadPrefs")
#define kLVVideoDir  @"/var/mobile/通知视频"
#define kLVLogFile   @"/var/mobile/通知视频/插件日志.txt"   // 全方位问题诊断日志（需手动开启）
#define kLVFlushLog  CFSTR("com.xiaofei.notifybgvideo/FlushLog")
#define kLVVersion   @"1.0.86"

// 问题日志的分类名（声音 / 卡顿 / 失效 是重点，其余按要求全量收集）
#define kLVCatSound    @"声音"
#define kLVCatPerf     @"卡顿"
#define kLVCatFail     @"失效"
#define kLVCatMount    @"挂载"
#define kLVCatPlayer   @"播放"
#define kLVCatAsset    @"素材"
#define kLVCatActivity @"活动"
#define kLVCatPrefs    @"偏好"
#define kLVCatExcept   @"异常"

#define kLVDumpFile  @"/var/mobile/通知视频/视图结构.txt"

// 实时活动 / Now Playing 的类型判定结果
// Unknown    = 内容还没加载完，暂时不敢下结论（此时不挂载，避免先显示出错的素材）
// General    = 普通实时活动（外卖/进度/运动…）
// NowPlaying = 锁屏媒体播放器（走独立「播放器素材」）
typedef NS_ENUM(NSInteger, LVActivityKind) {
    LVActivityKindUnknown    = 0,
    LVActivityKindGeneral    = 1,
    LVActivityKindNowPlaying = 2,
};

// path -> AVPlayer：支持主素材/选项素材/清除素材分别播放
static NSMutableSet<AVPlayer *> *gAllPlayers = nil;     // 当前所有存活的 AVPlayer（含共享），用于统一暂停/声音同步/可见性播放
static NSMapTable *gObserverMap = nil;   // player -> loop observer（AVPlayer 不遵循 NSCopying，不能用 NSDictionary 当 key）
static NSMapTable *gAuxObserverMap = nil; // player -> @[observer]：问题诊断用的听播通知（失败/卡顿/错误日志）
static NSMutableDictionary<NSString *, AVPlayer *> *gPlayerByPath = nil;  // 路径 -> 共享播放器：同一段视频只解码一次，多视图 AVPlayerLayer 共用
static NSMutableDictionary<NSValue *, NSNumber *> *gRefCount = nil;       // 播放器指针(NSValue) -> 引用计数：视图挂载+1、卸载-1，归零才真正销毁
static char kLayerKey;
static char kImgKey;
static char kPathKey;          // 记录 view 当前挂载的素材路径
static char kPlayerKey;        // 记录 view 当前使用的 AVPlayer（可能与其他同路径视图共享，按引用计数管理生命周期）
static char kActivityHostKey;  // 标记实时活动卡片的 PLPlatterView 宿主
static char kRecheckKey;       // 活动内容视图上：已安排的「类型复核」次数（NSNumber），到上限后停止
static char kKindKey;          // 活动内容视图上：最终确定的类型（NSNumber / LVActivityKind），内容视图销毁即自动释放
static char kKindProbeKey;     // 活动内容视图上：已定为普通活动后，是否做过一次「是不是漏判的播放器」复查
static char kKindDumpKey;      // 活动内容视图上：本次出现是否已经往日志里打过一次真实子视图结构
static char kExpectedKey;      // 「应挂素材」短时缓存
static char kExpectedStampKey;
static char kCoverKey;         // 「背景裁剪结果」短时缓存（NSValue / CGRect）
static char kCoverStampKey;
static char kCoverSignKey;     // 缓存签名：视图尺寸 + 直接子视图个数
static char kBgStampKey;       // 背景层隐藏处理的节流时间戳
static char kDebugKey;         // 可视化调试覆盖层
static char kKeepBgKey;        // 标记为「保留显示」的卡片系统背景层
static char kHideDoneKey;
static char kOrigHiddenKey;
static char kOrigAlphaKey;
static char kOrigBgColorKey;
static char kOrigCornerKey;    // 备份：宿主 layer.cornerRadius（关闭插件时还原）
static char kOrigMasksKey;     // 备份：宿主 layer.masksToBounds（关闭插件时还原）
// 弱引用：只用于遍历，绝不 retain —— 旧版用 NSMutableArray 强引用 + 每次挂载都 addObject，
// 数组会无限堆积并永久持有已销毁的视图，导致解锁后内存不降、遍历越来越慢（下拉卡顿）
static NSHashTable<UIView *> *_lvAttachedViews = nil;
static NSHashTable<UIView *> *_lvAttachedTable(void) {
    if (!_lvAttachedViews) { _lvAttachedViews = [NSHashTable weakObjectsHashTable]; }
    return _lvAttachedViews;
}
static BOOL gWasEnabled = NO;                 // 上一次「启用」状态，用于检测开关翻转
static NSSet<NSString *> *gLastActivePaths = nil;    // 上一次激活的素材路径集合，变化时重置全部播放器

// —— 偏好读取缓存：解析 plist 是磁盘 IO，而透明度/圆角这类函数会在 layoutSubviews 里被逐帧调用。
// 旧版每次都重新读文件并解析全文，下拉动画期间等于每帧几十次磁盘 IO —— 这是掉帧的隐性来源。
// 缓存 0.5 秒 + 按文件修改时间判断是否需要真重读，既保证开关即时生效，又免掉绝大多数 IO。
static NSDictionary *gPrefsCache = nil;
static NSTimeInterval gPrefsLastCheck = 0;
static NSTimeInterval gPrefsMTime = -1;

#pragma mark - 偏好（直接读文件）

static void _lvLog(NSString *line);
static void _lvLogOnce(NSString *cls, NSString *action);
static void _lvNote(NSString *cat, NSString *fmt, ...);       // 常规流程（仅在「详细日志」开启时写入）
static void _lvIssue(NSString *cat, NSString *fmt, ...);      // 疑似问题 / 已自动兜底
static void _lvFail(NSString *cat, NSString *fmt, ...);       // 明确失败
static void _lvExcept(const char *fn, NSException *e);        // 未捕获异常的抓取
static BOOL _lvLogging(void);
static NSArray<UIView *> *_lvFindPillButtonsInView(UIView *v);
static NSString *_lvButtonTitle(UIView *btn);
static BOOL _lvViewEffectivelyVisible(UIView *v);
static BOOL _lvIsActivityHost(UIView *v);
// 定义在后面的辅助函数：这里必须前向声明，否则 C99 报 implicit declaration，
// 整个 dylib 直接编译不过（1.0.82 就是因为漏了这两个声明而没有出包）
static BOOL _lvIsActivityContentClass(NSString *cls);
static BOOL _lvIsNowPlayingActivityView(UIView *v);
static NSInteger _lvNowPlayingState(void);          // -1 拿不到 / 0 没在播 / 1 正在播
static BOOL _lvIsLockScreenVisible(void);           // 锁屏是否还在前台（只在 sound 裁定里也会用到，必须先声明）
static LVActivityKind _lvDetectKindIn(UIView *root, BOOL *loaded);
static LVActivityKind _lvResolvedKindForView(UIView *v);
static void _lvOnMatch(UIView *v);

static NSArray<NSString *> *_lvSuites(void) {
    return @[@"com.xiaofei.notifybgvideo", @"com.xiaofei.notifybgvideo.prefs"];
}

static NSDictionary *_lvPrefs(void) {
    @try {
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (gPrefsCache && (now - gPrefsLastCheck) < 0.5) { return gPrefsCache; }
        gPrefsLastCheck = now;
        NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath:kLVPrefsFile error:nil];
        NSDate *mDate = attr ? [attr objectForKey:NSFileModificationDate] : nil;
        NSTimeInterval mt = mDate ? [mDate timeIntervalSince1970] : 0;
        if (gPrefsCache && mt == gPrefsMTime) { return gPrefsCache; }   // 文件没动过，直接复用上次解析结果
        NSDictionary *fresh = [NSDictionary dictionaryWithContentsOfFile:kLVPrefsFile] ?: @{};
        gPrefsCache = fresh;
        gPrefsMTime = mt;
        return fresh;
    } @catch (NSException *e) { _lvExcept(__func__, e); }
    return gPrefsCache ?: @{};
}

// 设置变更：立刻丢弃缓存，保证下一次读取拿到新值
static void _lvPrefsInvalidate(void) {
    gPrefsCache = nil;
    gPrefsMTime = -1;
    gPrefsLastCheck = 0;
}

// 注意：key 在 plist 里存在时直接返回，绝不再去查 CF 偏好。
// 旧写法只在读到「YES」时才提前返回，开关为关闭时会每帧遍历两个 suite 做
// CFPreferencesAppSynchronize（强制刷盘），layoutSubviews 里等于每帧几十次磁盘同步。
static BOOL _lvBool(NSString *key) {
    @try {
        id v = _lvPrefs()[key];
        if (v) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO; }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)] && [val boolValue]) { return YES; }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return NO;
}

static BOOL _lvAlphaEnabled(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoAlphaEnabled"];
        if (v) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : YES; }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoAlphaEnabled"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)]) { return [val boolValue]; }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return YES;
}

static CGFloat _lvAlpha(void) {
    if (!_lvAlphaEnabled()) { return 1.0; }
    @try {
        id v = _lvPrefs()[@"LockVideoAlpha"];
        if (v) {
            if ([v respondsToSelector:@selector(floatValue)]) {
                CGFloat a = [v floatValue];
                if (a > 0.05) { return MIN(a, 1.0); }
            }
            return 0.5;
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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return 0.5;
}

static BOOL _lvCornerEnabled(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoCornerEnabled"];
        if (v) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : YES; }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoCornerEnabled"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)]) { return [val boolValue]; }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return YES;
}

static CGFloat _lvCornerRadius(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoCornerRadius"];
        if (v) {
            if ([v respondsToSelector:@selector(floatValue)]) {
                CGFloat r = [v floatValue];
                if (r >= 0) { return MIN(r, 40.0); }
            }
            return 18.0;
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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return 18.0;
}

static NSString *_lvString(NSString *key) {
    @try {
        id v = _lvPrefs()[key];
        if (v) { return ([v isKindOfClass:[NSString class]] && [v length]) ? v : nil; }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val isKindOfClass:[NSString class]] && [val length]) { return val; }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return nil;
}

static BOOL _lvEnabled(void) { return _lvBool(@"LockVideoEnabled"); }

// 可视化调试开关：开启后给通知视图每一层描边并标注类名，用于定位「多出来的那层背景」
static BOOL _lvDebugOutline(void) { return _lvBool(@"LockVideoDebugOutline"); }

static BOOL _lvSound(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoSound"];
        if (v) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : YES; }
        for (NSString *suite in _lvSuites()) {
            CFPreferencesAppSynchronize((__bridge CFStringRef)suite);
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoSound"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)]) { return [val boolValue]; }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return @[];
}

static NSString *_lvPathForKey(NSString *key) {
    @try {
        id v = _lvPrefs()[key];
        if (v) {
            if ([v isKindOfClass:[NSString class]] && [v length]) {
                if ([[NSFileManager defaultManager] fileExistsAtPath:v]) { return v; }
                // 典型的「失效」：设置里明明选过，但文件已经被删掉/改了名
                _lvIssue(kLVCatAsset, @"选的素材文件不存在，%@ 暂时不生效：%@", key, v);
            }
            return nil;
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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return nil;
}

static NSString *_lvPath(void) {
    @try {
        NSString *saved = _lvPathForKey(@"LockVideoPath");
        if (saved) {
            _lvLogOnce(@"当前素材", [NSString stringWithFormat:@"已设置: %@", saved.lastPathComponent]);
            return saved;
        }
        // 没设置、或设置过的文件已不存在：退回扫描目录，取第一个可用素材。
        // （旧版本把「取消选择」写成空字符串后就永久不生效，这里不再把空值当取消）
        NSArray<NSString *> *files = _lvScanFiles();
        if (files.count) {
            _lvLogOnce(@"当前素材", [NSString stringWithFormat:@"未设置，自动用目录第一个: %@",
                                    [files.firstObject lastPathComponent]]);
            return files.firstObject;
        }
        _lvLogOnce(@"当前素材", @"未设置且素材目录为空 —— 卡片不会有背景，请在设置里「选择消息素材」");
        _lvFail(kLVCatAsset, @"没有可用素材：既没设置主素材，%@ 目录里也找不到视频/图片", kLVVideoDir);
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return nil;
}

static NSString *_lvOptionPath(void) { return _lvPathForKey(@"LockVideoOptionPath"); }
static NSString *_lvClearPath(void)  { return _lvPathForKey(@"LockVideoClearPath"); }
static NSString *_lvActivityPath(void){ return _lvPathForKey(@"LockVideoActivityPath"); }   // 实时活动独立素材
static NSString *_lvPlayerPath(void){ return _lvPathForKey(@"LockVideoPlayerPath"); }      // 播放器 / Now Playing 独立素材

#pragma mark - 全方位问题收集日志（默认关闭，设置里打开才记录）

// ─── 为什么要有这套日志 ─────────────────────────────────────────────
// 反馈过来的问题基本就落在三类：
//   声音 —— 不该响的响了 / 该响的没响 / 几个视图抢同一个播放器导致声音状态打架
//   卡顿 —— 下拉掉帧，多半是某一帧里我们做了递归扫描或磁盘读写
//   失效 —— 素材没挂上、播放器起不来、看着还是系统原样
// 这套日志就是给这三类（以及其它一切异常）留证据。
//
// ─── 使用规则（很重要）─────────────────────────────────────────────
//   1) 默认一个字都不写。只有在设置里打开「收集插件问题日志」才开始记录；
//      不打开时除了两次布尔判断，插件行为和以前完全一样，没有额外开销。
//   2) 全部磁盘写入在独立串行队列里做，主线程只负责把一行字丢进队列，绝不拖慢动画。
//   3) 三级严重度：
//        记录 —— 正常流程的关键节点（只有同时打开「详细日志」才写）
//        疑似 —— 发现不对劲，但插件已经自动兜底了（素材回退、推迟挂载、被迫重挂…）
//        失败 —— 明确没做成（文件没了、解码失败、播放器创建失败、该挂没挂上…）
//   4) 相同内容 3 秒内只写一次，其余折算成「重复 N 次」，
//      否则一次下拉通知就能刷出几千行，反而看不出问题在哪。
//   5) 日志超过 2MB 自动把旧的归档成 插件日志.txt.old，不让日志撑爆磁盘。
// ─────────────────────────────────────────────────────────────────

#define LVLOG_THROTTLE_SEC 3.0
#define LVLOG_BUFFER_MAX   60
#define LVLOG_ROTATE_BYTES (2ULL * 1024 * 1024)

#include <time.h>
#include <sys/time.h>

static NSString *_lvLogTimeString(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    time_t sec = (time_t)tv.tv_sec;
    struct tm tmBuf;
    localtime_r(&sec, &tmBuf);
    char buf[40];
    strftime(buf, sizeof(buf), "%m-%d %H:%M:%S", &tmBuf);
    int ms = (int)(tv.tv_usec / 1000);
    return [NSString stringWithFormat:@"%s.%03d", buf, ms];
}

// 单调时钟：比 NSDate 便宜得多（不产生对象），可以在每帧都跑的代码里放心用
static inline double _lvNowMs(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1000000.0;
}

static NSString *_lvDesc(UIView *v) {
    if (!v) { return @"(nil view)"; }
    return [NSString stringWithFormat:@"%@ %.0fx%.0f",
            NSStringFromClass([v class]), v.bounds.size.width, v.bounds.size.height];
}

static dispatch_queue_t _lvLogQueue(void) {
    static dispatch_queue_t q = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.xiaofei.notifybgvideo.log", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSMutableArray<NSString *> *gLogBuffer = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gLogLastAt = nil;
static NSMutableDictionary<NSString *, NSNumber *> *gLogRepeat = nil;
static BOOL gLogFlushScheduled = NO;
static BOOL gLogHeaderDone = NO;
static BOOL gLogReentrant = NO;   // 防止「读偏好出错 → 写日志 → 又读偏好」的无限递归

static void _lvLogFlushLocked(void);   // 只允许在日志队列里调用

static NSString *_lvLogHeaderText(void) {
    NSString *dev = @"?";
    NSString *sys = @"?";
    @try {
        UIDevice *d = [UIDevice currentDevice];
        if (d) {
            NSString *m = [d model];
            NSString *v = [d systemVersion];
            if (m.length) { dev = m; }
            if (v.length) { sys = v; }
        }
    } @catch (NSException *e) { }
    return [NSString stringWithFormat:
            @"\n──────── 开始记录：%@ ────────\n"
            @"插件版本 %@   设备 %@   系统 %@\n"
            @"日志文件 %@\n"
            @"格式：[时间] [分类/级别] 内容\n"
            @"级别：记录=正常流程 / 疑似=发现异常但已兜底 / 失败=确实没做成\n"
            @"重点分类：声音 / 卡顿 / 失效 / 播放 / 素材 / 活动 / 异常\n"
            @"──────────────────────────────\n",
            _lvLogTimeString(), kLVVersion, dev, sys, kLVLogFile];
}

static void _lvLogScheduleFlushLocked(void) {
    if (gLogFlushScheduled) { return; }
    gLogFlushScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), _lvLogQueue(), ^{
        @try {
            gLogFlushScheduled = NO;
            _lvLogFlushLocked();
        } @catch (NSException *e) { }
    });
}

static void _lvLogFlushLocked(void) {
    if (!gLogBuffer || gLogBuffer.count == 0) { return; }
    NSArray<NSString *> *batch = [gLogBuffer copy];
    [gLogBuffer removeAllObjects];
    NSFileHandle *h = nil;
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDir = NO;
        if (![fm fileExistsAtPath:kLVVideoDir isDirectory:&isDir]) {
            [fm createDirectoryAtPath:kLVVideoDir withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *path = kLVLogFile;
        if (![fm fileExistsAtPath:path]) {
            [_lvLogHeaderText() writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            gLogHeaderDone = YES;
        }
        NSMutableData *d = [NSMutableData dataWithCapacity:4096];
        if (!gLogHeaderDone) {
            gLogHeaderDone = YES;
            [d appendData:[_lvLogHeaderText() dataUsingEncoding:NSUTF8StringEncoding]];
        }
        for (NSString *line in batch) { [d appendData:[line dataUsingEncoding:NSUTF8StringEncoding]]; }
        if (d.length == 0) { return; }
        h = [NSFileHandle fileHandleForWritingAtPath:path];
        if (!h) { return; }
        [h seekToEndOfFile];
        [h writeData:d];
        [h closeFile];
        h = nil;

        unsigned long long sz = [[fm attributesOfItemAtPath:path error:nil] fileSize];
        if (sz > LVLOG_ROTATE_BYTES) {
            NSString *bak = [path stringByAppendingString:@".old"];
            [fm removeItemAtPath:bak error:nil];
            [fm moveItemAtPath:path toPath:bak error:nil];
            NSString *notice = [NSString stringWithFormat:
                @"[%@] [%@] 日志已超过 2MB，旧内容存到 插件日志.txt.old，本文件从头开始\n",
                _lvLogTimeString(), kLVCatPrefs];
            [notice writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
            gLogHeaderDone = YES;
        }
    } @catch (NSException *e) {
        @try { if (h) { [h closeFile]; } } @catch (NSException *e2) { }
    }
}

static void _lvLogEmit(NSString *lvl, NSString *cat, NSString *msg) {
    if (!msg.length) { return; }
    NSString *body = (msg.length > 400)
        ? [[msg substringToIndex:400] stringByAppendingString:@"…(已截断)"]
        : msg;
    NSString *lvlCopy = lvl ?: @"记录";
    NSString *catCopy = cat ?: @"通用";
    dispatch_async(_lvLogQueue(), ^{
        @try {
            if (!gLogBuffer) { gLogBuffer = [NSMutableArray arrayWithCapacity:LVLOG_BUFFER_MAX]; }
            if (!gLogLastAt) { gLogLastAt = [NSMutableDictionary dictionary]; }
            if (!gLogRepeat) { gLogRepeat = [NSMutableDictionary dictionary]; }
            NSString *key = [NSString stringWithFormat:@"%@|%@|%@", lvlCopy, catCopy, body];
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            NSNumber *last = gLogLastAt[key];
            NSString *out = body;
            if (last && (now - [last doubleValue]) < LVLOG_THROTTLE_SEC) {
                NSInteger r = [gLogRepeat[key] integerValue] + 1;
                gLogRepeat[key] = @(r);
                BOOL punch = (r < 20) ? ((r % 5) == 0) : ((r % 50) == 0);
                if (!punch) { return; }
                out = [NSString stringWithFormat:@"%@（%.0f 秒内重复 %ld 次）", body, LVLOG_THROTTLE_SEC, (long)r];
                gLogRepeat[key] = @(0);
            } else {
                NSInteger r = [gLogRepeat[key] integerValue];
                if (r > 0) {
                    [gLogBuffer addObject:[NSString stringWithFormat:
                        @"[%@] [%@/%@] ↑ 上面这条在这段时间里一共出现 %ld 次（已合并）\n",
                        _lvLogTimeString(), catCopy, lvlCopy, (long)r]];
                    gLogRepeat[key] = @(0);
                }
                gLogLastAt[key] = @(now);
            }
            [gLogBuffer addObject:[NSString stringWithFormat:@"[%@] [%@/%@] %@\n",
                                   _lvLogTimeString(), catCopy, lvlCopy, out]];
            if (gLogBuffer.count >= LVLOG_BUFFER_MAX) { _lvLogFlushLocked(); }
            else { _lvLogScheduleFlushLocked(); }
        } @catch (NSException *e) { }
    });
}

// 同步把缓冲区写到磁盘（设置面板导出日志前调用，保证导出的是完整内容）
static void _lvLogFlushNowSync(void) {
    @try {
        dispatch_sync(_lvLogQueue(), ^{
            @try { _lvLogFlushLocked(); } @catch (NSException *e) { }
        });
    } @catch (NSException *e) { }
}

// 注意：刻意不做 CFPreferencesAppSynchronize —— 那是强制刷盘的同步操作，
// 在会被每帧调用的路径上用它本身就是卡顿来源。
static BOOL _lvLogEnabledRaw(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoLogEnabled"];
        if (v) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO; }
        for (NSString *suite in _lvSuites()) {
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoLogEnabled"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)] && [val boolValue]) { return YES; }
        }
    } @catch (NSException *e) { }
    return NO;
}

static BOOL _lvLogVerboseRaw(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoLogVerbose"];
        if (v) { return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO; }
        for (NSString *suite in _lvSuites()) {
            CFTypeRef cf = CFPreferencesCopyAppValue(CFSTR("LockVideoLogVerbose"), (__bridge CFStringRef)suite);
            if (!cf) { continue; }
            id val = CFBridgingRelease(cf);
            if ([val respondsToSelector:@selector(boolValue)] && [val boolValue]) { return YES; }
        }
    } @catch (NSException *e) { }
    return NO;
}

static BOOL _lvLogging(void) {
    if (gLogReentrant) { return NO; }
    gLogReentrant = YES;
    BOOL r = NO;
    @try { r = _lvLogEnabledRaw(); } @catch (NSException *e) { r = NO; }
    gLogReentrant = NO;
    return r;
}

// 「详细日志」是否开启（记录级）
static BOOL _lvVerbose(void) {
    if (gLogReentrant) { return NO; }
    gLogReentrant = YES;
    BOOL r = NO;
    @try { r = _lvLogEnabledRaw() && _lvLogVerboseRaw(); } @catch (NSException *e) { r = NO; }
    gLogReentrant = NO;
    return r;
}

static void _lvNote(NSString *cat, NSString *fmt, ...) {
    if (!_lvVerbose()) { return; }
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    _lvLogEmit(@"记录", cat, m);
}

static void _lvIssue(NSString *cat, NSString *fmt, ...) {
    if (!_lvLogging()) { return; }
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    _lvLogEmit(@"疑似", cat, m);
}

static void _lvFail(NSString *cat, NSString *fmt, ...) {
    if (!_lvLogging()) { return; }
    va_list ap; va_start(ap, fmt);
    NSString *m = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    _lvLogEmit(@"失败", cat, m);
}

static void _lvExcept(const char *fn, NSException *e) {
    if (!_lvLogging()) { return; }
    NSString *name = e ? (e.name ?: @"(无名称)") : @"(nil 异常)";
    NSString *reason = e ? (e.reason ?: @"(无原因)") : @"(nil 异常)";
    _lvLogEmit(@"失败", kLVCatExcept,
               [NSString stringWithFormat:@"%s 抛出 %@：%@", fn ?: "?", name, reason]);
}

// 旧的 Hook 日志通道：改走问题日志的「记录」级（详细日志开启时才写）
static void _lvLog(NSString *line) {
    if (!_lvVerbose()) { return; }
    _lvLogEmit(@"记录", kLVCatPrefs, line ?: @"");
}

static void _lvLogOnce(NSString *cls, NSString *action) {
    if (!_lvVerbose()) { return; }
    _lvLogEmit(@"记录", cls ?: @"通用", action ?: @"");
}

// ─── 卡顿观测 ─────────────────────────────────────────────────────
// 只在「日志已开启」时才真正取时间戳；开关关闭时 LV_PERF_BEGIN 退化成一个 0 值，
// 额外开销约等于一次 clock_gettime，可以忽略。
static BOOL gPerfWatch = NO;
static double gPerfWatchStamp = 0;
static BOOL _lvPerfWatch(void) {
    if (gLogReentrant) { return NO; }
    double now = _lvNowMs();
    if (gPerfWatchStamp <= 0.0 || (now - gPerfWatchStamp) > 1000.0) {
        gPerfWatchStamp = now;
        gPerfWatch = _lvLogging();
    }
    return gPerfWatch;
}

#define LV_PERF_BEGIN()   double _lv_perf_t0 = (_lvPerfWatch() ? _lvNowMs() : 0.0)
// 可变参数写法：耗时 %.1f ms 由宏补在最后一位
#define LV_PERF_CHECK(cat, budgetMs, fmt, ...) do { \
        if (_lv_perf_t0 > 0.0) { \
            double _dt = _lvNowMs() - _lv_perf_t0; \
            if (_dt > (double)(budgetMs)) { \
                _lvIssue((cat), (fmt), ##__VA_ARGS__, _dt); \
            } \
        } \
    } while (0)

// 诊断用：把通知视图的完整层级写到 /var/mobile/通知视频/视图结构.txt
// 每一层记录：类名 / frame / hidden / alpha / 背景色 / 子图层 / 是否挂载素材
// 文件末尾还会列出「结论段」——所有挂了素材的视图及其素材文件名与覆盖区域
static NSTimeInterval gLastDumpTime = 0;
static void _lvDumpHierarchy(UIView *root, BOOL force) {
    @try {
        if (!root) { return; }
        // 视图结构.txt 只在「视图描边调试」开启时才导出，平时不再写日志
        if (!_lvDebugOutline()) { return; }
        if (![[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]) { return; }
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSTimeInterval gap = _lvDebugOutline() ? 1.5 : 8.0;
        if (!force && now - gLastDumpTime < gap) { return; }   // 节流，避免频繁写文件
        gLastDumpTime = now;

        NSMutableString *s = [NSMutableString string];
        [s appendFormat:@"时间: %@\n", [NSDate date]];
        [s appendFormat:@"系统: %@\n", [[UIDevice currentDevice] systemVersion]];
        [s appendFormat:@"插件启用: %@   可视化调试: %@\n",
         _lvEnabled() ? @"是" : @"否", _lvDebugOutline() ? @"开" : @"关"];
        [s appendFormat:@"根视图: %@ frame=%.0f,%.0f %.0fx%.0f\n\n",
         NSStringFromClass([root class]), root.frame.origin.x, root.frame.origin.y,
         root.frame.size.width, root.frame.size.height];

        NSMutableArray *attached = [NSMutableArray array];

        NSMutableArray *stack = [NSMutableArray array];
        [stack addObject:@[root, @0]];
        int visited = 0;
        while (stack.count > 0 && visited < 600) {
            NSArray *item = stack.lastObject;
            [stack removeLastObject];
            visited++;
            UIView *v = item[0];
            int depth = [item[1] intValue];
            if (depth > 10) { continue; }
            NSString *cls = NSStringFromClass([v class]);
            NSString *path = objc_getAssociatedObject(v, &kPathKey);
            NSString *mtl = path ? @" [已挂素材]" : @"";
            UIColor *bg = nil;
            @try { bg = v.backgroundColor; } @catch (NSException *e) { _lvExcept(__func__, e);}
            NSString *bgDesc = @"无";
            if (bg) {
                CGFloat r = 0, g = 0, b = 0, a = 0;
                if ([bg getRed:&r green:&g blue:&b alpha:&a]) {
                    bgDesc = [NSString stringWithFormat:@"%.2f,%.2f,%.2f,%.2f", r, g, b, a];
                }
            }
            NSUInteger subLayers = 0;
            @try { subLayers = v.layer.sublayers.count; } @catch (NSException *e) { _lvExcept(__func__, e);}
            NSString *actTag = @"";
            if (_lvIsActivityContentClass(cls) || _lvIsActivityHost(v)) {
                switch (_lvResolvedKindForView(v)) {
                    case LVActivityKindNowPlaying: actTag = @" [播放器]"; break;
                    case LVActivityKindGeneral:    actTag = @" [活动]";   break;
                    default:                       actTag = @" [类型未定]"; break;
                }
            }
            [s appendFormat:@"%@%@ frame=%.0f,%.0f %.0fx%.0f hidden=%d alpha=%.2f bg=%@ 图层=%lu%@%@\n",
             [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
             cls, v.frame.origin.x, v.frame.origin.y,
             v.frame.size.width, v.frame.size.height,
             (int)v.hidden, v.alpha, bgDesc, (unsigned long)subLayers, mtl, actTag];

            if (path) {
                AVPlayerLayer *pl = objc_getAssociatedObject(v, &kLayerKey);
                UIImageView *iv = objc_getAssociatedObject(v, &kImgKey);
                CGRect cover = pl ? pl.frame : (iv ? iv.frame : CGRectZero);
                [attached addObject:[NSString stringWithFormat:@"%@ 素材=%@ 覆盖=%.0f,%.0f %.0fx%.0f",
                                     cls, path.lastPathComponent,
                                     cover.origin.x, cover.origin.y,
                                     cover.size.width, cover.size.height]];
            }

            for (UIView *c in v.subviews) { [stack addObject:@[c, @(depth + 1)]]; }
        }

        [s appendString:@"\n===== 素材配置 =====\n"];
        NSString *mainP = _lvPath();
        NSString *optP = _lvOptionPath();
        NSString *clrP = _lvClearPath();
        NSString *actP = _lvActivityPath();
        [s appendFormat:@"  当前素材=%@\n", mainP ? mainP.lastPathComponent : @"未设置（卡片不会有背景）"];
        [s appendFormat:@"  选项素材=%@\n", optP ? optP.lastPathComponent : @"未设置"];
        [s appendFormat:@"  清除素材=%@\n", clrP ? clrP.lastPathComponent : @"未设置"];
        [s appendFormat:@"  实时活动素材=%@\n", actP ? actP.lastPathComponent : @"未设置（回退主素材）"];
        [s appendFormat:@"  素材目录文件数=%lu\n", (unsigned long)_lvScanFiles().count];

        [s appendFormat:@"\n===== 挂载了素材的视图（共 %lu 个）=====\n", (unsigned long)attached.count];
        if (attached.count == 0) {
            [s appendString:@"（无）\n"];
        } else {
            for (NSString *line in attached) { [s appendFormat:@"  %@\n", line]; }
        }

        // 壁纸层：卡片背景被裁剪后露出的就是它，若它也挂了素材就会看起来「下面还有一层视频」
        [s appendString:@"\n===== 壁纸层 =====\n"];
        @try {
            id app = [UIApplication sharedApplication];
            NSArray *wins = nil;
            @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) { _lvExcept(__func__, e);}
            BOOL found = NO;
            for (UIWindow *w in wins) {
                NSMutableArray *st = [NSMutableArray arrayWithObject:@[w, @0]];
                int vv = 0;
                while (st.count > 0 && vv < 400) {
                    NSArray *it = st.lastObject;
                    [st removeLastObject];
                    vv++;
                    UIView *sv = it[0];
                    int dd = [it[1] intValue];
                    if (dd > 9) { continue; }
                    NSString *c = NSStringFromClass([sv class]);
                    if ([c.lowercaseString containsString:@"wallpaper"]) {
                        NSString *pp = objc_getAssociatedObject(sv, &kPathKey);
                        [s appendFormat:@"  %@ frame=%.0f,%.0f %.0fx%.0f 素材=%@\n",
                         c, sv.frame.origin.x, sv.frame.origin.y,
                         sv.frame.size.width, sv.frame.size.height,
                         pp ? pp.lastPathComponent : @"无"];
                        found = YES;
                    }
                    if (dd < 9) {
                        for (UIView *cc in sv.subviews) { [st addObject:@[cc, @(dd + 1)]]; }
                    }
                }
            }
            if (!found) { [s appendString:@"  （未找到壁纸视图）\n"]; }
        } @catch (NSException *e) { _lvExcept(__func__, e);}
        [s writeToFile:kLVDumpFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// dump 用更好的根视图：「选项/清除」按钮不在小卡片 ShortLookView 的子树里，
// 之前按卡片导出的文件里永远看不到按钮区（挂载记录是 0 个但按钮明明挂了素材）。
// 向上找包含 cell / longlook / listview 的祖先，把整条通知都框进导出范围。
static UIView *_lvBetterDumpRoot(UIView *v) {
    if (!v) { return nil; }
    UIView *best = v;
    @try {
        UIView *p = v.superview;
        int up = 0;
        while (p && up < 8) {
            NSString *c = NSStringFromClass([p class]).lowercaseString ?: @"";
            if ([c containsString:@"cell"] || [c containsString:@"longlook"] ||
                [c containsString:@"listview"] || [c containsString:@"stackview"]) {
                best = p;
            }
            p = p.superview;
            up++;
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return best;
}

#pragma mark - 播放器（每个挂载视图独立一个 AVPlayer，避免同素材多视图共用导致卡住/花屏）

static void _lvAllowAutoLockForPlayer(AVPlayer *p) {
    @try {
        if (!p) { return; }
        SEL sel = NSSelectorFromString(@"setPreventsDisplaySleepDuringVideoPlayback:");
        if ([p respondsToSelector:sel]) {
            [p setValue:@NO forKey:@"preventsDisplaySleepDuringVideoPlayback"];
            _lvLogOnce(@"自动锁屏", @"已允许视频播放时熄屏");
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
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
    } @catch (NSException *e) { _lvExcept(__func__, e); return nil; }
}

static AVPlayer *_lvPlayerForPath(NSString *path) {
    @try {
        if (_lvPathIsImageAsset(path)) { return nil; }
        if (![path isKindOfClass:[NSString class]] || !path.length) {
            _lvLogOnce(@"扫描结果", [NSString stringWithFormat:@"%@ 里没有找到视频文件", kLVVideoDir]);
            return nil;
        }
        // 按路径复用：同一段视频只创建一个 AVPlayer，多个视图的 AVPlayerLayer 共用它，
        // 避免 1.0.79「每视图独立播放器」在同素材多视图时重复解码导致掉帧/卡顿。
        if (!gPlayerByPath) { gPlayerByPath = [NSMutableDictionary dictionary]; }
        if (!gObserverMap) { gObserverMap = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory]; }
        if (!gAllPlayers) { gAllPlayers = [NSMutableSet set]; }
        if (!gRefCount) { gRefCount = [NSMutableDictionary dictionary]; }

        AVPlayer *existing = gPlayerByPath[path];
        if (existing) {
            NSValue *pkey = [NSValue valueWithNonretainedObject:existing];
            NSInteger c = [gRefCount[pkey] integerValue];
            gRefCount[pkey] = @(c + 1);
            return existing;
        }

        AVPlayerItem *item = [AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]];
        if (!item) {
            _lvFail(kLVCatFail, @"视频轨道创建失败（文件路径对但读不出内容）：%@", path.lastPathComponent ?: path);
            return nil;
        }
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            _lvFail(kLVCatAsset, @"视频文件不存在：%@", path);
        }
        AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
        player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
        player.muted = !_lvSound();
        _lvAllowAutoLockForPlayer(player);
        [gAllPlayers addObject:player];
        gPlayerByPath[path] = player;
        NSValue *pkey = [NSValue valueWithNonretainedObject:player];
        gRefCount[pkey] = @(1);

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
                } @catch (NSException *e) { _lvExcept(__func__, e);}
            }];
            [gObserverMap setObject:observer forKey:player];

            // 故障诊断监听：视频自身出问题（解码跟不上、播到一半失败、错误日志）
            // 都是「卡顿 / 声音 / 失效」的直接证据，平时没人上报，只能靠这里留痕。
            if (!gAuxObserverMap) {
                gAuxObserverMap = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory
                                                       valueOptions:NSMapTableStrongMemory];
            }
            NSMutableArray *aux = [NSMutableArray array];
            NSOperationQueue *mq = [NSOperationQueue mainQueue];
            NSString *nm = path.lastPathComponent ?: path;
            id oStall = [[NSNotificationCenter defaultCenter]
                addObserverForName:AVPlayerItemPlaybackStalledNotification
                            object:item queue:mq usingBlock:^(NSNotification *n) {
                _lvIssue(kLVCatPerf, @"视频解码跟不上 / 读取被阻塞，播放中断：%@", nm);
            }];
            if (oStall) { [aux addObject:oStall]; }
            id oFail = [[NSNotificationCenter defaultCenter]
                addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification
                            object:item queue:mq usingBlock:^(NSNotification *n) {
                NSError *err = n.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
                _lvFail(kLVCatFail, @"视频播到一半失败：%@ 错误=%@", nm, err ?: (id)@"(未知)");
            }];
            if (oFail) { [aux addObject:oFail]; }
            id oNewErr = [[NSNotificationCenter defaultCenter]
                addObserverForName:AVPlayerItemNewErrorLogEntryNotification
                            object:item queue:mq usingBlock:^(NSNotification *n) {
                _lvFail(kLVCatFail, @"视频产生错误日志条目（解码器 / 文件损坏）：%@", nm);
            }];
            if (oNewErr) { [aux addObject:oNewErr]; }
            if (aux.count) { [gAuxObserverMap setObject:aux forKey:player]; }

            _lvNote(kLVCatPlayer, @"创建播放器（按路径复用）：%@ 声音=%d", nm, _lvSound());
        return player;
    } @catch (NSException *e) { _lvExcept(__func__, e);
        _lvLog([NSString stringWithFormat:@"player 异常: %@", e]);
        return nil;
    }
}

static void _lvDetachPlayer(AVPlayer *player) {
    if (!player) { return; }
    @try {
        id observer = [gObserverMap objectForKey:player];
        if (observer) {
            [[NSNotificationCenter defaultCenter] removeObserver:observer];
            [gObserverMap removeObjectForKey:player];
        }
        [player pause];
        NSMutableArray *aux = [gAuxObserverMap objectForKey:player];
        if (aux) {
            for (id tok in aux) { [[NSNotificationCenter defaultCenter] removeObserver:tok]; }
            [gAuxObserverMap removeObjectForKey:player];
        }
        [gAllPlayers removeObject:player];
        // 从「按路径复用」缓存中清除该播放器，避免被再次复用
        NSString *hitKey = nil;
        for (NSString *k in [gPlayerByPath allKeys]) {
            if (gPlayerByPath[k] == player) { hitKey = k; break; }
        }
        if (hitKey) { [gPlayerByPath removeObjectForKey:hitKey]; }
        [gRefCount removeObjectForKey:[NSValue valueWithNonretainedObject:player]];
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 视图卸载时释放一次引用；只有引用归零（没有其它同路径视图再用）才真正销毁播放器，
// 这样共享同一段视频的其它视图不会因为某一个视图卸载而被迫停掉/重建。
static void _lvReleasePlayerRef(AVPlayer *player) {
    if (!player) { return; }
    @try {
        NSValue *key = [NSValue valueWithNonretainedObject:player];
        NSInteger c = [gRefCount[key] integerValue];
        if (c <= 1) {
            _lvDetachPlayer(player);
        } else {
            gRefCount[key] = @(c - 1);
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 判断某个播放器是否被「其它有效可见」的挂载视图使用（防止共享播放器被单个隐藏视图误暂停/误静音）
static BOOL _lvPlayerHasOtherVisibleView(AVPlayer *p, UIView *exceptV) {
    if (!p) { return NO; }
    @try {
        for (UIView *v in [_lvAttachedTable() allObjects]) {
            if (v == exceptV) { continue; }
            AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
            AVPlayer *vp = l.player ?: objc_getAssociatedObject(v, &kPlayerKey);
            if (vp == p && _lvViewEffectivelyVisible(v) && !_lvPathIsImageAsset(objc_getAssociatedObject(v, &kPathKey))) {
                return YES;
            }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return NO;
}

static void _lvResetAllPlayers(void) {
    @try {
        for (AVPlayer *p in [gAllPlayers copy]) {
            _lvDetachPlayer(p);
        }
        [gAllPlayers removeAllObjects];
        [gPlayerByPath removeAllObjects];
        [gRefCount removeAllObjects];
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 暂停必须连声音一起掐掉：只 pause 不 muted 的话，正在缓冲/回到开头重新拉流的播放器
// 仍可能在下一次 seek 之后自己响起来 —— 用户听到的就是「明明划走了还在放」。
static void _lvPauseAllPlayers(void) {
    @try {
        for (AVPlayer *p in gAllPlayers) { p.muted = YES; [p pause]; }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvPlayAllVisiblePlayers(void) {
    @try {
        for (UIView *v in [_lvAttachedTable() allObjects]) {
            AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
            AVPlayer *p = l.player ?: objc_getAssociatedObject(v, &kPlayerKey);
            if (p && _lvViewEffectivelyVisible(v) && !_lvPathIsImageAsset(objc_getAssociatedObject(v, &kPathKey))) {
                [p play];
            }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

#pragma mark - 视图识别

// 当前是否真的有媒体在播（-1 拿不到=不表态 / 0 没有 / 1 有）
// 给「几何猜测」兜一层保险：压根没有东西在放，就别把实时活动误判成播放器
static NSInteger _lvNowPlayingState(void) {
    @try {
        Class mc = objc_getClass("SBMediaController");
        if (!mc) { return -1; }
        SEL shared = [mc respondsToSelector:@selector(sharedInstance)] ? @selector(sharedInstance) : @selector(mainInstance);
        if (![mc respondsToSelector:shared]) { return -1; }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id inst = [mc performSelector:shared];
#pragma clang diagnostic pop
        if (!inst) { return -1; }
        if ([inst respondsToSelector:@selector(nowPlayingApplication)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id app = [inst performSelector:@selector(nowPlayingApplication)];
#pragma clang diagnostic pop
            return app ? 1 : 0;
        }
        if ([inst respondsToSelector:@selector(isPlaying)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            BOOL playing = (BOOL)[inst performSelector:@selector(isPlaying)];
#pragma clang diagnostic pop
            return playing ? 1 : 0;
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return -1;
}

// 把活动卡片的子视图结构打成一串可读文本（类名 + 尺寸 + 无障碍标签），每次出现只记一次。
// 这是彻底分清「实时活动」和「锁屏媒体播放器」的关键证据：不同系统版本 / 不同 App 的
// 容器类名完全不一样，靠猜永远会有漏网的，必须看到真实类名才补得准。
static NSString *_lvSubtreeDigest(UIView *root) {
    NSMutableString *out = [NSMutableString string];
    @try {
        if (root.superview) {
            NSMutableArray<NSString *> *ups = [NSMutableArray array];
            NSInteger hop = 0;
            for (UIView *cur = root.superview; cur && hop < 6; cur = cur.superview) {
                hop++;
                NSString *al = nil;
                @try { al = cur.accessibilityLabel; } @catch (NSException *e) { al = nil; }
                CGSize sz = cur.bounds.size;
                [ups addObject:[NSString stringWithFormat:@"%@(%.0fx%.0f)%@",
                                NSStringFromClass([cur class]), sz.width, sz.height,
                                al.length ? [@"[" stringByAppendingFormat:@"%@]", al] : @""]];
            }
            [out appendFormat:@"祖先[%@] || ", [ups componentsJoinedByString:@" < "]];
        }
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
        int nodes = 0;
        while (stack.count && nodes < 70 && out.length < 900) {
            UIView *cur = [stack lastObject];
            [stack removeLastObject];
            nodes++;
            NSString *cls = NSStringFromClass([cur class]);
            CGSize sz = cur.bounds.size;
            [out appendFormat:@"%@(%.0fx%.0f)", cls, sz.width, sz.height];
            NSString *al = nil;
            @try { al = cur.accessibilityLabel; } @catch (NSException *e) { al = nil; }
            if (al.length) { [out appendFormat:@"[%@]", al]; }
            [out appendString:@" > "];
            for (UIView *c in cur.subviews) { [stack addObject:c]; }
        }
        if (out.length > 3) { [out replaceCharactersInRange:NSMakeRange(out.length - 3, 3) withString:@""]; }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return out.length ? out : @"(空)";
}

// 再试着从视图上读出「它属于哪个实时活动 / 哪个 App」。
// 只读纯数据型的私有属性，且要求选择器确实存在，读不到就拉倒 —— 纯诊断用途，不改任何行为。
static NSString *_lvProbeActivityIdentity(UIView *v) {
    NSMutableArray<NSString *> *hits = [NSMutableArray array];
    @try {
        NSArray<NSString *> *keys = @[@"activityIdentifier", @"_activityIdentifier",
                                      @"activityItemIdentifier", @"_activityItemIdentifier",
                                      @"activityAttributes", @"_activityAttributes",
                                      @"bundleIdentifier", @"appBundleIdentifier",
                                      @"_applicationIdentifier", @"contentIdentifier"];
        for (NSString *k in keys) {
            SEL sel = NSSelectorFromString(k);
            if (!sel || ![v respondsToSelector:sel]) { continue; }
            @try {
                id val = [v valueForKey:k];
                NSString *desc = val ? [val description] : nil;
                if (!desc.length) { continue; }
                if (desc.length > 120) { desc = [desc substringToIndex:120]; }
                [hits addObject:[NSString stringWithFormat:@"%@=%@", k, desc]];
            } @catch (NSException *e) { /* 私有属性读不出来是常态，忽略 */ }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return hits.count ? [hits componentsJoinedByString:@" | "] : @"(无私钥可读)";
}

static void _lvDumpActivityStructureOnce(UIView *v) {
    if (!_lvLogging() || !v) { return; }
    if (objc_getAssociatedObject(v, &kKindDumpKey)) { return; }
    objc_setAssociatedObject(v, &kKindDumpKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    _lvNote(kLVCatActivity, @"卡片真实结构（据此区分实时活动/播放器）：%@", _lvSubtreeDigest(v));
    _lvNote(kLVCatActivity, @"卡片所属活动/App（同上目的）：%@", _lvProbeActivityIdentity(v));
}

static void _lvAttachWithPath(UIView *v, NSString *path);

// 实时活动（Live Activity）内容宿主：锁屏音乐播放、外卖进度等卡片的内容层
// dump 实测类名：CSActivityItemContentView（列表内实时活动 / 授权弹窗里都有）
static BOOL _lvIsActivityContentClass(NSString *cls) {
    if (!cls) return NO;
    NSString *low = cls.lowercaseString;
    return [low containsString:@"csactivityitemcontentview"] ||
           [low containsString:@"activityitemcontentview"];
}

// 实时活动卡片的可见宿主：从 CSActivityItemContentView 向上找到 PLPlatterView，
// 这样视频层覆盖的是整个可见卡片区域，而不是尺寸更大/会被裁剪的内容视图
static UIView *_lvFindActivityPlatterHost(UIView *v) {
    @try {
        for (UIView *cur = v; cur; cur = cur.superview) {
            NSString *cls = NSStringFromClass([cur class]).lowercaseString;
            if ([cls isEqualToString:@"plplatterview"]) { return cur; }
            if ([cls containsString:@"platterview"] && ![cls containsString:@"custom"] &&
                ![cls containsString:@"action"] && ![cls containsString:@"content"]) {
                return cur;
            }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return nil;
}

// 实时活动授权弹窗（"允许 xxx 的实时活动？" / "不允许/允许"）不做背景视频
static BOOL _lvIsActivityAuthorizationAlert(UIView *v) {
    @try {
        NSArray<UIView *> *btns = _lvFindPillButtonsInView(v);
        for (UIView *btn in btns) {
            NSString *t = _lvButtonTitle(btn).lowercaseString;
            if ([t containsString:@"允许"] || [t containsString:@"不允许"]) { return YES; }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return NO;
}

// 判断一个实时活动是不是锁屏媒体播放器（Now Playing widget）
//
// 三条判据，任一命中即认定为播放器：
//   1) 强类名证据：NowPlaying / MediaControls / MRUI / CSNowPlaying 等明确的媒体控件类名
//   2) 强文本证据：它是个可点击控件（UIControl），无障碍标签是「播放/暂停/上一首/下一首…」
//   3) 弱类名证据累计 ≥ 2：artwork / playback / scrubber / music / progress …（单条太泛，不作数）
// 关键点：内容还没加载完（子树太单薄）时返回 Unknown，而不是急着判成「普通活动」。
// 旧版在这种时候就判 NO → 挂了实时活动素材甚至主素材 → 内容加载完又重挂 → 肉眼可见的「先错后对」。
static LVActivityKind _lvDetectKindIn(UIView *root, BOOL *loaded) {
    if (loaded) { *loaded = NO; }
    if (!root) { return LVActivityKindUnknown; }
    @try {
        if (root.bounds.size.width < 24.0 || root.bounds.size.height < 12.0) { return LVActivityKindUnknown; }

        static NSArray<NSString *> *strongMarkers = nil;
        static NSArray<NSString *> *weakMarkers = nil;
        static NSArray<NSString *> *axTexts = nil;
        if (!strongMarkers) {
            strongMarkers = @[
                @"nowplaying", @"nowplayingcontent", @"nowplayinglive", @"nowplayingitem",
                @"nowplayingheader", @"nowplayingartwork", @"nowplayingmetadata",
                @"nowplayingwidget", @"nowplayinglockscreen", @"nowplayingmodule",
                @"mediacontrols", @"mediacontrolsview", @"mediacontrolstime",
                @"mediacontrolstransport", @"mediacontrolsvolume", @"mediacontrolsrouting",
                @"mediaplayer", @"mediawidget", @"mediaartwork", @"mediaplayback",
                @"mruimedia", @"mrnowplaying", @"mruartwork", @"mrutransport", @"mruvolume",
                @"mruroute", @"mrumetadata", @"mrcontent", @"mrplatter", @"mrmedia", @"mrroute",
                @"csmediacontrols", @"csnowplaying", @"csnowplayingview", @"csnowplayingtransport",
                @"mpmediacontrols", @"mpmediacontrolsparent", @"mproute", @"mpvolume",
                @"mptransport", @"mpartwork", @"mpbutton",
                @"transportslider", @"transportbutton", @"transportcontrols",
                @"volumecontainer", @"volumeview", @"volumeslider", @"routingbutton",
                @"ellipsisbutton", @"routebutton", @"stepthrough", @"progressslider"
            ];
            weakMarkers = @[
                @"playback", @"scrubber", @"artwork", @"album", @"artist",
                @"tracktitle", @"music", @"skip", @"elapsedtime"
            ];
            axTexts = @[
                @"播放", @"暂停", @"上一首", @"上一曲", @"下一首", @"下一曲",
                @"下一个", @"上一个", @"跳过", @"停止",
                @"play", @"pause", @"next track", @"previous track", @"seek"
            ];
        }

        NSInteger weakHits = 0;
        NSUInteger nodes = 0;
        BOOL sawSlider = NO;          // 音量条 —— 只有媒体卡才有
        BOOL sawArtwork = NO;         // 接近正方的封面图（≥52pt）
        NSInteger smallControls = 0;  // 播控小按钮的个数
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:root];
        while (stack.count) {
            UIView *cur = [stack lastObject];
            [stack removeLastObject];
            if (++nodes > 300) { break; }
            NSString *low = NSStringFromClass([cur class]).lowercaseString;
            BOOL hitStrong = NO;
            for (NSString *m in strongMarkers) {
                if ([low containsString:m]) { hitStrong = YES; break; }
            }
            if (hitStrong) {
                if (loaded) { *loaded = YES; }
                return LVActivityKindNowPlaying;
            }
            for (NSString *m in weakMarkers) {
                if ([low containsString:m]) { weakHits++; break; }
            }
            if (!sawSlider && [cur isKindOfClass:[UISlider class]]) { sawSlider = YES; }
            if (!sawArtwork && [cur isKindOfClass:[UIImageView class]]) {
                CGSize sz = cur.bounds.size;
                if (sz.width >= 52.0 && sz.height >= 52.0 &&
                    (fabs(sz.width - sz.height) / MAX(sz.width, sz.height)) < 0.18) {
                    sawArtwork = YES;
                }
            }
            // 播控按钮的无障碍标签：只对真正的可点击控件采样，避免读到容器继承来的 label 误判
            if ([cur isKindOfClass:[UIControl class]]) {
                CGSize sz = cur.bounds.size;
                if (sz.width > 0.0 && sz.width < 76.0 && sz.height > 0.0 && sz.height < 76.0) { smallControls++; }
                NSString *al = nil;
                @try {
                    if ([cur respondsToSelector:@selector(accessibilityLabel)]) { al = [cur accessibilityLabel]; }
                    if (!al.length && [cur respondsToSelector:@selector(accessibilityIdentifier)]) { al = [cur accessibilityIdentifier]; }
                } @catch (NSException *e) { _lvExcept(__func__, e);}
                if (al.length) {
                    NSString *t = al.lowercaseString;
                    for (NSString *m in axTexts) {
                        if ([t containsString:m]) {
                            if (loaded) { *loaded = YES; }
                            return LVActivityKindNowPlaying;
                        }
                    }
                }
            }
            [stack addObjectsFromArray:cur.subviews];
        }

        // 祖先链也扫一层：有些系统版本把媒体控件放在卡片的父容器里，只读子树会漏掉
        NSInteger hop = 0;
        for (UIView *cur = root.superview; cur && hop < 5; cur = cur.superview) {
            hop++;
            NSString *low = NSStringFromClass([cur class]).lowercaseString;
            BOOL hit = NO;
            for (NSString *m in strongMarkers) {
                if ([low containsString:m]) { hit = YES; break; }
            }
            if (hit) {
                if (loaded) { *loaded = YES; }
                return LVActivityKindNowPlaying;
            }
        }

        // 纯几何猜测：不看类名也能认出「音乐播放器」的外形特征（音量条 / 封面 + 播控按钮）。
        // 前提是系统确实有东西在播 —— 否则宁可按普通实时活动处理，不至于两边都判错。
        if (_lvNowPlayingState() != 0) {
            if (sawSlider) {
                if (loaded) { *loaded = YES; }
                return LVActivityKindNowPlaying;
            }
            if (sawArtwork && smallControls >= 2) {
                if (loaded) { *loaded = YES; }
                return LVActivityKindNowPlaying;
            }
        }
        if (loaded) { *loaded = (nodes >= 6); }
        if (weakHits >= 2) { return LVActivityKindNowPlaying; }
        // 子视图太单薄 —— 十有八九是内容还没从 App 端渲染过来，先别下结论
        if (nodes < 6) { return LVActivityKindUnknown; }
        return LVActivityKindGeneral;
    } @catch (NSException *e) { _lvExcept(__func__, e); return LVActivityKindUnknown; }
}

// 兼容旧调用点
static BOOL _lvIsNowPlayingActivityView(UIView *v) {
    return _lvDetectKindIn(v, NULL) == LVActivityKindNowPlaying;
}

// 素材回退链 —— 关键修正之一：
//   没设「播放器素材」时，退回「实时活动素材」，最后才回退主素材。
//   旧版从播放器直接跳到主素材，于是「只设了活动素材」= 播放器上先出现通知消息视频。
static NSString *_lvResolvedPathForKind(LVActivityKind kind) {
    NSString *pp = _lvPlayerPath();
    NSString *ap = _lvActivityPath();
    if (kind == LVActivityKindNowPlaying) {
        if (pp.length) {
            if (_lvPathIsImageAsset(pp)) {
                _lvIssue(kLVCatAsset, @"播放器素材选的是图片（%@）：不会有画面也不会有声音，想在播放器上看到视频请在这里换成 MP4/MOV",
                         pp.lastPathComponent);
            }
            return pp;
        }
        if (ap.length) { return ap; }
        return _lvPath();
    }
    if (ap.length) { return ap; }
    return _lvPath();
}

// 从宿主往下找回活动内容视图，用于读取它的类型判定结果
static UIView *_lvFindActivityContentInHost(UIView *host) {
    if (!host) { return nil; }
    if (_lvIsActivityContentClass(NSStringFromClass([host class]))) { return host; }
    @try {
        NSMutableArray<UIView *> *stack = [NSMutableArray arrayWithObject:host];
        int visited = 0;
        while (stack.count && visited < 400) {
            UIView *cur = [stack lastObject];
            [stack removeLastObject];
            visited++;
            if (_lvIsActivityContentClass(NSStringFromClass([cur class]))) { return cur; }
            [stack addObjectsFromArray:cur.subviews];
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return nil;
}

// 手动兜底：自动识别在某些 App / 某些系统版本上会彻底失灵（整棵子树全是通用类名），
// 与其让用户干瞪眼，不如让他在设置里直接指定「锁屏上第几张卡是播放器」。
// rule=1 最上面那张，rule=2 最下面那张；rule=0 表示仍然走自动识别。
static NSInteger _lvPlayerPosRule(void) {
    @try {
        id v = _lvPrefs()[@"LockVideoPlayerPosRule"];
        if ([v respondsToSelector:@selector(integerValue)]) { return [v integerValue]; }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return 0;
}

static LVActivityKind _lvKindByPosition(UIView *v, NSInteger rule) {
    @try {
        UIView *probe = _lvFindActivityPlatterHost(v) ?: v;
        NSMutableArray<UIView *> *cards = [NSMutableArray array];
        for (UIView *x in [_lvAttachedTable() allObjects]) {
            if (!x || !x.window) { continue; }
            NSString *cls = NSStringFromClass([x class]);
            if (!_lvIsActivityContentClass(cls) && !_lvIsActivityHost(x)) { continue; }
            if ([cards indexOfObjectIdenticalTo:x] != NSNotFound) { continue; }
            [cards addObject:x];
        }
        if ([cards indexOfObjectIdenticalTo:probe] == NSNotFound) { [cards addObject:probe]; }
        if (cards.count <= 1) { return LVActivityKindGeneral; }   // 只有一张卡就没什么好分的
        [cards sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
            CGFloat ya = CGRectGetMidY([a convertRect:a.bounds toView:nil]);
            CGFloat yb = CGRectGetMidY([b convertRect:b.bounds toView:nil]);
            if (fabs(ya - yb) > 4.0) { return ya < yb ? NSOrderedAscending : NSOrderedDescending; }
            CGFloat xa = CGRectGetMidX([a convertRect:a.bounds toView:nil]);
            CGFloat xb = CGRectGetMidX([b convertRect:b.bounds toView:nil]);
            return xa < xb ? NSOrderedAscending : NSOrderedDescending;
        }];
        NSUInteger idx = [cards indexOfObjectIdenticalTo:probe];
        NSUInteger target = (rule == 1) ? 0 : (cards.count - 1);
        LVActivityKind k = (idx != NSNotFound && idx == target) ? LVActivityKindNowPlaying : LVActivityKindGeneral;
        _lvNote(kLVCatActivity, @"按位置判定：第 %lu/%lu 张卡 → %@",
                (unsigned long)(idx == NSNotFound ? 0 : idx + 1), (unsigned long)cards.count,
                k == LVActivityKindNowPlaying ? @"播放器" : @"普通活动");
        return k;
    } @catch (NSException *e) { _lvExcept(__func__, e); return LVActivityKindGeneral; }
}

// 综合「已确定的类型」与「当下检测结果」给出最终类型。
// 已定为播放器就钉住不放；已定为普通活动仍留一次升级机会（媒体控件可能是后加载的）。
static LVActivityKind _lvResolvedKindForView(UIView *v) {
    @try {
        NSInteger posRule = _lvPlayerPosRule();
        if (posRule != 0) { return _lvKindByPosition(v, posRule); }   // 用户手动指定优先
        UIView *content = nil;
        if (_lvIsActivityContentClass(NSStringFromClass([v class]))) {
            content = v;
        } else if (_lvIsActivityHost(v)) {
            content = _lvFindActivityContentInHost(v);
        } else {
            LVActivityKind k0 = _lvDetectKindIn(v, NULL);
            return (k0 == LVActivityKindUnknown) ? LVActivityKindGeneral : k0;
        }
        if (!content) { content = v; }
        NSNumber *sticky = objc_getAssociatedObject(content, &kKindKey);
        UIView *probeRoot = _lvFindActivityPlatterHost(v) ?: v;
        if (!sticky) {
            BOOL loaded = NO;
            LVActivityKind k = _lvDetectKindIn(probeRoot, &loaded);
            return (k == LVActivityKindUnknown) ? LVActivityKindGeneral : k;
        }
        if ([sticky integerValue] == LVActivityKindNowPlaying) { return LVActivityKindNowPlaying; }
        // 已定为普通活动：只给一次「是不是漏判的播放器」复查机会。
        // 媒体控件有可能延迟加载，但绝不能每次 layout 都重扫整棵子树 —— 那会拖垮下拉帧率。
        if (objc_getAssociatedObject(content, &kKindProbeKey)) { return LVActivityKindGeneral; }
        objc_setAssociatedObject(content, &kKindProbeKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LVActivityKind k = _lvDetectKindIn(probeRoot, NULL);
        if (k == LVActivityKindNowPlaying) {
            objc_setAssociatedObject(content, &kKindKey, @(LVActivityKindNowPlaying), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            return LVActivityKindNowPlaying;
        }
        return LVActivityKindGeneral;
    } @catch (NSException *e) { _lvExcept(__func__, e); return LVActivityKindGeneral; }
}

// 根据视图当前的真实类型，算出「此刻最应该挂的素材路径」
// 用于：①锁屏下拉动画/内容延迟加载导致首次挂载类型判断不准时，在 _lvRefresh 里纠正；
//       ②活动卡片若属于 Now Playing 应走播放器素材，否则走实时活动素材，都为空回退主素材。
// 返回 nil 表示「不干预」：①普通通知卡片；②活动类型还没定下来（交给延迟复核，别抢跑）
static NSString *_lvExpectedPathForView(UIView *v) {
    if (!v) return nil;
    @try {
        NSString *cls = NSStringFromClass([v class]);
        if (!_lvIsActivityContentClass(cls) && !_lvIsActivityHost(v)) { return nil; }

        // 结果短时缓存：layoutSubviews 每帧都会走到这里，
        // 不缓存的话等于每帧扫一遍子树的类名，下拉动画必然掉帧
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSNumber *stamp = objc_getAssociatedObject(v, &kExpectedStampKey);
        NSString *cached = objc_getAssociatedObject(v, &kExpectedKey);
        if (cached && stamp && (now - [stamp doubleValue]) < 0.35) {
            return cached.length ? cached : nil;
        }

        NSString *result = nil;
        @try {
            if (_lvIsActivityContentClass(cls) || _lvIsActivityHost(v)) {
                LVActivityKind k = _lvResolvedKindForView(v);
                result = _lvResolvedPathForKind(k);
            }
        } @catch (NSException *e) { _lvExcept(__func__, e);}

        objc_setAssociatedObject(v, &kExpectedKey, result ?: @"", OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kExpectedStampKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return result.length ? result : nil;
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return nil;
}

static BOOL _lvIsActionButtonGroupView(NSString *cls) {
    if (!cls) return NO;
    NSString *low = cls.lowercaseString;
    // —— 外围容器一律不算按钮区（只认「按钮组」和「按钮本身」，其余不碰）——
    if ([low containsString:@"presenting"]) return NO;   // PLActionButtonsPresentingView（按钮的呈现容器）
    if ([low containsString:@"floating"])   return NO;   // FVFloatingActionView（悬浮视图）
    if ([low containsString:@"menu"])       return NO;   // 动作菜单容器
    if ([low containsString:@"group"]) {
        return [low containsString:@"buttongroup"];      // PLCTButtonGroupView / PLPillButtonGroupView
    }
    if ([low containsString:@"pillcontent"]) return YES; // PLPillContentView（iOS18 动作菜单按钮容器）
    if ([low containsString:@"actionbutton"]) return YES; // NCNotificationListCellActionButton / PLPlatterActionButton(s)View
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
// 关键：PLPlatterActionButtonsView 类名含 actionbutton 又不含 group，
// 曾被误判成单个按钮，导致按钮组容器整块挂上素材——这就是「选项下面还有一层同款视频」的元凶
static BOOL _lvIsSingleActionButtonClass(NSString *cls) {
    if (!cls) { return NO; }
    NSString *low = cls.lowercaseString;
    if ([low containsString:@"group"])       { return NO; }
    if ([low containsString:@"buttonsview"]) { return NO; }   // PLPlatterActionButtonsView（按钮组容器）
    if ([low containsString:@"presenting"])  { return NO; }   // PLActionButtonsPresentingView
    if ([low containsString:@"pillcontent"]) { return NO; }   // PLPillContentView（菜单容器）
    if ([low containsString:@"actionbutton"]) { return YES; }
    return _lvIsPillButtonClass(cls);
}

static void _lvRestoreBackgroundsRecursive(UIView *v, int depth);
static void _lvDetach(UIView *v);

// 动作按钮组（含单个动作按钮）或通知卡片本体（shortlook/banner/longlook）
static BOOL _lvIsNotificationView(UIView *v) {
    @try {
        NSString *cls = NSStringFromClass([v class]);
        if (!cls) { return NO; }
        if (_lvIsActionButtonGroupView(cls)) return YES;
        if (_lvIsActivityContentClass(cls)) return YES;   // 实时活动内容宿主视同卡片
        if (_lvIsActivityHost(v)) { return YES; }           // 已被标记的实时活动宿主（PLPlatterView）也需要刷新
        NSString *low = cls.lowercaseString;
        if (![low containsString:@"notification"]) { return NO; }
        if ([low containsString:@"stackdimming"]) { return NO; }
        if ([low containsString:@"header"])       { return NO; }
        if ([low containsString:@"listview"])     { return NO; }
        if ([low containsString:@"sectionlist"])  { return NO; }
        if ([low containsString:@"listcell"])     { return NO; }
        if ([low containsString:@"content"])      { return NO; }
        return [low containsString:@"shortlook"] || [low containsString:@"banner"] || [low containsString:@"longlook"];
    } @catch (NSException *e) { _lvExcept(__func__, e); return NO; }
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
                _lvRestoreBackgroundsRecursive(sv, 0);   // 清掉历史版本残留的隐藏标记
                continue;
            }
            // 卡片自身的整块毛玻璃：保留显示，视频叠在它上面；
            // 被裁剪掉的按钮区因此露出系统原样，而不是透出壁纸
            if (objc_getAssociatedObject(sv, &kKeepBgKey)) {
                _lvRestoreBackgroundsRecursive(sv, 0);
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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvDetach(UIView *v);

// 只针对通知卡片本体（shortlook / banner / longlook）
static BOOL _lvIsCardHostClass(NSString *cls) {
    if (!cls) { return NO; }
    if (_lvIsActivityContentClass(cls)) { return YES; }   // 实时活动内容宿主按卡片宿主处理
    NSString *low = cls.lowercaseString;
    return [low containsString:@"shortlook"] || [low containsString:@"banner"] || [low containsString:@"longlook"];
}

static BOOL _lvIsActivityHost(UIView *v) {
    if (!v) { return NO; }
    return objc_getAssociatedObject(v, &kActivityHostKey) != nil;
}

// 找到卡片自身的整块背景层（毛玻璃 / 材质 / 暗化视图）在 sublayers 里的索引，找不到返回 -1。
// 找到后我们把视频层插到它「上面一层」——这样系统毛玻璃保留下来，
// 视频被裁剪掉的区域（按钮区）露出的就是真正的系统原样，而不是透出壁纸/别的视频。
// 卡片自身的整块背景层（毛玻璃 / 材质）判定：覆盖面积够大、且不是列表级暗化层
static BOOL _lvIsKeepableBackdrop(UIView *sv, UIView *host) {
    if (!sv || !host || !_lvIsBackgroundView(sv)) { return NO; }
    NSString *low = NSStringFromClass([sv class]).lowercaseString;
    if ([low containsString:@"stackdimming"]) { return NO; }
    CGRect f = sv.frame;
    if (f.size.width < host.bounds.size.width * 0.6) { return NO; }
    if (f.size.height < host.bounds.size.height * 0.6) { return NO; }
    return YES;
}

static int _lvTopFullCoverBackgroundIndex(UIView *v) {
    int idx = -1;
    @try {
        if (v.bounds.size.width < 8.0 || v.bounds.size.height < 8.0) { return -1; }
        NSArray<UIView *> *subs = v.subviews;
        for (NSUInteger i = 0; i < subs.count; i++) {
            UIView *sv = subs[i];
            if (!_lvIsKeepableBackdrop(sv, v)) { continue; }
            NSUInteger li = [v.layer.sublayers indexOfObject:sv.layer];
            if (li == NSNotFound) { continue; }
            if ((int)li > idx) { idx = (int)li; }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return idx;
}

// 卡片：先把自身的整块系统背景标记为「保留」，再照旧隐藏其余背景层；
// 视频层插到保留背景的上面一层 —— 被裁剪掉的按钮区就露出真正的系统原样
static void _lvPrepareHostBackgrounds(UIView *v) {
    if (!v) { return; }
    LV_PERF_BEGIN();
    if (_lvIsCardHostClass(NSStringFromClass([v class]))) {
        for (UIView *sv in v.subviews) {
            if (!_lvIsKeepableBackdrop(sv, v)) { continue; }
            objc_setAssociatedObject(sv, &kKeepBgKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            NSNumber *h = objc_getAssociatedObject(sv, &kOrigHiddenKey);
            if (h) { sv.hidden = [h boolValue]; objc_setAssociatedObject(sv, &kOrigHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            NSNumber *a = objc_getAssociatedObject(sv, &kOrigAlphaKey);
            if (a) { sv.alpha = [a floatValue]; objc_setAssociatedObject(sv, &kOrigAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
            UIColor *c = objc_getAssociatedObject(sv, &kOrigBgColorKey);
            if (c) { sv.backgroundColor = c; objc_setAssociatedObject(sv, &kOrigBgColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        }
    }
    _lvHideBackgroundsRecursive(v);
    LV_PERF_CHECK(kLVCatPerf, 3.0,
                  @"背景层隐藏处理 %@ 耗时 %.1f ms（预算 3ms）",
                  NSStringFromClass([v class]));
}

// 背景隐藏处理不必每帧都做：系统极少自己去复活那些背景层，
// 而这一步要递归整棵子树（现在的通知卡片动辄几百层子视图）。
// 每帧递归 = 下拉动画期间最大的重复开销，降到每 0.2 秒一次；
// 刚挂载/刚换素材这种必须马上正确的时刻走 _lvPrepareHostBackgroundsNow 强制一次。
static void _lvPrepareHostBackgroundsThrottled(UIView *v) {
    if (!v) { return; }
    @try {
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSNumber *last = objc_getAssociatedObject(v, &kBgStampKey);
        if (last && (now - [last doubleValue]) < 0.2) { return; }
        objc_setAssociatedObject(v, &kBgStampKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } @catch (NSException *e) { _lvExcept(__func__, e); }
    _lvPrepareHostBackgrounds(v);
}

// 立刻做一次背景隐藏处理（挂载 / 换素材时用）
static void _lvPrepareHostBackgroundsNow(UIView *v) {
    if (!v) { return; }
    objc_setAssociatedObject(v, &kBgStampKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    _lvPrepareHostBackgrounds(v);
}

// 图片素材是 UIView，同样要插到卡片系统毛玻璃「上面一层」，否则会被毛玻璃盖住
static void _lvInsertImageView(UIView *v, UIImageView *iv) {
    NSUInteger cur = (iv.superview == v) ? [v.subviews indexOfObject:iv] : NSNotFound;
    NSInteger target = 0;
    if (_lvIsCardHostClass(NSStringFromClass([v class]))) {
        NSArray<UIView *> *subs = v.subviews;
        for (NSUInteger i = 0; i < subs.count; i++) {
            UIView *sv = subs[i];
            if (sv == iv) { continue; }
            if (!_lvIsKeepableBackdrop(sv, v)) { continue; }
            NSInteger at = (NSInteger)[subs indexOfObject:sv];
            if (cur != NSNotFound && (NSInteger)cur < at) { target = at; }   // 移除自身后索引 -1
            else { target = at + 1; }
        }
    }
    if (cur != NSNotFound && (NSInteger)cur == target) { return; }
    [iv removeFromSuperview];
    [v insertSubview:iv atIndex:(NSUInteger)target];
}

static void _lvInsertLayer(UIView *v, AVPlayerLayer *l) {
    LV_PERF_BEGIN();
    BOOL isCard = _lvIsCardHostClass(NSStringFromClass([v class]));
    int bg = isCard ? _lvTopFullCoverBackgroundIndex(v) : -1;
    NSUInteger cur = (l.superlayer == v.layer) ? [v.layer.sublayers indexOfObject:l] : NSNotFound;
    unsigned target;
    if (bg < 0) {
        target = 0;
    } else if (cur != NSNotFound && cur < (NSUInteger)bg) {
        target = (unsigned)bg;          // 移除自身后背景层索引会 -1
    } else {
        target = (unsigned)bg + 1;
    }
    if (cur != NSNotFound && cur == target) {
        LV_PERF_CHECK(kLVCatPerf, 2.0,
                      @"视频图层定位 %@ 耗时 %.1f ms（预算 2ms）",
                      NSStringFromClass([v class]));
        return;
    }
    [l removeFromSuperlayer];
    [v.layer insertSublayer:l atIndex:target];
    LV_PERF_CHECK(kLVCatPerf, 2.0,
                  @"视频图层定位 %@ 耗时 %.1f ms（预算 2ms）",
                  NSStringFromClass([v class]));
}

#pragma mark - 按钮素材声音（左滑可见才出声）

// 视图是否「实际可见」：祖先链没有 hidden / alpha≈0，且投影到屏幕上有实际面积
// （iOS16 锁屏不左滑时，选项/清除按钮是被移出屏幕或隐藏的，靠这个判定区分）
static BOOL _lvViewEffectivelyVisible(UIView *v) {
    if (!v) { return NO; }
    @try {
        if (!v.window) { return NO; }
        for (UIView *cur = v; cur; cur = cur.superview) {
            if (cur.hidden || cur.alpha < 0.01) { return NO; }
        }
        CGRect r = [v convertRect:v.bounds toView:nil];
        CGRect screen = [UIScreen mainScreen].bounds;
        CGRect inter = CGRectIntersection(r, screen);
        if (CGRectIsNull(inter)) { return NO; }
        return inter.size.width > 2.0 && inter.size.height > 2.0;
    } @catch (NSException *e) { _lvExcept(__func__, e); return NO; }
}

// —— 统一声音裁定 ——
// 漏声的真正根因就在这一段：旧版只对「单个按钮」做可见性判断，
// 通知卡片 / 实时活动 / 宿主视图 只要 window 还在就无条件 [p play]，
// 卡片划出屏幕、被折叠、锁屏被盖住之后声音照样在跑 —— 用户听到的「漏声」就是这么来的。
// 现在所有挂了素材的视图都归这一个函数管，规则只有三条：
//   ① 锁屏不可见            → 静音 + 暂停
//   ② 视图不可见且没人共用它 → 静音 + 暂停
//   ③ 视图可见              → 按「视频声音」开关决定 muted，并 play
static void _lvApplyAudioPolicy(UIView *v) {
    @try {
        if (!v || !v.window) { return; }   // 没有 window 说明正在被搬动，属瞬时状态，交给整体兜底处理
        NSString *path = objc_getAssociatedObject(v, &kPathKey);
        if (!path.length || _lvPathIsImageAsset(path)) { return; }   // 图片/GIF 本来就没有声音
        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        AVPlayer *p = l.player ?: objc_getAssociatedObject(v, &kPlayerKey);
        if (!p) { return; }
        NSString *cls = NSStringFromClass([v class]);
        NSString *who = _lvIsSingleActionButtonClass(cls)
            ? [NSString stringWithFormat:@"按钮「%@」(%@)", _lvButtonTitle(v) ?: @"无标题", cls]
            : cls;
        if (!_lvEnabled() || !_lvIsLockScreenVisible()) {
            if (p.rate > 0.01) { _lvNote(kLVCatSound, @"%@ 锁屏不可见 → 静音并暂停", who); }
            p.muted = YES;
            [p pause];
            return;
        }
        if (_lvViewEffectivelyVisible(v)) {
            if (_lvPlayerHasOtherVisibleView(p, v)) {
                _lvNote(kLVCatSound, @"%@ 与别的可见卡片共用播放器，声音按共享状态处理", who);
            } else {
                p.muted = !_lvSound();
            }
            [p play];
            return;
        }
        if (_lvPlayerHasOtherVisibleView(p, v)) {
            _lvNote(kLVCatSound, @"%@ 不可见，但播放器被可见卡片共用，保持出声", who);
            return;
        }
        if (p.rate > 0.01) { _lvNote(kLVCatSound, @"%@ 不可见 → 静音并暂停（不再漏声）", who); }
        p.muted = YES;
        [p pause];
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 孤儿播放器兜底：视图被系统回收/复用之后，AVPlayer 可能还被 gAllPlayers 持有着继续播。
// 这一类漏声最难复现，所以干脆用反向规则彻底堵死：
// 只有「至少有一个可见视图正在用它」的播放器才允许出声，其余一律静音并暂停。
// 为避免下拉过程中卡片被临时摘窗导致声音一突一突，留了 0.6 秒宽限期。
static NSMutableDictionary<NSValue *, NSNumber *> *gSeenVisible = nil;
static void _lvEnforceAudioPolicy(void) {
    @try {
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (!gSeenVisible) { gSeenVisible = [NSMutableDictionary dictionary]; }
        BOOL allowAnything = (_lvEnabled() && _lvIsLockScreenVisible());
        NSMutableSet<AVPlayer *> *allowed = [NSMutableSet set];
        if (allowAnything) {
            for (UIView *v in [_lvAttachedTable() allObjects]) {
                if (!_lvViewEffectivelyVisible(v)) { continue; }
                NSString *path = objc_getAssociatedObject(v, &kPathKey);
                if (!path.length || _lvPathIsImageAsset(path)) { continue; }
                AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
                AVPlayer *p = l.player ?: objc_getAssociatedObject(v, &kPlayerKey);
                if (!p) { continue; }
                [allowed addObject:p];
                gSeenVisible[[NSValue valueWithNonretainedObject:p]] = @(now);
            }
        }
        BOOL want = _lvSound();
        for (AVPlayer *p in gAllPlayers) {
            NSValue *pk = [NSValue valueWithNonretainedObject:p];
            if ([allowed containsObject:p]) {
                if (p.muted == want) {   // muted 应当等于 !want，不一致说明有人绕过裁定改过它
                    _lvIssue(kLVCatSound, @"播放器声音状态与开关不一致，已就地纠正（声音开关=%d）", want);
                }
                p.muted = !want;
            } else {
                NSTimeInterval last = [gSeenVisible[pk] doubleValue];
                if (last > 0 && (now - last) < 0.6) { continue; }   // 宽限期内，可能是换卡片的瞬间
                if (p.rate > 0.01) { _lvNote(kLVCatSound, @"没有可见视图在用这个播放器却还在播 → 静音并暂停"); }
                p.muted = YES;
                [p pause];
                [gSeenVisible removeObjectForKey:pk];   // 记录只服务于宽限期，用完就丢，免得无限堆积
            }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// layoutSubviews 会逐帧来，但整套裁定只是「十几个视图 + 几个播放器」，
// 节流到 0.25 秒已经足够快（人耳听不出差别），却能把每帧的开销压到几乎为零。
static NSTimeInterval gAudioPolicyStamp = 0;
static void _lvEnforceAudioPolicyThrottled(void) {
    @try {
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (now - gAudioPolicyStamp < 0.25) { return; }
        gAudioPolicyStamp = now;
        _lvEnforceAudioPolicy();
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvApplyAudioPolicyEverywhere(void) {
    @try {
        for (UIView *v in [_lvAttachedTable() allObjects]) { _lvApplyAudioPolicy(v); }
        _lvEnforceAudioPolicy();
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvAttachWithPath(UIView *v, NSString *path);

// 防挂锁白名单：只允许两类视图挂载素材——
//   1) 通知卡片本体（shortlook / banner / longlook）
//   2) 按钮本身（UIButton 实例 / pill / ctbutton / actionbutton 等单个动作按钮类）
// 其余一切视图（按钮组容器、pillcontent、actionview、content 大视图等）一律禁止，
// 从根源上杜绝「按钮背后还有一个整体视图背景」的问题
static BOOL _lvAllowedToAttach(UIView *v) {
    if (!v) { return NO; }
    @try {
        NSString *cls = NSStringFromClass([v class]);
        if (!cls) { return NO; }
        // 按钮组/动作类容器：一律不允许挂载
        if (_lvIsActionButtonGroupView(cls)) {
            // 例外：类名匹配容器关键词但实际是单个按钮（不含 group 且是按钮类）
            return (_lvIsSingleActionButtonClass(cls) || [v isKindOfClass:[UIButton class]]);
        }
        NSString *low = cls.lowercaseString;
        if ([low containsString:@"shortlook"] || [low containsString:@"banner"] || [low containsString:@"longlook"]) {
            return YES;
        }
        if (_lvIsActivityContentClass(cls)) { return YES; }   // 实时活动内容宿主允许挂主素材
        if (_lvIsActivityHost(v)) { return YES; }             // 已被标记为实时活动可见宿主（PLPlatterView）
        if ([v isKindOfClass:[UIButton class]]) { return YES; }
        if (_lvIsPillButtonClass(cls)) { return YES; }
        if ([low containsString:@"actionbutton"]) { return YES; }
        return NO;
    } @catch (NSException *e) { _lvExcept(__func__, e); return NO; }
}

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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return NO;
}

// 判断某个子孙视图是否属于「按钮区」——三种判据，任一命中即可：
//   1) 已经挂上了独立素材（选项/清除按钮素材），这是最可靠的判据
//   2) 类名命中按钮组 / 单个动作按钮 / UIButton
//   3) 几何特征：内部有两个并排、等尺寸的子视图（按钮组的通用形状）
static BOOL _lvIsButtonAreaView(UIView *sv, UIView *host) {
    (void)host;
    @try {
        if (objc_getAssociatedObject(sv, &kPathKey)) { return YES; }
        NSString *cls = NSStringFromClass([sv class]);
        if (_lvIsActionButtonGroupView(cls) || _lvIsSingleActionButtonClass(cls)) { return YES; }
        if ([sv isKindOfClass:[UIButton class]]) { return YES; }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return NO;
}

// 计算宿主视图上素材背景层应覆盖的区域：
// 扫描整棵子树找出所有「按钮区」候选，取其中最靠上的那个，把背景层裁到它上方，
// 按钮区及下方一律不铺素材（露出系统原样，只有按钮本身显示自己的素材）。
// 找不到按钮区时铺满整个视图。
// 真正的计算：往下遍历整棵子树找「按钮区」，决定素材层裁到哪一行结束。
// 最坏要访问 1200 个节点，所以外面包了一层短时缓存。
static CGRect _lvCoverFrameComputed(UIView *v) {
    CGRect frame = v.bounds;
    if (!v) { return frame; }
    LV_PERF_BEGIN();
    @try {
        CGFloat hostH = v.bounds.size.height;
        if (hostH <= 1.0) { return frame; }
        NSMutableArray<UIView *> *stack = [NSMutableArray array];
        for (UIView *sv in v.subviews) { [stack addObject:sv]; }
        int visited = 0;
        CGFloat bestY = CGFLOAT_MAX;
        UIView *bestView = nil;
        while (stack.count > 0 && visited < 1200) {
            UIView *sv = stack.firstObject;
            [stack removeObjectAtIndex:0];
            visited++;
            BOOL hit = _lvIsButtonAreaView(sv, v);
            // 几何兜底只认下半部分（避免把卡片中部的图标/标题区误判成按钮区）
            if (!hit && hostH > 80.0) {
                CGRect gf = [v convertRect:sv.bounds fromView:sv];
                if (gf.origin.y > hostH * 0.5 && gf.origin.y < hostH - 12.0 && _lvLooksLikeButtonGroup(sv)) {
                    hit = YES;
                }
            }
            if (!hit) {
                for (UIView *c in sv.subviews) { [stack addObject:c]; }
                continue;
            }
            CGRect f = [v convertRect:sv.bounds fromView:sv];
            if (f.size.height < 8.0 || f.size.width < 8.0) {
                for (UIView *c in sv.subviews) { [stack addObject:c]; }
                continue;
            }
            // 只认位于下半部分的按钮区；顶部的小控件（开关、头像等）不参与裁剪
            if (f.origin.y > hostH * 0.15 && f.origin.y < bestY) {
                bestY = f.origin.y;
                bestView = sv;
            }
            for (UIView *c in sv.subviews) { [stack addObject:c]; }
        }
        if (bestView) {
            CGFloat bottom = bestY - 4.0;
            if (bottom >= 8.0 && bottom < frame.size.height) {
                frame.size.height = bottom;
                LV_PERF_CHECK(kLVCatPerf, 4.0,
                              @"背景裁剪计算 %@ 耗时 %.1f ms（预算 4ms）",
                              NSStringFromClass([v class]));
                _lvRestoreBackgroundsRecursive(bestView, 0);   // 清掉历史版本残留的隐藏标记
                _lvLogOnce(NSStringFromClass([v class]),
                           [NSString stringWithFormat:@"背景裁剪: 按钮区 %@ y=%.0f h=%.0f 裁到 h=%.0f",
                            NSStringFromClass([bestView class]), bestY,
                            bestView.bounds.size.height, frame.size.height]);
                return frame;
            }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    LV_PERF_CHECK(kLVCatPerf, 4.0,
                  @"背景裁剪计算 %@ 耗时 %.1f ms（预算 4ms）",
                  NSStringFromClass([v class]));
    return frame;
}

// 带缓存的入口 —— 这里是下拉卡顿最大的一笔开销：
// layoutSubviews 每帧都会调用它，而它原本每帧都要 BFS 扫一遍整棵子树找按钮区，
// 一张普通通知卡片动辄几百个子节点，等于每帧白白全树遍历一次。
// 签名取「bounds 尺寸 + 直接子视图个数」：这两样没变，按钮区位置基本不可能变，
// 直接复用上次算好的 frame；签名变了或超过 0.15 秒才真的重算。
static CGRect _lvCoverFrameForHost(UIView *v) {
    CGRect def = v ? v.bounds : CGRectZero;
    if (!v) { return def; }
    @try {
        NSString *sign = [NSString stringWithFormat:@"%.1f|%.1f|%lu",
                          v.bounds.size.width, v.bounds.size.height,
                          (unsigned long)v.subviews.count];
        NSValue *cached = objc_getAssociatedObject(v, &kCoverKey);
        NSString *oldSign = objc_getAssociatedObject(v, &kCoverSignKey);
        NSNumber *stamp = objc_getAssociatedObject(v, &kCoverStampKey);
        if (cached && oldSign && stamp && [oldSign isEqualToString:sign]) {
            NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
            if ((now - [stamp doubleValue]) < 0.15) { return [cached CGRectValue]; }
        }
        CGRect result = _lvCoverFrameComputed(v);
        NSTimeInterval t = [[NSDate date] timeIntervalSince1970];
        objc_setAssociatedObject(v, &kCoverKey, [NSValue valueWithCGRect:result], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kCoverSignKey, sign, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kCoverStampKey, @(t), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return result;
    } @catch (NSException *e) { _lvExcept(__func__, e); }
    return def;
}

#pragma mark - 可视化调试：给通知视图每一层描边并标注类名

#define kLVDebugTag 20240919
static char kDebugSigKey;
static NSTimeInterval gLastDebugDraw = 0;

static void _lvDebugRemove(UIView *v) {
    if (!v) { return; }
    @try {
        UIView *ov = objc_getAssociatedObject(v, &kDebugKey);
        if (ov) {
            [ov removeFromSuperview];
            objc_setAssociatedObject(v, &kDebugKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(v, &kDebugSigKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for (UIView *sv in [v.subviews copy]) {
            if (sv.tag == kLVDebugTag) { [sv removeFromSuperview]; }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 开关变化时把可能残留的调试覆盖层清干净
static void _lvScanAndRemoveDebugIn(UIView *v, int depth) {
    if (!v || depth > 14) { return; }
    @try {
        for (UIView *sv in [v.subviews copy]) {
            if (sv.tag == kLVDebugTag) { [sv removeFromSuperview]; continue; }
            _lvScanAndRemoveDebugIn(sv, depth + 1);
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvRemoveAllDebugOverlays(void) {
    @try {
        id app = [UIApplication sharedApplication];
        NSArray *wins = nil;
        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) { _lvExcept(__func__, e);}
        for (UIWindow *w in wins) { _lvScanAndRemoveDebugIn(w, 0); }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 关闭插件时彻底还原系统原样：
// 无视任何标记，凡是有备份（hidden/alpha/背景色）的视图一律还原，
// 并清掉插件留在视图上的全部关联标记；配合 _lvDetachAll 使用。
static void _lvForceRestoreAllInView(UIView *v, int depth) {
    if (!v || depth > 30) { return; }
    @try {
        NSNumber *oh = objc_getAssociatedObject(v, &kOrigHiddenKey);
        if (oh) {
            v.hidden = [oh boolValue];
            objc_setAssociatedObject(v, &kOrigHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSNumber *oa = objc_getAssociatedObject(v, &kOrigAlphaKey);
        if (oa) {
            v.alpha = [oa floatValue];
            objc_setAssociatedObject(v, &kOrigAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIColor *ob = objc_getAssociatedObject(v, &kOrigBgColorKey);
        if (ob) {
            v.backgroundColor = ob;
            objc_setAssociatedObject(v, &kOrigBgColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSNumber *oc = objc_getAssociatedObject(v, &kOrigCornerKey);
        if (oc) {
            v.layer.cornerRadius = [oc floatValue];
            objc_setAssociatedObject(v, &kOrigCornerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSNumber *om = objc_getAssociatedObject(v, &kOrigMasksKey);
        if (om) {
            v.layer.masksToBounds = [om boolValue];
            objc_setAssociatedObject(v, &kOrigMasksKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        // 兜底：就算不在挂载清单里，只要视图上还挂着插件素材层就一律拆掉
        AVPlayerLayer *al = objc_getAssociatedObject(v, &kLayerKey);
        if (al) {
            [al removeFromSuperlayer];
            objc_setAssociatedObject(v, &kLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIImageView *aiv = objc_getAssociatedObject(v, &kImgKey);
        if (aiv) {
            [aiv removeFromSuperview];
            objc_setAssociatedObject(v, &kImgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        objc_setAssociatedObject(v, &kHideDoneKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kKeepBgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kPathKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kRecheckKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kKindKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kKindProbeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kExpectedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kExpectedStampKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kCoverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kCoverStampKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kCoverSignKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kBgStampKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(v, &kActivityHostKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        for (UIView *sv in [v.subviews copy]) { _lvForceRestoreAllInView(sv, depth + 1); }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 颜色约定（截图后对照即可定位问题层）：
//   红色粗框 + 红色半透明填充 = 这一层挂了素材（视频/图片）
//   橙色     = 系统背景层（毛玻璃/材质）当前可见
//   蓝色虚线 = 系统背景层已被插件隐藏
//   绿色     = 按钮 / 按钮区
//   青色     = 卡片根视图
//   白色细框 = 其它视图
static void _lvDebugDraw(UIView *root) {
    if (!root) { return; }
    @try {
        if (!_lvDebugOutline()) { _lvDebugRemove(root); return; }

        // 签名不变就不重绘，避免 layoutSubviews 频繁触发时卡顿
        NSMutableString *sig = [NSMutableString stringWithFormat:@"%.0fx%.0f",
                                root.bounds.size.width, root.bounds.size.height];
        NSMutableArray *stack = [NSMutableArray arrayWithObject:@[root, @0]];
        int visited = 0;
        while (stack.count > 0 && visited < 400) {
            NSArray *item = stack.lastObject;
            [stack removeLastObject];
            visited++;
            UIView *sv = item[0];
            int depth = [item[1] intValue];
            if (depth > 9) { continue; }
            NSString *p = objc_getAssociatedObject(sv, &kPathKey);
            [sig appendFormat:@"|%@:%.0f,%.0f,%.0f,%.0f,%d,%@",
             NSStringFromClass([sv class]),
             sv.frame.origin.x, sv.frame.origin.y,
             sv.frame.size.width, sv.frame.size.height,
             (int)sv.hidden, p ?: @"-"];
            if (depth < 9) {
                for (UIView *c in sv.subviews) { [stack addObject:@[c, @(depth + 1)]]; }
            }
        }
        NSString *oldSig = objc_getAssociatedObject(root, &kDebugSigKey);
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        if (oldSig && [oldSig isEqualToString:sig] && now - gLastDebugDraw < 1.0) { return; }
        gLastDebugDraw = now;
        objc_setAssociatedObject(root, &kDebugSigKey, sig, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIView *ov = objc_getAssociatedObject(root, &kDebugKey);
        if (!ov) {
            ov = [[UIView alloc] initWithFrame:root.bounds];
            ov.tag = kLVDebugTag;
            ov.userInteractionEnabled = NO;
            ov.backgroundColor = [UIColor clearColor];
            ov.clipsToBounds = YES;
            objc_setAssociatedObject(root, &kDebugKey, ov, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (ov.superview != root) { [root addSubview:ov]; [root bringSubviewToFront:ov]; }
        ov.frame = root.bounds;
        for (CALayer *l in [[ov.layer sublayers] copy]) { [l removeFromSuperlayer]; }

        CGFloat scale = [UIScreen mainScreen].scale ?: 2.0;
        NSMutableArray *stack2 = [NSMutableArray arrayWithObject:@[root, @0]];
        visited = 0;
        while (stack2.count > 0 && visited < 400) {
            NSArray *item = stack2.lastObject;
            [stack2 removeLastObject];
            visited++;
            UIView *sv = item[0];
            int depth = [item[1] intValue];
            if (depth > 9) { continue; }
            NSString *cls = NSStringFromClass([sv class]);
            CGRect f = [root convertRect:sv.bounds fromView:sv];
            BOOL attached = objc_getAssociatedObject(sv, &kPathKey) != nil;
            BOOL isBg = _lvIsBackgroundView(sv);
            BOOL isBtn = [sv isKindOfClass:[UIButton class]] ||
                         _lvIsSingleActionButtonClass(cls) ||
                         _lvIsActionButtonGroupView(cls) ||
                         _lvIsPillButtonClass(cls);

            UIColor *color = nil;
            CGFloat lw = 1.0;
            UIColor *fill = nil;
            BOOL dashed = NO;
            BOOL wantLabel = NO;
            if (sv == root) {
                color = [UIColor cyanColor]; lw = 2.0; wantLabel = YES;
            } else if (attached) {
                color = [UIColor redColor]; lw = 3.0;
                fill = [[UIColor redColor] colorWithAlphaComponent:0.18];
                wantLabel = YES;
            } else if (isBg) {
                if (sv.hidden || sv.alpha < 0.02) {
                    color = [[UIColor blueColor] colorWithAlphaComponent:0.95];
                    lw = 1.5; dashed = YES; wantLabel = YES;
                } else {
                    color = [UIColor orangeColor]; lw = 2.0; wantLabel = YES;
                }
            } else if (isBtn) {
                color = [UIColor greenColor]; lw = 2.0; wantLabel = YES;
            } else {
                color = [[UIColor whiteColor] colorWithAlphaComponent:0.3]; lw = 1.0;
                wantLabel = (f.size.width > 70.0 && f.size.height > 26.0);
            }

            BOOL drawable = f.size.width > 3.0 && f.size.height > 3.0 && sv.alpha > 0.02;
            if (drawable && (attached || isBg || isBtn || sv == root ||
                             (f.size.width > 40.0 && f.size.height > 20.0))) {
                CAShapeLayer *sl = [CAShapeLayer layer];
                sl.frame = ov.bounds;
                sl.path = [UIBezierPath bezierPathWithRect:f].CGPath;
                sl.strokeColor = color.CGColor;
                sl.lineWidth = lw;
                sl.fillColor = fill ? fill.CGColor : [UIColor clearColor].CGColor;
                if (dashed) { sl.lineDashPattern = @[@3, @2]; }
                [ov.layer addSublayer:sl];

                if (wantLabel) {
                    CATextLayer *tl = [CATextLayer layer];
                    NSString *txt = [NSString stringWithFormat:@"%@ %.0fx%.0f%@",
                                     cls, f.size.width, f.size.height,
                                     attached ? @" ★素材" : @""];
                    tl.string = txt;
                    tl.fontSize = 8.0;
                    tl.foregroundColor = color.CGColor;
                    tl.contentsScale = scale;
                    tl.truncationMode = kCATruncationEnd;
                    tl.frame = CGRectMake(f.origin.x + 2.0, f.origin.y + 1.0,
                                          MIN(f.size.width - 4.0, 240.0), 10.0);
                    [ov.layer addSublayer:tl];
                }
            }
            if (depth < 9) {
                for (UIView *c in sv.subviews) { [stack2 addObject:@[c, @(depth + 1)]]; }
            }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 视图（及其浅层子树）上是否还留着插件的痕迹（素材层 / 备份值）
// 用途：跳过「对没有挂载的视图反复 detach」。旧版对没挂素材的活动内容视图每帧都跑一次
// _lvDetach → 递归整棵子树 restore，下拉动画期间纯粹白白烧 CPU，是掉帧的来源之一
static BOOL _lvHasPluginTraces(UIView *v, int depth) {
    if (!v || depth > 3) { return NO; }
    @try {
        if (objc_getAssociatedObject(v, &kPathKey))         { return YES; }
        if (objc_getAssociatedObject(v, &kLayerKey))        { return YES; }
        if (objc_getAssociatedObject(v, &kImgKey))          { return YES; }
        if (objc_getAssociatedObject(v, &kHideDoneKey))     { return YES; }
        if (objc_getAssociatedObject(v, &kKeepBgKey))       { return YES; }
        if (objc_getAssociatedObject(v, &kOrigHiddenKey))   { return YES; }
        if (objc_getAssociatedObject(v, &kOrigAlphaKey))    { return YES; }
        if (objc_getAssociatedObject(v, &kOrigBgColorKey))  { return YES; }
        if (objc_getAssociatedObject(v, &kOrigCornerKey))   { return YES; }
        if (objc_getAssociatedObject(v, &kOrigMasksKey))    { return YES; }
        if (depth >= 3) { return NO; }
        for (UIView *sv in v.subviews) {
            if (_lvHasPluginTraces(sv, depth + 1)) { return YES; }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return NO;
}

// 统一刷新：每帧更新背景层尺寸，并确保系统毛玻璃/背景层处于隐藏状态
static void _lvRefresh(UIView *v) {
    @try {
        _lvDebugDraw(v);
        if (!_lvEnabled()) {
            _lvDetach(v);
            return;
        }
        NSString *path = objc_getAssociatedObject(v, &kPathKey);
        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        UIImageView *iv = objc_getAssociatedObject(v, &kImgKey);
        // 未挂载素材的视图（如实时活动内容视图本体）保持系统原样，不再隐藏背景层
        if (!path.length || (!l && !iv)) {
            if (_lvHasPluginTraces(v, 0)) { _lvDetach(v); }   // 只有真的留过东西才需要还原
            return;
        }
        // 锁屏下拉动画 / 内容延迟加载可能让首次挂载时的类型判断不准（活动卡片被暂挂成主素材、
        // 或 Now Playing 子视图未就位被误判成普通活动）。这里按「当前真实类型」重算应挂素材，
        // 若与已挂载的不同则重挂，消除「首帧消息视频 → 后变正确视频」的闪烁。
        NSString *expected = _lvExpectedPathForView(v);
        if (expected.length && ![expected isEqualToString:path]) {
            // 「先显示通知视频、随后才跳成自己选的」就是这一步触发的：
            // 首次挂载时类型还没判定准，这里才纠正。记录下来，好定位到底是哪张卡片、哪次回退走岔了。
            _lvIssue(kLVCatFail, @"素材被更正（先看错的再看对的）：%@ 原=%@ 新=%@",
                     _lvDesc(v), path.lastPathComponent, expected.lastPathComponent);
            _lvAttachWithPath(v, expected);
            return;
        }
        if (l && path.length) {
            AVPlayer *p = objc_getAssociatedObject(v, &kPlayerKey);
            if (!p || ![gAllPlayers containsObject:p]) {   // 播放器可能已被重置销毁，需重建
                p = _lvPlayerForPath(path);
                objc_setAssociatedObject(v, &kPlayerKey, p, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (p && l.player != p) { l.player = p; }
            _lvInsertLayer(v, l);
            l.frame = _lvCoverFrameForHost(v);
            l.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
            _lvApplyAudioPolicy(v);            // 可见才响、不可见必须静音暂停：统一裁定，不在这里自己 play
            _lvEnforceAudioPolicyThrottled();  // 顺手把「没人用还在响」的孤儿播放器掐掉
        }
        if (iv) {
            if (iv.superview != v) { _lvInsertImageView(v, iv); }
            iv.frame = _lvCoverFrameForHost(v);
            iv.layer.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
        }
        _lvPrepareHostBackgroundsThrottled(v);
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvAttachWithPath(UIView *v, NSString *path) {
    if (!v || !path.length || !_lvEnabled()) { return; }
    // 防挂锁：白名单以外的视图（按钮组容器等）一律不挂载，并清掉可能的历史残留
    if (!_lvAllowedToAttach(v)) {
        _lvIssue(kLVCatFail, @"白名单拒绝挂载（这个视图不允许挂素材）：%@ 试图挂 %@",
                 _lvDesc(v), path.lastPathComponent);
        _lvDetach(v);
        return;
    }
    @try {
        // 素材路径变了：把旧播放器/图层彻底卸掉再重建，避免同视图堆叠多个素材
        NSString *oldPath = objc_getAssociatedObject(v, &kPathKey);
        if (oldPath.length && ![oldPath isEqualToString:path]) {
            _lvDetach(v);
        }
        objc_setAssociatedObject(v, &kPathKey, path, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        // ===== 图片 / GIF 分支 =====
        if (_lvPathIsImageAsset(path)) {
            AVPlayerLayer *oldL = objc_getAssociatedObject(v, &kLayerKey);
            if (oldL) { [oldL removeFromSuperlayer]; objc_setAssociatedObject(v, &kLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }

            UIImage *img = _lvAnimatedImage(path);
            if (!img) {
                _lvFail(kLVCatAsset, @"图片/GIF 解码失败，请确认文件完整：%@（挂在 %@）",
                        path.lastPathComponent, NSStringFromClass([v class]));
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
                _lvInsertImageView(v, iv);
                [_lvAttachedTable() addObject:v];
                _lvLogOnce(NSStringFromClass(v.class), @"已挂载图片/GIF");
            }
            iv.image = img;
            _lvInsertImageView(v, iv);
            iv.frame = _lvCoverFrameForHost(v);
            iv.alpha = (float)_lvAlpha();
            iv.layer.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;

            if (_lvIsActionButtonGroupView(NSStringFromClass(v.class)) || _lvIsPillButtonClass(NSStringFromClass(v.class))) {
                if (!objc_getAssociatedObject(v, &kOrigMasksKey)) {
                    objc_setAssociatedObject(v, &kOrigMasksKey, @(v.layer.masksToBounds), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                if (!objc_getAssociatedObject(v, &kOrigCornerKey)) {
                    objc_setAssociatedObject(v, &kOrigCornerKey, @(v.layer.cornerRadius), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                v.layer.masksToBounds = YES;
                v.layer.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
            }

            _lvPrepareHostBackgroundsNow(v);
            CGRect coverFrame = iv.frame;
            _lvLogOnce(NSStringFromClass(v.class),
                       [NSString stringWithFormat:@"图片挂载尺寸 %.0fx%.0f 透明度 %.2f",
                        coverFrame.size.width, coverFrame.size.height, _lvAlpha()]);
            return;
        }

        // ===== 视频分支 =====
        AVPlayer *p = objc_getAssociatedObject(v, &kPlayerKey);
        if (!p || ![gAllPlayers containsObject:p]) {   // 播放器可能已被重置销毁，需重建
            p = _lvPlayerForPath(path);
            objc_setAssociatedObject(v, &kPlayerKey, p, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIImageView *oldIv = objc_getAssociatedObject(v, &kImgKey);
        if (oldIv) {
            [oldIv removeFromSuperview];
            objc_setAssociatedObject(v, &kImgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        if (!p) {
            _lvFail(kLVCatFail, @"视频播放器创建不出来，背景挂不上：%@（挂在 %@）",
                    path.lastPathComponent, NSStringFromClass([v class]));
            return;
        }

        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        BOOL freshLayer = NO;
        if (!l) {
            l = [AVPlayerLayer playerLayerWithPlayer:p];
            l.videoGravity = AVLayerVideoGravityResizeAspectFill;
            l.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
            l.masksToBounds = YES;
            l.opacity = 0.0;   // 新建图层先透明，再淡入 —— 素材被更正（活动→播放器）时不至于先黑一块
            objc_setAssociatedObject(v, &kLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            freshLayer = YES;
            _lvLogOnce(NSStringFromClass(v.class), @"已挂载视频");
        }
        if (l.player != p) { l.player = p; }

        _lvInsertLayer(v, l);
        [_lvAttachedTable() addObject:v];
        l.frame = _lvCoverFrameForHost(v);
        l.cornerRadius = _lvCornerEnabled() ? _lvCornerRadius() : 0.0;
        CGFloat targetOpacity = (float)_lvAlpha();
        if (freshLayer) {
            [CATransaction begin];
            [CATransaction setAnimationDuration:0.18];
            [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
            l.opacity = targetOpacity;
            [CATransaction commit];
        } else {
            l.opacity = targetOpacity;
        }
        _lvApplyAudioPolicy(v);   // 挂载完成立刻套用统一裁定：不可见（比如还没左滑出来的按钮）保持静音暂停
        _lvPrepareHostBackgroundsNow(v);
        CGRect coverFrame = l.frame;
        _lvLogOnce(NSStringFromClass(v.class),
                   [NSString stringWithFormat:@"挂载尺寸 %.0fx%.0f 透明度 %.2f",
                    coverFrame.size.width, coverFrame.size.height, _lvAlpha()]);
    } @catch (NSException *e) { _lvExcept(__func__, e);
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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
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
            } @catch (NSException *e) { _lvExcept(__func__, e);}
        }
        // 无障碍标签兜底：部分系统按钮的文字只存在于 accessibilityLabel / identifier
        if ([btn respondsToSelector:@selector(accessibilityLabel)]) {
            @try {
                NSString *t = [btn accessibilityLabel];
                if (t.length) { return t; }
            } @catch (NSException *e) { _lvExcept(__func__, e);}
        }
        if ([btn respondsToSelector:@selector(accessibilityIdentifier)]) {
            @try {
                NSString *t = [btn accessibilityIdentifier];
                if (t.length) { return t; }
            } @catch (NSException *e) { _lvExcept(__func__, e);}
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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return nil;
}

// 按钮组挂载策略（纯标题匹配，不做位置猜测）：
//   标题含「清除/Clear」→ ClearPath；含「选项/Option」→ OptionPath；
//   其他标题（如实时活动的「不允许/允许」）或读不到标题 → 一律不挂素材，保持系统原样
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
            }
            if (path.length) { _lvAttachWithPath(v, path); }
            else { _lvDetach(v); }
            return;
        }

        // —— 情况 2：按钮组容器 ——
        NSArray<UIView *> *buttons = _lvFindPillButtonsInView(v);
        if (buttons.count > 0) {
            _lvDetach(v);   // 关键：清掉容器上可能残留的挂载并恢复其背景，缝隙不再显示视频
            // 保险：向上清理最多 4 层祖先中可能残留的旧版本挂载（只清 action/pill/button 类容器）
            UIView *p = v.superview;
            int up = 0;
            while (p && up < 4) {
                @try {
                    NSString *pc = NSStringFromClass([p class]).lowercaseString ?: @"";
                    if ([pc containsString:@"action"] || [pc containsString:@"pill"] || [pc containsString:@"buttongroup"]) {
                        _lvDetach(p);
                    }
                } @catch (NSException *e) { _lvExcept(__func__, e);}
                p = p.superview;
                up++;
            }
            NSMutableArray<NSString *> *titles = [NSMutableArray array];
            for (NSUInteger i = 0; i < buttons.count; i++) {
                UIView *sv = buttons[i];
                NSString *lowTitle = _lvButtonTitle(sv).lowercaseString;
                [titles addObject:[NSString stringWithFormat:@"%@(%@)",
                                   NSStringFromClass([sv class]), lowTitle ?: @"无标题"]];
                NSString *path = nil;
                if ([lowTitle containsString:@"清除"] || [lowTitle containsString:@"clear"]) {
                    path = _lvClearPath();
                } else if ([lowTitle containsString:@"选项"] || [lowTitle containsString:@"option"]) {
                    path = _lvOptionPath();
                } else {
                    // 不做位置猜测：标题不匹配的按钮一律不挂素材，保持系统原样
                    path = nil;
                }
                if (path.length) { _lvAttachWithPath(sv, path); }
                else { _lvDetach(sv); }
            }
            _lvLogOnce(NSStringFromClass([v class]),
                       [NSString stringWithFormat:@"按钮组识别: %@", [titles componentsJoinedByString:@" | "]]);
            // 按钮区一出现就强制导出完整层级（覆盖按钮所在整条通知），定位按钮下方多余视图
            _lvDumpHierarchy(_lvBetterDumpRoot(v), YES);
        } else {
            _lvDetach(v);   // 找不到单个按钮也不给容器挂背景
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

#pragma mark - 卸载

// 还原系统背景：不再依赖 kHideDoneKey 标记，凡是有备份值的一律还原，
// 并且无条件往下递归（历史版本残留、嵌套层的隐藏都能一次清干净）
static void _lvRestoreBackgroundsRecursive(UIView *v, int depth) {
    if (!v || depth > 30) return;
    @try {
        objc_setAssociatedObject(v, &kHideDoneKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        NSNumber *origHidden = objc_getAssociatedObject(v, &kOrigHiddenKey);
        if (origHidden) {
            v.hidden = [origHidden boolValue];
            objc_setAssociatedObject(v, &kOrigHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSNumber *origAlpha = objc_getAssociatedObject(v, &kOrigAlphaKey);
        if (origAlpha) {
            v.alpha = [origAlpha floatValue];
            objc_setAssociatedObject(v, &kOrigAlphaKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        UIColor *origBg = objc_getAssociatedObject(v, &kOrigBgColorKey);
        if (origBg) {
            v.backgroundColor = origBg;
            objc_setAssociatedObject(v, &kOrigBgColorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSNumber *origCorner = objc_getAssociatedObject(v, &kOrigCornerKey);
        if (origCorner) {
            v.layer.cornerRadius = [origCorner floatValue];
            objc_setAssociatedObject(v, &kOrigCornerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        NSNumber *origMasks = objc_getAssociatedObject(v, &kOrigMasksKey);
        if (origMasks) {
            v.layer.masksToBounds = [origMasks boolValue];
            objc_setAssociatedObject(v, &kOrigMasksKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        for (UIView *sv in [v.subviews copy]) { _lvRestoreBackgroundsRecursive(sv, depth + 1); }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvDetach(UIView *v) {
    if (!v) { return; }
    @try {
        // 释放这个视图对播放器的一次引用（共享播放器需归零才真正销毁）
        AVPlayer *p = objc_getAssociatedObject(v, &kPlayerKey);
        if (p) { _lvReleasePlayerRef(p); }
        objc_setAssociatedObject(v, &kPlayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
        if (l) { [l removeFromSuperlayer]; objc_setAssociatedObject(v, &kLayerKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        UIImageView *iv = objc_getAssociatedObject(v, &kImgKey);
        if (iv) { [iv removeFromSuperview]; objc_setAssociatedObject(v, &kImgKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        objc_setAssociatedObject(v, &kPathKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // 注意：这里绝不清除 kActivityHostKey。
        // 素材切换（活动→播放器）时 _lvAttachWithPath 会先 detach 再重挂，若把宿主标记清掉，
        // 切完之后 PLPlatterView 就不再触发 _lvRefresh，后续连尺寸同步都会断掉。
        // 需要在关闭插件时清理的话，请走 _lvDetachAll / _lvForceRestoreAllInView。
        _lvRestoreBackgroundsRecursive(v, 0);
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvDetachAll(void) {
    @try {
        for (UIView *v in [_lvAttachedTable() allObjects]) {
            objc_setAssociatedObject(v, &kActivityHostKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);   // 关闭插件：彻底摘掉宿主标记
            objc_setAssociatedObject(v, &kKindKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(v, &kKindProbeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(v, &kExpectedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(v, &kExpectedStampKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(v, &kCoverKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(v, &kCoverStampKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(v, &kCoverSignKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(v, &kBgStampKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            _lvDetach(v);
        }
        [_lvAttachedTable() removeAllObjects];
    } @catch (NSException *e) { _lvExcept(__func__, e);}
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
        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) { _lvExcept(__func__, e);}
        for (UIWindow *w in wins) {
            if (_lvIsLockScreenWindow(w)) { return YES; }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
    return _lvHasLockScreenWindow();
}

#pragma mark - 实时活动：类型判定与延迟复核

// 类型复核的时间点（秒）。实时活动的内容由 App 端异步渲染，
// 下拉那一瞬间子视图（媒体控件）通常还没到位 —— 旧版只派发到「下一轮 runloop」就完事，
// 结果播放器长期被判成普通实时活动，永远用不上播放器素材。
static NSArray<NSNumber *> *_lvRecheckDelays(void) {
    static NSArray<NSNumber *> *d = nil;
    if (!d) { d = @[@0.08, @0.22, @0.5, @1.0, @1.8]; }
    return d;
}

static void _lvScheduleActivityRecheck(UIView *v) {
    @try {
        if (!v) { return; }
        NSArray<NSNumber *> *delays = _lvRecheckDelays();
        NSInteger idx = [objc_getAssociatedObject(v, &kRecheckKey) integerValue];
        if (idx < 0) { idx = 0; }
        if (idx >= (NSInteger)delays.count) { return; }   // 次数用尽：维持现状，不再派发
        objc_setAssociatedObject(v, &kRecheckKey, @(idx + 1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        double delay = [delays[idx] doubleValue];
        __weak UIView *weakV = v;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            @try {
                UIView *vv = weakV;
                if (!vv || !vv.window) { return; }
                if (!_lvEnabled() || !_lvIsLockScreenVisible()) { return; }
                _lvOnMatch(vv);
            } @catch (NSException *e) { _lvExcept(__func__, e);}
        });
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvHandleActivityMatch(UIView *v) {
    if (!v) { return; }
    @try {
        if (_lvIsActivityAuthorizationAlert(v)) { _lvDetach(v); return; }   // 授权弹窗保持系统原样

        UIView *host = _lvFindActivityPlatterHost(v) ?: v;
        if (host != v) {
            objc_setAssociatedObject(host, &kActivityHostKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }

        _lvDumpActivityStructureOnce(v);   // 真实子视图结构写进日志：日后补准「播放器」判据全靠它
        BOOL loaded = NO;
        LVActivityKind kind = LVActivityKindUnknown;
        NSInteger posRule = _lvPlayerPosRule();
        if (posRule != 0) { kind = _lvKindByPosition(v, posRule); }
        if (kind == LVActivityKindUnknown) { kind = _lvDetectKindIn(host, &loaded); }
        if (kind == LVActivityKindUnknown) {
            // 内容还没加载完 —— 先什么都别挂。
            // 旧版这时候会按「普通活动」挂实时活动素材，素材没设就一路回退到主素材，
            // 于是下拉第一时间看到的是「通知消息视频」，等媒体控件加载完才跳成自己选的视频。
            // 宁可多等几十毫秒，也不要先给用户看一版错的。
            NSInteger idx = [objc_getAssociatedObject(v, &kRecheckKey) integerValue];
            if (idx >= (NSInteger)_lvRecheckDelays().count) {
                // 兜底：内容始终没渲染过来（某些 App 的 Live Activity 天生很单薄），
                // 次数用尽后按普通实时活动处理，别让卡片一直没背景
                kind = LVActivityKindGeneral;
                _lvIssue(kLVCatActivity, @"活动类型始终判不出来（已复核 %ld 次），已按普通实时活动处理：%@",
                         (long)idx, _lvDesc(v));
            } else {
                _lvNote(kLVCatActivity, @"实时活动内容还没渲染出来，先不挂素材，安排第 %ld 次复核：%@",
                        (long)(idx + 1), _lvDesc(v));
                _lvScheduleActivityRecheck(v);
                return;
            }
        }
        objc_setAssociatedObject(v, &kKindKey, @(kind), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSString *p = _lvResolvedPathForKind(kind);
        _lvNote(kLVCatActivity, @"类型判定=%@ → 素材=%@ （%@）",
                kind == LVActivityKindNowPlaying ? @"播放器" : @"普通活动",
                p.lastPathComponent ?: @"(无素材)", NSStringFromClass([v class]));
        if (p.length) { _lvAttachWithPath(host, p); }
        else {
            _lvFail(kLVCatAsset, @"识别出了活动卡片，但找不到对应素材（会保持系统原样）：%@", _lvDesc(host));
            _lvDetach(host);
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvOnMatch(UIView *v) {
    _lvLogOnce(NSStringFromClass(v.class), @"命中通知视图");
    _lvDebugDraw(v);
    _lvDumpHierarchy(_lvBetterDumpRoot(v), NO);
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
    } else if (_lvIsActivityContentClass(cls)) {
        _lvHandleActivityMatch(v);       // 实时活动 / Now Playing：先判类型再挂
    } else if (_lvIsActivityHost(v)) {
        // 关键修复：活动宿主（PLPlatterView）被兜底 hook 命中时，绝不能再退化成主素材。
        // 旧版这里落到 else → _lvAttach(host) → 直接挂「通知消息视频」，
        // 把刚刚挂好的活动/播放器素材顶掉 —— 就是用户看到的「下拉先出通知视频，随后才跳成选的那个」。
        NSString *p = _lvExpectedPathForView(v);
        if (p.length) {
            _lvAttachWithPath(v, p);
        } else {
            _lvNote(kLVCatActivity, @"活动宿主还没拿到类型，安排复核（不再退化成主素材）：%@", _lvDesc(v));
            _lvScheduleActivityRecheck(_lvFindActivityContentInHost(v) ?: v);
        }
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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}
- (void)layoutSubviews {
    %orig;
    @try { _lvRefresh((UIView *)self); } @catch (NSException *e) { _lvExcept(__func__, e);}
}
%end
%end

#pragma mark - 全局 hook（UIView 级别兜底）

static void (*_orig_didMoveToWindow)(UIView *, SEL);
static void _lv_didMoveToWindow(UIView *self, SEL _cmd) {
    _orig_didMoveToWindow(self, _cmd);
    @try {
        if (self.window && _lvIsNotificationView(self)) { _lvOnMatch(self); }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void (*_orig_layoutSubviews)(UIView *, SEL);
static void _lv_layoutSubviews(UIView *self, SEL _cmd) {
    _orig_layoutSubviews(self, _cmd);
    @try {
        if (_lvIsNotificationView(self) && self.window) {
            LV_PERF_BEGIN();
            _lvRefresh(self);
            LV_PERF_CHECK(kLVCatPerf, 8.0,
                          @"layoutSubviews 刷新 %@ 耗时 %.1f ms（预算 8ms，超过一帧就是掉帧来源）",
                          NSStringFromClass([self class]));
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
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
            if (!_lvEnabled() || !path.length) { return; }
            AVPlayer *p = objc_getAssociatedObject(v, &kPlayerKey);
            if (!p) {
                p = _lvPlayerForPath(path);
                objc_setAssociatedObject(v, &kPlayerKey, p, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (p) {
                AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
                if (!l) {
                    l = [AVPlayerLayer playerLayerWithPlayer:p];
                    l.videoGravity = AVLayerVideoGravityResizeAspectFill;
                    objc_setAssociatedObject(v, &kLayerKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                if (l.player != p) { l.player = p; }
                l.frame = v.bounds;
                // 图层已经在层级里时不要再 add —— addSublayer 会把它挪到最上层，
                // 锁屏每滑一次 didMoveToWindow 触发一次，壁纸素材就会盖住本该在它上面的东西
                if (l.superlayer != v.layer) { [v.layer addSublayer:l]; }
                [_lvAttachedTable() addObject:v];
                [p play];
            }
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

%end
%end

#pragma mark - 设置变化回调

static void _lvPollTick(void);
static void _lvStartPollTimer(void);
static void _lvStopPollTimer(void);

static void _lvFlushLogCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                const void *object, CFDictionaryRef userInfo) {
    @try { _lvLogFlushNowSync(); } @catch (NSException *e) { }
}

static void _lvPrefsChanged(CFNotificationCenterRef center,
                            void *observer,
                            CFStringRef name,
                            const void *object,
                                        CFDictionaryRef userInfo) {
    @try {
        // 设置刚被改写：立刻丢掉偏好缓存 —— 否则下一帧还在用旧值（也算是「失效」的一种表现）
        _lvPrefsInvalidate();
        _lvNote(kLVCatPrefs, @"收到设置变更通知");
        // 「实时活动/播放器」素材或区分方式改了：立刻让卡片上的判定缓存失效，下一帧就重算，
        // 否则用户改完设置要等卡片重新出现才生效（看起来就像设置「失效」了）
        for (UIView *v in [_lvAttachedTable() allObjects]) {
            objc_setAssociatedObject(v, &kExpectedStampKey, @0, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(v, &kKindProbeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        BOOL nowEnabled = _lvEnabled();
        // 可视化调试开关翻转时，先把残留的描边覆盖层清干净
        dispatch_async(dispatch_get_main_queue(), ^{
            @try { if (!_lvDebugOutline()) { _lvRemoveAllDebugOverlays(); } } @catch (NSException *e) { _lvExcept(__func__, e);}
        });
        if (nowEnabled != gWasEnabled) {
            gWasEnabled = nowEnabled;
            if (!nowEnabled) {
                // 关闭：卸载全部素材层 → 整棵视图树强制还原系统原样 → 清调试覆盖层 → 释放播放器
                _lvDetachAll();
                dispatch_async(dispatch_get_main_queue(), ^{
                    @try {
                        id app = [UIApplication sharedApplication];
                        NSArray *wins = nil;
                        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) { _lvExcept(__func__, e);}
                        for (UIWindow *w in wins) {
                            _lvForceRestoreAllInView(w, 0);
                            _lvScanAndRemoveDebugIn(w, 0);
                        }
                    } @catch (NSException *e) { _lvExcept(__func__, e);}
                });
                _lvResetAllPlayers();   // 直接释放全部播放器，省电省内存
                _lvStopPollTimer();     // 关掉轮询，彻底不再碰系统视图
                return;
            }
            _lvLog(@"启用=开：立即重新挂载");
            _lvStartPollTimer();
            dispatch_async(dispatch_get_main_queue(), ^{
                @try { _lvPollTick(); } @catch (NSException *e) { _lvExcept(__func__, e);}
            });
            return;
        }

        // 声音变化同步到所有播放器
        BOOL want = _lvSound();
        for (AVPlayer *p in gAllPlayers) {
            p.muted = !want;
            _lvAllowAutoLockForPlayer(p);
        }
        _lvNote(kLVCatSound, @"声音开关=%d，已同步 %lu 个播放器", want, (unsigned long)gAllPlayers.count);
        _lvApplyAudioPolicyEverywhere();   // 按钮素材立刻按可见性修正，不漏声

        // 收集当前激活的 path
        NSMutableSet<NSString *> *active = [NSMutableSet set];
        NSString *main = _lvPath();
        NSString *opt = _lvOptionPath();
        NSString *clr = _lvClearPath();
        NSString *act = _lvActivityPath();
        NSString *play = _lvPlayerPath();
        if (main.length) [active addObject:main];
        if (opt.length)  [active addObject:opt];
        if (clr.length)  [active addObject:clr];
        if (act.length)  [active addObject:act];
        if (play.length) [active addObject:play];

        // 素材路径发生变化：彻底重置全部播放器并重新挂载，避免旧播放器残留导致卡住或不同步
        if (!gLastActivePaths || ![active isEqualToSet:gLastActivePaths]) {
            gLastActivePaths = [active copy];
            _lvResetAllPlayers();
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            @try { _lvPollTick(); } @catch (NSException *e) { _lvExcept(__func__, e);}
        });
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

#pragma mark - 轮询扫描

static NSTimer *gPollTimer = nil;

// 轮询只在启用时跑：关闭插件直接停掉定时器，省电、也避免误挂载
static void _lvStartPollTimer(void) {
    @try {
        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{ _lvStartPollTimer(); });
            return;
        }
        if (gPollTimer) { return; }
        gPollTimer = [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer *t) {
            @try { _lvPollTick(); } @catch (NSException *e) { _lvExcept(__func__, e);}
        }];
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

static void _lvStopPollTimer(void) {
    @try {
        if (![NSThread isMainThread]) {
            dispatch_async(dispatch_get_main_queue(), ^{ _lvStopPollTimer(); });
            return;
        }
        if (gPollTimer) { [gPollTimer invalidate]; gPollTimer = nil; }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 轮询扫描命中判断 —— 与 _lvIsNotificationView 保持完全一致。
// 必须排除 content 容器：NCNotificationLongLookContentView 这类视图包含卡片+按钮区，
// 若被挂载会铺满整个区域，导致按钮组缝隙露出主素材
static BOOL _lvIsCardClass(NSString *cls) {
    if (!cls) { return NO; }
    if (_lvIsActionButtonGroupView(cls)) return YES;
    if (_lvIsActivityContentClass(cls)) return YES;   // 实时活动内容宿主视同卡片，挂主素材
    NSString *low = cls.lowercaseString;
    if (![low containsString:@"notif"]) { return NO; }
    if ([low containsString:@"stackdimming"]) { return NO; }
    if ([low containsString:@"header"])       { return NO; }
    if ([low containsString:@"listview"])     { return NO; }
    if ([low containsString:@"sectionlist"])  { return NO; }
    if ([low containsString:@"listcell"])     { return NO; }
    if ([low containsString:@"content"])      { return NO; }
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
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 清理历史版本残留的非法挂载：
// 视图带挂载记录但不在白名单内（例如旧版本挂在按钮组容器 / content 大视图上）——
// 一律卸载，防止按钮区露出素材
static void _lvCleanupStaleAttachments(void) {
    @try {
        NSMutableArray<UIView *> *stale = [NSMutableArray array];
        NSHashTable<UIView *> *table = _lvAttachedTable();
        for (UIView *v in [table allObjects]) {
            if (!v || !v.window) { continue; }
            if (_lvAllowedToAttach(v)) { continue; }   // 白名单内的合法挂载点
            [stale addObject:v];
        }
        for (UIView *v in stale) {
            _lvLog([NSString stringWithFormat:@"清理残留挂载: %@", NSStringFromClass([v class])]);
            _lvDetach(v);
            [table removeObject:v];
        }
    } @catch (NSException *e) { _lvExcept(__func__, e);}
}

// 运行时体检：每轮轮询做一次，专门抓「声音」和「失效」两类问题。
// 这些状态平时没有任何上报渠道，出问题只能靠用户口述；
// 这里直接把当时的真实状态（静音、播放速率、图层是否还在、播放器是否报错）写进日志。
static NSInteger gPollRounds = 0;
static void _lvAuditRuntime(void) {
    if (!_lvLogging()) { return; }
    @try {
        NSArray<UIView *> *views = [_lvAttachedTable() allObjects];
        BOOL wantSound = _lvSound();
        if (views.count == 0) {
            _lvIssue(kLVCatFail, @"当前没有任何视图挂着素材（卡片背景会保持系统原样）播放器数=%lu",
                     (unsigned long)gAllPlayers.count);
        }
        for (UIView *v in views) {
            NSString *path = objc_getAssociatedObject(v, &kPathKey);
            if (!path.length) { continue; }
            NSString *cls = NSStringFromClass([v class]);
            NSString *name = path.lastPathComponent ?: path;
            if (_lvPathIsImageAsset(path)) {
                UIImageView *iv = objc_getAssociatedObject(v, &kImgKey);
                if (!iv) { _lvFail(kLVCatFail, @"图片素材丢了图片视图：%@ / %@", cls, name); }
                else if (iv.superview != v) { _lvIssue(kLVCatFail, @"图片视图被系统摘掉了，下次刷新会重新插入：%@", cls); }
                continue;
            }
            AVPlayerLayer *l = objc_getAssociatedObject(v, &kLayerKey);
            AVPlayer *p = l.player ?: objc_getAssociatedObject(v, &kPlayerKey);
            if (!p) {
                _lvFail(kLVCatFail, @"挂了素材却没有可用播放器：%@ / %@", cls, name);
                continue;
            }
            if (l && l.superlayer != v.layer) {
                _lvIssue(kLVCatFail, @"视频图层被系统摘掉了，下次刷新会重新插入：%@ / %@", cls, name);
            }
            if (![gAllPlayers containsObject:p]) {
                _lvFail(kLVCatFail, @"播放器已销毁却仍挂在视图上：%@ / %@", cls, name);
            }
            if (p.status == AVPlayerStatusFailed || p.error) {
                _lvFail(kLVCatFail, @"播放器状态异常 status=%ld 错误=%@（%@）",
                        (long)p.status, p.error ?: (id)@"(无详细信息)", name);
            }
            if (p.currentItem.error) {
                _lvFail(kLVCatFail, @"视频轨道错误：%@（%@）", p.currentItem.error, name);
            }
            BOOL vis = _lvViewEffectivelyVisible(v);
            BOOL shared = _lvPlayerHasOtherVisibleView(p, v);
            if (vis) {
                if (p.rate < 0.01) {
                    _lvIssue(kLVCatFail, @"卡片可见但画面没动 rate=%.2f：%@ / %@", p.rate, cls, name);
                }
                if (!shared && p.muted != !wantSound) {
                    _lvIssue(kLVCatSound, @"声音开关=%d 但播放器实际静音=%d：%@", wantSound, p.muted, cls);
                }
            } else if (!shared) {
                if (p.rate > 0.01) { _lvIssue(kLVCatSound, @"卡片不可见却还在播放（会漏声音）：%@ / %@", cls, name); }
                if (wantSound && !p.muted) { _lvIssue(kLVCatSound, @"卡片不可见但没静音：%@", cls); }
            } else {
                _lvNote(kLVCatSound, @"播放器被多视图共用，按共享状态处理声音：%@ / %@", cls, name);
            }
        }
        if (gPollRounds % 40 == 0) {
            _lvNote(kLVCatPerf, @"运行概况：挂载视图=%lu 播放器=%lu 共享缓存=%lu",
                    (unsigned long)views.count, (unsigned long)gAllPlayers.count,
                    (unsigned long)gPlayerByPath.count);
        }
    } @catch (NSException *e) { _lvExcept(__func__, e); }
}

static void _lvPollTick(void) {
    @try {
        LV_PERF_BEGIN();
        gPollRounds++;
        if (!_lvEnabled()) {
            _lvPauseAllPlayers();
            return;
        }
        if (!_lvIsLockScreenVisible()) {
            _lvPauseAllPlayers();
            return;
        }
        _lvCleanupStaleAttachments();   // 清理旧版本挂在按钮区大视图上的残留
        _lvAuditRuntime();              // 体检：把「声音 / 失效」的真实状态写进日志
        id app = [UIApplication sharedApplication];
        NSArray *wins = nil;
        @try { wins = [app valueForKey:@"windows"]; } @catch (NSException *e) { _lvExcept(__func__, e);}
        BOOL foundAnyCard = NO;
        for (UIWindow *w in wins) {
            if (w.hidden || w.alpha <= 0.01) { continue; }
            BOOL found = NO;
            _lvScanAndAttach(w, &found);
            if (found) { foundAnyCard = YES; }
        }
        if (foundAnyCard) { _lvPlayAllVisiblePlayers(); }   // 只是「补播」，最终声音状态仍由下面的统一裁定决定
        else {
            _lvPauseAllPlayers();
            if (gPollRounds % 20 == 0) { _lvNote(kLVCatFail, @"连续 %ld 轮轮询都没找到任何通知卡片", (long)gPollRounds); }
        }
        _lvApplyAudioPolicyEverywhere();   // 所有视图：不可见的一律静音暂停，绝不漏声
        // 预算放宽到 30ms：轮询每 1.5 秒才走一次，它并不落在下拉动画的某一帧里，
        // 真正的掉帧取决于单帧内的刷新耗时，这里报得太紧只会让日志充满噪音。
        LV_PERF_CHECK(kLVCatPerf, 30.0,
                      @"每轮轮询扫描（遍历全部窗口找卡片）耗时 %.1f ms（预算 30ms）");
    } @catch (NSException *e) { _lvExcept(__func__, e);}
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
                if (_lvEnabled()) {
                    _lvStartPollTimer();
                    _lvLog(@"轮询扫描已启动(每1.5秒)");
                } else {
                    _lvLog(@"插件默认关闭：轮询未启动");
                }
            } @catch (NSException *e) { _lvExcept(__func__, e);}
        });

        gAllPlayers = [NSMutableSet set];
        gObserverMap = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory];
        gAuxObserverMap = [NSMapTable mapTableWithKeyOptions:NSMapTableStrongMemory valueOptions:NSMapTableStrongMemory];
        gPlayerByPath = [NSMutableDictionary dictionary];
        gRefCount = [NSMutableDictionary dictionary];
        if (!_lvAttachedViews) { _lvAttachedViews = [NSHashTable weakObjectsHashTable]; }

        // 不再在 ctor 里预创建播放器：等视图出现时再按需创建；同一路径的多个视图会复用同一个 AVPlayer（引用计数管理）

        gWasEnabled = _lvEnabled();

        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        _lvPrefsChanged,
                                        kLVNotify,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        // 设置面板导出日志前会发这个通知：先把缓冲区刷到磁盘，保证导出的是完整内容
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        _lvFlushLogCallback,
                                        kLVFlushLog,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);

        _lvLog([NSString stringWithFormat:@"状态: 启用=%d 声音=%d 主素材=%@ 选项=%@ 清除=%@ 实时活动=%@ 播放器=%@ 目录存在=%d",
                _lvEnabled(), _lvSound(), _lvPath() ?: @"(无)", _lvOptionPath() ?: @"(无)", _lvClearPath() ?: @"(无)",
                _lvActivityPath() ?: @"(无)", _lvPlayerPath() ?: @"(无)",
                [[NSFileManager defaultManager] fileExistsAtPath:kLVVideoDir]]);
        _lvLog([NSString stringWithFormat:@"plist文件内容: %@", _lvPrefs()]);
        _lvLog([NSString stringWithFormat:@"===== %@ 加载完成（统一声音裁定（不再漏声） + 实时活动/播放器分离（含手动指定） + 偏好读取去每帧磁盘同步 + 播放器失败监听 + 运行时体检） =====", kLVVersion]);
    } @catch (NSException *e) { _lvExcept(__func__, e);
        _lvLog([NSString stringWithFormat:@"ctor 异常: %@", e]);
    }
}
