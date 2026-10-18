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
action_prime = function('static void LMVPrimeActionBackgrounds(UIView *presenter)')
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
                  'LMVSourceForTarget', 'LMVCachedFrame', 'subviews'):
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
print('PASS: structural Message discovery, lifecycle prime/batch, O(1) geometry and system-background preservation contracts')
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
@class LMVVideoState;
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
@property(nonatomic) CGImageRef lastImage;
@property(nonatomic,copy) NSString *path, *registryKey, *ownerTarget;
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
static void LMVPerfProbe(const char *label, CFTimeInterval started) {}
static void LMVCardPipelineAudit(UIView *owner, LMVVideoState *state, NSString *target, UIView *anchor, NSString *stage) {}
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
static NSString *LMVSourceRegistryKey(NSString *path, NSString *target);
static LMVSharedSource *LMVSourceForTarget(NSString *path, NSString *target) {
    sourceRequests++; NSString *key=LMVSourceRegistryKey(path,target);
    return key ? LMVSharedSources[key] : nil;
}
static void LMVStartSource(LMVSharedSource *source) { source.playing=YES; }
static void LMVStopSource(LMVSharedSource *source) { source.playing=NO; }
static void LMVSourcePause(LMVSharedSource *source) { source.playing=NO; }
static void LMVSyncDisplayLink(void) {}
static void LMVRequestSyncDisplayLink(void) { LMVSyncDisplayLink(); }
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
    LMVSharedSources=[NSMutableDictionary new];
    // 1.76.1: one chain per CHANNEL. Seed one per channel per file, so a channel
    // that never opened a card still has the chain its cards will reuse.
    for (NSString *path in @[@"movie",@"movie2"]) {
        for (NSString *target in LMVTargets()) {
            LMVSharedSource *source=[LMVSharedSource new];source.identifier=LMVSharedSources.count+1;
            source.path=path;source.ownerTarget=target;source.registryKey=LMVSourceRegistryKey(path,target);
            assert(source.registryKey);LMVSharedSources[source.registryKey]=source;
        }
    }
    assert(LMVSharedSources.count==6);
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
static void bound(UIView *cell, MTMaterialView *m, CGFloat alpha=.73) {
    LMVVideoState *s=state(cell);assert(s && s.anchor==m && s.host==m.superview);
    assert(s.overlay.superview==m.superview && !s.originalAnchor && !s.originalScope);
    assert(!s.originals.count && ![LMVOriginalLeases() objectForKey:m.layer]);
    assert(m.layer.superlayer==m.superview.layer && near(m.layer.opacity,alpha));
    assert(m.layer.delegate==m);
    assert(s.layer.contents==(__bridge id)snapshot.image && s.layer.superlayer==s.overlay.layer);
    assert(CGRectEqualToRect(s.overlay.frame,[m convertRect:m.bounds toView:m.superview]));
    assert(CGRectEqualToRect(s.layer.frame,s.overlay.bounds));
    assert(s.overlay.layer.cornerRadius==m.layer.cornerRadius && !s.overlay.layer.mask);
    assert(near(s.overlay.alpha,LMVCardOpacity()));
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
    clockNow+=.01;assert(LMVPrimeMessageCard(cell));bound(cell,m,alphaZero?0:.73);
    LMVVideoState *s=state(cell);UIView *overlay=s.overlay;CALayer *layer=s.layer;
    assert(!s.originals.count && near(m.alpha,alphaZero?0:.73));
    // Hidden/zero-alpha ORIGINAL sibling does not hide our video surface.
    assert(s.active && s.source==LMVSharedSources[LMVSourceRegistryKey(@"movie",@"Message")]);
    m.hidden=NO;m.alpha=.73;clockNow+=.02;LMVUpdate(cell);bound(cell,m);
    assert(state(cell)==s && s.overlay==overlay && s.layer==layer && !s.originals.count);
    assert(s.source==LMVSharedSources[LMVSourceRegistryKey(@"movie",@"Message")] && near(m.alpha,.73));
    assert([s.source.ownerTarget isEqual:@"Message"]);
    LMVSharedSource *source=s.source;NSUInteger updates=fullUpdates,reads=cacheReads,allocations=viewAllocations,requests=sourceRequests;
    NSUInteger walks=subtreeReads;
    for(int n=0;n<50;n++) {
        m.frame=CGRectMake(13+n,17+n,280-n,90+n);
        assert(!LMVPrimeMessageCard(cell));
        assert(CGRectEqualToRect(overlay.frame,m.frame));
        assert(CGRectEqualToRect(layer.frame,overlay.bounds));
    }
    assert(fullUpdates==updates && cacheReads==reads && viewAllocations==allocations);
    assert(sourceRequests==requests); // No new source on stable visibility checks.
    assert(subtreeReads-walks<=250); // Actual attachment/exposure ancestry queries are bounded.
    assert(state(cell)==s && s.overlay==overlay && s.layer==layer && s.source==source && !s.originals.count);
    bound(cell,m);
    // Transient hiding/alpha/viewport loss retain only our overlay, never a lease.
    wrapper.hidden=YES;clockNow+=.01;LMVUpdate(cell);bound(cell,m);
    wrapper.hidden=NO;wrapper.alpha=0;clockNow+=.01;LMVUpdate(cell);bound(cell,m);
    wrapper.alpha=1;m.hidden=YES;clockNow+=.01;LMVUpdate(cell);bound(cell,m);
    m.hidden=NO;m.alpha=0;clockNow+=.01;LMVUpdate(cell);bound(cell,m,0);
    assert(s.source==source && s.overlay==overlay && !s.originals.count);
    cell.frame=CGRectMake(30,1200,320,160);clockNow+=.25;LMVUpdate(cell);bound(cell,m,0);
    assert(!s.active && s.overlay==overlay && !s.originals.count);
    cell.frame=CGRectMake(30,60,320,160);m.alpha=.73;LMVUpdate(cell);bound(cell,m);
    playback=NO;LMVUpdate(cell);bound(cell,m);playback=YES;
    LMVOpacityEnabled=NO;LMVUpdate(cell);bound(cell,m);assert(s.active && near(overlay.alpha,1));LMVOpacityEnabled=YES;
    LMVOpacity=0;LMVUpdate(cell);bound(cell,m);assert(!s.active && near(overlay.alpha,0));LMVOpacity=.55;
    unbind(cell);assert(!state(cell) && !overlay.superview && near(m.layer.opacity,.73) && !s.originals.count);
    [CATransaction commit];
}
'''

scenarios = r'''
static void testReplacement(void) {
    configure();UIWindow *window=[UIWindow new];UIView *wrapper;MTMaterialView *old;
    NCNotificationListCell *cell=card(window,&wrapper,&old);assert(LMVPrimeMessageCard(cell));bound(cell,old);
    LMVVideoState *s=state(cell);UIView *overlay=s.overlay;assert(!s.originals.count);
    // The very next pass (<100ms since discovery) must replace an invalid host.
    objc_setAssociatedObject(cell,&LMVDiscoveryKey,@(clockNow),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [old removeFromSuperview];MTMaterialView *next=material();[wrapper addSubview:next];clockNow+=.01;
    LMVUpdate(cell);bound(cell,next);
    assert(near(old.layer.opacity,.73) && !s.originals.count && !s.originalAnchor);
    assert(state(cell)==s && s.overlay==overlay);
    // A newly inserted sibling changes model host identity without detaching the anchor.
    UIView *other=view(UIView.class,CGRectMake(7,9,300,130));[cell addSubview:other];
    [other addSubview:next];clockNow+=.01;
    assert(LMVPrimeMessageCard(cell));bound(cell,next);
    assert(s.host==other && overlay.superview==other && !s.originals.count);
    // Lost plugin overlay is repaired synchronously before the current commit.
    [overlay removeFromSuperview];clockNow+=.01;assert(LMVPrimeMessageCard(cell));bound(cell,next);
    // A second invalid host: the prime itself must perform same-turn discovery.
    [next removeFromSuperview];MTMaterialView *third=material();[other addSubview:third];
    objc_setAssociatedObject(cell,&LMVDiscoveryKey,@(clockNow),OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    clockNow+=.01;assert(LMVPrimeMessageCard(cell));bound(cell,third);
    assert(!s.originals.count && near(next.layer.opacity,.73));
    // Selection changes replace owned state without touching the system backing.
    LMVVideoState *previous=s;UIView *previousOverlay=s.overlay;
    LMVPaths[@"Message"]=@"movie2";clockNow+=.01;LMVUpdate(cell);bound(cell,third);
    s=state(cell);assert(s!=previous && !previousOverlay.superview && !previous.originals.count);
    assert([s.path isEqualToString:@"movie2"] && [s.revision isEqualToString:@"r2"]);
    // Detachment restores immediately, even though old state may retain cache.
    UIView *currentOverlay=s.overlay;[third removeFromSuperview];clockNow+=.01;
    LMVUpdate(cell);assert(!s.originals.count && near(third.layer.opacity,.73));
    assert(!currentOverlay.superview && !s.originals.count && !s.anchor && !s.host);
    [other addSubview:third];clockNow+=.01;assert(LMVPrimeMessageCard(cell));bound(cell,third);
    // Whole-cell detach keeps model views alive but must release the background.
    [cell removeFromSuperview];clockNow+=.01;LMVUpdate(cell);
    assert(!state(cell).originals.count && near(third.layer.opacity,.73));
    [window addSubview:cell];clockNow+=.01;LMVUpdate(cell);bound(cell,third);
    // Empty selection and disable remove only the owned surface.
    [LMVPaths removeObjectForKey:@"Message"];LMVUpdate(cell);
    assert(!state(cell) && !s.originals.count && near(third.layer.opacity,.73));
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
    LMVVideoState *actionState=headerStates[@"Options"];assert(actionState.anchor==option && near(option.layer.opacity,.73) && !actionState.originals.count);
    UIButton *clearButton=[UIButton new];clearButton.testTitle=@"Clear All";MTMaterialView *clear=material();
    [presenter addSubview:clearButton];[clearButton addSubview:clear];
    LMVEnabled[@"Clear"]=@YES;LMVPaths[@"Clear"]=@"movie";
    clockNow+=.01;LMVUpdate(header);headerStates=objc_getAssociatedObject(header,&LMVStatesKey);assert(!headerStates[@"Clear"]);
    clockNow+=.101;LMVUpdate(header);headerStates=objc_getAssociatedObject(header,&LMVStatesKey);
    LMVVideoState *clearState=headerStates[@"Clear"];assert(clearState.anchor==clear && near(clear.layer.opacity,.73) && !clearState.originals.count);
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
    LMVVideoState *beforeReuse=state(cell);UIView *overlay=beforeReuse.overlay;
    LMVTestReuse(cell);assert(!beforeReuse.originals.count && near(m.alpha,.73) && !overlay.superview && !state(cell));
    assert(!objc_getAssociatedObject(cell,&LMVHostsKey) && !objc_getAssociatedObject(cell,&LMVDiscoveryKey));
    assert(LMVPrimeMessageCard(cell));bound(cell,m);unbind(cell);[CATransaction commit];
}
static void testAllTargetReplacementPolicy(void) {
    for (NSString *target in @[@"Message",@"Options",@"Clear"]) {
        configure(); LMVEnabled[@"Message"]=@NO; [LMVPaths removeAllObjects];
        LMVEnabled[target]=@YES; LMVPaths[target]=@"movie";
        // Cold/error/not-ready: no image/source; true custom alpha0 only pauses video.
        snapshot=[LMVFrameSnapshot new]; [LMVSharedSources removeAllObjects];
        LMVOpacity=0; LMVReadyAssets=[NSSet set];
        UIWindow *window=[UIWindow new]; UIView *wrapper; MTMaterialView *m;
        NCNotificationListCell *cell=card(window,&wrapper,&m);
        PLActionButtonsPresentingView *presenter=nil; UIButton *button=nil;
        if (![target isEqual:@"Message"]) {
            [m removeFromSuperview]; presenter=[PLActionButtonsPresentingView new];
            button=[UIButton new]; button.testTitle=[target isEqual:@"Clear"]?@"Clear All":@"Options";
            [wrapper addSubview:presenter]; [presenter addSubview:button]; [button addSubview:m];
        }
        m.layer.backgroundColor=NULL; assert(!m.layer.contents && !m.layer.sublayers.count);
        CGRect systemFrame=m.frame; CALayer *systemLayer=m.layer; UIView *systemHost=m.superview;
        UILabel *text=[UILabel new]; text.text=@"retained content"; text.alpha=.81; [wrapper addSubview:text];
        LMVUpdate(cell);
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey); LMVVideoState *s=states[target];
        assert(s && s.anchor==m && !s.originals.count && !s.layer.contents && !s.source && !s.active);
        assert(m.layer==systemLayer && near(m.alpha,.73) && m.layer.superlayer==systemHost.layer);
        assert(CGRectEqualToRect(m.frame,systemFrame) && !m.hidden && !s.originalAnchor && !s.originalScope);
        UIView *overlay=s.overlay; CALayer *video=s.layer;
        // Opacity setting OFF means default alpha1, not a transparent/nonplaying video.
        LMVOpacityEnabled=NO; clockNow+=.01; LMVUpdate(cell);
        assert(!s.originals.count && near(m.alpha,.73) && near(overlay.alpha,1) && s.active);
        assert(overlay==s.overlay && video==s.layer && !s.source && !video.contents);
        // Return to a genuine alpha0: retain the system material and pause consumption.
        LMVOpacityEnabled=YES; clockNow+=.01; LMVUpdate(cell);
        assert(!s.active && near(overlay.alpha,0) && near(m.alpha,.73));
        video.opacity=0;
        wrapper.hidden=YES; clockNow+=.101; LMVUpdate(cell);
        assert(!s.originals.count && near(m.alpha,.73) && !s.active);
        wrapper.hidden=NO; cell.frame=CGRectMake(30,2000,320,160); clockNow+=.101; LMVUpdate(cell);
        assert(!s.originals.count && near(m.alpha,.73) && !s.active);
        cell.frame=CGRectMake(30,60,320,160); clockNow+=.101; LMVUpdate(cell);
        // A system opacity update is not a dirty plugin lease: never re-suppress it.
        [CATransaction begin]; [CATransaction setDisableActions:YES]; m.layer.opacity=.62;
        assert(!LMVOriginalBackgroundNeedsMaintenance(s));
        if ([target isEqual:@"Message"]) assert(!LMVPrimeMessageCard(cell));
        else LMVPrimeActionBackgrounds(presenter);
        assert(near(m.alpha,.62) && !LMVOriginalBackgroundNeedsMaintenance(s) && !s.originals.count);
        [CATransaction commit];
        assert(m.layer==systemLayer && m.superview==systemHost && CGRectEqualToRect(m.frame,systemFrame));
        assert(text.layer.opacity==.81f && text.layer.superlayer==wrapper.layer && !text.hidden);
        if (button) assert(button.layer.opacity==1 && !button.hidden);
        // Selection/OFF/reuse remove only the overlay and reveal the unchanged system.
        [LMVPaths removeObjectForKey:target]; LMVUpdate(cell);
        states=objc_getAssociatedObject(cell,&LMVStatesKey);
        assert(!states[target] && !s.originals.count && !overlay.superview && near(m.alpha,.62));
        LMVPaths[target]=@"movie"; clockNow+=.101; LMVUpdate(cell);
        states=objc_getAssociatedObject(cell,&LMVStatesKey); s=states[target]; assert(s && !s.originals.count);
        overlay=s.overlay; LMVEnabled[target]=@NO; LMVUpdate(cell);
        states=objc_getAssociatedObject(cell,&LMVStatesKey);
        assert(!states[target] && !overlay.superview && near(m.alpha,.62));
        LMVEnabled[target]=@YES; clockNow+=.101; LMVUpdate(cell);
        states=objc_getAssociatedObject(cell,&LMVStatesKey); s=states[target]; assert(s && !s.originals.count);
        overlay=s.overlay; LMVTestReuse(cell); assert(near(m.alpha,.62) && !s.originals.count && !overlay.superview);
        clockNow+=.101; LMVUpdate(cell); states=objc_getAssociatedObject(cell,&LMVStatesKey); s=states[target];
        assert(s && !s.originals.count); [cell removeFromSuperview]; clockNow+=.101; LMVUpdate(cell);
        assert(!s.originals.count && near(m.alpha,.62) && m.layer==systemLayer && CGRectEqualToRect(m.frame,systemFrame));
        [CATransaction commit];
    }
}
static void testLeaseUpgradeRestore(void) {
    for (NSString *target in LMVTargets()) for (NSNumber *method in @[@(LMVOriginalSuppressDrawing),@(LMVOriginalDetach)]) {
        configure(); UIWindow *window=[UIWindow new]; UIView *wrapper; MTMaterialView *m;
        NCNotificationListCell *cell=card(window,&wrapper,&m); assert(LMVPrimeMessageCard(cell));
        LMVVideoState *s=state(cell); UIView *overlay=s.overlay; CALayer *video=s.layer;
        CALayer *original=m.layer; CGFloat baseline=.73;
        if(method.unsignedIntegerValue==LMVOriginalDetach){original=[CALayer layer];original.opacity=.37;[m.layer addSublayer:original];baseline=.37;}
        LMVOriginalLease *legacy=LMVAcquireOriginal(original,wrapper.layer,(LMVOriginalMethod)method.unsignedIntegerValue,s);
        assert(legacy && (method.unsignedIntegerValue==LMVOriginalDetach?!original.superlayer:original.opacity==0));
        s.originals=@[legacy];s.originalAnchor=m;s.originalScope=wrapper;
        // Upgrade via maintenance must restore even a clean, currently suppressed lease.
        LMVMaintainOriginalBackground(s,cell,target,YES);
        assert(legacy.retired && !s.originals.count && !s.originalAnchor && !s.originalScope);
        assert(original.superlayer==(original==m.layer?wrapper.layer:m.layer) && near(original.opacity,baseline));
        LMVReplaceBackground(s,m,wrapper,target,YES);
        assert(!s.originals.count && overlay==s.overlay && video==s.layer && near(original.opacity,baseline));
        unbind(cell);[CATransaction commit];
    }
}
static void testIndependentVisibleConsumers(void) {
 configure();for(NSString *t in LMVTargets()){LMVEnabled[t]=@YES;LMVPaths[t]=@"movie";}
 UIWindow *window=[UIWindow new];NSMutableDictionary *owners=[NSMutableDictionary new];
 for(NSString *target in LMVTargets()) {
  NSMutableArray *cards=[NSMutableArray new];owners[target]=cards;
  for(int n=0;n<2;n++) {
   UIView *wrapper;MTMaterialView *material;NCNotificationListCell *cell=card(window,&wrapper,&material);
   LMVVideoState *v=[LMVVideoState new];v.path=@"movie";v.anchor=material;v.host=wrapper;
   v.overlay=view(UIView.class,material.frame);v.overlay.userInteractionEnabled=NO;[wrapper addSubview:v.overlay];
   v.layer=[CALayer layer];[v.overlay.layer addSublayer:v.layer];
   v.overlay.layer.name=@"com.minis.lockmessagevideo.card.surface";v.layer.name=@"com.minis.lockmessagevideo.card.render";
   objc_setAssociatedObject(v.overlay,&LMVOwnershipKey,@{@"target":target,@"host":[NSValue valueWithNonretainedObject:wrapper]},OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   objc_setAssociatedObject(cell,&LMVStatesKey,[@{target:v} mutableCopy],OBJC_ASSOCIATION_RETAIN_NONATOMIC);
   [cards addObject:cell];LMVReconcileCardSources(cell);assert(v.active && v.source.playing);
  }
  NSDictionary *one=objc_getAssociatedObject(cards[0],&LMVStatesKey),*two=objc_getAssociatedObject(cards[1],&LMVStatesKey);
  assert(((LMVVideoState *)one[target]).source==((LMVVideoState *)two[target]).source);
 }
 // 1.76.1: one chain per CHANNEL. Message/Options/Clear all select "movie" but
 // share nothing between channels; the two cards inside one channel still share
 // that channel's chain - that is the "cards reuse their own source" contract.
 LMVSharedSource *message=LMVSharedSources[LMVSourceRegistryKey(@"movie",@"Message")];
 LMVSharedSource *options=LMVSharedSources[LMVSourceRegistryKey(@"movie",@"Options")];
 LMVSharedSource *clear=LMVSharedSources[LMVSourceRegistryKey(@"movie",@"Clear")];
 assert(message && options && clear && message!=options && options!=clear && message!=clear);
 assert(LMVSharedSources.count==6);
 for(NSString *t in LMVTargets())for(UIView *cell in owners[t])
   assert(((LMVVideoState *)((NSDictionary *)objc_getAssociatedObject(cell,&LMVStatesKey))[t]).source
          ==LMVSharedSources[LMVSourceRegistryKey(@"movie",t)]);
 UIView *first=owners[@"Message"][0],*second=owners[@"Message"][1];
 first.hidden=YES;LMVReconcileCardSources(first);assert(message.playing);
 second.hidden=YES;LMVReconcileCardSources(second);
 assert(!message.playing);                  // the last Message consumer is gone
 assert(options.playing && clear.playing);  // neighbours are untouched
 for(NSString *t in LMVTargets())for(UIView *cell in owners[t]){cell.hidden=YES;LMVReconcileCardSources(cell);}
 assert(!message.playing && !options.playing && !clear.playing);
 for(NSString *t in LMVTargets())for(UIView *cell in owners[t]){cell.hidden=NO;LMVReconcileCardSources(cell);}
 assert(message.playing && options.playing && clear.playing);
 first.hidden=NO;LMVReconcileCardSources(first);
 LMVVideoState *v=((NSDictionary *)objc_getAssociatedObject(first,&LMVStatesKey))[@"Message"];
 assert(v.source==message);v.anchor.hidden=YES;LMVReconcileCardSources(first);assert(message.playing);
 v.overlay.hidden=YES;LMVReconcileCardSources(first);assert(message.playing);
 for(UIView *cell in owners[@"Message"]){v=((NSDictionary *)objc_getAssociatedObject(cell,&LMVStatesKey))[@"Message"];if(v)v.overlay.hidden=YES;}
 for(NSString *t in @[@"Options",@"Clear"])for(UIView *cell in owners[t])cell.hidden=YES;
 for(NSString *t in LMVTargets())for(UIView *cell in owners[t])LMVReconcileCardSources(cell);
 assert(!message.playing);
 v.overlay.hidden=NO;
 for(NSString *t in LMVTargets())for(UIView *cell in owners[t]){cell.hidden=NO;LMVReconcileCardSources(cell);}
 // One cell carrying all three targets binds each channel to its own chain.
 UIView *wrapper; MTMaterialView *m; NCNotificationListCell *mixed=card(window,&wrapper,&m);
 PLActionButtonsPresentingView *presenter=[PLActionButtonsPresentingView new];[wrapper addSubview:presenter];
 NSMutableDictionary *materials=[@{@"Message":m} mutableCopy];
 for(NSString *t in @[@"Options",@"Clear"]){
  UIButton *b=[UIButton new];b.testTitle=[t isEqual:@"Clear"]?@"Clear All":@"Options";
  MTMaterialView *a=material();[presenter addSubview:b];[b addSubview:a];materials[t]=a;
 }
 clockNow+=.101;LMVUpdate(mixed);
 NSDictionary *mixedStates=objc_getAssociatedObject(mixed,&LMVStatesKey);
 LMVVideoState *ms=mixedStates[@"Message"],*os=mixedStates[@"Options"],*cs=mixedStates[@"Clear"];
 assert(ms && os && cs && ms.source==message && os.source==options && cs.source==clear);
 UIView *messageOverlay=ms.overlay,*optionsOverlay=os.overlay,*clearOverlay=cs.overlay;
 CGRect mf=m.frame,of=((UIView *)materials[@"Options"]).frame,cf=((UIView *)materials[@"Clear"]).frame;
 LMVEnabled[@"Message"]=@NO;
 for(UIView *cell in owners[@"Message"])LMVUpdate(cell);
 LMVUpdate(mixed);mixedStates=objc_getAssociatedObject(mixed,&LMVStatesKey);
 // Disabling one category drops only its overlays and pauses only its own chain.
 assert(!mixedStates[@"Message"] && !messageOverlay.superview && !message.playing);
 assert(options.playing && clear.playing);
 assert(mixedStates[@"Options"]==os && mixedStates[@"Clear"]==cs);
 assert(os.overlay==optionsOverlay && cs.overlay==clearOverlay);
 assert(near(m.alpha,.73) && CGRectEqualToRect(m.frame,mf) && !ms.originals.count);
 LMVEnabled[@"Message"]=@YES;clockNow+=.101;LMVUpdate(mixed);
 mixedStates=objc_getAssociatedObject(mixed,&LMVStatesKey);ms=mixedStates[@"Message"];
 assert(ms && ms.source==message && message.playing);
 [LMVPaths removeObjectForKey:@"Options"];
 for(UIView *cell in owners[@"Options"])LMVUpdate(cell);
 LMVUpdate(mixed);mixedStates=objc_getAssociatedObject(mixed,&LMVStatesKey);
 assert(!mixedStates[@"Options"] && !optionsOverlay.superview && message.playing);
 assert(mixedStates[@"Message"]==ms && mixedStates[@"Clear"]==cs);
 assert(cs.overlay==clearOverlay && near(((UIView *)materials[@"Options"]).alpha,.73));
 assert(near(((UIView *)materials[@"Clear"]).alpha,.73) && CGRectEqualToRect(((UIView *)materials[@"Options"]).frame,of));
 assert(CGRectEqualToRect(((UIView *)materials[@"Clear"]).frame,cf) && !os.originals.count && !cs.originals.count);
 // A channel moving to a DIFFERENT file gets its own chain; the neighbours keep theirs.
 [LMVPaths setObject:@"movie2" forKey:@"Options"];
 LMVSharedSource *other=LMVSharedSources[LMVSourceRegistryKey(@"movie2",@"Options")];
 assert(other && other!=message && LMVSourceForTarget(@"movie2",@"Options")==other &&
        LMVSourceForTarget(@"movie",@"Message")==message);
 mixed.hidden=YES;LMVReconcileCardSources(mixed);
 for(NSString *t in LMVTargets())for(UIView *cell in owners[t]){cell.hidden=YES;LMVReconcileCardSources(cell);}
 assert(!message.playing);
 [CATransaction commit];
}
int main(void) { @autoreleasepool {
    assert(NSThread.isMainThread);
    testEntry(NO);testEntry(YES);testReplacement();testIsolation();testPrimeGatesAndReuse();testAllTargetReplacementPolicy();testLeaseUpgradeRestore();testIndependentVisibleConsumers();
    [CATransaction flush];
    puts("PASS native: actual Tweak.xm update/discovery/prime/geometry + preservation/raw-lease headers; system background identity/frames preserved, hidden/alpha0 cached entry, 50 stable layouts, hierarchy visibility scope, <100ms replacement, reparent/overlay repair, path/disable/detach/reuse restore, labels/nested/owned overlay/header isolation, action throttle and launch/main-thread gates");
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
// Snapshot every SYSTEM view before a full binding pass. Owned overlay mutation
// is expected; all other identity/geometry/drawing attributes must be untouched.
static void LMVCaptureSystem(UIView *v, NSMutableArray *records) {
    if(objc_getAssociatedObject(v,&LMVOwnershipKey))return;
    NSMutableArray *order=[NSMutableArray new];
    for(CALayer *l in v.layer.sublayers)if(![l.name hasPrefix:@"com.minis.lockmessagevideo"]) [order addObject:l];
    CGRect systemFrame=v.frame;
    [records addObject:@{ @"view":v, @"layer":v.layer, @"parent":v.layer.superlayer?:NSNull.null,
        @"frame":[NSValue valueWithBytes:&systemFrame objCType:@encode(CGRect)],
        @"opacity":@(v.alpha), @"hidden":@(v.hidden), @"layerHidden":@(v.layer.hidden),
        @"radius":@(v.layer.cornerRadius), @"mask":v.layer.mask?:NSNull.null,
        @"contents":v.layer.contents?:NSNull.null, @"order":order }];
    for(UIView *child in v.subviews) LMVCaptureSystem(child,records);
}
static void LMVUpdate(UIView *cell) {
    NSMutableArray *records=[NSMutableArray new];LMVCaptureSystem(cell,records);
    fullUpdates++; LMVNativeUpdate(cell);
    for(NSDictionary *r in records) {
        UIView *v=r[@"view"];CGRect frame;[r[@"frame"] getValue:&frame];
        assert(v.layer==r[@"layer"] && (v.layer.superlayer?:NSNull.null)==r[@"parent"]);
        assert(CGRectEqualToRect(v.frame,frame) && v.alpha==[r[@"opacity"] doubleValue]);
        assert(v.hidden==[r[@"hidden"] boolValue] && v.layer.hidden==[r[@"layerHidden"] boolValue]);
        assert(v.layer.cornerRadius==[r[@"radius"] doubleValue] && (v.layer.mask?:NSNull.null)==r[@"mask"]);
        assert((v.layer.contents?:NSNull.null)==r[@"contents"]);
        NSMutableArray *order=[NSMutableArray new];
        for(CALayer *l in v.layer.sublayers)if(![l.name hasPrefix:@"com.minis.lockmessagevideo"]) [order addObject:l];
        assert([order isEqualToArray:r[@"order"]]);
    }
}
'''
card_header=(ROOT/'LMVCardPresentation.h').read_text()
card_attached=card_header[card_header.index('static BOOL LMVCardLayerAttached'):card_header.index('static CGFloat LMVCardExposureAlpha')]
card_state=card_header[card_header.index('static BOOL LMVCardStateAttached'):card_header.index('static BOOL LMVCardColdProbe')]
# This suite freezes its explicit visibility double; execute the new exact
# ownership/target consumer helper. Presentation exposure runs in its own suite.
fragments = [prefix, support, function('static CGFloat LMVCardOpacity(void)'), function('static NSString *LMVSourceRegistryKey(NSString *path, NSString *target)'),
             objc_type('LMVVideoState'), rect_string,
             '#import "LMVBackgroundDiscovery.h"', card_attached, card_state, consumer, release]
fragments += [PRODUCTION[x] for x in SIGNATURES[:2]]
if candidate:
    fragments.append(candidate)
fragments += [PRODUCTION[x] for x in SIGNATURES[2:5]]
fragments += ['#import "LMVActionDiscovery.h"']
fragments += [PRODUCTION[x] for x in SIGNATURES[5:8]]
fragments += [actual_update, function('static void LMVReconcileCardSources(UIView *cell)'), prime, action_prime, queue_stubs, reuse, helpers, scenarios]
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
