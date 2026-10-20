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
        @{@"id":@"SquidPanel",    @"name":@"鱿鱼面板"},
        @{@"id":@"AT",            @"name":@"AT 面板"},
        @{@"id":@"CV",            @"name":@"CopyVault 面板"},
        @{@"id":@"Myrtle",        @"name":@"Myrtle 面板"},
        @{@"id":@"PA",            @"name":@"电话助手"},
        @{@"id":@"GS",            @"name":@"GlassSuiteX 弹窗"},
        @{@"id":@"CCBorder",      @"name":@"CCBorder 长按菜单"},
        @{@"id":@"CopyLogX",      @"name":@"CopyLogX 面板"},
        // 2.46: the desktop is the one non-panel channel that runs a display link all
        // the time, so its cadence is worth exposing. It still has no probe/delay rows:
        // what the user can tune here is how often the surface is re-measured.
        @{@"id":@"Desktop",       @"name":@"桌面背景视频"},
    ];
}
static inline NSString *LMVTuneTargetName(NSString *target) {
    for (NSDictionary *item in LMVTuneTargets())
        if ([item[@"id"] isEqualToString:target]) return item[@"name"];
    return target ?: @"";
}

// One numeric parameter, edited by tapping the row (see LMVTuneController).
// 2.45: the enum form (choices/values) went away with the playback group - every
// remaining parameter is a bounded integer - so the two array arguments are gone
// rather than being passed nil at every call site.
static inline NSDictionary *LMVTuneParam(NSString *key,
                                  NSString *title,
                                  NSInteger minValue,
                                  NSInteger maxValue,
                                  NSInteger defaultValue) {
    NSMutableDictionary *p = [NSMutableDictionary dictionary];
    p[@"key"] = key; p[@"title"] = title;
    p[@"min"] = @(minValue); p[@"max"] = @(maxValue); p[@"def"] = @(defaultValue);
    return p;
}

// 2.41: only show parameters this channel actually reads. A switch that changes
// nothing is worse than no switch.
static inline BOOL LMVTuneHasTimer(NSString *target) {
    return [@[@"AT",@"CCBorder",@"CV",@"Myrtle",@"PA",@"SquidPanel",@"GS",@"CopyLogX"] containsObject:target];
}
// 2.43: all eight panel channels implement show/hide delay (each one carries its own
// pendingShow/pendingHide in its update path). The settings page only listed two, so
// six of them had no way to reach the code at all.
static inline BOOL LMVTuneHasSheetDelay(NSString *target) {
    return [@[@"PA",@"GS",@"CCBorder",@"CopyLogX",@"SquidPanel",@"AT",@"CV",@"Myrtle"] containsObject:target];
}
// Hooks exist only where a system callback was confirmed by a capture.
static inline BOOL LMVTuneHasHook(NSString *target) {
    return [@[@"GS",@"CopyLogX"] containsObject:target];
}
static inline NSArray<NSDictionary *> *LMVTuneGroupsForTarget(NSString *target) {
    // 2.46: the desktop has its own two cadences instead of the probe/delay group -
    // it is driven by a display link, not by a polling timer, so "出现延迟" and
    // "钩子节流" would mean nothing there.
    if ([target isEqualToString:@"Desktop"]) {
        return @[@{@"title":@"刷新", @"params":@[
            LMVTuneParam(@"IdleFPS", @"桌面可见刷新率 (Hz, 10~60)", 10, 60, 30),
            LMVTuneParam(@"CoveredFPS", @"被遮挡时心跳 (Hz, 1~30)", 1, 30, 5),
        ]}];
    }
    NSMutableArray *groups = [NSMutableArray array];
    if (LMVTuneHasTimer(target)) {
        NSMutableArray *probe = [NSMutableArray array];
        [probe addObject:LMVTuneParam(@"ProbeHz", @"检测频率 (Hz, 1~60)", 1, 60, 5)];
        if (LMVTuneHasSheetDelay(target)) {
            [probe addObject:LMVTuneParam(@"ShowDelayMs", @"出现延迟 (ms, 0~1000)", 0, 1000, 0)];
            [probe addObject:LMVTuneParam(@"HideDelayMs", @"关闭延迟 (ms, 0~2000)", 0, 2000, 0)];
        }
        // Keep the hook row separate: only GS/CopyLogX have a callback to throttle, and
        // showing it on the other six would be exactly the dead switch we just removed.
        if (LMVTuneHasHook(target)) {
            [probe addObject:LMVTuneParam(@"HookThrottleMs", @"钩子节流 (ms, 0~200)", 0, 200, 50)];
        }
        [groups addObject:@{@"title":@"探测", @"params":probe}];
    }
    return groups;
}

// Look up a parameter definition by key across every group.
static inline NSDictionary *LMVTuneFindParam(NSString *key) {
    static NSDictionary *index; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *map = [NSMutableDictionary dictionary];
        // 2.46: every channel's own group is scanned, so the desktop's two cadence
        // keys get their min/max/default like the probe keys do. LMVTuneTargets()
        // returns DICTIONARIES, so the id has to be taken out of each item - passing
        // the dictionary itself made -isEqualToString: go through forwarding and
        // abort the native fixture.
        for (NSDictionary *item in LMVTuneTargets())
            for (NSDictionary *group in LMVTuneGroupsForTarget(item[@"id"]))
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
    }
    return n;
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
    if (hz > 60) hz = 60;
    return 1.0 / (NSTimeInterval)hz;
}
static inline NSTimeInterval LMVTuneDelay(NSString *target, NSString *key) {
    return LMVTuneValue(target, key) / 1000.0;
}
