#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <float.h>
#import <math.h>
#import <sys/stat.h>

static NSString * const LMVDirectory = @"/var/mobile/LockMessageVideo";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSHashTable<UIView *> *LMVCells;
static NSMutableDictionary<NSString *, NSString *> *LMVPaths;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *, AVURLAsset *> *LMVSources;
static NSMutableDictionary<NSString *, AVAsset *> *LMVAssets;
static NSMutableDictionary<NSString *, AVPlayerItem *> *LMVItems;
static NSMutableSet<NSString *> *LMVReadyAssets;
static NSMutableDictionary<NSString *, UIImage *> *LMVPosters;
static NSMutableDictionary<NSString *, NSString *> *LMVRevisions;
static NSMutableDictionary<NSString *, NSNumber *> *LMVClockStarts;
static CGFloat LMVOpacity = 0.55;
static BOOL LMVOpacityEnabled = YES;
static int LMVBlankToken = -1;
static char LMVStatesKey, LMVHostsKey, LMVDiscoveryKey, LMVRetryKey, LMVOwnedOverlayKey;
static void LMVPrewarmPlayers(void);
static NSUInteger LMVPlayerCount;
static const NSUInteger LMVPlayerLimit = 18;
static void LMVUpdate(UIView *cell);
static void LMVSyncDisplayLink(void);

@interface LMVVideoState : NSObject
@property(nonatomic, strong) UIView *overlay;
@property(nonatomic, strong) AVPlayerLayer *layer;
@property(nonatomic, strong) UIImageView *poster;
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLooper *looper;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, copy) NSString *revision;
@property(nonatomic, weak) UIView *anchor;
@property(nonatomic, weak) CALayer *clipSource;
@property(nonatomic) CFTimeInterval lastVisible;
@property(nonatomic) CFTimeInterval visibilityLossSince;
@property(nonatomic) CFTimeInterval detachedSince;
@property(nonatomic) BOOL playing;
@end
@implementation LMVVideoState
- (void)dealloc {
    [_player pause];
    [_looper disableLooping];
    [_player removeAllItems];
    [_overlay removeFromSuperview];
    if (_player && LMVPlayerCount) LMVPlayerCount--;
}
@end

@interface SBLockScreenManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUILocked;
@end
static BOOL LMVPlaybackAllowed(void) {
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

static NSMutableDictionary<NSString *, LMVVideoState *> *LMVWarmPlayers;
static LMVVideoState *LMVCreatePlayer(NSString *path) {
    if (LMVPlayerCount >= LMVPlayerLimit || !LMVAssets[path]) return nil;
    LMVVideoState *state = [LMVVideoState new];
    state.path = path;
    state.revision = LMVRevisions[path];
    state.player = [AVQueuePlayer queuePlayerWithItems:@[]]; LMVPlayerCount++;
    state.player.preventsDisplaySleepDuringVideoPlayback = NO;
    state.player.muted = YES; state.player.volume = 0;
    state.player.automaticallyWaitsToMinimizeStalling = NO;
    AVPlayerItem *item = LMVItems[path] ?: [AVPlayerItem playerItemWithAsset:LMVAssets[path]];
    item.preferredForwardBufferDuration = 1;
    state.looper = [AVPlayerLooper playerLooperWithPlayer:state.player templateItem:item];
    state.layer = [AVPlayerLayer playerLayerWithPlayer:state.player];
    state.layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    state.layer.bounds = CGRectMake(0, 0, 320, 160);
    return state;
}
static void LMVPrewarmPlayers(void) {
    if (!LMVPlaybackAllowed()) return;
    for (NSString *path in LMVReadyAssets) {
        BOOL enabled = NO;
        for (NSString *target in LMVPaths) if (LMVEnabled[target].boolValue && [LMVPaths[target] isEqualToString:path]) enabled = YES;
        if (!enabled || LMVWarmPlayers[path] || LMVPlayerCount >= LMVPlayerLimit) continue;
        LMVVideoState *state = LMVCreatePlayer(path);
        if (!state) continue;
        LMVWarmPlayers[path] = state;
        // Do not issue preroll/cancelPendingPrerolls during notification transitions.
        // AVPlayer on iOS 16.5 can throw from that state transition; the cached
        // video-only item and poster remain available for the visible handoff.
    }
}
static void LMVPreparePoster(NSString *path, AVURLAsset *asset) {
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(960, 960);
    [generator generateCGImagesAsynchronouslyForTimes:@[[NSValue valueWithCMTime:kCMTimeZero]] completionHandler:^(CMTime requested, CGImageRef image, CMTime actual, AVAssetImageGeneratorResult result, NSError *error) {
        if (result != AVAssetImageGeneratorSucceeded || !image) return;
        UIImage *poster = [UIImage imageWithCGImage:image];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (LMVSources[path] != asset) return;
            LMVPosters[path] = poster;
            for (UIView *cell in LMVCells.allObjects) LMVUpdate(cell);
        });
    }];
}
static void LMVPrepareAssets(void) {
    NSSet *wanted = [NSSet setWithArray:LMVPaths.allValues];
    for (NSString *path in LMVSources.allKeys) {
        if (![wanted containsObject:path]) { [LMVSources removeObjectForKey:path]; [LMVAssets removeObjectForKey:path]; [LMVWarmPlayers removeObjectForKey:path]; [LMVItems removeObjectForKey:path]; [LMVReadyAssets removeObject:path]; [LMVPosters removeObjectForKey:path]; [LMVRevisions removeObjectForKey:path]; [LMVClockStarts removeObjectForKey:path]; }
    }
    for (NSString *path in wanted) {
        NSString *revision = LMVFileRevision(path);
        if (LMVSources[path] && [LMVRevisions[path] isEqualToString:revision]) continue;
        // Same URL does not imply the same file. Invalidate composition, poster,
        // decoder and time epoch together before preparing the replacement.
        [LMVWarmPlayers removeObjectForKey:path];
        [LMVSources removeObjectForKey:path]; [LMVAssets removeObjectForKey:path];
        [LMVItems removeObjectForKey:path]; [LMVReadyAssets removeObject:path];
        [LMVPosters removeObjectForKey:path]; [LMVClockStarts removeObjectForKey:path];
        if (!revision) { [LMVRevisions removeObjectForKey:path]; continue; }
        LMVRevisions[path] = revision;
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:@{AVURLAssetPreferPreciseDurationAndTimingKey: @NO}];
        LMVSources[path] = asset;
        LMVPreparePoster(path, asset);
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
            AVPlayerItem *cachedItem = playbackAsset ? [AVPlayerItem playerItemWithAsset:playbackAsset] : nil;
            cachedItem.preferredForwardBufferDuration = 1;
            dispatch_async(dispatch_get_main_queue(), ^{
                if (LMVSources[path] != asset || !ready) return;
                LMVAssets[path] = playbackAsset;
                LMVItems[path] = cachedItem;
                [LMVReadyAssets addObject:path];
                LMVPrewarmPlayers();
                for (UIView *cell in LMVCells.allObjects) LMVUpdate(cell);
            });
            });
        }];
    }
}
static void LMVLoadPreferences(void) {
    CFPreferencesAppSynchronize(kLMVPrefsID);
    LMVPaths = [NSMutableDictionary new];
    LMVEnabled = [NSMutableDictionary new];
    for (NSString *target in @[@"Message", @"Options", @"Clear"]) {
        NSString *enabledKey = [target stringByAppendingString:@"BackgroundEnabled"];
        NSNumber *enabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue((__bridge CFStringRef)enabledKey, kLMVPrefsID);
        LMVEnabled[target] = @([enabled respondsToSelector:@selector(boolValue)] && enabled.boolValue);
        NSString *videoKey = [target stringByAppendingString:@"Video"];
        NSString *relative = (__bridge_transfer NSString *)CFPreferencesCopyAppValue((__bridge CFStringRef)videoKey, kLMVPrefsID);
        if (!relative && [target isEqualToString:@"Message"]) relative = @"message.mov";
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
static BOOL LMVVisible(UIView *view) {
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
static BOOL LMVIsMessageHost(UIView *view) {
    NSString *name = NSStringFromClass(view.class);
    return [name isEqualToString:@"NCNotificationShortLookView"] ||
           [name isEqualToString:@"NCNotificationSeamlessContentView"];
}
static UIView *LMVMessageHost(UIView *view, NSUInteger depth) {
    if (depth > 16 || LMVActionBranch(view) || view.hidden || view.alpha < 0.01) return nil;
    if (LMVIsMessageHost(view) && view.bounds.size.width > 20 && view.bounds.size.height > 20) return view;
    for (UIView *child in view.subviews) {
        UIView *host = LMVMessageHost(child, depth + 1);
        if (host) return host;
    }
    return nil;
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
            [hosts setObject:host forKey:target];
        }
    }
    for (UIView *child in view.subviews) LMVFindActions(child, root, hosts, depth + 1);
}
static void LMVActionHosts(UIView *view, NSMapTable *hosts, NSUInteger depth) {
    if (depth > 12) return;
    if (LMVActionBranch(view)) { LMVFindActions(view, view, hosts, 0); return; }
    for (UIView *child in view.subviews) LMVActionHosts(child, hosts, depth + 1);
}
// Mirror masks into owned layers; never move or modify a system mask.
static CALayer *LMVCopyMask(CALayer *source, CALayer *copy, NSUInteger depth) {
    if (!source || depth > 8) return nil;
    BOOL shape = [source isKindOfClass:CAShapeLayer.class];
    if (!copy || [copy isKindOfClass:CAShapeLayer.class] != shape) copy = shape ? [CAShapeLayer layer] : [CALayer layer];
    copy.bounds = source.bounds; copy.position = source.position; copy.anchorPoint = source.anchorPoint;
    copy.transform = source.transform; copy.sublayerTransform = source.sublayerTransform;
    copy.opacity = source.opacity; copy.hidden = source.hidden;
    copy.cornerRadius = source.cornerRadius; copy.cornerCurve = source.cornerCurve;
    copy.maskedCorners = source.maskedCorners; copy.masksToBounds = source.masksToBounds;
    copy.backgroundColor = source.backgroundColor; copy.contents = source.contents;
    copy.contentsRect = source.contentsRect; copy.contentsCenter = source.contentsCenter;
    copy.contentsScale = source.contentsScale; copy.contentsGravity = source.contentsGravity;
    if (shape) {
        CAShapeLayer *a = (CAShapeLayer *)source, *b = (CAShapeLayer *)copy;
        b.path = a.path; b.fillColor = a.fillColor; b.fillRule = a.fillRule;
        b.strokeColor = a.strokeColor; b.lineWidth = a.lineWidth;
        b.lineCap = a.lineCap; b.lineJoin = a.lineJoin; b.lineDashPattern = a.lineDashPattern;
        b.lineDashPhase = a.lineDashPhase; b.strokeStart = a.strokeStart; b.strokeEnd = a.strokeEnd;
    }
    copy.mask = LMVCopyMask(source.mask, copy.mask, depth + 1);
    NSArray *old = copy.sublayers ?: @[];
    NSMutableArray *children = [NSMutableArray new];
    NSUInteger i = 0;
    for (CALayer *child in source.sublayers) {
        CALayer *next = LMVCopyMask(child, i < old.count ? old[i] : nil, depth + 1);
        if (next) [children addObject:next];
        i++;
    }
    copy.sublayers = children;
    return copy;
}
static CALayer *LMVClipSource(CALayer *layer, CALayer *excluded, NSUInteger depth) {
    if (layer == excluded || depth > 5) return nil;
    if (layer.mask || layer.cornerRadius > 0) return layer;
    for (CALayer *child in layer.sublayers) {
        if (!CGRectEqualToRect(child.frame, layer.bounds)) continue;
        CALayer *source = LMVClipSource(child, excluded, depth + 1);
        if (source) return source;
    }
    return nil;
}
static BOOL LMVIsOwnedOverlay(UIView *overlay) {
    return overlay && [objc_getAssociatedObject(overlay, &LMVOwnedOverlayKey) boolValue];
}
static void LMVRemoveDuplicateOverlays(UIView *host, UIView *keep) {
    if (!host) return;
    // Only touch plugin-owned marker views. System notification subviews and
    // their layers, including AVPlayerLayer instances, are never inspected or
    // removed as part of cleanup.
    for (UIView *child in [host.subviews copy]) {
        if (child != keep && LMVIsOwnedOverlay(child)) [child removeFromSuperview];
    }
}
static void LMVDetachOverlay(LMVVideoState *state) {
    if (LMVIsOwnedOverlay(state.overlay)) [state.overlay removeFromSuperview];
    state.anchor = nil;
    state.clipSource = nil;
}
static void LMVPause(LMVVideoState *state) {
    if (state.playing) { [state.player pause]; state.playing = NO; }
}
static void LMVStartSynchronized(LMVVideoState *state) {
    AVPlayerItem *item = state.player.currentItem;
    if (!state.player || state.playing || state.player.status != AVPlayerStatusReadyToPlay ||
        !item || item.status != AVPlayerItemStatusReadyToPlay) return;
    CMTime duration = LMVAssets[state.path].duration;
    double seconds = CMTimeGetSeconds(duration);
    if (!CMTIME_IS_NUMERIC(duration) || !isfinite(seconds) || seconds <= 0) return;
    // One host-clock schedule on each visibility resume, not per-frame seeking.
    // Every instance of a material uses the same epoch, including later arrivals.
    CMTime host = CMClockGetTime(CMClockGetHostTimeClock());
    host = CMTimeAdd(host, CMTimeMakeWithSeconds(0.10, 1000000000));
    double start = CMTimeGetSeconds(host);
    NSNumber *epoch = LMVClockStarts[state.path];
    if (!epoch) { epoch = @(start); LMVClockStarts[state.path] = epoch; }
    CMTime phase = CMTimeMakeWithSeconds(fmod(MAX(0.0, start - epoch.doubleValue), seconds), 60000);
    [state.player setRate:1.0 time:phase atHostTime:host];
    state.playing = YES;
}
static void LMVReleasePlayer(LMVVideoState *state) {
    LMVPause(state);
    [state.looper disableLooping];
    [state.player removeAllItems];
    [state.layer removeFromSuperlayer];
    if (state.player && LMVPlayerCount) LMVPlayerCount--;
    state.looper = nil; state.layer = nil; state.player = nil;
    state.poster.hidden = NO;
}
static void LMVMakeRoom(void) {
    if (LMVPlayerCount < LMVPlayerLimit) return;
    NSString *warmPath = LMVWarmPlayers.allKeys.firstObject;
    if (warmPath) { [LMVWarmPlayers removeObjectForKey:warmPath]; return; }
    UIView *victimCell = nil;
    NSString *victimTarget = nil;
    CFTimeInterval oldest = DBL_MAX;
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
        for (NSString *target in states) {
            LMVVideoState *state = states[target];
            if (state.player && !state.playing && state.lastVisible < oldest) {
                oldest = state.lastVisible; victimCell = cell; victimTarget = target;
            }
        }
    }
    if (victimCell) {
        NSMutableDictionary *states = objc_getAssociatedObject(victimCell, &LMVStatesKey);
        LMVVideoState *state = states[victimTarget];
        LMVReleasePlayer(state);
    }
}
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
        // A reused/detached cell is no longer a valid rendering owner. Remove
        // plugin views now; player, poster, and asset caches remain reusable.
        for (LMVVideoState *state in states.allValues) {
            LMVPause(state);
            LMVDetachOverlay(state);
            state.detachedSince = now;
        }
        return;
    }
    NSMapTable *hosts = objc_getAssociatedObject(cell, &LMVHostsKey);
    if (!hosts) { hosts = [NSMapTable strongToStrongObjectsMapTable]; objc_setAssociatedObject(cell, &LMVHostsKey, hosts, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    // UIKit briefly hides or detaches notification materials while collapsing a stack.
    // Keep our cached host and decoder through that transient window.
    BOOL missing = NO;
    for (NSString *target in @[@"Message", @"Options", @"Clear"]) {
        UIView *host = [hosts objectForKey:target];
        if (host && ![host isDescendantOfView:cell]) { [hosts removeObjectForKey:target]; host = nil; }
        if (LMVEnabled[target].boolValue && LMVPaths[target] && !host && ([target isEqualToString:@"Message"] || visible)) missing = YES;
    }
    NSNumber *last = objc_getAssociatedObject(cell, &LMVDiscoveryKey);
    if (missing && (!last || now - last.doubleValue >= 0.1)) {
        objc_setAssociatedObject(cell, &LMVDiscoveryKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LMVActionHosts(cell, hosts, 0);
        UIView *messageHost = LMVMessageHost(cell, 0);
        if (messageHost) [hosts setObject:messageHost forKey:@"Message"];
    }
    for (NSString *target in @[@"Message", @"Options", @"Clear"]) {
        UIView *anchor = [hosts objectForKey:target];
        NSString *path = LMVPaths[target];
        LMVVideoState *state = states[target];
        if (!LMVEnabled[target].boolValue || !path || (state && ![state.path isEqualToString:path])) {
            LMVPause(state); LMVDetachOverlay(state); [states removeObjectForKey:target]; state = nil;
            if (!LMVEnabled[target].boolValue || !path) continue;
        }
        if (!anchor || !anchor.superview || !anchor.window || anchor.hidden || anchor.alpha < 0.01) {
            // Host loss is an ownership boundary: remove immediately. Keep
            // only the player/poster cache, never a view attached to old
            // notification geometry during reuse or collapse.
            LMVPause(state); LMVDetachOverlay(state); continue;
        }
        state.detachedSince = 0;
        BOOL anchorVisible = visible && LMVVisible(anchor);
        if (anchorVisible) state.visibilityLossSince = 0;
        else if (state && !state.visibilityLossSince) state.visibilityLossSince = now;
        if (!anchorVisible && (!state.visibilityLossSince || now - state.visibilityLossSince >= 0.18)) LMVPause(state);
        if (!state) {
            // The fallback surface exists even while the decoder budget is exhausted.
            state = [LMVVideoState new]; state.path = path;
            state.revision = LMVRevisions[path];
            state.overlay = [UIView new];
            objc_setAssociatedObject(state.overlay, &LMVOwnedOverlayKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            state.overlay.userInteractionEnabled = NO;
            state.overlay.clipsToBounds = YES;
            state.poster = [UIImageView new];
            state.poster.contentMode = UIViewContentModeScaleAspectFill;
            state.poster.clipsToBounds = YES;
            [state.overlay addSubview:state.poster];
            states[target] = state;
        }
        if (![state.revision isEqualToString:LMVRevisions[path]]) {
            // Keep the owned overlay and its last poster during async rebind.
            LMVReleasePlayer(state);
            state.revision = LMVRevisions[path];
        }
        if (anchorVisible && !state.player && [LMVReadyAssets containsObject:path]) {
            LMVVideoState *warm = LMVWarmPlayers[path];
            if (!warm) { LMVMakeRoom(); warm = LMVCreatePlayer(path); }
            if (warm) {
                // Handoff is intentionally a pointer transfer only. Calling
                // cancelPendingPrerolls here can throw on iOS 16.5 while AVF
                // is still configuring the cached item.
                state.player = warm.player; state.looper = warm.looper; state.layer = warm.layer;
                warm.player = nil; warm.looper = nil; warm.layer = nil;
                [LMVWarmPlayers removeObjectForKey:path];
                [state.overlay.layer addSublayer:state.layer];
            }
        }
        // The content host owns local coordinates. Never copy the transformed
        // outer cell/material geometry into an overlay.
        UIView *host = anchor;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (state.overlay.superview != host || state.anchor != anchor) {
            [host insertSubview:state.overlay atIndex:0];
            state.anchor = anchor;
            state.clipSource = nil;
        }
        LMVRemoveDuplicateOverlays(host, state.overlay);
        // The wrapper is plugin-owned and uses only the current host's local
        // bounds. Do not copy a system mask or layer tree: system materials
        // can contain private AVPlayerLayer instances that must remain theirs.
        CALayer *hostLayer = host.layer.presentationLayer ?: host.layer;
        state.overlay.frame = host.bounds;
        state.overlay.transform = CGAffineTransformIdentity;
        state.overlay.layer.cornerRadius = hostLayer.cornerRadius;
        state.overlay.layer.cornerCurve = hostLayer.cornerCurve;
        state.overlay.layer.maskedCorners = hostLayer.maskedCorners;
        state.overlay.layer.mask = nil;
        state.overlay.layer.masksToBounds = YES;
        state.layer.frame = state.overlay.bounds;
        state.poster.frame = state.overlay.bounds;
        if (LMVPosters[path]) state.poster.image = LMVPosters[path];
        // A player with no drawable frame must not obscure the asynchronous poster.
        state.layer.hidden = !state.layer.readyForDisplay;
        state.poster.hidden = state.layer.readyForDisplay;
        state.overlay.alpha = LMVOpacityEnabled ? LMVOpacity : 0.0;
        [CATransaction commit];
        if (anchorVisible) state.lastVisible = now;
        // AVF configures a new looper's current item asynchronously. The common-
        // mode display link retries on main; keep the poster until a frame exists.
        if (anchorVisible && state.player.status == AVPlayerStatusReadyToPlay &&
            state.player.currentItem.status == AVPlayerItemStatusReadyToPlay && !state.playing) {
            LMVStartSynchronized(state);
        }
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
    for (LMVVideoState *state in states.allValues) { LMVPause(state); LMVDetachOverlay(state); }
    objc_setAssociatedObject(self, &LMVHostsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &LMVDiscoveryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end

// These private hosts own the message geometry during stack collapse. Hooks are
// guarded by Logos class resolution and never target arbitrary UIView objects.
static void LMVUpdateMessageHost(UIView *host) {
    Class cellClass = NSClassFromString(@"NCNotificationListCell");
    UIView *owner = host;
    while (owner && (!cellClass || ![owner isKindOfClass:cellClass])) owner = owner.superview;
    if (owner) { [LMVCells addObject:owner]; LMVUpdate(owner); }
}
%hook NCNotificationShortLookView
- (void)layoutSubviews {
    %orig;
    LMVUpdateMessageHost((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    LMVUpdateMessageHost((UIView *)self);
}
%end
%hook NCNotificationSeamlessContentView
- (void)layoutSubviews {
    %orig;
    LMVUpdateMessageHost((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    LMVUpdateMessageHost((UIView *)self);
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
static void LMVRefresh(BOOL reload) {
    if (reload) {
        // Imports can overwrite an existing filename; URL equality does not mean same media.
        [LMVWarmPlayers removeAllObjects];
        [LMVSources removeAllObjects]; [LMVAssets removeAllObjects]; [LMVItems removeAllObjects]; [LMVReadyAssets removeAllObjects]; [LMVPosters removeAllObjects];
        [LMVRevisions removeAllObjects]; [LMVClockStarts removeAllObjects];
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
                LMVPause(state); LMVDetachOverlay(state); [states removeObjectForKey:target];
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
static CADisplayLink *LMVLink;
static void LMVSuspend(void) {
    [LMVLink invalidate]; LMVLink = nil;
    [LMVWarmPlayers removeAllObjects];
    for (UIView *cell in LMVCells.allObjects) {
        NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
        for (LMVVideoState *state in states.allValues) LMVReleasePlayer(state);
    }
}
static void LMVSyncDisplayLink(void) {
    if (!LMVPlaybackAllowed() || LMVPlayerCount <= LMVWarmPlayers.count) {
        [LMVLink invalidate]; LMVLink = nil;
        return;
    }
    if (!LMVLink) {
        LMVLink = [CADisplayLink displayLinkWithTarget:[LMVDisplayLinkTarget new] selector:@selector(tick:)];
        LMVLink.preferredFramesPerSecond = 30;
        [LMVLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
@implementation LMVDisplayLinkTarget
- (void)tick:(CADisplayLink *)link {
    if (!LMVPlaybackAllowed()) { LMVSuspend(); return; }
    static CFTimeInterval lastCleanup;
    static CFTimeInterval lastRevisionCheck;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - lastRevisionCheck >= 2.0) {
        lastRevisionCheck = now;
        LMVPrepareAssets();
    }
    if (now - lastCleanup >= 0.5) {
        lastCleanup = now;
        for (UIView *cell in LMVCells.allObjects) {
            NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
            if (!LMVVisible(cell)) for (LMVVideoState *state in states.allValues) {
                if (now - state.lastVisible > 8) LMVReleasePlayer(state);
            }
        }
        LMVPrewarmPlayers();
    }
    for (UIView *cell in LMVCells.allObjects) {
        if (!cell.window) continue;
        NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
        BOOL cellVisible = LMVVisible(cell);
        BOOL update = cellVisible && !states.count;
        for (LMVVideoState *state in states.allValues) {
            BOOL visible = cellVisible && state.anchor && [state.anchor isDescendantOfView:cell] && LMVVisible(state.anchor);
            if (visible) state.lastVisible = CACurrentMediaTime();
            if (!visible && (!state.visibilityLossSince || CACurrentMediaTime() - state.visibilityLossSince >= 0.18)) LMVPause(state);
            BOOL ready = state.player.status == AVPlayerStatusReadyToPlay && state.player.currentItem.status == AVPlayerItemStatusReadyToPlay;
            BOOL canStart = visible && !state.playing && (ready || (!state.player && LMVPlayerCount < LMVPlayerLimit && [LMVReadyAssets containsObject:state.path]));
            if (canStart || ![state.revision isEqualToString:LMVRevisions[state.path]] || (state.layer && state.layer.hidden == state.layer.readyForDisplay) || (visible && !state.overlay.superview)) update = YES;
        }
        if (update) LMVUpdate(cell);
    }
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
        else { LMVPrepareAssets(); LMVPrewarmPlayers(); LMVRefresh(NO); }
    });
}
%ctor {
    @autoreleasepool {
        LMVCells = [NSHashTable weakObjectsHashTable];
        LMVWarmPlayers = [NSMutableDictionary new];
        LMVRevisions = [NSMutableDictionary new]; LMVClockStarts = [NSMutableDictionary new];
        LMVSources = [NSMutableDictionary new]; LMVAssets = [NSMutableDictionary new]; LMVItems = [NSMutableDictionary new]; LMVReadyAssets = [NSMutableSet new]; LMVPosters = [NSMutableDictionary new];
        LMVLoadPreferences();
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
