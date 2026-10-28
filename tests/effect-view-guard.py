#!/usr/bin/env python3
"""5.2.0: never add a subview to a UIVisualEffectView, and never let the exception out.

A UIVisualEffectView refuses direct subviews; -addSubview: / -insertSubview: raise.
Every mount site here runs from a display-link tick or a run-loop callback, so an
escaping exception aborts SpringBoard - the 5.1.x safe-mode report was exactly that
(`-[UIVisualEffectView _addSubview:positioned:relativeTo:]` on the main thread inside
CADisplayLink::dispatch_items).

Three rules are pinned:
  1. the notification-card mount (「选项 / 清除」actions on iOS 16) diverts into
     -contentView and catches;
  2. no mount site inserts without an exception guard;
  3. the panel channels keep their existing "never into the effect view" helper.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


tweak = (root / 'Tweak.xm').read_text()
lock = (root / 'LMVLockVideo.h').read_text()
desktop = (root / 'LMVDesktopVideo.h').read_text()
menu = (root / 'LMVHomeMenuVideo.h').read_text()

# 1) card mount: effect view is detected and diverted, exception caught
check('NSClassFromString(@"UIVisualEffectView")' in tweak,
      'the card mount does not look for a UIVisualEffectView host')
check('insertionParent = [host valueForKey:@"contentView"]' in tweak,
      'the card mount does not divert into the effect view contentView')
check('[host insertSubview:state.overlay aboveSubview:anchor]' not in tweak,
      'the card mount still inserts into the raw host')
check('@catch (NSException *exception) { [state.overlay removeFromSuperview]; }' in tweak,
      'the card mount lets an insertion exception escape')

# 2) every remaining mount site has a guard
for name, text, marker in (
        ('LMVLockVideo.h', lock, 'insertSubview:self.host'),
        ('LMVDesktopVideo.h', desktop, 'insertSubview:self.host'),
        ('LMVHomeMenuVideo.h', menu, 'insertSubview:self.host')):
    lines = [line for line in text.splitlines() if marker in line and '@try' not in line]
    check(not lines, f'{name} inserts a host without an exception guard: {lines[:2]}')
    check('@catch(NSException *ignored)' in text, f'{name} has no catch around its mount')

# 3) the panel channels still refuse the effect view outright
at = (root / 'LMVATPanelVideo.h').read_text()
check('[container isKindOfClass:UIVisualEffectView.class]' in at,
      'the panel mount lost its effect-view refusal')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 5.2.0 - card mount diverts into contentView, every host insertion is '
      'exception-guarded, panels still refuse the effect view')
