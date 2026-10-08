#pragma once
#include <stdbool.h>
// Shared by the actual UIKit consumer and the exhaustive portable gate test.
static inline bool LMVLockConsumerAllowed(bool coverHost, bool coverWindow, bool visible, bool screenOn) {
    return coverHost && coverWindow && visible && screenOn;
}
