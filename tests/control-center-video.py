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
assert 'LMVVideoWindowViewport(window)' in h
assert 'rootClip.size.width>=bounds.size.width*.98' in h
assert 'clipped.size.height>=viewport.size.height*.98' in h
assert 'if(view==root)continue' not in h
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
pre=pre.replace('- (BOOL)isDescendantOfView:(UIView *)view;', '- (BOOL)isDescendantOfView:(UIView *)view;\n- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;\n- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view;')
pre=pre.replace('- (UIWindow *)window {return self.superview.window;}', '- (UIWindow *)window {return self.superview.window;}\n- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {return [self.layer convertRect:rect toLayer:view.layer];}\n- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view {return [self.layer convertRect:rect fromLayer:view.layer];}')
pre=pre.replace('@interface UIViewController:NSObject\n','@interface UIViewController:NSObject\n@property(strong) UITraitCollection *traitCollection;\n- (void)viewWillDisappear:(BOOL)animated;\n- (void)traitCollectionDidChange:(UITraitCollection *)previous;\n')
pre=pre.replace('- (void)viewDidDisappear:(BOOL)animated {self.disappearances++;}', '- (void)viewDidDisappear:(BOOL)animated {self.disappearances++;}\n- (void)viewWillDisappear:(BOOL)animated {self.disappearances++;}\n- (void)traitCollectionDidChange:(UITraitCollection *)previous {self.layouts++;}\n- (UIView *)view {return self.viewIfLoaded;}')
pre=pre.replace('@interface UIWindow:UIView\n', '@class UIWindowScene;\n@interface UIWindow:UIView\n@property(strong) UITraitCollection *traitCollection;\n@property(strong) UIWindowScene *windowScene;\n')
pre=pre.replace('@interface UIWindowScene:UIScene\n', '@interface UIWindowScene:UIScene\n@property(strong) UITraitCollection *traitCollection;\n')
# Inherit the shared screen/window doubles when present. Keep this test runnable
# during independent updates of the shared test input; no production API mock is
# allowed to affect the material/manager implementation under test.
if 'coordinateSpace' not in pre:
 pre=pre.replace('+ (instancetype)mainScreen;', '+ (instancetype)mainScreen;\n- (CGRect)bounds;\n- (id)coordinateSpace;')
 pre=pre.replace('@implementation UIScreen\n', '@implementation UIScreen\n- (CGRect)bounds {return CGRectMake(0,0,390,844);}\n- (id)coordinateSpace {return self;}\n')
if 'screenOffset' not in pre:
 pre=pre.replace('@interface UIWindow:UIView\n', '@interface UIWindow:UIView\n@property(nonatomic) CGPoint screenOffset;\n- (CGRect)convertRect:(CGRect)rect fromCoordinateSpace:(id)space;\n')
 pre=pre.replace('@implementation UIWindow\n', '@implementation UIWindow\n- (CGRect)convertRect:(CGRect)rect fromCoordinateSpace:(id)space {return CGRectOffset(rect,-self.screenOffset.x,-self.screenOffset.y);}\n')
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
@interface CCUIScrollView:UIScrollView @end
@implementation CCUIScrollView @end
@interface ModuleSliderButtonHeaderBacking:UIView @end
@implementation ModuleSliderButtonHeaderBacking @end
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
 TestPlayer *samePlayer=manager.playback.player;
 // Actual Reachability geometry: unchanged full-sized window, screen shifted by
 // 422 points, and a material whose actual height is only half the root height.
 window.screenOffset=CGPointMake(0,422);background.frame=CGRectMake(0,0,390,422);
 assert(CGRectEqualToRect(window.bounds,CGRectMake(0,0,390,844)));
 assert(CGRectEqualToRect(LMVCCVisibleViewport(root),CGRectMake(0,0,390,422)));
 assert(LMVCCMaterial(root)==background);[manager update];
 assert(manager.playback.wantsPlayback && manager.material==background && !manager.playback.renderLayer.hidden);
 assert(CGRectEqualToRect(background.bounds,CGRectMake(0,0,390,422)));
 assert(CGRectEqualToRect(manager.playback.renderLayer.frame,background.bounds));
 assert(manager.playback.renderLayer.superlayer==background.layer && manager.playback.builds==built && manager.playback.player==samePlayer);
 LMVCCRecord *halfRecord=objc_getAssociatedObject(cc,&LMVCCRecordKey);halfRecord.visible=NO;
 [manager update];assert(manager.playback.wantsPlayback && manager.playback.player==samePlayer);halfRecord.visible=YES;
 // A full-root material also covers the half viewport; leaving/re-entering
 // Reachability changes only layout, never the selected source or player.
 background.frame=CGRectMake(0,0,390,844);[manager update];assert(LMVCCMaterial(root)==background);
 window.screenOffset=CGPointZero;[manager update];assert(manager.playback.builds==built && manager.playback.player==samePlayer);
 // A translated root exposes the same half independently of window translation.
 root.frame=CGRectMake(0,422,390,844);background.frame=CGRectMake(0,0,390,422);
 assert(CGRectEqualToRect(LMVCCVisibleViewport(root),CGRectMake(0,0,390,422)));[manager update];
 assert(manager.playback.wantsPlayback && manager.playback.builds==built);
 root.frame=CGRectMake(0,0,390,844);window.screenOffset=CGPointMake(0,422);
 // Nonzero bounds origins must be preserved during root-local conversion.
 root.bounds=CGRectMake(17,31,390,844);background.frame=CGRectMake(17,31,390,422);
 assert(CGRectEqualToRect(LMVCCVisibleViewport(root),CGRectMake(17,31,390,422)));
 [manager update];assert(manager.playback.wantsPlayback && manager.playback.builds==built && manager.playback.player==samePlayer);
 root.bounds=CGRectMake(0,0,390,844);background.frame=CGRectMake(0,0,390,422);
 // A half-height material in a fully visible root is not a background match.
 window.screenOffset=CGPointZero;assert(LMVCCMaterial(root)==nil);
 window.screenOffset=CGPointMake(0,422);
 // Controller -> window -> scene -> screen style priority remains authoritative.
 window.traitCollection=[UITraitCollection new];window.windowScene=[UIWindowScene new];window.windowScene.traitCollection=[UITraitCollection new];
 cc.traitCollection.userInterfaceStyle=UIUserInterfaceStyleUnspecified;window.traitCollection.userInterfaceStyle=UIUserInterfaceStyleLight;
 window.windowScene.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;assert(LMVCCStyle(cc)==UIUserInterfaceStyleLight);
 window.traitCollection.userInterfaceStyle=UIUserInterfaceStyleUnspecified;assert(LMVCCStyle(cc)==UIUserInterfaceStyleDark);
 window.windowScene.traitCollection.userInterfaceStyle=UIUserInterfaceStyleUnspecified;assert(LMVCCStyle(cc)==UIUserInterfaceStyleDark);
 cc.traitCollection.userInterfaceStyle=UIUserInterfaceStyleDark;
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
 UIView *host=[[UIView alloc] init];[background addSubview:host];[host addSubview:[ModuleSliderButtonHeaderBacking new]];
 assert(LMVCCMaterial(root)==background);
 // Direct gesture/scroll furniture is still impure; nested backing names are OK.
 host.gestureRecognizers=@[[NSObject new]];assert(LMVCCMaterial(root)==nil);host.gestureRecognizers=nil;
 UIScrollView *impure=[UIScrollView new];[background addSubview:impure];assert(LMVCCMaterial(root)==nil);[impure removeFromSuperview];
 // Tile, unknown class, hidden material/root/window and narrow slivers never
 // become backgrounds merely because the viewport is now half-height.
 MTMaterialView *tile=[[MTMaterialView alloc] initWithFrame:CGRectMake(0,0,80,80)];
 [background removeFromSuperview];[root addSubview:tile];assert(LMVCCMaterial(root)==nil);
 UIView *unknown=[[UIView alloc] initWithFrame:CGRectMake(0,0,390,422)];[root addSubview:unknown];assert(LMVCCMaterial(root)==nil);[unknown removeFromSuperview];
 [tile removeFromSuperview];[root addSubview:background];[button removeFromSuperview];[root addSubview:button];
 background.hidden=YES;assert(LMVCCMaterial(root)==nil);background.hidden=NO;
 background.alpha=0;assert(LMVCCMaterial(root)==nil);background.alpha=1;
 root.hidden=YES;assert(LMVCCMaterial(root)==nil);root.hidden=NO;
 window.hidden=YES;assert(LMVCCMaterial(root)==nil);window.hidden=NO;
 background.frame=CGRectMake(0,0,380,422);assert(LMVCCMaterial(root)==nil);
 background.frame=CGRectMake(0,0,390,410);assert(LMVCCMaterial(root)==nil);
 background.frame=CGRectMake(0,0,390,422);
 window.screenOffset=CGPointMake(0,843);assert(LMVCCMaterial(root)==nil);window.screenOffset=CGPointMake(0,422);
 // When the observed content scroll is present, only materials before it may
 // qualify. The fallback must not rescue a foreground material after content.
 CCUIScrollView *scroll=[CCUIScrollView new];[root addSubview:scroll];assert(LMVCCMaterial(root)==background);
 [background removeFromSuperview];[root addSubview:background];assert(LMVCCMaterial(root)==nil);
 [scroll removeFromSuperview];assert(LMVCCMaterial(root)==background);
 // Deep fallback now really visits descendants; hidden/alpha-zero ancestors
 // and foreground branches are pruned before any material inside can qualify.
 UIWindow *deepWindow=[UIWindow new];UIView *deepRoot=[UIView new],*outer=[UIView new],*inner=[UIView new];
 [deepWindow addSubview:deepRoot];[deepRoot addSubview:outer];[outer addSubview:inner];
 MTMaterialView *deep=[MTMaterialView new];[inner addSubview:deep];
 assert(LMVCCMaterial(deepRoot)==deep);outer.hidden=YES;assert(LMVCCMaterial(deepRoot)==nil);outer.hidden=NO;
 outer.alpha=0;assert(LMVCCMaterial(deepRoot)==nil);outer.alpha=1;
 [deep addSubview:[UIControl new]];assert(LMVCCMaterial(deepRoot)==nil);[deep.subviews.lastObject removeFromSuperview];
 deep.frame=CGRectMake(0,0,80,80);assert(LMVCCMaterial(deepRoot)==nil);deep.frame=CGRectMake(0,0,390,844);
 UIScrollView *foreground=[UIScrollView new];[deepRoot addSubview:foreground];[foreground addSubview:deep];assert(LMVCCMaterial(deepRoot)==nil);
 [inner addSubview:deep];assert(LMVCCMaterial(deepRoot)==deep);
 // Restore full-screen geometry for ordinary close/lifecycle checks; half-screen
 // exposure was independently verified above and can override transient callbacks.
 window.screenOffset=CGPointZero;root.frame=CGRectMake(0,0,390,844);background.frame=CGRectMake(0,0,390,844);
 // A controller known only through layout remains an unknown presentation.
 LMVCCRecord *record=objc_getAssociatedObject(cc,&LMVCCRecordKey);record.known=NO;[manager update];assert(!manager.playback.wantsPlayback && !manager.playback.renderLayer.superlayer);
 LMVCCLifecycle(cc,1);[manager update];assert(manager.playback.wantsPlayback);
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
 puts("PASS: actual CC production manager/typed hooks with QuartzCore: half-height direct backdrop in a translated full-sized window, offset bounds origins, full-root covers, root-width/visible-height coverage, tiles/unknown/hidden/foreground rejected, content-scroll ordering, real deep fallback traversal, controller/window/scene/screen styles while half-screen, same player/source through geometry changes, poster seeding and nested layer containment, cancelled/complete zero progress, close/blank/disable pause and enabled timer, double/BOOL forwarding once; UIKit inputs mocked, device compositing not tested");
}return 0;}
'''
# Validate the assembled inputs on every platform, even where Apple frameworks
# cannot run. Runtime geometry assertions above are executed only by native CI.
assert '- (CGRect)convertRect:(CGRect)rect fromView:(UIView *)view' in pre
assert pre.count('@implementation UIScreen')==1 and pre.count('@implementation UIWindow\n')==1
assert 'screenOffset' in pre and 'coordinateSpace' in pre
assert 'static CGRect LMVVideoWindowViewport' in helpers
assert 'CGPointMake(0,422)' in main and '390,422' in main and '==deep' in main
if platform.system()!='Darwin':
 print('PASS: CC source integration, viewport/coverage/traversal contracts and native harness assembly')
 print('SKIP: native CC manager/QuartzCore geometry and typed IMP execution require macOS Apple frameworks; no device compositing claim')
 raise SystemExit(0)
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'cc.m';binary=Path(tmp)/'cc';source.write_text(pre+helpers+preAfter+h+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
