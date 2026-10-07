#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <notify.h>
static int DBlankToken = -1;

static NSString *const DLog = @"/var/mobile/LockMessageVideo/media-live-tree.log";
static NSString *const DPrefs = @"/var/mobile/Library/Preferences/com.minis.lockmessagevideo.diagnostic.plist";
static const NSUInteger DLimit = 1024 * 1024;
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
    // CoverSheet/Notification/Widget are discovery anchors, not dump roots.
    return DContains(NSStringFromClass(v.class), @[@"NowPlaying", @"Media", @"MRU", @"Activity", @"LiveActivity", @"CHUIS", @"SBMedia"]);
}
static BOOL DAnchor(UIView *v) {
    return DContains(NSStringFromClass(v.class), @[@"CoverSheet", @"Notification", @"Widget"]);
}
static BOOL DVisible(UIView *v) {
    if (!v.window || v.window.hidden) return NO;
    for (UIView *p = v; p; p = p.superview) if (p.hidden || p.alpha <= 0.01) return NO;
    CGRect r = [v convertRect:v.bounds toView:v.window];
    return !CGRectIsEmpty(r) && CGRectIntersectsRect(r, v.window.bounds);
}
static NSString *DLine(UIView *v, NSUInteger depth) {
    return [NSString stringWithFormat:@"%@%@ frame=%@ hidden=%d alpha=%.3f\n",
        [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0],
        NSStringFromClass(v.class), NSStringFromCGRect(v.frame), v.hidden, (double)v.alpha];
}
static void DDump(UIView *v, NSUInteger depth, NSUInteger *nodes, NSMutableString *out) {
    if (*nodes >= 500 || out.length > 100000) return;
    (*nodes)++;
    [out appendString:DLine(v, depth)];
    if (depth >= 18) {
        if (v.subviews.count) [out appendString:@"  [depth limit]\n"];
        return;
    }
    for (UIView *child in v.subviews) DDump(child, depth + 1, nodes, out);
}
static void DFind(UIView *v, NSUInteger depth, NSUInteger *visited, NSMutableArray<UIView *> *roots) {
    if (depth > 24 || *visited >= 3000 || roots.count >= 12 || v.hidden || v.alpha <= 0.01) return;
    (*visited)++;
    if (DRelevant(v) && DVisible(v)) { [roots addObject:v]; return; }
    for (UIView *child in v.subviews) DFind(child, depth + 1, visited, roots);
}
static BOOL DFindAnchor(UIView *v, NSUInteger depth, NSUInteger *visited) {
    if (depth > 18 || *visited >= 1500 || v.hidden || v.alpha <= 0.01) return NO;
    (*visited)++;
    if (DAnchor(v) && DVisible(v)) return YES;
    for (UIView *child in v.subviews) if (DFindAnchor(child, depth + 1, visited)) return YES;
    return NO;
}
static NSArray<UIWindow *> *DWindows(void) {
    NSMutableOrderedSet *windows = [NSMutableOrderedSet orderedSet];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *w in ((UIWindowScene *)scene).windows) [windows addObject:w];
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *w in UIApplication.sharedApplication.windows) [windows addObject:w];
#pragma clang diagnostic pop
    return windows.array;
}
static BOOL DActive(NSArray<UIWindow *> *windows) {
    uint64_t blank = 0;
    if (DBlankToken >= 0 && notify_get_state(DBlankToken, &blank) == NOTIFY_STATUS_OK && blank) return NO;
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateBackground) return NO;
    if (DCover.isViewLoaded && DVisible(DCover.view)) return YES;
    for (UIWindow *w in windows) {
        if (w.hidden || w.alpha <= 0.01) continue;
        NSUInteger visited = 0;
        if (DFindAnchor(w, 0, &visited)) return YES;
    }
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
                // One bounded file: a new generation replaces the previous one.
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
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:DPrefs];
    DEnabled = prefs[@"Enabled"] ? [prefs[@"Enabled"] boolValue] : YES;
    if (!DEnabled) return;
    NSArray *windows = DWindows();
    if (!DActive(windows)) return;
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (now - DLastScan < 1.0) return;
    DLastScan = now;
    NSMutableString *body = [NSMutableString string];
    NSUInteger total = 0, windowCount = 0;
    for (UIWindow *w in windows) {
        if (w.hidden || w.alpha <= 0.01 || windowCount >= 16) continue;
        windowCount++;
        NSMutableArray *roots = [NSMutableArray array];
        NSUInteger visited = 0;
        DFind(w, 0, &visited, roots);
        if (!roots.count) continue;
        [body appendFormat:@"WINDOW %@ frame=%@ hidden=%d alpha=%.3f level=%.3f\n", NSStringFromClass(w.class), NSStringFromCGRect(w.frame), w.hidden, (double)w.alpha, (double)w.windowLevel];
        for (UIView *root in roots) {
            [body appendString:@"ROOT ancestry: "];
            UIView *parent = root.superview;
            for (NSUInteger i = 0; parent && i < 18; i++, parent = parent.superview)
                [body appendFormat:@"%@ > ", NSStringFromClass(parent.class)];
            [body appendString:@"\n"];
            DDump(root, 0, &total, body);
            if (total >= 500 || body.length > 100000) break;
        }
        if (total >= 500 || body.length > 100000) break;
    }
    if (!body.length) [body appendString:@"No visible matching media/live activity subtree (or remote content not exposed).\n"];
    if (total >= 500 || body.length > 100000) [body appendString:@"[snapshot node/size limit]\n"];
    // FNV-1a over geometry/class state, independent of reason/time.
    NSData *bytes = [body dataUsingEncoding:NSUTF8StringEncoding];
    uint64_t hash = 14695981039346656037ULL;
    const unsigned char *p = (const unsigned char *)bytes.bytes;
    for (NSUInteger i = 0; i < bytes.length; i++) { hash ^= p[i]; hash *= 1099511628211ULL; }
    if (hash == DLastHash && now - DLastWrite < 60.0) return;
    DLastHash = hash; DLastWrite = now;
    DAppend([NSString stringWithFormat:@"\n=== %@ diagnostic=0.0.1 reason=%@ nodes=%lu ===\n%@", NSDate.date, DReason ?: @"periodic", (unsigned long)total, body]);
}
static void DSchedule(NSString *reason) {
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
- (void)viewDidAppear:(BOOL)animated { %orig; DCover = (UIViewController *)self; DSchedule(@"cover appeared"); }
- (void)viewDidLayoutSubviews { %orig; DCover = (UIViewController *)self; DSchedule(@"cover layout"); }
%end
%end
%group NotificationHooks
%hook NCNotificationListView
- (void)layoutSubviews { %orig; DSchedule(@"notification layout"); }
%end
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        notify_register_check("com.apple.springboard.hasBlankedScreen", &DBlankToken);
        DWriter = dispatch_queue_create("com.minis.lockmessagevideo.diagnostic.writer", DISPATCH_QUEUE_SERIAL);
        Class cover = NSClassFromString(@"CSCoverSheetViewController");
        Class list = NSClassFromString(@"NCNotificationListView");
        if (cover) { %init(CoverHooks, CSCoverSheetViewController = cover); }
        if (list) { %init(NotificationHooks, NCNotificationListView = list); }
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer *timer) {
                (void)timer;
                DSchedule(@"periodic");
            }];
            DSchedule(@"loaded");
        });
    }
}
