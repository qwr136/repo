from pathlib import Path
import hashlib
r=Path(__file__).resolve().parents[1]
h=(r/'LMVWallpaperDiagnostics.h').read_text(); s=(r/'Tweak.xm').read_text()
for required in ['viewIfLoaded','childViewControllers','nextResponder','class_copyMethodList','method_getTypeEncoding','class_copyIvarList','presentationLayer','wallpaper-consumer','snapshots >= 4']:
    assert required in h,required
for forbidden in ['objc_msgSend','object_getIvar','setHidden:','setAlpha:','removeFromSuperview','removeFromSuperlayer','makeKeyWindow','valueForKey','sharedInstance']:
    assert forbidden not in h,forbidden
assert 'wallpaper-structure.log' in s and 'wallpaperRecords > 900' in s
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
expected={
'static void LMVUpdateLockScreen(UIView *host)':'cbf000df36a7e19779c73812404f69445ebe0a9816493f8f88f042e141ad6c98',
'static void LMVUpdateDesktop(UIView *host, LMVDesktopSnapshot *snapshot)':'a7d84fffe6a1b1dcb5b054ae76a9a7240cd78e13175eff666dcec362332e34f4',
'static void LMVMarkLaunchReady(void)':'d9c06fbd04d4da4e89a25321f39d9eb7e08d02e16d7416b489cda88bd9ea5e4c'}
for signature,digest in expected.items(): assert hashlib.sha256(body(s,signature).encode()).hexdigest()==digest,signature
assert not (r/'LMVWallpaperWindow.h').exists()
print('PASS: read-only bounded controller/scene/method diagnostic; 61 wallpaper/launch bodies preserved')
