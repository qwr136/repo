#!/usr/bin/env python3
"""0.0.124: pending-state thumbnail ("生成中…") with timed retry on the floating
panel; settings icon, draggable floating panel, panel previews, and the
floating-panel appearance controls (corner radius / width / height) all
unchanged from 0.0.123.

Source contracts plus a real PNG-header read for the supplied artwork. The pure
appearance rules are executed natively in tests/easter-panel-appearance.m on
macOS CI; this file never re-implements them, so the two cannot drift.
"""
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
header = (root / 'LMVEasterPanelAppearance.h').read_text()
overlay = (root / 'LMVEasterOverlay.h').read_text()
image = (root / 'LMVEasterImageSettings.h').read_text()
panel = (root / 'LMVEasterPanel.h').read_text()
makefile = (root / 'Makefile').read_text()
bundle_info = (root / 'LockMessageVideoPrefs/Info.plist').read_text()
entry = (root / 'layout/Library/PreferenceLoader/Preferences/LockMessageVideoPrefs.plist').read_text()

# ---- (1) settings icon: the supplied artwork, 88x88, packed into the bundle -----
# Read the real PNG header instead of trusting the file name.
# 29 pt is the size Settings uses for its rows; the 88x88 artwork is the source,
# and @3x lands on 87 px. (88 px as @1x rendered visibly larger than every other
# plug-in in the list.)
for name, size in [('icon.png', 29), ('icon@2x.png', 58), ('icon@3x.png', 87)]:
    data = (root / 'LockMessageVideoPrefs' / name).read_bytes()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', name
    width, height = struct.unpack('>II', data[16:24])
    assert (width, height) == (size, size), (name, width, height)
    assert 'LockMessageVideoPrefs/' + name in makefile, name
assert 'CFBundleIconFile' in bundle_info and '<string>icon</string>' in bundle_info
assert '<key>icon</key>' in entry, 'PreferenceLoader entry carries the icon too'

# ---- (2) draggable panel: title bar only, session-kept, always on screen --------
assert '@property(nonatomic) CGPoint panelOffset;' in overlay
assert '- (void)dragPanel:(UIPanGestureRecognizer *)pan {' in overlay
assert '[self.panel.navigationBar addGestureRecognizer:panelDrag];' in overlay
assert 'panelDrag.maximumNumberOfTouches = 1;' in overlay
assert 'self.panelOffset = CGPointMake(self.panelOffset.x + translation.x, self.panelOffset.y + translation.y);' in overlay
assert 'maxOffsetX' in overlay and 'minOffsetY' in overlay and 'maxOffsetY' in overlay, \
    'dragging is re-clamped so the panel can never leave the screen'
assert 'self.panelOffset = CGPointZero' not in overlay, \
    'the position is kept while the session lives'

# ---- (3) previews inside the floating panel ------------------------------------
# The picker already loads them on ONE utility queue, caches in an NSCache,
# remembers failures and only touches visible rows - it is simply switched on.
assert 'picker.showsThumbnails = YES' in panel
# 0.0.123: a transient decode failure used to park a row on the placeholder for the
# whole session (these rows were showing the film symbol), so the failure memory is
# now a bounded retry, and two workers fill a long list faster.
_picker = (root / 'LockMessageVideoPrefs/LMVMaterialPicker.h').read_text()
assert 'sharedQueue.maxConcurrentOperationCount = 2;' in _picker
assert 'NSInteger failures = self.thumbnailFailures[key].integerValue;' in _picker
assert 'if (failures >= LMVMaterialThumbnailMaxFailures)' in _picker
assert 'picker.thumbnailFailures[key] = @(failures + 1);' in _picker
assert '[picker.thumbnailFailures removeObjectForKey:key];' in _picker
# 0.0.125: Settings and the floating panel share ONE cache/queue/retry ledger per
# process (cross-process sharing stays on the disk sidecar), a decode lands in
# the shared cache even if its picker closed mid-flight, and closing a picker
# never cancels the shared queue.
assert 'static NSCache<NSString *, UIImage *> *sharedThumbnails;' in _picker
assert '_thumbnails = sharedThumbnails;' in _picker
assert '_thumbnailQueue = sharedQueue;' in _picker
assert '_thumbnailFailures = sharedFailures;' in _picker
assert '_thumbnailRetries = sharedRetries;' in _picker
assert '_retryScheduled = sharedScheduled;' in _picker
assert '_pending = sharedPending;' in _picker
assert 'if (poster) [sharedCache setObject:poster forKey:key cost:cost];' in _picker
assert '[sharedPending removeObject:key];' in _picker, 'pending clears even when the picker closed'
assert '[scheduled removeObject:key];' in _picker and '[ledger removeObjectForKey:key];' in _picker, 'retry ledger survives a closed picker'
assert '- (void)dealloc { [_thumbnailQueue cancelAllOperations]; }' not in _picker
# 0.0.124: a row with no poster yet is NOT shown as the film icon - it says 生成中
# and is retried on a timer, so a freshly imported movie fills itself in without
# leaving and re-entering the list.
assert 'static const NSInteger LMVMaterialThumbnailRetryLimit = 6;' in _picker
assert 'static const NSTimeInterval LMVMaterialThumbnailRetryDelay = 3.0;' in _picker
assert '- (BOOL)thumbnailIsPending:(NSDictionary *)row {' in _picker
assert '- (void)scheduleRetryForKey:(NSString *)key {' in _picker
assert '[picker scheduleRetryForKey:key];' in _picker
assert 'if (self.thumbnailRetries[key].integerValue >= LMVMaterialThumbnailRetryLimit) return;' in _picker
assert 'if (!key.length || [self.retryScheduled containsObject:key]) return;' in _picker, 'one timer per row'
# 0.0.125: a retry re-requests by ROW from the whole catalog, so a round is never
# consumed by a row that merely scrolled off screen.
assert 'for (NSDictionary *material in picker.materials)' in _picker
assert '@"生成中…"' in _picker
assert 'poster ?: [UIImage systemImageNamed:pending ? @"arrow.triangle.2.circlepath" : @"film"]' in _picker
assert 'showsThumbnails = NO' not in panel

# ---- (4)(5) corner radius + width/height on the page both entries share --------
for key in ('EasterPanelCornerEnabled', 'EasterPanelCorner', 'EasterPanelSizeEnabled',
            'EasterPanelWidthScale', 'EasterPanelHeightScale'):
    assert key in header, key
    assert key in image, key
assert 'if (section == LMVEasterImagePanelSection()) return 6;' in image
# A bad edit once made the new helper call ITSELF (compiles into infinite recursion
# and passes every string check), so the chain and the section count are pinned here.
import re as _re
for _helper in ('LMVEasterImageSection', 'LMVEasterImageDisplaySection',
                'LMVEasterImageRotationSection', 'LMVEasterImagePanelSection'):
    _body = _re.search(r'static NSInteger %s\(void\) \{ return ([^;]+); \}' % _helper, image)
    assert _body, _helper
    assert _helper + '()' not in _body.group(1), _helper + ' must not call itself'
assert 'static NSInteger LMVEasterImagePanelSection(void) { return LMVEasterImageRotationSection() + 1; }' in image
assert 'numberOfSectionsInTableView:(UITableView *)tableView { return LMVEasterImagePanelSection() + 1; }' in image
assert 'return @"悬浮窗外观";' in image
for selector in ('panelCornerToggled:', 'panelCornerChanged:', 'panelSizeToggled:', 'panelScaleChanged:', 'panelHapticToggled:'):
    assert 'action:@selector(%s)' % selector in image, selector
# 0.0.131: the ball tap haptic - on by default, toggled from this shared page so
# both entries (settings and the floating panel) change the same switch.
assert '@"悬浮球震动"' in image
assert 'EasterBallHapticEnabled' in image
assert 'LMVEasterPanelToggle(LMVEasterRead(@"EasterBallHapticEnabled"), YES)' in image
# Ranges and defaults keep the previous behaviour when the user never touches them.
assert '#define LMVEasterPanelCornerFallback 20.0' in header
assert '#define LMVEasterPanelCornerMin 0.0' in header and '#define LMVEasterPanelCornerMax 60.0' in header
assert '#define LMVEasterPanelScaleMin 0.5' in header and '#define LMVEasterPanelScaleMax 1.5' in header
# This header is included by BOTH compile units (SpringBoard tweak and the Prefs
# bundle) and each uses only part of it, so every helper must be static inline:
# a plain static function trips -Wunused-function in the other unit.
import re as _re2
assert not _re2.findall(r'^static (?!inline)\S+ \*?(\w+)\(', header, _re2.M), \
    'every helper in this shared header must be static inline'
assert 'LMVEasterPanelToggle(enabled, YES)' in header, 'corner defaults to on'
assert 'LMVEasterPanelToggle(enabled, NO)' in header, 'custom size defaults to off'
# Both entry points reach this one page, so both get the controls.
assert '#import "LMVEasterPanelAppearance.h"' in overlay and '#import "LMVEasterPanelAppearance.h"' in image
assert 'pushViewController:[LMVEasterImageSettings new]' in panel

# ---- native: execute the appearance rules where a toolchain exists -------------
if sys.platform != 'darwin':
    print('SKIP native: appearance-rule execution needs Foundation/UIKit; run on macOS CI')
    raise SystemExit(0)
with tempfile.TemporaryDirectory() as directory:
    binary = Path(directory) / 'lmv-easter-panel-appearance'
    subprocess.run(['clang', '-fobjc-arc', str(root / 'tests/easter-panel-appearance.m'),
                    '-framework', 'Foundation', '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
print('PASS: 88x88 settings icon packed and declared, panel drag by title bar (clamped), '
      'panel previews on, and corner/size controls shared by both entry points')
