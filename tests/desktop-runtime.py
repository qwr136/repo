#!/usr/bin/env python3
"""Execute actual desktop update and player detach functions with Foundation layer doubles."""
from pathlib import Path
import platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'Tweak.xm').read_text()
update=s.split('static void LMVUpdateDesktop(UIView *host) {',1)[1].split('static void LMVUpdateDesktops',1)[0]
update='static void LMVUpdateDesktop(UIView *host) {'+update
release='static void LMVReleasePlayer(LMVVideoState *state) {'+s.split('static void LMVReleasePlayer(LMVVideoState *state) {',1)[1].split('static void LMVPrepareAssets',1)[0]
# Desktop release and global decoder stops must have no layer visibility/content mutations.
release_desktop=s.split('static void LMVReleaseDesktopSource(LMVVideoState *state) {',1)[1].split('static void LMVUpdateDesktop',1)[0]
for forbidden in ['removeFromSuperlayer', 'layer.hidden', 'layer.contents']:
    assert forbidden not in release_desktop
assert '[state.layer removeFromSuperlayer]' in update  # Only disable/path/revision replacement.
assert update.count('[state.layer removeFromSuperlayer]')==1
assert 'LMVDesktopShouldAttach(state.layer.superlayer == host.layer)' in update
assert '%hook UIView' not in s and '%hook SBFloatingDock' not in s and '%hook SBIconContentView' not in s
for forbidden in ['StackShadow', 'NCNotificationListStackDimmingOverlayView', 'stackShadowOpacity']:
    assert forbidden not in s
    assert forbidden not in (r/'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
if platform.system()!='Darwin':
    print('PASS: desktop integration source constraints; Foundation execution requires macOS Actions')
    raise SystemExit(0)
preamble=r'''
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <assert.h>
#include "LMVConsumerPolicy.h"
static NSString *kCAGravityResizeAspectFill=@"aspectFill";
@interface CALayer : NSObject
@property(nonatomic,weak) CALayer *superlayer;
@property(nonatomic,strong) id contents;
@property(nonatomic,copy) NSString *name;
@property(nonatomic,copy) NSString *contentsGravity;
@property(nonatomic) BOOL masksToBounds, hidden;
@property(nonatomic) CGRect frame;
@property(nonatomic) NSUInteger inserts, removes;
@property(nonatomic,strong) NSMutableArray *children;
+ (instancetype)layer;
- (void)removeFromSuperlayer;
- (void)insertSublayer:(CALayer *)child atIndex:(unsigned)index;
- (void)insertSublayer:(CALayer *)child above:(CALayer *)other;
@end
@implementation CALayer
+ (instancetype)layer { return [self new]; }
- (instancetype)init { if((self=[super init])) _children=[NSMutableArray new]; return self; }
- (void)removeFromSuperlayer { _removes++; [self.superlayer.children removeObject:self]; self.superlayer=nil; }
- (void)insertSublayer:(CALayer *)child atIndex:(unsigned)index { _inserts++; child.superlayer=self; [self.children insertObject:child atIndex:MIN(index,self.children.count)]; }
- (void)insertSublayer:(CALayer *)child above:(CALayer *)other { [self insertSublayer:child atIndex:0]; }
@end
@interface UIView : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,strong) NSArray *subviews;
@property(nonatomic) CGRect bounds;
@property(nonatomic) BOOL hidden;
@property(nonatomic) double alpha;
@end
@implementation UIView
- (instancetype)init { if((self=[super init])) { _layer=[CALayer layer]; _subviews=@[]; _alpha=1; } return self; }
@end
@interface SBHomeScreenView : UIView @end
@implementation SBHomeScreenView @end
@interface CATransaction : NSObject
+ (void)begin; + (void)commit; + (void)setDisableActions:(BOOL)disabled;
@end
@implementation CATransaction
+ (void)begin {} + (void)commit {} + (void)setDisableActions:(BOOL)disabled {}
@end
@interface LMVSharedSource : NSObject
@property(nonatomic) const void *lastImage;
@property(nonatomic) BOOL playing;
@end
@implementation LMVSharedSource @end
@interface LMVVideoState : NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,weak) UIView *host;
@property(nonatomic,copy) NSString *path, *revision;
@property(nonatomic,strong) LMVSharedSource *source;
@property(nonatomic) BOOL active;
@end
@implementation LMVVideoState @end
@interface LMVFrameSnapshot : NSObject
@property(nonatomic) const void *image;
@end
@implementation LMVFrameSnapshot @end
static char LMVDesktopStateKey;
static NSMutableDictionary<NSString *, NSString *> *LMVPaths, *LMVRevisions;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *, LMVSharedSource *> *LMVSharedSources;
static NSMutableSet *LMVReadyAssets;
static LMVDesktopDecision testDecision;
static NSUInteger acquired,released;
static LMVDesktopDecision LMVDesktopHostDecision(UIView *host) { return testDecision; }
static void LMVDesktopDiagnostics(UIView *host, LMVDesktopDecision decision) {}
static BOOL LMVBranchHasWallpaper(UIView *view, NSUInteger depth) { return NO; }
static LMVFrameSnapshot *LMVCachedFrame(NSString *path, NSString *revision) { return nil; }
static LMVSharedSource *LMVSourceForPath(NSString *path) { acquired++; LMVSharedSource *source=[LMVSharedSource new]; LMVSharedSources[path]=source; return source; }
static BOOL LMVSourceHasConsumer(LMVSharedSource *source) { return NO; }
static void LMVStopSource(LMVSharedSource *source) { source.playing=NO; }
static void LMVDiagnostic(NSString *event) {}
'''
helpers='static void LMVReleaseDesktopSource(LMVVideoState *state) { released++; LMVReleasePlayer(state); }\n'
tests=r'''
int main(void) { @autoreleasepool {
    LMVPaths=[@{@"Desktop":@"desktop.mov"} mutableCopy]; LMVEnabled=[@{@"Desktop":@YES} mutableCopy];
    LMVRevisions=[@{@"desktop.mov":@"revision1"} mutableCopy]; LMVSharedSources=[NSMutableDictionary new];
    LMVReadyAssets=[NSMutableSet setWithObject:@"desktop.mov"];
    SBHomeScreenView *host=[SBHomeScreenView new]; host.bounds=(CGRect){0,0,390,844};
    UIView *dock=[UIView new], *unrelated=[UIView new]; dock.alpha=.37; unrelated.hidden=YES;
    CALayer *systemLayer=dock.layer; [host.layer.children addObject:systemLayer];
    testDecision=LMVDesktopDecide(1,1,1,1,1,1,0,LMVForegroundHome,0,0);
    LMVUpdateDesktop(host);
    LMVVideoState *state=objc_getAssociatedObject(host,&LMVDesktopStateKey);
    assert(state.active && acquired==1 && state.layer.superlayer==host.layer);
    state.layer.contents=@"last-real-frame";
    NSUInteger inserts=host.layer.inserts, removes=state.layer.removes;
    for(int phase=0;phase<5;phase++) {
        // Fully open NC; long press; transient unknown; app; invisible parent during animation.
        testDecision=LMVDesktopDecide(1,1,1,phase!=4,1,1,0,
            phase==2?LMVForegroundUnknown:phase==3?LMVForegroundApp:LMVForegroundHome,phase==0,phase==1);
        for(int repeat=0;repeat<20;repeat++) LMVUpdateDesktop(host);
        assert(!state.active && !state.source && !state.layer.hidden);
        assert([state.layer.contents isEqual:@"last-real-frame"] && state.layer.superlayer==host.layer);
        assert(host.layer.inserts==inserts && state.layer.removes==removes && acquired==1);
        assert(dock.alpha==.37 && !dock.hidden && unrelated.hidden && unrelated.alpha==1);
        assert([host.layer.children containsObject:systemLayer]);
    }
    testDecision=LMVDesktopDecide(1,1,1,1,1,1,0,LMVForegroundHome,0,0);
    LMVUpdateDesktop(host); assert(state.active && acquired==2 && !state.layer.hidden);
    testDecision=LMVDesktopDecide(1,1,1,1,1,1,1,LMVForegroundHome,0,0);
    LMVUpdateDesktop(host); assert(!state.active && state.layer.hidden && [state.layer.contents isEqual:@"last-real-frame"]);
    LMVEnabled[@"Desktop"]=@NO; LMVUpdateDesktop(host);
    assert(!objc_getAssociatedObject(host,&LMVDesktopStateKey) && !state.layer.superlayer);
    assert([host.layer.children containsObject:systemLayer] && dock.alpha==.37);
    puts("PASS: actual desktop update/player detach; 100 paused NC/menu/app/unknown/hidden-parent updates retain frame and layer order; lock hides; disable removes only owned layer; Dock/unrelated views unchanged");
} return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'desktop.m'; binary=Path(tmp)/'desktop'
    src.write_text(preamble+release+helpers+update+tests)
    subprocess.run(['clang','-fobjc-arc','-I',str(r),'-framework','Foundation',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
