#!/usr/bin/env python3
"""Execute production desktop update with Foundation doubles; no device claim."""
from pathlib import Path
import platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text()
update='static void LMVUpdateDesktop(UIView *host, LMVDesktopSnapshot *snapshot) {'+s.split('static void LMVUpdateDesktop(UIView *host, LMVDesktopSnapshot *snapshot) {',1)[1].split('static void LMVUpdateDesktops',1)[0]
release_desktop=s.split('static void LMVReleaseDesktopSource(LMVVideoState *state) {',1)[1].split('static void LMVUpdateDesktop',1)[0]
for forbidden in ['removeFromSuperlayer', 'layer.hidden', 'layer.contents']:
    assert forbidden not in release_desktop
assert 'state.layer.hidden = YES' in update
assert 'insertSublayer:state.layer' not in update
assert 'wallpaperEligible' in update
assert '%hook UIView' not in s and '%hook SBIconContentView' not in s
observer=s.split('%hook SBFloatingDockWindow',1)[1].split('%end',1)[0]
assert observer.count('%orig;')==4
for forbidden in ['windowLevel =', 'setWindowLevel:', '.frame =', '.alpha =', '.transform =', '.hidden =']:
    assert forbidden not in observer.split('%orig;',1)[1]
sync=s.split('static void LMVSyncDisplayLink(void) {',1)[1].split('@implementation LMVDisplayLinkTarget',1)[0]
assert 'LMVReleaseDesktopSource' not in sync
needs=s.split('static BOOL LMVDesktopNeedsFrames(void) {',1)[1].split('static void LMVDesktopHostChanged',1)[0]
assert 'state.active' in needs and 'LMVDesktopCapture' not in needs
cover=s.split('static BOOL LMVDesktopCoverFullyObscures',1)[1].split('@interface LMVDesktopSnapshot',1)[0]
assert 'slideableContentView' in cover and '[content convertRect:content.bounds' in cover
for forbidden in ['StackShadow','NCNotificationListStackDimmingOverlayView','stackShadowOpacity']:
    assert forbidden not in s and forbidden not in (r/'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
if platform.system()!='Darwin':
    print('PASS: desktop integration constraints; Foundation execution deferred to macOS Actions')
    raise SystemExit(0)
preamble=r'''
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
#include "LMVConsumerPolicy.h"
#define CALayer LMVTestLayer
#define CATransaction LMVTestTransaction
static NSString *kCAGravityResizeAspectFill=@"aspectFill";
@interface CALayer : NSObject
@property(nonatomic,weak) CALayer *superlayer;
@property(nonatomic,strong) id contents, mask;
@property(nonatomic,copy) NSString *name, *contentsGravity;
@property(nonatomic) BOOL masksToBounds, hidden;
@property(nonatomic) CGRect frame;
@property(nonatomic) float opacity;
@property(nonatomic) NSUInteger inserts, removes;
@property(nonatomic,strong) NSMutableArray *children;
+ (instancetype)layer;
- (void)removeFromSuperlayer;
- (void)insertSublayer:(CALayer *)child atIndex:(unsigned)index;
- (void)insertSublayer:(CALayer *)child above:(CALayer *)other;
@end
@implementation CALayer
+ (instancetype)layer { return [self new]; }
- (instancetype)init { if((self=[super init])) _children=[NSMutableArray new]; return self; }
- (void)removeFromSuperlayer { _removes++; [self.superlayer.children removeObject:self]; self.superlayer=nil; }
- (void)insertSublayer:(CALayer *)child atIndex:(unsigned)index { _inserts++; child.superlayer=self; [self.children insertObject:child atIndex:MIN(index,self.children.count)]; }
- (void)insertSublayer:(CALayer *)child above:(CALayer *)other { [self insertSublayer:child atIndex:0]; }
@end
@interface UIView : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) NSArray *subviews;
@property(nonatomic) CGRect bounds, frame;
@property(nonatomic) BOOL hidden;
@property(nonatomic) double alpha, windowLevel;
@property(nonatomic) CGAffineTransform transform;
@end
@implementation UIView
- (instancetype)init { if((self=[super init])) { _layer=[CALayer layer]; _subviews=@[]; _alpha=1; _transform=CGAffineTransformIdentity; } return self; }
@end
@interface SBHomeScreenView : UIView @end
@implementation SBHomeScreenView @end
@interface CATransaction : NSObject
+ (void)begin; + (void)commit; + (void)setDisableActions:(BOOL)disabled;
@end
@implementation CATransaction
+ (void)begin {} + (void)commit {} + (void)setDisableActions:(BOOL)disabled {}
@end
@interface LMVSharedSource : NSObject
@property(nonatomic) const void *lastImage;
@property(nonatomic) BOOL playing, restoreOnStart;
@property(nonatomic) double time;
@end
@implementation LMVSharedSource @end
@interface LMVVideoState : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,weak) UIView *host;
@property(nonatomic,copy) NSString *path, *revision;
@property(nonatomic,strong) LMVSharedSource *source;
@property(nonatomic) BOOL active, wallpaperEligible;
@property(nonatomic) LMVDesktopGateClock desktopClock;
@end
@implementation LMVVideoState @end
@interface LMVDesktopSnapshot : NSObject
@property(nonatomic) double now;
@end
@implementation LMVDesktopSnapshot @end
@interface LMVFrameSnapshot : NSObject
@property(nonatomic) const void *image;
@end
@implementation LMVFrameSnapshot @end
static char LMVDesktopStateKey;
static NSMutableDictionary<NSString *, NSString *> *LMVPaths, *LMVRevisions;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *, LMVSharedSource *> *LMVSharedSources;
static NSMutableSet *LMVReadyAssets;
static BOOL LMVOpacityEnabled=YES;
static CGFloat LMVOpacity=.55;
static LMVDesktopActivity testActivity;
static NSUInteger acquired,released,starts,stops;
static LMVDesktopActivity LMVDesktopHostActivity(UIView *host, LMVVideoState *state, LMVDesktopSnapshot *snapshot) { return testActivity; }
static void LMVDesktopApplyDockMask(UIView *host, LMVVideoState *state, LMVDesktopActivity activity, LMVDesktopSnapshot *snapshot) {}
// Lease behavior is executed by original-background.m using REAL QuartzCore.
static void LMVRestoreBackground(LMVVideoState *state) {}
static void LMVReplaceBackground(LMVVideoState *state, UIView *anchor, UIView *scope, NSString *target, BOOL inScope) {}
// Wallpaper discovery/leases run with actual QuartzCore in original-background.m;
// this harness isolates desktop playback and lifetime from UIKit wall/scene enumeration.
static void LMVReplaceObservedWallpaper(LMVVideoState *state, UIView *host, NSString *target, BOOL inScope) {}
static void LMVUpdateWallpaperWindows(void) {}
static BOOL LMVDesktopOriginalInScope(UIView *host, LMVDesktopSnapshot *snapshot, LMVDesktopActivity activity) { return activity.draw; }
static void LMVDesktopDiagnostics(UIView *host, LMVVideoState *state, LMVDesktopActivity activity, LMVDesktopSnapshot *snapshot) {}
static BOOL LMVBranchHasWallpaper(UIView *view, NSUInteger depth) { return NO; }
static LMVFrameSnapshot *LMVCachedFrame(NSString *path, NSString *revision) { return nil; }
static LMVSharedSource *LMVSourceForPath(NSString *path) { acquired++; LMVSharedSource *source=[LMVSharedSource new]; LMVSharedSources[path]=source; return source; }
static BOOL LMVSourceHasConsumer(LMVSharedSource *source) { return NO; }
static void LMVStartSource(LMVSharedSource *source) { if(!source.playing) starts++; source.playing=YES; }
static void LMVStopSource(LMVSharedSource *source) { if(source.playing) stops++; source.playing=NO; source.restoreOnStart=YES; }
static void LMVReleaseDesktopSource(LMVVideoState *state) { if(state.source) { released++; [LMVSharedSources removeObjectForKey:state.path]; } LMVStopSource(state.source); state.source=nil; state.active=NO; }
static void LMVDiagnostic(NSString *event) {}
'''
tests=r'''
static LMVDesktopActivity step(LMVForeground front, bool covered, bool context, bool dockBelow, double now, LMVVideoState *state, LMVDesktopGateClock *clock) {
    return LMVDesktopGate(LMVDesktopDecide(1,1,1,1,1,1,0,front,covered,context),front,1,1,covered,context,dockBelow,state.active,now,clock);
}
int main(void) { @autoreleasepool {
    LMVPaths=[@{@"Desktop":@"desktop.mov"} mutableCopy]; LMVEnabled=[@{@"Desktop":@YES} mutableCopy];
    LMVRevisions=[@{@"desktop.mov":@"revision1"} mutableCopy]; LMVSharedSources=[NSMutableDictionary new];
    LMVReadyAssets=[NSMutableSet setWithObject:@"desktop.mov"];
    SBHomeScreenView *host=[SBHomeScreenView new]; host.bounds=(CGRect){0,0,390,844};
    UIView *dock=[UIView new], *unrelated=[UIView new]; dock.alpha=1; dock.windowLevel=25; dock.frame=(CGRect){12,720,366,100}; unrelated.hidden=YES;
    CGRect originalFrame=dock.frame; CGAffineTransform originalTransform=dock.transform;
    CALayer *systemLayer=dock.layer; [host.layer.children addObject:systemLayer];
    LMVDesktopGateClock clock={0,0};
    testActivity=(LMVDesktopActivity){1,1,0,0}; LMVUpdateDesktop(host,nil);
    LMVVideoState *state=objc_getAssociatedObject(host,&LMVDesktopStateKey);
    assert(state.active && acquired==1 && state.layer.hidden && !state.layer.superlayer);
    state.layer.contents=@"last-real-frame"; state.source.time=18.25;
    LMVSharedSource *originalSource=state.source;
    NSUInteger inserts=host.layer.inserts, removes=state.layer.removes;
    // Exact observed release/reload points from the 21986-byte .54 log.
    double releases[]={291848.980,291851.604,291854.019};
    double resumes[]={291850.057,291852.383,291854.905};
    for(int phase=0;phase<3;phase++) {
        testActivity=step(LMVForegroundUnknown,0,0,0,releases[phase],state,&clock); LMVUpdateDesktop(host,nil);
        testActivity=step(LMVForegroundUnknown,0,0,0,releases[phase]+.16,state,&clock); LMVUpdateDesktop(host,nil);
        testActivity=step(LMVForegroundHome,0,0,0,resumes[phase],state,&clock); LMVUpdateDesktop(host,nil);
        assert(state.source==originalSource && acquired==1 && released==0);
        assert(state.layer.hidden && [state.layer.contents isEqual:@"last-real-frame"]);
    }
    // Partial NC continues; full actual content cover pauses without hiding/releasing;
    // first exposed rectangle resumes same source/time immediately.
    testActivity=step(LMVForegroundHome,0,0,0,291855.1,state,&clock); LMVUpdateDesktop(host,nil); assert(state.active);
    testActivity=step(LMVForegroundHome,1,0,0,291855.2,state,&clock); LMVUpdateDesktop(host,nil);
    assert(!state.active && !state.source.playing && state.layer.hidden && state.source==originalSource);
    testActivity=step(LMVForegroundHome,1,0,0,291860.2,state,&clock); LMVUpdateDesktop(host,nil); assert(released==0);
    testActivity=step(LMVForegroundHome,0,0,0,291860.21,state,&clock); LMVUpdateDesktop(host,nil);
    assert(state.active && state.source==originalSource && state.source.time==18.25 && !state.source.restoreOnStart);
    // Original iPadDock level change 25 -> -3 is external; video stays live.
    dock.windowLevel=-3;
    for(int n=0;n<20;n++) {
        testActivity=step(LMVForegroundHome,0,1,1,291861+n*.1,state,&clock); LMVUpdateDesktop(host,nil);
        assert(state.active && state.layer.hidden && state.source==originalSource);
        assert([state.layer.contents isEqual:@"last-real-frame"] && host.layer.inserts==inserts && state.layer.removes==removes);
        assert(!dock.hidden && dock.alpha==1 && dock.windowLevel==-3 && CGRectEqualToRect(dock.frame,originalFrame));
        assert(CGAffineTransformEqualToTransform(dock.transform,originalTransform) && unrelated.hidden && unrelated.alpha==1);
        assert([host.layer.children containsObject:systemLayer]);
    }
    dock.windowLevel=25; testActivity=step(LMVForegroundHome,0,0,0,291864,state,&clock); LMVUpdateDesktop(host,nil);
    assert(state.active && state.layer.hidden && acquired==1);
    testActivity=step(LMVForegroundApp,0,0,0,291865,state,&clock); LMVUpdateDesktop(host,nil);
    assert(!state.active && !originalSource.playing && state.source==originalSource);
    testActivity=step(LMVForegroundApp,0,0,0,291866.26,state,&clock); LMVUpdateDesktop(host,nil);
    assert(!state.source && released==1 && [state.layer.contents isEqual:@"last-real-frame"]);
    testActivity=step(LMVForegroundHome,0,0,0,291866.3,state,&clock); LMVUpdateDesktop(host,nil); assert(state.active && acquired==2);
    testActivity=LMVDesktopGate(LMVDesktopDecide(1,1,1,1,0,1,0,LMVForegroundHome,0,0),LMVForegroundHome,1,1,0,0,0,1,291867,&clock);
    LMVUpdateDesktop(host,nil); assert(!state.active && state.layer.hidden && [state.layer.contents isEqual:@"last-real-frame"]);
    LMVEnabled[@"Desktop"]=@NO; LMVUpdateDesktop(host,nil);
    assert(!objc_getAssociatedObject(host,&LMVDesktopStateKey) && !state.layer.superlayer);
    assert([host.layer.children containsObject:systemLayer] && dock.alpha==1);
    puts("PASS: actual desktop update; .54 source4..7 timings do not rebuild; partial/full/reveal NC; paused clock/frame retained; lower Dock keeps live desktop and masks only owned layer; real app pauses/retires; screen off/disable; system attributes unchanged (Foundation doubles, NOT device test)");
} return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'desktop.m'; binary=Path(tmp)/'desktop'
    src.write_text(preamble+update+tests)
    subprocess.run(['clang','-fobjc-arc','-I',str(r),'-framework','Foundation','-framework','CoreGraphics',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
