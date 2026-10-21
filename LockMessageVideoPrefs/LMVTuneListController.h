#import <Preferences/PSListController.h>

// 2.54: the index for 设置 → 自定义参数. The user asked for a two-level menu: one
// entry in the root list, a page that lists every channel, then that channel's own
// parameters. 2.52 had flattened all eleven rows into the root list, which made the
// settings page look like a channel switcher.
@interface LMVTuneListController : PSListController
@end
