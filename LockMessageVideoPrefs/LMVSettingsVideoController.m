#import "LMVSettingsVideoController.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <Preferences/PSSpecifier.h>
#import <AVFoundation/AVFoundation.h>

// 2.63: the Settings-app video background page. Every row writes the same keys
// LMVSettingsVideoBackground reads, so a change is visible on the next refresh
// without a respring.

// 2.63: a list for THIS channel's folder only. The shared picker scans the global
// catalog root, so reusing it would show (and allow choosing) materials that do
// not belong to the Settings background.
@interface LMVSettingsMaterialPicker : UITableViewController
@property(nonatomic, copy) NSArray<NSDictionary *> *materials;
@property(nonatomic, copy) NSString *selected;
@property(nonatomic, copy) void (^apply)(NSDictionary *row);
@end
@implementation LMVSettingsMaterialPicker
- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        self.title = @"选择视频";
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    self.tableView.rowHeight = 76;
    // 2.88: 这一层是我们自己的弹窗，直接透明，视频才能透上来。
    self.view.backgroundColor = UIColor.clearColor;
    self.tableView.backgroundColor = UIColor.clearColor;
}
- (void)cancel { [self dismissViewControllerAnimated:YES completion:nil]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return (NSInteger)self.materials.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"LMVSettingsMaterialCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    NSDictionary *row = self.materials[indexPath.row];
    cell.backgroundColor = UIColor.clearColor;
    cell.contentView.backgroundColor = UIColor.clearColor;
    cell.textLabel.text = row[@"name"];
    cell.detailTextLabel.text = [self.selected isEqualToString:row[@"relative"]] ? @"当前使用" : nil;
    cell.accessoryType = [self.selected isEqualToString:row[@"relative"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.imageView.image = row[@"preview"] ?: [UIImage systemImageNamed:@"film"];
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.clipsToBounds = YES;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSDictionary *row = self.materials[indexPath.row];
    void (^apply)(NSDictionary *) = self.apply;
    [self dismissViewControllerAnimated:YES completion:^{ if (apply) apply(row); }];
}
@end

static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSString *const LMVSettingsVideoRoot = @"/var/mobile/LockMessageVideo/设置视频背景";
static NSString *const LMVSettingsVideoEnabledKey = @"SettingsVideoBackgroundEnabled";
static NSString *const LMVSettingsVideoFileKey = @"SettingsVideo";
static NSString *const LMVSettingsVideoSoundKey = @"SettingsVideoSoundEnabled";
static NSString *const LMVSettingsVideoVolumeKey = @"SettingsVideoVolume";
static id LMVSettingsRead(NSString *key) {
    return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kLMVPrefsID);
}
static void LMVSettingsWrite(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, kLMVPrefsID);
    CFPreferencesAppSynchronize(kLMVPrefsID);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, NULL, YES);
}

@implementation LMVSettingsVideoController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"设置视频背景";
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *rows = [NSMutableArray array];

    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"设置 App 视频背景"];
    [group setProperty:@"开启后，设置 App 的背景会显示所选视频；素材目录：/var/mobile/LockMessageVideo/设置视频背景" forKey:@"footerText"];
    [rows addObject:group];

    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用设置视频背景" target:self
        set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [enabled setProperty:LMVSettingsVideoEnabledKey forKey:@"key"];
    [enabled setProperty:@NO forKey:@"default"];
    [rows addObject:enabled];

    PSSpecifier *choose = [PSSpecifier preferenceSpecifierNamed:@"切换视频" target:self set:nil get:nil
        detail:nil cell:PSButtonCell edit:nil];
    choose.buttonAction = @selector(switchMaterial:);
    [choose setProperty:@"SettingsVideoMaterial" forKey:@"id"];
    [rows addObject:choose];

    PSSpecifier *sound = [PSSpecifier preferenceSpecifierNamed:@"声音开关" target:self
        set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [sound setProperty:LMVSettingsVideoSoundKey forKey:@"key"];
    [sound setProperty:@NO forKey:@"default"];
    [rows addObject:sound];

    PSSpecifier *volume = [PSSpecifier preferenceSpecifierNamed:@"声音大小（%）" target:self
        set:@selector(setVolume:specifier:) get:@selector(volume:) detail:nil cell:PSSliderCell edit:nil];
    [volume setProperty:LMVSettingsVideoVolumeKey forKey:@"key"];
    [volume setProperty:@0.0 forKey:@"min"];
    [volume setProperty:@1.0 forKey:@"max"];
    [volume setProperty:@0.5 forKey:@"default"];
    [volume setProperty:@YES forKey:@"showValue"];
    [volume setProperty:@"SettingsVideoVolume" forKey:@"id"];
    [rows addObject:volume];

    [rows addObject:[PSSpecifier groupSpecifierWithName:@"素材"]];
    PSSpecifier *import = [PSSpecifier preferenceSpecifierNamed:@"导入素材" target:self set:nil get:nil
        detail:nil cell:PSButtonCell edit:nil];
    import.buttonAction = @selector(importMaterial:);
    [rows addObject:import];
    PSSpecifier *open = [PSSpecifier preferenceSpecifierNamed:@"打开素材路径" target:self set:nil get:nil
        detail:nil cell:PSButtonCell edit:nil];
    open.buttonAction = @selector(openMaterialFolder:);
    [rows addObject:open];

    // 2.69: the user asked for the diagnostics switch ON THIS PAGE. It writes the
    // same global key the rest of the tweak reads, so one switch covers both logs.
    PSSpecifier *diagGroup = [PSSpecifier groupSpecifierWithName:@"诊断"];
    [diagGroup setProperty:[NSString stringWithFormat:@"开启后日志写入 %@/settings-render.log", LMVSettingsVideoRoot] forKey:@"footerText"];
    [rows addObject:diagGroup];
    PSSpecifier *diag = [PSSpecifier preferenceSpecifierNamed:@"启用诊断日志" target:self
        set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [diag setProperty:@"DiagnosticsEnabled" forKey:@"key"];
    [diag setProperty:@NO forKey:@"default"];
    [rows addObject:diag];

    _specifiers = rows;
    return _specifiers;
}

- (id)enabled:(PSSpecifier *)specifier {
    NSNumber *value = nil;
    id stored = LMVSettingsRead([specifier propertyForKey:@"key"]);
    if ([stored isKindOfClass:NSNumber.class]) value = stored;
    return value ?: [specifier propertyForKey:@"default"] ?: @NO;
}

- (void)setEnabled:(id)value specifier:(PSSpecifier *)specifier {
    LMVSettingsWrite([specifier propertyForKey:@"key"], @([value boolValue]));
}

- (id)volume:(PSSpecifier *)specifier {
    id stored = LMVSettingsRead([specifier propertyForKey:@"key"]);
    return [stored isKindOfClass:NSNumber.class] ? stored : ([specifier propertyForKey:@"default"] ?: @0.5);
}

- (void)setVolume:(id)value specifier:(PSSpecifier *)specifier {
    double volume = [value doubleValue];
    if (volume < 0) volume = 0; if (volume > 1) volume = 1;
    LMVSettingsWrite([specifier propertyForKey:@"key"], @(volume));
}

// The material picker shared with the other channels scans the catalog root; for
// this page the list is the dedicated folder, so the rows are built here and the
// picker is used only as the thumbnail renderer.
- (NSArray<NSDictionary *> *)folderMaterials {
    NSMutableArray *rows = [NSMutableArray array];
    NSString *folder = LMVSettingsVideoRoot;
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSArray *files = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:folder error:nil]
        sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    for (NSString *name in files) {
        if (![@[@"mov", @"mp4", @"m4v"] containsObject:name.pathExtension.lowercaseString]) continue;
        NSMutableDictionary *row = [@{@"name": name.lastPathComponent, @"relative": name} mutableCopy];
        NSString *full = [folder stringByAppendingPathComponent:name];
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:full] options:nil]];
        generator.appliesPreferredTrackTransform = YES;
        generator.maximumSize = CGSizeMake(200, 200);
        CGImageRef image = [generator copyCGImageAtTime:CMTimeMake(1, 10) actualTime:NULL error:nil];
        if (image) { row[@"preview"] = [UIImage imageWithCGImage:image]; CGImageRelease(image); }
        [rows addObject:row];
    }
    return rows;
}

- (void)switchMaterial:(PSSpecifier *)specifier {
    if (self.presentedViewController) return;
    NSArray *rows = [self folderMaterials];
    if (!rows.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"还没有素材"
            message:[NSString stringWithFormat:@"把视频放进 %@，或点「导入素材」。", LMVSettingsVideoRoot]
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    NSString *selected = LMVSettingsRead(LMVSettingsVideoFileKey);
    LMVSettingsMaterialPicker *picker = [LMVSettingsMaterialPicker new];
    picker.selected = [selected isKindOfClass:NSString.class] ? selected : nil;
    picker.materials = rows;
    __weak typeof(self) weakSelf = self;
    picker.apply = ^(NSDictionary *row) {
        LMVSettingsWrite(LMVSettingsVideoFileKey, row[@"relative"]);
            [weakSelf reloadSpecifiers];
    };
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
}

// Import goes through the same Photos picker the other channels use, but the file
// is copied into THIS channel's folder - the user's path, not the shared library.
- (void)importMaterial:(PSSpecifier *)specifier {
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    config.filter = [PHPickerFilter videosFilter];
    config.selectionLimit = 1;
    config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result || ![result.itemProvider hasItemConformingToTypeIdentifier:@"public.movie"]) return;
    __weak typeof(self) weakSelf = self;
    [result.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
        NSError *copyError = error;
        NSString *name = nil;
        if (url && !copyError) {
            NSString *folder = LMVSettingsVideoRoot;
            [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *ext = url.pathExtension.length ? url.pathExtension : @"mov";
            name = [NSString stringWithFormat:@"设置视频-%@.%@", NSUUID.UUID.UUIDString, ext];
            NSString *destination = [folder stringByAppendingPathComponent:name];
            if (![NSFileManager.defaultManager copyItemAtPath:url.path toPath:destination error:&copyError]) name = nil;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (copyError || !name) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入失败"
                    message:copyError.localizedDescription ?: @"无法保存视频" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [weakSelf presentViewController:alert animated:YES completion:nil];
                return;
            }
            LMVSettingsWrite(LMVSettingsVideoFileKey, name);
                    [weakSelf reloadSpecifiers];
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入成功"
                message:[NSString stringWithFormat:@"已保存到 %@/%@", LMVSettingsVideoRoot, name]
                preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [weakSelf presentViewController:alert animated:YES completion:nil];
        });
    }];
}

- (void)openMaterialFolder:(PSSpecifier *)specifier {
    [NSFileManager.defaultManager createDirectoryAtPath:LMVSettingsVideoRoot withIntermediateDirectories:YES attributes:nil error:nil];
    // 2.79: open the folder directly (Filza / Files registers the folder scheme).
    NSURL *folder = [NSURL fileURLWithPath:LMVSettingsVideoRoot isDirectory:YES];
    UIApplication *app = UIApplication.sharedApplication;
    if ([app canOpenURL:folder]) { [app openURL:folder options:@{} completionHandler:nil]; return; }
    // Fallback: the file URL with the app's own scheme (Filza accepts this form).
    NSString *encoded = [LMVSettingsVideoRoot stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLPathAllowedCharacterSet];
    NSURL *filza = [NSURL URLWithString:[@"filza://" stringByAppendingString:encoded]];
    if (filza && [app canOpenURL:filza]) { [app openURL:filza options:@{} completionHandler:nil]; return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"素材路径"
        message:LMVSettingsVideoRoot preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end