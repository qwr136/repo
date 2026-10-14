#!/usr/bin/env python3
"""CC geometry oracle: bounding-box coverage cannot prove composited coverage.
The full production/QuartzCore regression is assembled by control-center-video.py.
This portable test first demonstrates the delivered 101 failure, then gates the
scoped ancestor-slot implementation; it does not pretend to run UIKit on Linux.
"""
from pathlib import Path
r=Path(__file__).resolve().parents[1]
h=(r/'LMVControlCenterVideo.h').read_text()

def intersect(a,b):
 x,y=max(a[0],b[0]),max(a[1],b[1])
 return (x,y,max(0,min(a[0]+a[2],b[0]+b[2])-x),max(0,min(a[1]+a[3],b[1]+b[3])-y))

def contains(a,b):
 return a[0]<=b[0] and a[1]<=b[1] and a[0]+a[2]>=b[0]+b[2] and a[1]+a[3]>=b[1]+b[3]

for surface in ('Home','App'):
 for frame in range(61):
  y=422*frame/60;viewport=(0,0,390,844-y)
  short=(0,0,390,viewport[3]-8)
  # 101's union frame passes, but the masksToBounds short-root ancestor cuts it.
  assert contains(viewport,viewport)
  actual=intersect(viewport,short)
  assert not contains(actual,viewport), (surface,frame)
print('REPRODUCED 101: 122 Home/App frames pass bounding-box union but fail effective ancestry coverage (8pt bottom leak).')
assert 'LMVCCAncestorSlot' in h, '101 failure: render remains inside clipped/short CC root; no scoped ancestor slot'
assert 'LMVCCPresentationAllows' in h and 'LMVCCEffectiveCoverage' in h
assert 'SBControlCenterWindow' in h
print('PASS: scoped ancestor-slot source gates; native effective-ancestry/order/withdrawal assertions live in control-center-video.py')
