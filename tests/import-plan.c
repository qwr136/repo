#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#define LMV_IMPORT_IO_ONLY 1
#include "../LockMessageVideoPrefs/LMVImport.h"

static int createFile(int directory, const char *name) {
    int fd=openat(directory,name,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    assert(fd>=0); return fd;
}
static void compare(int a, int b) {
    assert(lseek(a,0,SEEK_SET)==0 && lseek(b,0,SEEK_SET)==0);
    unsigned char first[4096], second[4096];
    for (;;) {
        ssize_t count=read(a,first,sizeof(first)); assert(count>=0);
        ssize_t other=read(b,second,sizeof(second)); assert(other==count);
        if (!count) break;
        assert(!memcmp(first,second,(size_t)count));
    }
}
int main(void) {
    char temporary[]="/tmp/lmv-original-XXXXXX"; assert(mkdtemp(temporary));
    int root=open(temporary,O_RDONLY|O_DIRECTORY|O_NOFOLLOW); assert(root>=0);
    assert(mkdirat(root,"library",0700)==0);
    int library=openat(root,"library",O_RDONLY|O_DIRECTORY|O_NOFOLLOW); assert(library>=0);
    int source=createFile(root,"source.mp4");
    unsigned char block[4096]; for (size_t i=0;i<sizeof(block);i++) block[i]=(unsigned char)(i*37);
    // Exercise a source larger than the removed 5 MiB compression budget.
    for (unsigned i=0;i<1537;i++) assert(write(source,block,sizeof(block))==sizeof(block));
    int pending=createFile(root,".pending.mp4"); struct stat owned;
    assert(lseek(source,0,SEEK_SET)==0);
    assert(LMVImportCopyBytes(source,pending,&owned)==0);
    assert(owned.st_size>5*1024*1024); compare(source,pending);
    struct stat status;
    assert(fstatat(library,"original.mp4",&status,AT_SYMLINK_NOFOLLOW)<0 && errno==ENOENT);
    assert(LMVImportPublish(root,".pending.mp4",library,"original.mp4",&owned)==0);
    assert(fstatat(root,".pending.mp4",&status,AT_SYMLINK_NOFOLLOW)<0 && errno==ENOENT);
    int original=openat(library,"original.mp4",O_RDONLY|O_NOFOLLOW); assert(original>=0); compare(source,original);
    assert(LMVImportFileMatches(library,"original.mp4",&owned));
    close(pending); close(original);
    // An occupied destination is never overwritten and retains its exact bytes.
    int occupied=createFile(library,"occupied.mov"); assert(write(occupied,"keep",4)==4);
    pending=createFile(root,".pending.mov"); assert(lseek(source,0,SEEK_SET)==0);
    assert(LMVImportCopyBytes(source,pending,&owned)==0);
    assert(LMVImportPublish(root,".pending.mov",library,"occupied.mov",&owned)==EEXIST);
    char kept[4]; assert(lseek(occupied,0,SEEK_SET)==0 && read(occupied,kept,4)==4 && !memcmp(kept,"keep",4));
    LMVImportUnlinkOwned(root,".pending.mov",&owned); close(pending); close(occupied);
    // Empty, oversized, directory and linked sources cannot enter the copy path.
    int empty=createFile(root,"empty.mov"); pending=createFile(root,".rejected");
    assert(LMVImportCopyBytes(empty,pending,&owned)==EINVAL);
    assert(ftruncate(empty,(off_t)LMVMaxImportBytes+1)==0); assert(lseek(empty,0,SEEK_SET)==0);
    assert(LMVImportCopyBytes(empty,pending,&owned)==EFBIG);
    assert(fstat(pending,&status)==0 && status.st_size==0);
    assert(LMVImportCopyBytes(library,pending,&owned)==EINVAL);
    assert(symlinkat("source.mp4",root,"linked.mov")==0);
    assert(openat(root,"linked.mov",O_RDONLY|O_NOFOLLOW)<0 && errno==ELOOP);
    assert(symlinkat("library",root,"linked-library")==0);
    assert(openat(root,"linked-library",O_RDONLY|O_DIRECTORY|O_NOFOLLOW)<0);
    close(empty); close(pending);
    // Replacement by a link fails publication; cleanup cannot unlink the link or target.
    pending=createFile(root,".replaced"); assert(lseek(source,0,SEEK_SET)==0);
    assert(LMVImportCopyBytes(source,pending,&owned)==0);
    assert(unlinkat(root,".replaced",0)==0);
    assert(symlinkat("source.mp4",root,".replaced")==0);
    assert(LMVImportPublish(root,".replaced",library,"replaced.mov",&owned)==ESTALE);
    LMVImportUnlinkOwned(root,".replaced",&owned);
    assert(fstatat(root,".replaced",&status,AT_SYMLINK_NOFOLLOW)==0 && S_ISLNK(status.st_mode));
    close(pending); close(source);
    const char *files[]={"source.mp4","empty.mov","linked.mov","linked-library",".rejected",".replaced"};
    for (size_t i=0;i<sizeof(files)/sizeof(files[0]);i++) assert(unlinkat(root,files[i],0)==0);
    assert(unlinkat(library,"original.mp4",0)==0 && unlinkat(library,"occupied.mov",0)==0);
    close(library); assert(unlinkat(root,"library",AT_REMOVEDIR)==0); close(root); assert(rmdir(temporary)==0);
    puts("PASS: actual bounded copy/publish functions preserve >5 MiB bytes/source, reject empty/>512 MiB/nonregular/symlink, publish complete inode atomically, preserve occupied destinations and cleanup ownership (no AVFoundation)");
    return 0;
}
