#pragma once
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 5.22: nine channel headers carried a byte-identical copy of this routine
// (each had to define it so a single header could be compiled on its own).
// One definition here removes eight copies without changing the behaviour:
// a view's class never changes, so the name is computed once per view.
static inline NSString *LMVProbeClassName(UIView *view) {
    if (!view) return @"";
    static char kLMVProbeClassNameKey;
    NSString *cached = objc_getAssociatedObject(view, &kLMVProbeClassNameKey);
    if (cached) return cached;
    cached = NSStringFromClass(view.class) ?: @"";
    objc_setAssociatedObject(view, &kLMVProbeClassNameKey, cached, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return cached;
}
