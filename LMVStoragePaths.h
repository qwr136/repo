#pragma once
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

// 4.0.7: the ONE storage root. It used to be typed out 13 times across seven
// files (media cache, poster store, frame disk, catalog, picker, diagnostics),
// so moving the folder meant finding them all. Everything now derives from here.
// User media lives on the real iOS root; only jailbreak resources are jbroot-
// relative, so this is deliberately an absolute path.
// Guarded so a test fixture can substitute the path with a #define before this
// header is reached (the native video/image fixtures point it at a temp folder).
#ifndef LMVStorageRootPath
static NSString *const LMVStorageRootPath = @"/var/mobile/LockMessageVideo";
#endif

// 4.0.8: the three subfolders and the index file name, named once.
// Guarded so a standalone fixture can #define its own copy before this header is
// reached; the macro test is why these are #ifndef blocks rather than plain consts.
#ifndef LMVLibrarySubfolder
static NSString *const LMVLibrarySubfolder = @"library";
#endif
#ifndef LMVImagesSubfolder
static NSString *const LMVImagesSubfolder = @"images";
#endif
#ifndef LMVEasterSubfolder
static NSString *const LMVEasterSubfolder = @"小彩蛋";
#endif
#ifndef LMVMaterialNamesFileName
static NSString *const LMVMaterialNamesFileName = @"material-names.plist";
#endif
// 4.1.0: the three record caches. Each folder name was typed twice - once where
// the store builds its own paths, once where the catalog sweeps orphaned records -
// so renaming one produced a sweep that scanned a folder nobody wrote to: no error,
// just records that never got cleaned up.
#ifndef LMVThumbnailCacheFolder
static NSString *const LMVThumbnailCacheFolder = @".material-thumbnails";
#endif
#ifndef LMVPosterCacheFolder
static NSString *const LMVPosterCacheFolder = @".background-posters";
#endif
#ifndef LMVFrameCacheFolder
static NSString *const LMVFrameCacheFolder = @".last-frames";
#endif

// POSIX calls need C strings; these are the same names, not a second source.
#define LMV_LIBRARY_NAME "library"
#define LMV_MATERIAL_NAMES_FILE "material-names.plist"

static inline NSString *LMVLibraryPath(void) {
    return [LMVStorageRootPath stringByAppendingPathComponent:LMVLibrarySubfolder];
}
static inline NSString *LMVImagesPath(void) {
    return [LMVStorageRootPath stringByAppendingPathComponent:LMVImagesSubfolder];
}
static inline NSString *LMVEasterPath(void) {
    return [LMVStorageRootPath stringByAppendingPathComponent:LMVEasterSubfolder];
}

// 4.1.0: the record-file name was built by the same five lines in five places (frame
// disk, poster store, catalog sweep, thumbnail record, thumbnail log id) with only
// the input differing. The input still differs - one caller normalizes symlinks,
// another only standardizes - so the input handling stays at each call site and only
// the digest itself lives here.
static inline NSString *LMVStorageHashName(NSString *string) {
    NSData *bytes = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *name = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [name appendFormat:@"%02x", digest[i]];
    return name;
}
// Record files are plists named after the digest of what they describe.
static inline NSString *LMVStorageHashFileName(NSString *string) {
    return [LMVStorageHashName(string) stringByAppendingPathExtension:@"plist"];
}
// Log ids only need to be unique within one run; six bytes keeps the line readable.
static inline NSString *LMVStorageHashPrefix(NSString *string, NSUInteger bytes) {
    NSString *hex = LMVStorageHashName(string);
    return [hex substringToIndex:MIN(bytes * 2, hex.length)];
}

// Full paths for the two stores that hang off the storage root. The catalog and the
// thumbnail header build their own paths from LMV_CATALOG_ROOT - fixtures override
// that macro, so they must keep using it rather than these helpers.
static inline NSString *LMVPosterCachePath(void) {
    return [LMVStorageRootPath stringByAppendingPathComponent:LMVPosterCacheFolder];
}
static inline NSString *LMVFrameCachePath(void) {
    return [LMVStorageRootPath stringByAppendingPathComponent:LMVFrameCacheFolder];
}
