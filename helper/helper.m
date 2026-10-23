//
//  helper.m — lmvthumb
//
//  A headless one-shot tool: given a material's relative path, decode one frame,
//  write the poster sidecar and exit. SpringBoard/Preferences spawn it instead of
//  decoding in-process, so the busiest process in the system never pays for a
//  thumbnail.
//
//  Usage: lmvthumb <path relative to /var/mobile/LockMessageVideo>
//  Exit:  0 ok/already-present, 2 bad args, 3 bad revision, 4 decode failed, 5 write failed
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dlfcn.h>

static NSString *const kLMVHelperLogPath = @"/var/mobile/LockMessageVideo/helper.log";
// 3.10.8: the first attempt left NOTHING in helper.log even though the host logged
// spawn rc=0, which means either the process died before main or it could not open
// the file. Write to a second location that needs no directory of ours, so the next
// run distinguishes "cannot write /var/mobile" from "never started".
static NSString *const kLMVHelperFallbackLog = @"/tmp/lmvthumb.log";

// Plain append under O_APPEND: one line per event, never buffered, never renamed.
// The host's shared-render.log has a 1200-record budget that would swallow these.
static void LMVHelperAppend(NSString *line) {
    if (!line.length) return;
    NSString *full = [NSString stringWithFormat:@"%.3f [helper uid=%d] %@\n", NSDate.date.timeIntervalSince1970, (int)geteuid(), line];
    NSData *data = [full dataUsingEncoding:NSUTF8StringEncoding];
    for (NSString *path in @[kLMVHelperLogPath, kLMVHelperFallbackLog]) {
        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
        if (fd < 0) continue;
        ssize_t ignored = write(fd, data.bytes, data.length);
        (void)ignored;
        close(fd);
    }
}

// The thumbnail header routes its own trace through this macro; point it at the
// helper log so every stage of the decode lands in the file the user reads.
#define LMVThumbnailDiagnostic(event) LMVHelperAppend(event)

#import "../LockMessageVideoPrefs/LMVMaterialThumbnail.h"

int main(int argc, char *argv[]) {
    @autoreleasepool {
        LMVHelperAppend([NSString stringWithFormat:@"start pid=%d argc=%d", getpid(), argc]);
        if (argc < 2) { LMVHelperAppend(@"exit no-arg"); return 2; }
        NSString *relative = [NSString stringWithUTF8String:argv[1]];
        if (!relative.length) { LMVHelperAppend(@"exit empty-arg"); return 2; }

        CFTimeInterval started = CFAbsoluteTimeGetCurrent();
        NSString *revision = LMVThumbnailRevision(relative);
        if (!revision.length) { LMVHelperAppend(@"exit bad-revision"); return 3; }

        // A poster that already exists is left alone: two importers racing for the
        // same material must not rewrite the file the other one is serving.
        if (LMVReadThumbnail(relative, revision)) {
            LMVHelperAppend([NSString stringWithFormat:@"exit already %.0fms", (CFAbsoluteTimeGetCurrent() - started) * 1000.0]);
            return 0;
        }

        UIImage *poster = LMVDecodeThumbnail(relative);
        if (!poster) { LMVHelperAppend(@"exit decode-failed"); return 4; }

        NSError *error = LMVWriteThumbnail(relative, revision, poster);
        if (error) {
            LMVHelperAppend([NSString stringWithFormat:@"exit write-failed code=%ld", (long)error.code]);
            return 5;
        }
        LMVHelperAppend([NSString stringWithFormat:@"exit done %.0fms", (CFAbsoluteTimeGetCurrent() - started) * 1000.0]);
        // Tell the host a poster appeared; without this the list would keep its
        // placeholder until the next reopen. Resolved dynamically so the tool does
        // not need an extra link dependency for one call.
        int (*post)(const char *) = (int (*)(const char *))dlsym(RTLD_DEFAULT, "notify_post");
        if (post) post("com.minis.lockmessagevideo/thumbReady");
    }
    return 0;
}
