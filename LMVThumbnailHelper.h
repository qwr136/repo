#pragma once
#import <Foundation/Foundation.h>
#include <spawn.h>
#include <dlfcn.h>
#include <unistd.h>
#include <sys/stat.h>

// 3.10.7: outsource thumbnail decoding to a headless one-shot tool (`lmvthumb`).
//
// SpringBoard is the busiest process on the device and a thumbnail is pure work:
// open the file, stand up a decoder session, grab a frame, scale it, write it.
// Doing that in-process is what turned a cold material list into "生成中" for
// seconds whenever the device was already loaded, and why a row could sit on a
// placeholder forever once its retry budget ran out.
//
// The tool is a separate executable under <jbroot>/usr/libexec. It shares nothing
// with the host: no UIKit window, no preference, no player. It reads one video,
// writes one sidecar and exits.
//
// Everything here degrades safely: if the tool is missing or the spawn is denied,
// the caller falls back to decoding in-process exactly like before.

extern char **environ;

// Same file the tool writes, so one log answers "did the helper run?".
static inline NSString *LMVHelperLogFile(void) {
    return @"/var/mobile/LockMessageVideo/helper.log";
}
static inline void LMVHelperTrace(NSString *line) {
    if (!line.length) return;
    NSString *full = [NSString stringWithFormat:@"%.3f [host] %@\n", NSDate.date.timeIntervalSince1970, line];
    NSData *data = [full dataUsingEncoding:NSUTF8StringEncoding];
    int fd = open(LMVHelperLogFile().fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
    if (fd < 0) return;
    ssize_t ignored = write(fd, data.bytes, data.length);
    (void)ignored;
    close(fd);
}

// RootHide does not use a fixed /var/jb: the jailbreak root is a random
// `.jbroot-XXXXXXXX` container, so the executable cannot be addressed by a
// literal path. The dylib itself always lives at
//   <jbroot>/Library/MobileSubstrate/DynamicLibraries/LockMessageVideo.dylib
// so four parents up from the loaded image is the root. The literal paths stay in
// the candidate list for normal rootless/rootful installations and for the
// unlikely case dladdr cannot be resolved.
static inline NSString *LMVHelperExecutablePath(void) {
    static NSString *resolved;
    static BOOL probed;
    if (probed) return resolved.length ? resolved : nil;
    probed = YES;
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    Dl_info info;
    if (dladdr((const void *)&LMVHelperExecutablePath, &info) && info.dli_fname) {
        NSString *image = [NSString stringWithUTF8String:info.dli_fname];
        if (image.length) {
            NSString *root = image;
            for (int i = 0; i < 4; i++) root = root.stringByDeletingLastPathComponent;
            if (root.length > 1) [candidates addObject:[root stringByAppendingPathComponent:@"usr/libexec/lmvthumb"]];
        }
    }
    [candidates addObject:@"/var/jb/usr/libexec/lmvthumb"];
    [candidates addObject:@"/usr/libexec/lmvthumb"];
    for (NSString *candidate in candidates) {
        if (access(candidate.fileSystemRepresentation, X_OK) == 0) { resolved = candidate; break; }
    }
    if (!resolved.length) {
        LMVHelperTrace([NSString stringWithFormat:@"resolve failed candidates=%lu", (unsigned long)candidates.count]);
    } else {
        LMVHelperTrace([@"resolve ok " stringByAppendingString:resolved]);
    }
    return resolved.length ? resolved : nil;
}

// One dispatch per material at a time. A row is redrawn on every scroll tick, and
// without this the same file would be handed to a new process on every frame.
// The tool posts thumbReady when it finishes; that clears the ledger so a failed
// run can be retried, and a 10 s age-out covers a tool that died silently.
static NSMutableDictionary<NSString *, NSNumber *> *LMVHelperDispatched;
static dispatch_once_t LMVHelperDispatchedOnce;

static inline void LMVHelperDispatchLedgerInit(void) {
    dispatch_once(&LMVHelperDispatchedOnce, ^{ LMVHelperDispatched = [NSMutableDictionary new]; });
}
// A list opening asks for every row at once. Without a ceiling that is one process
// per missing poster; the deferred rows are picked up again from the tool's own
// completion notification, which repaints the table and re-asks.
static const NSUInteger LMVHelperMaxInFlight = 4;
static const NSTimeInterval LMVHelperDispatchWindow = 10.0;

// 0 = the tool cannot be used, decode in-process (the old behaviour)
// 1 = accepted (or already in flight): do NOT decode here
// 2 = too many in flight: do NOT decode, wait for the next completion
static inline NSInteger LMVSpawnThumbnailHelper(NSString *relative) {
    if (![relative isKindOfClass:NSString.class] || !relative.length) return 0;
    LMVHelperDispatchLedgerInit();
    CFTimeInterval now = CFAbsoluteTimeGetCurrent();
    for (NSString *key in LMVHelperDispatched.allKeys) {
        if (now - LMVHelperDispatched[key].doubleValue >= LMVHelperDispatchWindow)
            [LMVHelperDispatched removeObjectForKey:key];
    }
    if (LMVHelperDispatched[relative]) return 1;          // still in flight
    NSString *tool = LMVHelperExecutablePath();
    if (!tool.length) return 0;
    if (LMVHelperDispatched.count >= LMVHelperMaxInFlight) return 2;
    const char *argv[] = {tool.fileSystemRepresentation, relative.UTF8String, NULL};
    pid_t pid = 0;
    int rc = posix_spawn(&pid, tool.fileSystemRepresentation, NULL, NULL, (char *const *)argv, environ);
    LMVHelperTrace([NSString stringWithFormat:@"spawn rc=%d pid=%d inFlight=%lu item=%@",
        rc, (int)pid, (unsigned long)LMVHelperDispatched.count, relative.lastPathComponent]);
    if (rc != 0) return 0;
    LMVHelperDispatched[relative] = @(now);
    return 1;
}
static inline void LMVHelperForgetDispatched(void) {
    LMVHelperDispatchLedgerInit();
    [LMVHelperDispatched removeAllObjects];
    LMVHelperTrace(@"ledger cleared");
}
