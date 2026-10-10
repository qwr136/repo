#!/usr/bin/env python3
"""Execute production host/manager/hooks with Foundation and real QuartzCore layers."""
from pathlib import Path
import platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LMVLockVideo.h').read_text()
s=(r/'Tweak.xm').read_text()
assert '#import "LMVLockVideo.h"' in s and 'LMVLockVideoRefresh(reload)' in s
assert 'LMVLockVideoSuspend()' in s and 'LMVLockVideoInstallHooks()' in s
assert 'LMVCacheFrame' not in h and 'LMVAcquireOriginal' not in h
assert 'VideoOpacity' not in h and 'SBHomeScreen' not in h and 'Desktop' not in h
assert 'LMVLockVideoHookMatches' in h
assert '[content.layer removeFromSuperlayer]' not in h
if platform.system()!='Darwin':
 print('PASS: isolated lock host contracts; real QuartzCore manager/geometry and IMP execution runs on macOS CI')
 raise SystemExit(0)
pre=r'''
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <assert.h>
#include <math.h>
#include <string.h>
static const NSUInteger UIViewAutoresizingFlexibleWidth=2,UIViewAutoresizingFlexibleHeight=16;
@class UIWindow;
@interface UIScreen:NSObject
+ (instancetype)mainScreen;
@end
@implementation UIScreen
+ (instancetype)mainScreen {static UIScreen *s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
@end
@interface UIColor:NSObject
@property(assign) CGColorRef CGColor;
+ (instancetype)clearColor;
+ (instancetype)blackColor;
@end
@implementation UIColor
+ (instancetype)clearColor {UIColor *c=[self new];c.CGColor=CGColorCreateGenericRGB(0,0,0,0);return c;}
+ (instancetype)blackColor {UIColor *c=[self new];c.CGColor=CGColorCreateGenericRGB(0,0,0,1);return c;}
- (void)dealloc {if(_CGColor)CGColorRelease(_CGColor);}
@end
@interface UIView:NSObject <CALayerDelegate>
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) NSMutableArray<UIView *> *subviews;
@property(nonatomic,weak) UIView *superview;
@property(nonatomic) CGRect frame,bounds;
@property(nonatomic) BOOL hidden,clipsToBounds,opaque,userInteractionEnabled,isAccessibilityElement,accessibilityElementsHidden;
@property(nonatomic) CGFloat alpha;
@property(nonatomic) NSUInteger autoresizingMask;
@property(nonatomic,strong) UIColor *backgroundColor;
@property(nonatomic,readonly) UIWindow *window;
- (instancetype)initWithFrame:(CGRect)rect;
- (BOOL)isDescendantOfView:(UIView *)view;
- (void)addSubview:(UIView *)view;
- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)sibling;
- (void)removeFromSuperview;
- (void)layoutSubviews;
@end
@implementation UIView
- (instancetype)init {return [self initWithFrame:CGRectMake(0,0,390,844)];}
- (instancetype)initWithFrame:(CGRect)rect {if((self=[super init])){_layer=[CALayer layer];_layer.delegate=self;_subviews=[NSMutableArray new];_alpha=1;_userInteractionEnabled=YES;self.frame=rect;}return self;}
- (CGRect)frame {return self.layer.frame;}
- (void)setFrame:(CGRect)value {self.layer.frame=value;}
- (CGRect)bounds {return self.layer.bounds;}
- (void)setBounds:(CGRect)value {self.layer.bounds=value;}
- (BOOL)isDescendantOfView:(UIView *)view {for(UIView *node=self;node;node=node.superview)if(node==view)return YES;return NO;}
- (UIWindow *)window {return self.superview.window;}
- (void)addSubview:(UIView *)view {[view removeFromSuperview];[self.subviews addObject:view];view.superview=self;[self.layer addSublayer:view.layer];}
- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)sibling {assert(sibling.superview==self);[view removeFromSuperview];NSUInteger n=[self.subviews indexOfObjectIdenticalTo:sibling];assert(n!=NSNotFound);[self.subviews insertObject:view atIndex:n+1];view.superview=self;[self.layer insertSublayer:view.layer above:sibling.layer];}
- (void)removeFromSuperview {[self.superview.subviews removeObjectIdenticalTo:self];[self.layer removeFromSuperlayer];self.superview=nil;}
- (void)layoutSubviews {}
@end
@interface UILabel:UIView @end
@implementation UILabel @end
@interface UITextView:UIView @end
@implementation UITextView @end
@interface UIControl:UIView @end
@implementation UIControl @end
@interface UIScrollView:UIView @end
@implementation UIScrollView @end
@interface UIViewController:NSObject
@property(nonatomic,strong) UIView *viewIfLoaded;
@property(nonatomic,strong) NSArray *childViewControllers;
@property(nonatomic,strong) UIViewController *presentedViewController;
@property(nonatomic) NSUInteger loads,layouts,appearances,disappearances;
- (void)loadView;
- (void)viewDidLoad;
- (void)viewDidLayoutSubviews;
- (void)viewWillAppear:(BOOL)animated;
- (void)viewDidAppear:(BOOL)animated;
- (void)viewDidDisappear:(BOOL)animated;
@end
@implementation UIViewController
- (instancetype)init {if((self=[super init]))_childViewControllers=@[];return self;}
- (void)loadView {self.loads++;}
- (void)viewDidLoad {self.loads++;}
- (void)viewDidLayoutSubviews {self.layouts++;}
- (void)viewWillAppear:(BOOL)animated {self.appearances++;}
- (void)viewDidAppear:(BOOL)animated {self.appearances++;}
- (void)viewDidDisappear:(BOOL)animated {self.disappearances++;}
@end
@interface UIWindow:UIView
@property(nonatomic,strong) UIScreen *screen;
@property(nonatomic,strong) UIViewController *rootViewController;
@end
@implementation UIWindow
- (instancetype)init {if((self=[super init]))_screen=UIScreen.mainScreen;return self;}
- (UIWindow *)window {return self;}
@end
@interface SBCoverSheetWindow:UIWindow @end
@implementation SBCoverSheetWindow @end
@interface CSCoverSheetView:UIView
@property(nonatomic,strong) UIView *slideableContentView;
@end
@implementation CSCoverSheetView @end
@interface SBUIBackgroundView:UIView @end
@implementation SBUIBackgroundView @end
@interface DimmingView:UIView @end
@implementation DimmingView @end
@interface CSCoverSheetViewController:UIViewController @end
@implementation CSCoverSheetViewController @end
@interface UIScene:NSObject @end
@implementation UIScene @end
@interface UIWindowScene:UIScene
@property(nonatomic,strong) NSArray *windows;
@end
@implementation UIWindowScene @end
@interface UIApplication:NSObject
@property(nonatomic,strong) NSArray *connectedScenes;
+ (instancetype)sharedApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication {static UIApplication *app;static dispatch_once_t once;dispatch_once(&once,^{app=[self new];});return app;}
@end
@interface TestDisplayLink:NSObject
@property(nonatomic) NSInteger preferredFramesPerSecond;
+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)selector;
- (void)addToRunLoop:(NSRunLoop *)loop forMode:(NSString *)mode;
- (void)invalidate;
@end
@implementation TestDisplayLink
+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)selector {return [self new];}
- (void)addToRunLoop:(NSRunLoop *)loop forMode:(NSString *)mode {}
- (void)invalidate {}
@end
#define CADisplayLink TestDisplayLink
#define LMVLockVideoLog(message) LMVDiagnostic(message)
'''
pre+=r'''
@interface TestPlayer:NSObject
@property NSInteger status;
@end
@implementation TestPlayer @end
@interface TestPlayerLayer:CALayer
@property BOOL readyForDisplay;
@end
@implementation TestPlayerLayer @end
@interface LMVLockVideoPlayback:NSObject
@property(strong) CALayer *renderLayer,*posterLayer;
@property(strong) TestPlayerLayer *playerLayer;
@property(strong) TestPlayer *player;
@property(strong) NSError *error;
@property BOOL loading,wantsPlayback;
@property(copy) void (^didChange)(void);
@property(copy) NSString *path,*revision;
@property NSUInteger builds,clears;
- (void)selectPath:(NSString *)path revision:(NSString *)revision;
- (void)setVisible:(BOOL)visible;
- (void)layoutInBounds:(CGRect)bounds;
- (void)clear;
@end
@implementation LMVLockVideoPlayback
- (instancetype)init {if((self=[super init])){_renderLayer=[CALayer layer];_posterLayer=[CALayer layer];_playerLayer=[TestPlayerLayer layer];_player=[TestPlayer new];}return self;}
- (void)selectPath:(NSString *)path revision:(NSString *)revision {if(![self.path isEqual:path] || ![self.revision isEqual:revision])self.builds++;self.path=path;self.revision=revision;}
- (void)setVisible:(BOOL)visible {self.wantsPlayback=visible;}
- (void)layoutInBounds:(CGRect)bounds {self.renderLayer.frame=bounds;}
- (void)clear {self.clears++;self.path=nil;self.revision=nil;self.wantsPlayback=NO;self.player=nil;}
@end
static NSString *LMVLockVideoRevision(NSString *path){return path.length?@"rev1":nil;}
static BOOL LMVInitialized,LMVLaunchReady;
static NSString * const LMVDirectory=@"/tmp/lock-test";
static CFStringRef const kLMVPrefsID=CFSTR("com.minis.lockmessagevideo.test");
static int LMVBlankToken=1;
static uint64_t screenBlank=0;
#define NOTIFY_STATUS_OK 0
static int notify_get_state(int token,uint64_t *state){*state=screenBlank;return 0;}
static NSUInteger requests;
static void LMVRequestSafeUpdate(void){if(LMVInitialized && LMVLaunchReady)requests++;}
static void LMVDiagnostic(NSString *message){}
static void MSHookMessageEx(Class cls,SEL selector,IMP replacement,IMP *original){Method m=class_getInstanceMethod(cls,selector);*original=method_getImplementation(m);class_replaceMethod(cls,selector,replacement,method_getTypeEncoding(m));}
'''
production=h[h.index('static BOOL LMVLockVideoRectValid'):]
main=r'''
static void assertSystemTree(UIView *parent,NSArray *expected) {
 NSMutableArray *filtered=[NSMutableArray new];for(UIView *v in parent.subviews)if(![v isKindOfClass:LMVLockVideoHost.class])[filtered addObject:v];
 assert([filtered isEqual:expected]);for(UIView *v in expected){assert(v.superview==parent && v.layer.superlayer==parent.layer && v.layer.delegate==v);}
}
int main(void){@autoreleasepool{
 SBCoverSheetWindow *window=[SBCoverSheetWindow new];CSCoverSheetView *cover=[CSCoverSheetView new];[window addSubview:cover];
 SBUIBackgroundView *background=[SBUIBackgroundView new];DimmingView *dimming=[DimmingView new];UIView *sliding=[UIView new];UILabel *clock=[UILabel new];UIControl *button=[UIControl new];
 [cover addSubview:background];[cover addSubview:dimming];[cover addSubview:sliding];[sliding addSubview:clock];[sliding addSubview:button];cover.slideableContentView=sliding;
 background.alpha=.37;background.layer.opacity=.37;NSArray *original=cover.subviews.copy;
 CSCoverSheetViewController *controller=[CSCoverSheetViewController new];controller.viewIfLoaded=cover;window.rootViewController=controller;
 LMVLockControllers=[NSHashTable weakObjectsHashTable];[LMVLockControllers addObject:controller];
 LMVLockVideoManager *manager=[LMVLockVideoManager new];manager.enabled=YES;manager.path=@"movie";manager.revision=@"rev1";manager.screenAllowed=YES;
 [manager update];assert(manager.host.superview==cover && manager.host.layer.superlayer==cover.layer);
 assert([cover.subviews indexOfObject:manager.host]==1 && [cover.subviews indexOfObject:dimming]==2);
 assert(!manager.host.userInteractionEnabled && manager.host.accessibilityElementsHidden && manager.host.alpha==1);
 assert(manager.playback.wantsPlayback && manager.link && !manager.host.hidden);
 assertSystemTree(cover,original);assert(background.alpha==.37 && background.layer.opacity==.37);
 // Root/window stay full-screen while ONLY slideable content moves: exposure
 // must follow content instead of the permanent controller bounds.
 for(int n=0;n<=100;n++) {
  CGFloat exposed=844*n/100.0;sliding.frame=CGRectMake(0,-844+exposed,390,844);
  [manager update];CGRect clip=LMVLockVideoClip(sliding,cover,window);
  if(n==0){assert(CGRectIsEmpty(clip) && !manager.host.superview && !manager.playback.wantsPlayback);}
  else {assert(fabs(clip.size.height-exposed)<.001 && fabs(clip.origin.y)<.001);assert(manager.host.superview==cover && manager.playback.wantsPlayback);
   assert(CGPathContainsPoint(manager.host.clipLayer.path,NULL,CGPointMake(100,exposed/2),NO));
   if(exposed<843)assert(!CGPathContainsPoint(manager.host.clipLayer.path,NULL,CGPointMake(100,exposed+1),NO));}
  assertSystemTree(cover,original);
 }
 // Unknown content and hidden window fail closed, no full-root/window fallback.
 cover.slideableContentView=nil;[manager update];assert(!manager.host.superview && !manager.playback.wantsPlayback);cover.slideableContentView=sliding;
 window.hidden=YES;[manager update];assert(!manager.playback.wantsPlayback);window.hidden=NO;[manager update];assert(manager.playback.wantsPlayback);
 // Bad background with foreground descendants may not become an anchor.
 UILabel *unsafe=[UILabel new];[background addSubview:unsafe];[manager update];assert(!manager.host.superview);[unsafe removeFromSuperview];[manager update];assert(manager.host.superview==cover);
 // Controller disappearance, no screen power, and disabled state each stop.
 LMVLockControllerRecord *record=[LMVLockControllerRecord new];record.lifecycleKnown=YES;record.visible=NO;
 objc_setAssociatedObject(controller,&LMVLockControllerRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 [manager update];assert(!manager.host.superview && !manager.playback.wantsPlayback);record.visible=YES;[manager update];assert(manager.playback.wantsPlayback);
 manager.screenAllowed=NO;[manager update];assert(!manager.host.superview && !manager.link);manager.screenAllowed=YES;
 manager.enabled=NO;[manager update];assert(!manager.host.superview && !manager.playback.wantsPlayback);manager.enabled=YES;
 // New root/window moves only the plugin host. Old and new system trees survive.
 SBCoverSheetWindow *second=[SBCoverSheetWindow new];CSCoverSheetView *newCover=[CSCoverSheetView new];SBUIBackgroundView *newBack=[SBUIBackgroundView new];UIView *newSliding=[UIView new];
 [second addSubview:newCover];[newCover addSubview:newBack];[newCover addSubview:newSliding];newCover.slideableContentView=newSliding;
 NSArray *newOriginal=newCover.subviews.copy;controller.viewIfLoaded=newCover;second.rootViewController=controller;[manager update];
 assert(manager.host.superview==newCover);assertSystemTree(cover,original);assertSystemTree(newCover,newOriginal);
 manager.path=nil;manager.revision=nil;[manager update];assert(!manager.host.superview && !manager.link && !manager.playback.wantsPlayback);
 // Execute installed typed IMPs: orig exactly once, only after-original records,
 // and launch gate does not request policy inside system initializers.
 assert(LMVLockVideoHookMatches(CSCoverSheetViewController.class,@selector(viewDidLoad),NO));
 assert(LMVLockVideoHookMatches(CSCoverSheetViewController.class,@selector(viewWillAppear:),YES));
 assert(!LMVLockVideoHookMatches(CSCoverSheetViewController.class,@selector(description),NO));
 assert(!LMVLockVideoHookMatches(CSCoverSheetViewController.class,@selector(viewDidLoad),YES));
 LMVInitialized=YES;LMVLaunchReady=NO;LMVLockVideoInstallHooks();
 [controller viewDidLoad];[controller viewDidLayoutSubviews];[controller viewWillAppear:YES];assert(controller.loads==1 && controller.layouts==1 && controller.appearances==1 && !requests);
 LMVLaunchReady=YES;[controller viewDidAppear:YES];[controller viewDidDisappear:NO];assert(controller.appearances==2 && controller.disappearances==1 && requests==2);
 LMVLockControllerRecord *finalRecord=objc_getAssociatedObject(controller,&LMVLockControllerRecordKey);assert(finalRecord.lifecycleKnown && !finalRecord.visible);
 [manager suspend];
 puts("PASS: actual production lock host/manager and typed hooks with real QuartzCore: background/video/dimming/foreground order, 101 content-only exposure positions, hidden/unknown/mixed rejection, disable/screen/controller cleanup, new root transfer, original tree intact, ABI mismatch rejection and one original call; playback mocked here, separately real AVFoundation; not device compositing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'host.m';binary=Path(tmp)/'host';source.write_text(pre+production+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
