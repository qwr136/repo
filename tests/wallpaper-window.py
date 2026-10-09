from pathlib import Path
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text(); w=(r/'LMVWallpaperWindow.h').read_text()
for name,end in [('LMVUpdateLockScreen','LMVUpdateLockScreens'),('LMVUpdateDesktop','LMVUpdateDesktops')]:
    body=s.split('static void '+name+'(',1)[1].split('static void '+end+'(',1)[0]
    assert 'insertSublayer:state.layer' not in body and 'state.layer.hidden = YES' in body
assert 'CALayer *parent = root;' in w and 'LMVAcquireOriginal(branch.layer' in w
assert 'LMVWallpaperRetire(window); surface = nil;' in w
assert 'if (!branches.count)' in w and 'if (!contents && !surface.layer.contents)' in w
assert 'LMVDiscoverWallpaperHosts();' in s and 'attempt <= 6' in s
assert 'state.layer.hidden = !activity.draw; state.active = NO;' not in s
assert 'LMVWallpaperPublish(source, image)' in s
assert 'LMVOriginalSuppressDrawing' in w and 'LMVReleaseOriginals(surface.leases, surface)' in w
print('PASS: wallpaper window sole renderer, recoverable original leases, disabled/revision invalidation, startup host rediscovery, no overlay fallback')
