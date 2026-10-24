#!/usr/bin/env python3
"""4.0.6: the three hot paths must not do the same work twice.

  1. settings row paint: one catalog read per row, not two;
  2. one material switch: one preference load, not two;
  3. display-link tick: one exposure read + one ancestry walk per cell,
     not two extra view-tree walks per target.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tweak = (root / 'Tweak.xm').read_text()
page = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
card = (root / 'LMVCardPresentation.h').read_text()

failures = []


def check(ok, message):
    if not ok:
        failures.append(message)


def slice_between(text, start, end):
    a = text.index(start)
    b = text.index(end, a)
    return text[a:b]


# 1) row paint reads the catalog once
paint = slice_between(page, '- (void)paintMaterialName:', '- (void)tableView:(UITableView *)tableView willDisplayCell:')
check(paint.count('LMVReadMaterialNames()') == 1,
      'paintMaterialName must read material-names.plist once, found %d' % paint.count('LMVReadMaterialNames()'))
# 2) refresh repaints through reloadData only
refresh = slice_between(page, '- (void)refreshMaterialRows {', '- (void)viewWillAppear:')
check('[self.table reloadData];' in refresh, 'refreshMaterialRows must reload the table')
check('visibleCells' not in refresh, 'the manual paint loop is redundant with reloadData')

# 3) a material switch loads preferences once
check('else { LMVRefresh(NO); return; }' in tweak,
      'a per-channel notification must not reload preferences a second time')
check('else { LMVRefresh(reload); return; }' not in tweak, 'the double load is back')

# 4) the tick computes ancestry/exposure once per cell
_t = tweak.index('- (void)tick:(CADisplayLink *)link {')
tick = tweak[_t:_t + 8000]
check('BOOL cellOnNotificationCenter=LMVNotificationCenterSurface(cell);' in tick,
      'tick must walk the cell ancestry once per frame')
check('LMVCardStateVisibleInScope(cell,state,target,cellVisible,cellOnNotificationCenter)' in tick,
      'tick must reuse the per-frame visibility instead of recomputing it per target')
check('LMVCardStateVisible(cell,state,target)' not in tick,
      'tick still calls the per-target variant that walks the tree again')
check('static BOOL LMVCardStateVisibleInScope(' in tweak, 'the scoped variant must exist')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 4.0.6 - one catalog read per row, one prefs load per switch, one ancestry walk per cell per frame')
