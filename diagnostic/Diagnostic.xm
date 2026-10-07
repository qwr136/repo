#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>
static int DBlankToken = -1;

static NSString *const DLog = @"/var/mobile/LockMessageVideo/media-live-tree.log";
static NSString *const DPrefs = @"/var/mobile/Library/Preferences/com.minis.lockmessagevideo.diagnostic.plist";
static const NSUInteger DLimit = 1024 * 1024;
static const NSUInteger DMaxNodes = 6000;
static const NSUInteger DMaxDepth = 32;
static const NSUInteger DMaxText = 1024 * 1024;
static NSUInteger DDepthCut, DNodeCut, DSizeCut, DFindCut, DWindowCut;
static dispatch_queue_t DWriter;
static __weak UIViewController *DCover;
static BOOL DEnabled = YES, DPending = NO;
static NSTimeInterval DLastScan = 0, DLastWrite = 0;
static uint64_t DLastHash = 0;
static NSString *DReason;

static BOOL DContains(NSString *name, NSArray<NSString *> *tokens) {
    for (NSString *token in tokens)
        if ([name rangeOfString:token options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    return NO;
}
static BOOL DRelevant(UIView *v) {
    // Non-cover windows use these selective roots; cover windows bypass matching.
    return DContains(NSStringFromClass(v.class), @[@"NowPlaying", @"Media", @"MRU", @"Activity", @"LiveActivity", @"CHUIS", @"SBMedia"]);
}

static BOOL DVisible(UIView *v) {
    if (!v.window || v.window.hidden) return NO;
    for (UIView *p = v; p; p = p.superview) if (p.hidden || p.alpha <= 0.01) return NO;
    CGRect r = [v convertRect:v.bounds toView:v.window];
    return !CGRectIsEmpty(r) && CGRectIntersectsRect(r, v.window.bounds);
}
static NSString *DLine(UIView *v, NSUInteger depth) {
    NSMutableArray *controllers = [NSMutableArray array];
    UIResponder *r = v.nextResponder;
    for (NSUInteger i = 0; r && i < 64; i++, r = r.nextResponder)
        if ([r isKindOfClass:UIViewController.class]) [controllers addObject:NSStringFromClass(r.class)];
    CGRect screenFrame = v.window ? [v convertRect:v.bounds toView:v.window] : v.frame;
    return [NSString stringWithFormat:@"%@%@ frame=%@ windowFrame=%@ hidden=%d alpha=%.3f masks=%d visible=%d parent=%@ controllers=%@\n",
        [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
        NSStringFromClass(v.class), NSStringFromCGRect(v.frame), NSStringFromCGRect(screenFrame),
        v.hidden, (double)v.alpha, v.layer.masksToBounds, DVisible(v),
        v.superview ? NSStringFromClass(v.superview.class) : @"none", [controllers componentsJoinedByString:@">"]];
}
static void DDump(UIView *v, NSUInteger depth, NSUInteger *nodes, NSMutableString *out) {
    if (*nodes >= DMaxNodes) { DNodeCut++; return; }
    NSString *line = DLine(v, depth);
    if (out.length + line.length >= DMaxText - 4096) { DSizeCut++; return; }
    (*nodes)++;
    [out appendString:line];
    if (depth >= DMaxDepth) {
        if (v.subviews.count) DDepthCut++;
        return;
    }
    // Do not prune hidden/alpha-zero parents: SpringBoard can animate the media branch.
    for (UIView *child in v.subviews) {
        if (*nodes >= DMaxNodes || DSizeCut) {
            DNodeCut += *nodes >= DMaxNodes;
            break;
        }
        DDump(child, depth + 1, nodes, out);
    }
}
static void DFind(UIView *v, NSUInteger depth, NSUInteger *visited, NSMutableArray<UIView *> *roots) {
    if (depth > DMaxDepth || *visited >= DMaxNodes || roots.count >= 24) { DFindCut++; return; }
    (*visited)++;
    if (DRelevant(v) && DVisible(v)) { [roots addObject:v]; return; }
    for (UIView *child in v.subviews) {
        if (*visited >= DMaxNodes || roots.count >= 24) { DFindCut++; break; }
        DFind(child, depth + 1, visited, roots);
    }
}

static NSHashTable<UIWindow *> *DObserved;
static NSMapTable<UIWindow *, NSString *> *DSources;
static void DObserve(UIView *view) {
    if (!NSThread.isMainThread) return;
    UIWindow *window = [view isKindOfClass:UIWindow.class] ? (UIWindow *)view : view.window;
    if (window) [DObserved addObject:window];
}
static void DAddWindow(NSMutableOrderedSet *windows, UIWindow *w, NSString *source) {
    if (!w) return;
    [windows addObject:w];
    NSString *previous = [DSources objectForKey:w];
    [DSources setObject:previous ? [previous stringByAppendingFormat:@"+%@", source] : source forKey:w];
}
static BOOL DCoverWindow(UIWindow *w) {
    Class cls = NSClassFromString(@"SBCoverSheetWindow");
    return (cls && [w isKindOfClass:cls]) || (DCover.isViewLoaded && DCover.view.window == w);
}
static NSArray<UIWindow *> *DWindows(void) {
    [DSources removeAllObjects];
    NSMutableOrderedSet *windows = [NSMutableOrderedSet orderedSet];
    for (UIWindow *w in DObserved.allObjects) DAddWindow(windows, w, @"hook");
    if (DCover.isViewLoaded) DAddWindow(windows, DCover.view.window, @"cover-controller");
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *w in ((UIWindowScene *)scene).windows) DAddWindow(windows, w, @"scene");
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in UIApplication.sharedApplication.windows) DAddWindow(windows, w, @"application");
#pragma clang diagnostic pop
    return [windows.array sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        NSInteger pa = DCoverWindow(a) ? 0 : (DContains(NSStringFromClass(a.class), @[@"HomeScreen"]) ? 2 : 1);
        NSInteger pb = DCoverWindow(b) ? 0 : (DContains(NSStringFromClass(b.class), @[@"HomeScreen"]) ? 2 : 1);
        if (pa != pb) return pa < pb ? NSOrderedAscending : NSOrderedDescending;
        return [NSStringFromClass(a.class) compare:NSStringFromClass(b.class)];
    }];
}
static BOOL DActive(NSArray<UIWindow *> *windows) {
    uint64_t blank = 0;
    if (DBlankToken >= 0 && notify_get_state(DBlankToken, &blank) == NOTIFY_STATUS_OK && blank) return NO;
    if (DCover.isViewLoaded && DVisible(DCover.view)) return YES;
    for (UIWindow *w in windows)
        if (DCoverWindow(w) && !w.hidden && w.alpha > 0.01 && !CGRectIsEmpty(w.bounds)) return YES;
    return NO;
}
static void DAppend(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    dispatch_async(DWriter, ^{
        @autoreleasepool {
            NSFileManager *fm = NSFileManager.defaultManager;
            [fm createDirectoryAtPath:DLog.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
            unsigned long long size = [[fm attributesOfItemAtPath:DLog error:nil][NSFileSize] unsignedLongLongValue];
            if (size + data.length > DLimit) {
                NSString *previous = [DLog stringByAppendingString:@".1"];
                [fm removeItemAtPath:previous error:nil];
                [fm moveItemAtPath:DLog toPath:previous error:nil];
                [data writeToFile:DLog options:NSDataWritingAtomic error:nil];
            } else {
                if (![fm fileExistsAtPath:DLog]) [fm createFileAtPath:DLog contents:nil attributes:nil];
                NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:DLog];
                @try { [handle seekToEndOfFile]; [handle writeData:data]; }
                @catch (NSException *e) { (void)e; }
                @finally { [handle closeFile]; }
            }
            [fm setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:DLog error:nil];
        }
    });
}
static void DScan(void) {
    if (!NSThread.isMainThread) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - DLastScan < 3.0) return;
    DLastScan = now;
    DDepthCut = DNodeCut = DSizeCut = DFindCut = DWindowCut = 0;
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:DPrefs];
    DEnabled = prefs[@"Enabled"] ? [prefs[@"Enabled"] boolValue] : YES;
    if (!DEnabled) return;
    NSArray *windows = DWindows();
    if (!DActive(windows)) return;
    NSMutableString *body = [NSMutableString string];
    NSUInteger total = 0, windowCount = 0;
    for (NSString *name in @[@"MRUNowPlayingView", @"MRUNowPlayingViewController", @"MediaControlsView", @"MediaControlsViewController"]) {
        [body appendFormat:@"RUNTIME class=%@ exists=%d (existence only, not observed)\n", name, NSClassFromString(name) != Nil];
    }
    [body appendFormat:@"ENUM windows=%lu maxDepth=%lu maxNodes=%lu maxText=%lu\n", (unsigned long)windows.count, (unsigned long)DMaxDepth, (unsigned long)DMaxNodes, (unsigned long)DMaxText];
    for (UIWindow *w in windows) {
        [body appendFormat:@"ENUM WINDOW %@ source=%@ frame=%@ hidden=%d alpha=%.3f level=%.3f cover=%d\n", NSStringFromClass(w.class), [DSources objectForKey:w], NSStringFromCGRect(w.frame), w.hidden, (double)w.alpha, (double)w.windowLevel, DCoverWindow(w)];
    }
    for (UIWindow *w in windows) {
        if (w.hidden || w.alpha <= 0.01) continue;
        if (windowCount >= 16) { DWindowCut++; continue; }
        windowCount++;
        NSMutableArray *roots = [NSMutableArray array];
        NSUInteger visited = 0;
        if (DCoverWindow(w)) {
            [roots addObject:w];
        } else {
            // Other windows: only media/live roots, never dump every window by default.
            DFind(w, 0, &visited, roots);
        }
        [body appendFormat:@"DISCOVERY %@ visited=%lu roots=%lu\n", NSStringFromClass(w.class), (unsigned long)visited, (unsigned long)roots.count];
        if (!roots.count) continue;
        [body appendFormat:@"WINDOW %@ frame=%@ hidden=%d alpha=%.3f level=%.3f\n", NSStringFromClass(w.class), NSStringFromCGRect(w.frame), w.hidden, (double)w.alpha, (double)w.windowLevel];
        for (UIView *root in roots) {
            [body appendString:@"ROOT ancestry: "];
            UIView *parent = root.superview;
            for (NSUInteger i = 0; parent && i < 64; i++, parent = parent.superview)
                [body appendFormat:@"%@ > ", NSStringFromClass(parent.class)];
            [body appendString:@"\n"];
            DDump(root, 0, &total, body);
            if (total >= DMaxNodes || DSizeCut) break;
        }
        if (total >= DMaxNodes || DSizeCut) {
            DNodeCut |= total >= DMaxNodes;
            DSizeCut |= body.length >= DMaxText;
            DWindowCut += windows.count - windowCount;
            break;
        }
    }
    if (!total) [body appendString:@"No captured subtree (or remote content not exposed).\n"];
    [body appendFormat:@"COVERAGE nodes=%lu depthCapBranches=%lu nodeCap=%lu sizeCap=%lu discoveryCap=%lu windowsOmitted=%lu hiddenParentPrunes=0\n", (unsigned long)total, (unsigned long)DDepthCut, (unsigned long)DNodeCut, (unsigned long)DSizeCut, (unsigned long)DFindCut, (unsigned long)DWindowCut];
    // FNV-1a over geometry/class state, independent of reason/time.
    NSData *bytes = [body dataUsingEncoding:NSUTF8StringEncoding];
    uint64_t hash = 14695981039346656037ULL;
    const unsigned char *p = (const unsigned char *)bytes.bytes;
    for (NSUInteger i = 0; i < bytes.length; i++) { hash ^= p[i]; hash *= 1099511628211ULL; }
    if (hash == DLastHash && now - DLastWrite < 60.0) return;
    DLastHash = hash; DLastWrite = now;
    DAppend([NSString stringWithFormat:@"\n=== %@ diagnostic=0.0.3 reason=%@ nodes=%lu ===\n%@", NSDate.date, DReason ?: @"periodic", (unsigned long)total, body]);
}
static void DSchedule(NSString *reason) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ DSchedule(reason); });
        return;
    }
    DReason = reason;
    if (DPending) return;
    DPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        DPending = NO;
        DScan();
    });
}

%group CoverHooks
%hook CSCoverSheetViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    DCover = (UIViewController *)self;
    DObserve(DCover.view);
    DSchedule(@"cover appeared");
}
- (void)viewDidLayoutSubviews {
    %orig;
    DCover = (UIViewController *)self;
    DObserve(DCover.view);
    DSchedule(@"cover layout");
}
%end
%end
%group NotificationHooks
%hook NCNotificationListView
- (void)layoutSubviews {
    %orig;
    DObserve((UIView *)self);
    DSchedule(@"notification layout");
}
%end
%end

%group CoverWindowHooks
%hook SBCoverSheetWindow
- (void)layoutSubviews {
    %orig;
    DObserve((UIView *)self);
    DSchedule(@"cover window layout");
}
%end
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        notify_register_check("com.apple.springboard.hasBlankedScreen", &DBlankToken);
        DWriter = dispatch_queue_create("com.minis.lockmessagevideo.diagnostic.writer", DISPATCH_QUEUE_SERIAL);
        DObserved = [NSHashTable weakObjectsHashTable];
        DSources = [NSMapTable weakToStrongObjectsMapTable];
        Class coverWindow = NSClassFromString(@"SBCoverSheetWindow");
        if (coverWindow) {
            %init(CoverWindowHooks, SBCoverSheetWindow = coverWindow);
        }
        Class cover = NSClassFromString(@"CSCoverSheetViewController");
        Class list = NSClassFromString(@"NCNotificationListView");
        if (cover) {
            %init(CoverHooks, CSCoverSheetViewController = cover);
        }
        if (list) {
            %init(NotificationHooks, NCNotificationListView = list);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *timer) {
                (void)timer;
                DSchedule(@"periodic");
            }];
            DSchedule(@"loaded");
        });
    }
}
