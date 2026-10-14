#pragma once
// 0.0.122 user feature: the floating panel's corner radius and its width/height
// are adjustable, and BOTH entry points of the same settings page (the Settings
// app and the panel's own "显示场景与图片旋转") must agree. The rules therefore
// live here as pure functions over the stored values, so they can be tested
// natively and can never drift apart between the two tables.
//
// Defaults preserve the previous hard-coded behaviour exactly: a 20 pt corner is
// always on, and the panel size stays automatic until the user turns sizing on.
#define LMVEasterPanelCornerFallback 20.0
#define LMVEasterPanelCornerMin 0.0
#define LMVEasterPanelCornerMax 60.0
#define LMVEasterPanelScaleMin 0.5
#define LMVEasterPanelScaleMax 1.5

static NSArray<NSString *> *LMVEasterPanelAppearanceKeys(void) {
    return @[@"EasterPanelCornerEnabled", @"EasterPanelCorner",
             @"EasterPanelSizeEnabled", @"EasterPanelWidthScale", @"EasterPanelHeightScale"];
}
// A non-finite input resolves to `low`: a corrupt/absent value must never
// produce a larger panel or corner than the user could have asked for.
static CGFloat LMVEasterPanelClamp(CGFloat value, CGFloat low, CGFloat high) {
    if (!isfinite(value)) return low;
    return fmax(low, fmin(high, value));
}
static BOOL LMVEasterPanelToggle(id value, BOOL fallback) {
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}
static CGFloat LMVEasterPanelCornerValue(id value) {
    double raw = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : LMVEasterPanelCornerFallback;
    return round(LMVEasterPanelClamp((CGFloat)raw, LMVEasterPanelCornerMin, LMVEasterPanelCornerMax));
}
static CGFloat LMVEasterPanelScaleValue(id value) {
    double raw = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 1.0;
    return round(LMVEasterPanelClamp((CGFloat)raw, LMVEasterPanelScaleMin, LMVEasterPanelScaleMax) * 100.0) / 100.0;
}
// Resolved corner radius. `fallbackCorner` is the value the panel used before this
// feature existed, applied whenever the toggle is off (or never set).
static CGFloat LMVEasterResolvedPanelCorner(id enabled, id corner, CGFloat fallbackCorner) {
    return LMVEasterPanelToggle(enabled, YES) ? LMVEasterPanelCornerValue(corner) : fallbackCorner;
}
// Resolved panel size. Sizing is OFF by default, so an untouched install keeps the
// automatic width/height computed from the screen.
static CGSize LMVEasterResolvedPanelSize(id enabled, id widthScale, id heightScale, CGSize automatic) {
    if (!LMVEasterPanelToggle(enabled, NO)) return automatic;
    return CGSizeMake(automatic.width * LMVEasterPanelScaleValue(widthScale),
                      automatic.height * LMVEasterPanelScaleValue(heightScale));
}
