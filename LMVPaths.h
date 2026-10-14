#pragma once
#import <Foundation/Foundation.h>

// Keep user data on the original iOS root. Only installed jailbreak resources
// are jbroot-relative; this is not a global replacement of every absolute path.
#define LMV_VERSION_STRING @"0.0.114"

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

// Convenience only: retain the caller's existing lstat/O_NOFOLLOW/fd checks.
// Relative paths are the only values to persist in CFPreferences/catalogs.
static inline NSString *LMVUserStoragePath(NSString *relativePath) {
    if (![relativePath isKindOfClass:NSString.class] || !relativePath.length ||
        relativePath.isAbsolutePath || [relativePath.pathComponents containsObject:@".."] ||
        [relativePath.pathComponents containsObject:@"."]) return nil;
    NSString *root = LMVUserStorageRoot();
    NSString *path = [[root stringByAppendingPathComponent:relativePath] stringByStandardizingPath];
    return [path hasPrefix:[root stringByAppendingString:@"/"]] ? path : nil;
}

static inline NSString *LMVPreferenceBundlePath(void) {
    return LMVInstalledPath(@"/Library/PreferenceBundles/LockMessageVideoPrefs.bundle");
}
