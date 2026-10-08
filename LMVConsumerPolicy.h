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
