#pragma once
#include <stdbool.h>
#include <string.h>
#include <math.h>
static inline bool LMVLockConsumerAllowed(bool coverHost, bool coverWindow, bool visible, bool screenOn) {
    return coverHost && coverWindow && visible && screenOn;
}
