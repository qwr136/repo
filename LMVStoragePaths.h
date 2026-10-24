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
static NSString *const LMVLibrarySubfolder = @"library";
static NSString *const LMVImagesSubfolder = @"images";
static NSString *const LMVEasterSubfolder = @"小彩蛋";
static NSString *const LMVMaterialNamesFileName = @"material-names.plist";
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
