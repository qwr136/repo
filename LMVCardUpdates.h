#pragma once
// Main-thread weak work lists: repeated layout of one card never requests an
// unrelated wallpaper/control-center/global policy refresh.
static NSHashTable<UIView *> *LMVDirtyCards,*LMVDirtyPresenters;
static BOOL LMVCardUpdatePending,LMVCardUpdateApplying;
static void LMVUpdateActionPresenter(UIView *presenter);
static void LMVScheduleCardUpdates(void) {
    if(!LMVInitialized || !LMVLaunchReady || !NSThread.isMainThread || LMVCardUpdatePending || LMVCardUpdateApplying)return;
    LMVCardUpdatePending=YES;
    dispatch_async(dispatch_get_main_queue(),^{
        LMVCardUpdatePending=NO;
        if(!LMVInitialized || !LMVLaunchReady)return;
        // Global preference work owns this turn and visits every live card.
        if(LMVPreferencesDirty){LMVRequestSafeUpdate();return;}
        if(LMVSafeUpdateApplying){LMVScheduleCardUpdates();return;}
        NSArray *cards=LMVDirtyCards.allObjects,*presenters=LMVDirtyPresenters.allObjects;
        [LMVDirtyCards removeAllObjects];[LMVDirtyPresenters removeAllObjects];
        LMVCardUpdateApplying=YES;
        // Presenter layout may belong to a card already in the local batch.
        // Resolve each owner once after all action discovery invalidations.
        NSMutableSet *owners=[NSMutableSet setWithArray:cards];
        for(UIView *presenter in presenters) {
            UIView *owner=presenter;Class cell=NSClassFromString(@"NCNotificationListCell");
            for(UIView *node=presenter;node;node=node.superview)if(cell && [node isKindOfClass:cell]){owner=node;break;}
            [LMVCells addObject:owner];[owners addObject:owner];
            objc_setAssociatedObject(owner,&LMVDiscoveryKey,nil,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        for(UIView *owner in owners){LMVUpdate(owner);LMVRetryDiscovery(owner);}
        LMVCardUpdateApplying=NO;
        if(LMVDirtyCards.allObjects.count || LMVDirtyPresenters.allObjects.count)LMVScheduleCardUpdates();
    });
}
static void LMVRequestCardUpdate(UIView *view,BOOL action) {
    if(!LMVInitialized || !NSThread.isMainThread || !view)return;
    if(!LMVDirtyCards)LMVDirtyCards=[NSHashTable weakObjectsHashTable];
    if(!LMVDirtyPresenters)LMVDirtyPresenters=[NSHashTable weakObjectsHashTable];
    [(action?LMVDirtyPresenters:LMVDirtyCards) addObject:view];
    LMVScheduleCardUpdates();
}
static void LMVForgetCardUpdate(UIView *view) {
    [LMVDirtyCards removeObject:view];[LMVDirtyPresenters removeObject:view];
}
