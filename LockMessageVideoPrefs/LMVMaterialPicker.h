#pragma once
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "LMVMaterialCatalog.h"
#import "LMVMaterialDeletion.h"
#import "LMVMaterialPrompt.h"

@interface LMVMaterialCell : UITableViewCell
@end
@implementation LMVMaterialCell
- (void)layoutSubviews {
    [super layoutSubviews];
    self.imageView.frame = CGRectMake(16, 10, 56, 56);
    CGFloat width = MAX(0, self.contentView.bounds.size.width - 102);
    self.textLabel.frame = CGRectMake(86, 10, width, self.detailTextLabel.text.length ? 38 : 56);
    self.detailTextLabel.frame = CGRectMake(86, 48, width, 18);
}
@end

@interface LMVMaterialPicker : UITableViewController
@property(nonatomic, copy) NSString *selected;
@property(nonatomic) BOOL pushed;
@property(nonatomic, strong) LMVMaterialPrompt *prompt;
@property(nonatomic, copy) void (^apply)(NSString *relative, NSString *name);
@property(nonatomic, copy) NSArray<NSDictionary *> *materials;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnails;
@property(nonatomic, strong) NSMutableSet<NSString *> *pending;
@property(nonatomic, strong) NSOperationQueue *thumbnailQueue;
@property(nonatomic) NSUInteger generation;
@end

@implementation LMVMaterialPicker
- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        _materials = @[];
        _thumbnails = [NSCache new];
        _thumbnails.countLimit = 60;
        _thumbnails.totalCostLimit = 6 * 1024 * 1024;
        _pending = [NSMutableSet new];
        _thumbnailQueue = [NSOperationQueue new];
        _thumbnailQueue.maxConcurrentOperationCount = 1;
        _thumbnailQueue.qualityOfService = NSQualityOfServiceUtility;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择素材";
    self.tableView.rowHeight = 76;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    [self reloadLibrary];
}
- (void)cancel {
    if (self.pushed) [self.navigationController popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}
- (void)dealloc { [_thumbnailQueue cancelAllOperations]; }
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [self.thumbnails removeAllObjects];
}
- (void)reloadLibrary {
    NSUInteger generation = ++self.generation;
    __weak typeof(self) weakSelf = self;
    dispatch_async(LMVMaterialQueue(), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *base = @"/var/mobile/LockMessageVideo";
        NSArray *library = [[fm contentsOfDirectoryAtPath:[base stringByAppendingPathComponent:@"library"] error:nil] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        NSMutableArray *paths = [NSMutableArray new];
        for (NSString *legacy in @[@"message.mov", @"options.mov", @"clear.mov"]) if ([fm fileExistsAtPath:[base stringByAppendingPathComponent:legacy]]) [paths addObject:legacy];
        for (NSString *file in library) if ([@[@"mov", @"mp4", @"m4v"] containsObject:file.pathExtension.lowercaseString]) [paths addObject:[@"library" stringByAppendingPathComponent:file]];
        NSMutableDictionary *names = LMVReadMaterialNames();
        BOOL namesChanged = NO;
        NSMutableArray *rows = [NSMutableArray new];
        for (NSString *relative in paths) {
            NSDictionary *attributes = [fm attributesOfItemAtPath:[base stringByAppendingPathComponent:relative] error:nil];
            if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) continue;
            NSString *name = LMVMaterialDisplayName(relative, names, attributes, rows.count);
            if (![names[relative] isKindOfClass:NSString.class] || ![names[relative] length]) {
                names[relative] = name;
                namesChanged = YES;
            }
            NSString *revision = [NSString stringWithFormat:@"%@|%@|%@", relative, attributes[NSFileModificationDate], attributes[NSFileSize]];
            [rows addObject:@{@"path": relative, @"name": name, @"revision": revision}];
        }
        if (namesChanged) LMVWriteMaterialNames(names);
        dispatch_async(dispatch_get_main_queue(), ^{
            LMVMaterialPicker *picker = weakSelf;
            if (!picker || picker.generation != generation) return;
            picker.materials = rows;
            [picker.tableView reloadData];
        });
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.materials.count + 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.materials.count ? @"向左滑动素材可重命名或删除。删除正在使用的素材会取消相关背景选择。" : @"素材库为空，请先从相册导入视频。";
}
- (void)requestThumbnail:(NSDictionary *)row {
    NSString *key = row[@"revision"];
    if ([self.thumbnails objectForKey:key] || [self.pending containsObject:key] || self.pending.count >= 12) return;
    [self.pending addObject:key];
    NSString *path = [@"/var/mobile/LockMessageVideo" stringByAppendingPathComponent:row[@"path"]];
    __weak typeof(self) weakSelf = self;
    [self.thumbnailQueue addOperationWithBlock:^{
        @autoreleasepool {
            // Decode only a small poster, on a bounded serial background queue.
            AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
            AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
            generator.appliesPreferredTrackTransform = YES;
            generator.maximumSize = CGSizeMake(144, 144);
            CGImageRef image = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
            UIImage *poster = image ? [UIImage imageWithCGImage:image] : nil;
            NSUInteger cost = image ? CGImageGetBytesPerRow(image) * CGImageGetHeight(image) : 0;
            if (image) CGImageRelease(image);
            dispatch_async(dispatch_get_main_queue(), ^{
                LMVMaterialPicker *picker = weakSelf;
                if (!picker) return;
                [picker.pending removeObject:key];
                [picker.thumbnails setObject:poster ?: [UIImage systemImageNamed:@"film"] forKey:key cost:cost];
                // Resolve current paths, never capture/reuse a cell from a previous generation.
                for (NSIndexPath *index in picker.tableView.indexPathsForVisibleRows) {
                    if (index.row < picker.materials.count) {
                        NSDictionary *visible = picker.materials[index.row];
                        if ([visible[@"revision"] isEqualToString:key]) [picker.tableView reloadRowsAtIndexPaths:@[index] withRowAnimation:UITableViewRowAnimationNone];
                        else [picker requestThumbnail:visible];
                    }
                }
            });
        }
    }];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Material"];
    if (!cell) cell = [[LMVMaterialCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"Material"];
    BOOL none = indexPath.row == self.materials.count;
    NSDictionary *row = none ? nil : self.materials[indexPath.row];
    NSString *relative = none ? @"" : row[@"path"];
    BOOL current = [self.selected isEqualToString:relative];
    cell.textLabel.text = none ? @"无素材" : row[@"name"];
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.text = current ? @"使用中" : nil;
    cell.accessoryType = current ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.imageView.image = none ? [UIImage systemImageNamed:@"nosign"] : [self.thumbnails objectForKey:row[@"revision"]] ?: [UIImage systemImageNamed:@"film"];
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.clipsToBounds = YES;
    cell.imageView.layer.cornerRadius = 6;
    cell.imageView.bounds = CGRectMake(0, 0, 56, 56);
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@%@", cell.textLabel.text, current ? @"，使用中" : @""];
    if (!none) [self requestThumbnail:row];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BOOL none = indexPath.row == self.materials.count;
    NSDictionary *row = none ? nil : self.materials[indexPath.row];
    NSString *relative = none ? @"" : row[@"path"];
    NSString *name = none ? @"无素材" : row[@"name"];
    void (^apply)(NSString *, NSString *) = self.apply;
    if (self.pushed) {
        if (apply) apply(relative, name);
        [self.navigationController popViewControllerAnimated:YES];
    } else [self dismissViewControllerAnimated:YES completion:^{ if (apply) apply(relative, name); }];
}
- (void)showPrompt:(NSString *)title message:(NSString *)message initial:(NSString *)initial action:(NSString *)action destructive:(BOOL)destructive completion:(void (^)(NSString *, BOOL))completion {
    if (self.prompt) return;
    LMVMaterialPrompt *prompt = [LMVMaterialPrompt new];
    prompt.promptTitle = title; prompt.message = message; prompt.initialText = initial;
    prompt.editing = initial != nil; prompt.actionTitle = action; prompt.destructive = destructive;
    __weak typeof(self) weakSelf = self;
    prompt.complete = ^(NSString *text, BOOL accepted) { weakSelf.prompt = nil; if (completion) completion(text, accepted); };
    UIViewController *host = self.navigationController ?: self;
    self.prompt = prompt; [host addChildViewController:prompt]; [host.view addSubview:prompt.view];
    prompt.view.frame = host.view.bounds; prompt.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [prompt didMoveToParentViewController:host];
}
- (void)deleteContained:(NSDictionary *)row {
    __weak typeof(self) weakSelf = self;
    [self showPrompt:@"删除素材？" message:[NSString stringWithFormat:@"将删除“%@”，相关背景会取消此素材选择。", row[@"name"]] initial:nil action:@"删除" destructive:YES completion:^(NSString *text, BOOL accepted) {
        LMVMaterialPicker *picker = weakSelf; if (!accepted || !picker) return;
        picker.tableView.userInteractionEnabled = NO;
        dispatch_async(LMVMaterialQueue(), ^{
            BOOL deleted = NO; NSError *error = LMVDeleteMaterial(row[@"path"], &deleted);
            dispatch_async(dispatch_get_main_queue(), ^{
                LMVMaterialPicker *live = weakSelf; if (!live) return;
                live.tableView.userInteractionEnabled = YES;
                if (deleted) {
                    if ([live.selected isEqualToString:row[@"path"]]) live.selected = @"";
                    [live.thumbnails removeObjectForKey:row[@"revision"]]; [live reloadLibrary];
                }
                [live showPrompt:error ? (deleted ? @"素材已删除，清理未完成" : @"删除失败") : @"素材已删除" message:error.localizedDescription ?: @"相关背景选择已更新。" initial:nil action:nil destructive:NO completion:nil];
            });
        });
    }];
}
- (void)renameContained:(NSDictionary *)row {
    __weak typeof(self) weakSelf = self;
    [self showPrompt:@"重命名素材" message:@"仅修改显示名称。" initial:row[@"name"] action:@"保存" destructive:NO completion:^(NSString *text, BOOL accepted) {
        if (!accepted) return;
        dispatch_async(LMVMaterialQueue(), ^{
            NSError *error = LMVRenameMaterial(row[@"path"], text);
            dispatch_async(dispatch_get_main_queue(), ^{
                LMVMaterialPicker *live = weakSelf; if (!live) return;
                if (!error) [live reloadLibrary];
                else [live showPrompt:@"重命名失败" message:error.localizedDescription initial:nil action:nil destructive:NO completion:nil];
            });
        });
    }];
}
- (void)confirmDelete:(NSDictionary *)row {
    if (self.pushed) { [self deleteContained:row]; return; }
    if (self.presentedViewController) return;
    NSString *relative=row[@"path"];
    UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"删除素材？" message:[NSString stringWithFormat:@"将删除“%@”，无法撤销。消息、锁屏、选项或清除背景如果正在使用它，会取消该素材选择。",row[@"name"]] preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf=self;
    [confirm addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        LMVMaterialPicker *picker=weakSelf;
        picker.tableView.userInteractionEnabled=NO;
        [picker dismissViewControllerAnimated:YES completion:^{
            dispatch_async(LMVMaterialQueue(),^{
                BOOL deleted=NO;
                NSError *error=LMVDeleteMaterial(relative,&deleted);
                dispatch_async(dispatch_get_main_queue(),^{
                    LMVMaterialPicker *live=weakSelf;
                    if (!live) return;
                    live.tableView.userInteractionEnabled=YES;
                    if (deleted) {
                        if ([live.selected isEqualToString:relative]) live.selected=@"";
                        [live.thumbnails removeObjectForKey:row[@"revision"]];
                        [live reloadLibrary];
                    }
                    NSString *title=error ? (deleted ? @"素材已删除，清理未完成" : @"删除失败") : @"素材已删除";
                    UIAlertController *result=[UIAlertController alertControllerWithTitle:title message:error.localizedDescription ?: @"相关背景选择已更新。其他素材保持不变。" preferredStyle:UIAlertControllerStyleAlert];
                    [result addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                    [live presentViewController:result animated:YES completion:nil];
                });
            });
        }];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.materials.count) return nil;
    NSDictionary *row = self.materials[indexPath.row];
    if (![row[@"path"] hasPrefix:@"library/"]) return nil;
    __weak typeof(self) weakSelf = self;
    UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"重命名" handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        LMVMaterialPicker *picker = weakSelf;
        if (!picker || picker.prompt) { done(NO); return; }
        if (picker.pushed) { [picker renameContained:row]; done(YES); return; }
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重命名素材" message:@"仅修改显示名称，视频文件和当前选择保持不变。" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = row[@"name"]; field.clearButtonMode = UITextFieldViewModeWhileEditing; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *save) {
            NSString *name = alert.textFields.firstObject.text;
            dispatch_async(LMVMaterialQueue(), ^{
                NSError *error = LMVRenameMaterial(row[@"path"], name);
                dispatch_async(dispatch_get_main_queue(), ^{
                    LMVMaterialPicker *live = weakSelf;
                    if (!live) return;
                    if (!error) [live reloadLibrary];
                    else {
                        UIAlertController *failure = [UIAlertController alertControllerWithTitle:@"重命名失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
                        [failure addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
                        [live presentViewController:failure animated:YES completion:nil];
                    }
                });
            });
        }]];
        [picker presentViewController:alert animated:YES completion:nil];
        done(YES);
    }];
    rename.backgroundColor = UIColor.systemBlueColor;
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        LMVMaterialPicker *picker = weakSelf;
        if (!picker || picker.presentedViewController || picker.prompt) { done(NO); return; }
        done(YES);
        [picker confirmDelete:row];
    }];
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[rename, remove]];
    configuration.performsFirstActionWithFullSwipe = NO;
    return configuration;
}
@end
