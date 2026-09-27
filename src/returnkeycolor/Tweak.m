#import <UIKit/UIKit.h>

// Swift 暴露的 C 入口
void RKSetup(void);

__attribute__((constructor))
static void _rk_constructor(void) {
    RKSetup();
}
