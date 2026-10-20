#import <Preferences/PSListController.h>

// 2.39: one page per video channel - 探测 / 播放 / 可见性 / 性能, all sliders and
// enum rows. Values live under Tune.<target>.<key> (see LMVPanelTuning.h).
@interface LMVTuneController : PSListController
- (instancetype)initWithTarget:(NSString *)target name:(NSString *)name;
@property (nonatomic, copy, readonly) NSString *target;
@end
