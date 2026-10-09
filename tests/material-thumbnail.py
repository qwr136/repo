#!/usr/bin/env python3
"""Run production poster cache/reader with real AVFoundation and Quartz on macOS.
UIImage is replaced by a small CGImage owner; no iOS device claim.
"""
from pathlib import Path
import platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LockMessageVideoPrefs/LMVMaterialThumbnail.h').read_text()
p=(r/'LockMessageVideoPrefs/LMVMaterialPicker.h').read_text()
assert 'copyNextSampleBuffer' in h and 'reader cancelReading' in h
assert 'track.timeRange.start' in h and 'track.preferredTransform' in h
assert 'NSDataWritingAtomic' in h and 'LMVThumbnailRevision(relative)' in h
assert '[picker.thumbnails setObject:poster' in p and 'poster ?: [UIImage systemImageNamed:@"film"]' not in p
assert 'relative, key' in p and 'thumbnailFailures removeAllObjects' in p
if platform.system()!='Darwin':
    print('PASS: poster source contracts; actual cache/orientation/decode runs in macOS CI')
    raise SystemExit(0)
wrapper=r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#include <assert.h>
@interface UIImage : NSObject
@property(nonatomic,assign) CGImageRef CGImage;
+ (instancetype)imageWithCGImage:(CGImageRef)image;
@end
@implementation UIImage
+ (instancetype)imageWithCGImage:(CGImageRef)image { if (!image) return nil; UIImage *value=[self new]; value.CGImage=CGImageRetain(image); return value; }
- (void)dealloc { if (_CGImage) CGImageRelease(_CGImage); }
@end
static NSData *UIImageJPEGRepresentation(UIImage *image, CGFloat quality) {
    if (!image.CGImage) return nil;
    NSMutableData *data=[NSMutableData new];
    CGImageDestinationRef destination=CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data,CFSTR("public.jpeg"),1,NULL);
    if (!destination) return nil;
    CGImageDestinationAddImage(destination,image.CGImage,(__bridge CFDictionaryRef)@{(id)kCGImageDestinationLossyCompressionQuality:@(quality)});
    BOOL ok=CGImageDestinationFinalize(destination); CFRelease(destination); return ok?data:nil;
}
'''
# Existing executable checks orientation, revisions, corrupt/stale/deleted records,
# file permissions and exact preservation of the source bytes.
tests=(r/'tests/material-thumbnail.m').read_text()
tests=tests.replace('#import "../LockMessageVideoPrefs/LMVMaterialThumbnail.h"', h.replace('#import <UIKit/UIKit.h>',''))
# Test a real encoded fixture too, so neither cache-only tests nor source strings
# can pass an entirely broken media decode implementation.
fixture=r'''
        NSString *clipRelative=@"library/fixture.mov";
        NSString *clipPath=[LMV_CATALOG_ROOT stringByAppendingPathComponent:clipRelative];
        NSError *error=nil;
        AVAssetWriter *writer=[[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:clipPath] fileType:AVFileTypeQuickTimeMovie error:&error];
        assert(writer && !error);
        AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@64,AVVideoHeightKey:@32}];
        AVAssetWriterInputPixelBufferAdaptor *adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferWidthKey:@64,(id)kCVPixelBufferHeightKey:@32}];
        assert([writer canAddInput:input]); [writer addInput:input];
        assert([writer startWriting]); [writer startSessionAtSourceTime:kCMTimeZero];
        CVPixelBufferRef frame=NULL;
        assert(CVPixelBufferCreate(NULL,64,32,kCVPixelFormatType_32BGRA,(__bridge CFDictionaryRef)@{(id)kCVPixelBufferCGImageCompatibilityKey:@YES,(id)kCVPixelBufferCGBitmapContextCompatibilityKey:@YES},&frame)==kCVReturnSuccess);
        CVPixelBufferLockBaseAddress(frame,0);
        unsigned char *pixels=CVPixelBufferGetBaseAddress(frame);
        for (size_t y=0;y<32;y++) for (size_t x=0;x<64;x++) {
            unsigned char *pixel=pixels+y*CVPixelBufferGetBytesPerRow(frame)+x*4;
            pixel[0]=10; pixel[1]=20; pixel[2]=240; pixel[3]=255;
        }
        CVPixelBufferUnlockBaseAddress(frame,0);
        for (int i=0;i<3;i++) {
            NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:8];
            while (!input.readyForMoreMediaData && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
            assert(input.readyForMoreMediaData);
            assert([adaptor appendPixelBuffer:frame withPresentationTime:CMTimeMake(i,30)]);
        }
        CVPixelBufferRelease(frame); [input markAsFinished];
        dispatch_semaphore_t finished=dispatch_semaphore_create(0);
        [writer finishWritingWithCompletionHandler:^{dispatch_semaphore_signal(finished);}];
        assert(!dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC)));
        assert(writer.status==AVAssetWriterStatusCompleted);
        NSData *before=[NSData dataWithContentsOfFile:clipPath];
        NSString *clipRevision=LMVThumbnailRevision(clipRelative);
        UIImage *decoded=LMVEnsureThumbnail(clipRelative,clipRevision);
        assert(decoded.CGImage && CGImageGetWidth(decoded.CGImage)<=144 && CGImageGetHeight(decoded.CGImage)<=144);
        assert(LMVReadThumbnail(clipRelative,clipRevision));
        assert([[NSData dataWithContentsOfFile:clipPath] isEqualToData:before]);
'''
tests=tests.replace('        [fm removeItemAtPath:LMV_CATALOG_ROOT error:nil];\n        puts(',fixture+'        [fm removeItemAtPath:LMV_CATALOG_ROOT error:nil];\n        puts(')
with tempfile.TemporaryDirectory() as tmp:
    source=Path(tmp)/'poster.m'; binary=Path(tmp)/'poster'
    source.write_text(wrapper+tests)
    subprocess.run(['clang','-fobjc-arc','-I',str(r/'LockMessageVideoPrefs'),'-framework','Foundation','-framework','CoreGraphics','-framework','ImageIO','-framework','AVFoundation','-framework','CoreVideo','-framework','CoreMedia',str(source),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=50)
