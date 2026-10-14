#!/usr/bin/env python3
"""Execute the actual final mask helper; union never bypasses scope/viewport."""
import ast,runpy,shutil,subprocess,tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1];h=(r/'LMVLockVideo.h').read_text()
assert 'LMVLockVideoFinalMask(local,space.bounds,physicalLocal,owned)' in h
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
 assert(equal(LMVLockVideoFinalMask(inset,container,physical,YES),container));
 assert(equal(LMVLockVideoFinalMask(CGRectZero,container,physical,YES),container));
 assert(equal(LMVLockVideoFinalMask(inset,container,physical,NO),inset));
 assert(CGRectIsEmpty(LMVLockVideoFinalMask(CGRectZero,container,physical,NO)));
 assert(CGRectIsEmpty(LMVLockVideoFinalMask(inset,container,CGRectZero,YES)));
 CGRect half=CGRectMake(0,0,390,211);assert(equal(LMVLockVideoFinalMask(inset,container,half,YES),half));
 for(int n=0;n<=100;n++){
  CGRect current=CGRectMake(0,0,390,422.0*n/100.0);
  if(n==0)assert(CGRectIsEmpty(LMVLockVideoFinalMask(inset,container,current,YES)));
  else assert(equal(LMVLockVideoFinalMask(inset,container,current,YES),current));
 }
 puts("PASS production final-mask: owned inset/empty union at least container, physical half/full/offscreen and unknown fallback preserve scope; not device compositing");return 0;
}
'''
with tempfile.TemporaryDirectory() as tmp:
 src=Path(tmp)/'mask.c';out=Path(tmp)/'mask';src.write_text(pre+valid+helper+main)
 subprocess.run([shutil.which('cc'),' -std=c99'.strip(),str(src),'-lm','-o',str(out)],check=True)
 subprocess.run([str(out)],check=True)
