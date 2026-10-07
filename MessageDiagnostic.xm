#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>

static CFStringRef const kDiagPrefs = CFSTR("com.minis.lockmessagevideo.message-diagnostic");
static NSString * const kDiagLog = @"/var/mobile/LockMessageVideo/message-diagnostic.log";
static const NSUInteger kDiagMaxBytes = 1024 * 1024;
static NSMutableDictionary<NSValue *, NSNumber *> *MDLastLog;
static BOOL MDEnabled(void) {
    CFPreferencesAppSynchronize(kDiagPrefs);
    CFTypeRef value = CFPreferencesCopyAppValue(CFSTR("Enabled"), kDiagPrefs);
    BOOL enabled = value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)value);
    if (value) CFRelease(value);
    return enabled;
}
static NSString *MDPointer(id object) { return object ? [NSString stringWithFormat:@"%p", object] : @"0x0"; }
static NSString *MDRect(CGRect rect) { return NSStringFromCGRect(rect); }
static NSString *MDTransform(CGAffineTransform t) { return NSStringFromCGAffineTransform(t); }
static NSString *MDAncestry(UIView *view) {
    NSMutableArray *classes = [NSMutableArray array];
    NSUInteger depth = 0;
    for (UIView *v = view; v && depth++ < 10; v = v.superview) [classes addObject:NSStringFromClass(v.class) ?: @"?"];
    return [classes componentsJoinedByString:@"<-"];
}
static BOOL MDIsExcluded(UIView *view) {
    for (UIView *v = view; v && v != view.window; v = v.superview) {
        NSString *name = NSStringFromClass(v.class);
        if ([name containsString:@"CSActivityItemContentView"] || [name containsString:@"LiveActivity"] || [name containsString:@"ActionButtons"] || [name containsString:@"Options"] || [name containsString:@"Clear"]) return YES;
    }
    return NO;
}
static NSArray<NSString *> *MDLayerMetadata(UIView *cell) {
    NSMutableArray *found = [NSMutableArray array];
    NSMutableArray *pending = [NSMutableArray arrayWithObject:cell.layer];
    NSUInteger visited = 0;
    while (pending.count && visited++ < 160) {
        CALayer *layer = pending.lastObject; [pending removeLastObject];
        NSString *name = NSStringFromClass(layer.class) ?: @"?";
        if ([name containsString:@"AVPlayerLayer"] || [name containsString:@"Video"] || layer.delegate) {
            NSString *owner = layer.delegate ? NSStringFromClass([layer.delegate class]) : @"none";
            [found addObject:[NSString stringWithFormat:@"layer=%@ owner=%@ ptr=%@ frame=%@ bounds=%@ transform=%@ mask=%@ corner=%.2f", name, owner, MDPointer(layer), MDRect(layer.frame), MDRect(layer.bounds), MDTransform(layer.affineTransform), MDPointer(layer.mask), layer.cornerRadius]];
        }
        [pending addObjectsFromArray:layer.sublayers ?: @[]];
    }
    return found;
}
static void MDRotateIfNeeded(void) {
    struct stat st;
    if (stat(kDiagLog.fileSystemRepresentation, &st) == 0 && st.st_size >= kDiagMaxBytes) {
        NSString *old = [kDiagLog stringByAppendingString:@".1"];
        unlink(old.fileSystemRepresentation);
        rename(kDiagLog.fileSystemRepresentation, old.fileSystemRepresentation);
    }
}
static void MDLogCell(UIView *cell, NSString *event) {
    if (!MDEnabled() || !cell || MDIsExcluded(cell)) return;
    if (!MDLastLog) MDLastLog = [NSMutableDictionary dictionary];
    NSValue *key = [NSValue valueWithNonretainedObject:cell];
    NSTimeInterval now = CACurrentMediaTime();
    NSNumber *last = MDLastLog[key];
    if ([event isEqualToString:@"layout"] && last && now - last.doubleValue < 0.25) return;
    MDLastLog[key] = @(now);
    NSMutableString *line = [NSMutableString stringWithFormat:@"t=%.6f event=%@ cell=%@ class=%@ frame=%@ bounds=%@ transform=%@ window=%@ windowClass=%@ ancestry=%@ masks=%d corner=%.2f", now, event, MDPointer(cell), NSStringFromClass(cell.class), MDRect(cell.frame), MDRect(cell.bounds), MDTransform(cell.transform), MDPointer(cell.window), cell.window ? NSStringFromClass(cell.window.class) : @"none", MDAncestry(cell), cell.layer.masksToBounds, cell.layer.cornerRadius];
    NSArray *layers = MDLayerMetadata(cell);
    if (layers.count) [line appendFormat:@" overlays=[%@]", [layers componentsJoinedByString:@" | "]];
    [line appendString:@"\n"];
    NSString *dir = [kDiagLog stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    MDRotateIfNeeded();
    int fd = open(kDiagLog.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd >= 0) { write(fd, line.UTF8String, strlen(line.UTF8String)); close(fd); }
}

%hook NCNotificationListCell
- (void)didMoveToWindow { %orig; MDLogCell(self, self.window ? @"attach" : @"detach"); }
- (void)prepareForReuse { MDLogCell(self, @"reuse-before"); %orig; MDLogCell(self, @"reuse-after"); }
- (void)layoutSubviews { %orig; MDLogCell(self, @"layout"); }
- (void)removeFromSuperview { MDLogCell(self, @"detach-before"); %orig; }
%end

%ctor {
    if (!NSClassFromString(@"NCNotificationListCell")) return;
    MDLastLog = [NSMutableDictionary dictionary];
}
