#!/usr/bin/env python3
"""5.23: display-link callbacks must not read cfprefsd per frame."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
def check(ok, msg):
    print(('PASS: ' if ok else 'FAIL: ') + msg)
    if not ok:
        raise SystemExit(1)
tuning = (root / 'LMVPanelTuning.h').read_text()
lock = (root / 'LMVLockVideo.h').read_text()
cc = (root / 'LMVControlCenterVideo.h').read_text()
check('static inline NSInteger LMVTuneCachedValue(' in tuning, 'cached reader exists')
lt = lock[lock.index('- (void)tick:(CADisplayLink *)link {'):lock.index('- (void)releasePaint {')]
check('LMVTuneCachedValue(@"LockNC",@"ProbeHz"' in lt and 'LMVTuneValue(@"LockNC",@"ProbeHz")' not in lt, 'lock tick cached')
ct = cc[cc.index('- (void)geometryTick:(CADisplayLink *)link {'):cc.index('- (void)update {')]
check('LMVTuneCachedValue(@"CC",@"ProbeHz"' in ct and 'LMVTuneValue(@"CC",@"ProbeHz")' not in ct, 'control centre tick cached')
check('LMVTuneCachedValue(@"CC",@"UpdateIntervalMs"' in cc, 'maintenance timer cached')
print('PASS: tuning reads cached; device frame pacing not measured')
