#include <assert.h>
#include <stdio.h>
#include "../LMVConsumerPolicy.h"
int main(void) {
    for (unsigned bits=0; bits<256; ++bits) {
        bool host=bits&1, window=bits&2, visible=bits&4, screen=bits&8;
        bool locked=bits&16, known=bits&32, home=bits&64, covered=bits&128;
        bool actual=LMVDesktopConsumerAllowed(host,window,visible,screen,locked,known,home,covered);
        assert(actual == (host && window && visible && screen && !locked && known && home && !covered));
        if (!screen || locked || !known || !home || covered) assert(!actual);
    }
    assert(LMVDesktopConsumerAllowed(1,1,1,1,0,1,1,0));
    puts("PASS: all 256 desktop visibility gates; app/lock/NC/blank/unknown deny; visible desktop resumes (portable policy, not device test)");
    return 0;
}
