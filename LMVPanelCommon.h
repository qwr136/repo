#pragma once
// 4.0.9: helper routines that every floating-panel header used to carry a private
// copy of. Each copy was byte-identical to the others, so a fix had to be applied
// 2-8 times, and one panel (Myrtle's coverage counter) had already drifted without
// any comment saying whether the drift was intentional.
//
// The panels are separate headers compiled into one translation unit, which is why
// their copies had to carry a per-panel prefix: two `static` functions cannot share
// a name in the same unit. Defining each routine once here removes that constraint -
// there is now exactly one definition, and every panel calls it.
//
// Every routine keeps the exact body it had in the panel headers. Nothing about
// scoring, thresholds or log formats changed in this move.
//
// This half stays free of UIKit view classes so a native fixture that only declares
// Foundation types can still compile a panel that uses the viewport rule. The
// helpers that need UIColor/UIScene/UIVisualEffectView live in LMVPanelCommonUI.h.
//
// Fixtures compile one panel header in a temp directory, so they copy both headers
// next to their source and prepend the import themselves - the panel headers put
// their imports at the top, and a fixture that slices the file from the first
// function down would otherwise cut them off.

#import <QuartzCore/QuartzCore.h>
#import <Foundation/Foundation.h>
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
