#pragma once
#import <UIKit/UIKit.h>

// LMVMaterialPicker's implementation lives in its header (it is shared with the
// tweak), so exactly ONE translation unit may include that header. Everything else
// goes through this declaration + factory, which keeps the class defined once in
// the preference bundle while letting the classic list and the gallery both open it.

@interface LMVMaterialPicker : UITableViewController
@property(nonatomic, copy) NSString *selected;
@property(nonatomic) BOOL showsThumbnails;
@property(nonatomic, copy) void (^apply)(NSString *relative, NSString *name);
@property(nonatomic, copy) void (^libraryChanged)(void);
@end

UIViewController *LMVCreateMaterialPicker(NSString *selected,
                                          BOOL showsThumbnails,
                                          void (^apply)(NSString *, NSString *),
                                          void (^libraryChanged)(void));
