#!/usr/bin/env python3
"""Actual attached manager/mask follows parent between geometry callbacks."""
import ast,platform,subprocess,tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1];h=(r/'LMVLockVideo.h').read_text()
assert 'LMVLockVideoAttachedGeometry' in h and 'lock-actualgeometry' in h
assert 'if(visible)panelAttached=LMVLockVideoAttachedGeometry' in h
if platform.system()!='Darwin':
 print('PASS attached full-paint source contracts; SKIP real CA motion execution needs macOS');raise SystemExit(0)
pre='';tree=ast.parse((r/'tests/lock-video-host.py').read_text())
for n in tree.body:
 if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='pre' for t in n.targets):pre=ast.literal_eval(n.value)
 elif isinstance(n,ast.AugAssign) and isinstance(n.target,ast.Name) and n.target.id=='pre':pre+=ast.literal_eval(n.value)
production=h[h.index('static BOOL LMVLockVideoRectValid'):].replace('LMVDiagnosticsEnabled.load()','NO')
main=r'''
int main(void){@autoreleasepool{
 SBCoverSheetWindow *w=[SBCoverSheetWindow new];CSCoverSheetView *panel=[CSCoverSheetView new];[w addSubview:panel];
 UIView *s=[UIView new];[panel addSubview:s];SBUIBackgroundView *back=[SBUIBackgroundView new];[s addSubview:back];UILabel *clock=[UILabel new];[s addSubview:clock];panel.slideableContentView=s;
 CSCoverSheetViewController *vc=[CSCoverSheetViewController new];vc.viewIfLoaded=panel;w.rootViewController=vc;
 LMVLockControllers=[NSHashTable weakObjectsHashTable];[LMVLockControllers addObject:vc];
 LMVLockVideoManager *m=[LMVLockVideoManager new];m.enabled=YES;m.path=@"movie";m.revision=@"rev";m.screenAllowed=YES;
 [m update];CALayer *render=m.playback.renderLayer;id player=m.playback.playerLayer;
 for(int i=0;i<60;i++){
  CGFloat y=-790+i*13;s.frame=CGRectMake(0,y,390,844);[m update];
  assert(m.host.superview==s && !m.host.hidden && m.playback.renderLayer==render && m.playback.playerLayer==player);
  CGRect mask=CGPathGetBoundingBox(m.host.clipLayer.path);assert(CGRectGetMinY(mask)==0);
  // Original parent moves one more frame BEFORE plugin display-link. 107
  // viewport-baked mask top at -y would leave a 6pt hole; whole paint does not.
  s.frame=CGRectMake(0,y+6,390,844);
  CGRect actual=[m.host.layer convertRect:mask toLayer:w.layer];actual=CGRectIntersection(actual,w.bounds);
  assert(CGRectGetMinY(actual)<=.01 && fabs(CGRectGetMaxY(actual)-(844+y+6))<.01);
  assert(!clock.hidden && back.layer.superlayer==s.layer);
 }
 s.frame=CGRectMake(0,0,390,844);panel.frame=CGRectMake(0,0,390,422);[m update];
 CGRect shown=[m.host.layer convertRect:CGPathGetBoundingBox(m.host.clipLayer.path) toLayer:w.layer];assert(CGRectGetMaxY(shown)<=422.01);
 m.screenAllowed=NO;[m update];assert(!m.host.superview && !m.playback.wantsPlayback);
 m.screenAllowed=YES;panel.frame=CGRectMake(0,0,390,844);s.frame=CGRectMake(0,-844,390,844);[m update];assert(!m.host.superview);
 m.enabled=NO;[m update];assert(!m.host.superview && !clock.hidden);
 puts("PASS actual NC attached-paint:60 full-panel pull frames,parent moves between callbacks without top lag,same player,foreground/backing preserved,half bottom/blank/withdraw/disable; not device pixels");
}return 0;}
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'motion.m';out=Path(d)/'motion';p.write_text(pre+production+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(p),'-o',str(out)],check=True)
 subprocess.run([str(out)],check=True,timeout=30)
