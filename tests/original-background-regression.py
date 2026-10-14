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
# Retained notification rendering and source lifetimes are isolated from Desktop.
for signature in ['static void LMVRequestSafeUpdate(void)','static void LMVMarkLaunchReady(void)',
                  'static BOOL LMVAlreadyLaunched(UIApplication *app)']:
    assert signature in s
assert '#import "LMVDesktopVideo.h"' in s
assert 'LMVAcquireOriginal' not in (r/'LMVDesktopVideo.h').read_text()
# Source initialization now intentionally defers disk PTS seek until ready (.59).
source=function(s,'static LMVSharedSource *LMVSourceForTarget(NSString *path, NSString *target)')
assert 'LMVDiskPending' in source
assert 'seekToTime:' not in source.split('LMVSharedSources[registryKey]=source',1)[0]
assert 'LMVSourceForPath' not in s
assert 'source.ownerTarget=target' in source
registry=function(s,'static NSString *LMVSourceRegistryKey(NSString *path, NSString *target)')
assert '@"Message"' in registry and '@"Options"' in registry and '@"Clear"' in registry
assert 'containsObject:target ?: @""' in registry
assert '[target stringByAppendingFormat:@"\\n%@",path]' in registry
# No early hook, singleton, global layer/view mutation or second decoder path.
for forbidden in ['SBLockScreenManager','SBWallpaperController','sharedInstance','%hook UIView','%hook CALayer','AVAudioSession','prerollAtRate','idleTimerDisabled']:
    assert forbidden not in s+h+l,forbidden
# Suppression depends on enable+selection+scope only: decoder failure and alpha0
# have no effect on replacement, including cold absence of a preview frame.
replace=function(h,'static void LMVReplaceBackground(LMVVideoState *state, UIView *anchor, UIView *scope, NSString *target, BOOL inScope)')
for forbidden in ['state.active','state.source','LMVReadyAssets','LMVOpacity','cached','lastImage']:
    assert forbidden not in replace,forbidden
assert 'LMVOriginalDetach' in replace
branch=function(h,'static void LMVOriginalCandidateBranch(UIView *view, BOOL wallpaper, NSUInteger depth, NSMutableArray *candidates, NSUInteger *remaining)')
# Nil contents/color alone is not proof that a delegate-backed material is empty.
# Preserve the independent safe-drawleaf path; the no-sublayer backing suppresses.
assert 'view.layer.sublayers.count > 0' in branch.split('BOOL detachOnly',1)[1].split(';',1)[0]
assert 'if (pure && !detachOnly)' in branch
assert '@"layer":view.layer, @"method":@(LMVOriginalSuppressDrawing)' in branch
scope=function(h,'static BOOL LMVOriginalTargetInScope(UIView *owner, UIView *anchor, UIView *scope)')
assert 'owner.window' in scope and 'isDescendantOfView:owner' in scope
for forbidden in ('hidden','alpha','LMVVisible','LMVReadyAssets','LMVOpacity','active'):
    assert forbidden not in scope,forbidden
maintenance=function(h,'static BOOL LMVOriginalBackgroundNeedsMaintenance(LMVVideoState *state)')
assert 'layer.opacity != 0.0f' in maintenance and 'layer.superlayer' in maintenance
for forbidden in ('subviews','LMVOriginalCandidates','objectEnumerator','LMVCachedFrame','LMVSource'):
    assert forbidden not in maintenance,forbidden
assert 'if (layer.superlayer) [layer removeFromSuperlayer]' in l
assert 'weakToWeakObjectsMapTable' in l and 'weakObjectsHashTable' in l
assert 'self.baselineOpacity = layer.opacity' in l and 'layer.opacity = self.baselineOpacity' in l
assert 'before.superlayer' in l and 'after.superlayer' in l
assert 'layer.contents =' not in l and 'layer.mask =' not in l
visibility=function(s,'static BOOL LMVVisible(UIView *view)')
discovery=function(s,'static UIView *LMVMessageMaterial(UIView *view, NSUInteger depth)')
card=(r/'LMVCardPresentation.h').read_text()
assert 'LMVCardExposed(view)' in visibility and 'LMVPlaybackAllowed()' in visibility
assert 'LMVOriginalVisibilityAlpha(view)' in card and 'lease.baselineOpacity' in card
assert 'LMVOriginalSuppressDrawing' in card and 'layer.opacity==0.0f' in card
candidate=function(s,'static UIView *LMVMessageMaterialCandidate(UIView *view, NSUInteger depth, BOOL visibleOnly)')
assert 'objc_getAssociatedObject(view, &LMVOwnershipKey)' in candidate
assert 'visibleOnly && (view.hidden || LMVOriginalVisibilityAlpha(view) < 0.01)' in candidate
assert 'LMVMessageMaterialCandidate(view,depth,YES)' in discovery and 'LMVMessageMaterialCandidate(view,depth,NO)' in discovery
update=function(s,'static void LMVUpdate(UIView *cell)')
assert 'LockScreen' not in s and 'LMVLockBackground.h' not in s
update=function(s,'static void LMVUpdate(UIView *cell)')
assert 'LMVReplaceBackground(state, anchor, host, target, originalInScope)' in update
assert 'CGFloat desiredOpacity=LMVOpacityEnabled ? LMVOpacity : 0.0' in function(s,'static void LMVLayoutCardSurface(LMVVideoState *state, UIView *anchor, UIView *host)')
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
print('PASS: message/action-only integration, enabled+selected cold/error/alpha0 policy, weak leases, scoped discovery, actual-frame swap (native execution separately; not device test)')
