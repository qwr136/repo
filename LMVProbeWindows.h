#pragma once
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#if __has_include("LMVPanelTuning.h")
#import "LMVPanelTuning.h"
#else
// Standalone fixtures compile this header alone; the snapshot default is 80 ms.
static inline NSInteger LMVTuneValue(NSString *target, NSString *key) { (void)target; (void)key; return 80; }
static inline void LMVTuneReport(NSString *target, NSString *key, NSInteger value) { (void)target; (void)key; (void)value; }
#endif
// 2.98: the TTL is a row now (设置 → 自定义参数 → 全局窗口快照). One value for all
// eight channels on purpose: the whole point of the snapshot is that they share ONE
// enumeration, so a per-channel TTL would restore the eight walks 2.55 removed.
static inline CFTimeInterval LMVProbeSnapshotTTL(void) {
    NSInteger ms=LMVTuneValue(@"Global",@"SnapshotMs");
    LMVTuneReport(@"Global",@"SnapshotMs",ms);
    return ms/1000.0;
}

// 2.55: ONE window enumeration per probe beat, shared by every panel channel.
//
// Each of the eight panel channels used to walk all scenes and all windows on every
// tick: 8 x 5 Hz = 40 walks a second, and each walk happened two or three times per
// tick (environment check, home-window lookup, the update itself). That multiplied
// into the CPU climb the user saw the moment the eight backgrounds were enabled.
//
// The window list only changes when a window is added or removed - never during a
// panel's slide animation, which only moves frames. A probe interval is 200 ms, so an
// 80 ms snapshot cannot hide a state the probe would have seen; it just makes every
// channel look at the same list instead of building its own. Each channel still
// applies its own visibility / class / geometry rules.
//
// Main thread only, like every caller. The array is retained for at most 80 ms, so a
// window torn down in that gap stays alive as an object - reading its properties is
// safe and it is released with the next snapshot.
static NSArray<UIWindow *> *LMVProbeAllWindows(void) {
    static NSArray<UIWindow *> *cache;
    static CFTimeInterval cachedAt;
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval ttl=LMVProbeSnapshotTTL();
    if (cache && now - cachedAt < ttl) return cache;
    NSMutableArray<UIWindow *> *list = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        [list addObjectsFromArray:((UIWindowScene *)scene).windows];
    }
    // Never cache an empty answer: during launch and scene reconnection the list is
    // briefly empty, and a cached empty list would make every channel stand down for
    // the whole TTL.
    if (!list.count) return cache ?: @[];
    cache = [list copy];
    cachedAt = now;
    return cache;
}
// The common case: windows that can actually carry a panel. Costs one property read
// per window on top of the shared list, instead of a full scene walk per channel.
static NSArray<UIWindow *> *LMVProbeVisibleWindows(void) {
    static NSArray<UIWindow *> *cache;
    static CFTimeInterval cachedAt;
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval ttl=LMVProbeSnapshotTTL();
    if (cache && now - cachedAt < ttl) return cache;
    NSMutableArray<UIWindow *> *list = [NSMutableArray array];
    for (UIWindow *window in LMVProbeAllWindows()) {
        if (window.hidden || window.alpha < .01) continue;
        [list addObject:window];
    }
    cache = [list copy];
    cachedAt = now;
    return cache;
}
