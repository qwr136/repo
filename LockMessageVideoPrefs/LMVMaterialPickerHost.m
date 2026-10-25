#import "LMVMaterialStorage.h"
#import "LMVMaterialPicker.h"

// The only translation unit allowed to include LMVMaterialPicker.h. The header
// carries the @implementation, so a second include would duplicate every ivar and
// class symbol at link time (this happened in 4.3.0's first build).
UIViewController *LMVCreateMaterialPicker(NSString *selected,
                                          BOOL showsThumbnails,
                                          void (^apply)(NSString *, NSString *),
                                          void (^libraryChanged)(void)) {
    LMVMaterialPicker *picker = [LMVMaterialPicker new];
    picker.selected = selected ?: @"";
    picker.showsThumbnails = showsThumbnails;
    picker.apply = apply;
    picker.libraryChanged = libraryChanged;
    return [[UINavigationController alloc] initWithRootViewController:picker];
}
