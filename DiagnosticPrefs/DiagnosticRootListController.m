#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface DiagnosticRootListController : PSListController
@end
@implementation DiagnosticRootListController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"消息背景诊断"; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}
@end
