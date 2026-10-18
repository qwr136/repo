#import "LMVTextColorPicker.h"
#import <math.h>

NSString *const LMVTextColorKey = @"CVTextColor";
static CFStringRef const kLMVColorPrefsID = CFSTR("com.minis.lockmessagevideo");

static uint32_t LMVColorWord(UIColor *color) {
    CGFloat r=1,g=1,b=1,a=1;
    if(![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGColorRef cg=color.CGColor;
        const CGFloat *parts=cg?CGColorGetComponents(cg):NULL;
        size_t count=cg?CGColorGetNumberOfComponents(cg):0;
        if(parts && count>=4) {r=parts[0];g=parts[1];b=parts[2];a=parts[3];}
        else if(parts && count>=2) {r=g=b=parts[0];a=parts[1];}
    }
    uint32_t ri=(uint32_t)lround(MAX(0,MIN(1,r))*255);
    uint32_t gi=(uint32_t)lround(MAX(0,MIN(1,g))*255);
    uint32_t bi=(uint32_t)lround(MAX(0,MIN(1,b))*255);
    uint32_t ai=(uint32_t)lround(MAX(0,MIN(1,a))*255);
    return (ri<<24)|(gi<<16)|(bi<<8)|ai;
}
UIColor *LMVTextColorCurrent(void) {
    NSNumber *value=(__bridge_transfer NSNumber *)CFPreferencesCopyAppValue((__bridge CFStringRef)LMVTextColorKey,kLMVColorPrefsID);
    if(![value isKindOfClass:NSNumber.class])return nil;
    uint32_t word=value.unsignedIntValue;
    return [UIColor colorWithRed:((word>>24)&0xFF)/255.0 green:((word>>16)&0xFF)/255.0
                           blue:((word>>8)&0xFF)/255.0 alpha:(word&0xFF)/255.0];
}
void LMVTextColorStore(UIColor *color) {
    if(color) {
        NSNumber *value=@(LMVColorWord(color));
        CFPreferencesSetAppValue((__bridge CFStringRef)LMVTextColorKey,(__bridge CFPropertyListRef)value,kLMVColorPrefsID);
    } else {
        CFPreferencesSetAppValue((__bridge CFStringRef)LMVTextColorKey,NULL,kLMVColorPrefsID);
    }
    CFPreferencesAppSynchronize(kLMVColorPrefsID);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("com.minis.lockmessagevideo/preferencesChanged"),NULL,NULL,YES);
}
NSString *LMVTextColorHex(UIColor *color) {
    uint32_t word=LMVColorWord(color?:UIColor.whiteColor);
    return [NSString stringWithFormat:@"#%02X%02X%02X",(word>>24)&0xFF,(word>>16)&0xFF,(word>>8)&0xFF];
}

#pragma mark - Grid palette (figure 4)

// 12 columns: the first row is a grey ramp, the eight rows below are a
// hue x brightness matrix. Drawn and hit-tested with the same formula, so the
// colour under the finger is exactly the colour that gets picked.
static const NSInteger kLMVGridColumns = 12;
static const NSInteger kLMVGridRows = 9;

static void LMVGridColorAt(NSInteger x,NSInteger y,CGFloat *r,CGFloat *g,CGFloat *b) {
    if(y<=0) {
        CGFloat v=1.0-(CGFloat)x/(CGFloat)(kLMVGridColumns-1);
        *r=*g=*b=v;
        return;
    }
    CGFloat hue=(CGFloat)x/(CGFloat)kLMVGridColumns;
    CGFloat t=(CGFloat)(y-1)/(CGFloat)(kLMVGridRows-2);
    CGFloat sat=0.34+0.66*t;
    CGFloat val=1.0-0.56*t;
    UIColor *color=[UIColor colorWithHue:hue saturation:sat brightness:val alpha:1];
    [color getRed:r green:g blue:b alpha:NULL];
}

@interface LMVColorGridView : UIView
@property(nonatomic,copy) void (^onPick)(CGFloat r,CGFloat g,CGFloat b);
- (void)pickPoint:(CGPoint)point;
- (void)handleTap:(UITapGestureRecognizer *)gesture;
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
@end
@implementation LMVColorGridView
- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:frame];
    if(self) {
        self.backgroundColor=UIColor.clearColor;
        self.layer.cornerRadius=10;
        self.layer.cornerCurve=kCACornerCurveContinuous;
        self.clipsToBounds=YES;
        self.isAccessibilityElement=YES;
        self.accessibilityLabel=@"颜色网格";
        self.accessibilityHint=@"点击或拖动选择颜色";
        // 1.84.1: raw touches were swallowed by the presented sheet's gesture
        // recognisers. Explicit recognisers always receive the touch.
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.minimumNumberOfTouches=1;
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    CGFloat w=CGRectGetWidth(self.bounds)/(CGFloat)kLMVGridColumns;
    CGFloat h=CGRectGetHeight(self.bounds)/(CGFloat)kLMVGridRows;
    for(NSInteger y=0;y<kLMVGridRows;y++) {
        for(NSInteger x=0;x<kLMVGridColumns;x++) {
            CGFloat r,g,b;
            LMVGridColorAt(x,y,&r,&g,&b);
            [[UIColor colorWithRed:r green:g blue:b alpha:1] setFill];
            CGContextFillRect(ctx,CGRectMake(x*w,y*h,w+0.6,h+0.6));
        }
    }
}
- (void)handleTap:(UITapGestureRecognizer *)gesture { [self pickPoint:[gesture locationInView:self]]; }
- (void)handlePan:(UIPanGestureRecognizer *)gesture { [self pickPoint:[gesture locationInView:self]]; }
- (void)pickPoint:(CGPoint)p {
    CGFloat w=CGRectGetWidth(self.bounds)/(CGFloat)kLMVGridColumns;
    CGFloat h=CGRectGetHeight(self.bounds)/(CGFloat)kLMVGridRows;
    NSInteger x=(NSInteger)floor(p.x/MAX(w,1));
    NSInteger y=(NSInteger)floor(p.y/MAX(h,1));
    x=MAX(0,MIN(kLMVGridColumns-1,x));
    y=MAX(0,MIN(kLMVGridRows-1,y));
    CGFloat r,g,b;
    LMVGridColorAt(x,y,&r,&g,&b);
    if(self.onPick) self.onPick(r,g,b);
}
@end

#pragma mark - Spectrum (figure 3)

// Horizontal hue, vertical white -> pure -> black. The same two gradients the
// view draws are inverted for the pick, so what the user touches is what they
// get even in the corner stops.
@interface LMVSpectrumView : UIView
@property(nonatomic,copy) void (^onPick)(CGFloat r,CGFloat g,CGFloat b);
- (void)showHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness;
- (void)pickPoint:(CGPoint)point;
- (void)handleTap:(UITapGestureRecognizer *)gesture;
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
@end
@implementation LMVSpectrumView {
    CGFloat _hue,_saturation,_brightness;
    CALayer *_marker;
    BOOL _hasMarker;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self=[super initWithFrame:frame];
    if(self) {
        self.backgroundColor=UIColor.clearColor;
        self.layer.cornerRadius=10;
        self.layer.cornerCurve=kCACornerCurveContinuous;
        self.clipsToBounds=YES;
        self.isAccessibilityElement=YES;
        self.accessibilityLabel=@"光谱选色";
        self.accessibilityHint=@"点击或拖动选择颜色";
        _marker=[CALayer layer];
        _marker.bounds=CGRectMake(0,0,20,20);
        _marker.cornerRadius=10;
        _marker.borderWidth=2;
        _marker.borderColor=UIColor.whiteColor.CGColor;
        _marker.shadowColor=UIColor.blackColor.CGColor;
        _marker.shadowOpacity=.55;
        _marker.shadowRadius=2;
        _marker.shadowOffset=CGSizeZero;
        _hasMarker=NO;
        [self.layer addSublayer:_marker];
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        pan.minimumNumberOfTouches=1;
        [self addGestureRecognizer:pan];
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    CGContextRef ctx=UIGraphicsGetCurrentContext();
    CGFloat w=CGRectGetWidth(self.bounds),h=CGRectGetHeight(self.bounds);
    if(!ctx || w<=0 || h<=0) return;
    // 1.84.1: build both gradients from plain component arrays. The CFArray of
    // CGColorRefs version drew nothing in the tweak process, which is why the
    // spectrum looked empty. Components are colour-space defined and cannot fail
    // that way.
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    if(!space) return;
    CGFloat hueComponents[]={
        1,0,0,1,   1,1,0,1,   0,1,0,1,   0,1,1,1,
        0,0,1,1,   1,0,1,1,   1,0,0,1
    };
    CGFloat hueLocations[]={0,1.0/6,2.0/6,0.5,4.0/6,5.0/6,1};
    CGGradientRef hueGradient=CGGradientCreateWithColorComponents(space,hueComponents,hueLocations,7);
    if(hueGradient) {
        CGContextDrawLinearGradient(ctx,hueGradient,CGPointMake(0,0),CGPointMake(w,0),0);
        CGGradientRelease(hueGradient);
    }
    CGFloat shadeComponents[]={
        1,1,1,1,   1,1,1,0,
        0,0,0,0,   0,0,0,1
    };
    CGFloat shadeLocations[]={0,0.5,0.5001,1};
    CGGradientRef shadeGradient=CGGradientCreateWithColorComponents(space,shadeComponents,shadeLocations,4);
    if(shadeGradient) {
        CGContextDrawLinearGradient(ctx,shadeGradient,CGPointMake(0,0),CGPointMake(0,h),
            kCGGradientDrawsBeforeStartLocation|kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(shadeGradient);
    }
    CGColorSpaceRelease(space);
}
- (void)layoutSubviews {
    [super layoutSubviews];
    [self placeMarker];
}
- (void)placeMarker {
    if(!_hasMarker) { _marker.hidden=YES; return; }
    _marker.hidden=NO;
    CGFloat w=CGRectGetWidth(self.bounds),h=CGRectGetHeight(self.bounds);
    CGFloat y=_saturation<0.999 ? _saturation*0.5 : 0.5+(1.0-_brightness)*0.5;
    _marker.position=CGPointMake(MAX(0,MIN(1,_hue))*w,MAX(0,MIN(1,y))*h);
}
- (void)showHue:(CGFloat)hue saturation:(CGFloat)saturation brightness:(CGFloat)brightness {
    _hue=MAX(0,MIN(1,hue));
    _saturation=MAX(0,MIN(1,saturation));
    _brightness=MAX(0,MIN(1,brightness));
    _hasMarker=YES;
    [self placeMarker];
}
- (void)handleTap:(UITapGestureRecognizer *)gesture { [self pickPoint:[gesture locationInView:self]]; }
- (void)handlePan:(UIPanGestureRecognizer *)gesture { [self pickPoint:[gesture locationInView:self]]; }
- (void)pickPoint:(CGPoint)p {
    CGFloat w=MAX(1,CGRectGetWidth(self.bounds)),h=MAX(1,CGRectGetHeight(self.bounds));
    CGFloat hue=MAX(0,MIN(1,p.x/w));
    CGFloat t=MAX(0,MIN(1,p.y/h));
    CGFloat saturation=t<=0.5 ? t*2.0 : 1.0;
    CGFloat brightness=t<=0.5 ? 1.0 : 1.0-(t-0.5)*2.0;
    UIColor *color=[UIColor colorWithHue:hue saturation:saturation brightness:brightness alpha:1];
    CGFloat r,g,b;
    [color getRed:&r green:&g blue:&b alpha:NULL];
    _hue=hue;_saturation=saturation;_brightness=brightness;_hasMarker=YES;
    [self placeMarker];
    if(self.onPick) self.onPick(r,g,b);
}
@end

#pragma mark - Picker

@interface LMVTextColorPicker () {
    UIView *_sheet;
    UILabel *_hex;
    UISegmentedControl *_mode;
    UIView *_gridPanel,*_spectrumPanel,*_sliderPanel;
    LMVColorGridView *_gridView;
    LMVSpectrumView *_spectrumView;
    UISlider *_redSlider,*_greenSlider,*_blueSlider,*_alphaSlider;
    UILabel *_redValue,*_greenValue,*_blueValue,*_alphaValue;
    UIView *_redTrack,*_greenTrack,*_blueTrack,*_alphaTrack;
    CAGradientLayer *_redGradient,*_greenGradient,*_blueGradient,*_alphaGradient;
    CGFloat _r,_g,_b,_a;
}
@end

@implementation LMVTextColorPicker
- (void)viewDidLoad {
    [super viewDidLoad];
    UIColor *stored=LMVTextColorCurrent();
    if(stored) {
        [stored getRed:&_r green:&_g blue:&_b alpha:&_a];
    } else {
        _r=_g=_b=1;_a=1;
    }
    self.view.backgroundColor=UIColor.clearColor;
    self.view.opaque=NO;

    _sheet=[UIView new];
    _sheet.backgroundColor=[UIColor secondarySystemBackgroundColor];
    _sheet.layer.cornerRadius=18;
    _sheet.layer.cornerCurve=kCACornerCurveContinuous;
    _sheet.clipsToBounds=YES;
    [self.view addSubview:_sheet];

    UILabel *title=[UILabel new];
    title.text=@"文字颜色";
    title.font=[UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.textAlignment=NSTextAlignmentCenter;
    title.textColor=UIColor.labelColor;
    title.tag=0x5A31;
    [_sheet addSubview:title];

    UIButton *close=[UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor=[UIColor tertiaryLabelColor];
    close.tag=0x5A32;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [_sheet addSubview:close];

    // 1.84: the user asked for the same three ways iOS offers - a grid, a
    // spectrum and plain sliders. All three write the same RGBA word.
    _mode=[[UISegmentedControl alloc] initWithItems:@[@"网格",@"光谱",@"滑块"]];
    _mode.selectedSegmentIndex=0;
    _mode.tag=0x5A36;
    [_mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [_sheet addSubview:_mode];

    _gridPanel=[UIView new]; _gridPanel.tag=0x5A40; [_sheet addSubview:_gridPanel];
    _spectrumPanel=[UIView new]; _spectrumPanel.tag=0x5A41; [_sheet addSubview:_spectrumPanel];
    _sliderPanel=[UIView new]; _sliderPanel.tag=0x5A42; [_sheet addSubview:_sliderPanel];

    _gridView=[LMVColorGridView new];
    _gridView.tag=0x5A43;
    __weak typeof(self) weakSelf=self;
    _gridView.onPick=^(CGFloat r,CGFloat g,CGFloat b) { [weakSelf pickRed:r green:g blue:b]; };
    [_gridPanel addSubview:_gridView];

    _spectrumView=[LMVSpectrumView new];
    _spectrumView.tag=0x5A44;
    _spectrumView.onPick=^(CGFloat r,CGFloat g,CGFloat b) { [weakSelf pickRed:r green:g blue:b]; };
    [_spectrumPanel addSubview:_spectrumView];

    _redSlider=[self sliderWithTag:1];
    _greenSlider=[self sliderWithTag:2];
    _blueSlider=[self sliderWithTag:3];
    _alphaSlider=[self sliderWithTag:4];
    _redTrack=[self trackWithTag:11];
    _greenTrack=[self trackWithTag:12];
    _blueTrack=[self trackWithTag:13];
    _alphaTrack=[self trackWithTag:14];
    _redGradient=(CAGradientLayer *)_redTrack.layer.sublayers.firstObject;
    _greenGradient=(CAGradientLayer *)_greenTrack.layer.sublayers.firstObject;
    _blueGradient=(CAGradientLayer *)_blueTrack.layer.sublayers.firstObject;
    _alphaGradient=(CAGradientLayer *)_alphaTrack.layer.sublayers.firstObject;

    _redValue=[self valueLabelWithTag:21];
    _greenValue=[self valueLabelWithTag:22];
    _blueValue=[self valueLabelWithTag:23];
    _alphaValue=[self valueLabelWithTag:24];

    _hex=[UILabel new];
    _hex.font=[UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    _hex.textColor=UIColor.systemBlueColor;
    _hex.textAlignment=NSTextAlignmentCenter;
    _hex.userInteractionEnabled=YES;
    _hex.tag=0x5A33;
    [_hex addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(copyHex)]];
    [_sliderPanel addSubview:_hex];

    UIView *presets=[UIView new];
    presets.tag=0x5A34;
    [_sheet addSubview:presets];
    NSArray *colors=@[UIColor.whiteColor,[UIColor colorWithWhite:.78 alpha:1],UIColor.blackColor];
    for(NSInteger i=0;i<colors.count;i++) {
        UIButton *dot=[UIButton buttonWithType:UIButtonTypeCustom];
        dot.tag=100+i;
        dot.backgroundColor=colors[i];
        dot.layer.cornerRadius=20;
        dot.layer.borderWidth=1;
        dot.layer.borderColor=[UIColor separatorColor].CGColor;
        [dot addTarget:self action:@selector(presetTapped:) forControlEvents:UIControlEventTouchUpInside];
        [presets addSubview:dot];
    }

    UIButton *reset=[UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"恢复默认颜色" forState:UIControlStateNormal];
    reset.titleLabel.font=[UIFont systemFontOfSize:15];
    reset.tag=0x5A35;
    [reset addTarget:self action:@selector(resetTapped) forControlEvents:UIControlEventTouchUpInside];
    [_sheet addSubview:reset];

    [self refreshUI];
    [self modeChanged];
}
- (UISlider *)sliderWithTag:(NSInteger)tag {
    UISlider *slider=[UISlider new];
    slider.tag=tag;
    slider.minimumTrackTintColor=UIColor.clearColor;
    slider.maximumTrackTintColor=UIColor.clearColor;
    slider.thumbTintColor=UIColor.whiteColor;
    [slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    // 1.84.1: alpha is shared by all three modes, so it lives on the sheet. It used
    // to be added to the slider panel while its frame was computed in sheet
    // coordinates - the slider ended up below the sheet.
    [(tag==4 ? _sheet : _sliderPanel) addSubview:slider];
    return slider;
}
- (UIView *)trackWithTag:(NSInteger)tag {
    UIView *track=[UIView new];
    track.tag=tag;
    track.layer.cornerRadius=5;
    track.clipsToBounds=YES;
    track.userInteractionEnabled=NO;
    CAGradientLayer *gradient=[CAGradientLayer layer];
    gradient.startPoint=CGPointMake(0,.5);
    gradient.endPoint=CGPointMake(1,.5);
    gradient.cornerRadius=5;
    [track.layer addSublayer:gradient];
    UIView *host=tag==14 ? _sheet : _sliderPanel;
    UIView *slider=[host viewWithTag:tag-10];
    if(slider)[host insertSubview:track belowSubview:slider];else[host addSubview:track];
    return track;
}
- (UILabel *)valueLabelWithTag:(NSInteger)tag {
    UILabel *label=[UILabel new];
    label.tag=tag;
    label.font=[UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightSemibold];
    label.textAlignment=NSTextAlignmentCenter;
    label.textColor=UIColor.labelColor;
    label.backgroundColor=UIColor.systemBackgroundColor;
    label.layer.cornerRadius=8;
    label.clipsToBounds=YES;
    [(tag==24 ? _sheet : _sliderPanel) addSubview:label];
    return label;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width=MIN(self.view.bounds.size.width-32,430);
    CGFloat height=MIN(self.view.bounds.size.height-80,560);
    CGFloat x=(self.view.bounds.size.width-width)/2;
    CGFloat y=(self.view.bounds.size.height-height)/2;
    _sheet.frame=CGRectMake(x,y,width,height);
    CGFloat pad=20,inner=width-pad*2;
    [self.view viewWithTag:0x5A31].frame=CGRectMake(pad,16,inner,24);
    [self.view viewWithTag:0x5A32].frame=CGRectMake(width-44,10,34,34);
    _mode.frame=CGRectMake(pad,48,inner,32);
    CGFloat contentTop=92;
    CGFloat contentBottom=height-152;
    CGRect content=CGRectMake(pad,contentTop,inner,MAX(120,contentBottom-contentTop));
    _gridPanel.frame=content;
    _spectrumPanel.frame=content;
    _sliderPanel.frame=content;
    if(_mode.selectedSegmentIndex==0) {
        _gridView.frame=CGRectMake(0,0,content.size.width,content.size.height);
    } else if(_mode.selectedSegmentIndex==1) {
        _spectrumView.frame=CGRectMake(0,0,content.size.width,content.size.height);
    }
    CGFloat sliderX=34;
    CGFloat valueX=inner-64;
    CGFloat sliderW=valueX-8-sliderX;
    for(NSInteger i=0;i<3;i++) {
        CGFloat rowY=6+i*56;
        UILabel *name=(UILabel *)[_sliderPanel viewWithTag:40+i];
        if(!name) {
            name=[UILabel new];name.tag=40+i;
            name.font=[UIFont systemFontOfSize:13];
            name.textColor=UIColor.secondaryLabelColor;
            name.text=@[@"红色",@"绿色",@"蓝色"][i];
            [_sliderPanel addSubview:name];
        }
        name.frame=CGRectMake(0,rowY,30,20);
        UIView *track=[_sliderPanel viewWithTag:11+i];
        track.frame=CGRectMake(sliderX,rowY+26,sliderW,10);
        ((CAGradientLayer *)track.layer.sublayers.firstObject).frame=track.bounds;
        UISlider *slider=(UISlider *)[_sliderPanel viewWithTag:1+i];
        slider.frame=CGRectMake(sliderX-2,rowY+8,sliderW+4,44);
        [_sliderPanel viewWithTag:21+i].frame=CGRectMake(valueX,rowY+13,64,32);
    }
    _hex.frame=CGRectMake(0,176,inner,28);
    UILabel *alphaName=[self.view viewWithTag:44];
    if(!alphaName) {
        alphaName=[UILabel new];alphaName.tag=44;
        alphaName.font=[UIFont systemFontOfSize:13];
        alphaName.textColor=UIColor.secondaryLabelColor;
        alphaName.text=@"不透明度";
        [_sheet addSubview:alphaName];
    }
    alphaName.frame=CGRectMake(pad,height-144,70,20);
    _alphaTrack.frame=CGRectMake(pad+34,height-118,inner-34-72,10);
    _alphaGradient.frame=_alphaTrack.bounds;
    _alphaSlider.frame=CGRectMake(pad+32,height-136,inner-34-72+4,44);
    _alphaValue.frame=CGRectMake(width-pad-64,height-131,64,32);
    UIView *presets=[self.view viewWithTag:0x5A34];
    presets.frame=CGRectMake(pad,height-96,inner,44);
    for(NSInteger i=0;i<3;i++) [presets viewWithTag:100+i].frame=CGRectMake(i*52,2,40,40);
    [self.view viewWithTag:0x5A35].frame=CGRectMake(pad,height-52,inner,36);
    [self refreshUI];
}
- (void)modeChanged {
    NSInteger index=_mode.selectedSegmentIndex;
    _gridPanel.hidden=index!=0;
    _spectrumPanel.hidden=index!=1;
    _sliderPanel.hidden=index!=2;
    if(index==1) {
        CGFloat hue=0,sat=0,bright=0;
        [[UIColor colorWithRed:_r green:_g blue:_b alpha:1] getHue:&hue saturation:&sat brightness:&bright alpha:NULL];
        [_spectrumView showHue:hue saturation:sat brightness:bright];
    }
    [self.view setNeedsLayout];
}
- (void)pickRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b {
    _r=r;_g=g;_b=b;
    [self refreshUI];
    [self publish];
}
- (void)sliderChanged {
    _r=_redSlider.value;_g=_greenSlider.value;_b=_blueSlider.value;_a=_alphaSlider.value;
    [self refreshUI];
    [self publish];
}
- (void)refreshUI {
    _redSlider.value=_r;_greenSlider.value=_g;_blueSlider.value=_b;_alphaSlider.value=_a;
    _redValue.text=[NSString stringWithFormat:@"%d",(int)lround(_r*255)];
    _greenValue.text=[NSString stringWithFormat:@"%d",(int)lround(_g*255)];
    _blueValue.text=[NSString stringWithFormat:@"%d",(int)lround(_b*255)];
    _alphaValue.text=[NSString stringWithFormat:@"%d%%",(int)lround(_a*100)];
    UIColor *current=[UIColor colorWithRed:_r green:_g blue:_b alpha:_a];
    _redGradient.colors=@[(id)[UIColor colorWithRed:0 green:_g blue:_b alpha:1].CGColor,
                          (id)[UIColor colorWithRed:1 green:_g blue:_b alpha:1].CGColor];
    _greenGradient.colors=@[(id)[UIColor colorWithRed:_r green:0 blue:_b alpha:1].CGColor,
                            (id)[UIColor colorWithRed:_r green:1 blue:_b alpha:1].CGColor];
    _blueGradient.colors=@[(id)[UIColor colorWithRed:_r green:_g blue:0 alpha:1].CGColor,
                           (id)[UIColor colorWithRed:_r green:_g blue:1 alpha:1].CGColor];
    _alphaGradient.colors=@[(id)[current colorWithAlphaComponent:0].CGColor,(id)current.CGColor];
    _hex.text=[NSString stringWithFormat:@"Hex 颜色 %@（点击复制）",LMVTextColorHex(current)];
    if(_mode.selectedSegmentIndex==1) {
        CGFloat hue=0,sat=0,bright=0;
        [current getHue:&hue saturation:&sat brightness:&bright alpha:NULL];
        [_spectrumView showHue:hue saturation:sat brightness:bright];
    }
}
- (void)publish {
    UIColor *color=[UIColor colorWithRed:_r green:_g blue:_b alpha:_a];
    LMVTextColorStore(color);
    if(self.onChange)self.onChange(color);
}
- (void)presetTapped:(UIButton *)sender {
    NSInteger slot=sender.tag-100;
    if(slot==0) {_r=_g=_b=1;}
    else if(slot==1) {_r=_g=_b=.78;}
    else {_r=_g=_b=0;}
    _a=1;
    [self refreshUI];
    [self publish];
}
- (void)resetTapped {
    LMVTextColorStore(nil);
    if(self.onChange)self.onChange(nil);
    [self closeTapped];
}
- (void)copyHex {
    UIPasteboard.generalPasteboard.string=LMVTextColorHex([UIColor colorWithRed:_r green:_g blue:_b alpha:_a]);
}
- (void)closeTapped {
    // 1.84: the last pick must be on disk and on screen before the sheet leaves.
    // Sliding then tapping X used to close with the sheet's previous colour still
    // applied, which read as "the circle did not take effect".
    [self publish];
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end
