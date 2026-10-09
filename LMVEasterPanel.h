#pragma once
#import <PhotosUI/PhotosUI.h>
#import "LMVEasterMedia.h"
#import "LMVEasterPhotoFlow.h"
#import "LockMessageVideoPrefs/LMVMaterialPicker.h"

// Floating video controls have no image settings or image import role.
@interface LMVEasterPanel : UITableViewController <PHPickerViewControllerDelegate>
@property(nonatomic) BOOL busy, opacityTracking;
@property(nonatomic) NSUInteger catalogGeneration;
@property(nonatomic, copy) NSDictionary *names;
@property(nonatomic, strong) LMVEasterPhotoFlow *photoFlow;
@property(nonatomic, copy) void (^close)(void);
@end
static NSArray *LMVEasterTargets(void) { return @[@"Message", @"LockScreen", @"Desktop", @"Options", @"Clear"]; }
static NSArray *LMVEasterTitles(void) { return @[@"消息背景", @"锁屏背景", @"桌面背景", @"选项背景", @"清除背景"]; }
static void LMVEasterPanelChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    __weak LMVEasterPanel *panel = (__bridge LMVEasterPanel *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(LMVEasterPrefs);
        if (panel.isViewLoaded && !panel.opacityTracking) { [panel.tableView reloadData]; [panel loadNames]; }
    });
}
@implementation LMVEasterPanel
- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, LMVEasterPanelChanged, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    return self;
}
- (void)dealloc { CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self); }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"背景视频";
    self.tableView.sectionHeaderHeight = 26;
    self.tableView.sectionFooterHeight = 6;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finish)];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; CFPreferencesAppSynchronize(LMVEasterPrefs);
    [self.tableView reloadData]; [self loadNames];
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
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 7; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 6 ? 1 : 2; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)index { return index.row == 1 ? 60 : 44; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section < 5 ? LMVEasterTitles()[section] : (section == 5 ? @"视频透明度" : @"独立原片导入");
}
- (CGFloat)opacity {
    id value = LMVEasterRead(@"VideoOpacity");
    double raw = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0.55;
    return isfinite(raw) ? MAX(0, MIN(1, raw)) : 0.55;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (index.section == 6) {
        cell.textLabel.text = self.busy ? @"正在保存…" : @"从相册导入视频（原片）";
        cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"];
        cell.userInteractionEnabled = !self.busy; return cell;
    }
    if (index.section == 5) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if (index.row == 0) {
            cell.textLabel.text = @"启用视频透明度";
            UISwitch *toggle = [UISwitch new]; toggle.tag = 5;
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
        NSDictionary *legacy = @{@"Message":@"message.mov", @"Options":@"options.mov", @"Clear":@"clear.mov"};
        NSString *relative = [selected isKindOfClass:NSString.class] ? selected : legacy[target];
        cell.detailTextLabel.text = relative.length ? LMVMaterialDisplayName(relative, self.names ?: @{}, @{}, index.section) : @"未选择";
        cell.detailTextLabel.numberOfLines = 2;
    }
    return cell;
}
- (void)toggle:(UISwitch *)toggle {
    NSString *key = toggle.tag == 5 ? @"VideoOpacityEnabled" : [LMVEasterTargets()[toggle.tag] stringByAppendingString:@"BackgroundEnabled"];
    LMVEasterSet(key, @(toggle.on));
}
- (void)opacityChanged:(UISlider *)slider {
    self.opacityTracking = slider.isTracking;
    LMVEasterSet(@"VideoOpacity", @(MAX(0, MIN(1, slider.value))));
    if (!slider.isTracking) { self.opacityTracking = NO; [self.tableView reloadData]; }
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES];
    if (self.presentedViewController || self.busy) return;
    if (index.section == 6) { [self importVideo]; return; }
    if (index.section >= 5 || index.row != 1) return;
    NSString *key = [LMVEasterTargets()[index.section] stringByAppendingString:@"Video"];
    LMVMaterialPicker *picker = [LMVMaterialPicker new]; picker.pushed = YES;
    id current = LMVEasterRead(key);
    NSDictionary *legacy = @{@"Message":@"message.mov", @"Options":@"options.mov", @"Clear":@"clear.mov"};
    picker.selected = [current isKindOfClass:NSString.class] ? current : legacy[LMVEasterTargets()[index.section]] ?: @"";
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
            LMVEasterPanel *panel = weakSelf; if (!panel) return;
            panel.busy = NO;
            if (relative) LMVEasterNotify();
            [panel.tableView reloadData]; [panel loadNames];
            if (error && panel.view.window && !panel.presentedViewController) {
                LMVMaterialPrompt *alert = [LMVMaterialPrompt new]; alert.promptTitle = @"导入失败"; alert.message = error.localizedDescription;
                UIViewController *host = panel.navigationController ?: panel;
                [host addChildViewController:alert]; [host.view addSubview:alert.view];
                alert.view.frame = host.view.bounds; alert.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
                [alert didMoveToParentViewController:host];
            }
        });
    }];
}
@end
