#!/usr/bin/env python3
"""4.0.9: no helper routine and no view tag may exist twice.

Before this version eight helper routines were byte-identical in 2-8 panel headers
each (32 definitions, ~200 lines), and two panels had tagged their host view with
the same number. Both are silent by nature: nothing fails to compile, the copies
just drift apart (Myrtle's coverage counter had already lost the 50% rule) and a
clashing tag only misbehaves when the two panels share a parent view.

This test fails if any of that comes back.
"""
from pathlib import Path
import re
import collections

root = Path(__file__).resolve().parents[1]
common = (root / 'LMVPanelCommon.h').read_text()

helpers = ['LMVSpringBoard', 'LMVVisibleArea', 'LMVColorEqual', 'LMVPerfSample',
           'LMVWindowReportSnapshot', 'LMVGlassLikeView', 'LMVObjectGetterFor',
           'LMVMaterialBehindCard']

sources = [p for p in root.rglob('*')
           if p.suffix in ('.h', '.m', '.mm', '.xm') and p.is_file()
           and 'tests' not in p.parts and 'Frameworks' not in p.parts]

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


# 1) Every helper is defined exactly once, in the shared header.
defs = collections.defaultdict(list)
for p in sources:
    text = p.read_text(errors='ignore')
    for name in helpers:
        for m in re.finditer(r'(?m)^static(?:\s+inline)?\s[^\n;{}]*?\b' + name + r'\s*\([^;{}]*?\)\s*\{', text):
            defs[name].append(str(p.relative_to(root)))
for name in helpers:
    check(name in common, name + ' is missing from the shared header')
    check(len(defs[name]) == 1, '%s is defined %d times: %s' % (name, len(defs[name]), defs[name]))
    if defs[name]:
        check(defs[name][0] == 'LMVPanelCommon.h',
              '%s is defined outside the shared header: %s' % (name, defs[name]))

# 2) Each panel that used to carry a copy now imports the shared header instead.
panels = ['LMVATPanelVideo.h', 'LMVCCBorderVideo.h', 'LMVControlCenterVideo.h',
          'LMVCopyLogXVideo.h', 'LMVCopyVaultPanelVideo.h', 'LMVDesktopVideo.h',
          'LMVEasterOverlay.h', 'LMVGlassSuiteVideo.h', 'LMVHomeMenuVideo.h',
          'LMVLockVideo.h', 'LMVMyrtlePanelVideo.h', 'LMVPhoneAssistVideo.h',
          'LMVSquidPanelVideo.h']
for name in panels:
    text = (root / name).read_text()
    check('#import "LMVPanelCommon.h"' in text, name + ' must import the shared helpers')

# 3) No per-panel prefix survived on the eight helpers.
prefixes = r'(ATPanel|CCBorder|CopyLogX|CVPanel|GlassSuite|HomeMenu|PhoneAssist|Squid|Myrtle|DesktopVideo|LockVideo|Easter|CC)'
suffixes = r'(SpringBoard|VisibleArea|ColorEqual|Perf|WindowReport|GlassKind|ObjectGetter)'
for p in sources:
    text = p.read_text(errors='ignore')
    for m in re.finditer(r'\bLMV' + prefixes + suffixes + r'\b', text):
        failures.append('per-panel copy is back: %s in %s' % (m.group(0), p.relative_to(root)))

# 4) View tags are unique: a shared number lets two panels adopt each other's host.
tags = {}
for p in sources:
    for m in re.finditer(r'static\s+NSInteger\s+const\s+(LMV\w*HostTag)\s*=\s*(0x[0-9A-Fa-f]+)', p.read_text(errors='ignore')):
        tags.setdefault(m.group(2).lower(), []).append((m.group(1), str(p.relative_to(root))))
for value, owners in tags.items():
    check(len(owners) == 1, 'tag %s is used by more than one panel: %s' % (value, owners))
check(len(tags) == 8, 'expected 8 host tags, found %d' % len(tags))

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 4.0.9 - 8 helpers defined once, 13 panels import them, 8 host tags unique')
