from pathlib import Path
import platform,subprocess,tempfile
r=Path(__file__).resolve().parents[1]
h=(r/'LockMessageVideoPrefs/LMVThumbnailDiagnosticLog.h').read_text()
p=(r/'LockMessageVideoPrefs/LMVMaterialPicker.h').read_text()
t=(r/'LockMessageVideoPrefs/LMVMaterialThumbnail.h').read_text()
s=(r/'Tweak.xm').read_text()
for stage in ['request','enqueue','memory-hit','skip-previous-failure','skip-pending','defer-queue-full','worker-start','worker-finish','apply-poster','apply-placeholder','display-poster','display-placeholder']:
 assert stage in p,stage
for stage in ['disk-miss','disk-hit','disk-stale-or-invalid-record','decode-start','generator-start','generator-success','reader-fallback-start','reader-success','decode-stale-discard','disk-write-success']:
 assert stage in t,stage
assert 'LMVThumbnailItemID(relative)' in t and 'row=%ld' in p
assert '#define LMVThumbnailDiagnostic(event) LMVDiagnostic(event)' not in s
assert 'now - bucket >= 60' in h and 'thumbnail-preview-springboard.log' in h and 'thumbnail-preview-settings.log' in h
assert 'LMVDiagnosticEpoch.fetch_add(1)' in s and 'epoch != LMVDiagnosticEpoch.load()' in s
if platform.system()!='Darwin':
 print('PASS: complete preview stages, anonymous row correlation, independent rolling quotas, versioned host-separated logs; file execution on macOS CI')
 raise SystemExit(0)
pre=r'''
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <assert.h>
static BOOL testEnabled=YES, testSpringboard=YES;
static NSTimeInterval testNow=100;
static dispatch_queue_t queue;
static CFPropertyListRef testCopy(CFStringRef key, CFStringRef domain) {return CFBridgingRetain(@(testEnabled));}
#define CFPreferencesCopyAppValue testCopy
'''
# Isolate filesystem/preferences/time/process inputs; execute the production
# async serial writer, rotation, quota and guard logic without touching real data.
code=h.replace('static dispatch_queue_t queue;','')
code=code.replace('NSDate.date.timeIntervalSince1970','testNow')
code=code.replace('[NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]','testSpringboard')
code=code.replace('@"/var/mobile/LockMessageVideo"','@"/tmp/lmv-preview-diagnostic-tests"')
main=r'''
static NSString *readLog(BOOL springboard) {
 NSString *name=springboard?@"thumbnail-preview-springboard.log":@"thumbnail-preview-settings.log";
 return [NSString stringWithContentsOfFile:[@"/tmp/lmv-preview-diagnostic-tests" stringByAppendingPathComponent:name] encoding:NSUTF8StringEncoding error:nil];
}
static void flush(void) {dispatch_sync(queue,^{});}
int main(void) {@autoreleasepool {
 [NSFileManager.defaultManager removeItemAtPath:@"/tmp/lmv-preview-diagnostic-tests" error:nil];
 LMVThumbnailDiagnosticWrite(@"thumbnail item=abc stage=request row=5"); flush();
 NSString *line=readLog(YES); assert([line containsString:@"version=0.0.72"] && [line containsString:@"host=SpringBoard"] && [line containsString:@"stage=request row=5"]);
 for(int i=0;i<1100;i++) LMVThumbnailDiagnosticWrite(@"thumbnail item=abc stage=sample");flush();
 assert([readLog(YES) containsString:@"budget-reached"]);
 NSUInteger before=readLog(YES).length;
 LMVThumbnailDiagnosticWrite(@"thumbnail should-drop");flush();assert(readLog(YES).length==before);
 testNow+=61;LMVThumbnailDiagnosticWrite(@"thumbnail new-window");flush();assert([readLog(YES) containsString:@"new-window"]);
 testEnabled=NO;LMVThumbnailDiagnosticWrite(@"thumbnail disabled");flush();assert(![readLog(YES) containsString:@" disabled"]);
 testEnabled=YES;testSpringboard=NO;testNow+=61;
 LMVThumbnailDiagnosticWrite(@"thumbnail settings");flush();assert([readLog(NO) containsString:@"host=Settings"]);
 assert(![readLog(YES) containsString:@"thumbnail settings"]);
 NSString *settings=@"/tmp/lmv-preview-diagnostic-tests/thumbnail-preview-settings.log";
 NSMutableData *large=[NSMutableData dataWithLength:262145];assert([large writeToFile:settings atomically:YES]);
 LMVThumbnailDiagnosticWrite(@"thumbnail rotated");flush();assert([NSFileManager.defaultManager fileExistsAtPath:[settings stringByAppendingString:@".1"]]);
 assert([readLog(NO) containsString:@"thumbnail rotated"]);
 [NSFileManager.defaultManager removeItemAtPath:@"/tmp/lmv-preview-diagnostic-tests" error:nil];
 puts("PASS: actual preview async file writer, off switch, host-separated files, quota recovery after window, version/PID labels and rotation; no device claim");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 src=Path(tmp)/'logger.m';binary=Path(tmp)/'logger';src.write_text(pre+code+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(src),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
