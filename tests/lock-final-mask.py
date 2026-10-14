#!/usr/bin/env python3
"""Execute the actual final mask helper; the mask never drops below the container."""
import ast,runpy,shutil,subprocess,tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1];h=(r/'LMVLockVideo.h').read_text()
assert 'LMVLockVideoFinalMask(local,space.bounds,physicalLocal)' in h
assert 'mask=LMVLockVideoRectValid(local)?CGRectUnion(local,container):container' in h
# Reuse the portable CGRect inputs only; helper itself is actual production.
tree=ast.parse((r/'tests/lock-reachability.py').read_text());pre=''
for node in tree.body:
 if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='cpre' for t in node.targets):pre=ast.literal_eval(node.value)
assert pre
valid=h[h.index('static BOOL LMVLockVideoRectValid'):h.index('static BOOL LMVLockVideoClass')]
helper=h[h.index('static CGRect LMVLockVideoFinalMask'):h.index('static CGRect LMVLockVideoGeometry')]
main=r'''
int main(void){
 CGRect container=CGRectMake(0,0,390,422),physical=CGRectMake(0,0,390,844),inset=CGRectMake(0,6,390,416);
 // 0.0.106: the union is unconditional now -- a pull-down transient that hides
 // the system background paint must not open a mask hole above the container.
 assert(equal(LMVLockVideoFinalMask(inset,container,physical),container));
 assert(equal(LMVLockVideoFinalMask(CGRectZero,container,physical),container));
 assert(equal(LMVLockVideoFinalMask(inset,container,physical),container));
 assert(equal(LMVLockVideoFinalMask(CGRectZero,container,physical),container));
 assert(CGRectIsEmpty(LMVLockVideoFinalMask(inset,container,CGRectZero)));
 CGRect half=CGRectMake(0,0,390,211);assert(equal(LMVLockVideoFinalMask(inset,container,half),half));
 for(int n=0;n<=100;n++){
  CGRect current=CGRectMake(0,0,390,422.0*n/100.0);
  if(n==0)assert(CGRectIsEmpty(LMVLockVideoFinalMask(inset,container,current)));
  else assert(equal(LMVLockVideoFinalMask(inset,container,current),current));
 }
 puts("PASS production final-mask: inset/empty union always at least the container, physical half/full/offscreen still bound it; not device compositing");return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
 src=Path(tmp)/'mask.c';out=Path(tmp)/'mask';src.write_text(pre+valid+helper+main)
 subprocess.run([shutil.which('cc'),' -std=c99'.strip(),str(src),'-lm','-o',str(out)],check=True)
 subprocess.run([str(out)],check=True)
