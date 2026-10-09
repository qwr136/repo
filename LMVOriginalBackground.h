#pragma once
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

// Only callers that confirmed a pure background drawing branch may acquire.
// UIView backing layers stay attached; only independent drawing leaves detach.
typedef NS_ENUM(NSUInteger, LMVOriginalMethod) {
    LMVOriginalDetach, LMVOriginalSuppressDrawing
};
@interface LMVOriginalLease : NSObject
@property(nonatomic, weak) CALayer *layer;
@property(nonatomic, strong) CALayer *offlineLayer;
@property(nonatomic, weak) CALayer *parent, *before, *after, *scope, *anchor;
@property(nonatomic) NSUInteger index;
@property(nonatomic) float baselineOpacity;
@property(nonatomic) LMVOriginalMethod method;
@property(nonatomic, strong) NSHashTable<NSObject *> *owners;
@property(nonatomic) BOOL retired;
- (BOOL)maintain;
- (void)releaseOwner:(NSObject *)owner;
@end
static NSMapTable<CALayer *, LMVOriginalLease *> *LMVOriginalLeases(void) {
    static NSMapTable *leases;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ leases = [NSMapTable weakToWeakObjectsMapTable]; });
    return leases;
}
@implementation LMVOriginalLease
- (BOOL)maintain {
    NSCAssert(NSThread.isMainThread, @"background leases require main thread");
    CALayer *layer = self.layer;
    if (self.retired || !layer || !self.parent || !self.scope) return NO;
    CALayer *ancestor = self.parent;
    while (ancestor && ancestor != self.scope) ancestor = ancestor.superlayer;
    if (!ancestor) return NO;
    if (self.method == LMVOriginalDetach) {
        // UIKit may reinsert during layout. Re-detach only in the original scope.
        // A move to another parent belongs to the system, never follow it.
        if (layer.superlayer && layer.superlayer != self.parent) return NO;
        if (layer.superlayer) [layer removeFromSuperlayer];
    } else {
        if (layer.superlayer != self.parent) return NO;
        if (layer.opacity != 0.0f) {
            // Observe a newer system model value on scoped updates, not every frame.
            self.baselineOpacity = layer.opacity;
            layer.opacity = 0.0f;
        }
    }
    return YES;
}
- (void)restore {
    if (self.retired) return;
    self.retired = YES;
    CALayer *layer = self.layer, *parent = self.parent;
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    if (self.method == LMVOriginalDetach) {
        if (layer && parent && !layer.superlayer) {
            // Neighbour anchors survive unrelated insertions; numeric index is fallback.
            if (self.after.superlayer == parent) [parent insertSublayer:layer below:self.after];
            else if (self.before.superlayer == parent) [parent insertSublayer:layer above:self.before];
            else [parent insertSublayer:layer atIndex:(unsigned)MIN(self.index, parent.sublayers.count)];
        }
    } else if (layer && layer.opacity == 0.0f) {
        layer.opacity = self.baselineOpacity;
    }
    [CATransaction commit];
    if (layer && [LMVOriginalLeases() objectForKey:layer] == self) [LMVOriginalLeases() removeObjectForKey:layer];
    self.offlineLayer = nil;
}
- (void)releaseOwner:(NSObject *)owner {
    [self.owners removeObject:owner];
    // Weak tables may retain empty buckets; count only live owner objects.
    if (!self.owners.allObjects.count) [self restore];
}
- (void)dealloc { [self restore]; }
@end
static LMVOriginalLease *LMVAcquireOriginal(CALayer *layer, CALayer *scope,
                                           LMVOriginalMethod method, NSObject *owner) {
    NSCAssert(NSThread.isMainThread, @"background leases require main thread");
    if (!layer || !scope || !owner) return nil;
    LMVOriginalLease *lease = [LMVOriginalLeases() objectForKey:layer];
    if (lease) {
        if (lease.retired || lease.scope != scope || lease.method != method) return nil;
        if (![lease maintain]) return nil;
        [lease.owners addObject:owner];
        return lease;
    }
    CALayer *parent = layer.superlayer;
    NSUInteger index = [parent.sublayers indexOfObjectIdenticalTo:layer];
    if (!parent || index == NSNotFound) return nil;
    lease = [LMVOriginalLease new];
    lease.layer = layer; lease.scope = scope; lease.parent = parent;
    lease.index = index; lease.method = method; lease.baselineOpacity = layer.opacity;
    lease.before = index ? parent.sublayers[index - 1] : nil;
    lease.after = index + 1 < parent.sublayers.count ? parent.sublayers[index + 1] : nil;
    lease.owners = [NSHashTable weakObjectsHashTable];
    [lease.owners addObject:owner];
    if (method == LMVOriginalDetach) lease.offlineLayer = layer;
    [LMVOriginalLeases() setObject:lease forKey:layer];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    BOOL applied = [lease maintain];
    [CATransaction commit];
    return applied ? lease : nil;
}
static void LMVReleaseOriginals(NSArray<LMVOriginalLease *> *leases, NSObject *owner) {
    for (LMVOriginalLease *lease in leases) [lease releaseOwner:owner];
}
