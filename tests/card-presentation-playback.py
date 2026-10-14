#!/usr/bin/env python3
"""Execute production exposure/consumer helpers with real CA and controlled snapshots.
No AVFoundation publish/decoder or device compositing claim.
"""
import ast,platform,subprocess,tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1];h=(r/'LMVCardPresentation.h').read_text();s=(r/'Tweak.xm').read_text()
assert '#import "LMVCardPresentation.h"' in s and 'LMVCardColdProbe(cell,states)' in s
assert s.count('LMVCardStateVisible(cell,state,target)')>=3
assert 'LMVCardExposureInTree(view,window,YES)' in h and 'lease.baselineOpacity' in h
# 0.0.112: a private (non-view-backed) CA rung may not veto on hidden/opacity;
# only a view-backed layer or real clipping geometry decides.
assert 'if(backing && (layer.hidden || (!presentation && backing.hidden)))return NO;' in h
assert 'alpha*=backing?LMVCardExposureAlpha(backing,layer,presentation):1.0;' in h
assert 'if(layer.hidden || !isfinite(layer.opacity))return NO;' not in h
assert '!backing && (layer.opacity<.01 || layer.masksToBounds || layer.mask)' not in h
assert 'NSRunLoopCommonModes' in s and 'LMVLink.preferredFramesPerSecond=30' in s
resign=s[s.index('addObserverForName:UIApplicationWillResignActiveNotification'):]
assert 'LMVSyncDisplayLink();LMVRequestSafeUpdate();' in resign
assert 'LMVReleaseAllPlayers();LMVRequestSafeUpdate();' not in resign
if platform.system()!='Darwin':
 print('PASS Message swipe exposure/consumer wiring; SKIP native Foundation/QuartzCore requires macOS')
 raise SystemExit(0)
pre='';tree=ast.parse((r/'tests/lock-video-host.py').read_text())
for n in tree.body:
 if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='pre' for t in n.targets):pre=ast.literal_eval(n.value)
 elif isinstance(n,ast.AugAssign) and isinstance(n.target,ast.Name) and n.target.id=='pre':pre+=ast.literal_eval(n.value)
mirror=r'''
@interface SampleLayer:CALayer
@property(nonatomic,strong) SampleLayer *sample;
@property(nonatomic,weak) CALayer *source;
@end
@implementation SampleLayer
- (instancetype)presentationLayer {return self.sample;}
- (instancetype)modelLayer {return (id)(self.source ?: self);}
@end
'''
pre=pre.replace('@class UIWindow;',mirror+'\n@class UIWindow;').replace('_layer=[CALayer layer];','_layer=[SampleLayer layer];')
pre+=r'''
#import "LMVOriginalBackground.h"
@interface NCNotificationListCell:UIView @end
@implementation NCNotificationListCell @end
@interface LMVVideoState:NSObject
@property(nonatomic,weak) UIView *anchor,*host;
@property(nonatomic,strong) UIView *overlay;
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,copy) NSString *path;
@end
@implementation LMVVideoState @end
static NSMutableDictionary<NSString *,NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *,NSString *> *LMVPaths;
static CGRect LMVVideoWindowViewport(UIWindow *window){return window.bounds;}
// Public UIView conversion is independent of an internal CA portal root.
@interface UIView(LMVFixtureCoordinates)
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)other;
@end
@implementation UIView(LMVFixtureCoordinates)
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)other {
    CGPoint a=CGPointZero,b=CGPointZero;
    for(UIView *n=self;n && n!=self.window;n=n.superview){a.x+=n.frame.origin.x;a.y+=n.frame.origin.y;}
    for(UIView *n=other;n && n!=other.window;n=n.superview){b.x+=n.frame.origin.x;b.y+=n.frame.origin.y;}
    return CGRectOffset(rect,a.x-b.x,a.y-b.y);
}
@end
static BOOL LMVVisible(UIView *view);
static BOOL LMVMessageCell(UIView *view){return [view isKindOfClass:NCNotificationListCell.class];}
static BOOL LMVNotificationCenterSurface(UIView *view);
static CGFloat LMVOriginalVisibilityAlpha(UIView *view){
 LMVOriginalLease *lease=[LMVOriginalLeases() objectForKey:view.layer];
 return lease && !lease.retired && lease.method==LMVOriginalSuppressDrawing && view.layer.opacity==0 ? lease.baselineOpacity:view.alpha;
}
'''
scope=s[s.index('static BOOL LMVNotificationCenterSurface(UIView *view) {'):s.index('#import "LMVCardPresentation.h"')]
pre+=scope
main=r'''
static SampleLayer *snapshot(UIView *v){
 SampleLayer *p=[SampleLayer layer];p.source=v.layer;p.bounds=v.layer.bounds;p.anchorPoint=v.layer.anchorPoint;p.position=v.layer.position;
 p.hidden=v.hidden;p.opacity=v.layer.opacity;((SampleLayer *)v.layer).sample=p;
 for(UIView *child in v.subviews)[p addSublayer:snapshot(child)];return p;
}
static BOOL LMVVisible(UIView *view){return !screenBlank && LMVNotificationCenterSurface(view) && LMVCardExposed(view);}
int main(void){@autoreleasepool{
 SBCoverSheetWindow *w=[SBCoverSheetWindow new];UIView *sliding=[UIView new];[w addSubview:sliding];
 NCNotificationListCell *card=[NCNotificationListCell new];card.frame=CGRectMake(0,60,390,150);[sliding addSubview:card];
 UIView *anchor=[UIView new];anchor.frame=CGRectMake(0,0,390,150);[card addSubview:anchor];
 UIView *overlay=[UIView new];overlay.frame=anchor.frame;[card addSubview:overlay];
 LMVVideoState *state=[LMVVideoState new];state.anchor=anchor;state.host=card;state.overlay=overlay;state.path=@"movie";
 state.layer=[CALayer layer];[overlay.layer addSublayer:state.layer];
 LMVEnabled=[@{@"Message":@YES} mutableCopy];LMVPaths=[@{@"Message":@"movie"} mutableCopy];
 assert(LMVCardStateVisible(card,state,@"Message"));snapshot(w);
 // 111 compatibility regression: UIKit owner stays attached while an internal
 // CA render root is bridged separately from window.layer. 110 rejected this
 // before checking public view exposure. No fallback for a detached UIView.
 ((SampleLayer *)w.layer).sample=nil;((SampleLayer *)sliding.layer).sample=nil;
 ((SampleLayer *)card.layer).sample=nil;((SampleLayer *)anchor.layer).sample=nil;((SampleLayer *)overlay.layer).sample=nil;
 SampleLayer *portal=[SampleLayer layer];portal.bounds=w.bounds;portal.anchorPoint=CGPointZero;
 [sliding.layer removeFromSuperlayer];[portal addSublayer:sliding.layer];
 assert(!LMVCardLayerAttached(card.layer,w.layer) && LMVCardAttached(card,w));
 for(NSString *t in @[@"Message",@"Options",@"Clear"]){LMVEnabled[t]=@YES;LMVPaths[t]=@"movie";assert(LMVCardStateVisible(card,state,t));}
 // 0.0.112 device regression: an internal CA render/portal root is not a UIView,
 // so its hidden/opacity is UIKit implementation state, not a visibility
 // contract. Vetoing on it rejected every real NC card, so no card ever became a
 // consumer and Message/Options/Clear never played at all. Such a rung still
 // contributes its clipping geometry below; only real geometry may reject it.
 portal.hidden=YES;assert(LMVCardStateVisible(card,state,@"Message"));portal.hidden=NO;
 portal.opacity=0;assert(LMVCardStateVisible(card,state,@"Message"));portal.opacity=1;
 // A VIEW-BACKED ancestor keeps the full veto in the same model-only state.
 ((SampleLayer *)w.layer).sample=nil;((SampleLayer *)sliding.layer).sample=nil;
 ((SampleLayer *)card.layer).sample=nil;((SampleLayer *)anchor.layer).sample=nil;((SampleLayer *)overlay.layer).sample=nil;
 sliding.hidden=YES;assert(!LMVCardStateVisible(card,state,@"Message"));sliding.hidden=NO;
 sliding.alpha=.005;assert(!LMVCardStateVisible(card,state,@"Message"));sliding.alpha=1;
 card.frame=CGRectMake(0,1200,390,150);assert(!LMVCardStateVisible(card,state,@"Message"));card.frame=CGRectMake(0,60,390,150);
 [portal removeFromSuperlayer];[w.layer addSublayer:sliding.layer];snapshot(w);
 // REPRO 107: UIKit has an intermediate layer although UIView ownership is
 // unchanged. Old superlayer==superview.layer returns NO for ALL three targets.
 SampleLayer *bridge=[SampleLayer layer];bridge.anchorPoint=CGPointZero;bridge.position=CGPointZero;bridge.bounds=w.bounds;
 [card.layer removeFromSuperlayer];[sliding.layer addSublayer:bridge];[bridge addSublayer:card.layer];
 assert(card.superview==sliding && card.layer.superlayer!=sliding.layer);
 for(NSString *target in @[@"Message",@"Options",@"Clear"]){LMVEnabled[target]=@YES;LMVPaths[target]=@"movie";assert(LMVCardStateVisible(card,state,target));}
 // Snapshot parent may be a different presentationLayer object from the one
 // separately returned by its UIView. Convert within the child's actual tree.
 snapshot(w);SampleLayer *sampleBridge=[SampleLayer layer];sampleBridge.source=bridge;sampleBridge.anchorPoint=CGPointZero;sampleBridge.bounds=w.bounds;
 SampleLayer *cardSample=((SampleLayer *)card.layer).sample;[cardSample removeFromSuperlayer];[((SampleLayer *)sliding.layer).sample addSublayer:sampleBridge];[sampleBridge addSublayer:cardSample];
 SampleLayer *otherSnapshot=[SampleLayer layer];otherSnapshot.source=sliding.layer;((SampleLayer *)sliding.layer).sample=otherSnapshot;
 sliding.frame=CGRectMake(0,-844,390,844); // force presentation-only consumer
 for(NSString *target in @[@"Message",@"Options",@"Clear"])assert(LMVCardStateVisible(card,state,target));
 // 0.0.112: same contract inside ONE committed snapshot tree. A private rung of
 // the snapshot may be hidden/opacity-zero without hiding the public view, so it
 // cannot veto either; its masksToBounds geometry still can.
 sampleBridge.opacity=0;assert(LMVCardStateVisible(card,state,@"Message"));sampleBridge.opacity=1;
 sampleBridge.hidden=YES;assert(LMVCardStateVisible(card,state,@"Message"));sampleBridge.hidden=NO;
 sampleBridge.masksToBounds=YES;sampleBridge.bounds=CGRectMake(0,0,390,30);assert(!LMVCardStateVisible(card,state,@"Message"));sampleBridge.masksToBounds=NO;
 sliding.frame=CGRectMake(0,0,390,844);
 [bridge removeFromSuperlayer];[sliding.layer addSublayer:card.layer];snapshot(w);
 // Overall NC panel model already withdrawn while its committed sample is visible.
 sliding.frame=CGRectMake(0,-844,390,844);assert(!LMVCardExposureInTree(card,w,NO));
 assert(LMVCardExposureInTree(card,w,YES) && LMVCardStateVisible(card,state,@"Message"));
 for(int i=0;i<500;i++)assert(LMVCardStateVisible(card,state,@"Message"));
 // A model-hidden ancestor can still be displayed, but actual sample-hidden cannot.
 sliding.hidden=YES;assert(LMVCardStateVisible(card,state,@"Message"));
 ((SampleLayer *)sliding.layer).sample.hidden=YES;assert(!LMVCardStateVisible(card,state,@"Message"));
 sliding.hidden=NO;sliding.frame=CGRectMake(0,0,390,844);snapshot(w);
 // Original pure backing suppression does not masquerade as real disappearance.
 LMVOriginalLease *lease=[LMVOriginalLease new];lease.layer=anchor.layer;lease.method=LMVOriginalSuppressDrawing;lease.baselineOpacity=.7;
 [LMVOriginalLeases() setObject:lease forKey:anchor.layer];anchor.layer.opacity=0;snapshot(w);
 assert(LMVCardStateVisible(card,state,@"Message"));
 // The system material can be hidden while OUR sibling video is genuinely
 // exposed. Anchor attachment is mandatory; its drawing state is not a gate.
 anchor.hidden=YES;snapshot(w);
 for(NSString *target in @[@"Message",@"Options",@"Clear"])assert(LMVCardStateVisible(card,state,target));
 anchor.hidden=NO;snapshot(w);
 // Model still onscreen, but committed presentation panel withdrawn: pause.
 ((SampleLayer *)sliding.layer).sample.position=CGPointMake(195,-844+422);
 assert(!LMVCardStateVisible(card,state,@"Message"));snapshot(w);
 sliding.frame=CGRectMake(0,0,390,30);sliding.clipsToBounds=NO;snapshot(w);sliding.clipsToBounds=YES;
 assert(LMVCardStateVisible(card,state,@"Message")); // committed tree still does NOT clip
 ((SampleLayer *)sliding.layer).sample.masksToBounds=YES;assert(!LMVCardStateVisible(card,state,@"Message"));
 sliding.frame=CGRectMake(0,0,390,844);snapshot(w);screenBlank=1;assert(!LMVCardStateVisible(card,state,@"Message"));screenBlank=0;
 LMVEnabled[@"Message"]=@NO;assert(!LMVCardStateVisible(card,state,@"Message"));LMVEnabled[@"Message"]=@YES;
 snapshot(w);w.hidden=YES;assert(LMVCardStateVisible(card,state,@"Message"));
 ((SampleLayer *)w.layer).sample.hidden=YES;assert(!LMVCardStateVisible(card,state,@"Message"));w.hidden=NO;snapshot(w);
 // Move to another NC window: cached sample of old tree is not admission.
 assert(LMVCardExposed(card));SBCoverSheetWindow *other=[SBCoverSheetWindow new];[card removeFromSuperview];[other addSubview:card];card.frame=CGRectMake(0,1000,390,150);
 assert(!LMVCardExposed(card));card.frame=CGRectMake(0,0,390,150);assert(LMVCardExposed(card));
 UIWindow *app=[UIWindow new];UIView *ordinary=[UIView new];[app addSubview:ordinary];assert(!LMVVisible(ordinary));
 [app addSubview:card];card.frame=CGRectMake(0,0,390,150);assert(LMVNotificationCenterSurface(card));
 for(NSString *target in @[@"Message",@"Options",@"Clear"])assert(LMVCardStateVisible(card,state,target));
 puts("PASS actual production Message consumer gate: overall NC model-offscreen/presentation-visible,500 stable,view-backed veto,private-rung non-veto (0.0.112),lease opacity baseline,clip,blank,disable,withdraw,window transfer/app rejection; not decode/device pixels");
}return 0;}
'''
with tempfile.TemporaryDirectory() as d:
 src=Path(d)/'card.m';out=Path(d)/'card';src.write_text(pre+'\n'+h+'\n'+main)
 subprocess.run(['clang','-fobjc-arc','-I',str(r),'-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(src),'-o',str(out)],check=True)
 subprocess.run([str(out)],check=True,timeout=40)
