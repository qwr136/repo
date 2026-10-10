#pragma once
#import <PhotosUI/PhotosUI.h>
#import "LMVEasterMedia.h"

@interface LMVEasterImageSettings : UITableViewController <PHPickerViewControllerDelegate>
@property(nonatomic) BOOL busy;
@property(nonatomic, copy) void (^close)(void);
@end
@implementation LMVEasterImageSettings
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"小彩蛋图片";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(finish)];
}
- (void)finish { if (self.close) self.close(); else [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 2; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)index { return index.row == 1 ? 80 : 44; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    // No static preview; keep image/GIF import and floating icon size.
    if (index.row == 0) {
        cell.textLabel.text = self.busy ? @"正在保存…" : @"从相册导入图片 / GIF"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; cell.userInteractionEnabled = !self.busy;
    } else {
        cell.textLabel.text = @"悬浮图标大小"; cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", LMVEasterSize()]; cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 32)];
        slider.minimumValue = 32; slider.maximumValue = 128; slider.value = LMVEasterSize(); slider.accessibilityLabel = @"悬浮图标大小";
        [slider addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = slider;
    }
    return cell;
}
- (void)sizeChanged:(UISlider *)slider {
    CGFloat size = MAX(32, MIN(128, round(slider.value))); LMVEasterSet(@"EasterEggSize", @(size));
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%.0f pt", size];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES]; if (index.row != 0 || self.busy || self.presentedViewController) return;
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
