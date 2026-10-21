#import "LMVMenuListController.h"
#import "LMVPRootListController.h"
#import "LMVSettingsVideoController.h"
#import <Preferences/PSSpecifier.h>

@implementation LMVMenuListController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"锁屏背景视频";
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *rows = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"视频背景"];
    [group setProperty:@"桌面视频背景里是原有的全部设置；设置视频背景是设置 App 自身的视频背景。" forKey:@"footerText"];
    [rows addObject:group];
    PSSpecifier *desktop = [PSSpecifier preferenceSpecifierNamed:@"桌面视频背景"
                                                          target:self set:nil get:nil
                                                          detail:nil cell:PSButtonCell edit:nil];
    desktop.buttonAction = @selector(openDesktop:);
    [rows addObject:desktop];
    PSSpecifier *settings = [PSSpecifier preferenceSpecifierNamed:@"设置视频背景"
                                                           target:self set:nil get:nil
                                                           detail:nil cell:PSButtonCell edit:nil];
    settings.buttonAction = @selector(openSettingsVideo:);
    [rows addObject:settings];
    _specifiers = rows;
    return _specifiers;
}

- (void)openDesktop:(PSSpecifier *)specifier {
    [self.navigationController pushViewController:[LMVPRootListController new] animated:YES];
}

- (void)openSettingsVideo:(PSSpecifier *)specifier {
    [self.navigationController pushViewController:[LMVSettingsVideoController new] animated:YES];
}

@end
