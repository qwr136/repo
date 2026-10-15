#pragma once
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "LMVMaterialCatalog.h"
#import "LMVThumbnailDiagnosticLog.h"
#import "LMVMaterialThumbnail.h"
#import "LMVMaterialDeletion.h"
#import "LMVMaterialPrompt.h"

// 0.0.124: bounded retry for a poster that is not on disk yet. A freshly imported
// movie is still being finalised when the list opens, so decoding its first frame
// can fail; the old code latched that failure for the whole session and left the
// film icon on the row forever. Two decode attempts per round, up to six rounds
// (0.0.125) - and the ledger lives on the SHARED picker state, so rounds survive
// re-entering the list and are never lost to a scrolled-away row.
static const NSInteger LMVMaterialThumbnailMaxFailures = 2;
static const NSInteger LMVMaterialThumbnailRetryLimit = 6;
static const NSTimeInterval LMVMaterialThumbnailRetryDelay = 3.0;

@interface LMVMaterialCell : UITableViewCell
@property(nonatomic) BOOL showsThumbnail;
@end
@implementation LMVMaterialCell
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat leading=self.showsThumbnail?86:16;
    self.imageView.hidden=!self.showsThumbnail;
    if (self.showsThumbnail) self.imageView.frame = CGRectMake(16, 10, 56, 56);
    CGFloat width = MAX(0, self.contentView.bounds.size.width-leading-16);
    CGFloat titleHeight=self.detailTextLabel.text.length?(self.showsThumbnail?38:24):(self.showsThumbnail?56:40);
    self.textLabel.frame = CGRectMake(leading, 10, width, titleHeight);
    self.detailTextLabel.frame = CGRectMake(leading, self.showsThumbnail?48:34, width, 18);
}
@end

@interface LMVMaterialPicker : UITableViewController
@property(nonatomic, copy) NSString *selected;
@property(nonatomic) BOOL pushed;
@property(nonatomic) BOOL showsThumbnails;
@property(nonatomic, strong) LMVMaterialPrompt *prompt;
@property(nonatomic, copy) void (^apply)(NSString *relative, NSString *name);
@property(nonatomic, copy) NSArray<NSDictionary *> *materials;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *thumbnails;
@property(nonatomic, strong) NSMutableSet<NSString *> *pending;
@property(nonatomic, strong) NSOperationQueue *thumbnailQueue;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *thumbnailFailures;
@property(nonatomic) NSUInteger generation;
@property(nonatomic, strong) NSMutableSet<NSString *> *previewStages;
// 0.0.124: how many retry rounds a row has used, and which rows already have one
// queued (so a row cannot schedule two timers).
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *thumbnailRetries;
@property(nonatomic, strong) NSMutableSet<NSString *> *retryScheduled;
- (void)requestThumbnail:(NSDictionary *)row;
- (void)scheduleRetryForKey:(NSString *)key;
- (BOOL)thumbnailIsPending:(NSDictionary *)row;
- (void)tracePreview:(NSString *)stage row:(NSDictionary *)row;
@end

@implementation LMVMaterialPicker

// 0.0.117: while the panel is open this window becomes KEY, so UIKit asks ITS
// root view controller for the supported orientations. A plain UIViewController
// answers portrait-only, which locks the whole scene (SpringBoard included) and
// left the floating ball where it was when the phone turned landscape with the
// rotation lock off. All-but-upside-down matches the other floating system
// surfaces; layout follows the root view bounds, so the ball moves with it.
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }

- (instancetype)init {
    self = [super initWithStyle:UITableViewStyleInsetGrouped];
    if (self) {
        // 0.0.125: every picker instance in this process shares ONE thumbnail
        // cache, ONE queue and ONE retry ledger. The Settings entry and the
        // floating-panel entry used to build fresh instances, so each open
        // re-read/re-decoded posters the other entry had just produced; worse,
        // a retry round was lost whenever its row happened to be off screen in
        // the instance that scheduled it. (Cross-process sharing stays on disk
        // via the sidecar records - SpringBoard and Settings cannot share
        // Objective-C objects.) All shared state is touched on the main thread
        // only; NSCache itself is thread-safe.
        static NSCache<NSString *, UIImage *> *sharedThumbnails;
        static NSMutableDictionary<NSString *, NSNumber *> *sharedFailures, *sharedRetries;
        static NSMutableSet<NSString *> *sharedScheduled, *sharedPending;
        static NSOperationQueue *sharedQueue;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            sharedThumbnails = [NSCache new];
            sharedThumbnails.countLimit = 60;
            sharedThumbnails.totalCostLimit = 6 * 1024 * 1024;
            sharedFailures = [NSMutableDictionary new];
            sharedRetries = [NSMutableDictionary new];
            sharedScheduled = [NSMutableSet new];
            sharedPending = [NSMutableSet new];
            sharedQueue = [NSOperationQueue new];
            // 0.0.123: two workers instead of one. Decoding a poster is dominated by
            // I/O + one frame decode, so a second worker doubles the fill rate of a
            // long list while keeping the peak bounded.
            sharedQueue.maxConcurrentOperationCount = 2;
            sharedQueue.qualityOfService = NSQualityOfServiceUtility;
        });
        _materials = @[];
        _showsThumbnails = YES;
        _thumbnails = sharedThumbnails;
        _pending = sharedPending;
        _previewStages = [NSMutableSet new];
        _thumbnailFailures = sharedFailures;
        _thumbnailRetries = sharedRetries;
        _retryScheduled = sharedScheduled;
        _thumbnailQueue = sharedQueue;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择素材";
    self.tableView.rowHeight = self.showsThumbnails?76:60;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStylePlain target:self action:@selector(cancel)];
    [self reloadLibrary];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Another process may have published sidecars since this picker last appeared.
    [self.thumbnailFailures removeAllObjects];
    [self.previewStages removeAllObjects];
    LMVThumbnailLog(@"picker-appear", @"", nil);
    [self requestVisibleThumbnails];
}
- (void)cancel {
    if (self.pushed) [self.navigationController popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:nil];
}
// The queue is shared by every picker in the process (0.0.125): closing one
// picker must never cancel another's in-flight decodes, and a finished decode
// still lands in the shared cache for the next open.
// Rows skipped while the queue was full are requested once scrolling settles.
- (void)requestVisibleThumbnails {
    if (!self.showsThumbnails) return;
    for (NSIndexPath *index in self.tableView.indexPathsForVisibleRows)
        if (index.row < self.materials.count) [self requestThumbnail:self.materials[index.row]];
}
- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView { [self requestVisibleThumbnails]; }
- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate { if (!decelerate) [self requestVisibleThumbnails]; }
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
            NSString *revision = LMVThumbnailRevision(relative);
            if (revision) [rows addObject:@{@"path": relative, @"name": name, @"revision": revision}];
        }
        if (namesChanged) LMVWriteMaterialNames(names);
        dispatch_async(dispatch_get_main_queue(), ^{
            LMVMaterialPicker *picker = weakSelf;
            if (!picker || picker.generation != generation) return;
            picker.materials = rows;
            [picker.previewStages removeAllObjects];
            LMVThumbnailLog([NSString stringWithFormat:@"catalog-ready count=%lu generation=%lu", (unsigned long)rows.count, (unsigned long)generation], @"", nil);
            [picker.tableView reloadData];
        });
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.materials.count + 1; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return self.materials.count ? @"向左滑动素材可重命名或删除。删除正在使用的素材会取消相关背景选择。" : @"素材库为空，请先从相册导入视频。";
}
- (void)tracePreview:(NSString *)stage row:(NSDictionary *)row {
    if (!LMVThumbnailDiagnosticIsEnabled()) return;
    NSString *identity = [NSString stringWithFormat:@"%@|%@", row[@"revision"] ?: @"invalid", stage];
    if ([self.previewStages containsObject:identity] || self.previewStages.count >= 400) return;
    [self.previewStages addObject:identity];
    NSUInteger index = [self.materials indexOfObjectIdenticalTo:row];
    LMVThumbnailLog([NSString stringWithFormat:@"%@ row=%ld generation=%lu", stage,
        index == NSNotFound ? -1L : (long)index + 1, (unsigned long)self.generation], row[@"path"] ?: @"", nil);
}
// A row with no poster is "still working" until its retry budget runs out, so the
// list can say 生成中 instead of showing the film icon (which read as "broken").
- (BOOL)thumbnailIsPending:(NSDictionary *)row {
    NSString *key = row[@"revision"];
    if (!key.length) return NO;
    if ([self.pending containsObject:key]) return YES;
    return self.thumbnailRetries[key].integerValue < LMVMaterialThumbnailRetryLimit;
}
// 0.0.124: retry a failed poster on a timer. Imported files settle within a few
// seconds, so the list fills itself in without the user leaving and re-entering it.
// 0.0.125: the retry re-requests by ROW (searching the whole catalog), not by
// visibility - previously a round was silently consumed whenever its row was
// scrolled off screen in the picker that scheduled it, which is exactly how a
// freshly imported entry ended up with no poster after all rounds were gone.
// Six rounds x 3 s covers a large copy that settles slowly.
- (void)scheduleRetryForKey:(NSString *)key {
    if (!key.length || [self.retryScheduled containsObject:key]) return;
    if (self.thumbnailRetries[key].integerValue >= LMVMaterialThumbnailRetryLimit) return;
    self.thumbnailRetries[key] = @(self.thumbnailRetries[key].integerValue + 1);
    [self.retryScheduled addObject:key];
    // The shared ledger objects are held strongly: a picker closing before the
    // timer fires must not leak the scheduled marker (which would block every
    // future retry for this row) nor keep the failure memory latched.
    NSMutableSet<NSString *> *scheduled = self.retryScheduled;
    NSMutableDictionary<NSString *, NSNumber *> *ledger = self.thumbnailFailures;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(LMVMaterialThumbnailRetryDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [scheduled removeObject:key];
        [ledger removeObjectForKey:key];
        LMVMaterialPicker *picker = weakSelf;
        if (!picker) return;
        for (NSDictionary *material in picker.materials)
            if ([material[@"revision"] isEqualToString:key]) { [picker requestThumbnail:material]; return; }
    });
}
- (void)requestThumbnail:(NSDictionary *)row {
    if (!self.showsThumbnails) return;
    NSString *key = row[@"revision"];
    if (!key.length) { [self tracePreview:@"request-invalid" row:row]; return; }
    [self tracePreview:@"request" row:row];
    if ([self.thumbnails objectForKey:key]) { [self tracePreview:@"memory-hit" row:row]; return; }
    // 0.0.123: a single transient failure (a file still being finalised, a slow
    // first frame) used to park this row on the placeholder for the whole
    // session. Retry a bounded number of times instead of latching.
    NSInteger failures = self.thumbnailFailures[key].integerValue;
    if (failures >= LMVMaterialThumbnailMaxFailures) { [self tracePreview:@"skip-previous-failure" row:row]; return; }
    if ([self.pending containsObject:key]) { [self tracePreview:@"skip-pending" row:row]; return; }
    if (self.pending.count >= 12) { [self tracePreview:@"defer-queue-full" row:row]; return; }
    [self tracePreview:@"enqueue" row:row];
    [self.pending addObject:key];
    NSString *relative = row[@"path"];
    NSTimeInterval queuedAt = NSDate.date.timeIntervalSince1970;
    // 0.0.125: hold the SHARED cache and SHARED pending set strongly - the work
    // must complete its bookkeeping even if this picker is deallocated first
    // (weakSelf alone would no-op the cache write and leak the pending entry,
    // which would permanently skip-pending the row in every future picker).
    NSCache<NSString *, UIImage *> *sharedCache = self.thumbnails;
    NSMutableSet<NSString *> *sharedPending = self.pending;
    __weak typeof(self) weakSelf = self;
    [self.thumbnailQueue addOperationWithBlock:^{
        @autoreleasepool {
            // Settings imports publish this poster; old files decode only on cache miss.
            NSTimeInterval startedAt = NSDate.date.timeIntervalSince1970;
            LMVThumbnailLog([NSString stringWithFormat:@"worker-start waitMs=%.1f", (startedAt - queuedAt) * 1000], relative, nil);
            UIImage *poster = LMVEnsureThumbnail(relative, key);
            LMVThumbnailLog([NSString stringWithFormat:@"worker-finish poster=%d elapsedMs=%.1f", poster != nil,
                (NSDate.date.timeIntervalSince1970 - startedAt) * 1000], relative, nil);
            NSUInteger cost = poster.CGImage ? CGImageGetBytesPerRow(poster.CGImage) * CGImageGetHeight(poster.CGImage) : 0;
            // Land the poster in the SHARED cache even if this picker was closed
            // while the decode ran - the next open, here or in the floating panel,
            // starts warm. Never cache the film symbol as if it were a poster.
            if (poster) [sharedCache setObject:poster forKey:key cost:cost];
            [sharedPending removeObject:key];
            dispatch_async(dispatch_get_main_queue(), ^{
                LMVMaterialPicker *picker = weakSelf;
                if (!picker) return;
                [picker tracePreview:poster ? @"apply-poster" : @"apply-placeholder" row:row];
                if (poster) [picker.thumbnailFailures removeObjectForKey:key];
                else { picker.thumbnailFailures[key] = @(failures + 1);
                       [picker scheduleRetryForKey:key]; }
                // Resolve current paths, never capture/reuse a cell from a previous generation.
                for (NSIndexPath *index in picker.tableView.indexPathsForVisibleRows) {
                    if (index.row < picker.materials.count) {
                        NSDictionary *visible = picker.materials[index.row];
                        if ([visible[@"revision"] isEqualToString:key]) { if (poster || [sharedCache objectForKey:key]) [picker.tableView reloadRowsAtIndexPaths:@[index] withRowAnimation:UITableViewRowAnimationNone]; else [picker requestThumbnail:visible]; }
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
    BOOL pending = !none && ![self.thumbnails objectForKey:row[@"revision"]] && [self thumbnailIsPending:row];
    cell.detailTextLabel.text = current ? @"使用中" : (pending ? @"生成中…" : nil);
    cell.accessoryType = current ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    ((LMVMaterialCell *)cell).showsThumbnail=self.showsThumbnails;
    // 0.0.124: three states, not two. Film means "this really failed"; a poster
    // that is merely not ready yet (typical right after an import) shows a
    // progress glyph so it is not mistaken for a broken entry.
    UIImage *poster = none ? nil : [self.thumbnails objectForKey:row[@"revision"]];
    cell.imageView.image = self.showsThumbnails ? (none ? [UIImage systemImageNamed:@"nosign"] :
        poster ?: [UIImage systemImageNamed:pending ? @"arrow.triangle.2.circlepath" : @"film"]) : nil;
    cell.imageView.contentMode = UIViewContentModeScaleAspectFill;
    cell.imageView.clipsToBounds = YES;
    cell.imageView.layer.cornerRadius = 6;
    cell.imageView.bounds = CGRectMake(0, 0, 56, 56);
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@%@", cell.textLabel.text, current ? @"，使用中" : @""];
    if (!none && self.showsThumbnails) {
        [self tracePreview:[self.thumbnails objectForKey:row[@"revision"]] ? @"display-poster" : @"display-placeholder" row:row];
        [self requestThumbnail:row];
    }
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
