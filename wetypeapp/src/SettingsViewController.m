#import "SettingsViewController.h"

/* 与 Tweak.x 完全一致的偏好域与键名 */
static NSString *const kDomain       = @"com.wetypeplus";
static NSString *const kEnabled      = @"enabled";
static NSString *const kMaxButtons   = @"maxButtons";
static NSString *const kHSpacing     = @"hSpacing";
static NSString *const kLeftMargin   = @"leftMargin";
static NSString *const kRightMargin  = @"rightMargin";
static NSString *const kDebugLog     = @"debugLog";

/* 行索引 */
typedef NS_ENUM(NSInteger, RowIndex) {
    RowEnabled = 0,
    RowMaxButtons,
    RowSpacing,
    RowLeft,
    RowRight,
    RowDebug,
    RowCount
};

@interface SettingsViewController ()
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISwitch *debugSwitch;
@property (nonatomic, strong) UISlider *maxSlider;
@property (nonatomic, strong) UILabel  *maxLabel;
@property (nonatomic, strong) UISlider *spacingSlider;
@property (nonatomic, strong) UILabel  *spacingLabel;
@property (nonatomic, strong) UISlider *leftSlider;
@property (nonatomic, strong) UILabel  *leftLabel;
@property (nonatomic, strong) UISlider *rightSlider;
@property (nonatomic, strong) UILabel  *rightLabel;
@end

@implementation SettingsViewController

- (instancetype)init {
    if (self = [super initWithStyle:UITableViewStyleGrouped]) {
        self.title = @"微信输入法自定义";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.estimatedRowHeight = 56;
    [self buildControls];
    [self loadPrefs];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@"恢复默认"
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(resetDefaults:)];
}

#pragma mark - 偏好读写

- (id)readKey:(NSString *)key default:(id)def {
    id v = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                       (__bridge CFStringRef)kDomain));
    return v ?: def;
}

- (void)writeKey:(NSString *)key value:(id)value {
    CFPreferencesSetValue((__bridge CFStringRef)key,
                          (__bridge CFPropertyListRef)value,
                          (__bridge CFStringRef)kDomain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    [self flashSaved];
}

- (void)loadPrefs {
    self.enabledSwitch.on = [[self readKey:kEnabled default:@YES] boolValue];
    self.debugSwitch.on   = [[self readKey:kDebugLog default:@NO] boolValue];

    NSInteger mb = [[self readKey:kMaxButtons default:@20] integerValue];
    mb = MAX(1, MIN(20, mb));
    self.maxSlider.value = (float)mb;
    self.maxLabel.text = [NSString stringWithFormat:@"%ld", (long)mb];

    CGFloat sp = MAX(0, [[self readKey:kHSpacing default:@0] floatValue]);
    self.spacingSlider.value = (float)sp;
    self.spacingLabel.text = [NSString stringWithFormat:@"%.0f pt", sp];

    CGFloat lm = MAX(0, [[self readKey:kLeftMargin default:@0] floatValue]);
    self.leftSlider.value = (float)lm;
    self.leftLabel.text = [NSString stringWithFormat:@"%.0f pt", lm];

    CGFloat rm = MAX(0, [[self readKey:kRightMargin default:@0] floatValue]);
    self.rightSlider.value = (float)rm;
    self.rightLabel.text = [NSString stringWithFormat:@"%.0f pt", rm];
}

- (void)resetDefaults:(id)sender {
    [self writeKey:kEnabled     value:@YES];
    [self writeKey:kMaxButtons  value:@20];
    [self writeKey:kHSpacing    value:@0];
    [self writeKey:kLeftMargin  value:@0];
    [self writeKey:kRightMargin value:@0];
    [self writeKey:kDebugLog    value:@NO];
    [self loadPrefs];
    [self.tableView reloadData];
}

- (void)flashSaved {
    self.navigationItem.prompt = @"已保存，收起再展开键盘即可生效";
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearPrompt) object:nil];
    [self performSelector:@selector(clearPrompt) withObject:nil afterDelay:1.6];
}

- (void)clearPrompt {
    self.navigationItem.prompt = nil;
}

#pragma mark - 控件构建

- (void)buildControls {
    _enabledSwitch = [[UISwitch alloc] init];
    [_enabledSwitch addTarget:self action:@selector(onEnabled:) forControlEvents:UIControlEventValueChanged];

    _debugSwitch = [[UISwitch alloc] init];
    [_debugSwitch addTarget:self action:@selector(onDebug:) forControlEvents:UIControlEventValueChanged];

    _maxSlider = [self sliderWithMin:1 max:20 step:1];
    [_maxSlider addTarget:self action:@selector(onMax:) forControlEvents:UIControlEventValueChanged];
    _maxLabel = [self valueLabel];

    _spacingSlider = [self sliderWithMin:0 max:60 step:1];
    [_spacingSlider addTarget:self action:@selector(onSpacing:) forControlEvents:UIControlEventValueChanged];
    _spacingLabel = [self valueLabel];

    _leftSlider = [self sliderWithMin:0 max:60 step:1];
    [_leftSlider addTarget:self action:@selector(onLeft:) forControlEvents:UIControlEventValueChanged];
    _leftLabel = [self valueLabel];

    _rightSlider = [self sliderWithMin:0 max:60 step:1];
    [_rightSlider addTarget:self action:@selector(onRight:) forControlEvents:UIControlEventValueChanged];
    _rightLabel = [self valueLabel];
}

- (UISlider *)sliderWithMin:(float)min max:(float)max step:(float)step {
    UISlider *s = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 180, 31)];
    s.minimumValue = min;
    s.maximumValue = max;
    s.value = min;
    return s;
}

- (UILabel *)valueLabel {
    UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 64, 21)];
    l.textAlignment = NSTextAlignmentRight;
    l.font = [UIFont systemFontOfSize:15];
    l.textColor = [UIColor secondaryLabelColor];
    return l;
}

#pragma mark - 事件

- (void)onEnabled:(UISwitch *)s { [self writeKey:kEnabled value:@(s.on)]; }
- (void)onDebug:(UISwitch *)s   { [self writeKey:kDebugLog value:@(s.on)]; }

- (void)onMax:(UISlider *)s {
    NSInteger v = (NSInteger)round(s.value);
    s.value = (float)v;
    self.maxLabel.text = [NSString stringWithFormat:@"%ld", (long)v];
    [self writeKey:kMaxButtons value:@(v)];
}

- (void)onSpacing:(UISlider *)s {
    CGFloat v = round(s.value);
    s.value = v;
    self.spacingLabel.text = [NSString stringWithFormat:@"%.0f pt", v];
    [self writeKey:kHSpacing value:@(v)];
}

- (void)onLeft:(UISlider *)s {
    CGFloat v = round(s.value);
    s.value = v;
    self.leftLabel.text = [NSString stringWithFormat:@"%.0f pt", v];
    [self writeKey:kLeftMargin value:@(v)];
}

- (void)onRight:(UISlider *)s {
    CGFloat v = round(s.value);
    s.value = v;
    self.rightLabel.text = [NSString stringWithFormat:@"%.0f pt", v];
    [self writeKey:kRightMargin value:@(v)];
}

#pragma mark - UITableView

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 3;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;          // 总开关
    if (section == 1) return 4;          // 数量 + 三项间距/边距
    return 1;                            // 诊断日志
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"总开关";
    if (section == 1) return @"工具栏布局";
    return @"调试";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"关闭后插件对任何输入法都不生效。";
    if (section == 1) return @"间距/边距设为 0 表示保持微信输入法原版；最大按钮数上限 1-20。";
    return @"开启后可在 syslog 中搜索 [WetypeToolbarPlus] 查看内部类名，便于精确适配。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cid = @"cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cid];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    [self configureCell:cell atIndexPath:indexPath];
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)ip {
    cell.textLabel.text = nil;
    cell.accessoryView = nil;

    // 清掉可能的旧 slider 容器
    for (UIView *v in cell.contentView.subviews) {
        if ([v isKindOfClass:[UISlider class]] || [v isKindOfClass:[UILabel class]]) [v removeFromSuperview];
    }

    if (ip.section == 0) {
        cell.textLabel.text = @"启用插件";
        cell.accessoryView = self.enabledSwitch;
    } else if (ip.section == 2) {
        cell.textLabel.text = @"诊断日志";
        cell.accessoryView = self.debugSwitch;
    } else {
        switch (ip.row) {
            case RowMaxButtons: {
                cell.textLabel.text = @"最大按钮数";
                [self embedSlider:self.maxSlider label:self.maxLabel inCell:cell];
                break;
            }
            case RowSpacing: {
                cell.textLabel.text = @"按钮间距";
                [self embedSlider:self.spacingSlider label:self.spacingLabel inCell:cell];
                break;
            }
            case RowLeft: {
                cell.textLabel.text = @"左边距";
                [self embedSlider:self.leftSlider label:self.leftLabel inCell:cell];
                break;
            }
            case RowRight: {
                cell.textLabel.text = @"右边距";
                [self embedSlider:self.rightSlider label:self.rightLabel inCell:cell];
                break;
            }
            default: break;
        }
    }
}

- (void)embedSlider:(UISlider *)slider label:(UILabel *)label inCell:(UITableViewCell *)cell {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 260, 31)];
    slider.frame = CGRectMake(0, 0, 196, 31);
    label.frame = CGRectMake(200, 0, 60, 31);
    [container addSubview:slider];
    [container addSubview:label];
    cell.accessoryView = container;
}

@end
