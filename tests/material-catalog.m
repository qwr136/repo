#import <Foundation/Foundation.h>
#include <assert.h>
#define LMV_CATALOG_ROOT @"/tmp/lmv-catalog-tests"
static NSError *LMVStorageError(NSInteger code, NSString *message) { return [NSError errorWithDomain:@"Test" code:code userInfo:@{NSLocalizedDescriptionKey:message}]; }
#import "../LockMessageVideoPrefs/LMVMaterialCatalog.h"
int main(void) {
    @autoreleasepool {
        NSFileManager *fm=NSFileManager.defaultManager;
        [fm removeItemAtPath:LMV_CATALOG_ROOT error:nil];
        [fm createDirectoryAtPath:[LMV_CATALOG_ROOT stringByAppendingPathComponent:@"library"] withIntermediateDirectories:YES attributes:nil error:nil];
        NSString *relative=@"library/11111111-1111-1111-1111-111111111111.mov";
        NSString *path=[LMV_CATALOG_ROOT stringByAppendingPathComponent:relative];
        NSData *bytes=[@"unchanged optimized video bytes" dataUsingEncoding:NSUTF8StringEncoding];
        assert([bytes writeToFile:path atomically:YES]);
        NSDictionary *selected=@{@"MessageVideo":relative,@"OptionsVideo":relative,@"ClearVideo":@"",@"LockScreenVideo":relative};
        NSDictionary *before=[selected copy];
        assert(!LMVRenameMaterial(relative,@"  山间清晨  "));
        NSDictionary *names=LMVReadMaterialNames();
        assert([names[relative] isEqualToString:@"山间清晨"]);
        assert([[NSData dataWithContentsOfFile:path] isEqualToData:bytes]);
        assert([selected isEqualToDictionary:before]);
        assert([LMVMaterialDisplayName(relative,names,@{},0) isEqualToString:@"山间清晨"]);
        assert([LMVMaterialDisplayName(relative,@{},@{},2) isEqualToString:@"视频素材 3"]);
        assert(LMVRenameMaterial(relative,@" "));
        assert(LMVRenameMaterial(@"library/../message.mov",@"invalid"));
        assert([LMVReadMaterialNames()[relative] isEqualToString:@"山间清晨"]);
        // Atomic persistence failure must leave existing metadata intact.
        assert(LMVWriteMaterialNames(@{@"bad": [NSObject new]}));
        assert([LMVReadMaterialNames()[relative] isEqualToString:@"山间清晨"]);
        [fm removeItemAtPath:LMV_CATALOG_ROOT error:nil];
        puts("PASS: actual catalog rename/read/fallback/invalid/atomic serialization failure; file bytes and selection identities retained");
    }
    return 0;
}
