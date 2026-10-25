#pragma once
#import <UIKit/UIKit.h>

@interface LMVGalleryController : UIViewController
// 4.3.1: the pane embeds this page, so "经典列表" asks the pane to switch instead
// of popping the navigation stack.
@property(nonatomic,copy) void (^onRequestClassicList)(void);
// 4.3.6: the display-settings page is implemented in a header that may only be
// included by ONE translation unit (the root controller), so the gallery asks the
// pane to present it instead of importing it.
@property(nonatomic,copy) void (^onRequestDisplaySettings)(void);
@end

@interface LMVMaterialLibraryController : UIViewController
@end

@interface LMVChannelDetailController : UIViewController
- (instancetype)initWithChannelID:(NSString *)channelID;
@property(nonatomic,copy,readonly) NSString *channelID;
@end
