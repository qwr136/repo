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
