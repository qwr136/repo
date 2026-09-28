#import <UIKit/UIKit.h>
#import "PSListController.h"

@interface WXKeyboardToolbarPrefsRootListController : PSListController
@end

@implementation WXKeyboardToolbarPrefsRootListController

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

@end
