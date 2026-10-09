#pragma once
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreMedia/CoreMedia.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <math.h>
#ifndef LMV_FRAME_DISK_ROOT
#define LMV_FRAME_DISK_ROOT @"/var/mobile/LockMessageVideo/.last-frames"
#endif
// Serial background queue only. A single atomic record contains image + exact PTS.
// Filenames are hashes of normalized paths; no material names or original media copy.
static NSString *LMVDiskNormalizedPath(NSString *path) {
    return [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
}
static NSString *LMVDiskRevision(NSString *path) {
    struct stat info;
    if (stat(path.fileSystemRepresentation, &info) || !S_ISREG(info.st_mode)) return nil;
    return [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%ld:%lld:%ld",
        (unsigned long long)info.st_dev, (unsigned long long)info.st_ino,
        (long long)info.st_size, (long long)info.st_mtimespec.tv_sec,
        info.st_mtimespec.tv_nsec, (long long)info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec];
}
static NSString *LMVDiskRecordPath(NSString *path) {
    NSData *bytes=[LMVDiskNormalizedPath(path) dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(bytes.bytes,(CC_LONG)bytes.length,digest);
    NSMutableString *name=[NSMutableString new];
    for (NSUInteger i=0;i<sizeof(digest);i++) [name appendFormat:@"%02x",digest[i]];
    return [LMV_FRAME_DISK_ROOT stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
}
static BOOL LMVDiskDirectory(void) {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *root=LMV_FRAME_DISK_ROOT, *parent=root.stringByDeletingLastPathComponent;
    struct stat s;
    if (![fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return NO;
    NSString *expected=[[parent stringByResolvingSymlinksInPath] stringByAppendingPathComponent:root.lastPathComponent];
    return !lstat(root.fileSystemRepresentation,&s) && S_ISDIR(s.st_mode) &&
        [[root stringByResolvingSymlinksInPath] isEqualToString:expected];
}
static void LMVDiskPrune(void) {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSArray *files=[fm contentsOfDirectoryAtPath:LMV_FRAME_DISK_ROOT error:nil];
    NSMutableArray *records=[NSMutableArray new]; unsigned long long total=0;
    for (NSString *name in files) {
        if (![name.pathExtension isEqualToString:@"plist"] || name.length!=70) continue;
        NSString *path=[LMV_FRAME_DISK_ROOT stringByAppendingPathComponent:name];
        struct stat s; if (lstat(path.fileSystemRepresentation,&s) || !S_ISREG(s.st_mode)) continue;
        total+=s.st_size;
        [records addObject:@{@"path":path,@"size":@(s.st_size),@"date":@(s.st_mtimespec.tv_sec)}];
    }
    [records sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) { return [a[@"date"] compare:b[@"date"]]; }];
    NSUInteger count=records.count;
    for (NSDictionary *record in records) {
        if (count<=12 && total<=32ULL*1024*1024) break;
        if ([fm removeItemAtPath:record[@"path"] error:nil]) { count--; total-=[record[@"size"] unsignedLongLongValue]; }
    }
}
static BOOL LMVDiskWrite(NSString *path, NSString *revision, CGImageRef image, CMTime time) {
    if (!image || !CMTIME_IS_NUMERIC(time) || CMTimeCompare(time,kCMTimeZero)<0 ||
        ![LMVDiskRevision(path) isEqualToString:revision] || !LMVDiskDirectory()) return NO;
    // Bound the stored/decompressed image regardless of original video dimensions.
    size_t w=CGImageGetWidth(image), h=CGImageGetHeight(image);
    if (!w || !h) return NO;
    double ratio=MIN(1.0,960.0/MAX(w,h)); size_t width=MAX(1,(size_t)(w*ratio)),height=MAX(1,(size_t)(h*ratio));
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,width,height,8,width*4,color,kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(color); if (!context) return NO;
    CGContextDrawImage(context,CGRectMake(0,0,width,height),image);
    CGImageRef scaled=CGBitmapContextCreateImage(context); CGContextRelease(context);
    NSMutableData *encoded=[NSMutableData new];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)encoded,CFSTR("public.jpeg"),1,NULL);
    BOOL ok=NO;
    if (destination && scaled) {
        CGImageDestinationAddImage(destination,scaled,(__bridge CFDictionaryRef)@{(id)kCGImageDestinationLossyCompressionQuality:@0.88});
        ok=CGImageDestinationFinalize(destination);
    }
    if (scaled) CGImageRelease(scaled); if (destination) CFRelease(destination);
    if (!ok || !encoded.length || encoded.length>4*1024*1024) return NO;
    NSDictionary *record=@{@"schema":@1,@"revision":revision,@"rendered":@YES,@"image":encoded,
        @"value":@(time.value),@"timescale":@(time.timescale),@"epoch":@(time.epoch)};
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    // Recheck after encoding: a changed source must never publish its old frame.
    if (![LMVDiskRevision(path) isEqualToString:revision]) return NO;
    NSString *target=LMVDiskRecordPath(path);
    struct stat s; if (!lstat(target.fileSystemRepresentation,&s) && !S_ISREG(s.st_mode)) return NO;
    ok=[data writeToFile:target options:NSDataWritingAtomic error:nil];
    if (ok) { [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:target error:nil]; LMVDiskPrune(); }
    return ok;
}
// Caller owns returned image. Invalid/stale records are removed; no poster fallback here.
static CGImageRef LMVDiskRead(NSString *path, NSString *revision, CMTime *time) {
    if (!LMVDiskDirectory()) return NULL;
    NSString *target=LMVDiskRecordPath(path); struct stat s;
    if (lstat(target.fileSystemRepresentation,&s) || !S_ISREG(s.st_mode)) return NULL;
    NSDictionary *record=nil;
    if (s.st_size>0 && s.st_size<=5*1024*1024) {
        NSData *data=[NSData dataWithContentsOfFile:target];
        id value=data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:nil] : nil;
        if ([value isKindOfClass:NSDictionary.class]) record=value;
    }
    NSData *imageData=record[@"image"];
    BOOL valid=[record[@"schema"] isEqual:@1] && [record[@"rendered"] isEqual:@YES] &&
        [record[@"revision"] isEqual:revision] && [LMVDiskRevision(path) isEqualToString:revision] &&
        [imageData isKindOfClass:NSData.class] && imageData.length>0 && imageData.length<=4*1024*1024;
    for (NSString *key in @[@"value",@"timescale",@"epoch"]) valid=valid && [record[key] isKindOfClass:NSNumber.class];
    CMTime pts=valid ? CMTimeMakeWithEpoch([record[@"value"] longLongValue],[record[@"timescale"] intValue],[record[@"epoch"] longLongValue]) : kCMTimeInvalid;
    valid=valid && CMTIME_IS_NUMERIC(pts) && CMTimeCompare(pts,kCMTimeZero)>=0;
    CGImageSourceRef source=valid ? CGImageSourceCreateWithData((__bridge CFDataRef)imageData,NULL) : NULL;
    NSDictionary *props=source ? (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source,0,NULL) : nil;
    size_t width=[props[(id)kCGImagePropertyPixelWidth] unsignedIntegerValue],height=[props[(id)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    CGImageRef image=NULL;
    if (source && width>0 && height>0 && width<=960 && height<=960)
        image=CGImageSourceCreateImageAtIndex(source,0,(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCacheImmediately:@YES});
    if (source) CFRelease(source);
    if (!image) [NSFileManager.defaultManager removeItemAtPath:target error:nil];
    else if (time) *time=pts;
    return image;
}
