#pragma once

#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <UIKit/UIKit.h>

// 5.28: the settings list used to hand every row to a stock Preferences cell,
// so the page was a single-line list of 44pt rows with the control jammed on the
// right. Every row now goes through this one class: a 17pt title, a 13pt grey
// subtitle underneath, and the control (switch / chevron / colour swatch /
// stepper) laid out on the same vertical grid. Row behaviour is unchanged - the
// specifier still carries the same key, target, setter and getter, and the
// controller still owns every write.
// 5.31: the numeric control is a -/+ stepper, not a slider. The value rides in
// the title ("显示大小 (28 pt)"), so the row stays one line tall.
typedef NS_ENUM(NSInteger, LMVPPanelControl) {
    LMVPPanelControlNone = 0,
    LMVPPanelControlSwitch,
    LMVPPanelControlLink,
    LMVPPanelControlColor,
    LMVPPanelControlStepper,
};

@interface LMVPSettingCell : PSTableCell

// Height is a pure function of the specifier: subtitle present -> 66,
// everything else 52. The stepper sits on the title line, so it never grows the
// row. No runtime guesswork in -layoutSubviews.
+ (CGFloat)lmvp_heightForSpecifier:(PSSpecifier *)specifier;
+ (LMVPPanelControl)lmvp_controlForSpecifier:(PSSpecifier *)specifier;

// The colour swatch and its hex text are painted by the controller (it owns the
// preference key); the cell only reports where that column starts so the title
// cannot run underneath it.
- (CGFloat)lmvp_trailingReservedWidth;

// PSSwitchTableCell and PSSliderTableCell both answer -value / -setValue: /
// -control, and Preferences reaches for those three on rows of those types. This
// class is a plain PSTableCell, so it has to answer them itself - an unguarded
// send to a cell that does not implement one aborts the whole Preferences app.
- (id)value;
- (void)setValue:(id)value;
- (UIControl *)control;

@end
