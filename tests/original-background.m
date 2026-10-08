// macOS Foundation + REAL QuartzCore layers; view doubles replace unavailable UIKit.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <assert.h>
#import "../LMVOriginalBackground.h"
@interface UIView : NSObject
@property(nonatomic, strong) CALayer *layer;
@property(nonatomic, strong) NSMutableArray *subviews;
@property(nonatomic, copy) NSArray *gestureRecognizers;
@property(nonatomic) BOOL isAccessibilityElement;
@property(nonatomic) CGFloat alpha;
- (void)addSubview:(UIView *)view;
@end
@implementation UIView
- (instancetype)init { if ((self=[super init])) { _layer=[CALayer layer]; _layer.delegate=(id)self; _layer.bounds=CGRectMake(0,0,390,844); _subviews=[NSMutableArray new]; } return self; }
- (CGFloat)alpha { return self.layer.opacity; }
- (void)setAlpha:(CGFloat)alpha { self.layer.opacity=alpha; }
- (void)addSubview:(UIView *)view { [self.subviews addObject:view]; [self.layer addSublayer:view.layer]; }
@end
@interface UIControl : UIView @end
@implementation UIControl @end
@interface UILabel : UIView @end
@implementation UILabel @end
@interface UIImageView : UIView @end
@implementation UIImageView @end
@interface UITextView : UIView @end
@implementation UITextView @end
@interface UIScrollView : UIView @end
@implementation UIScrollView @end
@interface MTMaterialView : UIView @end
@implementation MTMaterialView @end
@interface LocalWallpaperView : UIView @end
@implementation LocalWallpaperView @end
@interface WallpaperSceneView : UIView @end
@implementation WallpaperSceneView @end
@interface WallpaperThumbnailView : UIView @end
@implementation WallpaperThumbnailView @end
@interface _SBWallpaperSecureWindow : UIView @end
@implementation _SBWallpaperSecureWindow @end
@interface LMVTestBackdropLayer : CALayer @end
@implementation LMVTestBackdropLayer @end
@interface LocalWallpaperLayer : CALayer @end
@implementation LocalWallpaperLayer @end
@interface LMVVideoState : NSObject
@property(nonatomic,strong) NSArray<LMVOriginalLease *> *originals;
@property(nonatomic,weak) UIView *originalAnchor, *originalScope;
@property(nonatomic,copy) NSString *originalDiagnostic;
@end
@implementation LMVVideoState
- (void)dealloc { LMVReleaseOriginals(_originals,self); }
@end
static NSUInteger diagnostics;
static void LMVDiagnostic(NSString *event) { assert([event hasPrefix:@"original target="]); diagnostics++; }
#import "../LMVBackgroundDiscovery.h"
static CALayer *leaf(void) { CALayer *layer=[LMVTestBackdropLayer layer]; layer.bounds=CGRectMake(0,0,200,100); layer.opacity=.37f; return layer; }
static BOOL closeTo(float a,float b) { return fabsf(a-b)<.00001f; }
int main(void) { @autoreleasepool {
    // Exact identity, siblings, model attributes, and only LAST owner restores.
    CALayer *parent=[CALayer layer], *a=[CALayer layer], *b=[CALayer layer], *draw=leaf();
    [parent addSublayer:a]; [parent addSublayer:draw]; [parent addSublayer:b];
    draw.cornerRadius=7; CALayer *mask=[CALayer layer]; draw.mask=mask;
    NSObject *owner1=[NSObject new], *owner2=[NSObject new];
    LMVOriginalLease *lease=LMVAcquireOriginal(draw,parent,LMVOriginalDetach,owner1);
    assert(lease && !draw.superlayer && lease.offlineLayer==draw && closeTo(draw.opacity,.37));
    assert(LMVAcquireOriginal(draw,parent,LMVOriginalDetach,owner2)==lease);
    for(int n=0;n<100;n++) { assert([lease maintain]); assert(parent.sublayers.count==2 && draw.mask==mask && draw.cornerRadius==7); }
    [lease releaseOwner:owner1]; assert(!draw.superlayer && lease.owners.count==1);
    [lease releaseOwner:owner2]; assert(parent.sublayers[1]==draw && parent.sublayers.count==3 && draw.mask==mask);
    [lease releaseOwner:owner2]; assert(parent.sublayers.count==3);
    // A moved system leaf belongs to its new parent; never borrow/reparent it.
    lease=LMVAcquireOriginal(draw,parent,LMVOriginalDetach,owner1);
    CALayer *other=[CALayer layer]; [other addSublayer:draw];
    assert(![lease maintain]); [lease releaseOwner:owner1]; assert(draw.superlayer==other);
    // Weak parent/scope: deallocation does not retain an entire system host.
    __weak CALayer *weakParent;
    @autoreleasepool { CALayer *temporary=[CALayer layer]; weakParent=temporary; CALayer *d=leaf(); [temporary addSublayer:d]; lease=LMVAcquireOriginal(d,temporary,LMVOriginalDetach,owner1); [CATransaction flush]; }
    assert(!weakParent && ![lease maintain]); [lease releaseOwner:owner1];
    // Restore index after original neighbour removal; never reset system attributes.
    CALayer *indexParent=[CALayer layer], *left=[CALayer layer], *middle=leaf(), *right=[CALayer layer];
    [indexParent addSublayer:left]; [indexParent addSublayer:middle]; [indexParent addSublayer:right];
    lease=LMVAcquireOriginal(middle,indexParent,LMVOriginalDetach,owner1);
    [left removeFromSuperlayer]; [right removeFromSuperlayer];
    CALayer *newLeft=[CALayer layer], *newRight=[CALayer layer];
    [indexParent addSublayer:newLeft]; [indexParent addSublayer:newRight];
    [lease releaseOwner:owner1]; assert(indexParent.sublayers[1]==middle);
    // Coordinator discovers a leaf held offline by another consumer, last releases.
    UIView *sharedHost=[MTMaterialView new]; CALayer *sharedLeaf=leaf(); [sharedHost.layer addSublayer:sharedLeaf];
    LMVVideoState *shared1=[LMVVideoState new], *shared2=[LMVVideoState new];
    LMVReplaceBackground(shared1,sharedHost,sharedHost,@"Options",YES);
    LMVReplaceBackground(shared2,sharedHost,sharedHost,@"Clear",YES);
    assert(shared1.originals.count==1 && shared2.originals.count==1 && shared1.originals[0]==shared2.originals[0]);
    LMVRestoreBackground(shared1); assert(!sharedLeaf.superlayer);
    LMVRestoreBackground(shared2); assert(sharedLeaf.superlayer==sharedHost.layer);
    // Retain .42 baseline, newer system .63, mask/corners; no multiplication.
    CALayer *suppressed=leaf(); [parent addSublayer:suppressed]; suppressed.opacity=.42;
    lease=LMVAcquireOriginal(suppressed,parent,LMVOriginalSuppressDrawing,owner1);
    assert(suppressed.opacity==0 && closeTo(lease.baselineOpacity,.42));
    for(int n=0;n<100;n++) assert([lease maintain]);
    suppressed.opacity=.63; assert([lease maintain] && suppressed.opacity==0);
    [lease releaseOwner:owner1]; assert(closeTo(suppressed.opacity,.63));
    // All five targets: selected but loading/failed/alpha0/cold retain replacement.
    for(NSString *target in @[@"Message",@"Options",@"Clear",@"LockScreen",@"Desktop"]) {
        BOOL wallpaper=[target isEqualToString:@"LockScreen"] || [target isEqualToString:@"Desktop"];
        UIView *host=wallpaper ? [UIView new] : [MTMaterialView new];
        CALayer *original=wallpaper ? [LocalWallpaperLayer layer] : leaf();
        original.bounds=CGRectMake(0,0,200,100); original.opacity=.37;
        [host.layer addSublayer:original]; CALayer *video=[CALayer layer]; video.name=@"com.minis.lockmessagevideo.test";
        // Plugin layer is a sibling of material; it must never invalidate pure-view detection.
        CALayer *parent=wallpaper ? host.layer : [CALayer layer];
        if(!wallpaper) [parent addSublayer:host.layer];
        [parent addSublayer:video];
        LMVVideoState *state=[LMVVideoState new];
        LMVReplaceBackground(state,host,host,target,YES);
        assert(state.originals.count==1 && !original.superlayer && state.originals[0].offlineLayer==original);
        NSUInteger count=parent.sublayers.count, logs=diagnostics;
        for(int n=0;n<100;n++) {
            // No decoder, preview, alpha or readiness input exists in this lease path.
            video.opacity=(n%2)?0:.55; LMVReplaceBackground(state,host,host,target,YES);
            assert(!original.superlayer && state.originals.count==1 && parent.sublayers.count==count);
        }
        assert(diagnostics==logs && video.superlayer==parent);
        LMVRestoreBackground(state); assert(original.superlayer==host.layer && closeTo(original.opacity,.37));
        LMVRestoreBackground(state); assert(host.layer.sublayers.count==(wallpaper?2:1));
        // Offscope (reuse/host change/App/lock), disable or selection empty releases.
        LMVReplaceBackground(state,host,host,target,YES); assert(!original.superlayer);
        LMVReplaceBackground(state,host,host,target,NO); assert(original.superlayer==host.layer);
    }
    // Backing drawing suppression: keep UIView identity, baseline alpha visibility,
    // text constraints and the sibling plugin frame; never hide discovery anchor.
    UIView *scope=[UIView new]; MTMaterialView *material=[MTMaterialView new];
    [scope addSubview:material]; material.alpha=.44;
    CGColorRef color=CGColorCreateGenericRGB(.2,.3,.4,1); material.layer.backgroundColor=color; CGColorRelease(color);
    CALayer *materialMask=[CALayer layer]; material.layer.mask=materialMask; material.layer.cornerRadius=19;
    LMVVideoState *state=[LMVVideoState new];
    LMVReplaceBackground(state,material,scope,@"Message",YES);
    assert(state.originals.count==1 && material.layer.superlayer==scope.layer && material.layer.opacity==0);
    assert(closeTo(LMVOriginalVisibilityAlpha(material),.44) && material.layer.mask==materialMask && material.layer.cornerRadius==19);
    NSUInteger logs=diagnostics;
    for(int n=0;n<100;n++) LMVReplaceBackground(state,material,scope,@"Message",YES);
    assert(diagnostics==logs && state.originals.count==1);
    material.layer.opacity=.58; LMVReplaceBackground(state,material,scope,@"Message",YES);
    assert(material.layer.opacity==0 && closeTo(LMVOriginalVisibilityAlpha(material),.58));
    // System adds a label after binding: release the branch instead of hiding text.
    UILabel *title=[UILabel new]; [material addSubview:title];
    LMVReplaceBackground(state,material,scope,@"Message",YES);
    assert(!state.originals.count && closeTo(material.layer.opacity,.58) && title.layer.superlayer==material.layer);
    assert([state.originalDiagnostic containsString:@"guarded-no-op"]);
    // System-owned mask/contents change survives restoration, untouched by lease.
    UIView *wallHost=[UIView new]; LocalWallpaperView *wall=[LocalWallpaperView new];
    [wallHost addSubview:wall]; wall.alpha=.31;
    LMVReplaceBackground(state,wallHost,wallHost,@"Desktop",YES);
    assert(state.originals.count==1 && wall.layer.opacity==0 && wall.layer.superlayer==wallHost.layer);
    wall.layer.mask=materialMask; wall.layer.cornerRadius=11;
    LMVRestoreBackground(state); assert(closeTo(wall.layer.opacity,.31) && wall.layer.mask==materialMask && wall.layer.cornerRadius==11);
    // A shared secure/remote wallpaper subtree is never a replacement target.
    UIView *safeHost=[UIView new]; _SBWallpaperSecureWindow *shared=[_SBWallpaperSecureWindow new];
    WallpaperSceneView *scene=[WallpaperSceneView new]; LocalWallpaperLayer *remote=[LocalWallpaperLayer layer];
    remote.bounds=CGRectMake(0,0,390,844); [scene.layer addSublayer:remote]; [shared addSubview:scene]; [safeHost addSubview:shared];
    for(NSString *target in @[@"LockScreen",@"Desktop"]) {
        LMVReplaceBackground(state,safeHost,safeHost,target,YES);
        assert(!state.originals.count && remote.superlayer==scene.layer && shared.alpha==1 && scene.alpha==1);
        assert([state.originalDiagnostic containsString:@"secure-window-shared-or-unidentified"]);
    }
    WallpaperThumbnailView *thumb=[WallpaperThumbnailView new]; [safeHost addSubview:thumb];
    LMVReplaceBackground(state,safeHost,safeHost,@"Desktop",YES); assert(!state.originals.count && thumb.alpha==1);
    // Shared material owners restore only on last lease, including owner deallocation.
    material=[MTMaterialView new]; material.layer.backgroundColor=wall.layer.backgroundColor; material.alpha=.29;
    // Give the backing layer its own draw content so this exercises suppression.
    color=CGColorCreateGenericRGB(.1,.1,.1,1); material.layer.backgroundColor=color; CGColorRelease(color);
    scope=[UIView new]; [scope addSubview:material];
    LMVVideoState *second=[LMVVideoState new];
    LMVReplaceBackground(state,material,scope,@"Options",YES);
    LMVReplaceBackground(second,material,scope,@"Clear",YES);
    assert(state.originals[0]==second.originals[0] && material.layer.opacity==0);
    LMVRestoreBackground(state); assert(material.layer.opacity==0);
    @autoreleasepool { second=nil; }
    assert(closeTo(material.layer.opacity,.29));
    puts("PASS: actual QuartzCore lease/discovery; all five target detach/restore; 100 layouts; last-owner restore; baseline/system updates; missing-frame/alpha0 stay replaced; content/secure/remote/thumb guarded; NOT iOS device validation");
} return 0; }
