// macOS Foundation + REAL QuartzCore layers; view doubles replace unavailable UIKit.
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <assert.h>
#import "../LMVOriginalBackground.h"
@class UIWindow;
@interface UIView : NSObject
@property(nonatomic, strong) CALayer *layer;
@property(nonatomic, strong) NSMutableArray *subviews;
@property(nonatomic, copy) NSArray *gestureRecognizers;
@property(nonatomic) BOOL isAccessibilityElement;
@property(nonatomic) CGFloat alpha;
@property(nonatomic) BOOL hidden;
@property(nonatomic) CGRect bounds;
@property(nonatomic,weak) UIView *superview;
@property(nonatomic,copy) NSString *accessibilityLabel;
@property(nonatomic,weak) UIWindow *window;
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view;
- (BOOL)isDescendantOfView:(UIView *)view;
- (void)addSubview:(UIView *)view;
@end
@implementation UIView
- (instancetype)init { if ((self=[super init])) { _layer=[CALayer layer]; _layer.delegate=(id)self; _layer.bounds=CGRectMake(0,0,390,844); _subviews=[NSMutableArray new]; } return self; }
- (CGFloat)alpha { return self.layer.opacity; }
- (void)setAlpha:(CGFloat)alpha { self.layer.opacity=alpha; }
- (CGRect)convertRect:(CGRect)rect toView:(UIView *)view { return rect; }
- (CGRect)bounds { return self.layer.bounds; }
- (void)setBounds:(CGRect)bounds { self.layer.bounds = bounds; }
- (BOOL)isDescendantOfView:(UIView *)view { for (UIView *node=self; node; node=node.superview) if (node==view) return YES; return NO; }
- (void)addSubview:(UIView *)view { view.superview=self; view.window=self.window; [self.subviews addObject:view]; [self.layer addSublayer:view.layer]; }
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
@interface UIScreen : NSObject
+ (instancetype)mainScreen;
@end
@implementation UIScreen
+ (instancetype)mainScreen { static UIScreen *s; static dispatch_once_t once; dispatch_once(&once,^{s=[self new];}); return s; }
@end
@interface UIWindow : UIView
@property(nonatomic,strong) UIScreen *screen;
@end
@implementation UIWindow
- (instancetype)init { if ((self=[super init])) { self.window=self; _screen=UIScreen.mainScreen; } return self; }
@end
@interface UIScene : NSObject
@property(nonatomic) NSInteger activationState;
@end
@implementation UIScene @end
static const NSInteger UISceneActivationStateUnattached = -1;
@interface UIWindowScene : UIScene
@property(nonatomic,strong) NSArray *windows;
@end
@implementation UIWindowScene @end
@interface UIApplication : NSObject
@property(nonatomic,strong) NSArray *connectedScenes;
+ (instancetype)sharedApplication;
@end
@implementation UIApplication
+ (instancetype)sharedApplication { static UIApplication *a; static dispatch_once_t once; dispatch_once(&once,^{a=[self new];}); return a; }
@end
@interface _SBWallpaperSecureWindow : UIWindow @end
@implementation _SBWallpaperSecureWindow @end
@interface LMVTestBackdropLayer : CALayer @end
@implementation LMVTestBackdropLayer @end
@interface LocalWallpaperLayer : CALayer @end
@implementation LocalWallpaperLayer @end
@interface LMVVideoState : NSObject
@property(nonatomic,strong) NSArray<LMVOriginalLease *> *originals, *wallpaperOriginals;
@property(nonatomic,weak) UIView *originalAnchor, *originalScope;
@property(nonatomic,copy) NSString *originalDiagnostic, *wallpaperDiagnostic;
@end
@implementation LMVVideoState
- (void)dealloc { LMVReleaseOriginals(_originals,self); LMVReleaseOriginals(_wallpaperOriginals,self); }
@end
static NSUInteger diagnostics;
static void LMVDiagnostic(NSString *event) { assert([event hasPrefix:@"original "]); diagnostics++; }
// UIKit's NSStringFromCGRect is unavailable in the macOS native test runner.
static NSString *NSStringFromCGRect(CGRect rect) {
    return [NSString stringWithFormat:@"{{%g, %g}, {%g, %g}}", (double)rect.origin.x,
        (double)rect.origin.y, (double)rect.size.width, (double)rect.size.height];
}
#import "../LMVBackgroundDiscovery.h"
static BOOL LMVMessageCell(UIView *view) { return NO; }
static NSString *LMVSemanticTarget(UIView *view) { return [view.accessibilityLabel isEqualToString:@"Clear All"] ? @"Clear" : ([view.accessibilityLabel isEqualToString:@"Options"] ? @"Options" : nil); }
#import "../LMVActionDiscovery.h"
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
    // Remaining three action targets retain cold/error/alpha0 replacement policy.
    for(NSString *target in @[@"Message",@"Options",@"Clear"]) {
        MTMaterialView *host=[MTMaterialView new];CALayer *original=leaf();
        original.bounds=CGRectMake(0,0,200,100);original.opacity=.37;[host.layer addSublayer:original];
        CALayer *parent=[CALayer layer];[parent addSublayer:host.layer];
        CALayer *video=[CALayer layer];video.name=@"com.minis.lockmessagevideo.test";[parent addSublayer:video];
        LMVVideoState *state=[LMVVideoState new];
        LMVReplaceBackground(state,host,host,target,YES);
        assert(state.originals.count==1 && !original.superlayer);
        NSUInteger logs=diagnostics;
        for(int n=0;n<100;n++) {
            video.opacity=(n%2)?0:.55;LMVReplaceBackground(state,host,host,target,YES);
            assert(state.originals.count==1 && !original.superlayer && video.superlayer==parent);
        }
        assert(diagnostics==logs);
        LMVRestoreBackground(state);assert(original.superlayer==host.layer && closeTo(original.opacity,.37));
        LMVRestoreBackground(state);assert(host.layer.sublayers.count==1);
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
    // Shared material owners restore only on last lease, including owner deallocation.
    material=[MTMaterialView new];  material.alpha=.29;
    // Give the backing layer its own draw content so this exercises suppression.
    color=CGColorCreateGenericRGB(.1,.1,.1,1); material.layer.backgroundColor=color; CGColorRelease(color);
    scope=[UIView new]; [scope addSubview:material];
    __weak LMVVideoState *weakSecond;
    __strong LMVOriginalLease *retainedLease;
    @autoreleasepool {
        LMVVideoState *second=[LMVVideoState new]; weakSecond=second;
        LMVReplaceBackground(state,material,scope,@"Options",YES);
        LMVReplaceBackground(second,material,scope,@"Clear",YES);
        retainedLease=second.originals[0];
        assert(state.originals[0]==retainedLease && material.layer.opacity==0);
        assert(weakSecond && retainedLease.owners.allObjects.count==2);
        LMVRestoreBackground(state); assert(material.layer.opacity==0);
        // Weak-table enumerations and ObjC return temporaries may retain until pool drains.
    }
    assert(!weakSecond); // If this fails it is an owner lifetime bug, not restoration.
    assert(retainedLease.retired && retainedLease.owners.allObjects.count==0);
    assert(closeTo(material.layer.opacity,.29));
    // Expanded Clear All: semantic label/control and separate large material.
    // Execute production discovery, never hide the platter/control/text layer.
    UIView *platter=[UIView new]; UIControl *clear=[UIControl new];
    UILabel *clearLabel=[UILabel new]; clearLabel.accessibilityLabel=@"Clear All";
    [clear addSubview:clearLabel]; [platter addSubview:clear];
    MTMaterialView *wide=[MTMaterialView new]; wide.bounds=CGRectMake(0,0,240,80);
    CGColorRef backdropColor=CGColorCreateGenericRGB(.2,.2,.2,.8); wide.layer.backgroundColor=backdropColor; CGColorRelease(backdropColor);
    [platter addSubview:wide]; NSMapTable *hosts=[NSMapTable strongToStrongObjectsMapTable];
    LMVFindActions(platter,platter,hosts,0); assert([hosts objectForKey:@"Clear"]==wide);
    LMVReplaceBackground(state,wide,platter,@"Clear",YES);
    assert(wide.layer.opacity==0 && clear.layer.opacity==1 && clearLabel.layer.opacity==1 && platter.layer.opacity==1);
    // Deletion/reuse changes material identity; old branch restores immediately.
    wide.hidden=YES; MTMaterialView *replacement=[MTMaterialView new]; replacement.bounds=CGRectMake(0,0,280,90);
    replacement.layer.backgroundColor=wide.layer.backgroundColor; [platter addSubview:replacement]; [hosts removeAllObjects];
    LMVFindActions(platter,platter,hosts,0); assert([hosts objectForKey:@"Clear"]==replacement);
    LMVReplaceBackground(state,replacement,platter,@"Clear",YES);
    assert(wide.layer.opacity==1 && replacement.layer.opacity==0 && clearLabel.layer.opacity==1);
    LMVReplaceBackground(state,replacement,platter,@"Clear",NO); assert(replacement.layer.opacity==1);
    // Mixed Options/Clear root cannot lend its sibling material to either control.
    UIControl *options=[UIControl new]; options.accessibilityLabel=@"Options"; [platter addSubview:options];
    [hosts removeAllObjects]; LMVFindActions(platter,platter,hosts,0);
    assert([hosts objectForKey:@"Clear"]==clear && [hosts objectForKey:@"Options"]==options);
    puts("PASS: actual QuartzCore Message/Options/Clear lease/discovery; independent draw-leaf detach/restore, backing suppression, preserved labels/controls, shared owners, 100 refreshes and baseline/system updates; NOT device test");
} return 0; }
