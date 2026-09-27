#import <UIKit/UIKit.h>

// Swift 暴露的 C 入口
void WKSetup(void);

__attribute__((constructor))
static void _wk_constructor(void) {
    WKSetup();
}
