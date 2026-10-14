#!/usr/bin/env python3
"""Real AVFoundation audio-only channels; LMVTestAudioSession policy double on macOS.
Cannot prove iOS external music mixing or device compositing."""
import platform,subprocess,tempfile,wave,struct,math
from pathlib import Path
r=Path(__file__).resolve().parents[1];h=(r/'LMVMediaAudio.h').read_text();s=(r/'Tweak.xm').read_text()
assert 'AVAudioSessionCategoryAmbient' in h and 'AVAudioSessionCategoryOptionMixWithOthers' in h
assert 'setActive:NO' not in h and 'DuckOthers' not in h and 'AVMediaTypeAudio' in h
assert 'if(!visible){c.visible=NO;[c.player pause];return;}' in h
assert 'generation!=epoch' in h and 'c.enabled && c.volume>0' in h
assert 'LMVAudioConsume(@"ControlCenterDark"' in s and 'LMVAudioConsume(@"ControlCenterLight"' in s
assert 'LMVAudioAnyEnabled() && !LMVAudioTimer' in s and 'LMVAudioPauseAll();' in s
if platform.system()!='Darwin':
 print('PASS audio-only/default-off/visibility/pause/mix source contracts; SKIP AVFoundation runtime requires macOS');raise SystemExit(0)
pre=r'''
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#include <assert.h>
static CFStringRef const kLMVPrefsID=CFSTR("test");
static NSMutableDictionary *prefs;
static CFPropertyListRef testCopy(CFStringRef key,CFStringRef domain){return CFBridgingRetain(prefs[(__bridge NSString *)key]);}
#define CFPreferencesCopyAppValue testCopy
static NSString *const LMVTestAudioSessionCategoryAmbient=@"Ambient";
static const NSUInteger LMVTestAudioSessionCategoryOptionMixWithOthers=1;
static NSUInteger categoryWrites,activations;
@interface LMVTestAudioSession:NSObject
+ (instancetype)sharedInstance;
- (BOOL)setCategory:(NSString *)category withOptions:(NSUInteger)options error:(NSError **)error;
- (BOOL)setActive:(BOOL)value error:(NSError **)error;
@end
@implementation LMVTestAudioSession
+ (instancetype)sharedInstance{static id s;static dispatch_once_t once;dispatch_once(&once,^{s=[self new];});return s;}
- (BOOL)setCategory:(NSString *)c withOptions:(NSUInteger)o error:(NSError **)e{assert([c isEqual:@"Ambient"] && o==1);categoryWrites++;return YES;}
- (BOOL)setActive:(BOOL)v error:(NSError **)e{assert(v);activations++;return YES;}
@end
static BOOL waitAudio(BOOL (^f)(void),double seconds){NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];while(!f() && end.timeIntervalSinceNow>0)[NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];return f();}
'''
main=r'''
int main(int argc,const char **argv){@autoreleasepool{
 assert(argc==2);NSString *path=[NSString stringWithUTF8String:argv[1]];prefs=[NSMutableDictionary new];LMVAudioReload();
 assert(LMVAudioChannels.count==8 && !LMVAudioAnyEnabled());
 LMVAudioConsume(@"Message",path,@"r",YES,kCMTimeZero);assert(categoryWrites==0 && activations==0);
 for(NSString *target in LMVAudioTargets()){prefs[[target stringByAppendingString:@"SoundEnabled"]]=@YES;prefs[[target stringByAppendingString:@"Volume"]]=@.3;}
 LMVAudioReload();assert(LMVAudioAnyEnabled());
 for(NSString *target in LMVAudioTargets())LMVAudioConsume(target,path,@"r",YES,kCMTimeZero);
 assert(waitAudio(^BOOL{for(LMVAudioChannel *c in LMVAudioChannels.allValues)if(!c.player || c.player.rate==0)return NO;return YES;},15));
 assert(categoryWrites==1 && activations==1);
 for(NSString *target in LMVAudioTargets()) {
  LMVAudioChannel *c=LMVAudioChannels[target];AVQueuePlayer *p=c.player;
  assert(fabs(p.volume-.3)<.00001 && [p.currentItem.asset tracksWithMediaType:AVMediaTypeAudio].count>0 && [p.currentItem.asset tracksWithMediaType:AVMediaTypeVideo].count==0);
  for(int i=0;i<100;i++)LMVAudioConsume(target,path,@"r",YES,kCMTimeZero);assert(c.player==p);
  LMVAudioConsume(target,path,@"r",NO,kCMTimeZero);assert(p.rate==0 && !c.visible);
  LMVAudioConsume(target,path,@"r",YES,kCMTimeZero);assert(c.player==p && p.rate>0);
 }
 LMVAudioPauseAll();for(LMVAudioChannel *c in LMVAudioChannels.allValues)assert(c.player.rate==0);
 // Hidden while asynchronous asset load finishes must not emit sound.
 LMVAudioChannel *c=LMVAudioChannels[@"Message"];[c clear];LMVAudioConsume(@"Message",path,@"r2",YES,kCMTimeZero);LMVAudioConsume(@"Message",path,@"r2",NO,kCMTimeZero);
 assert(waitAudio(^BOOL{return !c.loading;},10));assert(c.player.rate==0);
 prefs[@"MessageSoundEnabled"]=@NO;LMVAudioReload();assert(!c.player && !c.loading);
 prefs[@"OptionsVolume"]=@(NAN);LMVAudioReload();assert(fabs(LMVAudioChannels[@"Options"].volume-.5)<.00001);
 for(NSString *target in LMVAudioTargets())prefs[[target stringByAppendingString:@"SoundEnabled"]]=@NO;LMVAudioReload();assert(!LMVAudioAnyEnabled());
 puts("PASS real AVFoundation eight independent audio-only chains,OFF no session,ambient MixWithOthers activation policy,finite volume,same source stable,visible resume,hidden/pending/disable pauses; macOS session double NOT external iOS music test");
}return 0;}
'''
with tempfile.TemporaryDirectory() as d:
 d=Path(d);src=d/'audio.m';out=d/'audio';wav=d/'tone.wav'
 with wave.open(str(wav),'w') as f:
  f.setnchannels(1);f.setsampwidth(2);f.setframerate(22050)
  f.writeframes(b''.join(struct.pack('<h',int(2000*math.sin(i*2*math.pi*440/22050))) for i in range(44100)))
 src.write_text(pre+h.replace('#pragma once','').replace('AVAudioSession','LMVTestAudioSession')+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','AVFoundation','-framework','QuartzCore','-framework','CoreMedia',str(src),'-o',str(out)],check=True)
 subprocess.run([str(out),str(wav)],check=True,timeout=45)
