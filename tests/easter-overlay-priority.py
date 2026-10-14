#!/usr/bin/env python3
"""Actual production priority helper; macOS uses Foundation/real CALayer doubles.
Linux executes the exact finite-level C helper for both float/double and source
contracts; --require-native refuses skipping ObjC. --emit-native emits full fixture.
No claim of real SpringBoard compositing or vendor gesture-class inspection.
"""
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
overlay = (root / 'LMVEasterOverlay.h').read_text()
apply = overlay[overlay.index('- (void)apply {'):overlay.index('- (CGRect)dragArea {')]
priority = overlay[overlay.index('static BOOL LMVEasterOverlayPriority('):overlay.index('static void LMVEasterDarwin(')]
blocking = overlay[overlay.index('static BOOL LMVEasterBlockingWindow('):overlay.index('static BOOL LMVEasterBoundedPriorityLevel(')]
changed = overlay[overlay.index('- (void)changed:'):overlay.index('- (void)reportWindow:', overlay.index('- (void)changed:'))]
snapshot = overlay[overlay.index('static NSArray *LMVEasterPhysicalSnapshot('):overlay.index('static BOOL LMVEasterPhysicalCheckNeeded(')]
assert 'LMVEasterOverlayPriority(windows,self.window,&level,&blockedWindow)' in apply
assert apply.index('LMVEasterOverlayPriority(') < apply.index('LMVEasterDisplayPolicy(') < apply.index('self.window.hidden = NO')
assert 'window==own' in priority and 'isfinite(candidate)' in priority
assert 'LMVEasterBlockingWindow(window,0)' in priority
assert 'LMVEasterVisibleDrawing' in blocking and 'LMVEasterVisibleForeground' in blocking
assert 'if(security || modal ||' in blocking and 'classSecurity && (drawing || substantive || foreground)' in blocking
assert '(visible && alert && [controller isKindOfClass:alert])' in blocking
import re
executable=re.sub(r'//[^\n]*|/\*.*?\*/','',priority+blocking,flags=re.S)
assert all(name not in executable for name in ('UINT_MAX', 'CGFLOAT_MAX', 'Squid', 'Gesture'))
assert 'MIN(host.windowLevel+1,UIWindowLevelAlert - 1)' not in overlay
assert 'valueWithNonretainedObject:window' in snapshot and '@(window.windowLevel)' in snapshot
assert 'UIWindowDidBecomeVisibleNotification' in overlay and 'UIWindowDidBecomeHiddenNotification' in overlay
assert 'notification.object == self.window' in changed and '[self refresh]' in changed
assert '[self invalidatePhysicalSnapshot]' in overlay
assert all(word not in apply for word in ('makeKeyWindow', 'makeKeyAndVisible', 'resignKeyWindow'))
assert apply.count('[[LMVEasterWindow alloc]') == 1 and 'if (!self.window)' in apply
assert '- (BOOL)canBecomeKeyWindow { return self.panel != nil && !self.hidden; }' in overlay

# Exact production arithmetic, not a Python reimplementation.
arithmetic = overlay[overlay.index('static BOOL LMVEasterBoundedPriorityLevel('):overlay.index('static BOOL LMVEasterOverlayPriority(')]
cmain = r'''
int main(void) {
    CGFloat out=42;
    assert(LMVEasterBoundedPriorityLevel(0,&out) && out==1);
    for(int i=0;i<10000;i++) assert(LMVEasterBoundedPriorityLevel(1000000,&out) && out==1000001);
    assert(LMVEasterBoundedPriorityLevel(0x1p24-2,&out) && out==0x1p24-1);
    out=42;
    if(sizeof(CGFloat)>sizeof(float)) {
        assert(LMVEasterBoundedPriorityLevel(0x1p24,&out) && out==0x1p24+1);
        assert(LMVEasterBoundedPriorityLevel(1000000000,&out) && out==1000000001);
        assert(LMVEasterBoundedPriorityLevel(0x1p48-2,&out) && out==0x1p48-1);
        out=42;assert(!LMVEasterBoundedPriorityLevel(0x1p48-1,&out) && out==42);
    } else assert(!LMVEasterBoundedPriorityLevel(0x1p24-1,&out) && out==42);
    assert(!LMVEasterBoundedPriorityLevel(NAN,&out) && out==42);
    assert(!LMVEasterBoundedPriorityLevel(INFINITY,&out) && out==42);
    assert(!LMVEasterBoundedPriorityLevel(-INFINITY,&out) && out==42);
    assert(!LMVEasterBoundedPriorityLevel(1e30,&out) && out==42);
    return 0;
}
'''
if '--emit-native' not in sys.argv:
    with tempfile.TemporaryDirectory() as tmp:
        for scalar in ('float', 'double'):
            source = Path(tmp) / (scalar + '.c')
            binary = Path(tmp) / scalar
            source.write_text('#include <math.h>\n#include <assert.h>\ntypedef int BOOL;\n#define YES 1\n#define NO 0\ntypedef ' + scalar + ' CGFloat;\n' + arithmetic + cmain)
            subprocess.run(['cc', '-std=c99', '-Wall', '-Wextra', str(source), '-lm', '-o', str(binary)], check=True)
            subprocess.run([str(binary)], check=True, timeout=10)
    print('PASS: exact production bounded +1 helper executes for CGFloat=float/double; source scope/security/cache/event/one-window/no-key-loop contracts')

# Reuse the existing real CALayer UIKit-double fixture and unmodified production
# window helpers. No fake mirror of BlockingWindow or OverlayPriority.
base = subprocess.check_output([sys.executable, str(root / 'tests/easter-window.py'), '--emit-native'], text=True)
assert arithmetic in base and priority in base
fixture = r'''
@interface UIControl : UIView @end
@implementation UIControl @end
@interface UIAlertView : UIView @end
@implementation UIAlertView @end
@interface UIActionSheet : UIView @end
@implementation UIActionSheet @end
@interface UIAlertController : UIViewController @end
@implementation UIAlertController @end
@interface OrdinaryGestureHUDWindow : UIWindow @end
@implementation OrdinaryGestureHUDWindow @end
@interface GestureAuthenticationWindow : UIWindow @end
@implementation GestureAuthenticationWindow @end
@interface PermissionView : UIView @end
@implementation PermissionView @end
static void solid(UIView *v) {
    UIColor *c=[UIColor new];c.CGColor=CGColorCreateGenericRGB(.2,.3,.4,1);v.backgroundColor=c;
}
static void rootView(UIWindow *w,UIView *v) {
    w.rootViewController.viewIfLoaded=v;v.window=w;v.superview=w;
    v.layer.frame=v.bounds;[w.layer addSublayer:v.layer];
}
static UIWindow *hud(CGFloat level) {
    UIWindow *w=[OrdinaryGestureHUDWindow new];w.windowLevel=level;
    rootView(w,w.rootViewController.viewIfLoaded);return w;
}
static void child(UIWindow *w,UIView *v) {
    UIView *r=w.rootViewController.viewIfLoaded;
    v.window=w;v.superview=r;v.layer.frame=v.bounds;[r.layer addSublayer:v.layer];r.subviews=@[v];
}
static void allowed(NSArray *windows,UIWindow *own,CGFloat expected) {
    CGFloat level=-123;UIWindow *blocked=nil;
    assert(LMVEasterOverlayPriority(windows,own,&level,&blocked));
    assert(isfinite(level) && level==expected && !blocked);
}
static void denied(NSArray *windows,UIWindow *own,UIWindow *expected) {
    CGFloat level=0;UIWindow *blocked=nil;
    assert(!LMVEasterOverlayPriority(windows,own,&level,&blocked) && blocked==expected);
}
int main(void) { @autoreleasepool {
    UIWindow *home=[SBHomeScreenWindow new];home.windowLevel=1000;rootView(home,home.rootViewController.viewIfLoaded);
    UIWindow *own=[UIWindow new];own.windowLevel=9999999;
    UIWindow *one=hud(2500),*two=hud(10000),*three=hud(1000000);
    NSArray *windows=@[home,one,two,three,own];
    allowed(windows,own,1000001); // transparent roots, above alert level
    UIView *tiny=[UIView new];tiny.bounds=CGRectMake(0,0,60,20);solid(tiny);child(three,tiny);
    allowed(windows,own,1000001); // actual visible small drawing, no foreground controls
    for(NSUInteger i=0;i<10000;i++) {
        CGFloat level=0;assert(LMVEasterOverlayPriority(windows,own,&level,NULL));
        assert(level==1000001);own.windowLevel=level;
    }
    // Foreign identity/level/hidden fields are in the live cached snapshot.
    NSArray *stable=LMVEasterPhysicalSnapshot(@[home,one,two,three],@[],1,YES,0,YES,0);
    UIWindow *replacement=hud(1000000);
    assert(![stable isEqual:LMVEasterPhysicalSnapshot(@[home,one,two,replacement],@[],1,YES,0,YES,0)]);
    two.windowLevel=2000000;
    assert(![stable isEqual:LMVEasterPhysicalSnapshot(@[home,one,two,three],@[],1,YES,0,YES,0)]);
    allowed(windows,own,2000001);two.windowLevel=10000;
    three.hidden=YES;allowed(windows,own,10001);three.hidden=NO;
    three.alpha=0;allowed(windows,own,10001);three.alpha=1;
    three.bounds=CGRectZero;allowed(windows,own,10001);three.bounds=CGRectMake(0,0,390,844);
    three.rootViewController.viewIfLoaded.hidden=YES;allowed(windows,own,10001);three.rootViewController.viewIfLoaded.hidden=NO;
    three.screen=[UIScreen new];allowed(windows,own,10001);three.screen=UIScreen.mainScreen;
    UIWindow *withdrawn=hud(1e30);withdrawn.hidden=YES;allowed(@[home,withdrawn,own],own,1001);
    // Malformed nonfinite HUD levels never infect the maximum or output.
    for(NSNumber *bad in @[@(NAN),@(INFINITY),@(-INFINITY)]) {
        UIWindow *w=hud(bad.doubleValue);allowed(@[home,w,own],own,1001);
    }
    UIWindow *huge=hud(0x1p24-1);allowed(@[home,huge,own],own,0x1p24);
    UIWindow *limit=hud(0x1p48-2);allowed(@[home,limit,own],own,0x1p48-1);
    UIWindow *unrepresentable=hud(0x1p48-1);denied(@[home,unrepresentable,own],own,unrepresentable);
    UIWindow *recording=[SBRecordingIndicatorWindow new];recording.windowLevel=1000000000;
    rootView(recording,recording.rootViewController.viewIfLoaded);
    allowed(@[home,recording,own],own,1000000001);recording.hidden=YES;allowed(@[home,recording,own],own,1001);
    // A gesture-containing security class gets NO special allowance, and a
    // small visible drawing is enough even without 30% area.
    UIWindow *auth=[GestureAuthenticationWindow new];auth.windowLevel=100000;
    UIView *authRoot=[UIView new];authRoot.bounds=CGRectMake(0,0,60,20);solid(authRoot);rootView(auth,authRoot);
    denied(@[home,auth,own],own,auth);auth.hidden=YES;allowed(@[home,auth,own],own,1001);auth.hidden=NO;
    authRoot.hidden=YES;allowed(@[home,auth,own],own,1001);authRoot.hidden=NO;
    UIWindow *permission=hud(100);PermissionView *permissionView=[PermissionView new];permissionView.bounds=CGRectMake(0,0,20,20);child(permission,permissionView);
    denied(@[home,permission,own],own,permission);
    // Security is evaluated BEFORE ignoring nonfinite levels.
    permission.windowLevel=NAN;denied(@[home,permission,own],own,permission);
    UIWindow *modal=hud(100);UIAlertController *alert=[UIAlertController new];
    alert.viewIfLoaded=[UIView new];alert.viewIfLoaded.bounds=CGRectMake(0,0,100,100);alert.viewIfLoaded.window=modal;
    alert.viewIfLoaded.layer.frame=alert.viewIfLoaded.bounds;[modal.layer addSublayer:alert.viewIfLoaded.layer];
    modal.rootViewController.presentedViewController=alert;
    denied(@[home,modal,own],own,modal);alert.viewIfLoaded.hidden=YES;allowed(@[home,modal,own],own,1001);alert.viewIfLoaded.hidden=NO;
    UIWindow *sheet=hud(100);UIActionSheet *sheetView=[UIActionSheet new];sheetView.bounds=CGRectMake(0,0,40,40);child(sheet,sheetView);
    denied(@[home,sheet,own],own,sheet);
    UIWindow *control=hud(10000);UIControl *button=[UIControl new];button.bounds=CGRectMake(0,0,30,20);child(control,button);
    allowed(@[home,control,own],own,10001);button.hidden=YES;allowed(@[home,control,own],own,10001);
    UIWindow *opaque=hud(10000);solid(opaque.rootViewController.viewIfLoaded);allowed(@[home,opaque,own],own,10001);
    // Trusted hosts still hide real authentication and presented alerts.
    home.rootViewController.presentedViewController=alert;
    denied(@[home,own],own,home);home.rootViewController.presentedViewController=nil;
    AuthenticationView *passcode=[AuthenticationView new];child(home,passcode);
    denied(@[home,own],own,home);passcode.hidden=YES;allowed(@[home,own],own,1001);
    BOOL authenticated=NO;
    assert(!LMVEasterScopePolicy(YES,0,YES,0,NO,NO,NO,&authenticated)); // ordinary app
    assert(!LMVEasterScopePolicy(YES,1,YES,0,NO,YES,YES,&authenticated)); // blank
    assert(!LMVEasterScopePolicy(NO,0,YES,0,NO,YES,YES,&authenticated)); // unknown blank state
    puts("PASS native: actual production priority/window helpers; multiple high transparent/tiny HUDs, 10000 stable own-excluded scans, foreign snapshot identity/level, withdrawal/nonfinite/bound, gesture-named security, permissions, small modal alert/action sheet/control, opaque high overlay, trusted host authentication; NOT SpringBoard compositing");
}return 0; }
'''
source = base + fixture
if '--emit-native' in sys.argv:
    print(source)
    raise SystemExit(0)
if platform.system() != 'Darwin':
    if '--require-native' in sys.argv:
        raise SystemExit('Native execution REQUIRED: macOS Foundation/QuartzCore/CoreGraphics unavailable')
    print('SKIP ObjC native: fixture assembled from exact production helpers; macOS required, no device validation claim')
    raise SystemExit(0)
with tempfile.TemporaryDirectory() as tmp:
    src = Path(tmp) / 'priority.m'
    binary = Path(tmp) / 'priority'
    src.write_text(source)
    subprocess.run(['clang', '-fobjc-arc', '-Wall', '-Wextra', '-Wno-unused-function', '-framework', 'Foundation', '-framework', 'QuartzCore', '-framework', 'CoreGraphics', str(src), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
