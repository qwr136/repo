#pragma once
#import <Preferences/PSListController.h>

// 2.63: THE ROOT IS A MENU NOW. The user asked for two second-level folders:
//   * 桌面视频背景  - every setting that existed before (lock/home/CC/panels/egg/...)
//   * 设置视频背景  - the new Settings-app video background
// This controller only routes; it owns no row logic of its own.
@interface LMVMenuListController : PSListController
@end
