#import "LogViewController.h"

@implementation LogViewController {
    UITextView  *_textView;
    UILabel     *_emptyLabel;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"查看日志";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    _textView = [[UITextView alloc] initWithFrame:self.view.bounds];
    _textView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _textView.font = [UIFont fontWithName:@"Menlo" size:11] ?: [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    _textView.editable = NO;
    _textView.alwaysBounceVertical = YES;
    _textView.textColor = [UIColor labelColor];
    [self.view addSubview:_textView];

    _emptyLabel = [[UILabel alloc] initWithFrame:self.view.bounds];
    _emptyLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _emptyLabel.textAlignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = [UIColor secondaryLabelColor];
    _emptyLabel.numberOfLines = 0;
    _emptyLabel.text = @"暂无日志。\n请先在「调试 → 诊断日志」中打开开关，\n然后切换到微信输入法键盘。";
    [self.view addSubview:_emptyLabel];

    UIBarButtonItem *refresh = [[UIBarButtonItem alloc] initWithTitle:@"刷新"
                                                                style:UIBarButtonItemStylePlain
                                                               target:self
                                                               action:@selector(reloadLog)];
    UIBarButtonItem *copy = [[UIBarButtonItem alloc] initWithTitle:@"复制"
                                                             style:UIBarButtonItemStylePlain
                                                            target:self
                                                            action:@selector(copyLog)];
    UIBarButtonItem *clear = [[UIBarButtonItem alloc] initWithTitle:@"清空"
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(clearLog)];
    self.navigationItem.rightBarButtonItems = @[clear, copy, refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadLog];
}

- (void)reloadLog {
    NSString *content = [NSString stringWithContentsOfFile:TP_LOG_PATH
                                                   encoding:NSUTF8StringEncoding
                                                      error:nil];
    if (content.length) {
        _textView.text = content;
        _textView.hidden = NO;
        _emptyLabel.hidden = YES;
        /* 滚动到底部, 看最新一条 */
        NSRange end = NSMakeRange(_textView.text.length, 0);
        [_textView scrollRangeToVisible:end];
    } else {
        _textView.hidden = YES;
        _emptyLabel.hidden = NO;
    }
}

- (void)copyLog {
    if (_textView.text.length) {
        [UIPasteboard generalPasteboard].string = _textView.text;
        [self flash:@"已复制"];
    }
}

- (void)clearLog {
    [[NSFileManager defaultManager] removeItemAtPath:TP_LOG_PATH error:nil];
    [self reloadLog];
    [self flash:@"已清空"];
}

- (void)flash:(NSString *)msg {
    self.navigationItem.prompt = msg;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(clearPrompt) object:nil];
    [self performSelector:@selector(clearPrompt) withObject:nil afterDelay:1.2];
}

- (void)clearPrompt {
    self.navigationItem.prompt = nil;
}

@end
