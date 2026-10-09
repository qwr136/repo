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

assert 'EasterEggEnabled' in prefs and 'EasterEggImage' in media + panel + overlay
assert 'EasterEggPreview' in prefs and 'iconImage' in prefs
assert '@selector(openEaster:)' in prefs and '- (void)openEaster:' in prefs
assert 'LMVMaterialPicker *picker = [LMVMaterialPicker new]' in panel
assert '@["Message"' not in panel
assert '@[@"Message", @"LockScreen", @"Desktop", @"Options", @"Clear"]' in panel
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
assert media.index('copyItemAtURL:source') < media.index('moveItemAtPath:staging')
assert media.index('tracksWithMediaType:AVMediaTypeVideo') < media.index('moveItemAtPath:staging')
assert 'copyNextSampleBuffer' in media and 'dispatch_sync(LMVMaterialQueue()' in media
assert 'count > 60' in media and 'kCGImageSourceThumbnailMaxPixelSize:@160' in media
assert '8 * 1024 * 1024' in media and '20 * 1024 * 1024' in media
assert 'requireGestureRecognizerToFail:pan' in overlay
assert 'UIGestureRecognizerStateEnded' in overlay and 'EasterEggX' in overlay
assert 'safeAreaInsets' in overlay and 'MAX(0, inset.size.width - 64)' in overlay
assert 'self.normalized.x' in overlay and 'self.normalized.y' in overlay
assert '- (BOOL)canBecomeKeyWindow { return NO; }' in overlay
assert 'makeKey' not in overlay and 'becomeFirstResponder' not in overlay
hit_start = overlay.index('- (UIView *)hitTest:')
assert 'return nil;' in overlay[hit_start:overlay.index('@end', hit_start)]
assert 'UIWindowLevelAlert - 1' in overlay and 'window.windowLevel >= level' in overlay
assert 'notify_get_state(LMVLockToken' in overlay and 'blank || locked' in overlay
assert 'sharedInstance' not in overlay and 'SBLock' not in overlay and 'SBWall' not in overlay
assert 'UIWindowDidBecomeVisibleNotification' in overlay and 'UISceneDidActivateNotification' in overlay
assert 'generation != manager.generation' in overlay
assert overlay.count('@implementation') == overlay.count('@interface')
start = tweak[tweak.index('static void LMVEasterStartIfReady(void)'):tweak.index('// Public, already-existing')]
assert start.index('!LMVLaunchReady') < start.index('LMVEaster = [LMVEasterManager new]')
assert '%hook UIView' not in tweak and '%hook UIWindow' not in tweak
print('PASS: toggle/picker keys, shared catalog, independent atomic original import, image bounds, no global hook/key window, launch/lock/screen gates, safe drag/state/revision contracts')
