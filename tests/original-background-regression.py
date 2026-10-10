#!/usr/bin/env python3
"""Integration contracts + byte-identity checks for protected .55/.56/.57 paths.
Native lease/discovery/object behavior is exercised by original-background.m.
"""
from pathlib import Path
import hashlib, plistlib
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text()
h=(r/'LMVBackgroundDiscovery.h').read_text()
l=(r/'LMVOriginalBackground.h').read_text()
def function(text,signature):
    import re
    match=re.search(re.escape(signature)+r'(?: __attribute__\(\(unused\)\))? \{',text)
    if not match: raise AssertionError(signature)
    start=match.start(); depth=1
    for i in range(match.end(),len(text)):
        if text[i]=='{':depth+=1
        elif text[i]=='}':
            depth-=1
            if not depth:return text[start:i+1]
    raise AssertionError(signature)
# SHA-256 of production 14f9e36 (.57), not the new implementation.
protected={
    'static void LMVRequestSafeUpdate(void)': 'e189230d92bf65841b1aba65a314a41468e3db8a64879abb3eda7ec4be504aca',
    'static void LMVMarkLaunchReady(void)': 'd9c06fbd04d4da4e89a25321f39d9eb7e08d02e16d7416b489cda88bd9ea5e4c',
    'static BOOL LMVAlreadyLaunched(UIApplication *app)': '5db967fa36dc6b884575898a29c30e5d2f85d9999c1146fa2b1cf0f4c9be1f5e',
    'static LMVDesktopSnapshot *LMVDesktopCapture(void)': '864623a1dcbebfc9d699746898fb81ca71349f5c84ed1876ac8ca036f8b3bc56',
    'static void LMVDesktopHostChanged(UIView *view)': 'd913d26ac489c99b48578e7e522d60563220bb895894b7199cb53a4336876526',
    'static void LMVUpdateDesktops(void)': 'a4ce7b7140232c7150e03cd380dd9fa652626850d4091ff551cc337f81219665',
    'static void LMVReleaseDesktopSource(LMVVideoState *state)': 'd37775b7f77e6299ae4b38d0b6f7dd683eb9cecc1967bb0e53dd8f2b4b28270b',
}
for signature in protected:
    assert signature in s, signature
# Source initialization now intentionally defers disk PTS seek until ready (.59).
source=function(s,'static LMVSharedSource *LMVSourceForTarget(NSString *path, NSString *target)')
assert 'LMVDiskPending' in source
assert 'seekToTime:' not in source.split('LMVSharedSources[registryKey]=source',1)[0]
assert 'LMVSourceForTarget(path,nil)' in function(s,'static LMVSharedSource *LMVSourceForPath(NSString *path)')
# No early hook, singleton, global layer/view mutation or second decoder path.
for forbidden in ['SBLockScreenManager','SBWallpaperController','sharedInstance','%hook UIView','%hook CALayer','AVAudioSession','prerollAtRate','idleTimerDisabled']:
    assert forbidden not in s+h+l,forbidden
# Suppression depends on enable+selection+scope only: decoder failure and alpha0
# have no effect on replacement, including cold absence of a preview frame.
replace=function(h,'static void LMVReplaceBackground(LMVVideoState *state, UIView *anchor, UIView *scope, NSString *target, BOOL inScope)')
for forbidden in ['state.active','state.source','LMVReadyAssets','LMVOpacity','cached','lastImage']:
    assert forbidden not in replace,forbidden
assert 'LMVOriginalDetach' in replace or 'LMVOriginalDetach' in (r/'LMVWallpaperWindow.h').read_text()
assert 'if (layer.superlayer) [layer removeFromSuperlayer]' in l
assert 'weakToWeakObjectsMapTable' in l and 'weakObjectsHashTable' in l
assert 'self.baselineOpacity = layer.opacity' in l and 'layer.opacity = self.baselineOpacity' in l
assert 'before.superlayer' in l and 'after.superlayer' in l
assert 'layer.contents =' not in l and 'layer.mask =' not in l
visibility=function(s,'static BOOL LMVVisible(UIView *view)')
discovery=function(s,'static UIView *LMVMessageMaterial(UIView *view, NSUInteger depth)')
assert 'LMVOriginalVisibilityAlpha(ancestor)' in visibility and 'LMVOriginalVisibilityAlpha(view)' in discovery
update=function(s,'static void LMVUpdate(UIView *cell)')
for target,signature in [('LockScreen','static void LMVUpdateLockScreen(UIView *host)'),('Desktop','static void LMVUpdateDesktop(UIView *host, LMVDesktopSnapshot *snapshot)')]:
    f=function(s,signature)
    assert 'wallpaperEligible' in f
    assert 'LMVUpdateWallpaperWindows();' in f
    assert 'LMVRevisions[path] &&' in f # invalid selection does not reconstruct target each layout
scope=function(s,'static BOOL LMVDesktopOriginalInScope(UIView *host, LMVDesktopSnapshot *snapshot, LMVDesktopActivity activity)')
assert 'snapshot.foreground != LMVForegroundApp' in scope and 'snapshot.screenOn' in scope and '!snapshot.locked' in scope
reuse=s.split('- (void)prepareForReuse {',1)[1].split('%end',1)[0]
assert 'LMVPause(state)' in reuse
assert 'LMVRestoreBackground(state)' in function(s,'static void LMVPause(LMVVideoState *state)')
assert 'LMVReleaseOriginals(_originals, self)' in s
prefs=function(s,'static void LMVLoadPreferences(void)')
assert 'BOOL explicitSelection' in prefs and '!explicitSelection && ![[NSFileManager' in prefs
assert 'if (![relative isKindOfClass:NSString.class] || !relative.length) continue' in prefs
assert 'if ([path hasPrefix:[LMVDirectory stringByAppendingString:@"/"]]) LMVPaths[target] = path' in prefs
# Actual frame publish swaps only owned contents; it never invokes replacement,
# reconstructs a card or re-discovers a material for every converted frame.
publish=function(s,'static void LMVPublishFrame(LMVSharedSource *source, CMTime time)')
for forbidden in ['LMVReplaceBackground','LMVRestoreBackground','LMVUpdate(', 'LMVOriginalCandidates','LMVVideoState new']:
    assert forbidden not in publish
assert 'state.layer.contents=(__bridge id)image' in publish
assert 'LMVOriginalPureView' in h and 'Thumbnail' in h and 'Secure' in h and 'Scene' in h
print('PASS: five-target integration, enabled+selected cold/error/alpha0 policy, weak leases, scoped discovery, actual-frame swap, protected baseline hashes (native execution separately; not device test)')
