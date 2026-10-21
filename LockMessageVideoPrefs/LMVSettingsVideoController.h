#pragma once
#import <Preferences/PSListController.h>
#import <UIKit/UIKit.h>
#import <PhotosUI/PhotosUI.h>

// 2.63: 「设置视频背景」 - the Settings app's own video background.
// Rows: 启用开关 / 切换视频（带预览图）/ 声音开关 / 声音大小 / 导入素材.
// Materials live in /var/mobile/LockMessageVideo/设置视频背景.
@interface LMVSettingsVideoController : PSListController <PHPickerViewControllerDelegate>
@end