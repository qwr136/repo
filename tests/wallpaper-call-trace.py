from pathlib import Path
import platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LMVWallpaperCallTrace.h').read_text(); s=(r/'Tweak.xm').read_text()
assert 'LMVTraceSignatureMatches' in h and 'class_addMethod' in h and 'method_setImplementation' in h
assert 'ns_returns_retained' in h and 'NSInteger *a, NSInteger b, id c' in h
for forbidden in ['setHidden:','setAlpha:','removeFromSuperview','UIImage image','fileContents','valueForKey','MSHookFunction']:
 assert forbidden not in h,forbidden
assert 'wallpaper-call.log' in s and 'traceRecords > 1800' in s and '262144' in s
assert 'LMVStartWallpaperTraceReports();' in s
if platform.system()!='Darwin':
 print('PASS: typed/pass-through trace contracts; runtime installation tests run on macOS CI')
 raise SystemExit(0)
preamble=r'''
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <atomic>
#include <assert.h>
static BOOL testEnabled=YES;
static NSMutableArray<NSString *> *events;
#define LMV_TRACE_TEST 1
#define LMVTraceEnabled() testEnabled
#define LMVTraceLog(...) [events addObject:(__VA_ARGS__)]
static unsigned getterCalls,updateCalls,pointerCalls,voidCalls,newCalls;
static id lastA,lastB,lastC;
@interface PBUIPosterViewController:NSObject
- (id)requireWallpaperWithReason:(id)reason;
@end
@implementation PBUIPosterViewController
- (id)requireWallpaperWithReason:(id)reason {getterCalls++;return reason;}
@end
@interface PBUIPosterWallpaperViewController:PBUIPosterViewController
- (double)triggerSceneUpdate; // Intentional mismatch: must remain untouched.
@end
@implementation PBUIPosterWallpaperViewController
- (double)triggerSceneUpdate {return 2.75;}
@end
@interface PBUIPosterWallpaperRemoteViewController:PBUIPosterWallpaperViewController
- (id)newImageProviderView;
- (BOOL)updateImageProviderView:(id)view withImage:(id)image;
- (id)imageForWallpaperStyle:(inout NSInteger *)style variant:(NSInteger)variant traitCollection:(id)traits;
@end
@implementation PBUIPosterWallpaperRemoteViewController
- (id)newImageProviderView {newCalls++;return [NSObject new];}
- (BOOL)updateImageProviderView:(id)view withImage:(id)image {updateCalls++;lastA=view;lastB=image;return view==image;}
- (id)imageForWallpaperStyle:(inout NSInteger *)style variant:(NSInteger)variant traitCollection:(id)traits {pointerCalls++;lastC=traits;if(style)*style+=variant;return traits;}
@end
@interface PBUIPosterVariantViewController:NSObject
- (void)sceneLayerManagerDidUpdateLayers:(id)manager;
- (void)scene:(id)scene didCompleteUpdateWithContext:(id)context error:(id)error;
@end
@implementation PBUIPosterVariantViewController
- (void)sceneLayerManagerDidUpdateLayers:(id)manager {voidCalls++;lastA=manager;}
- (void)scene:(id)scene didCompleteUpdateWithContext:(id)context error:(id)error {voidCalls++;lastA=scene;lastB=context;lastC=error;}
@end
@interface PBUIPosterLockViewController:PBUIPosterVariantViewController @end
@implementation PBUIPosterLockViewController @end
'''
tests=r'''
int main(void) {@autoreleasepool {
 events=[NSMutableArray new];
 LMVInstallWallpaperTrace(); LMVReportWallpaperTrace();
 assert(LMVTraceSpecs[0].original && LMVTraceSpecs[1].original && LMVTraceSpecs[2].original);
 Method method=class_getInstanceMethod(PBUIPosterWallpaperRemoteViewController.class,@selector(newImageProviderView));
 assert(method_getImplementation(method)==LMVTraceSpecs[0].replacement);
 NSUInteger mismatches=0;
 for(NSUInteger i=0;i<LMVTraceCount;i++) if(!strcmp(LMVTraceSpecs[i].selectorName,"triggerSceneUpdate") && !strcmp(LMVTraceSpecs[i].className,"PBUIPosterWallpaperViewController")) {
  assert(!LMVTraceSpecs[i].original && !strcmp(LMVTraceSpecs[i].status,"signature-mismatch"));mismatches++;
 }
 assert(mismatches==1);
 PBUIPosterWallpaperRemoteViewController *remote=[PBUIPosterWallpaperRemoteViewController new];
 NSObject *value=[NSObject new],*different=[NSObject new];
 assert([remote requireWallpaperWithReason:value]==value && getterCalls==1);
 assert([remote updateImageProviderView:value withImage:value] && updateCalls==1 && lastA==value && lastB==value);
 assert(![remote updateImageProviderView:value withImage:different] && updateCalls==2);
 NSInteger style=4;
 assert([remote imageForWallpaperStyle:&style variant:7 traitCollection:value]==value && style==11 && pointerCalls==1 && lastC==value);
 assert([remote imageForWallpaperStyle:NULL variant:8 traitCollection:nil]==nil && pointerCalls==2);
 assert([remote triggerSceneUpdate]==2.75);
 PBUIPosterWallpaperViewController *parent=[PBUIPosterWallpaperViewController new];
 assert([parent requireWallpaperWithReason:different]==different && getterCalls==2);
 PBUIPosterLockViewController *lock=[PBUIPosterLockViewController new];
 [lock sceneLayerManagerDidUpdateLayers:value];
 [lock scene:value didCompleteUpdateWithContext:different error:nil];
 assert(voidCalls==2 && lastA==value && lastB==different && lastC==nil);
 __weak id weak;
 @autoreleasepool {id fresh=[remote newImageProviderView];weak=fresh;assert(fresh && newCalls==1);}
 assert(!weak); // +1 new-method ownership must not leak or over-release.
 NSUInteger before=events.count;testEnabled=NO;
 assert([remote updateImageProviderView:value withImage:value]);assert(events.count==before && updateCalls==3);
 testEnabled=YES;
 for(int i=0;i<40;i++) assert([remote updateImageProviderView:value withImage:value]);
 assert(LMVTraceSpecs[1].hits.load()==42 && LMVTraceSpecs[1].emitted.load()==42);
 unsigned long count=LMVTraceSpecs[1].hits.load();
 LMVInstallWallpaperTrace();assert(LMVTraceSpecs[1].hits.load()==count);
 assert([remote requireWallpaperWithReason:value]==value && getterCalls==3);
 BOOL sawClass=NO,sawStack=NO,sawReturn=NO;
 for(NSString *event in events) {
  if([event containsString:@"class=PBUIPosterLockViewController"])sawClass=YES;
  if([event hasPrefix:@"wallpaper-call stack"])sawStack=YES;
  if([event hasPrefix:@"wallpaper-call return"])sawReturn=YES;
 }
 assert(sawClass && sawStack && sawReturn);
 puts("PASS: production typed IMP hooks installed, inherited methods isolated, originals called once, pointer/BOOL/id/void/new ownership preserved, mismatch skipped, off switch and rate limit honored; NOT device hook-hit proof");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'trace.mm';binary=Path(tmp)/'trace'
 source.write_text(preamble+h+tests)
 subprocess.run(['clang++','-std=c++11','-fobjc-arc','-framework','Foundation','-framework','QuartzCore',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
