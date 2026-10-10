#!/usr/bin/env python3
"""Run production floating-window predicates with Foundation/real CALayer doubles."""
from pathlib import Path
import platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'LMVEasterOverlay.h').read_text()
helpers=s[s.index('static BOOL LMVEasterSecurityName('):s.index('static void LMVEasterDarwin(')]
if platform.system()!='Darwin':
    assert 'window.windowLevel >= UIWindowLevelAlert && substantive' in helpers and 'area/full>=0.30' in helpers
    print('PASS: content-based floating window contracts; native predicates run in macOS CI')
    raise SystemExit(0)
preamble=r'''
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>
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
@property CGFloat alpha;
@property CGRect bounds;
@property(strong) CALayer *layer;
@property(strong) NSArray *subviews;
@property(strong) UIColor *backgroundColor;
@property(weak) UIWindow *window;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
@end
@implementation UIView
- (instancetype)init { if((self=[super init])) { _alpha=1;_bounds=CGRectMake(0,0,390,844);_layer=[CALayer layer];_subviews=@[]; }return self; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { return rect; }
@end
@interface UIVisualEffectView : UIView @end
@implementation UIVisualEffectView @end
@interface UIViewController : NSObject
@property(strong) UIViewController *presentedViewController;
@property(strong) UIView *viewIfLoaded;
@end
@implementation UIViewController @end
@interface UIWindow : UIView
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
main=r'''
static void solid(UIView *view) { UIColor *color=[UIColor new];color.CGColor=CGColorCreateGenericRGB(.2,.3,.4,1);view.backgroundColor=color; }
int main(void) { @autoreleasepool {
    assert(LMVEasterScreenAllowsOverlay(YES,0)); // locked and NC stay visible
    assert(!LMVEasterScreenAllowsOverlay(YES,1)); // actual screen off
    assert(!LMVEasterScreenAllowsOverlay(NO,0)); // unknown screen state
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
    puts("PASS: actual floating policy: clear persistent Myrtle/screenshot/recording windows and tiny indicators do not block; visible high alert/security branches block; hidden content does not; NOT actual SB compositing");
}return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    p=Path(tmp)/'windows.m';p.write_text(preamble+helpers+main);binary=Path(tmp)/'windows'
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(p),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=20)
