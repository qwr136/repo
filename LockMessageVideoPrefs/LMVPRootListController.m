#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>

static NSString * const kLMVPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.minis.lockmessagevideo.plist";
static NSString * const kLMVDir = @"/var/mobile/LockMessageVideo";

@interface LMVPRootListController : UITableViewController <PHPickerViewControllerDelegate>
@property(nonatomic,retain) UISwitch *enabledSwitch;
@end

@implementation LMVPRootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"锁屏消息视频";
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"cell"];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 1 : (section == 1 ? 2 : 1); }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.accessoryView = nil; cell.accessoryType = UITableViewCellAccessoryNone; cell.textLabel.text = nil; cell.detailTextLabel.text = nil;
    if (indexPath.section == 0) {
        cell.textLabel.text = @"启用消息背景";
        UISwitch *sw = [[UISwitch alloc] init];
        NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:kLMVPrefsPath] ?: @{};
        sw.on = [p[@"MessageBackgroundEnabled"] boolValue];
        [sw addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];
        self.enabledSwitch = sw; cell.accessoryView = sw;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = indexPath.row == 0 ? @"选择消息背景视频" : @"清除消息背景视频";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = @"路径：/var/mobile/LockMessageVideo/message.mov";
        cell.textLabel.numberOfLines = 0;
    }
    return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"消息通知背景" : (section == 1 ? @"视频" : @"说明");
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;
    if (indexPath.row == 0) [self presentPicker];
    else {
        [[NSFileManager defaultManager] removeItemAtPath:[kLMVDir stringByAppendingPathComponent:@"message.mov"] error:nil];
        [self postChanged];
    }
}

- (void)enabledChanged:(UISwitch *)sw {
    NSMutableDictionary *p = [NSMutableDictionary dictionaryWithContentsOfFile:kLMVPrefsPath] ?: [NSMutableDictionary dictionary];
    p[@"MessageBackgroundEnabled"] = @(sw.isOn);
    [p writeToFile:kLMVPrefsPath atomically:YES];
    [self postChanged];
}

- (void)postChanged {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, NULL, YES);
}

- (void)presentPicker {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    config.filter = [PHPickerFilter videosFilter]; config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self; [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result) return;
    [result.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
        NSError *e = error;
        NSString *dir = kLMVDir; NSString *dst = [dir stringByAppendingPathComponent:@"message.mov"];
        if (url && !e) {
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&e];
            if (!e) { [[NSFileManager defaultManager] removeItemAtPath:dst error:nil]; [[NSFileManager defaultManager] copyItemAtURL:url toURL:[NSURL fileURLWithPath:dst] error:&e]; }
        }
        if (!e) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self postChanged]; [self.tableView reloadData]; });
        }
    }];
}

@end
