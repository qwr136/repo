#pragma once
static UIView *LMVActionMaterial(UIView *view, NSUInteger depth, NSUInteger *budget) {
    if (!view || !*budget || depth > 8 || view.hidden || LMVOriginalVisibilityAlpha(view) < .01) return nil;
    --*budget;
    NSString *name = NSStringFromClass(view.class);
    if (([name containsString:@"MaterialView"] || [name containsString:@"Backdrop"] ||
        [name containsString:@"VisualEffect"]) && view.bounds.size.width > 20 && view.bounds.size.height > 20 &&
        (LMVOriginalPureView(view, NO, 0) || LMVActionBackgroundMaterial(view))) return view;
    if ([view isKindOfClass:UILabel.class] || [view isKindOfClass:UIImageView.class] ||
        [view isKindOfClass:UIScrollView.class] || LMVMessageCell(view)) return nil;
    UIView *largest = nil;
    for (UIView *child in view.subviews) {
        UIView *candidate = LMVActionMaterial(child, depth + 1, budget);
        if (candidate && (!largest || candidate.bounds.size.width * candidate.bounds.size.height > largest.bounds.size.width * largest.bounds.size.height)) largest = candidate;
    }
    return largest;
}
static BOOL LMVActionSemanticScope(UIView *view, NSString *target, NSUInteger depth, NSUInteger *budget) {
    if (!view || !*budget || depth > 8) return NO;
    --*budget;
    if (view.hidden || LMVOriginalVisibilityAlpha(view) < .01) return YES;
    NSString *semantic = LMVSemanticTarget(view);
    if (semantic && ![semantic isEqual:target]) return NO;
    for (UIView *child in view.subviews) if (!LMVActionSemanticScope(child, target, depth + 1, budget)) return NO;
    return YES;
}
static void LMVFindActionsBranch(UIView *view, UIView *root, NSMapTable *hosts, NSUInteger depth, NSUInteger *remaining) {
    if (!view || !*remaining) return;
    --*remaining;
    if (depth > 10 || view.hidden || LMVOriginalVisibilityAlpha(view) < .01) return;
    NSString *target = LMVSemanticTarget(view);
    if (target) {
        UIView *control = view;
        while (control && control != root && ![control isKindOfClass:UIControl.class]) control = control.superview;
        UIView *boundary = control && control != root ? control : view;
        UIView *material = nil;
        NSUInteger budget = 96;
        // Expanded ClearAll draws a sibling material under its PLPlatter/action
        // host. Ascend only within the already confirmed action presenter; never
        // substitute a notification cell/header or a mixed full-screen container.
        for (UIView *node = boundary; node && [node isDescendantOfView:root]; node = node.superview) {
            NSUInteger semanticBudget = 96;
            if (!LMVActionSemanticScope(node, target, 0, &semanticBudget)) break;
            UIView *candidate = LMVActionMaterial(node, 0, &budget);
            if (candidate) { material = candidate; break; }
            if (node == root) break;
        }
        UIView *candidate = material ?: (control && control != root ? control : nil);
        if (candidate) {
            UIView *existing = [hosts objectForKey:target];
            if (!existing || candidate.bounds.size.width * candidate.bounds.size.height > existing.bounds.size.width * existing.bounds.size.height)
                [hosts setObject:candidate forKey:target];
        }
    }
    for (UIView *child in view.subviews) LMVFindActionsBranch(child, root, hosts, depth + 1, remaining);
}
static void LMVFindActions(UIView *view, UIView *root, NSMapTable *hosts, NSUInteger depth) {
    NSUInteger remaining = 128;
    LMVFindActionsBranch(view, root, hosts, depth, &remaining);
}
