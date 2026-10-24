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
#import "LMVTuneController.h"
#import "LMVTuneListController.h"
#import "../LMVPanelTuning.h"
#import "../LMVEasterImageSettings.h"
#import "../LMVPaths.h"
#import "../LMVTextColorPicker.h"
#define LMVDirectory LMVUserStorageRoot()
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSArray<NSString *> *LMVTargets(void) { return @[@"Message", @"Options", @"Clear", @"LockScreen", @"Desktop"]; }
static NSArray<NSString *> *LMVNames(void) { return @[@"消息", @"选项", @"清除", @"锁屏", @"桌面"]; }
static BOOL LMVMaterialTargetAllowed(NSString *target) {
    if (![target isKindOfClass:NSString.class] || !target.length) return NO;
    return [LMVTargets() containsObject:target] || [@[@"ControlCenterDark", @"ControlCenterLight", @"HomeMenu", @"SquidPanel", @"AT", @"CV", @"Myrtle", @"PA", @"GS", @"CCBorder", @"CopyLogX"] containsObject:target];
}
// 3.05: one notification per channel. A global one wakes all thirteen channels, and
// switching the CopyLogX material made the desktop reload its own asset (perf desktop
// max=1732ms for an unrelated write). nil = a genuinely global write.
static void LMVNotifyFor(NSString *target) {
    CFPreferencesAppSynchronize(kLMVPrefsID);
    NSString *name = target.length
        ? [NSString stringWithFormat:@"com.minis.lockmessagevideo/preferencesChanged.%@", target]
        : @"com.minis.lockmessagevideo/preferencesChanged";
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge CFStringRef)name, NULL, NULL, YES);
}
static void LMVNotify(void) { LMVNotifyFor(nil); }
// A switch/slider row carries a key like "GSBackgroundEnabled"; the channel id is the
// prefix. Anything that does not match falls back to the global write, which is always
// safe - it just costs the full sweep.
static NSString *LMVTargetForPrefKey(NSString *key) {
    if (![key isKindOfClass:NSString.class] || !key.length) return nil;
    for (NSString *target in @[@"GS",@"CopyLogX",@"CCBorder",@"HomeMenu",@"SquidPanel",@"AT",@"CV",@"Myrtle",@"PA",@"Desktop",@"LockScreen"]) {
        if ([key hasPrefix:target]) return target;
    }
    return nil;
}

@interface LMVPRootListController : PSListController <PHPickerViewControllerDelegate>
@property(nonatomic) BOOL materialBusy;
// 1.88: the very table we are the delegate of - captured in -willDisplayCell: so
// a repaint never has to guess how to reach it (PSListController has `table`,
// never `tableView`, which is what used to crash Settings).
@property(nonatomic,weak) UITableView *cvTextColorTable;
// 2.56: the name painter is shared by -willDisplayCell: and the immediate repaint
// after a pick, so both paths cannot drift apart.
- (void)paintMaterialName:(NSString *)materialID inCell:(UITableViewCell *)cell;
- (void)refreshMaterialRows;
@end

@implementation LMVPRootListController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"锁屏背景视频";
}
// 2.52: the material name on a row is painted in -willDisplayCell:, which UIKit only
// calls when a row scrolls into view or is reloaded. Picking a material, renaming one
// or deleting one all happen inside a modal, so the row behind it kept whatever name
// it had the first time it was displayed - the preference had changed, the label had
// not. That is the reported "外面那个素材名字没有跟着变".
//
// 2.56: -reloadSpecifier: is NOT enough. It refreshes the specifier, not the pixels:
// the name lives in an accessory view painted by -willDisplayCell:, and the row reload
// does not re-run that method on an already-visible cell (the device kept showing 13
// after 14 was picked). 1.88 hit the same wall with the colour swatches, which is why
// they are painted directly. Repaint the visible cells first (immediate, no flicker,
// no dependence on when UIKit decides to ask for the cell again), then reload so a row
// that is currently off screen picks the new name up when it scrolls in.
- (void)refreshMaterialRows {
    if (!self.isViewLoaded || !_specifiers.count) return;
    for (UITableViewCell *cell in self.table.visibleCells) {
        NSIndexPath *indexPath = [self.table indexPathForCell:cell];
        PSSpecifier *item = [self specifierAtIndexPath:indexPath];
        NSString *identifier = [item propertyForKey:@"id"];
        if (![identifier isKindOfClass:NSString.class] || ![identifier hasSuffix:@"Material"]) continue;
        [self paintMaterialName:identifier inCell:cell];
    }
    [self.table reloadData];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Covers the return from the picker, from import, and from a rename/delete.
    [self refreshMaterialRows];
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
    NSArray *titles = @[@"切换素材", @"切换素材", @"切换素材", @"切换素材", @"切换素材"];
    SEL actions[] = {@selector(switchMessage:), @selector(switchOptions:), @selector(switchClear:), @selector(switchLockScreen:), @selector(switchDesktop:)};
    for (NSUInteger i = 0; i < LMVTargets().count; i++) {
        [_specifiers addObject:[PSSpecifier groupSpecifierWithName:[LMVNames()[i] stringByAppendingString:@"背景"]]];
        PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:[@"启用" stringByAppendingFormat:@"%@背景", LMVNames()[i]] target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
        [enabled setProperty:[LMVTargets()[i] stringByAppendingString:@"BackgroundEnabled"] forKey:@"key"];
        [enabled setProperty:@NO forKey:@"default"];
        [_specifiers addObject:enabled];
        PSSpecifier *choose = [PSSpecifier preferenceSpecifierNamed:titles[i] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        choose.buttonAction = actions[i];
        // 2.47: these five rows and the two control-centre rows never carried an id, so
        // the "which material is in use" label had nothing to key off and only the
        // channels below (HomeMenu onwards) showed a name. The id is the target plus
        // "Material", which is exactly what -willDisplayCell: turns back into the
        // stored <target>Video key.
        [choose setProperty:[LMVTargets()[i] stringByAppendingString:@"Material"] forKey:@"id"];
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
    PSSpecifier *controlCenterDark = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    controlCenterDark.buttonAction = @selector(switchControlCenterDark:);
    [controlCenterDark setProperty:@"ControlCenterDarkMaterial" forKey:@"id"];
    [_specifiers addObject:controlCenterDark];
    [self appendAudioForTarget:@"ControlCenterDark" title:@"深色模式"];
    PSSpecifier *controlCenterLight = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    controlCenterLight.buttonAction = @selector(switchControlCenterLight:);
    [controlCenterLight setProperty:@"ControlCenterLightMaterial" forKey:@"id"];
    [_specifiers addObject:controlCenterLight];
    [self appendAudioForTarget:@"ControlCenterLight" title:@"浅色模式"];
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"桌面长按菜单视频背景"]];
    PSSpecifier *homeMenuEnabled = [PSSpecifier preferenceSpecifierNamed:@"桌面长按菜单视频背景" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [homeMenuEnabled setProperty:@"HomeMenuBackgroundEnabled" forKey:@"key"];
    [homeMenuEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:homeMenuEnabled];
    PSSpecifier *homeMenuMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
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
    PSSpecifier *squidPanelMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    squidPanelMaterial.buttonAction = @selector(switchSquidPanel:);
    [squidPanelMaterial setProperty:@"SquidPanelMaterial" forKey:@"id"];
    [_specifiers addObject:squidPanelMaterial];
    [self appendAudioForTarget:@"SquidPanel" title:@"播放"];
    // 1.90: the Squid panel gets the same text-colour row as CopyVault, with its
    // own key. Settings only - the Easter panel does not carry it.
    PSSpecifier *squidText = [PSSpecifier preferenceSpecifierNamed:@"文字颜色" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    squidText.buttonAction = @selector(openSquidTextColor:);
    [squidText setProperty:@"SquidTextColor" forKey:@"id"];
    [_specifiers addObject:squidText];
    // 1.26: the AppTools (AT) pop-up background, right below the Squid panel
    // channel (same switch / material / sound / volume layout). This release
    // stores the settings and diagnoses the pop-up; the video mount follows.
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"AT 背景视频"]];
    PSSpecifier *atEnabled = [PSSpecifier preferenceSpecifierNamed:@"AT 背景视频" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [atEnabled setProperty:@"ATBackgroundEnabled" forKey:@"key"];
    [atEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:atEnabled];
    PSSpecifier *atMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
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
    PSSpecifier *cvMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
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
    PSSpecifier *myrtleMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    myrtleMaterial.buttonAction = @selector(switchMyrtle:);
    [myrtleMaterial setProperty:@"MyrtleMaterial" forKey:@"id"];
    [_specifiers addObject:myrtleMaterial];
    [self appendAudioForTarget:@"Myrtle" title:@"播放"];
    // 2.04: the PHONE-ASSIST pop-up (电话助手弹窗). Same layout as the channels
    // above: switch, material, sound + volume, text colour. The sheet is built on
    // UIAlertController internals, which is why it needs a channel of its own
    // instead of riding on the AppTools one - a real system alert must never get a
    // background, but this sheet must.
    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"电话助手弹窗背景视频"]];
    PSSpecifier *paEnabled = [PSSpecifier preferenceSpecifierNamed:@"电话助手弹窗背景视频" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [paEnabled setProperty:@"PABackgroundEnabled" forKey:@"key"];
    [paEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:paEnabled];
    PSSpecifier *paMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    paMaterial.buttonAction = @selector(switchPA:);
    [paMaterial setProperty:@"PAMaterial" forKey:@"id"];
    [_specifiers addObject:paMaterial];
    [self appendAudioForTarget:@"PA" title:@"播放"];
    PSSpecifier *paText = [PSSpecifier preferenceSpecifierNamed:@"文字颜色" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    paText.buttonAction = @selector(openPATextColor:);
    [paText setProperty:@"PATextColor" forKey:@"id"];
    [_specifiers addObject:paText];
    // 2.29: the GlassSuiteX sheet (GAXAlertOverlayView in the 2.26 log). Its own
    // switch / material / sound / volume, its own text colour, and a debug switch
    // that writes the detected card size to the diagnostic log.
    PSSpecifier *gsGroup = [PSSpecifier groupSpecifierWithName:@"GlassSuiteX 弹窗背景视频"];
    [gsGroup setProperty:@"开启诊断日志后，挂载状态会写入 shared-render.log（gs-panel 行）。" forKey:@"footerText"];
    [_specifiers addObject:gsGroup];
    PSSpecifier *gsEnabled = [PSSpecifier preferenceSpecifierNamed:@"GlassSuiteX 弹窗背景视频" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [gsEnabled setProperty:@"GSBackgroundEnabled" forKey:@"key"];
    [gsEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:gsEnabled];
    PSSpecifier *gsMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    gsMaterial.buttonAction = @selector(switchGS:);
    [gsMaterial setProperty:@"GSMaterial" forKey:@"id"];
    [_specifiers addObject:gsMaterial];
    [self appendAudioForTarget:@"GS" title:@"播放"];
    PSSpecifier *gsText = [PSSpecifier preferenceSpecifierNamed:@"文字颜色" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    gsText.buttonAction = @selector(openGSTextColor:);
    [gsText setProperty:@"GSTextColor" forKey:@"id"];
    [_specifiers addObject:gsText];
    // 2.30: the Control Center long-press menu (a real surface the 2.29 capture
    // found). Same layout as the other panel channels; the module that owns the
    // menu is written to the diagnostic line as module=...
    PSSpecifier *ccbGroup = [PSSpecifier groupSpecifierWithName:@"CCBorder 视频背景"];
    [ccbGroup setProperty:@"控制中心长按菜单的背景视频；诊断日志会带 module= 标识。" forKey:@"footerText"];
    [_specifiers addObject:ccbGroup];
    PSSpecifier *ccbEnabled = [PSSpecifier preferenceSpecifierNamed:@"CCBorder 视频背景" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [ccbEnabled setProperty:@"CCBorderBackgroundEnabled" forKey:@"key"];
    [ccbEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:ccbEnabled];
    PSSpecifier *ccbMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    ccbMaterial.buttonAction = @selector(switchCCBorder:);
    [ccbMaterial setProperty:@"CCBorderMaterial" forKey:@"id"];
    [_specifiers addObject:ccbMaterial];
    [self appendAudioForTarget:@"CCBorder" title:@"播放"];
    // 2.32: the CopyLogX clipboard panel - the 411x470 bottom sheet the 2.31 capture
    // caught the phone-assist channel mounting on by mistake.
    PSSpecifier *clxGroup = [PSSpecifier groupSpecifierWithName:@"CopyLogX 视频背景"];
    [clxGroup setProperty:@"剪贴板面板（411×470 底部卡片）的背景视频；诊断日志会写入 clx-panel。" forKey:@"footerText"];
    [_specifiers addObject:clxGroup];
    PSSpecifier *clxEnabled = [PSSpecifier preferenceSpecifierNamed:@"CopyLogX 视频背景" target:self set:@selector(setEnabled:specifier:) get:@selector(enabled:) detail:nil cell:PSSwitchCell edit:nil];
    [clxEnabled setProperty:@"CopyLogXBackgroundEnabled" forKey:@"key"];
    [clxEnabled setProperty:@NO forKey:@"default"];
    [_specifiers addObject:clxEnabled];
    PSSpecifier *clxMaterial = [PSSpecifier preferenceSpecifierNamed:@"切换素材" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    clxMaterial.buttonAction = @selector(switchCopyLogX:);
    [clxMaterial setProperty:@"CopyLogXMaterial" forKey:@"id"];
    [_specifiers addObject:clxMaterial];
    [self appendAudioForTarget:@"CopyLogX" title:@"播放"];
    PSSpecifier *clxText = [PSSpecifier preferenceSpecifierNamed:@"文字颜色" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    clxText.buttonAction = @selector(openCopyLogXTextColor:);
    [clxText setProperty:@"CopyLogXTextColor" forKey:@"id"];
    [_specifiers addObject:clxText];
    // 2.39: per-channel tuning, directly below CopyLogX and above the egg group.
    // 2.52: one flat section of eleven rows.
    // 2.54: that was still the wrong shape - the user wants a SECOND-LEVEL menu: one
    // entry here, a page listing the channels, then that channel's parameters. Eleven
    // rows in the root list made the page look like a channel switcher rather than
    // settings. The rows moved to LMVTuneListController; this is the only entry left.
    PSSpecifier *tuneGroup = [PSSpecifier groupSpecifierWithName:@"自定义参数"];
    [tuneGroup setProperty:@"每个通道单独一套参数（检测频率 / 出现延迟 / 关闭延迟 / 钩子节流 / 刷新率）。" forKey:@"footerText"];
    [_specifiers addObject:tuneGroup];
    PSSpecifier *tuneEntry = [PSSpecifier preferenceSpecifierNamed:@"功能面板参数" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    tuneEntry.buttonAction = @selector(openTuneList:);
    [tuneEntry setProperty:@"TuneList" forKey:@"id"];
    [_specifiers addObject:tuneEntry];
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
// 2.39: push the per-channel tuning page.
// 2.54: the root list now pushes the INDEX page, which pushes the per-channel page.
- (void)openTuneList:(PSSpecifier *)specifier {
    [self.navigationController pushViewController:[LMVTuneListController new] animated:YES];
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
// 1.89: the row shows the value itself ("#A7C6FF 100%") next to its title, so the
// colour can be read without opening the picker. An absent key means the panel
// keeps its own colours, which is "默认" rather than white.
// 1.90: CopyVault and Squid share this code; each row carries its own key and its
// own tag pair, so both can be painted without touching any private API.
// 2.04: one tag pair per coloured row. The original pair-by-pair logic covered two
// rows only; with a third row the recycled-cell cleanup has to know all of them.
// 2.45: the chosen material's name. PSButtonCell has no subtitle label, so the
// name is an accessory view (2.46) instead of a hand-placed subview.
static NSInteger const LMVMaterialValueTag = 0x5F2C;
static NSInteger LMVTextColorTagFor(NSString *key, BOOL value) {
    NSInteger base = 0x5A2C;
    if ([key isEqualToString:LMVSquidTextColorKey]) base = 0x5B2C;
    else if ([key isEqualToString:LMVPhoneAssistTextColorKey]) base = 0x5C2C;
    else if ([key isEqualToString:LMVGlassSuiteTextColorKey]) base = 0x5D2C;
    else if ([key isEqualToString:LMVCopyLogXTextColorKey]) base = 0x5E2C;
    return base + (value ? 1 : 0);
}
static NSString *LMVTextColorSummary(UIColor *color) {
    if (!color) return @"默认";
    CGFloat alpha = 1;
    [color getRed:NULL green:NULL blue:NULL alpha:&alpha];
    return [NSString stringWithFormat:@"%@ %.0f%%", LMVTextColorHex(color), alpha * 100.0];
}
- (NSDictionary *)textColorRowForSpecifier:(PSSpecifier *)specifier {
    id identifier = [specifier propertyForKey:@"id"];
    NSString *key = nil;
    if ([identifier isEqualToString:@"CVTextColor"]) key = LMVTextColorKey;
    else if ([identifier isEqualToString:@"SquidTextColor"]) key = LMVSquidTextColorKey;
    else if ([identifier isEqualToString:@"PATextColor"]) key = LMVPhoneAssistTextColorKey;
    else if ([identifier isEqualToString:@"GSTextColor"]) key = LMVGlassSuiteTextColorKey;
    else if ([identifier isEqualToString:@"CopyLogXTextColor"]) key = LMVCopyLogXTextColorKey;
    if (!key) return nil;
    return @{@"key": key, @"dot": @(LMVTextColorTagFor(key, NO)), @"value": @(LMVTextColorTagFor(key, YES))};
}
- (void)paintMaterialName:(NSString *)materialID inCell:(UITableViewCell *)cell {
    // 2.42: the material rows are all called 切换素材 now; the chosen file is shown
    // on the right so the row still says WHICH material is in use.
    BOOL materialRow = [materialID isKindOfClass:NSString.class] && [materialID hasSuffix:@"Material"];
    // 2.45: PSButtonCell is a plain (default-style) cell, so its detailTextLabel is
    // nil and 2.44's assignment went nowhere. 2.46: a hand-placed label in contentView
    // still came out blank on the device (the button cell lays its own content out and
    // the label was never given a usable frame), so the name is an ACCESSORY VIEW now:
    // UIKit places an accessory itself, right-aligned and vertically centred in exactly
    // the column a UISwitch occupies - no manual constraints, nothing to be laid out
    // over. Long names shrink to fit instead of pushing the title aside.
    [[cell.contentView viewWithTag:LMVMaterialValueTag] removeFromSuperview];
    if (!materialRow) {
        if (cell.accessoryView.tag == LMVMaterialValueTag) cell.accessoryView = nil;
        return;
    }
    UILabel *materialValue = (UILabel *)cell.accessoryView;
    if (![materialValue isKindOfClass:UILabel.class] || materialValue.tag != LMVMaterialValueTag) {
        materialValue = [UILabel new];
        materialValue.tag = LMVMaterialValueTag;
        materialValue.font = [UIFont systemFontOfSize:15];
        materialValue.textColor = [UIColor secondaryLabelColor];
        materialValue.textAlignment = NSTextAlignmentRight;
        materialValue.numberOfLines = 1;
        // 4.0.1: names were cut in the MIDDLE ("相册原…音图层"). Tail truncation
        // keeps the beginning readable, and the label may shrink a little before
        // it ever shows an ellipsis.
        materialValue.lineBreakMode = NSLineBreakByTruncatingTail;
        // 4.0.3: no auto-shrink. 4.0.1 let the label scale down to 0.85 before it
        // truncated, and only the rows whose width fell short did so - two rows
        // holding the same name ended up at different font sizes. Every row now
        // keeps 15pt and ellipsises at the tail instead.
        materialValue.adjustsFontSizeToFitWidth = NO;
        materialValue.minimumScaleFactor = 1.0;
        materialValue.userInteractionEnabled = NO;
        materialValue.accessibilityIdentifier = @"LMVMaterialValue";
        cell.accessoryView = materialValue;
    }
    NSString *key = [materialID stringByReplacingOccurrencesOfString:@"Material" withString:@"Video"];
    id value = LMVEasterRead(key);
    NSString *path = [value isKindOfClass:NSString.class] ? value : nil;
    // 2.44: the row said which material by showing the FILE NAME, and every
    // imported file is a UUID on disk - so a renamed material showed
    // "8A5A5463-A5C9-4847-BFC2-A0913B51..." outside the picker. Resolve the
    // display name the same way the picker does (catalog name first, then a
    // generated label for UUID-named files), so the raw UUID is never shown.
    // 4.0.0: names are no longer pre-written on list load, so the catalog name
    // (set by the user or the import path) is the first source; when it is
    // absent the catalog's generator turns a UUID file into a readable label.
    // 4.0.1: a selection whose file is gone is NOT a selection. The catalog's
    // generator invents "视频素材 N" whenever it has no file attributes, which is
    // exactly what an empty library used to show on every row (all of them said
    // 视频素材 1). Check the file first and fall through to 未选择.
    NSFileManager *files = [NSFileManager defaultManager];
    BOOL present = path.length &&
        [files fileExistsAtPath:[LMV_CATALOG_ROOT stringByAppendingPathComponent:path]];
    NSString *name = nil;
    if (present) {
        name = LMVReadMaterialNames()[path];
        if (![name isKindOfClass:NSString.class] || !name.length) {
            NSString *relative = path;
            NSDictionary *attributes = [files attributesOfItemAtPath:[LMV_CATALOG_ROOT stringByAppendingPathComponent:relative] error:nil];
            NSString *display = LMVMaterialDisplayName(relative, LMVReadMaterialNames(), attributes ?: @{}, 0);
            if ([display isKindOfClass:NSString.class] && display.length) name = display;
        }
    }
    materialValue.text = name.length ? name : @"未选择";
    [materialValue sizeToFit];
    CGFloat cap = MAX(80, cell.contentView.bounds.size.width * 0.60);
    if (materialValue.bounds.size.width > cap)
        materialValue.frame = CGRectMake(0, 0, cap, materialValue.bounds.size.height);
}
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    [self paintMaterialName:[specifier propertyForKey:@"id"] inCell:cell];
    NSDictionary *row = [self textColorRowForSpecifier:specifier];
    if (!row) {
        // 1.88: a recycled cell must not carry a swatch onto an unrelated row.
        for (NSNumber *tag in @[@(0x5A2C), @(0x5A2D), @(0x5B2C), @(0x5B2D), @(0x5C2C), @(0x5C2D), @(0x5D2C), @(0x5D2D), @(0x5E2C), @(0x5E2D), @(0x5F2C)])
            [[cell.contentView viewWithTag:tag.unsignedIntegerValue] removeFromSuperview];
        return;
    }
    NSInteger dotTag = [row[@"dot"] integerValue];
    NSInteger valueTag = [row[@"value"] integerValue];
    // A cell recycled between the two colour rows must not keep the other row's pair.
    for (NSNumber *base in @[@(0x5A2C), @(0x5B2C), @(0x5C2C), @(0x5D2C), @(0x5E2C)]) {
        if (base.integerValue == dotTag) continue;
        [[cell.contentView viewWithTag:base.unsignedIntegerValue] removeFromSuperview];
        [[cell.contentView viewWithTag:base.unsignedIntegerValue + 1] removeFromSuperview];
    }
    UIView *dot = [cell.contentView viewWithTag:dotTag];
    UILabel *value = [cell.contentView viewWithTag:valueTag];
    if (!dot) {
        dot = [UIView new];
        dot.tag = dotTag;
        dot.userInteractionEnabled = NO;
        dot.layer.borderWidth = 1;
        dot.layer.borderColor = [UIColor separatorColor].CGColor;
        [cell.contentView addSubview:dot];
    }
    if (!value) {
        value = [UILabel new];
        value.tag = valueTag;
        value.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightRegular];
        value.textColor = [UIColor secondaryLabelColor];
        value.textAlignment = NSTextAlignmentLeft;
        value.userInteractionEnabled = NO;
        [cell.contentView addSubview:value];
    }
    // 1.92: laid out with constraints instead of frames so the swatch cannot end
    // up glued to the bottom of the row: it is centred on the row, and its centre
    // sits on the same vertical line as the UISwitch accessory above (a switch is
    // 51pt wide and 16pt from the trailing edge, so its centre is 41.5pt in).
    CGFloat size = 22;
    if (!dot.accessibilityIdentifier.length) {
        dot.accessibilityIdentifier = @"LMVTextColorRow";
        dot.translatesAutoresizingMaskIntoConstraints = NO;
        value.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [dot.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [dot.widthAnchor constraintEqualToConstant:size],
            [dot.heightAnchor constraintEqualToConstant:size],
            // 2.46: align the swatch's RIGHT EDGE with the switch's right edge (16pt
            // from the cell), not its centre with the switch's centre. The swatch is
            // 22pt against the switch's 51pt, so centre-alignment left it visibly
            // 14.5pt to the left of the column the user marked. 16 + 22/2 = 27.
            [dot.centerXAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-27],
            [value.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [value.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:98],
            [value.trailingAnchor constraintLessThanOrEqualToAnchor:dot.leadingAnchor constant:-8]
        ]];
    }
    dot.layer.cornerRadius = size / 2;
    UIColor *current = LMVTextColorForKey(row[@"key"]);
    // 1.88: keep the table addressable so a pick can repaint in place.
    self.cvTextColorTable = tableView;
    dot.backgroundColor = current ?: UIColor.whiteColor;
    value.text = LMVTextColorSummary(current);
}
// 1.88: repaint the swatch without going through -reloadSpecifier: (which kept
// showing the stale colour) or the private -cellForSpecifier: lookup (which could
// return nothing). The visible cells are scanned by tag instead.
- (UIView *)dotViewWithTag:(NSInteger)tag {
    for (UITableViewCell *cell in (self.cvTextColorTable ?: self.table).visibleCells) {
        UIView *found = [cell.contentView viewWithTag:tag];
        if (found) return found;
    }
    return nil;
}
// 1.89: `color` is the live preview from the picker; nil means "read the stored
// value". Painting the passed colour keeps the row in step while the finger is
// still moving, without waiting for the preference write. `live` skips the text
// so a 60Hz drag does not re-lay-out the label on every event.
- (void)paintTextColorDot:(UIColor *)color key:(NSString *)key live:(BOOL)live {
    NSInteger dotTag = LMVTextColorTagFor(key, NO);
    UIView *dot = [self dotViewWithTag:dotTag];
    if (!dot) return;
    UIColor *shown = color ?: LMVTextColorForKey(key);
    dot.backgroundColor = shown ?: UIColor.whiteColor;
    if (live) return;
    UILabel *value = (UILabel *)[dot.superview viewWithTag:dotTag + 1];
    if (value) value.text = LMVTextColorSummary(shown);
}
- (void)openTextColorForKey:(NSString *)key {
    if (self.presentedViewController) return;
    LMVTextColorPicker *picker = [LMVTextColorPicker new];
    picker.preferenceKey = key;
    picker.modalPresentationStyle = UIModalPresentationOverFullScreen;
    __weak LMVPRootListController *weakSelf = self;
    // Every drag, grid tap and preset goes through here - paint immediately.
    picker.onChange = ^(UIColor *color) {
        [weakSelf paintTextColorDot:color key:key live:YES];
    };
    // ...and once more after the sheet has left, when the list is laid out again.
    picker.onDismiss = ^{
        [weakSelf paintTextColorDot:nil key:key live:NO];
    };
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)openCVTextColor:(PSSpecifier *)specifier {
    [self openTextColorForKey:LMVTextColorKey];
}
- (void)openSquidTextColor:(PSSpecifier *)specifier {
    [self openTextColorForKey:LMVSquidTextColorKey];
}
// 2.04: the phone-assist sheet's own colour row.
- (void)openPATextColor:(PSSpecifier *)specifier {
    [self openTextColorForKey:LMVPhoneAssistTextColorKey];
}
// 2.29: the GlassSuiteX sheet's own colour row.
- (void)openGSTextColor:(PSSpecifier *)specifier {
    [self openTextColorForKey:LMVGlassSuiteTextColorKey];
}
// 2.32: the CopyLogX clipboard panel's own colour row.
- (void)openCopyLogXTextColor:(PSSpecifier *)specifier {
    [self openTextColorForKey:LMVCopyLogXTextColorKey];
}
- (void)setEnabled:(id)value specifier:(PSSpecifier *)specifier {
    CFPreferencesSetAppValue((__bridge CFStringRef)[specifier propertyForKey:@"key"], (__bridge CFPropertyListRef)@([value boolValue]), kLMVPrefsID);
    LMVNotifyFor(LMVTargetForPrefKey([specifier propertyForKey:@"key"]));
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
    LMVNotifyFor(LMVTargetForPrefKey([specifier propertyForKey:@"key"]));
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
    LMVNotifyFor(target);
    // 2.52: repaint this target's row now. The picker is an over-full-screen modal,
    // so returning from it does not re-display the row underneath; without this the
    // old name stayed until the user scrolled it out and back in.
    [self refreshMaterialRows];
    NSDictionary *titles = @{@"Message": @"消息背景", @"Options": @"选项背景", @"Clear": @"清除背景", @"LockScreen": @"锁屏背景", @"Desktop": @"桌面背景", @"ControlCenterDark": @"控制中心深色背景", @"ControlCenterLight": @"控制中心浅色背景", @"HomeMenu": @"桌面长按菜单视频背景", @"SquidPanel": @"右一·右上滑面板背景视频", @"AT": @"AT 背景视频", @"CV": @"CopyVault 面板背景视频", @"Myrtle": @"Myrtle 面板背景视频", @"PA": @"电话助手弹窗背景视频", @"GS": @"GlassSuiteX 弹窗背景视频", @"CCBorder": @"CCBorder 视频背景", @"CopyLogX": @"CopyLogX 视频背景"};
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已应用素材" message:[NSString stringWithFormat:@"%@ 已切换为 %@", titles[target], name] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)switchTarget:(NSString *)target {
    if (self.presentedViewController || !LMVMaterialTargetAllowed(target)) return;
    NSString *key = [target stringByAppendingString:@"Video"];
    id selected = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kLMVPrefsID);
    NSDictionary *legacy = @{@"Message": @"message.mov", @"Options": @"options.mov", @"Clear": @"clear.mov", @"LockScreen": @"", @"Desktop": @"", @"ControlCenterDark": @"", @"ControlCenterLight": @"", @"HomeMenu": @"", @"SquidPanel": @"", @"AT": @"", @"CV": @"", @"Myrtle": @"", @"PA": @"", @"GS": @"", @"CCBorder": @"", @"CopyLogX": @""};
    if (![selected isKindOfClass:NSString.class]) selected = legacy[target] ?: @"";
    LMVMaterialPicker *picker = [LMVMaterialPicker new];
    picker.selected = selected;
    __weak typeof(self) weakSelf = self;
    picker.apply = ^(NSString *relative, NSString *name) { [weakSelf selectFile:relative name:name target:target]; };
    // 4.0.4: deleting the selected material happens AFTER the picker dismisses, so
    // the page underneath has already painted the old name by the time the file is
    // gone. Repaint when the library actually changes, otherwise the row keeps the
    // deleted material's name instead of falling back to 未选择.
    picker.libraryChanged = ^{ [weakSelf refreshMaterialRows]; };
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
- (void)switchPA:(PSSpecifier *)specifier { [self switchTarget:@"PA"]; }
- (void)switchGS:(PSSpecifier *)specifier { [self switchTarget:@"GS"]; }
- (void)switchCCBorder:(PSSpecifier *)specifier { [self switchTarget:@"CCBorder"]; }
// 2.32: the CopyLogX clipboard panel.
- (void)switchCopyLogX:(PSSpecifier *)specifier { [self switchTarget:@"CopyLogX"]; }
- (void)chooseVideo:(PSSpecifier *)specifier {
    if (self.materialBusy) return;
    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:[PHPhotoLibrary sharedPhotoLibrary]];
    config.filter = [PHPickerFilter videosFilter];
    // 4.0.0: allow multiple selections so several videos can be imported at once.
    config.selectionLimit = 0;
    config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSArray<PHPickerResult *> *videos = [results filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(PHPickerResult *result, NSDictionary<NSString *, id> *bindings) {
        return [result.itemProvider hasItemConformingToTypeIdentifier:@"public.movie"];
    }]];
    if (videos.count == 0) return;
    self.materialBusy = YES;
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSString *> *imported = [NSMutableArray new];
    NSMutableArray<NSString *> *failed = [NSMutableArray new];
    for (PHPickerResult *result in videos) {
        dispatch_group_enter(group);
        [result.itemProvider loadFileRepresentationForTypeIdentifier:@"public.movie" completionHandler:^(NSURL *url, NSError *error) {
            NSError *copyError = error;
            NSString *relative = nil;
            if (!url && !copyError) copyError = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
            if (url && !copyError) relative = LMVImportMovie(url, &copyError);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (relative && !copyError) [imported addObject:relative];
                else [failed addObject:copyError.localizedDescription ?: @"导入失败"];
                dispatch_group_leave(group);
            });
        }];
    }
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        self.materialBusy = NO;
        if (imported.count) {
            // Only the three message targets receive an initial selection after import.
            for (NSString *target in @[@"Message", @"Options", @"Clear"]) {
                NSString *key = [target stringByAppendingString:@"Video"];
                id selected = (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, kLMVPrefsID);
                BOOL legacyMessage = !selected && [target isEqualToString:@"Message"] && [[NSFileManager defaultManager] fileExistsAtPath:[LMVDirectory stringByAppendingPathComponent:@"message.mov"]];
                if (!selected && !legacyMessage) CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)imported.firstObject, kLMVPrefsID);
            }
            LMVNotify();
        }
        if (failed.count) {
            [self showError:[NSError errorWithDomain:@"com.minis.lockmessagevideo.import" code:1 userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%lu 个视频导入失败，其余已保存到素材库。", (unsigned long)failed.count]}]];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入成功" message:[NSString stringWithFormat:@"已验证原视频并按原片字节保存到素材库：共 %lu 个。\n保留画质、帧率与音轨，未重新编码。", (unsigned long)imported.count] preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    });
}
@end
