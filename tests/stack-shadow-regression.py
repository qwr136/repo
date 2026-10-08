#!/usr/bin/env python3
"""Exercise the actual alpha helper/hooks with Foundation view doubles on macOS.
This checks ownership/restoration/compounding, not UIKit or device compatibility.
"""
from pathlib import Path
import platform, subprocess, tempfile
root = Path(__file__).resolve().parents[1]
s = (root/'Tweak.xm').read_text()
prefs = (root/'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
assert 'static BOOL LMVStackShadowEnabled = NO;' in s
assert 'object_getClass(view) == LMVStackShadowClass' in s
assert 'LMVStackShadowViews = [NSHashTable weakObjectsHashTable]' in s
assert 'NSClassFromString(@"NCNotificationListStackDimmingOverlayView")' in s
assert 'class_getInstanceMethod(LMVStackShadowClass, @selector(setAlpha:))' in s
assert '%init(LMVStackShadowHooks)' in s
assert 'for (UIView *view in LMVStackShadowViews.allObjects) LMVApplyStackShadow(view);' in s
assert '%hook UIView' not in s
assert '降低通知堆叠阴影' in prefs and '通知堆叠阴影透明度' in prefs
assert '[stackEnabled setProperty:@NO forKey:@"default"]' in prefs
assert '[stackOpacity setProperty:[self enabled:stackEnabled] forKey:@"enabled"]' in prefs
assert '([key isEqualToString:@"StackShadowEnabled"] ? @"StackShadowOpacity" : nil)' in prefs
print('PASS: exact class guard, optional hook init, weak ownership, live preferences, default off, dependent slider')
if platform.system() != 'Darwin':
    print('Actual Objective-C alpha lifecycle test requires macOS; runs in GitHub Actions')
    raise SystemExit(0)
start = s.index('// Independent compatibility option;')
end = s.index('static int LMVBlankToken', start)
helpers = s[start:end]
hook = s.split('%hook NCNotificationListStackDimmingOverlayView\n',1)[1].split('%end',1)[0]
hook = hook.replace('%orig(alpha);','[super setAlpha:alpha];').replace('%orig(state.appliedAlpha);','[super setAlpha:state.appliedAlpha];')
hook = hook.replace('%orig;\n    LMVApplyStackShadow', '[super layoutSubviews];\n    LMVApplyStackShadow',1)
hook = hook.replace('%orig;\n    LMVApplyStackShadow', '[super didMoveToWindow];\n    LMVApplyStackShadow',1)
hook = hook.replace('%orig;\n    LMVApplyStackShadow', '[super didMoveToSuperview];\n    LMVApplyStackShadow',1)
assert '%orig' not in hook
preamble = r'''
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <math.h>
#include <assert.h>
typedef double CGFloat;
@interface UIView : NSObject
@property(nonatomic) CGFloat alpha;
@property(nonatomic, weak) UIView *superview;
- (void)layoutSubviews;
- (void)didMoveToWindow;
- (void)didMoveToSuperview;
- (void)systemLayerAlpha:(CGFloat)alpha;
@end
@implementation UIView
- (instancetype)init { if ((self=[super init])) _alpha=1; return self; }
- (void)layoutSubviews {}
- (void)didMoveToWindow {}
- (void)didMoveToSuperview {}
- (void)systemLayerAlpha:(CGFloat)alpha { _alpha=alpha; }
@end
@interface NCNotificationListCell : UIView
@end
@implementation NCNotificationListCell
@end
'''
tests = r'''
@interface ShadowSubclass : NCNotificationListStackDimmingOverlayView
@end
@implementation ShadowSubclass
@end
static void near(CGFloat actual, CGFloat expected) { assert(fabs(actual-expected)<0.000001); }
static void refresh(void) { for (UIView *v in LMVStackShadowViews.allObjects) LMVApplyStackShadow(v); }
int main(void) { @autoreleasepool {
    LMVStackShadowClass=NCNotificationListStackDimmingOverlayView.class;
    LMVStackShadowViews=[NSHashTable weakObjectsHashTable];
    NCNotificationListStackDimmingOverlayView *v=[NCNotificationListStackDimmingOverlayView new];
    NCNotificationListCell *cell=[NCNotificationListCell new];
    cell.alpha=0.85;
    UIView *wrapper=[UIView new]; wrapper.superview=cell; v.superview=wrapper;
    [v setAlpha:0.8]; [v didMoveToWindow]; [v layoutSubviews]; near(v.alpha,0.8);
    assert(!objc_getAssociatedObject(v,&LMVStackShadowStateKey));
    LMVStackShadowEnabled=YES; refresh(); near(v.alpha,0.28);
    for (int i=0;i<100;i++) { [v layoutSubviews]; [v didMoveToWindow]; } near(v.alpha,0.28);
    [v setAlpha:0.6]; near(v.alpha,0.21); // Latest external alpha becomes baseline.
    LMVStackShadowOpacity=0.5; refresh(); near(v.alpha,0.3);
    LMVStackShadowOpacity=0; refresh(); near(v.alpha,0);
    [v setAlpha:0.4]; near(v.alpha,0); // Zero reduction retains an unreduced baseline.
    LMVStackShadowOpacity=1; refresh(); near(v.alpha,0.4);
    [v systemLayerAlpha:0.9]; [v layoutSubviews]; near(v.alpha,0.9);
    LMVStackShadowOpacity=0.35; refresh(); near(v.alpha,0.315);
    [v systemLayerAlpha:0.7]; [v layoutSubviews]; near(v.alpha,0.245);
    LMVStackShadowEnabled=NO; refresh(); near(v.alpha,0.7);
    assert(!objc_getAssociatedObject(v,&LMVStackShadowStateKey));
    [v setAlpha:0.2]; [v layoutSubviews]; near(v.alpha,0.2);
    LMVStackShadowEnabled=YES; refresh(); near(v.alpha,0.07);
    v.superview=nil; [v didMoveToSuperview]; near(v.alpha,0.2);
    assert(!objc_getAssociatedObject(v,&LMVStackShadowStateKey));
    [v setAlpha:0.6]; [v layoutSubviews]; near(v.alpha,0.6);
    v.superview=wrapper; [v didMoveToSuperview]; near(v.alpha,0.21);
    near(cell.alpha,0.85); near(wrapper.alpha,1);
    NCNotificationListStackDimmingOverlayView *outside=[NCNotificationListStackDimmingOverlayView new];
    [outside setAlpha:0.8]; [outside layoutSubviews]; near(outside.alpha,0.8);
    assert(!objc_getAssociatedObject(outside,&LMVStackShadowStateKey));
    ShadowSubclass *child=[ShadowSubclass new]; [child setAlpha:0.8]; [child layoutSubviews]; near(child.alpha,0.8);
    assert(!objc_getAssociatedObject(child,&LMVStackShadowStateKey));
    UIView *other=[UIView new]; other.alpha=0.75; LMVApplyStackShadow(other); near(other.alpha,0.75);
    Class saved=LMVStackShadowClass; LMVStackShadowClass=Nil; LMVApplyStackShadow(other); near(other.alpha,0.75); LMVStackShadowClass=saved;
    __weak UIView *weakView;
    @autoreleasepool {
        UIView *temporary=[NCNotificationListStackDimmingOverlayView new];
        temporary.superview=cell; weakView=temporary; LMVApplyStackShadow(temporary);
    }
    assert(!weakView); // Weak registry must not retain removed views.
    LMVStackShadowEnabled=NO; refresh(); near(v.alpha,0.6);
    puts("PASS: actual alpha helper and setter, 100 repeated layouts, system updates, 0/1 endpoints, immediate off restoration, re-enable, direct-layer changes, exact-class and cell ancestry exclusion, detach restoration, untouched cell/wrapper alpha, missing class, weak teardown (Foundation doubles; not device-tested)");
} return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    src=Path(tmp)/'shadow.m'; binary=Path(tmp)/'shadow'
    src.write_text(preamble+helpers+'\n@interface NCNotificationListStackDimmingOverlayView : UIView\n@end\n@implementation NCNotificationListStackDimmingOverlayView\n'+hook+'\n@end\n'+tests)
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(src),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True)
