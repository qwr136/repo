#pragma once
#import <PhotosUI/PhotosUI.h>
#import "LMVEasterMedia.h"
#import "LockMessageVideoPrefs/LMVMaterialPicker.h"

@interface LMVEasterPanel : UITableViewController <PHPickerViewControllerDelegate>
@property(nonatomic) BOOL imageControls, importingMovie, busy;
@property(nonatomic) NSUInteger previewGeneration;
@property(nonatomic, strong) UIImage *preview;
@property(nonatomic, copy) void (^close)(void);
@end

static NSArray *LMVEasterTargets(void) { return @[@"Message", @"LockScreen", @"Desktop", @"Options", @"Clear"]; }
static NSArray *LMVEasterTitles(void) { return @[@"消息背景", @"锁屏背景", @"桌面背景", @"选项背景", @"清除背景"]; }
static void LMVEasterPanelChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    __weak LMVEasterPanel *panel = (__bridge LMVEasterPanel *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        CFPreferencesAppSynchronize(LMVEasterPrefs);
        if (panel.isViewLoaded) [panel.tableView reloadData];
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
    [super viewDidLoad]; self.title = @"小彩蛋";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finish)];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated]; CFPreferencesAppSynchronize(LMVEasterPrefs);
    [self.tableView reloadData]; [self loadPreview];
}
- (void)finish { if (self.close) self.close(); else [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)loadPreview {
    if (!self.imageControls) return;
    NSUInteger generation = ++self.previewGeneration;
    NSString *path = LMVEasterImagePath(LMVEasterRead(@"EasterEggImage"));
    self.preview = nil;
    __weak typeof(self) weakSelf = self;
    dispatch_async(LMVMaterialQueue(), ^{
        UIImage *image = path ? LMVEasterDecode([NSURL fileURLWithPath:path], NULL).frames.firstObject : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (weakSelf.previewGeneration != generation) return;
            weakSelf.preview = image; [weakSelf.tableView reloadData];
        });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.imageControls ? 7 : 6; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (self.imageControls && section == 0) return 3;
    NSInteger targetSection = section - (self.imageControls ? 1 : 0);
    return targetSection < 5 ? 2 : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (self.imageControls && section == 0) return @"悬浮图片";
    NSInteger targetSection = section - (self.imageControls ? 1 : 0);
    return targetSection < 5 ? LMVEasterTitles()[targetSection] : @"独立原片导入";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (self.imageControls && index.section == 0) {
        if (index.row == 0) {
            cell.textLabel.text = @"启用小彩蛋";
            UISwitch *toggle = [UISwitch new]; toggle.tag = 100;
            toggle.on = [LMVEasterRead(@"EasterEggEnabled") boolValue];
            [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
        } else if (index.row == 1) {
            cell.textLabel.text = @"图片预览"; cell.imageView.image = self.preview ?: [UIImage systemImageNamed:@"photo"];
            cell.imageView.contentMode = UIViewContentModeScaleAspectFit; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else { cell.textLabel.text = @"从相册导入图片 / GIF"; cell.imageView.image = [UIImage systemImageNamed:@"photo.on.rectangle"]; }
        return cell;
    }
    NSInteger targetIndex = index.section - (self.imageControls ? 1 : 0);
    if (targetIndex == 5) { cell.textLabel.text = self.busy ? @"正在保存…" : @"从相册导入视频（原片）"; cell.imageView.image = [UIImage systemImageNamed:@"square.and.arrow.down"]; cell.userInteractionEnabled = !self.busy; return cell; }
    NSString *target = LMVEasterTargets()[targetIndex];
    if (index.row == 0) {
        cell.textLabel.text = @"启用";
        UISwitch *toggle = [UISwitch new]; toggle.tag = targetIndex;
        toggle.on = [LMVEasterRead([target stringByAppendingString:@"BackgroundEnabled"]) boolValue];
        [toggle addTarget:self action:@selector(toggle:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else {
        cell.textLabel.text = @"选择素材"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        id selected = LMVEasterRead([target stringByAppendingString:@"Video"]);
        cell.detailTextLabel.text = [selected isKindOfClass:NSString.class] && [selected length] ? [selected lastPathComponent] : @"未选择";
    }
    return cell;
}
- (void)toggle:(UISwitch *)toggle {
    NSString *key = toggle.tag == 100 ? @"EasterEggEnabled" : [LMVEasterTargets()[toggle.tag] stringByAppendingString:@"BackgroundEnabled"];
    LMVEasterSet(key, @(toggle.on));
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES];
    if (self.presentedViewController || self.busy) return;
    if (self.imageControls && index.section == 0) { if (index.row == 2) [self importMedia:NO]; return; }
    NSInteger targetIndex = index.section - (self.imageControls ? 1 : 0);
    if (targetIndex == 5) { [self importMedia:YES]; return; }
    if (index.row != 1) return;
    NSString *key = [LMVEasterTargets()[targetIndex] stringByAppendingString:@"Video"];
    LMVMaterialPicker *picker = [LMVMaterialPicker new];
    id current = LMVEasterRead(key);
    NSDictionary *legacy = @{@"Message":@"message.mov", @"Options":@"options.mov", @"Clear":@"clear.mov"};
    picker.selected = [current isKindOfClass:NSString.class] ? current : legacy[LMVEasterTargets()[targetIndex]] ?: @"";
    __weak typeof(self) weakSelf = self;
    picker.apply = ^(NSString *relative, NSString *name) { LMVEasterSet(key, relative); [weakSelf.tableView reloadData]; };
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
}
- (void)importMedia:(BOOL)movie {
    self.importingMovie = movie;
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    configuration.filter = movie ? PHPickerFilter.videosFilter : PHPickerFilter.imagesFilter;
    configuration.selectionLimit = 1;
    configuration.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration]; picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    PHPickerResult *picked = results.firstObject; BOOL movie = self.importingMovie;
    [picker dismissViewControllerAnimated:YES completion:^{
        if (!picked || self.busy) return;
        NSString *type = movie ? @"public.movie" : ([picked.itemProvider hasItemConformingToTypeIdentifier:@"com.compuserve.gif"] ? @"com.compuserve.gif" : @"public.image");
        if (![picked.itemProvider hasItemConformingToTypeIdentifier:type]) return;
        self.busy = YES; [self.tableView reloadData];
        __weak typeof(self) weakSelf = self;
        [picked.itemProvider loadFileRepresentationForTypeIdentifier:type completionHandler:^(NSURL *url, NSError *providerError) {
            NSError *error = providerError; NSString *relative = nil;
            if (!url && !error) error = LMVStorageError(71, @"相册未返回文件");
            if (url && !error) relative = LMVEasterImport(url, movie, &error);
            dispatch_async(dispatch_get_main_queue(), ^{
                LMVEasterPanel *panel = weakSelf; if (!panel) return;
                panel.busy = NO;
                if (relative && !movie) { LMVEasterSet(@"EasterEggImage", relative); [panel loadPreview]; }
                else if (relative) LMVEasterNotify();
                [panel.tableView reloadData];
                if (error && panel.view.window && !panel.presentedViewController) {
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
                    [panel presentViewController:alert animated:YES completion:nil];
                }
            });
        }];
    }];
}
@end
