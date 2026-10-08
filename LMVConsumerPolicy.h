#pragma once
#include <stdbool.h>
#include <string.h>
#include <math.h>
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
// Geometry must come from a concrete Dock content container, never window bounds.
static inline bool LMVDesktopDockRegionSafe(LMVDesktopRect dock, LMVDesktopRect home) {
    if (!isfinite(dock.x) || !isfinite(dock.y) || !isfinite(dock.width) || !isfinite(dock.height) ||
        !isfinite(home.x) || !isfinite(home.y) || !isfinite(home.width) || !isfinite(home.height) ||
        dock.width <= 1 || dock.height <= 1 || home.width <= 0 || home.height <= 0) return false;
    return dock.width <= home.width + 0.5 && dock.height < home.height / 2 &&
        dock.width * dock.height < home.width * home.height / 2 &&
        dock.x < home.x + home.width && dock.y < home.y + home.height &&
        dock.x + dock.width > home.x && dock.y + dock.height > home.y;
}
typedef struct { bool retainFrame, decode; } LMVDesktopDecision;
static inline LMVDesktopDecision LMVDesktopDecide(bool homeHost, bool homeWindow, bool attached,
    bool visible, bool screenOn, bool lockKnown, bool locked, LMVForeground foreground, bool fullyCovered,
    bool contextOverlay) {
    LMVDesktopDecision decision;
    decision.retainFrame = homeHost && homeWindow && attached && screenOn && lockKnown && !locked;
    decision.decode = decision.retainFrame && visible && foreground == LMVForegroundHome && !fullyCovered;
    (void)contextOverlay; // Home menus do not obscure the entire desktop.
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
    LMVDesktopActivity activity = { decision.retainFrame, false, false,
                                   decision.retainFrame && dockBelow };
    if (!decision.retainFrame) {
        clock->transientSince = clock->offscreenSince = 0;
        activity.releaseSource = true;
        return activity;
    }
    bool app = foreground == LMVForegroundApp;
    bool unknown = foreground == LMVForegroundUnknown;
    bool home = foreground == LMVForegroundHome || (unknown && homeKey && visible && !covered && !context);
    bool transient = unknown || context || foreground == LMVForegroundOverlay;
    if (transient) { if (!clock->transientSince) clock->transientSince = now; }
    else clock->transientSince = 0;
    // A home context menu/Dock overlay keeps live video. Concrete app, full NC,
    // invisible host, lock and screen off still override every transition hint.
    bool overlayHome = (context || foreground == LMVForegroundOverlay) &&
        (foreground == LMVForegroundHome || homeKey || wasDecoding);
    bool settledHome = home && (!unknown || now - clock->transientSince >= 0.15);
    bool grace = transient && now - clock->transientSince < 0.15 && wasDecoding;
    activity.decode = visible && !app && !covered && (settledHome || overlayHome || grace);
    // Confirmed app/offscreen: pause immediately and retire unused media after
    // 1.25s. Full NC retains a paused source without frame pulls.
    bool offscreen = app || (!visible && !covered);
    if (offscreen) { if (!clock->offscreenSince) clock->offscreenSince = now; }
    else clock->offscreenSince = 0;
    activity.releaseSource = offscreen && now - clock->offscreenSince >= 1.25;
    return activity;
}
