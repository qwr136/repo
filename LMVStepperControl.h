#pragma once

#import <UIKit/UIKit.h>

// 5.31: 数值行不再用滑条。- / + 两栏胶囊，值由所在行的标题显示
// （「显示大小 (28 pt)」），控件本身只负责加减与取值。
// 点一次走一格，按住连续加减；到边界时对应一侧变灰。
@interface LMVStepperControl : UIControl

@property (nonatomic) double minimumValue;
@property (nonatomic) double maximumValue;
@property (nonatomic) double stepValue;
@property (nonatomic) double value;

- (void)setValue:(double)value animated:(BOOL)animated;

@end
