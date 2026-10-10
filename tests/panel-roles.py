from pathlib import Path
r=Path(__file__).resolve().parents[1]
video=(r/'LMVEasterPanel.h').read_text()
image=(r/'LMVEasterImageSettings.h').read_text()
photo=(r/'LMVEasterPhotoFlow.h').read_text()
material=(r/'LockMessageVideoPrefs/LMVMaterialPicker.h').read_text()
prompt=(r/'LockMessageVideoPrefs/LMVMaterialPrompt.h').read_text()
overlay=(r/'LMVEasterOverlay.h').read_text()
original=(r/'LMVLockBackground.h').read_text()
for forbidden in ['imageControls','EasterEggEnabled','EasterEggImage','imagesFilter','loadPreview','LMVCompressMovie']:
    assert forbidden not in video,forbidden
for forbidden in ['LMVEasterTargets','VideoOpacity','videosFilter','LMVMaterialPicker']:
    assert forbidden not in image,forbidden
assert 'return 1;' in image and 'return 2;' in image and '启用小彩蛋' not in image
assert 'loadPreview' not in image and 'UIImage *preview' not in image
assert 'picker.showsThumbnails = NO' in video
assert 'slider.minimumValue = 32; slider.maximumValue = 128' in image
assert 'VideoOpacityEnabled' in video and 'slider.minimumValue = 0; slider.maximumValue = 1' in video
assert '@[@"Message", @"LockScreen", @"Options", @"Clear"]' in video
assert '@[@"消息背景", @"锁屏背景", @"选项背景", @"清除背景"]' in video
assert 'Desktop' not in video and '桌面' not in video
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
assert 'cornerRadius = 20' in overlay and 'bounds.size.height * .65' in overlay
assert 'while (modal.presentedViewController)' not in overlay
assert 'canBecomeKeyWindow { return self.panel != nil' in overlay and '[self restoreKey]' in overlay
assert 'blankKnown' in overlay and 'screen-blank' in overlay
assert 'LMVAcquireOriginal' not in original and 'LMVOriginalDetach' not in original
assert 'video.opacity=1.0f' in original
assert 'above-system-background' in original and 'LMVLockExposedRect' in original
print('PASS: image/video roles, live sliders, bounded contained navigation/Photos lifecycle, main modal compatibility, original-video import, prompts, geometry, security and observed-wallpaper contracts (not UIKit execution)')
