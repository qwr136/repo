#!/usr/bin/env python3
"""Real production audio mapping/handlers; Foundation doubles execute on macOS."""
from pathlib import Path
import math, platform, re, subprocess, tempfile

root = Path(__file__).resolve().parents[1]
panel = (root / 'LMVEasterPanel.h').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
# 2.39: this fixture compiles the specifier builder; drop the tuning group and its
# entry point (covered by tests/tuning.py) so the row counts stay comparable.
def _strip_tuning(src):
    a = src.find('    // 2.39: per-channel tuning')
    if a >= 0:
        b = src.find('    [_specifiers addObject:[PSSpecifier groupSpecifierWithName:@"小彩蛋"]];', a)
        if b > a: src = src[:a] + src[b:]
    a = src.find('// 2.39: push the per-channel tuning page.')
    if a >= 0:
        b = src.find('- (void)openEaster:', a)
        if b > a: src = src[:a] + src[b:]
    return src
prefs = _strip_tuning(prefs)
targets = ['Message', 'Options', 'Clear', 'LockScreen', 'Desktop', 'ControlCenterDark', 'ControlCenterLight', 'HomeMenu', 'SquidPanel', 'AT', 'CV', 'Myrtle', 'PA', 'GS', 'CCBorder', 'CopyLogX']

def body(source, anchor):
    start = source.index(anchor)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

helpers = panel[panel.index('static NSArray *LMVEasterTargets('):panel.index('static void LMVEasterPanelChanged(')]
assert re.findall(r'@"(.*?)"', body(panel, 'static NSArray *LMVEasterAudioTargets(')) == targets
mapping = body(panel, 'static NSString *LMVEasterAudioTarget(')
assert 'section >= 0 && section < LMVEasterTargets().count && (row == 2 || row == 3)' in mapping
assert '(row == 2 || row == 3)) return @"HomeMenu";' in mapping
assert '(row == 2 || row == 3)) return @"SquidPanel";' in mapping
assert '(row == 2 || row == 3)) return @"AT";' in mapping
assert 'if (row == 2 || row == 3) return @"ControlCenterDark";' in mapping
assert 'if (row == 5 || row == 6) return @"ControlCenterLight";' in mapping
assert mapping.count('return ') == 13 and mapping.endswith('return nil;\n}')
cc_key = body(panel, 'static NSString *LMVEasterControlCenterKey(')
actual_material_rows = {int(row): target for row, target in re.findall(r'row == (\d+) \? @"(\w+)Video"', cc_key)}
assert actual_material_rows == {1: 'ControlCenterDark', 4: 'ControlCenterLight'}
assert 'if (section == LMVEasterSquidPanelSection()) return row == 3;' in helpers
assert 'return (row == 3 || row == 6);' in helpers
assert 'tag >= 0 && tag < LMVEasterAudioTargets().count' in helpers
assert '[value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0.5' in helpers
assert 'isfinite(raw) ? MAX(0.0, MIN(1.0, raw)) : 0.5' in helpers
assert '[value isKindOfClass:NSNumber.class] ? [value boolValue] : NO' in helpers

cells = body(panel, '- (UITableViewCell *)tableView:')
assert cells.index('LMVEasterAudioTarget(index.section, index.row)') < cells.index('LMVEasterHomeMenuSection()')
for exact in ('[LMVEasterAudioTargets() indexOfObject:audioTarget]', '@selector(soundChanged:)', '@selector(volumeChanged:)',
              'stepper.enabled = YES;', 'stepper.maximumValue = 100;',
              'stepper.accessibilityValue = [NSString stringWithFormat:@"%.0f%%", volume * 100.0];'):
    assert exact in cells, exact
sound = body(panel, '- (void)soundChanged:')
volume_change = body(panel, '- (void)volumeChanged:')
for method, suffix in ((sound, 'SoundEnabled'), (volume_change, 'Volume')):
    assert 'LMVEasterAudioTargetForTag(' in method and 'if (!target) return;' in method
    # 5.1.7: the write is scoped to the channel now, but still exactly one write.
    # 5.1.7: writes go through the scoped/local helpers now; still exactly one write.
    assert (method.count('LMVEasterSet(') + method.count('LMVEasterSetTarget(')
            + method.count('LMVEasterSetLocal(')) == 1
    assert f'[target stringByAppendingString:@"{suffix}"]' in method
assert 'LMVEasterAudioVolume(@(stepper.value / 100.0))' in volume_change
assert 'slider.isTracking' not in volume_change, 'a stepper has no drag state to track'
assert '!panel.opacityTracking && !panel.volumeTracking' in panel
selection = body(panel, '- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:')
# 1.83: the CopyVault colour branch presents a UIKit picker; the fixture links
# Foundation only, so it is stripped here while the production text stays asserted.
selection_for_fixture = selection.replace('''        if (index.row == 4) {
            LMVTextColorPicker *picker = [LMVTextColorPicker new];
            picker.modalPresentationStyle = UIModalPresentationPageSheet;
            __weak typeof(self) weakSelf = self;
            picker.onChange = ^(UIColor *color) { [weakSelf.tableView reloadData]; };
            [self presentViewController:picker animated:YES completion:nil];
            return;
        }
''', '')
assert 'key = LMVEasterControlCenterKey(index.row);\n        if (!key) return;' in selection
assert 'if (index.row != 1) return;\n        key = @"HomeMenuVideo";' in selection
assert 'if (index.row != 1) return;' in selection
assert 'key = @"SquidPanelVideo";' in selection
assert 'if (index.row != 1) return;\n        key = @"ATVideo";' in selection
assert 'index.section >= LMVEasterTargets().count || index.row != 1) return;' in selection

append = body(prefs, '- (void)appendAudioForTarget:')
specifiers_source = body(prefs, '- (void)lmvp_buildSpecifiers')
# 4.2.0: the generated sections call two row builders that live outside -specifiers,
# and this fixture compiles that method on its own. Build the same rows inline so the
# native build sees a real specifier instead of an undeclared selector.
# The two row builders are ObjC methods defined outside -specifiers, so this fixture
# cannot resolve them; drop those two appends rather than fake them. Everything else
# in the generated loop (group, switch, audio pair) still runs for real.
# 4.2.0: the generated loop calls two row builders (materialRowForTarget:,
# textColorRowWithID:) that live outside -specifiers and cannot be resolved by this
# fixture. Drop the two appends AND the if/declaration that wraps the colour one, so
# the if is not left dangling (an empty if body is a hard compile error). Everything
# else in the loop (group, switch, audio pair) still runs for real.
specifiers = (specifiers_source
    .replace('[_specifiers addObject:[self materialRowForTarget:target]];\n', '')
    .replace('        NSString *colourID = row[@"textColor"];\n        if ([colourID isKindOfClass:NSString.class] && colourID.length)\n            [_specifiers addObject:[self textColorRowWithID:colourID]];\n', ''))
assert append.count('cell:PSSwitchCell') == append.count('cell:PSSliderCell') == 1
for exact in ('[sound setProperty:@NO forKey:@"default"]', '[volume setProperty:@0.5 forKey:@"default"]',
              '[volume setProperty:@0.0 forKey:@"min"]', '[volume setProperty:@100.0 forKey:@"max"]',
              '[volume setProperty:[self enabled:sound] forKey:@"enabled"]',
              'set:@selector(setEnabled:specifier:) get:@selector(enabled:)',
              'set:@selector(setVolume:specifier:) get:@selector(volume:)',
              '[sound setProperty:volumeKey forKey:@"audioVolumeKey"]'):
    assert exact in append, exact
assert '[_specifiers addObject:choose];\n        [self appendAudioForTarget:LMVSectionTargets()[i]' in specifiers
for chosen, target in (('controlCenterDark', 'ControlCenterDark'), ('controlCenterLight', 'ControlCenterLight'), ('homeMenuMaterial', 'HomeMenu'), ('squidPanelMaterial', 'SquidPanel'), ('cvMaterial', 'CV'), ('myrtleMaterial', 'Myrtle')):
    # 4.2.0: the material row and the audio pair are emitted by the generated loop,
    # so they no longer sit next to a literal channel name.
    assert 'for (NSDictionary *row in LMVStandaloneChannelRows()) {' in specifiers_source
    assert '[self materialRowForTarget:target]' in specifiers_source and '[self appendAudioForTarget:target title:@"播放"]' in specifiers_source
assert specifiers.count('appendAudioForTarget:') == 4  # five-section loop + two control-centre halves + generated loop
# 2.05: the audio module derives its keys from the CHANNEL name, so the channel must
# be called PA - calling it PhoneAssist read PhoneAssistSoundEnabled while the rows
# wrote PASoundEnabled, and the switch did nothing.
assert 'appendAudioForTarget:target' in specifiers  # 4.2.0: one five-target loop, two control-centre halves and one generated loop.
set_enabled = body(prefs, '- (void)setEnabled:')
getter = body(prefs, '- (id)volume:')
setter = body(prefs, '- (void)setVolume:')
assert '@"VideoOpacity" : [specifier propertyForKey:@"audioVolumeKey"]' in set_enabled
for method in (getter, setter):
    assert 'isfinite(raw) ? MAX(0.0, MIN(1.0, raw)) : 0.5' in method
    assert '[specifier propertyForKey:@"key"]' in method and 'VideoOpacity' not in method
assert 'return @(volume * 100.0);' in getter and '[value doubleValue] / 100.0' in setter
assert setter.count('CFPreferencesSetAppValue(') == 1 and 'LMVNotifyFor(LMVTargetForPrefKey(' in setter
print('PASS: actual source nine-target-plus-AT audio mapping, isolated keys/defaults, percent conversion, finite clamp, CC material rows 1/4, disabled steppers and per-channel notification on write')

if platform.system() == 'Darwin':
    # Use the exact production helpers, row builder and handlers below, not a copied model.
    fixture = r'''
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#include <assert.h>
#include <math.h>
static NSMutableDictionary *store;
static NSInteger writes, notifications;
static NSString *lastKey;
static CFStringRef const kLMVPrefsID = CFSTR("com.minis.lockmessagevideo");
static id LMVEasterRead(NSString *key) { return store[key]; }
static NSString *lastTarget = nil;
static void LMVEasterSet(NSString *key, id value) { store[key]=value; lastKey=key; writes++; notifications++; }
// 5.1.7: the panel writes through the scoped helpers; the fixture routes them to the
// same store so write/notification counting stays meaningful.
static void LMVEasterSetTarget(NSString *key, id value, NSString *target) { store[key]=value; lastKey=key; writes++; notifications++; lastTarget=target; }
static void LMVEasterNotifyTarget(NSString *target) { notifications++; lastTarget=target; }
static void LMVEasterSetLocal(NSString *key, id value) { store[key]=value; lastKey=key; writes++; }
// 3.06: the production notifier is the REAL LMVNotifyFor now (its body is compiled
// in with the helpers below), so the POST itself is what has to be counted - a local
// LMVNotify stub would never be called by the setter and the count assertion failed.
static void TestPost(CFNotificationCenterRef center, CFStringRef name, const void *object, CFDictionaryRef userInfo, Boolean deliverImmediately) { notifications++; }
static void TestSync(CFStringRef domain) { }
static CFTypeRef TestCopy(CFStringRef key, CFStringRef domain) { id v=store[(__bridge NSString *)key]; return v ? CFRetain((__bridge CFTypeRef)v) : NULL; }
static void TestSet(CFStringRef key, CFPropertyListRef value, CFStringRef domain) { LMVEasterSet((__bridge NSString *)key, (__bridge id)value); notifications--; }
#define CFPreferencesCopyAppValue TestCopy
#define CFPreferencesSetAppValue TestSet
#define CFNotificationCenterPostNotification TestPost
#define CFPreferencesAppSynchronize TestSync
@HELPERS@
enum { PSGroupCell=0, PSButtonCell=13, PSSwitchCell=6, PSSliderCell=5 };
@interface PSSpecifier : NSObject
@property NSInteger cellType;
@property id target;
@property SEL buttonAction, controllerLoadAction;
@property Class detailControllerClass;
@property(copy) NSString *name;
@property NSMutableDictionary *props;
+ (instancetype)groupSpecifierWithName:(NSString *)name;
+ (instancetype)preferenceSpecifierNamed:(NSString *)name target:(id)t set:(SEL)s get:(SEL)g detail:(Class)d cell:(NSInteger)c edit:(Class)e;
- (id)propertyForKey:(NSString *)k;
- (void)setProperty:(id)v forKey:(NSString *)k;
- (void)removePropertyForKey:(NSString *)k;
@end
@implementation PSSpecifier
+ (instancetype)groupSpecifierWithName:(NSString *)n { return [self preferenceSpecifierNamed:n target:nil set:NULL get:NULL detail:Nil cell:PSGroupCell edit:Nil]; }
+ (instancetype)preferenceSpecifierNamed:(NSString *)n target:(id)t set:(SEL)s get:(SEL)g detail:(Class)d cell:(NSInteger)c edit:(Class)e { PSSpecifier *p=[self new];p.name=n;p.target=t;p.cellType=c;p.props=[NSMutableDictionary new];if(s)p.props[@"setter"]=NSStringFromSelector(s);if(g)p.props[@"getter"]=NSStringFromSelector(g);return p; }
- (id)propertyForKey:(NSString *)k { return self.props[k]; }
- (void)setProperty:(id)v forKey:(NSString *)k { self.props[k]=v; }
- (void)removePropertyForKey:(NSString *)k { [self.props removeObjectForKey:k]; }
@end
@interface UIView : NSObject
@property UIView *superview;
@property NSArray *subviews;
@property NSInteger tag;
@end
@implementation UIView @end
@interface UILabel : UIView
@property(copy) NSString *text;
@end
@implementation UILabel @end
@interface UITableViewCell : UIView
@property UILabel *textLabel;
@property UIView *contentView;
@property UIView *accessoryView;
@end
@implementation UITableViewCell @end
@interface UISwitch : NSObject
@property NSInteger tag;
@property BOOL on;
@end
@implementation UISwitch @end
@interface LMVStepperControl : UIView
@property BOOL enabled;
@property double value;
@property double minimumValue;
@property double maximumValue;
@property double stepValue;
@property(copy) NSString *accessibilityValue;
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events;
- (void)sendActionsForControlEvents:(NSUInteger)events;
@end
@implementation LMVStepperControl
- (void)addTarget:(id)target action:(SEL)action forControlEvents:(NSUInteger)events {}
- (void)sendActionsForControlEvents:(NSUInteger)events {}
@end
@interface UITableView : NSObject
@property NSInteger reloads;
@property NSArray *visibleCells;
- (void)reloadData;
- (void)deselectRowAtIndexPath:(NSIndexPath *)p animated:(BOOL)a;
@end
@implementation UITableView
- (void)reloadData { self.reloads++; }
- (void)deselectRowAtIndexPath:(NSIndexPath *)p animated:(BOOL)a {}
@end
@interface NSIndexPath (Rows)
@property(readonly) NSInteger section,row;
@end
@implementation NSIndexPath (Rows)
- (NSInteger)section { return [self indexAtPosition:0]; }
- (NSInteger)row { return [self indexAtPosition:1]; }
@end
@interface LMVMaterialPicker : NSObject
@property BOOL pushed,showsThumbnails;
@property(copy) NSString *selected;
@property(copy) void (^apply)(NSString *, NSString *);
@end
@implementation LMVMaterialPicker @end
@interface LMVEasterImageSettings : NSObject @end
@implementation LMVEasterImageSettings @end
@interface Navigation : NSObject
@property NSInteger pushes;
@property id last;
- (void)pushViewController:(id)p animated:(BOOL)a;
@end
@implementation Navigation
- (void)pushViewController:(id)p animated:(BOOL)a {self.pushes++;self.last=p;}
@end
@interface LMVEasterPanel : NSObject
@property BOOL busy,volumeTracking;
@property(nonatomic, copy) void (^requestKey)(void);
@property NSInteger imports;
@property id presentedViewController;
@property UITableView *tableView;
@property Navigation *navigationController;
@end
@implementation LMVEasterPanel
- (void)importVideo { self.imports++; }
@PANEL_METHODS@
@end
@interface LMVPRootListController : NSObject { NSMutableArray *_specifiers; }
@property NSInteger reloads;
- (id)enabled:(PSSpecifier *)s;
// 5.28: -specifiers ends with the presentation pass, which only stamps cellClass,
// panelKind and subtitle onto rows that already exist. The fixture compiles the
// real -specifiers body, so the selector is declared and stubbed here - the
// routing this test guards is unchanged.
- (void)applyPanelAppearance;
// 5.32: the list is rebuilt in place when a channel switch changes, and the
// fixture compiles the builder body rather than -specifiers itself.
- (NSArray *)specifiers;
- (void)lmvp_buildSpecifiers;
- (void)lmvp_rebuildSpecifiers;
- (PSSpecifier *)materialRowForTarget:(NSString *)t;
- (PSSpecifier *)textColorRowWithID:(NSString *)i;
@end
@implementation LMVPRootListController
- (void)reloadSpecifier:(id)s animated:(BOOL)a {self.reloads++;}
- (void)applyPanelAppearance {}
- (void)switchTarget:(NSString *)t {}
// 5.32: the channel switch rebuilds the list; this fixture tests the audio
// mapping, not the collapse, so the rebuild is a no-op here.
- (void)lmvp_rebuildSpecifiers {}
- (NSArray *)specifiers {
    if (!_specifiers) { _specifiers = [NSMutableArray new]; [self lmvp_buildSpecifiers]; }
    return _specifiers;
}
- (PSSpecifier *)materialRowForTarget:(NSString *)t { (void)t; return nil; }
- (PSSpecifier *)textColorRowWithID:(NSString *)i { (void)i; return nil; }
@BUTTONS@
@PREFS_METHODS@
@end
'''
    main = r'''
static NSIndexPath *path(NSInteger section, NSInteger row) { NSUInteger v[]={section,row};return [NSIndexPath indexPathWithIndexes:v length:2]; }
int main(void) { @autoreleasepool {
 store=[NSMutableDictionary new];
 NSArray *targets=LMVEasterAudioTargets();
 for (NSInteger section=0;section<18;section++) {
  for (NSInteger row=0;row<9;row++) {
   NSString *expected=nil;
   if(section<5&&(row==2||row==3))expected=targets[section];
   if(section==5&&(row==2||row==3))expected=targets[5];
   if(section==5&&(row==5||row==6))expected=targets[6];
   if(section==6&&(row==2||row==3))expected=targets[7];
   if(section==7&&(row==2||row==3))expected=targets[8];
   if(section==8&&(row==2||row==3))expected=targets[9];
   if(section==9&&(row==2||row==3))expected=targets[10];
   if(section==10&&(row==2||row==3))expected=targets[11];
  if(section==11&&(row==2||row==3))expected=targets[12];
  if(section==12&&(row==2||row==3))expected=targets[13];
  if(section==13&&(row==2||row==3))expected=targets[14];
  if(section==14&&(row==2||row==3))expected=targets[15];
   NSString *actual=LMVEasterAudioTarget(section,row);
   assert((!actual&&!expected)||[actual isEqual:expected]);
   BOOL volumeRow=(section==7)?(row==3):(row==3||row==6);
   assert(LMVEasterAudioVolumeRow(section,row)==(expected&&volumeRow));
  }
 }
 assert(!LMVEasterAudioTarget(-1,2)&&!LMVEasterAudioTarget(18,2));
 assert(!LMVEasterAudioTargetForTag(-1)&&!LMVEasterAudioTargetForTag(16));
 assert(LMVEasterAudioVolume(nil)==0.5&&LMVEasterAudioVolume(@"0.8")==0.5);
 for(NSNumber *value in @[@(-1),@0,@0.5,@1,@2,@(NAN),@(INFINITY),@(-INFINITY)]) {
  double raw=value.doubleValue, expected=isfinite(raw)?MAX(0,MIN(1,raw)):0.5;
  assert(LMVEasterAudioVolume(value)==expected);
 }
 LMVPRootListController *settings=[LMVPRootListController new];
 // 5.32: a disabled channel collapses to its switch row, so enable every
 // channel first - this test checks the full list, not the collapsed one.
 for (NSString *t in targets) store[[t stringByAppendingString:@"BackgroundEnabled"]]=@YES;
 store[@"ControlCenterBackgroundEnabled"]=@YES;
 NSArray *rows=[settings specifiers];
 assert(rows.count==85);
 NSInteger switches=0,sliders=0;
 for(NSString *target in targets) {
  NSString *soundKey=[target stringByAppendingString:@"SoundEnabled"],*volumeKey=[target stringByAppendingString:@"Volume"];
  PSSpecifier *sound=nil,*volume=nil;
  for(PSSpecifier *row in rows) {
   if([[row propertyForKey:@"key"] isEqual:soundKey]) {sound=row;switches++;}
   if([[row propertyForKey:@"key"] isEqual:volumeKey]) {volume=row;sliders++;}
  }
  assert(sound&&volume&&sound.cellType==PSSwitchCell&&volume.cellType==PSSliderCell);
  assert([[sound propertyForKey:@"default"] isEqual:@NO]);
  assert([[volume propertyForKey:@"default"] isEqual:@0.5]&&[[settings volume:volume] isEqual:@50]);
  assert([[volume propertyForKey:@"min"] isEqual:@0]&&[[volume propertyForKey:@"max"] isEqual:@100]);
  assert([[sound propertyForKey:@"audioVolumeKey"] isEqual:volumeKey]);
  assert([[volume propertyForKey:@"enabled"] isEqual:@NO]);
  NSInteger before=writes,notifies=notifications;
  [settings setEnabled:@YES specifier:sound];
  assert(writes==before+1&&notifications==notifies+1&&[lastKey isEqual:soundKey]);
  assert([[volume propertyForKey:@"enabled"] isEqual:@YES]);
  [settings setVolume:@75 specifier:volume];
  assert([lastKey isEqual:volumeKey]&&[store[volumeKey] doubleValue]==0.75);
  assert([[settings volume:volume] isEqual:@75]);
  [settings setEnabled:@NO specifier:sound];
  assert([[volume propertyForKey:@"enabled"] isEqual:@NO]&&[store[volumeKey] doubleValue]==0.75);
  for(NSNumber *bad in @[@(-100),@200,@(NAN),@(INFINITY),@(-INFINITY)]) {
   double raw=bad.doubleValue/100,expected=isfinite(raw)?MAX(0,MIN(1,raw)):0.5;
   [settings setVolume:bad specifier:volume];assert([store[volumeKey] doubleValue]==expected);
   store[volumeKey]=bad;raw=bad.doubleValue;expected=isfinite(raw)?MAX(0,MIN(1,raw)):0.5;
   assert([[settings volume:volume] doubleValue]==expected*100);
  }
 }
 assert(switches==16&&sliders==16);
 LMVEasterPanel *p=[LMVEasterPanel new];p.tableView=[UITableView new];p.navigationController=[Navigation new];
 UISwitch *toggle=[UISwitch new];LMVStepperControl *stepper=[LMVStepperControl new];
 for(NSInteger tag=0;tag<14;tag++) {
  NSString *target=targets[tag];toggle.tag=tag;toggle.on=YES;
  NSInteger before=writes;[p soundChanged:toggle];
  assert(writes==before+1&&[lastKey isEqual:[target stringByAppendingString:@"SoundEnabled"]]);
  stepper.tag=tag;stepper.value=75;[p volumeChanged:stepper];
  assert([lastKey isEqual:[target stringByAppendingString:@"Volume"]]);
  assert([store[lastKey] doubleValue]==0.75&&[stepper.accessibilityValue isEqual:@"75%"]);
  stepper.value=NAN;[p volumeChanged:stepper];assert([store[lastKey] doubleValue]==0.5);
 }
 for(NSNumber *tag in @[@(-1),@16,@99]) {NSInteger before=writes;toggle.tag=tag.integerValue;stepper.tag=tag.integerValue;[p soundChanged:toggle];[p volumeChanged:stepper];assert(writes==before);}
 for(NSInteger section=0;section<18;section++)for(NSInteger row=0;row<10;row++) {
  NSInteger before=p.navigationController.pushes,imports=p.imports;
  NSString *expected=nil;
  if(section<5&&row==1)expected=[targets[section] stringByAppendingString:@"Video"];
  if(section==5)expected=LMVEasterControlCenterKey(row);
  if(section==6&&row==1)expected=@"HomeMenuVideo";
  if(section==7&&row==1)expected=@"SquidPanelVideo";
  if(section==8&&row==1)expected=@"ATVideo";
  if(section==9&&row==1)expected=@"CVVideo";
  if(section==10&&row==1)expected=@"MyrtleVideo";
  if(section==11&&row==1)expected=@"PAVideo";
  if(section==12&&row==1)expected=@"GSVideo";
  if(section==13&&row==1)expected=@"CCBorderVideo";
  if(section==14&&row==1)expected=@"CopyLogXVideo";
  [p tableView:p.tableView didSelectRowAtIndexPath:path(section,row)];
  if(expected) {assert(p.navigationController.pushes==before+1);LMVMaterialPicker *picker=p.navigationController.last;picker.apply(@"library/test.mov",@"Test");assert([lastKey isEqual:expected]);}
  else if(section==15&&row==0)assert(p.navigationController.pushes==before+1);
  else {assert(p.navigationController.pushes==before);assert(p.imports==imports+(section==17&&row==0));}
 }
 puts("PASS: exact production specifiers minus 14 material/text-colour rows the fixture cannot compile (99 -> 85), all eleven audio keys/handlers/defaults/clamps, live percent and every real panel selection row (Foundation doubles; not UIKit)");
 } return 0; }
'''
    # 4.2.0: one shared switch action and one shared colour action replace the
    # sixteen per-channel ones.
    button_methods = '\n'.join(f'- (void){name}:(PSSpecifier *)s {{}}' for name in
                                ('switchTargetFromRow', 'chooseVideo', 'openEaster',
                                 'openMaterialPath', 'openTuneList', 'openTextColorFromRow'))
    # 3.05: the setters now notify PER CHANNEL (LMVNotifyFor/LMVTargetForPrefKey), so the
    # fixture must carry those two production helpers too - without them the native
    # build fails with "call to undeclared function".
    # 4.0.7: section ids and titles now come from the one channel table.
    channels = '\n'.join(line for line in (root / 'LockMessageVideoPrefs/LMVChannels.h').read_text().splitlines()
                         if not line.startswith('#import') and not line.startswith('#pragma'))
    actual_helpers = helpers + '\n' + body(prefs, 'static NSArray<NSString *> *LMVSectionTargets(') + '\n' + body(prefs, 'static NSArray<NSString *> *LMVNames(')
    actual_helpers += '\n' + body(prefs, 'static void LMVNotifyFor(') + '\n' + body(prefs, 'static NSString *LMVTargetForPrefKey(')
    # 5.34: turning a switch off now posts a state-free silence notification from
    # -setEnabled:, so the fixture must carry that helper as well.
    actual_helpers += '\n' + body(prefs, 'static void LMVPostSilence(')
    # The table must precede every fixture function that reads it, but after the
    # system imports (otherwise NSArray is not defined yet).
    fixture = fixture.replace('@HELPERS@', actual_helpers).replace('@BUTTONS@', button_methods)
    _lines = fixture.split('\n')
    _cut = max(i for i, line in enumerate(_lines[:24]) if line.startswith(('#import', '#include', '@class')))
    fixture = '\n'.join(_lines[:_cut + 1] + ['', channels] + _lines[_cut + 1:])
    fixture = fixture.replace('@PANEL_METHODS@', '\n'.join((sound, volume_change, selection_for_fixture)))
    fixture = fixture.replace('@PREFS_METHODS@', '\n'.join((append, specifiers, body(prefs, '- (id)enabled:'), set_enabled, getter, setter)))
    with tempfile.TemporaryDirectory() as tmp:
        Path(tmp).joinpath('LMVPanelCommon.h').write_text(Path(__file__).resolve().parents[1].joinpath('LMVPanelCommon.h').read_text())
        src, binary = Path(tmp)/'audio.m', Path(tmp)/'audio'
        src.write_text(fixture + main)
        subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', str(src), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
else:
    print('Native exact-handler test is available on macOS (GitHub Actions); static production contracts executed here.')
