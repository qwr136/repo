#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

static NSString * const kLMVPrefsPath = @"/var/jb/var/mobile/Library/Preferences/com.minis.lockmessagevideo.plist";
static NSString * const kLMVLogDir = @"/var/mobile/LockMessageVideo";
static NSString * const kLMVLogPath = @"/var/mobile/LockMessageVideo/view-tree.log";

static BOOL LMVEnabled(void) {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:kLMVPrefsPath] ?: @{};
    return [p[@"Enabled"] boolValue];
}

static void LMVWriteLog(NSString *line) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:kLMVLogDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *old = [NSString stringWithContentsOfFile:kLMVLogPath encoding:NSUTF8StringEncoding error:nil] ?: @"";
    if (old.length > 512 * 1024) old = [old substringFromIndex:old.length - 256 * 1024];
    NSString *text = [old stringByAppendingFormat:@"%@\n", line];
    [text writeToFile:kLMVLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

static void LMVDumpView(UIView *view, NSUInteger depth, NSMutableString *out) {
    if (!view || depth > 14) return;
    NSString *indent = [@"  " stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    NSString *cls = NSStringFromClass(view.class);
    CGRect f = view.frame;
    [out appendFormat:@"%@%@ frame=(%.1f,%.1f,%.1f,%.1f) hidden=%d alpha=%.2f subviews=%lu\n", indent, cls, f.origin.x, f.origin.y, f.size.width, f.size.height, view.hidden, view.alpha, (unsigned long)view.subviews.count];
    for (UIView *child in view.subviews) LMVDumpView(child, depth + 1, out);
}

static void LMVDumpSpringBoardWindows(void) {
    if (!LMVEnabled()) return;
    NSMutableString *out = [NSMutableString stringWithFormat:@"\n===== LockMessageVideo %@ =====\n", [NSDate date]];
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in [(UIWindowScene *)scene windows]) {
            [out appendFormat:@"WINDOW %@ level=%.1f hidden=%d\n", NSStringFromClass(window.class), window.windowLevel, window.hidden];
            LMVDumpView(window, 0, out);
        }
    }
    LMVWriteLog(out);
}

%hook CSCoverSheetViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    LMVDumpSpringBoardWindows();
}
- (void)viewDidLayoutSubviews {
    %orig;
    static BOOL once = NO;
    if (!once) { once = YES; LMVDumpSpringBoardWindows(); }
}
%end

%hook NCNotificationShortLookView
- (void)layoutSubviews {
    %orig;
    LMVDumpSpringBoardWindows();
}
%end

%hook NCNotificationListCell
- (void)layoutSubviews {
    %orig;
    LMVDumpSpringBoardWindows();
}
%end

%ctor {
    @autoreleasepool {
        [[NSFileManager defaultManager] createDirectoryAtPath:kLMVLogDir withIntermediateDirectories:YES attributes:nil error:nil];
        LMVWriteLog(@"LockMessageVideo diagnostic tweak loaded");
    }
}
