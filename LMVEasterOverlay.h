#pragma once
#import "LMVEasterPanel.h"
#import "LMVEasterGeometry.h"
#import "LMVEasterDisplayPolicy.h"
// 0.0.122: corner radius + panel size, shared with the settings page.
#import "LMVEasterPanelAppearance.h"
#import <notify.h>
#import <objc/message.h>
#import <string.h>

@class LMVEasterManager;
@interface LMVEasterRoot : UIViewController
@property(nonatomic, weak) LMVEasterManager *manager;
@end
@interface LMVEasterWindow : UIWindow
@property(nonatomic, weak) UIView *bubble;
@property(nonatomic, weak) UIView *panel;
@end
@implementation LMVEasterWindow
// 2.21: A WINDOW MAY BE HIDDEN BY THE SYSTEM WHILE THE DEVICE IS LOCKED.
// This project never declared it, and that is why the ball could only be seen at
// the instant of unlocking: the state machine had already said "show" (device log
// 2.19 shows six uninterrupted seconds of home-nc-cc host=SBCoverSheetWindow with
// our window at level 10000012, hidden=0, alpha=1.00), yet nothing was drawn while
// locked. The lock-screen video never had this problem because it lives INSIDE the
// cover sheet's own view hierarchy instead of a separate UIWindow. UIKit asks the
// window - and its root view controller - whether it may stay on screen while
// locked; the answer defaults to NO.
- (BOOL)_canShowWhileLocked { return YES; }
// Key status only while the contained panel is open, so its prompt text field can
// become first responder and show the keyboard. The manager hands key back to the
// previous SpringBoard key window when editing ends or the panel closes.
- (BOOL)canBecomeKeyWindow { return self.panel != nil && !self.hidden; }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.hidden || self.alpha < 0.01) return nil;
    // Only the actual bubble/panel rectangles accept touches. Navigation,
    // Photos children and contained prompts remain inside that same panel.
    for (UIView *view in @[self.panel ?: [NSNull null], self.bubble ?: [NSNull null]]) {
        if (![view isKindOfClass:UIView.class] || view.hidden || view.alpha < 0.01) continue;
        CGPoint local = [view convertPoint:point fromView:self];
        if ([view pointInside:local withEvent:event]) return [view hitTest:local withEvent:event];
    }
    return nil;
}
@end

@interface LMVEasterManager : NSObject
@property(nonatomic, strong) LMVEasterWindow *window;
// The hit/drag rectangle is never transformed; only this child draws/rotates.
@property(nonatomic, strong) UIView *bubble;
@property(nonatomic, strong) UIImageView *bubbleImage;
@property(nonatomic) LMVEasterDisplayControls displayControls;
@property(nonatomic) LMVEasterDisplayScene displayScene;
@property(nonatomic, strong) UINavigationController *panel;
@property(nonatomic, strong) LMVEasterImage *decoded;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *imageKey, *windowReason;
@property(nonatomic, strong) NSTimer *visibilityTimer;
@property(nonatomic, weak) UIWindow *foreignKey, *hostWindow;
@property(nonatomic) CGFloat keyboardTop;
// 0.0.122: the panel is draggable by its title bar; 1.64 persists the offset so
// closing the panel, hiding the egg or respringing all reopen it in the same
// place. It is re-clamped on every layout so it can never leave the screen.
@property(nonatomic) CGPoint panelOffset;
@property(nonatomic) NSUInteger generation, frame, lastHostSignature;
@property(nonatomic) BOOL pending, ready, authenticatedSession;
// 2.14: cover-sheet exposure origin (began unlocked = Notification Center; began
// locked = the lock screen, including the whole Face ID/unlock animation).
@property(nonatomic) BOOL coverWasExposed, coverStartedUnlocked;
// 2.22: the cover-sheet window the bubble is currently living inside, when the
// lock screen is the scene. Nil on every other scene (the ball uses its own window).
@property(nonatomic, weak) UIWindow *embedHost;
// 2.15: when the cover last became invisible. A re-exposure inside 150 ms is the
// unlock animation flapping, not a fresh Notification Center pull.
@property(nonatomic) CFTimeInterval coverGoneAt;
@property(nonatomic) CGPoint normalized;
// Cache only physical probes, never permission/scope decisions. Notifications
// invalidate them; a bounded default-mode audit catches silent tree replacement.
@property(nonatomic, copy) NSArray<UIWindow *> *physicalWindows;
@property(nonatomic, copy) NSArray<UIView *> *physicalProbes;
@property(nonatomic, copy) NSArray *physicalSnapshot;
@property(nonatomic) CFTimeInterval lastPhysicalCheck;
- (void)invalidatePhysicalSnapshot;
- (void)refresh;
- (void)closePanel;
- (void)reportWindow:(NSString *)reason;
- (void)layout;
- (void)restoreKey;
- (void)recordScreenBlank;
- (void)syncRotation;
@end
@implementation LMVEasterRoot
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = UIColor.clearColor; }
- (void)viewDidLayoutSubviews { [super viewDidLayoutSubviews]; [self.manager layout]; }

// 2.21: the window answers this too, but UIKit also asks the root view controller
// of the window it is about to suppress. Both answers must be YES or the lock
// screen still hides the ball. Plain system UI (lock-screen media, call banner)
// opts in the same way.
- (BOOL)_canShowWhileLocked { return YES; }

// 0.0.117: while the panel is open this window becomes KEY, so UIKit asks ITS
// root view controller for the supported orientations. A plain UIViewController
// answers portrait-only, which locks the whole scene (SpringBoard included) and
// left the floating ball where it was when the phone turned landscape with the
// rotation lock off. All-but-upside-down matches the other floating system
// surfaces; layout follows the root view bounds, so the ball moves with it.
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }

@end

static BOOL LMVEasterKnownWindow(UIWindow *window, NSArray<NSString *> *names) {
    for (NSString *name in names) { Class cls = NSClassFromString(name); if (cls && [window isKindOfClass:cls]) return YES; }
    return NO;
}
// Inspect only visible bounded drawing branches, not mere persistent window existence.
static BOOL LMVEasterSecurityName(NSString *name) {
    for (NSString *word in @[@"Passcode",@"Authentication",@"Biometric",@"Permission",@"Privacy",@"Authorization",@"LocalAuth",@"Credential"])
        if ([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound) return YES;
    return NO;
}
// 0.0.112: the system screen-recording / capture indicator is a PRIVACY surface
// ("Privacy" is in the security word list above), so recording a screen turned
// the floating ball off for the whole session: the audit read the recording
// indicator as a protected modal. An indicator is not a prompt -- the ball must
// stay visible (and above it). Only capture-worded surfaces are exempt; a real
// passcode/permission prompt never carries these words.
static BOOL LMVEasterCaptureName(NSString *name) {
    if (!name.length) return NO;
    for (NSString *word in @[@"Recording",@"ScreenCapture",@"CaptureIndicator",@"PrivacyIndicator",@"Broadcast",@"Replay",@"Mirroring"])
        if ([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound) return YES;
    return NO;
}
static BOOL LMVEasterVisibleDrawing(UIView *view, UIWindow *window, NSUInteger depth, NSUInteger *budget, BOOL *security) {
    if (!view || !*budget || depth>7 || view.hidden || view.alpha<0.01) return NO;
    --*budget;
    CGRect rect=CGRectIntersection([view convertRect:view.bounds toView:window],window.bounds);
    if (CGRectIsNull(rect) || CGRectIsEmpty(rect)) return NO;
    NSString *viewName=NSStringFromClass(view.class);
    if (LMVEasterSecurityName(viewName) && !LMVEasterCaptureName(viewName)) *security=YES;
    CGFloat area=rect.size.width*rect.size.height, full=window.bounds.size.width*window.bounds.size.height;
    BOOL draws=view.layer.contents!=nil || (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor)>0.05) ||
        [view isKindOfClass:UIVisualEffectView.class];
    BOOL substantive=draws && full>0 && area/full>=0.30;
    for (UIView *child in view.subviews) if (LMVEasterVisibleDrawing(child,window,depth+1,budget,security)) substantive=YES;
    return substantive;
}
// lockstate can briefly report locked while an unlocked CoverSheet is being
// pulled. Keep only an unlock observed during the CURRENT screen-on session;
// a blank event invalidates it before a later real LockScreen presentation.
static BOOL LMVEasterNCPolicy(BOOL blankKnown,uint64_t blank,BOOL lockKnown,uint64_t locked,
                             BOOL exposed,BOOL *authenticated) {
    if (!blankKnown || blank || !lockKnown) { *authenticated=NO; return NO; }
    // Only learn an unlocked session outside CoverSheet. Face ID can unlock
    // while the real lock screen remains onscreen; that is not Notification Center.
    if (!locked && !exposed) *authenticated=YES;
    return exposed && *authenticated;
}
static UIView *LMVEasterFindCover(UIView *view,NSUInteger depth,NSUInteger *budget) {
    if (!view || !*budget || depth>10) return nil;
    --*budget;
    Class cls=NSClassFromString(@"CSCoverSheetView");
    if (cls && [view isKindOfClass:cls]) return view;
    for (UIView *child in view.subviews) {
        UIView *cover=LMVEasterFindCover(child,depth+1,budget);if(cover)return cover;
    }
    return nil;
}
static BOOL LMVEasterNCWindowExposed(UIWindow *window) {
    Class cls=NSClassFromString(@"SBCoverSheetWindow");
    if (!cls || ![window isKindOfClass:cls] || window.screen!=UIScreen.mainScreen ||
        window.hidden || window.alpha<.01 || CGRectIsEmpty(window.bounds)) return NO;
    NSUInteger budget=128;UIView *cover=LMVEasterFindCover(window,0,&budget);
    if (!cover) return NO;
    UIView *content=nil;
    for (NSString *name in @[@"slideableContentView",@"contentView"]) {
        SEL selector=NSSelectorFromString(name);
        if (![cover respondsToSelector:selector]) continue;
        NSMethodSignature *sig=[cover methodSignatureForSelector:selector];
        if (!sig || sig.numberOfArguments!=2 || strcmp(sig.methodReturnType,@encode(id))) continue;
        id candidate=((id (*)(id,SEL))objc_msgSend)(cover,selector);
        if ([candidate isKindOfClass:UIView.class] && candidate!=cover && [candidate isDescendantOfView:cover]) {content=candidate;break;}
    }
    if (!content || CGRectIsEmpty(content.bounds)) return NO;
    for (UIView *node=content;node;node=node.superview) if (node.hidden || node.alpha<.01) return NO;
    CALayer *shown=content.layer.presentationLayer,*root=window.layer.presentationLayer;
    CGRect rect=(shown && root)?[shown convertRect:shown.bounds toLayer:root]:[content convertRect:content.bounds toView:window];
    if (CGRectIsNull(rect) || CGRectIsInfinite(rect)) return NO;
    CGRect overlap=CGRectIntersection(rect,window.bounds);
    return !CGRectIsNull(overlap) && !CGRectIsEmpty(overlap) && overlap.size.height>1 && overlap.size.width>1;
}
static BOOL LMVEasterWindowExposed(UIWindow *window) {
    if (!window || window.screen!=UIScreen.mainScreen || window.hidden || window.alpha<.01) return NO;
    UIView *root=window.rootViewController.viewIfLoaded;
    if (!root || root.hidden || root.alpha<.01) return NO;
    CGRect rect=[root convertRect:root.bounds toView:window];
    CGRect exposed=CGRectIntersection(rect,window.bounds);
    return !CGRectIsNull(exposed) && !CGRectIsEmpty(exposed) && exposed.size.width>1 && exposed.size.height>1;
}
static UIView *LMVEasterCCOverlay(UIWindow *window) {
    if (!LMVEasterKnownWindow(window,@[@"SBControlCenterWindow"]) || !LMVEasterWindowExposed(window)) return nil;
    NSMutableArray *pending=[NSMutableArray arrayWithObject:window.rootViewController.viewIfLoaded];NSUInteger budget=128;
    while(pending.count && budget) {
        --budget;UIView *view=pending.lastObject;[pending removeLastObject];
        if(view.hidden || view.alpha<.01)continue;
        if([view.layer.name hasSuffix:@"CCUIModularControlCenterOverlayViewController"]) {
            CGRect rect=CGRectIntersection([view convertRect:view.bounds toView:window],window.bounds);
            return !CGRectIsNull(rect) && !CGRectIsEmpty(rect)?view:nil;
        }
        if(view.subviews.count<48)[pending addObjectsFromArray:view.subviews];
    }
    return nil;
}
static BOOL LMVEasterCCWindowExposed(UIWindow *window) { return LMVEasterCCOverlay(window)!=nil; }
// Captures live geometry/ancestry, not drawing trees. Common-mode ticks compare
// this small snapshot; full drawing/security audits run at most once per second
// and only outside tracking (window/scene/lock notifications still run immediately).
static NSArray *LMVEasterPhysicalSnapshot(NSArray<UIWindow *> *windows,NSArray<UIView *> *probes,
                                        NSInteger foreground,BOOL blankKnown,uint64_t blank,
                                        BOOL lockKnown,uint64_t locked) {
    NSMutableArray *state=[NSMutableArray arrayWithArray:@[@(foreground),@(blankKnown),@(blank),@(lockKnown),@(locked)]];
    for(UIWindow *window in windows) {
        UIViewController *controller=window.rootViewController;
        NSUInteger depth=0;
        while(controller.presentedViewController && depth++<16)controller=controller.presentedViewController;
        UIView *root=controller.viewIfLoaded;CGRect bounds=window.bounds;
        [state addObject:@[[NSValue valueWithNonretainedObject:window],@(window.hidden),@(window.alpha),
            @(window.windowLevel),[NSValue value:&bounds withObjCType:@encode(CGRect)],
            [NSValue valueWithNonretainedObject:window.windowScene],@(window.windowScene.activationState),
            [NSValue valueWithNonretainedObject:window.screen],
            [NSValue valueWithNonretainedObject:controller],[NSValue valueWithNonretainedObject:root]]];
    }
    for(UIView *probe in probes) {
        NSUInteger depth=0;
        for(UIView *view=probe;view && depth++<16;view=view.superview) {
            CALayer *shown=view.layer.presentationLayer ?: view.layer;
            CGRect bounds=shown.bounds;CGPoint position=shown.position;CATransform3D transform=shown.transform;
            [state addObject:@[[NSValue valueWithNonretainedObject:view],
                [NSValue valueWithNonretainedObject:view.superview],@(view.hidden),@(view.alpha),
                [NSValue value:&bounds withObjCType:@encode(CGRect)],
                [NSValue value:&position withObjCType:@encode(CGPoint)],
                [NSValue value:&transform withObjCType:@encode(CATransform3D)]]];
        }
    }
    return state;
}
static BOOL LMVEasterPhysicalCheckNeeded(BOOL invalid,BOOL changed,CFTimeInterval now,
                                        CFTimeInterval last,BOOL tracking) {
    return invalid || changed || (!tracking && (now<last || now-last>=1.0));
}
static BOOL LMVEasterObjectGetter(id object,SEL selector) {
    if(!object || ![object respondsToSelector:selector])return NO;
    NSMethodSignature *signature=[object methodSignatureForSelector:selector];
    return signature && signature.numberOfArguments==2 && !strcmp(signature.methodReturnType,@encode(id));
}
// Home=1, application=-1, unknown=0. Only use existing published state.
static NSInteger LMVEasterForeground(void) {
    UIApplication *app=UIApplication.sharedApplication;BOOL known=NO,unknown=NO;
    for(NSString *name in @[@"_frontmostApplication",@"_accessibilityFrontMostApplication"]) {
        SEL selector=NSSelectorFromString(name);if(!LMVEasterObjectGetter(app,selector))continue;
        known=YES;id object=((id(*)(id,SEL))objc_msgSend)(app,selector);if(!object)continue;
        SEL bundle=NSSelectorFromString(@"bundleIdentifier");
        id identifier=LMVEasterObjectGetter(object,bundle)?((id(*)(id,SEL))objc_msgSend)(object,bundle):nil;
        if([identifier isKindOfClass:NSString.class] && [identifier length])return [identifier isEqualToString:@"com.apple.springboard"]?1:-1;
        unknown=YES;
    }
    return known && !unknown?1:0;
}
// 1.64: a cheap change detector for the three display hosts. The full physical
// snapshot walks every window and probe (hundreds of property reads) and is
// rate-limited to one second, so collapsing Control Centre used to leave the
// ball on screen for up to a second after the panel was gone. Comparing only
// the host windows costs a handful of reads and can therefore run at the
// timer's own rate: the moment CC/NC/Home appears or disappears the policy is
// re-evaluated, and the ball leaves with the panel instead of after it.
// 1.65: host visibility from the long-lived window object list. The 1.64
// attempt read a cached array that -refresh/-apply nulled out, so the signature
// usually read as zero and the ball fell back to the one-second audit: slower
// than the original half-second poll, exactly as the device felt. The window
// objects never go away, so their live hidden/alpha state is enough, and the
// tick needs no scene enumeration.
// 2.12: THE APP SWITCHER IS SPRINGBOARD, SO fg STAYS 1 AND THE HOME WINDOW
// BEHIND IT STAYS "EXPOSED". That is why the ball survived swiping up into the
// switcher, and why it popped back the moment an app was closed out of the
// switcher: the switcher is still up, but the home surface behind it qualifies.
// This overlay stays private-class-free (a regression test enforces it), so the
// only probe used is public: whoever holds KEY. On the desktop that is the home
// window; while the switcher is up it is the switcher's own window.
static BOOL LMVEasterSwitcherPresented(NSArray<UIWindow *> *windows) {
    for(UIWindow *window in windows) {
        if(!window.isKeyWindow)continue;
        NSString *name=NSStringFromClass(window.class);
        if([name containsString:@"Switcher"])return YES;
    }
    return NO;
}
// 2.12: AN APP ON SCREEN IS NOT THE DESKTOP. Unlocking straight into an app used
// to flash the ball: SpringBoard is still the frontmost process for a beat while
// the app's window is already up behind the cover. The app surface on this device
// is SBWindow (the desktop channel learned that in 1.25); on the desktop the same
// window exists but carries an empty root view, so "exposed AND has content" is
// the tell. Switcher surfaces are excluded - they are handled separately.
static BOOL LMVEasterAppWindowPresent(NSArray<UIWindow *> *windows) {
    for(UIWindow *window in windows) {
        if(!LMVEasterWindowExposed(window))continue;
        NSString *name=NSStringFromClass(window.class);
        if(![name isEqualToString:@"SBWindow"] && ![name containsString:@"AppWindow"])continue;
        UIView *root=window.rootViewController.viewIfLoaded;
        if(root && root.subviews.count)return YES;
    }
    return NO;
}
static NSUInteger LMVEasterQuickHostMask(NSArray<UIWindow *> *windows) {
    NSUInteger mask=0;
    for (UIWindow *window in windows) {
        if (LMVEasterKnownWindow(window,@[@"SBCoverSheetWindow"]) && LMVEasterWindowExposed(window)) mask|=1;
        if (LMVEasterKnownWindow(window,@[@"SBControlCenterWindow"]) && LMVEasterWindowExposed(window)) mask|=2;
    }
    // The switcher is not one of the three hosts, but opening/closing it changes
    // whether the home host is legal, so it has to invalidate the snapshot too.
    if (LMVEasterSwitcherPresented(windows)) mask|=4;
    if (LMVEasterAppWindowPresent(windows)) mask|=8;
    return mask;
}
static BOOL LMVEasterScopePolicy(BOOL blankKnown,uint64_t blank,BOOL lockKnown,uint64_t locked,
                               BOOL nc,BOOL cc,BOOL home,BOOL *authenticated) {
    BOOL ncAllowed=LMVEasterNCPolicy(blankKnown,blank,lockKnown,locked,nc,authenticated);
    if(!blankKnown || blank || !lockKnown)return NO;
    if(nc)return ncAllowed;
    return !locked && (cc || home);
}
// Ordinary transparent/tiny drawing HUDs have no foreground controls. Do not
// infer that from a vendor class name (especially a name containing Gesture).
static BOOL LMVEasterVisibleForeground(UIView *view,UIWindow *window,NSUInteger depth,
                                      NSUInteger *budget,BOOL *drawing,BOOL *modal) {
    if(!view || !*budget || depth>7 || view.hidden || view.alpha<.01)return NO;
    --*budget;
    CGRect rect=CGRectIntersection([view convertRect:view.bounds toView:window],window.bounds);
    if(CGRectIsNull(rect) || CGRectIsEmpty(rect) || CGRectIsInfinite(rect))return NO;
    if(view.layer.contents || (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor)>.05) ||
       [view isKindOfClass:UIVisualEffectView.class])*drawing=YES;
    BOOL foreground=NO;
    for(NSString *name in @[@"UIControl",@"UIAlertView",@"UIActionSheet"]) {
        Class cls=NSClassFromString(name);
        if(cls && [view isKindOfClass:cls]) {
            foreground=YES;if(![name isEqualToString:@"UIControl"])*modal=YES;
        }
    }
    for(UIView *child in view.subviews)
        if(LMVEasterVisibleForeground(child,window,depth+1,budget,drawing,modal))foreground=YES;
    return foreground;
}
static BOOL LMVEasterPriorityWindowVisible(UIWindow *window) {
    UIView *root=window.rootViewController.viewIfLoaded;
    return window && !window.hidden && isfinite(window.alpha) && window.alpha>=.01 &&
        (!root || (!root.hidden && isfinite(root.alpha) && root.alpha>=.01)) &&
        window.screen==UIScreen.mainScreen && !CGRectIsEmpty(window.bounds) &&
        !CGRectIsNull(window.bounds) && !CGRectIsInfinite(window.bounds);
}
// Dynamic because the private SDK surface is not always declared; a missing
// selector must mean "not captured", never a build or runtime error.
static BOOL LMVEasterScreenCaptured(void) {
    UIScreen *screen=UIScreen.mainScreen;SEL selector=NSSelectorFromString(@"isCaptured");
    if(!screen || ![screen respondsToSelector:selector])return NO;
    NSMethodSignature *signature=[screen methodSignatureForSelector:selector];
    if(!signature || signature.numberOfArguments!=2 || strcmp(signature.methodReturnType,@encode(BOOL)))return NO;
    return ((BOOL(*)(id,SEL))objc_msgSend)(screen,selector);
}
// 0.0.112: see LMVEasterCaptureName. A live capture surface may compete for the
// level (so the ball still sits above the recording indicator) but it must never
// block. While the display is actually captured, any window whose class is a
// capture indicator qualifies even if a vendor renamed it past the word list.
static BOOL LMVEasterCaptureWindow(UIWindow *window) {
    if(!window)return NO;
    NSString *root=window.rootViewController ? NSStringFromClass(window.rootViewController.class) : @"";
    if(LMVEasterCaptureName(NSStringFromClass(window.class)) || LMVEasterCaptureName(root))return YES;
    if(!LMVEasterScreenCaptured())return NO;
    for(NSString *word in @[@"Indicator",@"Capture"])
        for(NSString *name in @[NSStringFromClass(window.class),root])
            if([name rangeOfString:word options:NSCaseInsensitiveSearch].location!=NSNotFound)return YES;
    return NO;
}
static BOOL LMVEasterBlockingWindow(UIWindow *window, CGFloat level) {
    (void)level; // Security is never waived just because the bubble is higher.
    if(!LMVEasterPriorityWindowVisible(window))return NO;
    NSUInteger depth=0,drawingBudget=96,foregroundBudget=96;
    for(UIViewController *controller=window.rootViewController;controller && depth++<16;
        controller=controller.presentedViewController) {
        UIView *root=controller.viewIfLoaded;
        BOOL security=NO,drawing=NO,modal=NO;
        BOOL substantive=LMVEasterVisibleDrawing(root,window,0,&drawingBudget,&security);
        BOOL foreground=LMVEasterVisibleForeground(root,window,0,&foregroundBudget,&drawing,&modal);
        // A capture/recording indicator surface is never a protected modal
        // (0.0.112), even though its privacy wording matches the security list.
        BOOL classSecurity=(!LMVEasterCaptureName(NSStringFromClass(window.class)) &&
            LMVEasterSecurityName(NSStringFromClass(window.class))) ||
            (root.window==window && !LMVEasterCaptureName(NSStringFromClass(controller.class)) &&
             LMVEasterSecurityName(NSStringFromClass(controller.class)));
        Class alert=NSClassFromString(@"UIAlertController");
        CGRect rect=root?[root convertRect:root.bounds toView:window]:CGRectZero;
        CGRect exposed=CGRectIntersection(rect,window.bounds);
        BOOL visible=root && !root.hidden && root.alpha>=.01 && !CGRectIsNull(exposed) &&
            !CGRectIsEmpty(exposed) && !CGRectIsInfinite(exposed);
        // 0.0.112: while the display is CAPTURED the recording/privacy indicator
        // matches the privacy security words, so a bare name match may not hide
        // the floating ball. Real prompts stay protected through their
        // window/controller class, a visible foreground control, or an alert.
        BOOL strongSecurity=(classSecurity && (drawing || substantive || foreground)) ||
            (security && foreground);
        BOOL weakSecurity=security && !LMVEasterScreenCaptured();
        if(weakSecurity || strongSecurity || modal ||
           (visible && alert && [controller isKindOfClass:alert]))return YES;
    }
    return NO;
}
// Leave integer headroom even on CGFloat=float; never use UINT_MAX/CGFLOAT_MAX
// or let an unrepresentable +1 silently tie a foreign window. Extreme finite
// levels fail closed; malformed NaN/infinity cannot poison the running maximum.
static BOOL LMVEasterBoundedPriorityLevel(CGFloat highest,CGFloat *level) {
    // iOS CGFloat is double. The old universal 24-bit float cap falsely
    // rejected high recording/gesture windows and actively hid our overlay.
    // Keep exact +1 headroom for each actual scalar representation.
    const CGFloat limit=sizeof(CGFloat)>sizeof(float)?0x1p48-2:0x1p24-2;
    if(!isfinite(highest) || highest>limit || highest < -limit)return NO;
    CGFloat next=highest+1;
    if(!isfinite(next) || next<=highest)return NO;
    *level=next;return YES;
}
static BOOL LMVEasterOverlayPriority(NSArray<UIWindow *> *windows,UIWindow *own,
                                    CGFloat *level,UIWindow **blockedWindow) {
    CGFloat highest=0;
    if(blockedWindow)*blockedWindow=nil;
    for(UIWindow *window in windows) {
        if(window==own || !LMVEasterPriorityWindowVisible(window))continue;
        // A live recording/capture indicator only competes for the level below.
        if(!LMVEasterCaptureWindow(window) && LMVEasterBlockingWindow(window,0)) {
            if(blockedWindow)*blockedWindow=window;return NO;
        }
        CGFloat candidate=window.windowLevel;
        if(!isfinite(candidate))continue;
        // 0.0.118 device log: iOS shows a touch visualiser while the screen is
        // being RECORDED and its window reports windowLevel = DBL_MAX
        // (_LNSceneTouchVisualizerWindow). Demanding +1 headroom for it failed
        // closed and reported "blocked", which hid the floating ball for the whole
        // recording. A level we cannot represent is simply not a level competitor
        // and not a blocker: the final bounded computation below still keeps our
        // own level finite.
        if(!LMVEasterBoundedPriorityLevel(candidate,level))continue;
        highest=MAX(highest,candidate);
    }
    return LMVEasterBoundedPriorityLevel(highest,level);
}
static void LMVEasterDarwin(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    __weak LMVEasterManager *manager = (__bridge LMVEasterManager *)observer;
    dispatch_async(dispatch_get_main_queue(), ^{
        // Screen/recording transitions can queue multiple state notifications.
        // Apply the CURRENT blank value, not an obsolete captured value.
        uint64_t blank=0;
        BOOL blanked=LMVBlankToken>=0 && notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK && blank;
        if (blanked) [manager recordScreenBlank];
        [manager refresh];
    });
}
@implementation LMVEasterManager
- (instancetype)init {
    self = [super init];
    if (self) {
        _normalized = CGPointMake(0.9, 0.35);
        id x = LMVEasterRead(@"EasterEggX"), y = LMVEasterRead(@"EasterEggY");
        if ([x isKindOfClass:NSNumber.class] && [y isKindOfClass:NSNumber.class] && isfinite([x doubleValue]) && isfinite([y doubleValue])) _normalized = CGPointMake(MAX(0, MIN(1, [x doubleValue])), MAX(0, MIN(1, [y doubleValue])));
        // 1.64: the dragged panel position survives closing, hiding and respring.
        id ox = LMVEasterRead(@"EasterPanelOffsetX"), oy = LMVEasterRead(@"EasterPanelOffsetY");
        if ([ox isKindOfClass:NSNumber.class] && [oy isKindOfClass:NSNumber.class] &&
            isfinite([ox doubleValue]) && isfinite([oy doubleValue]))
            _panelOffset = CGPointMake([ox doubleValue], [oy doubleValue]);
        for (NSString *name in @[@"com.minis.lockmessagevideo/preferencesChanged", @"com.apple.springboard.hasBlankedScreen", @"com.apple.springboard.lockstate"]) CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self, LMVEasterDarwin, (__bridge CFStringRef)name, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        for (NSString *name in @[UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeHiddenNotification, UIWindowDidBecomeKeyNotification, UIScreenCapturedDidChangeNotification, UISceneDidActivateNotification, UISceneWillDeactivateNotification, UIApplicationDidBecomeActiveNotification, UIApplicationDidReceiveMemoryWarningNotification]) {
            [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(changed:) name:name object:nil];
        }
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(keyboard:) name:UIKeyboardWillHideNotification object:nil];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(editingEnded:) name:UITextFieldTextDidEndEditingNotification object:nil];
    }
    return self;
}
- (void)dealloc {
    // Stop only the owned image-layer animation even if the panel is still open.
    LMVEasterUpdateRotation(_bubbleImage.layer,NO,NO,NO,45);
    [self.timer invalidate]; [self.visibilityTimer invalidate]; [NSNotificationCenter.defaultCenter removeObserver:self];
    CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(), (__bridge void *)self);
}
- (void)changed:(NSNotification *)notification {
    if (notification.object == self.window) return;
    // Remember SpringBoard's own key window so text editing can hand key back.
    if ([notification.name isEqualToString:UIWindowDidBecomeKeyNotification] && [notification.object isKindOfClass:UIWindow.class])
        self.foreignKey = notification.object;
    if ([notification.name isEqualToString:UIApplicationDidReceiveMemoryWarningNotification]) {
        [self hide]; self.generation++; self.decoded = nil; self.imageKey = nil; self.bubbleImage.image = nil;
    }
    dispatch_async(dispatch_get_main_queue(), ^{ [self refresh]; });
}
- (void)reportWindow:(NSString *)reason {
    if ([self.windowReason isEqual:reason]) return;
    self.windowReason=reason;
    LMVEasterWindowDiagnostic(reason);
}
- (void)recordScreenBlank {
    // 0.0.114: a blank event used to tear the ball down with no diagnostic at
    // all, which made the whole class of "the ball disappeared" reports
    // undiagnosable. Record the reason first, then hide.
    [self reportWindow:@"hide:screen-blank"];
    self.authenticatedSession=NO; [self hide];
}
- (void)syncRotation {
    // The panel is a sibling, not a rotation/visibility gate for the image leaf.
    // 2.22: judged by the window the BUBBLE is in, not by our own window - on the
    // lock screen the bubble lives in the cover sheet while our window is not used.
    BOOL visible=self.bubble.window && self.bubble.window.alpha>=0.01 &&
        self.bubble && !self.bubble.hidden && self.bubble.alpha>=0.01 &&
        self.bubbleImage && !self.bubbleImage.hidden && self.bubbleImage.alpha>=0.01 && self.bubbleImage.image!=nil;
    LMVEasterUpdateRotation(self.bubbleImage.layer,visible,self.panel!=nil,
        self.displayControls.enabled && self.displayControls.rotationEnabled,self.displayControls.rotationSpeed);
}
- (void)hide {
    // Hide first so closePanel cannot briefly restart rotation while tearing down.
    self.window.hidden = YES;
    // 2.22: an embedded bubble is not covered by our own window's hidden flag.
    if (self.embedHost && self.bubble.superview == self.embedHost) {
        [self.bubble removeFromSuperview];
    }
    self.embedHost = nil;
    [self syncRotation]; [self closePanel];
    [self.timer invalidate]; self.timer = nil;
}
- (void)keyboard:(NSNotification *)notification {
    CGRect frame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    UIView *root = self.window.rootViewController.viewIfLoaded;
    CGFloat top = 0;
    if (root && ![notification.name isEqualToString:UIKeyboardWillHideNotification] && !CGRectIsEmpty(frame)) {
        CGRect local = [root convertRect:frame fromCoordinateSpace:(self.window.screen ?: UIScreen.mainScreen).coordinateSpace];
        if (CGRectGetMinY(local) < CGRectGetMaxY(root.bounds) - 1) top = CGRectGetMinY(local);
    }
    if (self.keyboardTop == top) return;
    self.keyboardTop = top;
    if (!self.panel) return;
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    [UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionBeginFromCurrentState animations:^{ [self layout]; } completion:nil];
}
- (void)editingEnded:(NSNotification *)notification {
    UIView *field = notification.object;
    if ([field isKindOfClass:UIView.class] && field.window == self.window) [self restoreKey];
}
// Hand key status back without touching any other window state.
- (void)restoreKey {
    if (!self.window.isKeyWindow) return;
    UIWindow *previous = self.foreignKey;
    if (!previous || previous == self.window || previous.hidden || previous.windowScene != self.window.windowScene || !previous.canBecomeKeyWindow) previous = self.hostWindow;
    if (previous && previous != self.window && !previous.hidden && previous.canBecomeKeyWindow) [previous makeKeyWindow];
    else [self.window resignKeyWindow];
    NSString *keyReason = [NSString stringWithFormat:@"key-restored to=%@", previous ? NSStringFromClass(previous.class) : @"none"];
    LMVEasterWindowDiagnostic(keyReason);
}
- (void)invalidatePhysicalSnapshot {
    // 1.65: keep physicalWindows. It is only the window OBJECT list, and the
    // objects live for the whole session; nulling it here made the host probe
    // read zero on almost every tick, so the 1.64 build fell back to the
    // one-second audit and felt slower than the old poll.
    self.physicalSnapshot=nil; self.physicalProbes=nil;
}
- (void)retuneVisibilityTimer {
    if (!self.visibilityTimer) return;
    // 2.10: A HIDDEN EGG DOES NOT NEED 20 Hz TO STAY HIDDEN.
    // This tick is what notices "the desktop came back", but while the ball is hidden
    // its answer is always the same one: not now. 5 Hz is four times cheaper and is
    // still faster than app exit (the cross-fade alone is ~300 ms) and far faster
    // than a Control Center swipe or an unlock.
    BOOL hidden=!self.window || self.window.hidden || self.window.alpha<0.01;
    NSTimeInterval want=hidden?0.2:0.05;
    if (fabs(self.visibilityTimer.timeInterval-want)<0.001) return;
    [self.visibilityTimer invalidate];
    __weak typeof(self) weakSelf=self;
    self.visibilityTimer=[NSTimer timerWithTimeInterval:want repeats:YES block:^(NSTimer *timer) { [weakSelf visibilityTick]; }];
    [NSRunLoop.mainRunLoop addTimer:self.visibilityTimer forMode:NSRunLoopCommonModes];
}
- (void)visibilityTick {
    if (!self.ready || self.pending) return;
    [self retuneVisibilityTimer];
    // 1.65: live 20 Hz host probe over the retained window objects.
    NSUInteger hostMask = LMVEasterQuickHostMask(self.physicalWindows);
    if (hostMask != self.lastHostSignature) {
        self.lastHostSignature = hostMask;
        self.physicalSnapshot = nil; self.lastPhysicalCheck = 0;
    }
    uint64_t blank=1,locked=1;
    BOOL blankKnown=LMVBlankToken>=0 && notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK;
    BOOL lockKnown=LMVLockToken>=0 && notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK;
    NSArray *snapshot=self.physicalSnapshot?LMVEasterPhysicalSnapshot(self.physicalWindows,self.physicalProbes,
        LMVEasterForeground(),blankKnown,blank,lockKnown,locked):nil;
    BOOL tracking=[NSRunLoop.mainRunLoop.currentMode isEqualToString:UITrackingRunLoopMode];
    // 1.74: keep the image rotation in step with the ball's own visibility on
    // EVERY tick (50 ms), not only when a full refresh happens to run. Hiding
    // stops the animation immediately; showing resumes it from the same phase.
    [self syncRotation];
    if (!LMVEasterPhysicalCheckNeeded(!self.physicalSnapshot,![snapshot isEqual:self.physicalSnapshot],
            CACurrentMediaTime(),self.lastPhysicalCheck,tracking)) return;
    [self refresh];
}
- (void)refresh {
    if (!NSThread.isMainThread || !self.ready) return;
    [self invalidatePhysicalSnapshot];
    if (self.pending) return;
    self.pending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{ self.pending = NO; [self apply]; });
}
- (void)apply {
    CFPreferencesAppSynchronize(LMVEasterPrefs);
    // 0.0.114: the Settings master switch gates the floating egg as well; an
    // absent key means enabled, so an existing installation is unaffected.
    id global=LMVEasterRead(@"GlobalEnabled");
    BOOL globalOn=([global isKindOfClass:NSNumber.class] ? [global boolValue] : YES);
    self.displayControls=LMVEasterDisplayControlsFromValues(globalOn?LMVEasterRead(@"EasterEggEnabled"):@NO,
        LMVEasterRead(@"EasterEggShowOnLockScreen"),LMVEasterRead(@"EasterEggShowOnControlCenter"),
        LMVEasterRead(@"EasterEggShowOnDesktop"),LMVEasterRead(@"EasterEggRotationEnabled"),LMVEasterRead(@"EasterEggRotationSpeed"));
    if (!self.displayControls.enabled) {
        self.generation++; [self hide]; [self.visibilityTimer invalidate]; self.visibilityTimer=nil;
        self.decoded = nil; self.imageKey = nil; self.bubbleImage.image = nil; [self reportWindow:@"disabled"]; return;
    }
    if (!self.visibilityTimer) {
        __weak typeof(self) weakSelf=self;
        // 1.65: 20 Hz. The tick is now a window-list class test, so a collapsed
        // Control Centre is seen in ~50 ms instead of waiting for the audit.
        self.visibilityTimer=[NSTimer timerWithTimeInterval:0.05 repeats:YES block:^(NSTimer *timer) { [weakSelf visibilityTick]; }];
        [NSRunLoop.mainRunLoop addTimer:self.visibilityTimer forMode:NSRunLoopCommonModes];
    }
    uint64_t blank=1,locked=1;
    BOOL blankKnown=LMVBlankToken>=0 && notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK;
    BOOL lockKnown=LMVLockToken>=0 && notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK;
    NSMutableArray<UIWindow *> *windows=[NSMutableArray new];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes)
        if ([scene isKindOfClass:UIWindowScene.class] && scene.activationState!=UISceneActivationStateUnattached)
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
    UIWindow *ncHost=nil,*ccHost=nil,*homeHost=nil,*coverHost=nil;
    NSInteger foreground=LMVEasterForeground();
    // 2.12: the switcher sits over SpringBoard itself, so neither the foreground
    // probe nor the home window's own visibility can tell it apart from "at the
    // desktop". It is asked once per apply and vetoes the home host outright.
    BOOL switcher=LMVEasterSwitcherPresented(windows);
    BOOL appWindow=LMVEasterAppWindowPresent(windows);
    for (UIWindow *window in windows) {
        if(window==self.window || !window.windowScene)continue;
        // 2.18: THE COVER WINDOW ITSELF IS THE EVIDENCE. LMVEasterNCWindowExposed
        // additionally requires the lock-screen CONTENT to be found and on screen,
        // which fails while Face ID scans (the lock UI is morphed/hidden) - that is
        // exactly the state the user reported: nothing on the lock screen, only a
        // flash at unlock. A visible SBCoverSheetWindow is enough to know a cover
        // surface is up; the scene (lock screen vs NC) then comes from the origin.
        if(LMVEasterKnownWindow(window,@[@"SBCoverSheetWindow"]) && !window.hidden &&
           window.alpha>=.01 && window.screen==UIScreen.mainScreen && !coverHost)coverHost=window;
        if(LMVEasterNCWindowExposed(window) && (!ncHost || window.windowLevel>ncHost.windowLevel))ncHost=window;
        if(LMVEasterCCWindowExposed(window) && (!ccHost || window.windowLevel>ccHost.windowLevel))ccHost=window;
        BOOL keyHome=window.isKeyWindow || (self.window.isKeyWindow && self.foreignKey==window);
        // 0.0.117: an exposed Home window that still holds KEY proves no
        // application took the foreground, so it is a valid desktop host even
        // when the frontmost-application probe is unavailable or reports the
        // Notification Centre / a recorder. An app that really came forward owns
        // the key window, so this cannot show the ball over an app.
        // 0.0.118 device log: while the display is RECORDED the frontmost probe
        // reports the recorder (fg=-1) and that window takes key, so the desktop
        // lost its host and the ball vanished (nc=0 cc=0 home=0 captured=1). The
        // user needs the ball visible in the recording, so an exposed Home window
        // is a valid host while the display is captured.
        if(LMVEasterKnownWindow(window,@[@"SBHomeScreenWindow"]) && LMVEasterWindowExposed(window) && !switcher && !appWindow &&
           (foreground==1 || keyHome || LMVEasterScreenCaptured()))homeHost=window;
    }
    // Probe roots plus the physical NC/CC surfaces, never the scrolling module
    // or floating panel descendants. Failed/hidden hosts are probed as well.
    NSMutableArray<UIView *> *probes=[NSMutableArray new];
    for(UIWindow *window in windows) {
        if(window==self.window)continue;
        if(window.rootViewController.viewIfLoaded)[probes addObject:window.rootViewController.viewIfLoaded];
        if(LMVEasterKnownWindow(window,@[@"SBCoverSheetWindow"])) {
            NSUInteger budget=128;UIView *cover=LMVEasterFindCover(window,0,&budget);
            if(cover)[probes addObject:cover];
            for(UIView *child in cover.subviews)if(probes.count<128)[probes addObject:child];
        }
        UIView *overlay=LMVEasterCCOverlay(window);if(overlay)[probes addObject:overlay];
    }
    NSMutableArray<UIWindow *> *physical=[windows mutableCopy];if(self.window)[physical removeObject:self.window];
    self.physicalWindows=physical;self.physicalProbes=probes;
    self.physicalSnapshot=LMVEasterPhysicalSnapshot(physical,probes,foreground,blankKnown,blank,lockKnown,locked);
    self.lastPhysicalCheck=CACurrentMediaTime();
    UIWindow *host=ccHost ?: ncHost ?: coverHost ?: homeHost;
    // 2.14: WHAT MATTERS IS HOW THE EXPOSURE STARTED, NOT WHAT LOCKSTATE SAYS NOW.
    // The ball flashed at the exact instant Face ID recognised the face: the cover
    // sheet stays on screen through the unlock, the flag below used to be "learned"
    // during that animation, and the cover then read as Notification Center. An
    // exposure that BEGAN while unlocked really is NC; one that began on the lock
    // screen is the lock screen, even after Face ID flips lockstate under it. This
    // is recomputed every tick from that origin, so the lockstate pulse Sent while
    // NC is being pulled still cannot make the ball flicker.
    BOOL coverExposed=(ncHost!=nil || coverHost!=nil);
    CFTimeInterval coverNow=CACurrentMediaTime();
    if(coverExposed) {
        if(!self.coverWasExposed) {
            // 2.15: THE UNLOCK ANIMATION DROPS AND RE-ADDS THE COVER. Treating that
            // re-add as a brand-new exposure made it look like a Notification Centre
            // pull over an unlocked app - the ball appeared at the exact instant Face
            // ID recognised the face. Only an exposure that follows at least 150 ms
            // of NO cover can be a real NC pull; a re-add inside that window is the
            // same lock-screen exposure continuing.
            BOOL freshExposure=self.coverGoneAt>0 && coverNow-self.coverGoneAt>=.15;
            self.coverStartedUnlocked=!locked && freshExposure;
            // 2.15: name the decision so the next device log answers "was the
            // re-add treated as a fresh NC pull?" without another round trip.
            [self reportWindow:[NSString stringWithFormat:@"cover-rise locked=%llu fresh=%d nc=%d gap=%.0fms",
                (unsigned long long)locked,(int)freshExposure,(int)self.coverStartedUnlocked,
                self.coverGoneAt>0?(coverNow-self.coverGoneAt)*1000.0:0.0]];
        }
        self.coverGoneAt=0;
    } else {
        if(self.coverGoneAt<=0) {
            self.coverGoneAt=coverNow;
            [self reportWindow:[NSString stringWithFormat:@"cover-fall locked=%llu",(unsigned long long)locked]];
        }
        self.coverStartedUnlocked=NO;
    }
    self.coverWasExposed=coverExposed;
    BOOL authenticated=coverExposed && self.coverStartedUnlocked;
    BOOL legacyAllows=LMVEasterScopePolicy(blankKnown,blank,lockKnown,locked,ncHost!=nil,ccHost!=nil,homeHost!=nil,&authenticated);
    self.authenticatedSession=authenticated;
    // 0.0.117 user policy: a surface that may not present the ball loses it
    // IMMEDIATELY - no grace period and no capture exception. The 0.0.116
    // "host vanished for one frame" regression is handled where it belongs, by
    // judging the Home window itself (below) instead of lingering on screen.
    if(!host){
        [self hide];
        [self reportWindow:[NSString stringWithFormat:@"%@ fg=%ld nc=%d cc=%d home=%d captured=%d cover=%d locked=%llu lockSw=%d",
            @"home-nc-cc:not-visible-or-locked",(long)foreground,ncHost!=nil,ccHost!=nil,homeHost!=nil,LMVEasterScreenCaptured(),
            coverHost!=nil,(unsigned long long)locked,(int)self.displayControls.showOnLockScreen]];
        return;
    }
    CGFloat level=0;UIWindow *blockedWindow=nil;
    BOOL safetyClear=LMVEasterOverlayPriority(windows,self.window,&level,&blockedWindow);
    LMVEasterDisplayScene displayScene=LMVEasterDisplayPolicy(self.displayControls,blankKnown,blank,lockKnown,locked,
        ncHost!=nil,ccHost!=nil,homeHost!=nil,authenticated,legacyAllows,safetyClear);
    // 2.17: Notification Center is a switch of its own (it shares the cover sheet
    // window with the lock screen, so it used to be unconditional). Turning it off
    // must also silence the unlock instant, which is judged as NC.
    if(displayScene==LMVEasterDisplayNC) {
        id ncValue=LMVEasterRead(@"EasterEggShowOnNotificationCenter");
        BOOL ncShown=![ncValue isKindOfClass:NSNumber.class] || [ncValue boolValue];
        if(!ncShown) {[self hide];[self reportWindow:@"nc-disabled"];return;}
    }
    // 2.18: the cover surface is up but the policy could not name a scene (its NC
    // host needs the lock-screen CONTENT, which Face ID hides). Decide from the
    // exposure origin instead, and let each switch gate its own scene.
    if(displayScene==LMVEasterDisplayNone && coverExposed && safetyClear &&
       blankKnown && !blank && !appWindow && !switcher && foreground!=-1) {
        id ncValue=LMVEasterRead(@"EasterEggShowOnNotificationCenter");
        BOOL ncShown=![ncValue isKindOfClass:NSNumber.class] || [ncValue boolValue];
        if(self.coverStartedUnlocked) {
            if(ncShown) displayScene=LMVEasterDisplayNC;
        } else if(self.displayControls.showOnLockScreen) {
            displayScene=LMVEasterDisplayLockScreen;
            [self reportWindow:[NSString stringWithFormat:@"lock-screen-hold locked=%llu fg=%ld ncHost=%d",
                (unsigned long long)locked,(long)foreground,(int)(ncHost!=nil)]];
        }
    }
    if(displayScene==LMVEasterDisplayNone) {
        NSString *reason=blockedWindow?[NSString stringWithFormat:@"blocked class=%@ level=%.0f",NSStringFromClass(blockedWindow.class),blockedWindow.windowLevel]:@"home-nc-cc:not-visible-or-locked";
        [self hide]; [self reportWindow:reason];return;
    }
    if(self.displayScene!=displayScene) { [self hide]; self.displayScene=displayScene; }
    if(self.hostWindow && self.hostWindow!=host)[self closePanel];
    BOOL presentationChanged=self.window.hidden || self.hostWindow!=host || self.window.windowLevel!=level;
    self.hostWindow=host;
    if (self.window && self.window.windowScene != host.windowScene) {
        // A scene change is a real teardown; say so instead of hiding silently.
        [self reportWindow:[NSString stringWithFormat:@"hide:window-scene host=%@",NSStringFromClass(host.class)]];
        [self hide]; self.window = nil; self.bubble = nil; self.bubbleImage = nil;
    }
    if (!self.window) {
        self.window = [[LMVEasterWindow alloc] initWithWindowScene:host.windowScene];
        LMVEasterRoot *root = [LMVEasterRoot new]; root.manager = self;
        self.window.rootViewController = root; self.window.backgroundColor = UIColor.clearColor;
        self.bubble = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 64, 64)];
        self.bubbleImage = [[UIImageView alloc] initWithFrame:self.bubble.bounds];
        self.bubbleImage.contentMode = UIViewContentModeScaleAspectFit; self.bubbleImage.userInteractionEnabled = NO;
        [self.bubble addSubview:self.bubbleImage]; self.bubble.userInteractionEnabled = YES;
        self.bubble.isAccessibilityElement = YES; self.bubble.accessibilityLabel = @"小彩蛋"; self.bubble.accessibilityTraits = UIAccessibilityTraitButton;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(openPanel)]; [tap requireGestureRecognizerToFail:pan];
        [self.bubble addGestureRecognizer:pan]; [self.bubble addGestureRecognizer:tap]; [root.view addSubview:self.bubble]; self.window.bubble = self.bubble;
    }
    self.window.windowLevel = level;
    NSString *path = LMVEasterImagePath(LMVEasterRead(@"EasterEggImage"));
    struct stat info; NSString *key = nil;
    if (path && lstat(path.fileSystemRepresentation, &info) == 0) key = [NSString stringWithFormat:@"%@:%llu:%lld:%lld:%ld", path, (unsigned long long)info.st_ino, (long long)info.st_size, (long long)info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec];
    if (!key) { self.generation++; self.imageKey = nil; self.decoded = nil; self.bubbleImage.image = nil; [self hide]; [self reportWindow:@"hide:image-selection-missing-or-invalid"]; return; }
    if (![self.imageKey isEqualToString:key]) {
        self.imageKey = key; self.decoded = nil; self.frame = 0; self.bubbleImage.image = nil; [self hide]; [self reportWindow:@"hide:image-decode-pending"];
        NSUInteger generation = ++self.generation; __weak typeof(self) weakSelf = self;
        dispatch_async(LMVMaterialQueue(), ^{
            LMVEasterImage *decoded = LMVEasterDecode([NSURL fileURLWithPath:path], NULL);
            dispatch_async(dispatch_get_main_queue(), ^{
                LMVEasterManager *manager = weakSelf;
                if (!manager || generation != manager.generation) return;
                manager.decoded = decoded; [manager refresh];
            });
        }); return;
    }
    if (!self.decoded.frames.count) { [self hide]; [self reportWindow:@"hide:image-decode-unavailable"]; return; }
    if(presentationChanged || ![self.windowReason hasPrefix:@"home-nc-cc host="])
        // 2.20: the host line now describes OUR OWN window as well. "Host found,
        // state says shown, nothing on screen" can only be: hidden, alpha 0, a
        // level below the lock UI, a zero-sized window, or a bubble parked off
        // screen - so all five are printed with the host.
        [self reportWindow:[NSString stringWithFormat:@"home-nc-cc host=%@ level=%.0f scene=%ld win=%.0fx%.0f winLvl=%.0f hid=%d a=%.2f attached=%d isHidden=%d bubble=%.0f,%.0f %.0fx%.0f img=%d",
            NSStringFromClass(host.class),level,(long)host.windowScene.activationState,
            self.window.bounds.size.width,self.window.bounds.size.height,self.window.windowLevel,
            (int)self.window.hidden,self.window.alpha,
            (int)(self.bubble.window==self.window),(int)self.window.isHidden,
            self.bubble.center.x,self.bubble.center.y,
            self.bubble.bounds.size.width,self.bubble.bounds.size.height,(int)(self.bubbleImage.image!=nil)]];
    // 2.22: ON THE LOCK SCREEN A SEPARATE WINDOW CANNOT BE USED. 2.21 proved it on
    // the device: the window reported hid=0 isHidden=0 a=1.00 attached=1 at level
    // 10000012 and still drew nothing, so the suppression is not lifted by a
    // declaration - the system simply does not render a non-system window while
    // locked. The lock-screen video has always worked for the opposite reason: it
    // is a plain subview inside the cover sheet. While the lock screen is the
    // scene the bubble moves into that same hierarchy; everywhere else it stays in
    // its own window and nothing about the desktop/NC/CC path changes.
    UIWindow *embedHost=(displayScene==LMVEasterDisplayLockScreen) ? coverHost : nil;
    UIView *canvas=embedHost ?: self.window.rootViewController.view;
    if (self.bubble.superview != canvas) [canvas addSubview:self.bubble];
    self.embedHost=embedHost;
    self.window.hidden = NO;
    self.bubbleImage.image = self.decoded.frames[self.frame % self.decoded.frames.count]; [self layout]; [self animateFrame]; [self syncRotation];
}
// 2.22: the view the bubble actually lives in. It is normally our own window's
// root view, but on the lock screen the bubble is a subview of the cover sheet
// (see the show block in -apply), and every coordinate below must use THAT space.
- (UIView *)canvas {
    UIView *superview=self.bubble.superview;
    if (superview) return superview;
    return self.window.rootViewController.view;
}
- (CGRect)dragArea {
    UIView *space=[self canvas];
    CGRect bounds = space.bounds;
    UIEdgeInsets safe = space.safeAreaInsets;
    CGRect inset = UIEdgeInsetsInsetRect(bounds, UIEdgeInsetsMake(safe.top + 8, safe.left + 8, safe.bottom + 8, safe.right + 8));
    LMVEasterRect safeRect = { inset.origin.x, inset.origin.y, inset.size.width, inset.size.height };
    LMVEasterRect area = LMVEasterCenterArea(safeRect, LMVEasterSize());
    return CGRectMake(area.x, area.y, area.width, area.height);
}
- (void)layout {
    if (!self.window || !self.bubble) return;
    CGFloat size = LMVEasterSize();CGRect bubbleBounds=CGRectMake(0, 0, size, size);
    if(!CGRectEqualToRect(self.bubble.bounds,bubbleBounds))self.bubble.bounds=bubbleBounds;
    if(!CGRectEqualToRect(self.bubbleImage.frame,bubbleBounds))self.bubbleImage.frame=bubbleBounds;
    CGRect area = [self dragArea];
    CGPoint center=CGPointMake(area.origin.x + area.size.width * self.normalized.x, area.origin.y + area.size.height * self.normalized.y);
    if(!CGPointEqualToPoint(self.bubble.center,center))self.bubble.center=center;
    if (self.panel) {
        UIView *space=[self canvas];
        CGRect bounds = UIEdgeInsetsInsetRect(space.bounds, space.safeAreaInsets);
        CGFloat width = MIN(360, MAX(0, bounds.size.width - 24)), height = MIN(550, MAX(0, bounds.size.height * .65));
        // 0.0.122: optional user width/height. Off by default, so an untouched
        // install keeps exactly the automatic size it had before.
        CGSize sized = LMVEasterResolvedPanelSize(LMVEasterRead(@"EasterPanelSizeEnabled"),
            LMVEasterRead(@"EasterPanelWidthScale"), LMVEasterRead(@"EasterPanelHeightScale"), CGSizeMake(width, height));
        width = MIN(MAX(0, sized.width), MAX(0, bounds.size.width)); height = MAX(0, sized.height);
        // 0.0.122: dragging is re-clamped here, so a panel dragged to the edge stays
        // fully on screen even after a rotation or a size change.
        CGFloat centeredX = CGRectGetMidX(bounds) - width / 2;
        CGFloat centeredY = CGRectGetMidY(bounds) - height / 2;
        CGFloat maxOffsetX = MAX(0, (bounds.size.width - width) / 2);
        CGFloat minOffsetY = CGRectGetMinY(bounds) - centeredY;
        CGFloat maxOffsetY = CGRectGetMaxY(bounds) - height - centeredY;
        self.panelOffset = CGPointMake(LMVEasterPanelClamp(self.panelOffset.x, -maxOffsetX, maxOffsetX),
            LMVEasterPanelClamp(self.panelOffset.y, minOffsetY, MAX(minOffsetY, maxOffsetY)));
        CGFloat x = centeredX + self.panelOffset.x;
        CGFloat y = centeredY + self.panelOffset.y;
        if (self.keyboardTop > 0) {
            // Keep the panel (and its contained prompt) above the keyboard.
            CGFloat limit = self.keyboardTop - 8;
            if (y + height > limit) { y = MAX(CGRectGetMinY(bounds), limit - height); height = MAX(0, MIN(height, limit - y)); }
        }
        // Corner radius follows the setting live, so dragging its slider shows the
        // change on the panel the user is looking at.
        CGFloat corner = LMVEasterResolvedPanelCorner(LMVEasterRead(@"EasterPanelCornerEnabled"),
            LMVEasterRead(@"EasterPanelCorner"), 20.0);
        if (self.panel.view.layer.cornerRadius != corner) self.panel.view.layer.cornerRadius = corner;
        CGRect panelFrame=CGRectMake(x, y, width, height);
        if(!CGRectEqualToRect(self.panel.view.frame,panelFrame))self.panel.view.frame=panelFrame;
    }
}
// 0.0.122: move the whole panel by its title bar. Only the offset is stored; the
// final frame is recomputed (and clamped to the screen) by -layout.
- (void)dragPanel:(UIPanGestureRecognizer *)pan {
    if (!self.panel) return;
    UIView *space = self.window.rootViewController.view;
    CGPoint translation = [pan translationInView:space];
    self.panelOffset = CGPointMake(self.panelOffset.x + translation.x, self.panelOffset.y + translation.y);
    [pan setTranslation:CGPointZero inView:space];
    [self layout];
    // 1.64: remember where the user dropped the panel. Written on gesture end
    // only, so a drag does not hammer the preferences tree every frame.
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        LMVEasterSet(@"EasterPanelOffsetX", @(self.panelOffset.x));
        LMVEasterSet(@"EasterPanelOffsetY", @(self.panelOffset.y));
        // 1.65: flush now, so a respring right after the drag still remembers.
        CFPreferencesAppSynchronize(LMVEasterPrefs);
    }
}
- (void)drag:(UIPanGestureRecognizer *)pan {
    UIView *space=[self canvas];
    CGPoint translation = [pan translationInView:space]; CGRect area = [self dragArea];
    CGPoint point = CGPointMake(MAX(CGRectGetMinX(area), MIN(CGRectGetMaxX(area), self.bubble.center.x + translation.x)), MAX(CGRectGetMinY(area), MIN(CGRectGetMaxY(area), self.bubble.center.y + translation.y)));
    self.normalized = CGPointMake(LMVEasterNormalizedPosition(point.x, area.origin.x, area.size.width), LMVEasterNormalizedPosition(point.y, area.origin.y, area.size.height));
    self.bubble.center = point; [pan setTranslation:CGPointZero inView:space];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        LMVEasterSet(@"EasterEggX", @(self.normalized.x)); LMVEasterSet(@"EasterEggY", @(self.normalized.y));
    }
}
- (void)animateFrame {
    if (self.timer || self.window.hidden || self.decoded.frames.count < 2) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:self.decoded.delays[self.frame % self.decoded.delays.count].doubleValue repeats:NO block:^(NSTimer *timer) {
        LMVEasterManager *manager = weakSelf; if (!manager) return;
        manager.timer = nil;
        if (manager.window.hidden || !manager.decoded.frames.count) return;
        manager.frame = (manager.frame + 1) % manager.decoded.frames.count;
        manager.bubbleImage.image = manager.decoded.frames[manager.frame]; [manager animateFrame];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}
- (void)openPanel {
    if (self.panel || self.window.hidden || self.displayScene==LMVEasterDisplayLockScreen) return;
    LMVEasterPanel *panel = [LMVEasterPanel new]; __weak typeof(self) weakSelf = self;
    panel.close = ^{ [weakSelf closePanel]; };
    self.panel = [[UINavigationController alloc] initWithRootViewController:panel];
    [self syncRotation];
    UIViewController *root = self.window.rootViewController;
    [root addChildViewController:self.panel];
    [self.panel beginAppearanceTransition:YES animated:NO];
    [root.view addSubview:self.panel.view]; [self.panel didMoveToParentViewController:root];
    [self.panel endAppearanceTransition];
    self.panel.view.layer.cornerRadius = LMVEasterResolvedPanelCorner(LMVEasterRead(@"EasterPanelCornerEnabled"),
        LMVEasterRead(@"EasterPanelCorner"), 20.0);
    self.panel.view.layer.cornerCurve = kCACornerCurveContinuous; self.panel.view.clipsToBounds = YES;
    // 0.0.122: dragging lives on the TITLE BAR, so the panel can be moved without
    // stealing the table's own scrolling gesture.
    UIPanGestureRecognizer *panelDrag = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)];
    panelDrag.maximumNumberOfTouches = 1;
    [self.panel.navigationBar addGestureRecognizer:panelDrag];
    self.window.panel = self.panel.view; [self layout];
    // Own key while the panel is open so contained rename/switch prompts get a keyboard.
    if (!self.window.isKeyWindow && self.window.canBecomeKeyWindow) [self.window makeKeyWindow];
}
- (void)closePanel {
    if (!self.panel) return;
    LMVEasterPanel *root=[self.panel.viewControllers.firstObject isKindOfClass:LMVEasterPanel.class]?(LMVEasterPanel *)self.panel.viewControllers.firstObject:nil;
    [root prepareForClose];
    [self.window endEditing:YES]; [self restoreKey];
    [self.panel beginAppearanceTransition:NO animated:NO];
    [self.panel willMoveToParentViewController:nil]; [self.panel.view removeFromSuperview];
    [self.panel removeFromParentViewController]; [self.panel endAppearanceTransition];
    self.panel = nil; self.window.panel = nil;
    [self syncRotation];
}
@end
