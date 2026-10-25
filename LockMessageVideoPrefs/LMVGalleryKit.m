#import "LMVGalleryKit.h"

// One recogniser class for every tappable card. Defined here (not in the header)
// because the implementation must exist exactly once in the bundle.
@interface LMVGPressRecognizer : UILongPressGestureRecognizer
@end

@implementation LMVGPressRecognizer
- (instancetype)init {
    self = [super initWithTarget:self action:@selector(handlePress:)];
    if (self) {
        self.minimumPressDuration = 0.01;
        self.cancelsTouchesInView = NO;
        self.delaysTouchesEnded = NO;
    }
    return self;
}
- (void)handlePress:(UILongPressGestureRecognizer *)recognizer {
    UIView *view = recognizer.view;
    if (!view) return;
    if (recognizer.state == UIGestureRecognizerStateBegan || recognizer.state == UIGestureRecognizerStateChanged) {
        [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction animations:^{
            view.transform = CGAffineTransformMakeScale(0.97, 0.97);
        } completion:nil];
    } else if (recognizer.state == UIGestureRecognizerStateEnded ||
               recognizer.state == UIGestureRecognizerStateCancelled ||
               recognizer.state == UIGestureRecognizerStateFailed) {
        [UIView animateWithDuration:0.28 delay:0 usingSpringWithDamping:0.72 initialSpringVelocity:0.5
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:^{ view.transform = CGAffineTransformIdentity; } completion:nil];
    }
}
@end

void LMVGAddPressFeedback(UIView *view) {
    if (!view) return;
    [view addGestureRecognizer:[LMVGPressRecognizer new]];
}
