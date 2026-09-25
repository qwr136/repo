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
    [self _refreshNameLabel];
}

// 框架在 reloadSpecifier 时未必调用上面的 refresh，这里兜底
- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    [self _refreshNameLabel];
}

// 从 specifier 同步当前显示的文件名（多路径保险，保证总是显示最新值）
- (void)_refreshNameLabel {
    @try {
        PSSpecifier *spec = self.specifier;
        if (!spec) return;
        NSString *txt = nil;
        id v = [spec propertyForKey:PSValueKey]; // @"value"
        if ([v isKindOfClass:[NSString class]] && [(NSString *)v length] > 0) {
            txt = v;
        } else {
            id d = [spec propertyForKey:@"detailText"];
            if ([d isKindOfClass:[NSString class]]) txt = d;
        }
        if (!txt) txt = @"（未选择）";
        if (![self.nameLabel.text isEqualToString:txt]) {
            self.nameLabel.text = txt;
        }
    } @catch (NSException *e) {}
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect b = self.bounds;

    UILabel *titleLabel = [self titleLabel];

    CGFloat leftPad  = 16.0;
    CGFloat labelW   = 110.0;
    CGFloat gap      = 8.0;
    CGFloat rightPad = 8.0;

    titleLabel.frame = CGRectMake(leftPad, 0, labelW, b.size.height);
    titleLabel.textAlignment = NSTextAlignmentLeft;

    CGFloat valueX = leftPad + labelW + gap;
    CGFloat valueW = b.size.width - valueX - rightPad;
    if (valueW < 40.0) valueW = 40.0;
    self.nameLabel.frame = CGRectMake(valueX, 0, valueW, b.size.height);

    // 兜底：每次 layout 都重新同步一次（保命，spec.value 已变更但 label 没刷的情况）
    [self _refreshNameLabel];
}

@end
