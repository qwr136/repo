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
        // 5.33: long Chinese titles ("旋转速度 (5 度/秒)") used to be cut down to
        // "旋转…" on the easter-image page. Shrinking by 15% keeps the value
        // readable instead of hiding it behind an ellipsis.
        self.textLabel.adjustsFontSizeToFitWidth = YES;
        self.textLabel.minimumScaleFactor = 0.85;
        self.detailTextLabel.font = LMVPPanelSubtitleFont();
        self.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        self.detailTextLabel.numberOfLines = 1;
        self.detailTextLabel.adjustsFontSizeToFitWidth = YES;
        self.detailTextLabel.minimumScaleFactor = 0.85;
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
    CGFloat cellWidth = CGRectGetWidth(self.bounds);
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

    // 5.33: place the control ourselves and derive the title width from where it
    // actually starts. The old arithmetic subtracted the stepper's 132pt from
    // contentView.bounds, which the cell had already narrowed, so the labels were
    // left about 60pt wide and every title ended in "…". Measuring the gap the
    // control really leaves is stable no matter how the cell resizes.
    UIView *accessory = self.accessoryView;
    if (accessory) {
        if (CGRectGetWidth(accessory.frame) <= 0.0) [accessory sizeToFit];
        // The accessory lives in the cell's coordinate space, the labels in the
        // content view's. They are the same width on every row we build, but
        // measuring the cell keeps the control pinned to the real trailing edge.
        CGFloat accessoryWidth = MIN(CGRectGetWidth(accessory.frame), MAX(0.0, cellWidth - left));
        CGFloat accessoryHeight = CGRectGetHeight(accessory.frame);
        CGFloat accessoryX = round(cellWidth - LMVPPanelSideInset - accessoryWidth);
        // Centre the control on the title line, not on the whole row: in a two-line
        // row the row centre lands between the two labels, which is what made the
        // stepper look like it had slipped downwards.
        accessory.frame = CGRectMake(accessoryX,
                                     round(CGRectGetMidY(self.textLabel.frame) - accessoryHeight / 2.0),
                                     accessoryWidth, accessoryHeight);
        textWidth = MAX(0.0, accessoryX - LMVPPanelControlGap - left);
        self.textLabel.frame = CGRectMake(left, titleY, textWidth, LMVPPanelTitleHeight);
        self.detailTextLabel.frame = twoLine
            ? CGRectMake(left, LMVPPanelSubtitleTop, textWidth, LMVPPanelSubtitleHeight)
            : CGRectZero;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    self.accessoryView = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.imageView.image = nil;
}

@end
