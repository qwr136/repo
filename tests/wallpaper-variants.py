from pathlib import Path
import platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LMVWallpaperWindow.h').read_text();s=(r/'Tweak.xm').read_text()
assert 'LMVWallpaperCoverIsVisible' not in h and 'CALayer *root=window.layer' not in h
assert 'PBUIPosterLockViewController' in h and 'PBUIPosterHomeViewController' in h
assert 'viewIfLoaded' in h and 'CALayer *parent=host.layer' in h
assert 'LMVWallpaperTargetConsumes(surface.target,source)' in h
assert 'surface.layer.contents=nil' in h and 'LMVWallpaperUpdating' in h
assert 'state.layer.hidden = !activity.draw; state.active = NO;' not in s
if platform.system()!='Darwin':
 print('PASS: independent variant roots/frames; real QuartzCore replacement test on macOS CI')
 raise SystemExit(0)
# Reuse the existing real QuartzCore view doubles (no UIKit on macOS).
pre=(r/'tests/original-background.m').read_text().split('@interface LMVVideoState : NSObject',1)[0]
pre=pre.replace('@class UIWindow;','@class UIWindow, UIViewController;')
pre=pre.replace('@property(nonatomic,strong) UIScreen *screen;','@property(nonatomic,strong) UIScreen *screen;\n@property(nonatomic,strong) UIViewController *rootViewController;')
# Import is resolved from this repository, not the temporary generated file.
pre=pre.replace('#import "../LMVOriginalBackground.h"','#import "LMVOriginalBackground.h"')
extra=r'''
@interface UIViewController:NSObject
@property(nonatomic,strong) UIView *viewIfLoaded;
@property(nonatomic,strong) NSArray<UIViewController *> *childViewControllers;
@end
@implementation UIViewController
- (instancetype)init {if((self=[super init]))_childViewControllers=@[];return self;}
@end
@interface PBUIPosterLockViewController:UIViewController @end
@implementation PBUIPosterLockViewController @end
@interface PBUIPosterHomeViewController:UIViewController @end
@implementation PBUIPosterHomeViewController @end
@interface PBUISnapshotReplicaView:UIView @end
@implementation PBUISnapshotReplicaView @end
@interface _UIScenePresentationView:UIView @end
@implementation _UIScenePresentationView @end
@interface LMVSharedSource:NSObject
@property(nonatomic,copy) NSString *path,*revision;
@property(nonatomic) CGImageRef lastImage;
@end
@implementation LMVSharedSource @end
@interface LMVVideoState:NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) LMVSharedSource *source;
@property(nonatomic) BOOL active;
@property(nonatomic,copy) NSString *path,*revision;
@property(nonatomic,strong) NSArray<LMVOriginalLease *> *originals,*wallpaperOriginals;
@property(nonatomic,weak) UIView *originalAnchor,*originalScope;
@property(nonatomic,copy) NSString *originalDiagnostic,*wallpaperDiagnostic;
@end
@implementation LMVVideoState @end
@interface LMVFrameSnapshot:NSObject
@property(nonatomic) CGImageRef image;
@end
@implementation LMVFrameSnapshot @end
static NSMutableDictionary<NSString *, NSString *> *LMVPaths,*LMVRevisions;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *, LMVSharedSource *> *LMVSharedSources;
static NSMutableDictionary<NSString *, LMVFrameSnapshot *> *testFrames;
static NSHashTable *LMVLockHosts,*LMVDesktopHosts;
static char LMVLockStateKey,LMVDesktopStateKey;
static BOOL LMVInitialized=YES,LMVLaunchReady=YES,LMVOpacityEnabled=YES;
static CGFloat LMVOpacity=.65;
static void LMVDiagnostic(NSString *message) {}
static NSString *NSStringFromCGRect(CGRect rect) {return @"rect";}
static NSString *LMVSourceRegistryKey(NSString *path,NSString *target) {return [NSString stringWithFormat:@"wallpaper/%@|%@",target,path];}
static LMVFrameSnapshot *LMVCachedWallpaperFrame(NSString *path,NSString *revision,NSString *target) {return testFrames[[LMVSourceRegistryKey(path,target) stringByAppendingString:revision]];}
#import "LMVBackgroundDiscovery.h"
#import "LMVWallpaperWindow.h"
static CGImageRef image(unsigned char red) {
 unsigned char p[]={red,0,0,255};CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
 CGContextRef c=CGBitmapContextCreate(p,1,1,8,4,cs,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(cs);
 CGImageRef out=CGBitmapContextCreateImage(c);CGContextRelease(c);return out;
}
static UIViewController *variant(UIWindow *window,UIView *wrapper,BOOL lock) {
 UIViewController *c=lock?[PBUIPosterLockViewController new]:[PBUIPosterHomeViewController new];
 c.viewIfLoaded=[UIView new];[wrapper addSubview:c.viewIfLoaded];
 [c.viewIfLoaded addSubview:[PBUISnapshotReplicaView new]];
 UIView *scene=[UIView new];[c.viewIfLoaded addSubview:scene];[scene addSubview:[_UIScenePresentationView new]];
 return c;
}
static LMVVideoState *consumer(BOOL lock,LMVSharedSource *source) {
 UIView *host=[UIView new];LMVVideoState *st=[LMVVideoState new];st.source=source;st.active=YES;
 st.path=source.path;st.revision=source.revision;st.layer=[CALayer layer];
 objc_setAssociatedObject(host,lock?&LMVLockStateKey:&LMVDesktopStateKey,st,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 [(lock ? LMVLockHosts : LMVDesktopHosts) addObject:host];
 // Consumer hosts kept strongly by the strong test table.
 return st;
}
int main(void) {@autoreleasepool {
 LMVPaths=[@{@"LockScreen":@"lock.mov",@"Desktop":@"home.mov"} mutableCopy];
 LMVRevisions=[@{@"lock.mov":@"r1",@"home.mov":@"r1"} mutableCopy];
 LMVEnabled=[@{@"LockScreen":@YES,@"Desktop":@YES} mutableCopy];
 LMVSharedSources=[NSMutableDictionary new];testFrames=[NSMutableDictionary new];
 LMVLockHosts=[NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];LMVDesktopHosts=[NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory];LMVWallpaperWindows=[NSHashTable weakObjectsHashTable];
 CGImageRef lockImage=image(30),homeImage=image(80),newImage=image(120);
 LMVSharedSource *lockSource=[LMVSharedSource new];lockSource.path=@"lock.mov";lockSource.revision=@"r1";lockSource.lastImage=lockImage;
 LMVSharedSource *homeSource=[LMVSharedSource new];homeSource.path=@"home.mov";homeSource.revision=@"r1";homeSource.lastImage=homeImage;
 LMVSharedSources[LMVSourceRegistryKey(@"lock.mov",@"LockScreen")]=lockSource;LMVSharedSources[LMVSourceRegistryKey(@"home.mov",@"Desktop")]=homeSource;
 LMVVideoState *lockState=consumer(YES,lockSource),*homeState=consumer(NO,homeSource);
 _SBWallpaperSecureWindow *window=[_SBWallpaperSecureWindow new];UIView *wrapper=[UIView new];[window addSubview:wrapper];
 wrapper.layer.transform=CATransform3DMakeScale(1.2,1.2,1);wrapper.layer.position=CGPointMake(210,500);
 CATransform3D oldTransform=wrapper.layer.transform;CGPoint oldPosition=wrapper.layer.position;
 UIViewController *root=[UIViewController new];root.viewIfLoaded=wrapper;window.rootViewController=root;
 UIViewController *lock=variant(window,wrapper,YES),*home=variant(window,wrapper,NO);root.childViewControllers=@[lock,home];
 CALayer *lockOriginal=lock.viewIfLoaded.layer,*homeOriginal=home.viewIfLoaded.layer;
 NSArray *lockChildren=lockOriginal.sublayers.copy,*homeChildren=homeOriginal.sublayers.copy;
 UIWindowScene *scene=[UIWindowScene new];scene.windows=@[window];UIApplication.sharedApplication.connectedScenes=@[scene];
 LMVUpdateWallpaperWindows();
 NSDictionary *surfaces=objc_getAssociatedObject(window,&LMVWallpaperSurfaceKey);
 LMVWallpaperSurface *l=surfaces[@"LockScreen"],*h=surfaces[@"Desktop"];
 assert(l && h && l.layer.superlayer==lockOriginal && h.layer.superlayer==homeOriginal);
 assert(l.leases.count==2 && h.leases.count==2);
 assert(l.layer.contents==(__bridge id)lockImage && h.layer.contents==(__bridge id)homeImage);
 assert(lockOriginal.superlayer==wrapper.layer && homeOriginal.superlayer==wrapper.layer);
 assert(CATransform3DEqualToTransform(oldTransform,wrapper.layer.transform) && CGPointEqualToPoint(oldPosition,wrapper.layer.position));
 assert(window.layer.sublayers.count==1 && window.layer.sublayers.firstObject==wrapper.layer);
 // Repeated partial-cover layout cannot globally choose Lock content for Home.
 lock.viewIfLoaded.layer.position=CGPointMake(195,-100);home.viewIfLoaded.layer.opacity=.8;
 for(int n=0;n<20;n++) LMVUpdateWallpaperWindows();
 assert(h.layer.contents==(__bridge id)homeImage && h.layer.superlayer==homeOriginal);
 assert(homeOriginal.opacity==.8f && lockOriginal.position.y==-100);
 lockSource.lastImage=newImage;LMVWallpaperPublish(lockSource,newImage);
 assert(l.layer.contents==(__bridge id)newImage && h.layer.contents==(__bridge id)homeImage);
 // Same file, separate sources: Lock continues without updating paused Home.
 LMVSharedSource *homeSame=[LMVSharedSource new];homeSame.path=@"lock.mov";homeSame.revision=@"r1";homeSame.lastImage=homeImage;
 LMVSharedSources[LMVSourceRegistryKey(@"lock.mov",@"Desktop")]=homeSame;
 LMVPaths[@"Desktop"]=@"lock.mov";homeState.source=homeSame;homeState.path=@"lock.mov";homeState.revision=@"r1";
 assert(homeSame!=lockSource);
 LMVUpdateWallpaperWindows();id frozen=h.layer.contents;homeState.active=NO;
 lockSource.lastImage=lockImage;LMVWallpaperPublish(lockSource,lockImage);LMVUpdateWallpaperWindows();
 assert(h.layer.contents==frozen && l.layer.contents==(__bridge id)lockImage);
 homeState.active=YES;homeSame.lastImage=newImage;LMVWallpaperPublish(homeSame,newImage);
 assert(h.layer.contents==(__bridge id)newImage && l.layer.contents==(__bridge id)lockImage);
 // Different file/revision with no frame must not retain previous material.
 LMVPaths[@"Desktop"]=@"cold.mov";LMVRevisions[@"cold.mov"]=@"r2";
 LMVUpdateWallpaperWindows();assert(!h.layer.contents && h.leases.count==2);
 // Disable only Lock: restore the same system children in original order.
 LMVEnabled[@"LockScreen"]=@NO;LMVUpdateWallpaperWindows();
 assert(![objc_getAssociatedObject(window,&LMVWallpaperSurfaceKey) objectForKey:@"LockScreen"]);
 assert([lockOriginal.sublayers isEqualToArray:lockChildren]);assert(h.layer.superlayer==homeOriginal && h.leases.count==2);
 // Reinserted original during layout is removed again only in original scope.
 [homeOriginal addSublayer:homeChildren.firstObject];LMVUpdateWallpaperWindows();
 assert(((CALayer *)homeChildren.firstObject).superlayer==nil && h.leases.count==2);
 // Replace Home controller root: old layers restore, new host gets own leases.
 UIView *previous=home.viewIfLoaded;UIViewController *replacement=variant(window,wrapper,NO);root.childViewControllers=@[lock,replacement];
 LMVUpdateWallpaperWindows();
 assert([previous.layer.sublayers isEqualToArray:homeChildren]);assert(h.host==replacement.viewIfLoaded && h.layer.superlayer==replacement.viewIfLoaded.layer);
 // Missing/unknown controller never causes global root layer fallback.
 root.childViewControllers=@[];LMVUpdateWallpaperWindows();assert(![objc_getAssociatedObject(window,&LMVWallpaperSurfaceKey) count]);
 assert(window.layer.sublayers.count==1);
 CGImageRelease(lockImage);CGImageRelease(homeImage);CGImageRelease(newImage);
 puts("PASS: actual variant module with real QuartzCore: independent Lock/Home backgrounds, no root-window video, wrapper identity/transform retained, partial cover isolation, same-file independent source pause, cold replacement, independent disable/restore, reinsert and root replacement; not device portal proof");
 (void)lockState;
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 src=Path(tmp)/'variants.mm';out=Path(tmp)/'variants';src.write_text(pre+extra)
 subprocess.run(['clang++','-std=c++11','-fobjc-arc','-I',str(r),'-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(src),'-o',str(out)],check=True)
 subprocess.run([str(out)],check=True,timeout=30)
