#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <stdlib.h>
#include <string.h>

// Override in a standalone trace test. Production increments this on each
// diagnostic toggle; no dependency on UIKit, private headers or private getters.
#ifndef LMVTraceEpoch
#ifdef LMV_TRACE_TEST
#define LMVTraceEpoch() 0UL
#else
#define LMVTraceEpoch() LMVDiagnosticEpoch.load()
#endif
#endif

static NSString *LMVWallpaperMetadataName(Class cls) {
    const char *name = cls ? class_getName(cls) : NULL;
    return name ? [NSString stringWithUTF8String:name] : @"nil";
}
static NSString *LMVWallpaperMetadataModule(Class cls) {
    const char *image = cls ? class_getImageName(cls) : NULL;
    // Only the loaded module name, never a user asset path.
    return image ? [[NSString stringWithUTF8String:image] lastPathComponent] : @"unknown";
}
static NSString *LMVWallpaperObservedTarget(Class cls) {
    // Exact observed ancestry, not a variant-number convention or name substring.
    for (NSUInteger n = 0; cls && n < 16; n++, cls = class_getSuperclass(cls)) {
        const char *name = class_getName(cls);
        if (!strcmp(name, "CSCoverSheetView") || !strcmp(name, "SBCoverSheetWindow") ||
            !strcmp(name, "CSCoverSheetViewController") || !strcmp(name, "PBUIPosterLockViewController")) return @"LockScreen";
    }
    return @"unknown";
}
static BOOL LMVWallpaperRelevantMetadata(NSString *name) {
    NSString *lower = name.lowercaseString;
    for (NSString *token in @[@"wallpaper", @"poster", @"image", @"provider", @"scene",
                              @"render", @"asset", @"controller", @"client", @"process", @"pid", @"identifier", @"identity"])
        if ([lower containsString:token]) return YES;
    return NO;
}
static void LMVWallpaperDiagnosticClass(Class cls, NSString *kind, Class owner) {
    if (!cls || !LMVTraceEnabled()) return;
    // One shared budget for providers, scenes, actual callback clients and hosts.
    // No object values are retained. Reflection occurs only once/class/session.
    static NSObject *lock = [NSObject new];
    static NSMutableSet<NSString *> *seen = [NSMutableSet new];
    static NSMutableSet<NSString *> *edges = [NSMutableSet new];
    static unsigned long epoch = ~0UL;
    @synchronized (lock) {
        unsigned long currentEpoch = LMVTraceEpoch();
        if (epoch != currentEpoch) { epoch = currentEpoch; [seen removeAllObjects]; [edges removeAllObjects]; }
        NSString *name = LMVWallpaperMetadataName(cls);
        NSString *edge = [NSString stringWithFormat:@"%@|%@|%@", name, LMVWallpaperMetadataName(owner), kind];
        if (edges.count < 96 && ![edges containsObject:edge]) {
            [edges addObject:edge];
            LMVTraceLog([NSString stringWithFormat:@"wallpaper-metadata kind=%@ class=%@ module=%@ owner=%@ target=%@ targetEvidence=observed-owner-ancestry realPID=unknown clientIdentity=not-read epoch=%lu",
                kind, name, LMVWallpaperMetadataModule(cls), LMVWallpaperMetadataName(owner),
                LMVWallpaperObservedTarget(owner ?: cls), epoch]);
        }
        if (seen.count >= 24 || [seen containsObject:name]) return;
        [seen addObject:name];
        NSUInteger methodsEmitted = 0, fieldsEmitted = 0, depth = 0;
        for (Class current = cls; current && current != NSObject.class && depth < 8;
             current = class_getSuperclass(current), depth++) {
            LMVTraceLog([NSString stringWithFormat:@"wallpaper-inheritance class=%@ depth=%lu declaredBy=%@ module=%@ superclass=%@",
                name, (unsigned long)depth, LMVWallpaperMetadataName(current), LMVWallpaperMetadataModule(current),
                LMVWallpaperMetadataName(class_getSuperclass(current))]);
            if (methodsEmitted < 16) {
                unsigned int count = 0;
                Method *methods = class_copyMethodList(current, &count);
                for (unsigned int i = 0; i < count && methodsEmitted < 16; i++) {
                    NSString *selector = NSStringFromSelector(method_getName(methods[i]));
                    if (!LMVWallpaperRelevantMetadata(selector)) continue;
                    const char *types = method_getTypeEncoding(methods[i]);
                    LMVTraceLog([NSString stringWithFormat:@"wallpaper-provider-method class=%@ declaredBy=%@ selector=%@ types=%s argc=%u evidence=metadata-only",
                        name, LMVWallpaperMetadataName(current), selector, types ?: "?", method_getNumberOfArguments(methods[i])]);
                    methodsEmitted++;
                }
                free(methods);
            }
            if (fieldsEmitted < 8) {
                unsigned int count = 0;
                Ivar *ivars = class_copyIvarList(current, &count);
                for (unsigned int i = 0; i < count && fieldsEmitted < 8; i++) {
                    const char *key = ivar_getName(ivars[i]);
                    if (!key || !LMVWallpaperRelevantMetadata([NSString stringWithUTF8String:key])) continue;
                    const char *type = ivar_getTypeEncoding(ivars[i]);
                    LMVTraceLog([NSString stringWithFormat:@"wallpaper-field class=%@ declaredBy=%@ name=%s declaredType=%s evidence=declaration-only value=not-read",
                        name, LMVWallpaperMetadataName(current), key, type ?: "?"]);
                    fieldsEmitted++;
                }
                free(ivars);
            }
        }
    }
}
static void LMVWallpaperDiagnosticObserved(id value, id owner, NSString *kind) {
    if (!value || !LMVTraceEnabled()) return;
    @try {
        // Both arguments are actual typed Objective-C objects from existing
        // verified wrappers. No ivar dereference or private selector invocation.
        LMVWallpaperDiagnosticClass(object_getClass(value), kind, owner ? object_getClass(owner) : Nil);
    } @catch (NSException *exception) {}
}
