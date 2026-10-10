#!/usr/bin/env python3
"""Execute the retained launch coalescer against remaining notification visibility hooks."""
from pathlib import Path
import platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1];s=(r/'Tweak.xm').read_text()
def function(signature):
    start=s.index(signature+' {');depth=0
    for pos in range(start+len(signature),len(s)):
        if s[pos]=='{':depth+=1
        elif s[pos]=='}':
            depth-=1
            if not depth:return s[start:pos+1]
    raise AssertionError(signature)
scheduler=function('static void LMVRequestSafeUpdate(void)')
mark=function('static void LMVMarkLaunchReady(void)')
late=function('static BOOL LMVAlreadyLaunched(UIApplication *app)')
cover=function('static void LMVCoverSheetVisibilityChanged(UIView *view)')
assert scheduler.index('!LMVLaunchReady')<scheduler.index('dispatch_async')<scheduler.index('LMVRefresh(reload)')
assert 'LMVSafeUpdateApplying' in scheduler and 'LMVSafeUpdatePending' in scheduler
assert 'LMVDesktop' not in s and 'LMVUpdateLockScreen' not in s
for name in ['NCNotificationListCell','SBCoverSheetWindow','CoverSheet','PLActionButtonsPresentingView']:
    hook=s.split('%hook '+name+'\n',1)[1].split('%end',1)[0]
    for forbidden in ['LMVUpdate(', 'LMVUpdateLockScreen(', 'LMVRefresh(', 'LMVSyncDisplayLink(', 'objc_msgSend']:
        assert forbidden not in hook,(name,forbidden)
    assert '%orig;' in hook
ctor=s.split('%ctor {',1)[1]
assert ctor.index('LMVInitialized = YES')<ctor.index('addObserverForName')<ctor.index('%init;')
assert 'LMVRefresh(' not in ctor and 'dispatch_after' not in ctor
assert 'UIApplicationDidFinishLaunchingNotification' in ctor
if platform.system()!='Darwin':
    print('PASS: lock-only startup scheduling; actual Foundation coalescer runs on macOS CI')
    raise SystemExit(0)
pre=r'''
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <objc/runtime.h>
#include <assert.h>
static NSMutableArray *queued;
static void enqueue(dispatch_queue_t queue,dispatch_block_t block){[queued addObject:[block copy]];}
#define dispatch_async enqueue
static void mainTurn(void){NSArray *turn=queued.copy;[queued removeAllObjects];for(dispatch_block_t block in turn)block();}
@interface UIView:NSObject @end
@implementation UIView @end
@interface UIApplication:NSObject
@property(nonatomic) NSInteger applicationState;
@property(nonatomic,strong) NSArray *connectedScenes;
@end
@implementation UIApplication @end
@interface UIScene:NSObject
@property(nonatomic) NSInteger activationState;
@end
@implementation UIScene @end
static const NSInteger UIApplicationStateInactive=1;
static const NSInteger UISceneActivationStateForegroundActive=0,UISceneActivationStateBackground=2;
static BOOL LMVInitialized,LMVLaunchReady,LMVSafeUpdatePending,LMVSafeUpdateApplying,LMVPreferencesDirty=YES;
static NSHashTable *LMVCells;
static NSUInteger policies,depth,maxDepth,retries;
static BOOL nest;
static void LMVCoverSheetVisibilityChanged(UIView *view);
static void LMVRetryDiscovery(UIView *view){retries++;}
@interface LMVEasterDouble:NSObject
- (void)refresh;
@end
@implementation LMVEasterDouble
- (void)refresh {}
@end
static LMVEasterDouble *LMVEaster;
static void LMVRefresh(BOOL reload){
 assert(LMVLaunchReady);policies++;depth++;maxDepth=MAX(depth,maxDepth);
 if(nest){nest=NO;LMVCoverSheetVisibilityChanged([UIView new]);}
 depth--;
}
'''
main=r'''
int main(void){@autoreleasepool{
 queued=[NSMutableArray new];LMVCells=[NSHashTable weakObjectsHashTable];
 UIView *host=[UIView new];UIView *cell=[UIView new];[LMVCells addObject:cell];
 LMVCoverSheetVisibilityChanged(host);assert(!queued.count);
 LMVInitialized=YES;
 for(int n=0;n<50;n++)LMVCoverSheetVisibilityChanged(host);
 assert(!queued.count && !policies);
 LMVMarkLaunchReady();assert(LMVLaunchReady && queued.count==1 && !policies);
 for(int n=0;n<50;n++)LMVCoverSheetVisibilityChanged(host);
 assert(queued.count==1);nest=YES;mainTurn();assert(policies==1 && maxDepth==1 && !queued.count && retries==1);
 for(int n=0;n<50;n++)LMVCoverSheetVisibilityChanged(host);
 assert(policies==1 && queued.count==1);mainTurn();assert(policies==2 && !queued.count);
 LMVPreferencesDirty=YES;LMVRequestSafeUpdate();mainTurn();assert(policies==3 && !LMVPreferencesDirty);
 UIApplication *app=[UIApplication new];UIScene *scene=[UIScene new];app.connectedScenes=@[scene];
 app.applicationState=UIApplicationStateInactive;scene.activationState=UISceneActivationStateForegroundActive;assert(!LMVAlreadyLaunched(app));
 app.applicationState=0;assert(LMVAlreadyLaunched(app));app.applicationState=2;scene.activationState=UISceneActivationStateBackground;assert(LMVAlreadyLaunched(app));
 puts("PASS: actual notification/CoverSheet launch scheduler, 50-call coalescing, delayed policy until readiness, nonrecursive nested updates, preference reload, existing app scene evidence; no UIKit device claim");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'startup.m';out=Path(tmp)/'startup';src.write_text(pre+scheduler+mark+late+cover+main)
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(src),'-o',str(out)],check=True)
    subprocess.run([str(out)],check=True,timeout=30)
