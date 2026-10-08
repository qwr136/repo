#pragma once
#import <Foundation/Foundation.h>

#ifndef LMV_CATALOG_ROOT
#define LMV_CATALOG_ROOT @"/var/mobile/LockMessageVideo"
#endif
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
static NSString *LMVMaterialDisplayName(NSString *relative, NSDictionary *names, NSDictionary *attributes, NSUInteger index) {
    id saved = names[relative];
    if ([saved isKindOfClass:NSString.class] && [saved length]) return saved;
    NSDictionary *legacy = @{@"message.mov": @"原消息视频", @"options.mov": @"原选项视频", @"clear.mov": @"原清除视频"};
    if (legacy[relative]) return legacy[relative];
    NSString *stem = relative.lastPathComponent.stringByDeletingPathExtension;
    NSRegularExpression *uuid = [NSRegularExpression regularExpressionWithPattern:@"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}" options:0 error:nil];
    if (stem.length && ![uuid numberOfMatchesInString:stem options:0 range:NSMakeRange(0, stem.length)]) return stem;
    NSDate *date = attributes[NSFileCreationDate] ?: attributes[NSFileModificationDate];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.dateFormat = @"yyyy-MM-dd";
    return date ? [NSString stringWithFormat:@"导入 %@ · %lu", [formatter stringFromDate:date], (unsigned long)index + 1] : [NSString stringWithFormat:@"视频素材 %lu", (unsigned long)index + 1];
}
static NSError *LMVRenameMaterial(NSString *relative, NSString *name) {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length || trimmed.length > 80) return LMVStorageError(20, @"素材名称应为 1–80 个字符");
    if (![relative hasPrefix:@"library/"] || [relative.pathComponents containsObject:@".."] || ![NSFileManager.defaultManager fileExistsAtPath:[LMV_CATALOG_ROOT stringByAppendingPathComponent:relative]]) return LMVStorageError(21, @"素材已不存在，无法重命名");
    NSMutableDictionary *names = LMVReadMaterialNames();
    names[relative] = trimmed;
    return LMVWriteMaterialNames(names);
}
