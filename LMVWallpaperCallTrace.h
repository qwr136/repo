#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <atomic>
#import <mutex>
#import <string.h>
#import <unistd.h>
// Diagnostic only: typed IMP wrappers call the original exactly once. No UIKit
// mutation, private getter, file-read hook, or replacement of wallpaper content.
#ifndef LMV_TRACE_TEST
#define LMVTraceEnabled() LMVDiagnosticsEnabled.load()
#define LMVTraceLog(...) LMVDiagnostic((__VA_ARGS__))
#endif
struct LMVTraceSpec {
    const char *className, *selectorName, *returnType;
    unsigned count;
    const char *args[4];
    IMP replacement, original;
    Class owner;
    std::atomic<unsigned long> hits{0};
    std::atomic<unsigned> emitted{0};
    const char *status;
    bool announced;
};
static const NSUInteger LMVTraceCount = 25;
static LMVTraceSpec LMVTraceSpecs[LMVTraceCount];
static std::mutex LMVTraceInstallMutex;
static std::atomic<unsigned long> LMVTraceCallID(0);
static thread_local BOOL LMVInsideTrace = NO;
static NSString *LMVTraceClass(id value) { return value ? NSStringFromClass(object_getClass(value)) : @"nil"; }
static NSString *LMVTraceStack(void) {
    NSMutableArray *frames = [NSMutableArray new];
    NSArray<NSNumber *> *addresses = NSThread.callStackReturnAddresses;
    for (NSUInteger i = 2; i < addresses.count && frames.count < 8; i++) {
        void *address = (void *)(uintptr_t)addresses[i].unsignedLongLongValue;
        Dl_info info = {};
        if (dladdr(address, &info)) {
            NSString *module = info.dli_fname ? [[NSString stringWithUTF8String:info.dli_fname] lastPathComponent] : @"?";
            NSString *symbol = info.dli_sname ? [NSString stringWithUTF8String:info.dli_sname] : @"?";
            uintptr_t base = (uintptr_t)info.dli_fbase;
            [frames addObject:[NSString stringWithFormat:@"%@+0x%llx:%@", module, (unsigned long long)((uintptr_t)address - base), symbol]];
        }
    }
    return [frames componentsJoinedByString:@" | "];
}
static unsigned long LMVTraceBegin(NSUInteger index, id object, NSString *arguments) {
    if (!LMVTraceEnabled() || LMVInsideTrace) return 0;
    LMVTraceSpec &spec = LMVTraceSpecs[index];
    unsigned long hit = spec.hits.fetch_add(1) + 1;
    // Calls are counted while enabled; only the first twelve per interface are
    // expanded, with two call stacks. No decoding or disk I/O in the wrapper.
    if (spec.emitted.fetch_add(1) >= 12) return 0;
    unsigned long call = LMVTraceCallID.fetch_add(1) + 1;
    LMVInsideTrace = YES;
    @try {
        LMVTraceLog([NSString stringWithFormat:@"wallpaper-call enter id=%lu slot=%lu pid=%d thread=%@ class=%@ installedOn=%s selector=%s hit=%lu args=%@",
            call, (unsigned long)index, getpid(), NSThread.isMainThread ? @"main" : @"background",
            LMVTraceClass(object), spec.className, spec.selectorName, hit, arguments]);
        if (hit <= 2) LMVTraceLog([NSString stringWithFormat:@"wallpaper-call stack id=%lu frames=%@", call, LMVTraceStack()]);
    } @catch (NSException *exception) {} @finally { LMVInsideTrace = NO; }
    return call;
}
static void LMVTraceEnd(NSUInteger index, unsigned long call, NSString *result) {
    if (!call || !LMVTraceEnabled()) return;
    LMVInsideTrace = YES;
    @try { LMVTraceLog([NSString stringWithFormat:@"wallpaper-call return id=%lu slot=%lu result=%@", call, (unsigned long)index, result]); }
    @catch (NSException *exception) {} @finally { LMVInsideTrace = NO; }
}
typedef id (*LMVTraceOriginal0)(id, SEL) __attribute__((ns_returns_retained));
static id LMVTraceWrap0(id self, SEL cmd) __attribute__((ns_returns_retained));
static id LMVTraceWrap0(id self, SEL cmd) {
    LMVTraceOriginal0 original = (LMVTraceOriginal0)LMVTraceSpecs[0].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(0, self, @"none") : 0;
    id result = original(self, cmd);
    if (call) LMVTraceEnd(0, call, LMVTraceClass(result));
    return result;
}

typedef BOOL (*LMVTraceOriginal1)(id, SEL, id a, id b);
static BOOL LMVTraceWrap1(id self, SEL cmd, id a, id b);
static BOOL LMVTraceWrap1(id self, SEL cmd, id a, id b) {
    LMVTraceOriginal1 original = (LMVTraceOriginal1)LMVTraceSpecs[1].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(1, self, [NSString stringWithFormat:@"%@,%@", LMVTraceClass(a), LMVTraceClass(b)]) : 0;
    BOOL result = original(self, cmd, a, b);
    if (call) LMVTraceEnd(1, call, [NSString stringWithFormat:@"BOOL=%d", result]);
    return result;
}

typedef id (*LMVTraceOriginal2)(id, SEL, NSInteger *a, NSInteger b, id c);
static id LMVTraceWrap2(id self, SEL cmd, NSInteger *a, NSInteger b, id c);
static id LMVTraceWrap2(id self, SEL cmd, NSInteger *a, NSInteger b, id c) {
    LMVTraceOriginal2 original = (LMVTraceOriginal2)LMVTraceSpecs[2].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(2, self, [NSString stringWithFormat:@"stylePointer=%d variant=%lld traits=%@", a != NULL, (long long)b, LMVTraceClass(c)]) : 0;
    id result = original(self, cmd, a, b, c);
    if (call) LMVTraceEnd(2, call, LMVTraceClass(result));
    return result;
}

typedef id (*LMVTraceOriginal3)(id, SEL, id a);
static id LMVTraceWrap3(id self, SEL cmd, id a);
static id LMVTraceWrap3(id self, SEL cmd, id a) {
    LMVTraceOriginal3 original = (LMVTraceOriginal3)LMVTraceSpecs[3].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(3, self, [NSString stringWithFormat:@"%@", LMVTraceClass(a)]) : 0;
    id result = original(self, cmd, a);
    if (call) LMVTraceEnd(3, call, LMVTraceClass(result));
    return result;
}

typedef id (*LMVTraceOriginal4)(id, SEL, id a);
static id LMVTraceWrap4(id self, SEL cmd, id a);
static id LMVTraceWrap4(id self, SEL cmd, id a) {
    LMVTraceOriginal4 original = (LMVTraceOriginal4)LMVTraceSpecs[4].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(4, self, [NSString stringWithFormat:@"%@", LMVTraceClass(a)]) : 0;
    id result = original(self, cmd, a);
    if (call) LMVTraceEnd(4, call, LMVTraceClass(result));
    return result;
}

typedef void (*LMVTraceOriginal5)(id, SEL, BOOL a);
static void LMVTraceWrap5(id self, SEL cmd, BOOL a);
static void LMVTraceWrap5(id self, SEL cmd, BOOL a) {
    LMVTraceOriginal5 original = (LMVTraceOriginal5)LMVTraceSpecs[5].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(5, self, [NSString stringWithFormat:@"obscured=%d", a]) : 0;
    original(self, cmd, a);
    LMVTraceEnd(5, call, @"void");
}

typedef id (*LMVTraceOriginal6)(id, SEL, id a);
static id LMVTraceWrap6(id self, SEL cmd, id a);
static id LMVTraceWrap6(id self, SEL cmd, id a) {
    LMVTraceOriginal6 original = (LMVTraceOriginal6)LMVTraceSpecs[6].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(6, self, [NSString stringWithFormat:@"%@", LMVTraceClass(a)]) : 0;
    id result = original(self, cmd, a);
    if (call) LMVTraceEnd(6, call, LMVTraceClass(result));
    return result;
}

typedef id (*LMVTraceOriginal7)(id, SEL, id a);
static id LMVTraceWrap7(id self, SEL cmd, id a);
static id LMVTraceWrap7(id self, SEL cmd, id a) {
    LMVTraceOriginal7 original = (LMVTraceOriginal7)LMVTraceSpecs[7].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(7, self, [NSString stringWithFormat:@"%@", LMVTraceClass(a)]) : 0;
    id result = original(self, cmd, a);
    if (call) LMVTraceEnd(7, call, LMVTraceClass(result));
    return result;
}

typedef void (*LMVTraceOriginal8)(id, SEL);
static void LMVTraceWrap8(id self, SEL cmd);
static void LMVTraceWrap8(id self, SEL cmd) {
    LMVTraceOriginal8 original = (LMVTraceOriginal8)LMVTraceSpecs[8].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(8, self, @"none") : 0;
    original(self, cmd);
    LMVTraceEnd(8, call, @"void");
}

typedef void (*LMVTraceOriginal9)(id, SEL);
static void LMVTraceWrap9(id self, SEL cmd);
static void LMVTraceWrap9(id self, SEL cmd) {
    LMVTraceOriginal9 original = (LMVTraceOriginal9)LMVTraceSpecs[9].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(9, self, @"none") : 0;
    original(self, cmd);
    LMVTraceEnd(9, call, @"void");
}

typedef id (*LMVTraceOriginal10)(id, SEL, id a);
static id LMVTraceWrap10(id self, SEL cmd, id a);
static id LMVTraceWrap10(id self, SEL cmd, id a) {
    LMVTraceOriginal10 original = (LMVTraceOriginal10)LMVTraceSpecs[10].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(10, self, [NSString stringWithFormat:@"%@", LMVTraceClass(a)]) : 0;
    id result = original(self, cmd, a);
    if (call) LMVTraceEnd(10, call, LMVTraceClass(result));
    return result;
}

typedef id (*LMVTraceOriginal11)(id, SEL, id a);
static id LMVTraceWrap11(id self, SEL cmd, id a);
static id LMVTraceWrap11(id self, SEL cmd, id a) {
    LMVTraceOriginal11 original = (LMVTraceOriginal11)LMVTraceSpecs[11].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(11, self, [NSString stringWithFormat:@"%@", LMVTraceClass(a)]) : 0;
    id result = original(self, cmd, a);
    if (call) LMVTraceEnd(11, call, LMVTraceClass(result));
    return result;
}

typedef void (*LMVTraceOriginal12)(id, SEL);
static void LMVTraceWrap12(id self, SEL cmd);
static void LMVTraceWrap12(id self, SEL cmd) {
    LMVTraceOriginal12 original = (LMVTraceOriginal12)LMVTraceSpecs[12].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(12, self, @"none") : 0;
    original(self, cmd);
    LMVTraceEnd(12, call, @"void");
}

typedef void (*LMVTraceOriginal13)(id, SEL);
static void LMVTraceWrap13(id self, SEL cmd);
static void LMVTraceWrap13(id self, SEL cmd) {
    LMVTraceOriginal13 original = (LMVTraceOriginal13)LMVTraceSpecs[13].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(13, self, @"none") : 0;
    original(self, cmd);
    LMVTraceEnd(13, call, @"void");
}

typedef void (*LMVTraceOriginal14)(id, SEL, id a);
static void LMVTraceWrap14(id self, SEL cmd, id a);
static void LMVTraceWrap14(id self, SEL cmd, id a) {
    LMVTraceOriginal14 original = (LMVTraceOriginal14)LMVTraceSpecs[14].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(14, self, [NSString stringWithFormat:@"%@", LMVTraceClass(a)]) : 0;
    original(self, cmd, a);
    LMVTraceEnd(14, call, @"void");
}

typedef void (*LMVTraceOriginal15)(id, SEL, id a, id b);
static void LMVTraceWrap15(id self, SEL cmd, id a, id b);
static void LMVTraceWrap15(id self, SEL cmd, id a, id b) {
    LMVTraceOriginal15 original = (LMVTraceOriginal15)LMVTraceSpecs[15].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(15, self, [NSString stringWithFormat:@"%@,%@", LMVTraceClass(a), LMVTraceClass(b)]) : 0;
    original(self, cmd, a, b);
    LMVTraceEnd(15, call, @"void");
}

typedef void (*LMVTraceOriginal16)(id, SEL, id a, id b, id c);
static void LMVTraceWrap16(id self, SEL cmd, id a, id b, id c);
static void LMVTraceWrap16(id self, SEL cmd, id a, id b, id c) {
    LMVTraceOriginal16 original = (LMVTraceOriginal16)LMVTraceSpecs[16].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(16, self, [NSString stringWithFormat:@"%@,%@,%@", LMVTraceClass(a), LMVTraceClass(b), LMVTraceClass(c)]) : 0;
    original(self, cmd, a, b, c);
    LMVTraceEnd(16, call, @"void");
}

typedef void (*LMVTraceOriginal17)(id, SEL, id a, id b, id c, id d);
static void LMVTraceWrap17(id self, SEL cmd, id a, id b, id c, id d);
static void LMVTraceWrap17(id self, SEL cmd, id a, id b, id c, id d) {
    LMVTraceOriginal17 original = (LMVTraceOriginal17)LMVTraceSpecs[17].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(17, self, [NSString stringWithFormat:@"%@,%@,%@,%@", LMVTraceClass(a), LMVTraceClass(b), LMVTraceClass(c), LMVTraceClass(d)]) : 0;
    original(self, cmd, a, b, c, d);
    LMVTraceEnd(17, call, @"void");
}

typedef void (*LMVTraceOriginal18)(id, SEL, id a);
static void LMVTraceWrap18(id self, SEL cmd, id a);
static void LMVTraceWrap18(id self, SEL cmd, id a) {
    LMVTraceOriginal18 original = (LMVTraceOriginal18)LMVTraceSpecs[18].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(18, self, [NSString stringWithFormat:@"%@", LMVTraceClass(a)]) : 0;
    original(self, cmd, a);
    LMVTraceEnd(18, call, @"void");
}

typedef void (*LMVTraceOriginal19)(id, SEL, id a, id b);
static void LMVTraceWrap19(id self, SEL cmd, id a, id b);
static void LMVTraceWrap19(id self, SEL cmd, id a, id b) {
    LMVTraceOriginal19 original = (LMVTraceOriginal19)LMVTraceSpecs[19].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(19, self, [NSString stringWithFormat:@"%@,%@", LMVTraceClass(a), LMVTraceClass(b)]) : 0;
    original(self, cmd, a, b);
    LMVTraceEnd(19, call, @"void");
}

typedef void (*LMVTraceOriginal20)(id, SEL, id a, id b);
static void LMVTraceWrap20(id self, SEL cmd, id a, id b);
static void LMVTraceWrap20(id self, SEL cmd, id a, id b) {
    LMVTraceOriginal20 original = (LMVTraceOriginal20)LMVTraceSpecs[20].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(20, self, [NSString stringWithFormat:@"%@,%@", LMVTraceClass(a), LMVTraceClass(b)]) : 0;
    original(self, cmd, a, b);
    LMVTraceEnd(20, call, @"void");
}

typedef void (*LMVTraceOriginal21)(id, SEL, id a);
static void LMVTraceWrap21(id self, SEL cmd, id a);
static void LMVTraceWrap21(id self, SEL cmd, id a) {
    LMVTraceOriginal21 original = (LMVTraceOriginal21)LMVTraceSpecs[21].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(21, self, [NSString stringWithFormat:@"%@", LMVTraceClass(a)]) : 0;
    original(self, cmd, a);
    LMVTraceEnd(21, call, @"void");
}

typedef void (*LMVTraceOriginal22)(id, SEL);
static void LMVTraceWrap22(id self, SEL cmd);
static void LMVTraceWrap22(id self, SEL cmd) {
    LMVTraceOriginal22 original = (LMVTraceOriginal22)LMVTraceSpecs[22].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(22, self, @"none") : 0;
    original(self, cmd);
    LMVTraceEnd(22, call, @"void");
}

typedef void (*LMVTraceOriginal23)(id, SEL, id a, id b);
static void LMVTraceWrap23(id self, SEL cmd, id a, id b);
static void LMVTraceWrap23(id self, SEL cmd, id a, id b) {
    LMVTraceOriginal23 original = (LMVTraceOriginal23)LMVTraceSpecs[23].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(23, self, [NSString stringWithFormat:@"%@,%@", LMVTraceClass(a), LMVTraceClass(b)]) : 0;
    original(self, cmd, a, b);
    LMVTraceEnd(23, call, @"void");
}

typedef void (*LMVTraceOriginal24)(id, SEL, id a);
static void LMVTraceWrap24(id self, SEL cmd, id a);
static void LMVTraceWrap24(id self, SEL cmd, id a) {
    LMVTraceOriginal24 original = (LMVTraceOriginal24)LMVTraceSpecs[24].original;
    unsigned long call = LMVTraceEnabled() ? LMVTraceBegin(24, self, [NSString stringWithFormat:@"%@", LMVTraceClass(a)]) : 0;
    original(self, cmd, a);
    LMVTraceEnd(24, call, @"void");
}
static void LMVTraceInitializeSpecs(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        LMVTraceSpecs[0].className = "PBUIPosterWallpaperRemoteViewController"; LMVTraceSpecs[0].selectorName = "newImageProviderView";
        LMVTraceSpecs[0].returnType = "@"; LMVTraceSpecs[0].count = 0; LMVTraceSpecs[0].replacement = (IMP)LMVTraceWrap0;
        LMVTraceSpecs[1].className = "PBUIPosterWallpaperRemoteViewController"; LMVTraceSpecs[1].selectorName = "updateImageProviderView:withImage:";
        LMVTraceSpecs[1].returnType = "B"; LMVTraceSpecs[1].count = 2; LMVTraceSpecs[1].replacement = (IMP)LMVTraceWrap1;
        LMVTraceSpecs[1].args[0] = "@";
        LMVTraceSpecs[1].args[1] = "@";
        LMVTraceSpecs[2].className = "PBUIPosterWallpaperRemoteViewController"; LMVTraceSpecs[2].selectorName = "imageForWallpaperStyle:variant:traitCollection:";
        LMVTraceSpecs[2].returnType = "@"; LMVTraceSpecs[2].count = 3; LMVTraceSpecs[2].replacement = (IMP)LMVTraceWrap2;
        LMVTraceSpecs[2].args[0] = "^q";
        LMVTraceSpecs[2].args[1] = "q";
        LMVTraceSpecs[2].args[2] = "@";
        LMVTraceSpecs[3].className = "PBUIPosterWallpaperRemoteViewController"; LMVTraceSpecs[3].selectorName = "requireWallpaperRasterizationWithReason:";
        LMVTraceSpecs[3].returnType = "@"; LMVTraceSpecs[3].count = 1; LMVTraceSpecs[3].replacement = (IMP)LMVTraceWrap3;
        LMVTraceSpecs[3].args[0] = "@";
        LMVTraceSpecs[4].className = "PBUIPosterWallpaperRemoteViewController"; LMVTraceSpecs[4].selectorName = "requireWallpaperWithReason:";
        LMVTraceSpecs[4].returnType = "@"; LMVTraceSpecs[4].count = 1; LMVTraceSpecs[4].replacement = (IMP)LMVTraceWrap4;
        LMVTraceSpecs[4].args[0] = "@";
        LMVTraceSpecs[5].className = "PBUIPosterWallpaperRemoteViewController"; LMVTraceSpecs[5].selectorName = "setWallpaperObscured:";
        LMVTraceSpecs[5].returnType = "v"; LMVTraceSpecs[5].count = 1; LMVTraceSpecs[5].replacement = (IMP)LMVTraceWrap5;
        LMVTraceSpecs[5].args[0] = "B";
        LMVTraceSpecs[6].className = "PBUIPosterWallpaperViewController"; LMVTraceSpecs[6].selectorName = "requireWallpaperRasterizationWithReason:";
        LMVTraceSpecs[6].returnType = "@"; LMVTraceSpecs[6].count = 1; LMVTraceSpecs[6].replacement = (IMP)LMVTraceWrap6;
        LMVTraceSpecs[6].args[0] = "@";
        LMVTraceSpecs[7].className = "PBUIPosterWallpaperViewController"; LMVTraceSpecs[7].selectorName = "requireWallpaperWithReason:";
        LMVTraceSpecs[7].returnType = "@"; LMVTraceSpecs[7].count = 1; LMVTraceSpecs[7].replacement = (IMP)LMVTraceWrap7;
        LMVTraceSpecs[7].args[0] = "@";
        LMVTraceSpecs[8].className = "PBUIPosterWallpaperViewController"; LMVTraceSpecs[8].selectorName = "updateLegacyPoster";
        LMVTraceSpecs[8].returnType = "v"; LMVTraceSpecs[8].count = 0; LMVTraceSpecs[8].replacement = (IMP)LMVTraceWrap8;
        LMVTraceSpecs[9].className = "PBUIPosterWallpaperViewController"; LMVTraceSpecs[9].selectorName = "triggerSceneUpdate";
        LMVTraceSpecs[9].returnType = "v"; LMVTraceSpecs[9].count = 0; LMVTraceSpecs[9].replacement = (IMP)LMVTraceWrap9;
        LMVTraceSpecs[10].className = "PBUIPosterViewController"; LMVTraceSpecs[10].selectorName = "requireWallpaperRasterizationWithReason:";
        LMVTraceSpecs[10].returnType = "@"; LMVTraceSpecs[10].count = 1; LMVTraceSpecs[10].replacement = (IMP)LMVTraceWrap10;
        LMVTraceSpecs[10].args[0] = "@";
        LMVTraceSpecs[11].className = "PBUIPosterViewController"; LMVTraceSpecs[11].selectorName = "requireWallpaperWithReason:";
        LMVTraceSpecs[11].returnType = "@"; LMVTraceSpecs[11].count = 1; LMVTraceSpecs[11].replacement = (IMP)LMVTraceWrap11;
        LMVTraceSpecs[11].args[0] = "@";
        LMVTraceSpecs[12].className = "PBUIPosterViewController"; LMVTraceSpecs[12].selectorName = "updateLegacyPoster";
        LMVTraceSpecs[12].returnType = "v"; LMVTraceSpecs[12].count = 0; LMVTraceSpecs[12].replacement = (IMP)LMVTraceWrap12;
        LMVTraceSpecs[13].className = "PBUIPosterViewController"; LMVTraceSpecs[13].selectorName = "triggerSceneUpdate";
        LMVTraceSpecs[13].returnType = "v"; LMVTraceSpecs[13].count = 0; LMVTraceSpecs[13].replacement = (IMP)LMVTraceWrap13;
        LMVTraceSpecs[14].className = "PBUIPosterVariantViewController"; LMVTraceSpecs[14].selectorName = "sceneLayerManagerDidUpdateLayers:";
        LMVTraceSpecs[14].returnType = "v"; LMVTraceSpecs[14].count = 1; LMVTraceSpecs[14].replacement = (IMP)LMVTraceWrap14;
        LMVTraceSpecs[14].args[0] = "@";
        LMVTraceSpecs[15].className = "PBUIPosterVariantViewController"; LMVTraceSpecs[15].selectorName = "scene:didApplyUpdateWithContext:";
        LMVTraceSpecs[15].returnType = "v"; LMVTraceSpecs[15].count = 2; LMVTraceSpecs[15].replacement = (IMP)LMVTraceWrap15;
        LMVTraceSpecs[15].args[0] = "@";
        LMVTraceSpecs[15].args[1] = "@";
        LMVTraceSpecs[16].className = "PBUIPosterVariantViewController"; LMVTraceSpecs[16].selectorName = "scene:didCompleteUpdateWithContext:error:";
        LMVTraceSpecs[16].returnType = "v"; LMVTraceSpecs[16].count = 3; LMVTraceSpecs[16].replacement = (IMP)LMVTraceWrap16;
        LMVTraceSpecs[16].args[0] = "@";
        LMVTraceSpecs[16].args[1] = "@";
        LMVTraceSpecs[16].args[2] = "@";
        LMVTraceSpecs[17].className = "PBUIPosterVariantViewController"; LMVTraceSpecs[17].selectorName = "scene:didUpdateClientSettingsWithDiff:oldClientSettings:transitionContext:";
        LMVTraceSpecs[17].returnType = "v"; LMVTraceSpecs[17].count = 4; LMVTraceSpecs[17].replacement = (IMP)LMVTraceWrap17;
        LMVTraceSpecs[17].args[0] = "@";
        LMVTraceSpecs[17].args[1] = "@";
        LMVTraceSpecs[17].args[2] = "@";
        LMVTraceSpecs[17].args[3] = "@";
        LMVTraceSpecs[18].className = "PBUIPosterVariantViewController"; LMVTraceSpecs[18].selectorName = "sceneDidActivate:";
        LMVTraceSpecs[18].returnType = "v"; LMVTraceSpecs[18].count = 1; LMVTraceSpecs[18].replacement = (IMP)LMVTraceWrap18;
        LMVTraceSpecs[18].args[0] = "@";
        LMVTraceSpecs[19].className = "PBUIPosterVariantViewController"; LMVTraceSpecs[19].selectorName = "sceneWillDeactivate:withError:";
        LMVTraceSpecs[19].returnType = "v"; LMVTraceSpecs[19].count = 2; LMVTraceSpecs[19].replacement = (IMP)LMVTraceWrap19;
        LMVTraceSpecs[19].args[0] = "@";
        LMVTraceSpecs[19].args[1] = "@";
        LMVTraceSpecs[20].className = "PBUIPosterVariantViewController"; LMVTraceSpecs[20].selectorName = "scene:clientDidConnect:";
        LMVTraceSpecs[20].returnType = "v"; LMVTraceSpecs[20].count = 2; LMVTraceSpecs[20].replacement = (IMP)LMVTraceWrap20;
        LMVTraceSpecs[20].args[0] = "@";
        LMVTraceSpecs[20].args[1] = "@";
        LMVTraceSpecs[21].className = "_UISceneLayerHostContainerView"; LMVTraceSpecs[21].selectorName = "sceneLayerManagerDidUpdateLayers:";
        LMVTraceSpecs[21].returnType = "v"; LMVTraceSpecs[21].count = 1; LMVTraceSpecs[21].replacement = (IMP)LMVTraceWrap21;
        LMVTraceSpecs[21].args[0] = "@";
        LMVTraceSpecs[22].className = "_UISceneLayerHostContainerView"; LMVTraceSpecs[22].selectorName = "_updateRenderingModeForLayersInNormalPresentation";
        LMVTraceSpecs[22].returnType = "v"; LMVTraceSpecs[22].count = 0; LMVTraceSpecs[22].replacement = (IMP)LMVTraceWrap22;
        LMVTraceSpecs[23].className = "_UIScenePresentationView"; LMVTraceSpecs[23].selectorName = "scene:didPrepareUpdateWithContext:";
        LMVTraceSpecs[23].returnType = "v"; LMVTraceSpecs[23].count = 2; LMVTraceSpecs[23].replacement = (IMP)LMVTraceWrap23;
        LMVTraceSpecs[23].args[0] = "@";
        LMVTraceSpecs[23].args[1] = "@";
        LMVTraceSpecs[24].className = "_UIScenePresentationView"; LMVTraceSpecs[24].selectorName = "sceneDidActivate:";
        LMVTraceSpecs[24].returnType = "v"; LMVTraceSpecs[24].count = 1; LMVTraceSpecs[24].replacement = (IMP)LMVTraceWrap24;
        LMVTraceSpecs[24].args[0] = "@";
    });
}
static const char *LMVTraceUnqualified(const char *type) {
    while (type && *type && strchr("rnNoORV", *type)) type++;
    return type;
}
static BOOL LMVTraceTypeMatches(const char *actual, const char *expected) {
    actual = LMVTraceUnqualified(actual);
    // Class annotations do not alter the Objective-C object calling convention.
    if (!strcmp(expected, "@")) return actual && actual[0] == '@' && actual[1] != '?';
    return actual && !strcmp(actual, expected);
}
static BOOL LMVTraceSignatureMatches(Method method, const LMVTraceSpec &spec) {
    if (method_getNumberOfArguments(method) != spec.count + 2) return NO;
    char *ret = method_copyReturnType(method);
    BOOL matches = LMVTraceTypeMatches(ret, spec.returnType); free(ret);
    for (unsigned i = 0; i < spec.count && matches; i++) {
        char *type = method_copyArgumentType(method, i + 2);
        matches = LMVTraceTypeMatches(type, spec.args[i]); free(type);
    }
    return matches;
}
static void LMVInstallWallpaperTrace(void) {
    // Executed at injection, then retried after class loading, on the main thread.
    std::lock_guard<std::mutex> guard(LMVTraceInstallMutex);
    LMVTraceInitializeSpecs();
    for (NSUInteger i = 0; i < LMVTraceCount; i++) {
        LMVTraceSpec &spec = LMVTraceSpecs[i];
        if (spec.original) continue;
        Class cls = objc_getClass(spec.className);
        if (!cls) { spec.status = "class-missing"; continue; }
        SEL selector = sel_registerName(spec.selectorName);
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) { spec.status = "method-missing"; continue; }
        if (!LMVTraceSignatureMatches(method, spec)) { spec.status = "signature-mismatch"; continue; }
        // Inherited entries are isolated on the requested concrete class. Exact
        // per-slot originals prevent recursion when an override calls super.
        IMP original = method_getImplementation(method);
        spec.original = original;
        if (class_addMethod(cls, selector, spec.replacement, method_getTypeEncoding(method))) {
            spec.owner = cls; spec.status = "installed-local-override";
        } else {
            Method local = class_getInstanceMethod(cls, selector);
            if (method_getImplementation(local) == spec.replacement) { spec.owner = cls; spec.status = "installed"; }
            else { spec.original = method_setImplementation(local, spec.replacement); spec.owner = cls; spec.status = "installed"; }
        }
        spec.announced = false;
    }
}
static void LMVReportWallpaperTrace(void) {
    if (!LMVTraceEnabled()) return;
    LMVInstallWallpaperTrace();
    static CFTimeInterval lastSummary;
    BOOL report = CACurrentMediaTime() - lastSummary >= 5.0;
    if (report) lastSummary = CACurrentMediaTime();
    std::lock_guard<std::mutex> guard(LMVTraceInstallMutex);
    for (NSUInteger i = 0; i < LMVTraceCount; i++) {
        LMVTraceSpec &spec = LMVTraceSpecs[i];
        Class cls = objc_getClass(spec.className);
        Method method = cls ? class_getInstanceMethod(cls, sel_registerName(spec.selectorName)) : NULL;
        BOOL ours = method && method_getImplementation(method) == spec.replacement;
        if (!spec.announced) {
            spec.announced = true;
            LMVTraceLog([NSString stringWithFormat:@"wallpaper-hook slot=%lu class=%s selector=%s status=%s currentIMP=%@ actualTypes=%s",
                (unsigned long)i, spec.className, spec.selectorName, spec.status ?: "pending",
                ours ? @"ours" : @"other", method ? method_getTypeEncoding(method) : "none"]);
        }
        if (report) LMVTraceLog([NSString stringWithFormat:@"wallpaper-coverage slot=%lu selector=%s hits=%lu records=%u currentIMP=%@ observation=%@",
            (unsigned long)i, spec.selectorName, spec.hits.load(), MIN(spec.emitted.load(),12U),
            ours ? @"ours" : @"other", spec.hits.load() ? @"called" : @"not-observed"]);
    }
}

static void LMVStartWallpaperTraceReports(void) {
    // Bounded checkpoints even with all video switches off. A later preferences
    // refresh also retries classes that were absent at injection.
    for (NSNumber *seconds in @[@1, @3, @8, @15, @30, @60])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(seconds.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            LMVInstallWallpaperTrace(); LMVReportWallpaperTrace();
        });
}
