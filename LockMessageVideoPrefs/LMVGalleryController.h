#pragma once
#import <UIKit/UIKit.h>

@interface LMVGalleryController : UIViewController
// 4.3.1: the pane embeds this page, so "经典列表" asks the pane to switch instead
// of popping the navigation stack.
@property(nonatomic,copy) void (^onRequestClassicList)(void);
@end

@interface LMVVideoPreviewController : UIViewController
- (instancetype)initWithChannelID:(NSString *)channelID;
@end

@interface LMVMaterialLibraryController : UIViewController
@end

@interface LMVChannelDetailController : UIViewController
- (instancetype)initWithChannelID:(NSString *)channelID;
@property(nonatomic,copy,readonly) NSString *channelID;
@end
