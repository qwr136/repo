#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>

// TIM 防撤回：拦截「撤回指令的本地处理」，让别人的撤回包不被执行，消息留在会话里。
//
// 为什么不用 %hook 直接写类名？
//   TIM/QQ 的代码经过混淆，类名方法名各版本都不一样，写死类名在新版本上必然失效。
//   所以这里改用「运行时扫描 + 关键词匹配 + 按返回类型替换实现」的通用方式：
//   只要方法名里带 revoke/recall，且看起来是「处理/接收」端（不是发起撤回、不是 UI），就替换成空实现。
//
// 诊断日志：/var/mobile/Documents/TIM防撤回日志.txt
//   第一次装上后，让别人给你发条消息再撤回，然后把日志发出来，就能按真实类名做精确适配。

#define kTRPrefsFile @"/var/mobile/Library/Preferences/com.xiaofei.timantirevoke.plist"
#define kTRLogFile   @"/var/mobile/Documents/TIM防撤回日志.txt"

#pragma mark - 偏好与日志

static NSDictionary *_trPrefs(void) {
    return [NSDictionary dictionaryWithContentsOfFile:kTRPrefsFile] ?: @{};
}

// 防撤回总开关：默认开启
static BOOL TREnabled(void) {
    @try {
        id v = _trPrefs()[@"TRAntiRevokeEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return YES;
}

// 日志开关：默认开启（首版需要靠日志定位真实类名）
static BOOL TRLogEnabled(void) {
    @try {
        id v = _trPrefs()[@"TRLogEnabled"];
        if ([v respondsToSelector:@selector(boolValue)]) { return [v boolValue]; }
    } @catch (NSException *e) {}
    return YES;
}

static void TRLog(NSString *line) {
    if (!TRLogEnabled()) { return; }
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:kTRLogFile]) {
            [@"TIM 防撤回日志\n" writeToFile:kTRLogFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:kTRLogFile];
        if (!h) { return; }
        [h seekToEndOfFile];
        static NSDateFormatter *fmt = nil;
        if (!fmt) { fmt = [[NSDateFormatter alloc] init]; fmt.dateFormat = @"MM-dd HH:mm:ss"; }
        NSString *ts = [fmt stringFromDate:[NSDate date]];
        [h writeData:[[NSString stringWithFormat:@"[%@] %@\n", ts, line] dataUsingEncoding:NSUTF8StringEncoding]];
        [h closeFile];
    } @catch (NSException *e) {}
}

#pragma mark - 拦截实现（按返回类型分派，避免 ABI 崩溃）

static int gHitCount = 0;   // 触发次数：前 50 次写日志，之后静默（省 IO）

static void TRNoteHit(const char *kind) {
    gHitCount++;
    if (gHitCount <= 50) {
        TRLog([NSString stringWithFormat:@"拦截生效(%s) 第%d次", kind, gHitCount]);
    } else if (gHitCount == 51) {
        TRLog(@"拦截持续生效，后续不再逐条记录（正常）");
    }
}

// void 返回：什么都不做
static void TRNoopVoid(id self, SEL _cmd) {
    @try { TRNoteHit("void"); } @catch (NSException *e) {}
}

// BOOL/int 返回：返回 NO/0，表示「这个撤回我没处理」
static BOOL TRNoopBool(id self, SEL _cmd) {
    @try { TRNoteHit("bool"); } @catch (NSException *e) {}
    return NO;
}

// 对象返回：返回 nil
static id TRNoopObj(id self, SEL _cmd) {
    @try { TRNoteHit("obj"); } @catch (NSException *e) {}
    return nil;
}

#pragma mark - 关键词匹配

// 方法名是否像「处理/接收撤回」——必须避开「发起撤回」和 UI 展示，
// 否则自己撤不回消息、或者撤回提示界面出问题
static BOOL TRSelHit(NSString *sel, BOOL strict) {
    if (sel.length == 0) { return NO; }
    NSString *low = [sel lowercaseString];
    if (!([low containsString:@"revoke"] || [low containsString:@"recall"])) { return NO; }

    // 一律排除：发起撤回 / 请求撤回 / 能否撤回 / UI 展示 / 提示文案
    static NSArray *bad = nil;
    if (!bad) {
        bad = @[@"send", @"request", @"post", @"upload", @"can", @"isable", @"should",
                @"allow", @"enable", @"create", @"tip", @"cell", @"view", @"label",
                @"button", @"alert", @"prompt", @"string", @"text", @"count", @"icon",
                @"image", @"color", @"height", @"width", @"frame", @"time", @"date"];
    }
    for (NSString *b in bad) {
        if ([low containsString:b]) { return NO; }
    }

    if (!strict) { return YES; }

    // strict 模式（全量兜底扫描用）：还要看起来像处理端
    static NSArray *good = nil;
    if (!good) {
        good = @[@"handle", @"on", @"deal", @"process", @"recv", @"receive",
                 @"notify", @"update", @"remove", @"delete", @"clear", @"msg", @"message"];
    }
    for (NSString *g in good) {
        if ([low containsString:g]) { return YES; }
    }
    return NO;
}

#pragma mark - 扫描并替换

static void TRHookMethodsOfClass(Class c, BOOL strict, NSMutableArray *hits) {
    if (!c) { return; }
    NSString *cn = NSStringFromClass(c) ?: @"?";
    unsigned n = 0;
    Method *ms = class_copyMethodList(c, &n);
    if (!ms) { return; }
    for (unsigned i = 0; i < n; i++) {
        Method m = ms[i];
        if (!m) { continue; }
        SEL s = method_getName(m);
        NSString *sn = NSStringFromSelector(s);
        if (!TRSelHit(sn, strict)) { continue; }

        char rt[16] = {0};
        method_getReturnType(m, rt, sizeof(rt));
        IMP imp = NULL;
        if (rt[0] == 'v')                                  { imp = (IMP)TRNoopVoid; }
        else if (rt[0] == 'B' || rt[0] == 'c' || rt[0] == 'i') { imp = (IMP)TRNoopBool; }
        else if (rt[0] == '@')                             { imp = (IMP)TRNoopObj; }
        else {
            TRLog([NSString stringWithFormat:@"跳过(返回类型不支持) %@ %@ rt=%s", cn, sn, rt]);
            continue;
        }
        method_setImplementation(m, imp);
        [hits addObject:[NSString stringWithFormat:@"%@ %@", cn, sn]];
        TRLog([NSString stringWithFormat:@"已拦截 %@ %@ (返回 %s)", cn, sn, rt]);
    }
    free(ms);
}

// 第一轮：只扫类名里带 revoke/recall 的类（快，命中率最高）
static NSMutableArray *TRScanByClassName(void) {
    NSMutableArray *hits = [NSMutableArray array];
    int num = objc_getClassList(NULL, 0);
    if (num <= 0) { return hits; }
    Class *cs = (Class *)malloc(sizeof(Class) * (size_t)num);
    num = objc_getClassList(cs, num);
    for (int i = 0; i < num; i++) {
        @autoreleasepool {
            NSString *low = [NSStringFromClass(cs[i]) lowercaseString];
            if ([low containsString:@"revoke"] || [low containsString:@"recall"]) {
                TRLog([NSString stringWithFormat:@"发现撤回相关类: %@", NSStringFromClass(cs[i])]);
                TRHookMethodsOfClass(cs[i], NO, hits);
            }
        }
    }
    free(cs);
    return hits;
}

// 第二轮兜底：类名被混淆时按方法名全量扫（strict，避免误伤）
static NSMutableArray *TRScanAllClasses(void) {
    NSMutableArray *hits = [NSMutableArray array];
    int num = objc_getClassList(NULL, 0);
    if (num <= 0) { return hits; }
    Class *cs = (Class *)malloc(sizeof(Class) * (size_t)num);
    num = objc_getClassList(cs, num);
    static NSArray *sysPrefix = nil;
    if (!sysPrefix) {
        sysPrefix = @[@"NS", @"UI", @"CA", @"CG", @"CF", @"_", @"OS", @"AV", @"CL", @"MK",
                      @"SK", @"PH", @"WK", @"QL", @"GK", @"NE", @"PK", @"SC", @"TK", @"MT", @"CN"];
    }
    for (int i = 0; i < num; i++) {
        @autoreleasepool {
            NSString *cn = NSStringFromClass(cs[i]);
            if (cn.length == 0) { continue; }
            BOOL skip = NO;
            for (NSString *p in sysPrefix) {
                if ([cn hasPrefix:p]) { skip = YES; break; }
            }
            if (skip) { continue; }   // 系统类直接跳过，省时间也避免误伤
            TRHookMethodsOfClass(cs[i], YES, hits);
        }
    }
    free(cs);
    return hits;
}

#pragma mark - 入口

%ctor {
    @autoreleasepool {
        @try {
            TRLog(@"===== TIM 防撤回 加载 =====");
            TRLog([NSString stringWithFormat:@"进程: %@ 开关=%d",
                   [[NSBundle mainBundle] bundleIdentifier] ?: @"?", TREnabled()]);

            if (!TREnabled()) {
                TRLog(@"开关关闭，本次不生效");
                return;
            }

            NSMutableArray *hits = TRScanByClassName();
            TRLog([NSString stringWithFormat:@"第一轮(类名匹配) 拦截 %lu 个方法", (unsigned long)hits.count]);

            if (hits.count == 0) {
                // 类名被混淆，3 秒后按方法名全量兜底扫（延迟执行，不影响 TIM 启动速度）
                TRLog(@"第一轮未命中（类名可能被混淆），3 秒后全量扫描方法名…");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                               dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    @try {
                        NSMutableArray *h2 = TRScanAllClasses();
                        TRLog([NSString stringWithFormat:@"第二轮(方法名兜底) 拦截 %lu 个方法",
                               (unsigned long)h2.count]);
                        if (h2.count == 0) {
                            TRLog(@"两轮都没命中：请把本日志发给我，按你的 TIM 版本做精确适配");
                        }
                    } @catch (NSException *e) {}
                });
            } else {
                TRLog(@"防撤回已就绪：别人撤回消息时应当不再消失");
            }
        } @catch (NSException *e) {
            TRLog([NSString stringWithFormat:@"ctor 异常: %@", e]);
        }
    }
}
