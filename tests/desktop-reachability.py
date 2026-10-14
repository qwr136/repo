#!/usr/bin/env python3
"""0.0.118-0.0.120 "屏蔽桌面便捷访问" - desktop-only Reachability block.

Linux runs the pure gate as C plus source contracts. The recognizer search and
UIKit wiring need macOS and are asserted as source contracts here; they are not
device validation and never claim SpringBoard compositing.
"""
import platform
import re
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
header = (root / 'LMVReachability.h').read_text()
tweak = (root / 'Tweak.xm').read_text()
settings = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()

# ---- source contracts -------------------------------------------------------
assert 'static BOOL LMVReachabilityDeskBlocked(' in header
assert '[recognizer isKindOfClass:UIScreenEdgePanGestureRecognizer.class]' in header
assert 'UIRectEdgeBottom' in header, 'only the bottom edge is Reachability'
assert 'LMVReachabilitySurfaceUp(@[@"SBCoverSheetWindow"], @[@"CoverSheet"])' in header
assert 'LMVReachabilitySurfaceUp(@[@"SBControlCenterWindow"], @[@"ControlCenter"])' in header
assert 'if (recognizer && recognizer.enabled == blocked) recognizer.enabled = !blocked;' in header
assert 'static void LMVReachabilityRestore(void)' in header
assert 'recognizer.enabled = YES;' in header, 'leaving the switch off must re-enable the gesture'
# No private symbol guessing: public UIKit classes, dynamic selectors only.
for forbidden in ('%hook', 'SBReachabilityManager', 'SBMainDisplayPolicyAggregator', '_setReachabilityEnabled'):
    assert forbidden not in header, forbidden

assert '#import "LMVReachability.h"' in tweak
assert 'static void LMVReachabilitySync(void)' in tweak
assert 'LMVReachabilityEnabled()' in tweak
assert 'CFPreferencesCopyAppValue(CFSTR(@"BlockDesktopReachability"), kLMVPrefsID)'.replace('@','') in header
assert 'LMVReachabilityTimer = [NSTimer timerWithTimeInterval:1.0 repeats:YES block' in tweak
assert '[LMVReachabilityTimer invalidate]; LMVReachabilityTimer = nil;' in tweak
assert 'LMVReachabilityRestore();' in tweak
assert tweak.index('LMVReachabilitySync();') < tweak.index('LMVLockVideoRefresh(reload);'), \
    'applied on every preference refresh'

# Settings row directly below the opacity rows and above the material-path group.
opacity = settings.index('[PSSpecifier groupSpecifierWithName:@"消息、选项、清除视频透明度"]')
reach = settings.index('[PSSpecifier groupSpecifierWithName:@"桌面便捷访问"]')
paths = settings.index('[PSSpecifier groupSpecifierWithName:@"素材路径"]')
assert opacity < reach < paths
assert 'preferenceSpecifierNamed:@"屏蔽桌面便捷访问"' in settings
assert '[reachability setProperty:@"BlockDesktopReachability" forKey:@"key"];' in settings
assert '#[reachability setProperty:@NO forKey:@"default"];'.replace('#', '') in settings

# ---- 0.0.119: the search must reach SpringBoard's SYSTEM GESTURE window --------
# Device log: `reachability block=1 enabled=1 recognizer=0` - the switch was inert.
# The scene-only walk never reached that window (the application owns it, not the
# window scene), and the search insisted on one UIKit class. It now also asks the
# application for its complete window list, accepting ANY recognizer that exposes
# `edges` with the bottom bit, preferring a real screen-edge pan over the fallback.
assert 'NSSelectorFromString(@"windows")' in header
assert 'respondsToSelector:allWindows' in header, 'complete window set on SpringBoard'
assert 'objc_msgSend)(UIApplication.sharedApplication, allWindows)' in header
assert 'depth > 32' in header, 'the system gesture view may sit deep in the tree'
assert 'respondsToSelector:edgesSelector' in header
assert 'if (!(edges & UIRectEdgeBottom)) continue;' in header
assert 'if (fallback && !*fallback) *fallback = recognizer;' in header
assert header.count('return fallback;') == 1
# Missing report: rate limited, and it names the windows that WERE reachable so a
# single log pass locates the surface carrying the gesture.
assert 'now - reportedMissingAt > 5.0' in header
assert 'LMVReachabilityWindowNames()' in header
assert 'windows=%lu %@' in header
# Toggle report: names the exact recognizer it changed (no unrelated edge pan).
assert 'target=%@ edges=%lu' in header

# ---- 0.0.120: the gesture is guarded at its TOUCH SOURCE ----------------------
# The 0.0.119 device log still reported recognizer=0 with the COMPLETE application
# window set (38 windows, including the system gesture and touch-visualiser
# windows), so toggling `enabled` can never work on SpringBoard. A bottom-edge pan
# - whatever class implements it - begins inside the bottom strip of the screen,
# which identifies it by geometry alone: no private class name, no `edges` guess.
assert 'static BOOL LMVReachabilityShouldSwallow(' in header
assert 'static volatile BOOL LMVReachabilityDesktopBlocked = NO;' in header
assert 'LMVReachabilityDesktopBlocked = blocked;' in header, 'the gate is published for the touch path'
assert 'if (LMVReachabilityInSpringBoard() != 1 || !LMVReachabilityDesktopBlocked) return NO;' in header
assert '@interface UIScreenEdgePanGestureRecognizer (LMVReachabilityGuard)' in header
assert 'point.y >= bounds.size.height - 20.0' in header, 'bottom strip only; other edges untouched'
assert 'if (!view || ![touch isKindOfClass:UITouch.class]) return NO;' in header
assert 'return; // not calling through: the state machine never sees the touch' in header
assert 'static void LMVReachabilityInstallTouchGuard(void)' in header
assert 'method_exchangeImplementations(existing, added)' in header
assert 'reachability touch-guard=%s' not in header and 'reachability touch-guard=installed' in header
assert 'reachability swallow count=%ld y=%.0f' in header
assert 'LMVReachabilityInstallTouchGuard();' in tweak
# SpringBoard-only scope: the filter plist injects exactly one bundle.
filter_plist = (root / 'layout/Library/MobileSubstrate/DynamicLibraries/LockMessageVideo.plist').read_text()
assert '<string>com.apple.springboard</string>' in filter_plist
assert filter_plist.count('<string>') == 1
# The windows search may PROBE a private selector name, but only to APPEND a window;
# every decision still comes from public API, and a miss adds nothing.
assert '_systemGestureWindow' in header
assert 'a miss simply adds nothing' in header
# Restore uses the SAME widened search, otherwise a fallback recognizer would stay
# disabled after the switch is turned off.
restore_src = header[header.index('static void LMVReachabilityRestore(void)'):]
assert 'LMVReachabilityEdgeRecognizerInView(window, 0, &fallback)' in restore_src
assert 'if (!recognizer) recognizer = fallback;' in restore_src
assert '只屏蔽桌面的便捷访问（降半屏）：锁屏与控制中心不受影响' in settings
assert 'cell:PSSwitchCell' in settings[reach:paths]

# ---- execute the pure gate --------------------------------------------------
rule = header[header.index('static BOOL LMVReachabilityDeskBlocked('):header.index('// Home=1, application=-1, unknown=0.')]
main = r'''
int main(void) {
    /* enabled blankK blank lockK locked fg nc cc expected */
    struct { int e, bk, b, lk, l, fg, nc, cc, want; } cases[] = {
        {1,1,0,1,0, 1,0,0, 1},  /* desktop, unlocked: BLOCK */
        {1,1,0,1,0, 1,0,1, 0},  /* Control Centre: never block */
        {1,1,0,1,0, 1,1,0, 0},  /* Notification Centre: never block */
        {1,1,0,1,1, 1,0,0, 0},  /* lock screen: never block */
        {1,1,1,1,0, 1,0,0, 0},  /* screen blank: never block */
        {1,1,0,0,0, 1,0,0, 0},  /* unknown lock state: never block */
        {1,0,0,1,0, 1,0,0, 0},  /* unknown blank state: never block */
        {1,1,0,1,0,-1,0,0, 0},  /* an app is frontmost: not the desktop */
        {1,1,0,1,0, 0,0,0, 0},  /* unknown foreground: conservative, no block */
        {0,1,0,1,0, 1,0,0, 0},  /* switch off */
        {1,1,0,1,0,-1,1,1, 0},  /* app + both surfaces: no block */
    };
    for (unsigned i = 0; i < sizeof(cases)/sizeof(cases[0]); i++)
        assert(LMVReachabilityDeskBlocked(cases[i].e, cases[i].bk, (uint64_t)cases[i].b,
            cases[i].lk, (uint64_t)cases[i].l, (NSInteger)cases[i].fg, cases[i].nc, cases[i].cc) == cases[i].want);
    puts("PASS production desktop-only Reachability gate: blocks only an unlocked, unblanked desktop with SpringBoard frontmost and no NC/CC surface");
    return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
    src = Path(tmp) / 'reach.c'
    binary = Path(tmp) / 'reach'
    src.write_text('#include <assert.h>\n#include <math.h>\n#include <stdint.h>\n#include <stdio.h>\n'
                   'typedef signed char BOOL;\n#define YES 1\n#define NO 0\ntypedef long NSInteger;\n'
                   + rule + main)
    subprocess.run(['cc', str(src), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)

if platform.system() != 'Darwin':
    print('SKIP native: recognizer/UIKit wiring needs macOS; source contracts executed')
    raise SystemExit(0)
print('PASS native: macOS contracts as above (no SpringBoard compositing claim)')
