#!/usr/bin/env python3
"""105 production opacity-slot regression; no claim of device pixels."""
import ast,platform,subprocess,tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1];h=(r/'LMVLockVideo.h').read_text()
for x in ('LMVLockVideoOpaqueChain','LMVLockVideoOpaqueSlot','lock-composite','maskShown=', 'effective=', 'self.extentAnchor'):
 assert x in h,x
assert '[renderParent insertSubview:self.host atIndex:front]' in h
assert 'parent.alpha=' not in h and 'node.alpha=' not in h
assert 'CGRectOffset(clip,hostFrame.origin.x,hostFrame.origin.y)' in h
if platform.system()!='Darwin':
 print('PASS opacity-slot source contracts; SKIP real QuartzCore manager execution requires macOS')
 raise SystemExit(0)
pre='';tree=ast.parse((r/'tests/lock-video-host.py').read_text())
for n in tree.body:
 if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='pre' for t in n.targets):pre=ast.literal_eval(n.value)
 elif isinstance(n,ast.AugAssign) and isinstance(n.target,ast.Name) and n.target.id=='pre':pre+=ast.literal_eval(n.value)
# Fixture mirrors UIView alpha -> CALayer.opacity exactly; production unaffected.
pre=pre.replace('_alpha=1;','self.alpha=1;')
pre=pre.replace('- (CGRect)frame {return self.layer.frame;}', '- (CGFloat)alpha {return self.layer.opacity;}\n- (void)setAlpha:(CGFloat)x {self.layer.opacity=x;}\n- (CGRect)frame {return self.layer.frame;}')
production=h[h.index('static BOOL LMVLockVideoRectValid'):].replace('LMVDiagnosticsEnabled.load()','NO')
main=r'''
static CGFloat opacity(UIView *v){CGFloat x=1;for(;v;v=v.superview)x*=v.layer.opacity;return x;}
int main(void){@autoreleasepool{
 LMVInitialized=YES;LMVLaunchReady=YES;
 SBCoverSheetWindow *w=[SBCoverSheetWindow new];UIView *outer=[UIView new];[w addSubview:outer];
 CSCoverSheetView *cover=[CSCoverSheetView new];[outer addSubview:cover];UIView *s=[UIView new];[cover addSubview:s];
 SBUIBackgroundView *back=[SBUIBackgroundView new];UILabel *clock=[UILabel new];[s addSubview:back];[s addSubview:clock];cover.slideableContentView=s;
 CSCoverSheetViewController *vc=[CSCoverSheetViewController new];vc.viewIfLoaded=cover;w.rootViewController=vc;
 LMVLockControllers=[NSHashTable weakObjectsHashTable];[LMVLockControllers addObject:vc];
 LMVLockVideoManager *m=[LMVLockVideoManager new];m.enabled=YES;m.path=@"movie";m.revision=@"rev";m.screenAllowed=YES;
 [m update];assert(m.host.superview==s && !back.hidden && opacity(m.host)==1);
 CALayer *render=m.playback.renderLayer;id player=m.playback.playerLayer;
 // Deterministic baseline reproduction: a .35-alpha owned parent makes the
 // old nested host effectively .35 even with host.alpha=1.
 s.alpha=.35;assert(opacity(m.host)<.36);[m update];
 assert(m.host.superview==cover && opacity(m.host)>.999 && back.hidden && !clock.hidden);
 assert(m.extentContainer==s && m.playback.renderLayer==render && m.playback.playerLayer==player);
 assert(s.alpha==.35 && [cover.subviews indexOfObjectIdenticalTo:m.host]+1==[cover.subviews indexOfObjectIdenticalTo:s]);
 LMVLockVideoPaintLease *lease=m.paintLease;
 for(int i=0;i<500;i++){[m update];assert(m.host.superview==cover && back.hidden && opacity(m.host)>.999 && m.paintLease==lease);}
 // Fading the entire cover selects the next opaque ancestor, below the cover.
 cover.alpha=.4;[m update];assert(m.host.superview==outer && opacity(m.host)>.999 && cover.alpha==.4);
 // All existing physical clips/partial bottom continue to constrain the video.
 s.frame=CGRectMake(0,-500,390,844);[m update];CGRect rect=[m.host.layer convertRect:CGPathGetBoundingBox(m.host.clipLayer.path) toLayer:w.layer];
 assert(fabs(CGRectGetMinY(rect))<.01 && fabs(CGRectGetMaxY(rect)-344)<.01);
 outer.clipsToBounds=YES;outer.frame=CGRectMake(0,0,390,200);[m update];rect=[m.host.layer convertRect:CGPathGetBoundingBox(m.host.clipLayer.path) toLayer:w.layer];assert(CGRectGetMaxY(rect)<=200.01);
 outer.frame=CGRectMake(0,0,390,844);outer.clipsToBounds=NO;s.frame=CGRectMake(0,0,390,844);
 // Opaque transition returns to original background slot with baseline restored.
 cover.alpha=1;s.alpha=1;[m update];assert(m.host.superview==s && !back.hidden && !m.extentContainer);
 // Never bypass a nonrectangular system mask, unrelated preceding foreground,
 // foreign window, or alter controls/text/parent opacity to force admission.
 CAShapeLayer *mask=[CAShapeLayer layer];s.layer.mask=mask;s.alpha=.5;[m update];assert(m.host.superview==s && !back.hidden);s.layer.mask=nil;
 UILabel *before=[UILabel new];[cover insertSubview:before atIndex:0];[m update];assert(m.host.superview==s && !before.hidden);[before removeFromSuperview];
 [m update];assert(back.hidden);m.screenAllowed=NO;[m update];assert(!m.host.superview && !back.hidden && !clock.hidden && !m.extentContainer);
 m.screenAllowed=YES;[m update];assert(back.hidden);s.frame=CGRectMake(0,-844,390,844);[m update];assert(!m.host.superview && !back.hidden);
 s.frame=CGRectMake(0,0,390,844);[m update];assert(back.hidden);[m suspend];assert(!back.hidden && !m.extentContainer);
 m.enabled=NO;[m update];assert(!m.host.superview && !back.hidden);
 puts("PASS production NC opacity-slot: same live player, below foreground, unchanged system alpha,500 stable updates,panel bottom/ancestor clips,opaque restore,mask/foreground/blank/offscreen/disable rejection; not device compositing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as d:
 src=Path(d)/'composite.m';out=Path(d)/'composite';src.write_text(pre+production+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(src),'-o',str(out)],check=True)
 subprocess.run([str(out)],check=True,timeout=40)
