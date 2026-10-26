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

// 5.1.3: one chip per cover. The cache is keyed by relative+revision, exactly like
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

// 5.1.3: the cover used to be grabbed at 0.05s only. A great many clips open on a
// black field or a fade-in, and that frame was written to the card - which read as
// "画质糊". Try a few later points and reject a nearly black frame; a genuinely
// dark clip still gets its first frame back, so nothing goes blank.
static BOOL LMVGImageIsNearlyBlack(CGImageRef image) {
    if (!image) return YES;
    uint8_t pixels[8 * 8 * 4] = {0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(pixels, 8, 8, 8, 8 * 4, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!ctx) return NO;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationLow);
    CGContextDrawImage(ctx, CGRectMake(0, 0, 8, 8), image);
    CGContextRelease(ctx);
    double sum = 0;
    for (NSUInteger i = 0; i < 8 * 8; i++)
        sum += 0.2126 * pixels[i * 4] + 0.7152 * pixels[i * 4 + 1] + 0.0722 * pixels[i * 4 + 2];
    return (sum / (8 * 8)) < 12.0;
}
static CGImageRef LMVGCopyCoverFrame(AVAssetImageGenerator *generator, AVAsset *asset) {
    double duration = CMTimeGetSeconds(asset.duration);
    CGImageRef fallback = NULL;
    for (NSNumber *offset in @[@0.05, @0.5, @1.0]) {
        double seconds = offset.doubleValue;
        if (seconds > 0.05 && (!isfinite(duration) || seconds >= duration)) continue;
        CGImageRef frame = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(seconds, 600) actualTime:NULL error:NULL];
        if (!frame) continue;
        if (!LMVGImageIsNearlyBlack(frame)) {
            if (fallback) CGImageRelease(fallback);
            return frame;
        }
        if (!fallback) fallback = frame; else CGImageRelease(frame);
    }
    return fallback;
}

// 5.1.3: decoded covers are persisted as JPEG so a cold start paints immediately
// instead of waiting for sixteen serial video decodes. The name is built by the
// shared helper in LMVStoragePaths.h, which the sweep also uses.
static NSString *LMVGalleryCoverFolder(void) {
    return [LMVStorageRootPath stringByAppendingPathComponent:LMVGalleryCoverCacheFolder];
}
static NSString *LMVGalleryCoverDiskPath(NSString *relative, CGFloat maxPixel, NSString *revision) {
    return [LMVGalleryCoverFolder() stringByAppendingPathComponent:
            LMVGalleryCoverFileName(relative, maxPixel, revision)];
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
        NSString *diskPath = LMVGalleryCoverDiskPath(relative, maxPixel, revision);
        UIImage *image = [LMVGCoverCache() objectForKey:key];
        // 5.1.3: a decoded cover survives a relaunch; the first paint after a cold
        // start no longer waits for the serial decoder.
        if (!image) {
            image = [UIImage imageWithContentsOfFile:diskPath];
            if (image) [LMVGCoverCache() setObject:image forKey:key cost:(NSUInteger)(image.size.width * image.size.height * 4)];
        }
        if (!image) {
            NSString *absolute = [LMVStorageRootPath stringByAppendingPathComponent:relative];
            @autoreleasepool {
                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:absolute] options:nil];
                // 5.1.3: the asset is already open for the cover - fill the
                // resolution chip cache here so the chip costs no second open.
                NSString *resolution = LMVGResolutionForAsset(relative, asset);
                if (resolution) [LMVGResolutionCache() setObject:resolution forKey:LMVGResolutionKey(relative)];
                AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
                generator.appliesPreferredTrackTransform = YES;
                generator.maximumSize = CGSizeMake(maxPixel, maxPixel);
                generator.requestedTimeToleranceBefore = CMTimeMakeWithSeconds(0.10, 600);
                generator.requestedTimeToleranceAfter = CMTimeMakeWithSeconds(0.10, 600);
                CGImageRef frame = LMVGCopyCoverFrame(generator, asset);
                if (frame) {
                    image = [UIImage imageWithCGImage:frame];
                    CGImageRelease(frame);
                }
            }
            // Very short clips can fail at 0.05s; the old 144px path is the fallback
            // (soft, but better than an empty gradient).
            if (!image && revision) image = LMVEnsureThumbnail(relative, revision);
            if (image) {
                [LMVGCoverCache() setObject:image forKey:key cost:(NSUInteger)(image.size.width * image.size.height * 4)];
                // Only sizes a page keeps on screen are persisted; the 2000px hero
                // would add hundreds of KB per clip for a one-off paint.
                if (maxPixel <= 1200) {
                    NSData *jpeg = UIImageJPEGRepresentation(image, 0.86);
                    if (jpeg.length && jpeg.length <= 512 * 1024) {
                        [NSFileManager.defaultManager createDirectoryAtPath:LMVGalleryCoverFolder()
                                              withIntermediateDirectories:YES attributes:nil error:nil];
                        [jpeg writeToFile:diskPath atomically:YES];
                    }
                }
            }
        }
        UIImage *result = image;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result); });
    });
}

void LMVGLoadCover(NSString *relative, void (^completion)(UIImage *image)) {
    // 5.1.3: 1500 was ~1.29x short of a 3x full-width cover on a portrait clip.
    LMVGLoadCoverSized(relative, 2000.0, completion);
}

void LMVGLoadThumb(NSString *relative, void (^completion)(UIImage *image)) {
    LMVGLoadCoverSized(relative, 360.0, completion);
}
