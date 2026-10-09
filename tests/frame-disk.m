#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
static NSString *testRoot;
#define LMV_FRAME_DISK_ROOT testRoot
#import "../LMVFrameDisk.h"
static CGImageRef picture(CGFloat red, CGFloat blue) {
    CGColorSpaceRef color=CGColorSpaceCreateDeviceRGB();
    CGContextRef context=CGBitmapContextCreate(NULL,32,32,8,128,color,kCGImageAlphaNoneSkipLast);
    CGColorSpaceRelease(color);
    CGContextSetRGBFillColor(context,red,0,blue,1); CGContextFillRect(context,CGRectMake(0,0,32,32));
    CGImageRef image=CGBitmapContextCreateImage(context); CGContextRelease(context); return image;
}
static void checkColor(CGImageRef image, BOOL blue) {
    CFDataRef data=CGDataProviderCopyData(CGImageGetDataProvider(image));
    const UInt8 *pixel=CFDataGetBytePtr(data);
    assert(blue ? pixel[2]>pixel[0]+100 : pixel[0]>pixel[2]+100);
    CFRelease(data);
}
int main(void) { @autoreleasepool {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *temporary=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [fm createDirectoryAtPath:temporary withIntermediateDirectories:YES attributes:nil error:nil];
    testRoot=[temporary stringByAppendingPathComponent:@"frames"];
    NSString *material=[temporary stringByAppendingPathComponent:@"actual.mov"];
    NSData *original=[@"original media untouched" dataUsingEncoding:NSUTF8StringEncoding];
    assert([original writeToFile:material atomically:YES]);
    NSString *revision=LMVDiskRevision(material);
    CGImageRef first=picture(1,0),last=picture(0,1);
    assert(LMVDiskWrite(material,revision,first,CMTimeMake(1,30)));
    // The last displayed blue frame, not the first poster, survives a new disk read.
    assert(LMVDiskWrite(material,revision,last,CMTimeMake(73,30)));
    CMTime time=kCMTimeInvalid; CGImageRef restored=LMVDiskRead(material,revision,&time);
    assert(restored && CMTimeCompare(time,CMTimeMake(73,30))==0); checkColor(restored,YES); CGImageRelease(restored);
    NSString *alias=[temporary stringByAppendingPathComponent:@"./actual.mov"];
    assert([LMVDiskRecordPath(alias) isEqual:LMVDiskRecordPath(material)]);
    assert([[NSData dataWithContentsOfFile:material] isEqual:original]);
    NSString *record=LMVDiskRecordPath(material);
    assert([fm fileExistsAtPath:record]);
    // Revision changes discard old pixels and PTS, and remove their stale record.
    assert([[@"changed source revision" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:material atomically:YES]);
    NSString *updated=LMVDiskRevision(material); assert(![updated isEqual:revision]);
    assert(!LMVDiskRead(material,updated,&time) && ![fm fileExistsAtPath:record]);
    assert(!LMVDiskWrite(material,revision,last,CMTimeMake(73,30)));
    assert(!LMVDiskWrite(material,updated,last,kCMTimeInvalid));
    assert(LMVDiskWrite(material,updated,last,CMTimeMake(9,30)));
    // Corrupt records are bounded and removed; symlinks cannot redirect writes.
    assert([[@"broken record" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:record atomically:YES]);
    assert(!LMVDiskRead(material,updated,&time) && ![fm fileExistsAtPath:record]);
    assert([fm createSymbolicLinkAtPath:record withDestinationPath:material error:nil]);
    assert(!LMVDiskWrite(material,updated,last,CMTimeMake(9,30)));
    assert([[NSData dataWithContentsOfFile:material] isEqual:[@"changed source revision" dataUsingEncoding:NSUTF8StringEncoding]]);
    [fm removeItemAtPath:record error:nil];
    for (NSUInteger i=0;i<15;i++) {
        NSString *path=[temporary stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu.mov",(unsigned long)i]];
        assert([original writeToFile:path atomically:YES]);
        assert(LMVDiskWrite(path,LMVDiskRevision(path),last,CMTimeMake(i,30)));
    }
    assert([fm contentsOfDirectoryAtPath:testRoot error:nil].count<=12);
    CGImageRelease(first); CGImageRelease(last); [fm removeItemAtPath:temporary error:nil];
    puts("PASS: real ImageIO disk roundtrip last displayed frame/exact PTS, normalized path, source preserved, revision invalidation, corrupt/symlink rejection, bounded records; NOT device runtime");
} return 0; }
