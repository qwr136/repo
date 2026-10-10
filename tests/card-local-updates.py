from pathlib import Path
import platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1];s=(r/'Tweak.xm').read_text()
queue=(r/'LMVCardUpdates.h').read_text();maintenance=(r/'LMVCardMaintenance.h').read_text()
assert 'LMVRefresh(' not in queue and 'LMVRequestCardUpdate((UIView *)self,NO)' in s
assert 'messageEligible && ![hosts objectForKey:@"Message"]' in s
assert 'LMVCardNeedsUpdate(cell,now)' in s and 'lastDiscovery=0' not in s
assert 'LMVDiagnosticsEnabled.load()' in s
if platform.system()!='Darwin':
 print('PASS: scoped card batching/cache contracts; Foundation production queue/maintenance/retry execution runs in macOS CI')
 raise SystemExit(0)
def function(signature):
 a=s.index(signature+' {');depth=0
 for n in range(a+len(signature),len(s)):
  if s[n]=='{':depth+=1
  elif s[n]=='}':
   depth-=1
   if not depth:return s[a:n+1]
 raise AssertionError(signature)
ready=function('static BOOL LMVCardHostsReady(UIView *cell)')
retry=function('static void LMVRetryDiscovery(UIView *cell)')
pre=r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>
#include <assert.h>
static NSMutableArray *turns,*delayed;
static void enqueue(dispatch_queue_t queue,dispatch_block_t block){[turns addObject:[block copy]];}
static void defer(dispatch_time_t when,dispatch_queue_t queue,dispatch_block_t block){[delayed addObject:[block copy]];}
#define dispatch_async enqueue
#define dispatch_after defer
static void turn(void){NSArray *batch=turns.copy;[turns removeAllObjects];for(dispatch_block_t b in batch)b();}
@interface UIView:NSObject
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,strong) id window;
@property CGRect frame,bounds;
- (BOOL)isDescendantOfView:(UIView *)view;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
@end
@implementation UIView
- (BOOL)isDescendantOfView:(UIView *)view {for(UIView *p=self;p;p=p.superview)if(p==view)return YES;return NO;}
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view {return CGRectOffset(rect,self.frame.origin.x,self.frame.origin.y);}
@end
@interface NCNotificationListCell:UIView @end
@implementation NCNotificationListCell @end
@interface LMVVideoState:NSObject
@property(strong) UIView *overlay;
@property(weak) UIView *anchor,*host;
@property(copy) NSString *path,*revision;
@property BOOL active;
@property(strong) id source;
@end
@implementation LMVVideoState @end
static BOOL LMVInitialized,LMVLaunchReady,LMVPreferencesDirty,LMVSafeUpdateApplying;
static char LMVStatesKey,LMVHostsKey,LMVDiscoveryKey,LMVRetryKey,LMVMaintenanceKey;
static NSHashTable *LMVCells;
static NSDictionary<NSString *,NSNumber *> *LMVEnabled;
static NSDictionary<NSString *,NSString *> *LMVPaths,*LMVRevisions;
static NSUInteger updated,retried,globalRequests;
static NSMutableArray *updatedOwners;
static NSArray *LMVTargets(void){return @[@"Message",@"Options",@"Clear"];}
static BOOL LMVMessageCell(UIView *v){return [v isKindOfClass:NCNotificationListCell.class];}
static BOOL LMVPlaybackAllowed(void){return YES;}
static void LMVUpdate(UIView *v){updated++;[updatedOwners addObject:v];}
static void LMVRequestSafeUpdate(void){globalRequests++;}
static void LMVRetryDiscovery(UIView *cell);
'''
main=r'''
int main(void){@autoreleasepool{
 turns=[NSMutableArray new];delayed=[NSMutableArray new];updatedOwners=[NSMutableArray new];LMVCells=[NSHashTable weakObjectsHashTable];
 LMVEnabled=@{@"Message":@YES};LMVPaths=@{@"Message":@"movie"};LMVRevisions=@{@"movie":@"rev"};
 NCNotificationListCell *a=[NCNotificationListCell new],*b=[NCNotificationListCell new];
 // Prelaunch requests are remembered without policy execution.
 LMVInitialized=YES;for(int n=0;n<50;n++)LMVRequestCardUpdate(a,NO);assert(!turns.count && !updated);
 LMVLaunchReady=YES;LMVScheduleCardUpdates();assert(turns.count==1);
 for(int n=0;n<50;n++)LMVRequestCardUpdate(a,NO);turn();assert(updated==1 && updatedOwners.firstObject==a && !globalRequests);
 // Card + its action presenter in the same turn still update owner once.
 UIView *presenter=[UIView new];presenter.superview=a;
 updated=0;[updatedOwners removeAllObjects];LMVRequestCardUpdate(a,NO);LMVRequestCardUpdate(presenter,YES);LMVRequestCardUpdate(b,NO);turn();
 assert(updated==2 && [updatedOwners containsObject:a] && [updatedOwners containsObject:b]);
 // Reused card cancels pending local work. Pref changes use the global path.
 updated=0;LMVRequestCardUpdate(a,NO);LMVForgetCardUpdate(a);turn();assert(!updated);
 LMVPreferencesDirty=YES;LMVRequestCardUpdate(a,NO);turn();assert(globalRequests==1 && !updated);LMVPreferencesDirty=NO;[LMVDirtyCards removeAllObjects];
 // Stable host needs no full pass at 30/100/200/500ms. Geometry/identity,
 // missing source, file revision and one-second maintenance still refresh.
 UIView *host=[UIView new],*anchor=[UIView new],*overlay=[UIView new];host.superview=a;anchor.superview=host;overlay.superview=host;
 anchor.frame=CGRectMake(10,20,100,60);anchor.bounds=CGRectMake(0,0,100,60);overlay.frame=anchor.frame;
 LMVVideoState *state=[LMVVideoState new];state.host=host;state.anchor=anchor;state.overlay=overlay;state.path=@"movie";state.revision=@"rev";state.active=YES;state.source=[NSObject new];
 objc_setAssociatedObject(a,&LMVStatesKey,@{@"Message":state},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 objc_setAssociatedObject(a,&LMVMaintenanceKey,@10,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 assert(!LMVCardNeedsUpdate(a,10.03) && !LMVCardNeedsUpdate(a,10.2) && !LMVCardNeedsUpdate(a,10.9));assert(LMVCardNeedsUpdate(a,11));
 anchor.frame=CGRectOffset(anchor.frame,1,0);assert(LMVCardNeedsUpdate(a,10.1));anchor.frame=overlay.frame;
 state.source=nil;assert(LMVCardNeedsUpdate(a,10.1));state.source=[NSObject new];
 LMVRevisions=@{@"movie":@"new"};assert(LMVCardNeedsUpdate(a,10.1));LMVRevisions=@{@"movie":@"rev"};
 anchor.superview=nil;assert(LMVCardNeedsUpdate(a,10.1));anchor.superview=host;
 // Missing-host retries stop immediately on successful discovery and obsolete
 // bindings cannot update a reused card.
 [delayed removeAllObjects];objc_setAssociatedObject(a,&LMVRetryKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
 NSMapTable *hosts=[NSMapTable strongToStrongObjectsMapTable];[hosts setObject:anchor forKey:@"Message"];
 objc_setAssociatedObject(a,&LMVHostsKey,hosts,OBJC_ASSOCIATION_RETAIN_NONATOMIC);LMVRetryDiscovery(a);assert(!delayed.count);
 [hosts removeObjectForKey:@"Message"];a.window=[NSObject new];LMVRetryDiscovery(a);assert(delayed.count==4);
 NSArray *callbacks=delayed.copy;[hosts setObject:anchor forKey:@"Message"];updated=0;for(dispatch_block_t callback in callbacks)callback();assert(!updated);
 [hosts removeObjectForKey:@"Message"];[delayed removeAllObjects];LMVRetryDiscovery(a);assert(delayed.count==4);callbacks=delayed.copy;
 objc_setAssociatedObject(a,&LMVRetryKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);for(dispatch_block_t callback in callbacks)callback();assert(!updated);
 puts("PASS: actual local card queue/maintenance/retry: 50 layouts coalesce once, owners deduplicated, reuse/global preference isolation, stable frames skip full updates, geometry/source/revision invalidation, one-second maintenance, ready-host and stale-binding retry cancellation; no device timing claim");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'cards.m';binary=Path(tmp)/'cards';source.write_text('\n'.join([pre,ready,retry,queue,maintenance,main]))
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','CoreGraphics',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
