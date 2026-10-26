#import "LMVGalleryController.h"
#import "LMVGalleryKit.h"
#import "LMVMaterialPickerAPI.h"
#import "LMVImport.h"
#import "LMVMaterialDeletion.h"

// 4.3.1 (C1): the two pages the gallery's bottom bar points at. Both are ordinary
// pushes on the Settings navigation stack, hide the bar like the gallery and keep
// every write on the same per-channel keys.

#pragma mark - Material library

@interface LMVMaterialLibraryController () <PHPickerViewControllerDelegate>
@property(nonatomic,strong) UIScrollView *scroll;
@property(nonatomic,strong) UIStackView *stack;
@property(nonatomic,strong) UIStackView *grid;
@property(nonatomic,strong) UILabel *subtitle;
@property(nonatomic,strong) NSArray<NSDictionary *> *materials;
@property(nonatomic) BOOL importing;
@property(nonatomic) BOOL editingMaterials;
@property(nonatomic,strong) UIButton *manageButton;
// 4.3.7: rename updates the visible label in place; a full rebuild flashed.
@property(nonatomic,strong) NSMutableDictionary<NSString *, UILabel *> *nameLabels;
// 4.3.8: reuse card views across reloads so covers are not re-decoded and the
// grid does not flash when entering/leaving edit mode or after an import.
@property(nonatomic,strong) NSMutableDictionary<NSString *, UIView *> *cardsByPath;
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
    self.nameLabels = [NSMutableDictionary new];
    self.cardsByPath = [NSMutableDictionary new];
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
    self.manageButton = [self button:@"管理素材" symbol:@"slider.horizontal.3" filled:NO action:@selector(manageMaterials)];
    [actions addArrangedSubview:self.manageButton];
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
        button.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.12];
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
    NSMutableArray<NSString *> *paths = [NSMutableArray new];
    for (NSDictionary *row in self.materials) [paths addObject:row[@"path"]];
    self.subtitle.text = [NSString stringWithFormat:@"%lu 个素材 · 原片保存", (unsigned long)self.materials.count];

    // Drop cards whose material disappeared.
    for (NSString *path in self.cardsByPath.allKeys) {
        if ([paths containsObject:path]) continue;
        UIView *card = self.cardsByPath[path];
        [card removeFromSuperview];
        [self.cardsByPath removeObjectForKey:path];
        [self.nameLabels removeObjectForKey:path];
    }
    // Detach old rows but keep the card views alive in the registry.
    for (UIView *row in [self.grid.arrangedSubviews copy]) {
        [self.grid removeArrangedSubview:row];
        [row removeFromSuperview];
    }

    if (!self.materials.count) {
        [self.grid addArrangedSubview:[self emptyStateView]];
        return;
    }

    UIStackView *row = nil;
    for (NSUInteger index = 0; index < self.materials.count; index++) {
        NSDictionary *material = self.materials[index];
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
        UIView *card = self.cardsByPath[material[@"path"]];
        if (!card) {
            card = [self cardForMaterial:material];
            self.cardsByPath[material[@"path"]] = card;
        } else {
            UILabel *name = self.nameLabels[material[@"path"]];
            name.text = material[@"name"];
            [card viewWithTag:1003].hidden = !self.editingMaterials;
            [card viewWithTag:1004].hidden = !self.editingMaterials;
        }
        [row addArrangedSubview:card];
    }
}

- (UIView *)emptyStateView {
    UIView *empty = [UIView new];
    empty.translatesAutoresizingMaskIntoConstraints = NO;
    empty.layer.cornerRadius = 20;
    empty.layer.cornerCurve = kCACornerCurveContinuous;
    empty.layer.borderWidth = 1.4;
    empty.layer.borderColor = [UIColor.separatorColor colorWithAlphaComponent:0.7].CGColor;
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
    return empty;
}

- (UIView *)cardForMaterial:(NSDictionary *)material {
    UIView *card = [UIView new];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    card.layer.cornerRadius = 16;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    card.clipsToBounds = YES;
    card.accessibilityIdentifier = material[@"path"];
    [card.heightAnchor constraintEqualToConstant:132].active = YES;

    UIImageView *cover = [UIImageView new];
    cover.translatesAutoresizingMaskIntoConstraints = NO;
    cover.contentMode = UIViewContentModeScaleAspectFill;
    cover.clipsToBounds = YES;
    cover.backgroundColor = UIColor.tertiarySystemFillColor;
    cover.tag = 1001;
    [card addSubview:cover];

    // 5.0.0: resolution chip inside the cover's bottom-right; the edit buttons
    // (trash/pencil) live top-right and never collide with it.
    UILabel *resolution = LMVGMakeResolutionBadge();
    [card addSubview:resolution];

    UILabel *name = LMVGLabel(material[@"name"], LMVGFont(11, UIFontWeightMedium), UIColor.labelColor);
    name.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [card addSubview:name];

    UILabel *badge = LMVGLabel(@"", LMVGFont(9, UIFontWeightSemibold), UIColor.systemBlueColor);
    badge.tag = 1002;
    badge.hidden = YES;
    [card addSubview:badge];

    // 4.3.8: small translucent chips instead of big white discs.
    UIButton *rename = [UIButton buttonWithType:UIButtonTypeSystem];
    rename.translatesAutoresizingMaskIntoConstraints = NO;
    [rename setImage:[UIImage systemImageNamed:@"pencil"] forState:UIControlStateNormal];
    rename.tintColor = UIColor.whiteColor;
    rename.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.38];
    rename.layer.cornerRadius = 8;
    rename.tag = 1004;
    rename.hidden = !self.editingMaterials;
    [rename addTarget:self action:@selector(renameMaterialTapped:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:rename];

    UIButton *remove = [UIButton buttonWithType:UIButtonTypeSystem];
    remove.translatesAutoresizingMaskIntoConstraints = NO;
    [remove setImage:[UIImage systemImageNamed:@"trash"] forState:UIControlStateNormal];
    remove.tintColor = [UIColor colorWithRed:1.0 green:0.45 blue:0.45 alpha:1.0];
    remove.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.38];
    remove.layer.cornerRadius = 8;
    remove.tag = 1003;
    remove.hidden = !self.editingMaterials;
    [remove addTarget:self action:@selector(deleteMaterialTapped:) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:remove];

    [remove.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-7].active = YES;
    [remove.topAnchor constraintEqualToAnchor:card.topAnchor constant:7].active = YES;
    [remove.widthAnchor constraintEqualToConstant:24].active = YES;
    [remove.heightAnchor constraintEqualToConstant:24].active = YES;
    [rename.trailingAnchor constraintEqualToAnchor:remove.leadingAnchor constant:-5].active = YES;
    [rename.topAnchor constraintEqualToAnchor:remove.topAnchor].active = YES;
    [rename.widthAnchor constraintEqualToConstant:24].active = YES;
    [rename.heightAnchor constraintEqualToConstant:24].active = YES;
    self.nameLabels[material[@"path"]] = name;

    [cover.leadingAnchor constraintEqualToAnchor:card.leadingAnchor].active = YES;
    [cover.trailingAnchor constraintEqualToAnchor:card.trailingAnchor].active = YES;
    [cover.topAnchor constraintEqualToAnchor:card.topAnchor].active = YES;
    [cover.heightAnchor constraintEqualToConstant:98].active = YES;
    [name.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:9].active = YES;
    [name.trailingAnchor constraintLessThanOrEqualToAnchor:badge.leadingAnchor constant:-4].active = YES;
    [name.topAnchor constraintEqualToAnchor:cover.bottomAnchor constant:6].active = YES;
    [badge.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-9].active = YES;
    [badge.centerYAnchor constraintEqualToAnchor:name.centerYAnchor].active = YES;
    [resolution.trailingAnchor constraintEqualToAnchor:cover.trailingAnchor constant:-6].active = YES;
    [resolution.bottomAnchor constraintEqualToAnchor:cover.bottomAnchor constant:-6].active = YES;

    BOOL used = NO;
    for (NSString *identifier in LMVChannelIDs())
        if ([LMVGSelectedMaterial(identifier) isEqualToString:material[@"path"]]) { used = YES; break; }
    if (used && !self.editingMaterials) {
        badge.text = @"使用中";
        badge.hidden = NO;
    }

    LMVGApplyResolution(resolution, material[@"path"]);
    __weak UIImageView *weakCover = cover;
    // 5.0.0: 800 left a portrait clip ~450px wide on a 3x tile (~510px drawn).
    LMVGLoadCoverSized(material[@"path"], 1000.0, ^(UIImage *image) {
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

// 4.3.5: in-place management. The button used to open the picker again; now it
// turns every card into an editable tile (trash + pencil), no second screen.
- (void)manageMaterials {
    self.editingMaterials = !self.editingMaterials;
    [self.manageButton setTitle:(self.editingMaterials ? @"完成" : @"管理素材") forState:UIControlStateNormal];
    // 4.3.8: toggle in place; rebuilding here flashed every cover.
    for (UIView *card in self.cardsByPath.allValues) {
        [card viewWithTag:1003].hidden = !self.editingMaterials;
        [card viewWithTag:1004].hidden = !self.editingMaterials;
        UILabel *badge = (UILabel *)[card viewWithTag:1002];
        badge.hidden = self.editingMaterials || !badge.text.length;
    }
}
- (void)deleteMaterialTapped:(UIButton *)sender {
    UIView *card = sender.superview;
    NSString *relative = card.accessibilityIdentifier;
    if (!relative.length) return;
    NSString *name = LMVGMaterialName(relative);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除素材？"
                                                                   message:[NSString stringWithFormat:@"“%@”将被永久删除，使用它的通道会取消选择。", name]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        dispatch_async(LMVMaterialQueue(), ^{
            BOOL deleted = NO;
            LMVDeleteMaterial(relative, &deleted);
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reload]; });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)renameMaterialTapped:(UIButton *)sender {
    UIView *card = sender.superview;
    NSString *relative = card.accessibilityIdentifier;
    if (!relative.length) return;
    NSString *current = LMVGMaterialName(relative);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名素材"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = current; }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *name = alert.textFields.firstObject.text ?: @"";
        if (!name.length) return;
        dispatch_async(LMVMaterialQueue(), ^{
            LMVRenameMaterial(relative, name);
            dispatch_async(dispatch_get_main_queue(), ^{
                // In-place: updating the label avoids the rebuild flash.
                weakSelf.nameLabels[relative].text = name;
                NSMutableArray *updated = [weakSelf.materials mutableCopy];
                for (NSUInteger i = 0; i < updated.count; i++) {
                    if (![updated[i][@"path"] isEqualToString:relative]) continue;
                    NSMutableDictionary *row = [updated[i] mutableCopy];
                    row[@"name"] = name;
                    updated[i] = row;
                    break;
                }
                weakSelf.materials = updated;
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
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
    __block NSUInteger imported = 0;
    for (PHPickerResult *result in videos) {
        dispatch_group_enter(group);
        [result.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
            NSString *relative = nil;
            if (url && !error) relative = LMVImportMovie(url, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (relative.length) imported++;
                dispatch_group_leave(group);
            });
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        weakSelf.importing = NO;
        [weakSelf reload];
        if (imported == 0) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入失败"
                                                                           message:@"视频没能保存，请重试。"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
        }
    });
}

@end

