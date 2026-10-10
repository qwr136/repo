#!/usr/bin/env python3
"""Source contracts, fd boundary checks and actual macOS AVFoundation import; not iOS UI."""
from pathlib import Path
import os, stat, tempfile, platform, subprocess
root=Path(__file__).resolve().parents[1]
prefs=(root/'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
tweak=(root/'Tweak.xm').read_text()
imp=(root/'LockMessageVideoPrefs/LMVImport.h').read_text()
storage=(root/'LockMessageVideoPrefs/LMVMaterialStorage.h').read_text()
picker=(root/'LockMessageVideoPrefs/LMVMaterialPicker.h').read_text()
assert prefs.index('preferenceSpecifierNamed:@"打开素材路径"') < prefs.index('preferenceSpecifierNamed:@"启用诊断日志"')
assert '清空原素材' not in prefs
assert '[diagnostics setProperty:@NO forKey:@"default"]' in prefs
assert 'style:UIAlertActionStyleDestructive' in picker and '无法撤销' in picker
assert 'self.materialBusy = YES' in prefs and 'self.materialBusy = NO' in prefs
assert 'dispatch_async(LMVMaterialQueue()' in picker
assert 'LMVDeleteMaterial(relative,&deleted)' in picker
deletion=(root/'LockMessageVideoPrefs/LMVMaterialDeletion.h').read_text()
assert 'AT_SYMLINK_NOFOLLOW' in deletion
assert 'dispatch_sync(LMVMaterialQueue()' in imp and 'if (NSThread.isMainThread)' in imp
assert 'std::atomic_bool LMVDiagnosticsEnabled(false)' in tweak
log=tweak.split('static void LMVDiagnostic(NSString *event) {',1)[1].split('@interface LMVFrameSnapshot',1)[0]
assert log.count('LMVDiagnosticsEnabled.load()')==2
assert 'LMVDiagnosticsEnabled.exchange(diagnosticsEnabled)' in tweak
assert 'CFSTR("DiagnosticsEnabled")' in tweak
assert '512ULL * 1024ULL * 1024ULL' in imp and '512 MiB' in prefs
assert 'LMVImportCopyBytes(input,staging,&owned)' in imp
assert 'LMVValidateMovie(ownedSource)' in imp and 'CMSampleBufferGetImageBuffer(sample)' in imp
transaction=imp.split('static NSString *LMVImportMovieOnMaterialQueue(',1)[1]
assert transaction.index('LMVImportCopyBytes(') < transaction.index('LMVValidateMovie(') < transaction.index('LMVImportPublish(') < transaction.index('LMVImportRegisterName(')
for token in ['O_NOFOLLOW', 'O_EXCL', 'AT_SYMLINK_NOFOLLOW', 'S_ISREG', 'linkat(', 'LMVImportUnlinkOwned', 'NSUnderlyingErrorKey']:
    assert token in imp, token
for token in ['LMVEncodePlan', 'LMVCompressMovie', 'LMVEncodeMovie', 'AVAssetWriter', 'AVMutableVideoComposition', 'AVVideoExpectedSourceFrameRateKey', '.encode-']:
    assert token not in imp, token
for filename in ['LMVPRootListController.m', 'LMVPVideoPickerController.m']:
    text=(root/'LockMessageVideoPrefs'/filename).read_text()
    assert 'config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;' in text
    assert 'LMVImportMovie(url, &' in text
    assert '重新压缩' not in text and '临时原素材已清理' not in text
assert '所有视频重新压缩' not in prefs and '无音轨 H.264' not in prefs
assert 'removeItemAtPath' not in storage and 'CFPreferencesSetAppValue' not in storage
assert 'S_ISREG(status.st_mode)' in deletion
assert 'unlinkat(folder,name,0)' in deletion
# Exercise equivalent nonrecursive fd-relative boundary policy on Linux.
with tempfile.TemporaryDirectory() as tmp:
    base=Path(tmp); originals=base/'originals'; library=base/'library'
    originals.mkdir(); library.mkdir(); (library/'selected.mov').write_bytes(b'keep')
    (originals/'video.mov').write_bytes(b'remove')
    (originals/'nested').mkdir(); (originals/'nested'/'child.mov').write_bytes(b'keep')
    (originals/'link').symlink_to(library,target_is_directory=True)
    fd=os.open(originals,os.O_RDONLY|os.O_DIRECTORY|os.O_NOFOLLOW)
    for name in os.listdir(fd):
        status=os.stat(name,dir_fd=fd,follow_symlinks=False)
        if stat.S_ISREG(status.st_mode): os.unlink(name,dir_fd=fd)
    assert sorted(os.listdir(fd))==['link','nested']; os.close(fd)
    assert (library/'selected.mov').read_bytes()==b'keep'
    assert (originals/'nested'/'child.mov').read_bytes()==b'keep'
    assert (originals/'link').is_symlink()
print('PASS: diagnostics/deletion contracts preserved; Current representation, original-copy/decode/publish/catalog order, no encoder, 512 MiB and fd boundaries')
if platform.system() != 'Darwin':
    print('DEFER: actual settings-import AVFoundation runtime requires macOS; Linux source/fd checks do not prove video decoding')
    raise SystemExit(0)

# Compile the production importer and catalog against real Foundation/AVFoundation.
# Only UIKit thumbnail generation is excluded; separate thumbnail tests cover it.
native=imp
for header in ['LMVThumbnailDiagnosticLog.h', 'LMVMaterialThumbnail.h']:
    native=native.replace('#import "'+header+'"', '')
for header in ['LMVMaterialStorage.h', 'LMVMaterialCatalog.h']:
    native=native.replace('"'+header+'"', '"'+str(root/'LockMessageVideoPrefs'/header)+'"')
native=native.replace('static NSError *LMVValidateMovie(NSURL *url) {', 'static NSError *LMVValidateMovieImplementation(NSURL *url) {')
native=native.replace('static NSError *LMVImportRegisterName(int root, NSString *relative, NSString *sourceName) {', 'static NSError *LMVImportRegisterNameImplementation(int root, NSString *relative, NSString *sourceName) {')
preamble=r'''
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
static NSString *testRoot;
#define LMV_CATALOG_ROOT testRoot
@interface UIImage : NSObject @end
@implementation UIImage @end
static NSString *LMVThumbnailRevision(NSString *relative) { return nil; }
static UIImage *LMVDecodeThumbnail(NSString *relative) { return nil; }
static NSError *LMVWriteThumbnail(NSString *relative, NSString *revision, UIImage *poster) { return nil; }
static void LMVThumbnailLog(NSString *event, NSString *relative, NSError *error) {}
static NSError *LMVValidateMovie(NSURL *url);
static NSError *LMVImportRegisterName(int root, NSString *relative, NSString *sourceName);
'''
main=r'''
static NSData *expectedBytes;
static NSUInteger expectedFiles, expectedNames, validations, registrations;
static BOOL failCatalog;
static NSUInteger libraryCount(void) {
    return [NSFileManager.defaultManager contentsOfDirectoryAtPath:[testRoot stringByAppendingPathComponent:@"library"] error:nil].count;
}
static void noPending(void) {
    for (NSString *name in [NSFileManager.defaultManager contentsOfDirectoryAtPath:testRoot error:nil]) assert(![name hasPrefix:@".import-"]);
}
static NSError *LMVValidateMovie(NSURL *url) {
    assert([url.lastPathComponent hasPrefix:@".import-source-"]);
    assert([[NSData dataWithContentsOfURL:url] isEqual:expectedBytes]);
    // Decode runs before either publication or catalog registration.
    assert(libraryCount()==expectedFiles && LMVReadMaterialNames().count==expectedNames);
    validations++;
    return LMVValidateMovieImplementation(url);
}
static NSError *LMVImportRegisterName(int descriptor, NSString *relative, NSString *sourceName) {
    assert(libraryCount()==expectedFiles+1 && LMVReadMaterialNames().count==expectedNames);
    assert([[NSData dataWithContentsOfFile:[testRoot stringByAppendingPathComponent:relative]] isEqual:expectedBytes]);
    noPending(); registrations++;
    if (failCatalog) return LMVImportIOError(EIO,@"injected catalog write failure");
    return LMVImportRegisterNameImplementation(descriptor,relative,sourceName);
}
static void makeVideo(NSURL *url) {
    NSError *error=nil;
    AVAssetWriter *writer=[[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error]; assert(writer && !error);
    AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@320,AVVideoHeightKey:@180}];
    input.transform=CGAffineTransformMakeRotation(M_PI_2);
    AVAssetWriterInputPixelBufferAdaptor *adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32ARGB),(id)kCVPixelBufferWidthKey:@320,(id)kCVPixelBufferHeightKey:@180}];
    assert([writer canAddInput:input]); [writer addInput:input]; assert([writer startWriting]); [writer startSessionAtSourceTime:kCMTimeZero];
    CVPixelBufferRef buffer=NULL; assert(CVPixelBufferCreate(NULL,320,180,kCVPixelFormatType_32ARGB,(__bridge CFDictionaryRef)@{},&buffer)==kCVReturnSuccess);
    CVPixelBufferLockBaseAddress(buffer,0); memset(CVPixelBufferGetBaseAddress(buffer),0x90,CVPixelBufferGetBytesPerRow(buffer)*180); CVPixelBufferUnlockBaseAddress(buffer,0);
    for(int i=0;i<60;i++) { NSUInteger attempts=0; while(!input.readyForMoreMediaData && attempts++<500) [NSThread sleepForTimeInterval:.01]; assert(input.readyForMoreMediaData); assert([adaptor appendPixelBuffer:buffer withPresentationTime:CMTimeMake(i,60)]); }
    CVPixelBufferRelease(buffer); [input markAsFinished]; dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }]; assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC))==0); assert(writer.status==AVAssetWriterStatusCompleted);
}
static void makeWave(NSURL *url) {
    // One second of valid PCM silence; real audio input for the fixture export.
    unsigned char header[44]={'R','I','F','F',0x24,0x77,0x01,0,'W','A','V','E','f','m','t',' ',16,0,0,0,1,0,1,0,0x80,0xbb,0,0,0,0x77,1,0,2,0,16,0,'d','a','t','a',0,0x77,1,0};
    NSMutableData *wave=[NSMutableData dataWithBytes:header length:44]; [wave increaseLengthBy:96000]; assert([wave writeToURL:url atomically:YES]);
}
static void makeMovie(NSURL *videoURL, NSURL *waveURL, NSURL *url, AVFileType type) {
    AVURLAsset *video=[AVURLAsset URLAssetWithURL:videoURL options:nil];
    AVURLAsset *audio=[AVURLAsset URLAssetWithURL:waveURL options:nil];
    AVMutableComposition *composition=[AVMutableComposition composition]; NSError *error=nil;
    AVMutableCompositionTrack *v=[composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    AVAssetTrack *source=[video tracksWithMediaType:AVMediaTypeVideo].firstObject; assert(source);
    assert([v insertTimeRange:CMTimeRangeMake(kCMTimeZero,CMTimeMake(1,1)) ofTrack:source atTime:kCMTimeZero error:&error]); v.preferredTransform=source.preferredTransform;
    AVMutableCompositionTrack *a=[composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    assert([a insertTimeRange:CMTimeRangeMake(kCMTimeZero,CMTimeMake(1,1)) ofTrack:[audio tracksWithMediaType:AVMediaTypeAudio].firstObject atTime:kCMTimeZero error:&error]);
    // Encoding belongs solely to fixture generation, never the importer under test.
    AVAssetExportSession *export=[[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetHighestQuality]; assert(export && [export.supportedFileTypes containsObject:type]);
    export.outputURL=url; export.outputFileType=type;
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    [export exportAsynchronouslyWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC))==0);
    if (export.status!=AVAssetExportSessionStatusCompleted) NSLog(@"fixture export error=%@",export.error);
    assert(export.status==AVAssetExportSessionStatusCompleted);
    assert([[AVURLAsset URLAssetWithURL:url options:nil] tracksWithMediaType:AVMediaTypeAudio].count==1);
}
static void setExpected(NSURL *url) {
    expectedBytes=[NSData dataWithContentsOfURL:url]; assert(expectedBytes.length);
    expectedFiles=libraryCount(); expectedNames=LMVReadMaterialNames().count;
}
static void assertRejected(NSURL *url) {
    NSError *error=nil; NSUInteger files=libraryCount(); NSDictionary *names=LMVReadMaterialNames();
    assert(!LMVImportMovie(url,&error) && error);
    assert(libraryCount()==files && [LMVReadMaterialNames() isEqual:names]); noPending();
}
int main(void) { @autoreleasepool {
    NSFileManager *fm=NSFileManager.defaultManager;
    NSString *temporary=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    assert([fm createDirectoryAtPath:temporary withIntermediateDirectories:YES attributes:nil error:nil]);
    testRoot=[temporary stringByAppendingPathComponent:@"LockMessageVideo"];
    NSURL *video=[NSURL fileURLWithPath:[temporary stringByAppendingPathComponent:@"video.mov"]]; makeVideo(video);
    NSURL *wave=[NSURL fileURLWithPath:[temporary stringByAppendingPathComponent:@"audio.wav"]]; makeWave(wave);
    NSArray *extensions=@[@"MOV",@"mp4",@"m4v"], *types=@[AVFileTypeQuickTimeMovie,AVFileTypeMPEG4,AVFileTypeAppleM4V];
    NSMutableArray<NSURL *> *fixtures=[NSMutableArray new];
    for (NSUInteger i=0;i<extensions.count;i++) {
        NSURL *url=[NSURL fileURLWithPath:[temporary stringByAppendingPathComponent:[@"original" stringByAppendingPathExtension:extensions[i]]]];
        makeMovie(video,wave,url,types[i]); [fixtures addObject:url];
    }
    NSURL *bad=[NSURL fileURLWithPath:[temporary stringByAppendingPathComponent:@"bad.mov"]];
    assert([[ @"not a video" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:bad atomically:YES]);
    NSError *mainError=nil; assert(!LMVImportMovie(fixtures[0],&mainError) && mainError.code==18);
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{ @autoreleasepool {
        assert([fm createDirectoryAtPath:testRoot withIntermediateDirectories:YES attributes:nil error:nil]);
        // Preserve old file, its catalog label, and any preference data untouched.
        NSString *legacy=[testRoot stringByAppendingPathComponent:@"message.mov"];
        assert([[ @"legacy user material" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:legacy atomically:YES]);
        NSData *legacyBytes=[NSData dataWithContentsOfFile:legacy];
        NSString *preference=[testRoot stringByAppendingPathComponent:@"existing-preference.plist"];
        assert([@{@"DesktopVideo":@"user-choice.mov"} writeToFile:preference atomically:YES]); NSData *preferenceBytes=[NSData dataWithContentsOfFile:preference];
        assert(!LMVWriteMaterialNames(@{@"message.mov":@"旧名称"}));
        setExpected(bad); NSUInteger prior=registrations; assertRejected(bad); assert(registrations==prior);
        assert([[NSData dataWithContentsOfURL:bad] isEqual:expectedBytes]);
        for (NSURL *url in fixtures) {
            setExpected(url); NSUInteger beforeValidation=validations, beforeRegistration=registrations;
            NSError *error=nil; NSString *relative=LMVImportMovie(url,&error);
            if (!relative || error) NSLog(@"settings original fixture error=%@",error);
            assert(relative && !error && [relative hasPrefix:@"library/"] && [relative.pathExtension isEqual:url.pathExtension.lowercaseString]);
            assert(validations==beforeValidation+1 && registrations==beforeRegistration+1);
            NSURL *saved=[NSURL fileURLWithPath:[testRoot stringByAppendingPathComponent:relative]];
            assert([[NSData dataWithContentsOfURL:saved] isEqual:expectedBytes]);
            assert([[NSData dataWithContentsOfURL:url] isEqual:expectedBytes]);
            AVURLAsset *original=[AVURLAsset URLAssetWithURL:url options:nil], *copy=[AVURLAsset URLAssetWithURL:saved options:nil];
            AVAssetTrack *first=[original tracksWithMediaType:AVMediaTypeVideo].firstObject, *second=[copy tracksWithMediaType:AVMediaTypeVideo].firstObject;
            assert(CMTimeCompare(original.duration,copy.duration)==0 && CGSizeEqualToSize(first.naturalSize,second.naturalSize));
            assert(first.nominalFrameRate==second.nominalFrameRate && CGAffineTransformEqualToTransform(first.preferredTransform,second.preferredTransform));
            assert([copy tracksWithMediaType:AVMediaTypeAudio].count==[original tracksWithMediaType:AVMediaTypeAudio].count);
            assert([LMVReadMaterialNames()[relative] hasPrefix:@"相册原片"] && [LMVReadMaterialNames()[@"message.mov"] isEqual:@"旧名称"]);
            assert(libraryCount()==expectedFiles+1); noPending();
        }
        assert([[NSData dataWithContentsOfFile:legacy] isEqual:legacyBytes] && [[NSData dataWithContentsOfFile:preference] isEqual:preferenceBytes]);
        // Failure after publication rolls back this file while retaining previous assets/catalog.
        setExpected(fixtures[0]); failCatalog=YES; assertRejected(fixtures[0]); failCatalog=NO;
        assert([[NSData dataWithContentsOfURL:fixtures[0]] isEqual:expectedBytes]);
        NSURL *empty=[NSURL fileURLWithPath:[temporary stringByAppendingPathComponent:@"empty.mov"]]; assert([NSData.data writeToURL:empty atomically:YES]); assertRejected(empty);
        NSURL *huge=[NSURL fileURLWithPath:[temporary stringByAppendingPathComponent:@"huge.mov"]];
        int fd=open(huge.fileSystemRepresentation,O_WRONLY|O_CREAT|O_EXCL,0600); assert(fd>=0 && ftruncate(fd,(off_t)LMVMaxImportBytes+1)==0); close(fd); assertRejected(huge);
        NSURL *linked=[NSURL fileURLWithPath:[temporary stringByAppendingPathComponent:@"linked.mov"]]; assert(symlink(fixtures[0].fileSystemRepresentation,linked.fileSystemRepresentation)==0); assertRejected(linked);
        NSURL *unsupported=[NSURL fileURLWithPath:[temporary stringByAppendingPathComponent:@"renamed.avi"]]; assert([fm copyItemAtURL:fixtures[0] toURL:unsupported error:nil]); assertRejected(unsupported);
        NSString *library=[testRoot stringByAppendingPathComponent:@"library"], *backup=[testRoot stringByAppendingPathComponent:@"library-backup"];
        assert([fm moveItemAtPath:library toPath:backup error:nil]); assert(symlink(backup.fileSystemRepresentation,library.fileSystemRepresentation)==0); assertRejected(fixtures[0]);
        assert(unlink(library.fileSystemRepresentation)==0); assert([fm moveItemAtPath:backup toPath:library error:nil]);
        NSString *catalog=LMVCatalogPath(), *catalogBackup=[testRoot stringByAppendingPathComponent:@"catalog-backup"];
        assert([fm moveItemAtPath:catalog toPath:catalogBackup error:nil]); assert(symlink(catalogBackup.fileSystemRepresentation,catalog.fileSystemRepresentation)==0);
        setExpected(fixtures[0]); assertRejected(fixtures[0]);
        assert(unlink(catalog.fileSystemRepresentation)==0); assert([fm moveItemAtPath:catalogBackup toPath:catalog error:nil]);
        assert([[NSData dataWithContentsOfFile:legacy] isEqual:legacyBytes]); noPending();
    } dispatch_semaphore_signal(done); });
    assert(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,60*NSEC_PER_SEC))==0);
    assert([fm removeItemAtPath:temporary error:nil]);
    puts("PASS: actual settings importer validates real AVFoundation MOV/MP4/M4V, preserves original bytes/source/audio/fps/size/transform/duration/extension, decode-before-publish-before-catalog, rejects bad/empty/>512 MiB/links, catalog rollback and old files/names/preferences (macOS, not iOS UI)");
} return 0; }
'''
with tempfile.TemporaryDirectory() as tmp:
    source=Path(tmp)/'settings-import.m'; source.write_text(preamble+native+main)
    binary=Path(tmp)/'settings-import'
    subprocess.run(['clang','-fobjc-arc','-I',str(root),'-framework','Foundation','-framework','AVFoundation','-framework','CoreVideo','-framework','CoreMedia','-framework','CoreGraphics',str(source),'-o',str(binary)],check=True)
    subprocess.run([str(binary)],check=True,timeout=150)
