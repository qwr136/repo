#!/usr/bin/env python3
"""电话助手通道的识别契约（2.26）。

背景：设备日志里 pa-nocard 只列出窗口，弹窗明明开着却报“没有卡片”。原因是
`LMVPhoneAssistSheetKind` 只认三个苹果私有类名（PhoneTVMac / PhoneContinuity /
CallAssist），第三方插件一旦替换或重新承载弹窗，这些名字就不存在了。

本测试锁住两件事：
1. 名字找不到时必须退回“结构识别”（弹窗永远带 Dimming/Backdrop 材质）；
2. 什么都没找到时必须把可见窗口的视图树（类名/坐标/透明度）打进日志，
   否则下一次抓日志仍然只能看到一串窗口类名。
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = (root / 'LMVPhoneAssistVideo.h').read_text()
workflow = (root / '.github/workflows/build.yml').read_text()

# 1) 结构识别存在，且确实按 Dimming/Backdrop 判定
assert 'static BOOL LMVPhoneAssistShellKind(UIView *view)' in src
shell = src[src.index('static BOOL LMVPhoneAssistShellKind(UIView *view)'):]
shell = shell[:shell.index('\n}')]
assert 'containsString:@"Dimming"' in shell and 'containsString:@"Backdrop"' in shell

# 2) 名字未命中时，查找流程必须调用结构识别
find = src[src.index('static UIView *LMVPhoneAssistFindCard'):]
find = find[:find.index('\n}')]
assert 'LMVPhoneAssistStructuralCard(window)' in find
assert 'LMVPhoneAssistCardMatch=@"shell"' in find
assert 'LMVPhoneAssistCardMatch=@"name"' in find

# 3) 结构识别只取弹窗内部的“卡片”，不取整窗，也不取材质本身
struct = src[src.index('static UIView *LMVPhoneAssistStructuralCard'):]
struct = struct[:struct.index('\n}')]
assert 'LMVPhoneAssistShellKind(child))continue' in struct
assert 'bounds.size.width-1 && frame.size.height>=bounds.size.height-1' in struct
assert 'bounds.size.width*.3' in struct and 'bounds.size.height*.05' in struct

# 4) 找不到卡片时的诊断必须包含视图树，并且状态行要写明命中方式
assert 'static NSString *LMVPhoneAssistTreeDump(UIWindow *window)' in src
assert 'pa-nocard windows=%lu %@%@' in src and 'LMVPhoneAssistTreeDump(candidate)' in src
assert 'match=%@' in src and 'LMVPhoneAssistCardMatch?:@"none"' in src

# 5) 测试本身接入 CI
assert 'tests/phone-assist-detection.py' in workflow


# 6) 2.27：覆盖型插件（GlassSuiteX）把玻璃放在自己的窗口里，必须能按其 dylib 归属
#    找到那个窗口并把视频挂到它最上层；如果它只是往弹窗里塞玻璃层，则跳过玻璃层。
assert 'static UIWindow *LMVPhoneAssistGlassWindow(UIWindow *alertWindow)' in src
glass = src[src.index('static UIWindow *LMVPhoneAssistGlassWindow'):]
glass = glass[:glass.index('\n}')]
assert 'containsString:@"GlassSuiteX"' in glass
assert 'LMVPhoneAssistImageName' in src and 'dladdr(' in src
assert 'mode=@"glass-window"' in src
assert 'LMVPhoneAssistGlassKind(sibling)' in src
# 索引越界保护：插到别人窗口的最上层时 index 可能等于 count
assert 'MIN(index,container.subviews.count)' in src

# 7) 2.28：不再在别人的视图树里抢层级，而是用自己的透明窗口，层级 = 最高可见窗口+1。
#    窗口必须拒绝一切触摸，否则会挡住电话助手自己的按钮。
assert '@interface LMVPhoneAssistOverlayWindow:UIWindow' in src
assert '- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event { return nil; }' in src
assert 'LMVPhoneAssistTopWindowLevel' in src and 'windowLevel+1' in src
assert 'presentOverlayForCard' in src and 'initWithWindowScene:window.windowScene' in src
assert 'mode=@"overlay"' in src
assert 'usingOverlay' in src and '[container insertSubview:self.host atIndex:0]' in src
# 覆盖窗口在 detach 时也要收起，否则弹窗关掉后视频会留在屏幕上
detach = src[src.index('- (void)detach {'):]
detach = detach[:detach.index('\n}')]
assert 'self.overlay.hidden=YES' in detach
# 覆盖窗口层级写进状态行，下次日志能直接确认它是否压在对方之上
assert 'olvl=%.0f' in src
print('PASS: phone-assist sheet found by class name, falls back to the dimming/backdrop '
      'structure, excludes full-screen and shell views, and reports the visible view tree '
      'plus the match source when nothing is found')
