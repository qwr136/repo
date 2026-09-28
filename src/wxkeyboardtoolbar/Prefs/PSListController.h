// 最小化的 Preferences 私有框架声明（仅供本 bundle 编译使用）。
#import <UIKit/UIKit.h>

@interface PSViewController : UIViewController
@end

@interface PSSpecifier : NSObject
- (id)propertyForKey:(NSString *)key;
@end

@interface PSListController : PSViewController {
@protected
    id _specifiers;
}
- (NSArray *)loadSpecifiersFromPlistName:(NSString *)plistName target:(id)target;
@property (nonatomic, retain) id specifiers;
@end
