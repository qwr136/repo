#import "LMVSettingsVideoChannel.h"
#import <objc/runtime.h>

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
            CACurrentMediaTime(), LMV_VERSION_STRING, getpid(), event];
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

// 2.77: ENTER A PAGE, REFRESH AT ONCE. Waiting for the 1 s tick showed the new
// table's white background first ("点二级菜单会先白一下"). Swizzling the two
// appearance callbacks is enough - the Settings app is our own process here.
static void (*LMVSettingsOriginalViewWillAppear)(id, SEL, BOOL);
static void (*LMVSettingsOriginalViewDidAppear)(id, SEL, BOOL);

static void LMVSettingsViewWillAppear(id self, SEL _cmd, BOOL animated) {
    LMVSettingsOriginalViewWillAppear(self, _cmd, animated);
    LMVSettingsVideoChannel *channel = [LMVSettingsVideoChannel shared];
    [channel refresh];
    [channel logOccluders:@"willAppear"];
}
static void LMVSettingsViewDidAppear(id self, SEL _cmd, BOOL animated) {
    LMVSettingsOriginalViewDidAppear(self, _cmd, animated);
    LMVSettingsVideoChannel *channel = [LMVSettingsVideoChannel shared];
    [channel refresh];
    [channel logOccluders:@"didAppear"];
}

// 2.78: A NEW CELL IS OPAQUE FOR ONE FRAME unless we clear it the moment it lays
// out. Polling once a second left a white flash on every scroll step, so the two
// cell classes are swizzled in this process instead.
static void (*LMVSettingsOriginalCellLayout)(id, SEL);
static void (*LMVSettingsOriginalCollectionCellLayout)(id, SEL);

static void LMVSettingsClearCell(id cell) {
    if (![LMVSettingsVideoChannel shared].isActive) return;
    UIColor *bg = [(UITableViewCell *)cell backgroundColor];
    if (bg && CGColorGetAlpha(bg.CGColor) > .001) [(UITableViewCell *)cell setBackgroundColor:UIColor.clearColor];
    UIView *content = [(UITableViewCell *)cell contentView];
    if (content && content.backgroundColor && CGColorGetAlpha(content.backgroundColor.CGColor) > .001)
        content.backgroundColor = UIColor.clearColor;
}

static void LMVSettingsCellLayout(id self, SEL _cmd) {
    LMVSettingsOriginalCellLayout(self, _cmd);
    LMVSettingsClearCell(self);
}
static void LMVSettingsCollectionCellLayout(id self, SEL _cmd) {
    LMVSettingsOriginalCollectionCellLayout(self, _cmd);
    LMVSettingsClearCell(self);
}

// 2.87: STOP THE WHITE AT ITS SOURCE. Sweeping colours cannot win: the app sets them
// again on every layout/scroll (cells, table, containers), so a white frame always
// slips through. This swizzles -setBackgroundColor: and forces the SURFACE classes to
// clear while the channel is active; decoration layers are still hidden by the sweep.
static void (*LMVSettingsOriginalSetBackgroundColor)(id, SEL, UIColor *);

// 2.90: NO CLASS LIST AT ALL. The diagnostic proved the white is transient: it is
// painted between our sweeps (white-frame count=0 at every sample). Filtering by
// class only narrowed which surfaces flash. While the channel is active EVERY
// background is forced clear at the moment it is set - labels, icons and images are
// unaffected because they do not use backgroundColor.
static BOOL LMVSettingsIsSurface(id view) {
    LMVSettingsVideoChannel *channel = [LMVSettingsVideoChannel shared];
    if (view == channel.host) return NO;
    // Never strip the colour from the text/tint of controls that need it to be seen.
    if ([view isKindOfClass:UIButton.class]) return NO;
    for (UIView *node = [(UIView *)view superview]; node; node = node.superview)
        if (node == channel.host) return NO;
    return YES;
}

// 2.89-diag: scrolling is where the white keeps appearing - log at most every 60 ms.
static void (*LMVSettingsOriginalSetContentOffset)(id, SEL, CGPoint);
static void (*LMVSettingsOriginalSetContentOffsetAnimated)(id, SEL, CGPoint, BOOL);

static void LMVSettingsScrollTick(void) {
    static CFTimeInterval last;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - last < .06) return;
    last = now;
    [[LMVSettingsVideoChannel shared] logOccluders:@"scroll"];
}

static void LMVSettingsSetContentOffset(id self, SEL _cmd, CGPoint offset) {
    LMVSettingsOriginalSetContentOffset(self, _cmd, offset);
    LMVSettingsScrollTick();
}
static void LMVSettingsSetContentOffsetAnimated(id self, SEL _cmd, CGPoint offset, BOOL animated) {
    LMVSettingsOriginalSetContentOffsetAnimated(self, _cmd, offset, animated);
    LMVSettingsScrollTick();
}

// 2.91: CLEAR DURING LAYOUT, NOT ON A TIMER. layoutSubviews runs while the frame is
// being prepared, so clearing here happens BEFORE it is composited - a 0.1 s sweep
// can never win that race (the diagnostic showed white-frame count=0 at every
// sample: the white lived for a frame or two between sweeps).
static void (*LMVSettingsOriginalLayoutSubviews)(id, SEL);

static void LMVSettingsLayoutSubviews(id self, SEL _cmd) {
    LMVSettingsOriginalLayoutSubviews(self, _cmd);
    LMVSettingsVideoChannel *channel = [LMVSettingsVideoChannel shared];
    if (!channel.isActive) return;
    UIView *view = (UIView *)self;
    if (view == channel.host) return;
    if ([view isKindOfClass:UIButton.class]) return;
    for (UIView *node = view.superview; node; node = node.superview)
        if (node == channel.host) return;
    // 2.92: the logged offenders (UITableView, its container UIView) must always be
    // forced clear during layout, whatever class list says.
    if ([view isKindOfClass:UITableView.class] || [view isKindOfClass:UICollectionView.class] ||
        [view isKindOfClass:UITableViewCell.class] || [view isKindOfClass:UICollectionViewCell.class] ||
        [view isKindOfClass:UIScrollView.class]) {
        view.backgroundColor = UIColor.clearColor;
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
    }
    // UIKit internal views often write the layer colour directly, which the
    // setBackgroundColor: hook cannot see - clear both.
    CALayer *layer = view.layer;
    if (layer.backgroundColor && CGColorGetAlpha(layer.backgroundColor) > .001)
        layer.backgroundColor = UIColor.clearColor.CGColor;
    // 2.92: the other logged offender is a plain full-screen UIView container.
    CGRect inWindow = view.window ? [view convertRect:view.bounds toView:view.window] : CGRectZero;
    BOOL fullScreen = view.window && inWindow.size.width >= view.window.bounds.size.width - 1 &&
        inWindow.size.height >= view.window.bounds.size.height * .5;
    if (fullScreen) {
        view.backgroundColor = UIColor.clearColor;
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
    } else if (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor) > .001) {
        view.backgroundColor = UIColor.clearColor;
    }
}

static void LMVSettingsSetBackgroundColor(id self, SEL _cmd, UIColor *color) {
    if ([LMVSettingsVideoChannel shared].isActive && LMVSettingsIsSurface(self)) color = UIColor.clearColor;
    LMVSettingsOriginalSetBackgroundColor(self, _cmd, color);
}

// 2.89-diag: WHICH VIEW IS WHITE RIGHT NOW? Walks every window view, ignores our own
// host, and reports the ones that (a) cover at least 30% of the host area and
// (b) still paint an opaque background. Logged only (no behaviour change).
static void LMVSettingsCollectOccluders(UIView *view, UIView *host, CGRect hostFrame, NSInteger depth,
                                        NSInteger *budget, NSMutableArray<NSString *> *out) {
    if (!view || depth > 14 || *budget <= 0) return;
    (*budget)--;
    if (view == host) return;
    if (!view.hidden && view.alpha > .01) {
        CGRect frame = [view convertRect:view.bounds toView:view.window];
        CGRect onScreen = CGRectIntersection(frame, view.window.bounds);
        CGFloat area = onScreen.size.width * onScreen.size.height;
        CGFloat hostArea = hostFrame.size.width * hostFrame.size.height;
        CGFloat bgAlpha = 0;
        if (view.backgroundColor) { CGFloat r=0,g=0,b=0,a=1; if ([view.backgroundColor getRed:&r green:&g blue:&b alpha:&a]) bgAlpha = a; }
        BOOL decorative = [NSStringFromClass(view.class) containsString:@"ScrollIndicator"];
        if (hostArea > 0 && area >= hostArea * .3 && bgAlpha > .5 && !decorative && frame.size.width > 8 && frame.size.height > 8) {
            [out addObject:[NSString stringWithFormat:@"%@@%.0f,%.0f %.0fx%.0f bg%.2f d%ld",
                NSStringFromClass(view.class), frame.origin.x, frame.origin.y,
                frame.size.width, frame.size.height, bgAlpha, (long)depth]];
        }
    }
    for (UIView *child in view.subviews)
        LMVSettingsCollectOccluders(child, host, hostFrame, depth + 1, budget, out);
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
    if (!self.frameLink) {
        __weak typeof(self) weakFrame = self;
        self.frameLink = [CADisplayLink displayLinkWithTarget:[NSBlockOperation blockOperationWithBlock:^{
            LMVSettingsVideoChannel *live = weakFrame;
            if (live.isActive) [live frameSweep];
        }] selector:@selector(main)];
        [self.frameLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    if (!self.clearTimer) {
        __weak typeof(self) weakClear = self;
        self.clearTimer = [NSTimer timerWithTimeInterval:.1 repeats:YES block:^(NSTimer *timer) {
            LMVSettingsVideoChannel *live = weakClear;
            if (live.isActive) [live clearVisibleBackgrounds];
        }];
        self.clearTimer.tolerance = .03;
        [NSRunLoop.mainRunLoop addTimer:self.clearTimer forMode:NSRunLoopCommonModes];
    }
    static BOOL hooked = NO;
    if (!hooked) {
        hooked = YES;
        Method will = class_getInstanceMethod(UIViewController.class, @selector(viewWillAppear:));
        Method did = class_getInstanceMethod(UIViewController.class, @selector(viewDidAppear:));
        if (will) {
            LMVSettingsOriginalViewWillAppear = (void *)method_getImplementation(will);
            method_setImplementation(will, (IMP)LMVSettingsViewWillAppear);
        }
        if (did) {
            LMVSettingsOriginalViewDidAppear = (void *)method_getImplementation(did);
            method_setImplementation(did, (IMP)LMVSettingsViewDidAppear);
        }
        Method layout = class_getInstanceMethod(UIView.class, @selector(layoutSubviews));
        if (layout) {
            LMVSettingsOriginalLayoutSubviews = (void *)method_getImplementation(layout);
            method_setImplementation(layout, (IMP)LMVSettingsLayoutSubviews);
        }
        Method setOffset = class_getInstanceMethod(UIScrollView.class, @selector(setContentOffset:));
        if (setOffset) {
            LMVSettingsOriginalSetContentOffset = (void *)method_getImplementation(setOffset);
            method_setImplementation(setOffset, (IMP)LMVSettingsSetContentOffset);
        }
        Method setOffsetAnimated = class_getInstanceMethod(UIScrollView.class, @selector(setContentOffset:animated:));
        if (setOffsetAnimated) {
            LMVSettingsOriginalSetContentOffsetAnimated = (void *)method_getImplementation(setOffsetAnimated);
            method_setImplementation(setOffsetAnimated, (IMP)LMVSettingsSetContentOffsetAnimated);
        }
        Method setBG = class_getInstanceMethod(UIView.class, @selector(setBackgroundColor:));
        if (setBG) {
            LMVSettingsOriginalSetBackgroundColor = (void *)method_getImplementation(setBG);
            method_setImplementation(setBG, (IMP)LMVSettingsSetBackgroundColor);
        }
        Method cell = class_getInstanceMethod(UITableViewCell.class, @selector(layoutSubviews));
        if (cell) {
            LMVSettingsOriginalCellLayout = (void *)method_getImplementation(cell);
            method_setImplementation(cell, (IMP)LMVSettingsCellLayout);
        }
        Method collectionCell = class_getInstanceMethod(UICollectionViewCell.class, @selector(layoutSubviews));
        if (collectionCell) {
            LMVSettingsOriginalCollectionCellLayout = (void *)method_getImplementation(collectionCell);
            method_setImplementation(collectionCell, (IMP)LMVSettingsCollectionCellLayout);
        }
    }
    // 2.77: the app returning from the background must resume playback at once.
    for (NSString *name in @[UIApplicationDidBecomeActiveNotification, UISceneDidActivateNotification]) {
        [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) {
            [[LMVSettingsVideoChannel shared] refresh];
        }];
    }
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
static NSMapTable<UIView *, UIColor *> *LMVSettingsSavedColors;
static NSHashTable<UIView *> *LMVSettingsHiddenViews;   // 2.86   // 2.85: weak keys (dangling restore crashed Settings)

- (BOOL)needsClear:(UIView *)view {
    if ([view isKindOfClass:UIScrollView.class] || [view isKindOfClass:UITableView.class] ||
        [view isKindOfClass:UICollectionView.class]) return YES;
    NSString *name = NSStringFromClass(view.class);
    // 2.66: the Settings app is a UISplitViewController in landscape: its two
    // column views are opaque (white list pane / black detail pane) and they were
    // hiding the video, leaving only the divider gap visible. Clear every column
    // container by CLASS NAME (private, so no header dependency).
    // 2.80: the device tree showed these still opaque between our host and the list:
    // UILayoutContainerView (bg1.00), UIViewControllerWrapperView (bg1.00) - neither
    // matched an earlier token, so the pages that use this chain had no video.
    for (NSString *token in @[@"SplitViewController", @"Column", @"TransitionView",
                              @"DropShadowView", @"LayoutContainerView", @"ViewControllerWrapperView",
                              @"Platter", @"BackgroundView", @"CollectionView"]) {
        if ([name rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

// 2.82: FORCE THE WHOLE SUBTREE TRANSPARENT. Class-name whitelists kept missing a
// layer (UILayoutContainerView / UIViewControllerWrapperView / whatever iOS adds
// next). Clearing EVERY background above the host is deterministic: text, icons and
// images keep drawing (they are not background colours), only the painted surfaces go.
- (void)clearSubtreeBackgrounds:(UIView *)view depth:(NSInteger)depth budget:(NSInteger *)budget {
    if (!view || depth > 16 || *budget <= 0) return;
    (*budget)--;
    if (view == self.host) return;
    if (view.layer.backgroundColor && CGColorGetAlpha(view.layer.backgroundColor) > .001)
        view.layer.backgroundColor = UIColor.clearColor.CGColor;
    if (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor) > .001) {
        if (!LMVSettingsSavedColors) LMVSettingsSavedColors = [NSMapTable weakToStrongObjectsMapTable];
        if (![LMVSettingsSavedColors objectForKey:view]) [LMVSettingsSavedColors setObject:view.backgroundColor forKey:view];
        view.backgroundColor = UIColor.clearColor;
    }
    if (view.opaque) view.opaque = NO;
    // 2.86: DECORATION LAYERS ARE HIDDEN, not recoloured - a background that the app
    // repaints on layout cannot flicker back if it is hidden outright. Only pure
    // decoration matches these names; nothing that draws text or icons does.
    NSString *cls = NSStringFromClass(view.class);
    BOOL decoration = [cls containsString:@"BarBackground"] || [cls containsString:@"ShadowView"] ||
        [cls containsString:@"_UIBarBackground"] || [cls isEqualToString:@"UIVisualEffectView"];
    if (decoration) {
        if (!LMVSettingsHiddenViews) LMVSettingsHiddenViews = [NSHashTable weakObjectsHashTable];
        if (!view.hidden) { [LMVSettingsHiddenViews addObject:view]; view.hidden = YES; }
        return;
    }
    for (UIView *child in view.subviews)
        [self clearSubtreeBackgrounds:child depth:depth + 1 budget:budget];
}

- (void)clearBackgroundsIn:(UIView *)view depth:(NSInteger)depth {
    if (!view || depth > 14) return;
    if ([self needsClear:view]) {
        if ([view isKindOfClass:UITableView.class])
            ((UITableView *)view).backgroundView = nil;
        if ([view isKindOfClass:UICollectionView.class])
            ((UICollectionView *)view).backgroundView = nil;
        if (view.backgroundColor && view.backgroundColor != UIColor.clearColor) {
            if (!LMVSettingsSavedColors) LMVSettingsSavedColors = [NSMapTable weakToStrongObjectsMapTable];
            if (![LMVSettingsSavedColors objectForKey:view]) [LMVSettingsSavedColors setObject:view.backgroundColor forKey:view];
            view.backgroundColor = UIColor.clearColor;
        }
    }
    for (UIView *child in view.subviews) [self clearBackgroundsIn:child depth:depth + 1];
}

- (void)restoreBackgrounds {
    for (UIView *view in LMVSettingsSavedColors) {
        UIColor *color = [LMVSettingsSavedColors objectForKey:view];
        if (view && color) view.backgroundColor = color;   // weak key: nil when deallocated
    }
    [LMVSettingsSavedColors removeAllObjects];
    for (UIView *view in LMVSettingsHiddenViews) view.hidden = NO;
    [LMVSettingsHiddenViews removeAllObjects];
}

- (void)buildPlayerForPath:(NSString *)path sound:(BOOL)sound volume:(float)volume {
    [self.frameLink invalidate]; self.frameLink = nil;
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

// 2.75: the video belongs UNDER THE LIST TEXT, not under the whole window: the
// Settings app keeps an opaque UITransitionView/DropShadowView between the window
// and the table, so a window-level host is invisible. Find the table the user is
// looking at and put the host directly BELOW it in its own superview.
// 2.77: pick the table the USER IS LOOKING AT (largest visible area in the window),
// not the first one in the tree - after pushing a page the previous table is still
// in the hierarchy and used to win, so the new page had no video.
- (UITableView *)tableIn:(UIView *)view depth:(NSInteger)depth budget:(NSInteger *)budget best:(UITableView **)best bestArea:(CGFloat *)bestArea window:(UIWindow *)window {
    if (!view || depth > 12 || *budget <= 0) return nil;
    (*budget)--;
    if ([view isKindOfClass:UITableView.class]) {
        UITableView *table = (UITableView *)view;
        if (!table.hidden && table.alpha > .01 && table.window == window) {
            CGRect frame = [table convertRect:table.bounds toView:window];
            CGRect onScreen = CGRectIntersection(frame, window.bounds);
            CGFloat area = onScreen.size.width * onScreen.size.height;
            if (area > *bestArea) { *bestArea = area; *best = table; }
        }
    }
    for (UIView *child in view.subviews)
        [self tableIn:child depth:depth + 1 budget:budget best:best bestArea:bestArea window:window];
    return *best;
}

static void LMVSettingsCollectScrollViews(UIView *view, NSInteger depth, NSInteger *budget, NSMutableArray<UIScrollView *> *out) {
    if (!view || depth > 12 || *budget <= 0) return;
    (*budget)--;
    // 2.79: Settings uses both UITableView and UICollectionView depending on the page.
    if ([view isKindOfClass:UITableView.class] || [view isKindOfClass:UICollectionView.class])
        [out addObject:(UIScrollView *)view];
    for (UIView *child in view.subviews) LMVSettingsCollectScrollViews(child, depth + 1, budget, out);
}

- (void)collectTables:(UIView *)view depth:(NSInteger)depth budget:(NSInteger *)budget into:(NSMutableArray<UITableView *> *)out {
    NSMutableArray<UIScrollView *> *views = [NSMutableArray array];
    LMVSettingsCollectScrollViews(view, depth, budget, views);
    for (UIScrollView *scroll in views) if ([scroll isKindOfClass:UITableView.class]) [out addObject:(UITableView *)scroll];
}

- (NSArray<UIScrollView *> *)allScrollViewsInWindow:(UIWindow *)window {
    if (!window.rootViewController.view) return @[];
    NSInteger budget = 1500;
    NSMutableArray<UIScrollView *> *out = [NSMutableArray array];
    LMVSettingsCollectScrollViews(window.rootViewController.view, 0, &budget, out);
    return out;
}

- (NSArray<UITableView *> *)allTablesInWindow:(UIWindow *)window {
    if (!window.rootViewController.view) return @[];
    NSInteger budget = 1200;
    NSMutableArray *out = [NSMutableArray array];
    [self collectTables:window.rootViewController.view depth:0 budget:&budget into:out];
    return out;
}

- (UITableView *)visibleTableInWindow:(UIWindow *)window {
    if (!window.rootViewController.view) return nil;
    NSInteger budget = 900; UITableView *best = nil; CGFloat bestArea = 0;
    return [self tableIn:window.rootViewController.view depth:0 budget:&budget best:&best bestArea:&bestArea window:window];
}

- (void)clearCellBackgroundsIn:(UITableView *)table {
    // 2.92: THE TABLE ITSELF PAINTS A FULL-SCREEN BACKGROUND (device log:
    // UITableView@0,0 430x932 bg1.00 d13). Clearing only cells left the list white.
    if (table.backgroundColor && CGColorGetAlpha(table.backgroundColor.CGColor) > .001) {
        if (!LMVSettingsSavedColors) LMVSettingsSavedColors = [NSMapTable weakToStrongObjectsMapTable];
        if (![LMVSettingsSavedColors objectForKey:table]) [LMVSettingsSavedColors setObject:table.backgroundColor forKey:table];
        table.backgroundColor = UIColor.clearColor;
    }
    if (table.layer.backgroundColor && CGColorGetAlpha(table.layer.backgroundColor) > .001)
        table.layer.backgroundColor = UIColor.clearColor.CGColor;
    if (table.backgroundView) table.backgroundView = nil;
    for (UITableViewCell *cell in table.visibleCells) {
        if (cell.backgroundColor && cell.backgroundColor != UIColor.clearColor) {
            if (!LMVSettingsSavedColors) LMVSettingsSavedColors = [NSMapTable weakToStrongObjectsMapTable];
            if (![LMVSettingsSavedColors objectForKey:cell]) [LMVSettingsSavedColors setObject:cell.backgroundColor forKey:cell];
            cell.backgroundColor = UIColor.clearColor;
        }
        UIView *content = cell.contentView;
        if (content.backgroundColor && content.backgroundColor != UIColor.clearColor) {
            if (!LMVSettingsSavedColors) LMVSettingsSavedColors = [NSMapTable weakToStrongObjectsMapTable];
            if (![LMVSettingsSavedColors objectForKey:content]) [LMVSettingsSavedColors setObject:content.backgroundColor forKey:content];
            content.backgroundColor = UIColor.clearColor;
        }
        for (UIView *sub in content.subviews)
            if ([sub isKindOfClass:UIVisualEffectView.class] && sub.backgroundColor && sub.backgroundColor != UIColor.clearColor)
                sub.backgroundColor = UIColor.clearColor;
    }
}

- (void)installIfNeeded {
    UIWindow *window = [self currentWindow];
    if (!window) return;
    UIView *root = window.rootViewController.view;
    if (!root) return;
    UITableView *table = [self visibleTableInWindow:window];
    (void)table;   // kept for the clearing pass below
    if (!self.host) {
        self.host = [[UIView alloc] initWithFrame:window.bounds];
        self.host.userInteractionEnabled = NO;
        self.host.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.host.backgroundColor = UIColor.clearColor;
        self.host.tag = LMVSettingsVideoHostTag;
    }
    self.window = window;
    // 2.82: the user confirmed mounting at the BOTTOM is fine - the failure was that
    // the layers above were not really cleared. Everything above the host is now
    // forced transparent (see clearSubtreeBackgrounds), so the bottom host shows.
    UIView *container = window;
    // 2.76: the host sits at (table index - 1) BECAUSE IT TAKES THE SLOT IN FRONT OF
    // THE TABLE. Comparing against the table's own index made the check fail on every
    // tick, so the view was removed and re-inserted once a second - the reported
    // "文字一闪一闪".
    NSInteger wantIndex = 0;
    NSInteger hostIndex = (NSInteger)[container.subviews indexOfObjectIdenticalTo:self.host];
    if (self.host.superview != container || hostIndex != wantIndex) {
        if (self.host.superview == container && hostIndex >= 0 && labs(hostIndex - wantIndex) != 1) {
            // A one-slot drift needs a move, not a teardown; keep the layer attached.
            [container exchangeSubviewAtIndex:(NSUInteger)hostIndex withSubviewAtIndex:(NSUInteger)wantIndex];
        } else {
            [self.host removeFromSuperview];
            [container insertSubview:self.host atIndex:(NSUInteger)wantIndex];
        }
    }
    CGRect target = window.bounds;
    if (!CGRectEqualToRect(self.host.frame, target)) self.host.frame = target;
    // The app's own container views are opaque; clear the scroll backgrounds so the
    // video is visible behind the grouped rows.
    if (root.backgroundColor && root.backgroundColor != UIColor.clearColor) {
        if (!LMVSettingsSavedColors) LMVSettingsSavedColors = [NSMapTable weakToStrongObjectsMapTable];
        if (![LMVSettingsSavedColors objectForKey:root]) [LMVSettingsSavedColors setObject:root.backgroundColor forKey:root];
        root.backgroundColor = UIColor.clearColor;
    }
    [self clearBackgroundsIn:root depth:0];
}

// 2.83: CLEARING MUST KEEP UP WITH THE UI. Settings re-applies background colours
// on layout (a new page, a re-used cell, a nav-bar refresh), so a 1 s sweep left
// opaque patches. This runs 4x a second and touches nothing else.
// 2.83: THE NAV BAR PAINTS THROUGH ITS APPEARANCE, not only through view backgrounds,
// so the top strip stayed opaque ("最上面还有些"). Clearing the appearance's colour,
// effect and shadow is what makes it transparent; the originals are kept for restore.
static NSMapTable<UINavigationBar *, NSDictionary *> *LMVSettingsSavedAppearances;

- (void)clearNavigationBarsIn:(UIView *)view depth:(NSInteger)depth {
    if (!view || depth > 14) return;
    if ([view isKindOfClass:UINavigationBar.class]) {
        UINavigationBar *bar = (UINavigationBar *)view;
        if (!LMVSettingsSavedAppearances) LMVSettingsSavedAppearances = [NSMapTable weakToStrongObjectsMapTable];
        if (![LMVSettingsSavedAppearances objectForKey:bar]) {
            NSMutableDictionary *saved = [NSMutableDictionary dictionary];
            if (bar.standardAppearance) saved[@"standard"] = bar.standardAppearance;
            if (bar.scrollEdgeAppearance) saved[@"scroll"] = bar.scrollEdgeAppearance;
            if (bar.compactAppearance) saved[@"compact"] = bar.compactAppearance;
            [LMVSettingsSavedAppearances setObject:saved forKey:bar];
        }
        UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
        [appearance configureWithTransparentBackground];
        appearance.backgroundColor = UIColor.clearColor;
        appearance.backgroundEffect = nil;
        appearance.shadowColor = UIColor.clearColor;
        bar.standardAppearance = appearance;
        bar.scrollEdgeAppearance = appearance;
        bar.compactAppearance = appearance;
        bar.translucent = YES;
    }
    for (UIView *child in view.subviews) [self clearNavigationBarsIn:child depth:depth + 1];
}

- (void)restoreNavigationBarAppearances {
    for (UINavigationBar *bar in LMVSettingsSavedAppearances) {
        NSDictionary *saved = [LMVSettingsSavedAppearances objectForKey:bar];
        if (!bar || !saved) continue;
        if (saved[@"standard"]) bar.standardAppearance = saved[@"standard"];
        if (saved[@"scroll"]) bar.scrollEdgeAppearance = saved[@"scroll"];
        if (saved[@"compact"]) bar.compactAppearance = saved[@"compact"];
    }
    [LMVSettingsSavedAppearances removeAllObjects];
}

- (NSArray<UIWindow *> *)allWindows {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *candidate in ((UIWindowScene *)scene).windows) {
            if (candidate.hidden || candidate.alpha < .01) continue;
            [windows addObject:candidate];
        }
    }
    return windows;
}

// 2.93: FORCE THE TWO LOGGED OFFENDERS EVERY FRAME. The app re-applies them between
// our sweeps (the log still shows UITableView bg1.00 after 2.92 cleared it). A display
// link runs right before each frame is composited, so there is no gap left.
- (void)frameSweep {
    UIWindow *window = self.window;
    if (!window) return;
    NSMutableArray<UIScrollView *> *scrolls = [NSMutableArray array];
    NSInteger budget = 1500;
    LMVSettingsCollectScrollViews(window.rootViewController.view, 0, &budget, scrolls);
    for (UIScrollView *scroll in scrolls) {
        // 2.93: transparent is not enough - the app re-paints it. Kill the layer's
        // paint entirely: no background colour on the view OR its layer, and the
        // dedicated background view is removed from the hierarchy.
        if (scroll.backgroundColor && CGColorGetAlpha(scroll.backgroundColor.CGColor) > .001)
            scroll.backgroundColor = UIColor.clearColor;
        if (scroll.layer.backgroundColor && CGColorGetAlpha(scroll.layer.backgroundColor) > .001)
            scroll.layer.backgroundColor = UIColor.clearColor.CGColor;
        if ([scroll isKindOfClass:UITableView.class]) {
            UITableView *t = (UITableView *)scroll;
            if (t.backgroundView && !t.backgroundView.hidden) {
                if (!LMVSettingsHiddenViews) LMVSettingsHiddenViews = [NSHashTable weakObjectsHashTable];
                [LMVSettingsHiddenViews addObject:t.backgroundView];
                t.backgroundView.hidden = YES;
            }
        }
        UIView *container = scroll.superview;
        if ((scroll.bounds.size.width >= window.bounds.size.width - 1) &&
            (scroll.bounds.size.height >= window.bounds.size.height * .5)) {
            if (container.backgroundColor && CGColorGetAlpha(container.backgroundColor.CGColor) > .001)
                container.backgroundColor = UIColor.clearColor;
            if (container.layer.backgroundColor && CGColorGetAlpha(container.layer.backgroundColor) > .001)
                container.layer.backgroundColor = UIColor.clearColor.CGColor;
        }
    }
}

- (void)logOccluders:(NSString *)reason {
    UIWindow *window = self.window;
    if (!window || !self.host) return;
    CGRect hostFrame = [self.host convertRect:self.host.bounds toView:window];
    NSInteger budget = 2600;
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    for (UIWindow *candidate in [self allWindows])
        LMVSettingsCollectOccluders(candidate, self.host, hostFrame, 0, &budget, found);
    LMVSettingsVideoLog([NSString stringWithFormat:@"white-frame reason=%@ count=%lu hosts=%.0fx%.0f %@",
        reason, (unsigned long)found.count, hostFrame.size.width, hostFrame.size.height,
        found.count ? [found componentsJoinedByString:@" | "] : @"none"]);
}

- (void)clearVisibleBackgrounds {
    UIWindow *window = self.window;
    // 2.84: sheets (our colour picker, the material picker) live in their own window
    // or in another scene's window; clearing only one window left them opaque.
    // 2.89: OTHER TWEAKS' SHEETS. A third-party picker often adds its views straight
    // to the WINDOW (or presents in its own window with no root controller), so
    // walking rootViewController.view missed them. Walk the window itself.
    for (UIWindow *candidate in [self allWindows]) {
        NSInteger budget = 3000;
        [self clearNavigationBarsIn:candidate depth:0];
        [self clearSubtreeBackgrounds:candidate depth:0 budget:&budget];
    }
    if (!window.rootViewController.view) return;
    NSInteger budget = 2000;
    [self clearSubtreeBackgrounds:window.rootViewController.view depth:0 budget:&budget];
    [self clearNavigationBarsIn:window.rootViewController.view depth:0];
    for (UITableView *table in [self allTablesInWindow:window]) [self clearCellBackgroundsIn:table];
    for (UIScrollView *scroll in [self allScrollViewsInWindow:window]) {
        if ([scroll isKindOfClass:UICollectionView.class]) {
            UICollectionView *collection = (UICollectionView *)scroll;
            if (collection.backgroundView) collection.backgroundView = nil;
            if (collection.backgroundColor && CGColorGetAlpha(collection.backgroundColor.CGColor) > .001)
                collection.backgroundColor = UIColor.clearColor;
        }
    }
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
    // 2.77: iOS pauses an AVPlayer when the app goes to the background; coming back
    // the player existed so nothing rebuilt it and the video stayed frozen
    // ("退出 app 再进去视频就暂停了"). Resume whenever we are the active channel.
    if (self.player.timeControlStatus != AVPlayerTimeControlStatusPlaying) [self.player play];
    UIWindow *window = self.window;
    // 2.78: the host lives in the WINDOW (both split-view columns see it); only the
    // tables are re-cleared here, never the host's container.
    UITableView *liveTable = window ? [self visibleTableInWindow:window] : nil;
    if (window && (!self.host.superview || self.host.superview == window ||
                   (liveTable && self.host.superview != liveTable.superview)))
        [self installIfNeeded];
    [self clearNavigationBarsIn:window.rootViewController.view depth:0];
    for (UITableView *table in [self allTablesInWindow:window]) [self clearCellBackgroundsIn:table];
    if (window.rootViewController.view) {
        NSInteger clearBudget = 2500;
        [self clearSubtreeBackgrounds:window.rootViewController.view depth:0 budget:&clearBudget];
    }
    // 2.79: collection-view pages (some Settings pages use them) get the same treatment.
    NSMutableArray<UIScrollView *> *scrolls = [NSMutableArray array];
    NSInteger scrollBudget = 1200;
    if (window) LMVSettingsCollectScrollViews(window.rootViewController.view, 0, &scrollBudget, scrolls);
    for (UIScrollView *scroll in scrolls) {
        if ([scroll isKindOfClass:UICollectionView.class]) {
            UICollectionView *collection = (UICollectionView *)scroll;
            if (collection.backgroundView) collection.backgroundView = nil;
            if (collection.backgroundColor && CGColorGetAlpha(collection.backgroundColor.CGColor) > .001)
                collection.backgroundColor = UIColor.clearColor;
        } else if (scroll.backgroundColor && CGColorGetAlpha(scroll.backgroundColor.CGColor) > .001) {
            scroll.backgroundColor = UIColor.clearColor;
        }
    }
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
            (unsigned long)[LMVSettingsSavedColors count],
            (unsigned long)window.subviews.count]);
        NSMutableString *tree = [NSMutableString string];
        NSUInteger budget = 400;
        LMVSettingsVideoDump(window, 0, tree, &budget);
        LMVSettingsVideoLog([NSString stringWithFormat:@"settings-video-tree\n%@", tree]);
    }
}

- (void)stop {
    [self.frameLink invalidate]; self.frameLink = nil;
    [self.player pause];
    [self.looper disableLooping];
    self.player = nil; self.looper = nil; self.path = nil;
    for (CALayer *layer in [self.host.layer.sublayers copy])
        if ([layer isKindOfClass:AVPlayerLayer.class]) [layer removeFromSuperlayer];
    [self.host removeFromSuperview];
    [self restoreBackgrounds];
    [self restoreNavigationBarAppearances];
}

@end