#pragma once
#import <PhotosUI/PhotosUI.h>
#import "LMVEasterMedia.h"
// 0.0.122: shared corner-radius / panel-size rules (also used by the overlay).
#import "LMVEasterPanelAppearance.h"

static NSInteger LMVEasterImageSection(void) { return 0; }
static NSInteger LMVEasterImageDisplaySection(void) { return LMVEasterImageSection() + 1; }
static NSInteger LMVEasterImageRotationSection(void) { return LMVEasterImageDisplaySection() + 1; }
// 0.0.122: floating-panel appearance lives on this same page, so both entries
// (Settings app and the panel's own 显示场景与图片旋转) edit exactly one place.
static NSInteger LMVEasterImagePanelSection(void) { return LMVEasterImageRotationSection() + 1; }
static NSArray<NSString *> *LMVEasterImageDisplayKeys(void) { return @[@"EasterEggShowOnLockScreen", @"EasterEggShowOnControlCenter", @"EasterEggShowOnDesktop"]; }
static NSArray<NSString *> *LMVEasterImageDisplayTitles(void) { return @[@"在锁屏显示小彩蛋", @"在控制中心显示小彩蛋", @"在桌面显示小彩蛋"]; }
static NSArray<NSNumber *> *LMVEasterImageDisplayDefaults(void) { return @[@NO, @YES, @YES]; }
static BOOL LMVEasterImageBool(NSString *key, BOOL fallback) {
    id value = LMVEasterRead(key);
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}
static CGFloat LMVEasterImageRotationSpeed(void) {
    id value = LMVEasterRead(@"EasterEggRotationSpeed");
    double speed = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 45.0;
    return isfinite(speed) ? MAX(5.0, MIN(720.0, speed)) : 45.0;
}
@interface LMVEasterImageSettings : UITableViewController <PHPickerViewControllerDelegate>
@property(nonatomic) BOOL busy, settingsTracking, previewVisible, previewCellVisible, previewLoading;
@property(atomic) NSUInteger importGeneration;
@property(nonatomic) NSUInteger previewGeneration, previewFrame;
@property(nonatomic, copy) NSString *previewSelection;
@property(nonatomic, strong) LMVEasterImage *previewDecoded;
@property(nonatomic, strong) UIImageView *previewView;
// 0.0.117: width/height of the preview, driven by the size slider.
@property(nonatomic, strong) NSArray<NSLayoutConstraint *> *previewSizeConstraints;
@property(nonatomic, strong) UILabel *previewLabel;
@property(nonatomic, strong) NSTimer *previewTimer;
@property(nonatomic, weak) PHPickerViewController *imagePicker;
@property(nonatomic, copy) void (^close)(void);
- (void)refreshPreview;
- (void)stopPreview;
- (void)animatePreview;
@end
static void LMVEasterImageSettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    __weak LMVEasterImageSettings *page = (__bridge LMVEasterImageSettings *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(LMVEasterPrefs);
        if (page.isViewLoaded && !page.settingsTracking) { [page refreshPreview]; [page.tableView reloadData]; }
    });
}
@implementation LMVEasterImageSettings

// 0.0.117: while the panel is open this window becomes KEY, so UIKit asks ITS
// root view controller for the supported orientations. A plain UIViewController
// answers portrait-only, which locks the whole scene (SpringBoard included) and
// left the floating ball where it was when the phone turned landscape with the
// rotation lock off. All-but-upside-down matches the other floating system
// surfaces; layout follows the root view bounds, so the ball moves with it.
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, LMVEasterImageSettingsChanged, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    return self;
}
- (void)dealloc { [_previewTimer invalidate]; CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self); }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; CFPreferencesAppSynchronize(LMVEasterPrefs); [self refreshPreview]; [self.tableView reloadData];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; self.previewVisible = YES; [self refreshPreview]; [self animatePreview];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated]; self.previewVisible = NO; [self stopPreview];
    // Presenting Photos pauses the preview, but does not invalidate that flow.
    if (self.isBeingDismissed || self.isMovingFromParentViewController || self.navigationController.isBeingDismissed) self.importGeneration++;
}
- (void)stopPreview { [self.previewTimer invalidate]; self.previewTimer = nil; }
- (void)animatePreview {
    [self stopPreview];
    if (!self.previewVisible || !self.previewCellVisible || self.presentedViewController || !self.view.window || self.previewDecoded.frames.count < 2) return;
    __weak typeof(self) weakSelf = self;
    NSTimeInterval delay = self.previewDecoded.delays[self.previewFrame].doubleValue;
    self.previewTimer = [NSTimer timerWithTimeInterval:delay repeats:NO block:^(NSTimer *timer) {
        LMVEasterImageSettings *page = weakSelf; if (!page || !page.previewVisible || !page.previewCellVisible) return;
        page.previewFrame = (page.previewFrame + 1) % page.previewDecoded.frames.count;
        page.previewView.image = page.previewDecoded.frames[page.previewFrame]; [page animatePreview];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.previewTimer forMode:NSRunLoopCommonModes];
}
- (void)refreshPreview {
    id value = LMVEasterRead(@"EasterEggImage");
    NSString *selection = [value isKindOfClass:NSString.class] ? value : @"";
    if ([selection isEqualToString:self.previewSelection]) { [self animatePreview]; return; }
    [self stopPreview]; self.previewSelection = selection; self.previewDecoded = nil; self.previewFrame = 0;
    self.previewView.image = nil; self.previewLabel.text = selection.length ? @"正在载入当前素材…" : @"尚未选择图片 / GIF";
    NSUInteger generation = ++self.previewGeneration; self.previewLoading = selection.length > 0;
    if (!selection.length) return;
    __weak typeof(self) weakSelf = self;
    dispatch_async(LMVMaterialQueue(), ^{
        NSString *path = LMVEasterImagePath(selection);
        LMVEasterImage *decoded = path ? LMVEasterDecode([NSURL fileURLWithPath:path], NULL) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            LMVEasterImageSettings *page = weakSelf;
            if (!page || generation != page.previewGeneration || ![page.previewSelection isEqualToString:selection]) return;
            page.previewLoading = NO; page.previewDecoded = decoded;
            page.previewView.image = decoded.frames.firstObject;
            page.previewLabel.text = decoded ? @"当前小彩蛋素材" : @"当前素材不可用";
            [page animatePreview];
        });
    });
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"小彩蛋图片";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finish)];
}
- (void)finish {
    self.importGeneration++; self.previewVisible = NO; [self stopPreview];
    if (self.close) self.close();
    else if (self.navigationController.viewControllers.count > 1) [self.navigationController popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return LMVEasterImagePanelSection() + 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == LMVEasterImageSection()) return 3;
    // Corner toggle + corner slider + size toggle + width + height.
    if (section == LMVEasterImagePanelSection()) return 5;
    return section == LMVEasterImageDisplaySection() ? LMVEasterImageDisplayKeys().count : 2;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == LMVEasterImageDisplaySection()) return @"小彩蛋显示场景";
    if (section == LMVEasterImagePanelSection()) return @"悬浮窗外观";
    return section == LMVEasterImageRotationSection() ? @"彩蛋图片旋转" : @"图片 / GIF 与图标大小";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == LMVEasterImageDisplaySection()) return @"默认不在锁屏显示；控制中心和桌面默认显示。通知中心沿用现有显示行为。";
    return section == LMVEasterImagePanelSection() ? @"拖动悬浮窗顶部标题栏即可移动窗口；窗口始终被限制在屏幕内。关闭「自定义悬浮窗大小」时按屏幕自动计算。" : nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)index {
    if (index.section == LMVEasterImageSection()) return index.row == 0 ? 184 : (index.row == 2 ? 80 : 44);
    if (index.section == LMVEasterImagePanelSection()) return (index.row % 2) ? 80 : 44;
    return index.section == LMVEasterImageRotationSection() && index.row == 1 ? 80 : 44;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (index.section == LMVEasterImageDisplaySection()) {
        NSString *key = LMVEasterImageDisplayKeys()[index.row];
        cell.textLabel.text = LMVEasterImageDisplayTitles()[index.row]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *toggle = [UISwitch new]; toggle.tag = index.row;
        toggle.on = LMVEasterImageBool(key, LMVEasterImageDisplayDefaults()[index.row].boolValue);
        toggle.accessibilityLabel = cell.textLabel.text;
        [toggle addTarget:self action:@selector(displayChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        return cell;
    }
    if (index.section == LMVEasterImagePanelSection()) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        BOOL cornerOn = LMVEasterPanelToggle(LMVEasterRead(@"EasterPanelCornerEnabled"), YES);
        BOOL sizeOn = LMVEasterPanelToggle(LMVEasterRead(@"EasterPanelSizeEnabled"), NO);
        if (index.row == 0) {
            cell.textLabel.text = @"悬浮窗圆角";
            UISwitch *toggle = [UISwitch new]; toggle.on = cornerOn;
            toggle.accessibilityLabel = cell.textLabel.text;
            [toggle addTarget:self action:@selector(panelCornerToggled:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else if (index.row == 2) {
            cell.textLabel.text = @"自定义悬浮窗大小";
            UISwitch *toggle = [UISwitch new]; toggle.on = sizeOn;
            toggle.accessibilityLabel = cell.textLabel.text;
            [toggle addTarget:self action:@selector(panelSizeToggled:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else {
            // 1.84.1: row 1 is the CORNER slider. It used to set the height label,
            // percentage and accessibility text before the branch checked which
            // row it was, so the row under "悬浮窗圆角" read "悬浮窗高度 71%".
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 32)];
            slider.tag = index.row;
            if (index.row == 1) {
                CGFloat corner = LMVEasterPanelCornerValue(LMVEasterRead(@"EasterPanelCorner"));
                cell.textLabel.text = @"窗口圆角";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", corner];
                slider.minimumValue = LMVEasterPanelCornerMin; slider.maximumValue = LMVEasterPanelCornerMax;
                slider.value = corner;
                slider.enabled = cornerOn; slider.accessibilityLabel = @"窗口圆角";
                [slider addTarget:self action:@selector(panelCornerChanged:) forControlEvents:UIControlEventValueChanged | UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            } else {
                BOOL width = index.row == 3;
                NSString *key = width ? @"EasterPanelWidthScale" : @"EasterPanelHeightScale";
                CGFloat scale = LMVEasterPanelScaleValue(LMVEasterRead(key));
                cell.textLabel.text = width ? @"悬浮窗宽度" : @"悬浮窗高度";
                cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", scale * 100.0];
                slider.minimumValue = LMVEasterPanelScaleMin; slider.maximumValue = LMVEasterPanelScaleMax;
                slider.value = scale;
                slider.enabled = sizeOn; slider.accessibilityLabel = width ? @"悬浮窗宽度" : @"悬浮窗高度";
                [slider addTarget:self action:@selector(panelScaleChanged:) forControlEvents:UIControlEventValueChanged | UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            }
            cell.accessoryView = slider;
        }
        return cell;
    }
    if (index.section == LMVEasterImageRotationSection()) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (index.row == 0) {
            cell.textLabel.text = @"启用彩蛋图片旋转";
            UISwitch *toggle = [UISwitch new]; toggle.on = LMVEasterImageBool(@"EasterEggRotationEnabled", NO);
            toggle.accessibilityLabel = cell.textLabel.text;
            [toggle addTarget:self action:@selector(rotationChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else {
            cell.textLabel.text = @"旋转速度"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f 度/秒", LMVEasterImageRotationSpeed()];
            UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 32)];
            slider.minimumValue = 5; slider.maximumValue = 720; slider.value = LMVEasterImageRotationSpeed();
            slider.enabled = LMVEasterImageBool(@"EasterEggRotationEnabled", NO); slider.accessibilityLabel = @"彩蛋图片旋转速度（度/秒）";
            [slider addTarget:self action:@selector(rotationSpeedChanged:) forControlEvents:UIControlEventValueChanged | UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel]; cell.accessoryView = slider;
        }
        return cell;
    }
    if (index.row == 0) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UIImageView *preview = [[UIImageView alloc] initWithFrame:CGRectZero];
        preview.contentMode = UIViewContentModeScaleAspectFit; preview.translatesAutoresizingMaskIntoConstraints = NO;
        preview.isAccessibilityElement = YES; preview.accessibilityLabel = @"当前小彩蛋图片或 GIF 预览";
        UILabel *label = [UILabel new]; label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; label.textColor = UIColor.secondaryLabelColor;
        label.textAlignment = NSTextAlignmentCenter; label.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:preview]; [cell.contentView addSubview:label];
        // 0.0.117: the preview is drawn at the ACTUAL bubble size and these two
        // constraints are updated live by the size slider, so dragging it shows
        // the real change instead of a fixed 140pt sample.
        NSLayoutConstraint *previewWidth=[preview.widthAnchor constraintEqualToConstant:LMVEasterSize()];
        NSLayoutConstraint *previewHeight=[preview.heightAnchor constraintEqualToConstant:LMVEasterSize()];
        [NSLayoutConstraint activateConstraints:@[
            [preview.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [preview.centerXAnchor constraintEqualToAnchor:cell.contentView.centerXAnchor],
            previewWidth, previewHeight,
            [label.topAnchor constraintEqualToAnchor:preview.bottomAnchor constant:6],
            [label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],
            [label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12]
        ]];
        self.previewView = preview; self.previewLabel = label; self.previewSizeConstraints = @[previewWidth, previewHeight];
        preview.image = self.previewFrame < self.previewDecoded.frames.count ? self.previewDecoded.frames[self.previewFrame] : nil;
        label.text = self.previewLoading ? @"正在载入当前素材…" : (self.previewDecoded ? @"当前小彩蛋素材" : (self.previewSelection.length ? @"当前素材不可用" : @"尚未选择图片 / GIF"));
        return cell;
    }
    if (index.row == 1) {
        cell.textLabel.text = self.busy ? @"正在保存…" : @"从相册导入图片 / GIF"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.userInteractionEnabled = !self.busy;
    } else {
        cell.textLabel.text = @"悬浮图标大小"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", LMVEasterSize()]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 32)];
        slider.minimumValue = 12; slider.maximumValue = 128; slider.value = LMVEasterSize(); slider.accessibilityLabel = @"悬浮图标大小";
        [slider addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged | UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel]; cell.accessoryView = slider;
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)index {
    if (index.section == LMVEasterImageSection() && index.row == 0) { self.previewCellVisible = YES; [self animatePreview]; }
}
- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)index {
    if (index.section == LMVEasterImageSection() && index.row == 0 && self.previewView.superview == cell.contentView) { self.previewCellVisible = NO; [self stopPreview]; }
}
- (void)displayChanged:(UISwitch *)toggle {
    if (toggle.tag < 0 || toggle.tag >= LMVEasterImageDisplayKeys().count) return;
    LMVEasterSet(LMVEasterImageDisplayKeys()[toggle.tag], @(toggle.on));
}
- (void)rotationChanged:(UISwitch *)toggle {
    LMVEasterSet(@"EasterEggRotationEnabled", @(toggle.on)); [self.tableView reloadData];
}
- (void)rotationSpeedChanged:(UISlider *)slider {
    self.settingsTracking = slider.isTracking;
    double raw = slider.value;
    CGFloat speed = isfinite(raw) ? MAX(5.0, MIN(720.0, round(raw))) : 45.0;
    LMVEasterSet(@"EasterEggRotationSpeed", @(speed));
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:LMVEasterImageRotationSection()]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f 度/秒", speed];
    if (!slider.isTracking) [self.tableView reloadData];
}
- (void)sizeChanged:(UISlider *)slider {
    self.settingsTracking = slider.isTracking;
    CGFloat size = MAX(12, MIN(128, round(slider.value))); LMVEasterSet(@"EasterEggSize", @(size));
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:LMVEasterImageSection()]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", size];
    // 0.0.117: resize the live preview with the slider, without rebuilding the cell
    // (a reload mid-drag would drop the slider's tracking state).
    for (NSLayoutConstraint *constraint in self.previewSizeConstraints) constraint.constant = size;
    if (!self.settingsTracking) [self.tableView reloadData];
}
// 0.0.122: floating-panel appearance. Values are clamped by the shared rules, and
// every change notifies SpringBoard, which re-lays the open panel immediately.
- (void)panelCornerToggled:(UISwitch *)toggle {
    LMVEasterSet(@"EasterPanelCornerEnabled", @(toggle.on)); [self.tableView reloadData];
}
- (void)panelSizeToggled:(UISwitch *)toggle {
    LMVEasterSet(@"EasterPanelSizeEnabled", @(toggle.on)); [self.tableView reloadData];
}
- (void)panelCornerChanged:(UISlider *)slider {
    self.settingsTracking = slider.isTracking;
    CGFloat corner = LMVEasterPanelCornerValue(@(slider.value)); LMVEasterSet(@"EasterPanelCorner", @(corner));
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:LMVEasterImagePanelSection()]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", corner];
    if (!slider.isTracking) [self.tableView reloadData];
}
- (void)panelScaleChanged:(UISlider *)slider {
    self.settingsTracking = slider.isTracking;
    BOOL width = slider.tag == 3;
    CGFloat scale = LMVEasterPanelScaleValue(@(slider.value));
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:slider.tag inSection:LMVEasterImagePanelSection()]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f%%", scale * 100.0];
    // 1.84: dragging must only move the number. Writing the preference on every
    // value change resized the floating panel mid-drag, which is what made the
    // slider feel like it was fighting the window. Commit on release only.
    if (slider.isTracking) return;
    LMVEasterSet(width ? @"EasterPanelWidthScale" : @"EasterPanelHeightScale", @(scale));
    [self.tableView reloadData];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES]; if (index.section != LMVEasterImageSection() || index.row != 1 || self.busy || self.presentedViewController) return;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary]; config.filter = PHPickerFilter.imagesFilter; config.selectionLimit = 1; config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self;
    self.imagePicker = picker; self.importGeneration++; [self stopPreview];
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    if (picker != self.imagePicker) return;
    PHPickerResult *picked = results.firstObject; NSUInteger generation = self.importGeneration;
    self.imagePicker = nil;
    [picker dismissViewControllerAnimated:YES completion:^{
        [self animatePreview];
        if (!picked || self.busy || generation != self.importGeneration) return;
        NSString *type = [picked.itemProvider hasItemConformingToTypeIdentifier:@"com.compuserve.gif"] ? @"com.compuserve.gif" : @"public.image";
        if (![picked.itemProvider hasItemConformingToTypeIdentifier:type]) return;
        self.busy = YES; [self.tableView reloadData]; __weak typeof(self) weakSelf = self;
        id expectedOld = LMVEasterRead(@"EasterEggImage");
        [picked.itemProvider loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url, NSError *providerError) {
            BOOL (^current)(void) = ^BOOL { LMVEasterImageSettings *page = weakSelf; return page && page.importGeneration == generation; };
            if (!current()) return;
            NSError *error = providerError;
            if (!url && !error) error = LMVStorageError(71, @"相册未返回图片");
            NSString *relative = url && !error ? LMVEasterReplaceImage(url, expectedOld, current, &error) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                LMVEasterImageSettings *page = weakSelf; if (!page || generation != page.importGeneration) return; page.busy = NO;
                if (relative) [page refreshPreview];
                [page.tableView reloadData];
                if (error && page.view.window && !page.presentedViewController) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [page presentViewController:alert animated:YES completion:nil];
                }
            });
        }];
    }];
}
@end
