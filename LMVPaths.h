#pragma once
#import <Foundation/Foundation.h>

// Keep user data on the original iOS root. Only installed jailbreak resources
// are jbroot-relative; this is not a global replacement of every absolute path.
#define LMV_VERSION_STRING @"1.60"

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

// Input: trusted logical absolute path to a package-installed resource.
// Output: physical rootfs path for Foundation/system APIs, or nil on failure.
// Do not pass an already mapped physical path or a Photos temporary URL here.
static inline NSString *LMVInstalledPath(NSString *logicalPath) {
    if (![logicalPath isKindOfClass:NSString.class] || !logicalPath.length ||
        !logicalPath.isAbsolutePath || [logicalPath.pathComponents containsObject:@".."] ||
        [logicalPath.pathComponents containsObject:@"."]) return nil;
    NSString *resolved = nil;
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE) && THEOS_PACKAGE_SCHEME_ROOTHIDE
    resolved = jbroot(logicalPath);
#elif defined(THEOS_PACKAGE_SCHEME_ROOTLESS) && THEOS_PACKAGE_SCHEME_ROOTLESS
    resolved = ROOT_PATH_NS(logicalPath);
#else
    // macOS native regression tests and ordinary rootful builds.
    resolved = logicalPath;
#endif
    return resolved.length && resolved.isAbsolutePath ? resolved : nil;
}

// Existing media, caches, catalog and diagnostics never move into jbroot.
static inline NSString *LMVUserStorageRoot(void) {
    return @"/var/mobile/LockMessageVideo";
}

// Installed package resources (icons, entry plists, the prefs bundle itself)
// resolve through jbroot; retained as the single documented mapping helper for
// every future package-installed resource path. Never use it for user data.
static inline NSString *LMVPreferenceBundlePath(void) {
    return LMVInstalledPath(@"/Library/PreferenceBundles/LockMessageVideoPrefs.bundle");
}
