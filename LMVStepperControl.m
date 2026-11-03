#import "LMVStepperControl.h"
#import "LockMessageVideoPrefs/LMVPPanelStyle.h"
#include <float.h>
#include <math.h>

// 5.31: 左下减号、右上加号，中间一条细分隔线。
// 只发 UIControlEventValueChanged，写盘交给 cell（cell 再交给 specifier）。
@interface LMVStepperControl ()
@property (nonatomic, strong) UIButton *minusButton;
@property (nonatomic, strong) UIButton *plusButton;
@property (nonatomic, strong) UIView *divider;
@property (nonatomic, strong) NSTimer *repeatTimer;
@property (nonatomic) double internalValue;
@end

@implementation LMVStepperControl

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _minimumValue = 0.0;
        _maximumValue = 1.0;
        _stepValue = 0.1;
        _internalValue = 0.0;

        self.backgroundColor = LMVPStepperFillColor();
        self.layer.cornerRadius = LMVPStepperCornerRadius;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;

        _minusButton = [self lmvp_makeButtonWithTitle:@"\u2212"];
        [_minusButton addTarget:self action:@selector(lmvp_pressDown)
               forControlEvents:UIControlEventTouchDown];
        [_minusButton addTarget:self action:@selector(lmvp_releaseButton)
               forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside
                                | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [self addSubview:_minusButton];

        _plusButton = [self lmvp_makeButtonWithTitle:@"+"];
        [_plusButton addTarget:self action:@selector(lmvp_pressUp)
              forControlEvents:UIControlEventTouchDown];
        [_plusButton addTarget:self action:@selector(lmvp_releaseButton)
              forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside
                               | UIControlEventTouchCancel | UIControlEventTouchDragExit];
        [self addSubview:_plusButton];

        _divider = [UIView new];
        _divider.backgroundColor = LMVPStepperDividerColor();
        _divider.userInteractionEnabled = NO;
        [self addSubview:_divider];

        _minusButton.accessibilityLabel = @"减小";
        _plusButton.accessibilityLabel = @"增大";
        self.isAccessibilityElement = NO;
    }
    return self;
}

- (UIButton *)lmvp_makeButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:LMVPStepperGlyphPointSize weight:UIFontWeightRegular];
    [button setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    [button setTitleColor:UIColor.tertiaryLabelColor forState:UIControlStateDisabled];
    // 按住不放连续加减；抬起由 touch-up / drag-exit 收尾。
    UILongPressGestureRecognizer *hold =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(lmvp_holdChanged:)];
    hold.minimumPressDuration = LMVPStepperHoldDelay;
    hold.allowableMovement = 12.0;
    hold.cancelsTouchesInView = NO;
    [button addGestureRecognizer:hold];
    return button;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    CGFloat half = floor(width / 2.0);
    self.minusButton.frame = CGRectMake(0.0, 0.0, half, height);
    self.plusButton.frame = CGRectMake(width - half, 0.0, half, height);
    CGFloat dividerHeight = MIN(LMVPStepperDividerHeight, height - 10.0);
    self.divider.frame = CGRectMake(floor(width / 2.0), (height - dividerHeight) / 2.0,
                                    1.0 / UIScreen.mainScreen.scale, dividerHeight);
}

#pragma mark - 取值

- (double)value {
    return self.internalValue;
}

- (void)setValue:(double)value {
    [self setValue:value animated:NO];
}

- (void)setValue:(double)value animated:(BOOL)animated {
    double clamped = [self lmvp_clamp:value];
    if (fabs(clamped - self.internalValue) < DBL_EPSILON) {
        [self lmvp_refreshEnabledState];
        return;
    }
    self.internalValue = clamped;
    [self lmvp_refreshEnabledState];
    if (animated && !UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.12 animations:^{
            [self lmvp_layoutGlyphs];
        }];
    }
}

- (void)setMinimumValue:(double)minimumValue {
    _minimumValue = minimumValue;
    self.internalValue = [self lmvp_clamp:self.internalValue];
    [self lmvp_refreshEnabledState];
}

- (void)setMaximumValue:(double)maximumValue {
    _maximumValue = maximumValue;
    self.internalValue = [self lmvp_clamp:self.internalValue];
    [self lmvp_refreshEnabledState];
}

- (void)setStepValue:(double)stepValue {
    _stepValue = stepValue > 0.0 ? stepValue : 1.0;
    [self lmvp_refreshEnabledState];
}

- (double)lmvp_clamp:(double)value {
    if (!isfinite(value)) value = self.minimumValue;
    double low = MIN(self.minimumValue, self.maximumValue);
    double high = MAX(self.minimumValue, self.maximumValue);
    return MAX(low, MIN(high, value));
}

// 一格一格走，并落在 min 起算的网格上；浮点步长（0.1x）靠四舍五入收掉误差。
- (double)lmvp_valueByStepping:(double)value delta:(double)delta {
    double step = self.stepValue;
    double origin = self.minimumValue;
    double index = round((value - origin) / step) + delta;
    double next = origin + index * step;
    return [self lmvp_clamp:next];
}

#pragma mark - 交互

- (void)lmvp_pressDown {
    [self lmvp_stepBy:-1.0];
    [self lmvp_startRepeating:-1.0];
}

- (void)lmvp_pressUp {
    [self lmvp_stepBy:1.0];
    [self lmvp_startRepeating:1.0];
}

- (void)lmvp_holdChanged:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        // touch-down 已经走过一格，长按期间只负责续走。
        [self lmvp_startRepeating:(recognizer.view == self.minusButton ? -1.0 : 1.0)];
    } else if (recognizer.state == UIGestureRecognizerStateEnded
               || recognizer.state == UIGestureRecognizerStateCancelled
               || recognizer.state == UIGestureRecognizerStateFailed) {
        [self lmvp_stopRepeating];
    }
}

- (void)lmvp_startRepeating:(double)direction {
    [self lmvp_stopRepeating];
    __weak typeof(self) weakSelf = self;
    self.repeatTimer = [NSTimer scheduledTimerWithTimeInterval:LMVPStepperRepeatInterval
                                                        repeats:YES
                                                          block:^(NSTimer *timer) {
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { [timer invalidate]; return; }
        BOOL moved = [strongSelf lmvp_stepBy:direction];
        if (!moved) [strongSelf lmvp_stopRepeating];
    }];
}

- (void)lmvp_stopRepeating {
    [self.repeatTimer invalidate];
    self.repeatTimer = nil;
}

- (void)lmvp_releaseButton {
    [self lmvp_stopRepeating];
}

- (BOOL)lmvp_stepBy:(double)direction {
    double next = [self lmvp_valueByStepping:self.internalValue delta:direction];
    if (fabs(next - self.internalValue) < DBL_EPSILON) {
        [self lmvp_refreshEnabledState];
        return NO;
    }
    self.internalValue = next;
    [self lmvp_refreshEnabledState];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
    return YES;
}

- (void)lmvp_refreshEnabledState {
    BOOL canDecrease = self.internalValue > self.minimumValue + DBL_EPSILON;
    BOOL canIncrease = self.internalValue < self.maximumValue - DBL_EPSILON;
    BOOL enabled = self.enabled;
    self.minusButton.enabled = enabled && canDecrease;
    self.plusButton.enabled = enabled && canIncrease;
    self.minusButton.alpha = self.minusButton.enabled ? 1.0 : 0.3;
    self.plusButton.alpha = self.plusButton.enabled ? 1.0 : 0.3;
    self.divider.alpha = enabled ? 1.0 : 0.4;
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self lmvp_refreshEnabledState];
}

- (void)lmvp_layoutGlyphs {
    [self.minusButton layoutIfNeeded];
    [self.plusButton layoutIfNeeded];
}

- (void)dealloc {
    [_repeatTimer invalidate];
}

@end
