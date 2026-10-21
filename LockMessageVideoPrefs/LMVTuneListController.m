#import "LMVTuneListController.h"
#import "LMVTuneController.h"
#import <Preferences/PSSpecifier.h>
#import "../LMVPanelTuning.h"

@implementation LMVTuneListController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"功能面板参数";
}
// One row per channel, in LMVTuneTargets' order - the same data the root list used
// to render directly. Adding a channel still only needs the new entry there.
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *rows = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"功能面板参数"];
    [group setProperty:@"点进任意一项，页顶会显示它的当前实际生效值。" forKey:@"footerText"];
    [rows addObject:group];
    for (NSDictionary *item in LMVTuneTargets()) {
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:item[@"name"]
                                                          target:self set:nil get:nil
                                                          detail:nil cell:PSButtonCell edit:nil];
        row.buttonAction = @selector(openTune:);
        [row setProperty:item[@"id"] forKey:@"tuneTarget"];
        [rows addObject:row];
    }
    _specifiers = rows;
    return _specifiers;
}
- (void)openTune:(PSSpecifier *)specifier {
    id value = [specifier propertyForKey:@"tuneTarget"];
    if (![value isKindOfClass:NSString.class] || ![value length]) return;
    LMVTuneController *page = [[LMVTuneController alloc] initWithTarget:value
                                                                   name:LMVTuneTargetName(value)];
    [self.navigationController pushViewController:page animated:YES];
}
@end
