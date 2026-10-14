#pragma once
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>

// Independent user controls; NC deliberately has no new switch.
typedef struct {
    BOOL enabled, showOnLockScreen, showOnControlCenter, showOnDesktop, rotationEnabled;
    double rotationSpeed;
} LMVEasterDisplayControls;
typedef NS_ENUM(NSUInteger, LMVEasterDisplayScene) {
    LMVEasterDisplayNone, LMVEasterDisplayNC, LMVEasterDisplayLockScreen,
    LMVEasterDisplayControlCenter, LMVEasterDisplayDesktop
};
static BOOL LMVEasterDisplayBool(id value, BOOL fallback) {
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}
static double LMVEasterRotationSpeed(id value) {
    double speed=[value isKindOfClass:NSNumber.class] ? [value doubleValue] : 45.0;
    if (!isfinite(speed)) speed=45.0;
    return fmax(5.0,fmin(720.0,speed));
}
static LMVEasterDisplayControls LMVEasterDisplayControlsFromValues(id enabled,id lock,id cc,id desktop,id rotation,id speed) {
    return (LMVEasterDisplayControls){LMVEasterDisplayBool(enabled,NO),LMVEasterDisplayBool(lock,NO),
        LMVEasterDisplayBool(cc,YES),LMVEasterDisplayBool(desktop,YES),LMVEasterDisplayBool(rotation,NO),
        LMVEasterRotationSpeed(speed)};
}
// legacyAllows/authenticated come from the unchanged, current-screen-session NC
// policy. A lock preference never substitutes for screen/lock state, exposure,
// or the existing drawing/security audit. Hosts are already exposed physical
// SB windows, not persistent existence or a synthetic window. Topmost CC/NC
// does not fall through to a disabled surface's underlying desktop.
static LMVEasterDisplayScene LMVEasterDisplayPolicy(LMVEasterDisplayControls controls,
    BOOL blankKnown,uint64_t blank,BOOL lockKnown,uint64_t locked,
    BOOL nc,BOOL cc,BOOL home,BOOL authenticated,BOOL legacyAllows,BOOL safetyClear) {
    if (!controls.enabled || !safetyClear || !blankKnown || blank || !lockKnown) return LMVEasterDisplayNone;
    if (cc) return !locked && legacyAllows && controls.showOnControlCenter ? LMVEasterDisplayControlCenter : LMVEasterDisplayNone;
    if (nc) {
        if (authenticated && legacyAllows) return LMVEasterDisplayNC;
        return locked && !authenticated && controls.showOnLockScreen ? LMVEasterDisplayLockScreen : LMVEasterDisplayNone;
    }
    return home && !locked && legacyAllows && controls.showOnDesktop ? LMVEasterDisplayDesktop : LMVEasterDisplayNone;
}
static NSString * const LMVEasterRotationAnimationKey = @"com.minis.lockmessagevideo.easter.rotation";
// The helper owns a linear, infinitely repeated turn with an explicit start in
// the image layer's LOCAL clock. Evaluate that turn before changing its speed;
// this also works offscreen when QuartzCore has no presentation layer to sample.
static double LMVEasterRotationPhaseAtTime(CABasicAnimation *animation,CFTimeInterval now) {
    if (!animation || ![animation.fromValue isKindOfClass:NSNumber.class] ||
        ![animation.toValue isKindOfClass:NSNumber.class] || !isfinite(animation.duration) || animation.duration<=0) return 0;
    double from=[animation.fromValue doubleValue],to=[animation.toValue doubleValue];
    double elapsed=(now-animation.beginTime)*animation.speed+animation.timeOffset;
    if (!isfinite(from) || !isfinite(to) || !isfinite(elapsed)) return 0;
    double progress=fmod(fmax(0,elapsed),animation.duration)/animation.duration;
    double phase=fmod(from+(to-from)*progress,2.0*M_PI);
    return phase<0 ? phase+2.0*M_PI : phase;
}
// Operate ONLY on the image view's own layer, never its hit/drag container.
// Stable visibility audits and panel transitions do not restart the animation.
// No timer/display link, model transform or removeAllAnimations (GIF stays independent).
static void LMVEasterUpdateRotation(CALayer *imageLayer,BOOL visible,BOOL panelOpen,BOOL enabled,double speed) {
    if (!imageLayer) return;
    // Panel presence is not image visibility; keep the argument for existing callers.
    (void)panelOpen;
    CAAnimation *existing=[imageLayer animationForKey:LMVEasterRotationAnimationKey];
    if (!visible || !enabled) {
        if (existing) [imageLayer removeAnimationForKey:LMVEasterRotationAnimationKey];
        return;
    }
    speed=LMVEasterRotationSpeed(@(speed));
    CFTimeInterval duration=360.0/speed;
    CABasicAnimation *rotation=[existing isKindOfClass:CABasicAnimation.class] &&
        [((CABasicAnimation *)existing).keyPath isEqualToString:@"transform.rotation.z"] ? (CABasicAnimation *)existing : nil;
    if (rotation && fabs(rotation.duration-duration)<0.000001 && rotation.repeatCount==HUGE_VALF) return;
    CFTimeInterval now=[imageLayer convertTime:CACurrentMediaTime() fromLayer:nil];
    double phase=LMVEasterRotationPhaseAtTime(rotation,now);
    CABasicAnimation *animation=[CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    animation.fromValue=@(phase); animation.toValue=@(phase+2.0*M_PI);
    animation.beginTime=now; animation.duration=duration; animation.repeatCount=HUGE_VALF;
    animation.timingFunction=[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [imageLayer addAnimation:animation forKey:LMVEasterRotationAnimationKey];
}
