#pragma once
// 4.0.9: eight helper routines that every floating-panel header used to carry a
// private copy of. Each copy was byte-identical to the others, so a fix had to be
// applied 2-8 times and one panel (Myrtle's coverage counter) had already drifted
// without any comment saying whether the drift was intentional.
//
// The panels are separate headers compiled into one translation unit, which is why
// their copies had to carry a per-panel prefix: two `static` functions cannot share
// a name in the same unit. Defining each routine once here removes that constraint -
// there is now exactly one definition, and every panel calls it.
//
// Every routine keeps the exact body it had in the panel headers. Nothing about
// scoring, thresholds, log formats or thresholds changed in this move.
//
// Standalone fixtures compile a single panel header in a temp directory with no
// include path, so they cannot see this file; each panel keeps a `#if
// __has_include` guard and the fixtures copy this header next to their source.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <math.h>
#import <string.h>

// The window snapshot and the glass test both need a view's class name. The real
// probe caches it on the view; a fixture that compiled one header alone has no
// probe, so fall back to the plain lookup. This stays behind a private name: the
// panel headers define their own LMVProbeClassName fallback when the probe is
// missing, and defining that same symbol here would collide with it.
#if __has_include("LMVProbeWindows.h")
#import "LMVProbeWindows.h"
#define LMVCommonClassName(view) LMVProbeClassName(view)
#else
static inline NSString *LMVCommonClassName(UIView *view) {
    return view ? (NSStringFromClass(view.class) ?: @"") : @"";
}
#endif

// The desktop and the exit hooks all ask the same question before touching
// SpringBoard-only state.
static inline BOOL LMVSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}

// How much of this view is REALLY on screen. A card that is mostly parked off
// screen is never a candidate, so under half is reported as zero.
//
// This rule is what keeps a mounted video off a hidden copy of the card. Several
// channels keep more than one: the 1.25 Squid capture showed two 430x435 activity
// panels, one at y=497 and one parked at y=1459 in a 932-high window, and scoring by
// raw area made the choice flip between them as the tree order changed - the video
// kept landing on the invisible one, which is what "看不到视频背景" was. CopyVault has
// the same shape with its card parked at y=1454 while the panel is closed.
static inline CGFloat LMVVisibleArea(CGRect frame, CGRect bounds) {
    if (CGRectIsEmpty(frame) || CGRectIsEmpty(bounds)) return 0;
    CGRect onScreen = CGRectIntersection(frame, bounds);
    if (CGRectIsEmpty(onScreen)) return 0;
    CGFloat total = frame.size.width * frame.size.height;
    if (total <= 0) return 0;
    CGFloat visible = onScreen.size.width * onScreen.size.height;
    return visible / total >= .5 ? visible : 0;
}

// Text colour is re-applied only when it actually differs; UIColor equality on the
// same colour space is not reliable enough for a per-view comparison.
static inline BOOL LMVColorEqual(UIColor *a, UIColor *b) {
    if (!a || !b) return a == b;
    CGFloat ar = 0, ag = 0, ab = 0, aa = 0, br = 0, bg = 0, bb = 0, ba = 0;
    if (![a getRed:&ar green:&ag blue:&ab alpha:&aa] || ![b getRed:&br green:&bg blue:&bb alpha:&ba]) return [a isEqual:b];
    return fabs(ar - br) < .002 && fabs(ag - bg) < .002 && fabs(ab - bb) < .002 && fabs(aa - ba) < .002;
}

// Two-second window per channel: the log stays readable and one slow frame shows up
// as max= instead of being averaged away. Returns nil until the window closes.
static inline NSString *LMVPerfSample(const char *channel, CFTimeInterval seconds) {
    static NSUInteger calls = 0, slow = 0;
    static CFTimeInterval maxSeconds = 0, windowStart = 0;
    CFTimeInterval now = CACurrentMediaTime();
    if (windowStart <= 0) windowStart = now;
    calls++;
    if (seconds > maxSeconds) maxSeconds = seconds;
    if (seconds > 0.004) slow++;
    if (now - windowStart < 2.0) return nil;
    NSString *report = [NSString stringWithFormat:@"perf %s calls=%lu max=%.2fms slow=%lu",
                        channel, (unsigned long)calls, maxSeconds * 1000.0, (unsigned long)slow];
    calls = 0; slow = 0; maxSeconds = 0; windowStart = now;
    return report;
}

// One scene walk, capped so a diagnostic line never grows without bound. This is the
// answer to "the panel window was never found" - print what the window list actually
// holds instead of failing silently, because "no panel lines at all" could mean the
// switch is off, there is no material, or the panel lives in a window never scanned,
// and those are three completely different fixes.
static inline NSString *LMVWindowReportSnapshot(void) {
    NSMutableString *out = [NSMutableString new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (out.length > 900) break;
            [out appendFormat:@"%@(h%d,a%.2f,%.0fx%.0f,lv%.0f,sub%lu) ",
             LMVCommonClassName(window), (int)window.hidden, window.alpha,
             window.frame.size.width, window.frame.size.height, window.windowLevel,
             (unsigned long)window.subviews.count];
        }
    }
    return out.length ? out : @"none";
}

// Blur/glass detection by class name. Content views are excluded by name before the
// keyword scan, because a glass platter's own content view also carries "Effect" in
// its class name. 2.29 device capture: the GlassSuite card itself is
// _UIVisualEffectContentView - treating it as glass skipped the real card and
// mounted the video above the whole sheet.
static inline BOOL LMVGlassLikeView(UIView *view) {
    if (!view) return NO;
    if ([view isKindOfClass:UIVisualEffectView.class]) return YES;
    NSString *name = LMVCommonClassName(view);
    if ([name containsString:@"ContentView"]) return NO;
    for (NSString *word in @[@"Blur", @"Glass", @"Vibrancy", @"Dimming", @"Backdrop", @"Effect"])
        if ([name rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}

// A private getter is only safe to call when it takes no arguments and returns an
// object; anything else would read garbage off the stack.
static inline BOOL LMVObjectGetterFor(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments == 2 && !strcmp(signature.methodReturnType, @encode(id));
}

// The visual-effect view that actually covers a card, not one of its decorations.
// A layer must cover at least 85% of the card to qualify, and the largest wins.
static inline UIView *LMVMaterialBehindCard(UIView *root, UIWindow *window) {
    if (!root || !window) return nil;
    CGRect cardFrame = [root convertRect:root.bounds toView:window];
    if (CGRectIsEmpty(cardFrame)) return nil;
    CGFloat cardArea = cardFrame.size.width * cardFrame.size.height;
    if (cardArea <= 0) return nil;
    UIView *best = nil; CGFloat bestArea = 0;
    NSMutableArray *pending = [NSMutableArray arrayWithObject:(id)root];
    NSUInteger budget = 300;
    while (pending.count && budget) {
        UIView *node = pending.lastObject; [pending removeLastObject];
        for (UIView *child in node.subviews) {
            if (!budget--) break;
            [pending addObject:child];
            if (![child isKindOfClass:UIVisualEffectView.class] || child.hidden || child.alpha < .01) continue;
            CGRect frame = [child convertRect:child.bounds toView:window];
            CGRect cover = CGRectIntersection(frame, cardFrame);
            if (CGRectIsEmpty(cover)) continue;
            CGFloat area = cover.size.width * cover.size.height;
            if (area / cardArea < .85) continue;
            if (area > bestArea) { bestArea = area; best = child; }
        }
    }
    return best;
}
