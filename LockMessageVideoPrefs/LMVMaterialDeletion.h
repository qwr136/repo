#pragma once
#import <Foundation/Foundation.h>
#import "LMVMaterialCatalog.h"
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>

#ifndef LMV_DELETE_PREFS_ID
#define LMV_DELETE_PREFS_ID CFSTR("com.minis.lockmessagevideo")
#endif
// Run on LMVMaterialQueue. No recursive deletion or symlink traversal.
// deleted distinguishes a filesystem failure from a post-delete persistence error.
static NSError *LMVDeleteMaterial(NSString *relative, BOOL *deleted) {
    if (deleted) *deleted=NO;
    NSArray *parts=relative.pathComponents;
    BOOL library=parts.count==2 && [parts[0] isEqualToString:@"library"];
    BOOL legacy=parts.count==1 && [@[@"message.mov",@"options.mov",@"clear.mov"] containsObject:relative];
    if ((!library && !legacy) || !relative.length || [parts containsObject:@".."] || [parts containsObject:@"."])
        return LMVStorageError(30,@"素材路径无效，未删除任何文件");
    int base=open([LMV_CATALOG_ROOT fileSystemRepresentation],O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if (base<0) return LMVStorageError(errno,@"无法打开素材目录，未删除任何文件");
    int folder=library ? openat(base,"library",O_RDONLY|O_DIRECTORY|O_NOFOLLOW) : dup(base);
    int code=errno; close(base);
    if (folder<0) return LMVStorageError(code,@"素材库目录不可访问，未删除任何文件");
    const char *name=relative.lastPathComponent.fileSystemRepresentation;
    struct stat status;
    if (fstatat(folder,name,&status,AT_SYMLINK_NOFOLLOW)!=0) {
        code=errno; close(folder); return LMVStorageError(code,@"素材已不存在或无法读取，未改变背景选择");
    }
    if (!S_ISREG(status.st_mode)) { close(folder); return LMVStorageError(31,@"只能删除普通视频文件，不删除目录或符号链接"); }
    if (unlinkat(folder,name,0)!=0) {
        code=errno; close(folder); return LMVStorageError(code,@"素材删除失败，背景选择保持不变");
    }
    close(folder);
    if (deleted) *deleted=YES;

    CFPreferencesAppSynchronize(LMV_DELETE_PREFS_ID);
    NSDictionary *defaults=@{@"Message":@"message.mov",@"Options":@"options.mov",@"Clear":@"clear.mov",@"LockScreen":@""};
    for (NSString *target in @[@"Message",@"LockScreen",@"Options",@"Clear"]) {
        NSString *key=[target stringByAppendingString:@"Video"];
        id value=(__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key,LMV_DELETE_PREFS_ID);
        NSString *selected=[value isKindOfClass:NSString.class] ? value : defaults[target];
        if ([selected isEqualToString:relative])
            CFPreferencesSetAppValue((__bridge CFStringRef)key,CFSTR(""),LMV_DELETE_PREFS_ID);
    }
    BOOL persisted=CFPreferencesAppSynchronize(LMV_DELETE_PREFS_ID);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),CFSTR("com.minis.lockmessagevideo/preferencesChanged"),NULL,NULL,YES);
    NSMutableDictionary *names=LMVReadMaterialNames();
    NSError *metadataError=nil;
    if (names[relative]) { [names removeObjectForKey:relative]; metadataError=LMVWriteMaterialNames(names); }
    if (!persisted) return LMVStorageError(32,@"视频已删除，但部分背景选择未能保存；请重新打开设置并选择素材");
    if (metadataError) return LMVStorageError(33,@"视频已删除且背景选择已清除，但旧名称记录未能清理");
    return nil;
}
