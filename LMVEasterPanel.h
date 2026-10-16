#pragma once
#import <PhotosUI/PhotosUI.h>
#import "LMVEasterMedia.h"
#import "LMVEasterPhotoFlow.h"
#import "LMVEasterImageSettings.h"
#import "LockMessageVideoPrefs/LMVMaterialPicker.h"

// Image import and display controls stay on their own settings page.
@interface LMVEasterPanel : UITableViewController <PHPickerViewControllerDelegate>
@property(nonatomic) BOOL busy, opacityTracking, volumeTracking, panelVisible;
@property(nonatomic) NSUInteger catalogGeneration;
@property(nonatomic, copy) NSDictionary *names;
@property(nonatomic, strong) LMVEasterPhotoFlow *photoFlow;
@property(nonatomic, strong) LMVMaterialPrompt *prompt;
@property(nonatomic, copy) void (^close)(void);
- (void)loadNames;
- (void)showPendingImportPrompt;
- (void)prepareForClose;
@end
// Import callbacks may finish after the overlay has closed its panel.
static NSMutableArray<LMVMaterialPrompt *> *LMVEasterPendingImportPrompts;
static NSString * const LMVEasterImportResultReady = @"LMVEasterImportResultReady";
static NSArray *LMVEasterTargets(void) { return @[@"Message", @"Options", @"Clear", @"LockScreen", @"Desktop"]; }
static NSArray *LMVEasterTitles(void) { return @[@"消息背景", @"选项背景", @"清除背景", @"锁屏背景", @"桌面背景"]; }
// Keep the five original targets first; HomeMenu/display follow both CC modes.
static NSInteger LMVEasterControlCenterSection(void) { return LMVEasterTargets().count; }
static NSInteger LMVEasterHomeMenuSection(void) { return LMVEasterControlCenterSection() + 1; }
// 1.22: the SquidGesturePro panel channel sits directly below the long-press menu.
static NSInteger LMVEasterSquidPanelSection(void) { return LMVEasterHomeMenuSection() + 1; }
// 1.26: the AppTools (AT) pop-up channel sits directly below the Squid panel one,
// the same way it does in Settings. This release only stores the settings.
static NSInteger LMVEasterATSection(void) { return LMVEasterSquidPanelSection() + 1; }
// 1.43: the CopyVault clipboard panel sits directly below the AT channel, the
// same way the AT channel sits below the Squid panel one.
static NSInteger LMVEasterCVSection(void) { return LMVEasterATSection() + 1; }
static NSInteger LMVEasterDisplaySection(void) { return LMVEasterCVSection() + 1; }
static NSInteger LMVEasterOpacitySection(void) { return LMVEasterDisplaySection() + 1; }
static NSInteger LMVEasterImportSection(void) { return LMVEasterOpacitySection() + 1; }
static NSString *LMVEasterControlCenterKey(NSInteger row) {
    return row == 1 ? @"ControlCenterDarkVideo" : (row == 4 ? @"ControlCenterLightVideo" : nil);
}
// Audio tags are target indices, never section indices (CC has two targets).
static NSArray *LMVEasterAudioTargets(void) {
    return @[@"Message", @"Options", @"Clear", @"LockScreen", @"Desktop", @"ControlCenterDark", @"ControlCenterLight", @"HomeMenu", @"SquidPanel", @"AT", @"CV"];
}
// 1.50: the four SquidGesturePro materials, in row order: the right-hand gestures
// ("swipe up" / "swipe up twice") and then the left-hand ones. Sound and volume are
// shared between all four - only one panel can be on screen at a time.
static NSArray *LMVEasterSquidKeys(void) {
    return @[@"SquidPanelVideo", @"SquidPanel2Video", @"SquidPanel3Video", @"SquidPanel4Video"];
}
// 1.54: the four rows are named the way the user names the gestures: 右一 = 右上滑,
// 右二 = 右上上滑, 左一 = 左上滑, 左二 = 左上上滑.
static NSArray *LMVEasterSquidTitles(void) {
    return @[@"切换右一素材（右上滑）", @"切换右二素材（右上上滑）", @"切换左一素材（左上滑）", @"切换左二素材（左上上滑）"];
}
// The gesture names the "认领" sheet offers.
static NSString *LMVEasterAudioTarget(NSInteger section, NSInteger row) {
    if (section >= 0 && section < LMVEasterTargets().count && (row == 2 || row == 3)) return LMVEasterTargets()[section];
    if (section == LMVEasterHomeMenuSection() && (row == 2 || row == 3)) return @"HomeMenu";
    if (section == LMVEasterSquidPanelSection() && (row == 7 || row == 8)) return @"SquidPanel";
    if (section == LMVEasterATSection() && (row == 2 || row == 3)) return @"AT";
    if (section == LMVEasterCVSection() && (row == 2 || row == 3)) return @"CV";
    if (section == LMVEasterControlCenterSection()) {
        if (row == 2 || row == 3) return @"ControlCenterDark";
        if (row == 5 || row == 6) return @"ControlCenterLight";
    }
    return nil;
}
static BOOL LMVEasterAudioVolumeRow(NSInteger section, NSInteger row) {
    if (!LMVEasterAudioTarget(section, row)) return NO;
    // 1.50: the squid section grew to nine rows (four materials + claim + swap +
    // sound + volume), so its volume row moved to 8 - reporting it as anything else
    // printed a SECOND "播放声音" switch where the slider belongs.
    if (section == LMVEasterSquidPanelSection()) return row == 8;
    return (row == 3 || row == 6);
}
static NSString *LMVEasterAudioTargetForTag(NSInteger tag) {
    return tag >= 0 && tag < LMVEasterAudioTargets().count ? LMVEasterAudioTargets()[tag] : nil;
}
static double LMVEasterAudioVolume(id value) {
    double raw = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0.5;
    return isfinite(raw) ? MAX(0.0, MIN(1.0, raw)) : 0.5;
}
static BOOL LMVEasterAudioEnabled(NSString *target) {
    id value = LMVEasterRead([target stringByAppendingString:@"SoundEnabled"]);
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : NO;
}
static void LMVEasterPanelChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    __weak LMVEasterPanel *panel = (__bridge LMVEasterPanel *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(LMVEasterPrefs);
        if (panel.isViewLoaded && !panel.opacityTracking && !panel.volumeTracking) { [panel.tableView reloadData]; [panel loadNames]; }
    });
}
@implementation LMVEasterPanel

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
    if (self) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, LMVEasterPanelChanged, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(importResultReady:) name:LMVEasterImportResultReady object:nil];
    }
    return self;
}
- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self);
}
- (void)importResultReady:(NSNotification *)notification {
    [self.tableView reloadData]; [self loadNames]; [self showPendingImportPrompt];
}
- (void)prepareForClose {
    self.panelVisible=NO;
    if (!self.prompt) return;
    LMVMaterialPrompt *prompt=self.prompt; self.prompt=nil; prompt.complete=nil;
    [prompt.view endEditing:YES]; [prompt willMoveToParentViewController:nil];
    [prompt.view removeFromSuperview]; [prompt removeFromParentViewController];
    if (!LMVEasterPendingImportPrompts) LMVEasterPendingImportPrompts=[NSMutableArray new];
    [LMVEasterPendingImportPrompts insertObject:prompt atIndex:0];
}
// 1.41/1.42: the floating panel's scroll inset, pinned to the navigation bar.
//
// The panel is a `UITableViewController`, so its table is a plain scroll view whose
// safe area tracks wherever the panel happens to sit. With the default
// `.automatic`, dragging the panel up until it reached the window's top safe area
// made the table add the whole status-bar height ON TOP of the navigation bar - the
// rows dropped ~one bar lower ("面板移到最上面时消息背景文字跑到下面", measured on
// the device: 123 pt from the card top to the first row at the top vs 70 pt below).
// `.never` plus a CONSTANT bar-height inset removes that dependency entirely.
//
// `seekTop` also pins the resting scroll position. A `.never` scroll view does not
// seek to -contentInset on its own, so the content would start one bar height too
// high and the first section header would sit UNDER the bar (the follow-up report:
// "消息背景 太高"). It runs from viewDidLoad because the panel's view is added with
// a zero frame and its layout is not guaranteed to run before the user sees it -
// an inset applied only from viewDidLayoutSubviews could be missing altogether.
- (CGFloat)barInset {
    CGFloat bar = self.navigationController.navigationBar.frame.size.height;
    return bar > 0 ? bar : 44;
}
- (void)pinBarInset:(BOOL)seekTop {
    CGFloat bar = [self barInset];
    UIEdgeInsets inset = self.tableView.contentInset;
    if (fabs(inset.top - bar) > .5) { inset.top = bar; self.tableView.contentInset = inset; }
    if (seekTop) self.tableView.contentOffset = CGPointMake(self.tableView.contentOffset.x, -bar);
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"背景视频";
    self.tableView.sectionHeaderHeight = 26;
    self.tableView.sectionFooterHeight = 6;
    self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self pinBarInset:YES];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finish)];
}
// Keep the pinned top inset in step with the bar; never touch the scroll position.
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self pinBarInset:NO];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; CFPreferencesAppSynchronize(LMVEasterPrefs);
    [self.tableView reloadData]; [self loadNames];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated]; self.panelVisible = YES;
    [self showPendingImportPrompt];
}
- (void)viewWillDisappear:(BOOL)animated {
    self.panelVisible = NO; [super viewWillDisappear:animated];
}
- (void)showPendingImportPrompt {
    if (!self.panelVisible || !self.isViewLoaded || !self.view.window || self.view.window.hidden || self.view.window.alpha < 0.01 || self.presentedViewController || self.prompt) return;
    UINavigationController *navigation = self.navigationController;
    if (self.isMovingFromParentViewController || self.isBeingDismissed || navigation.isBeingDismissed || (navigation && navigation.topViewController != self)) return;
    LMVMaterialPrompt *prompt = LMVEasterPendingImportPrompts.firstObject;
    if (!prompt) return;
    [LMVEasterPendingImportPrompts removeObjectAtIndex:0];
    __weak typeof(self) weakSelf = self;
    prompt.complete = ^(NSString *text, BOOL accepted) {
        weakSelf.prompt = nil; [weakSelf showPendingImportPrompt];
    };
    UIViewController *host = navigation ?: self;
    self.prompt = prompt; [host addChildViewController:prompt]; [host.view addSubview:prompt.view];
    prompt.view.frame = host.view.bounds; prompt.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [prompt didMoveToParentViewController:host];
}
- (void)finish { if (self.close) self.close(); else [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)loadNames {
    NSUInteger generation = ++self.catalogGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(LMVMaterialQueue(), ^{
        NSDictionary *names = LMVReadMaterialNames();
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!weakSelf || weakSelf.catalogGeneration != generation) return;
            weakSelf.names = names; [weakSelf.tableView reloadData];
        });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return LMVEasterImportSection() + 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section >= 0 && section < LMVEasterTargets().count) return 4;
    if (section == LMVEasterControlCenterSection()) return 7;
    if (section == LMVEasterHomeMenuSection()) return 4;
    if (section == LMVEasterSquidPanelSection()) return 9;
    if (section == LMVEasterATSection()) return 4;
    if (section == LMVEasterCVSection()) return 4;
    return section == LMVEasterImportSection() || section == LMVEasterDisplaySection() ? 1 : 2;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)index { return index.row > 0 ? 60 : 44; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section < LMVEasterTargets().count) return LMVEasterTitles()[section];
    if (section == LMVEasterControlCenterSection()) return @"控制中心背景";
    if (section == LMVEasterHomeMenuSection()) return @"桌面长按菜单视频背景";
    if (section == LMVEasterSquidPanelSection()) return @"鱿鱼面板背景视频";
    if (section == LMVEasterATSection()) return @"AT 背景视频";
    if (section == LMVEasterCVSection()) return @"CopyVault 面板背景视频";
    if (section == LMVEasterDisplaySection()) return @"小彩蛋显示设置";
    return section == LMVEasterOpacitySection() ? @"消息、选项、清除视频透明度" : @"独立原片导入";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == LMVEasterControlCenterSection() ? @"按系统深浅色模式自动选择素材；未选择对应模式素材时保留系统背景。" : nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return section == LMVEasterControlCenterSection() ? UITableViewAutomaticDimension : 6;
}
- (CGFloat)opacity {
    id value = LMVEasterRead(@"VideoOpacity");
    double raw = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0.55;
    return isfinite(raw) ? MAX(0, MIN(1, raw)) : 0.55;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSString *audioTarget = LMVEasterAudioTarget(index.section, index.row);
    if (audioTarget) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        NSInteger tag = [LMVEasterAudioTargets() indexOfObject:audioTarget];
        if (!LMVEasterAudioVolumeRow(index.section, index.row)) {
            cell.textLabel.text = @"播放声音";
            UISwitch *toggle = [UISwitch new]; toggle.tag = tag; toggle.on = LMVEasterAudioEnabled(audioTarget);
            [toggle addTarget:self action:@selector(soundChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else {
            UISlider *slider = [UISlider new]; slider.tag = tag;
            slider.minimumValue = 0; slider.maximumValue = 1;
            slider.value = LMVEasterAudioVolume(LMVEasterRead([audioTarget stringByAppendingString:@"Volume"]));
            slider.enabled = LMVEasterAudioEnabled(audioTarget);
            slider.accessibilityLabel = @"声音音量";
            slider.accessibilityValue = [NSString stringWithFormat:@"%.0f%%", slider.value * 100.0];
            cell.textLabel.text = [@"音量 " stringByAppendingString:slider.accessibilityValue];
            [slider addTarget:self action:@selector(volumeChanged:) forControlEvents:UIControlEventValueChanged | UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            slider.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:slider];
            [NSLayoutConstraint activateConstraints:@[
                [slider.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:120],
                [slider.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [slider.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
            ]];
        }
        return cell;
    }
    if (index.section == LMVEasterImportSection()) {
        cell.textLabel.text = self.busy ? @"正在保存…" : @"从相册导入视频（原片）";
        cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
        cell.userInteractionEnabled = !self.busy; return cell;
    }
    if (index.section == LMVEasterDisplaySection()) {
        cell.textLabel.text = @"显示场景与图片旋转"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    if (index.section == LMVEasterHomeMenuSection()) {
        if (index.row == 0) {
            cell.textLabel.text = @"桌面长按菜单视频背景"; cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *toggle = [UISwitch new]; toggle.tag = LMVEasterHomeMenuSection();
            toggle.on = [LMVEasterRead(@"HomeMenuBackgroundEnabled") boolValue];
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else {
            cell.textLabel.text = @"切换长按菜单素材"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            id selected = LMVEasterRead(@"HomeMenuVideo");
            NSString *relative = [selected isKindOfClass:NSString.class] ? selected : @"";
            cell.detailTextLabel.text = relative.length ? LMVMaterialDisplayName(relative, self.names ?: @{}, @{}, index.section) : @"未选择";
            cell.detailTextLabel.numberOfLines = 2;
        }
        return cell;
    }
    if (index.section == LMVEasterSquidPanelSection()) {
        if (index.row == 0) {
            cell.textLabel.text = @"鱿鱼面板背景视频"; cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *toggle = [UISwitch new]; toggle.tag = LMVEasterSquidPanelSection();
            toggle.on = [LMVEasterRead(@"SquidPanelBackgroundEnabled") boolValue];
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else if (index.row >= 1 && index.row <= 4) {
            // 1.44: each panel shape gets its own material; 1.50: the shape exists on
            // both gesture sides, so there are four materials and the rows name the
            // GESTURE (right/left, 上滑/上上滑), not the orientation.
            cell.textLabel.text = LMVEasterSquidTitles()[index.row - 1];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            id selected = LMVEasterRead(LMVEasterSquidKeys()[index.row - 1]);
            NSString *relative = [selected isKindOfClass:NSString.class] ? selected : @"";
            cell.detailTextLabel.text = relative.length ? LMVMaterialDisplayName(relative, self.names ?: @{}, @{}, index.section) : @"未选择";
            cell.detailTextLabel.numberOfLines = 2;
        } else if (index.row == 5) {
            // 1.52: the repair for a record that was written wrong - the pair ordering
            // can only sort a side while that side is half unknown, so a corrupt pair
            // has to be cleared instead. One tap, then open the four panels once.
            cell.textLabel.text = @"重置面板识别";
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.detailTextLabel.text = @"忘记已记的四块面板；之后按 右一→右二→左一→左二 各开一次";
            cell.detailTextLabel.numberOfLines = 2;
        } else if (index.row == 6) {
            // 1.46: the manual override. A button rather than a switch: the panel's
            // switches are told apart by their tag and every tag is a section index,
            // so this row reports its state in the detail label instead.
            cell.textLabel.text = @"对调上滑 / 上上滑素材";
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.detailTextLabel.text = [LMVEasterRead(@"SquidPanelSwapShapes") boolValue] ? @"已对调" : @"正常";
            cell.detailTextLabel.numberOfLines = 1;
        } else {
            cell.textLabel.text = @""; cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryNone;
        }
        return cell;
    }
    if (index.section == LMVEasterATSection()) {
        if (index.row == 0) {
            cell.textLabel.text = @"AT 背景视频"; cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *toggle = [UISwitch new]; toggle.tag = LMVEasterATSection();
            toggle.on = [LMVEasterRead(@"ATBackgroundEnabled") boolValue];
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else {
            cell.textLabel.text = @"切换 AT 素材"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            id selected = LMVEasterRead(@"ATVideo");
            NSString *relative = [selected isKindOfClass:NSString.class] ? selected : @"";
            cell.detailTextLabel.text = relative.length ? LMVMaterialDisplayName(relative, self.names ?: @{}, @{}, index.section) : @"未选择";
            cell.detailTextLabel.numberOfLines = 2;
        }
        return cell;
    }
    if (index.section == LMVEasterCVSection()) {
        if (index.row == 0) {
            cell.textLabel.text = @"CopyVault 面板背景视频"; cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *toggle = [UISwitch new]; toggle.tag = LMVEasterCVSection();
            toggle.on = [LMVEasterRead(@"CVBackgroundEnabled") boolValue];
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else {
            cell.textLabel.text = @"切换 CopyVault 素材"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            id selected = LMVEasterRead(@"CVVideo");
            NSString *relative = [selected isKindOfClass:NSString.class] ? selected : @"";
            cell.detailTextLabel.text = relative.length ? LMVMaterialDisplayName(relative, self.names ?: @{}, @{}, index.section) : @"未选择";
            cell.detailTextLabel.numberOfLines = 2;
        }
        return cell;
    }
    if (index.section == LMVEasterControlCenterSection()) {
        if (index.row == 0) {
            cell.textLabel.text = @"启用控制中心背景";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *toggle = [UISwitch new]; toggle.tag = LMVEasterControlCenterSection();
            toggle.on = [LMVEasterRead(@"ControlCenterBackgroundEnabled") boolValue];
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else {
            cell.textLabel.text = index.row == 1 ? @"切换深色模式素材" : @"切换浅色模式素材";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            id selected = LMVEasterRead(LMVEasterControlCenterKey(index.row));
            NSString *relative = [selected isKindOfClass:NSString.class] ? selected : @"";
            cell.detailTextLabel.text = relative.length ? LMVMaterialDisplayName(relative, self.names ?: @{}, @{}, index.row == 1 ? 0 : 1) : @"未选择";
            cell.detailTextLabel.numberOfLines = 2;
        }
        return cell;
    }
    if (index.section == LMVEasterOpacitySection()) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (index.row == 0) {
            cell.textLabel.text = @"启用视频透明度";
            UISwitch *toggle = [UISwitch new]; toggle.tag = LMVEasterOpacitySection();
            id enabled = LMVEasterRead(@"VideoOpacityEnabled");
            toggle.on = enabled ? [enabled boolValue] : YES;
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else {
            UISlider *slider = [UISlider new]; slider.minimumValue = 0; slider.maximumValue = 1; slider.value = [self opacity];
            slider.accessibilityLabel = @"视频透明度";
            [slider addTarget:self action:@selector(opacityChanged:) forControlEvents:UIControlEventValueChanged | UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
            slider.translatesAutoresizingMaskIntoConstraints = NO; [cell.contentView addSubview:slider];
            [NSLayoutConstraint activateConstraints:@[
                [slider.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16],
                [slider.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-16],
                [slider.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor]
            ]];
        }
        return cell;
    }
    NSString *target = LMVEasterTargets()[index.section];
    if (index.row == 0) {
        cell.textLabel.text = @"启用";
        UISwitch *toggle = [UISwitch new]; toggle.tag = index.section;
        toggle.on = [LMVEasterRead([target stringByAppendingString:@"BackgroundEnabled"]) boolValue];
        [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else {
        cell.textLabel.text = @"选择素材"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        id selected = LMVEasterRead([target stringByAppendingString:@"Video"]);
        NSDictionary *legacy = @{@"Message":@"message.mov", @"Options":@"options.mov", @"Clear":@"clear.mov", @"LockScreen":@"", @"Desktop":@""};
        NSString *relative = [selected isKindOfClass:NSString.class] ? selected : legacy[target];
        cell.detailTextLabel.text = relative.length ? LMVMaterialDisplayName(relative, self.names ?: @{}, @{}, index.section) : @"未选择";
        cell.detailTextLabel.numberOfLines = 2;
    }
    return cell;
}
- (void)toggle:(UISwitch *)toggle {
    if (toggle.tag < 0 || toggle.tag > LMVEasterOpacitySection()) return;
    NSString *key;
    if (toggle.tag == LMVEasterControlCenterSection()) key = @"ControlCenterBackgroundEnabled";
    else if (toggle.tag == LMVEasterOpacitySection()) key = @"VideoOpacityEnabled";
    else if (toggle.tag == LMVEasterHomeMenuSection()) key = @"HomeMenuBackgroundEnabled";
    else if (toggle.tag == LMVEasterSquidPanelSection()) key = @"SquidPanelBackgroundEnabled";
    else if (toggle.tag == LMVEasterATSection()) key = @"ATBackgroundEnabled";
    else if (toggle.tag == LMVEasterCVSection()) key = @"CVBackgroundEnabled";
    else if (toggle.tag < LMVEasterTargets().count) key = [LMVEasterTargets()[toggle.tag] stringByAppendingString:@"BackgroundEnabled"];
    else return;
    LMVEasterSet(key, @(toggle.on));
}
- (void)soundChanged:(UISwitch *)toggle {
    NSString *target = LMVEasterAudioTargetForTag(toggle.tag);
    if (!target) return;
    LMVEasterSet([target stringByAppendingString:@"SoundEnabled"], @(toggle.on));
    [self.tableView reloadData];
}
- (void)volumeChanged:(UISlider *)slider {
    NSString *target = LMVEasterAudioTargetForTag(slider.tag);
    if (!target) return;
    double volume = LMVEasterAudioVolume(@(slider.value));
    self.volumeTracking = slider.isTracking;
    LMVEasterSet([target stringByAppendingString:@"Volume"], @(volume));
    slider.accessibilityValue = [NSString stringWithFormat:@"%.0f%%", volume * 100.0];
    for (UIView *view = slider.superview; view; view = view.superview) {
        if ([view isKindOfClass:UITableViewCell.class]) {
            ((UITableViewCell *)view).textLabel.text = [@"音量 " stringByAppendingString:slider.accessibilityValue]; break;
        }
    }
    if (!slider.isTracking) { self.volumeTracking = NO; [self.tableView reloadData]; }
}
- (void)opacityChanged:(UISlider *)slider {
    self.opacityTracking = slider.isTracking;
    LMVEasterSet(@"VideoOpacity", @(MAX(0, MIN(1, slider.value))));
    if (!slider.isTracking) { self.opacityTracking = NO; [self.tableView reloadData]; }
}
// 1.52: clear the learned panels and let the automatic rules start over, for a record
// that went wrong (see LMVSquidPanelVideo's LMVSquidPanelForgetAll).
- (void)resetSquidPanel {
    LMVEasterSet(@"SquidPanelResetToken", [NSString stringWithFormat:@"%.3f", NSDate.date.timeIntervalSince1970]);
    [self.tableView reloadData];
}
// 1.53: nothing manual is left here - the runtime works the four panels out by itself
// (see LMVSquidPanelVideo) and "重置面板识别" is the only repair row.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES];
    if (self.presentedViewController || self.busy) return;
    if (index.section == LMVEasterImportSection()) { if (index.row == 0) [self importVideo]; return; }
    if (index.section == LMVEasterDisplaySection()) {
        if (index.row != 0) return;
        [self.navigationController pushViewController:[LMVEasterImageSettings new] animated:YES]; return;
    }
    NSString *key = nil;
    NSString *fallback = @"";
    if (index.section == LMVEasterControlCenterSection()) {
        key = LMVEasterControlCenterKey(index.row);
        if (!key) return;
    } else if (index.section == LMVEasterHomeMenuSection()) {
        if (index.row != 1) return;
        key = @"HomeMenuVideo";
    } else if (index.section == LMVEasterSquidPanelSection()) {
        if (index.row == 5) { [self resetSquidPanel]; return; }
        if (index.row == 6) {
            BOOL now = [LMVEasterRead(@"SquidPanelSwapShapes") boolValue];
            LMVEasterSet(@"SquidPanelSwapShapes", @(!now));
            [self.tableView reloadData];
            return;
        }
        if (index.row < 1 || index.row > 4) return;
        key = LMVEasterSquidKeys()[index.row - 1];
    } else if (index.section == LMVEasterATSection()) {
        if (index.row != 1) return;
        key = @"ATVideo";
    } else if (index.section == LMVEasterCVSection()) {
        if (index.row != 1) return;
        key = @"CVVideo";
    } else {
        if (index.section < 0 || index.section >= LMVEasterTargets().count || index.row != 1) return;
        NSString *target = LMVEasterTargets()[index.section];
        key = [target stringByAppendingString:@"Video"];
        NSDictionary *legacy = @{@"Message":@"message.mov", @"Options":@"options.mov", @"Clear":@"clear.mov", @"LockScreen":@"", @"Desktop":@""};
        fallback = legacy[target] ?: @"";
    }
    // 0.0.122: the floating panel shows the same previews as the Settings app.
    // LMVMaterialPicker already loads them on a single utility queue with an
    // NSCache + a remembered-failure set and only for visible rows, so a large
    // library never blocks scrolling.
    LMVMaterialPicker *picker = [LMVMaterialPicker new]; picker.pushed = YES; picker.showsThumbnails = YES;
    id current = LMVEasterRead(key);
    picker.selected = [current isKindOfClass:NSString.class] ? current : fallback;
    __weak typeof(self) weakSelf = self;
    picker.apply = ^(NSString *relative, NSString *name) { LMVEasterSet(key, relative); [weakSelf.tableView reloadData]; };
    [self.navigationController pushViewController:picker animated:YES];
}
- (void)importVideo {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    configuration.filter = PHPickerFilter.videosFilter; configuration.selectionLimit = 1;
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration]; picker.delegate = self;
    self.photoFlow = [[LMVEasterPhotoFlow alloc] initWithPicker:picker];
    __weak typeof(self) weakSelf = self;
    self.photoFlow.cancel = ^{ [weakSelf finishPhotoFlow]; };
    [self.navigationController pushViewController:self.photoFlow animated:YES];
}
- (void)finishPhotoFlow {
    if (!self.photoFlow) return;
    self.photoFlow.picker.delegate = nil;
    [self.navigationController popToViewController:self animated:YES]; self.photoFlow = nil;
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    if (picker != self.photoFlow.picker) return;
    PHPickerResult *picked = results.firstObject; [self finishPhotoFlow];
    if (!picked || self.busy || ![picked.itemProvider hasItemConformingToTypeIdentifier:@"public.movie"]) return;
    self.busy = YES; [self.tableView reloadData];
    __weak typeof(self) weakSelf = self;
    [picked.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *providerError) {
        NSError *error = providerError; NSString *relative = nil;
        if (!url && !error) error = LMVStorageError(71, @"相册未返回文件");
        // The raw video import is independent of the Settings encoder.
        if (url && !error) relative = LMVEasterImport(url, YES, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            LMVEasterPanel *panel = weakSelf;
            panel.busy = NO;
            BOOL success = relative && !error;
            if (success) LMVEasterNotify();
            [panel.tableView reloadData]; [panel loadNames];
            LMVMaterialPrompt *prompt = [LMVMaterialPrompt new];
            prompt.promptTitle = success ? @"导入成功" : @"导入失败";
            prompt.message = success ? @"已保存到素材库" : (error.localizedDescription ?: @"无法保存视频");
            if (!LMVEasterPendingImportPrompts) LMVEasterPendingImportPrompts = [NSMutableArray new];
            [LMVEasterPendingImportPrompts addObject:prompt];
            [NSNotificationCenter.defaultCenter postNotificationName:LMVEasterImportResultReady object:nil];
            [panel showPendingImportPrompt];
        });
    }];
}
@end
