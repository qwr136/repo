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
// Only direct regular files are removed. No symlink traversal, recursive removal,
// preference mutation, or access to library/selected optimized videos.
static NSError *LMVClearOriginals(void) {
    int base=open("/var/mobile/LockMessageVideo",O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if (base<0) return errno==ENOENT ? nil : LMVStorageError(errno,@"无法打开素材目录（不允许符号链接）");
    int original=openat(base,"原素材",O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    int openError=errno;
    close(base);
    if (original<0) return openError==ENOENT ? nil : LMVStorageError(openError,@"原素材目录不可访问或是符号链接，未清理");
    DIR *directory=fdopendir(original);
    if (!directory) { int code=errno; close(original); return LMVStorageError(code,@"无法读取原素材目录"); }
    NSUInteger failed=0, remaining=0;
    struct dirent *entry;
    errno=0;
    while ((entry=readdir(directory))) {
        if (!strcmp(entry->d_name,".") || !strcmp(entry->d_name,"..")) continue;
        struct stat status;
        if (fstatat(original,entry->d_name,&status,AT_SYMLINK_NOFOLLOW)!=0 || !S_ISREG(status.st_mode)) { failed++; errno=0; continue; }
        // unlinkat without AT_REMOVEDIR cannot recursively remove a directory.
        if (unlinkat(original,entry->d_name,0)!=0) failed++;
        errno=0;
    }
    if (errno) failed++;
    rewinddir(directory);
    errno=0;
    while ((entry=readdir(directory))) {
        if (strcmp(entry->d_name,".") && strcmp(entry->d_name,"..")) remaining++;
    }
    if (errno) failed++;
    closedir(directory);
    if (failed || remaining) return LMVStorageError(1,[NSString stringWithFormat:@"清理未全部完成：剩余 %lu 项；不可删除项、子目录或符号链接已保留。素材库和当前选中视频未改变。",(unsigned long)remaining]);
    return nil;
}
