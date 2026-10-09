#pragma once
#import <Foundation/Foundation.h>
// Settings and SpringBoard share poster files, but keep diagnostic records separate.
#ifndef LMVThumbnailDiagnostic
static void LMVThumbnailDiagnosticWrite(NSString *event) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.minis.lockmessagevideo.thumbnail-diagnostics", DISPATCH_QUEUE_SERIAL); });
    dispatch_async(queue, ^{
        @autoreleasepool {
            NSNumber *enabled = (__bridge_transfer NSNumber *)CFPreferencesCopyAppValue(CFSTR("DiagnosticsEnabled"), CFSTR("com.minis.lockmessagevideo"));
            if (![enabled respondsToSelector:@selector(boolValue)] || !enabled.boolValue) return;
            static NSUInteger records;
            if (++records > 100) return;
            NSFileManager *fm = NSFileManager.defaultManager;
            NSString *root = @"/var/mobile/LockMessageVideo";
            [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *path = [root stringByAppendingPathComponent:@"thumbnail-preview.log"];
            if ([[fm attributesOfItemAtPath:path error:nil][NSFileSize] unsignedLongLongValue] > 65536) {
                NSString *previous = [path stringByAppendingString:@".1"];
                [fm removeItemAtPath:previous error:nil]; [fm moveItemAtPath:path toPath:previous error:nil];
            }
            if (![fm fileExistsAtPath:path]) [fm createFileAtPath:path contents:nil attributes:@{NSFilePosixPermissions:@0600}];
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
            @try {
                [handle seekToEndOfFile];
                NSString *line = [NSString stringWithFormat:@"%.3f %@\n", NSDate.date.timeIntervalSince1970, event];
                [handle writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
            } @catch (NSException *exception) {} @finally { [handle closeFile]; }
        }
    });
}
#define LMVThumbnailDiagnostic(event) LMVThumbnailDiagnosticWrite(event)
#endif
