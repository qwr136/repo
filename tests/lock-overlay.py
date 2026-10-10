from pathlib import Path
import platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LMVLockBackground.h').read_text();s=(r/'Tweak.xm').read_text()
assert 'video.opacity=1.0f' in h and 'LMVOpacity' not in h
assert 'LMVAcquireOriginal' not in h and 'LMVRestoreBackground' not in h
assert 'above:background.layer' in h and 'state.displayHost=host' in h
assert 'LMVDesktop' not in s and 'Desktop' not in s
assert 'state=objc_getAssociatedObject(host,&LMVLockStateKey);' in s
assert not (r/'LMVWallpaperWindow.h').exists() and not (r/'LMVNotificationWallpaper.h').exists()
if platform.system()!='Darwin':
    print('PASS: opaque lock/NC overlay, no original mutation, no desktop renderer; native QuartzCore test on macOS CI')
    raise SystemExit(0)
# Use the actual layer helpers. UIKit unavailable on macOS is represented by
# view doubles; CALayer/CAShapeLayer, geometry, opacity and sibling order are real.
pre=(r/'tests/original-background.m').read_text().split('@interface LMVVideoState : NSObject',1)[0]
pre=pre.replace('#import "../LMVOriginalBackground.h"','#import "LMVOriginalBackground.h"')
pre=pre.replace('@property(nonatomic) CGRect bounds;','@property(nonatomic) CGRect bounds, frame;')
pre=pre.replace('- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { return rect; }','''- (CGRect)frame { return _layer.frame; }
- (void)setFrame:(CGRect)frame { _layer.frame=frame; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { return [_layer convertRect:rect toLayer:view.layer]; }''')
extra=r'''
#import <objc/message.h>
#import <math.h>
#import <string.h>
@interface UIColor:NSObject
+ (instancetype)blackColor;
@property(nonatomic,readonly) CGColorRef CGColor;
@end
@implementation UIColor
+ (instancetype)blackColor { static UIColor *v; static dispatch_once_t once; dispatch_once(&once, ^{v=[self new];});return v; }
- (CGColorRef)CGColor { static CGColorRef color; static dispatch_once_t once; dispatch_once(&once, ^{color=CGColorCreateGenericRGB(0,0,0,1);});return color; }
@end
@interface SBCoverSheetWindow:UIWindow @end
@implementation SBCoverSheetWindow @end
@interface CSCoverSheetView:UIView
@property(nonatomic,strong) UIView *slideableContentView;
@end
@implementation CSCoverSheetView @end
@interface SBUIBackgroundView:UIView @end
@implementation SBUIBackgroundView @end
@interface LMVVideoState:NSObject
@property(nonatomic,strong) CALayer *layer;
@property(nonatomic,weak) UIView *displayHost;
@property(nonatomic,copy) NSString *path, *displayDiagnostic;
@property(nonatomic) CFTimeInterval displayDiagnosticAt;
@end
@implementation LMVVideoState @end
static NSHashTable<UIView *> *LMVLockHosts;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *, NSString *> *LMVPaths;
static void LMVDiagnostic(NSString *message) {}
static NSString *NSStringFromCGRect(CGRect rect) {return @"rect";}
#import "LMVLockBackground.h"
static void geometry(UIView *v,CGRect frame) {v.bounds=(CGRect){CGPointZero,frame.size};v.frame=frame;}
static BOOL drawsAt(LMVVideoState *state,UIWindow *window,CGPoint point) {
    if(state.layer.hidden || !state.layer.contents)return NO;
    CAShapeLayer *mask=(CAShapeLayer *)state.layer.mask;
    CGPoint local=[state.layer convertPoint:point fromLayer:window.layer];
    return CGPathContainsPoint(mask.path,NULL,local,NO);
}
static void intact(UIView *host,NSArray<CALayer *> *original) {
    NSArray *now=host.layer.sublayers;
    NSUInteger previous=NSNotFound;
    for(CALayer *layer in original) {
        assert(layer.superlayer==host.layer);
        NSUInteger index=[now indexOfObjectIdenticalTo:layer];assert(index!=NSNotFound);
        if(previous!=NSNotFound)assert(index>previous);previous=index;
    }
    for(UIView *view in host.subviews)assert(view.layer.superlayer==host.layer && view.layer.delegate==view);
}
int main(void) {@autoreleasepool {
    LMVEnabled=[@{@"LockScreen":@YES} mutableCopy];LMVPaths=[@{@"LockScreen":@"lock.mov"} mutableCopy];
    LMVLockHosts=[NSHashTable weakObjectsHashTable];
    SBCoverSheetWindow *window=[SBCoverSheetWindow new];geometry(window,CGRectMake(0,0,390,844));
    UIView *wrapper=[UIView new];[window addSubview:wrapper];geometry(wrapper,window.bounds);
    // Moving content sits above a separate system backdrop that can be translucent.
    UIView *panel=[UIView new];[wrapper addSubview:panel];geometry(panel,window.bounds);panel.alpha=.2;
    CALayer *backdrop=panel.layer;float backdropOpacity=backdrop.opacity;
    CSCoverSheetView *cover=[CSCoverSheetView new];[wrapper addSubview:cover];geometry(cover,window.bounds);
    UIView *content=[UIView new];[cover addSubview:content];geometry(content,CGRectMake(0,-844,390,844));cover.slideableContentView=content;
    SBUIBackgroundView *background=[SBUIBackgroundView new];[content addSubview:background];geometry(background,content.bounds);background.alpha=.3;
    UILabel *clock=[UILabel new],*card=[UILabel new];[content addSubview:clock];[content addSubview:card];
    NSArray *system=content.layer.sublayers.copy;
    LMVVideoState *state=[LMVVideoState new];state.layer=[CALayer layer];state.path=@"lock.mov";state.layer.contents=@"video-frame";
    UIWindowScene *scene=[UIWindowScene new];scene.windows=@[window];UIApplication.sharedApplication.connectedScenes=@[scene];
    LMVDiscoverLockHosts();assert([LMVLockHosts containsObject:cover]);
    assert(!LMVLockOverlayVisible(cover));
    for(int i=0;i<=100;i++) {
        CGFloat height=i*8.44;
        geometry(content,CGRectMake(0,-844+height,390,844));
        // Changing the separate backdrop opacity cannot fade our opaque video.
        panel.alpha=(i%2)?.2:.6;state.layer.opacity=.2;
        LMVLayoutLockOverlay(cover,state);
        intact(content,system);
        assert(state.layer.superlayer==content.layer && state.layer.opacity==1);
        assert(background.layer.opacity==.3f && clock.layer.opacity==1 && card.layer.opacity==1);
        NSArray *children=content.layer.sublayers;
        assert([children indexOfObjectIdenticalTo:state.layer]==[children indexOfObjectIdenticalTo:background.layer]+1);
        assert([children indexOfObjectIdenticalTo:clock.layer]>[children indexOfObjectIdenticalTo:state.layer]);
        if(height>1)assert(drawsAt(state,window,CGPointMake(100,height-1)));
        if(height<844)assert(!drawsAt(state,window,CGPointMake(100,height+1)));
    }
    assert(LMVLockOverlayVisible(cover));
    // Half pull and cancellation do not draw behind the exposed Home/App region.
    geometry(content,CGRectMake(0,-422,390,844));LMVLayoutLockOverlay(cover,state);
    assert(drawsAt(state,window,CGPointMake(100,100)) && !drawsAt(state,window,CGPointMake(100,600)));
    geometry(content,CGRectMake(0,-844,390,844));LMVLayoutLockOverlay(cover,state);assert(state.layer.hidden);
    // Unknown host getter falls back only to a moved CoverSheet, never window bounds.
    cover.slideableContentView=nil;geometry(cover,CGRectMake(0,-422,390,844));LMVLayoutLockOverlay(cover,state);
    assert(state.layer.superlayer==cover.layer && !drawsAt(state,window,CGPointMake(100,600)));
    cover.slideableContentView=content;geometry(cover,window.bounds);geometry(content,window.bounds);
    LMVLayoutLockOverlay(cover,state);assert(!state.layer.hidden);
    // No frame does not expose a black patch or destroy original background.
    state.layer.contents=nil;LMVLayoutLockOverlay(cover,state);assert(state.layer.hidden);intact(content,system);
    state.layer.contents=@"video-frame";LMVLayoutLockOverlay(cover,state);
    // Selection changed: an old local state is never reattached.
    LMVPaths[@"LockScreen"]=@"other.mov";LMVLayoutLockOverlay(cover,state);assert(!state.layer.superlayer);
    LMVPaths[@"LockScreen"]=@"lock.mov";LMVLayoutLockOverlay(cover,state);assert(state.layer.superlayer==content.layer);
    LMVEnabled[@"LockScreen"]=@NO;LMVLayoutLockOverlay(cover,state);assert(!state.layer.superlayer);
    assert([content.layer.sublayers isEqualToArray:system]);
    assert(backdrop.superlayer==wrapper.layer && backdropOpacity==.2f);
    // Keep all original views/parents intact; only plugin video comes and goes.
    puts("PASS: actual opaque lock/NC overlay layer, 101 exposed-content positions, outside-region rejection, foreground order, translucent backdrop bypass, original tree unchanged, fallback/missing-frame/change/disable and no old state resurrection; not device compositing proof");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'lock.mm';binary=Path(tmp)/'lock';src.write_text(pre+extra)
    subprocess.run(['clang++','-std=c++11','-fobjc-arc','-I',str(r),'-framework','Foundation','-framework','QuartzCore','-framework','CoreGraphics',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)
