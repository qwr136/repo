#pragma once

#import <UIKit/UIKit.h>

// 5.30: 面板与彩蛋悬浮窗共用的滑条外观：细轨道 + 竖纹胶囊手柄。
// 交互完全交给 UISlider（拖动、点轨道跳转、VoiceOver 增减），
// 这里只换绘制；用了图片轨道后 tintColor 不再生效，颜色从轨道图片来。
@interface LMVSliderControl : UISlider
@end
