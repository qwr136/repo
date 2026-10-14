#!/usr/bin/env python3
"""Actual production NC paint/order/layout tests; not device compositing."""
import ast,platform,subprocess,tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1];h=(r/'LMVLockVideo.h').read_text()
assert 'LMVLockVideoFindAbovePaint' in h and 'LMVLockVideoAboveHostTree' in h
assert 'frame.size.height>.5' in h and 'height>=content.bounds.size.height*0.3' not in h
assert 'LMVLockVideo.paintLeaseDirty=YES;[LMVLockVideo update]' in h
if platform.system()!='Darwin':
 print('PASS NC thin-top capture/ancestor/layout source contracts; SKIP native Foundation/QuartzCore needs macOS')
 raise SystemExit(0)
pre='';tree=ast.parse((r/'tests/lock-video-host.py').read_text())
for node in tree.body:
 if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='pre' for t in node.targets):pre=ast.literal_eval(node.value)
 elif isinstance(node,ast.AugAssign) and isinstance(node.target,ast.Name) and node.target.id=='pre':pre+=ast.literal_eval(node.value)
pre=pre.replace('@interface CSCoverSheetViewController:UIViewController @end','static dispatch_block_t onOriginalLayout;\n@interface CSCoverSheetViewController:UIViewController @end')
pre=pre.replace('@implementation CSCoverSheetViewController @end','@implementation CSCoverSheetViewController\n- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];if(onOriginalLayout)onOriginalLayout();}\n@end')
pre+=r'''
@interface NCMaterialDisplayingCaptureOnlyViewControllerView:UIView @end
@implementation NCMaterialDisplayingCaptureOnlyViewControllerView @end
'''
production=h[h.index('static BOOL LMVLockVideoRectValid'):].replace('LMVDiagnosticsEnabled.load()','NO')
main=r'''
static void assertSystem(UIView *view){for(UIView *child in view.subviews)assert(child.layer.superlayer==view.layer && child.layer.delegate==child);}
int main(void){@autoreleasepool{
 LMVInitialized=YES;LMVLaunchReady=YES;
 SBCoverSheetWindow *window=[SBCoverSheetWindow new];UIView *wrapper=[UIView new];[window addSubview:wrapper];
 CSCoverSheetView *cover=[CSCoverSheetView new];[wrapper addSubview:cover];
 UIView *sliding=[UIView new];SBUIBackgroundView *back=[SBUIBackgroundView new];UILabel *clock=[UILabel new];
 [cover addSubview:sliding];[sliding addSubview:back];[sliding addSubview:clock];cover.slideableContentView=sliding;
 CSCoverSheetViewController *vc=[CSCoverSheetViewController new];vc.viewIfLoaded=cover;window.rootViewController=vc;
 LMVLockControllers=[NSHashTable weakObjectsHashTable];[LMVLockControllers addObject:vc];
 LMVLockVideoManager *m=[LMVLockVideoManager new];m.enabled=YES;m.path=@"movie";m.revision=@"rev";m.screenAllowed=YES;
 LMVLockVideo=m;[m update];assert(m.host.superview==sliding && !m.host.hidden);
 // A four-point wallpaper capture above an ANCESTOR, not our container. 102
 // missed both the thin rectangle and this out-of-container z-order path.
 NCMaterialDisplayingCaptureOnlyViewControllerView *thin=[NCMaterialDisplayingCaptureOnlyViewControllerView new];thin.frame=CGRectMake(0,0,390,4);[wrapper addSubview:thin];
 m.paintLeaseDirty=YES;[m update];assert(thin.hidden && m.paintLease.entries.count==1 && !clock.hidden);
 [m releasePaint];assert(!thin.hidden);
 // A real foreground descendant, however small, forbids suppressing its parent.
 UILabel *text=[UILabel new];[thin addSubview:text];m.paintLeaseDirty=YES;[m update];assert(!thin.hidden && !text.hidden);[text removeFromSuperview];
 // Original layout recreates a capture and restores hidden flags BEFORE our
 // callback. The repair must run before returning, with no queued turn/timer.
 LMVLockVideoInstallHooks();__block UIView *newCapture=nil;
 onOriginalLayout=^{
  thin.hidden=NO;sliding.frame=CGRectMake(0,6,390,838);back.frame=CGRectMake(0,-6,390,844);
  newCapture=[NCMaterialDisplayingCaptureOnlyViewControllerView new];newCapture.frame=CGRectMake(0,0,390,5);[wrapper addSubview:newCapture];
 };
 [vc viewDidLayoutSubviews];assert(vc.layouts==1 && thin.hidden && newCapture.hidden);
 CGRect clip=CGPathGetBoundingBox(m.host.clipLayer.path);CGRect visible=[m.host.layer convertRect:clip toLayer:window.layer];assert(CGRectGetMinY(visible)<=.01);
 onOriginalLayout=nil;
 for(int n=0;n<100;n++){thin.hidden=NO;[vc viewDidLayoutSubviews];assert(thin.hidden && newCapture.hidden && !clock.hidden);assertSystem(wrapper);assertSystem(cover);assertSystem(sliding);}
 // No blind window background removal: unrelated windows and below-host
 // captures are never touched; baselineHidden=YES remains YES on release.
 NCMaterialDisplayingCaptureOnlyViewControllerView *baseline=[NCMaterialDisplayingCaptureOnlyViewControllerView new];baseline.frame=CGRectMake(0,0,390,3);baseline.hidden=YES;[wrapper addSubview:baseline];m.paintLeaseDirty=YES;[m update];
 UIWindow *other=[UIWindow new];UIView *foreign=[NCMaterialDisplayingCaptureOnlyViewControllerView new];[other addSubview:foreign];
 [m suspend];assert(!thin.hidden && !newCapture.hidden && baseline.hidden && !foreign.hidden && !clock.hidden);
 m.screenAllowed=YES;m.enabled=YES;[m update];assert(thin.hidden);sliding.frame=CGRectMake(0,-844,390,844);[m update];assert(!m.host.superview && !thin.hidden && !newCapture.hidden);
 m.enabled=NO;[m update];assert(!thin.hidden && !foreign.hidden);
 LMVLockVideo=nil;[m suspend];
 puts("PASS production NC: thin top capture/ancestor paint rejection-safe lease, after-original same-transaction mask+new capture repair,100 system redraws,foreground protection,baseline/offscreen/disable/scope restore; not device compositing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 src=Path(tmp)/'top.m';binary=Path(tmp)/'top';src.write_text(pre+production+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(src),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
