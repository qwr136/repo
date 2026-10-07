#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import <notify.h>

static NSString * const kLMVVideoPath = @"/var/mobile/LockMessageVideo/message.mov";
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static NSHashTable<UIView *> *LMVCells;
static BOOL LMVEnabled;
static CGFloat LMVOpacity = 0.55;
static int LMVBlankToken = -1;

@interface LMVVideoState : NSObject
@property(nonatomic, strong) UIView *overlay;
@property(nonatomic, strong) AVPlayerLayer *layer;
@property(nonatomic, strong) AVQueuePlayer *player;
@property(nonatomic, strong) AVPlayerLooper *looper;
@end
@implementation LMVVideoState
- (void)dealloc {
    [_player pause];
    [_looper disableLooping];
    [_player removeAllItems];
    [_overlay removeFromSuperview];
}
@end
static char LMVStateKey;

static void LMVLoadPreferences(void) {
    CFPreferencesAppSynchronize(kLMVPrefsID);
    NSNumber *enabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("MessageBackgroundEnabled"), kLMVPrefsID);
    NSNumber *opacity = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("MessageBackgroundOpacity"), kLMVPrefsID);
    LMVEnabled = enabled.boolValue;
    LMVOpacity = opacity ? MAX(0.1, MIN(1.0, opacity.floatValue)) : 0.55;
}

static BOOL LMVVisible(UIView *cell) {
    if (!cell.window || cell.window.hidden) return NO;
    for (UIView *view = cell; view; view = view.superview) {
        if (view.hidden || view.alpha < 0.01) return NO;
    }
    uint64_t blank = 0;
    if (LMVBlankToken >= 0 && notify_get_state(LMVBlankToken, &blank) == NOTIFY_STATUS_OK && blank) return NO;
    return CGRectIntersectsRect([cell convertRect:cell.bounds toView:cell.window], cell.window.bounds);
}

// Probe only descendants of a notification cell; private material hierarchy can vary.
static UIView *LMVMaterial(UIView *view, NSUInteger depth) {
    if (depth > 12) return nil;
    NSString *name = NSStringFromClass(view.class);
    if ([name containsString:@"MaterialView"] && !view.hidden && view.bounds.size.width > 20 && view.bounds.size.height > 20) return view;
    for (UIView *child in view.subviews) {
        UIView *found = LMVMaterial(child, depth + 1);
        if (found) return found;
    }
    return nil;
}

static void LMVClear(UIView *cell) {
    LMVVideoState *state = objc_getAssociatedObject(cell, &LMVStateKey);
    [state.player pause];
    [state.overlay removeFromSuperview];
    objc_setAssociatedObject(cell, &LMVStateKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void LMVUpdate(UIView *cell) {
    if (!LMVEnabled || ![[NSFileManager defaultManager] fileExistsAtPath:kLMVVideoPath]) {
        LMVClear(cell);
        return;
    }
    BOOL visible = LMVVisible(cell);
    LMVVideoState *state = objc_getAssociatedObject(cell, &LMVStateKey);
    if (!visible) { [state.player pause]; return; }
    UIView *material = LMVMaterial(cell, 0);
    if (!material || !material.superview) { LMVClear(cell); return; }
    UIView *host = material.superview;
    if (!state) {
        state = [LMVVideoState new];
        state.overlay = [[UIView alloc] initWithFrame:material.frame];
        state.overlay.userInteractionEnabled = NO;
        state.overlay.clipsToBounds = YES;
        state.player = [AVQueuePlayer queuePlayerWithItems:@[]];
        state.player.muted = YES;
        state.looper = [AVPlayerLooper playerLooperWithPlayer:state.player templateItem:[AVPlayerItem playerItemWithURL:[NSURL fileURLWithPath:kLMVVideoPath]]];
        state.layer = [AVPlayerLayer playerLayerWithPlayer:state.player];
        state.layer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        [state.overlay.layer addSublayer:state.layer];
        objc_setAssociatedObject(cell, &LMVStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Above the material background, below subsequent content siblings; no negative zPosition.
    [host insertSubview:state.overlay aboveSubview:material];
    state.overlay.frame = material.frame;
    state.overlay.layer.cornerRadius = material.layer.cornerRadius;
    state.layer.frame = state.overlay.bounds;
    state.overlay.alpha = LMVOpacity;
    [state.player play];
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
    if (![(UIView *)self window]) LMVClear((UIView *)self);
    else LMVUpdate((UIView *)self);
}
- (void)prepareForReuse {
    LMVClear((UIView *)self);
    %orig;
}
%end

static void LMVDarwinNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        LMVLoadPreferences();
        for (UIView *cell in LMVCells.allObjects) {
            LMVClear(cell);
            LMVUpdate(cell);
            [cell setNeedsLayout];
        }
    });
}

%ctor {
    @autoreleasepool {
        LMVCells = [NSHashTable weakObjectsHashTable];
        LMVLoadPreferences();
        notify_register_check("com.apple.springboard.hasBlankedScreen", &LMVBlankToken);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, LMVDarwinNotification, CFSTR("com.minis.lockmessagevideo/videoChanged"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_async(dispatch_get_main_queue(), ^{
            [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
                for (UIView *cell in LMVCells.allObjects) LMVUpdate(cell);
            }];
        });
    }
}
