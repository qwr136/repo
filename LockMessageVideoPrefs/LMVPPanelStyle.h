#pragma once

#import <UIKit/UIKit.h>

// 5.28: one source of truth for the settings list geometry. The rows are a
// two-line layout (17pt title + 13pt subtitle) with the control on the right,
// matching the card style the panel uses everywhere else.
static const CGFloat LMVPPanelSideInset = 16.0;
static const CGFloat LMVPPanelControlGap = 12.0;
static const CGFloat LMVPPanelRowHeight = 52.0;
static const CGFloat LMVPPanelTallRowHeight = 66.0;
static const CGFloat LMVPPanelSliderRowHeight = 88.0;
static const CGFloat LMVPPanelSliderTallRowHeight = 96.0;
static const CGFloat LMVPPanelSwitchWidth = 51.0;
static const CGFloat LMVPPanelChevronWidth = 12.0;
static const CGFloat LMVPPanelColorWidth = 96.0;
static const CGFloat LMVPPanelColorDotSize = 22.0;
static const CGFloat LMVPPanelTitleTop = 10.0;
static const CGFloat LMVPPanelTitleHeight = 22.0;
static const CGFloat LMVPPanelSubtitleTop = 33.0;
static const CGFloat LMVPPanelSubtitleHeight = 18.0;
static const CGFloat LMVPSliderTrackTop = 58.0;
static const CGFloat LMVPSliderTrackHeight = 31.0;

static inline UIFont *LMVPPanelTitleFont(void) {
    return [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
}

static inline UIFont *LMVPPanelSubtitleFont(void) {
    return [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
}

static inline UIFont *LMVPPanelValueFont(void) {
    return [UIFont monospacedDigitSystemFontOfSize:15.0 weight:UIFontWeightRegular];
}
