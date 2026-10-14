#pragma once
#import <PhotosUI/PhotosUI.h>
#import "LMVEasterMedia.h"

static NSInteger LMVEasterImageSection(void) { return 0; }
static NSInteger LMVEasterImageDisplaySection(void) { return LMVEasterImageSection() + 1; }
static NSInteger LMVEasterImageRotationSection(void) { return LMVEasterImageDisplaySection() + 1; }
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
    return isfinite(speed) ? MAX(5.0, MIN(180.0, speed)) : 45.0;
}
@interface LMVEasterImageSettings : UITableViewController <PHPickerViewControllerDelegate>
@property(nonatomic) BOOL busy, settingsTracking;
@property(nonatomic, copy) void (^close)(void);
@end
static void LMVEasterImageSettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    __weak LMVEasterImageSettings *page = (__bridge LMVEasterImageSettings *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(LMVEasterPrefs);
        if (page.isViewLoaded && !page.settingsTracking) [page.tableView reloadData];
    });
}
@implementation LMVEasterImageSettings
- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, LMVEasterImageSettingsChanged, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
    return self;
}
- (void)dealloc { CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self); }
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; CFPreferencesAppSynchronize(LMVEasterPrefs); [self.tableView reloadData];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"小彩蛋图片";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finish)];
}
- (void)finish {
    if (self.close) self.close();
    else if (self.navigationController.viewControllers.count > 1) [self.navigationController popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return LMVEasterImageRotationSection() + 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == LMVEasterImageDisplaySection() ? LMVEasterImageDisplayKeys().count : 2;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == LMVEasterImageDisplaySection()) return @"小彩蛋显示场景";
    return section == LMVEasterImageRotationSection() ? @"彩蛋图片旋转" : @"图片 / GIF 与图标大小";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == LMVEasterImageDisplaySection() ? @"默认不在锁屏显示；控制中心和桌面默认显示。通知中心沿用现有显示行为。" : nil;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)index {
    return index.section != LMVEasterImageDisplaySection() && index.row == 1 ? 80 : 44;
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
            slider.minimumValue = 5; slider.maximumValue = 180; slider.value = LMVEasterImageRotationSpeed();
            slider.enabled = LMVEasterImageBool(@"EasterEggRotationEnabled", NO); slider.accessibilityLabel = @"彩蛋图片旋转速度（度/秒）";
            [slider addTarget:self action:@selector(rotationSpeedChanged:) forControlEvents:UIControlEventValueChanged | UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel]; cell.accessoryView = slider;
        }
        return cell;
    }
    // No static preview; keep image/GIF import and floating icon size.
    if (index.row == 0) {
        cell.textLabel.text = self.busy ? @"正在保存…" : @"从相册导入图片 / GIF"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.userInteractionEnabled = !self.busy;
    } else {
        cell.textLabel.text = @"悬浮图标大小"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", LMVEasterSize()]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 32)];
        slider.minimumValue = 32; slider.maximumValue = 128; slider.value = LMVEasterSize(); slider.accessibilityLabel = @"悬浮图标大小";
        [slider addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged | UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel]; cell.accessoryView = slider;
    }
    return cell;
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
    CGFloat speed = isfinite(raw) ? MAX(5.0, MIN(180.0, round(raw))) : 45.0;
    LMVEasterSet(@"EasterEggRotationSpeed", @(speed));
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:LMVEasterImageRotationSection()]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f 度/秒", speed];
    if (!slider.isTracking) [self.tableView reloadData];
}
- (void)sizeChanged:(UISlider *)slider {
    self.settingsTracking = slider.isTracking;
    CGFloat size = MAX(32, MIN(128, round(slider.value))); LMVEasterSet(@"EasterEggSize", @(size));
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:LMVEasterImageSection()]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", size];
    if (!slider.isTracking) [self.tableView reloadData];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES]; if (index.section != LMVEasterImageSection() || index.row != 0 || self.busy || self.presentedViewController) return;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary]; config.filter = PHPickerFilter.imagesFilter; config.selectionLimit = 1; config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    PHPickerResult *picked = results.firstObject;
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!picked || self.busy) return;
        NSString *type = [picked.itemProvider hasItemConformingToTypeIdentifier:@"com.compuserve.gif"] ? @"com.compuserve.gif" : @"public.image";
        if (![picked.itemProvider hasItemConformingToTypeIdentifier:type]) return;
        self.busy = YES; [self.tableView reloadData]; __weak typeof(self) weakSelf = self;
        [picked.itemProvider loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url, NSError *providerError) {
            NSError *error = providerError;
            if (!url && !error) error = LMVStorageError(71, @"相册未返回图片");
            NSString *relative = url && !error ? LMVEasterImport(url, NO, &error) : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                LMVEasterImageSettings *page = weakSelf; if (!page) return; page.busy = NO;
                if (relative) LMVEasterSet(@"EasterEggImage", relative);
                [page.tableView reloadData];
                if (error && page.view.window && !page.presentedViewController) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert]; [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]]; [page presentViewController:alert animated:YES completion:nil];
                }
            });
        }];
    }];
}
@end
