#import "LMVGalleryController.h"
#import "LMVGalleryKit.h"
#import "../LMVPaths.h"
#import "LMVImport.h"
#import "LMVMaterialPickerAPI.h"
#import "../LMVTextColorPicker.h"

#define LMVGalleryVersion LMV_VERSION_STRING

static UIColor *LMVGAccent(void) {
    return [UIColor colorWithRed:0.23 green:0.43 blue:0.96 alpha:1.0];
}

@interface LMVGDetailGradientView : UIView
@property(nonatomic,copy) NSString *channelID;
@property(nonatomic) BOOL shade;
@end
@implementation LMVGDetailGradientView
+ (Class)layerClass { return CAGradientLayer.class; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CAGradientLayer *gradient = (CAGradientLayer *)self.layer;
    if (self.shade) {
        gradient.colors = @[(id)[UIColor.clearColor CGColor],
                            (id)[UIColor.blackColor colorWithAlphaComponent:0.55].CGColor];
        gradient.locations = @[@0.45, @1.0];
        gradient.startPoint = CGPointMake(0.5, 0.0);
        gradient.endPoint = CGPointMake(0.5, 1.0);
    } else {
        LMVGApplyGradient(gradient, self.channelID ?: @"");
    }
}
@end

@interface LMVChannelDetailController () <PHPickerViewControllerDelegate>
@property(nonatomic,copy) NSString *channelID;
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) UIImageView *cover;
@property(nonatomic,strong) UILabel *resolutionBadge;
@property(nonatomic,copy) NSString *coverRelative;
@property(nonatomic,strong) NSLayoutConstraint *coverTopInset;
@property(nonatomic,strong) UIScrollView *materialStrip;
@property(nonatomic,strong) UILabel *subtitle;
@property(nonatomic,strong) UISwitch *toggle;
@property(nonatomic,strong) UISegmentedControl *segments;
@property(nonatomic,strong) UIStackView *panel;
@property(nonatomic,strong) NSArray<NSDictionary *> *materials;
@property(nonatomic) BOOL importing;
@property(nonatomic) NSInteger segmentIndex;
@end

@implementation LMVChannelDetailController

- (instancetype)initWithChannelID:(NSString *)channelID {
    self = [super init];
    if (self) _channelID = [channelID copy];
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self buildScroll];
    [self buildCover];
    [self buildTitle];
    [self buildSegments];
    [self rebuildPanel];
    [self refresh];
    [self loadMaterials];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    self.coverTopInset.constant = self.view.safeAreaInsets.top + 6;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    [self refresh];
    [self loadMaterials];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)buildScroll {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.contentInset = UIEdgeInsetsMake(0, 0, 40, 0);
    [self.view addSubview:scroll];
    self.scroll = scroll;

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    [scroll addSubview:stack];
    self.stack = stack;

    [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor].active = YES;
    [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor].active = YES;
    [scroll.topAnchor constraintEqualToAnchor:self.view.topAnchor].active = YES;
    [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor].active = YES;
    [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor].active = YES;
    [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor].active = YES;
    [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor].active = YES;
    [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor].active = YES;
    [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor].active = YES;
}

- (void)buildCover {
    // 4.3.6: rounded preview with margins instead of a full-bleed square header,
    // and no playback on tap.
    UIView *spacer = [UIView new];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.stack addArrangedSubview:spacer];
    self.coverTopInset = [spacer.heightAnchor constraintEqualToConstant:8];
    self.coverTopInset.active = YES;

    UIView *wrap = [UIView new];
    wrap.translatesAutoresizingMaskIntoConstraints = NO;
    wrap.layoutMargins = UIEdgeInsetsMake(0, 14, 0, 14);
    [self.stack addArrangedSubview:wrap];

    UIView *coverBox = [UIView new];
    coverBox.translatesAutoresizingMaskIntoConstraints = NO;
    coverBox.clipsToBounds = YES;
    coverBox.layer.cornerRadius = 22;
    coverBox.layer.cornerCurve = kCACornerCurveContinuous;
    [wrap addSubview:coverBox];
    [coverBox.leadingAnchor constraintEqualToAnchor:wrap.layoutMarginsGuide.leadingAnchor].active = YES;
    [coverBox.trailingAnchor constraintEqualToAnchor:wrap.layoutMarginsGuide.trailingAnchor].active = YES;
    [coverBox.topAnchor constraintEqualToAnchor:wrap.topAnchor].active = YES;
    [coverBox.bottomAnchor constraintEqualToAnchor:wrap.bottomAnchor].active = YES;
    [coverBox.heightAnchor constraintEqualToConstant:220].active = YES;

    LMVGDetailGradientView *gradient = [LMVGDetailGradientView new];
    gradient.translatesAutoresizingMaskIntoConstraints = NO;
    gradient.channelID = self.channelID;
    [coverBox addSubview:gradient];

    UIImageView *cover = [UIImageView new];
    cover.translatesAutoresizingMaskIntoConstraints = NO;
    cover.contentMode = UIViewContentModeScaleAspectFill;
    cover.clipsToBounds = YES;
    [coverBox addSubview:cover];
    cover.layer.minificationFilter = kCAFilterTrilinear;
    self.cover = cover;

    LMVGDetailGradientView *shade = [LMVGDetailGradientView new];
    shade.translatesAutoresizingMaskIntoConstraints = NO;
    shade.shade = YES;
    shade.userInteractionEnabled = NO;
    [coverBox addSubview:shade];

    for (UIView *view in @[gradient, cover, shade]) {
        [view.leadingAnchor constraintEqualToAnchor:coverBox.leadingAnchor].active = YES;
        [view.trailingAnchor constraintEqualToAnchor:coverBox.trailingAnchor].active = YES;
        [view.topAnchor constraintEqualToAnchor:coverBox.topAnchor].active = YES;
        [view.bottomAnchor constraintEqualToAnchor:coverBox.bottomAnchor].active = YES;
    }

    UIButton *back = LMVGRoundButton(@"chevron.left", self, @selector(goBack));
    back.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.28];
    back.tintColor = UIColor.whiteColor;
    [coverBox addSubview:back];
    [back.leadingAnchor constraintEqualToAnchor:coverBox.leadingAnchor constant:12].active = YES;
    [back.topAnchor constraintEqualToAnchor:coverBox.topAnchor constant:12].active = YES;

    // 5.1.3: resolution chip, bottom-right of the preview.
    UILabel *resolution = LMVGMakeResolutionBadge();
    [coverBox addSubview:resolution];
    self.resolutionBadge = resolution;
    [resolution.trailingAnchor constraintEqualToAnchor:coverBox.trailingAnchor constant:-12].active = YES;
    [resolution.bottomAnchor constraintEqualToAnchor:coverBox.bottomAnchor constant:-12].active = YES;
}

- (void)buildTitle {
    UIView *box = [UIView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.layoutMargins = UIEdgeInsetsMake(14, 16, 0, 16);
    [self.stack addArrangedSubview:box];

    UILabel *title = LMVGLabel(LMVGChannelTitle(self.channelID), LMVGFont(24, UIFontWeightHeavy), UIColor.labelColor);
    UISwitch *toggle = [UISwitch new];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.onTintColor = UIColor.systemGreenColor;
    [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
    self.toggle = toggle;

    UILabel *subtitle = LMVGLabel(@"", LMVGFont(12, UIFontWeightRegular), UIColor.secondaryLabelColor);
    subtitle.numberOfLines = 0;
    self.subtitle = subtitle;

    [box addSubview:title];
    [box addSubview:toggle];
    [box addSubview:subtitle];
    [title.leadingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.leadingAnchor].active = YES;
    [title.topAnchor constraintEqualToAnchor:box.topAnchor constant:14].active = YES;
    [title.trailingAnchor constraintLessThanOrEqualToAnchor:toggle.leadingAnchor constant:-10].active = YES;
    [toggle.trailingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.trailingAnchor].active = YES;
    [toggle.centerYAnchor constraintEqualToAnchor:title.centerYAnchor].active = YES;
    [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor].active = YES;
    [subtitle.trailingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.trailingAnchor].active = YES;
    [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5].active = YES;
    [subtitle.bottomAnchor constraintEqualToAnchor:box.bottomAnchor].active = YES;
}

- (void)buildSegments {
    UIView *box = [UIView new];
    box.translatesAutoresizingMaskIntoConstraints = NO;
    box.layoutMargins = UIEdgeInsetsMake(14, 16, 0, 16);
    [self.stack addArrangedSubview:box];

    NSMutableArray *titles = [NSMutableArray arrayWithArray:@[@"素材", @"声音"]];
    if (LMVGTextColorKey(self.channelID).length) [titles addObject:@"颜色"];
    UISegmentedControl *segments = [[UISegmentedControl alloc] initWithItems:titles];
    segments.translatesAutoresizingMaskIntoConstraints = NO;
    segments.selectedSegmentIndex = 0;
    segments.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
    segments.selectedSegmentTintColor = UIColor.systemBackgroundColor;
    [segments addTarget:self action:@selector(segmentChanged:) forControlEvents:UIControlEventValueChanged];
    [box addSubview:segments];
    self.segments = segments;
    [segments.leadingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.leadingAnchor].active = YES;
    [segments.trailingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.trailingAnchor].active = YES;
    [segments.topAnchor constraintEqualToAnchor:box.topAnchor constant:14].active = YES;
    [segments.heightAnchor constraintEqualToConstant:34].active = YES;
    [segments.bottomAnchor constraintEqualToAnchor:box.bottomAnchor].active = YES;

    UIStackView *panel = [UIStackView new];
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.axis = UILayoutConstraintAxisVertical;
    panel.spacing = 10;
    panel.layoutMargins = UIEdgeInsetsMake(14, 16, 0, 16);
    panel.layoutMarginsRelativeArrangement = YES;
    [self.stack addArrangedSubview:panel];
    self.panel = panel;
}

- (void)refresh {
    NSString *relative = LMVGSelectedMaterial(self.channelID);
    NSString *name = relative.length ? LMVGMaterialName(relative) : @"未选择素材";
    BOOL on = LMVGPrefBool(LMVGEnableKey(self.channelID), NO);
    self.toggle.on = on;
    self.subtitle.text = [NSString stringWithFormat:@"%@ · %@", name, on ? @"已启用" : @"未启用"];
    LMVGApplyResolution(self.resolutionBadge, relative);
    if (![self.coverRelative isEqualToString:relative]) {
        self.coverRelative = relative ?: @"";
        self.cover.image = nil;
    }
    if (!self.cover.image) {
        __weak typeof(self) weakSelf = self;
        LMVGLoadCover(relative, ^(UIImage *image) {
            if (!image) return;
            if (LMVGReduceMotion()) { weakSelf.cover.image = image; return; }
            [UIView transitionWithView:weakSelf.cover duration:0.28 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
                weakSelf.cover.image = image;
            } completion:nil];
        });
    }
}

- (void)loadMaterials {
    __weak typeof(self) weakSelf = self;
    LMVGLoadMaterials(^(NSArray<NSDictionary *> *rows) {
        weakSelf.materials = rows;
        if (weakSelf.segmentIndex == 0) [weakSelf rebuildPanel];
    });
}

#pragma mark - Panel

- (void)segmentChanged:(UISegmentedControl *)segments {
    self.segmentIndex = segments.selectedSegmentIndex;
    [self rebuildPanel];
}

- (void)rebuildPanel {
    for (UIView *view in self.panel.arrangedSubviews) {
        [self.panel removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    if (self.segmentIndex == 0) [self buildMaterialsPanel];
    else if (self.segmentIndex == 1) [self buildSoundPanel];
    else [self buildColorPanel];
    // 4.3.7: the strip always starts at the first material after entering or
    // refreshing, instead of keeping whatever offset it had.
    if (self.segmentIndex == 0) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.materialStrip setContentOffset:CGPointZero animated:NO];
        });
    }
}

- (void)buildMaterialsPanel {
    UILabel *heading = LMVGLabel([NSString stringWithFormat:@"素材库 · %lu 个", (unsigned long)self.materials.count],
                                 LMVGFont(12, UIFontWeightSemibold), UIColor.secondaryLabelColor);
    [self.panel addArrangedSubview:heading];

    if (!self.materials.count) {
        UILabel *empty = LMVGLabel(@"还没有素材。点下方「从相册导入」添加视频。",
                                   LMVGFont(11, UIFontWeightRegular), UIColor.tertiaryLabelColor);
        empty.numberOfLines = 0;
        [self.panel addArrangedSubview:empty];
    } else {
        UIScrollView *scroll = [UIScrollView new];
        scroll.translatesAutoresizingMaskIntoConstraints = NO;
        scroll.showsHorizontalScrollIndicator = NO;
        UIStackView *row = [UIStackView new];
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.axis = UILayoutConstraintAxisHorizontal;
        row.spacing = 8;
        [scroll addSubview:row];
        [self.panel addArrangedSubview:scroll];
        self.materialStrip = scroll;
        [scroll.heightAnchor constraintEqualToConstant:112].active = YES;
        [row.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor].active = YES;
        [row.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor].active = YES;
        [row.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor].active = YES;
        [row.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor].active = YES;
        [row.heightAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.heightAnchor].active = YES;

        NSString *selected = LMVGSelectedMaterial(self.channelID);
        for (NSDictionary *material in self.materials) {
            [row addArrangedSubview:[self materialCard:material selected:selected]];
        }
    }

    UIStackView *buttons = [UIStackView new];
    buttons.axis = UILayoutConstraintAxisHorizontal;
    buttons.spacing = 10;
    buttons.distribution = UIStackViewDistributionFillEqually;
    [self.panel addArrangedSubview:buttons];
    UIButton *change = [self actionButton:@"更换素材" symbol:@"rectangle.2.swap" filled:YES action:@selector(cycleMaterial)];
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(changeMaterialFromLongPress:)];
    [change addGestureRecognizer:longPress];
    [buttons addArrangedSubview:change];
    [buttons addArrangedSubview:[self actionButton:@"从相册导入" symbol:@"square.and.arrow.down" filled:NO action:@selector(importVideos)]];
    [buttons.heightAnchor constraintEqualToConstant:44].active = YES;

    UILabel *note = LMVGLabel(@"点按「更换素材」直接切到下一个；长按可从列表中选择。删除使用中的素材会取消选择。",
                              LMVGFont(10, UIFontWeightRegular), UIColor.tertiaryLabelColor);
    note.numberOfLines = 0;
    [self.panel addArrangedSubview:note];
}

- (UIView *)materialCard:(NSDictionary *)material selected:(NSString *)selected {
    UIControl *card = [UIControl new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.accessibilityIdentifier = material[@"path"];
    BOOL isSelected = [material[@"path"] isEqualToString:selected];

    UIImageView *thumb = [UIImageView new];
    thumb.translatesAutoresizingMaskIntoConstraints = NO;
    thumb.contentMode = UIViewContentModeScaleAspectFill;
    thumb.clipsToBounds = YES;
    thumb.backgroundColor = [UIColor tertiarySystemFillColor];
    thumb.layer.cornerRadius = 12;
    thumb.layer.cornerCurve = kCACornerCurveContinuous;
    thumb.layer.borderWidth = isSelected ? 2.5 : 0;
    thumb.layer.borderColor = LMVGAccent().CGColor;
    thumb.layer.minificationFilter = kCAFilterTrilinear;
    thumb.tag = 2001;
    [card addSubview:thumb];

    UILabel *name = LMVGLabel(material[@"name"], LMVGFont(10, UIFontWeightMedium),
                              isSelected ? LMVGAccent() : UIColor.secondaryLabelColor);
    name.textAlignment = NSTextAlignmentCenter;
    name.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [card addSubview:name];

    [card.widthAnchor constraintEqualToConstant:96].active = YES;
    [thumb.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
    [thumb.trailingAnchor constraintEqualToAnchor:card.trailingAnchor].active = YES;
    [thumb.topAnchor constraintEqualToAnchor:card.topAnchor].active = YES;
    [thumb.heightAnchor constraintEqualToConstant:74].active = YES;
    [name.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
    [name.trailingAnchor constraintEqualToAnchor:card.trailingAnchor].active = YES;
    [name.topAnchor constraintEqualToAnchor:thumb.bottomAnchor constant:4].active = YES;
    [name.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor].active = YES;

    __weak UIImageView *weakThumb = thumb;
    NSString *relative = material[@"path"];
    LMVGLoadThumb(relative, ^(UIImage *image) {
        if (!image) return;
        [UIView transitionWithView:weakThumb duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            weakThumb.image = image;
        } completion:nil];
    });
    LMVGAddPressFeedback(card);

    [card addTarget:self action:@selector(materialTapped:) forControlEvents:UIControlEventTouchUpInside];
    card.accessibilityLabel = material[@"name"];
    card.accessibilityValue = isSelected ? @"使用中" : @"";
    return card;
}

- (UIButton *)actionButton:(NSString *)title symbol:(NSString *)symbol filled:(BOOL)filled action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    UIImage *image = [UIImage systemImageNamed:symbol];
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:image forState:UIControlStateNormal];
    button.titleLabel.font = LMVGFont(12, UIFontWeightSemibold);
    button.layer.cornerRadius = 12;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    if (filled) {
        button.backgroundColor = LMVGAccent();
        button.tintColor = UIColor.whiteColor;
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    } else {
        button.backgroundColor = [UIColor secondarySystemGroupedBackgroundColor];
        button.tintColor = LMVGAccent();
        [button setTitleColor:LMVGAccent() forState:UIControlStateNormal];
    }
    // Title and icon are laid out by the default button metrics; no deprecated
    // edge insets and no configuration object (which would reset the colours set
    // above on iOS 15+).
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)buildSoundPanel {
    NSString *soundKey = [self.channelID stringByAppendingString:@"SoundEnabled"];
    NSString *volumeKey = [self.channelID stringByAppendingString:@"Volume"];

    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *label = LMVGLabel(@"播放声音", LMVGFont(13, UIFontWeightMedium), UIColor.labelColor);
    UILabel *detail = LMVGLabel(@"跟随系统静音开关", LMVGFont(10, UIFontWeightRegular), UIColor.secondaryLabelColor);
    UISwitch *toggle = [UISwitch new];
    toggle.translatesAutoresizingMaskIntoConstraints = NO;
    toggle.onTintColor = UIColor.systemGreenColor;
    toggle.on = LMVGPrefBool(soundKey, NO);
    toggle.tag = 3001;
    [toggle addTarget:self action:@selector(soundToggled:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:label];
    [row addSubview:detail];
    [row addSubview:toggle];
    [label.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [label.topAnchor constraintEqualToAnchor:row.topAnchor constant:6].active = YES;
    [detail.leadingAnchor constraintEqualToAnchor:label.leadingAnchor].active = YES;
    [detail.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:1].active = YES;
    [detail.bottomAnchor constraintEqualToAnchor:row.bottomAnchor].active = YES;
    [toggle.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
    [toggle.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [row.heightAnchor constraintEqualToConstant:52].active = YES;
    [self.panel addArrangedSubview:row];

    UIView *volumeRow = [UIView new];
    volumeRow.translatesAutoresizingMaskIntoConstraints = NO;
    UILabel *volumeLabel = LMVGLabel(@"音量", LMVGFont(13, UIFontWeightMedium), UIColor.labelColor);
    UISlider *slider = [UISlider new];
    slider.translatesAutoresizingMaskIntoConstraints = NO;
    slider.minimumValue = 0;
    slider.maximumValue = 100;
    slider.value = LMVGPrefDouble(volumeKey, 0.5) * 100.0;
    slider.minimumTrackTintColor = LMVGAccent();
    slider.tag = 3002;
    [slider addTarget:self action:@selector(volumeChanged:) forControlEvents:UIControlEventValueChanged];
    UILabel *value = LMVGLabel([NSString stringWithFormat:@"%.0f", slider.value], LMVGFont(11, UIFontWeightRegular), UIColor.secondaryLabelColor);
    value.tag = 3003;
    value.textAlignment = NSTextAlignmentRight;
    [volumeRow addSubview:volumeLabel];
    [volumeRow addSubview:slider];
    [volumeRow addSubview:value];
    [volumeLabel.leadingAnchor constraintEqualToAnchor:volumeRow.leadingAnchor].active = YES;
    [volumeLabel.centerYAnchor constraintEqualToAnchor:volumeRow.centerYAnchor].active = YES;
    [volumeLabel.widthAnchor constraintEqualToConstant:44].active = YES;
    [slider.leadingAnchor constraintEqualToAnchor:volumeLabel.trailingAnchor constant:6].active = YES;
    [slider.centerYAnchor constraintEqualToAnchor:volumeRow.centerYAnchor].active = YES;
    [value.leadingAnchor constraintEqualToAnchor:slider.trailingAnchor constant:6].active = YES;
    [value.trailingAnchor constraintEqualToAnchor:volumeRow.trailingAnchor].active = YES;
    [value.centerYAnchor constraintEqualToAnchor:volumeRow.centerYAnchor].active = YES;
    [value.widthAnchor constraintEqualToConstant:30].active = YES;
    [volumeRow.heightAnchor constraintEqualToConstant:48].active = YES;
    [self.panel addArrangedSubview:volumeRow];

    UILabel *note = LMVGLabel(@"面板通道支持独立音量；关闭「播放声音」后视频静音播放。",
                              LMVGFont(10, UIFontWeightRegular), UIColor.tertiaryLabelColor);
    note.numberOfLines = 0;
    [self.panel addArrangedSubview:note];
}

- (void)buildColorPanel {
    NSString *key = LMVGTextColorKey(self.channelID);
    UIColor *current = LMVTextColorForKey(key);

    UIView *row = [UIView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *swatch = [UIView new];
    swatch.translatesAutoresizingMaskIntoConstraints = NO;
    swatch.backgroundColor = current ?: UIColor.whiteColor;
    swatch.layer.cornerRadius = 14;
    swatch.layer.borderWidth = 1;
    swatch.layer.borderColor = [UIColor separatorColor].CGColor;
    swatch.tag = 4001;
    UILabel *label = LMVGLabel(LMVGTextColorRowTitle(self.channelID), LMVGFont(13, UIFontWeightMedium), UIColor.labelColor);
    UILabel *detail = LMVGLabel(current ? LMVTextColorHex(current) : @"跟随面板默认", LMVGFont(10, UIFontWeightRegular), UIColor.secondaryLabelColor);
    detail.tag = 4002;
    UIButton *choose = [UIButton buttonWithType:UIButtonTypeSystem];
    choose.translatesAutoresizingMaskIntoConstraints = NO;
    [choose setTitle:@"选择颜色" forState:UIControlStateNormal];
    choose.titleLabel.font = LMVGFont(12, UIFontWeightSemibold);
    [choose setTitleColor:LMVGAccent() forState:UIControlStateNormal];
    [choose addTarget:self action:@selector(openColorPicker) forControlEvents:UIControlEventTouchUpInside];
    [row addSubview:swatch];
    [row addSubview:label];
    [row addSubview:detail];
    [row addSubview:choose];
    [swatch.leadingAnchor constraintEqualToAnchor:row.leadingAnchor].active = YES;
    [swatch.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [swatch.widthAnchor constraintEqualToConstant:28].active = YES;
    [swatch.heightAnchor constraintEqualToConstant:28].active = YES;
    [label.leadingAnchor constraintEqualToAnchor:swatch.trailingAnchor constant:12].active = YES;
    [label.topAnchor constraintEqualToAnchor:row.topAnchor constant:4].active = YES;
    [detail.leadingAnchor constraintEqualToAnchor:label.leadingAnchor].active = YES;
    [detail.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:1].active = YES;
    [detail.bottomAnchor constraintEqualToAnchor:row.bottomAnchor].active = YES;
    [choose.trailingAnchor constraintEqualToAnchor:row.trailingAnchor].active = YES;
    [choose.centerYAnchor constraintEqualToAnchor:row.centerYAnchor].active = YES;
    [row.heightAnchor constraintEqualToConstant:50].active = YES;
    [self.panel addArrangedSubview:row];

    UILabel *note = LMVGLabel(@"只影响该面板的文字；恢复默认请删除该面板的素材选择。",
                              LMVGFont(10, UIFontWeightRegular), UIColor.tertiaryLabelColor);
    note.numberOfLines = 0;
    [self.panel addArrangedSubview:note];
}

#pragma mark - Actions

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)toggled:(UISwitch *)toggle {
    LMVGLightHaptic();
    // 5.2.1: Control Center's two frames share ONE switch - writing
    // "ControlCenterDarkBackgroundEnabled" here changed a key the tweak never reads,
    // so the toggle did nothing on that page.
    NSString *key = LMVGEnableKey(self.channelID);
    LMVGPrefSet(key, @(toggle.on));
    LMVGNotifyChannel(self.channelID);
    [self refresh];
}

- (void)soundToggled:(UISwitch *)toggle {
    NSString *key = [self.channelID stringByAppendingString:@"SoundEnabled"];
    LMVGPrefSet(key, @(toggle.on));
    LMVGNotifyChannel(self.channelID);
}

- (void)volumeChanged:(UISlider *)slider {
    NSString *key = [self.channelID stringByAppendingString:@"Volume"];
    double value = MAX(0.0, MIN(1.0, slider.value / 100.0));
    LMVGPrefSet(key, @(value));
    LMVGNotifyChannel(self.channelID);
    UILabel *label = (UILabel *)[self.panel viewWithTag:3003];
    label.text = [NSString stringWithFormat:@"%.0f", slider.value];
}

- (void)materialTapped:(UIControl *)control {
    NSString *relative = control.accessibilityIdentifier;
    if (!relative.length) return;
    LMVGLightHaptic();
    LMVGPrefSet([self.channelID stringByAppendingString:@"Video"], relative);
    LMVGNotifyChannel(self.channelID);
    [self refresh];
    [self rebuildPanel];
    [self revealSelectedMaterial];
}

// 4.3.4: the button's primary action is a direct switch (the reported surprise was
// that it only opened a list). Long-press still reaches the full picker.
// 4.3.8: after a selection the strip scrolls to that card and the page scrolls
// down so the chosen material is actually visible.
- (void)revealSelectedMaterial {
    if (self.segmentIndex != 0) return;
    NSString *selected = LMVGSelectedMaterial(self.channelID);
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        LMVChannelDetailController *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.segmentIndex != 0) return;
        UIView *row = strongSelf.materialStrip.subviews.firstObject;
        for (UIView *card in row.subviews) {
            if (![card.accessibilityIdentifier isEqualToString:selected]) continue;
            [strongSelf.materialStrip scrollRectToVisible:CGRectInset(card.frame, -16, 0) animated:YES];
            break;
        }
        CGRect rect = [strongSelf.panel convertRect:strongSelf.panel.bounds toView:strongSelf.scroll];
        [strongSelf.scroll scrollRectToVisible:CGRectInset(rect, 0, -12) animated:YES];
    });
}

- (void)cycleMaterial {
    if (!self.materials.count) { [self importVideos]; return; }
    NSString *current = LMVGSelectedMaterial(self.channelID);
    NSUInteger index = NSNotFound;
    for (NSUInteger i = 0; i < self.materials.count; i++) {
        if ([self.materials[i][@"path"] isEqualToString:current]) { index = i; break; }
    }
    NSUInteger next = (index == NSNotFound) ? 0 : (index + 1) % self.materials.count;
    LMVGPrefSet([self.channelID stringByAppendingString:@"Video"], self.materials[next][@"path"]);
    LMVGNotifyChannel(self.channelID);
    LMVGLightHaptic();
    [self refresh];
    [self rebuildPanel];
    [self revealSelectedMaterial];
}
- (void)changeMaterialFromLongPress:(UILongPressGestureRecognizer *)recognizer {
    if (recognizer.state != UIGestureRecognizerStateBegan) return;
    [self changeMaterial];
}
- (void)changeMaterial {
    __weak typeof(self) weakSelf = self;
    UIViewController *picker = LMVCreateMaterialPicker(LMVGSelectedMaterial(self.channelID), YES, ^(NSString *relative, NSString *name) {
        LMVGPrefSet([weakSelf.channelID stringByAppendingString:@"Video"], relative ?: @"");
        LMVGNotifyChannel(weakSelf.channelID);
        [weakSelf refresh];
        [weakSelf rebuildPanel];
    }, nil);
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)importVideos {
    if (self.importing) return;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    config.filter = [PHPickerFilter videosFilter];
    config.selectionLimit = 0;
    config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSArray *videos = [results filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PHPickerResult *result, NSDictionary *bindings) {
        return [result.itemProvider hasItemConformingToTypeIdentifier:@"public.movie"];
    }]];
    if (!videos.count) return;
    self.importing = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSString *> *imported = [NSMutableArray new];
    for (PHPickerResult *result in videos) {
        dispatch_group_enter(group);
        [result.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
            NSString *relative = nil;
            if (url && !error) relative = LMVImportMovie(url, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (relative.length) [imported addObject:relative];
                dispatch_group_leave(group);
            });
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        weakSelf.importing = NO;
        if (imported.count) {
            LMVGPrefSet([weakSelf.channelID stringByAppendingString:@"Video"], imported.firstObject);
            LMVGNotifyChannel(weakSelf.channelID);
            [weakSelf refresh];
            [weakSelf loadMaterials];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入失败"
                                                                           message:@"没能保存视频，请重试。"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
        }
    });
}

- (void)openColorPicker {
    NSString *key = LMVGTextColorKey(self.channelID);
    if (!key.length) return;
    LMVTextColorPicker *picker = [LMVTextColorPicker new];
    picker.preferenceKey = key;
    picker.modalPresentationStyle = UIModalPresentationOverFullScreen;
    __weak typeof(self) weakSelf = self;
    picker.onChange = ^(UIColor *color) {
        UIView *swatch = [weakSelf.panel viewWithTag:4001];
        swatch.backgroundColor = color ?: UIColor.whiteColor;
        UILabel *detail = (UILabel *)[weakSelf.panel viewWithTag:4002];
        detail.text = color ? LMVTextColorHex(color) : @"跟随面板默认";
    };
    [self presentViewController:picker animated:YES completion:nil];
}

@end
