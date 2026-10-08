#pragma once
#include <stdbool.h>
#include <string.h>
static inline bool LMVLockConsumerAllowed(bool coverHost, bool coverWindow, bool visible, bool screenOn) {
    return coverHost && coverWindow && visible && screenOn;
}
typedef enum { LMVWindowOther, LMVWindowHome, LMVWindowFloatingDock } LMVWindowRole;
typedef enum { LMVForegroundUnknown, LMVForegroundHome, LMVForegroundOverlay, LMVForegroundApp } LMVForeground;
// Only runtime superclass names are passed here; no window visibility is changed.
static inline LMVWindowRole LMVDesktopWindowRole(const char *name) {
    if (!name) return LMVWindowOther;
    if (!strcmp(name, "SBHomeScreenWindow")) return LMVWindowHome;
    if (!strcmp(name, "SBFloatingDockWindow")) return LMVWindowFloatingDock;
    return LMVWindowOther;
}
static inline LMVForeground LMVDesktopResolveForeground(bool bundleKnown, bool bundleHome,
                                                       bool missing, LMVWindowRole role, bool homeController) {
    // An actual foreground application always wins over a visible floating Dock.
    if (bundleKnown) return bundleHome ? LMVForegroundHome : LMVForegroundApp;
    if (role == LMVWindowFloatingDock) return LMVForegroundOverlay;
    if (homeController) return LMVForegroundOverlay;
    if (missing && role == LMVWindowHome) return LMVForegroundHome;
    return LMVForegroundUnknown;
}
typedef struct { double x, y, width, height; } LMVDesktopRect;
static inline bool LMVDesktopRectCovers(LMVDesktopRect cover, LMVDesktopRect home) {
    return home.width > 0 && home.height > 0 && cover.width > 0 && cover.height > 0 &&
        cover.x <= home.x + 0.5 && cover.y <= home.y + 0.5 &&
        cover.x + cover.width >= home.x + home.width - 0.5 &&
        cover.y + cover.height >= home.y + home.height - 0.5;
}
static inline bool LMVDesktopFullyCovered(LMVDesktopRect model, LMVDesktopRect presentation,
                                         LMVDesktopRect home, bool opaque) {
    return opaque && LMVDesktopRectCovers(model, home) && LMVDesktopRectCovers(presentation, home);
}
typedef struct { bool retainFrame, decode; } LMVDesktopDecision;
static inline LMVDesktopDecision LMVDesktopDecide(bool homeHost, bool homeWindow, bool attached,
    bool visible, bool screenOn, bool lockKnown, bool locked, LMVForeground foreground, bool fullyCovered,
    bool contextOverlay) {
    LMVDesktopDecision decision;
    decision.retainFrame = homeHost && homeWindow && attached && screenOn && lockKnown && !locked;
    decision.decode = decision.retainFrame && visible && foreground == LMVForegroundHome &&
        !fullyCovered && !contextOverlay;
    return decision;
}
// An attached owned layer keeps its position across system context-menu snapshots.
static inline bool LMVDesktopShouldAttach(bool alreadyAttached) { return !alreadyAttached; }
// One snapshot drives drawing, consumption and resource lifetime. Unknown frontmost
// objects are transitions, not evidence of an application. Home key + no cover/lock
// is a strong return signal; brief ambiguity never destroys a shared source.
typedef struct { double transientSince, offscreenSince; } LMVDesktopGateClock;
typedef struct { bool draw, decode, releaseSource, dockFallback; } LMVDesktopActivity;
static inline bool LMVDesktopDockBelow(bool sameScreen, bool dockVisible, double dockLevel,
                                      double homeLevel, bool intersects) {
    return sameScreen && dockVisible && intersects && dockLevel < homeLevel;
}
static inline LMVDesktopActivity LMVDesktopGate(LMVDesktopDecision decision, LMVForeground foreground,
    bool homeKey, bool visible, bool covered, bool context, bool dockBelow, bool wasDecoding,
    double now, LMVDesktopGateClock *clock) {
    LMVDesktopActivity activity = { decision.retainFrame && !dockBelow, false, false,
                                   decision.retainFrame && dockBelow };
    if (!decision.retainFrame) {
        clock->transientSince = clock->offscreenSince = 0;
        activity.releaseSource = true;
        return activity;
    }
    bool app = foreground == LMVForegroundApp;
    bool unknown = foreground == LMVForegroundUnknown;
    bool home = foreground == LMVForegroundHome || (unknown && homeKey && visible && !covered && !context);
    bool transient = unknown || context || foreground == LMVForegroundOverlay || dockBelow;
    if (transient) { if (!clock->transientSince) clock->transientSince = now; }
    else clock->transientSince = 0;
    // At most 150ms of grace for ambiguous transitions; never for a real app,
    // hidden host, full cover, lock, screen off, or a lower Dock window.
    bool settledHome = home && (!unknown || now - clock->transientSince >= 0.15);
    bool grace = transient && now - clock->transientSince < 0.15 && wasDecoding;
    activity.decode = visible && !app && !covered && !dockBelow &&
        ((settledHome && !context) || grace);
    // Confirmed app/offscreen: pause immediately and retire unused media after
    // 1.25s. Full NC/context retains a paused source without frame pulls.
    bool offscreen = app || (!visible && !covered);
    if (offscreen) { if (!clock->offscreenSince) clock->offscreenSince = now; }
    else clock->offscreenSince = 0;
    activity.releaseSource = offscreen && now - clock->offscreenSince >= 1.25;
    return activity;
}
