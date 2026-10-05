#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <net/if_dl.h>

static NSString * const kNSPrefsRootful  = @"/var/mobile/Library/Preferences/cn.qwr136.netspeed.plist";
static NSString * const kNSPrefsRootless = @"/var/jb/var/mobile/Library/Preferences/cn.qwr136.netspeed.plist";

static NSString *NSPrefsPath(void) {
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:kNSPrefsRootful]) return kNSPrefsRootful;
    if ([fm fileExistsAtPath:kNSPrefsRootless]) return kNSPrefsRootless;
    return kNSPrefsRootful;
}

static NSDictionary *NSLoadPrefs(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:NSPrefsPath()];
    if (!d) d = [NSDictionary dictionaryWithContentsOfFile:kNSPrefsRootless];
    if (!d) d = [NSDictionary dictionaryWithContentsOfFile:kNSPrefsRootful];
    return d ?: @{};
}

static BOOL NSPrefBool(NSDictionary *p, NSString *k, BOOL def) {
    id v = p[k];
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : def;
}

static double NSPrefDouble(NSDictionary *p, NSString *k, double def) {
    id v = p[k];
    return [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : def;
}

static void NSSavePosition(CGFloat x, CGFloat y) {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:NSPrefsPath()];
    if (!d) d = [NSMutableDictionary dictionary];
    d[@"posX"] = @(x);
    d[@"posY"] = @(y);
    [d writeToFile:NSPrefsPath() atomically:YES];
}

static BOOL NSReadNetTotals(uint64_t *outIn, uint64_t *outOut) {
    static NSMutableDictionary *prevIn;
    static NSMutableDictionary *prevOut;
    static uint64_t totalIn = 0;
    static uint64_t totalOut = 0;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prevIn = [NSMutableDictionary dictionary];
        prevOut = [NSMutableDictionary dictionary];
    });

    struct ifaddrs *ifaddr = NULL;
    if (getifaddrs(&ifaddr) != 0 || !ifaddr) return NO;

    for (struct ifaddrs *ifa = ifaddr; ifa; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_LINK) continue;
        if (ifa->ifa_flags & IFF_LOOPBACK) continue;
        struct if_data *d = (struct if_data *)ifa->ifa_data;
        if (!d) continue;

        NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
        if (!name) continue;

        uint32_t curIn = d->ifi_ibytes;
        uint32_t curOut = d->ifi_obytes;
        uint32_t preIn = [prevIn[name] unsignedIntValue];
        uint32_t preOut = [prevOut[name] unsignedIntValue];

        totalIn  += (uint32_t)(curIn - preIn);
        totalOut += (uint32_t)(curOut - preOut);

        prevIn[name] = @(curIn);
        prevOut[name] = @(curOut);
    }

    freeifaddrs(ifaddr);
    *outIn = totalIn;
    *outOut = totalOut;
    return YES;
}

static NSString *NSFormatSpeed(double bps) {
    if (!isfinite(bps) || bps < 0) bps = 0;
    if (bps < 1024.0) return [NSString stringWithFormat:@"%.0f B/s", bps];
    if (bps < 1024.0 * 1024.0) return [NSString stringWithFormat:@"%.1f KB/s", bps / 1024.0];
    if (bps < 1024.0 * 1024.0 * 1024.0) return [NSString stringWithFormat:@"%.2f MB/s", bps / (1024.0 * 1024.0)];
    return [NSString stringWithFormat:@"%.2f GB/s", bps / (1024.0 * 1024.0 * 1024.0)];
}

static UIWindowScene *NSActiveScene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *s in app.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]] &&
            s.activationState == UISceneActivationStateForegroundActive) {
            return (UIWindowScene *)s;
        }
    }
    for (UIScene *s in app.connectedScenes) {
        if ([s isKindOfClass:[UIWindowScene class]]) return (UIWindowScene *)s;
    }
    return nil;
}

@interface NSNetSpeedManager : NSObject
@property (nonatomic, strong) UIWindow *window;
@property (nonatomic, strong) UIView *container;
@property (nonatomic, strong) UILabel *label;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) uint64_t lastIn;
@property (nonatomic, assign) uint64_t lastOut;
@property (nonatomic, assign) NSTimeInterval lastTime;
@property (nonatomic, assign) BOOL hasLast;
+ (instancetype)shared;
- (void)start;
- (void)resetPosition;
@end

static void NSPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                   const void *object, CFDictionaryRef userInfo);

@implementation NSNetSpeedManager

+ (instancetype)shared {
    static NSNetSpeedManager *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [NSNetSpeedManager new]; });
    return s;
}

- (void)start {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sceneChanged:)
                                                 name:UISceneDidActivateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(sceneChanged:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    (__bridge const void *)self,
                                    NSPrefsChangedCallback,
                                    CFSTR("cn.qwr136.netspeed/relayout"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    [self buildWindowIfNeeded];
    if (!self.timer) {
        self.timer = [NSTimer timerWithTimeInterval:1.0 target:self selector:@selector(tick) userInfo:nil repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
}

static void NSPrefsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                   const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNetSpeedManager shared] resetPosition];
    });
}

- (void)sceneChanged:(NSNotification *)n {
    dispatch_async(dispatch_get_main_queue(), ^{ [self buildWindowIfNeeded]; });
}

- (void)buildWindowIfNeeded {
    UIWindowScene *scene = NSActiveScene();
    if (!scene) return;
    if (self.window && self.window.windowScene == scene) {
        self.window.hidden = NO;
        return;
    }
    if (self.window) {
        self.window.hidden = YES;
        self.window = nil;
        self.container = nil;
        self.label = nil;
    }

    UIWindow *w = [[UIWindow alloc] initWithWindowScene:scene];
    w.windowLevel = UIWindowLevelAlert + 1;
    w.backgroundColor = [UIColor clearColor];
    w.frame = CGRectMake(0, 0, 220, 30);

    UIView *c = [[UIView alloc] initWithFrame:w.bounds];
    c.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
    c.layer.cornerRadius = 8;
    c.clipsToBounds = YES;
    c.userInteractionEnabled = YES;

    UILabel *l = [[UILabel alloc] initWithFrame:c.bounds];
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = [UIColor whiteColor];
    l.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightSemibold];
    l.adjustsFontSizeToFitWidth = YES;
    l.minimumScaleFactor = 0.6;
    l.text = @"↓ --   ↑ --";
    [c addSubview:l];

    w.rootViewController = [UIViewController new];
    w.rootViewController.view.backgroundColor = [UIColor clearColor];
    w.rootViewController.view.frame = w.bounds;
    [w.rootViewController.view addSubview:c];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [c addGestureRecognizer:pan];
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    tap.numberOfTapsRequired = 2;
    [c addGestureRecognizer:tap];

    self.window = w;
    self.container = c;
    self.label = l;

    [self applySavedPosition];
    w.hidden = NO;
}

- (void)defaultPosition {
    UIWindowScene *scene = self.window.windowScene;
    if (!scene) return;
    CGRect b = scene.coordinateSpace.bounds;
    self.window.center = CGPointMake(b.size.width / 2.0, 64.0);
}

- (void)applySavedPosition {
    NSDictionary *p = NSLoadPrefs();
    id px = p[@"posX"];
    id py = p[@"posY"];
    if ([px respondsToSelector:@selector(doubleValue)] && [py respondsToSelector:@selector(doubleValue)]) {
        self.window.center = CGPointMake([px doubleValue], [py doubleValue]);
    } else {
        [self defaultPosition];
    }
}

- (void)resetPosition {
    [self defaultPosition];
    NSSavePosition(self.window.center.x, self.window.center.y);
}

- (void)handlePan:(UIPanGestureRecognizer *)g {
    if (!self.window) return;
    CGPoint t = [g translationInView:self.window];
    CGPoint c = self.window.center;
    c.x += t.x;
    c.y += t.y;
    UIWindowScene *scene = self.window.windowScene;
    if (scene) {
        CGRect b = scene.coordinateSpace.bounds;
        CGFloat hw = self.window.bounds.size.width / 2.0;
        CGFloat hh = self.window.bounds.size.height / 2.0;
        c.x = MAX(hw, MIN(b.size.width - hw, c.x));
        c.y = MAX(hh + 20.0, MIN(b.size.height - hh, c.y));
    }
    self.window.center = c;
    [g setTranslation:CGPointZero inView:self.window];
    if (g.state == UIGestureRecognizerStateEnded || g.state == UIGestureRecognizerStateCancelled) {
        NSSavePosition(c.x, c.y);
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)g {
    [self resetPosition];
}

- (void)resizeToFit {
    if (!self.window) return;
    CGSize s = [self.label sizeThatFits:CGSizeMake(360, 60)];
    CGFloat w = ceil(s.width) + 22.0;
    CGFloat h = ceil(s.height) + 8.0;
    CGPoint center = self.window.center;
    CGRect f = self.window.frame;
    f.size = CGSizeMake(w, h);
    self.window.frame = f;
    self.container.frame = self.window.bounds;
    self.label.frame = self.container.bounds;
    self.window.center = center;
}

- (void)tick {
    if (!self.window) [self buildWindowIfNeeded];
    if (!self.window) return;

    NSDictionary *p = NSLoadPrefs();
    BOOL enabled = NSPrefBool(p, @"enabled", YES);
    self.window.hidden = !enabled;
    if (!enabled) return;

    double fontSize = NSPrefDouble(p, @"fontSize", 12.0);
    double bgOpacity = NSPrefDouble(p, @"bgOpacity", 0.5);
    self.label.font = [UIFont monospacedDigitSystemFontOfSize:fontSize weight:UIFontWeightSemibold];
    self.container.backgroundColor = [UIColor colorWithWhite:0 alpha:bgOpacity];

    uint64_t in = 0, out = 0;
    if (!NSReadNetTotals(&in, &out)) return;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (!self.hasLast) {
        self.lastIn = in;
        self.lastOut = out;
        self.lastTime = now;
        self.hasLast = YES;
        return;
    }

    double dt = now - self.lastTime;
    if (dt <= 0.05) dt = 1.0;
    double dIn = in >= self.lastIn ? (double)(in - self.lastIn) : 0;
    double dOut = out >= self.lastOut ? (double)(out - self.lastOut) : 0;
    self.lastIn = in;
    self.lastOut = out;
    self.lastTime = now;

    BOOL showDownload = NSPrefBool(p, @"showDownload", YES);
    BOOL showUpload = NSPrefBool(p, @"showUpload", YES);
    NSMutableArray *parts = [NSMutableArray array];
    if (showDownload) [parts addObject:[NSString stringWithFormat:@"↓ %@", NSFormatSpeed(dIn / dt)]];
    if (showUpload) [parts addObject:[NSString stringWithFormat:@"↑ %@", NSFormatSpeed(dOut / dt)]];
    self.label.text = parts.count ? [parts componentsJoinedByString:@"   "] : @"悬浮网速";

    [self resizeToFit];
}

@end

%ctor {
    @autoreleasepool {
        if (![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.springboard"]) return;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [[NSNetSpeedManager shared] start];
        });
    }
}
