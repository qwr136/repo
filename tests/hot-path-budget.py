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


# 1) row paint never reads the catalog itself - it shares one parsed copy per refresh
paint = slice_between(page, '- (void)paintMaterialName:(NSString *)materialID inCell:(UITableViewCell *)cell {',
                      '- (void)tableView:(UITableView *)tableView willDisplayCell:')
check('LMVReadMaterialNames()' not in paint,
      'paintMaterialName must not parse material-names.plist; it runs once per painted row')
check('[self materialNames]' in paint, 'paintMaterialName must use the shared catalog copy')
# 2) refresh repaints through reloadData only
refresh = slice_between(page, '- (void)refreshMaterialRows {', '- (void)viewWillAppear:')
check('[self.table reloadData];' in refresh, 'refreshMaterialRows must reload the table')
check('self.materialNamesCache = nil;' in refresh,
      'refreshMaterialRows must drop the cached catalog so the next paint re-reads it')
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

# 5.1.5: five hot-path clean-ups, each pinned so a later edit cannot silently undo it.
_media = (root / 'LMVMediaAudio.h').read_text()
_playback = (root / 'LMVLockVideoPlayback.h').read_text()
_desktop = (root / 'LMVDesktopVideo.h').read_text()

# (a) one channel notification reloads one channel, not sixteen
check('static void LMVAudioReloadTarget(NSString *only)' in _media,
      'audio reload is not scoped to a single channel')
check('reloadTargets = only.length ? @[only] : LMVAudioTargets()' in _media,
      'scoped audio reload still walks every target')
check('LMVPreferencesScope' in tweak and 'LMVLoadPreferencesTarget(target)' in tweak,
      'the per-channel path does not scope the preference load')
check('LMVReloadAudioControlsFor(target)' in tweak,
      'the per-channel path still reloads every channel')
# (b) the playing asset must not ask for frame-accurate timing
check(_playback.count('AVURLAssetPreferPreciseDurationAndTimingKey') >= 2,
      'the playing asset still scans the whole sample table')
check('options:nil];' not in _playback.split('- (void)selectPath')[1].split('loadValuesAsynchronouslyForKeys')[0],
      'selectPath still builds its asset with options:nil')
# (c) frame 0 is decoded once when a poster is already on screen
check('posterReady' in _playback, 'the duplicate 1280 poster decode is back')
# (d) stale key-window probes are dropped
check('windowProbeGen' in _desktop and 'manager.windowProbeGen!=probeGen' in _desktop,
      'queued key-window probes have no epoch guard')
# (e) the unreachable rate!=1.0 branch stays deleted
check('rate!=1.0' not in _media, 'the dead manual-loop branch is back')
check('AVPlayerLooper playerLooperWithPlayer' in _media, 'the looper path disappeared')

# 5.1.7: panel writes must be scoped to one channel, never the global sweep.
_panel = (root / 'LMVEasterPanel.h').read_text()
_emed = (root / 'LMVEasterMedia.h').read_text()
check('LMVEasterSetTarget(key, relative, LMVEasterRefreshTargetForKey(key))' in _panel,
      'a material switch still posts the global notification')
check(_panel.count('LMVEasterSetTarget(') >= 2,
      'the material / sound writes are not scoped to their channel')
check('LMVEasterSetLocal([target stringByAppendingString:@"Volume"]' in _panel,
      'the volume write no longer happens on every frame')
check('LMVEasterNotifyTarget(target);' in _panel,
      'the throttled volume announcement is missing')
check('LMVEasterSetLocal(@"EasterPanelScrollY"' in _panel,
      'saving the scroll position still fires a refresh')
check('volumeNow - LMVEasterLastVolumeNotify >= 0.1' in _panel,
      'the volume slider notifies on every frame again')
check('preferencesChanged." stringByAppendingString:target' in _emed,
      'the scoped notification name is not built')

# 5.1.8: one switch must not rebuild the panel; a drag must not relay out the table.
def _method_body(text, signature):
    return text.split(signature, 1)[1].split('\n- (', 1)[0]

check('cell.imageView.image=nil;' in _panel,
      'a reused cell keeps the import row icon on unrelated rows')
check('[self.tableView reloadData]' not in _method_body(_panel, '- (void)soundChanged:'),
      'a sound toggle still reloads all eighteen sections')
check('[self.tableView reloadData]' not in _method_body(_panel, '- (void)volumeChanged:'),
      'releasing the volume slider still reloads the panel')
_overlay = (root / 'LMVEasterOverlay.h').read_text()
_drag = _method_body(_overlay, '- (void)dragPanel:')
check('self.panel.view.center = CGPointMake(' in _drag,
      'the drag does not move the panel while the finger is down')
check('self.panel.view.frame =' not in _drag,
      'the drag writes -frame again, which relays out the table on every touch move')
check('[self layout];' in _drag and _drag.count('[self layout];') == 1,
      'the drag lays out more than once')

if failures:
    for failure in failures:
        print('FAIL: ' + failure)
    raise SystemExit(1)
print('PASS: 4.1.1 - one catalog parse per refresh, one prefs load per switch, one ancestry walk per cell per frame; '
      '5.1.5 - scoped reload, non-precise asset, one poster decode, epoch-guarded probes, no dead loop branch')
