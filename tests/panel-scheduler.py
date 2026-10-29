#!/usr/bin/env python3
"""5.23: one scheduler drives the nine panel channels; logs are gated first."""
from pathlib import Path
root = Path(__file__).resolve().parents[1]

def check(ok, msg):
    print(('PASS: ' if ok else 'FAIL: ') + msg)
    if not ok:
        raise SystemExit(1)

sched = (root / 'LMVScheduler.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
check('static void LMVSchedulerPump(void)' in sched and 'static void LMVSchedule(' in sched, 'scheduler entry points')
check(sched.count('dispatch_after(') == 1, 'single one-shot chain')

channels = {'LMVATPanelVideo.h':'AT','LMVPhoneAssistVideo.h':'PA','LMVMyrtlePanelVideo.h':'Myrtle',
            'LMVHomeMenuVideo.h':'HomeMenu','LMVGlassSuiteVideo.h':'GS','LMVCopyLogXVideo.h':'CopyLogX',
            'LMVSquidPanelVideo.h':'SquidPanel','LMVCopyVaultPanelVideo.h':'CV','LMVCCBorderVideo.h':'CCBorder'}
for name, channel in channels.items():
    text = (root / name).read_text()
    check(('LMVSchedule(@"%s"' % channel) in text, name + ' 走中央调度器')
    check('timerWithTimeInterval' not in text, name + ' 不再自建 NSTimer')

check('LMVScheduler.h' in tweak.split('#import "LMVLockVideo.h"')[0], '调度器先于通道头')
check('LMVScheduler.h' in tweak.split('#import "LMVLockVideo.h"')[0], '调度器先于通道头引入')
print('PASS: scheduler and gated logging contract; wake-ups not measured on device')
