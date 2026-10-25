#pragma once
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

// 4.0.7: THE channel table. Before this, the same list lived in five places
// (tweak card targets, notification registration, deletion sweep, settings
// allow-list, alert titles). Adding a channel meant editing all five, and two
// shipped bugs (4.0.2 missing notifications, 4.0.4 missing deletion keys) were
// exactly that miss. Every consumer now derives from here.
//
//  id       preference prefix: <id>Video, <id>BackgroundEnabled, Tune.<id>.*
//  title    user-facing name shown in alerts and section headers
//  card     presented on a notification card (Tweak.xm card pipeline)
//  section  belongs to the five fixed sections of the settings page
//  legacy   pre-1.x file name used when the key is absent ("" = none)
//
// 4.2.0: four columns describe how the settings page lays a channel out. They used
// to be encoded in the page itself - nine hand-written blocks plus sixteen action
// methods - so adding a channel meant touching all of them and forgetting one left
// the new panel with a missing row. The page is now generated from these columns.
//  audio      the channel has a "play sound" switch and a volume slider
//  textColor  id of the text-colour row ("" = the channel has none)
//  footer     section footer text ("" = none)
//  standalone the channel gets its own section below the control-centre one
//             (the five fixed sections and the two control-centre halves do not)
static inline NSArray<NSDictionary *> *LMVChannelTable(void) {
    static NSArray<NSDictionary *> *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rows = @[
            @{@"id": @"Message",            @"title": @"消息背景",             @"card": @YES, @"section": @YES, @"legacy": @"message.mov", @"legacyTitle": @"原消息视频", @"audio": @NO, @"textColor": @"", @"footer": @"", @"standalone": @NO},
            @{@"id": @"Options",            @"title": @"选项背景",             @"card": @YES, @"section": @YES, @"legacy": @"options.mov", @"legacyTitle": @"原选项视频", @"audio": @NO, @"textColor": @"", @"footer": @"", @"standalone": @NO},
            @{@"id": @"Clear",              @"title": @"清除背景",             @"card": @YES, @"section": @YES, @"legacy": @"clear.mov", @"legacyTitle": @"原清除视频", @"audio": @NO, @"textColor": @"", @"footer": @"", @"standalone": @NO},
            @{@"id": @"LockScreen",         @"title": @"锁屏背景",             @"card": @NO,  @"section": @YES, @"legacy": @"", @"audio": @NO, @"textColor": @"", @"footer": @"", @"standalone": @NO},
            @{@"id": @"Desktop",            @"title": @"桌面背景",             @"card": @NO,  @"section": @YES, @"legacy": @"", @"audio": @NO, @"textColor": @"", @"footer": @"", @"standalone": @NO},
            @{@"id": @"ControlCenterDark",  @"title": @"控制中心深色背景",      @"card": @NO,  @"section": @NO,  @"legacy": @"", @"audio": @YES, @"textColor": @"", @"footer": @"", @"standalone": @NO},
            @{@"id": @"ControlCenterLight", @"title": @"控制中心浅色背景",      @"card": @NO,  @"section": @NO,  @"legacy": @"", @"audio": @YES, @"textColor": @"", @"footer": @"", @"standalone": @NO},
            @{@"id": @"HomeMenu",           @"title": @"长按菜单背景",  @"card": @NO,  @"section": @NO,  @"legacy": @"", @"audio": @YES, @"textColor": @"", @"footer": @"", @"standalone": @YES},
            @{@"id": @"SquidPanel",         @"title": @"SquidGesture Pro背景",      @"card": @NO,  @"section": @NO,  @"legacy": @"", @"audio": @YES, @"textColor": @"SquidTextColor", @"footer": @"", @"standalone": @YES},
            @{@"id": @"AT",                 @"title": @"AppTools背景",          @"card": @NO,  @"section": @NO,  @"legacy": @"", @"audio": @YES, @"textColor": @"", @"footer": @"", @"standalone": @YES},
            @{@"id": @"CV",                 @"title": @"CopyVault背景", @"card": @NO, @"section": @NO,  @"legacy": @"", @"audio": @YES, @"textColor": @"CVTextColor", @"footer": @"", @"standalone": @YES},
            @{@"id": @"Myrtle",             @"title": @"Myrtle背景",   @"card": @NO,  @"section": @NO,  @"legacy": @"", @"audio": @YES, @"textColor": @"", @"footer": @"", @"standalone": @YES},
            @{@"id": @"PA",                 @"title": @"电话助手背景",  @"card": @NO,  @"section": @NO,  @"legacy": @"", @"audio": @YES, @"textColor": @"PATextColor", @"footer": @"", @"standalone": @YES},
            @{@"id": @"GS",                 @"title": @"GlassSuiteX背景", @"card": @NO, @"section": @NO, @"legacy": @"", @"audio": @YES, @"textColor": @"GSTextColor", @"footer": @"开启诊断日志后，挂载状态会写入 shared-render.log（gs-panel 行）。", @"standalone": @YES},
            @{@"id": @"CCBorder",           @"title": @"CCBorder背景",     @"card": @NO,  @"section": @NO,  @"legacy": @"", @"audio": @YES, @"textColor": @"", @"footer": @"控制中心长按菜单的背景视频；诊断日志会带 module= 标识。", @"standalone": @YES},
            @{@"id": @"CopyLogX",           @"title": @"CopyLogX背景",     @"card": @NO,  @"section": @NO,  @"legacy": @"", @"audio": @YES, @"textColor": @"CopyLogXTextColor", @"footer": @"剪贴板面板（411×470 底部卡片）的背景视频；诊断日志会写入 clx-panel。", @"standalone": @YES},
        ];
    });
    return rows;
}

// Cached projections: LMVCardTargets() runs in refresh loops, so these must not
// allocate a new array on every call.
static inline NSArray<NSString *> *LMVChannelIDsMatching(NSString *flag) {
    NSMutableArray *ids = [NSMutableArray new];
    for (NSDictionary *row in LMVChannelTable())
        if (!flag || [row[flag] boolValue]) [ids addObject:row[@"id"]];
    return [ids copy];
}
static inline NSArray<NSString *> *LMVChannelIDs(void) {
    static NSArray<NSString *> *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = LMVChannelIDsMatching(nil); });
    return value;
}
// 4.2.0: the channels whose settings section is generated rather than hand-written.
static inline NSArray<NSDictionary *> *LMVStandaloneChannelRows(void) {
    static NSArray<NSDictionary *> *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *rows = [NSMutableArray new];
        for (NSDictionary *row in LMVChannelTable())
            if ([row[@"standalone"] boolValue]) [rows addObject:row];
        value = [rows copy];
    });
    return value;
}
static inline NSArray<NSString *> *LMVCardChannelIDs(void) {
    static NSArray<NSString *> *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = LMVChannelIDsMatching(@"card"); });
    return value;
}
static inline NSArray<NSString *> *LMVSectionChannelIDs(void) {
    static NSArray<NSString *> *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = LMVChannelIDsMatching(@"section"); });
    return value;
}
static inline NSDictionary<NSString *, NSString *> *LMVChannelTitles(void) {
    static NSDictionary *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *titles = [NSMutableDictionary new];
        for (NSDictionary *row in LMVChannelTable()) titles[row[@"id"]] = row[@"title"];
        value = [titles copy];
    });
    return value;
}
// Only the card channels have ever had a legacy source name; the rest map to "".
static inline NSDictionary<NSString *, NSString *> *LMVChannelLegacyDefaults(void) {
    static NSDictionary *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *defaults = [NSMutableDictionary new];
        for (NSDictionary *row in LMVChannelTable()) defaults[row[@"id"]] = row[@"legacy"] ?: @"";
        value = [defaults copy];
    });
    return value;
}
static inline NSDictionary<NSString *, NSString *> *LMVCardLegacyDefaults(void) {
    static NSDictionary *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *defaults = [NSMutableDictionary new];
        for (NSDictionary *row in LMVChannelTable())
            if ([row[@"card"] boolValue]) defaults[row[@"id"]] = row[@"legacy"] ?: @"";
        value = [defaults copy];
    });
    return value;
}

// 4.0.8: the pre-1.x material names live in the table's "legacy" column, so there
// is exactly one list. Only the three card channels have one.
static inline NSArray<NSString *> *LMVLegacyMaterialNames(void) {
    static NSArray<NSString *> *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *names = [NSMutableArray new];
        for (NSDictionary *row in LMVChannelTable())
            if ([row[@"legacy"] length]) [names addObject:row[@"legacy"]];
        value = [names copy];
    });
    return value;
}
static inline BOOL LMVIsLegacyMaterialName(NSString *name) {
    return [name isKindOfClass:NSString.class] && [LMVLegacyMaterialNames() containsObject:name];
}

// Display name for a pre-1.x file, kept beside the legacy list it describes.
static inline NSDictionary<NSString *, NSString *> *LMVLegacyDisplayNames(void) {
    static NSDictionary *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *names = [NSMutableDictionary new];
        for (NSDictionary *row in LMVChannelTable())
            if ([row[@"legacy"] length] && [row[@"legacyTitle"] length]) names[row[@"legacy"]] = row[@"legacyTitle"];
        value = [names copy];
    });
    return value;
}
