#!/usr/bin/env python3
# 4.4.8 stage 2 regression: stationary cards must skip the exposure walk instead of
# re-walking the view/superview/superlayer tree every frame. This pins the contract
# so a later refactor cannot silently drop the skip and re-introduce the 52-76% slow.
import re, sys

tweak = open('Tweak.xm').read()
fails = []
def check(cond, msg):
    if cond:
        print('ok  -', msg)
    else:
        fails.append(msg)

# The building blocks must exist.
check('static NSUInteger LMVCardFingerprint(UIView *cell, NSDictionary *states)' in tweak,
      'per-cell fingerprint function defined')
check('#define LMV_CARD_RECOMPUTE_EVERY' in tweak,
      'periodic full-recompute safety-net interval defined')
check('static BOOL LMVCardVisibilityDirty=NO;' in tweak,
      'preference-change dirty flag declared')

# The tick must wire the skip: compute a per-cell decision, compare the fingerprint,
# and branch around the exposure walk when geometry is unchanged.
_t = tweak.index('- (void)tick:(CADisplayLink *)link {')
tick = tweak[_t:_t + 9000]
check('BOOL lmvRecompute=' in tick, 'tick computes a recompute decision')
check('NSUInteger lmvFP=LMVCardFingerprint(cell,states);' in tick,
      'tick fingerprints the cell each frame')
check('lmvFP != [objc_getAssociatedObject(cell,&LMVCardFPKey)' in tick,
      'tick compares the fingerprint against last frame')
check('if (!lmvRecompute) {' in tick, 'tick has a stationary skip branch')
check('continue;' in tick, 'tick skips the exposure walk when stationary')
check('LMVCardVisibilityDirty=NO;' in tick, 'tick consumes the dirty flag each frame')

# A preference write must invalidate, so an enabled/path flip that does not move
# geometry still recomputes on the next tick (otherwise a channel would silently
# fail to appear until the periodic net caught it).
_d = tweak.index('static void LMVDarwinNotification(')
darwin = tweak[_d:_d + 1400]
check('LMVCardVisibilityDirty=YES;' in darwin,
      'preference write sets the visibility dirty flag')

if fails:
    print('\nFAILURES:')
    for f in fails:
        print(' -', f)
    sys.exit(1)
print('\ncards-static-skip: all checks passed')
