#pragma once
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static const unsigned long long LMVMaxImportBytes = 512ULL * 1024ULL * 1024ULL;
// Shared with the portable regression harness: bounded, byte-preserving I/O only.
static int LMVImportCopyBytes(int source, int staging, struct stat *owned) {
    struct stat before, after;
    if (fstat(source, &before)) return errno;
    if (!S_ISREG(before.st_mode) || before.st_size <= 0) return EINVAL;
    if ((unsigned long long)before.st_size > LMVMaxImportBytes) return EFBIG;
    unsigned long long total = 0;
    char buffer[64 * 1024];
    for (;;) {
        ssize_t count = read(source, buffer, sizeof(buffer));
        if (count < 0) { if (errno == EINTR) continue; return errno; }
        if (!count) break;
        total += (unsigned long long)count;
        if (total > (unsigned long long)before.st_size || total > LMVMaxImportBytes) return EFBIG;
        for (ssize_t offset = 0; offset < count;) {
            ssize_t written = write(staging, buffer + offset, (size_t)(count - offset));
            if (written < 0) { if (errno == EINTR) continue; return errno; }
            if (!written) return EIO;
            offset += written;
        }
    }
    if (fstat(source, &after)) return errno;
#if defined(__APPLE__)
    int timesMatch = before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec && before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec && before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec && before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec;
#else
    int timesMatch = before.st_mtim.tv_sec == after.st_mtim.tv_sec && before.st_mtim.tv_nsec == after.st_mtim.tv_nsec && before.st_ctim.tv_sec == after.st_ctim.tv_sec && before.st_ctim.tv_nsec == after.st_ctim.tv_nsec;
#endif
    if (total != (unsigned long long)before.st_size || before.st_size != after.st_size || before.st_dev != after.st_dev || before.st_ino != after.st_ino || !timesMatch) return ESTALE;
    if (fsync(staging) || fstat(staging, owned)) return errno;
    return S_ISREG(owned->st_mode) && (unsigned long long)owned->st_size == total ? 0 : EIO;
}
static int LMVImportFileMatches(int folder, const char *name, const struct stat *owned) {
    struct stat current;
    if (fstatat(folder, name, &current, AT_SYMLINK_NOFOLLOW) || !S_ISREG(current.st_mode) || current.st_dev != owned->st_dev || current.st_ino != owned->st_ino || current.st_size != owned->st_size) return 0;
#if defined(__APPLE__)
    return current.st_mtimespec.tv_sec == owned->st_mtimespec.tv_sec && current.st_mtimespec.tv_nsec == owned->st_mtimespec.tv_nsec;
#else
    return current.st_mtim.tv_sec == owned->st_mtim.tv_sec && current.st_mtim.tv_nsec == owned->st_mtim.tv_nsec;
#endif
}
static void LMVImportUnlinkOwned(int folder, const char *name, const struct stat *owned) {
    struct stat current;
    if (!fstatat(folder,name,&current,AT_SYMLINK_NOFOLLOW) && S_ISREG(current.st_mode) && current.st_dev==owned->st_dev && current.st_ino==owned->st_ino) unlinkat(folder, name, 0);
}
// linkat publishes the complete inode atomically and never replaces an existing name.
static int LMVImportPublish(int root, const char *pending, int library, const char *name, const struct stat *owned) {
    if (!LMVImportFileMatches(root, pending, owned)) return ESTALE;
    if (linkat(root, pending, library, name, 0)) return errno;
    if (!LMVImportFileMatches(library, name, owned)) return ESTALE;
    LMVImportUnlinkOwned(root, pending, owned);
    return 0;
}

#ifndef LMV_IMPORT_IO_ONLY
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import "LMVMaterialStorage.h"
#import "LMVThumbnailDiagnosticLog.h"
#import "LMVMaterialThumbnail.h"
#import "LMVMaterialCatalog.h"
static NSError *LMVImportError(NSInteger code, NSString *message, NSError *underlying) {
    NSMutableDictionary *info=[NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    if (underlying) {
        info[NSUnderlyingErrorKey]=underlying;
        info[NSLocalizedDescriptionKey]=[NSString stringWithFormat:@"%@\n%@ (%@ %ld)",message,underlying.localizedDescription,underlying.domain,(long)underlying.code];
    }
    return [NSError errorWithDomain:@"LockMessageVideo.Import" code:code userInfo:info];
}
// Read a frame from the owned original; validation never writes media bytes.
static NSError *LMVValidateMovie(NSURL *url) {
    NSError *error=nil;
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
    double duration=CMTimeGetSeconds(asset.duration);
    AVAssetTrack *track=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!asset.playable || !track || !isfinite(duration) || duration<=0) return LMVImportError(12,@"原视频没有可播放的视频轨道或有效时长",nil);
    double width=fabs(track.naturalSize.width), height=fabs(track.naturalSize.height);
    if (!isfinite(width) || !isfinite(height) || width<1 || height<1 || width*height>16.0*1024*1024) return LMVImportError(4,@"原视频尺寸无效或超过 1600 万像素解码预算",nil);
    AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:asset error:&error];
    AVAssetReaderTrackOutput *output=[AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)}];
    output.alwaysCopiesSampleData=NO;
    if (!reader || ![reader canAddOutput:output]) return error ?: LMVImportError(13,@"无法验证原视频解码",nil);
    [reader addOutput:output];
    if (![reader startReading]) return reader.error ?: LMVImportError(14,@"原视频解码启动失败",nil);
    CMSampleBufferRef sample=[output copyNextSampleBuffer];
    BOOL valid=sample && CMSampleBufferDataIsReady(sample) && CMSampleBufferGetImageBuffer(sample)!=NULL;
    if (sample) CFRelease(sample);
    error=reader.error; [reader cancelReading];
    return valid && !error ? nil : (error ?: LMVImportError(15,@"原视频没有可解码画面",nil));
}
static NSError *LMVImportIOError(int code, NSString *message) {
    return LMVImportError(19,message,[NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil]);
}
static int LMVImportOpenDirectory(int parent, const char *name) {
    if (mkdirat(parent,name,0755) && errno!=EEXIST) return -1;
    return openat(parent,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
}
static BOOL LMVImportDirectoryMatches(int descriptor, NSString *path) {
    struct stat pinned, current;
    return !fstat(descriptor,&pinned) && !lstat(path.fileSystemRepresentation,&current) && S_ISDIR(current.st_mode) && pinned.st_dev==current.st_dev && pinned.st_ino==current.st_ino;
}
// Use the pinned root for catalog I/O as well; reject a linked or corrupt catalog
// rather than replacing old user labels. Keep the existing plist schema/API.
static NSError *LMVImportRegisterName(int root, NSString *relative, NSString *sourceName) {
    NSMutableDictionary *names=[NSMutableDictionary new];
    int catalog=openat(root,"material-names.plist",O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
    if (catalog<0 && errno!=ENOENT) return LMVImportIOError(errno,@"无法安全读取素材名称目录");
    if (catalog>=0) {
        struct stat status;
        if (fstat(catalog,&status) || !S_ISREG(status.st_mode) || status.st_size<=0 || status.st_size>16*1024*1024) { close(catalog); return LMVImportError(21,@"素材名称目录不安全或无效，保留已有名称",nil); }
        NSMutableData *data=[NSMutableData data];
        char buffer[16*1024]; int failure=0;
        for (;;) {
            ssize_t count=read(catalog,buffer,sizeof(buffer));
            if (count<0) { if (errno==EINTR) continue; failure=errno; break; }
            if (!count) break;
            if (data.length+(NSUInteger)count>16*1024*1024) { failure=EFBIG; break; }
            [data appendBytes:buffer length:(NSUInteger)count];
        }
        close(catalog);
        if (failure) return LMVImportIOError(failure,@"无法读取素材名称目录");
        NSError *parseError=nil;
        id value=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:NULL error:&parseError];
        if (![value isKindOfClass:NSDictionary.class]) return LMVImportError(21,@"素材名称目录损坏，保留已有文件",parseError);
        names=[value mutableCopy];
    }
    NSString *label=sourceName.length ? [sourceName substringToIndex:MIN(sourceName.length,72)] : @"视频";
    names[relative]=[@"相册原片 · " stringByAppendingString:label];
    NSError *error=nil;
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:names format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data) return error;
    NSString *pending=[@".import-catalog-" stringByAppendingString:NSUUID.UUID.UUIDString];
    int output=openat(root,pending.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
    if (output<0) return LMVImportIOError(errno,@"无法保存素材名称");
    struct stat owned={0}; int failure=fstat(output,&owned) ? errno : 0;
    for (NSUInteger offset=0; !failure && offset<data.length;) {
        ssize_t count=write(output,(const char *)data.bytes+offset,data.length-offset);
        if (count<0) { if (errno==EINTR) continue; failure=errno; break; }
        if (!count) { failure=EIO; break; }
        offset+=(NSUInteger)count;
    }
    if (!failure && fsync(output)) failure=errno;
    fstat(output,&owned);
    if (close(output) && !failure) failure=errno;
    struct stat existing;
    if (!failure && !fstatat(root,"material-names.plist",&existing,AT_SYMLINK_NOFOLLOW)) {
        if (!S_ISREG(existing.st_mode)) failure=EINVAL;
    } else if (!failure && errno!=ENOENT) failure=errno;
    if (!failure && !LMVImportFileMatches(root,pending.fileSystemRepresentation,&owned)) failure=ESTALE;
    if (!failure && renameat(root,pending.fileSystemRepresentation,root,"material-names.plist")) failure=errno;
    if (failure) LMVImportUnlinkOwned(root,pending.fileSystemRepresentation,&owned);
    return failure ? LMVImportIOError(failure,@"无法原子保存素材名称，保留已有名称") : nil;
}
// Photos' temporary representation remains alive until this background transaction
// returns. Only owned staging is decoded; library receives the same original bytes.
static NSString *LMVImportMovieOnMaterialQueue(NSURL *source, NSError **outError) {
    NSError *error=nil;
    NSString *base=LMV_CATALOG_ROOT;
    NSString *library=[base stringByAppendingPathComponent:@"library"];
    NSString *ext=source.pathExtension.lowercaseString;
    if (!source.isFileURL || ![@[@"mov",@"mp4",@"m4v"] containsObject:ext]) {
        if (outError) *outError=LMVImportError(1,@"请选择 MOV、MP4、M4V 原视频文件",nil);
        return nil;
    }
    NSString *name=[NSUUID.UUID.UUIDString stringByAppendingPathExtension:ext];
    NSString *pending=[@".import-source-" stringByAppendingString:name];
    NSString *relative=[@"library" stringByAppendingPathComponent:name];
    NSURL *ownedSource=[NSURL fileURLWithPath:[base stringByAppendingPathComponent:pending]];
    int parent=-1, root=-1, folder=-1, input=-1, staging=-1;
    BOOL ownsStaging=NO, published=NO;
    struct stat owned={0};
    do {
        parent=open(base.stringByDeletingLastPathComponent.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
        if (parent<0) { error=LMVImportIOError(errno,@"素材父目录不可访问或不安全"); break; }
        root=LMVImportOpenDirectory(parent,base.lastPathComponent.fileSystemRepresentation);
        if (root<0) { error=LMVImportIOError(errno,@"素材目录不可访问或不安全"); break; }
        folder=LMVImportOpenDirectory(root,"library");
        if (folder<0) { error=LMVImportIOError(errno,@"素材库目录不可访问或不安全"); break; }
        input=open(source.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);
        if (input<0) { error=LMVImportIOError(errno,@"原视频不是可读取的普通文件"); break; }
        staging=openat(root,pending.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
        if (staging<0) { error=LMVImportIOError(errno,@"无法创建原片导入临时文件"); break; }
        if (fstat(staging,&owned)) { error=LMVImportIOError(errno,@"无法确认临时文件所有权"); break; }
        ownsStaging=YES;
        int copied=LMVImportCopyBytes(input,staging,&owned);
        // Refresh size for cleanup even if a bounded copy stopped halfway.
        fstat(staging,&owned);
        if (copied) { error=LMVImportIOError(copied,copied==EFBIG ? @"原视频需为不超过 512 MiB 的普通文件" : @"无法完整复制原视频，或源文件在导入期间发生变化"); break; }
        if (close(staging)) { staging=-1; error=LMVImportIOError(errno,@"原片临时文件写入失败"); break; }
        staging=-1;
        if (!LMVImportDirectoryMatches(root,base) || !LMVImportDirectoryMatches(folder,library) || !LMVImportFileMatches(root,pending.fileSystemRepresentation,&owned)) { error=LMVImportError(20,@"导入目录或临时文件发生变化，未加入素材库",nil); break; }
        error=LMVValidateMovie(ownedSource);
        if (error) break;
        if (!LMVImportDirectoryMatches(root,base) || !LMVImportDirectoryMatches(folder,library)) { error=LMVImportError(20,@"导入目录发生变化，未加入素材库",nil); break; }
        int moved=LMVImportPublish(root,pending.fileSystemRepresentation,folder,name.fileSystemRepresentation,&owned);
        published=LMVImportFileMatches(folder,name.fileSystemRepresentation,&owned);
        if (moved) { error=LMVImportIOError(moved,@"原片无法原子发布到素材库"); break; }
        // Catalog registration follows publication; rollback only this owned file.
        error=LMVImportRegisterName(root,relative,source.lastPathComponent.stringByDeletingPathExtension);
    } while (0);
    if (input>=0) close(input);
    if (staging>=0) close(staging);
    if (ownsStaging) LMVImportUnlinkOwned(root,pending.fileSystemRepresentation,&owned);
    if (error && published) LMVImportUnlinkOwned(folder,name.fileSystemRepresentation,&owned);
    if (folder>=0) close(folder);
    if (root>=0) close(root);
    if (parent>=0) close(parent);
    if (error) {
        if (outError) *outError=LMVImportError(17,@"原片导入未完成；未加入素材库",error);
        return nil;
    }
    NSString *revision = LMVThumbnailRevision(relative);
    if (revision) {
        UIImage *poster = LMVDecodeThumbnail(relative);
        if (poster) {
            NSError *thumbnailError = LMVWriteThumbnail(relative, revision, poster);
            if (thumbnailError) LMVThumbnailLog(@"import-sidecar-write", relative, thumbnailError);
        } else {
            LMVThumbnailLog(@"import-sidecar-decode", relative, nil);
        }
    }
    return relative;
}

// NSItemProvider's file URL expires when its callback returns. Keep that callback
// alive while the serial background transaction runs; NEVER wait on the UI thread.
static NSString *LMVImportMovie(NSURL *source, NSError **outError) {
    if (NSThread.isMainThread) {
        if (outError) *outError=LMVImportError(18,@"视频导入必须在相册后台回调中执行",nil);
        return nil;
    }
    __block NSString *relative=nil;
    __block NSError *error=nil;
    dispatch_sync(LMVMaterialQueue(), ^{
        @autoreleasepool { relative=LMVImportMovieOnMaterialQueue(source,&error); }
    });
    if (outError) *outError=error;
    return relative;
}

#endif // LMV_IMPORT_IO_ONLY
