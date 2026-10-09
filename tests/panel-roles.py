from pathlib import Path
r=Path(__file__).resolve().parents[1]
video=(r/'LMVEasterPanel.h').read_text()
image=(r/'LMVEasterImageSettings.h').read_text()
photo=(r/'LMVEasterPhotoFlow.h').read_text()
material=(r/'LockMessageVideoPrefs/LMVMaterialPicker.h').read_text()
prompt=(r/'LockMessageVideoPrefs/LMVMaterialPrompt.h').read_text()
overlay=(r/'LMVEasterOverlay.h').read_text()
original=(r/'LMVObservedWallpaper.h').read_text()
for forbidden in ['imageControls','EasterEggEnabled','EasterEggImage','imagesFilter','loadPreview','LMVCompressMovie']:
    assert forbidden not in video,forbidden
for forbidden in ['LMVEasterTargets','VideoOpacity','videosFilter','LMVMaterialPicker']:
    assert forbidden not in image,forbidden
assert 'return 1;' in image and 'return 3;' in image and '启用小彩蛋' not in image
assert 'slider.minimumValue = 32; slider.maximumValue = 128' in image
assert 'VideoOpacityEnabled' in video and 'slider.minimumValue = 0; slider.maximumValue = 1' in video
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
assert 'blankKnown=%d lockKnown=%d' in overlay and 'pulledDown' in overlay
assert 'state.active' not in original and 'LMVOpacity' not in original and 'state.source' not in original
assert 'LMVBackgroundOnlyView(view)' in original and 'Passcode' in original and '_SBWallpaperSecureWindow' in original
assert 'LMVAcquireOriginal(branch.layer, branch.superview.layer, LMVOriginalSuppressDrawing' in original
assert 'LMVAcquireOriginal(window.layer' not in original and 'layer.contents =' not in original
print('PASS: image/video roles, live sliders, bounded contained navigation/Photos lifecycle, main modal compatibility, original-video import, prompts, geometry, security and observed-wallpaper contracts (not UIKit execution)')
