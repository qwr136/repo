#pragma once
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonCrypto.h>

#ifndef LMV_CATALOG_ROOT
#define LMV_CATALOG_ROOT @"/var/mobile/LockMessageVideo"
#endif

// 4.0.0: best-effort purge of orphaned per-material caches. A material's file
// can disappear (deleted in a file manager, re-imported under a new inode) while
// its thumbnails / first-frame posters / last-frame records linger. We keep only
// the records whose source material still exists, deleting the rest. Keys are
// derived the same way the stores hash them, so this never touches a live record.
static NSString *LMVCacheHashName(NSString *string) {
    NSData *bytes = [string dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *name = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
    return [name stringByAppendingPathExtension:@"plist"];
}
static void LMVSweepCacheDirectory(NSString *root, NSSet<NSString *> *keep) {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSArray *files = [fm contentsOfDirectoryAtPath:root error:nil];
    for (NSString *file in files) {
        if (![file.pathExtension isEqualToString:@"plist"]) continue;
        if ([keep containsObject:file]) continue;
        [fm removeItemAtPath:[root stringByAppendingPathComponent:file] error:nil];
    }
}
static void LMVSweepStaleCaches(NSArray<NSString *> *liveRelatives) {
    NSString *catalogRoot = LMV_CATALOG_ROOT;
    NSMutableSet<NSString *> *thumbnails = [NSMutableSet new];
    NSMutableSet<NSString *> *posters = [NSMutableSet new];
    NSMutableSet<NSString *> *frames = [NSMutableSet new];
    for (NSString *relative in liveRelatives) {
        NSString *absolute = [catalogRoot stringByAppendingPathComponent:relative];
        [thumbnails addObject:LMVCacheHashName(relative)];
        [posters addObject:LMVCacheHashName([absolute stringByStandardizingPath])];
        [frames addObject:LMVCacheHashName([[absolute stringByStandardizingPath] stringByResolvingSymlinksInPath])];
    }
    LMVSweepCacheDirectory([catalogRoot stringByAppendingPathComponent:@".material-thumbnails"], thumbnails);
    LMVSweepCacheDirectory([catalogRoot stringByAppendingPathComponent:@".background-posters"], posters);
    LMVSweepCacheDirectory([catalogRoot stringByAppendingPathComponent:@".last-frames"], frames);
}
// All catalog reads/writes run on LMVMaterialQueue, shared with import/clear.
// Keys are stable relative paths. Renaming never mutates a material or preference.
static NSString *LMVCatalogPath(void) {
    return [LMV_CATALOG_ROOT stringByAppendingPathComponent:@"material-names.plist"];
}
static NSMutableDictionary *LMVReadMaterialNames(void) {
    id value = [NSDictionary dictionaryWithContentsOfFile:LMVCatalogPath()];
    return [value isKindOfClass:NSDictionary.class] ? [value mutableCopy] : [NSMutableDictionary new];
}
static NSError *LMVWriteMaterialNames(NSDictionary *names) {
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:names format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data || ![data writeToFile:LMVCatalogPath() options:NSDataWritingAtomic error:&error]) return error ?: LMVStorageError(22, @"无法保存素材名称");
    return nil;
}
// 2.44: two materials could end up with the same generated name ("12" twice in the
// reported catalog), which makes the list look like one entry was duplicated. Any
// generated name is made unique against the names already on record.
static NSString *LMVUniqueMaterialName(NSString *candidate, NSDictionary *names, NSString *relative) {
    if (!candidate.length) return candidate;
    BOOL clash = NO;
    for (NSString *key in names) {
        if ([key isEqualToString:relative]) continue;
        id value = names[key];
        if ([value isKindOfClass:NSString.class] && [value isEqualToString:candidate]) { clash = YES; break; }
    }
    if (!clash) return candidate;
    for (NSUInteger suffix = 2; suffix < 100; suffix++) {
        NSString *next = [NSString stringWithFormat:@"%@ (%lu)", candidate, (unsigned long)suffix];
        BOOL taken = NO;
        for (NSString *key in names) {
            if ([key isEqualToString:relative]) continue;
            id value = names[key];
            if ([value isKindOfClass:NSString.class] && [value isEqualToString:next]) { taken = YES; break; }
        }
        if (!taken) return next;
    }
    return candidate;
}
static NSString *LMVMaterialDisplayName(NSString *relative, NSDictionary *names, NSDictionary *attributes, NSUInteger index) {
    id saved = names[relative];
    if ([saved isKindOfClass:NSString.class] && [saved length]) return saved;
    NSDictionary *legacy = @{@"message.mov": @"原消息视频", @"options.mov": @"原选项视频", @"clear.mov": @"原清除视频"};
    if (legacy[relative]) return legacy[relative];
    NSString *stem = relative.lastPathComponent.stringByDeletingPathExtension;
    NSRegularExpression *uuid = [NSRegularExpression regularExpressionWithPattern:@"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}" options:0 error:nil];
    if (stem.length && ![uuid numberOfMatchesInString:stem options:0 range:NSMakeRange(0, stem.length)])
        return LMVUniqueMaterialName(stem, names, relative);
    NSDate *date = attributes[NSFileCreationDate] ?: attributes[NSFileModificationDate];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd";
    NSString *generated = date ? [NSString stringWithFormat:@"导入 %@ · %lu", [formatter stringFromDate:date], (unsigned long)index + 1]
                               : [NSString stringWithFormat:@"视频素材 %lu", (unsigned long)index + 1];
    return LMVUniqueMaterialName(generated, names, relative);
}
static NSError *LMVRenameMaterial(NSString *relative, NSString *name) {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length || trimmed.length > 80) return LMVStorageError(20, @"素材名称应为 1–80 个字符");
    if (![relative hasPrefix:@"library/"] || [relative.pathComponents containsObject:@".."] || ![NSFileManager.defaultManager fileExistsAtPath:[LMV_CATALOG_ROOT stringByAppendingPathComponent:relative]]) return LMVStorageError(21, @"素材已不存在，无法重命名");
    NSMutableDictionary *names = LMVReadMaterialNames();
    names[relative] = trimmed;
    return LMVWriteMaterialNames(names);
}
