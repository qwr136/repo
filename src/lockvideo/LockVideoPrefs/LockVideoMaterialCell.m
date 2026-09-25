// LockVideoMaterialCell.m
#import "LockVideoMaterialCell.h"

@implementation LockVideoMaterialCell

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect b = self.bounds;

    // 1) 隐藏右侧的 chevron 箭头
    UIView *disc = nil;
    SEL disSel = NSSelectorFromString(@"disclosureIndicatorImageView");
    if ([self respondsToSelector:disSel]) {
        // suppress unused warning
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        disc = (UIView *)[self performSelector:disSel];
        #pragma clang diagnostic pop
    }
    if (disc) {
        disc.hidden = YES;
        disc.alpha = 0.0;
    }

    // 2) 重排 valueLabel 到中间
    UILabel *titleLabel  = [self titleLabel];
    UILabel *valueLabel  = [self valueLabel];

    CGFloat leftPad  = 16.0;   // 与标准 PSLinkCell 一致
    CGFloat rightPad = 8.0;    // chevron 位置略往右收一点
    CGFloat labelW   = 110.0;  // 「选择素材」四个字 + 一些留白
    CGFloat gap      = 8.0;

    titleLabel.frame = CGRectMake(leftPad, 0, labelW, b.size.height);
    titleLabel.textAlignment = NSTextAlignmentLeft;

    CGFloat valueX = leftPad + labelW + gap;
    CGFloat valueW = b.size.width - valueX - rightPad;
    if (valueW < 40.0) valueW = 40.0;
    valueLabel.frame = CGRectMake(valueX, 0, valueW, b.size.height);
    valueLabel.textAlignment = NSTextAlignmentCenter;
    valueLabel.adjustsFontSizeToFitWidth = YES;
    valueLabel.minimumScaleFactor = 0.7;
    valueLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
}

@end
