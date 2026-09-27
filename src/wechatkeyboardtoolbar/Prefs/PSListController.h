// 最小化的 Preferences 私有框架声明（仅供本 bundle 编译使用）。
// 若编译环境的 SDK 已带完整 Preferences headers，本文件也会被
// 引号 include 优先命中，声明自洽、互不冲突。
#import <UIKit/UIKit.h>

@interface PSViewController : UIViewController
@end

@interface PSListController : PSViewController {
@protected
	id _specifiers;
}
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)plistName target:(id)target;
@property (nonatomic, retain) id specifiers;
@end
