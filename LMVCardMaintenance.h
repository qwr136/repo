#pragma once
static BOOL LMVCardNeedsUpdate(UIView *cell,CFTimeInterval now) {
    NSDictionary *states=objc_getAssociatedObject(cell,&LMVStatesKey);
    NSNumber *maintenance=objc_getAssociatedObject(cell,&LMVMaintenanceKey);
    BOOL due=!maintenance || now-maintenance.doubleValue>=1.0;
    if(due)return YES;
    for(NSString *target in LMVTargets()) {
        BOOL selected=LMVEnabled[target].boolValue && LMVPaths[target];
        LMVVideoState *state=states[target];
        if(!selected){if(state)return YES;continue;}
        if([target isEqualToString:@"Message"] && !LMVMessageCell(cell))continue;
        if(!state || !state.anchor) {
            NSNumber *last=objc_getAssociatedObject(cell,&LMVDiscoveryKey);
            if(!last || now-last.doubleValue>=.1)return YES;
            continue;
        }
        UIView *anchor=state.anchor,*host=state.host;
        if(!anchor.superview || !host || ![anchor isDescendantOfView:cell] ||
           state.overlay.superview!=host || ![state.path isEqualToString:LMVPaths[target]])return YES;
        NSString *revision=LMVRevisions[state.path];
        if(revision && ![revision isEqualToString:state.revision])return YES;
        if(state.active && !state.source)return YES;
        CGRect frame=[anchor convertRect:anchor.bounds toView:host];
        if(!CGRectEqualToRect(frame,state.overlay.frame))return YES;
    }
    return NO;
}
