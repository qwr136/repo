#!/usr/bin/env python3
# 0.0.80 contract: a visible Notification Center card is fully updated on a single
# 100 ms cadence, and the cadence is tracked per cell.
#
# Before 0.0.80 the display-link tick used one global `discover` window (0.20 s).
# On the first frame after that window elapsed EVERY visible card ran the full
# LMVUpdate path in the same tick, so a pull-down animation collided with a burst
# of discovery + layout work. The fix gives every visible card its own timestamp
# and a 100 ms interval, so the work is spread out and bounded.
import pathlib, re, sys

root = pathlib.Path(__file__).resolve().parent.parent
tweak = (root / 'Tweak.xm').read_text()

fail = []
def check(cond, label):
    if not cond:
        fail.append(label)

# --- the interval constant exists, is 0.1 s, and is the only cadence value ---
check('static const CFTimeInterval LMVCardUpdateInterval = 0.1;' in tweak,
      'LMVCardUpdateInterval must be declared as 0.1')
check(tweak.count('LMVCardUpdateInterval') >= 4,
      'LMVCardUpdateInterval must be used by both the tick loop and the discovery path')

# --- the per-cell timestamp key is declared alongside the other associated keys ---
check('LMVCardUpdateKey' in tweak, 'LMVCardUpdateKey must exist')
decl = re.search(r'static char ([^;]*LMVCardUpdateKey[^;]*);', tweak)
check(decl is not None, 'LMVCardUpdateKey must be declared in the associated-object key list')

# --- the global discovery window must be gone ---
check('lastDiscovery' not in tweak,
      'the old global `lastDiscovery` window must be removed')
check('discover && cellVisible' not in tweak,
      'the old `discover && cellVisible` burst trigger must be removed')

# --- the tick loop throttles each visible card independently ---
tick = tweak[tweak.index('- (void)tick:(CADisplayLink *)link {'):]
tick = tick[:tick.index('nextSource++;')]

check('objc_getAssociatedObject(cell,&LMVCardUpdateKey)' in tick,
      'tick must read the per-cell last-update timestamp')
check('objc_setAssociatedObject(cell,&LMVCardUpdateKey,@(link.timestamp)' in tick,
      'tick must stamp the per-cell timestamp when a card is updated')
check('link.timestamp-lastUpdate.doubleValue>=LMVCardUpdateInterval' in tick,
      'the per-cell due check must compare against LMVCardUpdateInterval')
check('if (changed || due) LMVUpdate(cell);' in tick,
      'a card must be fully updated when it changed, or when it is due')
# The full update must NOT run merely because the cell is visible.
check('(discover && cellVisible)' not in tick,
      'visibility alone must never trigger a full update in the tick')

# --- the discovery/action re-resolve path uses the very same interval ---
discovery = tweak[tweak.index('NSNumber *last = objc_getAssociatedObject(cell, &LMVDiscoveryKey);'):]
discovery = discovery[:discovery.index('static char discoveryDiagnosticKey;')]
check(discovery.count('LMVCardUpdateInterval') == 2,
      'both discovery gates must use LMVCardUpdateInterval')
check('>= 0.1' not in discovery,
      'the discovery path must not keep a second, hard-coded 0.1 gate')

# --- visibility observation itself stays per-tick and cheap (not throttled) ---
check('BOOL cellVisible=LMVVisible(cell), changed=NO;' in tick,
      'visibility must still be observed on every tick')

# --- the visibility flag is only read for the active/consumer computations ---
check('state.active=active;' in tick,
      'per-tick state must still be maintained so pause/resume stays immediate')

if fail:
    print('FAIL:')
    for item in fail:
        print('  - ' + item)
    sys.exit(1)
print('PASS: 0.0.80 per-cell 100 ms visible-card update cadence; no global discovery burst; visibility still observed every tick (not a device runtime test)')
