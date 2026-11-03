#pragma once

#import <UIKit/UIKit.h>

// 5.28: one source of truth for the settings list geometry. The rows are a
// two-line layout (17pt title + 13pt subtitle) with the control on the right,
// matching the card style the panel uses everywhere else.
static const CGFloat LMVPPanelSideInset = 16.0;
static const CGFloat LMVPPanelControlGap = 12.0;
static const CGFloat LMVPPanelRowHeight = 52.0;
static const CGFloat LMVPPanelTallRowHeight = 66.0;
static const CGFloat LMVPPanelSwitchWidth = 51.0;
static const CGFloat LMVPPanelChevronWidth = 12.0;
static const CGFloat LMVPPanelColorWidth = 96.0;
static const CGFloat LMVPPanelColorDotSize = 22.0;
static const CGFloat LMVPPanelTitleTop = 10.0;
static const CGFloat LMVPPanelTitleHeight = 22.0;
static const CGFloat LMVPPanelSubtitleTop = 33.0;
static const CGFloat LMVPPanelSubtitleHeight = 18.0;
// 5.31: 数值行从滑条改成 -/+ 步进器。右侧控件的尺寸、圆角、字形与长按节奏
// 都在这里；改外观只动这几个常量，控件本身不写死数字。
static const CGFloat LMVPStepperWidth = 132.0;
static const CGFloat LMVPStepperHeight = 32.0;
static const CGFloat LMVPStepperCornerRadius = 10.0;
static const CGFloat LMVPStepperGlyphPointSize = 20.0;
static const CGFloat LMVPStepperDividerHeight = 20.0;
static const NSTimeInterval LMVPStepperHoldDelay = 0.35;
static const NSTimeInterval LMVPStepperRepeatInterval = 0.10;

static inline UIColor *LMVPStepperFillColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.12]
            : [UIColor colorWithWhite:0.0 alpha:0.06];
    }];
}

static inline UIColor *LMVPStepperDividerColor(void) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithWhite:1.0 alpha:0.18]
            : [UIColor colorWithWhite:0.0 alpha:0.12];
    }];
}

static inline UIFont *LMVPPanelTitleFont(void) {
    return [UIFont systemFontOfSize:17.0 weight:UIFontWeightRegular];
}

static inline UIFont *LMVPPanelSubtitleFont(void) {
    return [UIFont systemFontOfSize:13.0 weight:UIFontWeightRegular];
}
