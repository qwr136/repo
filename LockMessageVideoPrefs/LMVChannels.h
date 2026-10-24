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
static NSArray<NSDictionary *> *LMVChannelTable(void) {
    static NSArray<NSDictionary *> *rows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        rows = @[
            @{@"id": @"Message",            @"title": @"消息背景",             @"card": @YES, @"section": @YES, @"legacy": @"message.mov"},
            @{@"id": @"Options",            @"title": @"选项背景",             @"card": @YES, @"section": @YES, @"legacy": @"options.mov"},
            @{@"id": @"Clear",              @"title": @"清除背景",             @"card": @YES, @"section": @YES, @"legacy": @"clear.mov"},
            @{@"id": @"LockScreen",         @"title": @"锁屏背景",             @"card": @NO,  @"section": @YES, @"legacy": @""},
            @{@"id": @"Desktop",            @"title": @"桌面背景",             @"card": @NO,  @"section": @YES, @"legacy": @""},
            @{@"id": @"ControlCenterDark",  @"title": @"控制中心深色背景",      @"card": @NO,  @"section": @NO,  @"legacy": @""},
            @{@"id": @"ControlCenterLight", @"title": @"控制中心浅色背景",      @"card": @NO,  @"section": @NO,  @"legacy": @""},
            @{@"id": @"HomeMenu",           @"title": @"桌面长按菜单视频背景",  @"card": @NO,  @"section": @NO,  @"legacy": @""},
            @{@"id": @"SquidPanel",         @"title": @"鱿鱼面板背景视频",      @"card": @NO,  @"section": @NO,  @"legacy": @""},
            @{@"id": @"AT",                 @"title": @"AT 背景视频",          @"card": @NO,  @"section": @NO,  @"legacy": @""},
            @{@"id": @"CV",                 @"title": @"CopyVault 面板背景视频", @"card": @NO, @"section": @NO,  @"legacy": @""},
            @{@"id": @"Myrtle",             @"title": @"Myrtle 面板背景视频",   @"card": @NO,  @"section": @NO,  @"legacy": @""},
            @{@"id": @"PA",                 @"title": @"电话助手弹窗背景视频",  @"card": @NO,  @"section": @NO,  @"legacy": @""},
            @{@"id": @"GS",                 @"title": @"GlassSuiteX 弹窗背景视频", @"card": @NO, @"section": @NO, @"legacy": @""},
            @{@"id": @"CCBorder",           @"title": @"CCBorder 视频背景",     @"card": @NO,  @"section": @NO,  @"legacy": @""},
            @{@"id": @"CopyLogX",           @"title": @"CopyLogX 视频背景",     @"card": @NO,  @"section": @NO,  @"legacy": @""},
        ];
    });
    return rows;
}

// Cached projections: LMVCardTargets() runs in refresh loops, so these must not
// allocate a new array on every call.
static NSArray<NSString *> *LMVChannelIDsMatching(NSString *flag) {
    NSMutableArray *ids = [NSMutableArray new];
    for (NSDictionary *row in LMVChannelTable())
        if (!flag || [row[flag] boolValue]) [ids addObject:row[@"id"]];
    return [ids copy];
}
static NSArray<NSString *> *LMVChannelIDs(void) {
    static NSArray<NSString *> *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = LMVChannelIDsMatching(nil); });
    return value;
}
static NSArray<NSString *> *LMVCardChannelIDs(void) {
    static NSArray<NSString *> *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = LMVChannelIDsMatching(@"card"); });
    return value;
}
static NSArray<NSString *> *LMVSectionChannelIDs(void) {
    static NSArray<NSString *> *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ value = LMVChannelIDsMatching(@"section"); });
    return value;
}
static NSDictionary<NSString *, NSString *> *LMVChannelTitles(void) {
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
static NSDictionary<NSString *, NSString *> *LMVChannelLegacyDefaults(void) {
    static NSDictionary *value;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *defaults = [NSMutableDictionary new];
        for (NSDictionary *row in LMVChannelTable()) defaults[row[@"id"]] = row[@"legacy"] ?: @"";
        value = [defaults copy];
    });
    return value;
}
static NSDictionary<NSString *, NSString *> *LMVCardLegacyDefaults(void) {
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
