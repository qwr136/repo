#!/usr/bin/env python3
"""4.0.2: every channel the settings page can switch must be listened to.

Darwin notifications have no wildcards, so Tweak.xm registers each per-target
name explicitly. 3.05 added per-channel notifications but left Message /
Options / Clear out of the list: switching their material posted
"...preferencesChanged.Message" to a name nobody observed, so the notification
card kept playing the old video until a respring.

This test derives the channels from the settings controller and asserts that
each one has a matching observer, and that an unknown name still falls back to
the full refresh instead of silently doing nothing.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
tweak = (root / 'Tweak.xm').read_text()
page = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


# Channels the page can switch: every switchX: method's target.
targets = set(re.findall(r'\[self switchTarget:@"([A-Za-z]+)"\]', page))
check(targets, 'no switchTarget calls found in the settings page')
for required in ('Message', 'Options', 'Clear'):
    check(required in targets, 'settings page lost its %s switch' % required)

# The registration block: the channel array in the observer setup.
m = re.search(r'for \(NSString \*channel in @\[(.*?)\]\)', tweak, re.S)
check(m is not None, 'per-target notification registration block not found')
block = m.group(1) if m else ''

for target in sorted(targets):
    check('@"%s"' % target in block,
          'channel %s posts preferencesChanged.%s but nothing observes it' % (target, target))

# Unknown names must not be dropped on the floor.
check('else { LMVRefresh(NO); return; }' in tweak,
      'an unregistered channel name must fall back to the full refresh')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 4.0.2 - every switchable channel (%d) has a Darwin observer, unknown names fall back to a full refresh' % len(targets))
