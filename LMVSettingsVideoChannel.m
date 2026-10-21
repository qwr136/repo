#import "LMVSettingsVideoChannel.h"

// 2.65: the player that runs inside the Settings app.
//
// Layering: window → our host (index 0) → the app's own view tree. The app's
// scroll/navigation backgrounds are made clear so the video shows through; every
// original colour is remembered and restored when the channel stands down.
// 2.67: diagnostics for THIS process. The SpringBoard logger does not exist here,
// so the channel writes the same file/format itself (only when 诊断日志 is on).
static NSInteger const LMVSettingsVideoHostTag = 0x5E65;

static void LMVSettingsVideoLog(NSString *event) {
    if (!event.length) return;
    NSNumber *on = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("DiagnosticsEnabled"), LMVSettingsVideoPrefsID);
    if (!on.boolValue) return;
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ formatter = [NSDateFormatter new]; formatter.dateFormat = @"HH:mm:ss.SSS"; });
    // 2.68: the user asked for this log INSIDE the material folder.
    NSString *folder = LMVSettingsVideoRoot;
    [NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [folder stringByAppendingPathComponent:@"settings-render.log"];
    if (![NSFileManager.defaultManager fileExistsAtPath:path])
        [NSFileManager.defaultManager createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    @try {
        [handle seekToEndOfFile];
        NSString *line = [NSString stringWithFormat:@"%.3f version=%@ session=1 pid=%d %@\n",
            CACurrentMediaTime(), @"2.67", getpid(), event];
        [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
    } @catch (__unused NSException *exception) { }
    @finally { [handle closeFile]; }
}

// One line per node, depth-limited: class@x,y WxH h<0/1> a<alpha> bg<a> sub<n>
// Our own host/layer are tagged so the log can be read without guessing.
static void LMVSettingsVideoDump(UIView *view, NSInteger depth, NSMutableString *out, NSUInteger *budget) {
    if (!view || depth > 7 || *budget == 0) return;
    (*budget)--;
    CGFloat bgAlpha = 1;
    UIColor *color = view.backgroundColor;
    if (color) { CGFloat r=0,g=0,b=0,a=1; [color getRed:&r green:&g blue:&b alpha:&a]; bgAlpha = a; }
    CGRect frame = view.frame;
    [out appendFormat:@"%@%@@%.0f,%.0f %.0fx%.0f h%d a%.2f bg%.2f sub%lu \n",
        [NSString stringWithFormat:@"%*s", (int)(depth * 2), ""],
        NSStringFromClass(view.class), frame.origin.x, frame.origin.y,
        frame.size.width, frame.size.height, (int)view.hidden, view.alpha, bgAlpha,
        (unsigned long)view.subviews.count];
    for (UIView *child in view.subviews) LMVSettingsVideoDump(child, depth + 1, out, budget);
}

@implementation LMVSettingsVideoChannel

+ (instancetype)shared {
    static LMVSettingsVideoChannel *shared;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ shared = [LMVSettingsVideoChannel new]; });
    return shared;
}

- (void)start {
    if (self.timer) return;
    // One cheap tick a second: the material, the switch and the key window can all
    // change while the app is running, and a 1 Hz poll costs nothing here.
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refresh];
    }];
    self.timer.tolerance = .3;
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self refresh];
    LMVSettingsVideoLog(@"settings-video start (Settings process)");
}

- (NSString *)selectedPath {
    id relative = LMVSettingsVideoRead(LMVSettingsVideoFileKey);
    if (![relative isKindOfClass:NSString.class] || ![(NSString *)relative length]) return nil;
    NSString *name = [(NSString *)relative lastPathComponent];
    if (!name.length || [name isEqualToString:@".."] || [name isEqualToString:@"."]) return nil;
    NSString *path = [LMVSettingsVideoRoot stringByAppendingPathComponent:name];
    return [NSFileManager.defaultManager fileExistsAtPath:path] ? path : nil;
}

- (UIWindow *)currentWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *candidate in windowScene.windows) {
            if (candidate.hidden || candidate.alpha < .01) continue;
            if (candidate.windowLevel != UIWindowLevelNormal) continue;
            return candidate;
        }
    }
    return nil;
}

// The Settings app paints its list on a UIScrollView/UINavigationController view.
// Only background colours are touched, and each one is remembered.
static NSMutableDictionary<NSValue *, UIColor *> *LMVSettingsSavedColors;

- (BOOL)needsClear:(UIView *)view {
    if ([view isKindOfClass:UIScrollView.class] || [view isKindOfClass:UITableView.class] ||
        [view isKindOfClass:UICollectionView.class]) return YES;
    NSString *name = NSStringFromClass(view.class);
    // 2.66: the Settings app is a UISplitViewController in landscape: its two
    // column views are opaque (white list pane / black detail pane) and they were
    // hiding the video, leaving only the divider gap visible. Clear every column
    // container by CLASS NAME (private, so no header dependency).
    for (NSString *token in @[@"SplitViewController", @"Column", @"TransitionView",
                              @"DropShadowView", @"Platter", @"BackgroundView", @"CollectionView"]) {
        if ([name rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

- (void)clearBackgroundsIn:(UIView *)view depth:(NSInteger)depth {
    if (!view || depth > 14) return;
    if ([self needsClear:view]) {
        if ([view isKindOfClass:UITableView.class])
            ((UITableView *)view).backgroundView = nil;
        if ([view isKindOfClass:UICollectionView.class])
            ((UICollectionView *)view).backgroundView = nil;
        if (view.backgroundColor && view.backgroundColor != UIColor.clearColor) {
            if (!LMVSettingsSavedColors) LMVSettingsSavedColors = [NSMutableDictionary dictionary];
            NSValue *key = [NSValue valueWithNonretainedObject:view];
            if (!LMVSettingsSavedColors[key]) LMVSettingsSavedColors[key] = view.backgroundColor;
            view.backgroundColor = UIColor.clearColor;
        }
    }
    for (UIView *child in view.subviews) [self clearBackgroundsIn:child depth:depth + 1];
}

- (void)restoreBackgrounds {
    for (NSValue *key in LMVSettingsSavedColors) {
        UIView *view = [key nonretainedObjectValue];
        UIColor *color = LMVSettingsSavedColors[key];
        if (view && color) view.backgroundColor = color;
    }
    [LMVSettingsSavedColors removeAllObjects];
}

- (void)buildPlayerForPath:(NSString *)path sound:(BOOL)sound volume:(float)volume {
    [self.player pause];
    [self.looper disableLooping];
    self.player = nil; self.looper = nil;
    if (!path) return;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    item.preferredForwardBufferDuration = 1;
    AVQueuePlayer *player = [AVQueuePlayer queuePlayerWithItems:@[]];
    player.muted = !sound;
    player.volume = sound ? volume : 0;
    player.allowsExternalPlayback = NO;
    player.automaticallyWaitsToMinimizeStalling = NO;
    if ([player respondsToSelector:@selector(setPreventsDisplaySleepDuringVideoPlayback:)])
        player.preventsDisplaySleepDuringVideoPlayback = NO;
    AVPlayerLooper *looper = [AVPlayerLooper playerLooperWithPlayer:player templateItem:item];
    AVPlayerLayer *layer = [AVPlayerLayer playerLayerWithPlayer:player];
    layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    layer.frame = self.host.bounds;
    [self.host.layer addSublayer:layer];
    self.player = player; self.looper = looper;
    [player play];
}

- (void)installIfNeeded {
    UIWindow *window = [self currentWindow];
    if (!window) return;
    UIView *root = window.rootViewController.view;
    if (!root) return;
    if (!self.host) {
        self.host = [[UIView alloc] initWithFrame:window.bounds];
        self.host.userInteractionEnabled = NO;
        self.host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.host.backgroundColor = UIColor.clearColor;
        self.host.tag = LMVSettingsVideoHostTag;
    }
    self.window = window;
    if (self.host.superview != window) {
        [window insertSubview:self.host atIndex:0];
    }
    if (!CGRectEqualToRect(self.host.frame, window.bounds)) self.host.frame = window.bounds;
    // The app's own container views are opaque; clear the scroll backgrounds so the
    // video is visible behind the grouped rows.
    if (root.backgroundColor && root.backgroundColor != UIColor.clearColor) {
        if (!LMVSettingsSavedColors) LMVSettingsSavedColors = [NSMutableDictionary dictionary];
        NSValue *key = [NSValue valueWithNonretainedObject:root];
        if (!LMVSettingsSavedColors[key]) LMVSettingsSavedColors[key] = root.backgroundColor;
        root.backgroundColor = UIColor.clearColor;
    }
    [self clearBackgroundsIn:root depth:0];
}

- (void)refresh {
    if (!LMVSettingsVideoEnabled()) { [self stop]; return; }
    NSString *path = [self selectedPath];
    if (!path) { [self stop]; return; }
    [self installIfNeeded];
    if (!self.host.superview) { [self stop]; return; }
    BOOL sound = [LMVSettingsVideoRead(LMVSettingsVideoSoundKey) boolValue];
    NSNumber *volumeValue = LMVSettingsVideoRead(LMVSettingsVideoVolumeKey);
    float volume = volumeValue ? [volumeValue floatValue] : .5f;
    if (volume < 0) volume = 0; if (volume > 1) volume = 1;
    if (![self.path isEqualToString:path] || !self.player || self.player.muted == sound) {
        BOOL rebuild = ![self.path isEqualToString:path] || !self.player;
        self.path = path;
        if (rebuild) [self buildPlayerForPath:path sound:sound volume:volume];
        else { self.player.muted = !sound; self.player.volume = sound ? volume : 0; }
    }
    self.player.muted = !sound;
    self.player.volume = sound ? volume : 0;
    UIWindow *window = self.window;
    if (window && !CGRectEqualToRect(self.host.frame, window.bounds)) self.host.frame = window.bounds;
    for (CALayer *layer in self.host.layer.sublayers) {
        if ([layer isKindOfClass:AVPlayerLayer.class] && !CGRectEqualToRect(layer.frame, self.host.bounds))
            layer.frame = self.host.bounds;
    }
    // 2.67: diagnostics. One summary line plus a depth-limited hierarchy dump, so
    // "sound but no picture" can be answered from the log: where the host sits, what
    // sits above it, and which views are still opaque.
    static CFTimeInterval lastLog;
    CFTimeInterval now = CACurrentMediaTime();
    NSNumber *diagnostics = (__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("DiagnosticsEnabled"), LMVSettingsVideoPrefsID);
    if (diagnostics.boolValue && now - lastLog > 3) {
        lastLog = now;
        NSInteger index = window ? (NSInteger)[window.subviews indexOfObjectIdenticalTo:self.host] : -1;
        CALayer *layer = nil;
        for (CALayer *candidate in self.host.layer.sublayers)
            if ([candidate isKindOfClass:AVPlayerLayer.class]) { layer = candidate; break; }
        LMVSettingsVideoLog([NSString stringWithFormat:
            @"settings-video win=%@ %.0fx%.0f host@%ld %.0fx%.0f layer=%.0fx%.0f hidden=%d ready=%d cleared=%lu subs=%lu",
            window ? NSStringFromClass(window.class) : @"none",
            window.bounds.size.width, window.bounds.size.height,
            (long)index, self.host.bounds.size.width, self.host.bounds.size.height,
            layer ? layer.frame.size.width : 0, layer ? layer.frame.size.height : 0,
            layer ? (int)layer.hidden : -1,
            layer ? (int)((AVPlayerLayer *)layer).readyForDisplay : -1,
            (unsigned long)LMVSettingsSavedColors.count,
            (unsigned long)window.subviews.count]);
        NSMutableString *tree = [NSMutableString string];
        NSUInteger budget = 400;
        LMVSettingsVideoDump(window, 0, tree, &budget);
        LMVSettingsVideoLog([NSString stringWithFormat:@"settings-video-tree\n%@", tree]);
    }
}

- (void)stop {
    [self.player pause];
    [self.looper disableLooping];
    self.player = nil; self.looper = nil; self.path = nil;
    for (CALayer *layer in [self.host.layer.sublayers copy])
        if ([layer isKindOfClass:AVPlayerLayer.class]) [layer removeFromSuperlayer];
    [self.host removeFromSuperview];
    [self restoreBackgrounds];
}

@end