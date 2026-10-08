#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>

#import "LMVImport.h"
static NSString * const LMVDirectory = @"/var/mobile/LockMessageVideo";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSArray<NSString *> *LMVTargets(void) { return @[@"Message", @"Options", @"Clear"]; }
static NSArray<NSString *> *LMVNames(void) { return @[@"消息", @"选项", @"清除"]; }
static void LMVNotify(void) {
    CFPreferencesAppSynchronize(kLMVPrefsID);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, NULL, YES);
}

@interface LMVPRootListController : PSListController <PHPickerViewControllerDelegate>
@property(nonatomic) BOOL materialBusy;
@end

@implementation LMVPRootListController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"锁屏背景视频";
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    _specifiers = [NSMutableArray new];
    NSArray *titles = @[@"切换背景素材", @"切换选项素材", @"切换清除素材"];
    SEL actions[] = {@selector(switchMessage:), @selector(switchOptions:), @selector(switchClear:)};
    for (NSUInteger i = 0; i < LMVTargets().count; i++) {
        [_specifiers addObject:[PSSpecifier groupSpecifierWithName:[LMVNames()[i] stringByAppendingString:@"背景"]]];
        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:[@"启用" stringByAppendingFormat:@"%@背景", LMVNames()[i]] target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
        [enabled setProperty:[LMVTargets()[i] stringByAppendingString:@"BackgroundEnabled"] forKey:@"key"];
        [enabled setProperty:@NO forKey:@"default"];
        [_specifiers addObject:enabled];
        PSSpecifier *choose = [PSSpecifier preferenceSpecifierNamed:titles[i] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        choose.buttonAction = actions[i];
        [_specifiers addObject:choose];
    }
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"素材库"]];
    PSSpecifier *import = [PSSpecifier preferenceSpecifierNamed:@"从相册导入视频" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    import.buttonAction = @selector(chooseVideo:);
    [import setProperty:@"ImportVideo" forKey:@"id"];
    [_specifiers addObject:import];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"所有视频重新压缩至 ≤5 MiB，原素材始终保留；无法压缩则提示失败"]];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"视频透明度"]];
    PSSpecifier *opacityEnabled = [PSSpecifier preferenceSpecifierNamed:@"启用视频透明度" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [opacityEnabled setProperty:@"VideoOpacityEnabled" forKey:@"key"];
    [opacityEnabled setProperty:@YES forKey:@"default"];
    [_specifiers addObject:opacityEnabled];
    PSSpecifier *opacity = [PSSpecifier preferenceSpecifierNamed:@"视频透明度" target:self set:@selector(setOpacity:specifier:) get:@selector(opacity:) detail:nil cell:PSSliderCell edit:nil];
    [opacity setProperty:@"VideoOpacity" forKey:@"key"];
    [opacity setProperty:@0.0 forKey:@"min"];
    [opacity setProperty:@1.0 forKey:@"max"];
    [opacity setProperty:@0.55 forKey:@"default"];
    [opacity setProperty:@YES forKey:@"showValue"];
    [opacity setProperty:@"VideoOpacitySlider" forKey:@"id"];
    [opacity setProperty:[self enabled:opacityEnabled] forKey:@"enabled"];
    [_specifiers addObject:opacity];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"素材路径"]];
    PSSpecifier *open = [PSSpecifier preferenceSpecifierNamed:@"打开素材路径" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    open.buttonAction = @selector(openMaterialPath:);
    [_specifiers addObject:open];
    PSSpecifier *clear = [PSSpecifier preferenceSpecifierNamed:@"清空原素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    clear.buttonAction = @selector(clearOriginals:);
    [clear setProperty:@"ClearOriginals" forKey:@"id"];
    [_specifiers addObject:clear];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"诊断"]];
    PSSpecifier *diagnostics = [PSSpecifier preferenceSpecifierNamed:@"启用诊断日志" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [diagnostics setProperty:@"DiagnosticsEnabled" forKey:@"key"];
    [diagnostics setProperty:@NO forKey:@"default"];
    [_specifiers addObject:diagnostics];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"默认关闭，仅开启后写入 shared-render.log；关闭不会删除已有日志"]];
    return _specifiers;
}
- (id)enabled:(PSSpecifier *)specifier {
    NSNumber *value = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], kLMVPrefsID);
    return value ?: [specifier propertyForKey:@"default"] ?: @NO;
}
- (void)setEnabled:(id)value specifier:(PSSpecifier *)specifier {
    CFPreferencesSetAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], (__bridge CFPropertyListRef)@([value boolValue]), kLMVPrefsID);
    LMVNotify();
    if ([[specifier propertyForKey:@"key"] isEqualToString:@"VideoOpacityEnabled"]) {
        for (PSSpecifier *slider in _specifiers) {
            if ([[slider propertyForKey:@"key"] isEqualToString:@"VideoOpacity"]) {
                [slider setProperty:@([value boolValue]) forKey:@"enabled"];
                [self reloadSpecifier:slider animated:NO];
                break;
            }
        }
    }
}
- (id)opacity:(PSSpecifier *)specifier {
    NSNumber *value = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("VideoOpacity"), kLMVPrefsID);
    if (!value) value = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("MessageBackgroundOpacity"), kLMVPrefsID);
    return @([value respondsToSelector:@selector(floatValue)] ? MAX(0.0, MIN(1.0, value.floatValue)) : 0.55);
}
- (void)setOpacity:(id)value specifier:(PSSpecifier *)specifier {
    NSNumber *opacity = @(MAX(0.0, MIN(1.0, [value floatValue])));
    CFPreferencesSetAppValue(CFSTR("VideoOpacity"), (__bridge CFPropertyListRef)opacity, kLMVPrefsID);
    LMVNotify();
}
- (void)showMaterialPath {
    if (!self.view.window || self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"素材路径" message:[LMVDirectory stringByAppendingString:@"/"] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制路径" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIPasteboard.generalPasteboard.string = [LMVDirectory stringByAppendingString:@"/"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)openMaterialPath:(PSSpecifier *)specifier {
    [[NSFileManager defaultManager] createDirectoryAtPath:LMVDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    // Filza's view route takes the absolute path, not a query parameter.
    // Public example: FouadRaheb/AppData ADHelper.m openDirectoryAtURL:.
    NSURLComponents *components = [NSURLComponents new];
    components.scheme = @"filza";
    components.host = @"view";
    components.path = [LMVDirectory stringByAppendingString:@"/"];
    NSURL *url = components.URL;
    UIApplication *application = UIApplication.sharedApplication;
    if (!url) { [self showMaterialPath]; return; }
    // Preference bundles run inside Settings: its own query whitelist can hide
    // an installed handler. Probe defensively, but let openURL confirm absence.
    BOOL advertised = [application canOpenURL:url];
    (void)advertised;
    __weak typeof(self) weakSelf = self;
    [application openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf showMaterialPath]; });
    }];
}
- (void)setMaterialBusy:(BOOL)busy {
    _materialBusy = busy;
    for (PSSpecifier *item in _specifiers) {
        NSString *identifier = [item propertyForKey:@"id"];
        if ([identifier isEqualToString:@"ImportVideo"] || [identifier isEqualToString:@"ClearOriginals"]) {
            [item setProperty:@(!busy) forKey:@"enabled"];
            [self reloadSpecifier:item animated:NO];
        }
    }
}
- (void)clearOriginals:(PSSpecifier *)specifier {
    if (self.materialBusy || self.presentedViewController) return;
    UIAlertController *confirm = [UIAlertController alertControllerWithTitle:@"清空原素材？" message:@"将永久删除 /var/mobile/LockMessageVideo/原素材/ 中的原视频，无法撤销。不会删除素材库或当前选中的压缩视频。子目录及符号链接不会删除。" preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        if (self.materialBusy) return;
        self.materialBusy = YES;
        [self dismissViewControllerAnimated:YES completion:^{
        dispatch_async(LMVMaterialQueue(), ^{
            NSError *error = LMVClearOriginals();
            dispatch_async(dispatch_get_main_queue(), ^{
                self.materialBusy = NO;
                UIAlertController *result = [UIAlertController alertControllerWithTitle:error ? @"清理未完成" : @"清空成功" message:error.localizedDescription ?: @"原素材已清空，素材库和当前选中视频保持不变。" preferredStyle:UIAlertControllerStyleAlert];
                [result addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:result animated:YES completion:nil];
            });
        });
        }];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}
- (void)showError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败" message:error.localizedDescription ?: @"无法复制视频" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)presentMenu:(UIAlertController *)menu {
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.view;
    menu.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
    [self presentViewController:menu animated:YES completion:nil];
}
- (void)selectFile:(NSString *)file target:(NSString *)target {
    NSString *key = [target stringByAppendingString:@"Video"];
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)file, kLMVPrefsID);
    LMVNotify();
}
- (void)switchTarget:(NSString *)target {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *library = [LMVDirectory stringByAppendingPathComponent:@"library"];
    NSArray *files = [[fm contentsOfDirectoryAtPath:library error:nil] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"选择素材" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSString *key = [target stringByAppendingString:@"Video"];
    NSString *selected = (__bridge_transfer NSString *)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kLMVPrefsID);
    if (![selected isKindOfClass:NSString.class]) selected = nil;
    if ([fm fileExistsAtPath:[LMVDirectory stringByAppendingPathComponent:@"message.mov"]]) {
        BOOL current = [selected isEqualToString:@"message.mov"] || (!selected && [target isEqualToString:@"Message"]);
        [menu addAction:[UIAlertAction actionWithTitle:current ? @"原消息视频（当前）" : @"原消息视频" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self selectFile:@"message.mov" target:target]; }]];
    }
    for (NSString *name in files) {
        if (![@[@"mov", @"mp4", @"m4v"] containsObject:name.pathExtension.lowercaseString]) continue;
        NSString *relative = [@"library" stringByAppendingPathComponent:name];
        NSString *title = name.stringByDeletingPathExtension;
        if ([selected isEqualToString:relative]) title = [title stringByAppendingString:@"（当前）"];
        [menu addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self selectFile:relative target:target]; }]];
    }
    if (menu.actions.count == 0) menu.message = @"素材库为空";
    [menu addAction:[UIAlertAction actionWithTitle:@"无素材" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self selectFile:@"" target:target]; }]];
    [self presentMenu:menu];
}
- (void)switchMessage:(PSSpecifier *)specifier { [self switchTarget:@"Message"]; }
- (void)switchOptions:(PSSpecifier *)specifier { [self switchTarget:@"Options"]; }
- (void)switchClear:(PSSpecifier *)specifier { [self switchTarget:@"Clear"]; }
- (void)chooseVideo:(PSSpecifier *)specifier {
    if (self.materialBusy) return;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    config.filter = [PHPickerFilter videosFilter];
    config.selectionLimit = 1;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    PHPickerResult *result = results.firstObject;
    if (!result || ![result.itemProvider hasItemConformingToTypeIdentifier:@"public.movie"]) return;
    self.materialBusy = YES;
    [result.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
        NSError *copyError = error;
        NSString *relative = nil;
        if (!url && !copyError) copyError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        if (url && !copyError) {
            relative = LMVImportMovie(url, &copyError);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.materialBusy = NO;
            if (copyError) [self showError:copyError];
            else {
                for (NSString *target in LMVTargets()) {
                    NSString *key = [target stringByAppendingString:@"Video"];
                    id selected = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kLMVPrefsID);
                    BOOL legacyMessage = !selected && [target isEqualToString:@"Message"] && [[NSFileManager defaultManager] fileExistsAtPath:[LMVDirectory stringByAppendingPathComponent:@"message.mov"]];
                    if (!selected && !legacyMessage) CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)relative, kLMVPrefsID);
                }
                LMVNotify();
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入成功" message:[NSString stringWithFormat:@"已重新编码为无音轨 H.264 并验证，保存到素材库：%@\n原件保留在 /var/mobile/LockMessageVideo/原素材/", relative] preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}
@end
