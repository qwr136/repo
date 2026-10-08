#!/usr/bin/env python3
"""Execute production Dock discovery/path/mask with real Core Animation layers.
UIKit coordinate bridges are Foundation doubles; this is not a device test.
"""
from pathlib import Path
import platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text()
geometry='// Read-only, bounded discovery.'+s.split('// Read-only, bounded discovery.',1)[1].split('// Opt-in bounded structural diagnostics',1)[0]
assert 'window.bounds' not in geometry
assert 'node != window && LMVDesktopDockContainer(node)' in geometry
assert 'visited >= 96' in geometry and 'windows > 16' in geometry
assert 'LMVDesktopDockRegionSafe' in geometry and 'CGPathEqualToPath' in geometry
assert 'no-safe-dock-region' in geometry and 'kCAFillRuleEvenOdd' in geometry
assert 'viewIfLoaded' in geometry and 'view.nextResponder' in geometry
for forbidden in ['insertSublayer','removeFromSuperlayer','setWindowLevel:','objc_msgSend','NSSelectorFromString','sharedInstance']:
    assert forbidden not in geometry, forbidden
assert 'dock-window-below-home-owned-layer-hidden' not in s
if platform.system()!='Darwin':
    print('PASS: bounded scoped Dock source contracts; real CALayer execution deferred to macOS Actions')
    raise SystemExit(0)
preamble=r'''
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <assert.h>
#include "LMVConsumerPolicy.h"
@interface TestLayer : CALayer
@property(nonatomic,strong) CALayer *shown;
@end
@implementation TestLayer
- (TestLayer *)presentationLayer { return (TestLayer *)self.shown; }
@end
@class UIView, UIWindow, ScreenSpace;
@interface UIViewController : NSObject
@property(nonatomic,strong) UIView *viewIfLoaded;
@end
@implementation UIViewController @end
@interface SBFloatingDockViewController : UIViewController @end
@implementation SBFloatingDockViewController @end
@interface UIScreen : NSObject
@property(nonatomic,strong) ScreenSpace *coordinateSpace;
@end
@interface UIView : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) NSMutableArray<UIView *> *subviews;
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) id nextResponder;
@property(nonatomic) BOOL hidden;
@property(nonatomic) double alpha;
@property(nonatomic) CGRect bounds;
@end
@implementation UIView
- (instancetype)init { if ((self=[super init])) { _layer=[TestLayer layer]; _subviews=[NSMutableArray new]; _alpha=1; } return self; }
- (void)setBounds:(CGRect)bounds { _bounds=bounds; self.layer.bounds=bounds; }
@end
@interface UIWindow : UIView
@property(nonatomic,strong) UIScreen *screen;
@property(nonatomic) double windowLevel;
@property(nonatomic) CGPoint screenOrigin;
- (CGPoint)convertPoint:(CGPoint)point toCoordinateSpace:(id)space;
@end
@interface ScreenSpace : NSObject
- (CGPoint)convertPoint:(CGPoint)point toCoordinateSpace:(UIWindow *)window;
@end
@implementation ScreenSpace
- (CGPoint)convertPoint:(CGPoint)point toCoordinateSpace:(UIWindow *)window { return CGPointMake(point.x-window.screenOrigin.x,point.y-window.screenOrigin.y); }
@end
@implementation UIScreen
- (instancetype)init { if((self=[super init])) _coordinateSpace=[ScreenSpace new]; return self; }
@end
@implementation UIWindow
- (CGPoint)convertPoint:(CGPoint)point toCoordinateSpace:(id)space { return CGPointMake(point.x+self.screenOrigin.x,point.y+self.screenOrigin.y); }
@end
@interface SBFloatingDockWindow : UIWindow @end
@implementation SBFloatingDockWindow @end
@interface SBFloatingDockView : UIView @end
@implementation SBFloatingDockView @end
@interface SBFloatingDockPlatterView : UIView @end
@implementation SBFloatingDockPlatterView @end
@interface SBIconView : UIView @end
@implementation SBIconView @end
@interface Host : UIView
@property(nonatomic,weak) UIWindow *window;
@end
@implementation Host @end
// Production uses UIView.window. Resolve it on the double without creating views.
@interface UIView (Window)
- (UIWindow *)window;
@end
@implementation UIView (Window)
- (UIWindow *)window { for(UIView *v=self;v;v=v.superview) if([v isKindOfClass:UIWindow.class]) return (UIWindow *)v; return nil; }
@end
@interface LMVVideoState : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) CAShapeLayer *desktopDockMask;
@property(nonatomic) CGRect desktopDockRect;
@property(nonatomic,copy) NSString *desktopDockReason;
@end
@implementation LMVVideoState @end
@interface LMVDesktopSnapshot : NSObject
@property(nonatomic,strong) NSArray<UIWindow *> *windows;
@end
@implementation LMVDesktopSnapshot @end
static LMVDesktopRect LMVDesktopPolicyRect(CGRect r) { return (LMVDesktopRect){r.origin.x,r.origin.y,r.size.width,r.size.height}; }
static LMVWindowRole LMVDesktopRole(id o) { return [o isKindOfClass:SBFloatingDockWindow.class] ? LMVWindowFloatingDock : LMVWindowOther; }
static void attach(UIView *parent, UIView *child, CGRect frame) {
    child.superview=parent; [parent.subviews addObject:child]; [parent.layer addSublayer:child.layer];
    child.layer.frame=frame; child.bounds=child.layer.bounds;
}
static BOOL visibleAt(LMVVideoState *state, CGPoint point) { return !state.layer.mask || CGPathContainsPoint(state.desktopDockMask.path,NULL,point,true); }
'''
tests=r'''
int main(void) { @autoreleasepool {
    UIScreen *screen=[UIScreen new];
    UIWindow *home=[UIWindow new]; home.screen=screen; home.windowLevel=-2; home.bounds=CGRectMake(0,0,390,844);
    Host *host=[Host new]; attach(home,host,home.bounds); host.window=home;
    SBFloatingDockWindow *dock=[SBFloatingDockWindow new]; dock.screen=screen; dock.windowLevel=-3; dock.bounds=home.bounds;
    SBFloatingDockView *wrapper=[SBFloatingDockView new]; attach(dock,wrapper,dock.bounds); // full-screen wrapper must fail
    SBFloatingDockPlatterView *platter=[SBFloatingDockPlatterView new]; attach(wrapper,platter,CGRectMake(12,720,366,100));
    platter.layer.cornerRadius=25;
    LMVVideoState *state=[LMVVideoState new]; state.layer=[CALayer layer]; state.layer.frame=host.bounds; state.layer.contents=@"cached-real-frame";
    LMVDesktopSnapshot *snapshot=[LMVDesktopSnapshot new]; snapshot.windows=@[dock];
    LMVDesktopActivity lower={1,1,0,1}, normal={1,1,0,0};
    CGRect originalFrame=dock.layer.frame; CATransform3D originalTransform=dock.layer.transform;
    LMVDesktopApplyDockMask(host,state,lower,snapshot);
    assert(state.layer.mask==state.desktopDockMask && [state.desktopDockReason isEqual:@"scoped-dock-region"]);
    assert(CGRectEqualToRect(state.desktopDockRect,CGRectMake(12,720,366,100)));
    assert(visibleAt(state,CGPointMake(195,300)) && !visibleAt(state,CGPointMake(195,770)));
    assert(visibleAt(state,CGPointMake(12,720))); // true measured round corner
    CAShapeLayer *owned=state.desktopDockMask; CGPathRef identity=CGPathRetain(owned.path);
    for(int i=0;i<500;i++) LMVDesktopApplyDockMask(host,state,lower,snapshot);
    assert(state.desktopDockMask==owned && owned.path==identity && owned.superlayer==nil);
    assert([state.layer.contents isEqual:@"cached-real-frame"] && !state.layer.hidden);
    CGPathRelease(identity);
    // exact simple system shape mask can supply the outline without cornerRadius.
    CAShapeLayer *systemMask=[CAShapeLayer layer]; systemMask.frame=platter.bounds;
    CGPathRef outline=CGPathCreateWithRoundedRect(platter.bounds,20,20,NULL); systemMask.path=outline; CGPathRelease(outline);
    platter.layer.mask=systemMask; platter.layer.cornerRadius=0;
    LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(state.layer.mask && platter.layer.mask==systemMask);
    assert(!visibleAt(state,CGPointMake(195,770)) && visibleAt(state,CGPointMake(12,720)));
    // Unsupported arbitrary mask/corner is not guessed; old owned mask is cleared.
    platter.layer.mask=[CALayer layer]; LMVDesktopApplyDockMask(host,state,lower,snapshot);
    assert(!state.layer.mask && [state.desktopDockReason isEqual:@"no-safe-dock-region"]);
    platter.layer.mask=nil; LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask);
    platter.layer.cornerRadius=25;
    platter.hidden=YES; LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask); platter.hidden=NO;
    wrapper.alpha=0; LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask); wrapper.alpha=1;
    dock.hidden=YES; LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask); dock.hidden=NO;
    dock.alpha=0; LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask); dock.alpha=1;
    dock.screen=[UIScreen new]; LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask); dock.screen=screen;
    dock.windowLevel=25; LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask); dock.windowLevel=-3;
    // Full-screen content, offscreen Dock, and only individual icons produce no hole.
    platter.layer.frame=home.bounds; platter.bounds=platter.layer.bounds;
    LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask);
    platter.layer.frame=CGRectMake(12,900,366,100); platter.bounds=platter.layer.bounds;
    LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask);
    SBIconView *icon=[SBIconView new]; attach(dock,icon,CGRectMake(30,735,60,60)); icon.layer.cornerRadius=12;
    LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask);
    platter.layer.frame=CGRectMake(12,720,366,100); platter.bounds=platter.layer.bounds;
    // Only known loaded controller content is accepted, never a generic/icon view.
    UIView *content=[UIView new]; SBFloatingDockViewController *controller=[SBFloatingDockViewController new];
    content.nextResponder=controller; assert(!LMVDesktopDockContainer(content));
    controller.viewIfLoaded=content; assert(LMVDesktopDockContainer(content));
    // Public coordinate-space bridges account for independent window origins.
    dock.screenOrigin=CGPointMake(0,5); LMVDesktopApplyDockMask(host,state,lower,snapshot);
    assert(CGRectEqualToRect(state.desktopDockRect,CGRectMake(12,725,366,100))); dock.screenOrigin=CGPointZero;
    platter.layer.shadowOpacity=1; platter.layer.shadowRadius=50;
    LMVDesktopApplyDockMask(host,state,lower,snapshot);
    assert(CGRectEqualToRect(state.desktopDockRect,CGRectMake(6,714,378,112))); // margin bounded to six
    platter.layer.shadowOpacity=0;
    // Actual moving presentation rect, coherent trees on both windows/host.
    CALayer *dockShown=[CALayer layer], *wrapperShown=[CALayer layer], *platterShown=[CALayer layer];
    dockShown.frame=dock.layer.frame; wrapperShown.frame=wrapper.layer.frame; platterShown.frame=CGRectMake(12,705,366,100); platterShown.cornerRadius=25;
    [dockShown addSublayer:wrapperShown]; [wrapperShown addSublayer:platterShown];
    CALayer *homeShown=[CALayer layer], *hostShown=[CALayer layer]; homeShown.frame=home.layer.frame; hostShown.frame=host.layer.frame; [homeShown addSublayer:hostShown];
    ((TestLayer *)dock.layer).shown=dockShown; ((TestLayer *)wrapper.layer).shown=wrapperShown; ((TestLayer *)platter.layer).shown=platterShown;
    ((TestLayer *)home.layer).shown=homeShown; ((TestLayer *)host.layer).shown=hostShown;
    LMVDesktopApplyDockMask(host,state,lower,snapshot);
    assert(CGRectEqualToRect(state.desktopDockRect,CGRectMake(12,705,366,100)));
    dockShown.position=CGPointMake(dockShown.position.x+1,dockShown.position.y); // unstable window bridge
    LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(!state.layer.mask);
    ((TestLayer *)dock.layer).shown=nil; ((TestLayer *)wrapper.layer).shown=nil; ((TestLayer *)platter.layer).shown=nil;
    ((TestLayer *)home.layer).shown=nil; ((TestLayer *)host.layer).shown=nil;
    LMVDesktopApplyDockMask(host,state,lower,snapshot); assert(state.layer.mask==owned);
    LMVDesktopApplyDockMask(host,state,normal,snapshot); assert(!state.layer.mask && visibleAt(state,CGPointMake(195,770)));
    assert(CGRectEqualToRect(dock.layer.frame,originalFrame) && CATransform3DEqualToTransform(dock.layer.transform,originalTransform));
    assert(dock.windowLevel==-3 && !dock.hidden && dock.alpha==1 && platter.layer.mask==nil);
    assert(state.desktopDockMask==owned && [state.layer.contents isEqual:@"cached-real-frame"]);
    puts("PASS: production bounded Dock discovery/path/mask with real CALayers; full-window/unknown/icon/offscreen/wrong-screen/hidden/alpha/level reject; actual round corners/shape path/window bridge/presentation; 500 layouts one identical owned mask, cached frame and system attributes retained (NOT device test)");
} return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'dock.m'; binary=Path(tmp)/'dock'
    preamble=preamble.replace('#include <assert.h>','#include <assert.h>\n#import <objc/runtime.h>\n@compatibility_alias UIResponder NSObject;')
    src.write_text(preamble+geometry+tests)
    subprocess.run(['clang','-fobjc-arc','-I',str(r),'-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
