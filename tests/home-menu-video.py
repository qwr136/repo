#!/usr/bin/env python3
"""Actual HomeMenu production manager/hooks; real QuartzCore + UIKit doubles.
Linux runs source contracts only; macOS executes native assertions (no model).
"""
from pathlib import Path
import ast, os, platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LMVHomeMenuVideo.h').read_text()
p=(r/'LMVLockVideoPlayback.h').read_text()
for key in ('HomeMenuBackgroundEnabled','HomeMenuVideo','LMVHomeMenuVideoRefresh','LMVHomeMenuVideoSuspend','LMVHomeMenuVideoInstallHooks'):
    assert key in h
assert 'EasterEnabled' not in h[h.index('#import <stdbool.h>'):]
assert '[LMVLockVideoPlayback new]' in h and '_playback.persistentPosterEnabled=NO' in h
assert 'AVMediaTypeVideo' in p and 'live.player.muted=YES;live.player.volume=0' in p
for forbidden in ('LMVCacheFrame','LMVAcquireOriginal','LMVRequestSafeUpdate','connectedScenes','sharedInstance','LMVLockVideoRefresh(','LMVCCVideoRefresh('):
    assert forbidden not in h, forbidden
assert 'LMVHomeMenuSpringBoard() && LMVDesktopForeground()==1' in h
assert 'sourcePreview' in h and 'SBIconView' in h and 'record.known' in h and 'record.active' in h
assert '@encode(bool)' in h and 'method_copyArgumentType' in h
assert 'material.layer.opacity=0' in h and '[self.lease restore]' in h
assert 'materialAlpha=lease.applied' in h
assert 'playerLayer.readyForDisplay' in h and 'self.playback.posterLayer.hidden=YES' in h
assert 'self.host.layer.transform=material.layer.transform' in h
assert 'if(!CGRectEqualToRect(self.playback.renderLayer.frame,self.host.bounds))' in h
assert 'now-LMVHomeMenuVideo.lastAudit>=.25' in h
assert '[material.layer removeFromSuperlayer]' not in h
# 1.35: the desktop channel now concedes the dock strip only while a menu is up, and
# it needs the menu's own edges to re-measure on - layoutSubviews as the menu
# appears, didMoveToWindow as it leaves. Lock both wiring points, and that the flag
# is edge-only (a plain property read, so repeated layouts cost nothing).
assert 'static void LMVHomeMenuTellDesktop(BOOL up) {' in h, 'the desktop edge notification exists'
assert 'if(LMVHomeMenuDesktopToldUp==up)return;' in h, 'the notification is edge-only'
assert 'if(((UIView *)object).window)LMVHomeMenuTellDesktop(YES);' in h, 'the appear edge is wired'
assert 'LMVHomeMenuTellDesktop(((UIView *)object).window!=nil);' in h, 'the leave edge is wired'
if platform.system()!='Darwin' and not os.environ.get('LMV_NATIVE_EXPORT_DIR'):
    print('PASS: HomeMenu source contracts; SKIP native QuartzCore (requires macOS, not device validation)')
    raise SystemExit(0)
# Extract only doubles from existing Lock native tests, not its test logic.
tree=ast.parse((r/'tests/lock-video-host.py').read_text());pre=''
for node in tree.body:
    if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='pre' for t in node.targets):pre=ast.literal_eval(node.value)
    elif isinstance(node,ast.AugAssign) and isinstance(node.target,ast.Name) and node.target.id=='pre':pre+=ast.literal_eval(node.value)
assert pre
pre=pre.replace('- (BOOL)isDescendantOfView:(UIView *)view;', '- (BOOL)isDescendantOfView:(UIView *)view;\n- (void)didMoveToWindow;\n- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;')
pre=pre.replace('- (void)layoutSubviews {}', '- (void)layoutSubviews {}\n- (void)didMoveToWindow {}\n- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {return [self.layer convertRect:rect toLayer:view.layer];}')
pre=pre.replace('@interface UIApplication:NSObject\n', '@interface UIApplication:NSObject\n@property(nonatomic,strong) id frontmost;\n- (id)_frontmostApplication;\n')
pre=pre.replace('@implementation UIApplication\n', '@implementation UIApplication\n- (id)_frontmostApplication {return self.frontmost;}\n')
pre=pre.replace('@property NSUInteger builds,clears;', '@property NSUInteger builds,clears,layoutCalls,visibleCalls;\n@property BOOL persistentPosterEnabled;')
pre=pre.replace('self.path=path;self.revision=revision;}', 'self.path=path;self.revision=revision;self.player=[TestPlayer new];self.playerLayer.readyForDisplay=YES;}')
pre=pre.replace('- (void)setVisible:(BOOL)visible {self.wantsPlayback=visible;}', '- (void)setVisible:(BOOL)visible {self.visibleCalls++;self.wantsPlayback=visible;self.renderLayer.hidden=!visible || !self.playerLayer.readyForDisplay;}')
pre=pre.replace('- (void)layoutInBounds:(CGRect)bounds {self.renderLayer.frame=bounds;}', '- (void)layoutInBounds:(CGRect)bounds {self.layoutCalls++;self.renderLayer.frame=bounds;}')
pre=pre.replace('static int LMVBlankToken=1;', 'static int LMVBlankToken=1,LMVLockToken=2;')
pre=pre.replace('static uint64_t screenBlank=0;', 'static uint64_t screenBlank=0,screenLocked=0;')
pre=pre.replace('*state=screenBlank;return 0;', '*state=token==LMVLockToken?screenLocked:screenBlank;return 0;')
pre+=r'''
#import <stdbool.h>
@interface UIVisualEffectView:UIView @end
@implementation UIVisualEffectView @end
@interface UIImageView:UIView @end
@implementation UIImageView @end
@interface UICollectionView:UIScrollView @end
@implementation UICollectionView @end
@interface UITargetedPreview:NSObject
@property(nonatomic,strong) UIView *view;
@end
@implementation UITargetedPreview @end
@interface UIPresentationController:NSObject @end
@implementation UIPresentationController @end
@interface SBHomeScreenWindow:UIWindow @end
@implementation SBHomeScreenWindow @end
@interface SBIconView:UIView @end
@implementation SBIconView @end
@interface TestApplication:NSObject
@property(nonatomic,copy) NSString *bundleIdentifier;
@end
@implementation TestApplication @end
@interface _UIContextMenuListView:UIView
@property(nonatomic,strong) UIVisualEffectView *backgroundView;
@property(nonatomic,strong) UIView *clippingView;
@property(nonatomic,strong) UICollectionView *collectionView;
@property NSUInteger originalLayouts;
@end
@implementation _UIContextMenuListView
- (void)layoutSubviews {self.originalLayouts++;}
@end
@interface _UIContextMenuView:UIView
@property(nonatomic,strong) _UIContextMenuListView *currentListView;
@end
@implementation _UIContextMenuView @end
@interface _UIContextMenuPresentationController:UIPresentationController
@property(nonatomic,strong) UITargetedPreview *sourcePreview;
@property(nonatomic,strong) _UIContextMenuView *menuView;
@property NSUInteger begins,ends,dismisses;
@property bool completed;
- (void)presentationTransitionWillBegin;
- (void)presentationTransitionDidEnd:(bool)completed;
- (void)dismissalTransitionWillBegin;
@end
@implementation _UIContextMenuPresentationController
- (void)presentationTransitionWillBegin {self.begins++;}
- (void)presentationTransitionDidEnd:(bool)completed {self.ends++;self.completed=completed;}
- (void)dismissalTransitionWillBegin {self.dismisses++;}
@end
@interface WrongABI:NSObject
- (id)layoutSubviews;
- (void)presentationTransitionDidEnd:(int)completed;
@end
@implementation WrongABI
- (id)layoutSubviews {return nil;}
- (void)presentationTransitionDidEnd:(int)completed {}
@end
static NSDictionary *testPrefs;
static CFPropertyListRef testPreference(CFStringRef key,CFStringRef domain) {assert(domain==kLMVPrefsID);return CFBridgingRetain(testPrefs[(__bridge NSString *)key]);}
#define CFPreferencesCopyAppValue testPreference
static NSString *testBundle=@"com.apple.springboard";
static id bundleGetter(id object,SEL selector) {return testBundle;}
static void turn(void) {[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];}
'''
# Actual production implementations of the small shared contracts.
lock=(r/'LMVLockVideo.h').read_text()
rect=lock[lock.index('static BOOL LMVLockVideoRectValid'):lock.index('static UIView *LMVLockVideoObjectView')]
desktop=(r/'LMVDesktopVideo.h').read_text()
getters=desktop[desktop.index('static BOOL LMVDesktopObjectGetter'):desktop.index('static BOOL LMVDesktopWallpaperClass')]
home=desktop[desktop.index('static BOOL LMVDesktopHomeWindow'):desktop.index('static BOOL LMVDesktopGeometryVisible')]
foreground=desktop[desktop.index('static NSInteger LMVDesktopForeground'):desktop.index('@interface LMVDesktopControllerRecord')]
cc=(r/'LMVControlCenterVideo.h').read_text()
path=cc[cc.index('static NSString *LMVCCSelectedPath'):cc.index('static UIUserInterfaceStyle LMVCCStyle')]

main=r'''
static void preserve(UIView *view){for(UIView *child in view.subviews)assert(child.superview==view && child.layer.superlayer==view.layer && child.layer.delegate==child);}
int main(void){@autoreleasepool{
 Method bundleMethod=class_getInstanceMethod(NSBundle.class,@selector(bundleIdentifier));IMP originalBundle=method_getImplementation(bundleMethod);method_setImplementation(bundleMethod,(IMP)bundleGetter);
 LMVInitialized=YES;LMVLaunchReady=YES;screenBlank=0;screenLocked=0;
 TestApplication *homeApp=[TestApplication new];homeApp.bundleIdentifier=@"com.apple.springboard";UIApplication.sharedApplication.frontmost=homeApp;
 testPrefs=@{@"HomeMenuBackgroundEnabled":@YES,@"HomeMenuVideo":@"library/menu.mov"};
 SBHomeScreenWindow *homeWindow=[SBHomeScreenWindow new];SBIconView *icon=[SBIconView new];[homeWindow addSubview:icon];
 UITargetedPreview *preview=[UITargetedPreview new];preview.view=icon;
 UIWindow *menuWindow=[UIWindow new];_UIContextMenuView *menu=[_UIContextMenuView new];[menuWindow addSubview:menu];
 _UIContextMenuListView *list=[_UIContextMenuListView new];[menu addSubview:list];menu.currentListView=list;
 UIView *clip=[UIView new];[list addSubview:clip];list.clippingView=clip;
 UIVisualEffectView *material=[UIVisualEffectView new];UICollectionView *collection=[UICollectionView new];[clip addSubview:material];[clip addSubview:collection];
 list.backgroundView=material;list.collectionView=collection;material.layer.opacity=.67;material.layer.cornerRadius=16;
 UILabel *title=[UILabel new];[collection addSubview:title];
 _UIContextMenuPresentationController *presentation=[_UIContextMenuPresentationController new];presentation.sourcePreview=preview;presentation.menuView=menu;
 LMVHomeMenuVideoInstallHooks();
 assert(LMVHomeMenuHookMatches(_UIContextMenuListView.class,@selector(layoutSubviews),NO));
 assert(!LMVHomeMenuHookMatches(WrongABI.class,@selector(layoutSubviews),NO));
 assert(!LMVHomeMenuHookMatches(WrongABI.class,@selector(presentationTransitionDidEnd:),YES));
 // Preferences/launch alone do not create a UI or playback chain.
 LMVHomeMenuVideoRefresh(YES);assert(!LMVHomeMenuVideo);
 [presentation presentationTransitionWillBegin];turn();
 assert(presentation.begins==1 && LMVHomeMenuVideo && LMVHomeMenuVideo.host.superview==clip && material.layer.opacity==0);
 assert(!title.hidden && collection.layer.superlayer==clip.layer && material.layer.superlayer==clip.layer);
 assert(LMVHomeMenuVideo.playback.posterLayer.hidden && LMVHomeMenuVideo.playback.wantsPlayback);
 LMVLockVideoPlayback *playback=LMVHomeMenuVideo.playback;UIView *host=LMVHomeMenuVideo.host;
 NSUInteger builds=playback.builds,layouts=playback.layoutCalls,visible=playback.visibleCalls;
 for(int n=0;n<500;n++){[LMVHomeMenuVideo updateList:list];[list layoutSubviews];preserve(clip);preserve(collection);}
 assert(LMVHomeMenuVideo.playback==playback && playback.builds==builds && playback.layoutCalls==layouts && playback.visibleCalls==visible);
 assert(list.originalLayouts==500 && !title.hidden && material.layer.opacity==0 && host.superview==clip);
 // Match transforms/bounds/position in the same sibling coordinate system.
 material.layer.bounds=CGRectMake(17,21,320,300);material.layer.position=CGPointMake(160,170);material.layer.transform=CATransform3DMakeScale(.9,.9,1);
 [list layoutSubviews];assert(CGRectEqualToRect(host.layer.bounds,material.layer.bounds) && CATransform3DEqualToTransform(host.layer.transform,material.layer.transform));
 // Re-draw baseline is maintained, not overwritten with a stale original value.
 material.layer.opacity=.51;[LMVHomeMenuVideo updateList:list];assert(material.layer.opacity==0);
 [presentation dismissalTransitionWillBegin];assert(presentation.dismisses==1 && !host.superview && fabs(material.layer.opacity-.51)<.0001);
 [presentation presentationTransitionWillBegin];turn();[presentation presentationTransitionDidEnd:false];assert(!host.superview && presentation.ends==1 && !presentation.completed);
 [presentation presentationTransitionWillBegin];turn();[presentation presentationTransitionDidEnd:true];assert(host.superview==clip && presentation.ends==2 && presentation.completed);
 // Same SpringBoard process can present other content: exact Home icon source,
 // physical unlocked Home and active context-menu record are all required.
 homeApp.bundleIdentifier=@"com.apple.mobilesafari";LMVHomeMenuVideoRefresh(NO);assert(!host.superview && material.layer.opacity>0);
 homeApp.bundleIdentifier=@"com.apple.springboard";screenLocked=1;LMVHomeMenuVideoRefresh(NO);assert(!host.superview);screenLocked=0;
 screenBlank=1;LMVHomeMenuVideoRefresh(NO);assert(!host.superview);screenBlank=0;
 preview.view=title;LMVHomeMenuVideoRefresh(NO);assert(!host.superview);preview.view=icon;
 testBundle=@"com.example.other";LMVHomeMenuVideoRefresh(NO);assert(!host.superview);testBundle=@"com.apple.springboard";
 // A foreground-bearing background must never be suppressed with the menu.
 UILabel *unsafe=[UILabel new];[material addSubview:unsafe];LMVHomeMenuVideoRefresh(NO);assert(!host.superview && material.layer.opacity>0 && !unsafe.hidden);[unsafe removeFromSuperview];
 [presentation presentationTransitionWillBegin];turn();assert(host.superview==clip);
 testPrefs=@{@"HomeMenuBackgroundEnabled":@NO,@"HomeMenuVideo":@"library/menu.mov"};LMVHomeMenuVideoRefresh(YES);assert(!host.superview && !playback.path && material.layer.opacity>0);
 testPrefs=@{@"HomeMenuBackgroundEnabled":@YES,@"HomeMenuVideo":@"../escape.mov"};LMVHomeMenuVideoRefresh(YES);assert(!host.superview && !LMVHomeMenuPath);
 testPrefs=@{@"HomeMenuBackgroundEnabled":@YES,@"HomeMenuVideo":@"library/replacement.mov"};LMVHomeMenuVideoRefresh(YES);assert(host.superview==clip && [playback.path hasSuffix:@"replacement.mov"]);
 [list removeFromSuperview];[list didMoveToWindow];assert(!host.superview && material.layer.opacity>0);
 LMVHomeMenuVideoSuspend();assert(!LMVHomeMenuObservedList);
 method_setImplementation(bundleMethod,originalBundle);
 puts("PASS production HomeMenu: exact unlocked Home icon preview and active menu record, one independent live chain,500 stable layouts,real CA sibling transform/rounding,baseline redraw/close/cancel/reuse/disable/path/screen/App/foreign/unsafe rejection and typed original forwarding; no iOS device claim");
}return 0;}
'''
# Reuse the existing controlled revision input from the Lock test doubles.

source=pre+rect+getters+home+foreground+path+h+main
if os.environ.get('LMV_NATIVE_EXPORT_DIR'):
    out=Path(os.environ['LMV_NATIVE_EXPORT_DIR']);out.mkdir(parents=True,exist_ok=True)
    (out/'home-menu-video.m').write_text(source)
    print('EXPORTED production HomeMenu native fixture')
    raise SystemExit(0)
with tempfile.TemporaryDirectory(prefix='lmv-home-menu-') as tmp:
    src=Path(tmp)/'menu.m';out=Path(tmp)/'menu';src.write_text(source)
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(src),'-o',str(out)],check=True)
    subprocess.run([str(out)],check=True,timeout=45)
