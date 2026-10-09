#pragma once
#import <UIKit/UIKit.h>

// Only used by the contained floating picker. Regular Settings keeps native alerts.
@interface LMVMaterialPrompt : UIViewController
@property(nonatomic, copy) NSString *promptTitle, *message, *initialText, *actionTitle;
@property(nonatomic) BOOL editing, destructive;
@property(nonatomic, copy) void (^complete)(NSString *text, BOOL accepted);
@property(nonatomic, strong) UITextField *field;
@property(nonatomic, strong) UIView *card;
@end
@implementation LMVMaterialPrompt
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.22];
    self.card = [UIView new]; self.card.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.card.layer.cornerRadius = 16; self.card.layer.cornerCurve = kCACornerCurveContinuous;
    self.card.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:self.card];
    UIStackView *stack = [UIStackView new]; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO; [self.card addSubview:stack];
    UILabel *title = [UILabel new]; title.text = self.promptTitle; title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; title.numberOfLines = 0; [stack addArrangedSubview:title];
    UILabel *message = [UILabel new]; message.text = self.message; message.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline]; message.numberOfLines = 0; [stack addArrangedSubview:message];
    if (self.editing) {
        self.field = [UITextField new]; self.field.text = self.initialText; self.field.borderStyle = UITextBorderStyleRoundedRect;
        self.field.clearButtonMode = UITextFieldViewModeWhileEditing; [stack addArrangedSubview:self.field];
        [self.field.heightAnchor constraintEqualToConstant:36].active = YES;
    }
    UIStackView *buttons = [UIStackView new]; buttons.distribution = UIStackViewDistributionFillEqually; buttons.spacing = 8;
    if (self.actionTitle.length) {
        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem]; [cancel setTitle:@"取消" forState:UIControlStateNormal];
        [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside]; [buttons addArrangedSubview:cancel];
    }
    UIButton *accept = [UIButton buttonWithType:UIButtonTypeSystem]; [accept setTitle:self.actionTitle ?: @"好" forState:UIControlStateNormal];
    if (self.destructive) [accept setTitleColor:UIColor.systemRedColor forState:UIControlStateNormal];
    [accept addTarget:self action:@selector(accept) forControlEvents:UIControlEventTouchUpInside]; [buttons addArrangedSubview:accept];
    [buttons.heightAnchor constraintEqualToConstant:44].active = YES; [stack addArrangedSubview:buttons];
    [NSLayoutConstraint activateConstraints:@[
        [self.card.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:14],
        [self.card.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-14],
        [self.card.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:self.card.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor constant:-12]
    ]];
}
- (void)finish:(BOOL)accepted {
    NSString *text = self.field.text; void (^complete)(NSString *, BOOL) = self.complete;
    [self.view endEditing:YES];
    [self willMoveToParentViewController:nil]; [self.view removeFromSuperview]; [self removeFromParentViewController];
    if (complete) complete(text, accepted);
}
- (void)cancel { [self finish:NO]; }
- (void)accept { [self finish:YES]; }
@end
