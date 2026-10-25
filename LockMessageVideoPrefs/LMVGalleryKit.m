#import "LMVGalleryKit.h"
#import <AVFoundation/AVFoundation.h>

// One recogniser class for every tappable card. Defined here (not in the header)
// because the implementation must exist exactly once in the bundle.
@interface LMVGPressRecognizer : UILongPressGestureRecognizer <UIGestureRecognizerDelegate>
@end

@implementation LMVGPressRecognizer
- (instancetype)init {
    self = [super initWithTarget:self action:@selector(handlePress:)];
    if (self) {
        self.minimumPressDuration = 0.01;
        self.cancelsTouchesInView = NO;
        self.delaysTouchesEnded = NO;
        self.delaysTouchesBegan = NO;
        self.delegate = self;
    }
    return self;
}
// 4.3.2: without this the press recogniser won the touch and the card's tap
// never fired ("点了没反应"). They must recognise together.
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
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

#pragma mark - Covers

static NSCache<NSString *, UIImage *> *LMVGCoverCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 48;
        cache.totalCostLimit = 96 * 1024 * 1024;
    });
    return cache;
}
// One serial queue: ten simultaneous first-frame decodes were the "很卡" part.
static dispatch_queue_t LMVGCoverQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.minis.lockmessagevideo.gallery-covers", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

void LMVGLoadCoverSized(NSString *relative, CGFloat maxPixel, void (^completion)(UIImage *)) {
    if (!completion) return;
    if (![relative isKindOfClass:NSString.class] || !relative.length) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    NSString *revision = LMVThumbnailRevision(relative);
    NSString *key = [NSString stringWithFormat:@"%.0f|%@|%@", maxPixel, relative, revision ?: @""];
    UIImage *cached = [LMVGCoverCache() objectForKey:key];
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
        return;
    }
    dispatch_async(LMVGCoverQueue(), ^{
        UIImage *image = [LMVGCoverCache() objectForKey:key];
        if (!image) {
            NSString *absolute = [LMVStorageRootPath stringByAppendingPathComponent:relative];
            @autoreleasepool {
                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:absolute] options:nil];
                AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
                generator.appliesPreferredTrackTransform = YES;
                generator.maximumSize = CGSizeMake(maxPixel, maxPixel);
                generator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.35, 600);
                generator.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(0.35, 600);
                NSError *error = nil;
                CGImageRef frame = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(0.05, 600) actualTime:NULL error:&error];
                if (frame) {
                    image = [UIImage imageWithCGImage:frame];
                    CGImageRelease(frame);
                }
            }
            // Very short clips can fail at 0.05s; the old 144px path is the fallback
            // (soft, but better than an empty gradient).
            if (!image && revision) image = LMVEnsureThumbnail(relative, revision);
            if (image) [LMVGCoverCache() setObject:image forKey:key cost:(NSUInteger)(image.size.width * image.size.height * 4)];
        }
        UIImage *result = image;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    });
}

void LMVGLoadCover(NSString *relative, void (^completion)(UIImage *image)) {
    LMVGLoadCoverSized(relative, 900.0, completion);
}

void LMVGLoadThumb(NSString *relative, void (^completion)(UIImage *image)) {
    LMVGLoadCoverSized(relative, 360.0, completion);
}
