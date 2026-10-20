#pragma once
#import <Foundation/Foundation.h>
// 2.39: per-channel tuning (每个视频背景自己的一套参数).
//
// Settings shows one row per channel under 「自定义参数」; tapping it pushes a page
// built from LMVTuneGroupsForTarget(). Every value is stored under
//   Tune.<target>.<key>
// in the tweak's own preference domain, so two channels never share a value.
//
// This header is compiled into both the dylib (SpringBoard) and the preference
// bundle, so everything here is `static` and depends only on Foundation.

static NSString *const LMVTuneDomain = @"com.minis.lockmessagevideo";

// The channels, in the same order Settings lists them.
static inline NSArray<NSDictionary *> *LMVTuneTargets(void) {
    return @[
        @{@"id":@"Lock",          @"name":@"锁屏背景视频"},
        @{@"id":@"Desktop",       @"name":@"桌面背景视频"},
        @{@"id":@"ControlCenter", @"name":@"控制中心"},
        @{@"id":@"HomeMenu",      @"name":@"主屏菜单"},
        @{@"id":@"SquidPanel",    @"name":@"鱿鱼面板"},
        @{@"id":@"AT",            @"name":@"AT 面板"},
        @{@"id":@"CV",            @"name":@"CopyVault 面板"},
        @{@"id":@"Myrtle",        @"name":@"Myrtle 面板"},
        @{@"id":@"PA",            @"name":@"电话助手"},
        @{@"id":@"GS",            @"name":@"GlassSuiteX 弹窗"},
        @{@"id":@"CCBorder",      @"name":@"CCBorder 长按菜单"},
        @{@"id":@"CopyLogX",      @"name":@"CopyLogX 面板"},
        @{@"id":@"Bubble",        @"name":@"悬浮球"},
    ];
}
static inline NSString *LMVTuneTargetName(NSString *target) {
    for (NSDictionary *item in LMVTuneTargets())
        if ([item[@"id"] isEqualToString:target]) return item[@"name"];
    return target ?: @"";
}

// One parameter. `choices`/`values` are only used by enum rows (PSButtonCell);
// everything else is a slider between min and max.
static inline NSDictionary *LMVTuneParam(NSString *key,
                                  NSString *title,
                                  NSInteger minValue,
                                  NSInteger maxValue,
                                  NSInteger defaultValue,
                                  NSArray *choices,
                                  NSArray *values) {
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    p[@"key"] = key; p[@"title"] = title;
    p[@"min"] = @(minValue); p[@"max"] = @(maxValue); p[@"def"] = @(defaultValue);
    if (choices) p[@"choices"] = choices;
    if (values) p[@"values"] = values;
    return p;
}

// Four groups for every video channel. The bubble has no video, so it gets its
// own (much shorter) list - showing "帧率上限" for a floating ball would be noise.
// Built once: LMVTuneValue() runs on the SpringBoard main thread several times a
// second, so rebuilding fourteen dictionaries per read would be silly.
static inline NSArray<NSDictionary *> *LMVTuneBubbleGroups(void) {
    static NSArray *groups; static dispatch_once_t once;
    dispatch_once(&once, ^{
        groups = @[
            @{@"title":@"悬浮球", @"params":@[
                // Only what the overlay actually reads: size and opacity.
                LMVTuneParam(@"BubbleSize", @"尺寸 (24~128)", 24, 128, 52, nil, nil),
                LMVTuneParam(@"BubbleAlpha", @"不透明度 (%, 20~100)", 20, 100, 100, nil, nil),
            ]},
        ];
    });
    return groups;
}
// 2.41: only show parameters this channel actually reads. A switch that changes
// nothing is worse than no switch.
static inline BOOL LMVTuneHasTimer(NSString *target) {
    return [@[@"AT",@"CCBorder",@"CV",@"Myrtle",@"PA",@"SquidPanel",@"GS",@"CopyLogX"] containsObject:target];
}
static inline BOOL LMVTuneHasSheetDelay(NSString *target) {
    return [@[@"GS",@"CopyLogX"] containsObject:target];
}
static inline NSArray<NSDictionary *> *LMVTuneGroupsForTarget(NSString *target) {
    if ([target isEqualToString:@"Bubble"]) return LMVTuneBubbleGroups();
    NSMutableArray *groups = [NSMutableArray array];
    if (LMVTuneHasTimer(target)) {
        NSMutableArray *probe = [NSMutableArray array];
        [probe addObject:LMVTuneParam(@"ProbeHz", @"检测频率 (Hz, 1~60)", 1, 60, 5, nil, nil)];
        if (LMVTuneHasSheetDelay(target)) {
            [probe addObject:LMVTuneParam(@"ShowDelayMs", @"出现延迟 (ms, 0~1000)", 0, 1000, 0, nil, nil)];
            [probe addObject:LMVTuneParam(@"HideDelayMs", @"关闭延迟 (ms, 0~2000)", 0, 2000, 0, nil, nil)];
            [probe addObject:LMVTuneParam(@"HookThrottleMs", @"钩子节流 (ms, 0~200)", 0, 200, 50, nil, nil)];
        }
        [groups addObject:@{@"title":@"探测", @"params":probe}];
    }
    static NSArray *rest; static dispatch_once_t once;
    dispatch_once(&once, ^{
    rest = @[
        @{@"title":@"播放", @"params":@[
            // 2.41: free numbers, not preset choices. 0 fps = keep the source rate.
            LMVTuneParam(@"MaxFPS", @"帧率上限 (0=原始, 1~120)", 0, 120, 0, nil, nil),
            LMVTuneParam(@"RatePercent", @"播放速度 (%, 10~400)", 10, 400, 100, nil, nil),
            LMVTuneParam(@"Gravity", @"填充方式", 0, 1, 0, @[@"填充", @"适应"], @[@0, @1]),
            LMVTuneParam(@"LoopCount", @"循环次数 (0=无限, 1~99)", 0, 99, 0, nil, nil),
        ]},
        @{@"title":@"可见性", @"params":@[
            LMVTuneParam(@"HiddenAction", @"面板不可见", 0, 2, 0, @[@"暂停", @"继续", @"暂停并隐藏"], @[@0, @1, @2]),
            LMVTuneParam(@"OccludedAction", @"被完全遮挡", 0, 1, 0, @[@"暂停", @"继续"], @[@0, @1]),
            LMVTuneParam(@"LockedAction", @"锁屏 / 息屏", 0, 1, 0, @[@"暂停", @"继续"], @[@0, @1]),
            LMVTuneParam(@"ForegroundAction", @"App 前台", 0, 1, 0, @[@"暂停", @"继续"], @[@0, @1]),
        ]},
        @{@"title":@"性能", @"params":@[
            LMVTuneParam(@"LowPowerAction", @"低电量模式", 0, 2, 0, @[@"不变", @"降帧", @"暂停"], @[@0, @1, @2]),
            LMVTuneParam(@"ThermalAction", @"设备过热", 0, 2, 0, @[@"不变", @"降帧", @"暂停"], @[@0, @1, @2]),
        ]},
    ];
    });
    [groups addObjectsFromArray:rest];
    return groups;
}

// Look up a parameter definition by key across every group.
static inline NSDictionary *LMVTuneFindParam(NSString *key) {
    static NSDictionary *index; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        // GS carries the probe group, Lock carries playback/visibility/perf,
        // Bubble carries its own two. Together they cover every key.
        for (NSString *target in @[@"GS", @"Lock", @"Bubble"])
            for (NSDictionary *group in LMVTuneGroupsForTarget(target))
                for (NSDictionary *p in group[@"params"])
                    if (!map[p[@"key"]]) map[p[@"key"]] = p;
        index = [map copy];
    });
    return key ? index[key] : nil;
}

static inline NSString *LMVTuneFullKey(NSString *target, NSString *key) {
    return [NSString stringWithFormat:@"Tune.%@.%@", target, key];
}
// 2.41: Settings writes in another process. CFPreferences keeps a per-process cache,
// so without this the dylib keeps reading the value it saw at launch and every
// setting looks dead. Throttled to once a second.
static inline void LMVTuneSync(void) {
    static NSTimeInterval last;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - last < 1.0) return;
    last = now;
    CFPreferencesAppSynchronize((__bridge CFStringRef)LMVTuneDomain);
}
static inline NSInteger LMVTuneValue(NSString *target, NSString *key) {
    LMVTuneSync();
    NSDictionary *p = LMVTuneFindParam(key);
    NSInteger fallback = p ? [p[@"def"] integerValue] : 0;
    if (!target.length || !key.length) return fallback;
    CFStringRef full = (__bridge CFStringRef)LMVTuneFullKey(target, key);
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue(full, (__bridge CFStringRef)LMVTuneDomain);
    if (![value isKindOfClass:NSNumber.class]) return fallback;
    NSInteger n = [value integerValue];
    if (p) {
        NSInteger lo = [p[@"min"] integerValue], hi = [p[@"max"] integerValue];
        if (n < lo) n = lo;
        if (n > hi) n = hi;
        // An enum stored under an older build (e.g. MaxFPS = 4 from the 0...4 index
        // range in 2.39) is not one of the choices any more - fall back to the default
        // instead of showing "?" forever.
        NSArray *values = p[@"values"];
        if (values.count && ![values containsObject:@(n)]) n = [p[@"def"] integerValue];
    }
    return n;
}
// True when this channel/key was ever written - lets a legacy key keep its own
// default until the user actually touches the new slider.
static inline BOOL LMVTuneHasValue(NSString *target, NSString *key) {
    if (!target.length || !key.length) return NO;
    LMVTuneSync();
    CFStringRef full = (__bridge CFStringRef)LMVTuneFullKey(target, key);
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue(full, (__bridge CFStringRef)LMVTuneDomain);
    return [value isKindOfClass:NSNumber.class];
}
static inline void LMVTuneSetValue(NSString *target, NSString *key, NSInteger value) {
    if (!target.length || !key.length) return;
    NSDictionary *p = LMVTuneFindParam(key);
    if (p) {
        NSInteger lo = [p[@"min"] integerValue], hi = [p[@"max"] integerValue];
        if (value < lo) value = lo;
        if (value > hi) value = hi;
    }
    CFStringRef full = (__bridge CFStringRef)LMVTuneFullKey(target, key);
    CFPreferencesSetAppValue(full, (__bridge CFNumberRef)@(value), (__bridge CFStringRef)LMVTuneDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)LMVTuneDomain);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, NULL, YES);
}

// Probe interval in seconds. The channels use this instead of a hard-coded 0.2.
static inline NSTimeInterval LMVTuneProbeInterval(NSString *target) {
    NSInteger hz = LMVTuneValue(target, @"ProbeHz");
    if (hz < 1) hz = 1;
    if (hz > 20) hz = 20;
    return 1.0 / (NSTimeInterval)hz;
}
static inline NSTimeInterval LMVTuneDelay(NSString *target, NSString *key) {
    return LMVTuneValue(target, key) / 1000.0;
}
