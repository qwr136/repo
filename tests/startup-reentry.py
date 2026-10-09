#!/usr/bin/env python3
"""Execute production launch scheduler with Foundation doubles on macOS."""
from pathlib import Path
import platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text()
def function(signature):
    start=s.index(signature+' {'); body=start+len(signature)+1; depth=0
    for i in range(body,len(s)):
        if s[i]=='{': depth+=1
        elif s[i]=='}':
            depth-=1
            if depth==0: return s[start:i+1]
    raise AssertionError(signature)
scheduler=function('static void LMVRequestSafeUpdate(void)')
mark=function('static void LMVMarkLaunchReady(void)')
late=function('static BOOL LMVAlreadyLaunched(UIApplication *app)')
host=function('static void LMVDesktopHostChanged(UIView *view)')
wallpaper=s.split('%hook _SBWallpaperSecureWindow\n',1)[1].split('%end',1)[0]
wallpaper_body=wallpaper.split('- (void)setHidden:(BOOL)hidden {',1)[1].split('\n}',1)[0].replace('%orig;', '(void)hidden;')
window_hook='static void testWallpaperHook(UIView *self, BOOL hidden) {'+wallpaper_body+'\n}'
observer_start=s.index('[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification')
launch_observer=s[observer_start:s.index('}];',observer_start)+3]
updates=function('static void LMVUpdateDesktops(void)')
assert scheduler.index('!LMVLaunchReady') < scheduler.index('dispatch_async') < scheduler.index('LMVRefresh(reload)')
assert 'LMVSafeUpdateApplying' in scheduler and 'LMVSafeUpdatePending' in scheduler
assert updates.index('!LMVLaunchReady') < updates.index('if (!enabled)') < updates.index('LMVDesktopCapture()')
assert 'LMVUpdateDesktop(host, nil)' in updates
assert 'notify_get_state(LMVLockToken, &lockState)' in s
for forbidden in ['SBLockScreenManager','SBWallpaperController','sharedInstance','_sharedInstanceIfExists']:
    assert forbidden not in s, forbidden
for name in ['NCNotificationListCell','SBHomeScreenView','SBHomeScreenWindow','SBHomeScreenViewController','CSCoverSheetViewController','SBFloatingDockWindow','SBFloatingDockView','SBFloatingDockPlatterView','_SBWallpaperSecureWindow','CSCoverSheetView','SBCoverSheetWindow','CoverSheet','PLActionButtonsPresentingView']:
    hook=s.split('%hook '+name+'\n',1)[1].split('%end',1)[0]
    for forbidden in ['LMVUpdate(', 'LMVUpdateDesktops(', 'LMVDesktopCapture(', 'LMVUpdateLockScreen(', 'LMVRefresh(', 'LMVSyncDisplayLink(', 'objc_msgSend']:
        assert forbidden not in hook, (name,forbidden)
    assert hook.count('%orig;') >= 1
for name in ['LMVDesktopHostChanged','LMVLockHostChanged','LMVCoverSheetVisibilityChanged']:
    f=function('static void '+name+'(UIView *view)')
    assert '!LMVInitialized' in f and 'LMVRequestSafeUpdate()' in f
    assert 'LMVDesktopCapture' not in f and 'LMVRefresh(' not in f
ctor=s.split('%ctor {',1)[1]
assert ctor.index('LMVInitialized = YES') < ctor.index('addObserverForName') < ctor.index('%init;')
assert 'UIApplicationDidFinishLaunchingNotification' in ctor
assert 'LMVRefresh(' not in ctor and 'dispatch_after' not in ctor
assert 'UIApplicationStateInactive' in late and 'UISceneActivationStateForegroundActive' in late
if platform.system()!='Darwin':
    print('PASS: startup source contracts; Foundation execution runs in macOS Actions')
    raise SystemExit(0)
preamble=r'''
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#include <assert.h>
// A deterministic main-queue double lets each turn be asserted separately.
static NSMutableArray *queued;
static void enqueue(dispatch_queue_t queue, dispatch_block_t block) { [queued addObject:[block copy]]; }
#define dispatch_async enqueue
static void mainTurn(void) { NSArray *turn=queued.copy; [queued removeAllObjects]; for (dispatch_block_t block in turn) block(); }
@interface UIView : NSObject @end
@implementation UIView @end
@interface SBHomeScreenView : UIView @end
@implementation SBHomeScreenView @end
@interface _SBWallpaperSecureWindow : UIView @end
@implementation _SBWallpaperSecureWindow @end
typedef NS_ENUM(NSInteger, UIApplicationState) { UIApplicationStateActive, UIApplicationStateInactive, UIApplicationStateBackground };
typedef NS_ENUM(NSInteger, UISceneActivationState) { UISceneActivationStateForegroundActive, UISceneActivationStateForegroundInactive, UISceneActivationStateBackground, UISceneActivationStateUnattached };
@interface UIScene : NSObject
@property(nonatomic) UISceneActivationState activationState;
@end
@implementation UIScene @end
@interface UIApplication : NSObject
@property(nonatomic) UIApplicationState applicationState;
@property(nonatomic,strong) NSArray *connectedScenes;
@end
@implementation UIApplication @end
static NSString *UIApplicationDidFinishLaunchingNotification=@"UIApplicationDidFinishLaunchingNotification";
static NSHashTable *LMVCells, *LMVDesktopHosts, *LMVWallpaperWindows;
static void LMVUpdateWallpaperWindows(void) {}
static BOOL LMVInitialized, LMVLaunchReady, LMVSafeUpdatePending, LMVSafeUpdateApplying, LMVPreferencesDirty=YES;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *, NSString *> *LMVPaths;
static NSTimer *LMVDesktopVisibilityTimer;
static NSUInteger policies, singletonCreations, captures, desktopUpdates, retires, depth, maxDepth;
static BOOL insideWallpaperOnce, nestCallback;
static void LMVDesktopHostChanged(UIView *view);
static void LMVUpdateDesktops(void);
static void LMVRetryDiscovery(UIView *view) {}
static void LMVDiagnostic(NSString *event) {}
static id LMVDesktopCapture(void) { assert(!insideWallpaperOnce); captures++; return @"notify-state-snapshot"; }
static void LMVUpdateDesktop(UIView *view, id snapshot) { desktopUpdates++; if(!snapshot) retires++; }
// Test double recreates the original .55 lock manager -> wallpaper once cycle.
static void legacyCreatingLockManager(void) { singletonCreations++; if(insideWallpaperOnce) [NSException raise:@"RecursiveWallpaperOnce" format:@"lock manager requested wallpaper while its once is active"]; }
static void legacyWindowHook(void) { policies++; legacyCreatingLockManager(); }
static void LMVRefresh(BOOL reload) {
    assert(LMVLaunchReady && !insideWallpaperOnce); policies++; depth++; maxDepth=MAX(maxDepth,depth);
    LMVUpdateDesktops();
    if(nestCallback) { nestCallback=NO; LMVDesktopHostChanged([SBHomeScreenView new]); }
    depth--;
}
#define LMVDesktopSnapshot NSObject
'''
tests=r'''
int main(void) { @autoreleasepool {
    queued=[NSMutableArray new]; LMVCells=[NSHashTable weakObjectsHashTable]; LMVDesktopHosts=[NSHashTable weakObjectsHashTable];
    LMVEnabled=[@{@"Desktop":@YES} mutableCopy]; LMVPaths=[@{@"Desktop":@"desktop.mov"} mutableCopy];
    _SBWallpaperSecureWindow *wallpaper=[_SBWallpaperSecureWindow new]; SBHomeScreenView *home=[SBHomeScreenView new];
    // Reproduce the previous synchronous failure without killing the test runner.
    insideWallpaperOnce=YES; BOOL reproduced=NO;
    @try { legacyWindowHook(); } @catch(NSException *e) { reproduced=[e.name isEqual:@"RecursiveWallpaperOnce"]; }
    assert(reproduced && singletonCreations==1);
    policies=singletonCreations=0;
    LMVDesktopHostChanged(home); assert(queued.count==0 && LMVDesktopHosts.count==0);
    LMVInitialized=YES;
    for(int i=0;i<20;i++) { testWallpaperHook(wallpaper, YES); LMVDesktopHostChanged(home); }
    LMVUpdateDesktops(); mainTurn();
    assert(LMVDesktopHosts.count==1 && policies==0 && captures==0 && singletonCreations==0 && queued.count==0);
    insideWallpaperOnce=NO;
    // Register the production observer and publish the actual Foundation event.
    testRegisterLaunchObserver();
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidFinishLaunchingNotification object:nil];
    assert(!LMVLaunchReady && policies==0);
    mainTurn(); assert(LMVLaunchReady && policies==0 && queued.count==1);
    for(int i=0;i<20;i++) LMVDesktopHostChanged(home);
    assert(queued.count==1); nestCallback=YES; mainTurn();
    assert(policies==1 && captures==1 && maxDepth==1 && singletonCreations==0 && queued.count==0);
    // Later window hooks still never execute policy synchronously, and coalesce.
    for(int i=0;i<20;i++) LMVDesktopHostChanged(wallpaper);
    assert(policies==1 && queued.count==1); mainTurn(); assert(policies==2 && queued.count==0);
    // Disabled desktop retires without capture (the .55 path queried regardless).
    LMVEnabled[@"Desktop"]=@NO; NSUInteger oldCaptures=captures; LMVDesktopHostChanged(home); mainTurn();
    assert(captures==oldCaptures && retires==1 && singletonCreations==0);
    // Late injection evidence uses public existing state; inactive is fail-closed.
    UIApplication *app=[UIApplication new]; UIScene *scene=[UIScene new]; app.connectedScenes=@[scene];
    app.applicationState=UIApplicationStateInactive; scene.activationState=UISceneActivationStateForegroundInactive;
    assert(!LMVAlreadyLaunched(app)); scene.activationState=UISceneActivationStateForegroundActive;
    assert(!LMVAlreadyLaunched(app)); app.applicationState=UIApplicationStateActive; assert(LMVAlreadyLaunched(app));
    app.applicationState=UIApplicationStateBackground; scene.activationState=UISceneActivationStateBackground; assert(LMVAlreadyLaunched(app));
    puts("PASS: reproduced .55 recursive startup; actual production launch gate/coalescer/desktop host/update functions defer all policy until launch + next main turn, no singleton creation, runtime coalescing/nested callback max depth 1, disabled no snapshot, late injection scene evidence (Foundation doubles, NOT device safety proof)");
} return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'startup.m'; binary=Path(tmp)/'startup'
    observer='static void testRegisterLaunchObserver(void) {'+launch_observer+'}'
    src.write_text(preamble+scheduler+mark+late+updates+host+window_hook+observer+tests)
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
