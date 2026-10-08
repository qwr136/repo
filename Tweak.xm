#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <objc/runtime.h>
#import <notify.h>
#import <float.h>
#import <math.h>
#import <sys/stat.h>

static NSString * const LMVDirectory = @"/var/mobile/LockMessageVideo";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSHashTable<UIView *> *LMVCells;
static NSMutableDictionary<NSString *, NSString *> *LMVPaths;
// Stable semantic names prevent nil hosts when private MaterialView subclasses change.
static NSDictionary<NSString *, NSString *> *LMVMaterialSources;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *, AVURLAsset *> *LMVSources;
static NSMutableDictionary<NSString *, AVAsset *> *LMVAssets;
static NSMutableSet<NSString *> *LMVReadyAssets;
@class LMVSharedSource;
static NSMutableDictionary<NSString *, LMVSharedSource *> *LMVSharedSources;
static NSMutableDictionary<NSString *, NSString *> *LMVRevisions;
static dispatch_queue_t LMVFrameQueue;
static BOOL LMVFrameBusy;
static BOOL LMVCoverHidden;
static CIContext *LMVCIContext;
static CGFloat LMVOpacity = 0.55;
static BOOL LMVOpacityEnabled = YES;
static int LMVBlankToken = -1;
static char LMVStatesKey, LMVHostsKey, LMVDiscoveryKey, LMVRetryKey, LMVOwnershipKey;
static NSArray<NSString *> *LMVTargets(void) { return @[@"Message", @"Options", @"Clear"]; }
static void LMVUpdate(UIView *cell);
static void LMVSyncDisplayLink(void);
static void LMVReleaseAllPlayers(void);
static void LMVRefresh(BOOL reload);
static BOOL LMVVisible(UIView *view);
static CADisplayLink *LMVLink;

@interface LMVSharedSource : NSObject
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItemVideoOutput *output;
@property(nonatomic, assign) CGImageRef lastImage;
@property(nonatomic, copy) NSString *path;
@property(nonatomic) BOOL playing;
@property(nonatomic) BOOL frameBusy;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) CGAffineTransform imageTransform;
@property(nonatomic) CMTime lastTime;
@property(nonatomic, strong) id endObserver;
@end
@implementation LMVSharedSource
- (void)dealloc { [_player pause]; if (_lastImage) CGImageRelease(_lastImage); if (_endObserver) [NSNotificationCenter.defaultCenter removeObserver:_endObserver]; }
@end
@interface LMVVideoState : NSObject
@property(nonatomic, strong) UIView *overlay;
@property(nonatomic, strong) CALayer *layer;
@property(nonatomic, strong) LMVSharedSource *source;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *revision;
@property(nonatomic, weak) UIView *anchor;
@property(nonatomic, weak) UIView *host;
@property(nonatomic) BOOL active;
@property(nonatomic) CFTimeInterval lastVisible;
@property(nonatomic) CFTimeInterval visibilityLossSince;
@property(nonatomic) CFTimeInterval detachedSince;
@end
@implementation LMVVideoState
- (void)dealloc { [_overlay removeFromSuperview]; }
@end
@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end
static BOOL LMVPlaybackAllowed(void) {
    if (LMVCoverHidden) return NO;
    uint64_t blank = 1;
    if (LMVBlankToken < 0 || notify_get_state(LMVBlankToken, &blank) != NOTIFY_STATUS_OK || blank) return NO;
    // Notification Center can be visible with an unlocked UI. Per-view
    // visibility gates playback; display blanking remains the hard stop.
    return YES;
}

static NSString *LMVFileRevision(NSString *path) {
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) != 0 || !S_ISREG(info.st_mode)) return nil;
    return [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%ld:%lld:%ld",
        (unsigned long long)info.st_dev, (unsigned long long)info.st_ino,
        (long long)info.st_size, (long long)info.st_mtimespec.tv_sec,
        info.st_mtimespec.tv_nsec, (long long)info.st_ctimespec.tv_sec,
        info.st_ctimespec.tv_nsec];
}

static LMVSharedSource *LMVSourceForPath(NSString *path) {
    LMVSharedSource *source=(LMVSharedSource *)LMVSharedSources[path];
    if (source || !LMVAssets[path]) return source;
    AVPlayerItem *item=[AVPlayerItem playerItemWithAsset:LMVAssets[path]];
    item.preferredForwardBufferDuration=1;
    AVPlayerItemVideoOutput *output=[[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
    [item addOutput:output];
    AVPlayer *player=[AVPlayer playerWithPlayerItem:item];
    player.preventsDisplaySleepDuringVideoPlayback=NO; player.muted=YES; player.volume=0; player.automaticallyWaitsToMinimizeStalling=NO;
    source=[LMVSharedSource new]; source.player=player; source.output=output; source.path=path; source.imageTransform=[[LMVAssets[path] tracksWithMediaType:AVMediaTypeVideo] firstObject].preferredTransform; LMVSharedSources[path]=source;
    __weak LMVSharedSource *weakSource=source;
    source.endObserver=[NSNotificationCenter.defaultCenter addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { LMVSharedSource *live=weakSource; if (live && live.playing) { [live.player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero]; [live.player play]; } }];
    return source;
}
// One conversion in flight globally. No work queue grows with the card count.
static void LMVPublishFrame(LMVSharedSource *source, CMTime time) {
    if (!source || LMVFrameBusy || source.frameBusy || !source.playing || ![source.output hasNewPixelBufferForItemTime:time]) return;
    CMTime itemTime=kCMTimeInvalid;
    CVPixelBufferRef buffer=[source.output copyPixelBufferForItemTime:time itemTimeForDisplay:&itemTime];
    if (!buffer) return;
    source.frameBusy=YES; LMVFrameBusy=YES;
    NSUInteger generation=source.generation;
    CGAffineTransform transform=source.imageTransform;
    dispatch_async(LMVFrameQueue, ^{
        @autoreleasepool {
            CIImage *ci=[[CIImage imageWithCVPixelBuffer:buffer] imageByApplyingTransform:transform];
            CGFloat largest=MAX(ci.extent.size.width,ci.extent.size.height);
            if (largest>960.0) ci=[ci imageByApplyingTransform:CGAffineTransformMakeScale(960.0/largest,960.0/largest)];
            CGImageRef image=[LMVCIContext createCGImage:ci fromRect:ci.extent];
            CVPixelBufferRelease(buffer); // copyPixelBuffer gives one +1; no extra retain.
            dispatch_async(dispatch_get_main_queue(), ^{
                if (image && source.generation==generation && LMVSharedSources[source.path]==source && source.playing && LMVPlaybackAllowed()) {
                    if (source.lastImage) CGImageRelease(source.lastImage);
                    source.lastImage=image; source.lastTime=itemTime;
                    [CATransaction begin]; [CATransaction setDisableActions:YES];
                    for (UIView *cell in LMVCells.allObjects) {
                        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
                        for (LMVVideoState *state in states.allValues) if (state.source==source) state.layer.contents=(__bridge id)image;
                    }
                    [CATransaction commit];
                } else if (image) CGImageRelease(image);
                source.frameBusy=NO; LMVFrameBusy=NO;
            });
        }
    });
}
static void LMVStartSource(LMVSharedSource *source) {
    if (!source || source.playing || !source.player.currentItem) return;
    source.playing=YES; [source.player play];
}
static void LMVStopSource(LMVSharedSource *source) {
    if (source && source.playing) {
        [source.player pause]; source.playing=NO; source.generation++;
        // Freeze the playback clock at the last published frame, not the next decoded frame.
        if (source.lastImage && CMTIME_IS_NUMERIC(source.lastTime))
            [source.player seekToTime:source.lastTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
    }
}
static BOOL LMVSourceHasConsumer(LMVSharedSource *source) {
    if (!source) return NO;
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
        for (LMVVideoState *state in states.allValues) if (state.source==source && state.active && state.overlay.superview) return YES;
    }
    return NO;
}
static void LMVReleasePlayer(LMVVideoState *state) {
    if (!state) return;
    LMVSharedSource *source=state.source;
    [state.layer removeFromSuperlayer]; state.layer.contents=nil; state.layer=nil; state.source=nil; state.active=NO;
    if (!LMVSourceHasConsumer(source)) LMVStopSource(source);
}
static void LMVPrepareAssets(void) {
    NSSet *wanted = [NSSet setWithArray:LMVPaths.allValues];
    for (NSString *path in LMVSources.allKeys) {
        if (![wanted containsObject:path]) { [LMVSources removeObjectForKey:path]; [LMVAssets removeObjectForKey:path];  [LMVReadyAssets removeObject:path]; LMVStopSource(LMVSharedSources[path]); [LMVSharedSources removeObjectForKey:path]; [LMVRevisions removeObjectForKey:path]; }
    }
    for (NSString *path in wanted) {
        NSString *revision = LMVFileRevision(path);
        if (LMVSources[path] && [LMVRevisions[path] isEqualToString:revision]) continue;
        // Same URL does not imply the same file. Invalidate composition,
        // prewarm decoder and time epoch together.
                [LMVSources removeObjectForKey:path]; [LMVAssets removeObjectForKey:path];
        [LMVReadyAssets removeObject:path];
        LMVStopSource(LMVSharedSources[path]); [LMVSharedSources removeObjectForKey:path];
        if (!revision) { [LMVRevisions removeObjectForKey:path]; continue; }
        LMVRevisions[path] = revision;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
        LMVSources[path] = asset;
        [asset loadValuesAsynchronouslyForKeys:@[@"tracks", @"playable", @"duration"] completionHandler:^{
            // Composition work stays off the scrolling/main thread and is cached per file.
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSError *error = nil;
            BOOL ready = [asset statusOfValueForKey:@"tracks" error:&error] == AVKeyValueStatusLoaded && [asset statusOfValueForKey:@"playable" error:&error] == AVKeyValueStatusLoaded && [asset statusOfValueForKey:@"duration" error:&error] == AVKeyValueStatusLoaded && asset.playable;
            CMTime duration = ready ? asset.duration : kCMTimeInvalid;
            ready = ready && CMTIME_IS_NUMERIC(duration) && CMTimeCompare(duration, kCMTimeZero) > 0;
            AVMutableComposition *video = ready ? [AVMutableComposition composition] : nil;
            CMTimeRange fullRange = CMTimeRangeMake(kCMTimeZero, duration);
            NSUInteger videoTrackCount = 0;
            if (ready) {
                for (AVAssetTrack *source in [asset tracksWithMediaType:AVMediaTypeVideo]) {
                    CMTimeRange range = CMTimeRangeGetIntersection(source.timeRange, fullRange);
                    if (!CMTIMERANGE_IS_VALID(range) || CMTimeCompare(range.duration, kCMTimeZero) <= 0) continue;
                    AVMutableCompositionTrack *track = [video addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
                    if (!track || ![track insertTimeRange:range ofTrack:source atTime:range.start error:&error]) {
                        ready = NO;
                        break;
                    }
                    track.preferredTransform = source.preferredTransform;
                    videoTrackCount++;
                }
                ready = ready && videoTrackCount > 0;
                if (ready && CMTimeCompare(video.duration, duration) < 0) {
                    [video insertEmptyTimeRange:CMTimeRangeMake(video.duration, CMTimeSubtract(duration, video.duration))];
                }
            }
            // No fallback to an audio-bearing asset, even if preparation fails.
            if (!ready) NSLog(@"[LockMessageVideo] Video-only preparation failed for %@: %@", path.lastPathComponent, error ?: @"Invalid duration or no usable video track");
            AVAsset *playbackAsset = ready ? [video copy] : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (LMVSources[path] != asset || !ready) return;
                LMVAssets[path] = playbackAsset;

                                [LMVReadyAssets addObject:path];
                for (UIView *cell in LMVCells.allObjects) LMVUpdate(cell);
            });
            });
        }];
    }
}
static void LMVLoadPreferences(void) {
    CFPreferencesAppSynchronize(kLMVPrefsID);
    LMVPaths = [NSMutableDictionary new];
    // These are semantic source names, kept independent from UIKit private class names.
    LMVMaterialSources = @{
        @"Message": @"message.mov",
        @"Options": @"options.mov",
        @"Clear": @"clear.mov"
    };
    LMVEnabled = [NSMutableDictionary new];
    for (NSString *target in LMVTargets()) {
        NSString *enabledKey = [target stringByAppendingString:@"BackgroundEnabled"];
        NSNumber *enabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue((__bridge CFStringRef)enabledKey, kLMVPrefsID);
        LMVEnabled[target] = @([enabled respondsToSelector:@selector(boolValue)] && enabled.boolValue);
        NSString *videoKey = [target stringByAppendingString:@"Video"];
        NSString *relative = (__bridge_transfer NSString *)CFPreferencesCopyAppValue((__bridge CFStringRef)videoKey, kLMVPrefsID);
        // Always resolve through the semantic source table; never pass a nil source name.
        if (![relative isKindOfClass:NSString.class] || !relative.length) relative = LMVMaterialSources[target];
        if (![relative isKindOfClass:NSString.class] || !relative.length) continue;
        NSString *path = [[LMVDirectory stringByAppendingPathComponent:relative] stringByStandardizingPath];
        if ([path hasPrefix:[LMVDirectory stringByAppendingString:@"/"]] && [[NSFileManager defaultManager] fileExistsAtPath:path]) LMVPaths[target] = path;
    }
    NSNumber *opacityEnabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("VideoOpacityEnabled"), kLMVPrefsID);
    LMVOpacityEnabled = !opacityEnabled || opacityEnabled.boolValue;
    NSNumber *opacity = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("VideoOpacity"), kLMVPrefsID);
    if (!opacity) opacity = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("MessageBackgroundOpacity"), kLMVPrefsID);
    // Off means fully transparent; keep the historical enabled default.
    LMVOpacity = [opacity respondsToSelector:@selector(floatValue)] ? MAX(0.0, MIN(1.0, opacity.floatValue)) : 0.55;
    LMVPrepareAssets();
}
static CGRect LMVRectInView(UIView *view, UIView *ancestor) {
    CALayer *source = view.layer.presentationLayer;
    CALayer *destination = ancestor.layer.presentationLayer;
    if (source && destination) return [source convertRect:source.bounds toLayer:destination];
    return [view convertRect:view.bounds toView:ancestor];
}
static BOOL LMVNotificationCenterSurface(UIView *view) {
    if (!view.window || view.window.hidden) return NO;
    for (UIView *node = view; node; node = node.superview) {
        NSString *name = NSStringFromClass(node.class);
        if ([name containsString:@"SBCoverSheet"] || [name containsString:@"NCNotification"] ||
            [name containsString:@"NotificationCenter"] || [name containsString:@"CoverSheet"]) return YES;
    }
    NSString *windowName = NSStringFromClass(view.window.class);
    if ([windowName containsString:@"CoverSheet"] || [windowName containsString:@"NotificationCenter"]) return YES;
    for (UIViewController *controller = view.window.rootViewController; controller; controller = controller.presentedViewController) {
        NSString *name = NSStringFromClass(controller.class);
        if ([name containsString:@"CoverSheet"] || [name containsString:@"NotificationCenter"]) return YES;
    }
    return NO;
}
static BOOL LMVVisible(UIView *view) {
    if (!LMVNotificationCenterSurface(view)) return NO;
    if (!view.window || view.window.hidden || view.bounds.size.width < 1 || view.bounds.size.height < 1) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha < 0.01) return NO;
        if (ancestor.clipsToBounds && !CGRectIntersectsRect(LMVRectInView(view, ancestor), (ancestor.layer.presentationLayer ?: ancestor.layer).bounds)) return NO;
    }
    uint64_t blank = 0;
    if (LMVBlankToken >= 0 && notify_get_state(LMVBlankToken, &blank) == NOTIFY_STATUS_OK && blank) return NO;
    return CGRectIntersectsRect(LMVRectInView(view, view.window), (view.window.layer.presentationLayer ?: view.window.layer).bounds);
}
static BOOL LMVActionBranch(UIView *view) {
    // Grouped notification actions use this presenter even when the concrete
    // private subclass no longer contains "ActionButtons" in its name.
    Class presenter = NSClassFromString(@"PLActionButtonsPresentingView");
    return [NSStringFromClass(view.class) containsString:@"ActionButtons"] || (presenter && [view isKindOfClass:presenter]);
}
static BOOL LMVIsClassOrSubclass(UIView *view, NSString *name) {
    Class cls = NSClassFromString(name);
    return cls && [view isKindOfClass:cls];
}
static UIView *LMVMessageMaterial(UIView *view, NSUInteger depth) {
    if (depth > 12 || LMVActionBranch(view) || view.hidden || view.alpha < 0.01) return nil;
    if ([NSStringFromClass(view.class) containsString:@"MaterialView"] && view.bounds.size.width > 20 && view.bounds.size.height > 20) return view;
    for (UIView *child in view.subviews) {
        if (LMVIsClassOrSubclass(child, @"NCNotificationListCell")) continue;
        UIView *material = LMVMessageMaterial(child, depth + 1);
        if (material) return material;
    }
    return nil;
}
static BOOL LMVMessageCell(UIView *cell) {
    return LMVIsClassOrSubclass(cell, @"NCNotificationListCell");
}
static NSString *LMVSemanticTarget(UIView *view) {
    NSString *title = nil;
    if ([view isKindOfClass:UIButton.class]) title = [(UIButton *)view currentTitle];
    if ([view isKindOfClass:UILabel.class]) title = [(UILabel *)view text];
    for (NSString *label in @[(title ?: @""), (view.accessibilityLabel ?: @"")]) {
        NSString *text = [[label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
        // Exact labels only: never classify an unlabeled header close control.
        if ([@[@"clear", @"clear all", @"清除", @"清除全部", @"全部清除", @"清除所有", @"清除所有通知"] containsObject:text]) return @"Clear";
        if ([@[@"options", @"manage", @"选项", @"管理"] containsObject:text]) return @"Options";
    }
    return nil;
}
static void LMVFindActions(UIView *view, UIView *root, NSMapTable *hosts, NSUInteger depth) {
    if (depth > 10) return;
    NSString *target = LMVSemanticTarget(view);
    if (target) {
        UIView *host = view;
        while (host && host != root && ![host isKindOfClass:UIControl.class]) host = host.superview;
        if (host && host != root) {
            UIView *material = LMVMessageMaterial(host, 0);
            [hosts setObject:(material ?: host) forKey:target];
        }
    }
    for (UIView *child in view.subviews) LMVFindActions(child, root, hosts, depth + 1);
}
static void LMVActionHosts(UIView *view, NSMapTable *hosts, NSUInteger depth) {
    if (depth > 12) return;
    if (LMVActionBranch(view)) { LMVFindActions(view, view, hosts, 0); return; }
    for (UIView *child in view.subviews) LMVActionHosts(child, hosts, depth + 1);
}
static void LMVPause(LMVVideoState *state) { LMVReleasePlayer(state); }

static void LMVRetryDiscovery(UIView *cell) {
    if (objc_getAssociatedObject(cell, &LMVRetryKey)) return;
    objc_setAssociatedObject(cell, &LMVRetryKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    __weak UIView *weakCell = cell;
    for (NSUInteger attempt = 1; attempt <= 4; attempt++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(attempt * 0.06 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *owner = weakCell;
            if (!owner) return;
            if (owner.window && LMVPlaybackAllowed()) {
                objc_setAssociatedObject(owner, &LMVDiscoveryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                LMVUpdate(owner);
            }
        });
    }
}
static void LMVUpdate(UIView *cell) {
    NSMutableDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
    if (!states) { states = [NSMutableDictionary new]; objc_setAssociatedObject(cell, &LMVStatesKey, states, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    if (!LMVPlaybackAllowed()) {
        for (LMVVideoState *state in states.allValues) LMVReleasePlayer(state);
        LMVSyncDisplayLink();
        return;
    }
    BOOL visible = LMVVisible(cell);
    CFTimeInterval now = CACurrentMediaTime();
    if (!cell.window) {
        for (LMVVideoState *state in states.allValues) {
            if (!state.detachedSince) state.detachedSince = now;
            if (now - state.detachedSince > 0.35) LMVReleasePlayer(state);
        }
        return;
    }
    NSMapTable *hosts = objc_getAssociatedObject(cell, &LMVHostsKey);
    if (!hosts) { hosts = [NSMapTable strongToStrongObjectsMapTable]; objc_setAssociatedObject(cell, &LMVHostsKey, hosts, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    // UIKit briefly hides or detaches notification materials while collapsing a stack.
    // Keep our cached host and decoder through that transient window.
    BOOL messageEligible = LMVMessageCell(cell);
    if (!messageEligible) {
        [hosts removeObjectForKey:@"Message"];
        LMVVideoState *old = states[@"Message"];
        LMVPause(old); [old.overlay removeFromSuperview];
        [states removeObjectForKey:@"Message"];
    }
    BOOL missing = NO;
    for (NSString *target in LMVTargets()) {
        UIView *host = [hosts objectForKey:target];
        if ([target isEqualToString:@"Message"] && !messageEligible) host = nil;
        if (host && !([host isDescendantOfView:cell] || host == cell)) {
            [hosts removeObjectForKey:target]; host = nil;
            // An invalid boundary is not a transient detach: remove only our
            // owned overlay immediately, before discovery binds a new host.
            LMVVideoState *old = states[target];
            LMVPause(old); [old.overlay removeFromSuperview];
            objc_setAssociatedObject(old.overlay, &LMVOwnershipKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            old.anchor = nil; old.host = nil;
        }
        if (LMVEnabled[target].boolValue && LMVPaths[target] && !host && ([target isEqualToString:@"Message"] || visible)) missing = YES;
    }
    NSNumber *last = objc_getAssociatedObject(cell, &LMVDiscoveryKey);
    if (missing && (!last || now - last.doubleValue >= 0.1)) {
        objc_setAssociatedObject(cell, &LMVDiscoveryKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LMVActionHosts(cell, hosts, 0);
        if (messageEligible) {
            UIView *material = LMVMessageMaterial(cell, 0);
            if (material) [hosts setObject:material forKey:@"Message"];
        }
    }
    for (NSString *target in LMVTargets()) {
        UIView *anchor = [hosts objectForKey:target];
        NSString *path = LMVPaths[target];
        LMVVideoState *state = states[target];
        if (!LMVEnabled[target].boolValue || !path || (state && ![state.path isEqualToString:path])) {
            LMVPause(state); [state.overlay removeFromSuperview]; [states removeObjectForKey:target]; state = nil;
            if (!LMVEnabled[target].boolValue || !path) continue;
        }
        if (!anchor || !anchor.superview) {
            if (state && !state.detachedSince) state.detachedSince = now;
            if (state && state.overlay.superview && state.detachedSince && now - state.detachedSince < 0.18) continue;
            LMVPause(state); [state.overlay removeFromSuperview]; state.anchor = nil; continue;
        }
        state.detachedSince = 0;
        BOOL anchorVisible = visible && LMVVisible(anchor);
        if (anchorVisible) state.visibilityLossSince = 0;
        else if (state && !state.visibilityLossSince) state.visibilityLossSince = now;
        if (!anchorVisible && (!state.visibilityLossSince || now - state.visibilityLossSince >= 0.18)) LMVReleasePlayer(state);
        if (!state) {
            // The material remains underneath until a real decoded frame is available.
            state = [LMVVideoState new]; state.path = path;
            state.revision = LMVRevisions[path];
            state.overlay = [UIView new]; state.overlay.userInteractionEnabled = NO;
            state.overlay.clipsToBounds = YES;
                    states[target] = state;
        }
        if (![state.revision isEqualToString:LMVRevisions[path]]) {
            // Keep the owned overlay and its owned overlay during async rebind.
            LMVReleasePlayer(state);
            state.revision = LMVRevisions[path];
        }
        if (!state.source && anchorVisible) state.source=LMVSourceForPath(path);
        if (state.source && !state.layer) {
            state.layer=[CALayer layer]; state.layer.contentsGravity=kCAGravityResizeAspectFill;
            [state.overlay.layer addSublayer:state.layer];
            if (state.source.lastImage) state.layer.contents=(__bridge id)state.source.lastImage;
        }
        BOOL material = [NSStringFromClass(anchor.class) containsString:@"MaterialView"];
        UIView *host = material ? anchor.superview : anchor;
        // Host identity is part of ownership. Never retain an overlay under a
        // reused parent when UIKit swaps the notification content host.
        if (state.host && state.host != host) {
            [state.overlay removeFromSuperview];
            state.anchor = nil;
        }
        NSDictionary *ownership = @{ @"target": target, @"host": [NSValue valueWithNonretainedObject:host] };
        objc_setAssociatedObject(state.overlay, &LMVOwnershipKey, ownership, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state.host = host;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (state.overlay.superview != host || state.anchor != anchor) {
            if (material) [host insertSubview:state.overlay aboveSubview:anchor];
            else [host insertSubview:state.overlay atIndex:0];
            state.anchor = anchor;
        }
        // Model geometry into the model host, never presentation-to-model coordinates.
        // Only the plugin-owned surface participates in clipping; parent size is unchanged.
        CALayer *clip=anchor.layer;
        state.overlay.transform = CGAffineTransformIdentity;
        state.overlay.frame = [anchor convertRect:anchor.bounds toView:host];
        state.overlay.autoresizingMask = UIViewAutoresizingNone;
        CGFloat radius=clip.cornerRadius;
        if (radius<=0) radius=MIN(20.0, MIN(anchor.bounds.size.width,anchor.bounds.size.height)*0.5);
        state.overlay.layer.cornerRadius = radius;
        state.overlay.layer.cornerCurve = kCACornerCurveContinuous;
        state.overlay.layer.maskedCorners = kCALayerMinXMinYCorner|kCALayerMaxXMinYCorner|kCALayerMinXMaxYCorner|kCALayerMaxXMaxYCorner;
        state.overlay.layer.mask = nil;
        state.layer.frame = state.overlay.bounds;
        state.layer.hidden = NO;
        state.overlay.alpha = LMVOpacityEnabled ? LMVOpacity : 0.0;
        [CATransaction commit];
        state.active=anchorVisible && LMVOpacityEnabled && LMVOpacity>0.0;
        if (anchorVisible) state.lastVisible = now;
        // Starting the one shared source has no host-clock delay or phase seek.
        if (state.active && state.source) LMVStartSource(state.source);
    }
    LMVSyncDisplayLink();
}
%hook NCNotificationListCell
- (void)layoutSubviews {
    %orig;
    [LMVCells addObject:(UIView *)self];
    LMVUpdate((UIView *)self);
    LMVRetryDiscovery((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    [LMVCells addObject:(UIView *)self];
    LMVUpdate((UIView *)self);
    LMVRetryDiscovery((UIView *)self);
}
- (void)prepareForReuse {
    objc_setAssociatedObject(self, &LMVRetryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSDictionary *states = objc_getAssociatedObject(self, &LMVStatesKey);
    for (LMVVideoState *state in states.allValues) { LMVPause(state); [state.overlay removeFromSuperview]; objc_setAssociatedObject(state.overlay, &LMVOwnershipKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); state.anchor = nil; state.host = nil; }
    objc_setAssociatedObject(self, &LMVStatesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &LMVHostsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &LMVDiscoveryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end
static void LMVCoverSheetVisibilityChanged(UIView *view) {
    BOOL window=[view isKindOfClass:UIWindow.class];
    // A root UIWindow legitimately has no superview and its window accessor may be nil.
    BOOL hidden=view.hidden || view.alpha<0.01 || (!window && (!view.window || !view.superview));
    LMVCoverHidden=hidden;
    if (hidden) LMVReleaseAllPlayers(); else LMVRefresh(NO);
}
%hook SBCoverSheetWindow
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVCoverSheetVisibilityChanged((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    LMVCoverSheetVisibilityChanged((UIView *)self);
}
%end
%hook CoverSheet
- (void)setHidden:(BOOL)hidden {
    %orig;
    LMVCoverSheetVisibilityChanged((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    LMVCoverSheetVisibilityChanged((UIView *)self);
}
%end
static void LMVUpdateActionPresenter(UIView *presenter) {
    UIView *ancestor = presenter.superview;
    Class cellClass = NSClassFromString(@"NCNotificationListCell");
    while (ancestor && (!cellClass || ![ancestor isKindOfClass:cellClass])) ancestor = ancestor.superview;
    // A grouped swipe presenter can live outside NCNotificationListCell.
    // Track only the dedicated action presenter, not a notification header.
    UIView *owner = ancestor ?: presenter;
    [LMVCells addObject:owner];
    objc_setAssociatedObject(owner, &LMVDiscoveryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    LMVUpdate(owner);
}
%hook PLActionButtonsPresentingView
- (void)layoutSubviews {
    %orig;
    LMVUpdateActionPresenter((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    LMVUpdateActionPresenter((UIView *)self);
}
%end
static void LMVReleaseAllPlayers(void) {
    // Keep one paused player/time and one last decoded CGImage per file, not per card.
    [LMVLink invalidate]; LMVLink=nil;
    for (LMVSharedSource *source in LMVSharedSources.allValues) LMVStopSource(source);
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
        for (LMVVideoState *state in states.allValues) state.active=NO;
    }
}
static void LMVRefresh(BOOL reload) {
    if (reload) {
        // Imports can overwrite an existing filename; URL equality does not mean same media.
        
        LMVReleaseAllPlayers();
        [LMVSources removeAllObjects]; [LMVAssets removeAllObjects]; [LMVReadyAssets removeAllObjects]; [LMVSharedSources removeAllObjects];
        [LMVRevisions removeAllObjects];
        for (UIView *cell in LMVCells.allObjects) {
            NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
            for (LMVVideoState *state in states.allValues) {
                LMVReleasePlayer(state); state.revision = nil;
            }
        }
        LMVLoadPreferences();
    }
    for (UIView *cell in LMVCells.allObjects) {
        NSMutableDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
        for (NSString *target in states.allKeys) {
            LMVVideoState *state = states[target];
            if (!LMVVisible(cell) && CACurrentMediaTime() - state.lastVisible > 8) LMVReleasePlayer(state);
            if (!LMVEnabled[target].boolValue || ![state.path isEqualToString:LMVPaths[target]]) {
                LMVPause(state); [state.overlay removeFromSuperview]; [states removeObjectForKey:target];
            }
        }
        LMVUpdate(cell);
    }
    LMVSyncDisplayLink();
}
// Tracking mode suppresses default-mode timers and scrolling does not relayout every cell.
// Only visibility/readiness/host identity transitions invoke the heavier layout path.
@interface LMVDisplayLinkTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end
static void LMVSuspend(void) {
    LMVReleaseAllPlayers();
}
static void LMVSyncDisplayLink(void) {
    BOOL needed=NO;
    if (LMVPlaybackAllowed()) for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
        for (LMVVideoState *state in states.allValues) if (state.active) { needed=YES; break; }
    }
    if (!needed) { for (LMVSharedSource *source in LMVSharedSources.allValues) LMVStopSource(source); [LMVLink invalidate]; LMVLink=nil; return; }
    if (LMVLink) return;
    LMVDisplayLinkTarget *target=[LMVDisplayLinkTarget new];
    LMVLink=[CADisplayLink displayLinkWithTarget:target selector:@selector(tick:)];
    LMVLink.preferredFramesPerSecond=30;
    [LMVLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
@implementation LMVDisplayLinkTarget
- (void)tick:(CADisplayLink *)link {
    if (!LMVPlaybackAllowed()) { LMVSuspend(); return; }
    // Visibility is separate from frame conversion; never rediscover/layout every card per frame.
    NSMutableSet<LMVSharedSource *> *visible=[NSMutableSet new];
    NSUInteger consumers=0;
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
        BOOL cellVisible=LMVVisible(cell), changed=NO;
        for (LMVVideoState *state in states.allValues) {
            BOOL active=cellVisible && state.anchor && LMVVisible(state.anchor) && state.overlay.superview && LMVOpacityEnabled && LMVOpacity>0.0;
            if (active!=state.active) changed=YES;
            state.active=active;
        }
        if (changed) LMVUpdate(cell);
        for (LMVVideoState *state in states.allValues) if (state.active && state.source) { [visible addObject:state.source]; consumers++; }
    }
    for (LMVSharedSource *source in LMVSharedSources.allValues) {
        if ([visible containsObject:source]) LMVStartSource(source); else LMVStopSource(source);
    }
    static NSUInteger lastSources=NSUIntegerMax,lastConsumers=NSUIntegerMax,nextSource=0;
    if (lastSources!=visible.count || lastConsumers!=consumers) {
        NSLog(@"[LockMessageVideo] shared sources=%lu visible sources=%lu consumers=%lu",(unsigned long)LMVSharedSources.count,(unsigned long)visible.count,(unsigned long)consumers);
        lastSources=visible.count; lastConsumers=consumers;
    }
    NSArray *sources=visible.allObjects;
    // Rotate priority when multiple materials compete for the single in-flight conversion.
    for (NSUInteger n=0;n<sources.count;n++) {
        LMVSharedSource *source=sources[(n+nextSource)%sources.count];
        CMTime time=[source.output itemTimeForHostTime:link.timestamp];
        LMVPublishFrame(source,time);
    }
    nextSource++;
    LMVSyncDisplayLink();
}
@end
static void LMVDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL media = CFEqual(name, CFSTR("com.minis.lockmessagevideo/videoChanged"));
        if (media) LMVRefresh(YES);
        else {
            LMVLoadPreferences();
            for (UIView *cell in LMVCells.allObjects) {
                NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
                for (LMVVideoState *state in states.allValues) state.overlay.alpha = LMVOpacityEnabled ? LMVOpacity : 0.0;
            }
            LMVRefresh(NO);
        }
    });
}
static void LMVScreenNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!LMVPlaybackAllowed()) LMVSuspend();
        else { LMVPrepareAssets();  LMVRefresh(NO); }
    });
}
%ctor {
    @autoreleasepool {
        LMVFrameQueue=dispatch_queue_create("com.minis.lockmessagevideo.frames",DISPATCH_QUEUE_SERIAL);
        LMVCIContext=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@NO}];
        LMVCells = [NSHashTable weakObjectsHashTable];
        
        LMVRevisions = [NSMutableDictionary new];
        LMVSources = [NSMutableDictionary new]; LMVAssets = [NSMutableDictionary new];  LMVReadyAssets = [NSMutableSet new]; LMVSharedSources = [NSMutableDictionary new];
        LMVLoadPreferences();
        %init;
        notify_register_check("com.apple.springboard.hasBlankedScreen", &LMVBlankToken);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        for (NSString *name in @[@"com.apple.springboard.hasBlankedScreen", @"com.apple.springboard.lockstate"]) {
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVScreenNotification, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                LMVRefresh(NO);
            }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                LMVSuspend();
            }];
            LMVRefresh(NO);
        });
    }
}
