#pragma once
// Import after Lock/Desktop/CC. Independent of EasterEnabled/bubble visibility.
// iOS 16.0 (20A5303f) classdump evidence (not claims about other OS builds):
// https://raw.githubusercontent.com/lechium/iPhoneOS_16.0_20A5303f/master/System/Library/PrivateFrameworks/UIKitCore/_UIContextMenuListView.h
// https://raw.githubusercontent.com/lechium/iPhoneOS_16.0_20A5303f/master/System/Library/PrivateFrameworks/UIKitCore/_UIContextMenuPresentationController.h
// _UIContextMenuActionsListView/Controller are NOT present in that UIKitCore
// tree; never install guessed aliases. SBIconController's local vendor header
// declares NSObject, not UIViewController: no new SBIconController hooks here.
#import <stdbool.h>

static void LMVHomeMenuVideoRefresh(BOOL reload);
static void LMVHomeMenuVideoSuspend(void);
static BOOL LMVHomeMenuEnabled,LMVHomeMenuPrefsKnown,LMVHomeMenuPending;
static NSString *LMVHomeMenuPath,*LMVHomeMenuRevision;
static BOOL LMVHomeMenuSpringBoard(void) {
    return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];
}
static BOOL LMVHomeMenuEnvironment(void) {
    uint64_t blank=1,locked=1;
    return LMVInitialized && LMVLaunchReady && NSThread.isMainThread &&
        LMVHomeMenuSpringBoard() && LMVDesktopForeground()==1 &&
        LMVBlankToken>=0 && LMVLockToken>=0 &&
        notify_get_state(LMVBlankToken,&blank)==NOTIFY_STATUS_OK &&
        notify_get_state(LMVLockToken,&locked)==NOTIFY_STATUS_OK && !blank && !locked;
}
// Getter ABI is inspected without invoking an unknown selector. Object return
// encodings may contain a class name; runtime method_copyReturnType is '@'.
static id LMVHomeMenuGet(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    Method method=object?class_getInstanceMethod(object_getClass(object),selector):NULL;
    if(!method || method_getNumberOfArguments(method)!=2)return nil;
    char *type=method_copyReturnType(method);BOOL okay=type && type[0]=='@';free(type);
    char *selfType=method_copyArgumentType(method,0),*cmdType=method_copyArgumentType(method,1);
    okay=okay && selfType && !strcmp(selfType,@encode(id)) && cmdType && !strcmp(cmdType,@encode(SEL));free(selfType);free(cmdType);
    return okay?((id(*)(id,SEL))objc_msgSend)(object,selector):nil;
}
static UIView *LMVHomeMenuBranch(UIView *view,UIView *parent) {
    for(NSUInteger n=0;view && n<12;n++,view=view.superview)if(view.superview==parent)return view;
    return nil;
}
static BOOL LMVHomeMenuVisible(UIView *view) {
    UIWindow *window=view.window;
    if(!window || window.screen!=UIScreen.mainScreen || !LMVLockVideoRectValid(view.bounds))return NO;
    NSUInteger depth=0;
    for(UIView *node=view;node;node=node.superview)if(++depth>24 || node.hidden || node.alpha<.01)return NO;
    CGRect exposed=[view convertRect:view.bounds toView:window];
    return !CGRectIsEmpty(CGRectIntersection(exposed,window.bounds));
}
static BOOL LMVHomeMenuIconSource(id presentation) {
    id preview=LMVHomeMenuGet(presentation,@"sourcePreview");
    if(![preview isKindOfClass:UITargetedPreview.class])return NO;
    UIView *view=LMVHomeMenuGet(preview,@"view");
    if(![view isKindOfClass:UIView.class] || !LMVDesktopHomeWindow(view.window) || !LMVHomeMenuVisible(view))return NO;
    Class icon=NSClassFromString(@"SBIconView");
    if(!icon || ![icon isSubclassOfClass:UIView.class])return NO;
    for(NSUInteger n=0;view && n<12;n++,view=view.superview)if([view isKindOfClass:icon])return YES;
    return NO; // Snapshot/unknown source is not evidence of a Home icon.
}
// 1.32: the two shapes this channel could not recognise on the reported device.
// The 1.30 log pins BOTH at once:
//
//   SBFloatingDockWindow@0,0,430,932{ ... _UIContextMenuContainerView^UIVisualEffectView,
//     _UIContextMenuPlatterTransitionView@0,0,430,932{ _UIContextMenuView{
//       _UIContextMenuListView{ ... }}}}
//
// - the dock's long-press menu lives in SBFloatingDockWindow, NOT in the Home
//   window, so the icon-source test above - which requires LMVDesktopHomeWindow -
//   could never accept it, no matter what the presentation record said;
// - and that menu is presented through _UIContextMenuPlatterTransitionView, so the
//   presentation-controller hooks that create the record never fire either.
// Either one alone leaves the menu with no video. Both are replaced by the same
// idea: identify a Home-scope menu from the LIST'S OWN ANCESTRY - under the Home
// window or under the floating dock window. An in-app menu has neither, and
// LMVHomeMenuEnvironment still requires the desktop to be frontmost, so the scope
// stays tight.
static BOOL LMVHomeMenuHomeScope(UIView *list) {
    UIWindow *host=list.window;
    if(!host || host.screen!=UIScreen.mainScreen || host.hidden || host.alpha<.01) return NO;
    Class dock=NSClassFromString(@"SBFloatingDockWindow");
    if(dock && [host isKindOfClass:dock]) return YES;
    return LMVDesktopHomeWindow(host);
}
@interface LMVHomeMenuRecord:NSObject
@property(nonatomic,weak) id presentation;
@property(nonatomic,weak) UIView *menu;
@property(nonatomic) BOOL known,active;
@end
@implementation LMVHomeMenuRecord @end
static char LMVHomeMenuRecordKey,LMVHomeMenuLeaseKey;
static NSHashTable<LMVHomeMenuRecord *> *LMVHomeMenuRecords;
static LMVHomeMenuRecord *LMVHomeMenuOwner(UIView *list) {
    NSUInteger budget=8;
    for(LMVHomeMenuRecord *record in LMVHomeMenuRecords) {
        if(!budget--)break;
        if(!record.known || !record.active || !record.presentation || !record.menu)continue;
        for(UIView *node=list;node;node=node.superview) {
            if(node==record.menu) {
                // 1.32: an icon source OUTSIDE the Home window - i.e. an icon on the
                // floating dock - is no longer a rejection. It only means this
                // presentation record cannot PROVE the scope by itself. Returning nil
                // here is exactly what kept the dock menu unbound while the desktop
                // menu worked: the record existed, the list matched, and the very
                // last test threw it away because the dock icon's window is
                // SBFloatingDockWindow rather than SBHomeScreenWindow. Break instead,
                // so the ancestry test below can accept it.
                if(LMVHomeMenuIconSource(record.presentation)) return record;
                break;
            }
            if(node==list.window)break;
        }
    }
    // 1.32: ancestry fallback - see LMVHomeMenuHomeScope. A platter-era menu has no
    // usable record at all, and a dock menu's record (when one exists) is rejected
    // by the icon-source test above because its icon does not live in the Home
    // window. One shared scope record is enough: the rest of the channel only keys
    // off the list identity it carries.
    if(LMVHomeMenuVisible(list) && LMVHomeMenuHomeScope(list)) {
        static LMVHomeMenuRecord *scopeRecord;
        if(!scopeRecord) scopeRecord=[LMVHomeMenuRecord new];
        scopeRecord.known=YES;scopeRecord.active=YES;scopeRecord.menu=list;
        return scopeRecord;
    }
    return nil;
}
// Only the documented list.backgroundView (UIVisualEffectView) may be leased.
// Audit this tiny background subtree on a coalesced local policy turn, not the
// collection/cells/cards/window tree. Unknown or foreground-bearing fails shut.
static BOOL LMVHomeMenuPureBackground(UIView *view) {
    if(![view isKindOfClass:UIVisualEffectView.class] || view.layer.mask)return NO;
    NSMutableArray<UIView *> *pending=[NSMutableArray arrayWithObject:view];NSUInteger budget=40;
    while(pending.count && budget--) {
        UIView *node=pending.lastObject;[pending removeLastObject];
        if([node isKindOfClass:UILabel.class] || [node isKindOfClass:UITextView.class] ||
           [node isKindOfClass:UIControl.class] || [node isKindOfClass:UIScrollView.class] ||
           [node isKindOfClass:UIImageView.class] || node.gestureRecognizers.count || node.subviews.count>12)return NO;
        [pending addObjectsFromArray:node.subviews];
    }
    return pending.count==0;
}
@interface LMVHomeMenuMaterialLease:NSObject
@property(nonatomic,weak) UIView *view,*parent;
@property(nonatomic) float baselineOpacity;
@property(nonatomic) BOOL applied;
- (void)restore;
@end
@implementation LMVHomeMenuMaterialLease
- (void)restore {
    UIView *view=self.view;
    if(view && objc_getAssociatedObject(view,&LMVHomeMenuLeaseKey)==self) {
        if(self.applied && view.layer.opacity==0)view.layer.opacity=self.baselineOpacity;
        objc_setAssociatedObject(view,&LMVHomeMenuLeaseKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    self.applied=NO;
}
- (void)dealloc {[self restore];}
@end
@interface LMVHomeMenuVideoHost:UIView
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@end
@implementation LMVHomeMenuVideoHost
- (instancetype)initWithFrame:(CGRect)frame {
    if((self=[super initWithFrame:frame])) {
        self.userInteractionEnabled=NO;self.isAccessibilityElement=NO;self.accessibilityElementsHidden=YES;
        self.opaque=NO;self.backgroundColor=UIColor.clearColor;self.clipsToBounds=YES;
    }
    return self;
}
- (void)layoutSubviews {[super layoutSubviews];[self.playback layoutInBounds:self.bounds];}
@end
@interface LMVHomeMenuVideoManager:NSObject
@property(nonatomic,strong) LMVLockVideoPlayback *playback;
@property(nonatomic,strong) LMVHomeMenuVideoHost *host;
@property(nonatomic,strong) LMVHomeMenuMaterialLease *lease;
@property(nonatomic,weak) UIView *list,*material,*clip,*collection;
@property(nonatomic,weak) LMVHomeMenuRecord *record;
@property(nonatomic) BOOL updating;
@property(nonatomic) CFTimeInterval lastAudit;
- (void)detach;
- (void)updateList:(UIView *)list;
- (void)syncGeometry;
@end
static LMVHomeMenuVideoManager *LMVHomeMenuVideo;
static void LMVHomeMenuRequestUpdate(void);
// 1.32: find the menu's own material without trusting a private getter name. The
// platter-era list keeps its blur in a plain UIView wrapper rather than behind
// `backgroundView`, so walk the list's OWN subtree - bounded, and still filtered by
// the existing background-only audit before anything is leased.
static UIView *LMVHomeMenuMaterialIn(UIView *root) {
    NSMutableArray<UIView *> *pending=[NSMutableArray arrayWithObject:root];
    NSUInteger budget=80;
    while(pending.count && budget--) {
        UIView *node=pending.firstObject;[pending removeObjectAtIndex:0];
        if(node!=root && [node isKindOfClass:UIVisualEffectView.class] && !node.layer.mask) return node;
        [pending addObjectsFromArray:node.subviews];
    }
    return nil;
}
// Read only confirmed list getters, check all ancestry/order before UI creation.
static BOOL LMVHomeMenuSurface(UIView *list,UIView **materialOut,UIView **clipOut,UIView **collectionOut) {
    Class cls=NSClassFromString(@"_UIContextMenuListView");
    if(!cls || ![list isKindOfClass:cls] || !LMVHomeMenuVisible(list))return NO;
    UIView *material=LMVHomeMenuGet(list,@"backgroundView"),*clip=LMVHomeMenuGet(list,@"clippingView");
    UIView *collection=LMVHomeMenuGet(list,@"collectionView");
    // 1.32: a getter miss is no longer a rejection - locate the material in the
    // list's own subtree instead. Everything below still has to hold for it to be
    // used, so this widens the accepted SHAPE without weakening the audit.
    if(![material isKindOfClass:UIVisualEffectView.class]) material=LMVHomeMenuMaterialIn(list);
    if(![material isKindOfClass:UIVisualEffectView.class] || ![material isDescendantOfView:list] ||
       !LMVHomeMenuPureBackground(material) || material.hidden ||
       !LMVLockVideoRectValid(material.bounds))return NO;
    // The clipping/collection pair is checked only when both getters answered. A
    // shape that does not expose them is judged by the material and its siblings.
    if([clip isKindOfClass:UIView.class] && [collection isKindOfClass:UICollectionView.class]) {
        if(![clip isDescendantOfView:list] || ![collection isDescendantOfView:clip])return NO;
    } else {clip=nil;collection=nil;}
    UIView *parent=material.superview;
    if(!parent || parent.subviews.count>20)return NO;
    UIView *foreground=collection ? LMVHomeMenuBranch(collection,parent) : nil;
    if(!foreground) {
        // No collection reference: a visible sibling ABOVE the material is the same
        // evidence the original order check was asking for. A material that is the
        // topmost sibling is not a menu background and stays rejected.
        for(UIView *sibling in parent.subviews.reverseObjectEnumerator)
            if(sibling!=material && !sibling.hidden && sibling.alpha>=.01) {foreground=sibling;break;}
    }
    if(!foreground || foreground==material)return NO;
    NSUInteger back=[parent.subviews indexOfObjectIdenticalTo:material],front=[parent.subviews indexOfObjectIdenticalTo:foreground];
    LMVHomeMenuMaterialLease *lease=objc_getAssociatedObject(material,&LMVHomeMenuLeaseKey);
    CGFloat materialAlpha=lease.applied && lease.parent==parent && material.layer.opacity==0?lease.baselineOpacity:material.alpha;
    if(back==NSNotFound || front==NSNotFound || back>=front || materialAlpha<.01 ||
       (material.layer.opacity<.01 && !(lease.applied && lease.parent==parent && lease.baselineOpacity>=.01)))return NO;
    if(materialOut)*materialOut=material;if(clipOut)*clipOut=clip;if(collectionOut)*collectionOut=collection;
    return YES;
}
static __weak UIView *LMVHomeMenuObservedList;
@implementation LMVHomeMenuVideoManager
- (instancetype)init {
    if(!LMVHomeMenuEnvironment())return nil;
    if((self=[super init])) {
        _playback=[LMVLockVideoPlayback new];_playback.target=@"HomeMenu";_playback.persistentPosterEnabled=NO;
        _host=[[LMVHomeMenuVideoHost alloc] initWithFrame:CGRectZero];_host.playback=_playback;
        _playback.renderLayer.name=@"com.minis.lockmessagevideo.home-menu.render";
        [_host.layer addSublayer:_playback.renderLayer];
        __weak typeof(self) weakSelf=self;
        _playback.didChange=^{if(weakSelf && !weakSelf.updating)LMVHomeMenuRequestUpdate();};
    }
    return self;
}
- (void)dealloc {[_lease restore];[_host removeFromSuperview];}
- (void)detach {
    [self.lease restore];self.lease=nil;[self.host removeFromSuperview];self.host.hidden=YES;
    if(self.playback.wantsPlayback)[self.playback setVisible:NO];
    self.material=nil;self.clip=nil;self.collection=nil;self.record=nil;
}
- (void)syncGeometry {
    UIView *material=self.material,*parent=material.superview;
    if(!material || self.host.superview!=parent)return;
    [CATransaction begin];[CATransaction setDisableActions:YES];
    // Same sibling coordinate system and exact local bounds/transform, never a
    // convertRect bounding-box enlargement when UIKit scales the menu platter.
    if(!CGRectEqualToRect(self.host.layer.bounds,material.layer.bounds))self.host.layer.bounds=material.layer.bounds;
    if(!CGPointEqualToPoint(self.host.layer.anchorPoint,material.layer.anchorPoint))self.host.layer.anchorPoint=material.layer.anchorPoint;
    if(!CGPointEqualToPoint(self.host.layer.position,material.layer.position))self.host.layer.position=material.layer.position;
    if(!CATransform3DEqualToTransform(self.host.layer.transform,material.layer.transform))self.host.layer.transform=material.layer.transform;
    if(self.host.layer.cornerRadius!=material.layer.cornerRadius)self.host.layer.cornerRadius=material.layer.cornerRadius;
    self.host.layer.masksToBounds=YES;
    if(!CGRectEqualToRect(self.playback.renderLayer.frame,self.host.bounds))[self.playback layoutInBounds:self.host.bounds];
    [CATransaction commit];
}
- (void)updateList:(UIView *)list {
    if(self.updating)return;self.updating=YES;
    UIView *material=nil,*clip=nil,*collection=nil;
    LMVHomeMenuRecord *record=LMVHomeMenuOwner(list);
    BOOL allowed=LMVHomeMenuEnabled && LMVHomeMenuPath.length && LMVHomeMenuRevision.length &&
        LMVHomeMenuEnvironment() && record && LMVHomeMenuSurface(list,&material,&clip,&collection);
    if(!allowed) {
        // 2.15: this channel used to fail silently. Name the reason and the class
        // we were handed, so a covering tweak that reshapes the menu can be told
        // apart from "switch off" or "no material selected".
        if(LMVDiagnosticsEnabled.load()) {
            NSString *line=[NSString stringWithFormat:@"home-menu-nocard list=%@ enabled=%d path=%d env=%d record=%d surface=%d",
                NSStringFromClass(list.class),(int)LMVHomeMenuEnabled,(int)(LMVHomeMenuPath.length>0),
                (int)LMVHomeMenuEnvironment(),(int)(record!=nil),(int)(material!=nil)];
            static NSString *lastLine=nil;
            if(![line isEqualToString:lastLine]) {lastLine=[line copy];LMVDiagnostic(line);}
        }
        [self detach];self.updating=NO;return;
    }
    self.list=list;
    if(self.material!=material || self.record!=record || self.lease.parent!=material.superview)[self detach];
    self.material=material;self.clip=clip;self.collection=collection;self.record=record;
    BOOL changed=![self.playback.path isEqualToString:LMVHomeMenuPath] || ![self.playback.revision isEqualToString:LMVHomeMenuRevision];
    if(changed) {
        [self.lease restore];self.lease=nil;[self.host removeFromSuperview];
        [self.playback selectPath:LMVHomeMenuPath revision:LMVHomeMenuRevision];
    }
    if(!self.playback.wantsPlayback)[self.playback setVisible:YES];
    // Poster is never a substitute for a live menu. Retain original blur until
    // the independent decoder actually has a video frame; errors restore it.
    BOOL live=self.playback.player && self.playback.playerLayer.readyForDisplay && !self.playback.error;
    self.playback.posterLayer.hidden=YES;
    if(!live) {[self.lease restore];self.lease=nil;[self.host removeFromSuperview];self.host.hidden=YES;self.updating=NO;return;}
    UIView *parent=material.superview;
    if(self.host.superview!=parent)[parent insertSubview:self.host aboveSubview:material];
    else {
        NSUInteger own=[parent.subviews indexOfObjectIdenticalTo:self.host],back=[parent.subviews indexOfObjectIdenticalTo:material];
        if(own!=back+1)[parent insertSubview:self.host aboveSubview:material];
    }
    [self syncGeometry];
    if(!self.lease) {
        if(objc_getAssociatedObject(material,&LMVHomeMenuLeaseKey)) {[self detach];self.updating=NO;return;}
        self.lease=[LMVHomeMenuMaterialLease new];self.lease.view=material;self.lease.parent=parent;
        self.lease.baselineOpacity=material.layer.opacity;
        objc_setAssociatedObject(material,&LMVHomeMenuLeaseKey,self.lease,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if(material.layer.opacity!=0) {self.lease.baselineOpacity=material.layer.opacity;material.layer.opacity=0;}
    self.lease.applied=YES;if(self.host.hidden)self.host.hidden=NO;
    if(LMVDiagnosticsEnabled.load()) {
        UIView *containerView=self.host.superview;
        NSInteger index=containerView?(NSInteger)[containerView.subviews indexOfObjectIdenticalTo:self.host]:-1;
        NSString *line=[NSString stringWithFormat:@"home-menu material=%@ %.0fx%.0f host=%.0fx%.0f container=%@ idx=%ld live=%d",
            NSStringFromClass(material.class),material.bounds.size.width,material.bounds.size.height,
            self.host.bounds.size.width,self.host.bounds.size.height,
            containerView?NSStringFromClass(containerView.class):@"none",(long)index,
            (int)(self.playback.player!=nil && self.playback.playerLayer.readyForDisplay && !self.playback.error)];
        static NSString *lastLine=nil;
        if(![line isEqualToString:lastLine]) {lastLine=[line copy];LMVDiagnostic(line);}
    }
    self.updating=NO;
}
@end
static void LMVHomeMenuRequestUpdate(void) {
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady || LMVHomeMenuPending)return;
    LMVHomeMenuPending=YES;
    dispatch_async(dispatch_get_main_queue(),^{LMVHomeMenuPending=NO;LMVHomeMenuVideoRefresh(NO);});
}
static void LMVHomeMenuVideoRefresh(BOOL reload) {
    if(!NSThread.isMainThread || !LMVInitialized)return;
    if(reload || !LMVHomeMenuPrefsKnown) {
        LMVHomeMenuPrefsKnown=YES;
        id enabled=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("HomeMenuBackgroundEnabled"),kLMVPrefsID);
        // 0.0.114: master switch, inline (see LMVLockVideo.h).
        id globalValue=(__bridge_transfer id)CFPreferencesCopyAppValue(CFSTR("GlobalEnabled"),kLMVPrefsID);
        LMVHomeMenuEnabled=(![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]) &&
            [enabled isKindOfClass:NSNumber.class] && [enabled boolValue];
        LMVHomeMenuPath=LMVCCSelectedPath(@"HomeMenuVideo");
        LMVHomeMenuRevision=LMVLockVideoRevision(LMVHomeMenuPath);
    }
    if(!LMVHomeMenuEnabled || !LMVHomeMenuPath.length || !LMVHomeMenuRevision.length) {
        [LMVHomeMenuVideo detach];if(LMVHomeMenuVideo.playback.path)[LMVHomeMenuVideo.playback clear];return;
    }
    UIView *list=LMVHomeMenuObservedList;
    if(!LMVHomeMenuEnvironment() || !LMVHomeMenuOwner(list) || !LMVHomeMenuSurface(list,NULL,NULL,NULL)) {
        [LMVHomeMenuVideo detach];return;
    }
    // Hook install/preferences/launch alone never construct UI or a player.
    if(!LMVHomeMenuVideo)LMVHomeMenuVideo=[LMVHomeMenuVideoManager new];
    [LMVHomeMenuVideo updateList:list];
}
static void LMVHomeMenuVideoSuspend(void) {
    if(!NSThread.isMainThread)return;
    [LMVHomeMenuVideo detach];LMVHomeMenuObservedList=nil;
    for(LMVHomeMenuRecord *record in LMVHomeMenuRecords)record.active=NO;
}
// Observe confirmed presentation AFTER original. No singleton or loadView call.
static void LMVHomeMenuPresentation(id object,BOOL active) {
    if(!NSThread.isMainThread || !LMVHomeMenuSpringBoard())return;
    LMVHomeMenuRecord *record=objc_getAssociatedObject(object,&LMVHomeMenuRecordKey);
    if(!record && active && LMVHomeMenuEnvironment() && LMVHomeMenuIconSource(object)) {
        record=[LMVHomeMenuRecord new];record.presentation=object;
        objc_setAssociatedObject(object,&LMVHomeMenuRecordKey,record,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if(!LMVHomeMenuRecords)LMVHomeMenuRecords=[NSHashTable weakObjectsHashTable];[LMVHomeMenuRecords addObject:record];
    }
    if(!record)return;
    record.known=YES;record.active=active;record.menu=LMVHomeMenuGet(object,@"menuView");
    if(!active && LMVHomeMenuVideo.record==record) {[LMVHomeMenuVideo detach];LMVHomeMenuObservedList=nil;}
    if(active) {
        // The header documents currentListView; read only already attached UI.
        UIView *list=LMVHomeMenuGet(record.menu,@"currentListView");
        if([list isKindOfClass:UIView.class] && list.window)LMVHomeMenuObservedList=list;
        LMVHomeMenuRequestUpdate();
    }
}
static void (*LMVHomeMenuOriginalLayout)(id,SEL),(*LMVHomeMenuOriginalMove)(id,SEL);
static void (*LMVHomeMenuOriginalWillBegin)(id,SEL),(*LMVHomeMenuOriginalDismiss)(id,SEL);
static void (*LMVHomeMenuOriginalDidEnd)(id,SEL,bool);
// 1.35 note: this file deliberately does NOT notify the desktop channel when a menu
// appears. The desktop decides for itself whether the dock strip must be vacated
// (LMVDesktopContextMenuUp), which keeps this module free of a compile-time
// dependency on LMVDesktopVideo.h. The CI harness compiles THIS header on its own
// with clang, so any reference to a desktop symbol fails the build there.
static void LMVHomeMenuHookLayout(id object,SEL selector) {
    LMVHomeMenuOriginalLayout(object,selector);
    if(!NSThread.isMainThread || !LMVInitialized || !LMVLaunchReady || !LMVHomeMenuEnabled)return;
    if(LMVHomeMenuVideo.list==object && LMVHomeMenuVideo.host.superview) {
        if(!LMVHomeMenuEnvironment() || !LMVHomeMenuOwner(object)) {[LMVHomeMenuVideo detach];return;}
        [LMVHomeMenuVideo syncGeometry];
        CFTimeInterval now=CACurrentMediaTime();
        if(now-LMVHomeMenuVideo.lastAudit>=.25) {LMVHomeMenuVideo.lastAudit=now;LMVHomeMenuRequestUpdate();}
        return;
    }
    if(LMVHomeMenuOwner(object)) {LMVHomeMenuObservedList=object;LMVHomeMenuRequestUpdate();}
}
static void LMVHomeMenuHookMove(id object,SEL selector) {
    LMVHomeMenuOriginalMove(object,selector);
    if(!NSThread.isMainThread)return;
    if(LMVHomeMenuVideo.list==object && !((UIView *)object).window) {
        [LMVHomeMenuVideo detach];if(LMVHomeMenuObservedList==object)LMVHomeMenuObservedList=nil;
    }
    if(((UIView *)object).window && LMVHomeMenuOwner(object)) {LMVHomeMenuObservedList=object;LMVHomeMenuRequestUpdate();}
}
static void LMVHomeMenuHookWillBegin(id object,SEL selector) {LMVHomeMenuOriginalWillBegin(object,selector);LMVHomeMenuPresentation(object,YES);}
static void LMVHomeMenuHookDidEnd(id object,SEL selector,bool completed) {LMVHomeMenuOriginalDidEnd(object,selector,completed);LMVHomeMenuPresentation(object,completed);}
static void LMVHomeMenuHookDismiss(id object,SEL selector) {LMVHomeMenuOriginalDismiss(object,selector);LMVHomeMenuPresentation(object,NO);}
// _Bool in classdump is C bool ('B'), NOT a guessed BOOL ('c' on some ABIs).
static BOOL LMVHomeMenuHookMatches(Class cls,SEL selector,BOOL hasBool) {
    Method method=class_getInstanceMethod(cls,selector);
    if(!method || method_getNumberOfArguments(method)!=(hasBool?3U:2U))return NO;
    char *result=method_copyReturnType(method),*selfType=method_copyArgumentType(method,0),*cmdType=method_copyArgumentType(method,1);
    BOOL okay=result && !strcmp(result,@encode(void)) && selfType && !strcmp(selfType,@encode(id)) && cmdType && !strcmp(cmdType,@encode(SEL));
    free(result);free(selfType);free(cmdType);
    if(hasBool) {char *arg=method_copyArgumentType(method,2);okay=okay && arg && !strcmp(arg,@encode(bool));free(arg);}
    return okay;
}
static void LMVHomeMenuVideoInstallHooks(void) {
    static BOOL installed;if(installed || !LMVHomeMenuSpringBoard())return;
    // 1.32: the LIST hooks are the ones that actually find the menu, and they now
    // install on their own. Until this change the whole install aborted unless
    // _UIContextMenuPresentationController existed AND exposed all three
    // presentation methods - a shape the platter-era UIKit does not use for the
    // Home/dock long-press menu. Requiring it took the list hooks down with it, so
    // a menu that WAS on screen never had its list observed. The presentation hooks
    // are kept as an OPTIONAL extra: on builds that still use them they supply the
    // icon source; on builds that do not, the ancestry path in LMVHomeMenuOwner
    // identifies the menu.
    Class list=NSClassFromString(@"_UIContextMenuListView");
    if(!list || ![list isSubclassOfClass:UIView.class])return;
    if(!LMVHomeMenuHookMatches(list,@selector(layoutSubviews),NO) ||
       !LMVHomeMenuHookMatches(list,@selector(didMoveToWindow),NO))return;
    installed=YES;
    MSHookMessageEx(list,@selector(layoutSubviews),(IMP)LMVHomeMenuHookLayout,(IMP *)&LMVHomeMenuOriginalLayout);
    MSHookMessageEx(list,@selector(didMoveToWindow),(IMP)LMVHomeMenuHookMove,(IMP *)&LMVHomeMenuOriginalMove);
    Class presentation=NSClassFromString(@"_UIContextMenuPresentationController");
    if(presentation && [presentation isSubclassOfClass:UIPresentationController.class] &&
       LMVHomeMenuHookMatches(presentation,@selector(presentationTransitionWillBegin),NO) &&
       LMVHomeMenuHookMatches(presentation,@selector(presentationTransitionDidEnd:),YES) &&
       LMVHomeMenuHookMatches(presentation,@selector(dismissalTransitionWillBegin),NO)) {
        MSHookMessageEx(presentation,@selector(presentationTransitionWillBegin),(IMP)LMVHomeMenuHookWillBegin,(IMP *)&LMVHomeMenuOriginalWillBegin);
        MSHookMessageEx(presentation,@selector(presentationTransitionDidEnd:),(IMP)LMVHomeMenuHookDidEnd,(IMP *)&LMVHomeMenuOriginalDidEnd);
        MSHookMessageEx(presentation,@selector(dismissalTransitionWillBegin),(IMP)LMVHomeMenuHookDismiss,(IMP *)&LMVHomeMenuOriginalDismiss);
    }
}
