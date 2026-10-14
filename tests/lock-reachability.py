#!/usr/bin/env python3
"""Run additional production Lock geometry/lease regressions, not device compositing."""
import ast, platform, subprocess, tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1]
h=(r/'LMVLockVideo.h').read_text()
assert 'LMVLockVideoGeometry' in h and 'record.wasExposed' in h
assert 'LMVLockVideoRepaint(node,content)' in h
assert 'self.host.frame=hostFrame' in h and 'entry.baselineHidden' in h
if platform.system()!='Darwin':
    print('PASS source contracts; SKIP native Lock top-band/lease/half-screen execution: requires Apple frameworks')
    raise SystemExit(0)
tree=ast.parse((r/'tests/lock-video-host.py').read_text());pre=''
for node in tree.body:
    if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='pre' for t in node.targets):pre=ast.literal_eval(node.value)
    elif isinstance(node,ast.AugAssign) and isinstance(node.target,ast.Name) and node.target.id=='pre':pre+=ast.literal_eval(node.value)
h=h.replace('LMVDiagnosticsEnabled.load()', 'NO')
production=h[h.index('static BOOL LMVLockVideoRectValid'):]
main=r'''
int main(void){@autoreleasepool{
 SBCoverSheetWindow *window=[SBCoverSheetWindow new];CSCoverSheetView *cover=[CSCoverSheetView new];[window addSubview:cover];
 SBUIBackgroundView *background=[SBUIBackgroundView new];UIView *sliding=[UIView new];UILabel *clock=[UILabel new];
 [cover addSubview:background];[cover addSubview:sliding];[sliding addSubview:clock];cover.slideableContentView=sliding;
 CSCoverSheetViewController *controller=[CSCoverSheetViewController new];controller.viewIfLoaded=cover;window.rootViewController=controller;
 LMVLockControllers=[NSHashTable weakObjectsHashTable];[LMVLockControllers addObject:controller];
 LMVLockVideoManager *m=[LMVLockVideoManager new];m.enabled=YES;m.path=@"movie";m.revision=@"rev";m.screenAllowed=YES;
 [m update];assert(m.playback.wantsPlayback && m.host.superview==cover);
 LMVLockControllerRecord *record=objc_getAssociatedObject(controller,&LMVLockControllerRecordKey);record.lifecycleKnown=YES;record.visible=YES;[m update];
 // False lifecycle disappearance while the same content has genuine half-screen exposure.
 sliding.frame=CGRectMake(0,0,390,422);[m update];record.visible=NO;
 for(int n=0;n<50;n++){[m update];assert(m.playback.wantsPlayback && m.host.superview==cover);}
 assert(!CGPathContainsPoint(m.host.clipLayer.path,NULL,CGPointMake(100,423),NO));
 sliding.frame=CGRectMake(0,-844,390,844);[m update];assert(!m.host.superview && !m.playback.wantsPlayback && !record.wasExposed);
 record.visible=YES;sliding.frame=CGRectMake(0,0,390,844);[m update];
 // Above-sibling capture without descendants must be suppressed continuously.
 Class captureClass=objc_allocateClassPair(UIView.class,"NCMaterialDisplayingCaptureOnlyViewControllerView",0);objc_registerClassPair(captureClass);
 UIView *capture=[captureClass new];[cover addSubview:capture];m.paintLeaseTime=0;[m update];assert(capture.hidden);
 LMVLockVideoPaintLease *lease=m.paintLease;
 for(int n=0;n<50;n++){m.paintLeaseTime=0;[m update];assert(capture.hidden && m.paintLease==lease);}
 [m releasePaint];assert(!capture.hidden);[capture removeFromSuperview];
 // Actual content-owned paint leads by 6 points, unlike unobserved future geometry.
 SBUIBackgroundView *movingBack=[SBUIBackgroundView new];[clock removeFromSuperview];[sliding addSubview:movingBack];[sliding addSubview:clock];
 sliding.frame=CGRectMake(0,6,390,844);movingBack.frame=CGRectMake(0,-6,390,844);
 for(int n=0;n<50;n++){[m update];assert(m.host.superview==sliding && LMVLockVideoContentBackdrop(sliding)==movingBack);
  CGRect local=CGPathGetBoundingBox(m.host.clipLayer.path);CGRect shown=[m.host.layer convertRect:local toLayer:window.layer];
  assert(CGRectGetMinY(shown)<=.01 && CGRectGetMaxY(shown)<=844.01 && m.playback.wantsPlayback);}
 // Unknown content/disable restore original captured background exactly.
 [m suspend];assert(!m.playback.wantsPlayback);[m.host removeFromSuperview];
 puts("PASS production Lock: same-content half-screen false disappearance, no below-panel mask, direct capture sibling/50 stable leases, exposed top paint/50 stable content hosts; not device compositing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'lock.m';binary=Path(tmp)/'lock';src.write_text(pre+production+main)
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)
