#!/usr/bin/env python3
"""Source contracts; UIKit/Photos interaction still requires a jailbroken device."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
media = (root / 'LMVEasterMedia.h').read_text()
panel = (root / 'LMVEasterPanel.h').read_text()
overlay = (root / 'LMVEasterOverlay.h').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
tweak = (root / 'Tweak.xm').read_text()

image = (root / 'LMVEasterImageSettings.h').read_text()
assert 'EasterEggEnabled' in prefs and 'EasterEggImage' in media + image + overlay
assert 'EasterEggImageSettings' in prefs and 'reloadEasterPreview' not in prefs
assert '@selector(openEaster:)' in prefs and '- (void)openEaster:' in prefs
assert 'LMVMaterialPicker *picker = [LMVMaterialPicker new]' in panel
assert '@["Message"' not in panel
for ui in (prefs, panel):
    assert '@[@"Message", @"Options", @"Clear", @"LockScreen", @"Desktop"]' in ui
    assert '消息、选项、清除视频透明度' in ui
    for target in ('LockScreen', 'Desktop'):
        assert target + 'Opacity' not in ui
assert '@[@"消息背景", @"选项背景", @"清除背景", @"锁屏背景", @"桌面背景"]' in panel
for target in ('LockScreen', 'Desktop'):
    assert f'@"{target}":@""' in panel and f'@"{target}": @""' in prefs
    assert f'@selector(switch{target}:)' in prefs
assert 'if ([target isEqualToString:@"LockScreen"] || [target isEqualToString:@"Desktop"]) continue;' in prefs
assert 'return LMVEasterTargets().count + 2;' in panel
assert 'static NSArray<NSString *> *LMVTargets(void) { return @[@"Message", @"Options", @"Clear"]; }' in tweak  # Only the message-family backend retains three targets.
delete = (root / 'LockMessageVideoPrefs/LMVMaterialDeletion.h').read_text()
assert '@[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop"]' in delete
for target in ('LockScreen', 'Desktop'):
    assert f'@"{target}":@""' in delete
assert 'CFPreferencesSetAppValue((__bridge CFStringRef)key,CFSTR(""),LMV_DELETE_PREFS_ID)' in delete
assert 'removeItemAtPath' not in delete and delete.count('unlinkat(') == 1
assert 'stringByAppendingString:@"BackgroundEnabled"' in panel
assert 'stringByAppendingString:@"Video"' in panel
assert 'CFNotificationCenterAddObserver' in panel and 'preferencesChanged' in panel
assert 'Photos' not in (root / 'LockMessageVideo.plist').read_text()
assert 'LMVImportMovie' not in media and 'LMVCompressMovie' not in media and 'AVAssetWriter' not in media
assert '[root stringByAppendingPathComponent:@"library"]' in media
assert 'LMVWriteMaterialNames(names)' in media and 'movie)' in media
assert 'LMVEasterFolder' in media and 'parts.count != 2' in media
assert 'stringByResolvingSymlinksInPath' in media and 'lstat(' in media
assert 'NSFileTypeRegular' in media and 'S_ISREG' in media
assert 'NSUUID.UUID.UUIDString' in media and '.pending-' in media
movie = media[media.index('static NSString *LMVEasterImport('):]
assert movie.index('copyItemAtURL:source') < movie.index('tracksWithMediaType:AVMediaTypeVideo') < movie.index('[fm moveItemAtPath:staging')
assert 'if (!error) [fm moveItemAtPath:staging' in movie
assert 'copyNextSampleBuffer' in media and 'dispatch_sync(LMVMaterialQueue()' in media
assert movie.index('[fm moveItemAtPath:staging') < movie.index('error = LMVWriteMaterialNames(names)') < movie.index('else result =')
assert 'if (error) [fm removeItemAtPath:destination error:nil];' in movie
assert 'BOOL success = relative && !error;' in panel and 'if (success) LMVEasterNotify();' in panel
import_callback = panel[panel.index('- (void)picker:(PHPickerViewController *)picker didFinishPicking:'):]
assert 'LMVEasterSet(' not in import_callback and 'CFPreferencesSetAppValue' not in import_callback
assert 'self.busy = YES;' in import_callback and 'panel.busy = NO;' in import_callback
assert 'prompt.promptTitle = success ? @"导入成功" : @"导入失败";' in import_callback
assert 'prompt.message = success ? @"已保存到素材库"' in import_callback
assert 'count > 60' in media and 'kCGImageSourceThumbnailMaxPixelSize:@160' in media
assert '8 * 1024 * 1024' in media and '20 * 1024 * 1024' in media
assert 'totalDuration>60.0' in media and 'LMVEasterPreviewImage' not in media
assert 'LMVEasterVisibleDrawing' in overlay and 'area/full>=0.30' in overlay
assert 'MAX((CGFloat)1200' in overlay and 'UISceneActivationStateUnattached' in overlay
assert 'requireGestureRecognizerToFail:pan' in overlay
assert 'UIGestureRecognizerStateEnded' in overlay and 'EasterEggX' in overlay
assert 'safeAreaInsets' in overlay and 'LMVEasterCenterArea(safeRect, LMVEasterSize())' in overlay
assert 'self.normalized.x' in overlay and 'self.normalized.y' in overlay
assert '- (BOOL)canBecomeKeyWindow { return self.panel != nil && !self.hidden; }' in overlay
assert 'restoreKey' in overlay and 'becomeFirstResponder' not in overlay
hit_start = overlay.index('- (UIView *)hitTest:')
assert 'return nil;' in overlay[hit_start:overlay.index('@end', hit_start)]
assert 'UIWindowLevelAlert - 1' in overlay and 'window.windowLevel >= UIWindowLevelAlert' in overlay
assert 'LMVEasterNCPolicy(blankKnown,blank,lockKnown,locked,host!=nil,&authenticated)' in overlay
assert 'LMVEasterNCWindowExposed(window)' in overlay and 'authenticatedSession' in overlay
assert '@["SBHomeScreenWindow"' not in overlay
assert 'notify_get_state(LMVBlankToken' in overlay
assert 'sharedInstance' not in overlay and 'SBLock' not in overlay and 'SBWall' not in overlay
assert 'UIWindowDidBecomeVisibleNotification' in overlay and 'UISceneDidActivateNotification' in overlay
assert 'generation != manager.generation' in overlay
assert overlay.count('@implementation') == overlay.count('@interface')
start = tweak[tweak.index('static void LMVEasterStartIfReady(void)'):tweak.index('// Public, already-existing')]
assert start.index('!LMVLaunchReady') < start.index('LMVEaster = [LMVEasterManager new]')
assert '%hook UIView' not in tweak and '%hook UIWindow' not in tweak
print('PASS: toggle/picker keys, shared catalog, independent atomic original import, image bounds, no global hook/key window, launch/lock/screen gates, safe drag/state/revision contracts')

assert 'imageControls' not in panel and 'EasterEgg' not in panel
assert 'LMVEasterImageSettings *panel' in prefs
assert 'numberOfSectionsInTableView:' in image and 'return 1;' in image
assert 'LMVEasterTargets' not in image and 'VideoOpacity' not in image
assert 'EasterEggSize' in image and 'LMVEasterSize()' in overlay and 'LMVEasterBoundedSize' in (root / 'LMVEasterGeometry.h').read_text()
assert 'VideoOpacityEnabled' in panel and 'opacityChanged:' in panel
assert 'pushViewController:picker' in panel and 'picker.pushed = YES' in panel
assert 'LMVMaterialDisplayName(relative' in panel
