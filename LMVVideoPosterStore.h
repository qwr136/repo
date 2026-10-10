#pragma once
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CommonCrypto/CommonDigest.h>
#import <fcntl.h>
#import <unistd.h>
#import <sys/stat.h>
#import <errno.h>
#ifndef LMV_VIDEO_POSTER_ROOT
#define LMV_VIDEO_POSTER_ROOT @"/var/mobile/LockMessageVideo/.background-posters"
#endif
static dispatch_queue_t LMVVideoPosterQueue(void) {
    static dispatch_queue_t queue;static dispatch_once_t once;
    dispatch_once(&once,^{queue=dispatch_queue_create("com.minis.lockmessagevideo.background-posters",DISPATCH_QUEUE_SERIAL);});return queue;
}
static NSString *LMVVideoPosterName(NSString *path) {
    if(!path.length || !path.isAbsolutePath)return nil;
    NSData *data=[path.stringByStandardizingPath dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(data.bytes,(CC_LONG)data.length,digest);
    NSMutableString *name=[NSMutableString new];for(NSUInteger n=0;n<sizeof(digest);n++)[name appendFormat:@"%02x",digest[n]];
    return [name stringByAppendingPathExtension:@"plist"];
}
static int LMVVideoPosterDirectory(BOOL create) {
    if(create) [NSFileManager.defaultManager createDirectoryAtPath:LMV_VIDEO_POSTER_ROOT withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:nil];
    struct stat s;if(lstat([LMV_VIDEO_POSTER_ROOT fileSystemRepresentation],&s) || !S_ISDIR(s.st_mode))return -1;
    return open([LMV_VIDEO_POSTER_ROOT fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
}
static CGImageRef LMVVideoPosterRead(NSString *path,NSString *revision) {
    NSString *name=LMVVideoPosterName(path);
    if(!name || !revision.length || ![LMVLockVideoRevision(path) isEqualToString:revision])return NULL;
    int directory=LMVVideoPosterDirectory(NO);if(directory<0)return NULL;
    int file=openat(directory,name.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW);close(directory);if(file<0)return NULL;
    struct stat s;if(fstat(file,&s) || !S_ISREG(s.st_mode) || s.st_size<=0 || s.st_size>8*1024*1024){close(file);return NULL;}
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)s.st_size];NSUInteger count=0;BOOL okay=YES;
    while(count<data.length) {ssize_t n=read(file,(char *)data.mutableBytes+count,data.length-count);if(n<0 && errno==EINTR)continue;if(n<=0){okay=NO;break;}count+=(NSUInteger)n;}close(file);
    if(!okay)return NULL;
    id record=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
    if(![record isKindOfClass:NSDictionary.class] || ![record[@"schema"] isEqual:@1] ||
       ![record[@"path"] isKindOfClass:NSString.class] || ![record[@"revision"] isKindOfClass:NSString.class] ||
       ![record[@"path"] isEqualToString:path.stringByStandardizingPath] || ![record[@"revision"] isEqualToString:revision])return NULL;
    NSData *encoded=record[@"image"];if(![encoded isKindOfClass:NSData.class] || !encoded.length || encoded.length>6*1024*1024)return NULL;
    CGImageSourceRef source=CGImageSourceCreateWithData((__bridge CFDataRef)encoded,NULL);if(!source)return NULL;
    NSDictionary *props=(__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source,0,NULL);
    NSUInteger width=[props[(id)kCGImagePropertyPixelWidth] unsignedIntegerValue],height=[props[(id)kCGImagePropertyPixelHeight] unsignedIntegerValue];
    CGImageRef image=NULL;
    if(width>0 && height>0 && width<=1440 && height<=1440) image=CGImageSourceCreateImageAtIndex(source,0,(__bridge CFDictionaryRef)@{(id)kCGImageSourceShouldCacheImmediately:@YES});
    CFRelease(source);
    if(image && ![LMVLockVideoRevision(path) isEqualToString:revision]) {CGImageRelease(image);image=NULL;}
    return image;
}
static BOOL LMVVideoPosterWrite(NSString *path,NSString *revision,CGImageRef image) {
    NSString *name=LMVVideoPosterName(path);
    if(!name || !image || !revision.length || ![LMVLockVideoRevision(path) isEqualToString:revision])return NO;
    size_t width=CGImageGetWidth(image),height=CGImageGetHeight(image);if(!width || !height || width>16384 || height>16384)return NO;
    CGFloat scale=MIN(1.0,1440.0/MAX(width,height));size_t w=MAX(1,(size_t)llround(width*scale)),h=MAX(1,(size_t)llround(height*scale));
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();CGContextRef context=CGBitmapContextCreate(NULL,w,h,8,w*4,color,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(color);if(!context)return NO;
    CGContextSetInterpolationQuality(context,kCGInterpolationHigh);CGContextDrawImage(context,CGRectMake(0,0,w,h),image);
    CGImageRef scaled=CGBitmapContextCreateImage(context);CGContextRelease(context);if(!scaled)return NO;
    NSMutableData *encoded=[NSMutableData new];CGImageDestinationRef writer=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)encoded,CFSTR("public.jpeg"),1,NULL);
    BOOL okay=NO;if(writer){CGImageDestinationAddImage(writer,scaled,(__bridge CFDictionaryRef)@{(id)kCGImageDestinationLossyCompressionQuality:@0.9});okay=CGImageDestinationFinalize(writer);CFRelease(writer);}CGImageRelease(scaled);
    if(!okay || encoded.length>6*1024*1024)return NO;
    NSDictionary *record=@{@"schema":@1,@"path":path.stringByStandardizingPath,@"revision":revision,@"image":encoded};
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];if(!data || data.length>8*1024*1024)return NO;
    int directory=LMVVideoPosterDirectory(YES);if(directory<0)return NO;
    struct stat s;
    if(fstatat(directory,name.fileSystemRepresentation,&s,AT_SYMLINK_NOFOLLOW)==0 && !S_ISREG(s.st_mode)){close(directory);return NO;}
    NSString *temporary=[@".poster-" stringByAppendingString:NSUUID.UUID.UUIDString];
    int file=openat(directory,temporary.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0644);if(file<0){close(directory);return NO;}
    NSUInteger count=0;okay=YES;
    while(count<data.length){ssize_t n=write(file,(const char *)data.bytes+count,data.length-count);if(n<0 && errno==EINTR)continue;if(n<=0){okay=NO;break;}count+=(NSUInteger)n;}
    if(okay && fsync(file)!=0)okay=NO;close(file);
    okay=okay && [LMVLockVideoRevision(path) isEqualToString:revision];
    if(okay)okay=renameat(directory,temporary.fileSystemRepresentation,directory,name.fileSystemRepresentation)==0;
    if(!okay)unlinkat(directory,temporary.fileSystemRepresentation,0);close(directory);
    if(okay) {
        // Bounded cache; only own digest-named records, never video materials.
        NSArray *files=[NSFileManager.defaultManager contentsOfDirectoryAtPath:LMV_VIDEO_POSTER_ROOT error:nil];
        NSMutableArray *records=[NSMutableArray new];for(NSString *entry in files)if(entry.length==70 && [entry.pathExtension isEqualToString:@"plist"])[records addObject:entry];
        [records sortUsingComparator:^NSComparisonResult(NSString *a,NSString *b){
            NSDate *x=[NSFileManager.defaultManager attributesOfItemAtPath:[LMV_VIDEO_POSTER_ROOT stringByAppendingPathComponent:a] error:nil][NSFileModificationDate];
            NSDate *y=[NSFileManager.defaultManager attributesOfItemAtPath:[LMV_VIDEO_POSTER_ROOT stringByAppendingPathComponent:b] error:nil][NSFileModificationDate];return [(x ?: NSDate.distantPast) compare:(y ?: NSDate.distantPast)];
        }];
        int dir=LMVVideoPosterDirectory(NO);if(dir>=0){while(records.count>12){NSString *old=records.firstObject;[records removeObjectAtIndex:0];if(![old isEqualToString:name])unlinkat(dir,old.fileSystemRepresentation,0);}close(dir);}
    }
    return okay;
}
