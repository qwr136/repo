#include <string.h>
#include <math.h>
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>

#import "LMVImport.h"
#import "LMVMaterialPicker.h"
static NSString * const LMVDirectory = @"/var/mobile/LockMessageVideo";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSArray<NSString *> *LMVTargets(void) { return @[@"Message", @"LockScreen", @"Options", @"Clear"]; }
static NSArray<NSString *> *LMVNames(void) { return @[@"消息", @"锁屏", @"选项", @"清除"]; }
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
    NSArray *titles = @[@"切换背景素材", @"切换锁屏素材", @"切换选项素材", @"切换清除素材"];
    SEL actions[] = {@selector(switchMessage:), @selector(switchLockScreen:), @selector(switchOptions:), @selector(switchClear:)};
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
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"所有视频重新压缩至 ≤5 MiB；临时原素材仅在导入期间存在，无法压缩则提示失败"]];
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
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"通知堆叠阴影"]];
    PSSpecifier *stackEnabled = [PSSpecifier preferenceSpecifierNamed:@"降低通知堆叠阴影" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [stackEnabled setProperty:@"StackShadowEnabled" forKey:@"key"];
    [stackEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:stackEnabled];
    PSSpecifier *stackOpacity = [PSSpecifier preferenceSpecifierNamed:@"通知堆叠阴影透明度" target:self set:@selector(setStackShadowOpacity:specifier:) get:@selector(stackShadowOpacity:) detail:nil cell:PSSliderCell edit:nil];
    [stackOpacity setProperty:@"StackShadowOpacity" forKey:@"key"];
    [stackOpacity setProperty:@0.0 forKey:@"min"];
    [stackOpacity setProperty:@1.0 forKey:@"max"];
    [stackOpacity setProperty:@0.35 forKey:@"default"];
    [stackOpacity setProperty:@YES forKey:@"showValue"];
    [stackOpacity setProperty:@"StackShadowOpacitySlider" forKey:@"id"];
    [stackOpacity setProperty:[self enabled:stackEnabled] forKey:@"enabled"];
    [_specifiers addObject:stackOpacity];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"默认关闭；0 隐藏，1 保留原始阴影，0.35 保留原始透明度的 35%。仅调整系统通知堆叠遮罩"]];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"素材路径"]];
    PSSpecifier *open = [PSSpecifier preferenceSpecifierNamed:@"打开素材路径" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    open.buttonAction = @selector(openMaterialPath:);
    [_specifiers addObject:open];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"诊断"]];
    PSSpecifier *diagnostics = [PSSpecifier preferenceSpecifierNamed:@"启用诊断日志" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [diagnostics setProperty:@"DiagnosticsEnabled" forKey:@"key"];
    [diagnostics setProperty:@NO forKey:@"default"];
    [_specifiers addObject:diagnostics];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"默认关闭，仅开启后写入 shared-render.log；关闭不会删除已有日志"]];
    // This controller owns all rows. Never inherit plist controller/action routes.
    for (PSSpecifier *row in _specifiers) {
        if (row.cellType != PSButtonCell) continue;
        row.target = self;
        row.detailControllerClass = Nil;
        row.controllerLoadAction = NULL;
        for (NSString *key in @[@"action", @"detail", @"controller", @"loadAction", @"bundle", @"lazy-bundle", @"isController"])
            [row removePropertyForKey:key];
        NSAssert(row.buttonAction && [self respondsToSelector:row.buttonAction], @"Invalid settings button: %@", row.name);
    }
    return _specifiers;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *row = [self specifierAtIndexPath:indexPath];
    if (row.cellType == PSButtonCell) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        if ([[row propertyForKey:@"enabled"] isEqual:@NO]) return;
        SEL action = row.buttonAction;
        // Call only our own one-specifier button handlers, never controllerForSpecifier:.
        NSMethodSignature *signature = action ? [self methodSignatureForSelector:action] : nil;
        if (row.target != self || !signature || signature.numberOfArguments != 3 || strcmp(signature.methodReturnType, @encode(void)) != 0) return;
        void (*invoke)(id, SEL, PSSpecifier *) = (void (*)(id, SEL, PSSpecifier *))[self methodForSelector:action];
        invoke(self, action, row);
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}
- (id)enabled:(PSSpecifier *)specifier {
    NSNumber *value = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], kLMVPrefsID);
    return value ?: [specifier propertyForKey:@"default"] ?: @NO;
}
- (void)setEnabled:(id)value specifier:(PSSpecifier *)specifier {
    CFPreferencesSetAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], (__bridge CFPropertyListRef)@([value boolValue]), kLMVPrefsID);
    LMVNotify();
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *sliderKey = [key isEqualToString:@"VideoOpacityEnabled"] ? @"VideoOpacity" :
        ([key isEqualToString:@"StackShadowEnabled"] ? @"StackShadowOpacity" : nil);
    if (sliderKey) {
        for (PSSpecifier *slider in _specifiers) {
            if ([[slider propertyForKey:@"key"] isEqualToString:sliderKey]) {
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
- (id)stackShadowOpacity:(PSSpecifier *)specifier {
    NSNumber *value = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("StackShadowOpacity"), kLMVPrefsID);
    double opacity = [value respondsToSelector:@selector(doubleValue)] ? value.doubleValue : 0.35;
    return @(isfinite(opacity) ? MAX(0.0, MIN(1.0, opacity)) : 0.35);
}
- (void)setStackShadowOpacity:(id)value specifier:(PSSpecifier *)specifier {
    double opacity = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : 0.35;
    NSNumber *clamped = @(isfinite(opacity) ? MAX(0.0, MIN(1.0, opacity)) : 0.35);
    CFPreferencesSetAppValue(CFSTR("StackShadowOpacity"), (__bridge CFPropertyListRef)clamped, kLMVPrefsID);
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
        if ([identifier isEqualToString:@"ImportVideo"]) {
            [item setProperty:@(!busy) forKey:@"enabled"];
            [self reloadSpecifier:item animated:NO];
        }
    }
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
- (void)selectFile:(NSString *)file name:(NSString *)name target:(NSString *)target {
    NSString *key = [target stringByAppendingString:@"Video"];
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)file, kLMVPrefsID);
    LMVNotify();
    NSDictionary *titles = @{@"Message": @"消息背景", @"Options": @"选项背景", @"Clear": @"清除背景", @"LockScreen": @"锁屏背景"};
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已应用素材" message:[NSString stringWithFormat:@"%@ 已切换为 %@", titles[target], name] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)switchTarget:(NSString *)target {
    if (self.presentedViewController) return;
    NSString *key = [target stringByAppendingString:@"Video"];
    id selected = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kLMVPrefsID);
    NSDictionary *legacy = @{@"Message": @"message.mov", @"Options": @"options.mov", @"Clear": @"clear.mov"};
    if (![selected isKindOfClass:NSString.class]) selected = legacy[target] ?: @"";
    LMVMaterialPicker *picker = [LMVMaterialPicker new];
    picker.selected = selected;
    __weak typeof(self) weakSelf = self;
    picker.apply = ^(NSString *relative, NSString *name) { [weakSelf selectFile:relative name:name target:target]; };
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
}
- (void)switchMessage:(PSSpecifier *)specifier { [self switchTarget:@"Message"]; }
- (void)switchLockScreen:(PSSpecifier *)specifier { [self switchTarget:@"LockScreen"]; }
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
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入成功" message:[NSString stringWithFormat:@"已重新编码为无音轨 H.264 并验证，保存到素材库：%@\n导入临时原素材已清理。", relative] preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}
@end
