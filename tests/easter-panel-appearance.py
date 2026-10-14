#!/usr/bin/env python3
"""0.0.122: settings icon, draggable floating panel, panel previews, and the
floating-panel appearance controls (corner radius / width / height).

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
for name, size in [('icon.png', 88), ('icon@2x.png', 176), ('icon@3x.png', 264)]:
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
assert 'showsThumbnails = NO' not in panel

# ---- (4)(5) corner radius + width/height on the page both entries share --------
for key in ('EasterPanelCornerEnabled', 'EasterPanelCorner', 'EasterPanelSizeEnabled',
            'EasterPanelWidthScale', 'EasterPanelHeightScale'):
    assert key in header, key
    assert key in image, key
assert 'if (section == LMVEasterImagePanelSection()) return 5;' in image
assert 'return @"悬浮窗外观";' in image
for selector in ('panelCornerToggled:', 'panelCornerChanged:', 'panelSizeToggled:', 'panelScaleChanged:'):
    assert 'action:@selector(%s)' % selector in image, selector
# Ranges and defaults keep the previous behaviour when the user never touches them.
assert '#define LMVEasterPanelCornerFallback 20.0' in header
assert '#define LMVEasterPanelCornerMin 0.0' in header and '#define LMVEasterPanelCornerMax 60.0' in header
assert '#define LMVEasterPanelScaleMin 0.5' in header and '#define LMVEasterPanelScaleMax 1.5' in header
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
