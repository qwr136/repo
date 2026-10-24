#pragma once
#import <Foundation/Foundation.h>

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

// Full paths for the two stores that hang off the storage root. The catalog and the
// thumbnail header build their own paths from LMV_CATALOG_ROOT - fixtures override
// that macro, so they must keep using it rather than these helpers.
static inline NSString *LMVPosterCachePath(void) {
    return [LMVStorageRootPath stringByAppendingPathComponent:LMVPosterCacheFolder];
}
static inline NSString *LMVFrameCachePath(void) {
    return [LMVStorageRootPath stringByAppendingPathComponent:LMVFrameCacheFolder];
}
