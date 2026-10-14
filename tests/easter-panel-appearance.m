#include <assert.h>
#include <math.h>
#include <stdio.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include "../LMVEasterPanelAppearance.h"

// 0.0.122: the floating panel's corner radius and width/height. These rules are
// shared by the Settings app and the panel's own page, so they are executed here
// rather than trusted to a string match.
int main(void) {
    // Corner radius: an untouched install keeps the exact previous 20 pt.
    assert(LMVEasterResolvedPanelCorner(nil, nil, 20.0) == 20.0);
    assert(LMVEasterResolvedPanelCorner(@YES, nil, 20.0) == 20.0);
    assert(LMVEasterResolvedPanelCorner(@NO, @44, 20.0) == 20.0);
    assert(LMVEasterResolvedPanelCorner(@YES, @44, 20.0) == 44.0);
    // Bounded on both sides, and a non-finite input cannot escape the range.
    assert(LMVEasterResolvedPanelCorner(@YES, @(-5), 20.0) == 0.0);
    assert(LMVEasterResolvedPanelCorner(@YES, @999, 20.0) == 60.0);
    assert(LMVEasterResolvedPanelCorner(@YES, @(NAN), 20.0) == 0.0);
    assert(LMVEasterResolvedPanelCorner(@YES, @(INFINITY), 20.0) == 60.0);
    assert(LMVEasterResolvedPanelCorner(@YES, @"not-a-number", 20.0) == 20.0);

    // Panel size: OFF by default, so the automatic size is returned untouched.
    CGSize automatic = CGSizeMake(360, 550);
    CGSize untouched = LMVEasterResolvedPanelSize(nil, nil, nil, automatic);
    assert(untouched.width == 360 && untouched.height == 550);
    CGSize disabled = LMVEasterResolvedPanelSize(@NO, @0.5, @1.5, automatic);
    assert(disabled.width == 360 && disabled.height == 550);
    CGSize scaled = LMVEasterResolvedPanelSize(@YES, @0.5, @1.5, automatic);
    assert(scaled.width == 180 && scaled.height == 825);
    CGSize held = LMVEasterResolvedPanelSize(@YES, @1.0, @1.0, automatic);
    assert(held.width == 360 && held.height == 550);
    // 10% / 900% clamp onto the supported range.
    CGSize bounded = LMVEasterResolvedPanelSize(@YES, @0.1, @9.0, automatic);
    assert(bounded.width == 180 && bounded.height == 825);

    // Clamp helper itself: low on non-finite, order-independent bounds never invert.
    assert(LMVEasterPanelClamp(NAN, 3.0, 7.0) == 3.0);
    assert(LMVEasterPanelClamp(-1.0, 0.0, 1.0) == 0.0);
    assert(LMVEasterPanelClamp(9.0, 0.0, 1.0) == 1.0);
    assert(LMVEasterPanelClamp(0.5, 0.0, 1.0) == 0.5);

    // The five stored keys are exactly the ones the settings page writes.
    NSArray<NSString *> *keys = LMVEasterPanelAppearanceKeys();
    assert(keys.count == 5);
    assert([keys containsObject:@"EasterPanelCornerEnabled"] && [keys containsObject:@"EasterPanelCorner"]);
    assert([keys containsObject:@"EasterPanelSizeEnabled"]);
    assert([keys containsObject:@"EasterPanelWidthScale"] && [keys containsObject:@"EasterPanelHeightScale"]);
    for (NSString *key in keys) assert(![key hasPrefix:@"EasterEgg"]);
    printf("PASS actual production panel-appearance rules: 20pt default kept, corner 0..60, "
           "size off by default, 50%%..150%% scale, non-finite inputs bounded\n");
    return 0;
}
