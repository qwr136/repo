from pathlib import Path
import hashlib
r=Path(__file__).resolve().parents[1]
h=(r/'LMVWallpaperDiagnostics.h').read_text(); p=(r/'LMVWallpaperProviderDiagnostics.h').read_text(); s=(r/'Tweak.xm').read_text()
for required in ['viewIfLoaded','childViewControllers','nextResponder','class_copyMethodList','method_getTypeEncoding','class_copyIvarList','presentationLayer','wallpaper-consumer','snapshots >= 8']:
    assert required in h+p,required
for forbidden in ['objc_msgSend','object_getIvar','setHidden:','setAlpha:','removeFromSuperview','removeFromSuperlayer','makeKeyWindow','valueForKey','sharedInstance']:
    assert forbidden not in h+p,forbidden
assert 'wallpaper-structure.log' in s and 'wallpaperRecords > 2400' in s
assert 'LMVCaptureWallpaperDiagnostics();' in s
# The requested baseline keeps the three production bodies byte-identical to 0.0.61.
def body(text,signature):
    start=text.index(signature+' {'); depth=0
    for pos in range(start+len(signature),len(text)):
        if text[pos]=='{':depth+=1
        if text[pos]=='}':
            depth-=1
            if not depth:return text[start:pos+1]
    raise AssertionError(signature)
expected='d9c06fbd04d4da4e89a25321f39d9eb7e08d02e16d7416b489cda88bd9ea5e4c'
assert hashlib.sha256(body(s,'static void LMVMarkLaunchReady(void)').encode()).hexdigest()==expected
assert (r/'LMVLockBackground.h').exists()
assert not (r/'LMVWallpaperWindow.h').exists()
assert 'LMVDesktopHosts' not in h and 'mode=opaque-overlay' in h
print('PASS: read-only bounded controller/scene/method diagnostic; startup unchanged and lock-only rendering diagnostics')
