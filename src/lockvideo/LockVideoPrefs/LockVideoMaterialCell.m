// LockVideoMaterialCell.m
#import "LockVideoMaterialCell.h"

@implementation LockVideoMaterialCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier {
    if ((self = [super initWithStyle:style
                     reuseIdentifier:reuseIdentifier
                           specifier:specifier])) {
        // 让框架按 PSLinkCell 类型处理 tap 流程
        self.type = PSLinkCell;
        // 彻底去掉右侧 chevron
        self.accessoryType = UITableViewCellAccessoryNone;

        // 中间居中显示文件名的 label
        _nameLabel = [[UILabel alloc] init];
        _nameLabel.backgroundColor = [UIColor clearColor];
        UILabel *t = [self titleLabel];
        _nameLabel.font = (t && t.font) ? t.font
                                         : [UIFont systemFontOfSize:14];
        _nameLabel.textColor = [UIColor colorWithRed:0.40 green:0.40 blue:0.45 alpha:1.0];
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _nameLabel.adjustsFontSizeToFitWidth = YES;
        _nameLabel.minimumScaleFactor = 0.7;
        _nameLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
        [self.contentView addSubview:_nameLabel];
    }
    return self;
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];

    // 优先读 value，再 fallback 到 detailText（与 controller 写入保持一致）
    NSString *txt = nil;
    id v = [specifier propertyForKey:PSValueKey]; // @"value"
    if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
        txt = v;
    } else {
        id d = [specifier propertyForKey:@"detailText"];
        if ([d isKindOfClass:[NSString class]]) txt = d;
    }
    if (!txt) txt = @"（未选择）";
    self.nameLabel.text = txt;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect b = self.bounds;

    UILabel *titleLabel = [self titleLabel];

    CGFloat leftPad  = 16.0;   // 与标准 PSLinkCell 一致
    CGFloat labelW   = 110.0;  // 「选择素材」四个字
    CGFloat gap      = 8.0;
    CGFloat rightPad = 8.0;

    titleLabel.frame = CGRectMake(leftPad, 0, labelW, b.size.height);
    titleLabel.textAlignment = NSTextAlignmentLeft;

    CGFloat valueX = leftPad + labelW + gap;
    CGFloat valueW = b.size.width - valueX - rightPad;
    if (valueW < 40.0) valueW = 40.0;
    self.nameLabel.frame = CGRectMake(valueX, 0, valueW, b.size.height);
}

@end
