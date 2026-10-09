#include <assert.h>
#include <stdio.h>
#include "../LMVEasterGeometry.h"
int main(void) {
    assert(LMVEasterBoundedSize(NAN) == 64 && LMVEasterBoundedSize(INFINITY) == 64);
    assert(LMVEasterBoundedSize(0) == 32 && LMVEasterBoundedSize(999) == 128);
    LMVEasterRect portrait = {8, 67, 374, 735}, landscape = {67, 8, 710, 327};
    for (int size = 32; size <= 128; size++) {
        assert(LMVEasterBoundedSize(size) == size);
        for (int rotation = 0; rotation < 2; rotation++) {
            LMVEasterRect safe = rotation ? landscape : portrait;
            LMVEasterRect area = LMVEasterCenterArea(safe, size);
            for (int x = 0; x <= 10; x++) for (int y = 0; y <= 10; y++) {
                double cx = area.x + area.width * x / 10., cy = area.y + area.height * y / 10.;
                assert(cx-size/2. >= safe.x-1e-8 && cx+size/2. <= safe.x+safe.width+1e-8);
                assert(cy-size/2. >= safe.y-1e-8 && cy+size/2. <= safe.y+safe.height+1e-8);
                assert(fabs(LMVEasterNormalizedPosition(cx,area.x,area.width)-x/10.)<1e-8);
                assert(fabs(LMVEasterNormalizedPosition(cy,area.y,area.height)-y/10.)<1e-8);
            }
        }
    }
    LMVEasterRect tiny = LMVEasterCenterArea((LMVEasterRect){0,0,20,20},128);
    assert(tiny.x==10 && tiny.y==10 && tiny.width==0 && tiny.height==0);
    assert(LMVEasterNormalizedPosition(-200,20,300)==0 && LMVEasterNormalizedPosition(999,20,300)==1);
    assert(LMVEasterNormalizedPosition(50,50,0)==.5);
    puts("PASS: production size clamp, all 32-128 pt sizes, 23,474 normalized centers across safe portrait/landscape, bounded degenerate area");
    return 0;
}
