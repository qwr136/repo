#!/usr/bin/env python3
"""CCBorder 通道的识别与挂载契约（2.31）。

背景：2.30 真机日志显示长按菜单的卡片识别被 _UICutoutShadowView 截胡
（_UIRoundedRectShadowView 子类，浮层下方的边缘阴影）：视频挂进它 index 0 后
被浮层整个盖住——声音在播、画面不可见（ccb-panel mode=card live=1 rate=1.0）。

本测试锁住三件事：
1. Shadow/Cutout 视图永远不作为卡片；
2. UIVisualEffectView 的内容卡片单独成层，优先于旧的「最大可见」兜底；
3. 挂载：content 索引 0 为主、above-material 兜底（材质+1，先跳过玻璃兄弟），
   且 ccb-stack / ccb-nocard / ccb-notready 诊断能把「挂上了但被遮挡」
   「目标没识别」「识别了但没就绪」分开。
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = (root / 'LMVCCBorderVideo.h').read_text()
workflow = (root / '.github/workflows/build.yml').read_text()

# 1) Shadow/Cutout 判定存在，且在卡片扫描里与 glass 一起被排除评分
assert 'static BOOL LMVCCBorderShadowKind(UIView *view)' in src
shadow = src[src.index('static BOOL LMVCCBorderShadowKind'):]
shadow = shadow[:shadow.index('\n}')]
assert 'containsString:@"Shadow"' in shadow and 'containsString:@"Cutout"' in shadow
cardin = src[src.index('static UIView *LMVCCBorderCardIn'):]
cardin = cardin[:cardin.index('\n}')]
assert 'LMVCCBorderGlassKind(child) || LMVCCBorderShadowKind(child))continue' in cardin

# 2) 内容卡片（UIVisualEffectView 的非玻璃子视图）单独成层，优于兜底的“最大可见”
assert '[child.superview isKindOfClass:UIVisualEffectView.class]' in cardin
assert 'return bestContent ?: bestFallback;' in cardin

# 3) 挂载：content 索引 0 主路径 + above-material 兜底（材质+1，先跳过玻璃兄弟），
#    兜底材质在菜单内查找
update_src = src[src.index('- (void)update {'):src.index('@end', src.index('- (void)update {'))]
assert 'mode=@"content"' in update_src and 'mode=@"above-material"' in update_src
assert 'NSUInteger slot=(NSUInteger)(near+1);' in update_src
assert 'index=slot;target=material.frame;mode=@"above-material";' in update_src
assert 'LMVCCBorderMaterial(menu,card,window)' in src

# 4) 诊断：ccb-stack + ccb-nocard + ccb-notready + 状态行的 sup/z
assert 'static NSString *LMVCCBorderStackDescription' in src
assert 'ccb-stack card=%@' in src
assert 'ccb-nocard windows=%lu' in src and 'ccb-notready player=%d' in src
assert 'sup=%@ z=%ld' in src

# 4b) 2.62: landscape must not change which card qualifies. The width floor used to be
# a fraction of the window WIDTH, so rotating 430 -> 932 raised it from 129 pt to
# 279 pt and the same 250 pt module menu stopped qualifying ("CCBorder 横屏没有视频").
# Lock the orientation-neutral reference and the two floors derived from it.
assert 'CGFloat ref=MIN(bounds.size.width,bounds.size.height);' in src, 'short-side reference'
assert 'frame.size.width<ref*.3 || frame.size.height<ref*.05' in src, 'orientation-neutral floors'
assert 'frame.size.width<bounds.size.width*.3' not in src, 'no width-fraction floor (landscape bug)'
# The full-screen rejection must still compare against the real window (it is what
# keeps the platter/background out); only the minimum-size floors became relative.
assert 'frame.size.width>=bounds.size.width-1 && frame.size.height>=bounds.size.height-1' in src

# 5) 测试本身接入 CI
assert 'tests/ccb-detection.py' in workflow

print('PASS: CCBorder never treats shadow/cutout layers as the card, prefers the '
      'effect-view content card, mounts at content index 0 with an above-material '
      'fallback, and reports ccb-stack/ccb-nocard/ccb-notready so a covered mount '
      'is distinguishable from a missing target or a not-ready decoder')