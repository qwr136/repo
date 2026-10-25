#pragma once
#import <UIKit/UIKit.h>

@interface LMVGalleryController : UIViewController
@end

@interface LMVPanelGridController : UIViewController
@end

@interface LMVMaterialLibraryController : UIViewController
@end

@interface LMVChannelDetailController : UIViewController
- (instancetype)initWithChannelID:(NSString *)channelID;
@property(nonatomic,copy,readonly) NSString *channelID;
@end
