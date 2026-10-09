#pragma once
#include <math.h>
static inline double LMVEasterBoundedSize(double size) {
    return isfinite(size) ? fmax(32, fmin(128, size)) : 64;
}
typedef struct { double x, y, width, height; } LMVEasterRect;
static inline LMVEasterRect LMVEasterCenterArea(LMVEasterRect safe, double size) {
    size = LMVEasterBoundedSize(size);
    LMVEasterRect area = {
        safe.x + (safe.width >= size ? size / 2 : safe.width / 2),
        safe.y + (safe.height >= size ? size / 2 : safe.height / 2),
        fmax(0, safe.width - size), fmax(0, safe.height - size)
    };
    return area;
}
static inline double LMVEasterNormalizedPosition(double position, double origin, double span) {
    return span > 0 ? fmax(0, fmin(1, (position - origin) / span)) : .5;
}
