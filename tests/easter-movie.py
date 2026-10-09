#!/usr/bin/env python3
"""Execute the actual importer on macOS, using a UIImage double only for UIKit."""
from pathlib import Path
import platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
media=(r/'LMVEasterMedia.h').read_text()
# Scoped movie transaction: image-import publication is outside this function.
start=media.index('static NSString *LMVEasterImport(')
movie=media[start:]
assert movie.index('copyItemAtURL:source') < movie.index('tracksWithMediaType:AVMediaTypeVideo') < movie.index('[fm moveItemAtPath:staging')
assert 'if (!error) [fm moveItemAtPath:staging' in movie
assert movie.index('copyNextSampleBuffer') < movie.index('[fm moveItemAtPath:staging')
assert 'if (error) [fm removeItemAtPath:staging' in movie
if platform.system()!='Darwin':
    print('PASS: scoped video validation/publish contracts; native AVFoundation test runs on macOS')
    raise SystemExit(0)
media=media.replace('#pragma once','').replace('#import <UIKit/UIKit.h>','')
import re
media=re.sub(r'static NSString \* const LMVEasterFolder = .*?;', 'static NSString *LMVEasterFolder;', media)
media=media.replace('@"/var/mobile/LockMessageVideo"','testRoot')
for header in ['LMVMaterialStorage.h','LMVMaterialCatalog.h']:
    media=media.replace('"LockMessageVideoPrefs/'+header+'"','"'+str(r/'LockMessageVideoPrefs'/header)+'"')
preamble=r'''
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
static NSString *testRoot;
#define LMV_CATALOG_ROOT testRoot
@interface UIImage : NSObject
+ (instancetype)imageWithCGImage:(CGImageRef)image;
+ (instancetype)animatedImageWithImages:(NSArray *)images duration:(double)duration;
@end
@implementation UIImage
+ (instancetype)imageWithCGImage:(CGImageRef)image { return [self new]; }
+ (instancetype)animatedImageWithImages:(NSArray *)images duration:(double)duration { return [self new]; }
@end
'''
main=r'''
static void makeMovie(NSURL *url) {
    NSError *error=nil;
    AVAssetWriter *writer=[[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error]; assert(writer && !error);
    AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@64,AVVideoHeightKey:@64}];
    AVAssetWriterInputPixelBufferAdaptor *adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32ARGB),(id)kCVPixelBufferWidthKey:@64,(id)kCVPixelBufferHeightKey:@64}];
    assert([writer canAddInput:input]); [writer addInput:input]; assert([writer startWriting]); [writer startSessionAtSourceTime:kCMTimeZero];
    CVPixelBufferRef buffer=NULL; assert(CVPixelBufferCreate(NULL,64,64,kCVPixelFormatType_32ARGB,(__bridge CFDictionaryRef)@{},&buffer)==kCVReturnSuccess);
    CVPixelBufferLockBaseAddress(buffer,0); memset(CVPixelBufferGetBaseAddress(buffer),0x90,CVPixelBufferGetBytesPerRow(buffer)*64); CVPixelBufferUnlockBaseAddress(buffer,0);
    for(int i=0;i<2;i++) { NSUInteger attempts=0; while(!input.readyForMoreMediaData && attempts++<500) [NSThread sleepForTimeInterval:.01]; assert(input.readyForMoreMediaData); assert([adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i,2)]); }
    CVPixelBufferRelease(buffer); [input markAsFinished]; dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }]; assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC))==0); assert(writer.status==AVAssetWriterStatusCompleted);
}
int main(void) { @autoreleasepool {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *temporary=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [fm createDirectoryAtPath:temporary withIntermediateDirectories:YES attributes:nil error:nil];
    testRoot=[temporary stringByAppendingPathComponent:@"LockMessageVideo"]; LMVEasterFolder=[testRoot stringByAppendingPathComponent:@"小彩蛋"];
    NSURL *bad=[NSURL fileURLWithPath:[temporary stringByAppendingPathComponent:@"bad.mov"]];
    assert([[@"not a movie" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:bad atomically:YES]);
    NSURL *good=[NSURL fileURLWithPath:[temporary stringByAppendingPathComponent:@"original.mov"]]; makeMovie(good);
    NSData *before=[NSData dataWithContentsOfURL:good]; assert(before.length);
    dispatch_sync(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        @autoreleasepool {
            NSError *error=nil; assert(!LMVEasterImport(bad,YES,&error) && error);
            NSString *library=[testRoot stringByAppendingPathComponent:@"library"];
            assert([fm contentsOfDirectoryAtPath:library error:nil].count==0);
            assert(LMVReadMaterialNames().count==0);
            error=nil; NSString *relative=LMVEasterImport(good,YES,&error); assert(relative && !error);
            assert([relative hasPrefix:@"library/"]);
            assert([[NSData dataWithContentsOfFile:[testRoot stringByAppendingPathComponent:relative]] isEqual:before]);
            assert([[NSData dataWithContentsOfURL:good] isEqual:before]);
            assert([LMVReadMaterialNames()[relative] hasPrefix:@"彩蛋原片"]);
            assert([fm contentsOfDirectoryAtPath:library error:nil].count==1);
            error=nil; assert(!LMVEasterImport(bad,NO,&error) && error);
            assert([fm contentsOfDirectoryAtPath:LMVEasterFolder error:nil].count==0);
        }
    });
    [fm removeItemAtPath:temporary error:nil];
    puts("PASS: actual importer rejects bad video without file/catalog publication, validates a real H264 original byte-for-byte without compression, image/video isolation; macOS not iOS device");
} return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    source=Path(tmp)/'movie.m'; source.write_text(preamble+media+main)
    binary=Path(tmp)/'movie'
    subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','AVFoundation','-framework','CoreVideo','-framework','CoreMedia','-framework','CoreGraphics','-framework','ImageIO',str(source),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=30)
