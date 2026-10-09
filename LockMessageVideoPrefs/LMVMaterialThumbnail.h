#pragma once
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <CommonCrypto/CommonDigest.h>
#import "LMVMaterialStorage.h"
#import "LMVMaterialCatalog.h"
#import <math.h>

// Independent of playback's .last-frames cache. Never change a video or its name.
// Call on a background queue; immutable records are atomically shared across processes.
static NSString *LMVThumbnailRevision(NSString *relative) {
    if (![relative isKindOfClass:NSString.class] || [relative.pathComponents containsObject:@".."] ||
        [relative hasPrefix:@"/"] || relative.length == 0) return nil;
    NSString *path = [LMV_CATALOG_ROOT stringByAppendingPathComponent:relative];
    struct stat s;
    if (stat(path.fileSystemRepresentation, &s) || !S_ISREG(s.st_mode)) return nil;
    return [NSString stringWithFormat:@"%@|%llu:%llu:%lld:%lld:%ld:%lld:%ld", relative,
        (unsigned long long)s.st_dev, (unsigned long long)s.st_ino, (long long)s.st_size,
        (long long)s.st_mtimespec.tv_sec, s.st_mtimespec.tv_nsec,
        (long long)s.st_ctimespec.tv_sec, s.st_ctimespec.tv_nsec];
}
static NSString *LMVThumbnailRecordPath(NSString *relative) {
    NSData *bytes = [relative dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *name = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
    return [[LMV_CATALOG_ROOT stringByAppendingPathComponent:@".material-thumbnails"]
        stringByAppendingPathComponent:[name stringByAppendingPathExtension:@"plist"]];
}
#ifndef LMVThumbnailDiagnostic
#define LMVThumbnailDiagnostic(event) do { } while (0)
#endif
static void LMVThumbnailLog(NSString *stage, NSString *relative, NSError *error) {
    (void)relative;
    // Hooked by the including host; never include paths, filenames or error descriptions.
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if (![underlying isKindOfClass:NSError.class]) underlying = nil;
    NSString *event = [NSString stringWithFormat:@"thumbnail stage=%@ error=%@/%ld underlying=%@/%ld",
        stage, error.domain ?: @"none", (long)error.code, underlying.domain ?: @"none", (long)underlying.code];
    LMVThumbnailDiagnostic(event);
    (void)event;
}
static UIImage *LMVReadThumbnail(NSString *relative, NSString *revision) {
    NSString *target = LMVThumbnailRecordPath(relative);
    struct stat s;
    if (lstat(target.fileSystemRepresentation, &s)) {
        if (errno != ENOENT) LMVThumbnailLog(@"sidecar-stat", relative, [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]);
        return nil;
    }
    if (!S_ISREG(s.st_mode) || s.st_size <= 0 || s.st_size > 256 * 1024) return nil;
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:target options:0 error:&error];
    id record = data ? [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error] : nil;
    if (error) LMVThumbnailLog(@"sidecar-read", relative, error);
    if (![record isKindOfClass:NSDictionary.class] || ![record[@"schema"] isEqual:@1] ||
        ![record[@"revision"] isEqual:revision] || ![LMVThumbnailRevision(relative) isEqualToString:revision]) return nil;
    NSData *encoded = record[@"image"];
    if (![encoded isKindOfClass:NSData.class] || !encoded.length || encoded.length > 240 * 1024) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)encoded, NULL);
    NSDictionary *props = source ? (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL) : nil;
    NSUInteger width = [props[(id)kCGImagePropertyPixelWidth] unsignedIntegerValue];
    NSUInteger height = [props[(id)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    CGImageRef image = source && width && height && width <= 144 && height <= 144 ?
        CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCacheImmediately:@YES}) : NULL;
    if (source) CFRelease(source);
    UIImage *poster = image ? [UIImage imageWithCGImage:image] : nil;
    if (image) CGImageRelease(image);
    if (!poster) LMVThumbnailLog(@"sidecar-image", relative, LMVStorageError(40, @"海报图像无效"));
    return poster;
}
static NSError *LMVWriteThumbnail(NSString *relative, NSString *revision, UIImage *poster) {
    NSData *encoded = poster ? UIImageJPEGRepresentation(poster, 0.85) : nil;
    if (!encoded.length || encoded.length > 240 * 1024) return LMVStorageError(41, @"海报编码失败或过大");
    NSString *target = LMVThumbnailRecordPath(relative);
    NSString *directory = target.stringByDeletingLastPathComponent;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSError *error = nil;
    if (![fm createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:&error]) return error;
    struct stat s;
    if (lstat(directory.fileSystemRepresentation, &s) || !S_ISDIR(s.st_mode)) return LMVStorageError(42, @"海报目录不是普通目录");
    if (!lstat(target.fileSystemRepresentation, &s) && !S_ISREG(s.st_mode)) return LMVStorageError(43, @"海报目标不是普通文件");
    NSDictionary *record = @{@"schema":@1, @"revision":revision ?: @"", @"image":encoded};
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data) return error;
    // Recheck immediately before publishing; replacement/deletion never gets an old poster.
    if (![LMVThumbnailRevision(relative) isEqualToString:revision]) return LMVStorageError(44, @"素材版本已改变，未保存旧海报");
    if (![data writeToFile:target options:NSDataWritingAtomic error:&error]) return error;
    if (![fm setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:target error:&error]) return error;
    return nil;
}

// Scale/rotate a decoded BGRA frame on the CPU. No CoreImage/GPU dependency in Settings.
static UIImage *LMVThumbnailFromBuffer(CVPixelBufferRef buffer, CGAffineTransform transform) {
    if (!buffer || CVPixelBufferGetPixelFormatType(buffer) != kCVPixelFormatType_32BGRA) return nil;
    size_t width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer);
    CGRect oriented = CGRectApplyAffineTransform(CGRectMake(0, 0, width, height), transform);
    double w = CGRectGetWidth(oriented), h = CGRectGetHeight(oriented);
    if (!isfinite(w) || !isfinite(h) || w <= 0 || h <= 0) return nil;
    double scale = MIN(1.0, 144.0 / MAX(w, h));
    size_t outW = MAX(1, (size_t)floor(w * scale)), outH = MAX(1, (size_t)floor(h * scale));
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef small = CGBitmapContextCreate(NULL, outW, outH, 8, outW * 4, color, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(color);
    if (!small) return nil;
    UIImage *poster = nil;
    if (CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly) == kCVReturnSuccess) {
        color = CGColorSpaceCreateDeviceRGB();
        CGContextRef raw = CGBitmapContextCreate(CVPixelBufferGetBaseAddress(buffer), width, height, 8,
            CVPixelBufferGetBytesPerRow(buffer), color, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
        CGColorSpaceRelease(color);
        CGImageRef frame = raw ? CGBitmapContextCreateImage(raw) : NULL;
        if (raw) CGContextRelease(raw);
        if (frame) {
            // Track matrices use top-left video coordinates; Quartz images use bottom-left.
            CGContextTranslateCTM(small, 0, outH);
            CGContextScaleCTM(small, (double)outW / w, -(double)outH / h);
            CGContextTranslateCTM(small, -CGRectGetMinX(oriented), -CGRectGetMinY(oriented));
            CGContextConcatCTM(small, transform);
            CGContextTranslateCTM(small, 0, height);
            CGContextScaleCTM(small, 1, -1);
            CGContextDrawImage(small, CGRectMake(0, 0, width, height), frame);
            CGImageRelease(frame);
            CGImageRef image = CGBitmapContextCreateImage(small);
            if (image) { poster = [UIImage imageWithCGImage:image]; CGImageRelease(image); }
        }
        CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    }
    CGContextRelease(small);
    return poster;
}
static UIImage *LMVDecodeThumbnail(NSString *relative) {
    NSString *path = [LMV_CATALOG_ROOT stringByAppendingPathComponent:relative];
    NSError *error = nil;
    if (![NSFileManager.defaultManager attributesOfItemAtPath:path error:&error] || ![NSFileManager.defaultManager isReadableFileAtPath:path]) {
        LMVThumbnailLog(@"video-read", relative, error ?: [NSError errorWithDomain:NSPOSIXErrorDomain code:EACCES userInfo:nil]);
        return nil;
    }
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!track) { LMVThumbnailLog(@"video-track", relative, LMVStorageError(45, @"没有视频轨道")); return nil; }
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(144, 144);
    generator.requestedTimeToleranceBefore = kCMTimePositiveInfinity;
    generator.requestedTimeToleranceAfter = kCMTimePositiveInfinity;
    // Respect edited clips whose video track starts after zero; avoid out-of-range t=1.
    CMTime start = CMTIME_IS_NUMERIC(track.timeRange.start) ? track.timeRange.start : kCMTimeZero;
    double duration = CMTimeGetSeconds(track.timeRange.duration);
    for (NSNumber *offset in @[@0, @0.1]) {
        double seconds = offset.doubleValue;
        if (seconds > 0 && (!isfinite(duration) || seconds >= duration)) continue;
        error = nil;
        CGImageRef image = [generator copyCGImageAtTime:CMTimeAdd(start, CMTimeMakeWithSeconds(seconds, 600)) actualTime:NULL error:&error];
        if (image) { UIImage *poster = [UIImage imageWithCGImage:image]; CGImageRelease(image); return poster; }
        LMVThumbnailLog(@"image-generator", relative, error ?: LMVStorageError(46, @"取帧未返回图像"));
    }
    // A different decode path; exactly one sample, with a bounded decoded frame size.
    double sourceWidth = fabs(track.naturalSize.width), sourceHeight = fabs(track.naturalSize.height);
    if (!isfinite(sourceWidth) || !isfinite(sourceHeight) || sourceWidth < 1 || sourceHeight < 1 ||
        sourceWidth * sourceHeight > 16.0 * 1024 * 1024) {
        LMVThumbnailLog(@"reader-budget", relative, LMVStorageError(49, @"首帧尺寸超过预览解码预算"));
        return nil;
    }
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track
        outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
    output.alwaysCopiesSampleData = NO;
    if (!reader || ![reader canAddOutput:output]) { LMVThumbnailLog(@"reader-create", relative, error ?: LMVStorageError(47, @"无法建立首帧读取器")); return nil; }
    [reader addOutput:output];
    if (![reader startReading]) { LMVThumbnailLog(@"reader-start", relative, reader.error); return nil; }
    CMSampleBufferRef sample = [output copyNextSampleBuffer];
    UIImage *poster = sample ? LMVThumbnailFromBuffer(CMSampleBufferGetImageBuffer(sample), track.preferredTransform) : nil;
    if (sample) CFRelease(sample);
    error = reader.error;
    [reader cancelReading];
    if (!poster) LMVThumbnailLog(@"reader-frame", relative, error ?: LMVStorageError(48, @"首帧无法转换为海报"));
    return poster;
}
static UIImage *LMVEnsureThumbnail(NSString *relative, NSString *revision) {
    if (!revision.length) return nil;
    UIImage *poster = LMVReadThumbnail(relative, revision);
    if (poster) return poster;
    poster = LMVDecodeThumbnail(relative);
    if (![LMVThumbnailRevision(relative) isEqualToString:revision]) return nil;
    if (poster) {
        NSError *error = LMVWriteThumbnail(relative, revision, poster);
        if (error) LMVThumbnailLog(@"sidecar-write", relative, error);
    }
    // A sidecar I/O failure must not discard an already decoded in-memory poster.
    return poster;
}
