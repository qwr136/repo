#include <assert.h>
#include <stdio.h>
#include "../LMVConsumerPolicy.h"
int main(void) {
    for (unsigned mask=0; mask<16; mask++) {
        bool allowed=LMVLockConsumerAllowed(mask&1,mask&2,mask&4,mask&8);
        assert(allowed==(mask==15));
    }
    // Hidden cover or screen off must stop even when all card features enabled.
    assert(!LMVLockConsumerAllowed(true,true,false,true));
    assert(!LMVLockConsumerAllowed(true,true,true,false));
    assert(!LMVLockConsumerAllowed(true,false,true,true));
    puts("PASS: all 16 actual lock consumer gate combinations (not UIKit host validation)");
    return 0;
}
