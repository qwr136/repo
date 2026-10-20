#import "LMVTuneController.h"
#import <Preferences/PSSpecifier.h>
#import "../LMVPanelTuning.h"

@interface LMVTuneController ()
@property (nonatomic, copy) NSString *target;
@property (nonatomic, copy) NSString *channelName;
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
