#import "LMVGalleryController.h"
#import "LMVGalleryKit.h"
#import "LMVTuneListController.h"
#import "LMVMaterialPickerAPI.h"

// 4.3.0: the settings page as a picture-led gallery. The classic specifier list is
// still one tap away from 「更多」, so nothing is lost if a device-specific layout
// problem shows up. This page only reads/writes the same preference keys and posts
// the same per-channel notifications as the list, so the tweak cannot tell them apart.

#define LMVGalleryVersion @"4.4.8"

// A view whose layer is the gradient itself, so it tracks Auto Layout instead of
// keeping the frame it was born with. Used for both the cover placeholder palette
// and the bottom shade that keeps white labels readable over any frame.
@interface LMVGradientView : UIView
@property(nonatomic,copy) NSString *channelID;
@property(nonatomic) BOOL shade;
@end

@implementation LMVGradientView
+ (Class)layerClass { return CAGradientLayer.class; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CAGradientLayer *gradient = (CAGradientLayer *)self.layer;
    if (self.shade) {
        gradient.colors = @[(id)[UIColor.clearColor CGColor],
                            (id)[UIColor.blackColor colorWithAlphaComponent:0.62].CGColor];
        gradient.locations = @[@0.35, @1.0];
        gradient.startPoint = CGPointMake(0.5, 0.0);
        gradient.endPoint = CGPointMake(0.5, 1.0);
    } else {
        LMVGApplyGradient(gradient, self.channelID ?: @"");
    }
}
@end

@interface LMVGalleryController () <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) UIScrollView *heroScroll;
@property(nonatomic,strong) UIStackView *heroRow;
@property(nonatomic,strong) UIPageControl *pageControl;
@property(nonatomic,strong) UIStackView *sceneGrid;
@property(nonatomic,strong) UILabel *subtitleLabel;
@property(nonatomic,strong) NSArray<NSString *> *scenes;
@property(nonatomic,strong) NSArray<NSString *> *panels;
@property(nonatomic,strong) NSArray<NSString *> *featured;
@property(nonatomic,strong) NSMutableArray<UIView *> *sceneCards;
@property(nonatomic,strong) NSMutableArray<UIView *> *heroCards;
// 4.3.6: the hero does NOT play video. It auto-advances to the next channel every
// few seconds, which is what "自动循环" asked for; tapping opens the channel page.
@property(nonatomic,strong) NSTimer *heroTimer;
@end

@implementation LMVGalleryController

- (instancetype)init {
    self = [super init];
    if (self) {
        // 4.3.4: the nine panel channels join the scene grid; the home page no
        // longer repeats the panel strip that the bottom bar already opens.
        _featured = LMVGSceneIDs();
        _panels = LMVGPanelIDs();
        _scenes = [_featured arrayByAddingObjectsFromArray:_panels];
        _sceneCards = [NSMutableArray new];
        _heroCards = [NSMutableArray new];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemGroupedBackgroundColor;
    [self buildScroll];
    [self buildTopBar];
    [self buildTitle];
    [self buildHero];
    [self buildSceneSection];
    [self buildFooter];
    [self buildTabBar];
    [self refreshContent];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    // Hiding the bar also disables the edge swipe; restore it explicitly so the
    // page still feels like a normal push in Settings.
    self.navigationController.interactivePopGestureRecognizer.delegate = nil;
    self.navigationController.interactivePopGestureRecognizer.enabled = YES;
    [self refreshContent];
    [self startHeroTimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopHeroTimer];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
}

- (void)dealloc {
    [_heroTimer invalidate];
}

#pragma mark - Layout

- (void)buildScroll {
    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.contentInset = UIEdgeInsetsMake(0, 0, 132, 0);
    [self.view addSubview:scroll];
    self.scroll = scroll;

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 0;
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

- (UIView *)paddedContainer {
    UIView *view = [UIView new];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    view.layoutMargins = UIEdgeInsetsMake(0, 14, 0, 14);
    return view;
}

- (void)buildTopBar {
    UIView *bar = [self paddedContainer];
    [self.stack addArrangedSubview:bar];
    [bar.heightAnchor constraintEqualToConstant:52].active = YES;

    UIButton *back = LMVGRoundButton(@"chevron.left", self, @selector(goBack));
    // 4.3.7: a single tap no longer opens the sheet; double-tap jumps to the
    // classic list. The sheet stays on the bottom 设置 tab.
    UIButton *more = LMVGRoundButton(@"ellipsis", nil, nil);
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openClassicList)];
    doubleTap.numberOfTapsRequired = 2;
    [more addGestureRecognizer:doubleTap];
    [bar addSubview:back];
    [bar addSubview:more];
    [back.leadingAnchor constraintEqualToAnchor:bar.layoutMarginsGuide.leadingAnchor].active = YES;
    [back.topAnchor constraintEqualToAnchor:bar.topAnchor constant:10].active = YES;
    [more.trailingAnchor constraintEqualToAnchor:bar.layoutMarginsGuide.trailingAnchor].active = YES;
    [more.topAnchor constraintEqualToAnchor:bar.topAnchor constant:10].active = YES;
}

- (void)buildTitle {
    UIView *box = [self paddedContainer];
    [self.stack addArrangedSubview:box];

    UILabel *title = LMVGLabel(@"锁屏背景", LMVGFont(30, UIFontWeightHeavy), UIColor.labelColor);
    UILabel *subtitle = LMVGLabel(@"", LMVGFont(12, UIFontWeightRegular), UIColor.secondaryLabelColor);
    self.subtitleLabel = subtitle;
    [box addSubview:title];
    [box addSubview:subtitle];
    [title.leadingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.leadingAnchor].active = YES;
    [title.trailingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.trailingAnchor].active = YES;
    [title.topAnchor constraintEqualToAnchor:box.topAnchor constant:2].active = YES;
    [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor].active = YES;
    [subtitle.trailingAnchor constraintEqualToAnchor:title.trailingAnchor].active = YES;
    [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3].active = YES;
    [subtitle.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-12].active = YES;
}

- (void)buildHero {
    UIView *box = [self paddedContainer];
    box.layoutMargins = UIEdgeInsetsMake(0, 0, 0, 0);
    [self.stack addArrangedSubview:box];

    UIScrollView *hero = [UIScrollView new];
    hero.translatesAutoresizingMaskIntoConstraints = NO;
    hero.showsHorizontalScrollIndicator = NO;
    hero.decelerationRate = UIScrollViewDecelerationRateFast;
    hero.clipsToBounds = NO;
    hero.delegate = self;
    [box addSubview:hero];
    self.heroScroll = hero;

    UIStackView *row = [UIStackView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 10;
    row.alignment = UIStackViewAlignmentFill;
    [hero addSubview:row];
    self.heroRow = row;

    [hero.leadingAnchor constraintEqualToAnchor:box.leadingAnchor].active = YES;
    [hero.trailingAnchor constraintEqualToAnchor:box.trailingAnchor].active = YES;
    [hero.topAnchor constraintEqualToAnchor:box.topAnchor].active = YES;
    [hero.heightAnchor constraintEqualToConstant:178].active = YES;

    [row.leadingAnchor constraintEqualToAnchor:hero.contentLayoutGuide.leadingAnchor constant:14].active = YES;
    [row.trailingAnchor constraintEqualToAnchor:hero.contentLayoutGuide.trailingAnchor constant:-14].active = YES;
    [row.topAnchor constraintEqualToAnchor:hero.contentLayoutGuide.topAnchor].active = YES;
    [row.bottomAnchor constraintEqualToAnchor:hero.contentLayoutGuide.bottomAnchor].active = YES;
    [row.heightAnchor constraintEqualToAnchor:hero.frameLayoutGuide.heightAnchor].active = YES;

    for (NSString *identifier in self.featured) {
        UIView *card = [self heroCardForChannel:identifier];
        [row addArrangedSubview:card];
        [card.widthAnchor constraintEqualToAnchor:hero.frameLayoutGuide.widthAnchor constant:-28].active = YES;
        [self.heroCards addObject:card];
    }

    UIPageControl *page = [UIPageControl new];
    page.translatesAutoresizingMaskIntoConstraints = NO;
    page.numberOfPages = self.featured.count;
    page.currentPageIndicatorTintColor = UIColor.labelColor;
    page.pageIndicatorTintColor = [UIColor.labelColor colorWithAlphaComponent:0.18];
    page.userInteractionEnabled = NO;
    [box addSubview:page];
    self.pageControl = page;
    [page.centerXAnchor constraintEqualToAnchor:box.centerXAnchor].active = YES;
    [page.topAnchor constraintEqualToAnchor:hero.bottomAnchor constant:2].active = YES;
    [page.bottomAnchor constraintEqualToAnchor:box.bottomAnchor].active = YES;

}

- (UIView *)heroCardForChannel:(NSString *)identifier {
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 22;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    card.accessibilityIdentifier = identifier;

    LMVGradientView *gradient = [LMVGradientView new];
    gradient.translatesAutoresizingMaskIntoConstraints = NO;
    gradient.channelID = identifier;
    [card addSubview:gradient];
    [gradient.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
    [gradient.trailingAnchor constraintEqualToAnchor:card.trailingAnchor].active = YES;
    [gradient.topAnchor constraintEqualToAnchor:card.topAnchor].active = YES;
    [gradient.bottomAnchor constraintEqualToAnchor:card.bottomAnchor].active = YES;

    UIImageView *cover = [UIImageView new];
    cover.translatesAutoresizingMaskIntoConstraints = NO;
    cover.contentMode = UIViewContentModeScaleAspectFill;
    cover.clipsToBounds = YES;
    cover.tag = 1001;
    [card addSubview:cover];
    [cover.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
    [cover.trailingAnchor constraintEqualToAnchor:card.trailingAnchor].active = YES;
    [cover.topAnchor constraintEqualToAnchor:card.topAnchor].active = YES;
    [cover.bottomAnchor constraintEqualToAnchor:card.bottomAnchor].active = YES;

    LMVGradientView *shade = [LMVGradientView new];
    shade.translatesAutoresizingMaskIntoConstraints = NO;
    shade.shade = YES;
    shade.userInteractionEnabled = NO;
    [card addSubview:shade];
    [shade.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
    [shade.trailingAnchor constraintEqualToAnchor:card.trailingAnchor].active = YES;
    [shade.topAnchor constraintEqualToAnchor:card.topAnchor].active = YES;
    [shade.bottomAnchor constraintEqualToAnchor:card.bottomAnchor].active = YES;

    UILabel *name = LMVGLabel(LMVGChannelTitle(identifier), LMVGFont(17, UIFontWeightBold), UIColor.whiteColor);
    UILabel *material = LMVGLabel(@"", LMVGFont(11, UIFontWeightRegular), [UIColor.whiteColor colorWithAlphaComponent:0.82]);
    material.tag = 1002;
    UILabel *badge = LMVGLabel(@"", LMVGFont(10, UIFontWeightSemibold), UIColor.whiteColor);
    badge.tag = 1003;
    badge.textAlignment = NSTextAlignmentCenter;
    badge.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.22];
    badge.layer.cornerRadius = 10;
    badge.layer.cornerCurve = kCACornerCurveContinuous;
    badge.clipsToBounds = YES;
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:name];
    [card addSubview:material];
    [card addSubview:badge];
    [name.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14].active = YES;
    [name.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-14].active = YES;
    [material.leadingAnchor constraintEqualToAnchor:name.leadingAnchor].active = YES;
    [material.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-14].active = YES;
    [material.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:2].active = YES;
    [material.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-13].active = YES;
    [badge.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12].active = YES;
    [badge.topAnchor constraintEqualToAnchor:card.topAnchor constant:12].active = YES;
    [badge.heightAnchor constraintEqualToConstant:20].active = YES;
    [badge.widthAnchor constraintGreaterThanOrEqualToConstant:52].active = YES;

    LMVGAddPressFeedback(card);
    // 4.3.6: tapping opens the channel page; no full-screen playback anywhere.
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openChannel:)];
    tap.delegate = self;
    [card addGestureRecognizer:tap];
    card.userInteractionEnabled = YES;
    card.isAccessibilityElement = YES;
    card.accessibilityLabel = LMVGChannelTitle(identifier);
    return card;
}

- (UIView *)sectionHeader:(NSString *)title detail:(NSString *)detail {
    UIView *box = [self paddedContainer];
    box.layoutMargins = UIEdgeInsetsMake(0, 16, 0, 16);
    UILabel *left = LMVGLabel(title, LMVGFont(15, UIFontWeightBold), UIColor.labelColor);
    UILabel *right = LMVGLabel(detail, LMVGFont(11, UIFontWeightRegular), UIColor.secondaryLabelColor);
    [box addSubview:left];
    [box addSubview:right];
    [left.leadingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.leadingAnchor].active = YES;
    [left.topAnchor constraintEqualToAnchor:box.topAnchor constant:20].active = YES;
    [left.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8].active = YES;
    [right.trailingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.trailingAnchor].active = YES;
    [right.lastBaselineAnchor constraintEqualToAnchor:left.lastBaselineAnchor].active = YES;
    return box;
}

- (void)buildSceneSection {
    [self.stack addArrangedSubview:[self sectionHeader:@"场景" detail:[NSString stringWithFormat:@"%lu 个", (unsigned long)self.scenes.count]]];

    UIView *box = [self paddedContainer];
    [self.stack addArrangedSubview:box];
    UIStackView *grid = [UIStackView new];
    grid.translatesAutoresizingMaskIntoConstraints = NO;
    grid.axis = UILayoutConstraintAxisVertical;
    grid.spacing = 8;
    [box addSubview:grid];
    self.sceneGrid = grid;
    [grid.leadingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.leadingAnchor].active = YES;
    [grid.trailingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.trailingAnchor].active = YES;
    [grid.topAnchor constraintEqualToAnchor:box.topAnchor].active = YES;
    [grid.bottomAnchor constraintEqualToAnchor:box.bottomAnchor].active = YES;

    [self rebuildSceneGrid];
}

- (void)rebuildSceneGrid {
    for (UIView *view in self.sceneGrid.arrangedSubviews) {
        [self.sceneGrid removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    [self.sceneCards removeAllObjects];

    UIStackView *row = nil;
    for (NSUInteger index = 0; index < self.scenes.count; index++) {
        if (index % 2 == 0) {
            row = [UIStackView new];
            row.axis = UILayoutConstraintAxisHorizontal;
            row.spacing = 8;
            row.distribution = UIStackViewDistributionFillEqually;
            [self.sceneGrid addArrangedSubview:row];
            if (index + 1 >= self.scenes.count) {
                UIView *filler = [UIView new];
                filler.translatesAutoresizingMaskIntoConstraints = NO;
                [row addArrangedSubview:filler];
            }
        }
        UIView *card = [self sceneCardForChannel:self.scenes[index]];
        [row addArrangedSubview:card];
        [card.heightAnchor constraintEqualToConstant:106].active = YES;
        [self.sceneCards addObject:card];
    }
}

- (UIView *)sceneCardForChannel:(NSString *)identifier {
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    card.accessibilityIdentifier = identifier;

    LMVGradientView *gradient = [LMVGradientView new];
    gradient.translatesAutoresizingMaskIntoConstraints = NO;
    gradient.channelID = identifier;
    [card addSubview:gradient];
    [gradient.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
    [gradient.trailingAnchor constraintEqualToAnchor:card.trailingAnchor].active = YES;
    [gradient.topAnchor constraintEqualToAnchor:card.topAnchor].active = YES;
    [gradient.bottomAnchor constraintEqualToAnchor:card.bottomAnchor].active = YES;

    UIImageView *cover = [UIImageView new];
    cover.translatesAutoresizingMaskIntoConstraints = NO;
    cover.contentMode = UIViewContentModeScaleAspectFill;
    cover.clipsToBounds = YES;
    cover.tag = 1001;
    [card addSubview:cover];
    [cover.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
    [cover.trailingAnchor constraintEqualToAnchor:card.trailingAnchor].active = YES;
    [cover.topAnchor constraintEqualToAnchor:card.topAnchor].active = YES;
    [cover.bottomAnchor constraintEqualToAnchor:card.bottomAnchor].active = YES;

    LMVGradientView *shade = [LMVGradientView new];
    shade.translatesAutoresizingMaskIntoConstraints = NO;
    shade.shade = YES;
    shade.userInteractionEnabled = NO;
    [card addSubview:shade];
    [shade.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
    [shade.trailingAnchor constraintEqualToAnchor:card.trailingAnchor].active = YES;
    [shade.topAnchor constraintEqualToAnchor:card.topAnchor].active = YES;
    [shade.bottomAnchor constraintEqualToAnchor:card.bottomAnchor].active = YES;

    UILabel *name = LMVGLabel(LMVGChannelTitle(identifier), LMVGFont(12, UIFontWeightSemibold), UIColor.whiteColor);
    name.shadowColor = [UIColor.blackColor colorWithAlphaComponent:0.35];
    name.shadowOffset = CGSizeMake(0, 1);
    UILabel *material = LMVGLabel(@"", LMVGFont(9, UIFontWeightRegular), [UIColor.whiteColor colorWithAlphaComponent:0.78]);
    material.tag = 1006;
    material.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [card addSubview:name];
    [card addSubview:material];
    [name.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:22].active = YES;
    [name.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-10].active = YES;
    [name.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-22].active = YES;
    [material.leadingAnchor constraintEqualToAnchor:name.leadingAnchor].active = YES;
    [material.trailingAnchor constraintLessThanOrEqualToAnchor:card.trailingAnchor constant:-10].active = YES;
    [material.topAnchor constraintEqualToAnchor:name.bottomAnchor constant:1].active = YES;

    UIView *dot = [UIView new];
    dot.translatesAutoresizingMaskIntoConstraints = NO;
    dot.tag = 1004;
    dot.layer.cornerRadius = 3;
    dot.hidden = YES;
    [card addSubview:dot];
    [dot.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10].active = YES;
    [dot.centerYAnchor constraintEqualToAnchor:name.centerYAnchor].active = YES;
    [dot.widthAnchor constraintEqualToConstant:6].active = YES;
    [dot.heightAnchor constraintEqualToConstant:6].active = YES;

    LMVGAddPressFeedback(card);
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openChannel:)];
    [card addGestureRecognizer:tap];
    card.userInteractionEnabled = YES;
    card.isAccessibilityElement = YES;
    card.accessibilityLabel = LMVGChannelTitle(identifier);
    return card;
}

- (void)buildFooter {
    UIView *box = [self paddedContainer];
    UILabel *note = LMVGLabel(@"封面为视频首帧；点开任意通道可更换素材、调整声音与文字颜色。",
                              LMVGFont(10, UIFontWeightRegular), UIColor.tertiaryLabelColor);
    note.numberOfLines = 0;
    [box addSubview:note];
    [note.leadingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.leadingAnchor].active = YES;
    [note.trailingAnchor constraintEqualToAnchor:box.layoutMarginsGuide.trailingAnchor].active = YES;
    [note.topAnchor constraintEqualToAnchor:box.topAnchor constant:16].active = YES;
    [note.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-8].active = YES;
    [self.stack addArrangedSubview:box];
}

- (void)buildTabBar {
    UIView *bar = [UIView new];
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    bar.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    bar.layer.cornerRadius = 22;
    bar.layer.cornerCurve = kCACornerCurveContinuous;
    bar.layer.shadowColor = UIColor.blackColor.CGColor;
    bar.layer.shadowOpacity = 0.10;
    bar.layer.shadowRadius = 16;
    bar.layer.shadowOffset = CGSizeMake(0, 8);
    [self.view addSubview:bar];

    UIStackView *row = [UIStackView new];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.distribution = UIStackViewDistributionFillEqually;
    [bar addSubview:row];

    NSArray *items = @[@[@"rectangle.stack", @"场景", @"scrollTop"],
                       @[@"photo.on.rectangle", @"素材", @"openMaterialLibrary"],
                       @[@"gearshape", @"设置", @"showMore"]];
    [items enumerateObjectsUsingBlock:^(NSArray *item, NSUInteger index, BOOL *stop) {
        UIView *tab = [self tabItemSymbol:item[0] title:item[1] action:NSSelectorFromString(item[2])];
        tab.tag = index;
        if (index == 0) {
            for (UIView *subview in tab.subviews) {
                if ([subview isKindOfClass:UIImageView.class]) ((UIImageView *)subview).tintColor = UIColor.systemBlueColor;
                if ([subview isKindOfClass:UILabel.class]) ((UILabel *)subview).textColor = UIColor.systemBlueColor;
            }
        }
        [row addArrangedSubview:tab];
    }];

    [bar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14].active = YES;
    [bar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14].active = YES;
    [bar.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-10].active = YES;
    [bar.heightAnchor constraintEqualToConstant:58].active = YES;
    [row.leadingAnchor constraintEqualToAnchor:bar.leadingAnchor constant:6].active = YES;
    [row.trailingAnchor constraintEqualToAnchor:bar.trailingAnchor constant:-6].active = YES;
    [row.topAnchor constraintEqualToAnchor:bar.topAnchor].active = YES;
    [row.bottomAnchor constraintEqualToAnchor:bar.bottomAnchor].active = YES;
}

- (UIView *)tabItemSymbol:(NSString *)symbol title:(NSString *)title action:(SEL)action {
    UIControl *control = [UIControl new];
    control.translatesAutoresizingMaskIntoConstraints = NO;

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.tintColor = UIColor.secondaryLabelColor;
    icon.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *label = LMVGLabel(title, LMVGFont(9, UIFontWeightMedium), UIColor.secondaryLabelColor);
    label.textAlignment = NSTextAlignmentCenter;

    [control addSubview:icon];
    [control addSubview:label];
    [icon.centerXAnchor constraintEqualToAnchor:control.centerXAnchor].active = YES;
    [icon.topAnchor constraintEqualToAnchor:control.topAnchor constant:11].active = YES;
    [icon.widthAnchor constraintEqualToConstant:20].active = YES;
    [icon.heightAnchor constraintEqualToConstant:20].active = YES;
    [label.leadingAnchor constraintEqualToAnchor:control.leadingAnchor].active = YES;
    [label.trailingAnchor constraintEqualToAnchor:control.trailingAnchor].active = YES;
    [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:2].active = YES;
    [control addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    control.accessibilityLabel = title;
    return control;
}

#pragma mark - Data

- (void)refreshContent {
    NSUInteger enabled = LMVGEnabledCount();
    self.subtitleLabel.text = [NSString stringWithFormat:@"%lu 个通道 · %lu 个已启用 · v%@",
                               (unsigned long)LMVChannelIDs().count, (unsigned long)enabled, LMVGalleryVersion];

    for (UIView *card in self.heroCards) {
        NSString *identifier = card.accessibilityIdentifier;
        if (!identifier.length) continue;
        NSString *relative = LMVGSelectedMaterial(identifier);
        NSString *name = relative.length ? LMVGMaterialName(relative) : @"未选择素材";
        BOOL on = LMVGPrefBool([identifier stringByAppendingString:@"BackgroundEnabled"], NO);
        UILabel *material = (UILabel *)[card viewWithTag:1002];
        material.text = [NSString stringWithFormat:@"%@ · %@", name, on ? @"使用中" : @"未启用"];
        UILabel *badge = (UILabel *)[card viewWithTag:1003];
        badge.text = on ? @"使用中" : @"未启用";
        badge.alpha = on ? 1.0 : 0.75;
        UIImageView *cover = (UIImageView *)[card viewWithTag:1001];
        // A material change returns here with the old pixels still in place; compare
        // the path we last painted (kept on accessibilityValue) before reusing it.
        if (![card.accessibilityValue isEqualToString:relative]) {
            card.accessibilityValue = relative ?: @"";
            cover.image = nil;
        }
        if (!cover.image) {
            __weak UIImageView *weakCover = cover;
            LMVGLoadCover(relative, ^(UIImage *image) {
                if (!image) return;
                if (LMVGReduceMotion()) { weakCover.image = image; return; }
                [UIView transitionWithView:weakCover duration:0.28 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
                    weakCover.image = image;
                } completion:nil];
            });
        }
    }

    for (UIView *card in self.sceneCards) {
        NSString *identifier = card.accessibilityIdentifier;
        BOOL on = LMVGPrefBool([identifier stringByAppendingString:@"BackgroundEnabled"], NO);
        UIView *dot = [card viewWithTag:1004];
        dot.hidden = !on;
        dot.backgroundColor = UIColor.systemGreenColor;
        NSString *relative = LMVGSelectedMaterial(identifier);
        UILabel *material = (UILabel *)[card viewWithTag:1006];
        material.text = relative.length ? LMVGMaterialName(relative) : @"未选择素材";
        material.textColor = relative.length ? [UIColor.whiteColor colorWithAlphaComponent:0.78] : [UIColor.whiteColor colorWithAlphaComponent:0.5];
        UIImageView *cover = (UIImageView *)[card viewWithTag:1001];
        if (![card.accessibilityValue isEqualToString:relative]) {
            card.accessibilityValue = relative ?: @"";
            cover.image = nil;
        }
        if (!cover.image) {
            __weak UIImageView *weakCover = cover;
            LMVGLoadCoverSized(relative, 700.0, ^(UIImage *image) {
                if (!image) return;
                if (LMVGReduceMotion()) { weakCover.image = image; return; }
                [UIView transitionWithView:weakCover duration:0.28 options:UIViewAnimationOptionTransitionCrossDissolve animations:^{
                    weakCover.image = image;
                } completion:nil];
            });
        }
    }

}

#pragma mark - Auto-advance

- (void)startHeroTimer {
    [self stopHeroTimer];
    if (LMVGReduceMotion() || self.featured.count < 2) return;
    self.heroTimer = [NSTimer scheduledTimerWithTimeInterval:4.5 target:self selector:@selector(advanceHero) userInfo:nil repeats:YES];
}

- (void)stopHeroTimer {
    [self.heroTimer invalidate];
    self.heroTimer = nil;
}

- (void)advanceHero {
    if (self.presentedViewController || self.heroScroll.isDragging) return;
    NSInteger next = (self.pageControl.currentPage + 1) % (NSInteger)self.featured.count;
    CGFloat step = [self heroStep];
    if (step <= 0) return;
    [self.heroScroll setContentOffset:CGPointMake(next * step, 0) animated:YES];
    self.pageControl.currentPage = next;
}

#pragma mark - Actions

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)openChannel:(UITapGestureRecognizer *)gesture {
    NSString *identifier = gesture.view.accessibilityIdentifier;
    if (!identifier.length) return;
    LMVGLightHaptic();
    LMVChannelDetailController *detail = [[LMVChannelDetailController alloc] initWithChannelID:identifier];
    [self.navigationController pushViewController:detail animated:YES];
}

- (void)scrollTop {
    [self.scroll setContentOffset:CGPointMake(0, -self.scroll.adjustedContentInset.top) animated:YES];
}
- (void)openMaterialLibrary {
    [self.navigationController pushViewController:[LMVMaterialLibraryController new] animated:YES];
}
- (void)openLibrary {
    UIViewController *picker = LMVCreateMaterialPicker(@"", YES, nil, nil);
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)openClassicList {
    if (self.onRequestClassicList) self.onRequestClassicList();
}
- (void)showMore {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    BOOL easterOn = LMVGPrefBool(@"EasterEggEnabled", NO);
    [sheet addAction:[UIAlertAction actionWithTitle:(easterOn ? @"关闭小彩蛋" : @"启用小彩蛋")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        LMVGPrefSet(@"EasterEggEnabled", @(!easterOn));
        LMVGNotifyChannel(nil);
        LMVGLightHaptic();
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"功能面板参数" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [weakSelf.navigationController pushViewController:[LMVTuneListController new] animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"显示场景与图片旋转" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        if (weakSelf.onRequestDisplaySettings) weakSelf.onRequestDisplaySettings();
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMaxY(self.view.bounds) - 80, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark - Gestures

// Tapping the little edit button must not also start playback.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    UIView *view = touch.view;
    while (view && view != gestureRecognizer.view) {
        if ([view isKindOfClass:UIControl.class]) return NO;
        view = view.superview;
    }
    return YES;
}

#pragma mark - Carousel

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView != self.heroScroll) return;
    CGFloat step = [self heroStep];
    if (step <= 0) return;
    NSInteger page = (NSInteger)lround(scrollView.contentOffset.x / step);
    page = MAX(0, MIN((NSInteger)self.featured.count - 1, page));
    if (self.pageControl.currentPage != page) self.pageControl.currentPage = page;

    if (LMVGReduceMotion()) return;
    CGFloat center = scrollView.contentOffset.x + scrollView.bounds.size.width * 0.5;
    for (UIView *card in self.heroCards) {
        CGPoint point = [card.superview convertPoint:card.center toView:scrollView];
        CGFloat delta = point.x - center;
        UIImageView *cover = (UIImageView *)[card viewWithTag:1001];
        if (cover.image) {
            // Slight counter-move; the 1.08 scale keeps the moving edges covered.
            cover.transform = CGAffineTransformMakeScale(1.08, 1.08);
            cover.transform = CGAffineTransformTranslate(cover.transform, -delta * 0.05 / 1.08, 0);
        }
    }
}

// Card width is view width - 28 (14pt page margins), plus 10pt spacing.
- (CGFloat)heroStep {
    CGFloat width = self.heroScroll.bounds.size.width;
    return width > 20 ? width - 18 : 0;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == self.heroScroll) [self stopHeroTimer];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    if (scrollView == self.heroScroll) [self startHeroTimer];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    if (scrollView != self.heroScroll) return;
    CGFloat step = [self heroStep];
    if (step <= 0) return;
    CGFloat proposed = targetContentOffset->x;
    CGFloat maxX = MAX(0, scrollView.contentSize.width - scrollView.bounds.size.width);
    NSInteger page = (NSInteger)lround(proposed / step);
    page = MAX(0, MIN((NSInteger)self.featured.count - 1, page));
    targetContentOffset->x = MIN(maxX, page * step);
}

@end
