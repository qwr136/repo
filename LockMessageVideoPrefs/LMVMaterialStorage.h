#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <dirent.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>

// One owner for import (including preservation/encoding) and explicit clearing.
static dispatch_queue_t LMVMaterialQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue=dispatch_queue_create("com.minis.lockmessagevideo.materials",DISPATCH_QUEUE_SERIAL); });
    return queue;
}
static NSError *LMVStorageError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"LockMessageVideo.Storage" code:code userInfo:@{NSLocalizedDescriptionKey:message}];
}
