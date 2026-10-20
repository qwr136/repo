from pathlib import Path
import re
r=Path(__file__).resolve().parents[1]
video=(r/'LMVEasterPanel.h').read_text()
image=(r/'LMVEasterImageSettings.h').read_text()
photo=(r/'LMVEasterPhotoFlow.h').read_text()
material=(r/'LockMessageVideoPrefs/LMVMaterialPicker.h').read_text()
prompt=(r/'LockMessageVideoPrefs/LMVMaterialPrompt.h').read_text()
overlay=(r/'LMVEasterOverlay.h').read_text()
original=(r/'Tweak.xm').read_text()
for forbidden in ['imageControls','EasterEggEnabled','EasterEggImage','imagesFilter','loadPreview','LMVCompressMovie']:
    assert forbidden not in video,forbidden
for forbidden in ['LMVEasterTargets','VideoOpacity','videosFilter','LMVMaterialPicker']:
    assert forbidden not in image,forbidden
# 0.0.122: the page gained a floating-panel appearance section (corner radius,
# width, height) that both entry points share.
assert 'return LMVEasterImagePanelSection() + 1;' in image and 'LMVEasterImageDisplayKeys().count : 2;' in image and '启用小彩蛋' not in image
assert 'if (section == LMVEasterImagePanelSection()) return 5;' in image
assert 'LMVEasterResolvedPanelCorner(' in overlay
assert '#import "LMVEasterImageSettings.h"' in video
assert 'pushViewController:[LMVEasterImageSettings new]' in video
assert '显示场景与图片旋转' in video
assert 'loadPreview' not in image and 'UIImage *preview' not in image
# 0.0.122: the floating panel shows previews too; the picker already loads
# them on one utility queue with an NSCache, remembers failures and only
# touches visible rows, so a large library never blocks scrolling.
assert 'picker.showsThumbnails = YES' in video
assert 'slider.minimumValue = 12; slider.maximumValue = 128' in image
assert 'constraintEqualToConstant:LMVEasterSize()' in image and 'previewSizeConstraints' in image
assert 'if (self.close) self.close();' in image
assert 'self.navigationController.viewControllers.count > 1' in image and 'popViewControllerAnimated:YES' in image
assert 'else [self dismissViewControllerAnimated:YES completion:nil];' in image
assert 'VideoOpacityEnabled' in video and 'slider.minimumValue = 0; slider.maximumValue = 1' in video
targets = re.findall(r'@"([^"]+)"', re.search(r'LMVEasterTargets\(void\) \{ return @\[(.*?)\]; \}', video).group(1))
assert targets == ['Message', 'Options', 'Clear', 'LockScreen', 'Desktop']
assert '@[@"消息背景", @"选项背景", @"清除背景", @"锁屏背景", @"桌面背景"]' in video
for target in ('LockScreen', 'Desktop'):
    assert video.count(f'@"{target}":@""') == 2  # Label and picker both start unselected.
    assert target + 'Opacity' not in video
assert len(targets) + 5 == 10  # Existing eight sections + HomeMenu + image display entry.
assert re.search(r'numberOfSectionsInTableView:.*?return LMVEasterImportSection\(\) \+ 1;', video) is not None
assert 'LMVEasterControlCenterSection() + 1' in video and 'LMVEasterOpacitySection() + 1' in video
assert 'LMVEasterImportSection() + 1' in video and 'LMVEasterHomeMenuSection() + 1' in video
assert 'section >= 0 && section < LMVEasterTargets().count) return 4' in video
assert 'section == LMVEasterControlCenterSection()) return 7' in video
assert 'section == LMVEasterHomeMenuSection()) return 4' in video
assert 'LMVEasterAudioTarget(index.section, index.row)' in video
assert '@selector(soundChanged:)' in video and '@selector(volumeChanged:)' in video
assert 'section == LMVEasterImportSection() || section == LMVEasterDisplaySection() ? 1 : 2' in video
assert 'if (section < LMVEasterTargets().count) return LMVEasterTitles()[section]' in video
assert 'ControlCenterBackgroundEnabled' in video
assert 'ControlCenterDarkVideo' in video and 'ControlCenterLightVideo' in video
assert '切换素材' in video and '切换素材' in video
assert 'toggle.tag = LMVEasterOpacitySection();' in video
assert 'toggle.tag > LMVEasterOpacitySection()' in video
assert 'else if (toggle.tag == LMVEasterHomeMenuSection()) key = @"HomeMenuBackgroundEnabled";' in video
assert 'else if (toggle.tag < LMVEasterTargets().count)' in video and 'else return;' in video
assert 'toggle.on = [LMVEasterRead(@"HomeMenuBackgroundEnabled") boolValue];' in video
assert 'id selected = LMVEasterRead(@"HomeMenuVideo");' in video
assert 'key = @"HomeMenuVideo";' in video and '切换素材' in video
assert 'toggle.tag == LMVEasterControlCenterSection()' in video
assert 'if (index.section == LMVEasterImportSection())' in video
assert 'if (index.section < 0 || index.section >= LMVEasterTargets().count || index.row != 1) return;' in video
assert 'if (self.presentedViewController || self.busy) return;' in video
assert 'toggle.on = enabled ? [enabled boolValue] : YES;' in video
assert 'toggle.on = [LMVEasterRead([target stringByAppendingString:@"BackgroundEnabled"]) boolValue];' in video
assert 'isfinite(raw) ? MAX(0, MIN(1, raw)) : 0.55' in video
assert 'opacityTracking' in video and '!panel.opacityTracking' in video
assert 'pushViewController:picker' in video and 'picker.pushed = YES' in video
assert 'pushViewController:self.photoFlow' in video and 'popToViewController:self' in video
assert video.count('presentViewController:') == 0, 'the floating panel no longer presents the text-colour sheet'
assert '[self addChildViewController:self.picker]' in photo and '[self.picker didMoveToParentViewController:self]' in photo
assert '[self.picker willMoveToParentViewController:nil]' in photo and '[self.picker removeFromParentViewController]' in photo
assert 'PHPickerConfigurationAssetRepresentationModeCurrent' in video and 'LMVEasterImport(url, YES' in video
assert 'if (self.pushed)' in material and 'popViewControllerAnimated:YES' in material
assert 'else [self dismissViewControllerAnimated:YES' in material
assert 'self.navigationController ?: self' in material
assert 'if (self.pushed) { [self deleteContained:row]; return; }' in material
assert 'if (picker.pushed) { [picker renameContained:row]; done(YES); return; }' in material
assert '[self removeFromParentViewController]' in prompt
assert '- (void)showPendingImportPrompt;' in video  # Callback-visible declaration for -Werror.
assert '- (void)viewDidAppear:(BOOL)animated' in video and 'self.panelVisible = YES;' in video
assert '- (void)viewWillDisappear:(BOOL)animated' in video and 'self.panelVisible = NO;' in video
show = video[video.index('- (void)showPendingImportPrompt {'):video.index('- (void)finish {')]
for guard in ['!self.panelVisible', '!self.isViewLoaded', '!self.view.window', 'self.view.window.hidden', 'self.view.window.alpha < 0.01', 'self.presentedViewController', 'self.prompt', 'navigation.topViewController != self', 'self.isBeingDismissed']:
    assert guard in show, guard
assert 'static NSMutableArray<LMVMaterialPrompt *> *LMVEasterPendingImportPrompts;' in video
assert 'LMVEasterPendingImportPrompts.firstObject' in show and 'removeObjectAtIndex:0' in show
assert 'self.prompt = prompt;' in show and '[host addChildViewController:prompt]' in show
assert '[prompt didMoveToParentViewController:host]' in show
complete = re.search(r'prompt\.complete = \^\(NSString \*text, BOOL accepted\) \{(.*?)\};', show, re.S).group(1)
assert 'weakSelf.prompt = nil;' in complete and 'showPendingImportPrompt' in complete
for forbidden in ['dismissViewController', 'popViewController', 'finish]', 'close']:
    assert forbidden not in complete
assert 'dispatch_after' not in video and 'UIAlertController' not in video
callback = video[video.index('- (void)picker:(PHPickerViewController *)picker didFinishPicking:'):]
assert 'if (!picked || self.busy || ![picked.itemProvider hasItemConformingToTypeIdentifier:@"public.movie"]) return;' in callback
assert callback.index('if (!picked') < callback.index('self.busy = YES;') < callback.index('loadFileRepresentationForTypeIdentifier:')
assert callback.index('LMVEasterImport(url, YES, &error)') < callback.index('panel.busy = NO;') < callback.index('[panel loadNames];') < callback.index('[LMVEasterPendingImportPrompts addObject:prompt];')
assert 'BOOL success = relative && !error;' in callback and 'if (success) LMVEasterNotify();' in callback
assert 'prompt.promptTitle = success ? @"导入成功" : @"导入失败";' in callback
assert 'prompt.message = success ? @"已保存到素材库" : (error.localizedDescription ?: @"无法保存视频");' in callback
assert 'if (!panel) return;' not in callback  # Survives overlay panel teardown.
assert 'LMVEasterSet(' not in callback and 'CFPreferencesSetAppValue' not in callback
# 0.0.122: the panel's corner radius comes from the shared appearance rules
# (20 pt when the toggle is off or was never set), never a literal at the call site.
assert 'LMVEasterResolvedPanelCorner(LMVEasterRead(@"EasterPanelCornerEnabled"),' in overlay
assert ', 20.0);' in overlay and 'bounds.size.height * .65' in overlay
assert 'while (modal.presentedViewController)' not in overlay
assert 'canBecomeKeyWindow { return self.panel != nil' in overlay and '[self restoreKey]' in overlay
assert 'blankKnown' in overlay and 'home-nc-cc:not-visible-or-locked' in overlay
assert 'LMVEasterNCPolicy' in overlay and 'recordScreenBlank' in overlay
# 0.0.133: the ball haptic was removed entirely (no effect on device) - the tap
# action is back to just opening the panel.
assert 'Haptic' not in overlay and '悬浮球震动' not in overlay
assert 'UIImpactFeedbackGenerator' not in overlay
assert '@[@"Message", @"Options", @"Clear"]' in original  # Main renderer remains limited to the original three roles.
assert 'LMVLayoutLockOverlay' not in original
assert not (r/'LMVLockBackground.h').exists()
print('PASS: image/video roles, live sliders, bounded contained navigation/Photos lifecycle, main modal compatibility, original-video import, prompts, geometry, security and observed-wallpaper contracts (not UIKit execution)')
