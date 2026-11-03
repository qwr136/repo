#import "LMVSliderControl.h"

// 尺寸按 @1x 画，换成图片后 UISlider 不再理会 tintColor，
// 所以填充色、空白色只在这里定义。
static const CGFloat kLMVSliderTrackHeight = 4.0;
static const CGFloat kLMVSliderThumbWidth = 14.0;
static const CGFloat kLMVSliderThumbHeight = 26.0;

static UIImage *LMVSliderTrackImage(UIColor *color) {
    CGFloat height = kLMVSliderTrackHeight;
    CGFloat width = height * 2.0;
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, height)];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context;
        [color setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, width, height)
                                        cornerRadius:height / 2.0] fill];
    }];
    UIEdgeInsets caps = UIEdgeInsetsMake(0.0, height / 2.0, 0.0, height / 2.0);
    return [image resizableImageWithCapInsets:caps];
}

static UIImage *LMVSliderThumbImage(void) {
    CGSize size = CGSizeMake(kLMVSliderThumbWidth, kLMVSliderThumbHeight);
    UIGraphicsImageRenderer *renderer =
        [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGContextRef cg = context.CGContext;

        // 手柄比轨道高得多，没有阴影会和轨道糊在一起。
        CGContextSetShadowWithColor(cg, CGSizeMake(0.0, 1.0), 2.0,
                                    [UIColor colorWithWhite:0.0 alpha:0.16].CGColor);
        [[UIColor whiteColor] setFill];
        [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0.0, 0.0, size.width, size.height)
                                        cornerRadius:size.width / 2.0] fill];
        CGContextSetShadowWithColor(cg, CGSizeZero, 0.0, NULL);

        // 中间三条竖纹，提示这个胶囊可以横向拖。
        [[UIColor colorWithWhite:0.62 alpha:1.0] setFill];
        CGFloat barWidth = 1.5;
        CGFloat barHeight = 9.0;
        CGFloat gap = 3.5;
        for (NSInteger index = -1; index <= 1; index++) {
            CGRect bar = CGRectMake(size.width / 2.0 + index * gap - barWidth / 2.0,
                                    (size.height - barHeight) / 2.0,
                                    barWidth,
                                    barHeight);
            [[UIBezierPath bezierPathWithRoundedRect:bar cornerRadius:barWidth / 2.0] fill];
        }
    }];
}

@implementation LMVSliderControl

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self lmvp_applySliderAppearance];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) [self lmvp_applySliderAppearance];
    return self;
}

- (void)lmvp_applySliderAppearance {
    static UIImage *thumb = nil;
    static UIImage *minimumTrack = nil;
    static UIImage *maximumTrack = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        thumb = LMVSliderThumbImage();
        minimumTrack = LMVSliderTrackImage([UIColor systemBlueColor]);
        maximumTrack = LMVSliderTrackImage([UIColor tertiarySystemFillColor]);
    });
    [self setThumbImage:thumb forState:UIControlStateNormal];
    [self setThumbImage:thumb forState:UIControlStateHighlighted];
    [self setMinimumTrackImage:minimumTrack forState:UIControlStateNormal];
    [self setMaximumTrackImage:maximumTrack forState:UIControlStateNormal];
}

// 轨道左右各让出半个手柄，拖到两端时滑块不会顶出边界。
- (CGRect)trackRectForBounds:(CGRect)bounds {
    CGFloat height = kLMVSliderTrackHeight;
    CGFloat inset = kLMVSliderThumbWidth / 2.0;
    return CGRectMake(inset,
                      CGRectGetMidY(bounds) - height / 2.0,
                      MAX(0.0, CGRectGetWidth(bounds) - inset * 2.0),
                      height);
}

- (CGRect)thumbRectForBounds:(CGRect)bounds trackRect:(CGRect)rect value:(float)value {
    CGRect base = [super thumbRectForBounds:bounds trackRect:rect value:value];
    return CGRectMake(CGRectGetMidX(base) - kLMVSliderThumbWidth / 2.0,
                      CGRectGetMidY(bounds) - kLMVSliderThumbHeight / 2.0,
                      kLMVSliderThumbWidth,
                      kLMVSliderThumbHeight);
}

// 图片不会像系统滑条那样自动变淡，禁用态手动降透明度。
- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    self.alpha = enabled ? 1.0 : 0.45;
}

@end
