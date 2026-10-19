#!/usr/bin/env python3
"""Production display policy + Foundation/QuartzCore native positive/negative controls.
Linux verifies wiring only; --require-native refuses a skip. --emit-native prints
an Objective-C fixture (compile on macOS with ARC/Foundation/QuartzCore/CoreGraphics).
"""
from pathlib import Path
import platform, subprocess, sys, tempfile
root=Path(__file__).resolve().parents[1]
s=(root/'LMVEasterOverlay.h').read_text()
policy=(root/'LMVEasterDisplayPolicy.h').read_text()
apply=s[s.index('- (void)apply {'):s.index('- (CGRect)dragArea {')]
hide=s[s.index('- (void)hide {'):s.index('- (void)keyboard:')]
rotation=policy[policy.index('static void LMVEasterUpdateRotation('):]
assert all(k in apply for k in ('EasterEggEnabled','EasterEggShowOnLockScreen','EasterEggShowOnControlCenter',
    'EasterEggShowOnDesktop','EasterEggRotationEnabled','EasterEggRotationSpeed'))
assert 'LMVEasterDisplayControlsFromValues' in apply and 'CFPreferencesAppSynchronize' in apply
assert 'legacyAllows,safetyClear)' in apply and 'LMVEasterOverlayPriority(windows,self.window,&level,&blockedWindow)' in apply
blocking=s[s.index('static BOOL LMVEasterBlockingWindow'):s.index('static void LMVEasterDarwin')]
assert 'LMVEasterVisibleDrawing' in blocking and 'LMVEasterBlockingWindow' in blocking
assert apply.index('LMVEasterDisplayPolicy(') < apply.index('self.window.hidden = NO')
assert s.count('[[LMVEasterWindow alloc]')==1
assert 'self.bubble = [[UIView alloc]' in apply and 'self.bubbleImage = [[UIImageView alloc]' in apply
assert 'self.bubbleImage.userInteractionEnabled = NO' in apply
assert hide.index('self.window.hidden = YES') < hide.index('[self syncRotation]') < hide.index('[self closePanel]')
# 2.23: the constant is no longer referenced by an openPanel guard (the panel may
# open on the lock screen now), but the lock-screen scene must still be named - it
# drives the cover-sheet embedding choice.
assert s.count('[self syncRotation]')>=4 and '(displayScene==LMVEasterDisplayLockScreen)' in s
assert all(w not in rotation for w in ('NSTimer','CADisplayLink','removeAllAnimations','setTransform:'))
assert 'duration=360.0/speed' in rotation and 'HUGE_VALF' in rotation
assert 'imageLayer addAnimation:animation forKey:LMVEasterRotationAnimationKey' in rotation
assert 'manager.bubbleImage.image = manager.decoded.frames[manager.frame]' in s
assert 'self.physicalSnapshot=nil' in s and '[manager refresh]' in s and 'preferencesChanged' in s
if platform.system()!='Darwin' and '--emit-native' not in sys.argv:
    if '--require-native' in sys.argv:
        raise SystemExit('Native execution REQUIRED: macOS clang + Foundation/QuartzCore/CoreGraphics unavailable on this host')
    print('PASS: display/rotation production wiring source contracts; SKIP native matrix/CAAnimation execution (requires macOS)')
    raise SystemExit(0)
preamble=subprocess.check_output([sys.executable,str(root/'tests/easter-window.py'),'--emit-native'],text=True)
main=r'''
@interface RotationLayer : CALayer
@property NSUInteger additions, removals;
@end
@implementation RotationLayer
- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key {
    self.additions++;[super addAnimation:animation forKey:key];
}
- (void)removeAnimationForKey:(NSString *)key {
    self.removals++;[super removeAnimationForKey:key];
}
@end
static LMVEasterDisplayScene runPolicy(LMVEasterDisplayControls controls,
    BOOL bk,uint64_t blank,BOOL lk,uint64_t locked,BOOL nc,BOOL cc,BOOL home,BOOL auth,BOOL safe) {
    BOOL legacy=LMVEasterScopePolicy(bk,blank,lk,locked,nc,cc,home,&auth);
    return LMVEasterDisplayPolicy(controls,bk,blank,lk,locked,nc,cc,home,auth,legacy,safe);
}
static void solidDisplay(UIView *view) {
    UIColor *color=[UIColor new];color.CGColor=CGColorCreateGenericRGB(.2,.3,.4,1);view.backgroundColor=color;
}
@interface PasscodeView : UIView @end
@implementation PasscodeView @end
@interface PermissionView : UIView @end
@implementation PermissionView @end
int main(void) { @autoreleasepool {
    LMVEasterDisplayControls defaults=LMVEasterDisplayControlsFromValues(nil,nil,nil,nil,nil,nil);
    assert(!defaults.enabled && !defaults.showOnLockScreen && defaults.showOnControlCenter && defaults.showOnDesktop);
    assert(!defaults.rotationEnabled && defaults.rotationSpeed==45);
    assert(!LMVEasterDisplayBool(@"YES",NO));assert(LMVEasterDisplayBool(@"NO",YES));
    assert(LMVEasterRotationSpeed(nil)==45 && LMVEasterRotationSpeed(@"junk")==45);
    assert(LMVEasterRotationSpeed(@(NAN))==45 && LMVEasterRotationSpeed(@(INFINITY))==45);
    assert(LMVEasterRotationSpeed(@(-1))==5 && LMVEasterRotationSpeed(@721)==720);
    assert(LMVEasterRotationSpeed(@5)==5 && LMVEasterRotationSpeed(@180)==180 && LMVEasterRotationSpeed(@720)==720);
    for(NSUInteger flags=0;flags<32;flags++) {
        LMVEasterDisplayControls c=LMVEasterDisplayControlsFromValues(@(!!(flags&1)),@(!!(flags&2)),
            @(!!(flags&4)),@(!!(flags&8)),@(!!(flags&16)),@45);
        BOOL on=c.enabled;
        assert(runPolicy(c,YES,0,YES,0,NO,NO,YES,NO,YES)==(on && c.showOnDesktop?LMVEasterDisplayDesktop:LMVEasterDisplayNone));
        assert(runPolicy(c,YES,0,YES,0,NO,YES,NO,NO,YES)==(on && c.showOnControlCenter?LMVEasterDisplayControlCenter:LMVEasterDisplayNone));
        assert(runPolicy(c,YES,0,YES,0,YES,NO,NO,YES,YES)==(on?LMVEasterDisplayNC:LMVEasterDisplayNone));
        assert(runPolicy(c,YES,0,YES,1,YES,NO,NO,YES,YES)==(on?LMVEasterDisplayNC:LMVEasterDisplayNone)); // NC lockstate pulse
        assert(runPolicy(c,YES,0,YES,1,YES,NO,NO,NO,YES)==(on && c.showOnLockScreen?LMVEasterDisplayLockScreen:LMVEasterDisplayNone));
        assert(runPolicy(c,YES,0,YES,0,YES,NO,NO,NO,YES)==LMVEasterDisplayNone); // Face ID alone is not NC
        assert(runPolicy(c,YES,0,YES,0,YES,YES,YES,NO,YES)==LMVEasterDisplayNone); // overlapping CC never bypasses that gate
        assert(runPolicy(c,YES,0,YES,0,NO,NO,NO,NO,YES)==LMVEasterDisplayNone); // ordinary app/unknown
        assert(runPolicy(c,YES,0,YES,1,NO,NO,YES,NO,YES)==LMVEasterDisplayNone); // no real CoverSheet
        assert(runPolicy(c,YES,0,YES,1,NO,YES,YES,NO,YES)==LMVEasterDisplayNone); // CC on locked device is NOT lock support
        assert(runPolicy(c,YES,0,YES,0,YES,YES,YES,YES,YES)==(on && c.showOnControlCenter?LMVEasterDisplayControlCenter:LMVEasterDisplayNone)); // topmost, no fallthrough
        for(NSUInteger scene=0;scene<4;scene++) {
            BOOL nc=scene==0 || scene==3,cc=scene==1,home=scene==2,auth=scene!=3;uint64_t locked=scene==3;
            assert(runPolicy(c,NO,0,YES,locked,nc,cc,home,auth,YES)==LMVEasterDisplayNone);
            assert(runPolicy(c,YES,1,YES,locked,nc,cc,home,auth,YES)==LMVEasterDisplayNone);
            assert(runPolicy(c,YES,0,NO,locked,nc,cc,home,auth,YES)==LMVEasterDisplayNone);
            assert(runPolicy(c,YES,0,YES,locked,nc,cc,home,auth,NO)==LMVEasterDisplayNone); // security gate dominates all flags
        }
    }
    LMVEasterDisplayControls c=LMVEasterDisplayControlsFromValues(@YES,@YES,@YES,@YES,@YES,@45);
    SBCoverSheetWindow *window=[SBCoverSheetWindow new];
    CSCoverSheetView *cover=[CSCoverSheetView new];cover.superview=window;cover.window=window;
    [window.layer addSublayer:cover.layer];cover.layer.frame=window.bounds;window.subviews=@[cover];
    UIView *content=[UIView new];content.superview=cover;content.window=window;
    [cover.layer addSublayer:content.layer];content.layer.frame=cover.bounds;cover.subviews=@[content];cover.slideableContentView=content;
    window.rootViewController.viewIfLoaded=cover;
    assert(LMVEasterNCWindowExposed(window));
    assert(runPolicy(c,YES,0,YES,1,LMVEasterNCWindowExposed(window),NO,NO,NO,YES)==LMVEasterDisplayLockScreen);
    content.layer.frame=CGRectMake(0,-844,390,844);
    assert(!LMVEasterNCWindowExposed(window));
    assert(runPolicy(c,YES,0,YES,1,LMVEasterNCWindowExposed(window),NO,NO,NO,YES)==LMVEasterDisplayNone);
    content.layer.frame=cover.bounds;
    for(UIView *danger in @[[PasscodeView new],[AuthenticationView new],[PermissionView new]]) {
        danger.window=window;danger.superview=content;[content.layer addSublayer:danger.layer];danger.layer.frame=content.bounds;content.subviews=@[danger];
        NSUInteger budget=64;BOOL security=NO;LMVEasterVisibleDrawing(cover,window,0,&budget,&security);
        assert(security && runPolicy(c,YES,0,YES,1,YES,NO,NO,NO,!security)==LMVEasterDisplayNone);
        danger.hidden=YES;budget=64;security=NO;LMVEasterVisibleDrawing(cover,window,0,&budget,&security);assert(!security);
        [danger.layer removeFromSuperlayer];
    }
    UIWindow *alert=[AuthenticationWindow new];alert.windowLevel=UIWindowLevelAlert;solidDisplay(alert.rootViewController.viewIfLoaded);
    assert(LMVEasterBlockingWindow(alert,1200));
    assert(runPolicy(c,YES,0,YES,1,YES,NO,NO,NO,!LMVEasterBlockingWindow(alert,1200))==LMVEasterDisplayNone);
    alert.hidden=YES;assert(!LMVEasterBlockingWindow(alert,1200));
'''
main+=r'''
    RotationLayer *image=[RotationLayer layer];CALayer *container=[CALayer layer];
    container.frame=CGRectMake(20,30,64,64);image.frame=container.bounds;[container addSublayer:image];
    CGRect fixedFrame=container.frame;CATransform3D fixedTransform=container.transform;
    CABasicAnimation *unrelated=[CABasicAnimation animationWithKeyPath:@"opacity"];
    unrelated.fromValue=@1;unrelated.toValue=@.9;unrelated.duration=100;unrelated.repeatCount=HUGE_VALF;
    [image addAnimation:unrelated forKey:@"other-effect"];image.additions=0;
    LMVEasterUpdateRotation(image,YES,NO,NO,45);assert(![image animationForKey:LMVEasterRotationAnimationKey]);
    LMVEasterUpdateRotation(image,NO,NO,YES,45);assert(image.additions==0);
    LMVEasterUpdateRotation(image,YES,YES,YES,45);assert(image.additions==1);
    CFTimeInterval panelBegin=[image animationForKey:LMVEasterRotationAnimationKey].beginTime;
    LMVEasterUpdateRotation(image,YES,NO,YES,45);assert(image.additions==1 && [image animationForKey:LMVEasterRotationAnimationKey].beginTime==panelBegin);
    LMVEasterUpdateRotation(image,YES,NO,YES,45);
    CABasicAnimation *animation=(id)[image animationForKey:LMVEasterRotationAnimationKey];
    assert(animation && [animation.keyPath isEqualToString:@"transform.rotation.z"]);
    assert(animation.duration==8 && animation.repeatCount==HUGE_VALF);
    assert([animation.fromValue doubleValue]==0 && fabs([animation.toValue doubleValue]-2*M_PI)<1e-9);
    assert([image animationForKey:@"other-effect"] && image.additions==1);
    for(NSUInteger i=0;i<10000;i++)LMVEasterUpdateRotation(image,YES,NO,YES,45);
    assert(image.additions==1 && image.removals==0); // actual native CALayer, not a duplicated Python policy
    LMVEasterUpdateRotation(image,YES,NO,YES,180);
    assert([image animationForKey:LMVEasterRotationAnimationKey].duration==2 && image.additions==2);
    LMVEasterUpdateRotation(image,YES,NO,YES,5);
    assert([image animationForKey:LMVEasterRotationAnimationKey].duration==72 && image.additions==3);
    for(NSUInteger action=0;action<3;action++) {
        LMVEasterUpdateRotation(image,YES,NO,YES,45);assert([image animationForKey:LMVEasterRotationAnimationKey]);
        // preference OFF, screen blank/scope exit/image replacement, master OFF;
        // panel open now deliberately keeps rotation and phase.
        LMVEasterUpdateRotation(image,action!=1,YES,action==1,45);
        assert(![image animationForKey:LMVEasterRotationAnimationKey]);
        NSUInteger removed=image.removals;
        LMVEasterUpdateRotation(image,NO,YES,NO,45);assert(image.removals==removed);
        assert([image animationForKey:@"other-effect"]);
    }
    LMVEasterUpdateRotation(nil,YES,NO,YES,45);
    assert(CGRectEqualToRect(container.frame,fixedFrame) && CATransform3DEqualToTransform(container.transform,fixedTransform));
    assert(CATransform3DIsIdentity(image.transform)); // model transform/frame/hitTest/drag untouched
    puts("PASS native: production 32 flag combinations, NC/Home/CC/App/realLock/blank/unknown, actual CoverSheet exposure and authentication/permission/alert safety; real CAAnimation start/stop/45/5/180 speeds + 10000 stable updates, unrelated animation and container unchanged; NOT device SpringBoard compositing");
}return 0; }
'''
source=preamble+policy.replace('#pragma once','')+main
if '--emit-native' in sys.argv:
    print(source)
    raise SystemExit(0)
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp)/'display.m';p.write_text(source);binary=Path(tmp)/'display'
    subprocess.run(['clang','-fobjc-arc','-Wall','-Wextra','-framework','Foundation','-framework','QuartzCore',
        '-framework','CoreGraphics',str(p),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)
