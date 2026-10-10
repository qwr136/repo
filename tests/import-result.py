from pathlib import Path
import platform, subprocess, tempfile
r=Path(__file__).resolve().parents[1]
s=(r/'LMVEasterPanel.h').read_text()
def method(signature):
 a=s.index(signature+' {');depth=0
 for i in range(a+len(signature),len(s)):
  if s[i]=='{':depth+=1
  elif s[i]=='}':
   depth-=1
   if not depth:return s[a:i+1]
 raise AssertionError(signature)
show=method('- (void)showPendingImportPrompt')
close=method('- (void)prepareForClose')
ready=method('- (void)importResultReady:(NSNotification *)notification')
callback=s[s.index('            BOOL success = relative && !error;'):s.index('        });',s.index('            BOOL success = relative && !error;'))]
assert 'LMVEasterImportResultReady' in callback and 'if (success) LMVEasterNotify();' in callback
assert 'postNotificationName:LMVEasterImportResultReady' in callback
assert 'prompt.complete=nil' in close and 'insertObject:prompt atIndex:0' in close
assert 'prepareForClose' in (r/'LMVEasterOverlay.h').read_text()
if platform.system()!='Darwin':
 print('PASS: strict success/failure decision and cross-panel result delivery/requeue; native method execution on macOS CI')
 raise SystemExit(0)
pre=r'''
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <assert.h>
static const NSUInteger UIViewAutoresizingFlexibleWidth=2,UIViewAutoresizingFlexibleHeight=16;
@interface UIWindow:NSObject
@property BOOL hidden;
@property CGFloat alpha;
@end
@implementation UIWindow
- (instancetype)init {if((self=[super init]))_alpha=1;return self;}
@end
@interface UIView:NSObject
@property(strong) UIWindow *window;
@property CGRect bounds,frame;
@property NSUInteger autoresizingMask;
@property(strong) NSMutableArray *subviews;
@property(weak) UIView *superview;
@property NSUInteger endEdits;
- (void)addSubview:(UIView *)view;
- (void)removeFromSuperview;
- (void)endEditing:(BOOL)value;
@end
@implementation UIView
- (instancetype)init {if((self=[super init])){_bounds=CGRectMake(0,0,360,500);_subviews=[NSMutableArray new];}return self;}
- (void)addSubview:(UIView *)view {view.superview=self;[self.subviews addObject:view];view.window=self.window;}
- (void)removeFromSuperview {[self.superview.subviews removeObjectIdenticalTo:self];self.superview=nil;self.window=nil;}
- (void)endEditing:(BOOL)value {self.endEdits++;}
@end
@class UINavigationController;
@interface UIViewController:NSObject
@property(strong) UIView *view;
@property(strong) UIViewController *presentedViewController;
@property(weak) UIViewController *parentViewController;
@property(strong) NSMutableArray *childViewControllers;
@property BOOL isMovingFromParentViewController,isBeingDismissed,isViewLoaded;
@property(strong) UINavigationController *navigationController;
- (void)addChildViewController:(UIViewController *)child;
- (void)removeFromParentViewController;
- (void)willMoveToParentViewController:(UIViewController *)parent;
- (void)didMoveToParentViewController:(UIViewController *)parent;
@end
@implementation UIViewController
- (instancetype)init {if((self=[super init])){_view=[UIView new];_childViewControllers=[NSMutableArray new];_isViewLoaded=YES;}return self;}
- (void)addChildViewController:(UIViewController *)child {child.parentViewController=self;[self.childViewControllers addObject:child];}
- (void)removeFromParentViewController {[self.parentViewController.childViewControllers removeObjectIdenticalTo:self];self.parentViewController=nil;}
- (void)willMoveToParentViewController:(UIViewController *)parent {}
- (void)didMoveToParentViewController:(UIViewController *)parent {}
@end
@interface UINavigationController:UIViewController
@property(strong) UIViewController *topViewController;
@end
@implementation UINavigationController @end
@interface LMVMaterialPrompt:UIViewController
@property(copy) NSString *promptTitle,*message;
@property(copy) void (^complete)(NSString *,BOOL);
- (void)finish;
@end
@implementation LMVMaterialPrompt
- (void)finish {
 void (^done)(NSString *,BOOL)=self.complete;
 [self.view removeFromSuperview];[self removeFromParentViewController];
 if(done)done(nil,YES);
}
@end
@interface TestTable:NSObject
@property NSUInteger reloads;
- (void)reloadData;
@end
@implementation TestTable
- (void)reloadData {self.reloads++;}
@end
@interface LMVEasterPanel:UIViewController
@property BOOL panelVisible;
@property(strong) LMVMaterialPrompt *prompt;
@property(strong) TestTable *tableView;
@property NSUInteger nameLoads;
- (void)loadNames;
- (void)showPendingImportPrompt;
- (void)prepareForClose;
- (void)importResultReady:(NSNotification *)notification;
@end
static NSMutableArray<LMVMaterialPrompt *> *LMVEasterPendingImportPrompts;
static NSString * const LMVEasterImportResultReady=@"LMVEasterImportResultReady";
static NSUInteger notified;
static void LMVEasterNotify(void){notified++;}
'''
implementation='@implementation LMVEasterPanel\n- (void)loadNames {self.nameLoads++;}\n'+show+close+ready+'\n@end\n'
# Execute the exact production result branch, including error/success mapping,
# queued alert and notification (the movie transaction has a separate AVFoundation test).
result='static void deliver(LMVEasterPanel *panel,NSString *relative,NSError *error) {\n'+callback+'\n}\n'
main=r'''
static LMVEasterPanel *makePanel(BOOL visible) {
 LMVEasterPanel *p=[LMVEasterPanel new];p.panelVisible=visible;p.tableView=[TestTable new];
 p.view.window=[UIWindow new];
 UINavigationController *nav=[UINavigationController new];nav.view.window=p.view.window;nav.topViewController=p;p.navigationController=nav;
 [NSNotificationCenter.defaultCenter addObserver:p selector:@selector(importResultReady:) name:LMVEasterImportResultReady object:nil];
 return p;
}
int main(void){@autoreleasepool{
 LMVEasterPendingImportPrompts=[NSMutableArray new];
 LMVEasterPanel *p=makePanel(YES);deliver(p,@"library/new.mov",nil);
 assert(notified==1 && p.prompt && [p.prompt.promptTitle isEqual:@"导入成功"] && [p.prompt.message isEqual:@"已保存到素材库"]);
 assert(p.prompt.parentViewController==p.navigationController && !LMVEasterPendingImportPrompts.count);
 assert([p.navigationController.view.subviews containsObject:p.prompt.view]);
 LMVMaterialPrompt *first=p.prompt;[first finish];assert(!p.prompt && !first.parentViewController && !first.view.superview);
 assert(p.navigationController.topViewController==p); // confirmation does not close the panel
 NSError *error=[NSError errorWithDomain:@"test" code:5 userInfo:@{NSLocalizedDescriptionKey:@"failed"}];
 deliver(p,@"library/no.mov",error);assert(notified==1 && [p.prompt.promptTitle isEqual:@"导入失败"]);[p.prompt finish];
 // Completion while the old panel is hidden must be delivered to the CURRENT visible panel.
 p.panelVisible=NO;LMVEasterPanel *other=makePanel(YES);deliver(p,@"library/next.mov",nil);
 assert(notified==2 && !p.prompt && other.prompt && !LMVEasterPendingImportPrompts.count);
 [other prepareForClose];assert(!other.prompt && !other.panelVisible && LMVEasterPendingImportPrompts.count==1);
 [other showPendingImportPrompt];assert(!other.prompt);other.panelVisible=YES;[other showPendingImportPrompt];assert(other.prompt && !LMVEasterPendingImportPrompts.count);
 [other.prompt finish];assert(!other.prompt);
 // If every panel is closed the result persists until the next opening.
 other.panelVisible=NO;deliver(nil,@"library/offscreen.mov",nil);assert(notified==3 && LMVEasterPendingImportPrompts.count==1);
 LMVEasterPanel *reopened=makePanel(YES);[reopened showPendingImportPrompt];assert(reopened.prompt && !LMVEasterPendingImportPrompts.count);
 [reopened.prompt finish];
 // A navigation transition or hidden window must not display into the Photos surface.
 reopened.navigationController.topViewController=[UIViewController new];deliver(reopened,@"library/wait.mov",nil);assert(!reopened.prompt && LMVEasterPendingImportPrompts.count==1);
 reopened.navigationController.topViewController=reopened;reopened.view.window.hidden=YES;[reopened showPendingImportPrompt];assert(!reopened.prompt);
 reopened.view.window.hidden=NO;[reopened showPendingImportPrompt];assert(reopened.prompt);[reopened.prompt finish];
 puts("PASS: actual import-result branch and contained prompt methods: strict success/failure, current-panel notification, hidden/nav-deferred result, acknowledgement keeps panel open, close/reopen requeues unconfirmed prompt; UIKit Photos still needs device test");
 [NSNotificationCenter.defaultCenter removeObserver:p];[NSNotificationCenter.defaultCenter removeObserver:other];[NSNotificationCenter.defaultCenter removeObserver:reopened];
}return 0;}
'''
with tempfile.TemporaryDirectory() as tmp:
 source=Path(tmp)/'result.m';binary=Path(tmp)/'result';source.write_text(pre+implementation+result+main)
 subprocess.run(['clang','-fobjc-arc','-framework','Foundation','-framework','CoreGraphics',str(source),'-o',str(binary)],check=True)
 subprocess.run([str(binary)],check=True,timeout=30)
