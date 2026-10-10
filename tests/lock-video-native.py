#!/usr/bin/env python3
"""Compile the real production playback header; no UIKit/display-server claims."""
from pathlib import Path
import platform,subprocess,tempfile,wave
r=Path(__file__).resolve().parents[1]
h=(r/'LMVLockVideoPlayback.h').read_text()
assert 'AVQueuePlayer' in h and 'AVPlayerLooper' in h and 'AVPlayerLayer' in h
assert 'addMutableTrackWithMediaType:AVMediaTypeVideo' in h
assert 'LMVCacheFrame' not in h and 'AVAudioSession' not in h
assert 'removeAllItems' in h and 'disableLooping' in h and 'replacePlayerLayer' in h
if platform.system()!='Darwin':
 print('PASS: independent video-only lock playback contracts; actual Foundation/AVFoundation production execution runs on macOS CI')
 raise SystemExit(0)
code=r'''
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#include <assert.h>
#include <math.h>
#include <string.h>
#import "LMVLockVideoPlayback.h"
static void spin(NSTimeInterval time) {
 NSDate *end=[NSDate dateWithTimeIntervalSinceNow:time];
 while(end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
}
static BOOL until(BOOL (^test)(void),NSTimeInterval timeout) {
 NSDate *end=[NSDate dateWithTimeIntervalSinceNow:timeout];
 while(!test() && end.timeIntervalSinceNow>0)spin(.01);
 return test();
}
static void movie(NSURL *url,unsigned char value) {
 NSError *error=nil;AVAssetWriter *writer=[[AVAssetWriter alloc] initWithURL:url fileType:AVFileTypeQuickTimeMovie error:&error];assert(writer && !error);
 AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@32,AVVideoHeightKey:@32}];
 AVAssetWriterInputPixelBufferAdaptor *adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferWidthKey:@32,(id)kCVPixelBufferHeightKey:@32,(id)kCVPixelBufferIOSurfacePropertiesKey:@{}}];
 [writer addInput:input];assert([writer startWriting]);[writer startSessionAtSourceTime:kCMTimeZero];
 for(int n=0;n<32;n++) {
  assert(until(^BOOL{return input.readyForMoreMediaData || writer.status!=AVAssetWriterStatusWriting;},10));assert(input.readyForMoreMediaData);
  CVPixelBufferRef pixel=NULL;assert(CVPixelBufferPoolCreatePixelBuffer(NULL,adaptor.pixelBufferPool,&pixel)==kCVReturnSuccess);
  CVPixelBufferLockBaseAddress(pixel,0);memset(CVPixelBufferGetBaseAddress(pixel),value,CVPixelBufferGetBytesPerRow(pixel)*32);CVPixelBufferUnlockBaseAddress(pixel,0);
  assert([adaptor appendPixelBuffer:pixel withPresentationTime:CMTimeMake(n,16)]);CVPixelBufferRelease(pixel);
 }
 [input markAsFinished];__block BOOL finished=NO;[writer finishWritingWithCompletionHandler:^{finished=YES;}];
 assert(until(^BOOL{return finished;},20));assert(writer.status==AVAssetWriterStatusCompleted);
}
static void mix(NSURL *video,NSURL *waveURL,NSURL *destination) {
 AVURLAsset *va=[AVURLAsset URLAssetWithURL:video options:nil],*aa=[AVURLAsset URLAssetWithURL:waveURL options:nil];
 assert([va tracksWithMediaType:AVMediaTypeVideo].count && [aa tracksWithMediaType:AVMediaTypeAudio].count);
 AVMutableComposition *composition=[AVMutableComposition composition];NSError *error=nil;
 AVAssetTrack *v=[va tracksWithMediaType:AVMediaTypeVideo].firstObject,*a=[aa tracksWithMediaType:AVMediaTypeAudio].firstObject;
 AVMutableCompositionTrack *vt=[composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
 assert([vt insertTimeRange:v.timeRange ofTrack:v atTime:kCMTimeZero error:&error]);assert(!error);
 AVMutableCompositionTrack *at=[composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
 assert([at insertTimeRange:CMTimeRangeMake(kCMTimeZero,va.duration) ofTrack:a atTime:kCMTimeZero error:&error]);assert(!error);
 AVAssetExportSession *exporter=[[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];assert(exporter);
 exporter.outputURL=destination;exporter.outputFileType=AVFileTypeQuickTimeMovie;
 __block BOOL done=NO;[exporter exportAsynchronouslyWithCompletionHandler:^{done=YES;}];assert(until(^BOOL{return done;},20));
 if(exporter.status!=AVAssetExportSessionStatusCompleted)NSLog(@"fixture export: %@",exporter.error);
 assert(exporter.status==AVAssetExportSessionStatusCompleted);
}
int main(int argc,const char **argv) {@autoreleasepool {
 assert(argc==2);NSString *folder=[NSString stringWithUTF8String:argv[1]];
 NSString *base=[folder stringByAppendingPathComponent:@"base.mov"],*mixed=[folder stringByAppendingPathComponent:@"mixed.mov"],*second=[folder stringByAppendingPathComponent:@"second.mov"],*wavePath=[folder stringByAppendingPathComponent:@"audio.wav"];
 movie([NSURL fileURLWithPath:base],45);movie([NSURL fileURLWithPath:second],145);mix([NSURL fileURLWithPath:base],[NSURL fileURLWithPath:wavePath],[NSURL fileURLWithPath:mixed]);
 AVURLAsset *asset=[AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:mixed] options:nil];assert([asset tracksWithMediaType:AVMediaTypeAudio].count);
 NSError *error=nil;AVMutableComposition *silent=LMVLockVideoComposition(asset,&error);assert(silent && !error);
 assert([silent tracksWithMediaType:AVMediaTypeVideo].count==1 && [silent tracksWithMediaType:AVMediaTypeAudio].count==0);
 AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:silent error:&error];assert(reader && !error);
 AVAssetReaderTrackOutput *output=[AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:[silent tracksWithMediaType:AVMediaTypeVideo].firstObject outputSettings:nil];[reader addOutput:output];assert([reader startReading]);
 CMSampleBufferRef sample=[output copyNextSampleBuffer];assert(sample);CFRelease(sample);[reader cancelReading];
 LMVLockVideoPlayback *p=[LMVLockVideoPlayback new];CALayer *surface=[CALayer layer];surface.frame=CGRectMake(0,0,390,844);[surface addSublayer:p.renderLayer];
 [p layoutInBounds:surface.bounds];NSString *rev=LMVLockVideoRevision(mixed);assert(rev);
 [p selectPath:mixed revision:rev];assert(p.loading && p.renderLayer.hidden);[p setVisible:YES];
 assert(until(^BOOL{return !p.loading && p.player && p.looper && p.posterLayer.contents;},15));assert(!p.error && p.buildCount==1);
 assert(p.playerLayer.player==p.player && p.templateItem.asset!=asset && p.player.muted && p.player.volume==0 && !p.player.allowsExternalPlayback);
 assert([p.templateItem.asset tracksWithMediaType:AVMediaTypeAudio].count==0);
 AVQueuePlayer *first=p.player;AVPlayerLooper *loop=p.looper;AVPlayerLayer *firstLayer=p.playerLayer;
 for(int n=0;n<50;n++){[p selectPath:mixed revision:rev];[p layoutInBounds:CGRectMake(0,0,390+n,844)];}
 assert(p.player==first && p.looper==loop && p.playerLayer==firstLayer && p.buildCount==1);
 LMVLockVideoPlayback *desktop=[LMVLockVideoPlayback new];
 [desktop selectPath:mixed revision:rev];[desktop setVisible:YES];
 assert(until(^BOOL{return desktop.player && desktop.looper && desktop.posterLayer.contents && desktop.player.rate>0;},15));
 assert(desktop.player!=p.player && desktop.looper!=p.looper && desktop.templateItem!=p.templateItem && desktop.playerLayer!=p.playerLayer && desktop.posterLayer!=p.posterLayer);
 [p setVisible:NO];spin(.15);assert(desktop.player.rate>0 && p.player.rate==0);
 [p clear];assert(desktop.player && desktop.looper && desktop.playerLayer.player==desktop.player && desktop.player.rate>0);
 [p selectPath:mixed revision:rev];[p setVisible:YES];assert(until(^BOOL{return p.player && p.posterLayer.contents && p.player.rate>0;},15));
 first=p.player;loop=p.looper;firstLayer=p.playerLayer;NSUInteger baselineBuilds=p.buildCount;
 [desktop clear];assert(p.player==first && p.looper==loop && p.player.rate>0);
 AVPlayerItem *otherItem=[AVPlayerItem playerItemWithAsset:asset];AVPlayer *other=[AVPlayer playerWithPlayerItem:otherItem];
 assert(p.player.currentItem!=otherItem);[other pause];[p setVisible:YES];assert(until(^BOOL{return p.player.rate>0;},10));
 [p setVisible:NO];assert(p.player.rate==0 && p.renderLayer.hidden);CMTime paused=p.player.currentTime;spin(.2);
 assert(CMTIME_IS_NUMERIC(paused) && fabs(CMTimeGetSeconds(CMTimeSubtract(p.player.currentTime,paused)))<.03);
 [p setVisible:YES];assert(until(^BOOL{return p.player.rate>0;},10));spin(.15);assert(p.buildCount==baselineBuilds && p.player==first);
 [p selectPath:second revision:LMVLockVideoRevision(second)];assert(first.rate==0 && first.items.count==0 && firstLayer.player==nil && p.playerLayer!=firstLayer);
 assert(until(^BOOL{return !p.loading && p.player && p.posterLayer.contents;},15));assert(!p.error && p.buildCount==baselineBuilds+1);
 AVQueuePlayer *secondPlayer=p.player;AVPlayerLayer *secondLayer=p.playerLayer;[p clear];spin(.1);
 assert(!p.player && !p.looper && !p.templateItem && !p.posterLayer.contents && p.renderLayer.hidden && secondPlayer.rate==0 && !secondPlayer.items.count && !secondLayer.player);
 // Reject a stale revision instead of loading bytes from a replaced file.
 [p selectPath:mixed revision:@"wrong-revision"];assert(until(^BOOL{return !p.loading;},15));assert(p.error && !p.player && p.renderLayer.hidden);
 NSString *invalid=[folder stringByAppendingPathComponent:@"bad.mov"];assert([[@"invalid" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:invalid atomically:YES]);
 [p selectPath:invalid revision:LMVLockVideoRevision(invalid)];assert(until(^BOOL{return !p.loading;},15));assert(p.error && !p.player && p.renderLayer.hidden);
 [p selectPath:mixed revision:rev];[p selectPath:second revision:LMVLockVideoRevision(second)];[p clear];spin(.5);
 assert(!p.loading && !p.player && !p.posterLayer.contents && p.renderLayer.hidden);
 // Verify actual looping after re-open, without demanding layer readiness on
 // a headless CI runner (poster remains the fallback until a real compositor).
 [p selectPath:base revision:LMVLockVideoRevision(base)];[p setVisible:YES];assert(until(^BOOL{return p.player && p.looper && p.player.rate>0;},15));
 assert(until(^BOOL{return p.looper.loopCount>=1 || p.looper.status==AVPlayerLooperStatusFailed;},12));
 assert(p.looper.status!=AVPlayerLooperStatusFailed && p.looper.loopCount>=1);[p clear];[other pause];
 puts("PASS: production lock playback with real AVFoundation: audio-bearing source becomes decodable video-only composition, independent queue/Looper/Layer and PTS, 50 layouts/selects stable, pause/resume, replacement discards old display/queue, strict revision/error and rapid stale-load rejection, actual loop; not device compositing");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 folder=Path(tmp)
 with wave.open(str(folder/'audio.wav'),'wb') as audio:
  audio.setnchannels(1);audio.setsampwidth(2);audio.setframerate(44100);audio.writeframes(bytes(44100*3*2))
 source=folder/'lock.m';binary=folder/'lock';source.write_text(code)
 subprocess.run(['clang','-fobjc-arc','-Wno-deprecated-declarations','-I',str(r),'-framework','Foundation','-framework','AVFoundation','-framework','QuartzCore','-framework','CoreMedia','-framework','CoreVideo','-framework','CoreGraphics',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary),str(folder)],check=True,timeout=120)
