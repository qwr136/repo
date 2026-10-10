#!/usr/bin/env python3
"""Run the production CC material manager and typed lifecycle/progress hooks."""
from pathlib import Path
import ast,platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LMVControlCenterVideo.h').read_text();s=(r/'Tweak.xm').read_text()
assert '#import "LMVControlCenterVideo.h"' in s and 'LMVCCRefresh(reload)' in s
assert 'ControlCenterDarkVideo' in h and 'ControlCenterLightVideo' in h
assert 'MTMaterialView' in h and 'LMVCCHookMatches' in h
assert 'LMVCacheFrame' not in h and 'LMVAcquireOriginal' not in h
if platform.system()!='Darwin':
 print('PASS: CC dark/light and typed hook integration; native QuartzCore manager/IMP tests run on macOS CI')
 raise SystemExit(0)
# Use the same UIKit input doubles as existing lock tests. All behavior under
# test below comes directly from the production CC header.
tree=ast.parse((r/'tests/lock-video-host.py').read_text());pre=''
for node in tree.body:
 if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='pre' for t in node.targets):pre=ast.literal_eval(node.value)
 elif isinstance(node,ast.AugAssign) and isinstance(node.target,ast.Name) and node.target.id=='pre':pre+=ast.literal_eval(node.value)
pre=pre.replace('@class UIWindow;', '''typedef NS_ENUM(NSInteger, UIUserInterfaceStyle) { UIUserInterfaceStyleUnspecified=0,UIUserInterfaceStyleLight=1,UIUserInterfaceStyleDark=2 };
@interface UITraitCollection:NSObject
@property UIUserInterfaceStyle userInterfaceStyle;
@end
@implementation UITraitCollection @end
@class UIWindow;''')
pre=pre.replace('@interface UIScreen:NSObject\n', '@interface UIScreen:NSObject\n@property(strong) UITraitCollection *traitCollection;\n')
pre=pre.replace('@property(nonatomic) NSUInteger autoresizingMask;', '@property(nonatomic) NSUInteger autoresizingMask;\n@property(nonatomic,strong) NSArray *gestureRecognizers;')
pre=pre.replace('- (BOOL)isDescendantOfView:(UIView *)view;', '- (BOOL)isDescendantOfView:(UIView *)view;\n- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;')
pre=pre.replace('- (UIWindow *)window {return self.superview.window;}', '- (UIWindow *)window {return self.superview.window;}\n- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {return [self.layer convertRect:rect toLayer:view.layer];}')
pre=pre.replace('@interface UIViewController:NSObject\n','@interface UIViewController:NSObject\n@property(strong) UITraitCollection *traitCollection;\n- (void)viewWillDisappear:(BOOL)animated;\n- (void)traitCollectionDidChange:(UITraitCollection *)previous;\n')
pre=pre.replace('- (void)viewDidDisappear:(BOOL)animated {self.disappearances++;}', '- (void)viewDidDisappear:(BOOL)animated {self.disappearances++;}\n- (void)viewWillDisappear:(BOOL)animated {self.disappearances++;}\n- (void)traitCollectionDidChange:(UITraitCollection *)previous {self.layouts++;}')
pre=pre.replace('@interface UIWindow:UIView\n', '@class UIWindowScene;\n@interface UIWindow:UIView\n@property(strong) UIWindowScene *windowScene;\n')
pre=pre.replace('@interface UIWindowScene:UIScene\n', '@interface UIWindowScene:UIScene\n@property(strong) UITraitCollection *traitCollection;\n')
pre=pre.replace('static int LMVBlankToken=1;','static int LMVBlankToken=1;')
pre=pre.replace('@property NSUInteger builds,clears;', '@property NSUInteger builds,clears;\n@property BOOL persistentPosterEnabled;')
pre=pre.replace('self.wantsPlayback=visible;', 'self.wantsPlayback=visible;self.renderLayer.hidden=!visible || self.error!=nil || !self.posterLayer.contents;')
pre+=r'''
@interface MTMaterialView:UIView @end
@implementation MTMaterialView @end
@interface CCUIModularControlCenterOverlayViewController:UIViewController
@property NSUInteger progressCalls;
@property double lastProgress;
@property BOOL lastInteractive;
- (void)setTransitionProgress:(double)progress;
- (void)setTransitionProgress:(double)progress interactive:(BOOL)interactive;
- (void)_setTransitionProgress:(double)progress interactive:(BOOL)interactive;
@end
@implementation CCUIModularControlCenterOverlayViewController
- (void)setTransitionProgress:(double)p {self.progressCalls++;self.lastProgress=p;}
- (void)setTransitionProgress:(double)p interactive:(BOOL)i {self.progressCalls++;self.lastProgress=p;self.lastInteractive=i;}
- (void)_setTransitionProgress:(double)p interactive:(BOOL)i {self.progressCalls++;self.lastProgress=p;self.lastInteractive=i;}
@end
@interface SBControlCenterController:NSObject
@property NSUInteger calls;
@property double lastProgress;
@property id lastOverlay;
- (void)controlCenterViewController:(id)controller significantPresentationProgressChange:(double)progress;
@end
@implementation SBControlCenterController
- (void)controlCenterViewController:(id)c significantPresentationProgressChange:(double)p {self.calls++;self.lastProgress=p;self.lastOverlay=c;}
@end
'''
lock=(r/'LMVLockVideo.h').read_text()
helpers=lock[lock.index('static BOOL LMVLockVideoRectValid'):lock.index('@interface LMVLockVideoHost')]
preAfter=r'''
static BOOL LMVLockVideoScreenAllowed(void){return !screenBlank;}
static BOOL LMVDesktopGeometryVisible(UIView *view){return view.window && !view.window.hidden && !view.hidden && view.alpha>.01 && !CGRectIsEmpty(LMVLockVideoVisibleRect(view,view.window));}
static void turn(void){[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];}
'''
main=r'''
int main(void){@autoreleasepool {
 LMVInitialized=YES;LMVLaunchReady=YES;
 UIScreen.mainScreen.traitCollection=[UITraitCollection new];UIScreen.mainScreen.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;
 UIWindow *window=[UIWindow new];UIView *root=[UIView new];[window addSubview:root];
 MTMaterialView *background=[MTMaterialView new];UIControl *button=[UIControl new];[root addSubview:background];[root addSubview:button];
 CALayer *systemLayer=[CALayer layer];[background.layer addSublayer:systemLayer];NSArray *systemTree=background.layer.sublayers.copy;
 CCUIModularControlCenterOverlayViewController *cc=[CCUIModularControlCenterOverlayViewController new];cc.viewIfLoaded=root;cc.traitCollection=[UITraitCollection new];cc.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;window.rootViewController=cc;
 LMVCCControllers=[NSHashTable weakObjectsHashTable];LMVCCLifecycle(cc,1);
 LMVControlCenterVideoManager *manager=[LMVControlCenterVideoManager new];manager.enabled=YES;manager.darkPath=@"dark.mov";manager.lightPath=@"light.mov";
 [manager update];assert([manager.path isEqual:@"dark.mov"] && manager.playback.wantsPlayback && manager.playback.renderLayer.superlayer==background.layer);
 assert(root.subviews.lastObject==button && button.layer.superlayer==root.layer && background.superview==root && background.layer.superlayer==root.layer);
 for(CALayer *layer in systemTree)assert(layer.superlayer==background.layer);
 NSUInteger built=manager.playback.builds;for(int n=0;n<100;n++)[manager update];assert(manager.playback.builds==built);
 UIScreen.mainScreen.traitCollection.userInterfaceStyle=UIUserInterfaceStyleLight;[manager update];assert([manager.path isEqual:@"light.mov"] && manager.playback.builds==built+1);
 // System light must win over CC's locally forced dark control trait.
 assert(LMVCCStyle(cc)==UIUserInterfaceStyleLight);
 manager.lightPath=nil;[manager update];assert(!manager.playback.wantsPlayback && !manager.playback.renderLayer.superlayer && !manager.path);
 manager.lightPath=@"new-light.mov";[manager update];assert([manager.path isEqual:@"new-light.mov"] && manager.playback.wantsPlayback);
 // Unrelated material mixed with UI controls must not be a background candidate.
 [background addSubview:[UIControl new]];[manager update];assert(!manager.playback.renderLayer.superlayer && !manager.playback.wantsPlayback);
 [background.subviews.lastObject removeFromSuperview];[manager update];assert(manager.playback.wantsPlayback);
 // Ignore tile-sized MTMaterialView even if it appears before full background.
 MTMaterialView *tile=[[MTMaterialView alloc] initWithFrame:CGRectMake(0,0,80,80)];[root addSubview:tile];assert(LMVCCMaterial(root)==background);
 // Positive progress cancels a queued zero close; full close hides and pauses.
 LMVCCProgress(cc,0);LMVCCProgress(cc,.25);turn();[manager update];assert(manager.playback.wantsPlayback);
 LMVCCProgress(cc,0);turn();[manager update];assert(!manager.playback.wantsPlayback && !manager.timer);
 LMVCCLifecycle(cc,1);[manager update];assert(manager.playback.wantsPlayback);LMVCCLifecycle(cc,2);
 LMVCCLifecycle(cc,3);[manager update];assert(manager.playback.wantsPlayback);LMVCCLifecycle(cc,0);[manager update];assert(!manager.playback.wantsPlayback && !manager.playback.renderLayer.superlayer);
 LMVCCLifecycle(cc,1);screenBlank=1;[manager update];assert(!manager.playback.wantsPlayback);screenBlank=0;[manager update];assert(manager.playback.wantsPlayback);
 manager.enabled=NO;[manager update];assert(!manager.playback.renderLayer.superlayer && !manager.playback.wantsPlayback);manager.enabled=YES;
 // Actual runtime hooks forward original args once; double/BOOL ABI checked.
 const char *types[]={@encode(double),@encode(BOOL)};assert(LMVCCHookMatches(cc.class,@selector(setTransitionProgress:interactive:),types,2));
 const char *wrong[]={@encode(float),@encode(BOOL)};assert(!LMVCCHookMatches(cc.class,@selector(setTransitionProgress:interactive:),wrong,2));
 LMVCCInstallHooks();[cc viewDidLoad];[cc viewWillAppear:YES];[cc viewDidAppear:YES];
 [cc setTransitionProgress:.37];[cc setTransitionProgress:.5 interactive:YES];[cc _setTransitionProgress:.7 interactive:NO];
 assert(cc.loads==1 && cc.appearances==2 && cc.progressCalls==3 && fabs(cc.lastProgress-.7)<.00001 && !cc.lastInteractive);
 SBControlCenterController *owner=[SBControlCenterController new];[owner controlCenterViewController:cc significantPresentationProgressChange:.6];assert(owner.calls==1 && owner.lastOverlay==cc && fabs(owner.lastProgress-.6)<.00001);
 [cc traitCollectionDidChange:nil];[cc viewWillDisappear:NO];[cc viewDidDisappear:NO];assert(cc.layouts==1 && cc.disappearances==2);
 [manager update];assert(!manager.playback.wantsPlayback);[manager suspend];
 puts("PASS: actual CC production manager/typed hooks with QuartzCore: dark/light independent paths and screen-style priority, no-selection restore, full-background material only, original backing/button tree intact, same-path stability, cancelled/complete zero progress, disappear/blank/disable pause, double/BOOL argument forwarding once; AVFoundation separately real, not device compositing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'cc.m';binary=Path(tmp)/'cc';source.write_text(pre+helpers+preAfter+h+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
