#!/usr/bin/env python3
"""Run production floating-window predicates with Foundation/real CALayer doubles."""
from pathlib import Path
import platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'LMVEasterOverlay.h').read_text()
helpers=s[s.index('static BOOL LMVEasterKnownWindow('):s.index('static void LMVEasterDarwin(')]
if platform.system()!='Darwin':
    assert 'window.windowLevel >= UIWindowLevelAlert && substantive' in helpers and 'area/full>=0.30' in helpers
    print('PASS: content-based floating window contracts; native predicates run in macOS CI')
    raise SystemExit(0)
preamble=r'''
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>
#import <string.h>
#include <assert.h>
static const CGFloat UIWindowLevelAlert = 2000;
@class UIWindow;
@interface UIScreen : NSObject
+ (instancetype)mainScreen;
@end
@implementation UIScreen
+ (instancetype)mainScreen { static UIScreen *s; static dispatch_once_t once; dispatch_once(&once,^{s=[self new];});return s; }
@end
@interface UIColor : NSObject
@property(assign) CGColorRef CGColor;
@end
@implementation UIColor
- (void)dealloc { if (_CGColor) CGColorRelease(_CGColor); }
@end
@interface UIView : NSObject
@property BOOL hidden;
@property(weak) UIView *superview;
@property CGFloat alpha;
@property CGRect bounds;
@property(strong) CALayer *layer;
@property(strong) NSArray *subviews;
@property(strong) UIColor *backgroundColor;
@property(weak) UIWindow *window;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (BOOL)isDescendantOfView:(UIView *)view;
@end
@implementation UIView
- (instancetype)init { if((self=[super init])) { _alpha=1;_bounds=CGRectMake(0,0,390,844);_layer=[CALayer layer];_subviews=@[]; }return self; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { return [self.layer convertRect:rect toLayer:view.layer]; }
- (BOOL)isDescendantOfView:(UIView *)view {for(UIView *v=self;v;v=v.superview)if(v==view)return YES;return NO;}
@end
@interface UIVisualEffectView : UIView @end
@implementation UIVisualEffectView @end
@interface UIViewController : NSObject
@property(strong) UIViewController *presentedViewController;
@property(strong) UIView *viewIfLoaded;
@end
@implementation UIViewController @end
@interface UIWindow : UIView
@property BOOL isKeyWindow;
@property CGFloat windowLevel;
@property(strong) UIScreen *screen;
@property(strong) UIViewController *rootViewController;
@end
@implementation UIWindow
- (instancetype)init { if((self=[super init])) { _screen=UIScreen.mainScreen;_rootViewController=[UIViewController new];_rootViewController.viewIfLoaded=[UIView new];_rootViewController.viewIfLoaded.window=self;}return self; }
@end
@interface MyrtleWindow : UIWindow @end
@implementation MyrtleWindow @end
@interface SSScreenshotsWindow : UIWindow @end
@implementation SSScreenshotsWindow @end
@interface SBRecordingIndicatorWindow : UIWindow @end
@implementation SBRecordingIndicatorWindow @end
@interface WallpaperSecureWindow : UIWindow @end
@implementation WallpaperSecureWindow @end
@interface AuthenticationWindow : UIWindow @end
@implementation AuthenticationWindow @end
@interface AuthenticationView : UIView @end
@implementation AuthenticationView @end
'''
preamble+=r"""
@interface UIApplication:NSObject
@property(strong) id frontmost;
+ (instancetype)sharedApplication;
- (id)_frontmostApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication {static UIApplication *app;static dispatch_once_t once;dispatch_once(&once,^{app=[self new];});return app;}
- (id)_frontmostApplication {return self.frontmost;}
@end
@interface TestApplication:NSObject
@property(copy) NSString *bundleIdentifier;
@end
@implementation TestApplication @end
@interface SBHomeScreenWindow:UIWindow @end
@implementation SBHomeScreenWindow @end
@interface SBControlCenterWindow:UIWindow @end
@implementation SBControlCenterWindow @end
@interface SBCoverSheetWindow:UIWindow @end
@implementation SBCoverSheetWindow @end
@interface CSCoverSheetView:UIView
@property(nonatomic,strong) UIView *slideableContentView;
@end
@implementation CSCoverSheetView @end
"""
main=r'''
static void solid(UIView *view) { UIColor *color=[UIColor new];color.CGColor=CGColorCreateGenericRGB(.2,.3,.4,1);view.backgroundColor=color; }
int main(void) { @autoreleasepool {
    BOOL authenticated=NO;
    assert(LMVEasterScopePolicy(YES,0,YES,0,NO,NO,YES,&authenticated)); // desktop
    assert(LMVEasterScopePolicy(YES,0,YES,0,NO,YES,NO,&authenticated)); // CC
    assert(!LMVEasterScopePolicy(YES,0,YES,0,NO,NO,NO,&authenticated)); // app
    assert(!LMVEasterScopePolicy(YES,0,YES,1,NO,YES,YES,&authenticated)); // true lock
    assert(!LMVEasterScopePolicy(YES,1,YES,0,NO,YES,YES,&authenticated)); // blank
    TestApplication *foreground=[TestApplication new];foreground.bundleIdentifier=@"com.apple.mobilesafari";
    UIApplication.sharedApplication.frontmost=foreground;assert(LMVEasterForeground()==-1);
    foreground.bundleIdentifier=@"com.apple.springboard";assert(LMVEasterForeground()==1);
    UIApplication.sharedApplication.frontmost=nil;assert(LMVEasterForeground()==1);
    SBControlCenterWindow *ccWindow=[SBControlCenterWindow new];UIView *ccRoot=ccWindow.rootViewController.viewIfLoaded;
    [ccWindow.layer addSublayer:ccRoot.layer];ccRoot.superview=ccWindow;ccRoot.layer.frame=ccWindow.bounds;
    UIView *ccOverlay=[UIView new];ccOverlay.window=ccWindow;ccOverlay.superview=ccRoot;ccOverlay.layer.frame=ccRoot.bounds;ccOverlay.layer.name=@"VC:CCUIModularControlCenterOverlayViewController";
    [ccRoot.layer addSublayer:ccOverlay.layer];ccRoot.subviews=@[ccOverlay];
    assert(LMVEasterCCWindowExposed(ccWindow));ccOverlay.hidden=YES;assert(!LMVEasterCCWindowExposed(ccWindow));ccOverlay.hidden=NO;
    ccWindow.hidden=YES;assert(!LMVEasterCCWindowExposed(ccWindow));ccWindow.hidden=NO;
    ccOverlay.layer.name=nil;assert(!LMVEasterCCWindowExposed(ccWindow));
    authenticated=NO;
    assert(!LMVEasterNCPolicy(YES,0,YES,1,YES,&authenticated)); // real lock
    assert(!LMVEasterNCPolicy(YES,0,YES,0,YES,&authenticated)); // Face ID on lock screen is still outside NC
    assert(!LMVEasterNCPolicy(YES,0,YES,0,NO,&authenticated)); // desktop learns unlock, still hidden
    assert(authenticated && LMVEasterNCPolicy(YES,0,YES,0,YES,&authenticated)); // NC
    assert(LMVEasterNCPolicy(YES,0,YES,1,YES,&authenticated)); // unlocked pull published lockstate pulse
    assert(!LMVEasterNCPolicy(YES,0,YES,0,NO,&authenticated)); // app/desktop outside NC
    assert(!LMVEasterNCPolicy(YES,1,YES,1,NO,&authenticated)); // blank invalidates auth
    assert(!authenticated && !LMVEasterNCPolicy(YES,0,YES,1,YES,&authenticated)); // wake lock still hidden
    assert(!LMVEasterNCPolicy(NO,0,YES,0,YES,&authenticated));
    assert(!LMVEasterNCPolicy(YES,0,NO,0,YES,&authenticated));
    // A visible window alone is insufficient; its actual content must be exposed.
    SBCoverSheetWindow *coverWindow=[SBCoverSheetWindow new];
    CSCoverSheetView *cover=[CSCoverSheetView new];cover.window=coverWindow;cover.superview=coverWindow;
    [coverWindow.layer addSublayer:cover.layer];cover.layer.frame=coverWindow.bounds;coverWindow.subviews=@[cover];
    UIView *content=[UIView new];content.window=coverWindow;content.superview=cover;content.layer.frame=CGRectMake(0,-844,390,844);
    [cover.layer addSublayer:content.layer];cover.subviews=@[content];cover.slideableContentView=content;
    assert(!LMVEasterNCWindowExposed(coverWindow));
    content.layer.frame=CGRectMake(0,-824,390,844);assert(LMVEasterNCWindowExposed(coverWindow));
    cover.slideableContentView=nil;assert(!LMVEasterNCWindowExposed(coverWindow));cover.slideableContentView=content;
    content.layer.frame=CGRectMake(0,-844,390,844);assert(!LMVEasterNCWindowExposed(coverWindow));
    coverWindow.hidden=YES;assert(!LMVEasterNCWindowExposed(coverWindow));coverWindow.hidden=NO;
    UIWindow *app=[UIWindow new];assert(!LMVEasterNCWindowExposed(app));
    for (UIWindow *window in @[[MyrtleWindow new],[SSScreenshotsWindow new],[SBRecordingIndicatorWindow new]]) {
        window.windowLevel=1500;assert(!LMVEasterBlockingWindow(window,1200));
        UIView *indicator=[UIView new];indicator.bounds=CGRectMake(0,0,60,20);solid(indicator);
        window.rootViewController.viewIfLoaded.subviews=@[indicator];assert(!LMVEasterBlockingWindow(window,1200));
    }
    UIWindow *wall=[WallpaperSecureWindow new]; wall.windowLevel=1500;solid(wall.rootViewController.viewIfLoaded);
    assert(!LMVEasterBlockingWindow(wall,1200));
    UIWindow *emptyAuth=[AuthenticationWindow new];emptyAuth.windowLevel=100;assert(!LMVEasterBlockingWindow(emptyAuth,1200));
    solid(emptyAuth.rootViewController.viewIfLoaded);assert(LMVEasterBlockingWindow(emptyAuth,1200));
    UIWindow *alert=[UIWindow new];alert.windowLevel=2000;solid(alert.rootViewController.viewIfLoaded);
    assert(LMVEasterBlockingWindow(alert,1200));alert.hidden=YES;assert(!LMVEasterBlockingWindow(alert,1200));alert.hidden=NO;
    alert.rootViewController.viewIfLoaded.alpha=0;assert(!LMVEasterBlockingWindow(alert,1200));
    UIWindow *auth=[UIWindow new];auth.windowLevel=100;
    AuthenticationView *view=[AuthenticationView new];view.window=auth;auth.rootViewController.viewIfLoaded=view;
    assert(LMVEasterBlockingWindow(auth,1200));view.hidden=YES;assert(!LMVEasterBlockingWindow(auth,1200));
    puts("PASS: actual NC-only unlock/blank/exposure policy and floating safety: clear persistent Myrtle/screenshot/recording windows and tiny indicators do not block; visible high alert/security branches block; hidden content does not; NOT actual SB compositing");
}return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp)/'windows.m';p.write_text(preamble+helpers+main);binary=Path(tmp)/'windows'
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(p),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=20)
