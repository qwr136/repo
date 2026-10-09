#pragma once
#import <PhotosUI/PhotosUI.h>

// PHPicker's public UIViewController is contained in our own bounded navigation.
// Its remote Photos service may still show system-owned permission/keyboard UI.
@interface LMVEasterPhotoFlow : UIViewController
@property(nonatomic, strong) PHPickerViewController *picker;
@property(nonatomic, copy) void (^cancel)(void);
- (instancetype)initWithPicker:(PHPickerViewController *)picker;
@end
@implementation LMVEasterPhotoFlow
- (instancetype)initWithPicker:(PHPickerViewController *)picker {
    if ((self = [super init])) _picker = picker;
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"导入视频（原片）";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancelFlow)];
    [self addChildViewController:self.picker];
    [self.view addSubview:self.picker.view];
    self.picker.view.frame = self.view.bounds;
    self.picker.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.picker didMoveToParentViewController:self];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.picker.view.frame = UIEdgeInsetsInsetRect(self.view.bounds, self.view.safeAreaInsets);
}
- (void)cancelFlow { if (self.cancel) self.cancel(); }
- (void)removePicker {
    if (!self.picker.parentViewController) return;
    [self.picker willMoveToParentViewController:nil];
    [self.picker.view removeFromSuperview];
    [self.picker removeFromParentViewController];
    self.picker.delegate = nil;
}
- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    if (!self.parentViewController) [self removePicker];
}
- (void)dealloc { _picker.delegate = nil; }
@end
