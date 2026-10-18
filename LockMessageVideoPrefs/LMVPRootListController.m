#include <string.h>
#include <math.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>

#import "LMVImport.h"
#import "LMVMaterialPicker.h"
#import "../LMVEasterImageSettings.h"
#import "../LMVPaths.h"
#import "../LMVTextColorPicker.h"
#define LMVDirectory LMVUserStorageRoot()
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSArray<NSString *> *LMVTargets(void) { return @[@"Message", @"Options", @"Clear", @"LockScreen", @"Desktop"]; }
static NSArray<NSString *> *LMVNames(void) { return @[@"消息", @"选项", @"清除", @"锁屏", @"桌面"]; }
static BOOL LMVMaterialTargetAllowed(NSString *target) {
    if (![target isKindOfClass:NSString.class] || !target.length) return NO;
    return [LMVTargets() containsObject:target] || [@[@"ControlCenterDark", @"ControlCenterLight", @"HomeMenu", @"SquidPanel", @"AT", @"CV", @"Myrtle"] containsObject:target];
}
static void LMVNotify(void) {
    CFPreferencesAppSynchronize(kLMVPrefsID);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, NULL, YES);
}

@interface LMVPRootListController : PSListController <PHPickerViewControllerDelegate>
@property(nonatomic) BOOL materialBusy;
// 1.88: the swatch that shows the current CopyVault text colour. Holding a weak
// reference means the picker can repaint it directly instead of relying on
// -reloadSpecifier: (which kept the old colour) or on a private cell lookup.
@property(nonatomic,weak) UIView *cvTextColorDot;
// 1.88: the very table we are the delegate of - captured in -willDisplayCell: so
// the refresh below never has to guess how to reach it.
@property(nonatomic,weak) UITableView *cvTextColorTable;
@end

@implementation LMVPRootListController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"背景视频";
}
- (void)appendAudioForTarget:(NSString *)target title:(NSString *)title {
    NSString *volumeKey = [target stringByAppendingString:@"Volume"];
    PSSpecifier *sound = [PSSpecifier preferenceSpecifierNamed:[title stringByAppendingString:@"声音"] target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [sound setProperty:[target stringByAppendingString:@"SoundEnabled"] forKey:@"key"];
    [sound setProperty:@NO forKey:@"default"];
    [sound setProperty:volumeKey forKey:@"audioVolumeKey"];
    [_specifiers addObject:sound];
    PSSpecifier *volume = [PSSpecifier preferenceSpecifierNamed:[title isEqualToString:@"播放"] ? @"声音音量（%）" : [title stringByAppendingString:@"音量（%）"] target:self set:@selector(setVolume:specifier:) get:@selector(volume:) detail:nil cell:PSSliderCell edit:nil];
    [volume setProperty:volumeKey forKey:@"key"];
    [volume setProperty:@0.0 forKey:@"min"];
    [volume setProperty:@100.0 forKey:@"max"];
    // Defaults/preferences are normalized; only this slider's display is percent.
    [volume setProperty:@0.5 forKey:@"default"];
    [volume setProperty:@YES forKey:@"showValue"];
    [volume setProperty:[volumeKey stringByAppendingString:@"Slider"] forKey:@"id"];
    [volume setProperty:[self enabled:sound] forKey:@"enabled"];
    [_specifiers addObject:volume];
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    _specifiers = [NSMutableArray new];
    // 0.0.114: the master switch sits at the very top. It gates every channel
    // (five targets, control centre, desktop, home-menu and the floating egg).
    // Its stored default is ON and an absent key reads as ON in the tweak, so
    // upgrading never changes an existing configuration.
    PSSpecifier *globalGroup = [PSSpecifier groupSpecifierWithName:@"总开关"];
    [globalGroup setProperty:@"关闭后所有通道与悬浮球立即停止；各单项开关的设置会保留。" forKey:@"footerText"];
    [_specifiers addObject:globalGroup];
    PSSpecifier *global = [PSSpecifier preferenceSpecifierNamed:@"启用全局开关" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [global setProperty:@"GlobalEnabled" forKey:@"key"];
    [global setProperty:@YES forKey:@"default"];
    [_specifiers addObject:global];
    NSArray *titles = @[@"切换背景素材", @"切换选项素材", @"切换清除素材", @"切换锁屏素材", @"切换桌面素材"];
    SEL actions[] = {@selector(switchMessage:), @selector(switchOptions:), @selector(switchClear:), @selector(switchLockScreen:), @selector(switchDesktop:)};
    for (NSUInteger i = 0; i < LMVTargets().count; i++) {
        [_specifiers addObject:[PSSpecifier groupSpecifierWithName:[LMVNames()[i] stringByAppendingString:@"背景"]]];
        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:[@"启用" stringByAppendingFormat:@"%@背景", LMVNames()[i]] target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
        [enabled setProperty:[LMVTargets()[i] stringByAppendingString:@"BackgroundEnabled"] forKey:@"key"];
        [enabled setProperty:@NO forKey:@"default"];
        [_specifiers addObject:enabled];
        PSSpecifier *choose = [PSSpecifier preferenceSpecifierNamed:titles[i] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        choose.buttonAction = actions[i];
        [_specifiers addObject:choose];
        [self appendAudioForTarget:LMVTargets()[i] title:@"播放"];
    }
    PSSpecifier *controlCenter = [PSSpecifier groupSpecifierWithName:@"控制中心背景"];
    [controlCenter setProperty:@"按系统深浅色模式自动选择素材；未选择对应模式素材时保留系统背景。" forKey:@"footerText"];
    [_specifiers addObject:controlCenter];
    PSSpecifier *controlCenterEnabled = [PSSpecifier preferenceSpecifierNamed:@"启用控制中心背景" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [controlCenterEnabled setProperty:@"ControlCenterBackgroundEnabled" forKey:@"key"];
    [controlCenterEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:controlCenterEnabled];
    PSSpecifier *controlCenterDark = [PSSpecifier preferenceSpecifierNamed:@"切换深色模式素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    controlCenterDark.buttonAction = @selector(switchControlCenterDark:);
    [_specifiers addObject:controlCenterDark];
    [self appendAudioForTarget:@"ControlCenterDark" title:@"深色模式"];
    PSSpecifier *controlCenterLight = [PSSpecifier preferenceSpecifierNamed:@"切换浅色模式素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    controlCenterLight.buttonAction = @selector(switchControlCenterLight:);
    [_specifiers addObject:controlCenterLight];
    [self appendAudioForTarget:@"ControlCenterLight" title:@"浅色模式"];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"桌面长按菜单视频背景"]];
    PSSpecifier *homeMenuEnabled = [PSSpecifier preferenceSpecifierNamed:@"桌面长按菜单视频背景" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [homeMenuEnabled setProperty:@"HomeMenuBackgroundEnabled" forKey:@"key"];
    [homeMenuEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:homeMenuEnabled];
    PSSpecifier *homeMenuMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换长按菜单素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    homeMenuMaterial.buttonAction = @selector(switchHomeMenu:);
    [homeMenuMaterial setProperty:@"HomeMenuMaterial" forKey:@"id"];
    [_specifiers addObject:homeMenuMaterial];
    [self appendAudioForTarget:@"HomeMenu" title:@"播放"];
    // 1.22: the SquidGesturePro panel background, right below the long-press menu
    // channel (same switch / material / sound / volume layout).
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"鱿鱼面板背景视频"]];
    PSSpecifier *squidPanelEnabled = [PSSpecifier preferenceSpecifierNamed:@"鱿鱼面板背景视频" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [squidPanelEnabled setProperty:@"SquidPanelBackgroundEnabled" forKey:@"key"];
    [squidPanelEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:squidPanelEnabled];
    PSSpecifier *squidPanelMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换视频" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    squidPanelMaterial.buttonAction = @selector(switchSquidPanel:);
    [squidPanelMaterial setProperty:@"SquidPanelMaterial" forKey:@"id"];
    [_specifiers addObject:squidPanelMaterial];
    [self appendAudioForTarget:@"SquidPanel" title:@"播放"];
    // 1.26: the AppTools (AT) pop-up background, right below the Squid panel
    // channel (same switch / material / sound / volume layout). This release
    // stores the settings and diagnoses the pop-up; the video mount follows.
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"AT 背景视频"]];
    PSSpecifier *atEnabled = [PSSpecifier preferenceSpecifierNamed:@"AT 背景视频" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [atEnabled setProperty:@"ATBackgroundEnabled" forKey:@"key"];
    [atEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:atEnabled];
    PSSpecifier *atMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换 AT 素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    atMaterial.buttonAction = @selector(switchAT:);
    [atMaterial setProperty:@"ATMaterial" forKey:@"id"];
    [_specifiers addObject:atMaterial];
    [self appendAudioForTarget:@"AT" title:@"播放"];
    // 1.43: the CopyVault clipboard panel background, right below the AT channel
    // (same switch / material / sound / volume layout).
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"CopyVault 面板背景视频"]];
    PSSpecifier *cvEnabled = [PSSpecifier preferenceSpecifierNamed:@"CopyVault 面板背景视频" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [cvEnabled setProperty:@"CVBackgroundEnabled" forKey:@"key"];
    [cvEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:cvEnabled];
    PSSpecifier *cvMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换 CopyVault 素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    cvMaterial.buttonAction = @selector(switchCV:);
    [cvMaterial setProperty:@"CVMaterial" forKey:@"id"];
    [_specifiers addObject:cvMaterial];
    [self appendAudioForTarget:@"CV" title:@"播放"];
    // 1.83: CopyVault text colour - one row with a round swatch on the right;
    // tapping it opens the shared picker (the Easter panel uses the same one).
    PSSpecifier *cvText = [PSSpecifier preferenceSpecifierNamed:@"文字颜色" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    cvText.buttonAction = @selector(openCVTextColor:);
    [cvText setProperty:@"CVTextColor" forKey:@"id"];
    [_specifiers addObject:cvText];
    // 1.77: the Myrtle panel background (the App Library / search surface that the
    // Myrtle windows carry). Same switch / material / sound / volume layout as CV.
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"Myrtle 面板背景视频"]];
    PSSpecifier *myrtleEnabled = [PSSpecifier preferenceSpecifierNamed:@"Myrtle 面板背景视频" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [myrtleEnabled setProperty:@"MyrtleBackgroundEnabled" forKey:@"key"];
    [myrtleEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:myrtleEnabled];
    PSSpecifier *myrtleMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换 Myrtle 素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    myrtleMaterial.buttonAction = @selector(switchMyrtle:);
    [myrtleMaterial setProperty:@"MyrtleMaterial" forKey:@"id"];
    [_specifiers addObject:myrtleMaterial];
    [self appendAudioForTarget:@"Myrtle" title:@"播放"];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"小彩蛋"]];
    PSSpecifier *eggEnabled = [PSSpecifier preferenceSpecifierNamed:@"启用小彩蛋" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [eggEnabled setProperty:@"EasterEggEnabled" forKey:@"key"];
    [eggEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:eggEnabled];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"小彩蛋显示设置"]];
    PSSpecifier *eggImage = [PSSpecifier preferenceSpecifierNamed:@"显示场景与图片旋转" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    eggImage.buttonAction = @selector(openEaster:);
    [eggImage setProperty:@"EasterEggImageSettings" forKey:@"id"];
    [_specifiers addObject:eggImage];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"素材库"]];
    [(PSSpecifier *)_specifiers.lastObject setProperty:@"保留相册提供的当前原片，不重新编码、缩放或降低帧率，音轨保留；支持 MOV、MP4、M4V，单个视频不超过 512 MiB，验证可播放后加入素材库。" forKey:@"footerText"];
    PSSpecifier *import = [PSSpecifier preferenceSpecifierNamed:@"从相册导入视频" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    import.buttonAction = @selector(chooseVideo:);
    [import setProperty:@"ImportVideo" forKey:@"id"];
    [_specifiers addObject:import];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"消息、选项、清除视频透明度"]];
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
        if (row.target != self || !signature || signature.numberOfArguments != 3 || strcmp(signature.methodReturnType, @encode(void)) != 0 || [signature getArgumentTypeAtIndex:2][0] != '@') return;
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
- (void)openEaster:(PSSpecifier *)specifier {
    if (self.presentedViewController) return;
    LMVEasterImageSettings *panel = [LMVEasterImageSettings new];
    __weak LMVEasterImageSettings *weakPanel = panel;
    panel.close = ^{ [weakPanel dismissViewControllerAnimated:YES completion:nil]; };
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:panel] animated:YES completion:nil];
}
// 1.83: PSButtonCell keeps the tap routing; the round swatch is painted on the
// cell here so no private cell subclass (and no extra Preferences header) is needed.
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    UIView *existing = [cell.contentView viewWithTag:0x5A2C];
    if (![[specifier propertyForKey:@"id"] isEqualToString:@"CVTextColor"]) {
        // 1.88: a recycled cell must not carry the swatch onto an unrelated row.
        [existing removeFromSuperview];
        if (self.cvTextColorDot == existing) self.cvTextColorDot = nil;
        return;
    }
    UIView *dot = existing;
    if (!dot) {
        dot = [UIView new];
        dot.tag = 0x5A2C;
        dot.userInteractionEnabled = NO;
        dot.layer.borderWidth = 1;
        dot.layer.borderColor = [UIColor separatorColor].CGColor;
        [cell.contentView addSubview:dot];
    }
    // 1.88: keep the swatch addressable so a pick can repaint it in place.
    self.cvTextColorTable = tableView;
    self.cvTextColorDot = dot;
    dot.backgroundColor = LMVTextColorCurrent() ?: UIColor.whiteColor;
    CGFloat size = 18;
    dot.frame = CGRectMake(cell.contentView.bounds.size.width - size - 18,
                           (cell.contentView.bounds.size.height - size) / 2, size, size);
    dot.layer.cornerRadius = size / 2;
}
// 1.88: repaint the swatch from disk without touching the row's cell. The old
// path went through -reloadSpecifier: (which kept showing the stale colour) and
// through the private -cellForSpecifier: lookup (which could return nothing), so
// closing the picker left the dot on the previous colour. Now the picker holds a
// weak reference to the very view it has to update, with a visible-cell scan and
// a last-resort table reload behind it.
- (void)refreshCVTextColorDot {
    UIColor *color = LMVTextColorCurrent() ?: UIColor.whiteColor;
    UIView *dot = self.cvTextColorDot;
    if (dot) {
        dot.backgroundColor = color;
        return;
    }
    for (UITableViewCell *cell in (self.cvTextColorTable ?: self.table).visibleCells) {
        UIView *found = [cell.contentView viewWithTag:0x5A2C];
        if (!found) continue;
        self.cvTextColorDot = found;
        found.backgroundColor = color;
        return;
    }
    [(self.cvTextColorTable ?: self.table) reloadData];
}
- (void)openCVTextColor:(PSSpecifier *)specifier {
    if (self.presentedViewController) return;
    LMVTextColorPicker *picker = [LMVTextColorPicker new];
    picker.modalPresentationStyle = UIModalPresentationPageSheet;
    __weak LMVPRootListController *weakSelf = self;
    // Every drag, grid tap and preset goes through here - paint immediately.
    picker.onChange = ^(UIColor *color) {
        [weakSelf refreshCVTextColorDot];
    };
    // ...and once more after the sheet has left, when the list is laid out again.
    picker.onDismiss = ^{
        [weakSelf refreshCVTextColorDot];
    };
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)setEnabled:(id)value specifier:(PSSpecifier *)specifier {
    CFPreferencesSetAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], (__bridge CFPropertyListRef)@([value boolValue]), kLMVPrefsID);
    LMVNotify();
    NSString *key = [specifier propertyForKey:@"key"];
    NSString *sliderKey = [key isEqualToString:@"VideoOpacityEnabled"] ? @"VideoOpacity" : [specifier propertyForKey:@"audioVolumeKey"];
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
- (id)volume:(PSSpecifier *)specifier {
    id value = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], kLMVPrefsID);
    double raw = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0.5;
    double volume = isfinite(raw) ? MAX(0.0, MIN(1.0, raw)) : 0.5;
    return @(volume * 100.0);
}
- (void)setVolume:(id)value specifier:(PSSpecifier *)specifier {
    double raw = [value isKindOfClass:NSNumber.class] ? [value doubleValue] / 100.0 : 0.5;
    double volume = isfinite(raw) ? MAX(0.0, MIN(1.0, raw)) : 0.5;
    CFPreferencesSetAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], (__bridge CFPropertyListRef)@(volume), kLMVPrefsID);
    LMVNotify();
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
    if (!LMVMaterialTargetAllowed(target)) return;
    NSString *key = [target stringByAppendingString:@"Video"];
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)file, kLMVPrefsID);
    LMVNotify();
    NSDictionary *titles = @{@"Message": @"消息背景", @"Options": @"选项背景", @"Clear": @"清除背景", @"LockScreen": @"锁屏背景", @"Desktop": @"桌面背景", @"ControlCenterDark": @"控制中心深色背景", @"ControlCenterLight": @"控制中心浅色背景", @"HomeMenu": @"桌面长按菜单视频背景", @"SquidPanel": @"右一·右上滑面板背景视频", @"AT": @"AT 背景视频", @"CV": @"CopyVault 面板背景视频", @"Myrtle": @"Myrtle 面板背景视频"};
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已应用素材" message:[NSString stringWithFormat:@"%@ 已切换为 %@", titles[target], name] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)switchTarget:(NSString *)target {
    if (self.presentedViewController || !LMVMaterialTargetAllowed(target)) return;
    NSString *key = [target stringByAppendingString:@"Video"];
    id selected = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kLMVPrefsID);
    NSDictionary *legacy = @{@"Message": @"message.mov", @"Options": @"options.mov", @"Clear": @"clear.mov", @"LockScreen": @"", @"Desktop": @"", @"ControlCenterDark": @"", @"ControlCenterLight": @"", @"HomeMenu": @"", @"SquidPanel": @"", @"AT": @"", @"CV": @"", @"Myrtle": @""};
    if (![selected isKindOfClass:NSString.class]) selected = legacy[target] ?: @"";
    LMVMaterialPicker *picker = [LMVMaterialPicker new];
    picker.selected = selected;
    __weak typeof(self) weakSelf = self;
    picker.apply = ^(NSString *relative, NSString *name) { [weakSelf selectFile:relative name:name target:target]; };
    [self presentViewController:[[UINavigationController alloc] initWithRootViewController:picker] animated:YES completion:nil];
}
- (void)switchMessage:(PSSpecifier *)specifier { [self switchTarget:@"Message"]; }
- (void)switchOptions:(PSSpecifier *)specifier { [self switchTarget:@"Options"]; }
- (void)switchClear:(PSSpecifier *)specifier { [self switchTarget:@"Clear"]; }
- (void)switchLockScreen:(PSSpecifier *)specifier { [self switchTarget:@"LockScreen"]; }
- (void)switchDesktop:(PSSpecifier *)specifier { [self switchTarget:@"Desktop"]; }
- (void)switchControlCenterDark:(PSSpecifier *)specifier { [self switchTarget:@"ControlCenterDark"]; }
- (void)switchControlCenterLight:(PSSpecifier *)specifier { [self switchTarget:@"ControlCenterLight"]; }
- (void)switchHomeMenu:(PSSpecifier *)specifier { [self switchTarget:@"HomeMenu"]; }
- (void)switchSquidPanel:(PSSpecifier *)specifier { [self switchTarget:@"SquidPanel"]; }
// 1.50: "认领刚用过的面板" - the panel's content says nothing about which gesture opened
// it, so this is the user's word on it: the panel they were just looking at is bound
// to the gesture they pick (the kernel reads the slot + token on its next refresh).

- (void)switchAT:(PSSpecifier *)specifier { [self switchTarget:@"AT"]; }
- (void)switchCV:(PSSpecifier *)specifier { [self switchTarget:@"CV"]; }
- (void)switchMyrtle:(PSSpecifier *)specifier { [self switchTarget:@"Myrtle"]; }
- (void)chooseVideo:(PSSpecifier *)specifier {
    if (self.materialBusy) return;
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
                // Only the three message targets receive an initial selection after import.
                for (NSString *target in @[@"Message", @"Options", @"Clear"]) {
                    NSString *key = [target stringByAppendingString:@"Video"];
                    id selected = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kLMVPrefsID);
                    BOOL legacyMessage = !selected && [target isEqualToString:@"Message"] && [[NSFileManager defaultManager] fileExistsAtPath:[LMVDirectory stringByAppendingPathComponent:@"message.mov"]];
                    if (!selected && !legacyMessage) CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)relative, kLMVPrefsID);
                }
                LMVNotify();
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入成功" message:[NSString stringWithFormat:@"已验证原视频并按原片字节保存到素材库：%@\n保留画质、帧率与音轨，未重新编码。", relative] preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}
@end
