#import <UIKit/UIKit.h>
#import "PSListController.h"

@interface WeChatKeyboardToolbarPrefsRootListController : PSListController
@end

@implementation WeChatKeyboardToolbarPrefsRootListController

- (NSArray *)specifiers {
	if (_specifiers == nil) {
		_specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
	}
	return _specifiers;
}

@end
