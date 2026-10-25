#!/usr/bin/env python3
"""4.0.7: one channel table, one storage root.

Before this, the channel list was copied into five places and the storage path
into thirteen; two shipped bugs were missed copies. This test fails if any of
those lists is hand-written again.
"""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
channels = (root / 'LockMessageVideoPrefs/LMVChannels.h').read_text()
storage = (root / 'LMVStoragePaths.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
page = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
delete = (root / 'LockMessageVideoPrefs/LMVMaterialDeletion.h').read_text()
audio = (root / 'LMVMediaAudio.h').read_text()
panel = (root / 'LMVEasterPanel.h').read_text()

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


rows = re.findall(r'@"id": @"([A-Za-z]+)"', channels)
check(len(rows) == 16, 'the channel table must hold 16 channels, found %d' % len(rows))
check(len(set(rows)) == len(rows), 'duplicate channel ids in the table')
for required in ('Message', 'Options', 'Clear', 'SquidPanel', 'CopyLogX'):
    check(required in rows, 'channel table lost ' + required)

# Each consumer derives instead of copying.
check('return LMVCardChannelIDs();' in tweak, 'tweak card targets must come from the table')
check('LMVCardLegacyDefaults()' in tweak, 'legacy card sources must come from the table')
check('arrayWithArray:LMVChannelIDs()' in tweak, 'notification registration must come from the table')
check('return [LMVChannelIDs() containsObject:target];' in page, 'settings allow-list must come from the table')
check('NSDictionary *titles = LMVChannelTitles();' in page, 'alert titles must come from the table')
check('LMVSectionChannelIDs()' in page, 'the five sections must come from the table')
check('NSDictionary *defaults=LMVChannelLegacyDefaults();' in delete and
      'for (NSString *target in LMVChannelIDs())' in delete, 'deletion sweep must come from the table')
check('return LMVChannelIDs();' in audio, 'audio list must come from the table')
check('LMVSectionChannelIDs()' in panel, 'panel sections must come from the table')

# No hand-written copies left outside the table.
check('@[@"Message",@"Options",@"Clear",@"LockScreen"' not in audio, 'audio list is hand-written again')
check('@"CopyLogX":@"CopyLogX背景"' not in page, 'titles are hand-written again')

# One storage root.
check('LMVStorageRootPath = @"/var/mobile/LockMessageVideo";' in storage, 'storage root constant missing')
code = ''.join(p.read_text(errors='ignore') for p in root.rglob('*')
               if p.suffix in ('.h', '.m', '.xm') and p.is_file() and 'tests' not in p.parts)
# One canonical constant plus one fixture-isolated fallback (the logger header is
# copied into a temp dir and cannot import anything).
check(code.count('@"/var/mobile/LockMessageVideo"') == 2,
      'the storage path is typed out %d times (expected 2)' % code.count('@"/var/mobile/LockMessageVideo"'))


# 4.0.8: subfolder names, the index file name and the legacy material names are
# also named once. Comments may mention them; code may not.
def code_lines():
    for path in root.rglob('*'):
        if path.suffix not in ('.h', '.m', '.xm') or not path.is_file() or 'tests' in path.parts:
            continue
        for line in path.read_text(errors='ignore').splitlines():
            if line.lstrip().startswith('//'):
                continue
            yield path, line

for needle, where in ((r'@"library"', 'storage header'), (r'@"images"', 'storage header'),
                      (r'material-names\.plist', 'storage header'),
                      (r'message\.mov|options\.mov|clear\.mov', 'channel table'),
                      (r'stringByAppendingPathComponent:@"小彩蛋"', 'storage header')):
    hits = [(p, line.strip()) for p, line in code_lines() if re.search(needle, line)]
    allowed = [h for h in hits if str(h[0]).endswith('LMVStoragePaths.h') or str(h[0]).endswith('LMVChannels.h')]
    check(len(hits) == len(allowed), '%s is typed outside the %s: %s' % (needle, where, [str(h[0]) for h in hits if h not in allowed]))

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 4.0.9 - 16 channels, one table, one storage root, one name per folder/index/legacy file')
