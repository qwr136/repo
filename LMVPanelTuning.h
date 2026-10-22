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
// 2.55: what a DISABLED channel polls at. It used to be 0.5 s (2 s for GS/CopyLogX) so
// the channel would notice its switch being turned on - but every switch write posts
// com.minis.lockmessagevideo/preferencesChanged, and that runs LMVRefresh(YES), which
// re-creates the timer immediately. Eight idle channels at 2 Hz were 16 wakeups a
// second that could never find anything; 30 s is a backstop in case that notification
// is ever lost, and costs 0.27 wakeups a second across all eight.
static const NSTimeInterval LMVTuneIdleInterval = 30.0;
// 2.50: the runtime report MUST live in its own domain. Writing Runtime.* into the
// settings domain and then calling CFPreferencesAppSynchronize from SpringBoard
// flushed that process's stale snapshot back to disk, overwriting the value the user
// had just saved in Settings (device log: idle went back to 30, covered to 1, while
// the page still showed 10). Separate domain, no shared keys, no way to collide.
static NSString *const LMVTuneRuntimeDomain = @"com.minis.lockmessagevideo.runtime";

// The channels, in the same order Settings lists them. 2.52: the settings page no
// longer splits on "group" - every target is listed under one heading (功能面板参数),
// as the user asked - so the field is a classification label only. It is kept because
// the order and the label are useful data, not because anything reads it to section
// the list.
static inline NSArray<NSDictionary *> *LMVTuneTargets(void) {
    return @[
        @{@"id":@"SquidPanel",    @"name":@"鱿鱼面板",                 @"group":@"panel"},
        @{@"id":@"AT",            @"name":@"AT 面板",                  @"group":@"panel"},
        @{@"id":@"CV",            @"name":@"CopyVault 面板",           @"group":@"panel"},
        @{@"id":@"Myrtle",        @"name":@"Myrtle 面板",              @"group":@"panel"},
        @{@"id":@"PA",            @"name":@"电话助手",                 @"group":@"panel"},
        @{@"id":@"GS",            @"name":@"GlassSuiteX 弹窗",         @"group":@"panel"},
        @{@"id":@"CCBorder",      @"name":@"CCBorder 长按菜单",        @"group":@"panel"},
        @{@"id":@"CopyLogX",      @"name":@"CopyLogX 面板",            @"group":@"panel"},
        // 2.61: the desktop long-press menu, by user request. It is the ninth panel
        // channel: hook-driven like the others, and it now carries a ProbeHz fallback
        // timer + show/hide delay, so it gets the same three rows here.
        @{@"id":@"HomeMenu",      @"name":@"桌面长按菜单",              @"group":@"panel"},
        // 2.46: the desktop is the one non-panel channel that runs a display link all
        // the time, so its cadence is worth exposing. It still has no probe/delay rows:
        // what the user can tune here is how often the surface is re-measured.
        @{@"id":@"Desktop",       @"name":@"桌面背景视频",             @"group":@"other"},
        // 2.97: the two always-on layers. Both ran a CADisplayLink at a hard-coded
        // 60 Hz with no way to see or change it.
        //   LockNC is ONE channel on purpose: the notification centre and the lock
        // screen are the same CoverSheet layer and the same player, so two separate
        // rows would have been two switches writing the same number.
        @{@"id":@"LockNC",        @"name":@"锁屏/通知中心背景视频",     @"group":@"other"},
        @{@"id":@"CC",            @"name":@"控制中心背景视频",         @"group":@"other"},
        // 2.48: the two remaining always-on consumers. The ball's tick notices "the
        // desktop came back"; the card link is the 30 Hz surface under the notification
        // cards. Both used to be hard-coded.
        @{@"id":@"Bubble",        @"name":@"悬浮球",                   @"group":@"other"},
        @{@"id":@"Cards",         @"name":@"通知卡片（消息/选项/清除）", @"group":@"other"},
        // 2.98: the shared window snapshot behind all eight panel channels. One row,
        // not eight: the channels share a single enumeration by design (2.55), so a
        // per-channel value would multiply the walks it removed.
        @{@"id":@"Global",        @"name":@"全局窗口快照（7 个共用）",   @"group":@"other"},
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
    return [@[@"AT",@"CCBorder",@"CV",@"Myrtle",@"PA",@"SquidPanel",@"GS",@"CopyLogX",@"HomeMenu"] containsObject:target];
}
// 2.43: all eight panel channels implement show/hide delay (each one carries its own
// pendingShow/pendingHide in its update path). The settings page only listed two, so
// six of them had no way to reach the code at all.
static inline BOOL LMVTuneHasSheetDelay(NSString *target) {
    return [@[@"PA",@"GS",@"CCBorder",@"CopyLogX",@"SquidPanel",@"AT",@"CV",@"Myrtle",@"HomeMenu"] containsObject:target];
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
        return @[
            @{@"title":@"检测", @"params":@[
                // 2.97: the 100 ms gate was a hard-coded constant, so "how often is
                // the desktop really measured" could not be answered or changed.
                LMVTuneParam(@"ProbeIntervalMs", @"检测节流 (ms, 0~1000)", 0, 1000, 100),
                // 3.02: the 60 Hz cover watcher was a constant. It runs only while the
                // desktop is covered, and it is the 3% CPU seen inside an app; expose it
                // so the trade (reveal latency vs. idle cost) is the user's call.
                LMVTuneParam(@"CoverWatchHz", @"遮挡检测频率 (Hz, 1~60)", 1, 60, 60),
            ]},
            @{@"title":@"刷新", @"params":@[
                LMVTuneParam(@"IdleFPS", @"桌面可见刷新率 (Hz, 10~60)", 10, 60, 30),
                LMVTuneParam(@"CoveredFPS", @"被遮挡时心跳 (Hz, 1~30)", 1, 30, 5),
            ]}
        ];
    }
    // 2.97: the two always-on layers that had their callback rate nailed to 60.
    // They get a detection-frequency row of their own plus the shared "当前生效"
    // line that every channel already reports through.
    if ([target isEqualToString:@"CC"]) {
        return @[@{@"title":@"检测", @"params":@[
            LMVTuneParam(@"ProbeHz", @"检测频率 (Hz, 1~60)", 1, 60, 60),
        ]}];
    }
    if ([target isEqualToString:@"LockNC"]) {
        return @[@{@"title":@"检测", @"params":@[
            LMVTuneParam(@"ProbeHz", @"检测频率 (Hz, 1~60)", 1, 60, 60),
        ]}];
    }
    // 2.48: the ball and the card link have one cadence each, and neither is a panel
    // (no show/hide delay, no hook), so they get a single-row group of their own.
    if ([target isEqualToString:@"Bubble"]) {
        return @[@{@"title":@"检测", @"params":@[
            LMVTuneParam(@"TickHz", @"悬浮球检测频率 (Hz, 1~30)", 1, 30, 20),
        ]}];
    }
    if ([target isEqualToString:@"Global"]) {
        return @[@{@"title":@"检测", @"params":@[
            LMVTuneParam(@"SnapshotMs", @"快照有效期 (ms, 0~60000)", 0, 60000, 80),
            // 3.08: the window-signature probe that gives the six hook-less channels
            // their event entry. 30 Hz by default; raise it if a panel still shows up
            // late, lower it to save power.
            LMVTuneParam(@"PresenceHz", @"变化探针频率 (Hz, 5~60)", 5, 60, 30),
            // 3.10.2: 9 of the panel channels are kicked by the signature probe the
            // moment a panel appears (LMVPanelAppearKick). While nothing is mounted
            // their own timer is only a safety net; 2.5 s is enough for that and
            // removes nine per-second view-tree walks. 0 disables the cap.
            LMVTuneParam(@"FallbackProbeMs", @"未挂载兜底间隔 (ms, 0~10000)", 0, 10000, 2500),
        ]}];
    }
    if ([target isEqualToString:@"Cards"]) {
        return @[@{@"title":@"刷新", @"params":@[
            LMVTuneParam(@"FPS", @"通知卡片刷新率 (Hz, 1~60)", 1, 60, 30),
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
        // 3.04: CopyLogX is the only panel that presents in a NEW window, so it is the
        // only one where the shared snapshot TTL is visible as a delay. It gets its own
        // list and its own row; the other seven keep the shared one.
        if ([target isEqualToString:@"CopyLogX"]) {
            [probe addObject:LMVTuneParam(@"ProbeSnapshotMs", @"快照有效期 (ms, 1~1000)", 1, 1000, 80)];
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

// 3.05: ONE NOTIFICATION PER CHANNEL. The old single name woke every channel for any
// change - switching the CopyLogX material also made the desktop reload its own asset
// (device log: perf desktop max=1732ms for a change that had nothing to do with it).
// The unsuffixed name is kept ONLY for genuinely global writes (master switch, shared
// material deletion); it still means "refresh everything".
static inline NSString *LMVTunePreferenceNote(NSString *target) {
    if (!target.length) return @"com.minis.lockmessagevideo/preferencesChanged";
    return [NSString stringWithFormat:@"com.minis.lockmessagevideo/preferencesChanged.%@", target];
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
        (__bridge CFStringRef)LMVTunePreferenceNote(target), NULL, NULL, YES);
}

// 2.48: WHAT THE CHANNEL ACTUALLY RUNS AT. Settings and SpringBoard are separate
// processes, so the page cannot read the display link's frame rate. Each channel
// writes the value it APPLIED under Runtime.<target>.<key> (plus a timestamp), and
// the page reads it back - that is the difference between "saved" and "in effect".
// Writes happen only when the value CHANGES, so the steady state costs nothing.
static inline void LMVTuneReport(NSString *target, NSString *key, NSInteger value) {
    if (!target.length || !key.length) return;
    static NSMutableDictionary<NSString *, NSNumber *> *last;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ last = [NSMutableDictionary new]; });
    NSString *identity = [target stringByAppendingFormat:@".%@", key];
    NSNumber *previous = last[identity];
    if (previous && previous.integerValue == value) return;
    last[identity] = @(value);
    NSString *full = [NSString stringWithFormat:@"Runtime.%@.%@", target, key];
    CFPreferencesSetAppValue((__bridge CFStringRef)full, (__bridge CFNumberRef)@(value),
                             (__bridge CFStringRef)LMVTuneRuntimeDomain);
    NSString *stamp = [NSString stringWithFormat:@"Runtime.%@.At", target];
    CFPreferencesSetAppValue((__bridge CFStringRef)stamp,
                             (__bridge CFNumberRef)@(NSDate.date.timeIntervalSince1970),
                             (__bridge CFStringRef)LMVTuneRuntimeDomain);
    // 2.52: a PER-KEY stamp as well. The shared one above moves whenever ANY value in
    // this channel changes, so a value that is only written on the desktop (the
    // visible-state frame rate) inherited the 2 Hz heartbeat's fresh timestamp and was
    // read as "just measured" long after the desktop had been covered. Two keys, two
    // truths: the shared one still answers "is the channel alive", this one answers
    // "when was THIS value observed".
    NSString *keyStamp = [NSString stringWithFormat:@"Runtime.%@.%@.At", target, key];
    CFPreferencesSetAppValue((__bridge CFStringRef)keyStamp,
                             (__bridge CFNumberRef)@(NSDate.date.timeIntervalSince1970),
                             (__bridge CFStringRef)LMVTuneRuntimeDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)LMVTuneRuntimeDomain);
}
// 2.52: "this value was observed now", without rewriting the value. -LMVTuneReport:
// returns early when the value did not change, so its stamp would otherwise mean
// "when this number last CHANGED" - for the desktop's visible-state rate that reads as
// "minutes ago" while the number is in fact current, and as "just now" while it is
// stale. Touch is called on every observation (throttled to one write a second) and
// only from the state that can actually observe it, so the stamp answers the question
// the page asks: how long ago was this measured?
static inline void LMVTuneTouch(NSString *target, NSString *key) {
    if (!target.length || !key.length) return;
    static NSMutableDictionary<NSString *, NSNumber *> *lastTouch;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lastTouch = [NSMutableDictionary new]; });
    NSTimeInterval now = NSDate.date.timeIntervalSince1970;
    NSString *identity = [target stringByAppendingFormat:@".%@", key];
    NSNumber *previous = lastTouch[identity];
    // 2 s, not 1: two values (the visible-state rate and the measured rate) are
    // touched on the same seconds, and every touch is a synchronous domain write from
    // SpringBoard's main thread. At 2 s the page still says 刚刚 (its threshold is 5 s)
    // while the write traffic stays around one a second.
    if (previous && now - previous.doubleValue < 2.0) return;
    lastTouch[identity] = @(now);
    NSString *stamp = [NSString stringWithFormat:@"Runtime.%@.%@.At", target, key];
    CFPreferencesSetAppValue((__bridge CFStringRef)stamp,
                             (__bridge CFNumberRef)@(now),
                             (__bridge CFStringRef)LMVTuneRuntimeDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)LMVTuneRuntimeDomain);
}
// Reads come from Settings, writes from SpringBoard, so the runtime domain is
// synchronised here too - throttled, because the page reads once a second anyway.
static inline void LMVTuneRuntimeSync(void) {
    static NSTimeInterval last;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - last < 0.9) return;
    last = now;
    CFPreferencesAppSynchronize((__bridge CFStringRef)LMVTuneRuntimeDomain);
}
static inline NSNumber *LMVTuneRuntime(NSString *target, NSString *key) {
    if (!target.length || !key.length) return nil;
    LMVTuneRuntimeSync();
    NSString *full = [NSString stringWithFormat:@"Runtime.%@.%@", target, key];
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)full,
                                                               (__bridge CFStringRef)LMVTuneRuntimeDomain);
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}
static inline NSTimeInterval LMVTuneRuntimeAge(NSString *target) {
    if (!target.length) return -1;
    LMVTuneRuntimeSync();
    NSString *stamp = [NSString stringWithFormat:@"Runtime.%@.At", target];
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)stamp,
                                                               (__bridge CFStringRef)LMVTuneRuntimeDomain);
    if (![value isKindOfClass:NSNumber.class]) return -1;
    return MAX(0.0, NSDate.date.timeIntervalSince1970 - [value doubleValue]);
}
// 2.52: how long ago THIS value was observed, not when the channel last spoke. See
// LMVTuneReport. Returns -1 when the key has never been reported.
static inline NSTimeInterval LMVTuneRuntimeKeyAge(NSString *target, NSString *key) {
    if (!target.length || !key.length) return -1;
    LMVTuneRuntimeSync();
    NSString *stamp = [NSString stringWithFormat:@"Runtime.%@.%@.At", target, key];
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)stamp,
                                                               (__bridge CFStringRef)LMVTuneRuntimeDomain);
    if (![value isKindOfClass:NSNumber.class]) return -1;
    return MAX(0.0, NSDate.date.timeIntervalSince1970 - [value doubleValue]);
}

// Probe interval in seconds. The channels use this instead of a hard-coded 0.2.
static inline NSTimeInterval LMVTuneProbeInterval(NSString *target) {
    NSInteger hz = LMVTuneValue(target, @"ProbeHz");
    if (hz < 1) hz = 1;
    if (hz > 60) hz = 60;
    // Every panel channel goes through here, so the applied frequency is reported
    // once, in one place, instead of in eight files.
    LMVTuneReport(target, @"ProbeHz", hz);
    return 1.0 / (NSTimeInterval)hz;
}
// 3.10.2: a channel that is not mounted cannot change anything between two ticks -
// the shared signature probe already refreshes it on the frame a panel appears. Only
// the idle timer is slowed down; once something is mounted the user's rate stands,
// so scrolling and geometry follow-through are untouched.
static inline NSTimeInterval LMVTuneFallbackInterval(NSTimeInterval want, BOOL mounted) {
    if (mounted) return want;
    NSInteger ms = LMVTuneValue(@"Global", @"FallbackProbeMs");
    if (ms <= 0) return want;
    NSTimeInterval floorInterval = ms / 1000.0;
    return want < floorInterval ? floorInterval : want;
}
static inline NSTimeInterval LMVTuneDelay(NSString *target, NSString *key) {
    NSInteger ms = LMVTuneValue(target, key);
    // Same reason as LMVTuneProbeInterval: the value the channel actually uses is
    // reported here, so every row on a tuning page can show "in effect", not "saved".
    LMVTuneReport(target, key, ms);
    return ms / 1000.0;
}
