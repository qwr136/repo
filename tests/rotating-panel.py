#!/usr/bin/env python3
"""Production rotation helper + manager wiring; real macOS QuartzCore regression.
Linux runs source contracts only. --require-native refuses that skip;
--emit-native emits a self-contained ARC/Foundation/QuartzCore/CoreGraphics fixture.
UIKit owner inputs are doubles; neither this test nor macOS proves device compositing.
"""
from pathlib import Path
import platform
import subprocess
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
overlay = (root / 'LMVEasterOverlay.h').read_text()
policy = (root / 'LMVEasterDisplayPolicy.h').read_text()


def method(signature, following):
    start = overlay.index(signature + ' {')
    return overlay[start:overlay.index(following, start)]


sync = method('- (void)syncRotation', '- (void)hide {')
hide = method('- (void)hide', '- (void)keyboard:')
blank = method('- (void)recordScreenBlank', '- (void)syncUprightRotation {')
dealloc = method('- (void)dealloc', '- (void)changed:')
opened = method('- (void)openPanel', '- (void)closePanel {')
closed = method('- (void)closePanel', '@end')
apply = method('- (void)apply', '- (CGRect)dragArea {')
rotation = policy[policy.index('static void LMVEasterUpdateRotation('):]
assert 'if (!visible || !enabled)' in rotation, 'panel must not stop image rotation'
assert '(void)panelOpen;' in rotation and '|| panelOpen' not in rotation
assert 'convertTime:CACurrentMediaTime() fromLayer:nil' in rotation
assert 'animation.beginTime=now' in rotation and 'LMVEasterRotationPhaseAtTime(rotation,now)' in rotation
assert rotation.index('rotation.repeatCount==HUGE_VALF) return') < rotation.index('convertTime:')
assert all(word not in rotation for word in ('NSTimer', 'CADisplayLink', 'removeAllAnimations', 'setTransform:'))
assert 'LMVEasterUpdateRotation(self.bubbleImage.layer,visible,self.panel!=nil,' in sync
# 2.22 BEHAVIOUR CHANGE (assertion updated with reason, not weakened): the gate is
# no longer "our own window is visible" but "the window the BUBBLE is in is
# visible". On the lock screen the bubble is embedded in the cover sheet, because a
# separate non-system window is not rendered while the device is locked (2.21
# device log: hid=0 isHidden=0 a=1.00 attached=1 and still nothing on screen).
# Judging by self.window would then report "invisible" and silently kill rotation.
assert all(word in sync for word in ('self.bubble.window &&', '!self.bubble.hidden', '!self.bubbleImage.hidden',
    'self.bubble.window.alpha>=0.01', 'self.bubble.alpha>=0.01', 'self.bubbleImage.alpha>=0.01',
    'self.bubbleImage.image!=nil', 'self.displayControls.enabled && self.displayControls.rotationEnabled'))
assert '[self syncRotation]' in opened and '[self syncRotation]' in closed
# 2.23 BEHAVIOUR CHANGE (assertion updated with reason, not weakened): the panel is
# now allowed on the lock screen. The old guard existed because a separate window
# could not be drawn while locked, so an opened panel was invisible and the tap was
# swallowed. 2.22 embedded the ball in the cover sheet, which made "visible but
# dead" worse; the panel now goes into the SAME canvas and renders like the ball.
# 2.26: the lock-screen guard is back on purpose - the installed 2.22 behaviour is
# "ball visible, tap ignored", and that is the state that does not crash.
assert 'self.displayScene==LMVEasterDisplayLockScreen) return' in opened
# 2.24: the panel is not merely a subview - it is a CHILD VIEW CONTROLLER of the
# cover sheet's controller, because pushing the material picker and presenting the
# photo picker both need a controller that is installed in a hierarchy.
assert 'UIView *container = [self canvas];' in opened
# 2.25: never re-parent a SYSTEM controller (2.24 did, and SpringBoard went into
# safe mode). The panel stays a plain subview of the canvas on the lock screen, and
# only our OWN window's root controller may parent it.
assert 'coverController' not in opened
assert 'if (self.embedHost) {' in opened and '[container addSubview:self.panel.view];' in opened
assert 'UIViewController *root = self.window.rootViewController;' in opened
# 2.24: the panel must never lay out inside a degenerate area (2.23 shipped a 45 pt
# pill because the cover sheet reported almost no usable height).
layout = method('- (void)layout', '- (void)dragPanel:')
assert 'CGRect bounds = [self panelArea];' in layout
assert 'area.size.height<300' in overlay
assert hide.index('self.window.hidden = YES') < hide.index('[self syncRotation]') < hide.index('[self closePanel]')
# 0.0.114: a blank teardown must also say WHY (it used to hide silently, which
# made every "the ball disappeared" report undiagnosable).
assert 'self.authenticatedSession=NO; [self hide]' in blank
assert '[self reportWindow:@"hide:screen-blank"]' in blank
assert blank.index('reportWindow') < blank.index('[self hide]')
assert 'LMVEasterUpdateRotation(_bubbleImage.layer,NO,NO,NO,45)' in dealloc
assert '[self.timer invalidate]' in dealloc and '[self.visibilityTimer invalidate]' in dealloc
assert 'legacyAllows,safetyClear)' in apply and 'LMVEasterOverlayPriority(windows,self.window,&level,&blockedWindow)' in apply
priority = overlay[overlay.index('static BOOL LMVEasterBlockingWindow('):overlay.index('static void LMVEasterDarwin(')]
assert 'LMVEasterVisibleDrawing' in priority and 'LMVEasterBlockingWindow(window,0)' in priority
assert all(word not in apply for word in ('makeKeyWindow', 'resignKeyWindow'))
assert apply.index('LMVEasterDisplayPolicy(') < apply.index('self.window.hidden = NO')
assert 'self.bubbleImage.userInteractionEnabled = NO' in apply
# 2.63: the art sits in its own child so it can be counter-rotated in landscape
# while the hit/drag rectangle stays axis-aligned.
assert '[self.bubbleArt addSubview:self.bubbleImage]' in apply and '[self.bubble addSubview:self.bubbleArt]' in apply
assert all(word not in overlay for word in ('self.bubble.layer', 'self.window.layer', 'removeAllAnimations'))
gif = method('- (void)animateFrame', '- (void)openPanel {')
assert 'manager.bubbleImage.image = manager.decoded.frames[manager.frame]; [manager animateFrame]' in gif
assert 'forMode:NSRunLoopCommonModes' in gif and 'panel' not in gif and 'Rotation' not in gif

preamble = r'''
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
'''
# Embed the unmodified production header and exact lifecycle method bodies, not
# a Python reimplementation. Counters call real CALayer implementations.
fixture = r'''
@interface CountingLayer : CALayer
@property NSUInteger additions, removals;
@end
@implementation CountingLayer
- (void)addAnimation:(CAAnimation *)animation forKey:(NSString *)key {
    if ([key isEqualToString:LMVEasterRotationAnimationKey]) self.additions++;
    [super addAnimation:animation forKey:key];
}
- (void)removeAnimationForKey:(NSString *)key {
    if ([key isEqualToString:LMVEasterRotationAnimationKey]) self.removals++;
    [super removeAnimationForKey:key];
}
@end
@interface RotationView : NSObject
@property BOOL hidden;
@property CGFloat alpha;
@property(strong) CALayer *layer;
@property(strong) id image;
// 2.22: syncRotation judges visibility by the window the BUBBLE is in (the bubble
// can be embedded in the cover sheet on the lock screen), and hide() detaches an
// embedded bubble from its host - so the doubles need these three members.
@property(strong) RotationView *window, *superview;
- (void)removeFromSuperview;
@end
@implementation RotationView
- (instancetype)init { if ((self=[super init])) { _alpha=1; _layer=[CALayer layer]; } return self; }
- (void)removeFromSuperview { _superview=nil; }
@end
@interface RotationOwner : NSObject
@property(strong) RotationView *window, *bubble, *bubbleImage, *bubbleArt;
@property(strong) RotationView *embedHost;
@property(strong) id panel;
@property LMVEasterDisplayControls displayControls;
@property(strong) NSTimer *timer, *visibilityTimer;
@property BOOL authenticatedSession;
@property NSInteger reports;
@property(strong) NSString *lastReason;
- (void)syncRotation;
- (void)hide;
- (void)closePanel;
- (void)recordScreenBlank;
- (void)reportWindow:(NSString *)reason;
@end
@implementation RotationOwner
// UIKit panel containment is out of scope; its production rotation wiring is
// checked above. Only inputs/close containment are doubles; sync/hide/blank/
// dealloc below are the exact production method bodies.
- (void)closePanel { if (!self.panel) return; self.panel=nil; [self syncRotation]; }
- (void)syncUprightRotation {}
- (void)reportWindow:(NSString *)reason { self.reports++; self.lastReason=reason; }
'''
fixture += sync + hide + blank + dealloc + '@end\n'
fixture += r'''
static CABasicAnimation *turn(CALayer *layer) { return (id)[layer animationForKey:LMVEasterRotationAnimationKey]; }
static void near(double actual,double expected) { assert(isfinite(actual) && fabs(actual-expected)<1e-8); }
static void shape(CALayer *layer,double start,double phase,double duration) {
    CABasicAnimation *a=turn(layer); assert([a isKindOfClass:CABasicAnimation.class]);
    assert([a.keyPath isEqualToString:@"transform.rotation.z"] && a.repeatCount==HUGE_VALF);
    near(a.beginTime,start); near(a.duration,duration); near([a.fromValue doubleValue],phase);
    near([a.toValue doubleValue],phase+2*M_PI); assert(a.speed==1 && a.timeOffset==0 && !a.autoreverses);
    float p[2]; [a.timingFunction getControlPointAtIndex:1 values:p]; near(p[0],0); near(p[1],0);
    [a.timingFunction getControlPointAtIndex:2 values:p]; near(p[0],1); near(p[1],1);
}
int main(void) { @autoreleasepool {
    RotationOwner *owner=[RotationOwner new];
    owner.window=[RotationView new]; owner.bubble=[RotationView new]; owner.bubbleImage=[RotationView new];
    owner.bubble.window=owner.window; // the bubble lives in the window unless embedded
    CountingLayer *image=[CountingLayer layer]; owner.bubbleImage.layer=image; owner.bubbleImage.image=@"frame-0";
    owner.displayControls=LMVEasterDisplayControlsFromValues(@YES,@YES,@YES,@YES,@YES,@45);
    CALayer *window=owner.window.layer,*container=owner.bubble.layer,*panel=[CALayer layer];
    window.frame=CGRectMake(0,0,390,844); container.frame=CGRectMake(20,30,64,64); image.frame=container.bounds;
    panel.frame=CGRectMake(10,150,360,500); [window addSublayer:container]; [container addSublayer:image]; [window addSublayer:panel];
    CGRect containerFrame=container.frame,windowFrame=window.frame,panelFrame=panel.frame;
    // A paused real local clock is deterministic; no fake animation storage or
    // presentation layer is needed, and all add/remove operations are QuartzCore.
    image.speed=0; image.timeOffset=100;
    CABasicAnimation *other=[CABasicAnimation animationWithKeyPath:@"opacity"];
    other.fromValue=@1; other.toValue=@.9; other.duration=100; other.repeatCount=HUGE_VALF;
    [image addAnimation:other forKey:@"other-effect"];
    LMVEasterUpdateRotation(nil,YES,YES,YES,45);
    LMVEasterUpdateRotation(image,YES,NO,NO,45); assert(!turn(image));
    LMVEasterUpdateRotation(image,NO,YES,YES,45); assert(image.additions==0 && image.removals==0);
    // First start WITH panel open must run, not merely preserve a closed start.
    owner.panel=@"open"; [owner syncRotation]; shape(image,100,0,8);
    assert(image.additions==1 && image.removals==0);
    image.timeOffset=102; // 45 deg/s * 2 seconds = pi/2
    for (NSUInteger i=0;i<10000;i++) {
        owner.panel=i%2 ? @"open" : nil; owner.bubbleImage.image=@(i); [owner syncRotation];
    }
    shape(image,100,0,8); assert(image.additions==1 && image.removals==0);
    LMVEasterUpdateRotation(image,YES,YES,YES,180); shape(image,102,M_PI/2,2);
    image.timeOffset=102.375;
    LMVEasterUpdateRotation(image,YES,NO,YES,5); shape(image,102.375,7*M_PI/8,72);
    image.timeOffset=102.375+72+9; // one whole turn + 45 degrees, preserve wrapping
    LMVEasterUpdateRotation(image,YES,YES,YES,45); shape(image,183.375,9*M_PI/8,8);
    image.timeOffset=183.375+8*100000+4; // repeated turns, not just the first cycle
    LMVEasterUpdateRotation(image,YES,YES,YES,90); shape(image,image.timeOffset,M_PI/8,4);
    assert(image.additions==5 && image.removals==0);
    for (NSUInteger i=0;i<1000;i++) LMVEasterUpdateRotation(image,YES,i%2,YES,90);
    assert(image.additions==5 && image.removals==0 && [image animationForKey:@"other-effect"]);
    // Invalid/out-of-range speed is normalized exactly once; unchanged normalized
    // values do not churn. Restart after a real visibility stop may start at zero.
    double here=image.timeOffset;
    LMVEasterUpdateRotation(image,YES,YES,YES,-1); shape(image,here,M_PI/8,72);
    NSUInteger added=image.additions;
    LMVEasterUpdateRotation(image,YES,NO,YES,5); assert(image.additions==added);
    LMVEasterUpdateRotation(image,YES,YES,YES,721); shape(image,here,M_PI/8,.5);
    added=image.additions; LMVEasterUpdateRotation(image,YES,NO,YES,720); assert(image.additions==added);
    LMVEasterUpdateRotation(image,YES,YES,YES,INFINITY); shape(image,here,M_PI/8,8);
    added=image.additions; LMVEasterUpdateRotation(image,YES,YES,YES,NAN); assert(image.additions==added);
    // Stop matrix invokes actual manager syncRotation with the panel still open.
    for (NSUInteger reason=0;reason<10;reason++) {
        owner.window.hidden=NO; owner.bubble.hidden=NO; owner.bubbleImage.hidden=NO;
        owner.window.alpha=1; owner.bubble.alpha=1; owner.bubbleImage.alpha=1;
        owner.bubbleImage.image=@"GIF-frame"; owner.panel=@"open";
        owner.displayControls=LMVEasterDisplayControlsFromValues(@YES,@YES,@YES,@YES,@YES,@45);
        [owner syncRotation]; assert(turn(image));
        switch (reason) {
            case 0: owner.window.hidden=YES; break;
            case 1: owner.bubble.hidden=YES; break;
            case 2: owner.bubbleImage.hidden=YES; break;
            case 3: owner.bubbleImage.image=nil; break;
            case 4: { LMVEasterDisplayControls c=owner.displayControls; c.enabled=NO; owner.displayControls=c; break; }
            case 5: { LMVEasterDisplayControls c=owner.displayControls; c.rotationEnabled=NO; owner.displayControls=c; break; }
            case 6: owner.window.alpha=0; break;
            case 7: owner.bubble.alpha=0; break;
            case 8: owner.bubbleImage.alpha=0; break;
            case 9: owner.authenticatedSession=YES; owner.reports=0; [owner recordScreenBlank]; assert(!owner.authenticatedSession && !owner.panel && owner.reports==1 && [owner.lastReason isEqualToString:@"hide:screen-blank"]); break;
        }
        [owner syncRotation]; assert(!turn(image));
        NSUInteger removed=image.removals; [owner syncRotation]; assert(image.removals==removed);
        assert([image animationForKey:@"other-effect"]);
    }
    owner.window.hidden=NO; [owner syncRotation]; assert(turn(image));
    NSUInteger removed=image.removals;
    // Production dealloc must remove the owned turn on a layer retained by our
    // tree even while the panel is open; unrelated layer animations survive.
    owner.panel=@"open"; __weak RotationOwner *weakOwner=owner; owner=nil;
    assert(!weakOwner && !turn(image) && image.removals==removed+1);
    assert([image animationForKey:@"other-effect"]);
    assert(CGRectEqualToRect(container.frame,containerFrame) && CGRectEqualToRect(window.frame,windowFrame));
    assert(CGRectEqualToRect(panel.frame,panelFrame));
    for (CALayer *layer in @[window,container,panel]) {
        assert(![layer animationForKey:LMVEasterRotationAnimationKey] && CATransform3DIsIdentity(layer.transform));
    }
    assert(CATransform3DIsIdentity(image.transform));
    // A running/scaled ancestor clock must use convertTime, not global media
    // time. Speed replacement uses the old turn evaluated at the NEW beginTime.
    CALayer *scaled=[CALayer layer];
    CountingLayer *running=[CountingLayer layer]; [scaled addSublayer:running];
    // No render server commits a running ancestor clock in this CLI harness.
    // Real paused local time is deterministic and still tests convertTime.
    running.speed=0;running.timeOffset=100;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    LMVEasterUpdateRotation(running,YES,NO,YES,45);
    CABasicAnimation *first=turn(running);
    near(first.beginTime,100);
    // Jump only the fixture's clock by 2 local seconds to guarantee nonzero
    // phase without sleeping or depending on a window server/display refresh.
    running.timeOffset+=2;
    LMVEasterUpdateRotation(running,YES,YES,YES,180);
    CABasicAnimation *second=turn(running);
    double elapsed=second.beginTime-first.beginTime;
    assert(elapsed>=2 && elapsed<3);
    near([second.fromValue doubleValue],fmod(elapsed,8)/8*2*M_PI);
    near([second.toValue doubleValue]-[second.fromValue doubleValue],2*M_PI);
    assert(second.duration==2 && running.additions==2 && running.removals==0);
    LMVEasterUpdateRotation(running,NO,YES,YES,180); assert(!turn(running));
    [CATransaction commit];
    puts("PASS native: actual production rotation helper/manager sync, panel-open start, 10000 open/close/GIF-frame stable refreshes, nonzero/wrapped/scaled-local-clock speed phase continuity, finite clamps, hidden/no-image/master/rotation/blank stops, dealloc, unrelated effects and fixed parent/panel/hitbox; NOT device compositing");
} return 0; }
'''
source = preamble + policy.replace('#pragma once', '') + fixture
assert sync in source and hide in source and blank in source and dealloc in source
assert 'LMVEasterUpdateRotation(image,YES,YES,YES,180)' in source
if '--emit-native' in sys.argv:
    print(source)
    raise SystemExit(0)
print('PASS source: panel-independent image-leaf rotation, phase/wiring/blank/dealloc/GIF/security contracts and native fixture assembly')
if platform.system() != 'Darwin':
    if '--require-native' in sys.argv:
        raise SystemExit('Native execution REQUIRED: macOS clang + Foundation/QuartzCore/CoreGraphics unavailable on this host')
    print('SKIP native: real Foundation/QuartzCore execution requires macOS; no device validation claim')
    raise SystemExit(0)
with tempfile.TemporaryDirectory() as tmp:
    src = Path(tmp) / 'rotating-panel.m'
    binary = Path(tmp) / 'rotating-panel'
    src.write_text(source)
    subprocess.run(['clang', '-fobjc-arc', '-Wall', '-Wextra', '-Wno-unused-function',
                    '-framework', 'Foundation', '-framework', 'QuartzCore',
                    '-framework', 'CoreGraphics', str(src), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True, timeout=30)
