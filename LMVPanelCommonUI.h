#pragma once
// 4.0.9: the helpers that need a real UIKit view class.
//
// Kept apart from LMVPanelCommon.h because the native fixtures compile a single
// panel header against hand-written UIKit doubles: they can always provide
// Foundation/CoreGraphics, but only some of them declare UIColor/UIScene. Splitting
// the file means a panel that only needs the viewport rule does not drag the rest in.
#import <UIKit/UIKit.h>
#import "LMVPanelCommon.h"

// The class name is needed by the window snapshot and the glass test. The probe
// caches it on the view; a fixture that compiled one panel header alone has none, so
// fall back to the plain lookup. Kept behind a private name: the panel headers define
// their own LMVProbeClassName fallback and defining that symbol here would collide.
#if __has_include("LMVProbeWindows.h")
#import "LMVProbeWindows.h"
#define LMVCommonClassName(view) LMVProbeClassName(view)
#else
static inline NSString *LMVCommonClassName(id view) {
    return view ? (NSStringFromClass([view class]) ?: @"") : @"";
}
#endif

// Text colour is re-applied only when it actually differs; UIColor equality on the
// same colour space is not reliable enough for a per-view comparison.
static inline BOOL LMVColorEqual(UIColor *a, UIColor *b) {
    if (!a || !b) return a == b;
    CGFloat ar = 0, ag = 0, ab = 0, aa = 0, br = 0, bg = 0, bb = 0, ba = 0;
    if (![a getRed:&ar green:&ag blue:&ab alpha:&aa] || ![b getRed:&br green:&bg blue:&bb alpha:&ba]) return [a isEqual:b];
    return fabs(ar - br) < .002 && fabs(ag - bg) < .002 && fabs(ab - bb) < .002 && fabs(aa - ba) < .002;
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
