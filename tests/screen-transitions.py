#!/usr/bin/env python3
"""Execute production queued screen/resign handlers with controlled state, not UIKit."""
import platform, subprocess, tempfile
from pathlib import Path
r=Path(__file__).resolve().parents[1];s=(r/'Tweak.xm').read_text()
def function(signature):
 start=s.index(signature+' {');depth=0
 for pos in range(start+len(signature),len(s)):
  if s[pos]=='{':depth+=1
  elif s[pos]=='}':
   depth-=1
   if not depth:return s[start:pos+1]
 raise AssertionError(signature)
screen=function('static void LMVScreenNotification(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo)')
start=s.index('[NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification')
resign=s[start:s.index('        %init;',start)]
block=resign[resign.index('dispatch_async'):resign.index('\n        }];')].strip()
assert screen.index('dispatch_async')<screen.index('notify_get_state')
assert 'LMVDesktopVideoScreenChanged()' in screen
assert 'if (!LMVPlaybackAllowed()) LMVSuspend();' in block and 'LMVSyncDisplayLink();LMVRequestSafeUpdate();' in block
assert 'LMVReleaseAllPlayers();' not in block
if platform.system()!='Darwin':
 print('PASS screen/resign event source contracts; SKIP actual queued handler execution requires Foundation')
 raise SystemExit(0)
pre=r'''
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#include <assert.h>
static NSMutableArray *queued;
static void enqueue(dispatch_queue_t queue,dispatch_block_t block){[queued addObject:[block copy]];}
#define dispatch_async enqueue
static void turn(void){NSArray *now=queued.copy;[queued removeAllObjects];for(dispatch_block_t b in now)b();}
static const int NOTIFY_STATUS_OK=0;
static int LMVBlankToken=1;
static uint64_t testBlank;
static int notify_get_state(int token,uint64_t *out){*out=testBlank;return 0;}
static BOOL LMVInitialized=YES,LMVLaunchReady=YES;
static NSUInteger blanked,suspended,unlocked,prepared,requests,messageReconciled,menuPaused,panelPaused,atPanelPaused;
static BOOL LMVPlaybackAllowed(void){return !testBlank;}
static void LMVDesktopVideoScreenBlank(void){blanked++;}
static void LMVDesktopVideoScreenChanged(void){unlocked++;}
static void LMVSuspend(void){suspended++;}
static void LMVPrepareAssets(void){prepared++;}
static void LMVRequestSafeUpdate(void){requests++;}
static void LMVSyncDisplayLink(void){messageReconciled++;}
static void LMVHomeMenuVideoSuspend(void){menuPaused++;}
static void LMVSquidPanelVideoSuspend(void){panelPaused++;}
static void LMVATPanelVideoSuspend(void){atPanelPaused++;}
'''
main=r'''
int main(void){@autoreleasepool{
 queued=[NSMutableArray new];
 testBlank=1;LMVScreenNotification(NULL,NULL,NULL,NULL,NULL);testBlank=0;turn();
 assert(!blanked && !suspended && unlocked==1 && prepared==1 && requests==1);
 testBlank=0;LMVScreenNotification(NULL,NULL,NULL,NULL,NULL);testBlank=1;turn();
 assert(blanked==1 && suspended==1 && unlocked==1);
 testBlank=0;resign();turn();assert(suspended==1 && messageReconciled==1 && menuPaused==1 && panelPaused==1 && atPanelPaused==1);
 testBlank=1;resign();turn();assert(suspended==2 && messageReconciled==1);
 LMVLaunchReady=NO;LMVScreenNotification(NULL,NULL,NULL,NULL,NULL);turn();assert(suspended==2);
 puts("PASS production screen/resign handlers: obsolete queued blank cannot cover newly unlocked Home, latest actual blank suspends, exposed CC not suspended solely by SpringBoard inactive; no UIKit device claim");
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 src=Path(tmp)/'screen.m';binary=Path(tmp)/'screen';src.write_text(pre+screen+'\nstatic void resign(void){'+block+'}\n'+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation',str(src),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
