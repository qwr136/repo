#!/usr/bin/env python3
"""Execute production selection publication + unlink boundary; UI is source-only."""
from pathlib import Path
import platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1];m=(r/'LMVEasterMedia.h').read_text();ui=(r/'LMVEasterImageSettings.h').read_text()
assert 'if (index.row == 0)' in ui and '当前小彩蛋图片或 GIF 预览' in ui
assert 'index.section != LMVEasterImageSection() || index.row != 1' in ui
assert 'LMVEasterReplaceImage(url, expectedOld, current, &error)' in ui
assert 'dispatch_async(LMVMaterialQueue()' in ui and 'generation != page.previewGeneration' in ui
assert 'previewVisible' in ui and 'previewCellVisible' in ui and 'stopPreview' in ui
assert 'slider.maximumValue = 720' in ui and 'MIN(720.0, round(raw))' in ui
code=m[m.index('static void LMVEasterDeleteReplacedImage'):m.index('static NSString *LMVEasterImportWithPublication')]
assert code.index('BOOL persisted')<code.index('LMVEasterDeleteReplacedImage(old, relative)')
assert 'AT_SYMLINK_NOFOLLOW' in code and 'O_NOFOLLOW' in code
if platform.system()!='Darwin':
 print('PASS preview/import-generation/replace publication source contracts; SKIP native filesystem+preferences transaction requires macOS');raise SystemExit(0)
code=code.replace('open("/var/mobile/LockMessageVideo",','open(testRoot.fileSystemRepresentation,')
pre=r'''
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#include <assert.h>
static NSString *testRoot;
static id selected;
static BOOL persistOK=YES;
static NSUInteger notifications;
static CFStringRef const LMVEasterPrefs=CFSTR("test");
static id LMVEasterRead(NSString *key){return selected;}
static NSError *LMVStorageError(NSInteger n,NSString *s){return [NSError errorWithDomain:@"test" code:n userInfo:@{NSLocalizedDescriptionKey:s}];}
static Boolean testSync(CFStringRef domain){return persistOK;}
static void testSet(CFStringRef key,CFPropertyListRef value,CFStringRef domain){selected=(__bridge id)value;}
static void post(CFNotificationCenterRef center,CFStringRef name,const void *object,CFDictionaryRef info,Boolean immediate){notifications++;}
#define CFPreferencesAppSynchronize testSync
#define CFPreferencesSetAppValue testSet
#define CFNotificationCenterPostNotification post
'''
main=r'''
static NSString *put(NSString *relative){NSString *p=[testRoot stringByAppendingPathComponent:relative];[NSFileManager.defaultManager createDirectoryAtPath:p.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];assert([[@"pixels" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:p atomically:YES]);return p;}
static BOOL has(NSString *r){return [NSFileManager.defaultManager fileExistsAtPath:[testRoot stringByAppendingPathComponent:r]];}
int main(void){@autoreleasepool{
 testRoot=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
 put(@"images/old.gif");put(@"images/new.png");put(@"images/unrelated.jpg");put(@"library/keep.mov");selected=@"images/old.gif";
 NSError *e=nil;assert(LMVEasterPublishImage(@"images/new.png",@"images/old.gif",^BOOL{return YES;},&e));
 assert(!e && !has(@"images/old.gif") && has(@"images/new.png") && has(@"images/unrelated.jpg") && has(@"library/keep.mov"));assert([selected isEqual:@"images/new.png"] && notifications==1);
 // Cancel/stale expected selection and preference failure preserve old bytes.
 put(@"images/failed.gif");e=nil;assert(!LMVEasterPublishImage(@"images/failed.gif",@"wrong",^BOOL{return YES;},&e));assert(e && has(@"images/new.png"));
 e=nil;assert(!LMVEasterPublishImage(@"images/failed.gif",selected,^BOOL{return NO;},&e));assert(has(@"images/new.png"));
 persistOK=NO;e=nil;assert(!LMVEasterPublishImage(@"images/failed.gif",selected,^BOOL{return YES;},&e));assert([selected isEqual:@"images/new.png"] && has(@"images/new.png"));persistOK=YES;
 NSString *external=[testRoot stringByAppendingPathComponent:@"outside.jpg"];put(@"outside.jpg");NSString *link=[testRoot stringByAppendingPathComponent:@"images/link.jpg"];assert(symlink(external.fileSystemRepresentation,link.fileSystemRepresentation)==0);
 LMVEasterDeleteReplacedImage(@"images/link.jpg",@"images/new.png");assert(has(@"outside.jpg") && has(@"images/link.jpg"));
 LMVEasterDeleteReplacedImage(@"images/../outside.jpg",@"images/new.png");LMVEasterDeleteReplacedImage(@"library/keep.mov",@"images/new.png");LMVEasterDeleteReplacedImage(@"images/new.png",@"images/new.png");assert(has(@"outside.jpg") && has(@"library/keep.mov") && has(@"images/new.png"));
 put(@"小彩蛋/legacy.gif");LMVEasterDeleteReplacedImage(@"小彩蛋/legacy.gif",@"images/new.png");assert(!has(@"小彩蛋/legacy.gif"));
 [NSFileManager.defaultManager removeItemAtPath:testRoot error:nil];
 puts("PASS production image publication: durable selection before retiring old GIF/image,failed/cancel/stale keeps old,selected-only unlink,legacy folder,video/unrelated/new/symlink/traversal protected; UI Photos/device not executed");
}return 0;}
'''
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'replace.m';out=Path(d)/'replace';p.write_text(pre+code+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','CoreFoundation',str(p),'-o',str(out)],check=True)
 subprocess.run([str(out)],check=True,timeout=30)
