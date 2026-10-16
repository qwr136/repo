#pragma once
// 1.50: a one-shot list chooser for the floating panel.
//
// The floating panel owns no PRESENTATION role - every choice inside it is either a
// pushed controller (LMVMaterialPicker) or a child view (LMVMaterialPrompt) - so the
// "认领刚用过的面板" row cannot use a UIAlertController action sheet. This is the
// smallest thing that keeps that rule: a pushed table of strings that reports the
// row the user tapped and pops itself.
//
// Split into its own header (rather than living in LMVEasterPanel.h) so the panel's
// own cell/selection sources stay the single owner of those delegate selectors -
// several source contracts slice those methods by anchor.
#import <UIKit/UIKit.h>

@interface LMVEasterChoice:UITableViewController
@property(nonatomic,strong) NSArray<NSString *> *options;
@property(nonatomic,copy) void (^pick)(NSInteger index);
@end

@implementation LMVEasterChoice
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)self.options.count;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)index {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = self.options[index.row];
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)index {
    [tableView deselectRowAtIndexPath:index animated:YES];
    if (self.pick) self.pick(index.row);
    [self.navigationController popViewControllerAnimated:YES];
}
@end
