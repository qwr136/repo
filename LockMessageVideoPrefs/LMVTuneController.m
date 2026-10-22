#import "LMVTuneController.h"
#import <Preferences/PSSpecifier.h>
#import "../LMVPanelTuning.h"

@interface LMVTuneController ()
@property (nonatomic, copy) NSString *target;
@property (nonatomic, copy) NSString *channelName;
// 2.48: the block at the top of the page that answers "is my value actually in
// effect?". It is a group footer, refreshed once a second while the page is visible.
@property (nonatomic, strong) PSSpecifier *statusGroup;
@property (nonatomic, strong) NSTimer *statusTimer;
@end

@implementation LMVTuneController
- (instancetype)initWithTarget:(NSString *)target name:(NSString *)name {
    if ((self = [super init])) {
        _target = [target copy];
        _channelName = [name copy];
        self.title = name;
    }
    return self;
}

// Short names so the status line fits on one line on a phone.
static NSString *LMVTuneShortLabel(NSString *key) {
    if ([key isEqualToString:@"ProbeHz"] || [key isEqualToString:@"TickHz"]) return @"检测";
    if ([key isEqualToString:@"FPS"]) return @"刷新";
    if ([key isEqualToString:@"IdleFPS"]) return @"可见";
    if ([key isEqualToString:@"WantFPS"]) return @"实际";
    if ([key isEqualToString:@"CoveredFPS"]) return @"遮挡";
    if ([key isEqualToString:@"ShowDelayMs"]) return @"出现";
    if ([key isEqualToString:@"HideDelayMs"]) return @"关闭";
    if ([key isEqualToString:@"HookThrottleMs"]) return @"节流";
    if ([key isEqualToString:@"ProbeIntervalMs"]) return @"节流";
    if ([key isEqualToString:@"SnapshotMs"]) return @"快照";
    if ([key isEqualToString:@"ProbeSnapshotMs"]) return @"快照";
    if ([key isEqualToString:@"CoverWatchHz"]) return @"遮挡检测";
    return key;
}
// 2.52: "when was this observed". The shared age answers "is the channel alive";
// the per-key age answers "is this particular number current". Both are needed: the
// desktop's visible-state rate can be minutes old while the channel talks to us
// every second at its covered heartbeat.
static NSString *LMVTuneAgoText(NSTimeInterval age) {
    if (age < 0) return @"未上报";
    if (age < 5) return @"刚刚";
    if (age < 60) return [NSString stringWithFormat:@"%.0f 秒前", age];
    if (age < 3600) return [NSString stringWithFormat:@"%.0f 分钟前", age / 60];
    return [NSString stringWithFormat:@"%.1f 小时前", age / 3600];
}
- (NSString *)runtimeStatus {
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    for (NSDictionary *group in LMVTuneGroupsForTarget(self.target)) {
        for (NSDictionary *p in group[@"params"]) {
            NSNumber *value = LMVTuneRuntime(self.target, p[@"key"]);
            [parts addObject:[NSString stringWithFormat:@"%@ %@", LMVTuneShortLabel(p[@"key"]),
                value ? [NSString stringWithFormat:@"%ld", (long)value.integerValue] : @"未上报"]];
        }
    }
    // The desktop reports the frame rate it really applied while it was VISIBLE.
    // 2.52: that value only ever comes from the desktop, and this page is an app - the
    // desktop is covered for as long as the page is on screen - so it is necessarily a
    // past observation. Stamping it with its own age stops "10" from reading as the
    // current value; when it disagrees with the saved setting, say what happens next.
    NSNumber *idleApplied = LMVTuneRuntime(self.target, @"IdleApplied");
    NSString *idleHint = nil;
    if (idleApplied) {
        NSTimeInterval idleAge = LMVTuneRuntimeKeyAge(self.target, @"IdleApplied");
        [parts addObject:[NSString stringWithFormat:@"桌面时 %ld（%@）",
            (long)idleApplied.integerValue, LMVTuneAgoText(idleAge)]];
        NSNumber *idleSetting = LMVTuneRuntime(self.target, @"IdleFPS");
        if (idleSetting && idleSetting.integerValue != idleApplied.integerValue)
            idleHint = [NSString stringWithFormat:@"回桌面后按 %ld 生效", (long)idleSetting.integerValue];
    }
    NSNumber *want = LMVTuneRuntime(self.target, @"WantFPS");
    if (want) {
        NSNumber *reason = LMVTuneRuntime(self.target, @"WantReason");
        NSString *suffix = @"";
        if (reason) {
            NSInteger code = reason.integerValue;
            if (code == 2) suffix = @"，爆发中";
            else if (code == 1) suffix = @"，被遮挡";
            else suffix = @"，桌面可见";
        }
        [parts addObject:[NSString stringWithFormat:@"实际 %ld%@", (long)want.integerValue, suffix]];
    }
    // 2.54: "实际" is the value that was APPLIED to the display link, which cannot
    // answer "is it really delivering 20 frames?". This one is counted from the
    // callbacks themselves, so 设定 20 / 实测 19 is a real comparison.
    NSNumber *measured = LMVTuneRuntime(self.target, @"MeasuredFPS");
    if (measured) {
        NSTimeInterval measuredAge = LMVTuneRuntimeKeyAge(self.target, @"MeasuredFPS");
        [parts addObject:[NSString stringWithFormat:@"实测 %ld（%@）",
            (long)measured.integerValue, LMVTuneAgoText(measuredAge)]];
    }
    NSTimeInterval age = LMVTuneRuntimeAge(self.target);
    NSString *freshness = nil;
    if (age < 0) freshness = @"通道未运行";
    else if (age < 1.5) freshness = @"刚刚";
    else if (age < 10) freshness = [NSString stringWithFormat:@"%.0f 秒前", age];
    // The timestamp only moves when the VALUE changes, so "287 秒前" meant "unchanged
    // for 287 seconds", which read as "not working". Say what it means.
    else freshness = @"持续生效";
    NSString *line = [NSString stringWithFormat:@"当前生效：%@（%@）",
                      [parts componentsJoinedByString:@" / "], freshness];
    // Its own line: the hint is an action, not another measured value.
    if (idleHint.length) line = [line stringByAppendingFormat:@"\n%@", idleHint];
    return line;
}
- (void)refreshStatus {
    if (!self.statusGroup) return;
    NSString *text = [self runtimeStatus];
    if ([text isEqualToString:[self.statusGroup propertyForKey:@"footerText"]]) return;
    [self.statusGroup setProperty:text forKey:@"footerText"];
    [self reloadSpecifier:self.statusGroup animated:NO];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
    if (self.statusTimer) return;
    __weak typeof(self) weakSelf = self;
    self.statusTimer = [NSTimer timerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshStatus];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.statusTimer forMode:NSRunLoopCommonModes];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.statusTimer invalidate];
    self.statusTimer = nil;
}
- (NSString *)labelForParam:(NSDictionary *)p {
    // 2.45: every remaining parameter is numeric, so the enum wording is gone.
    NSInteger current = LMVTuneValue(self.target, p[@"key"]);
    return [NSString stringWithFormat:@"%@：%ld", p[@"title"], (long)current];
}
// 2.41: PSSliderCell never drew its label on the user's iOS, so a row was just a
// nameless bar. Numbers are edited by tapping the row instead - the title and the
// current value are always visible, which is the whole point of a settings page.
- (void)editNumber:(PSSpecifier *)specifier {
    NSDictionary *p = [specifier propertyForKey:@"tuneParam"];
    NSInteger current = LMVTuneValue(self.target, p[@"key"]);
    NSString *message = [NSString stringWithFormat:@"范围 %@ ~ %@", p[@"min"], p[@"max"]];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:p[@"title"]
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.keyboardType = UIKeyboardTypeNumberPad;
        field.text = [NSString stringWithFormat:@"%ld", (long)current];
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSInteger value = [alert.textFields.firstObject.text integerValue];
        LMVTuneSetValue(weakSelf.target, p[@"key"], value);
        NSInteger applied = LMVTuneValue(weakSelf.target, p[@"key"]);
        [specifier setName:[NSString stringWithFormat:@"%@：%ld", p[@"title"], (long)applied]];
        [weakSelf reloadSpecifier:specifier animated:YES];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (id)readValue:(PSSpecifier *)specifier {
    return @(LMVTuneValue(self.target, [specifier propertyForKey:@"tuneKey"]));
}
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    LMVTuneSetValue(self.target, [specifier propertyForKey:@"tuneKey"], [value integerValue]);
}
- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *rows = [NSMutableArray array];
        PSSpecifier *status = [PSSpecifier groupSpecifierWithName:@"当前生效"];
        [status setProperty:[self runtimeStatus] forKey:@"footerText"];
        self.statusGroup = status;
        [rows addObject:status];
        for (NSDictionary *group in LMVTuneGroupsForTarget(self.target)) {
            [rows addObject:[PSSpecifier groupSpecifierWithName:group[@"title"]]];
            for (NSDictionary *p in group[@"params"]) {
                PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:[self labelForParam:p]
                                                                target:self set:nil get:nil
                                                                detail:nil cell:PSButtonCell edit:nil];
                s.buttonAction = @selector(editNumber:);
                [s setProperty:p[@"key"] forKey:@"tuneKey"];
                [s setProperty:p forKey:@"tuneParam"];
                [rows addObject:s];
            }
        }
        _specifiers = [rows copy];
    }
    return _specifiers;
}
@end
