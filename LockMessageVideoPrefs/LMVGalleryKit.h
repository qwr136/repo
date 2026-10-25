#pragma once
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <PhotosUI/PhotosUI.h>
#import "LMVChannels.h"
#import "LMVMaterialStorage.h"
#import "LMVMaterialCatalog.h"
#import "LMVThumbnailDiagnosticLog.h"
#import "LMVMaterialThumbnail.h"
#import "../LMVTextColorPicker.h"

// 4.3.0: shared plumbing for the gallery-style settings pages. Everything the two
// new controllers need (preference access, channel metadata, cover loading and the
// material catalog) lives here so the pages themselves stay layout-only.
// The classic PSListController remains untouched and reachable from 「更多」.

static NSString *const kLMVGalleryPrefsID = @"com.minis.lockmessagevideo";

static inline id LMVGPrefObject(NSString *key) {
    if (![key isKindOfClass:NSString.class] || !key.length) return nil;
    return (__bridge_transfer id)CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                           (__bridge CFStringRef)kLMVGalleryPrefsID);
}
static inline void LMVGPrefSet(NSString *key, id value) {
    if (![key isKindOfClass:NSString.class] || !key.length) return;
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value,
                             (__bridge CFStringRef)kLMVGalleryPrefsID);
}
static inline BOOL LMVGPrefBool(NSString *key, BOOL fallback) {
    id value = LMVGPrefObject(key);
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}
static inline double LMVGPrefDouble(NSString *key, double fallback) {
    id value = LMVGPrefObject(key);
    double raw = [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
    return isfinite(raw) ? raw : fallback;
}
// Per-channel notifications are the contract the tweak listens on; a channel write
// must never fall back to the global name or every panel wakes up.
static inline void LMVGNotifyChannel(NSString *target) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kLMVGalleryPrefsID);
    NSString *name = target.length
        ? [NSString stringWithFormat:@"com.minis.lockmessagevideo/preferencesChanged.%@", target]
        : @"com.minis.lockmessagevideo/preferencesChanged";
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)name, NULL, NULL, YES);
}

static inline NSDictionary *LMVGChannelRow(NSString *identifier) {
    for (NSDictionary *row in LMVChannelTable())
        if ([row[@"id"] isEqualToString:identifier]) return row;
    return nil;
}
static inline NSString *LMVGChannelTitle(NSString *identifier) {
    return LMVGChannelRow(identifier)[@"title"] ?: identifier;
}
static inline NSArray<NSString *> *LMVGSceneIDs(void) {
    return LMVSectionChannelIDs();
}
static inline NSArray<NSString *> *LMVGPanelIDs(void) {
    NSMutableArray *ids = [NSMutableArray new];
    for (NSDictionary *row in LMVChannelTable())
        if ([row[@"standalone"] boolValue]) [ids addObject:row[@"id"]];
    return ids;
}
static inline NSUInteger LMVGEnabledCount(void) {
    NSUInteger count = 0;
    for (NSString *identifier in LMVChannelIDs())
        if (LMVGPrefBool([identifier stringByAppendingString:@"BackgroundEnabled"], NO)) count++;
    return count;
}

// The preference stores the relative path; pre-1.x installs may only have the
// legacy file with no key, so the channel table's legacy column is the fallback.
static inline NSString *LMVGSelectedMaterial(NSString *identifier) {
    id value = LMVGPrefObject([identifier stringByAppendingString:@"Video"]);
    if ([value isKindOfClass:NSString.class] && [value length]) return value;
    NSString *legacy = LMVGChannelRow(identifier)[@"legacy"];
    if (![legacy isKindOfClass:NSString.class] || !legacy.length) return @"";
    NSString *absolute = [LMVStorageRootPath stringByAppendingPathComponent:legacy];
    return [NSFileManager.defaultManager fileExistsAtPath:absolute] ? legacy : @"";
}
static inline NSString *LMVGMaterialName(NSString *relative) {
    if (![relative isKindOfClass:NSString.class] || !relative.length) return @"未选择素材";
    NSDictionary *names = LMVReadMaterialNames();
    NSDictionary *attributes = [NSFileManager.defaultManager
        attributesOfItemAtPath:[LMVStorageRootPath stringByAppendingPathComponent:relative] error:nil];
    return LMVMaterialDisplayName(relative, names, attributes, 0);
}

static inline NSString *LMVGSymbolForChannel(NSString *identifier) {
    static NSDictionary *symbols;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        symbols = @{
            @"Message": @"message.fill", @"Options": @"list.bullet",
            @"Clear": @"xmark.circle", @"LockScreen": @"lock.fill",
            @"Desktop": @"desktopcomputer", @"ControlCenterDark": @"slider.horizontal.3",
            @"ControlCenterLight": @"slider.horizontal.3", @"HomeMenu": @"hand.tap",
            @"SquidPanel": @"square.grid.2x2", @"AT": @"phone.badge.waveform",
            @"CV": @"doc.on.clipboard", @"Myrtle": @"rectangle.stack",
            @"PA": @"phone.fill", @"GS": @"square.stack.3d.up",
            @"CCBorder": @"rectangle.on.rectangle", @"CopyLogX": @"doc.on.doc",
        };
    });
    NSString *name = symbols[identifier] ?: @"square.fill";
    // hand.tap needs iOS 14; the bundle targets 15, but keep a defensive fallback
    // for symbols that a future build drops.
    if (![UIImage systemImageNamed:name]) name = @"square.fill";
    return name;
}

static inline NSArray<UIColor *> *LMVGPalette(NSString *identifier) {
    static NSArray<NSArray<UIColor *> *> *palettes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        palettes = @[
            @[[UIColor colorWithRed:0.17 green:0.30 blue:0.50 alpha:1], [UIColor colorWithRed:0.48 green:0.35 blue:0.66 alpha:1], [UIColor colorWithRed:0.77 green:0.44 blue:0.54 alpha:1]],
            @[[UIColor colorWithRed:0.06 green:0.23 blue:0.27 alpha:1], [UIColor colorWithRed:0.18 green:0.56 blue:0.48 alpha:1], [UIColor colorWithRed:0.66 green:0.85 blue:0.69 alpha:1]],
            @[[UIColor colorWithRed:0.23 green:0.11 blue:0.18 alpha:1], [UIColor colorWithRed:0.56 green:0.23 blue:0.35 alpha:1], [UIColor colorWithRed:0.88 green:0.63 blue:0.42 alpha:1]],
            @[[UIColor colorWithRed:0.10 green:0.12 blue:0.23 alpha:1], [UIColor colorWithRed:0.29 green:0.35 blue:0.62 alpha:1], [UIColor colorWithRed:0.66 green:0.75 blue:0.91 alpha:1]],
            @[[UIColor colorWithRed:0.14 green:0.16 blue:0.11 alpha:1], [UIColor colorWithRed:0.36 green:0.48 blue:0.23 alpha:1], [UIColor colorWithRed:0.78 green:0.85 blue:0.60 alpha:1]],
            @[[UIColor colorWithRed:0.17 green:0.10 blue:0.23 alpha:1], [UIColor colorWithRed:0.42 green:0.23 blue:0.56 alpha:1], [UIColor colorWithRed:0.77 green:0.60 blue:0.88 alpha:1]],
        ];
    });
    NSUInteger hash = 0;
    for (NSUInteger i = 0; i < identifier.length; i++) hash = hash * 31 + [identifier characterAtIndex:i];
    return palettes[hash % palettes.count];
}
static inline void LMVGApplyGradient(CALayer *layer, NSString *identifier) {
    if (![layer isKindOfClass:CAGradientLayer.class]) return;
    NSArray<UIColor *> *palette = LMVGPalette(identifier);
    CAGradientLayer *gradient = (CAGradientLayer *)layer;
    gradient.colors = @[(id)palette[0].CGColor, (id)palette[1].CGColor, (id)palette[2].CGColor];
    gradient.locations = @[@0.0, @0.55, @1.0];
    gradient.startPoint = CGPointMake(0.1, 0.0);
    gradient.endPoint = CGPointMake(0.9, 1.0);
}

// Covers are generated off the main thread (first frame extraction is expensive)
// and cached on disk by LMVEnsureThumbnail, so a revisit is just a file read.
static inline void LMVGLoadCover(NSString *relative, void (^completion)(UIImage *image)) {
    if (!completion) return;
    if (![relative isKindOfClass:NSString.class] || !relative.length) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil); });
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *revision = LMVThumbnailRevision(relative);
        UIImage *image = revision ? LMVEnsureThumbnail(relative, revision) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(image); });
    });
}

// Same catalog rules as LMVMaterialPicker: legacy files first, then the library
// folder, deduplicated, live files only, names resolved through the catalog.
static inline void LMVGLoadMaterials(void (^completion)(NSArray<NSDictionary *> *rows)) {
    if (!completion) return;
    dispatch_async(LMVMaterialQueue(), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *base = LMVStorageRootPath;
        NSArray *library = [[fm contentsOfDirectoryAtPath:[base stringByAppendingPathComponent:LMVLibrarySubfolder] error:nil]
                            sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
        NSMutableArray *paths = [NSMutableArray new];
        for (NSString *legacy in LMVLegacyMaterialNames())
            if ([fm fileExistsAtPath:[base stringByAppendingPathComponent:legacy]]) [paths addObject:legacy];
        NSMutableOrderedSet *unique = [NSMutableOrderedSet orderedSetWithArray:paths];
        for (NSString *file in library)
            if ([@[@"mov", @"mp4", @"m4v"] containsObject:file.pathExtension.lowercaseString])
                [unique addObject:[LMVLibrarySubfolder stringByAppendingPathComponent:file]];
        NSMutableDictionary *names = LMVReadMaterialNames();
        NSMutableDictionary *displayNames = [names mutableCopy];
        NSMutableArray *rows = [NSMutableArray new];
        for (NSString *relative in unique) {
            NSDictionary *attributes = [fm attributesOfItemAtPath:[base stringByAppendingPathComponent:relative] error:nil];
            if (![attributes[NSFileType] isEqualToString:NSFileTypeRegular]) continue;
            NSString *name = LMVMaterialDisplayName(relative, displayNames, attributes, rows.count);
            displayNames[relative] = name;
            NSString *revision = LMVThumbnailRevision(relative);
            if (revision) [rows addObject:@{@"path": relative, @"name": name, @"revision": revision}];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(rows); });
    });
}

// Channel -> text-colour picker key, taken from the channel table's textColor column
// and the picker's own key constants. "" means the channel has no colour row.
static inline NSString *LMVGTextColorKey(NSString *identifier) {
    NSString *row = LMVGChannelRow(identifier)[@"textColor"];
    if (![row isKindOfClass:NSString.class] || !row.length) return @"";
    static NSDictionary *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @{@"SquidTextColor": LMVSquidTextColorKey,
                 @"CVTextColor": LMVTextColorKey,
                 @"PATextColor": LMVPhoneAssistTextColorKey,
                 @"GSTextColor": LMVGlassSuiteTextColorKey,
                 @"CopyLogXTextColor": LMVCopyLogXTextColorKey};
    });
    return keys[row] ?: @"";
}
static inline NSString *LMVGTextColorRowTitle(NSString *identifier) {
    NSString *row = LMVGChannelRow(identifier)[@"textColor"];
    if (![row isKindOfClass:NSString.class] || !row.length) return @"";
    static NSDictionary *titles;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        titles = @{@"SquidTextColor": @"鱿鱼面板文字颜色",
                   @"CVTextColor": @"CopyVault 文字颜色",
                   @"PATextColor": @"电话助手文字颜色",
                   @"GSTextColor": @"GlassSuiteX 文字颜色",
                   @"CopyLogXTextColor": @"CopyLogX 文字颜色"};
    });
    return titles[row] ?: @"文字颜色";
}

static inline UIButton *LMVGRoundButton(NSString *symbol, id target, SEL action) {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *image = [UIImage systemImageNamed:symbol];
    [button setImage:image forState:UIControlStateNormal];
    button.tintColor = UIColor.labelColor;
    button.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    button.layer.cornerRadius = 18;
    button.layer.cornerCurve = kCACornerCurveContinuous;
    button.translatesAutoresizingMaskIntoConstraints = NO;
    [button.widthAnchor constraintEqualToConstant:36].active = YES;
    [button.heightAnchor constraintEqualToConstant:36].active = YES;
    if (target) [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
static inline UILabel *LMVGLabel(NSString *text, UIFont *font, UIColor *color) {
    UILabel *label = [UILabel new];
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}
static inline UIFont *LMVGFont(CGFloat size, UIFontWeight weight) {
    UIFont *font = [UIFont systemFontOfSize:size weight:weight];
    return [[UIFontMetrics defaultMetrics] scaledFontForFont:font];
}
static inline UIView *LMVGSpacer(void) {
    UIView *view = [UIView new];
    view.translatesAutoresizingMaskIntoConstraints = NO;
    return view;
}
