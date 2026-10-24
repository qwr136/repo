#pragma once
#import <Foundation/Foundation.h>

// Keep user data on the original iOS root. Only installed jailbreak resources
// are jbroot-relative; this is not a global replacement of every absolute path.
#define LMV_VERSION_STRING @"4.0.5"


#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE) && THEOS_PACKAGE_SCHEME_ROOTHIDE
# if !__has_include(<roothide.h>)
#  error "Native RootHide requires the pinned roothide/theos <roothide.h> API"
# endif
# include <roothide.h>
#elif defined(THEOS_PACKAGE_SCHEME_ROOTLESS) && THEOS_PACKAGE_SCHEME_ROOTLESS
# if !__has_include(<rootless.h>)
#  error "Legacy rootless requires the Theos <rootless.h> API"
# endif
# include <rootless.h>
#endif

// Existing media, caches, catalog and diagnostics never move into jbroot.
static inline NSString *LMVUserStorageRoot(void) {
    return @"/var/mobile/LockMessageVideo";
}
