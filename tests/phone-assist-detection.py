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

print('PASS: phone-assist sheet found by class name, falls back to the dimming/backdrop '
      'structure, excludes full-screen and shell views, and reports the visible view tree '
      'plus the match source when nothing is found')
