from pathlib import Path
import platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LMVNotificationWallpaper.h').read_text();s=(r/'Tweak.xm').read_text()
assert 'SBWallpaperEffectView' in h and 'SBCoverSheetPanelBackgroundContainerView' in h
assert 'PBUIWallpaperView' in h and 'LMVOriginalDetach' in h
assert 'surface.layer.frame=panel.bounds' in h and 'insertSublayer:surface.layer atIndex:0' in h
assert 'LMVSourceForTarget' not in h and 'independentLockSource=1' in h
assert 'LMVNotificationWallpaperVisible()' in s and 'LMVNotificationWallpaperPublish(source, image)' in s
assert 'CALayer *root=window.layer' not in h and 'Desktop' not in h
if platform.system()!='Darwin':
 print('PASS: sliding NC background scope and early-exposure gate; actual layer behavior tested in macOS CI')
 raise SystemExit(0)
# Same REAL QuartzCore, UIKit-free harness used by .68; add only the observed
# classes and geometry that the interactive pull uses.
ns={};text=(r/'tests/wallpaper-variants.py').read_text(); prefix=text.split('if platform.system()',1)[0]
# Load constant preamble construction without executing its main test.
a=text.index("pre=(r/'tests/original-background.m')");b=text.index("int main(void)",a)
# Directly reuse its pre/extra constants by parsing the script rather than running it.
import ast
module=ast.parse(text)
extra=next(ast.literal_eval(x.value) for x in module.body if isinstance(x,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='extra' for t in x.targets))
extra=extra[:extra.index('int main(void)')]
pre=(r/'tests/original-background.m').read_text().split('@interface LMVVideoState : NSObject',1)[0]
pre=pre.replace('@class UIWindow;','@class UIWindow, UIViewController;')
pre=pre.replace('#import "../LMVOriginalBackground.h"','#import "LMVOriginalBackground.h"')
pre=pre.replace('@property(nonatomic,strong) UIScreen *screen;','@property(nonatomic,strong) UIScreen *screen;\n@property(nonatomic,strong) UIViewController *rootViewController;')
pre=pre.replace('@property(nonatomic) CGRect bounds;','@property(nonatomic) CGRect bounds,frame;')
pre=pre.replace('- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { return rect; }', '''- (UIView *)superview { return self.layer.superlayer ? _superview : nil; }
- (CGRect)frame { return self.layer.frame; }
- (void)setFrame:(CGRect)frame { self.layer.frame=frame; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { return self.superview ? [self.layer convertRect:rect toLayer:view.layer] : CGRectNull; }''')
extra=extra.replace('@property(nonatomic,copy) NSString *path,*revision;\n@property(nonatomic) CGImageRef lastImage;', '@property(nonatomic,copy) NSString *path,*revision,*ownerTarget;\n@property(nonatomic) CGImageRef lastImage;')
new=r'''
@interface SBCoverSheetWindow:UIWindow @end
@implementation SBCoverSheetWindow @end
@interface SBCoverSheetPanelBackgroundContainerView:UIView @end
@implementation SBCoverSheetPanelBackgroundContainerView @end
@interface SBWallpaperEffectView:UIView @end
@implementation SBWallpaperEffectView @end
@interface PBUIWallpaperView:UIView @end
@implementation PBUIWallpaperView @end
#import "LMVNotificationWallpaper.h"
static void geometry(UIView *view, CGRect frame) {view.bounds=(CGRect){CGPointZero,frame.size};view.frame=frame;}
int main(void) {@autoreleasepool {
 LMVEnabled=[@{@"LockScreen":@YES,@"Desktop":@YES} mutableCopy];
 LMVPaths=[@{@"LockScreen":@"lock.mov",@"Desktop":@"home.mov"} mutableCopy];
 LMVRevisions=[@{@"lock.mov":@"r1",@"home.mov":@"r1"} mutableCopy];
 LMVSharedSources=[NSMutableDictionary new];testFrames=[NSMutableDictionary new];
 LMVLockHosts=[NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];LMVDesktopHosts=[NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];
 LMVNCWallpaperWindows=[NSHashTable weakObjectsHashTable];
 CGImageRef first=image(50),second=image(80);
 LMVSharedSource *source=[LMVSharedSource new];source.path=@"lock.mov";source.revision=@"r1";source.ownerTarget=@"LockScreen";source.lastImage=first;
 LMVSharedSources[LMVSourceRegistryKey(source.path,@"LockScreen")]=source;consumer(YES,source);
 SBCoverSheetWindow *window=[SBCoverSheetWindow new];geometry(window,CGRectMake(0,0,390,844));
 UIView *wrapper=[UIView new];[window addSubview:wrapper];geometry(wrapper,window.bounds);
 SBCoverSheetPanelBackgroundContainerView *panel=[SBCoverSheetPanelBackgroundContainerView new];[wrapper addSubview:panel];geometry(panel,CGRectMake(0,-844,390,844));
 SBWallpaperEffectView *effect=[SBWallpaperEffectView new];[panel addSubview:effect];geometry(effect,panel.bounds);
 effect.alpha=0;PBUIWallpaperView *wall=[PBUIWallpaperView new];[effect addSubview:wall];geometry(wall,panel.bounds);
 UILabel *foreground=[UILabel new];[panel addSubview:foreground];geometry(foreground,CGRectMake(0,10,120,40));
 NSArray *original=panel.layer.sublayers.copy;CALayer *contentLayer=foreground.layer;
 UIWindowScene *scene=[UIWindowScene new];scene.windows=@[window];UIApplication.sharedApplication.connectedScenes=@[scene];
 assert(!LMVNotificationWallpaperVisible());
 // First exposed strip already has the video; no progress=1 or full-screen gate.
 geometry(panel,CGRectMake(0,-824,390,844));assert(LMVNotificationWallpaperVisible());
 CGPoint position=panel.layer.position;CATransform3D transform=panel.layer.transform;
 LMVUpdateNotificationWallpapers();
 NSArray *surfaces=objc_getAssociatedObject(window,&LMVNCWallpaperKey);assert(surfaces.count==1);
 LMVWallpaperSurface *surface=surfaces.firstObject;
 assert(surface.layer.superlayer==panel.layer && surface.leases.count==1 && !effect.layer.superlayer);
 assert(surface.layer.contents==(__bridge id)first && foreground.layer==contentLayer && contentLayer.superlayer==panel.layer);
 assert(CGPointEqualToPoint(panel.layer.position,position) && CATransform3DEqualToTransform(panel.layer.transform,transform));
 LMVOriginalLease *lease=surface.leases.firstObject;
 for(int i=0;i<100;i++) {
  geometry(panel,CGRectMake(0,-824+i*8,390,844));LMVUpdateNotificationWallpapers();
  assert(surface.layer.superlayer==panel.layer && surface.leases.firstObject==lease && !effect.layer.superlayer);
  assert(surface.layer.frame.size.height==844 && !foreground.hidden && foreground.layer.opacity==1);
 }
 source.lastImage=second;LMVNotificationWallpaperPublish(source,second);assert(surface.layer.contents==(__bridge id)second);
 LMVSharedSource *desktop=[LMVSharedSource new];desktop.path=@"home.mov";desktop.revision=@"r1";desktop.ownerTarget=@"Desktop";
 LMVNotificationWallpaperPublish(desktop,first);assert(surface.layer.contents==(__bridge id)second);
 // Cancelling pull keeps video inside offscreen panel, not behind Home icons.
 geometry(panel,CGRectMake(0,-844,390,844));assert(!LMVNotificationWallpaperVisible());LMVUpdateNotificationWallpapers();
 assert(surface.layer.superlayer==panel.layer && window.layer.sublayers.count==1);
 LMVEnabled[@"LockScreen"]=@NO;LMVUpdateNotificationWallpapers();
 assert([panel.layer.sublayers isEqualToArray:original] && !surface.layer.superlayer);
 // Enable again with effect alpha still zero: own video is a sibling and remains visible.
 LMVEnabled[@"LockScreen"]=@YES;geometry(panel,CGRectMake(0,-422,390,844));LMVUpdateNotificationWallpapers();
 surface=[objc_getAssociatedObject(window,&LMVNCWallpaperKey) firstObject];assert(surface.layer.contents && surface.layer.opacity>0 && effect.alpha==0);
 window.hidden=YES;LMVUpdateNotificationWallpapers();assert(effect.layer.superlayer==panel.layer && !surface.layer.superlayer);
 CGImageRelease(first);CGImageRelease(second);
 puts("PASS: actual NC background module: first exposed strip ready, 100 partial-pull positions and stable detach lease, system slide/foreground preserved, Lock-only frames, cancellation offscreen, disable/hidden restore; not device portal proof");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 src=Path(tmp)/'nc.mm';binary=Path(tmp)/'nc';src.write_text(pre+extra+new)
 subprocess.run(['clang++','-std=c++11','-fobjc-arc','-I',str(r),'-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(src),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
