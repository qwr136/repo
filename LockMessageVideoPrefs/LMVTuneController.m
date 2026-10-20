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
    NSArray *choices = p[@"choices"];
    NSArray *values = p[@"values"];
    if (!choices.count) return p[@"title"];
    NSInteger current = LMVTuneValue(self.target, p[@"key"]);
    NSUInteger idx = [values indexOfObject:@(current)];
    NSString *choice = (idx != NSNotFound && idx < choices.count) ? choices[idx] : @"?";
    return [NSString stringWithFormat:@"%@：%@", p[@"title"], choice];
}

- (id)readValue:(PSSpecifier *)specifier {
    return @(LMVTuneValue(self.target, [specifier propertyForKey:@"tuneKey"]));
}
- (void)writeValue:(id)value specifier:(PSSpecifier *)specifier {
    LMVTuneSetValue(self.target, [specifier propertyForKey:@"tuneKey"], [value integerValue]);
}
- (void)cycleEnum:(PSSpecifier *)specifier {
    NSDictionary *p = [specifier propertyForKey:@"tuneParam"];
    NSArray *choices = p[@"choices"], *values = p[@"values"];
    if (!choices.count || choices.count != values.count) return;
    NSInteger current = LMVTuneValue(self.target, p[@"key"]);
    NSUInteger idx = [values indexOfObject:@(current)];
    NSUInteger next = (idx == NSNotFound || idx + 1 >= values.count) ? 0 : idx + 1;
    LMVTuneSetValue(self.target, p[@"key"], [values[next] integerValue]);
    [specifier setName:[NSString stringWithFormat:@"%@：%@", p[@"title"], choices[next]]];
    [self reloadSpecifier:specifier animated:YES];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *group in LMVTuneGroupsForTarget(self.target)) {
            [rows addObject:[PSSpecifier groupSpecifierWithName:group[@"title"]]];
            for (NSDictionary *p in group[@"params"]) {
                if ([p[@"choices"] count]) {
                    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:[self labelForParam:p]
                                                                    target:self set:nil get:nil
                                                                    detail:nil cell:PSButtonCell edit:nil];
                    s.buttonAction = @selector(cycleEnum:);
                    [s setProperty:p[@"key"] forKey:@"tuneKey"];
                    [s setProperty:p forKey:@"tuneParam"];
                    [rows addObject:s];
                } else {
                    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:p[@"title"]
                                                                    target:self
                                                                       set:@selector(writeValue:specifier:)
                                                                       get:@selector(readValue:)
                                                                    detail:nil cell:PSSliderCell edit:nil];
                    [s setProperty:p[@"key"] forKey:@"tuneKey"];
                    [s setProperty:@([p[@"min"] integerValue]) forKey:@"min"];
                    [s setProperty:@([p[@"max"] integerValue]) forKey:@"max"];
                    [s setProperty:@([p[@"def"] integerValue]) forKey:@"default"];
                    [rows addObject:s];
                }
            }
        }
        _specifiers = [rows copy];
    }
    return _specifiers;
}
@end
