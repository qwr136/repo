#!/usr/bin/env python3
"""Real production audio mapping/handlers; Foundation doubles execute on macOS."""
from pathlib import Path
import math, platform, re, subprocess, tempfile

root = Path(__file__).resolve().parents[1]
panel = (root / 'LMVEasterPanel.h').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
targets = ['Message', 'Options', 'Clear', 'LockScreen', 'Desktop', 'ControlCenterDark', 'ControlCenterLight', 'HomeMenu', 'SquidPanel', 'AT', 'CV']

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
assert '(row == 8 || row == 9)) return @"SquidPanel";' in mapping
assert '(row == 2 || row == 3)) return @"AT";' in mapping
assert 'if (row == 2 || row == 3) return @"ControlCenterDark";' in mapping
assert 'if (row == 5 || row == 6) return @"ControlCenterLight";' in mapping
assert mapping.count('return ') == 8 and mapping.endswith('return nil;\n}')
cc_key = body(panel, 'static NSString *LMVEasterControlCenterKey(')
actual_material_rows = {int(row): target for row, target in re.findall(r'row == (\d+) \? @"(\w+)Video"', cc_key)}
assert actual_material_rows == {1: 'ControlCenterDark', 4: 'ControlCenterLight'}
assert 'if (section == LMVEasterSquidPanelSection()) return row == 9;' in helpers
assert 'return (row == 3 || row == 6);' in helpers
assert 'tag >= 0 && tag < LMVEasterAudioTargets().count' in helpers
assert '[value isKindOfClass:NSNumber.class] ? [value doubleValue] : 0.5' in helpers
assert 'isfinite(raw) ? MAX(0.0, MIN(1.0, raw)) : 0.5' in helpers
assert '[value isKindOfClass:NSNumber.class] ? [value boolValue] : NO' in helpers

cells = body(panel, '- (UITableViewCell *)tableView:')
assert cells.index('LMVEasterAudioTarget(index.section, index.row)') < cells.index('LMVEasterHomeMenuSection()')
for exact in ('[LMVEasterAudioTargets() indexOfObject:audioTarget]', '@selector(soundChanged:)', '@selector(volumeChanged:)',
              'slider.enabled = LMVEasterAudioEnabled(audioTarget);', 'slider.maximumValue = 1;',
              'slider.accessibilityValue = [NSString stringWithFormat:@"%.0f%%", slider.value * 100.0];'):
    assert exact in cells, exact
sound = body(panel, '- (void)soundChanged:')
volume_change = body(panel, '- (void)volumeChanged:')
for method, suffix in ((sound, 'SoundEnabled'), (volume_change, 'Volume')):
    assert 'LMVEasterAudioTargetForTag(' in method and 'if (!target) return;' in method
    assert method.count('LMVEasterSet(') == 1
    assert f'[target stringByAppendingString:@"{suffix}"]' in method
assert 'LMVEasterAudioVolume(@(slider.value))' in volume_change
assert 'self.volumeTracking = slider.isTracking;' in volume_change
assert '!panel.opacityTracking && !panel.volumeTracking' in panel
selection = body(panel, '- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:')
assert 'key = LMVEasterControlCenterKey(index.row);\n        if (!key) return;' in selection
assert 'if (index.row != 1) return;\n        key = @"HomeMenuVideo";' in selection
assert 'if (index.row < 1 || index.row > 4) return;\n        key = LMVEasterSquidKeys()[index.row - 1];' in selection
assert 'if (index.row != 1) return;\n        key = @"ATVideo";' in selection
assert 'index.section >= LMVEasterTargets().count || index.row != 1) return;' in selection

append = body(prefs, '- (void)appendAudioForTarget:')
specifiers = body(prefs, '- (NSArray *)specifiers')
assert append.count('cell:PSSwitchCell') == append.count('cell:PSSliderCell') == 1
for exact in ('[sound setProperty:@NO forKey:@"default"]', '[volume setProperty:@0.5 forKey:@"default"]',
              '[volume setProperty:@0.0 forKey:@"min"]', '[volume setProperty:@100.0 forKey:@"max"]',
              '[volume setProperty:[self enabled:sound] forKey:@"enabled"]',
              'set:@selector(setEnabled:specifier:) get:@selector(enabled:)',
              'set:@selector(setVolume:specifier:) get:@selector(volume:)',
              '[sound setProperty:volumeKey forKey:@"audioVolumeKey"]'):
    assert exact in append, exact
assert '[_specifiers addObject:choose];\n        [self appendAudioForTarget:LMVTargets()[i]' in specifiers
for chosen, target in (('controlCenterDark', 'ControlCenterDark'), ('controlCenterLight', 'ControlCenterLight'), ('homeMenuMaterial', 'HomeMenu'), ('squidPanelSwap', 'SquidPanel'), ('cvMaterial', 'CV')):
    assert f'[_specifiers addObject:{chosen}];\n    [self appendAudioForTarget:@"{target}"' in specifiers
assert specifiers.count('appendAudioForTarget:') == 7  # One five-target loop, plus five explicit targets (CC dark/light, HomeMenu, SquidPanel, AT, CV).
set_enabled = body(prefs, '- (void)setEnabled:')
getter = body(prefs, '- (id)volume:')
setter = body(prefs, '- (void)setVolume:')
assert '@"VideoOpacity" : [specifier propertyForKey:@"audioVolumeKey"]' in set_enabled
for method in (getter, setter):
    assert 'isfinite(raw) ? MAX(0.0, MIN(1.0, raw)) : 0.5' in method
    assert '[specifier propertyForKey:@"key"]' in method and 'VideoOpacity' not in method
assert 'return @(volume * 100.0);' in getter and '[value doubleValue] / 100.0' in setter
assert setter.count('CFPreferencesSetAppValue(') == 1 and 'LMVNotify();' in setter
print('PASS: actual source nine-target-plus-AT audio mapping, isolated keys/defaults, percent conversion, finite clamp, CC material rows 1/4, disabled sliders and live notification protection')

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
static void LMVEasterSet(NSString *key, id value) { store[key]=value; lastKey=key; writes++; notifications++; }
static void LMVNotify(void) { notifications++; }
static CFTypeRef TestCopy(CFStringRef key, CFStringRef domain) { id v=store[(__bridge NSString *)key]; return v ? CFRetain((__bridge CFTypeRef)v) : NULL; }
static void TestSet(CFStringRef key, CFPropertyListRef value, CFStringRef domain) { LMVEasterSet((__bridge NSString *)key, (__bridge id)value); notifications--; }
#define CFPreferencesCopyAppValue TestCopy
#define CFPreferencesSetAppValue TestSet
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
@end
@implementation UIView @end
@interface UILabel : UIView
@property(copy) NSString *text;
@end
@implementation UILabel @end
@interface UITableViewCell : UIView
@property UILabel *textLabel;
@end
@implementation UITableViewCell @end
@interface UISwitch : NSObject
@property NSInteger tag;
@property BOOL on;
@end
@implementation UISwitch @end
@interface UISlider : UIView
@property NSInteger tag;
@property float value;
@property(getter=isTracking) BOOL tracking;
@property(copy) NSString *accessibilityValue;
@end
@implementation UISlider @end
@interface UITableView : NSObject
@property NSInteger reloads;
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
@property NSInteger imports;
@property id presentedViewController;
@property UITableView *tableView;
@property Navigation *navigationController;
@end
@implementation LMVEasterPanel
- (void)importVideo { self.imports++; }
- (void)claimSquidPanel {}
- (void)resetSquidPanel {}
@PANEL_METHODS@
@end
@interface LMVPRootListController : NSObject { NSMutableArray *_specifiers; }
@property NSInteger reloads;
- (id)enabled:(PSSpecifier *)s;
@end
@implementation LMVPRootListController
- (void)reloadSpecifier:(id)s animated:(BOOL)a {self.reloads++;}
- (void)switchTarget:(NSString *)t {}
@BUTTONS@
@PREFS_METHODS@
@end
'''
    main = r'''
static NSIndexPath *path(NSInteger section, NSInteger row) { NSUInteger v[]={section,row};return [NSIndexPath indexPathWithIndexes:v length:2]; }
int main(void) { @autoreleasepool {
 store=[NSMutableDictionary new];
 NSArray *targets=LMVEasterAudioTargets();
 for (NSInteger section=0;section<13;section++) {
  for (NSInteger row=0;row<10;row++) {
   NSString *expected=nil;
   if(section<5&&(row==2||row==3))expected=targets[section];
   if(section==5&&(row==2||row==3))expected=targets[5];
   if(section==5&&(row==5||row==6))expected=targets[6];
   if(section==6&&(row==2||row==3))expected=targets[7];
   if(section==7&&(row==8||row==9))expected=targets[8];
   if(section==8&&(row==2||row==3))expected=targets[9];
   if(section==9&&(row==2||row==3))expected=targets[10];
   NSString *actual=LMVEasterAudioTarget(section,row);
   assert((!actual&&!expected)||[actual isEqual:expected]);
   BOOL volumeRow=(section==7)?(row==9):(row==3||row==6);
   assert(LMVEasterAudioVolumeRow(section,row)==(expected&&volumeRow));
  }
 }
 assert(!LMVEasterAudioTarget(-1,2)&&!LMVEasterAudioTarget(12,2));
 assert(!LMVEasterAudioTargetForTag(-1)&&!LMVEasterAudioTargetForTag(11));
 assert(LMVEasterAudioVolume(nil)==0.5&&LMVEasterAudioVolume(@"0.8")==0.5);
 for(NSNumber *value in @[@(-1),@0,@0.5,@1,@2,@(NAN),@(INFINITY),@(-INFINITY)]) {
  double raw=value.doubleValue, expected=isfinite(raw)?MAX(0,MIN(1,raw)):0.5;
  assert(LMVEasterAudioVolume(value)==expected);
 }
 LMVPRootListController *settings=[LMVPRootListController new];
 NSArray *rows=[settings specifiers];
 assert(rows.count==75);
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
 assert(switches==11&&sliders==11);
 LMVEasterPanel *p=[LMVEasterPanel new];p.tableView=[UITableView new];p.navigationController=[Navigation new];
 UISwitch *toggle=[UISwitch new];UISlider *slider=[UISlider new];
 for(NSInteger tag=0;tag<11;tag++) {
  NSString *target=targets[tag];toggle.tag=tag;toggle.on=YES;
  NSInteger before=writes;[p soundChanged:toggle];
  assert(writes==before+1&&[lastKey isEqual:[target stringByAppendingString:@"SoundEnabled"]]);
  slider.tag=tag;slider.value=0.75;slider.tracking=YES;[p volumeChanged:slider];
  assert(p.volumeTracking&&[lastKey isEqual:[target stringByAppendingString:@"Volume"]]);
  assert([store[lastKey] doubleValue]==0.75&&[slider.accessibilityValue isEqual:@"75%"]);
  slider.tracking=NO;slider.value=NAN;[p volumeChanged:slider];assert(!p.volumeTracking&&[store[lastKey] doubleValue]==0.5);
 }
 for(NSNumber *tag in @[@(-1),@11,@99]) {NSInteger before=writes;toggle.tag=tag.integerValue;slider.tag=tag.integerValue;[p soundChanged:toggle];[p volumeChanged:slider];assert(writes==before);}
 for(NSInteger section=0;section<13;section++)for(NSInteger row=0;row<10;row++) {
  NSInteger before=p.navigationController.pushes,imports=p.imports;
  NSString *expected=nil;
  if(section<5&&row==1)expected=[targets[section] stringByAppendingString:@"Video"];
  if(section==5)expected=LMVEasterControlCenterKey(row);
  if(section==6&&row==1)expected=@"HomeMenuVideo";
  if(section==7&&row>=1&&row<=4)expected=@[@"SquidPanelVideo",@"SquidPanel2Video",@"SquidPanel3Video",@"SquidPanel4Video"][row-1];
  if(section==8&&row==1)expected=@"ATVideo";
  if(section==9&&row==1)expected=@"CVVideo";
  [p tableView:p.tableView didSelectRowAtIndexPath:path(section,row)];
  if(expected) {assert(p.navigationController.pushes==before+1);LMVMaterialPicker *picker=p.navigationController.last;picker.apply(@"library/test.mov",@"Test");assert([lastKey isEqual:expected]);}
  else if(section==10&&row==0)assert(p.navigationController.pushes==before+1);
  else {assert(p.navigationController.pushes==before);assert(p.imports==imports+(section==12&&row==0));}
 }
 puts("PASS: exact production specifiers (75), all eleven audio keys/handlers/defaults/clamps, live percent and every real panel selection row (Foundation doubles; not UIKit)");
 } return 0; }
'''
    button_methods = '\n'.join(re.findall(r'- \(void\)switch\w+:\(PSSpecifier \*\)specifier \{ \[self switchTarget:@"\w+"\]; \}', prefs))
    button_methods += '\n' + '\n'.join(f'- (void){name}:(PSSpecifier *)s {{}}' for name in ('chooseVideo', 'openEaster', 'openMaterialPath', 'claimSquidPanel', 'resetSquidPanel'))
    actual_helpers = helpers + '\n' + body(prefs, 'static NSArray<NSString *> *LMVTargets(') + '\n' + body(prefs, 'static NSArray<NSString *> *LMVNames(')
    fixture = fixture.replace('@HELPERS@', actual_helpers).replace('@BUTTONS@', button_methods)
    fixture = fixture.replace('@PANEL_METHODS@', '\n'.join((sound, volume_change, selection)))
    fixture = fixture.replace('@PREFS_METHODS@', '\n'.join((append, specifiers, body(prefs, '- (id)enabled:'), set_enabled, getter, setter)))
    with tempfile.TemporaryDirectory() as tmp:
        src, binary = Path(tmp)/'audio.m', Path(tmp)/'audio'
        src.write_text(fixture + main)
        subprocess.run(['clang', '-fobjc-arc', '-framework', 'Foundation', str(src), '-o', str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
else:
    print('Native exact-handler test is available on macOS (GitHub Actions); static production contracts executed here.')
