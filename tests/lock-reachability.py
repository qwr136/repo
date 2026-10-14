#!/usr/bin/env python3
"""Run additional production Lock geometry/lease regressions, not device compositing."""
import ast, platform, shutil, subprocess, tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1]
h=(r/'LMVLockVideo.h').read_text()
assert 'LMVLockVideoGeometry' in h and 'record.wasExposed' in h
assert 'LMVLockVideoRepaint(node,content)' in h
assert 'self.host.frame=hostFrame' in h and 'entry.baselineHidden' in h
assert 'sliding && !sliding.hidden && sliding.alpha>.01' in h, 'preserve .100 content visibility gate'
assert 'owned=CGRectUnion(containerRect,exposure)' in h, 'union is restricted to owned paint/container space'
assert 'CGRectIntersection(contentRect,LMVLockVideoVisibleRect(backdrop,window))' in h
assert 'sameOwner && !root.clipsToBounds' in h, 'empty layout recovery needs the same attached, actually visible owner'
assert 'CGRectIntersection(rect,root.bounds)' in h and 'CGRectIntersection(rect,LMVVideoWindowViewport(window))' in h
assert 'CGRectIntersection(rect,[layer convertRect:layer.bounds toLayer:root])' in h
assert 'CGRectIntersection(containerRect,CGRectIntersection(viewport,panelRect))' in h, 'root fallback remains a partial panel'
assert 'if (ownsBackdrop && !content.hidden && content.alpha>.01) {' in h, 'content-owned exposure union must not gate on momentary backdrop visibility'
assert 'BOOL backdropOn=backdrop && !backdrop.hidden && backdrop.alpha>.01;' in h
assert '(ownsBackdrop || (rootBackdrop && backdropOn))' in h, 'root-owned fallback still needs a currently visible backdrop'
# Execute the unmodified production scalar geometry on every platform; Apple
# CI additionally runs the full production UIView/QuartzCore manager below.
cc=shutil.which('cc')
assert cc, 'a C compiler is required for production geometry regression'
cpre=r'''
#include <assert.h>
#include <math.h>
#include <stdio.h>
typedef int BOOL;
#define NO 0
#define YES 1
typedef double CGFloat;
typedef struct {double x,y;} CGPoint;
typedef struct {double width,height;} CGSize;
typedef struct {CGPoint origin;CGSize size;} CGRect;
#define CGRectZero ((CGRect){{0,0},{0,0}})
#define MIN(a,b) fmin((a),(b))
#define MAX(a,b) fmax((a),(b))
static CGRect CGRectMake(double x,double y,double w,double h){return (CGRect){{x,y},{w,h}};}
static double CGRectGetMinX(CGRect r){return r.origin.x;}
static double CGRectGetMinY(CGRect r){return r.origin.y;}
static double CGRectGetMaxX(CGRect r){return r.origin.x+r.size.width;}
static double CGRectGetMaxY(CGRect r){return r.origin.y+r.size.height;}
static BOOL CGRectIsNull(CGRect r){return isinf(r.origin.x)||isinf(r.origin.y);}
static BOOL CGRectIsInfinite(CGRect r){return isinf(r.size.width)||isinf(r.size.height);}
static BOOL CGRectIsEmpty(CGRect r){return r.size.width<=0||r.size.height<=0;}
static CGRect CGRectIntersection(CGRect a,CGRect b){
 double x=MAX(a.origin.x,b.origin.x),y=MAX(a.origin.y,b.origin.y);
 double w=MIN(CGRectGetMaxX(a),CGRectGetMaxX(b))-x,h=MIN(CGRectGetMaxY(a),CGRectGetMaxY(b))-y;
 return w>0&&h>0?CGRectMake(x,y,w,h):CGRectZero;
}
static CGRect CGRectUnion(CGRect a,CGRect b){
 double x=MIN(a.origin.x,b.origin.x),y=MIN(a.origin.y,b.origin.y);
 return CGRectMake(x,y,MAX(CGRectGetMaxX(a),CGRectGetMaxX(b))-x,MAX(CGRectGetMaxY(a),CGRectGetMaxY(b))-y);
}
static BOOL CGRectContainsRect(CGRect a,CGRect b){return a.origin.x<=b.origin.x&&a.origin.y<=b.origin.y&&CGRectGetMaxX(a)>=CGRectGetMaxX(b)&&CGRectGetMaxY(a)>=CGRectGetMaxY(b);}
static BOOL equal(CGRect a,CGRect b){return fabs(a.origin.x-b.origin.x)<.001&&fabs(a.origin.y-b.origin.y)<.001&&fabs(a.size.width-b.size.width)<.001&&fabs(a.size.height-b.size.height)<.001;}
'''
valid=h[h.index('static BOOL LMVLockVideoRectValid'):h.index('static BOOL LMVLockVideoClass')]
owned=h[h.index('static CGRect LMVLockVideoOwnedPaintRect'):h.index('static CGRect LMVLockVideoGeometry')]
cmain=r'''
int main(void){
 CGRect screen=CGRectMake(0,0,390,844),half=CGRectMake(0,0,390,422),inset=CGRectMake(0,6,390,416);
 // Old .101 geometry unions two already-inset bands: deterministic top leak.
 CGRect old=CGRectUnion(CGRectIntersection(half,inset),inset);
 assert(!equal(old,half));assert(!CGRectContainsRect(old,half));
 assert(equal(LMVLockVideoOwnedPaintRect(half,inset,inset,screen),half));
 assert(equal(LMVLockVideoOwnedPaintRect(half,inset,CGRectZero,screen),half));
 assert(equal(LMVLockVideoOwnedPaintRect(half,half,screen,screen),half));
 assert(equal(LMVLockVideoOwnedPaintRect(half,half,CGRectMake(0,0,390,211),screen),CGRectMake(0,0,390,211)));
 assert(equal(LMVLockVideoOwnedPaintRect(screen,screen,screen,half),half));
 CGRect narrow=CGRectMake(8,6,374,416),wide=CGRectMake(0,0,390,422);
 assert(equal(LMVLockVideoOwnedPaintRect(narrow,wide,screen,screen),wide));
 assert(equal(LMVLockVideoOwnedPaintRect(narrow,CGRectMake(0,0,390,100),screen,screen),narrow));
 assert(CGRectIsEmpty(LMVLockVideoOwnedPaintRect(CGRectZero,half,screen,screen)));
 assert(CGRectIsEmpty(LMVLockVideoOwnedPaintRect(half,CGRectZero,screen,screen)));
 assert(CGRectIsEmpty(LMVLockVideoOwnedPaintRect(half,half,screen,CGRectZero)));
 puts("PASS compiled production owned geometry: .101 top-leak reproduction / .102 union, empty-layout bounds, .100 half/bottom/viewport, no L-shaped widening, missing/offscreen fail-closed");
 return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'geometry.c';binary=Path(tmp)/'geometry';src.write_text(cpre+valid+owned+cmain)
    subprocess.run([cc,'-std=c99',str(src),'-lm','-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)
if platform.system()!='Darwin':
    print('PASS source contracts and compiled production geometry; SKIP UIView/QuartzCore owner/lifecycle harness: requires Apple frameworks')
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
 // Concrete top-strip regression: content is inset by 8pt horizontally and
 // 6pt vertically, while its recognized background covers the actual panel.
 // .100 rejects this because the two bands do not have identical x edges.
 sliding.frame=CGRectMake(8,6,374,416);movingBack.frame=CGRectMake(-8,-6,390,422);
 for(int n=0;n<50;n++){[m update];assert(m.host.superview==sliding && m.playback.wantsPlayback);
  CGRect shown=[m.host.layer convertRect:CGPathGetBoundingBox(m.host.clipLayer.path) toLayer:window.layer];
  assert(CGRectEqualToRect(shown,CGRectMake(0,0,390,422)));}
 // The controller itself can also inset/resize during layout while a pure
 // descendant backdrop still paints the top of the admitted panel. Fill only
 // the actually painted top band, keeping the original half-screen bottom.
 cover.frame=CGRectMake(0,6,390,416);sliding.frame=CGRectMake(8,0,374,416);movingBack.frame=CGRectMake(-8,-6,390,422);
 for(int n=0;n<50;n++){[m update];CGRect fixed=[m.host.layer convertRect:CGPathGetBoundingBox(m.host.clipLayer.path) toLayer:window.layer];
  assert(CGRectEqualToRect(fixed,CGRectMake(0,0,390,422)));}
 cover.frame=CGRectMake(0,0,390,844);sliding.frame=CGRectMake(8,6,374,416);
 // .101 FAIL / .102 PASS: root/paint layout share a 6pt TOP inset
 // inside the still-visible owned container. The previous union of two
 // already-inset rectangles could never grow back to container bounds.
 cover.frame=CGRectMake(0,6,390,416);sliding.frame=CGRectMake(0,-6,390,422);movingBack.frame=CGRectMake(0,6,390,416);
 for(int n=0;n<50;n++){[m update];CGRect fixed=[m.host.layer convertRect:CGPathGetBoundingBox(m.host.clipLayer.path) toLayer:window.layer];
  assert(CGRectEqualToRect(fixed,CGRectMake(0,0,390,422)));assert(CGRectContainsRect(CGPathGetBoundingBox(m.host.clipLayer.path),sliding.bounds));}
 // .101 FAIL / .102 PASS: a zero-height NON-CLIPPING controller layout
 // must not hide an already attached visible owner/background. No old mask
 // cache: geometry comes from current container/paint in the real layer tree.
 cover.frame=CGRectMake(0,0,390,0);sliding.frame=CGRectMake(0,0,390,422);
 for(int n=0;n<50;n++){[m update];assert(m.host.superview==sliding && m.playback.wantsPlayback && !m.host.hidden);
  assert(CGRectEqualToRect(CGPathGetBoundingBox(m.host.clipLayer.path),sliding.bounds));}
 // Real clipping overrides owned-paint union, even in that same empty layout.
 cover.clipsToBounds=YES;[m update];assert(!m.host.superview && !m.playback.wantsPlayback);cover.clipsToBounds=NO;
 // No new owner may attach using an empty root as a full-screen fallback.
 [m update];assert(!m.host.superview && !m.playback.wantsPlayback);
 cover.frame=CGRectMake(0,0,390,844);sliding.frame=CGRectMake(8,6,374,416);movingBack.frame=CGRectMake(-8,-6,390,422);[m update];
 // Missing/hidden background cannot revive an empty root; actual withdrawal
 // remains fail-closed despite the same content identity.
 movingBack.hidden=YES;cover.frame=CGRectMake(0,0,390,0);[m update];assert(!m.host.superview && !m.playback.wantsPlayback);
 movingBack.hidden=NO;cover.frame=CGRectMake(0,0,390,844);[m update];
 // Never invent paint below the partial NC or across an L-shaped union.
 CGRect frame=CGRectZero;
 movingBack.frame=CGRectMake(-8,-6,390,100);
 CGRect clip=LMVLockVideoGeometry(sliding,sliding,cover,movingBack,window,&frame);
 CGRect shown=[sliding.layer convertRect:CGRectOffset(clip,frame.origin.x,frame.origin.y) toLayer:window.layer];
 assert(CGRectEqualToRect(shown,CGRectMake(8,6,374,416)));
 // Actual clipping is authoritative; a verified active root-host final mask
 // now includes the whole container above the admitted bottom (0.1.3 semantics).
 movingBack.frame=CGRectMake(-8,-6,390,422);sliding.clipsToBounds=YES;[m update];
 shown=[m.host.layer convertRect:CGPathGetBoundingBox(m.host.clipLayer.path) toLayer:window.layer];
 assert(CGRectEqualToRect(shown,CGRectMake(8,6,374,416)));sliding.clipsToBounds=NO;
 // 0.0.105 top strip: the content-owned backdrop is momentarily hidden/zero-alpha
 // during the pull-down while the same attached content still paints the panel.
 // .104 dropped both unions here, so the 6pt band above the inset slideable
 // content fell back to the derived rect and showed the original wallpaper.
 // The confirmed, attached, exposed content owner must keep the union; a
 // root-owned fallback still requires its backdrop to be currently visible.
 movingBack.hidden=YES;
 for(int n=0;n<50;n++){[m update];assert(m.host.superview==sliding && m.playback.wantsPlayback);
  CGRect band=[m.host.layer convertRect:CGPathGetBoundingBox(m.host.clipLayer.path) toLayer:window.layer];
  assert(CGRectEqualToRect(band,CGRectMake(0,0,390,422)));}
 movingBack.hidden=NO;
 clip=LMVLockVideoGeometry(sliding,cover,cover,background,window,&frame);
 shown=[cover.layer convertRect:CGRectOffset(clip,frame.origin.x,frame.origin.y) toLayer:window.layer];
 assert(CGRectEqualToRect(shown,CGRectMake(0,0,390,422)));
 // Preserve .100 fail-closed gates, including transient zero content: do not
 // change half-screen visibility/lifecycle on the strength of a top-strip test.
 sliding.frame=CGRectMake(0,0,0,0);[m update];assert(!m.playback.wantsPlayback && !m.host.superview && !record.wasExposed);
 sliding.frame=CGRectMake(0,-844,390,844);movingBack.frame=CGRectMake(0,0,390,422);
 [m update];assert(!m.playback.wantsPlayback && !record.wasExposed);
 sliding.frame=CGRectMake(0,0,390,422);movingBack.frame=CGRectMake(0,0,390,422);
 cover.frame=CGRectMake(0,0,390,211);window.hidden=YES;cover.hidden=YES;[m update];assert(m.playback.wantsPlayback);
 CGRect preserved=[m.host.layer convertRect:CGPathGetBoundingBox(m.host.clipLayer.path) toLayer:window.layer];
 assert(CGRectEqualToRect(preserved,CGRectMake(0,0,390,211)));
 record.visible=NO;for(int n=0;n<50;n++){[m update];assert(m.playback.wantsPlayback);}
 sliding.hidden=YES;[m update];assert(!m.playback.wantsPlayback && !record.wasExposed);sliding.hidden=NO;
 record.visible=YES;cover.slideableContentView=nil;[m update];assert(!m.playback.wantsPlayback && !m.host.superview);cover.slideableContentView=sliding;
 cover.hidden=NO;window.hidden=NO;
 [m update];m.enabled=NO;[m update];assert(!m.playback.wantsPlayback && !m.host.superview);m.enabled=YES;
 m.screenAllowed=NO;[m update];assert(!m.playback.wantsPlayback && !m.host.superview);
 // Unknown content/disable restore original captured background exactly.
 [m suspend];assert(!m.playback.wantsPlayback);[m.host removeFromSuperview];
 puts("PASS production Lock: same-content half-screen false disappearance, no below-panel mask, direct capture sibling/50 stable leases, exposed top paint/50 stable content hosts; not device compositing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'lock.m';binary=Path(tmp)/'lock';src.write_text(pre+production+main)
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)
