#!/usr/bin/env python3
"""4.1.0: nothing that is one fact may be written twice.

Three rounds of the same disease, each silent by nature:

  1. eight panel helpers, byte-identical in 2-8 headers each (32 definitions). One
     copy had already drifted - Myrtle's coverage counter lost the 50% rule - and
     nothing in the source said whether that was intentional.
  2. two panels tagged their host view with the same number, so each could adopt the
     other's host when both hung under one parent.
  3. three cache folder names, one digest routine copied five times, and three record
     ceilings typed at both the read and the write side of the same store.

None of these fail to compile. All of them fail quietly. This test fails loudly.
"""
from pathlib import Path
import re
import collections

root = Path(__file__).resolve().parents[1]
common = (root / 'LMVPanelCommon.h').read_text()
common_ui = (root / 'LMVPanelCommonUI.h').read_text()
storage = (root / 'LMVStoragePaths.h').read_text()

panels_helpers = ['LMVSpringBoard', 'LMVVisibleArea', 'LMVColorEqual', 'LMVPerfSample',
                  'LMVWindowReportSnapshot', 'LMVGlassLikeView', 'LMVObjectGetterFor',
                  'LMVMaterialBehindCard']
# These three are the shared implementation and must physically live in the storage header.
storage_helpers = ['LMVStorageHashName', 'LMVStorageHashFileName', 'LMVStorageHashPrefix']
# These five are the per-store wrappers. They stay where they are (their inputs differ:
# one normalizes symlinks, one only standardizes) but each may be defined only once.
store_helpers = ['LMVDiskRecordPath', 'LMVVideoPosterName', 'LMVCacheHashName',
                 'LMVThumbnailRecordPath', 'LMVThumbnailItemID']
all_helpers = panels_helpers + storage_helpers + store_helpers

sources = [p for p in root.rglob('*')
           if p.suffix in ('.h', '.m', '.mm', '.xm') and p.is_file()
           and 'tests' not in p.parts and 'Frameworks' not in p.parts]

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


# 1) Count every definition of every helper, once.
defs = collections.defaultdict(list)
for p in sources:
    text = p.read_text(errors='ignore')
    for name in all_helpers:
        for m in re.finditer(r'(?m)^static(?:\s+inline)?\s[^\n;{}]*?\b' + name + r'\s*\([^;{}]*?\)\s*\{', text):
            defs[name].append(str(p.relative_to(root)))

for name in panels_helpers:
    check(name in common or name in common_ui, name + ' is missing from the shared headers')
    check(len(defs[name]) == 1, '%s is defined %d times: %s' % (name, len(defs[name]), defs[name]))
    if defs[name]:
        check(defs[name][0] in ('LMVPanelCommon.h', 'LMVPanelCommonUI.h'),
              '%s is defined outside the shared headers: %s' % (name, defs[name]))

for name in storage_helpers:
    check(name in storage, name + ' is missing from LMVStoragePaths.h')
    check(len(defs[name]) == 1, '%s is defined %d times: %s' % (name, len(defs[name]), defs[name]))
    if defs[name]:
        check(defs[name][0] == 'LMVStoragePaths.h',
              '%s must live in LMVStoragePaths.h, found in %s' % (name, defs[name]))

for name in store_helpers:
    check(len(defs[name]) == 1,
          '%s is defined %d times: %s' % (name, len(defs[name]), defs[name]))

# 2) Each panel that used to carry a copy now imports the shared header instead.
panels = ['LMVATPanelVideo.h', 'LMVCCBorderVideo.h', 'LMVControlCenterVideo.h',
          'LMVCopyLogXVideo.h', 'LMVCopyVaultPanelVideo.h', 'LMVDesktopVideo.h',
          'LMVEasterOverlay.h', 'LMVGlassSuiteVideo.h', 'LMVHomeMenuVideo.h',
          'LMVLockVideo.h', 'LMVMyrtlePanelVideo.h', 'LMVPhoneAssistVideo.h',
          'LMVSquidPanelVideo.h']
for name in panels:
    text = (root / name).read_text()
    check('#import "LMVPanelCommon.h"' in text or '#import "LMVPanelCommonUI.h"' in text,
          name + ' must import the shared helpers')

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

# 5) The three record cache folders are named once. A second copy is how a sweep ends
#    up scanning a folder nobody writes to - no error, just records never collected.
cache_folders = ['@".material-thumbnails"', '@".background-posters"', '@".last-frames"']
for literal in cache_folders:
    check(literal in storage, literal + ' must be named in LMVStoragePaths.h')
    elsewhere = [str(p.relative_to(root)) for p in sources
                 if p.name != 'LMVStoragePaths.h' and literal in p.read_text(errors='ignore')]
    check(not elsewhere, literal + ' is also typed in %s' % elsewhere)

# 6) The three record ceilings are named, not typed. Three files are exempt on
#    purpose, because their numbers mean something else: LMVMaterialPicker.h uses 6 MB
#    as an NSCache memory budget, LMVEasterMedia.h uses 8 MB and 20 MB as image decode
#    budgets. Same digits, different constraints - merging them would be wrong.
limits = [(r'\b6\s*\*\s*1024\s*\*\s*1024', 'poster image'),
          (r'\b8\s*\*\s*1024\s*\*\s*1024', 'poster record'),
          (r'\b4\s*\*\s*1024\s*\*\s*1024', 'frame image')]
for pattern, label in limits:
    rx = re.compile(pattern)
    bare = []
    for p in sources:
        if p.name in ('LMVStoragePaths.h', 'LMVMaterialPicker.h', 'LMVEasterMedia.h'):
            continue
        for line in p.read_text(errors='ignore').splitlines():
            if line.lstrip().startswith('//'):
                continue
            if rx.search(line):
                bare.append('%s: %s' % (p.name, line.strip()[:70]))
    check(not bare, '%s ceiling is still a bare number: %s' % (label, bare))

# 7) The settings page has two lists that used to be hand-written in several places.
#    Both now derive from the one table; a second copy is how the wrong channel gets a
#    notification and a recycled cell keeps the previous row's colour swatch.
page = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
check('for (NSString *target in LMVChannelIDs())' in page,
      'the switch-to-channel prefix lookup must come from the channel table')
check('@"GS",@"CopyLogX",@"CCBorder"' not in page,
      'the channel prefix list is hand-written again')
for base in ('0x5A2C', '0x5B2C', '0x5C2C', '0x5D2C', '0x5E2C'):
    check(page.count('@(%s)' % base) == 1,
          'colour tag base %s appears %d times; it belongs in LMVTextColorRows() once'
          % (base, page.count('@(%s)' % base)))
check('LMVTextColorRows()' in page and page.count('static NSArray<NSDictionary *> *LMVTextColorRows(void)') == 1,
      'the colour rows must come from one table')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 4.2.0 - 8 panel helpers, 3 hash helpers and 5 store wrappers defined once; '
      '13 panels import the shared header; 8 host tags, 3 cache folders, 3 ceilings, one colour-row table')
