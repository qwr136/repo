#pragma once
#import <UIKit/UIKit.h>
// 1.83: shared text-colour picker for the CopyVault panel.
//
// Pure UIKit on purpose: the same implementation is compiled into the tweak (the
// Easter panel presents it) and into the preference bundle (Settings presents it),
// so neither copy may touch the private Preferences framework.
//
// Stored as one RGBA word under `CVTextColor`. An absent key means "keep
// CopyVault's own colours" - that is different from an explicit opaque white.
// Tweak.xm is Objective-C++ and this file is also compiled as plain Objective-C,
// so the C entry points need C linkage or the linker sees a mangled name.
#ifdef __cplusplus
extern "C" {
#endif
extern NSString *const LMVTextColorKey;
UIColor *LMVTextColorCurrent(void);
void LMVTextColorStore(UIColor *color);
NSString *LMVTextColorHex(UIColor *color);
#ifdef __cplusplus
}
#endif

@interface LMVTextColorPicker : UIViewController
@property(nonatomic,copy) void (^onChange)(UIColor *color);
// 1.88: fired after the sheet has actually left the screen, so the caller can
// repaint its swatch once the table is laid out again (the swatch used to stay
// on the old colour when the picker was closed).
@property(nonatomic,copy) void (^onDismiss)(void);
@end
