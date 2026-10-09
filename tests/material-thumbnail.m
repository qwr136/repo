// iOS test executable; exercises real helper code, requires UIKit/AVFoundation.
// Not runnable in Alpine. No device/build proof is implied by this file.
#import <Foundation/Foundation.h>
#include <assert.h>
#define LMV_CATALOG_ROOT @"/tmp/lmv-thumbnail-tests"
#import "../LockMessageVideoPrefs/LMVMaterialThumbnail.h"

static void checkOrientation(CVPixelBufferRef buffer, CGAffineTransform transform, BOOL rotated, BOOL redFirst) {
    UIImage *poster = LMVThumbnailFromBuffer(buffer, transform);
    assert(poster.CGImage);
    size_t w = CGImageGetWidth(poster.CGImage), h = CGImageGetHeight(poster.CGImage);
    assert(w == (rotated ? 2 : 4) && h == (rotated ? 4 : 2));
    unsigned char pixels[32] = {0};
    CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, w, h, 8, w * 4, color, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(color);
    CGContextDrawImage(context, CGRectMake(0,0,w,h), poster.CGImage);
    CGContextRelease(context);
    // Split is horizontal for landscape, vertical after a 90/270 degree rotation.
    size_t a = rotated ? 0 : 0, b = rotated ? (h - 1) * w * 4 : (w - 1) * 4;
    assert((pixels[a] > pixels[a + 2]) == redFirst);
    assert((pixels[b] > pixels[b + 2]) != redFirst);
}
int main(void) {
    @autoreleasepool {
        NSFileManager *fm = NSFileManager.defaultManager;
        [fm removeItemAtPath:LMV_CATALOG_ROOT error:nil];
        [fm createDirectoryAtPath:[LMV_CATALOG_ROOT stringByAppendingPathComponent:@"library"] withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *relative = @"library/测试.mov";
        NSString *path = [LMV_CATALOG_ROOT stringByAppendingPathComponent:relative];
        NSData *video = [@"original-video" dataUsingEncoding:NSUTF8StringEncoding];
        assert([video writeToFile:path atomically:YES]);
        NSString *revision = LMVThumbnailRevision(relative);
        assert(revision.length && !LMVReadThumbnail(relative, revision));
        CVPixelBufferRef buffer = NULL;
        assert(CVPixelBufferCreate(NULL,4,2,kCVPixelFormatType_32BGRA,NULL,&buffer) == kCVReturnSuccess);
        CVPixelBufferLockBaseAddress(buffer,0);
        unsigned char *base = CVPixelBufferGetBaseAddress(buffer);
        size_t stride = CVPixelBufferGetBytesPerRow(buffer);
        for (size_t y=0;y<2;y++) for (size_t x=0;x<4;x++) {
            unsigned char *p = base + y*stride + x*4;
            p[0] = x<2 ? 0 : 255; p[1]=0; p[2]=x<2 ? 255 : 0; p[3]=255;
        }
        CVPixelBufferUnlockBaseAddress(buffer,0);
        checkOrientation(buffer,CGAffineTransformIdentity,NO,YES);
        checkOrientation(buffer,CGAffineTransformMake(-1,0,0,-1,4,2),NO,NO);
        checkOrientation(buffer,CGAffineTransformMake(0,1,-1,0,2,0),YES,YES);
        checkOrientation(buffer,CGAffineTransformMake(0,-1,1,0,0,4),YES,NO);
        UIImage *poster = LMVThumbnailFromBuffer(buffer,CGAffineTransformIdentity);
        CVPixelBufferRelease(buffer);
        assert(!LMVWriteThumbnail(relative,revision,poster));
        assert(LMVReadThumbnail(relative,revision));
        assert([[NSData dataWithContentsOfFile:path] isEqualToData:video]);
        NSString *record = LMVThumbnailRecordPath(relative);
        NSDictionary *attr = [fm attributesOfItemAtPath:record error:nil];
        assert(([attr[NSFilePosixPermissions] unsignedIntegerValue] & 0777) == 0644);
        // Atomic same-sized source replacement changes inode/revision, invalidating old image.
        assert([[ @"replaced-video" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
        NSString *replacement = LMVThumbnailRevision(relative);
        assert(![replacement isEqualToString:revision]);
        assert(!LMVReadThumbnail(relative,revision));
        assert(!LMVReadThumbnail(relative,replacement));
        assert(LMVWriteThumbnail(relative,revision,poster));
        assert(!LMVWriteThumbnail(relative,replacement,poster));
        assert([[ @"corrupt" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:record atomically:YES]);
        assert(!LMVReadThumbnail(relative,replacement));
        [fm removeItemAtPath:path error:nil];
        assert(!LMVThumbnailRevision(relative));
        assert(!LMVReadThumbnail(relative,replacement));
        [fm removeItemAtPath:LMV_CATALOG_ROOT error:nil];
        puts("PASS: real poster orientation, atomic roundtrip, permissions, source preservation, replacement/stale/corrupt/deletion rejection");
    }
    return 0;
}
