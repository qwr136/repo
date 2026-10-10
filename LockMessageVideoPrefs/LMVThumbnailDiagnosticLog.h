#pragma once
#import <Foundation/Foundation.h>
#import <unistd.h>
// Dedicated serial writer in BOTH hosts. Playback and wallpaper quotas cannot
// swallow preview events; SpringBoard and Preferences never rotate the same file.
#ifndef LMVThumbnailDiagnostic
static BOOL LMVThumbnailDiagnosticIsEnabled(void) {
    NSNumber *enabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("DiagnosticsEnabled"), CFSTR("com.minis.lockmessagevideo"));
    return [enabled respondsToSelector:@selector(boolValue)] && enabled.boolValue;
}
static void LMVThumbnailDiagnosticWrite(NSString *event) {
    if (!event.length || !LMVThumbnailDiagnosticIsEnabled()) return;
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.minis.lockmessagevideo.thumbnail-diagnostics", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        @autoreleasepool {
            if (!LMVThumbnailDiagnosticIsEnabled()) return;
            static NSUInteger records;
            static NSTimeInterval bucket;
            NSTimeInterval now = NSDate.date.timeIntervalSince1970;
            BOOL first = !bucket || now - bucket >= 60;
            if (first) { records = 0; bucket = now; }
            // Windowed budget, not lifetime starvation. Report the dropped window.
            if (++records > 1000) return;
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *root = @"/var/mobile/LockMessageVideo";
            [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
            BOOL springboard = [NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"];
            NSString *path = [root stringByAppendingPathComponent:springboard ? @"thumbnail-preview-springboard.log" : @"thumbnail-preview-settings.log"];
            if ([[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue] > 262144) {
                NSString *previous = [path stringByAppendingString:@".1"];
                [fm removeItemAtPath:previous error:nil]; [fm moveItemAtPath:path toPath:previous error:nil];
            }
            if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}];
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            @try {
                [handle seekToEndOfFile];
                NSString *line = [NSString stringWithFormat:@"%.3f version=0.0.80 pid=%d host=%@ %@\n", now, getpid(), springboard ? @"SpringBoard" : @"Settings", records == 1000 ? @"thumbnail budget-reached retry-after-window" : event];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            } @catch (NSException *exception) {} @finally { [handle closeFile]; }
        }
    });
}
#define LMVThumbnailDiagnostic(event) LMVThumbnailDiagnosticWrite(event)
#endif
