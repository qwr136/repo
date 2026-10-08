#pragma once
#include <stdbool.h>
// Shared by the actual UIKit consumer and the exhaustive portable gate test.
static inline bool LMVLockConsumerAllowed(bool coverHost, bool coverWindow, bool visible, bool screenOn) {
    return coverHost && coverWindow && visible && screenOn;
}
// Unknown visibility/foreground state must never start a desktop decoder.
static inline bool LMVDesktopConsumerAllowed(bool homeHost, bool homeWindow, bool visible, bool screenOn,
                                             bool locked, bool foregroundKnown, bool foregroundHome, bool covered) {
    return homeHost && homeWindow && visible && screenOn && !locked && foregroundKnown && foregroundHome && !covered;
}
