#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <float.h>

static NSString * const LMVDirectory = @"/var/mobile/LockMessageVideo";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSHashTable<UIView *> *LMVCells;
static NSMutableDictionary<NSString *, NSString *> *LMVPaths;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static NSMutableDictionary<NSString *, AVURLAsset *> *LMVSources;
static NSMutableDictionary<NSString *, AVAsset *> *LMVAssets;
static NSMutableSet<NSString *> *LMVReadyAssets;
static NSMutableDictionary<NSString *, UIImage *> *LMVPosters;
static CGFloat LMVOpacity = 0.55;
static int LMVBlankToken = -1;
static char LMVStatesKey, LMVHostsKey, LMVDiscoveryKey;
static NSUInteger LMVPlayerCount;
static const NSUInteger LMVPlayerLimit = 18;
static void LMVUpdate(UIView *cell);

@interface LMVVideoState : NSObject
@property(nonatomic, strong) UIView *overlay;
@property(nonatomic, strong) AVPlayerLayer *layer;
@property(nonatomic, strong) UIImageView *poster;
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLooper *looper;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, weak) UIView *anchor;
@property(nonatomic, weak) CALayer *clipSource;
@property(nonatomic) CFTimeInterval lastVisible;
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

static void LMVPrepareAudioSession(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error = nil;
        // SpringBoard owns this shared session; never activate/deactivate it here.
        if (![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAmbient
                                                  mode:AVAudioSessionModeDefault
                                               options:AVAudioSessionCategoryOptionMixWithOthers
                                                 error:&error]) {
            NSLog(@"[LockMessageVideo] Non-interrupting audio category failed: %@", error);
        }
    });
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
        if (![wanted containsObject:path]) { [LMVSources removeObjectForKey:path]; [LMVAssets removeObjectForKey:path]; [LMVReadyAssets removeObject:path]; [LMVPosters removeObjectForKey:path]; }
    }
    for (NSString *path in wanted) {
        if (LMVSources[path]) continue;
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
    NSNumber *opacity = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("MessageBackgroundOpacity"), kLMVPrefsID);
    LMVOpacity = [opacity respondsToSelector:@selector(floatValue)] ? MAX(0.1, MIN(1.0, opacity.floatValue)) : 0.55;
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
static BOOL LMVActionBranch(UIView *view) { return [NSStringFromClass(view.class) containsString:@"ActionButtons"]; }
static UIView *LMVMessageMaterial(UIView *view, NSUInteger depth) {
    if (depth > 12 || LMVActionBranch(view) || view.hidden || view.alpha < 0.01) return nil;
    if ([NSStringFromClass(view.class) containsString:@"MaterialView"] && view.bounds.size.width > 20 && view.bounds.size.height > 20) return view;
    for (UIView *child in view.subviews) {
        UIView *material = LMVMessageMaterial(child, depth + 1);
        if (material) return material;
    }
    return nil;
}
static NSString *LMVSemanticTarget(UIView *view) {
    NSString *title = nil;
    if ([view isKindOfClass:UIButton.class]) title = [(UIButton *)view currentTitle];
    if ([view isKindOfClass:UILabel.class]) title = [(UILabel *)view text];
    for (NSString *label in @[(title ?: @""), (view.accessibilityLabel ?: @"")]) {
        NSString *text = [[label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
        if ([@[@"clear", @"clear all", @"清除", @"清除全部", @"清除所有", @"清除所有通知"] containsObject:text]) return @"Clear";
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
static void LMVPause(LMVVideoState *state) {
    if (state.playing) { [state.player pause]; state.playing = NO; }
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
static void LMVUpdate(UIView *cell) {
    NSMutableDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
    if (!states) { states = [NSMutableDictionary new]; objc_setAssociatedObject(cell, &LMVStatesKey, states, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    BOOL visible = LMVVisible(cell);
    if (!cell.window) { for (LMVVideoState *state in states.allValues) LMVPause(state); return; }
    if (!visible) { for (LMVVideoState *state in states.allValues) LMVPause(state); }
    NSMapTable *hosts = objc_getAssociatedObject(cell, &LMVHostsKey);
    if (!hosts) { hosts = [NSMapTable strongToWeakObjectsMapTable]; objc_setAssociatedObject(cell, &LMVHostsKey, hosts, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    UIView *cachedMessage = [hosts objectForKey:@"Message"];
    if (cachedMessage && (cachedMessage.hidden || cachedMessage.alpha < 0.01 || cachedMessage.bounds.size.width < 1)) {
        [hosts removeObjectForKey:@"Message"];
        objc_setAssociatedObject(cell, &LMVDiscoveryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    BOOL missing = NO;
    for (NSString *target in @[@"Message", @"Options", @"Clear"]) {
        UIView *host = [hosts objectForKey:target];
        if (host && ![host isDescendantOfView:cell]) { [hosts removeObjectForKey:target]; host = nil; }
        if (LMVEnabled[target].boolValue && LMVPaths[target] && !host && ([target isEqualToString:@"Message"] || visible)) missing = YES;
    }
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *last = objc_getAssociatedObject(cell, &LMVDiscoveryKey);
    if (missing && (!last || now - last.doubleValue >= 0.2)) {
        objc_setAssociatedObject(cell, &LMVDiscoveryKey, @(now), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        LMVActionHosts(cell, hosts, 0);
        UIView *material = LMVMessageMaterial(cell, 0);
        if (material) [hosts setObject:material forKey:@"Message"];
    }
    for (NSString *target in @[@"Message", @"Options", @"Clear"]) {
        UIView *anchor = [hosts objectForKey:target];
        NSString *path = LMVPaths[target];
        LMVVideoState *state = states[target];
        if (!LMVEnabled[target].boolValue || !path || (state && ![state.path isEqualToString:path])) {
            LMVPause(state); [state.overlay removeFromSuperview]; [states removeObjectForKey:target]; state = nil;
            if (!LMVEnabled[target].boolValue || !path) continue;
        }
        if (!anchor || !anchor.superview) { LMVPause(state); [state.overlay removeFromSuperview]; state.anchor = nil; continue; }
        BOOL anchorVisible = visible && LMVVisible(anchor);
        if (!anchorVisible) LMVPause(state);
        if (!state) {
            // The fallback surface exists even while the decoder budget is exhausted.
            state = [LMVVideoState new]; state.path = path;
            state.overlay = [UIView new]; state.overlay.userInteractionEnabled = NO;
            state.overlay.clipsToBounds = YES;
            state.poster = [UIImageView new];
            state.poster.contentMode = UIViewContentModeScaleAspectFill;
            state.poster.clipsToBounds = YES;
            [state.overlay addSubview:state.poster];
            states[target] = state;
        }
        if (anchorVisible && !state.player && [LMVReadyAssets containsObject:path]) {
            LMVMakeRoom();
            if (LMVPlayerCount < LMVPlayerLimit) {
                LMVPrepareAudioSession();
                state.player = [AVQueuePlayer queuePlayerWithItems:@[]]; LMVPlayerCount++;
                state.player.muted = YES; state.player.automaticallyWaitsToMinimizeStalling = NO;
                AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:LMVAssets[path]];
                item.preferredForwardBufferDuration = 1;
                state.looper = [AVPlayerLooper playerLooperWithPlayer:state.player templateItem:item];
                state.layer = [AVPlayerLayer playerLayerWithPlayer:state.player];
                state.layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
                [state.overlay.layer addSublayer:state.layer];
            }
        }
        BOOL material = [NSStringFromClass(anchor.class) containsString:@"MaterialView"];
        UIView *host = material ? anchor.superview : anchor;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (state.overlay.superview != host || state.anchor != anchor) {
            if (material) [host insertSubview:state.overlay aboveSubview:anchor];
            else [host insertSubview:state.overlay atIndex:0];
            state.anchor = anchor;
            state.clipSource = nil;
        }
        if (!state.clipSource || !state.clipSource.superlayer) state.clipSource = LMVClipSource(anchor.layer, state.overlay.layer, 0);
        CALayer *clip = state.clipSource ?: anchor.layer;
        if (material) {
            state.overlay.bounds = anchor.bounds;
            state.overlay.center = anchor.center;
            state.overlay.transform = anchor.transform;
        } else { state.overlay.frame = host.bounds; }
        state.overlay.layer.cornerRadius = clip.cornerRadius;
        state.overlay.layer.cornerCurve = clip.cornerCurve;
        state.overlay.layer.maskedCorners = clip.maskedCorners;
        state.overlay.layer.mask = LMVCopyMask(clip.mask, state.overlay.layer.mask, 0);
        state.layer.frame = state.overlay.bounds;
        state.poster.frame = state.overlay.bounds;
        state.poster.image = LMVPosters[path];
        // A player with no drawable frame must not obscure the asynchronous poster.
        state.layer.hidden = !state.layer.readyForDisplay;
        state.poster.hidden = state.layer.readyForDisplay;
        state.overlay.alpha = LMVOpacity;
        [CATransaction commit];
        if (anchorVisible) state.lastVisible = now;
        if (anchorVisible && state.player && !state.playing) { [state.player play]; state.playing = YES; }
    }
}
%hook NCNotificationListCell
- (void)layoutSubviews {
    %orig;
    [LMVCells addObject:(UIView *)self];
    LMVUpdate((UIView *)self);
}
- (void)didMoveToWindow {
    %orig;
    [LMVCells addObject:(UIView *)self];
    LMVUpdate((UIView *)self);
}
- (void)prepareForReuse {
    NSDictionary *states = objc_getAssociatedObject(self, &LMVStatesKey);
    for (LMVVideoState *state in states.allValues) { LMVPause(state); [state.overlay removeFromSuperview]; state.anchor = nil; }
    objc_setAssociatedObject(self, &LMVHostsKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(self, &LMVDiscoveryKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    %orig;
}
%end
%hook PLActionButtonsPresentingView
- (void)layoutSubviews {
    %orig;
    UIView *ancestor = (UIView *)self;
    Class cellClass = NSClassFromString(@"NCNotificationListCell");
    while (ancestor && cellClass && ![ancestor isKindOfClass:cellClass]) ancestor = ancestor.superview;
    if (ancestor && cellClass) LMVUpdate(ancestor);
}
%end
static void LMVRefresh(BOOL reload) {
    if (reload) {
        // Imports can overwrite an existing filename; URL equality does not mean same media.
        [LMVSources removeAllObjects]; [LMVAssets removeAllObjects]; [LMVReadyAssets removeAllObjects]; [LMVPosters removeAllObjects];
        for (UIView *cell in LMVCells.allObjects) {
            NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
            for (LMVVideoState *state in states.allValues) {
                LMVReleasePlayer(state); state.poster.image = nil;
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
        if (reload) LMVUpdate(cell);
    }
}
// Tracking mode suppresses default-mode timers and scrolling does not relayout every cell.
// Only visibility/readiness/host identity transitions invoke the heavier layout path.
@interface LMVDisplayLinkTarget : NSObject
- (void)tick:(CADisplayLink *)link;
@end
@implementation LMVDisplayLinkTarget
- (void)tick:(CADisplayLink *)link {
    for (UIView *cell in LMVCells.allObjects) {
        if (!cell.window) continue;
        NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
        BOOL cellVisible = LMVVisible(cell);
        BOOL update = cellVisible && !states.count;
        for (LMVVideoState *state in states.allValues) {
            BOOL visible = cellVisible && state.anchor && [state.anchor isDescendantOfView:cell] && LMVVisible(state.anchor);
            if (visible) state.lastVisible = CACurrentMediaTime();
            if (!visible) LMVPause(state);
            BOOL canStart = visible && !state.playing && (state.player || (LMVPlayerCount < LMVPlayerLimit && [LMVReadyAssets containsObject:state.path]));
            if (canStart || (state.layer && state.layer.hidden == state.layer.readyForDisplay) || (visible && !state.overlay.superview)) update = YES;
        }
        if (update) LMVUpdate(cell);
    }
}
@end
static void LMVDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ LMVRefresh(YES); });
}
%ctor {
    @autoreleasepool {
        LMVCells = [NSHashTable weakObjectsHashTable];
        LMVSources = [NSMutableDictionary new]; LMVAssets = [NSMutableDictionary new]; LMVReadyAssets = [NSMutableSet new]; LMVPosters = [NSMutableDictionary new];
        LMVLoadPreferences();
        notify_register_check("com.apple.springboard.hasBlankedScreen", &LMVBlankToken);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { LMVRefresh(NO); }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                for (UIView *cell in LMVCells.allObjects) { NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey); for (LMVVideoState *state in states.allValues) LMVPause(state); }
            }];
            NSTimer *cleanup = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) { LMVRefresh(NO); }];
            [NSRunLoop.mainRunLoop addTimer:cleanup forMode:NSRunLoopCommonModes];
            CADisplayLink *link = [CADisplayLink displayLinkWithTarget:[LMVDisplayLinkTarget new] selector:@selector(tick:)];
            link.preferredFramesPerSecond = 60;
            [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
        });
    }
}
