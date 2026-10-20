#import <Preferences/PSListController.h>

// 2.39: one page per video channel. 2.44 left a single 探测 group (frequency,
// show/hide delay, hook throttle); 2.45 dropped the enum row form, so every row is a
// numeric value edited by tapping it. Values live under Tune.<target>.<key>
// (see LMVPanelTuning.h).
@interface LMVTuneController : PSListController
- (instancetype)initWithTarget:(NSString *)target name:(NSString *)name;
@property (nonatomic, copy, readonly) NSString *target;
@end
