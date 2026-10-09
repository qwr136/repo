#pragma once
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import "LockMessageVideoPrefs/LMVMaterialStorage.h"
#import "LockMessageVideoPrefs/LMVMaterialCatalog.h"

static NSString * const LMVEasterFolder = @"/var/mobile/LockMessageVideo/\u5c0f\u5f69\u86cb";
static CFStringRef const LMVEasterPrefs = CFSTR("com.minis.lockmessagevideo");
static void LMVEasterNotify(void) {
    CFPreferencesAppSynchronize(LMVEasterPrefs);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.minis.lockmessagevideo/preferencesChanged"), NULL, NULL, YES);
}
static id LMVEasterRead(NSString *key) {
    return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key, LMVEasterPrefs);
}
static void LMVEasterSet(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, LMVEasterPrefs);
    LMVEasterNotify();
}
static BOOL LMVEasterSafeDirectory(NSString *path, NSError **error) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    struct stat status;
    if (lstat(path.fileSystemRepresentation, &status) || !S_ISDIR(status.st_mode) || ![[path stringByResolvingSymlinksInPath] isEqualToString:path]) {
        if (error) *error = LMVStorageError(60, @"素材目录不安全，未保存文件");
        return NO;
    }
    return YES;
}
static NSString *LMVEasterImagePath(id relative) {
    if (![relative isKindOfClass:NSString.class]) return nil;
    NSArray *parts = [relative pathComponents];
    if (parts.count != 2 || ![parts[0] isEqualToString:@"\u5c0f\u5f69\u86cb"] || [parts containsObject:@".."] || [parts containsObject:@"."]) return nil;
    NSString *path = [@"/var/mobile/LockMessageVideo" stringByAppendingPathComponent:relative];
    struct stat status;
    if (lstat(path.fileSystemRepresentation, &status) || !S_ISREG(status.st_mode) || status.st_size <= 0 || status.st_size > 20 * 1024 * 1024 || ![[path stringByResolvingSymlinksInPath] isEqualToString:path]) return nil;
    return path;
}

@interface LMVEasterImage : NSObject
@property(nonatomic, copy) NSArray<UIImage *> *frames;
@property(nonatomic, copy) NSArray<NSNumber *> *delays;
@end
@implementation LMVEasterImage
@end

// A bounded decode: at most 60 x 160px frames, below 8 MiB decoded pixels.
static LMVEasterImage *LMVEasterDecode(NSURL *url, NSError **error) {
    NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:url.path error:error];
    if (!attrs || ![attrs[NSFileType] isEqual:NSFileTypeRegular] || !attrs.fileSize || attrs.fileSize > 20 * 1024 * 1024) {
        if (error && !*error) *error = LMVStorageError(61, @"图片需为不超过 20 MiB 的普通文件");
        return nil;
    }
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, (__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCache:@NO});
    size_t count = source ? CGImageSourceGetCount(source) : 0;
    if (!count || count > 60) {
        if (source) CFRelease(source);
        if (error) *error = LMVStorageError(62, @"图片无法解码，或 GIF 超过 60 帧");
        return nil;
    }
    NSMutableArray *frames = [NSMutableArray new], *delays = [NSMutableArray new];
    NSUInteger cost = 0;
    for (size_t i = 0; i < count; i++) {
        @autoreleasepool {
            CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, i, (__bridge CFDictionaryRef)@{(id)kCGImageSourceCreateThumbnailFromImageAlways:@YES, (id)kCGImageSourceCreateThumbnailWithTransform:@YES, (id)kCGImageSourceThumbnailMaxPixelSize:@160, (id)kCGImageSourceShouldCacheImmediately:@YES});
            if (!image) break;
            cost += CGImageGetBytesPerRow(image) * CGImageGetHeight(image);
            if (cost > 8 * 1024 * 1024) { CGImageRelease(image); break; }
            [frames addObject:[UIImage imageWithCGImage:image]];
            CGImageRelease(image);
            NSDictionary *properties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
            NSDictionary *gif = properties[(id)kCGImagePropertyGIFDictionary];
            double delay = [gif[(id)kCGImagePropertyGIFUnclampedDelayTime] ?: gif[(id)kCGImagePropertyGIFDelayTime] doubleValue];
            [delays addObject:@(isfinite(delay) && delay >= 0.02 ? MIN(delay, 10.0) : 0.1)];
        }
    }
    CFRelease(source);
    if (frames.count != count) {
        if (error) *error = LMVStorageError(63, @"图片解码失败或超过内存限制");
        return nil;
    }
    LMVEasterImage *decoded = [LMVEasterImage new]; decoded.frames = frames; decoded.delays = delays;
    return decoded;
}

// Must execute inside NSItemProvider's background callback: its URL expires on return.
static NSString *LMVEasterImport(NSURL *source, BOOL movie, NSError **outError) {
    if (NSThread.isMainThread || !source.isFileURL) {
        if (outError) *outError = LMVStorageError(64, @"导入必须在相册后台回调中执行");
        return nil;
    }
    __block NSString *result = nil; __block NSError *error = nil;
    dispatch_sync(LMVMaterialQueue(), ^{
        @autoreleasepool {
            NSString *root = @"/var/mobile/LockMessageVideo";
            NSString *folder = movie ? [root stringByAppendingPathComponent:@"library"] : LMVEasterFolder;
            NSFileManager *fm = NSFileManager.defaultManager;
            if (!LMVEasterSafeDirectory(root, &error) || !LMVEasterSafeDirectory(folder, &error)) return;
            NSString *ext = source.pathExtension.lowercaseString;
            if (movie && ![@[@"mov", @"mp4", @"m4v"] containsObject:ext]) { error = LMVStorageError(65, @"支持 MOV、MP4、M4V 视频"); return; }
            if (!movie && ![@[@"gif", @"png", @"jpg", @"jpeg", @"heic", @"heif"] containsObject:ext]) { error = LMVStorageError(66, @"不支持此图片格式"); return; }
            NSString *name = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:ext];
            NSString *staging = [folder stringByAppendingPathComponent:[@".pending-" stringByAppendingString:name]];
            NSString *destination = [folder stringByAppendingPathComponent:name];
            NSDictionary *attrs = [fm attributesOfItemAtPath:source.path error:&error];
            unsigned long long maximum = movie ? 512ULL * 1024 * 1024 : 20ULL * 1024 * 1024;
            if (error || !attrs.fileSize || attrs.fileSize > maximum) { error = error ?: LMVStorageError(67, movie ? @"视频需小于 512 MiB" : @"图片需小于 20 MiB"); return; }
            if (![fm copyItemAtURL:source toURL:[NSURL fileURLWithPath:staging] error:&error]) return;
            NSURL *owned = [NSURL fileURLWithPath:staging];
            if (movie) {
                AVURLAsset *asset = [AVURLAsset URLAssetWithURL:owned options:nil];
                double duration = CMTimeGetSeconds(asset.duration);
                AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
                if (!asset.playable || !track || !isfinite(duration) || duration <= 0) error = LMVStorageError(68, @"原视频没有可播放的视频轨道");
                if (!error) {
                    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
                    AVAssetReaderTrackOutput *output = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)}];
                    if (!reader || ![reader canAddOutput:output]) error = error ?: LMVStorageError(69, @"视频格式无法解码");
                    else {
                        [reader addOutput:output];
                        BOOL started = [reader startReading];
                        CMSampleBufferRef sample = started ? [output copyNextSampleBuffer] : NULL;
                        if (!sample) error = reader.error ?: LMVStorageError(69, @"视频没有可解码画面");
                        if (sample) CFRelease(sample);
                        [reader cancelReading];
                    }
                }
            } else if (!LMVEasterDecode(owned, &error)) error = error ?: LMVStorageError(70, @"图片无法解码");
            if (!error && ![fm moveItemAtPath:staging toPath:destination error:&error]) { /* atomic same-volume publication */ }
            if (!error && movie) {
                NSString *relative = [@"library" stringByAppendingPathComponent:name];
                NSMutableDictionary *names = LMVReadMaterialNames();
                names[relative] = [NSString stringWithFormat:@"彩蛋原片 · %@", source.lastPathComponent.stringByDeletingPathExtension];
                error = LMVWriteMaterialNames(names);
                if (error) [fm removeItemAtPath:destination error:nil];
            }
            if (error) [fm removeItemAtPath:staging error:nil];
            else result = [(movie ? @"library" : @"\u5c0f\u5f69\u86cb") stringByAppendingPathComponent:name];
        }
    });
    if (outError) *outError = error;
    return result;
}
