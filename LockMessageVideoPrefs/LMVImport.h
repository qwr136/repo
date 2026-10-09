#import <AVFoundation/AVFoundation.h>
#import <math.h>
#import "LMVMaterialStorage.h"
#import "LMVThumbnailDiagnosticLog.h"
#import "LMVMaterialThumbnail.h"
#import "LMVEncodePlan.h"

static const unsigned long long LMVMaxImportBytes = 5ULL * 1024ULL * 1024ULL;
static NSError *LMVImportError(NSInteger code, NSString *message, NSError *underlying) {
    NSMutableDictionary *info=[NSMutableDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey];
    if (underlying) {
        info[NSUnderlyingErrorKey]=underlying;
        info[NSLocalizedDescriptionKey]=[NSString stringWithFormat:@"%@\n%@ (%@ %ld)",message,underlying.localizedDescription,underlying.domain,(long)underlying.code];
    }
    return [NSError errorWithDomain:@"LockMessageVideo.Import" code:code userInfo:info];
}
// Called only on the Photos provider/background queue, never layout or main.
static NSError *LMVEncodeMovie(AVURLAsset *asset, AVAssetTrack *track, NSURL *destination, LMVEncodePlan plan) {
    NSError *error=nil;
    AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:asset error:&error];
    if (!reader) return error ?: LMVImportError(2,@"无法创建视频读取器",nil);
    AVAssetWriter *writer=[[AVAssetWriter alloc] initWithURL:destination fileType:AVFileTypeQuickTimeMovie error:&error];
    if (!writer) return error ?: LMVImportError(3,@"无法创建 H.264 编码器",nil);
    NSDictionary *settings=@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@(plan.width),AVVideoHeightKey:@(plan.height),AVVideoCompressionPropertiesKey:@{AVVideoAverageBitRateKey:@(plan.bitrate),AVVideoExpectedSourceFrameRateKey:@(plan.fps),AVVideoMaxKeyFrameIntervalKey:@((NSInteger)ceil(plan.fps)),AVVideoProfileLevelKey:AVVideoProfileLevelH264MainAutoLevel}};
    // Composition delivers already scaled / frame-limited buffers to the encoder.
    // Unlike dropping samples after full-rate decode/append, 4K/60+ imports do not
    // encode full resolution or every source frame. Source decode is still required.
    AVAssetReaderVideoCompositionOutput *output=[AVAssetReaderVideoCompositionOutput assetReaderVideoCompositionOutputWithVideoTracks:@[track] videoSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)}];
    CGRect oriented=CGRectApplyAffineTransform((CGRect){CGPointZero,track.naturalSize},track.preferredTransform);
    CGAffineTransform transform=track.preferredTransform;
    transform=CGAffineTransformConcat(transform,CGAffineTransformMakeTranslation(-CGRectGetMinX(oriented),-CGRectGetMinY(oriented)));
    transform=CGAffineTransformConcat(transform,CGAffineTransformMakeScale(plan.width/CGRectGetWidth(oriented),plan.height/CGRectGetHeight(oriented)));
    AVMutableVideoCompositionLayerInstruction *layer=[AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:track];
    [layer setTransform:transform atTime:kCMTimeZero];
    AVMutableVideoCompositionInstruction *instruction=[AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange=CMTimeRangeMake(kCMTimeZero,asset.duration); instruction.layerInstructions=@[layer];
    AVMutableVideoComposition *composition=[AVMutableVideoComposition videoComposition];
    composition.renderSize=CGSizeMake(plan.width,plan.height);
    composition.frameDuration=CMTimeMake(1000,(int32_t)llround(plan.fps*1000));
    composition.instructions=@[instruction]; output.videoComposition=composition;
    output.alwaysCopiesSampleData=NO;
    AVAssetWriterInput *input=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:settings];
    input.expectsMediaDataInRealTime=NO; // Orientation is baked by the composition.
    if (![reader canAddOutput:output] || ![writer canAddInput:input]) return LMVImportError(5,@"视频格式无法重新编码",nil);
    [reader addOutput:output]; [writer addInput:input]; // NO audio input/output.
    if (![writer startWriting]) return writer.error ?: LMVImportError(6,@"无法开始编码",nil);
    if (![reader startReading]) { [writer cancelWriting]; return reader.error ?: LMVImportError(7,@"无法开始读取视频",nil); }
    CMTime start=track.timeRange.start;
    [writer startSessionAtSourceTime:CMTIME_IS_NUMERIC(start)?start:kCMTimeZero];
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    dispatch_queue_t queue=dispatch_queue_create("com.minis.lockmessagevideo.encode",DISPATCH_QUEUE_SERIAL);
    __block BOOL ended=NO; __block NSError *encodeError=nil; __block NSUInteger samples=0;
    [input requestMediaDataWhenReadyOnQueue:queue usingBlock:^{
        if (ended) return;
        while (input.readyForMoreMediaData && !ended) {
            CMSampleBufferRef sample=[output copyNextSampleBuffer];
            if (sample) {
                BOOL ok=[input appendSampleBuffer:sample]; CFRelease(sample);
                if (ok) { samples++; continue; }
                encodeError=writer.error ?: LMVImportError(8,@"H.264 编码写入失败",nil);
                ended=YES; [reader cancelReading]; [writer cancelWriting]; dispatch_semaphore_signal(done);
            } else {
                ended=YES;
                if (reader.status!=AVAssetReaderStatusCompleted || !samples) {
                    encodeError=reader.error ?: LMVImportError(9,@"视频读取未完成或没有解码帧",nil);
                    [writer cancelWriting]; dispatch_semaphore_signal(done);
                } else {
                    [input markAsFinished];
                    [writer finishWritingWithCompletionHandler:^{ dispatch_semaphore_signal(done); }];
                }
            }
        }
    }];
    dispatch_semaphore_wait(done,DISPATCH_TIME_FOREVER);
    if (encodeError) return encodeError;
    if (writer.status!=AVAssetWriterStatusCompleted) return writer.error ?: LMVImportError(10,@"编码未完成",nil);
    return nil;
}
static NSError *LMVValidateMovie(NSURL *url, double originalDuration) {
    NSError *error=nil;
    unsigned long long bytes=[NSFileManager.defaultManager attributesOfItemAtPath:url.path error:&error].fileSize;
    if (error) return error;
    if (!bytes || bytes>LMVMaxImportBytes) return LMVImportError(11,@"重新编码结果为空或仍超过 5 MiB",nil);
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:url options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
    double duration=CMTimeGetSeconds(asset.duration);
    AVAssetTrack *track=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    if (!asset.playable || !track || !isfinite(duration) || duration<=0 || fabs(duration-originalDuration)>MAX(0.25,originalDuration*0.02) || [asset tracksWithMediaType:AVMediaTypeAudio].count) return LMVImportError(12,@"结果不可播放、时长不完整或仍包含音轨",nil);
    AVAssetReader *reader=[[AVAssetReader alloc] initWithAsset:asset error:&error];
    AVAssetReaderTrackOutput *output=[AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA)}];
    if (!reader || ![reader canAddOutput:output]) return error ?: LMVImportError(13,@"无法验证视频解码",nil);
    [reader addOutput:output];
    if (![reader startReading]) return reader.error ?: LMVImportError(14,@"结果解码启动失败",nil);
    CMSampleBufferRef sample=[output copyNextSampleBuffer];
    BOOL valid=sample && CMSampleBufferGetImageBuffer(sample)!=NULL;
    if (sample) CFRelease(sample);
    error=reader.error; [reader cancelReading];
    return valid ? nil : (error ?: LMVImportError(15,@"结果没有可解码画面",nil));
}
static NSError *LMVCompressMovie(NSURL *source, NSURL *destination) {
    NSFileManager *fm=NSFileManager.defaultManager; NSError *error=nil;
    unsigned long long inputBytes=[fm attributesOfItemAtPath:source.path error:&error].fileSize;
    if (error) return error;
    AVURLAsset *asset=[AVURLAsset URLAssetWithURL:source options:@{AVURLAssetPreferPreciseDurationAndTimingKey:@YES}];
    AVAssetTrack *track=[asset tracksWithMediaType:AVMediaTypeVideo].firstObject;
    double duration=CMTimeGetSeconds(asset.duration);
    if (!track || !isfinite(duration) || duration<=0) return LMVImportError(1,@"原视频没有有效视频轨道或时长",nil);
    CGRect oriented=CGRectApplyAffineTransform((CGRect){CGPointZero,track.naturalSize},track.preferredTransform);
    double width=CGRectGetWidth(oriented), height=CGRectGetHeight(oriented);
    if (!isfinite(width) || !isfinite(height) || width<2 || height<2) return LMVImportError(4,@"视频尺寸无效",nil);
    double feedbackScale=1.0;
    for (NSInteger attempt=0;attempt<3;attempt++) {
        [fm removeItemAtURL:destination error:nil];
        LMVEncodePlan plan=LMVMakeEncodePlan(width,height,duration,track.nominalFrameRate,inputBytes,attempt,feedbackScale);
        error=LMVEncodeMovie(asset,track,destination,plan);
        if (!error) error=LMVValidateMovie(destination,duration);
        unsigned long long bytes=[fm attributesOfItemAtPath:destination.path error:nil].fileSize;
        if (!error && bytes>=inputBytes) error=LMVImportError(16,@"重新编码未能减小文件；未加入素材库，临时原素材将清理",nil);
        if (!error) return nil;
        // Only size failures can benefit from another encode. Decode/I/O/codec
        // or validation errors are terminal; never repeat the same doomed export.
        BOOL sizeFailure=[error.domain isEqualToString:@"LockMessageVideo.Import"] && (error.code==11 || error.code==16) && bytes>0;
        if (!sizeFailure) break;
        double target=MIN((double)LMVMaxImportBytes,(double)inputBytes)*0.82;
        feedbackScale=MIN(feedbackScale,MIN(1.0,target/(double)bytes));
    }
    [fm removeItemAtURL:destination error:nil];
    return error;
}
// Copies Photos' temporary representation synchronously before its callback ends.
// Library receives ONLY a validated, smaller, silent H.264 variant, via final move.
static NSString *LMVImportMovieOnMaterialQueue(NSURL *source, NSError **outError) {
    NSFileManager *fm=NSFileManager.defaultManager; NSError *error=nil;
    NSString *base=@"/var/mobile/LockMessageVideo";
    NSString *library=[base stringByAppendingPathComponent:@"library"];
    NSString *stem=NSUUID.UUID.UUIDString;
    NSString *ext=source.pathExtension.lowercaseString;
    if (![@[@"mov",@"mp4",@"m4v"] containsObject:ext]) ext=@"mov";
    // Photos' representation is temporary. Own one private copy only for the
    // encode transaction; never place this uncompressed copy in the library.
    NSURL *ownedSource=[NSURL fileURLWithPath:[base stringByAppendingPathComponent:[NSString stringWithFormat:@".import-source-%@.%@",stem,ext]]];
    if (![fm copyItemAtURL:source toURL:ownedSource error:&error]) {
        if (outError) *outError=error;
        return nil;
    }
    [fm createDirectoryAtPath:library withIntermediateDirectories:YES attributes:nil error:&error];
    // Work outside library: incomplete output can never appear in material menus.
    NSURL *temporary=[NSURL fileURLWithPath:[base stringByAppendingPathComponent:[NSString stringWithFormat:@".encode-%@.mov",stem]]];
    NSString *name=[stem stringByAppendingPathExtension:@"mov"];
    if (!error) error=LMVCompressMovie(ownedSource,temporary);
    if (!error) [fm moveItemAtURL:temporary toURL:[NSURL fileURLWithPath:[library stringByAppendingPathComponent:name]] error:&error];
    // Both success and failure own and remove the temporary uncompressed copy.
    [fm removeItemAtURL:ownedSource error:nil];
    if (error) {
        [fm removeItemAtURL:temporary error:nil];
        if (outError) *outError=LMVImportError(17,@"导入未完成；临时原素材已清理，未加入素材库",error);
        return nil;
    }
    NSString *relative = [@"library" stringByAppendingPathComponent:name];
    NSString *revision = LMVThumbnailRevision(relative);
    if (revision) {
        UIImage *poster = LMVDecodeThumbnail(relative);
        if (poster) {
            NSError *thumbnailError = LMVWriteThumbnail(relative, revision, poster);
            if (thumbnailError) LMVThumbnailLog(@"import-sidecar-write", relative, thumbnailError);
        } else {
            LMVThumbnailLog(@"import-sidecar-decode", relative, nil);
        }
    }
    return relative;
}

// NSItemProvider's file URL expires when its callback returns. Keep that callback
// alive while the serial background transaction runs; NEVER wait on the UI thread.
static NSString *LMVImportMovie(NSURL *source, NSError **outError) {
    if (NSThread.isMainThread) {
        if (outError) *outError=LMVImportError(18,@"视频导入必须在相册后台回调中执行",nil);
        return nil;
    }
    __block NSString *relative=nil;
    __block NSError *error=nil;
    dispatch_sync(LMVMaterialQueue(), ^{
        @autoreleasepool { relative=LMVImportMovieOnMaterialQueue(source,&error); }
    });
    if (outError) *outError=error;
    return relative;
}
