#import "LMVPanelRowCell.h"
#import "LockMessageVideoPrefs/LMVPPanelStyle.h"

@implementation LMVPanelRowCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.textLabel.font = LMVPPanelTitleFont();
        self.textLabel.textColor = UIColor.labelColor;
        self.textLabel.numberOfLines = 1;
        self.detailTextLabel.font = LMVPPanelSubtitleFont();
        self.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        self.detailTextLabel.numberOfLines = 1;
        self.separatorInset = UIEdgeInsetsMake(0, LMVPPanelSideInset, 0, 0);
    }
    return self;
}

// The control on the right decides how much width the two labels may use. The
// accessory is measured after -sizeToFit so a plain UILabel (the material count)
// reserves its real width instead of zero.
- (CGFloat)lmvp_reservedWidth {
    UIView *accessory = self.accessoryView;
    if (accessory) {
        if (CGRectGetWidth(accessory.frame) <= 0.0) [accessory sizeToFit];
        CGFloat width = CGRectGetWidth(accessory.frame);
        return width > 0.0 ? width + LMVPPanelControlGap : 0.0;
    }
    switch (self.accessoryType) {
        case UITableViewCellAccessoryDisclosureIndicator:
        case UITableViewCellAccessoryDetailDisclosureButton:
            return 28.0;
        case UITableViewCellAccessoryCheckmark:
            return 24.0;
        default:
            return 0.0;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    BOOL twoLine = self.detailTextLabel.text.length > 0;

    CGFloat left = LMVPPanelSideInset;
    if (self.imageView.image) {
        self.imageView.frame = CGRectMake(LMVPPanelSideInset, (height - 24.0) / 2.0, 24.0, 24.0);
        left = CGRectGetMaxX(self.imageView.frame) + 8.0;
    }

    CGFloat reserved = [self lmvp_reservedWidth];
    CGFloat textWidth = MAX(0.0, width - left - LMVPPanelSideInset - reserved);

    CGFloat titleY = twoLine ? LMVPPanelTitleTop : (height - LMVPPanelTitleHeight) / 2.0;
    self.textLabel.frame = CGRectMake(left, titleY, textWidth, LMVPPanelTitleHeight);
    self.detailTextLabel.frame = twoLine
        ? CGRectMake(left, LMVPPanelSubtitleTop, textWidth, LMVPPanelSubtitleHeight)
        : CGRectZero;

    // Centre the control on the title line, not on the whole row: in a two-line
    // row the row centre lands between the two labels, which is what made the
    // stepper look like it had slipped downwards.
    UIView *accessory = self.accessoryView;
    if (accessory && CGRectGetHeight(accessory.frame) > 0.0) {
        CGRect frame = accessory.frame;
        frame.origin.y = round(CGRectGetMidY(self.textLabel.frame) - CGRectGetHeight(frame) / 2.0);
        accessory.frame = frame;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.accessoryView = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.imageView.image = nil;
}

@end
