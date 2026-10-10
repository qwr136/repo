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
assert 'return 1;' in image and 'return 2;' in image and '启用小彩蛋' not in image
assert 'loadPreview' not in image and 'UIImage *preview' not in image
assert 'picker.showsThumbnails = NO' in video
assert 'slider.minimumValue = 32; slider.maximumValue = 128' in image
assert 'VideoOpacityEnabled' in video and 'slider.minimumValue = 0; slider.maximumValue = 1' in video
targets = re.findall(r'@"([^"]+)"', re.search(r'LMVEasterTargets\(void\) \{ return @\[(.*?)\]; \}', video).group(1))
assert targets == ['Message', 'Options', 'Clear', 'LockScreen', 'Desktop']
assert '@[@"消息背景", @"选项背景", @"清除背景", @"锁屏背景", @"桌面背景"]' in video
for target in ('LockScreen', 'Desktop'):
    assert video.count(f'@"{target}":@""') == 2  # Label and picker both start unselected.
    assert target + 'Opacity' not in video
assert len(targets) + 2 == 7  # Five video targets, shared message opacity and original import.
assert 'return LMVEasterTargets().count + 2;' in video
assert 'return section == LMVEasterTargets().count + 1 ? 1 : 2;' in video
assert 'section < LMVEasterTargets().count ? LMVEasterTitles()[section]' in video
assert 'section == LMVEasterTargets().count ? @"消息、选项、清除视频透明度" : @"独立原片导入"' in video
assert 'if (index.section == LMVEasterTargets().count)' in video
assert 'toggle.tag = LMVEasterTargets().count;' in video
assert 'if (toggle.tag < 0 || toggle.tag > targetCount) return;' in video
assert 'toggle.tag == targetCount ? @"VideoOpacityEnabled"' in video
assert video.count('if (index.section == LMVEasterTargets().count + 1)') == 2
assert 'if (index.section < 0 || index.section >= LMVEasterTargets().count || index.row != 1) return;' in video
assert 'if (self.presentedViewController || self.busy) return;' in video
assert 'toggle.on = enabled ? [enabled boolValue] : YES;' in video
assert 'toggle.on = [LMVEasterRead([target stringByAppendingString:@"BackgroundEnabled"]) boolValue];' in video
assert 'isfinite(raw) ? MAX(0, MIN(1, raw)) : 0.55' in video
assert 'opacityTracking' in video and '!panel.opacityTracking' in video
assert 'pushViewController:picker' in video and 'picker.pushed = YES' in video
assert 'pushViewController:self.photoFlow' in video and 'popToViewController:self' in video
assert 'presentViewController:' not in video
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
assert 'cornerRadius = 20' in overlay and 'bounds.size.height * .65' in overlay
assert 'while (modal.presentedViewController)' not in overlay
assert 'canBecomeKeyWindow { return self.panel != nil' in overlay and '[self restoreKey]' in overlay
assert 'blankKnown' in overlay and 'notification-center-only:not-visible-or-locked' in overlay
assert 'LMVEasterNCPolicy' in overlay and 'recordScreenBlank' in overlay
assert '@[@"Message", @"Options", @"Clear"]' in original  # Main renderer remains limited to the original three roles.
assert 'LMVLayoutLockOverlay' not in original
assert not (r/'LMVLockBackground.h').exists()
print('PASS: image/video roles, live sliders, bounded contained navigation/Photos lifecycle, main modal compatibility, original-video import, prompts, geometry, security and observed-wallpaper contracts (not UIKit execution)')
