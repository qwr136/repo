#pragma once

#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>

// 5.28: the settings list used to hand every row to a stock Preferences cell,
// so the page was a single-line list of 44pt rows with the control jammed on the
// right. Every row now goes through this one class: a 17pt title, a 13pt grey
// subtitle underneath, and the control (switch / chevron / colour swatch /
// slider) laid out on the same vertical grid. Row behaviour is unchanged - the
// specifier still carries the same key, target, setter and getter, and the
// controller still owns every write.
typedef NS_ENUM(NSInteger, LMVPPanelControl) {
    LMVPPanelControlNone = 0,
    LMVPPanelControlSwitch,
    LMVPPanelControlLink,
    LMVPPanelControlColor,
    LMVPPanelControlSlider,
};

@interface LMVPSettingCell : PSTableCell

// Height is a pure function of the specifier: subtitle present -> 66, slider
// rows 88/96, everything else 52. No runtime guesswork in -layoutSubviews.
+ (CGFloat)lmvp_heightForSpecifier:(PSSpecifier *)specifier;
+ (LMVPPanelControl)lmvp_controlForSpecifier:(PSSpecifier *)specifier;

// The colour swatch and its hex text are painted by the controller (it owns the
// preference key); the cell only reports where that column starts so the title
// cannot run underneath it.
- (CGFloat)lmvp_trailingReservedWidth;

@end
