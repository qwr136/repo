#import "LMVGalleryController.h"
#import "LMVGalleryKit.h"
#import "LMVMaterialPickerAPI.h"
#import "LMVImport.h"

// 4.3.1 (C1): the two pages the gallery's bottom bar points at. Both are ordinary
// pushes on the Settings navigation stack, hide the bar like the gallery and keep
// every write on the same per-channel keys.

#pragma mark - Panel grid

@interface LMVPanelGridController () <UIScrollViewDelegate>
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) NSArray<NSString *> *panels;
@property(nonatomic,strong) NSMutableArray<UIView *> *cards;
@end

@implementation LMVPanelGridController

- (instancetype)init {
    self = [super init];
    if (self) {
        _panels = LMVGPanelIDs();
        _cards = [NSMutableArray new];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self build];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    [self refresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)build {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.contentInset = UIEdgeInsetsMake(0, 0, 28, 0);
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

    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.layoutMargins = UIEdgeInsetsMake(0, 14, 0, 14);
    [stack addArrangedSubview:bar];
    [bar.heightAnchor constraintEqualToConstant:52].active = YES;
    UIButton *back = LMVGRoundButton(@"chevron.left", self, @selector(goBack));
    [bar addSubview:back];
    [back.leadingAnchor constraintEqualToAnchor:bar.layoutMarginsGuide.leadingAnchor].active = YES;
    [back.topAnchor constraintEqualToAnchor:bar.topAnchor constant:10].active = YES;

    UIView *head = [UIView new];
    head.translatesAutoresizingMaskIntoConstraints = NO;
    head.layoutMargins = UIEdgeInsetsMake(0, 16, 0, 16);
    [stack addArrangedSubview:head];
    UILabel *title = LMVGLabel(@"面板", LMVGFont(28, UIFontWeightHeavy), UIColor.labelColor);
    UILabel *sub = LMVGLabel([NSString stringWithFormat:@"%lu 个面板通道 · 已启用 %lu 个",
                              (unsigned long)self.panels.count,
                              (unsigned long)[self enabledCount]], LMVGFont(12, UIFontWeightRegular), UIColor.secondaryLabelColor);
    [head addSubview:title];
    [head addSubview:sub];
    [title.leadingAnchor constraintEqualToAnchor:head.layoutMarginsGuide.leadingAnchor].active = YES;
    [title.topAnchor constraintEqualToAnchor:head.topAnchor constant:2].active = YES;
    [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor].active = YES;
    [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4].active = YES;
    [sub.bottomAnchor constraintEqualToAnchor:head.bottomAnchor constant:-14].active = YES;

    UIView *gridBox = [UIView new];
    gridBox.translatesAutoresizingMaskIntoConstraints = NO;
    gridBox.layoutMargins = UIEdgeInsetsMake(0, 14, 0, 14);
    [stack addArrangedSubview:gridBox];
    UIStackView *grid = [UIStackView new];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 9;
    [gridBox addSubview:grid];
    [grid.leadingAnchor constraintEqualToAnchor:gridBox.layoutMarginsGuide.leadingAnchor].active = YES;
    [grid.trailingAnchor constraintEqualToAnchor:gridBox.layoutMarginsGuide.trailingAnchor].active = YES;
    [grid.topAnchor constraintEqualToAnchor:gridBox.topAnchor].active = YES;
    [grid.bottomAnchor constraintEqualToAnchor:gridBox.bottomAnchor].active = YES;

    UIStackView *row = nil;
    for (NSUInteger index = 0; index < self.panels.count; index++) {
        if (index % 2 == 0) {
            row = [UIStackView new];
            row.axis = UILayoutConstraintAxisHorizontal;
            row.spacing = 9;
            row.distribution = UIStackViewDistributionFillEqually;
            [grid addArrangedSubview:row];
            if (index + 1 >= self.panels.count) {
                UIView *filler = [UIView new];
                filler.translatesAutoresizingMaskIntoConstraints = NO;
                [row addArrangedSubview:filler];
            }
        }
        UIView *card = [self cardForChannel:self.panels[index]];
        [row addArrangedSubview:card];
        [card.heightAnchor constraintEqualToConstant:112].active = YES;
        [self.cards addObject:card];
    }
}

- (NSUInteger)enabledCount {
    NSUInteger count = 0;
    for (NSString *identifier in self.panels)
        if (LMVGPrefBool([identifier stringByAppendingString:@"BackgroundEnabled"], NO)) count++;
    return count;
}

- (UIView *)cardForChannel:(NSString *)identifier {
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 18;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.accessibilityIdentifier = identifier;

    UIView *tile = [UIView new];
    tile.translatesAutoresizingMaskIntoConstraints = NO;
    tile.backgroundColor = [UIColor.systemBlue colorWithAlphaComponent:0.10];
    tile.layer.cornerRadius = 13;
    tile.layer.cornerCurve = kCACornerCurveContinuous;
    [card addSubview:tile];
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:LMVGSymbolForChannel(identifier)]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.systemBlueColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;
    [tile addSubview:icon];

    UIView *dot = [UIView new];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.tag = 1004;
    dot.layer.cornerRadius = 3;
    dot.backgroundColor = UIColor.systemGreenColor;
    dot.hidden = YES;
    [card addSubview:dot];

    UILabel *name = LMVGLabel(LMVGChannelTitle(identifier), LMVGFont(13, UIFontWeightSemibold), UIColor.labelColor);
    name.numberOfLines = 2;
    UILabel *material = LMVGLabel(@"", LMVGFont(10, UIFontWeightRegular), UIColor.secondaryLabelColor);
    material.tag = 1002;
    material.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [card addSubview:name];
    [card addSubview:material];

    [tile.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12].active = YES;
    [tile.topAnchor constraintEqualToAnchor:card.topAnchor constant:12].active = YES;
    [tile.widthAnchor constraintEqualToConstant:34].active = YES;
    [tile.heightAnchor constraintEqualToConstant:34].active = YES;
    [icon.centerXAnchor constraintEqualToAnchor:tile.centerXAnchor].active = YES;
    [icon.centerYAnchor constraintEqualToAnchor:tile.centerYAnchor].active = YES;
    [icon.widthAnchor constraintEqualToConstant:18].active = YES;
    [icon.heightAnchor constraintEqualToConstant:18].active = YES;
    [dot.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12].active = YES;
    [dot.topAnchor constraintEqualToAnchor:card.topAnchor constant:16].active = YES;
    [dot.widthAnchor constraintEqualToConstant:6].active = YES;
    [dot.heightAnchor constraintEqualToConstant:6].active = YES;
    [name.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12].active = YES;
    [name.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12].active = YES;
    [name.topAnchor constraintEqualToAnchor:tile.bottomAnchor constant:9].active = YES;
    [material.leadingAnchor constraintEqualToAnchor:name.leadingAnchor].active = YES;
    [material.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12].active = YES;
    [material.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:2].active = YES;
    [material.bottomAnchor constraintLessThanOrEqualToAnchor:card.bottomAnchor constant:-10].active = YES;

    LMVGAddPressFeedback(card);
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openChannel:)];
    [card addGestureRecognizer:tap];
    card.userInteractionEnabled = YES;
    card.isAccessibilityElement = YES;
    card.accessibilityLabel = LMVGChannelTitle(identifier);
    return card;
}

- (void)refresh {
    for (UIView *card in self.cards) {
        NSString *identifier = card.accessibilityIdentifier;
        BOOL on = LMVGPrefBool([identifier stringByAppendingString:@"BackgroundEnabled"], NO);
        [card viewWithTag:1004].hidden = !on;
        NSString *relative = LMVGSelectedMaterial(identifier);
        UILabel *material = (UILabel *)[card viewWithTag:1002];
        material.text = relative.length ? LMVGMaterialName(relative) : @"未选择素材";
        material.textColor = relative.length ? UIColor.secondaryLabelColor : UIColor.tertiaryLabelColor;
    }
}

- (void)openChannel:(UITapGestureRecognizer *)gesture {
    NSString *identifier = gesture.view.accessibilityIdentifier;
    if (!identifier.length) return;
    [self.navigationController pushViewController:[[LMVChannelDetailController alloc] initWithChannelID:identifier] animated:YES];
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

@end

#pragma mark - Material library

@interface LMVMaterialLibraryController () <PHPickerViewControllerDelegate>
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) UIStackView *grid;
@property(nonatomic,strong) UILabel *subtitle;
@property(nonatomic,strong) NSArray<NSDictionary *> *materials;
@property(nonatomic) BOOL importing;
@end

@implementation LMVMaterialLibraryController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self build];
    [self reload];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    [self reload];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)build {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.contentInset = UIEdgeInsetsMake(0, 0, 110, 0);
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

    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.layoutMargins = UIEdgeInsetsMake(0, 14, 0, 14);
    [stack addArrangedSubview:bar];
    [bar.heightAnchor constraintEqualToConstant:52].active = YES;
    UIButton *back = LMVGRoundButton(@"chevron.left", self, @selector(goBack));
    [bar addSubview:back];
    [back.leadingAnchor constraintEqualToAnchor:bar.layoutMarginsGuide.leadingAnchor].active = YES;
    [back.topAnchor constraintEqualToAnchor:bar.topAnchor constant:10].active = YES;

    UIView *head = [UIView new];
    head.translatesAutoresizingMaskIntoConstraints = NO;
    head.layoutMargins = UIEdgeInsetsMake(0, 16, 0, 16);
    [stack addArrangedSubview:head];
    UILabel *title = LMVGLabel(@"素材库", LMVGFont(28, UIFontWeightHeavy), UIColor.labelColor);
    UILabel *sub = LMVGLabel(@"", LMVGFont(12, UIFontWeightRegular), UIColor.secondaryLabelColor);
    self.subtitle = sub;
    [head addSubview:title];
    [head addSubview:sub];
    [title.leadingAnchor constraintEqualToAnchor:head.layoutMarginsGuide.leadingAnchor].active = YES;
    [title.topAnchor constraintEqualToAnchor:head.topAnchor constant:2].active = YES;
    [sub.leadingAnchor constraintEqualToAnchor:title.leadingAnchor].active = YES;
    [sub.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:4].active = YES;
    [sub.bottomAnchor constraintEqualToAnchor:head.bottomAnchor constant:-14].active = YES;

    UIView *gridBox = [UIView new];
    gridBox.translatesAutoresizingMaskIntoConstraints = NO;
    gridBox.layoutMargins = UIEdgeInsetsMake(0, 14, 0, 14);
    [stack addArrangedSubview:gridBox];
    UIStackView *grid = [UIStackView new];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 9;
    [gridBox addSubview:grid];
    self.grid = grid;
    [grid.leadingAnchor constraintEqualToAnchor:gridBox.layoutMarginsGuide.leadingAnchor].active = YES;
    [grid.trailingAnchor constraintEqualToAnchor:gridBox.layoutMarginsGuide.trailingAnchor].active = YES;
    [grid.topAnchor constraintEqualToAnchor:gridBox.topAnchor].active = YES;
    [grid.bottomAnchor constraintEqualToAnchor:gridBox.bottomAnchor].active = YES;

    UIView *bar2 = [UIView new];
    bar2.translatesAutoresizingMaskIntoConstraints = NO;
    bar2.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    bar2.layer.cornerRadius = 22;
    bar2.layer.cornerCurve = kCACornerCurveContinuous;
    bar2.layer.shadowColor = UIColor.blackColor.CGColor;
    bar2.layer.shadowOpacity = 0.10;
    bar2.layer.shadowRadius = 16;
    bar2.layer.shadowOffset = CGSizeMake(0, 8);
    [self.view addSubview:bar2];

    UIStackView *actions = [UIStackView new];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.spacing = 10;
    actions.distribution = UIStackViewDistributionFillEqually;
    [bar2 addSubview:actions];
    [actions addArrangedSubview:[self button:@"从相册导入" symbol:@"square.and.arrow.down" filled:YES action:@selector(importVideos)]];
    [actions addArrangedSubview:[self button:@"管理素材" symbol:@"slider.horizontal.3" filled:NO action:@selector(manageMaterials)]];
    [bar2.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14].active = YES;
    [bar2.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14].active = YES;
    [bar2.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10].active = YES;
    [bar2.heightAnchor constraintEqualToConstant:58].active = YES;
    [actions.leadingAnchor constraintEqualToAnchor:bar2.leadingAnchor constant:8].active = YES;
    [actions.trailingAnchor constraintEqualToAnchor:bar2.trailingAnchor constant:-8].active = YES;
    [actions.topAnchor constraintEqualToAnchor:bar2.topAnchor constant:8].active = YES;
    [actions.bottomAnchor constraintEqualToAnchor:bar2.bottomAnchor constant:-8].active = YES;
}

- (UIButton *)button:(NSString *)title symbol:(NSString *)symbol filled:(BOOL)filled action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button setTitle:title forState:UIControlStateNormal];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.titleLabel.font = LMVGFont(12, UIFontWeightSemibold);
    button.layer.cornerRadius = 14;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    if (filled) {
        button.backgroundColor = UIColor.systemBlueColor;
        button.tintColor = UIColor.whiteColor;
        [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    } else {
        button.backgroundColor = [UIColor systemBlueColor];
        button.backgroundColor = [UIColor.systemBlue colorWithAlphaComponent:0.12];
        button.tintColor = UIColor.systemBlueColor;
        [button setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
    }
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)reload {
    __weak typeof(self) weakSelf = self;
    LMVGLoadMaterials(^(NSArray<NSDictionary *> *rows) {
        weakSelf.materials = rows;
        [weakSelf rebuildGrid];
    });
}

- (void)rebuildGrid {
    for (UIView *view in self.grid.arrangedSubviews) {
        [self.grid removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    self.subtitle.text = [NSString stringWithFormat:@"%lu 个素材 · 原片保存", (unsigned long)self.materials.count];

    if (!self.materials.count) {
        UIView *empty = [UIView new];
        empty.translatesAutoresizingMaskIntoConstraints = NO;
        empty.layer.cornerRadius = 20;
        empty.layer.cornerCurve = kCACornerCurveContinuous;
        empty.layer.borderWidth = 1.4;
        empty.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.7].CGColor;
        [self.grid addArrangedSubview:empty];
        [empty.heightAnchor constraintEqualToConstant:170].active = YES;
        UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"photo.on.rectangle.angled"]];
        icon.translatesAutoresizingMaskIntoConstraints = NO;
        icon.tintColor = UIColor.tertiaryLabelColor;
        UILabel *label = LMVGLabel(@"还没有素材", LMVGFont(14, UIFontWeightSemibold), UIColor.secondaryLabelColor);
        UILabel *hint = LMVGLabel(@"点下方「从相册导入」添加视频", LMVGFont(11, UIFontWeightRegular), UIColor.tertiaryLabelColor);
        [empty addSubview:icon];
        [empty addSubview:label];
        [empty addSubview:hint];
        [icon.centerXAnchor constraintEqualToAnchor:empty.centerXAnchor].active = YES;
        [icon.centerYAnchor constraintEqualToAnchor:empty.centerYAnchor constant:-26].active = YES;
        [icon.widthAnchor constraintEqualToConstant:34].active = YES;
        [icon.heightAnchor constraintEqualToConstant:34].active = YES;
        [label.centerXAnchor constraintEqualToAnchor:empty.centerXAnchor].active = YES;
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:10].active = YES;
        [hint.centerXAnchor constraintEqualToAnchor:empty.centerXAnchor].active = YES;
        [hint.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:4].active = YES;
        return;
    }

    UIStackView *row = nil;
    for (NSUInteger index = 0; index < self.materials.count; index++) {
        if (index % 2 == 0) {
            row = [UIStackView new];
            row.axis = UILayoutConstraintAxisHorizontal;
            row.spacing = 9;
            row.distribution = UIStackViewDistributionFillEqually;
            [self.grid addArrangedSubview:row];
            if (index + 1 >= self.materials.count) {
                UIView *filler = [UIView new];
                filler.translatesAutoresizingMaskIntoConstraints = NO;
                [row addArrangedSubview:filler];
            }
        }
        UIView *card = [self cardForMaterial:self.materials[index]];
        [row addArrangedSubview:card];
        [card.heightAnchor constraintEqualToConstant:132].active = YES;
    }
}

- (UIView *)cardForMaterial:(NSDictionary *)material {
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    card.accessibilityIdentifier = material[@"path"];

    UIImageView *cover = [UIImageView new];
    cover.translatesAutoresizingMaskIntoConstraints = NO;
    cover.contentMode = UIViewContentModeScaleAspectFill;
    cover.clipsToBounds = YES;
    cover.backgroundColor = UIColor.tertiarySystemFillColor;
    cover.tag = 1001;
    [card addSubview:cover];

    UILabel *name = LMVGLabel(material[@"name"], LMVGFont(11, UIFontWeightMedium), UIColor.labelColor);
    name.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [card addSubview:name];

    UILabel *badge = LMVGLabel(@"", LMVGFont(9, UIFontWeightSemibold), UIColor.systemBlueColor);
    badge.tag = 1002;
    badge.hidden = YES;
    [card addSubview:badge];

    [cover.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
    [cover.trailingAnchor constraintEqualToAnchor:card.trailingAnchor].active = YES;
    [cover.topAnchor constraintEqualToAnchor:card.topAnchor].active = YES;
    [cover.heightAnchor constraintEqualToConstant:98].active = YES;
    [name.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:9].active = YES;
    [name.trailingAnchor constraintLessThanOrEqualToAnchor:badge.leadingAnchor constant:-4].active = YES;
    [name.topAnchor constraintEqualToAnchor:cover.bottomAnchor constant:6].active = YES;
    [badge.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-9].active = YES;
    [badge.centerYAnchor constraintEqualToAnchor:name.centerYAnchor].active = YES;

    BOOL used = NO;
    for (NSString *identifier in LMVChannelIDs())
        if ([LMVGSelectedMaterial(identifier) isEqualToString:material[@"path"]]) { used = YES; break; }
    if (used) {
        badge.text = @"使用中";
        badge.hidden = NO;
    }

    __weak UIImageView *weakCover = cover;
    LMVGLoadCover(material[@"path"], ^(UIImage *image) {
        if (!image) return;
        [UIView transitionWithView:weakCover duration:0.25 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
            weakCover.image = image;
        } completion:nil];
    });
    LMVGAddPressFeedback(card);
    return card;
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)manageMaterials {
    UIViewController *picker = LMVCreateMaterialPicker(@"", YES, nil, ^{ });
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
    for (PHPickerResult *result in videos) {
        dispatch_group_enter(group);
        [result.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
            if (url && !error) LMVImportMovie(url, &error);
            dispatch_async(dispatch_get_main_queue(), ^{ dispatch_group_leave(group); });
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        weakSelf.importing = NO;
        [weakSelf reload];
    });
}

@end
