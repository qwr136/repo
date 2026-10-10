#!/usr/bin/env python3
"""Exercise the actual Desktop manager/hooks with Foundation and real CALayers."""
from pathlib import Path
import ast,platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LMVDesktopVideo.h').read_text();s=(r/'Tweak.xm').read_text()
assert '#import "LMVDesktopVideo.h"' in s and 'LMVDesktopVideoRefresh(reload)' in s
assert 'LMVDesktopVideoInstallHooks()' in s and 'LMVDesktopVideoSuspend()' in s
assert 'LMVCacheFrame' not in h and 'LMVAcquireOriginal' not in h
assert 'LMVDesktopExplicitWallpaper' in h and 'homescreenWallpaperView' in h
assert 'sharedWallpaperView' not in h  # Ambiguous Lock/Home source must not be used.
if platform.system()!='Darwin':
 print('PASS: independent Desktop integration contracts; real manager/QuartzCore/typed IMP execution runs on macOS CI')
 raise SystemExit(0)
# Reuse only the UIKit/Foundation doubles from the existing native lock test;
# never execute that test's logic or copy/reimplement production desktop logic.
tree=ast.parse((r/'tests/lock-video-host.py').read_text());pre=''
for node in tree.body:
 if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='pre' for t in node.targets):pre=ast.literal_eval(node.value)
 elif isinstance(node,ast.AugAssign) and isinstance(node.target,ast.Name) and node.target.id=='pre':pre+=ast.literal_eval(node.value)
assert pre
pre=pre.replace('@property(nonatomic) NSUInteger autoresizingMask;', '@property(nonatomic) NSUInteger autoresizingMask;\n@property(nonatomic,strong) NSArray *gestureRecognizers;')
pre=pre.replace('- (void)addSubview:(UIView *)view;', '- (void)addSubview:(UIView *)view;\n- (void)insertSubview:(UIView *)view atIndex:(NSUInteger)index;')
pre=pre.replace('- (void)layoutSubviews {}', '- (void)insertSubview:(UIView *)view atIndex:(NSUInteger)index {[view removeFromSuperview];[self.subviews insertObject:view atIndex:MIN(index,self.subviews.count)];view.superview=self;[self.layer insertSublayer:view.layer atIndex:(unsigned)MIN(index,self.layer.sublayers.count)];}\n- (void)layoutSubviews {}')
pre=pre.replace('@interface UIWindow:UIView\n', '@interface UIWindow:UIView\n- (CGRect)convertRect:(CGRect)rect toWindow:(UIWindow *)window;\n')
pre=pre.replace('- (UIWindow *)window {return self;}','- (UIWindow *)window {return self;}\n- (CGRect)convertRect:(CGRect)rect toWindow:(UIWindow *)window {return [self.layer convertRect:rect toLayer:window.layer];}')
pre=pre.replace('@interface UIApplication:NSObject\n','@interface UIApplication:NSObject\n@property(nonatomic,strong) id frontmost;\n- (id)_frontmostApplication;\n')
pre=pre.replace('@implementation UIApplication\n','@implementation UIApplication\n- (id)_frontmostApplication {return self.frontmost;}\n')
pre=pre.replace('static int LMVBlankToken=1;', 'static int LMVBlankToken=1,LMVLockToken=2;')
pre=pre.replace('static uint64_t screenBlank=0;', 'static uint64_t screenBlank=0,screenLocked=0;')
pre=pre.replace('*state=screenBlank;return 0;', '*state=token==LMVLockToken?screenLocked:screenBlank;return 0;')
pre=pre.replace('self.wantsPlayback=visible;', 'self.wantsPlayback=visible;self.renderLayer.hidden=!visible || self.error!=nil || !self.posterLayer.contents;')
pre=pre.replace('@property NSUInteger builds,clears;', '@property NSUInteger builds,clears,earlyReads;\n@property BOOL persistentPosterEnabled,posterOnlyVisible;\n- (void)preparePosterForPath:(NSString *)path revision:(NSString *)revision;\n- (void)loadCachedPosterNowForPath:(NSString *)path revision:(NSString *)revision;\n- (void)showPreparedPoster:(BOOL)visible;\n- (void)applyPreparedPoster:(CGImageRef)image path:(NSString *)path revision:(NSString *)revision;')
pre=pre.replace('@implementation LMVLockVideoPlayback\n', '@implementation LMVLockVideoPlayback\n- (void)preparePosterForPath:(NSString *)path revision:(NSString *)revision {}\n- (void)applyPreparedPoster:(CGImageRef)image path:(NSString *)path revision:(NSString *)revision {self.posterLayer.contents=(__bridge id)image;}\n- (void)loadCachedPosterNowForPath:(NSString *)path revision:(NSString *)revision {self.earlyReads++;}\n- (void)showPreparedPoster:(BOOL)visible {self.posterOnlyVisible=visible;self.wantsPlayback=NO;self.renderLayer.hidden=!visible || !self.posterLayer.contents;}\n')
# Reproduce the .077 failure boundary: dyld initializer executes before UIKit.
# Any view/player construction or screen/application query then throws.
pre=pre.replace('#import <Foundation/Foundation.h>', '#import <Foundation/Foundation.h>\nstatic BOOL forbidUIKit;\nstatic NSUInteger viewConstructions,playbackConstructions,screenQueries,appQueries;')
pre=pre.replace('+ (instancetype)mainScreen {static UIScreen *s;', '+ (instancetype)mainScreen {screenQueries++;NSCAssert(!forbidUIKit,@"UIScreen used during loader initialization");static UIScreen *s;')
pre=pre.replace('+ (instancetype)sharedApplication {static UIApplication *app;', '+ (instancetype)sharedApplication {appQueries++;NSCAssert(!forbidUIKit,@"UIApplication used during loader initialization");static UIApplication *app;')
pre=pre.replace('- (instancetype)initWithFrame:(CGRect)rect {if((self=[super init]))', '- (instancetype)initWithFrame:(CGRect)rect {viewConstructions++;NSCAssert(!forbidUIKit,@"UIView created during loader initialization");if((self=[super init]))')
pre=pre.replace('- (instancetype)init {if((self=[super init])){_renderLayer=', '- (instancetype)init {playbackConstructions++;NSCAssert(!forbidUIKit,@"Playback created during loader initialization");if((self=[super init])){_renderLayer=')
pre+=r'''
static NSDictionary *testPrefs;
static CFPropertyListRef testPreference(CFStringRef key,CFStringRef domain) {return CFBridgingRetain(testPrefs[(__bridge NSString *)key]);}
#define CFPreferencesCopyAppValue testPreference
static NSUInteger posterReads;
static dispatch_queue_t LMVVideoPosterQueue(void) {static dispatch_queue_t queue;static dispatch_once_t once;dispatch_once(&once,^{queue=dispatch_queue_create("test.desktop-poster",DISPATCH_QUEUE_SERIAL);});return queue;}
static CGImageRef LMVVideoPosterRead(NSString *path,NSString *revision) {
    posterReads++;CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(NULL,2,2,8,8,color,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(color);
    assert(context);CGContextSetRGBFillColor(context,1,0,0,1);CGContextFillRect(context,CGRectMake(0,0,2,2));CGImageRef image=CGBitmapContextCreateImage(context);CGContextRelease(context);return image;
}
static void posterTurn(void) {dispatch_sync(LMVVideoPosterQueue(),^{});[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.02]];}
@interface SBHomeScreenWindow:UIWindow @end
@implementation SBHomeScreenWindow @end
@interface SBHomeScreenViewController:UIViewController @end
@implementation SBHomeScreenViewController @end
@interface SBIconController:UIViewController @end
@implementation SBIconController @end
@interface PBUIPosterHomeViewController:UIViewController @end
@implementation PBUIPosterHomeViewController @end
@interface PBUIPosterLockViewController:UIViewController @end
@implementation PBUIPosterLockViewController @end
@interface SBFWallpaperView:UIView
@property(nonatomic,strong) UIView *contentView;
@end
@implementation SBFWallpaperView @end
static NSUInteger sharedCalls;
@interface SBWallpaperController:NSObject
@property(nonatomic,strong) UIView *homescreenWallpaperView,*lockscreenWallpaperView;
+ (instancetype)sharedInstance;
@end
@implementation SBWallpaperController
+ (instancetype)sharedInstance {sharedCalls++;static SBWallpaperController *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
@end
@interface TestApplication:NSObject
@property(nonatomic,copy) NSString *bundleIdentifier;
@end
@implementation TestApplication @end
'''
lock=(r/'LMVLockVideo.h').read_text()
# Execute real discovery, geometry and ABI validators needed by Desktop.
helpers=lock[lock.index('static BOOL LMVLockVideoRectValid'):lock.index('@interface LMVLockVideoHost')]
abi=lock[lock.index('static BOOL LMVLockVideoHookMatches'):lock.index('static void LMVLockVideoInstallHooks')]
main=r'''
static void originalTree(UIView *parent,NSArray *expected) {
 NSMutableArray *actual=[NSMutableArray new];for(UIView *v in parent.subviews)if(![v isKindOfClass:LMVDesktopVideoHost.class])[actual addObject:v];
 assert([actual isEqual:expected]);for(UIView *v in expected)assert(v.superview==parent && v.layer.superlayer==parent.layer && v.layer.delegate==v);
}
int main(void){@autoreleasepool {
 // Execute the same entry called from the real dylib ctor while all UIKit
 // constructors, screen queries and application queries are forbidden.
 LMVInitialized=YES;LMVLaunchReady=NO;forbidUIKit=YES;
 testPrefs=@{@"DesktopBackgroundEnabled":@YES,@"DesktopVideo":@"library/warm.mov"};
 for(int n=0;n<50;n++)LMVDesktopPrimeEarly();
 assert(!LMVDesktopVideo && !LMVDesktopUIAvailable);
 assert(![LMVDesktopVideoManager new] && !LMVDesktopEnsureManager());
 LMVDesktopEarlyLayout();posterTurn();
 assert(LMVDesktopSeed.image && posterReads==1 && !viewConstructions && !playbackConstructions && !screenQueries && !appQueries);
 // Disabled early priming also stays data-only and drops the prior seed.
 testPrefs=@{@"DesktopBackgroundEnabled":@NO};LMVDesktopPrimeEarly();posterTurn();assert(!LMVDesktopSeed.image && !LMVDesktopVideo && !viewConstructions && !playbackConstructions && !screenQueries && !appQueries);
 testPrefs=@{@"DesktopBackgroundEnabled":@YES,@"DesktopVideo":@"library/warm.mov"};LMVDesktopPrimeEarly();posterTurn();assert(LMVDesktopSeed.image && posterReads==2);
 forbidUIKit=NO;
 LMVLaunchReady=YES;
 SBHomeScreenWindow *homeWindow=[SBHomeScreenWindow new];UIView *home=[UIView new];[homeWindow addSubview:home];
 SBHomeScreenViewController *controller=[SBHomeScreenViewController new];controller.viewIfLoaded=home;homeWindow.rootViewController=controller;
 SBUIBackgroundView *back=[SBUIBackgroundView new];UIView *icons=[UIView new];UIControl *dock=[UIControl new];[home addSubview:back];[home addSubview:icons];[home addSubview:dock];NSArray *homeOriginal=home.subviews.copy;
 UIWindow *wallWindow=[UIWindow new];SBFWallpaperView *wall=[SBFWallpaperView new];UIView *wallPixels=[UIView new];[wallWindow addSubview:wall];[wall addSubview:wallPixels];wall.contentView=wallPixels;
 NSArray *wallOriginal=wall.subviews.copy;
 SBCoverSheetWindow *nc=[SBCoverSheetWindow new];CSCoverSheetView *cover=[CSCoverSheetView new];UIView *sliding=[UIView new];[nc addSubview:cover];[cover addSubview:sliding];cover.slideableContentView=sliding;sliding.frame=CGRectMake(0,-844,390,844);
 UIWindowScene *scene=[UIWindowScene new];scene.windows=@[homeWindow,wallWindow,nc];UIApplication.sharedApplication.connectedScenes=@[scene];
 LMVDesktopControllers=[NSHashTable weakObjectsHashTable];[LMVDesktopControllers addObject:controller];
 LMVDesktopControllerRecord *record=[LMVDesktopControllerRecord new];record.known=YES;record.visible=YES;objc_setAssociatedObject(controller,&LMVDesktopControllerRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 LMVDesktopExplicitWallpaper=wall;
 LMVDesktopVideoManager *m=[LMVDesktopVideoManager new];m.enabled=YES;m.path=@"movie";m.revision=@"rev1";
 m.playback.path=@"movie";m.playback.posterLayer.contents=(id)@"pixel";
 [m update];assert(m.host.superview==wall && [wall.subviews indexOfObject:m.host]==1 && wallPixels.hidden && m.playback.wantsPlayback);
 assert(m.host.alpha==1 && !m.host.userInteractionEnabled && m.host.accessibilityElementsHidden);originalTree(wall,wallOriginal);originalTree(home,homeOriginal);
 for(int n=0;n<100;n++){[m update];assert(m.host.superview==wall && wallPixels.hidden);originalTree(wall,wallOriginal);}
 // App transition pauses/hides Desktop and restores only the leased content.
 TestApplication *app=[TestApplication new];app.bundleIdentifier=@"com.apple.mobilesafari";UIApplication.sharedApplication.frontmost=app;[m update];
 assert(!m.host.superview && !m.playback.wantsPlayback && !wallPixels.hidden);UIApplication.sharedApplication.frontmost=nil;[m update];assert(m.host.superview==wall);
 // Content-only NC pulls do not retarget Home, do not mutate Home frame/alpha,
 // and fully covered NC pauses decoding while retaining the last Desktop frame.
 for(int n=0;n<=100;n++) {
  CGFloat height=844*n/100.0;sliding.frame=CGRectMake(0,-844+height,390,844);screenLocked=n?1:0;[m update];
  assert(m.host.superview==wall && wallPixels.hidden);originalTree(wall,wallOriginal);originalTree(home,homeOriginal);
  if(n==100)assert(!m.playback.wantsPlayback && !m.playback.renderLayer.hidden);else assert(m.playback.wantsPlayback);
 }
 sliding.frame=CGRectMake(0,-844,390,844);screenLocked=0;[m update];assert(m.playback.wantsPlayback);
 // A screen blank invalidates authentication; waking at real lock never draws Desktop.
 screenBlank=1;[m update];assert(!m.host.superview && !m.authenticatedSession && !wallPixels.hidden);
 screenBlank=0;screenLocked=1;sliding.frame=CGRectMake(0,0,390,844);[m update];assert(!m.host.superview && !m.playback.wantsPlayback);
 screenLocked=0;sliding.frame=CGRectMake(0,-844,390,844);[m update];assert(m.host.superview==wall);
 // Unknown NC content fails closed; disabled, missing material and errors restore.
 cover.slideableContentView=nil;[m update];assert(!m.host.superview && !wallPixels.hidden);cover.slideableContentView=sliding;
 m.enabled=NO;[m update];assert(!m.host.superview && !m.playback.wantsPlayback && !wallPixels.hidden);m.enabled=YES;m.playback.path=@"movie";
 [m update];m.playback.error=[NSError errorWithDomain:@"test" code:5 userInfo:nil];[m update];assert(!m.lease);m.playback.error=nil;
 // Wallpaper content must stay background-only. Foreground text forbids hiding.
 UILabel *text=[UILabel new];[wallPixels addSubview:text];[m update];assert(!m.lease && !wallPixels.hidden && m.host.superview==home);
 [text removeFromSuperview];[m update];assert(m.host.superview==wall && wallPixels.hidden);
 // Host replacement restores old content before acquiring a new lease.
 SBFWallpaperView *newWall=[SBFWallpaperView new];UIView *newPixels=[UIView new];[wallWindow addSubview:newWall];[newWall addSubview:newPixels];newWall.contentView=newPixels;
 LMVDesktopExplicitWallpaper=newWall;[m update];assert(m.host.superview==newWall && newPixels.hidden && !wallPixels.hidden);originalTree(wall,wallOriginal);
 // Original hidden baseline remains hidden when the plugin releases it.
 [m suspend];assert(!newPixels.hidden && !m.playback.wantsPlayback);m.suspended=NO;newPixels.hidden=YES;[m update];[m suspend];assert(newPixels.hidden);newPixels.hidden=NO;m.suspended=NO;
 // Exact PaperBoard Home variant receives its own video above its background
 // scene/snapshot content; Lock variant is never a candidate.
 LMVDesktopExplicitWallpaper=nil;record.visible=NO;PBUIPosterHomeViewController *poster=[PBUIPosterHomeViewController new];UIView *posterRoot=[UIView new];UIView *snapshot=[UIView new];[wallWindow addSubview:posterRoot];[posterRoot addSubview:snapshot];poster.viewIfLoaded=posterRoot;[LMVDesktopControllers addObject:poster];
 NSArray *posterOriginal=posterRoot.subviews.copy;[m update];assert(m.host.superview==posterRoot && posterRoot.subviews.lastObject==m.host);originalTree(posterRoot,posterOriginal);
 [LMVDesktopControllers removeObject:poster];record.visible=YES;[m update];assert(m.host.superview==home && [home.subviews indexOfObject:m.host]==1);originalTree(home,homeOriginal);
 // Early first layout with a matching still image must draw before launch,
 // with no request to start the player. Transition to ready retains that layer.
 LMVLaunchReady=NO;[m update];assert(m.host.superview==home && !m.playback.wantsPlayback && m.playback.posterOnlyVisible && !m.playback.renderLayer.hidden);
 CALayer *earlyLayer=m.playback.renderLayer;LMVLaunchReady=YES;[m update];assert(m.playback.wantsPlayback && m.playback.renderLayer==earlyLayer && !m.playback.renderLayer.hidden);
 // Typed IMP hooks forward once, record visibility only, and never invoke
 // wallpaper sharedInstance from lifecycle or discovery.
 [m suspend];[m.host removeFromSuperview];
 LMVInitialized=YES;LMVLaunchReady=NO;LMVDesktopUIAvailable=NO;LMVDesktopVideo=nil;
 LMVDesktopVideoInstallHooks();NSUInteger before=sharedCalls;
 // viewDidLoad and arbitrary wallpaper layout do not open the UI creation gate.
 NSUInteger constructed=playbackConstructions;
 [controller viewDidLoad];assert(!LMVDesktopVideo && !LMVDesktopUIAvailable);
 [wall layoutSubviews];assert(!LMVDesktopVideo && !LMVDesktopUIAvailable);
 SBHomeScreenViewController *detached=[SBHomeScreenViewController new];detached.viewIfLoaded=[UIView new];
 [detached viewDidLayoutSubviews];assert(!LMVDesktopVideo && !LMVDesktopUIAvailable);
 // Attached Home original layout has completed: now create one manager and
 // adopt the cache-only seed without starting a video decoder before launch.
 [controller viewDidLayoutSubviews];assert(LMVDesktopUIAvailable && LMVDesktopVideo && playbackConstructions==constructed+1);
 assert(LMVDesktopVideo.playback.posterLayer.contents && LMVDesktopVideo.playback.posterOnlyVisible && !LMVDesktopVideo.playback.wantsPlayback);
 assert(!LMVDesktopVideo.playback.builds && LMVDesktopSeed.image==NULL);
 for(int n=0;n<50;n++)LMVDesktopHostReady(controller);assert(playbackConstructions==constructed+1);
 [controller viewWillAppear:YES];[controller viewDidAppear:YES];[controller viewDidDisappear:NO];
 assert(controller.loads==1 && controller.layouts==1 && controller.appearances==2 && controller.disappearances==1 && sharedCalls==before && !requests);
 [LMVDesktopVideo suspend];[LMVDesktopVideo.host removeFromSuperview];
 SBWallpaperController *publisher=[SBWallpaperController sharedInstance];publisher.homescreenWallpaperView=wall;publisher.lockscreenWallpaperView=[UIView new];LMVDesktopDiscover();assert(LMVDesktopExplicitWallpaper==wall && sharedCalls==before+1);
 publisher.lockscreenWallpaperView=wall;LMVDesktopDiscover();assert(!LMVDesktopExplicitWallpaper);publisher.lockscreenWallpaperView=[UIView new];
 [m suspend];[m.host removeFromSuperview];
 puts("PASS: production Desktop manager/typed hooks with real QuartzCore: explicit Home wallpaper above content, baseline-aware content restore, app/screen/lock/unknown gates, 101 NC pulls and paused retained frame, fallback below icons/Dock, exact PaperBoard Home variant, replacement/disable/error, no singleton creation or backing detach; separate real AVFoundation test covers decoder independence; not device compositing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'desktop.m';binary=Path(tmp)/'desktop';source.write_text(pre+helpers+abi+h+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
