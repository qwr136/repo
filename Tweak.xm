#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <notify.h>

static NSString * const LMVDirectory = @"/var/mobile/LockMessageVideo";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSHashTable<UIView *> *LMVCells;
static NSMutableDictionary<NSString *, NSString *> *LMVPaths;
static NSMutableDictionary<NSString *, NSNumber *> *LMVEnabled;
static CGFloat LMVOpacity = 0.55;
static int LMVBlankToken = -1;
static char LMVStatesKey;

@interface LMVVideoState : NSObject
@property(nonatomic, strong) UIView *overlay;
@property(nonatomic, strong) AVPlayerLayer *layer;
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLooper *looper;
@property(nonatomic, copy) NSString *path;
@end
@implementation LMVVideoState
- (void)dealloc {
    [_player pause];
    [_looper disableLooping];
    [_player removeAllItems];
    [_overlay removeFromSuperview];
}
@end

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
}
static BOOL LMVVisible(UIView *view) {
    if (!view.window || view.window.hidden || view.bounds.size.width < 1 || view.bounds.size.height < 1) return NO;
    for (UIView *ancestor = view; ancestor; ancestor = ancestor.superview) {
        if (ancestor.hidden || ancestor.alpha < 0.01) return NO;
        if (ancestor.clipsToBounds && !CGRectIntersectsRect([view convertRect:view.bounds toView:ancestor], ancestor.bounds)) return NO;
    }
    uint64_t blank = 0;
    if (LMVBlankToken >= 0 && notify_get_state(LMVBlankToken, &blank) == NOTIFY_STATUS_OK && blank) return NO;
    return CGRectIntersectsRect([view convertRect:view.bounds toView:view.window], view.window.bounds);
}
static BOOL LMVActionBranch(UIView *view) {
    return [NSStringFromClass(view.class) containsString:@"ActionButtons"];
}
// The message material must belong to the moving content, never the revealed action branch.
static UIView *LMVMessageMaterial(UIView *view, NSUInteger depth) {
    if (depth > 12 || LMVActionBranch(view)) return nil;
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"MaterialView"] && !view.hidden && view.bounds.size.width > 20 && view.bounds.size.height > 20) return view;
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
    NSArray *labels = @[(title ?: @""), (view.accessibilityLabel ?: @"")];
    for (NSString *label in labels) {
        NSString *text = [[label stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
        if ([@[@"clear", @"clear all", @"清除", @"清除全部", @"清除所有", @"清除所有通知"] containsObject:text]) return @"Clear";
        if ([@[@"options", @"manage", @"选项", @"管理"] containsObject:text]) return @"Options";
    }
    return nil;
}
static void LMVFindActions(UIView *view, UIView *root, NSMutableDictionary *hosts, NSUInteger depth) {
    if (depth > 10) return;
    NSString *target = LMVSemanticTarget(view);
    if (target) {
        UIView *host = view;
        // Prefer the concrete control; never apply one video's layer to the entire options/clear strip.
        while (host != root && ![host isKindOfClass:UIControl.class]) host = host.superview;
        if (host && host != root && host.bounds.size.width > 1 && host.bounds.size.height > 1) hosts[target] = host;
    }
    for (UIView *child in view.subviews) LMVFindActions(child, root, hosts, depth + 1);
}
static void LMVActionHosts(UIView *view, NSMutableDictionary *hosts, NSUInteger depth) {
    if (depth > 12) return;
    if (LMVActionBranch(view)) { LMVFindActions(view, view, hosts, 0); return; }
    for (UIView *child in view.subviews) LMVActionHosts(child, hosts, depth + 1);
}
static void LMVClear(UIView *cell) {
    NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
    for (LMVVideoState *state in states.allValues) { [state.player pause]; [state.overlay removeFromSuperview]; }
    objc_setAssociatedObject(cell, &LMVStatesKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
static void LMVUpdate(UIView *cell) {
    NSMutableDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey);
    if (!states) {
        states = [NSMutableDictionary new];
        objc_setAssociatedObject(cell, &LMVStatesKey, states, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (!LMVVisible(cell)) {
        for (LMVVideoState *state in states.allValues) [state.player pause];
        return;
    }
    NSMutableDictionary *hosts = [NSMutableDictionary new];
    LMVActionHosts(cell, hosts, 0);
    UIView *material = LMVMessageMaterial(cell, 0);
    if (material) hosts[@"Message"] = material;
    for (NSString *target in @[@"Message", @"Options", @"Clear"]) {
        UIView *anchor = hosts[target];
        NSString *path = LMVPaths[target];
        LMVVideoState *state = states[target];
        if (!LMVEnabled[target].boolValue || !path || !anchor || !anchor.superview) {
            [state.player pause];
            [state.overlay removeFromSuperview];
            [states removeObjectForKey:target];
            continue;
        }
        if (!LMVVisible(anchor)) { [state.player pause]; state.overlay.hidden = YES; continue; }
        if (state && ![state.path isEqualToString:path]) {
            [state.player pause]; [state.overlay removeFromSuperview]; [states removeObjectForKey:target]; state = nil;
        }
        if (!state) {
            state = [LMVVideoState new];
            state.path = path;
            state.overlay = [UIView new];
            state.overlay.userInteractionEnabled = NO;
            state.overlay.clipsToBounds = YES;
            state.player = [AVQueuePlayer queuePlayerWithItems:@[]];
            state.player.muted = YES;
            state.looper = [AVPlayerLooper playerLooperWithPlayer:state.player templateItem:[AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:path]]];
            state.layer = [AVPlayerLayer playerLayerWithPlayer:state.player];
            state.layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
            [state.overlay.layer addSublayer:state.layer];
            states[target] = state;
        }
        BOOL message = [target isEqualToString:@"Message"];
        UIView *host = message ? anchor.superview : anchor;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        if (message) {
            [host insertSubview:state.overlay aboveSubview:anchor];
            state.overlay.frame = anchor.frame;
        } else {
            [host insertSubview:state.overlay atIndex:0];
            state.overlay.frame = host.bounds;
        }
        state.overlay.layer.cornerRadius = anchor.layer.cornerRadius;
        state.layer.frame = state.overlay.bounds;
        state.overlay.alpha = LMVOpacity;
        state.overlay.hidden = NO;
        [CATransaction commit];
        [state.player play];
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
    if (![(UIView *)self window]) LMVClear((UIView *)self); else LMVUpdate((UIView *)self);
}
- (void)prepareForReuse {
    LMVClear((UIView *)self);
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
    if (reload) LMVLoadPreferences();
    for (UIView *cell in LMVCells.allObjects) {
        if (reload) LMVClear(cell);
        LMVUpdate(cell);
        [cell setNeedsLayout];
    }
}
static void LMVDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{ LMVRefresh(YES); });
}
%ctor {
    @autoreleasepool {
        LMVCells = [NSHashTable weakObjectsHashTable];
        LMVLoadPreferences();
        notify_register_check("com.apple.springboard.hasBlankedScreen", &LMVBlankToken);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { LMVRefresh(NO); }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { for (UIView *cell in LMVCells.allObjects) { NSDictionary *states = objc_getAssociatedObject(cell, &LMVStatesKey); for (LMVVideoState *state in states.allValues) [state.player pause]; } }];
            [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { LMVRefresh(NO); }];
        });
    }
}
