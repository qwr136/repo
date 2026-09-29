#import "KeyboardTestViewController.h"

@implementation KeyboardTestViewController {
    UISearchBar *_searchBar;
    UILabel     *_hintLabel;
    UILabel     *_echoLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"键盘测试";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];

    _hintLabel = [[UILabel alloc] init];
    _hintLabel.numberOfLines = 0;
    _hintLabel.font = [UIFont systemFontOfSize:14];
    _hintLabel.textColor = [UIColor secondaryLabelColor];
    _hintLabel.text = @"点下方搜索框唤起微信输入法键盘，\n即可在本 App 内直接观察工具栏增强效果（按钮数上限 / 间距 / 边距）。\n若弹出的不是微信输入法，请先在系统「设置 → 通用 → 键盘」中启用并允许完全访问。";
    [self.view addSubview:_hintLabel];

    _searchBar = [[UISearchBar alloc] init];
    _searchBar.placeholder = @"搜索 / 测试工具栏…";
    _searchBar.delegate = self;
    _searchBar.showsCancelButton = YES;
    _searchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    [self.view addSubview:_searchBar];

    _echoLabel = [[UILabel alloc] init];
    _echoLabel.numberOfLines = 0;
    _echoLabel.font = [UIFont systemFontOfSize:15];
    _echoLabel.textColor = [UIColor labelColor];
    _echoLabel.text = @"输入内容将显示在这里。";
    [self.view addSubview:_echoLabel];

    [self layout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layout];
}

- (void)layout {
    CGFloat w = self.view.bounds.size.width;
    CGFloat pad = 16;
    _hintLabel.frame = CGRectMake(pad, 20, w - pad * 2, 120);
    _searchBar.frame = CGRectMake(pad, 150, w - pad * 2, 44);
    _echoLabel.frame = CGRectMake(pad, 210, w - pad * 2, 80);
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    /* 进入页面自动聚焦, 立即唤起键盘 */
    [_searchBar becomeFirstResponder];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    _echoLabel.text = searchText.length ? searchText : @"输入内容将显示在这里。";
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

@end
