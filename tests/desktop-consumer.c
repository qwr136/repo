#include <assert.h>
#include <stdio.h>
#include "../LMVConsumerPolicy.h"
static LMVDesktopDecision decide(LMVForeground f, bool covered, bool menu) {
    return LMVDesktopDecide(1,1,1,1,1,1,0,f,covered,menu);
}
int main(void) {
    for (unsigned bits=0; bits<512; ++bits) for (int f=0;f<4;f++) {
        bool host=bits&1, window=bits&2, attached=bits&4, visible=bits&8, screen=bits&16;
        bool known=bits&32, locked=bits&64, covered=bits&128, menu=bits&256;
        LMVDesktopDecision d=LMVDesktopDecide(host,window,attached,visible,screen,known,locked,f,covered,menu);
        assert(d.retainFrame == (host && window && attached && screen && known && !locked));
        assert(d.decode == (d.retainFrame && visible && f==LMVForegroundHome && !covered && !menu));
        if (!screen || locked || !attached || !host || !window || !known) assert(!d.retainFrame && !d.decode);
        if (f!=LMVForegroundHome || covered || menu) assert(!d.decode);
    }
    LMVDesktopRect home={0,0,390,844}, partial={0,-700,390,844}, full={0,0,390,844};
    assert(!LMVDesktopFullyCovered(full,partial,home,1)); // model at destination, animation not finished
    assert(!LMVDesktopFullyCovered(partial,full,home,1)); // dismissal already started
    assert(!LMVDesktopFullyCovered(full,full,home,0));
    assert(LMVDesktopFullyCovered(full,full,home,1));
    assert(!LMVDesktopFullyCovered((LMVDesktopRect){500,0,390,844},full,home,1));
    assert(!LMVDesktopFullyCovered((LMVDesktopRect){0,0,0,0},full,home,1));
    assert(decide(LMVForegroundHome,0,0).decode); // partial NC
    assert(decide(LMVForegroundHome,1,0).retainFrame && !decide(LMVForegroundHome,1,0).decode);
    assert(decide(LMVForegroundUnknown,0,0).retainFrame && !decide(LMVForegroundUnknown,0,0).decode);
    assert(decide(LMVForegroundHome,0,1).retainFrame && !decide(LMVForegroundHome,0,1).decode);
    assert(decide(LMVForegroundApp,0,0).retainFrame && !decide(LMVForegroundApp,0,0).decode);
    LMVWindowRole dock=LMVDesktopWindowRole("SBFloatingDockWindow");
    assert(dock==LMVWindowFloatingDock);
    assert(LMVDesktopResolveForeground(0,0,0,dock,0)==LMVForegroundOverlay);
    assert(LMVDesktopResolveForeground(1,0,0,dock,1)==LMVForegroundApp);
    assert(LMVDesktopResolveForeground(1,1,0,dock,0)==LMVForegroundHome);
    assert(LMVDesktopResolveForeground(0,0,0,LMVWindowOther,1)==LMVForegroundOverlay);
    assert(LMVDesktopResolveForeground(0,0,1,LMVWindowHome,0)==LMVForegroundHome);
    assert(LMVDesktopWindowRole("ThirdPartyWindow")==LMVWindowOther);
    assert(LMVDesktopWindowRole("SBFloatingDockWindowFake")==LMVWindowOther);
    assert(LMVDesktopResolveForeground(0,0,0,LMVWindowOther,0)==LMVForegroundUnknown);
    assert(!LMVDesktopShouldAttach(1) && LMVDesktopShouldAttach(0));
    LMVDesktopGateClock clock={0,0};
    LMVDesktopActivity a=LMVDesktopGate(decide(LMVForegroundHome,0,0),LMVForegroundHome,1,1,0,0,0,1,291848.458,&clock);
    assert(a.draw && a.decode && !a.releaseSource);
    double releaseTimes[]={291848.980,291851.604,291854.019};
    double reloadTimes[]={291850.057,291852.383,291854.905};
    for(unsigned i=0;i<3;i++) {
        a=LMVDesktopGate(decide(LMVForegroundUnknown,0,0),LMVForegroundUnknown,1,1,0,0,0,1,releaseTimes[i],&clock);
        assert(a.draw && a.decode && !a.releaseSource); // tiny ambiguity debounced
        a=LMVDesktopGate(decide(LMVForegroundUnknown,0,0),LMVForegroundUnknown,1,1,0,0,0,1,releaseTimes[i]+.16,&clock);
        assert(a.decode && !a.releaseSource); // unknown home-key does not pause indefinitely
        a=LMVDesktopGate(decide(LMVForegroundHome,0,0),LMVForegroundHome,1,1,0,0,0,1,reloadTimes[i],&clock);
        assert(a.decode && !a.releaseSource);
    }
    // Same timestamp sequence applies without a home-key signal: pause, not rebuild.
    a=LMVDesktopGate(decide(LMVForegroundUnknown,0,0),LMVForegroundUnknown,0,1,0,0,0,1,291855,&clock);
    assert(a.decode && !a.releaseSource);
    a=LMVDesktopGate(decide(LMVForegroundUnknown,0,0),LMVForegroundUnknown,0,1,0,0,0,1,291855.16,&clock);
    assert(!a.decode && a.draw && !a.releaseSource);
    a=LMVDesktopGate(decide(LMVForegroundHome,0,0),LMVForegroundHome,1,1,0,0,0,0,291855.2,&clock);
    assert(a.decode); // resume on first known home
    // Full content rect pauses, retained frame stays drawn; reveal resumes.
    a=LMVDesktopGate(decide(LMVForegroundHome,1,0),LMVForegroundHome,0,1,1,0,0,1,291856,&clock);
    assert(a.draw && !a.decode && !a.releaseSource);
    a=LMVDesktopGate(decide(LMVForegroundHome,1,0),LMVForegroundHome,0,1,1,0,0,0,291860,&clock);
    assert(a.draw && !a.decode && !a.releaseSource);
    a=LMVDesktopGate(decide(LMVForegroundHome,0,0),LMVForegroundHome,1,1,0,0,0,0,291860.01,&clock);
    assert(a.decode && a.draw);
    assert(!LMVDesktopDockBelow(1,1,25,-2,1));
    assert(LMVDesktopDockBelow(1,1,-3,-2,1));
    assert(!LMVDesktopDockBelow(0,1,-3,-2,1));
    assert(!LMVDesktopDockBelow(1,0,-3,-2,1));
    assert(!LMVDesktopDockBelow(1,1,-3,-2,0));
    a=LMVDesktopGate(decide(LMVForegroundHome,0,1),LMVForegroundHome,1,1,0,1,1,1,291861,&clock);
    assert(a.dockFallback && !a.draw && !a.decode && !a.releaseSource);
    a=LMVDesktopGate(decide(LMVForegroundHome,0,0),LMVForegroundHome,1,1,0,0,0,0,291862,&clock);
    assert(!a.dockFallback && a.draw && a.decode);
    a=LMVDesktopGate(decide(LMVForegroundApp,0,0),LMVForegroundApp,1,1,0,0,0,1,291863,&clock);
    assert(!a.decode && !a.releaseSource); // real app stops immediately
    a=LMVDesktopGate(decide(LMVForegroundApp,0,0),LMVForegroundApp,1,1,0,0,0,0,291864.26,&clock);
    assert(!a.decode && a.releaseSource); // unused media bounded retirement
    a=LMVDesktopGate(LMVDesktopDecide(1,1,1,1,0,1,0,LMVForegroundHome,0,0),LMVForegroundHome,1,1,0,0,0,1,291865,&clock);
    assert(!a.draw && !a.decode && a.releaseSource);
    puts("PASS: 2048 desktop policy combinations; source4..7 .54 log timeline; unknown home-key recovery, partial/full/reveal NC, Dock25->-3 fallback, real app hard pause/bounded retirement, screen off");
    return 0;
}
