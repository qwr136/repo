#pragma once
#import <Foundation/Foundation.h>
// 5.23: nine panel channels shared one pump instead of nine NSTimers.
#define LMV_HAS_SCHEDULER 1
#define LMV_MAX_SCHEDULED 16
typedef struct { __unsafe_unretained NSString *name; CFTimeInterval interval, nextAt; void (^body)(void); } LMVSchedulerEntry;
static LMVSchedulerEntry gLMVSched[LMV_MAX_SCHEDULED];
static NSUInteger gLMVSchedCount = 0, gLMVSchedGen = 0;

static void LMVSchedulerPump(void);

static void LMVSchedulerArm(CFTimeInterval delay) {
    if (delay < 0.05) delay = 0.05;
    if (delay > 5.0) delay = 5.0;
    gLMVSchedGen++;
    NSUInteger gen = gLMVSchedGen;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ if (gen == gLMVSchedGen) LMVSchedulerPump(); });
}
static void LMVSchedulerPump(void) {
    if (!gLMVSchedCount) return;
    CFTimeInterval now = CACurrentMediaTime(), nearest = 5.0;
    for (NSUInteger i = 0; i < gLMVSchedCount; i++) {
        if (gLMVSched[i].nextAt <= now) {
            gLMVSched[i].nextAt = now + gLMVSched[i].interval;
            void (^body)(void) = gLMVSched[i].body;
            if (body) body();
        }
        CFTimeInterval delta = gLMVSched[i].nextAt - CACurrentMediaTime();
        if (delta < nearest) nearest = delta;
    }
    LMVSchedulerArm(nearest);
}
static void LMVSchedule(NSString *name, CFTimeInterval interval, void (^body)(void)) {
    if (!name.length || interval <= 0.0) return;
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ LMVSchedule(name, interval, body); });
        return;
    }
    for (NSUInteger i = 0; i < gLMVSchedCount; i++) {
        if ([gLMVSched[i].name isEqualToString:name]) {
            gLMVSched[i].interval = interval;
            gLMVSched[i].body = body;
            CFTimeInterval soonest = CACurrentMediaTime() + interval;
            if (gLMVSched[i].nextAt > soonest) gLMVSched[i].nextAt = soonest;
            LMVSchedulerArm(0.05);
            return;
        }
    }
    if (gLMVSchedCount >= LMV_MAX_SCHEDULED) return;
    gLMVSched[gLMVSchedCount].name = name;
    gLMVSched[gLMVSchedCount].interval = interval;
    gLMVSched[gLMVSchedCount].nextAt = CACurrentMediaTime() + interval;
    gLMVSched[gLMVSchedCount].body = body;
    gLMVSchedCount++;
    LMVSchedulerArm(interval);
}
