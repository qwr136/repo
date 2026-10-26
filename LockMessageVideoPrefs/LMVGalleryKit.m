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
    if (!view || LMVGReduceMotion()) return;
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
        cache.countLimit = 40;
        cache.totalCostLimit = 192 * 1024 * 1024;
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

#pragma mark - Resolution

// 5.0.0: one chip per cover. The cache is keyed by relative+revision, exactly like
// the cover cache, so a replaced file can never keep the old resolution.
static NSCache<NSString *, NSString *> *LMVGResolutionCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 256;
    });
    return cache;
}
static NSString *LMVGResolutionKey(NSString *relative) {
    return [NSString stringWithFormat:@"%@|%@", relative, LMVThumbnailRevision(relative) ?: @""];
}
NSString *LMVGResolutionText(CGSize pixelSize) {
    CGFloat w = fabs(pixelSize.width), h = fabs(pixelSize.height);
    if (!isfinite(w) || !isfinite(h) || w < 1 || h < 1) return nil;
    CGFloat shortSide = MIN(w, h);
    if (shortSide >= 2160) return @"4K";
    if (shortSide >= 1440) return @"2K";
    if (shortSide >= 1080) return @"1080P";
    if (shortSide >= 720) return @"720P";
    if (shortSide >= 480) return @"480P";
    return [NSString stringWithFormat:@"%.0f×%.0f", w, h];
}
// The transform only matters for the exact WxH fallback; the shorthand labels use
// the shorter side and are immune to rotation metadata.
static NSString *LMVGResolutionForAsset(NSString *relative, AVURLAsset *asset) {
    if (!relative.length || !asset) return nil;
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!track) return nil;
    CGSize natural = track.naturalSize;
    CGRect oriented = CGRectApplyAffineTransform(CGRectMake(0, 0, fabs(natural.width), fabs(natural.height)), track.preferredTransform);
    return LMVGResolutionText(oriented.size);
}
void LMVGLoadResolution(NSString *relative, void (^completion)(NSString *)) {
    if (!completion) return;
    if (![relative isKindOfClass:NSString.class] || !relative.length) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    NSString *key = LMVGResolutionKey(relative);
    NSString *cached = [LMVGResolutionCache() objectForKey:key];
    if (cached) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(cached); });
        return;
    }
    dispatch_async(LMVGCoverQueue(), ^{
        NSString *value = [LMVGResolutionCache() objectForKey:key];
        if (!value) {
            NSString *absolute = [LMVStorageRootPath stringByAppendingPathComponent:relative];
            @autoreleasepool {
                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:absolute] options:nil];
                value = LMVGResolutionForAsset(relative, asset);
                if (value) [LMVGResolutionCache() setObject:value forKey:key];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(value); });
    });
}
// Insets are drawn by the label itself, so "4K" and "1080P" both get the same
// 4pt padding without a width constraint per string.
@interface LMVGPaddedLabel : UILabel
@property(nonatomic) UIEdgeInsets contentInsets;
@end
@implementation LMVGPaddedLabel
- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.contentInsets)];
}
- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    return CGSizeMake(size.width + self.contentInsets.left + self.contentInsets.right,
                      size.height + self.contentInsets.top + self.contentInsets.bottom);
}
@end
UILabel *LMVGMakeResolutionBadge(void) {
    LMVGPaddedLabel *label = [[LMVGPaddedLabel alloc] initWithFrame:CGRectZero];
    label.contentInsets = UIEdgeInsetsMake(1, 4, 1, 4);
    label.font = LMVGFont(9, UIFontWeightSemibold);
    label.textColor = UIColor.whiteColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.52];
    label.layer.cornerRadius = 4;
    label.layer.cornerCurve = kCACornerCurveContinuous;
    label.clipsToBounds = YES;
    label.tag = 1007;
    label.hidden = YES;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.isAccessibilityElement = NO;
    return label;
}
void LMVGApplyResolution(UILabel *badge, NSString *relative) {
    if (!badge) return;
    badge.text = nil;
    badge.hidden = YES;
    LMVGLoadResolution(relative, ^(NSString *text) {
        if (!badge) return;
        badge.text = text;
        badge.hidden = !text.length;
    });
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
                // 5.0.0: the asset is already open for the cover - fill the
                // resolution chip cache here so the chip costs no second open.
                NSString *resolution = LMVGResolutionForAsset(relative, asset);
                if (resolution) [LMVGResolutionCache() setObject:resolution forKey:LMVGResolutionKey(relative)];
                AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
                generator.appliesPreferredTrackTransform = YES;
                generator.maximumSize = CGSizeMake(maxPixel, maxPixel);
                generator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.10, 600);
                generator.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(0.10, 600);
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
    // 5.0.0: 1500 was ~1.29x short of a 3x full-width cover on a portrait clip.
    LMVGLoadCoverSized(relative, 2000.0, completion);
}

void LMVGLoadThumb(NSString *relative, void (^completion)(UIImage *image)) {
    LMVGLoadCoverSized(relative, 360.0, completion);
}
