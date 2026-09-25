// LockVideoMaterialCell.h
// 「选择素材」行的自定义单元格：继承 PSTableCell。
// type 设成 PSLinkCell（仅影响 tap 行为，与外观无关），用 cellClass 让框架创建。
// 自己新增一个 nameLabel 居中显示文件名，去掉右侧 chevron。
#import <Preferences/Preferences.h>

@interface LockVideoMaterialCell : PSTableCell
@property (nonatomic, strong) UILabel *nameLabel;
@end
