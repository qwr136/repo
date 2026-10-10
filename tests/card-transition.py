#!/usr/bin/env python3
"""Message collapse/expand regression: contracts everywhere, real CA on macOS.

Run: python3 tests/card-transition.py
Darwin requires Xcode/CLT clang++, Foundation, CoreGraphics and QuartzCore.
UIKit views and playback/cache/visibility are doubles; Tweak.xm policy, prime,
geometry and original-background headers are extracted/imported at each run.
No AVFoundation decoder/device timing claim (covered by the existing suite).
"""
from pathlib import Path
import platform
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TEXT = (ROOT / 'Tweak.xm').read_text()


def function(signature):
    """Skip declarations; balance braces while ignoring comments and literals."""
    signature_pattern = r'\s*'.join(re.escape(part) for part in signature.split())
    match = re.search(signature_pattern + r'\s*(?:__attribute__\(\(unused\)\)\s*)?\{', TEXT)
    assert match, 'Missing production function: ' + signature
    token = re.compile(r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[{}]', re.S)
    depth = 1
    for item in token.finditer(TEXT, match.end()):
        if item.group() == '{':
            depth += 1
        elif item.group() == '}':
            depth -= 1
            if depth == 0:
                return TEXT[match.start():item.end()]
    raise AssertionError('Unbalanced production function: ' + signature)


def objc_type(name):
    parts = []
    for kind in ('interface', 'implementation'):
        match = re.search(r'@' + kind + r'\s+' + name + r'\b.*?@end', TEXT, re.S)
        assert match, name + ' ' + kind
        parts.append(match.group())
    return '\n'.join(parts)


SIGNATURES = [
    'static BOOL LMVActionBranch(UIView *view)',
    'static BOOL LMVIsClassOrSubclass(UIView *view, NSString *name)',
    'static UIView *LMVMessageMaterial(UIView *view, NSUInteger depth)',
    'static BOOL LMVMessageCell(UIView *cell)',
    'static NSString *LMVSemanticTarget(UIView *view)',
    'static void LMVActionHosts(UIView *view, NSMapTable *hosts, NSUInteger depth)',
    'static void LMVPause(LMVVideoState *state)',
    'static void LMVLayoutCardSurface(LMVVideoState *state, UIView *anchor, UIView *host)',
    'static void LMVUpdate(UIView *cell)',
    'static BOOL LMVPrimeMessageCard(UIView *cell)',
]
PRODUCTION = {signature: function(signature) for signature in SIGNATURES}
discovery = PRODUCTION[SIGNATURES[2]]
update = PRODUCTION[SIGNATURES[-2]]
prime = PRODUCTION[SIGNATURES[-1]]
geometry = PRODUCTION[SIGNATURES[-3]]
candidate_signature = 'static UIView *LMVMessageMaterialCandidate(UIView *view, NSUInteger depth, BOOL visibleOnly)'
candidate = function(candidate_signature) if 'LMVMessageMaterialCandidate' in discovery else ''
if candidate:
    assert 'visibleOnly' in candidate and 'LMVOwnershipKey' in candidate and 'NCNotificationListCell' in candidate
    assert 'YES' in discovery and 'NO' in discovery, 'Discover visible first, then structural fallback'
else:
    assert 'view.hidden' not in discovery and 'LMVOriginalVisibilityAlpha' not in discovery
    assert 'LMVOwnershipKey' in discovery and 'NCNotificationListCell' in discovery
compact_update = re.sub(r'\s+', '', update)
assert 'LMVMessageMaterial(cell,0)' in compact_update
assert 'LMVReplaceBackground(state,anchor,host,target,originalInScope)' in compact_update
assert 'LMVLayoutCardSurface(state,anchor,host)' in compact_update
message_gate = update.rfind('if (messageEligible')
message_find = update.rfind('LMVMessageMaterial(cell, 0)')
assert message_gate >= 0 and message_find > message_gate
assert '0.1' not in update[message_gate:message_find], 'Message discovery must bypass action throttle'
message_scope = re.search(r'if\s*\(\[target isEqualToString:@"Message"\]\)\s*\{(.*?)\n\s*\}', update, re.S)
assert message_scope and 'originalInScope' in message_scope.group(1)
assert 'isDescendantOfView:cell' in message_scope.group(1)
assert 'anchorVisible' not in message_scope.group(1) and 'LMVVisible' not in message_scope.group(1)
assert '0.1' in update and 'refreshActions' in update, 'Action throttle must remain'
assert 'LMVUpdate(cell)' in prime and 'LMVLayoutCardSurface' in prime
for contract in ('LMVInitialized', 'LMVLaunchReady', 'NSThread.isMainThread',
                 'LMVMessageCell', 'Message', 'LMVEnabled', 'LMVPaths'):
    assert contract in prime, 'Prime gate missing: ' + contract
for forbidden in ('LMVMessageMaterial', 'LMVActionHosts', 'LMVReplaceBackground',
                  'LMVSourceForPath', 'LMVCachedFrame', 'subviews'):
    assert forbidden not in geometry, 'Geometry must remain O(1): ' + forbidden
hook = TEXT.split('%hook NCNotificationListCell', 1)[1].split('%end', 1)[0]
for name in ('layoutSubviews', 'didMoveToWindow'):
    body = re.search(r'-\s*\(void\)' + name + r'\s*\{(.*?)\n\}', hook, re.S)
    assert body and body.group(1).index('%orig;') < body.group(1).index('LMVPrimeMessageCard')
    assert 'LMVRequestCardUpdate' in body.group(1), 'Keep normal batched update: ' + name
assert 'LMVForgetCardUpdate' in hook and 'LMVPause(state)' in hook
assert 'LMVRestoreBackground(state)' in PRODUCTION[SIGNATURES[6]]
for name in ('LMVOriginalBackground.h', 'LMVBackgroundDiscovery.h', 'LMVActionDiscovery.h'):
    assert (ROOT / name).is_file(), name
print('PASS: structural Message discovery, lifecycle prime/batch, O(1) geometry and real lease contracts')
if platform.system() != 'Darwin':
    print('SKIP native: real Foundation + QuartzCore execution requires macOS; Linux contracts only')
    raise SystemExit(0)

# Reuse the complete UIKit class catalog from the existing native lease runner.
# Its view hierarchy/coordinate placeholders are upgraded to real CA behavior.
base = (ROOT / 'tests/original-background.m').read_text()
prefix = base.split('@interface LMVVideoState', 1)[0]
prefix = prefix.replace('#import "../LMVOriginalBackground.h"', '#import "LMVOriginalBackground.h"')
prefix = prefix.replace('@class UIWindow;', '''#include <atomic>
static NSUInteger viewAllocations, subtreeReads, fullUpdates, cacheReads, sourceRequests, retries;
@class UIWindow;
typedef NS_OPTIONS(NSUInteger, UIViewAutoresizing) { UIViewAutoresizingNone = 0 };
''')
prefix = prefix.replace('@property(nonatomic) CGRect bounds;', '''@property(nonatomic) CGRect bounds;
@property(nonatomic) CGRect frame;
@property(nonatomic) CGAffineTransform transform;
@property(nonatomic) BOOL clipsToBounds, userInteractionEnabled;
@property(nonatomic) UIViewAutoresizing autoresizingMask;
- (void)removeFromSuperview;
- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index;
- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)sibling;''')
prefix = prefix.replace('@implementation UIView\n', '''@implementation UIView
@synthesize subviews = _subviews, window = _window;
- (NSMutableArray *)subviews { subtreeReads++; return _subviews; }
- (void)setWindow:(UIWindow *)window { _window=window; for (UIView *v in _subviews) v.window=window; }
- (CGRect)frame { return self.layer.frame; }
- (void)setFrame:(CGRect)frame { self.layer.frame=frame; }
- (CGAffineTransform)transform { return self.layer.affineTransform; }
- (void)setTransform:(CGAffineTransform)t { [self.layer setAffineTransform:t]; }
''')
prefix = prefix.replace('_layer=[CALayer layer];', 'viewAllocations++; _layer=[CALayer layer]; _layer.anchorPoint=CGPointZero; _layer.position=CGPointZero;')
prefix = prefix.replace('return rect;', 'return [self.layer convertRect:rect toLayer:view.layer];')
prefix = prefix.replace('- (void)addSubview:(UIView *)view { view.superview=self; view.window=self.window; [self.subviews addObject:view]; [self.layer addSublayer:view.layer]; }', '''
- (void)removeFromSuperview {
    [self.superview.subviews removeObjectIdenticalTo:self];
    self.superview=nil; self.window=nil; [self.layer removeFromSuperlayer];
}
- (void)insertSubview:(UIView *)view atIndex:(NSInteger)index {
    [view removeFromSuperview]; view.superview=self; view.window=self.window;
    [_subviews insertObject:view atIndex:(NSUInteger)index];
    [self.layer insertSublayer:view.layer atIndex:(unsigned)index];
}
- (void)addSubview:(UIView *)view { [self insertSubview:view atIndex:_subviews.count]; }
- (void)insertSubview:(UIView *)view aboveSubview:(UIView *)sibling {
    [view removeFromSuperview];
    NSUInteger index=[_subviews indexOfObjectIdenticalTo:sibling]; assert(index!=NSNotFound);
    [self insertSubview:view atIndex:index+1];
}''')
prefix = prefix.replace('@interface UILabel : UIView @end', '@interface UILabel : UIView\n@property(nonatomic,copy) NSString *text;\n@end')
# Keep NSStringFromCGRect exactly as in the existing runner.
rect_string = base.split('static NSString *NSStringFromCGRect(CGRect rect)', 1)[1].split('#import "../LMVBackgroundDiscovery.h"', 1)[0]
rect_string = 'static NSString *NSStringFromCGRect(CGRect rect)' + rect_string

support = r'''
@interface UIButton : UIControl
@property(nonatomic,copy) NSString *testTitle;
- (NSString *)currentTitle;
@end
@implementation UIButton
- (NSString *)currentTitle { return self.testTitle; }
@end
@interface NCNotificationListCell : UIView @end
@implementation NCNotificationListCell @end
@interface PLActionButtonsPresentingView : UIView @end
@implementation PLActionButtonsPresentingView @end
@interface LMVSharedSource : NSObject
@property(nonatomic) NSUInteger identifier;
@property(nonatomic) BOOL playing;
@end
@implementation LMVSharedSource @end
@interface LMVFrameSnapshot : NSObject
@property(nonatomic) CGImageRef image;
@end
@implementation LMVFrameSnapshot
- (void)dealloc { if (_image) CGImageRelease(_image); }
@end
static BOOL LMVInitialized=YES, LMVLaunchReady=YES, LMVOpacityEnabled=YES, LMVPreferencesDirty=NO;
static CGFloat LMVOpacity=.55;
static std::atomic_bool LMVDiagnosticsEnabled(false);
static char LMVStatesKey, LMVHostsKey, LMVDiscoveryKey, LMVRetryKey, LMVOwnershipKey, LMVMaintenanceKey;
static NSHashTable<UIView *> *LMVCells;
static NSMutableDictionary<NSString *,NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *,NSString *> *LMVPaths, *LMVRevisions;
static NSMutableDictionary<NSString *,LMVSharedSource *> *LMVSharedSources;
static NSSet *LMVReadyAssets;
static LMVFrameSnapshot *snapshot;
static BOOL playback=YES;
static CFTimeInterval clockNow=10;
#define CACurrentMediaTime() clockNow
static NSArray *LMVTargets(void) { return @[@"Message",@"Options",@"Clear"]; }
static void LMVDiagnostic(NSString *event) {}
static BOOL LMVPlaybackAllowed(void) { return playback; }
static BOOL LMVNotificationCenterSurface(UIView *view) { return view.window!=nil; }
// Visibility is explicitly a double. Geometry/leases/host discovery are real.
static BOOL LMVVisible(UIView *view) {
    if (!view.window || view.window.hidden || CGRectIsEmpty(view.bounds)) return NO;
    for (UIView *p=view;p;p=p.superview)
        if (p.hidden || LMVOriginalVisibilityAlpha(p)<.01) return NO;
    return CGRectIntersectsRect([view convertRect:view.bounds toView:view.window],view.window.bounds);
}
static LMVFrameSnapshot *LMVCachedFrame(NSString *path, NSString *revision) { cacheReads++; return snapshot; }
static LMVSharedSource *LMVSourceForPath(NSString *path) { sourceRequests++; return LMVSharedSources[path]; }
static void LMVStartSource(LMVSharedSource *source) { source.playing=YES; }
static void LMVStopSource(LMVSharedSource *source) { source.playing=NO; }
static void LMVSyncDisplayLink(void) {}
static void LMVRetryDiscovery(UIView *cell) { retries++; }
static void LMVUpdate(UIView *cell);
'''
# Visibility calls a production header function, so declare it before support.
support = 'static CGFloat LMVOriginalVisibilityAlpha(UIView *view);\n' + support

helpers = r'''
static BOOL near(float a,float b) { return fabsf(a-b)<.00001f; }
static void configure(void) {
    LMVEnabled=[@{@"Message":@YES,@"Options":@NO,@"Clear":@NO} mutableCopy];
    LMVPaths=[@{@"Message":@"movie"} mutableCopy];
    LMVRevisions=[@{@"movie":@"r1",@"movie2":@"r2"} mutableCopy];
    LMVSharedSource *source=[LMVSharedSource new];source.identifier=1;
    LMVSharedSources=[@{@"movie":source,@"movie2":[LMVSharedSource new]} mutableCopy];
    LMVCells=[NSHashTable weakObjectsHashTable];
    snapshot=[LMVFrameSnapshot new];
    unsigned char pixels[]={90,140,200,255};
    CFDataRef data=CFDataCreate(NULL,pixels,sizeof(pixels));
    CGDataProviderRef provider=CGDataProviderCreateWithCFData(data);
    CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
    snapshot.image=CGImageCreate(1,1,8,32,4,colors,kCGImageAlphaPremultipliedLast,
        provider,NULL,false,kCGRenderingIntentDefault);
    CGColorSpaceRelease(colors);CGDataProviderRelease(provider);CFRelease(data);
    assert(snapshot.image);
    LMVInitialized=LMVLaunchReady=LMVOpacityEnabled=playback=YES;LMVOpacity=.55;
    [CATransaction begin];[CATransaction setDisableActions:YES];
}
static UIView *view(Class cls, CGRect frame) {
    UIView *v=[cls new];v.frame=frame;return v;
}
static MTMaterialView *material(void) {
    MTMaterialView *m=(id)view(MTMaterialView.class,CGRectMake(13,17,280,90));
    m.layer.backgroundColor=CGColorGetConstantColor(kCGColorWhite);
    m.layer.cornerRadius=12;m.alpha=.73;return m;
}
static NCNotificationListCell *card(UIWindow *window, UIView **wrapper, MTMaterialView **m) {
    NCNotificationListCell *cell=(id)view(NCNotificationListCell.class,CGRectMake(30,60,320,160));
    *wrapper=view(UIView.class,CGRectMake(5,7,300,130));*m=material();
    [window addSubview:cell];[cell addSubview:*wrapper];[*wrapper addSubview:*m];[LMVCells addObject:cell];
    return cell;
}
static LMVVideoState *state(UIView *cell) {
    return ((NSDictionary *)objc_getAssociatedObject(cell,&LMVStatesKey))[@"Message"];
}
static void bound(UIView *cell, MTMaterialView *m) {
    LMVVideoState *s=state(cell);assert(s && s.anchor==m && s.host==m.superview);
    assert(s.overlay.superview==m.superview && s.originalAnchor==m && s.originalScope==m.superview);
    assert(s.originals.count==1 && s.originals.firstObject.layer==m.layer);
    assert(s.originals.firstObject.method==LMVOriginalSuppressDrawing);
    assert(m.layer.superlayer==m.superview.layer && m.layer.opacity==0);
    assert(s.layer.contents==(__bridge id)snapshot.image && s.layer.superlayer==s.overlay.layer);
    assert(CGRectEqualToRect(s.overlay.frame,[m convertRect:m.bounds toView:m.superview]));
    assert(CGRectEqualToRect(s.layer.frame,s.overlay.bounds));
    assert(s.overlay.layer.cornerRadius==m.layer.cornerRadius && !s.overlay.layer.mask);
    assert(near(s.overlay.alpha,LMVOpacityEnabled?LMVOpacity:0));
}
static void unbind(UIView *cell) {
    LMVEnabled[@"Message"]=@NO;LMVUpdate(cell);
}
static void testEntry(BOOL alphaZero) {
    configure();UIWindow *window=[UIWindow new];UIView *wrapper;MTMaterialView *m;
    NCNotificationListCell *cell=card(window,&wrapper,&m);
    if(alphaZero)m.alpha=0;else m.hidden=YES;
    // Structure is discoverable before UIKit publishes visible material pixels.
    assert(LMVMessageMaterial(cell,0)==m);
    objc_setAssociatedObject(cell,&LMVDiscoveryKey,@(clockNow),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    clockNow+=.01;assert(LMVPrimeMessageCard(cell));bound(cell,m);
    LMVVideoState *s=state(cell);UIView *overlay=s.overlay;CALayer *layer=s.layer;
    LMVOriginalLease *lease=s.originals.firstObject;
    assert(near(lease.baselineOpacity,alphaZero?0:.73));
    assert(!s.active && !s.source); // cache is seeded before visibility/playback
    m.hidden=NO;m.alpha=.73;clockNow+=.02;LMVUpdate(cell);bound(cell,m);
    assert(state(cell)==s && s.overlay==overlay && s.layer==layer && s.originals.firstObject==lease);
    assert(s.source==LMVSharedSources[@"movie"] && near(lease.baselineOpacity,.73));
    LMVSharedSource *source=s.source;NSUInteger updates=fullUpdates,reads=cacheReads,allocations=viewAllocations,requests=sourceRequests;
    NSUInteger walks=subtreeReads;
    for(int n=0;n<50;n++) {
        m.frame=CGRectMake(13+n,17+n,280-n,90+n);
        assert(!LMVPrimeMessageCard(cell));
        assert(CGRectEqualToRect(overlay.frame,m.frame));
        assert(CGRectEqualToRect(layer.frame,overlay.bounds));
    }
    assert(fullUpdates==updates && cacheReads==reads && viewAllocations==allocations);
    assert(sourceRequests==requests && subtreeReads==walks);
    assert(state(cell)==s && s.overlay==overlay && s.layer==layer && s.source==source && s.originals.firstObject==lease);
    bound(cell,m);
    // Transient ancestor/anchor hiding, alpha and viewport loss retain leases.
    wrapper.hidden=YES;clockNow+=.01;LMVUpdate(cell);bound(cell,m);
    wrapper.hidden=NO;wrapper.alpha=0;clockNow+=.01;LMVUpdate(cell);bound(cell,m);
    wrapper.alpha=1;m.hidden=YES;clockNow+=.01;LMVUpdate(cell);bound(cell,m);
    m.hidden=NO;m.alpha=0;clockNow+=.01;LMVUpdate(cell);bound(cell,m);
    assert(s.source==source && s.overlay==overlay && s.originals.firstObject==lease);
    cell.frame=CGRectMake(30,1200,320,160);clockNow+=.25;LMVUpdate(cell);bound(cell,m);
    assert(!s.active && s.overlay==overlay && s.originals.firstObject==lease);
    cell.frame=CGRectMake(30,60,320,160);m.alpha=.73;LMVUpdate(cell);bound(cell,m);
    playback=NO;LMVUpdate(cell);bound(cell,m);playback=YES;
    LMVOpacityEnabled=NO;LMVUpdate(cell);bound(cell,m);LMVOpacityEnabled=YES;
    unbind(cell);assert(!state(cell) && !overlay.superview && near(m.layer.opacity,.73) && lease.retired);
    [CATransaction commit];
}
'''

scenarios = r'''
static void testReplacement(void) {
    configure();UIWindow *window=[UIWindow new];UIView *wrapper;MTMaterialView *old;
    NCNotificationListCell *cell=card(window,&wrapper,&old);assert(LMVPrimeMessageCard(cell));bound(cell,old);
    LMVVideoState *s=state(cell);UIView *overlay=s.overlay;LMVOriginalLease *lease=s.originals.firstObject;
    // The very next pass (<100ms since discovery) must replace an invalid host.
    objc_setAssociatedObject(cell,&LMVDiscoveryKey,@(clockNow),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [old removeFromSuperview];MTMaterialView *next=material();[wrapper addSubview:next];clockNow+=.01;
    LMVUpdate(cell);bound(cell,next);
    assert(near(old.layer.opacity,.73) && lease.retired && s.originalAnchor!=old);
    assert(state(cell)==s && s.overlay==overlay);
    // A newly inserted sibling changes model host identity without detaching the anchor.
    UIView *other=view(UIView.class,CGRectMake(7,9,300,130));[cell addSubview:other];
    LMVOriginalLease *nextLease=s.originals.firstObject;[other addSubview:next];clockNow+=.01;
    assert(LMVPrimeMessageCard(cell));bound(cell,next);
    assert(s.host==other && overlay.superview==other && nextLease.retired);
    // Lost plugin overlay is repaired synchronously before the current commit.
    [overlay removeFromSuperview];clockNow+=.01;assert(LMVPrimeMessageCard(cell));bound(cell,next);
    // A second invalid host: the prime itself must perform same-turn discovery.
    lease=s.originals.firstObject;[next removeFromSuperview];MTMaterialView *third=material();[other addSubview:third];
    objc_setAssociatedObject(cell,&LMVDiscoveryKey,@(clockNow),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    clockNow+=.01;assert(LMVPrimeMessageCard(cell));bound(cell,third);
    assert(lease.retired && near(next.layer.opacity,.73));
    // Selection changes restore the old lease before a new state acquires it.
    LMVVideoState *previous=s;UIView *previousOverlay=s.overlay;lease=s.originals.firstObject;
    LMVPaths[@"Message"]=@"movie2";clockNow+=.01;LMVUpdate(cell);bound(cell,third);
    s=state(cell);assert(s!=previous && !previousOverlay.superview && lease.retired);
    assert([s.path isEqualToString:@"movie2"] && [s.revision isEqualToString:@"r2"]);
    // Detachment restores immediately, even though old state may retain cache.
    lease=s.originals.firstObject;UIView *currentOverlay=s.overlay;[third removeFromSuperview];clockNow+=.01;
    LMVUpdate(cell);assert(lease.retired && near(third.layer.opacity,.73));
    assert(!currentOverlay.superview && !s.originals.count && !s.anchor && !s.host);
    [other addSubview:third];clockNow+=.01;assert(LMVPrimeMessageCard(cell));bound(cell,third);
    // Whole-cell detach keeps model views alive but must release the background.
    lease=state(cell).originals.firstObject;[cell removeFromSuperview];clockNow+=.01;LMVUpdate(cell);
    assert(lease.retired && !state(cell).originals.count && near(third.layer.opacity,.73));
    [window addSubview:cell];clockNow+=.01;LMVUpdate(cell);bound(cell,third);
    // Empty selection and disable both release the lease and owned surface.
    lease=state(cell).originals.firstObject;[LMVPaths removeObjectForKey:@"Message"];LMVUpdate(cell);
    assert(!state(cell) && lease.retired && near(third.layer.opacity,.73));
    LMVPaths[@"Message"]=@"movie";assert(LMVPrimeMessageCard(cell));bound(cell,third);
    unbind(cell);assert(near(third.layer.opacity,.73));[CATransaction commit];
}
static void testIsolation(void) {
    configure();UIWindow *window=[UIWindow new];UIView *wrapper;MTMaterialView *m;
    NCNotificationListCell *cell=card(window,&wrapper,&m);
    UILabel *label=(id)view(UILabel.class,CGRectMake(0,0,100,20));label.text=@"message";label.alpha=.81;[wrapper addSubview:label];
    PLActionButtonsPresentingView *actions=(id)view(PLActionButtonsPresentingView.class,CGRectMake(0,100,200,50));
    MTMaterialView *actionMaterial=material();[actions addSubview:actionMaterial];[cell insertSubview:actions atIndex:0];
    NCNotificationListCell *nested=(id)view(NCNotificationListCell.class,CGRectMake(0,0,300,100));
    MTMaterialView *nestedMaterial=material();[nested addSubview:nestedMaterial];[cell insertSubview:nested atIndex:0];
    // An owned overlay with a MaterialView-like descendant must be opaque to discovery.
    UIView *owned=view(UIView.class,CGRectMake(0,0,300,100));MTMaterialView *fake=material();[owned addSubview:fake];
    objc_setAssociatedObject(owned,&LMVOwnershipKey,@{@"target":@"Message"},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [cell insertSubview:owned atIndex:0];
    MTMaterialView *hiddenOld=material();hiddenOld.hidden=YES;[wrapper insertSubview:hiddenOld atIndex:0];
    assert(LMVMessageMaterial(cell,0)==m);
    hiddenOld.hidden=NO;hiddenOld.alpha=0;assert(LMVMessageMaterial(cell,0)==m);
    [hiddenOld removeFromSuperview];assert(LMVPrimeMessageCard(cell));bound(cell,m);
    assert(label.superview==wrapper && label.layer.superlayer==wrapper.layer && near(label.alpha,.81) && [label.text isEqual:@"message"]);
    assert(near(actionMaterial.alpha,.73) && actionMaterial.layer.superlayer==actions.layer);
    assert(near(nestedMaterial.alpha,.73) && nestedMaterial.layer.superlayer==nested.layer && !state(nested));
    assert(near(fake.alpha,.73) && fake.layer.superlayer==owned.layer);
    // A material containing content uses a child overlay, never suppresses text.
    unbind(cell);[owned removeFromSuperview];[nested removeFromSuperview];[actions removeFromSuperview];[m addSubview:label];
    LMVEnabled[@"Message"]=@YES;assert(LMVPrimeMessageCard(cell));
    LMVVideoState *s=state(cell);assert(s.anchor==m && s.host==m && s.overlay.superview==m);
    assert(!s.originals.count && near(m.alpha,.73) && near(label.alpha,.81));
    assert(label.layer.superlayer==m.layer && m.subviews.firstObject==s.overlay);
    // Header surfaces are not Message cells; no seed or Message host is permitted.
    UIView *header=view(UIView.class,CGRectMake(0,0,320,80));MTMaterialView *headerMaterial=material();
    [window addSubview:header];[header addSubview:headerMaterial];NSUInteger before=fullUpdates;
    assert(!LMVPrimeMessageCard(header) && before==fullUpdates);LMVUpdate(header);
    assert(!state(header) && near(headerMaterial.alpha,.73));
    // Actual Clear/Options discovery retains its 100ms throttle.
    LMVEnabled[@"Options"]=@YES;LMVPaths[@"Options"]=@"movie";
    PLActionButtonsPresentingView *presenter=[PLActionButtonsPresentingView new];
    UIButton *button=[UIButton new];button.testTitle=@"Options";MTMaterialView *option=material();
    [header addSubview:presenter];[presenter addSubview:button];[button addSubview:option];
    objc_setAssociatedObject(header,&LMVDiscoveryKey,@(clockNow),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    clockNow+=.01;LMVUpdate(header);
    NSDictionary *headerStates=objc_getAssociatedObject(header,&LMVStatesKey);assert(!headerStates[@"Options"]);
    clockNow+=.101;LMVUpdate(header);headerStates=objc_getAssociatedObject(header,&LMVStatesKey);
    LMVVideoState *actionState=headerStates[@"Options"];assert(actionState.anchor==option && option.layer.opacity==0);
    UIButton *clearButton=[UIButton new];clearButton.testTitle=@"Clear All";MTMaterialView *clear=material();
    [presenter addSubview:clearButton];[clearButton addSubview:clear];
    LMVEnabled[@"Clear"]=@YES;LMVPaths[@"Clear"]=@"movie";
    clockNow+=.01;LMVUpdate(header);headerStates=objc_getAssociatedObject(header,&LMVStatesKey);assert(!headerStates[@"Clear"]);
    clockNow+=.101;LMVUpdate(header);headerStates=objc_getAssociatedObject(header,&LMVStatesKey);
    assert(((LMVVideoState *)headerStates[@"Clear"]).anchor==clear && clear.layer.opacity==0);
    assert(!state(header) && near(headerMaterial.alpha,.73));
    LMVEnabled[@"Options"]=LMVEnabled[@"Clear"]=@NO;LMVUpdate(header);
    assert(near(option.alpha,.73) && near(clear.alpha,.73));
    unbind(cell);[CATransaction commit];
}
static void testPrimeGatesAndReuse(void) {
    configure();UIWindow *window=[UIWindow new];UIView *wrapper;MTMaterialView *m;
    NCNotificationListCell *cell=card(window,&wrapper,&m);NSUInteger before=fullUpdates;
    LMVInitialized=NO;assert(!LMVPrimeMessageCard(cell));LMVInitialized=YES;
    LMVLaunchReady=NO;assert(!LMVPrimeMessageCard(cell));LMVLaunchReady=YES;
    LMVEnabled[@"Message"]=@NO;assert(!LMVPrimeMessageCard(cell));LMVEnabled[@"Message"]=@YES;
    [LMVPaths removeObjectForKey:@"Message"];assert(!LMVPrimeMessageCard(cell));LMVPaths[@"Message"]=@"movie";
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
        assert(!NSThread.isMainThread && !LMVPrimeMessageCard(cell));dispatch_semaphore_signal(done);
    });
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))==0);
    assert(fullUpdates==before && !state(cell));
    assert(LMVPrimeMessageCard(cell));bound(cell,m);
    LMVOriginalLease *lease=state(cell).originals.firstObject;UIView *overlay=state(cell).overlay;
    LMVTestReuse(cell);assert(lease.retired && near(m.alpha,.73) && !overlay.superview && !state(cell));
    assert(!objc_getAssociatedObject(cell,&LMVHostsKey) && !objc_getAssociatedObject(cell,&LMVDiscoveryKey));
    assert(LMVPrimeMessageCard(cell));bound(cell,m);unbind(cell);[CATransaction commit];
}
int main(void) { @autoreleasepool {
    assert(NSThread.isMainThread);
    testEntry(NO);testEntry(YES);testReplacement();testIsolation();testPrimeGatesAndReuse();
    [CATransaction flush];
    puts("PASS native: actual Tweak.xm update/discovery/prime/geometry + lease headers; hidden/alpha0 cached entry, 50 stable layouts, hierarchy visibility scope, <100ms replacement, reparent/overlay repair, path/disable/detach/reuse restore, labels/nested/owned overlay/header isolation, action throttle and launch/main-thread gates");
} return 0; }
'''

# Execute the actual reuse hook body too, stripping only Logos/UI batch plumbing.
reuse = re.search(r'-\s*\(void\)prepareForReuse\s*\{(.*?)\n\}', hook, re.S).group(1)
reuse = reuse.replace('%orig;', '').replace('(UIView *)self', 'cell')
reuse = re.sub(r'\bself\b', 'cell', reuse)
reuse = 'static void LMVTestReuse(UIView *cell) {\n' + reuse + '\n}'

release = function('static void LMVReleasePlayer(LMVVideoState *state)')
consumer = function('static BOOL LMVSourceHasConsumer(LMVSharedSource *source)')
queue_stubs = 'static void LMVForgetCardUpdate(UIView *cell) {}\n'
# Rename only at preprocessing time; the extracted production body is untouched.
# Count calls through a wrapper so 50 stable primes prove they skip LMVUpdate.
actual_update = '\n#define LMVUpdate LMVNativeUpdate\n' + update + '''
#undef LMVUpdate
static void LMVUpdate(UIView *cell) { fullUpdates++; LMVNativeUpdate(cell); }
'''
fragments = [prefix, support, objc_type('LMVVideoState'), rect_string,
             '#import "LMVBackgroundDiscovery.h"', consumer, release]
fragments += [PRODUCTION[x] for x in SIGNATURES[:2]]
if candidate:
    fragments.append(candidate)
fragments += [PRODUCTION[x] for x in SIGNATURES[2:5]]
fragments += ['#import "LMVActionDiscovery.h"']
fragments += [PRODUCTION[x] for x in SIGNATURES[5:8]]
fragments += [actual_update, prime, queue_stubs, reuse, helpers, scenarios]
with tempfile.TemporaryDirectory(prefix='lmv-card-transition-') as temporary:
    source = Path(temporary) / 'card-transition.mm'
    binary = Path(temporary) / 'card-transition'
    source.write_text('\n\n'.join(fragments))
    subprocess.run(['xcrun', 'clang++', '-std=c++17', '-fobjc-arc', '-fblocks',
                    '-Werror=implicit-function-declaration', '-I', str(ROOT),
                    '-framework', 'Foundation', '-framework', 'QuartzCore',
                    '-framework', 'CoreGraphics', str(source), '-o', str(binary)],
                   check=True, timeout=120)
    subprocess.run([str(binary)], check=True, timeout=30)
