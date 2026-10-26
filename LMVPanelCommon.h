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

// Two-second window per channel: the log stays readable and one slow frame shows up
// as max= instead of being averaged away. Returns nil until the window closes.
// 4.4.1: one bucket PER CHANNEL NAME. Several channels can share a translation
// unit (cards and bubble both live in Tweak.xm), and a single set of statics mixed
// their counts into one line - the number then described neither channel.
static inline NSString *LMVPerfSample(const char *channel, CFTimeInterval seconds) {
    // 4.4.3: 8 slots were not enough - Tweak.xm hosts eleven channels (nine panels
    // plus cards and bubble), so pa/cards/bubble were dropped WITHOUT a word and the
    // log looked complete. 24 leaves room, and the drop count travels on every line.
    static const char *names[24] = {0};
    static NSUInteger calls[24] = {0}, slow[24] = {0};
    static CFTimeInterval maxSeconds[24] = {0}, windowStart[24] = {0};
    static NSUInteger used = 0, dropped = 0;
    NSUInteger slot = 0;
    BOOL found = NO;
    for (NSUInteger i = 0; i < used; i++) {
        if (names[i] && channel && strcmp(names[i], channel) == 0) { slot = i; found = YES; break; }
    }
    if (!found) {
        if (used >= 24) { dropped++; return nil; }
        names[used] = channel; slot = used; used++;
    }
    CFTimeInterval now = CACurrentMediaTime();
    if (windowStart[slot] <= 0) windowStart[slot] = now;
    calls[slot]++;
    if (seconds > maxSeconds[slot]) maxSeconds[slot] = seconds;
    if (seconds > 0.004) slow[slot]++;
    if (now - windowStart[slot] < 2.0) return nil;
    NSString *report = [NSString stringWithFormat:@"perf %s calls=%lu max=%.2fms slow=%lu dropped=%lu",
                        channel, (unsigned long)calls[slot], maxSeconds[slot] * 1000.0,
                        (unsigned long)slow[slot], (unsigned long)dropped];
    calls[slot] = 0; slow[slot] = 0; maxSeconds[slot] = 0; windowStart[slot] = now;
    return report;
}

// 5.1.4: the floating "背景视频" panel covers the whole screen while it is open, so
// the desktop watcher can discover nothing and its 10-13 ms probe is pure cost.
// One owner (the panel's open/close) writes it, the desktop channel reads it.
static inline BOOL *LMVEasterPanelQuietFlag(void) {
    static BOOL quiet = NO;
    return &quiet;
}

// A private getter is only safe to call when it takes no arguments and returns an
// object; anything else would read garbage off the stack.
static inline BOOL LMVObjectGetterFor(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments == 2 && !strcmp(signature.methodReturnType, @encode(id));
}
