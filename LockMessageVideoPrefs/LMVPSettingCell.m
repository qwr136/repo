#import "LMVPSettingCell.h"

#import <math.h>
#import <objc/message.h>

#import "LMVPPanelStyle.h"
#import "../LMVStepperControl.h"

static NSString *const kLMVPPanelSubtitleKey = @"subtitle";
static NSString *const kLMVPPanelKindKey = @"panelKind";

// PSSpecifier binds a row to a getter/setter pair on the controller and exposes
// them through -performGetter / -performSetterWithValue:. Both are declared in
// Preferences' PSSpecifier header and have been stable since iOS 5, so the row
// never has to reach for a selector by name.
static id LMVPPanelReadValue(PSSpecifier *specifier) {
    if ([specifier respondsToSelector:@selector(performGetter)]) return [specifier performGetter];
    return nil;
}

static void LMVPPanelWriteValue(PSSpecifier *specifier, id value) {
    if ([specifier respondsToSelector:@selector(performSetterWithValue:)])
        [specifier performSetterWithValue:value];
}

@interface LMVPSettingCell ()
@property(nonatomic,strong) UILabel *panelTitle;
@property(nonatomic,strong) UILabel *panelSubtitle;
@property(nonatomic,strong) UISwitch *panelSwitch;
@property(nonatomic,strong) LMVStepperControl *panelStepper;
@property(nonatomic,strong) UILabel *panelChevron;
@property(nonatomic) LMVPPanelControl panelControl;
@end

@implementation LMVPSettingCell

+ (LMVPPanelControl)lmvp_controlForSpecifier:(PSSpecifier *)specifier {
    NSString *kind = [specifier propertyForKey:kLMVPPanelKindKey];
    if ([kind isKindOfClass:NSString.class] && kind.length) {
        if ([kind isEqualToString:@"switch"]) return LMVPPanelControlSwitch;
        if ([kind isEqualToString:@"link"]) return LMVPPanelControlLink;
        if ([kind isEqualToString:@"color"]) return LMVPPanelControlColor;
        if ([kind isEqualToString:@"stepper"]) return LMVPPanelControlStepper;
        return LMVPPanelControlNone;
    }
    // Fallback for rows that were never annotated: the stock cell type still
    // says what the row does, so the layout stays correct either way.
    if (specifier.cellType == PSSwitchCell) return LMVPPanelControlSwitch;
    if (specifier.cellType == PSSliderCell) return LMVPPanelControlStepper;
    if (specifier.cellType == PSButtonCell) return LMVPPanelControlLink;
    return LMVPPanelControlNone;
}

+ (CGFloat)lmvp_heightForSpecifier:(PSSpecifier *)specifier {
    LMVPPanelControl control = [self lmvp_controlForSpecifier:specifier];
    id subtitle = [specifier propertyForKey:kLMVPPanelSubtitleKey];
    BOOL tall = [subtitle isKindOfClass:NSString.class] && [subtitle length] > 0;
    // 5.31: the stepper sits on the title line, so a numeric row is exactly as
    // tall as any other row - no separate 88/96 case any more.
    (void)control;
    return tall ? LMVPPanelTallRowHeight : LMVPPanelRowHeight;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style
              reuseIdentifier:(NSString *)reuseIdentifier
                    specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier specifier:specifier];
    if (self) {
        self.separatorInset = UIEdgeInsetsMake(0, LMVPPanelSideInset, 0, 0);
        [self lmvp_buildViews];
        [self lmvp_applySpecifier];
    }
    return self;
}

- (void)lmvp_buildViews {
    // PSTableCell fills textLabel/detailTextLabel from the specifier. This row
    // draws its own pair, so the stock labels are kept out of the way instead of
    // fighting them for the same frame.
    self.textLabel.hidden = YES;
    self.detailTextLabel.hidden = YES;

    _panelTitle = [UILabel new];
    _panelTitle.font = LMVPPanelTitleFont();
    _panelTitle.textColor = UIColor.labelColor;
    _panelTitle.numberOfLines = 1;
    _panelTitle.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:_panelTitle];

    _panelSubtitle = [UILabel new];
    _panelSubtitle.font = LMVPPanelSubtitleFont();
    _panelSubtitle.textColor = UIColor.secondaryLabelColor;
    _panelSubtitle.numberOfLines = 1;
    _panelSubtitle.lineBreakMode = NSLineBreakByTruncatingTail;
    [self.contentView addSubview:_panelSubtitle];

    _panelSwitch = [UISwitch new];
    _panelSwitch.hidden = YES;
    [_panelSwitch addTarget:self action:@selector(lmvp_switchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_panelSwitch];

    _panelStepper = [LMVStepperControl new];
    _panelStepper.hidden = YES;
    [_panelStepper addTarget:self action:@selector(lmvp_stepperChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:_panelStepper];

    _panelChevron = [UILabel new];
    _panelChevron.text = @"\u203A";
    _panelChevron.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightRegular];
    _panelChevron.textColor = UIColor.tertiaryLabelColor;
    _panelChevron.textAlignment = NSTextAlignmentCenter;
    _panelChevron.hidden = YES;
    [self.contentView addSubview:_panelChevron];
}

- (void)setSpecifier:(PSSpecifier *)specifier {
    [super setSpecifier:specifier];
    [self lmvp_applySpecifier];
}

- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier];
    [self lmvp_applySpecifier];
}

- (void)lmvp_applySpecifier {
    PSSpecifier *specifier = self.specifier;
    if (!specifier) return;

    self.panelControl = [[self class] lmvp_controlForSpecifier:specifier];
    self.panelTitle.text = specifier.name ?: @"";
    id subtitle = [specifier propertyForKey:kLMVPPanelSubtitleKey];
    self.panelSubtitle.text = [subtitle isKindOfClass:NSString.class] ? subtitle : nil;
    self.panelSubtitle.hidden = (self.panelSubtitle.text.length == 0);

    self.panelSwitch.hidden = (self.panelControl != LMVPPanelControlSwitch);
    self.panelStepper.hidden = (self.panelControl != LMVPPanelControlStepper);
    // A material row carries its value as an accessory view (painted by the
    // controller); the row already shows the name, so the chevron stays out.
    self.panelChevron.hidden = (self.panelControl != LMVPPanelControlLink) || (self.accessoryView != nil);

    if (self.panelControl == LMVPPanelControlSwitch) {
        id value = LMVPPanelReadValue(specifier);
        if (![value respondsToSelector:@selector(boolValue)]) value = [specifier propertyForKey:@"default"];
        self.panelSwitch.on = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
    } else if (self.panelControl == LMVPPanelControlStepper) {
        [self lmvp_configureStepper];
        id value = LMVPPanelReadValue(specifier);
        double number = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue]
                                                                          : self.panelStepper.minimumValue;
        if (!isfinite(number)) number = self.panelStepper.minimumValue;
        self.panelStepper.value = number;
        [self lmvp_refreshValueText];
    }

    [self lmvp_applyEnabled];
    self.accessibilityLabel = self.panelSubtitle.hidden
        ? self.panelTitle.text
        : [NSString stringWithFormat:@"%@，%@", self.panelTitle.text, self.panelSubtitle.text];
}

- (void)lmvp_applyEnabled {
    NSNumber *enabled = [self.specifier propertyForKey:@"enabled"];
    BOOL on = enabled ? enabled.boolValue : YES;
    self.panelSwitch.enabled = on;
    self.panelStepper.enabled = on;
    self.panelChevron.alpha = on ? 1.0 : 0.4;
    CGFloat alpha = on ? 1.0 : 0.45;
    self.panelTitle.alpha = alpha;
    self.panelSubtitle.alpha = alpha;
    self.userInteractionEnabled = on;
}

- (void)lmvp_configureStepper {
    PSSpecifier *specifier = self.specifier;
    NSNumber *low = [specifier propertyForKey:@"min"];
    NSNumber *high = [specifier propertyForKey:@"max"];
    double minimum = low ? low.doubleValue : 0.0;
    double maximum = high ? high.doubleValue : 1.0;
    if (!isfinite(minimum)) minimum = 0.0;
    if (!isfinite(maximum) || maximum <= minimum) maximum = minimum + 1.0;
    // The step is a presentation decision, not a stored one: a 0-100 volume
    // moves a point at a time, a 0-1 ratio (opacity) moves a percent.
    NSNumber *step = [specifier propertyForKey:@"step"];
    double stride = step ? step.doubleValue : (maximum <= 1.0 + DBL_EPSILON ? 0.01 : 1.0);
    if (!isfinite(stride) || stride <= 0.0) stride = 1.0;
    self.panelStepper.minimumValue = minimum;
    self.panelStepper.maximumValue = maximum;
    self.panelStepper.stepValue = stride;
}

// Percent rows ("声音音量（%）" 0-100) read as integers; the 0-1 rows are ratios
// and read as percentages too, which is how the panel has always described
// opacity. Anything else keeps one decimal.
- (NSString *)lmvp_valueTextForNumber:(double)value {
    NSNumber *high = [self.specifier propertyForKey:@"max"];
    double upper = high ? high.doubleValue : 1.0;
    if (upper <= 1.0 + DBL_EPSILON) return [NSString stringWithFormat:@"%.0f%%", value * 100.0];
    if (upper >= 10.0) return [NSString stringWithFormat:@"%.0f%%", value];
    return [NSString stringWithFormat:@"%.1f", value];
}

// The value lives in the title, matching the card style the panel uses
// elsewhere: "显示大小 (28 pt)". A trailing unit already baked into the
// specifier name is dropped so the row never reads "音量（%）(50%)".
- (void)lmvp_refreshValueText {
    if (self.panelControl != LMVPPanelControlStepper) return;
    NSString *name = self.specifier.name ?: @"";
    for (NSString *suffix in @[@"（%）", @"(%)", @"（%)", @"(%）"]) {
        if ([name hasSuffix:suffix]) { name = [name substringToIndex:name.length - suffix.length]; break; }
    }
    NSString *value = [self lmvp_valueTextForNumber:self.panelStepper.value];
    self.panelTitle.text = [NSString stringWithFormat:@"%@ (%@)", name, value];
    self.panelStepper.accessibilityValue = value;
}

// Preferences drives switch and slider rows through these three methods: it sets
// the value when the row scrolls in and reads the control back when the row is
// reloaded. PSSwitchTableCell and PSSliderTableCell implement them; a custom
// PSTableCell subclass does not inherit them, and the send is not guarded by
// -respondsToSelector:, so a missing one aborts the Preferences process before
// the row ever appears. They only move the drawn control - every write still
// goes through the specifier's setter.
- (UIControl *)control {
    if (self.panelControl == LMVPPanelControlSwitch) return self.panelSwitch;
    if (self.panelControl == LMVPPanelControlStepper) return self.panelStepper;
    return nil;
}

- (id)value {
    if (self.panelControl == LMVPPanelControlSwitch) return @(self.panelSwitch.isOn);
    if (self.panelControl == LMVPPanelControlStepper) return @(self.panelStepper.value);
    return nil;
}

- (void)setValue:(id)value {
    if (self.panelControl == LMVPPanelControlSwitch) {
        if (![value respondsToSelector:@selector(boolValue)]) value = [self.specifier propertyForKey:@"default"];
        self.panelSwitch.on = [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : NO;
        return;
    }
    if (self.panelControl == LMVPPanelControlStepper) {
        double number = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue]
                                                                         : self.panelStepper.minimumValue;
        if (!isfinite(number)) number = self.panelStepper.minimumValue;
        self.panelStepper.value = number;
        [self lmvp_refreshValueText];
    }
}

- (void)lmvp_switchChanged:(UISwitch *)sender {
    LMVPPanelWriteValue(self.specifier, @(sender.isOn));
}
- (void)lmvp_stepperChanged:(LMVStepperControl *)sender {
    [self lmvp_refreshValueText];
    LMVPPanelWriteValue(self.specifier, @(sender.value));
}

- (CGFloat)lmvp_trailingReservedWidth {
    switch (self.panelControl) {
        case LMVPPanelControlSwitch: return LMVPPanelSwitchWidth;
        case LMVPPanelControlLink: return LMVPPanelChevronWidth;
        case LMVPPanelControlColor: return LMVPPanelColorWidth;
        case LMVPPanelControlStepper: return LMVPStepperWidth;
        default: return 0.0;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];

    // The controller attaches the material name in -willDisplayCell:, which runs
    // after the cell was configured; re-check here so a recycled link row never
    // shows both the name and a chevron.
    self.panelChevron.hidden = (self.panelControl != LMVPPanelControlLink) || (self.accessoryView != nil);

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    CGFloat side = LMVPPanelSideInset;
    CGFloat reserved = [self lmvp_trailingReservedWidth];
    // An accessory view (the material name painted by the controller) already
    // narrows contentView, so it must not be reserved twice.
    if (self.accessoryView) reserved = 0.0;
    CGFloat gap = reserved > 0.0 ? LMVPPanelControlGap : 0.0;
    CGFloat textWidth = MAX(0.0, width - side * 2.0 - reserved - gap);
    // The colour row paints its hex text from 98pt in and its swatch at the
    // trailing edge; the title keeps clear of both.
    if (self.panelControl == LMVPPanelControlColor) textWidth = 82.0;

    BOOL hasSubtitle = !self.panelSubtitle.hidden;
    if (hasSubtitle) {
        self.panelTitle.frame = CGRectMake(side, LMVPPanelTitleTop, textWidth, LMVPPanelTitleHeight);
        self.panelSubtitle.frame = CGRectMake(side, LMVPPanelSubtitleTop, textWidth, LMVPPanelSubtitleHeight);
    } else {
        self.panelTitle.frame = CGRectMake(side, (height - LMVPPanelTitleHeight) / 2.0,
                                           textWidth, LMVPPanelTitleHeight);
        self.panelSubtitle.frame = CGRectZero;
    }

    switch (self.panelControl) {
        case LMVPPanelControlSwitch:
            self.panelSwitch.frame = CGRectMake(width - side - LMVPPanelSwitchWidth,
                                                (height - 31.0) / 2.0,
                                                LMVPPanelSwitchWidth, 31.0);
            break;
        case LMVPPanelControlLink:
            self.panelChevron.frame = CGRectMake(width - side - LMVPPanelChevronWidth,
                                                 (height - 22.0) / 2.0,
                                                 LMVPPanelChevronWidth, 22.0);
            break;
        case LMVPPanelControlStepper:
            self.panelStepper.frame = CGRectMake(width - side - LMVPStepperWidth,
                                                 (height - LMVPStepperHeight) / 2.0,
                                                 LMVPStepperWidth, LMVPStepperHeight);
            break;
        default:
            break;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    // The controller paints the swatch and the material name per row; a recycled
    // cell must not carry either into an unrelated row.
    self.accessoryView = nil;
}

@end
