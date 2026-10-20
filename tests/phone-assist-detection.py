#!/usr/bin/env python3
"""电话助手通道的识别契约（2.34）。

2.26 为了让「被第三方插件改名后的弹窗」还能认出来，加了一条结构兜底：
任何带 Dimming/Backdrop 材质的窗口都算候选，再从中取最大可见卡片。

2.31 的设备日志证明这条兜底会把整块屏幕都当成电话助手：灵动岛（390×77）、
控制中心长按菜单、CopyLogX 剪贴板面板（411×470）轮流被挂上，每 100ms 换一次。

2.34 起这些表面各自有独立通道，PA 回到 2.24 之前的行为：只按类名在自己的
弹窗上挂载。本测试锁住四件事：

1. 结构兜底（ShellKind / StructuralCard / match=shell）已经删除；
2. 仍然只认三个苹果私有类名，且只取弹窗内部卡片、不取整窗；
3. 别的通道不再被 PA 认领（CopyLogX 的交接代码也已删除）；
4. 找不到卡片时仍要打印可见窗口的视图树，否则下一次抓日志无从判断。
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = (root / 'LMVPhoneAssistVideo.h').read_text()
workflow = (root / '.github/workflows/build.yml').read_text()

# 1) 结构兜底必须已经删干净
assert 'LMVPhoneAssistStructuralCard' not in src
assert 'LMVPhoneAssistShellKind' not in src
assert 'LMVPhoneAssistCardMatch=@"shell"' not in src
# 注释里仍会提到这两个词（解释为什么删掉兜底），但不能再有按材质判定的代码
assert 'containsString:@"Dimming"' not in src and 'containsString:@"Backdrop"' not in src

# 2) 只按类名识别
assert 'static BOOL LMVPhoneAssistSheetKind(UIView *view)' in src
sheet = src[src.index('static BOOL LMVPhoneAssistSheetKind(UIView *view)'):]
sheet = sheet[:sheet.index('\n}')]
for name in ('PhoneTVMac', 'PhoneContinuity', 'CallAssist'):
    assert f'containsString:@"{name}"' in sheet, name
assert 'LMVPhoneAssistCardMatch=@"name"' in src
assert 'static UIView *LMVPhoneAssistCard(UIWindow *window)' in src
card = src[src.index('static UIView *LMVPhoneAssistCard(UIWindow *window)'):]
card = card[:card.index('\n}')]
assert 'bounds.size.width-1 && frame.size.height>=bounds.size.height-1' in card
assert 'bounds.size.width*.3' in card and 'bounds.size.height*.05' in card

# 3) 不再接管其它通道的卡片
assert 'LMVCopyLogXIsCard' not in src and 'LMVCopyLogXClaimed' not in src

# 4) 找不到卡片时仍要能说明现场
assert 'static NSString *LMVPhoneAssistTreeDump(UIWindow *window)' in src
assert 'pa-nocard windows=%lu %@%@' in src and 'LMVPhoneAssistTreeDump(candidate)' in src
assert 'match=%@' in src and 'LMVPhoneAssistCardMatch?:@"none"' in src

# 5) 测试接入 CI
assert 'tests/phone-assist-detection.py' in workflow

print('PASS: phone-assist sheet identified by class name only (PhoneTVMac / '
      'PhoneContinuity / CallAssist); the 2.26 dimming/backdrop fallback is gone so the '
      'island, Control Center menus and the CopyLogX panel can no longer be claimed; '
      'pa-nocard still dumps the visible view tree')
