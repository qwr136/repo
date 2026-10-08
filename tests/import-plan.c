#include <assert.h>
#include <stdio.h>
#include "../LockMessageVideoPrefs/LMVEncodePlan.h"
int main(void) {
    const double durations[]={1.533,10,60,300,1800,7200};
    const unsigned long long sizes[]={50000,1024*1024,5*1024*1024,100*1024*1024,2ULL*1024*1024*1024};
    unsigned count=0;
    for (unsigned d=0; d<6; d++) for (unsigned b=0; b<5; b++) {
        long previousRate=2000000, previousWidth=4096;
        for (long attempt=0; attempt<3; attempt++) {
            LMVEncodePlan p=LMVMakeEncodePlan(3840,2160,durations[d],120,sizes[b],attempt,1.0);
            assert(p.width>=2 && p.height>=2 && p.width%2==0 && p.height%2==0);
            assert(p.width<=960 && p.height<=960 && p.fps<=30 && p.fps>0);
            assert(p.bitrate<=previousRate && p.width<=previousWidth);
            if (p.bitrate>1000) assert(p.bitrate*durations[d]/8.0 <= fmin(5.0*1024*1024,sizes[b])*0.821);
            previousRate=p.bitrate; previousWidth=p.width; count++;
        }
    }
    LMVEncodePlan portrait=LMVMakeEncodePlan(1080,1920,60,60,100*1024*1024,0,1);
    assert(portrait.height>portrait.width && portrait.fps==30);
    LMVEncodePlan lowfps=LMVMakeEncodePlan(640,480,10,12,5*1024*1024,0,1);
    assert(lowfps.fps==12 && lowfps.width<=640 && lowfps.height<=480);
    LMVEncodePlan longvideo=LMVMakeEncodePlan(3840,2160,1800,60,100*1024*1024,0,1);
    assert(longvideo.bitrate<32000 && longvideo.fps==15 && longvideo.width<=360);
    puts("PASS: 90 budget/resolution/fps plans + portrait, low-FPS and long-video cases (not AVFoundation runtime)");
    return count==90 ? 0 : 1;
}
