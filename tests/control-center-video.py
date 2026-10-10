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
pre=pre.replace('- (void)viewDidDisappear:(BOOL)animated {self.disappearances++;}', '- (void)viewDidDisappear:(BOOL)animated {self.disappearances++;}\n- (void)viewWillDisappear:(BOOL)animated {self.disappearances++;}\n- (void)traitCollectionDidChange:(UITraitCollection *)previous {self.layouts++;}\n- (UIView *)view {return self.viewIfLoaded;}')
pre=pre.replace('@interface UIWindow:UIView\n', '@class UIWindowScene;\n@interface UIWindow:UIView\n@property(strong) UITraitCollection *traitCollection;\n@property(strong) UIWindowScene *windowScene;\n')
pre=pre.replace('@interface UIWindowScene:UIScene\n', '@interface UIWindowScene:UIScene\n@property(strong) UITraitCollection *traitCollection;\n')
# The CC discovery path walks view.nextResponder when the controller chain does not
# expose the overlay, and the fallback reads window.rootViewController.view.
pre=pre.replace('@property(nonatomic,weak) UIView *superview;', '@property(nonatomic,weak) UIView *superview;\n@property(nonatomic,weak) NSObject *nextResponder;')
# UIViewController.view is a separate accessor from viewIfLoaded in the fallback
# discovery path, so the double must expose both.
pre=pre.replace('@property(nonatomic,strong) UIView *viewIfLoaded;\n@property(nonatomic,strong) NSArray *childViewControllers;',
                '@property(nonatomic,strong) UIView *viewIfLoaded;\n- (UIView *)view;\n@property(nonatomic,strong) NSArray *childViewControllers;')
pre=pre.replace('static int LMVBlankToken=1;','static int LMVBlankToken=1;')
pre=pre.replace('@property NSUInteger builds,clears;', '@property NSUInteger builds,clears,posterPrepareCalls,posterPathReads;\n@property BOOL persistentPosterEnabled;\n@property(strong) NSString *posterPreparedPath,*posterPreparedRevision;')
pre=pre.replace('- (void)clear;', '''- (void)clear;
- (void)updatePresentation;
- (void)preparePosterForPath:(NSString *)path revision:(NSString *)revision;
- (void)loadCachedPosterNowForPath:(NSString *)path revision:(NSString *)revision;
+ (CGImageRef)sharedPosterImage;''')
# 0.0.79: the double must model the real poster contract, because "poster prepared
# before selectPath" is one of the fixes under test. With a persistent poster
# enabled and a path selected, a poster frame exists from that moment on, so
# renderLayer is allowed to become visible even before the player is ready.
# NOTE: this replacement must run BEFORE any other edit touches setVisible:, so the
# anchor below still matches the untouched base implementation.
pre=pre.replace('- (void)setVisible:(BOOL)visible {self.wantsPlayback=visible;}',
 '''- (void)setVisible:(BOOL)visible {self.wantsPlayback=visible;[self updatePresentation];}
- (void)updatePresentation {BOOL ready=self.player!=nil && self.posterLayer.contents!=nil;self.renderLayer.hidden=!self.wantsPlayback || self.error!=nil || (!ready && !self.posterLayer.contents);}''')
pre=pre.replace('- (void)selectPath:(NSString *)path revision:(NSString *)revision {if(![self.path isEqual:path] || ![self.revision isEqual:revision])self.builds++;self.path=path;self.revision=revision;}',
 '''- (void)selectPath:(NSString *)path revision:(NSString *)revision {if(![self.path isEqual:path] || ![self.revision isEqual:revision])self.builds++;self.path=path;self.revision=revision;[self updatePresentation];}
- (void)preparePosterForPath:(NSString *)path revision:(NSString *)revision {
 if(!self.persistentPosterEnabled || !path.length || !revision.length)return;
 self.posterPrepareCalls++;
 // Faithful to the real implementation: it early-returns when the prepared
 // path/revision already match, which is exactly why the manager cannot rely on
 // this call alone for a reopen.
 if([self.posterPreparedPath isEqualToString:path] && [self.posterPreparedRevision isEqualToString:revision] && self.posterLayer.contents!=nil)return;
 self.posterPreparedPath=path;self.posterPreparedRevision=revision;
 // A real poster produces layer contents, which is what lets renderLayer show.
 self.posterLayer.contents=(__bridge id)[LMVLockVideoPlayback sharedPosterImage];
 [self updatePresentation];
}
- (void)loadCachedPosterNowForPath:(NSString *)path revision:(NSString *)revision {
 // Synchronous cache read: no decoder, just re-seat the still frame. This is the
 // call the reopen path uses when the poster was dropped while closed.
 if(!self.persistentPosterEnabled || !path.length || !revision.length)return;
 self.posterPathReads++;
 if(self.posterLayer.contents!=nil)return;
 self.posterPreparedPath=path;self.posterPreparedRevision=revision;
 self.posterLayer.contents=(__bridge id)[LMVLockVideoPlayback sharedPosterImage];
 [self updatePresentation];
}
+ (CGImageRef)sharedPosterImage {
 static CGImageRef image;
 if(!image){CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();unsigned char pixel[4]={0,0,0,255};
  CGContextRef ctx=CGBitmapContextCreate(pixel,1,1,8,4,space,kCGImageAlphaPremultipliedLast);
  if(ctx){image=CGBitmapContextCreateImage(ctx);CGContextRelease(ctx);}CGColorSpaceRelease(space);}
 return image;
}''')
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
 CALayer *systemLayer=[CALayer layer];[background.layer addSublayer:systemLayer];
 CCUIModularControlCenterOverlayViewController *cc=[CCUIModularControlCenterOverlayViewController new];cc.viewIfLoaded=root;cc.traitCollection=[UITraitCollection new];cc.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;window.rootViewController=cc;
 LMVCCControllers=[NSHashTable weakObjectsHashTable];LMVCCLifecycle(cc,1);
 LMVControlCenterVideoManager *manager=[LMVControlCenterVideoManager new];manager.enabled=YES;manager.darkPath=@"dark.mov";manager.lightPath=@"light.mov";
 [manager update];assert([manager.path isEqual:@"dark.mov"] && manager.playback.wantsPlayback && manager.playback.renderLayer.superlayer==background.layer);
 assert(root.subviews.lastObject==button && button.layer.superlayer==root.layer && background.superview==root && background.layer.superlayer==root.layer);
 assert(systemLayer.superlayer==background.layer);
 // The video layer must never become a sibling of Control Center content: it is
 // contained by the backdrop's own layer, so sibling order is untouched. Assert
 // the structural property via superlayer identity - the test links the real
 // QuartzCore (its sublayers array is private) and the mock UIView drives the
 // layer tree, so identity walking is the reliable check.
 assert(manager.playback.renderLayer.superlayer==background.layer);
 assert(manager.playback.renderLayer.superlayer!=root.layer);
 assert(manager.playback.renderLayer.superlayer!=button.layer);
 assert(background.layer.superlayer==root.layer);
 // 0.0.79: the poster must be prepared for the selected path, otherwise
 // renderLayer stays hidden and nothing is ever displayed.
 assert(manager.playback.posterPreparedPath!=nil && [manager.playback.posterPreparedPath isEqual:@"dark.mov"]);
 NSUInteger built=manager.playback.builds;for(int n=0;n<100;n++)[manager update];assert(manager.playback.builds==built);
 // 0.0.79: the controller/scene trait is authoritative. The screen trait is
 // deliberately left on Dark while the controller flips to Light; the video must
 // follow the controller, which is the value that actually changes on device.
 cc.traitCollection.userInterfaceStyle=UIUserInterfaceStyleLight;[manager update];assert([manager.path isEqual:@"light.mov"] && manager.playback.builds==built+1);
 assert(LMVCCStyle(cc)==UIUserInterfaceStyleLight);
 cc.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;[manager update];assert([manager.path isEqual:@"dark.mov"]);
 // A screen-only change must NOT outweigh the controller, because the screen
 // trait is exactly the stale value that pinned the light asset on device.
 UIScreen.mainScreen.traitCollection.userInterfaceStyle=UIUserInterfaceStyleLight;[manager update];assert([manager.path isEqual:@"dark.mov"]);
 cc.traitCollection.userInterfaceStyle=UIUserInterfaceStyleLight;[manager update];assert([manager.path isEqual:@"light.mov"]);
 manager.lightPath=nil;[manager update];assert(!manager.playback.wantsPlayback && !manager.playback.renderLayer.superlayer && !manager.path);
 manager.lightPath=@"new-light.mov";[manager update];assert([manager.path isEqual:@"new-light.mov"] && manager.playback.wantsPlayback);
 // A real UI control INSIDE the backdrop makes it interactive content, so it is
 // not a pure background and must be rejected.
 [background addSubview:[UIControl new]];[manager update];assert(!manager.playback.renderLayer.superlayer && !manager.playback.wantsPlayback);
 [background.subviews.lastObject removeFromSuperview];[manager update];assert(manager.playback.wantsPlayback);
 // The backdrop's own nested layer host and module-ish class names inside it are
 // NOT a reason to reject the material view: that false rejection is what made
 // the feature invisible.
 UIView *host=[[UIView alloc] init];[background addSubview:host];
 assert(LMVCCMaterial(root)==background);
 // Ignore tile-sized MTMaterialView even if it appears before full background.
 MTMaterialView *tile=[[MTMaterialView alloc] initWithFrame:CGRectMake(0,0,80,80)];[root addSubview:tile];assert(LMVCCMaterial(root)==background);
 // Positive progress cancels a queued zero close; full close hides and pauses.
 LMVCCProgress(cc,0);LMVCCProgress(cc,.25);turn();[manager update];assert(manager.playback.wantsPlayback);
 LMVCCProgress(cc,0);turn();[manager update];assert(!manager.playback.wantsPlayback);
 LMVCCLifecycle(cc,1);[manager update];assert(manager.playback.wantsPlayback);LMVCCLifecycle(cc,2);
 LMVCCLifecycle(cc,3);[manager update];assert(manager.playback.wantsPlayback);LMVCCLifecycle(cc,0);[manager update];assert(!manager.playback.wantsPlayback && !manager.playback.renderLayer.superlayer);
 LMVCCLifecycle(cc,1);screenBlank=1;[manager update];assert(!manager.playback.wantsPlayback);screenBlank=0;[manager update];assert(manager.playback.wantsPlayback);
 // 0.0.79 regression: "open once, close, reopen shows nothing". Same asset on
 // reopen means path/revision are UNCHANGED, so the change-gated block that used
 // to be the only poster seeder was skipped - and the close pass had dropped the
 // poster, leaving renderLayer.hidden=YES. The manager must re-seed the poster on
 // every hidden->visible transition.
 LMVCCLifecycle(cc,0);[manager update];assert(!manager.playback.wantsPlayback && !manager.presented);
 // Simulate the close pass dropping the poster frame (player paused + detached).
 manager.playback.posterLayer.contents=nil;
 NSUInteger reads=manager.playback.posterPathReads;
 LMVCCLifecycle(cc,1);[manager update];
 assert(manager.presented && manager.playback.wantsPlayback);
 assert(manager.playback.posterPathReads>reads);
 assert(manager.playback.posterLayer.contents!=nil);
 assert(!manager.playback.renderLayer.hidden);
 // The path must NOT have been rebuilt just because we reopened: same asset.
 NSUInteger built2=manager.playback.builds;
 LMVCCLifecycle(cc,0);[manager update];LMVCCLifecycle(cc,1);[manager update];
 assert(manager.playback.builds==built2);
 // The poll timer keeps running while enabled so a late poster/first frame can
 // always recover, and stops once the feature is off.
 assert(manager.timer!=nil);
 manager.enabled=NO;[manager update];assert(!manager.playback.renderLayer.superlayer && !manager.playback.wantsPlayback && manager.timer==nil);manager.enabled=YES;[manager update];assert(manager.timer!=nil);
 // Actual runtime hooks forward original args once; double/BOOL ABI checked.
 const char *types[]={@encode(double),@encode(BOOL)};assert(LMVCCHookMatches(cc.class,@selector(setTransitionProgress:interactive:),types,2));
 const char *wrong[]={@encode(float),@encode(BOOL)};assert(!LMVCCHookMatches(cc.class,@selector(setTransitionProgress:interactive:),wrong,2));
 LMVCCInstallHooks();[cc viewDidLoad];[cc viewWillAppear:YES];[cc viewDidAppear:YES];
 [cc setTransitionProgress:.37];[cc setTransitionProgress:.5 interactive:YES];[cc _setTransitionProgress:.7 interactive:NO];
 assert(cc.loads==1 && cc.appearances==2 && cc.progressCalls==3 && fabs(cc.lastProgress-.7)<.00001 && !cc.lastInteractive);
 SBControlCenterController *owner=[SBControlCenterController new];[owner controlCenterViewController:cc significantPresentationProgressChange:.6];assert(owner.calls==1 && owner.lastOverlay==cc && fabs(owner.lastProgress-.6)<.00001);
 [cc traitCollectionDidChange:nil];[cc viewWillDisappear:NO];[cc viewDidDisappear:NO];assert(cc.layouts==1 && cc.disappearances==2);
 [manager update];assert(!manager.playback.wantsPlayback);[manager suspend];
 puts("PASS: actual CC production manager/typed hooks with QuartzCore: dark/light independent paths with controller-trait priority over the stale screen trait, poster prepared before selection, video layer contained by the backdrop layer so sibling order is untouched, no-selection restore, full-background material only, nested layer host not falsely rejected, same-path stability, cancelled/complete zero progress, disappear/blank/disable pause, double/BOOL argument forwarding once; AVFoundation separately real, not device compositing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'cc.m';binary=Path(tmp)/'cc';source.write_text(pre+helpers+preAfter+h+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
