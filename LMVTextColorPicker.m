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

@interface LMVTextColorPicker () {
    UIView *_sheet;
    UILabel *_hex;
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
    [_sheet addSubview:_hex];

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
}
- (UISlider *)sliderWithTag:(NSInteger)tag {
    UISlider *slider=[UISlider new];
    slider.tag=tag;
    slider.minimumTrackTintColor=UIColor.clearColor;
    slider.maximumTrackTintColor=UIColor.clearColor;
    slider.thumbTintColor=UIColor.whiteColor;
    [slider addTarget:self action:@selector(sliderChanged) forControlEvents:UIControlEventValueChanged];
    [_sheet addSubview:slider];
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
    UIView *slider=[_sheet viewWithTag:tag-10];
    if(slider)[_sheet insertSubview:track belowSubview:slider];else[_sheet addSubview:track];
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
    [_sheet addSubview:label];
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
    CGFloat sliderX=pad+34;
    CGFloat valueX=width-pad-64;
    CGFloat sliderW=valueX-8-sliderX;
    for(NSInteger i=0;i<3;i++) {
        CGFloat rowY=58+i*56;
        UILabel *name=(UILabel *)[self.view viewWithTag:40+i];
        if(!name) {
            name=[UILabel new];name.tag=40+i;
            name.font=[UIFont systemFontOfSize:13];
            name.textColor=UIColor.secondaryLabelColor;
            name.text=@[@"红色",@"绿色",@"蓝色"][i];
            [_sheet addSubview:name];
        }
        name.frame=CGRectMake(pad,rowY,30,20);
        UIView *track=[self.view viewWithTag:11+i];
        track.frame=CGRectMake(sliderX,rowY+26,sliderW,10);
        ((CAGradientLayer *)track.layer.sublayers.firstObject).frame=track.bounds;
        UISlider *slider=(UISlider *)[self.view viewWithTag:1+i];
        slider.frame=CGRectMake(sliderX-2,rowY+8,sliderW+4,44);
        [self.view viewWithTag:21+i].frame=CGRectMake(valueX,rowY+13,64,32);
    }
    _hex.frame=CGRectMake(pad,236,inner,28);
    UILabel *alphaName=[self.view viewWithTag:44];
    if(!alphaName) {
        alphaName=[UILabel new];alphaName.tag=44;
        alphaName.font=[UIFont systemFontOfSize:13];
        alphaName.textColor=UIColor.secondaryLabelColor;
        alphaName.text=@"不透明度";
        [_sheet addSubview:alphaName];
    }
    alphaName.frame=CGRectMake(pad,282,70,20);
    _alphaTrack.frame=CGRectMake(sliderX,308,sliderW,10);
    _alphaGradient.frame=_alphaTrack.bounds;
    _alphaSlider.frame=CGRectMake(sliderX-2,290,sliderW+4,44);
    _alphaValue.frame=CGRectMake(valueX,295,64,32);
    UIView *presets=[self.view viewWithTag:0x5A34];
    presets.frame=CGRectMake(pad,352,inner,44);
    for(NSInteger i=0;i<3;i++) [presets viewWithTag:100+i].frame=CGRectMake(i*52,2,40,40);
    [self.view viewWithTag:0x5A35].frame=CGRectMake(pad,height-52,inner,36);
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
    [self dismissViewControllerAnimated:YES completion:nil];
}
@end
