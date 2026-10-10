#!/usr/bin/env python3
from pathlib import Path
import platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LMVVideoPosterStore.h').read_text()
assert 'O_NOFOLLOW' in h and 'renameat(' in h and 'fstat(' in h
assert 'LMVLockVideoRevision(path)' in h and 'CGImageSourceCopyPropertiesAtIndex' in h
assert 'LMVFrameCache' not in h and 'LMVFrameDisk' not in h
if platform.system()!='Darwin':
 print('PASS: revision-bound atomic background poster store contracts; native ImageIO roundtrip runs on macOS CI')
 raise SystemExit(0)
code=r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <sys/stat.h>
#include <assert.h>
#include <math.h>
#include <unistd.h>
static NSString *posterRoot;
#define LMV_VIDEO_POSTER_ROOT posterRoot
static NSString *LMVLockVideoRevision(NSString *path) {
 struct stat s;if(!path.length || lstat(path.fileSystemRepresentation,&s) || !S_ISREG(s.st_mode) || s.st_size<=0)return nil;
 return [NSString stringWithFormat:@"%llu:%llu:%lld:%lld:%ld:%lld:%ld",(unsigned long long)s.st_dev,(unsigned long long)s.st_ino,(long long)s.st_size,(long long)s.st_mtimespec.tv_sec,s.st_mtimespec.tv_nsec,(long long)s.st_ctimespec.tv_sec,s.st_ctimespec.tv_nsec];
}
#import "LMVVideoPosterStore.h"
static CGImageRef image(size_t w,size_t h) {
 CGColorSpaceRef c=CGColorSpaceCreateDeviceRGB();CGContextRef ctx=CGBitmapContextCreate(NULL,w,h,8,w*4,c,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(c);assert(ctx);
 CGContextSetRGBFillColor(ctx,1,0,0,1);CGContextFillRect(ctx,CGRectMake(0,0,w,h));CGImageRef i=CGBitmapContextCreateImage(ctx);CGContextRelease(ctx);return i;
}
static void red(CGImageRef i) {
 unsigned char pixel[4]={0};CGColorSpaceRef c=CGColorSpaceCreateDeviceRGB();CGContextRef ctx=CGBitmapContextCreate(pixel,1,1,8,4,c,kCGImageAlphaPremultipliedLast);CGColorSpaceRelease(c);assert(ctx);
 CGContextDrawImage(ctx,CGRectMake(0,0,1,1),i);CGContextRelease(ctx);assert(pixel[0]>240 && pixel[1]<15 && pixel[2]<15);
}
int main(int argc,const char **argv){@autoreleasepool {
 assert(argc==2);NSString *root=[NSString stringWithUTF8String:argv[1]];posterRoot=[root stringByAppendingPathComponent:@"cache"];
 NSString *path=[root stringByAppendingPathComponent:@"video.mov"];NSData *original=[@"a video material used only for revision identity" dataUsingEncoding:NSUTF8StringEncoding];assert([original writeToFile:path atomically:YES]);
 NSString *rev=LMVLockVideoRevision(path);CGImageRef first=image(640,960);assert(LMVVideoPosterWrite(path,rev,first));CGImageRelease(first);
 CGImageRef read=LMVVideoPosterRead(path,rev);assert(read && CGImageGetWidth(read)==640 && CGImageGetHeight(read)==960);red(read);CGImageRelease(read);
 NSString *cache=[posterRoot stringByAppendingPathComponent:LMVVideoPosterName(path)];NSData *good=[NSData dataWithContentsOfFile:cache];assert(good.length);
 assert(!LMVVideoPosterWrite(path,@"stale",NULL));assert([[NSData dataWithContentsOfFile:cache] isEqual:good]);
 assert(!LMVVideoPosterRead(path,@"stale"));assert([[NSData dataWithContentsOfFile:path] isEqual:original]);
 // Replacement of equal-size source bytes must invalidate the old inode/revision.
 assert([original writeToFile:path atomically:YES]);NSString *replaced=LMVLockVideoRevision(path);assert(![rev isEqual:replaced]);assert(!LMVVideoPosterRead(path,replaced) && !LMVVideoPosterRead(path,rev));
 first=image(2000,1000);assert(LMVVideoPosterWrite(path,replaced,first));CGImageRelease(first);read=LMVVideoPosterRead(path,replaced);assert(read && CGImageGetWidth(read)<=1440 && CGImageGetHeight(read)<=1440);CGImageRelease(read);
 good=[NSData dataWithContentsOfFile:cache];assert([[@"corrupt" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:cache atomically:YES]);assert(!LMVVideoPosterRead(path,replaced));
 assert([good writeToFile:cache atomically:YES]);NSMutableDictionary *record=[[NSPropertyListSerialization propertyListWithData:good options:NSPropertyListMutableContainers format:nil error:nil] mutableCopy];record[@"path"]=@4;
 NSData *bad=[NSPropertyListSerialization dataWithPropertyList:record format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];assert([bad writeToFile:cache atomically:YES]);assert(!LMVVideoPosterRead(path,replaced));assert([good writeToFile:cache atomically:YES]);
 // Cache symlinks must neither be followed nor overwritten; source stays intact.
 [NSFileManager.defaultManager removeItemAtPath:cache error:nil];assert(symlink(path.fileSystemRepresentation,cache.fileSystemRepresentation)==0);assert(!LMVVideoPosterRead(path,replaced));
 first=image(10,10);assert(!LMVVideoPosterWrite(path,replaced,first));CGImageRelease(first);assert([[NSData dataWithContentsOfFile:path] isEqual:original]);
 [NSFileManager.defaultManager removeItemAtPath:cache error:nil];[NSFileManager.defaultManager removeItemAtPath:posterRoot error:nil];
 assert(symlink(root.fileSystemRepresentation,posterRoot.fileSystemRepresentation)==0);first=image(10,10);assert(!LMVVideoPosterWrite(path,replaced,first));CGImageRelease(first);assert(!LMVVideoPosterRead(path,replaced));
 [NSFileManager.defaultManager removeItemAtPath:posterRoot error:nil];first=image(10,10);assert(LMVVideoPosterWrite(path,replaced,first));CGImageRelease(first);[NSFileManager.defaultManager removeItemAtPath:path error:nil];assert(!LMVVideoPosterRead(path,replaced));
 dispatch_sync(LMVVideoPosterQueue(),^{});
 puts("PASS: actual ImageIO background poster store: matching path/revision pixels roundtrip, atomic replacement, bounded dimensions, corrupt/missing/type/symlink rejection, equal-size source replacement invalidates, source bytes preserved; not device startup timing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'poster.m';binary=Path(tmp)/'poster';source.write_text(code)
 subprocess.run(['clang','-fobjc-arc','-I',str(r),'-framework','Foundation','-framework','CoreGraphics','-framework','ImageIO',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary),tmp],check=True,timeout=30)
