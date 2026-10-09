from pathlib import Path
import re, subprocess
r=Path(__file__).resolve().parents[1]
h=(r/'LMVWallpaperDiagnostics.h').read_text(); s=(r/'Tweak.xm').read_text()
for required in ['viewIfLoaded','childViewControllers','nextResponder','class_copyMethodList','method_getTypeEncoding','class_copyIvarList','presentationLayer','wallpaper-consumer','snapshots >= 4']:
    assert required in h,required
for forbidden in ['objc_msgSend','object_getIvar','setHidden:','setAlpha:','removeFromSuperview','removeFromSuperlayer','makeKeyWindow','valueForKey','sharedInstance']:
    assert forbidden not in h,forbidden
assert 'wallpaper-structure.log' in s and 'wallpaperRecords > 900' in s
assert 'LMVCaptureWallpaperDiagnostics();' in s
# The requested baseline must retain actual 61 wallpaper and overlay behavior.
base=subprocess.run(['git','show','bc10e435107eb67bc1d1af7deb9e184ee3f5dd7b:Tweak.xm'],cwd=r,capture_output=True,text=True,check=True).stdout
def body(text,signature):
    start=text.index(signature+' {'); depth=0
    for pos in range(start+len(signature),len(text)):
        if text[pos]=='{':depth+=1
        if text[pos]=='}':
            depth-=1
            if not depth:return text[start:pos+1]
    raise AssertionError(signature)
for signature in ['static void LMVUpdateLockScreen(UIView *host)','static void LMVUpdateDesktop(UIView *host, LMVDesktopSnapshot *snapshot)','static void LMVMarkLaunchReady(void)']:
    assert body(s,signature)==body(base,signature),signature
assert not (r/'LMVWallpaperWindow.h').exists()
print('PASS: read-only bounded controller/scene/method diagnostic; 61 wallpaper/launch bodies preserved')
