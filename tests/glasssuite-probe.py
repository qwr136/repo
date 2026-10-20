#!/usr/bin/env python3
"""GlassSuiteX 弹窗通道的探测开销契约（2.36）。

背景：2.35 的抓取里 GS 通道本身工作正常——

    gs-panel win=SBHomeScreenWindow 430x932 mode=content
    card=_UIVisualEffectContentView@51,172,328x589 r0 live=1 rate=1.0

但只在开启 GS、其它通道全关的情况下 spcpu 就很高。原因是探测本身：每 0.1 秒
从 SBHomeScreenWindow 根节点做一次 600 节点的深度遍历，未命中还要把 11 个可见
窗口各扫一遍，每个非 GAX 视图都调一次 dladdr。弹窗关着时反而更贵。

本测试锁住 2.36 的修法，防止以后又被改回去：

1. 缓存的是「卡片」而不是「窗口」；
2. 未命中时只扫窗口的两层，并整棵跳过图标/文件夹/壁纸等子树；
3. dladdr 结果按 Class 缓存，普通 UIView 根本不查；
4. 轮询分三档（有卡片 0.25s / 无卡片 0.75s / 开关关闭 2s）并带 tolerance；
5. 挂载位置不变（内容视图 index 0）；
6. 诊断行带父链，能直接对着 FLEX 看。
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = (root / 'LMVGlassSuiteVideo.h').read_text()
workflow = (root / '.github/workflows/build.yml').read_text()

# ---- 1) 生命周期仍在 --------------------------------------------------------
assert 'static void LMVGlassSuiteVideoRefresh(BOOL reload);' in src
assert 'static void LMVGlassSuiteVideoSuspend(void);' in src
assert 'static void LMVGlassSuiteVideoInstallHooks(void) {' in src
assert 'LMVCCSelectedPath(@"GSVideo")' in src

# ---- 2) 缓存卡片，而不是窗口 -------------------------------------------------
assert 'static __weak UIView *LMVGlassSuiteCardRef;' in src
assert 'static UIView *LMVGlassSuiteCachedCard(UIWindow **windowOut)' in src
assert 'if(!card || !card.superview || card.hidden || card.alpha<.01)return nil;' in src
# 旧的窗口缓存必须消失，否则每次仍会重走整棵主屏树
assert 'LMVGlassSuiteLastWindow' not in src, 'the window cache is what forced a full re-walk'

# ---- 3) 浅层扫描 + 剪枝 ------------------------------------------------------
assert 'static UIView *LMVGlassSuiteShallowCard(UIWindow *window)' in src
assert 'for(UIView *layer in window.subviews)' in src
assert 'for(UIView *child in layer.subviews)' in src
assert 'static BOOL LMVGlassSuiteSkipSubtree(UIView *view)' in src
for word in ('SBIcon', 'SBRecycled', 'SBFolder', 'Backdrop', 'Wallpaper', 'StatusBar'):
    assert f'@"{word}"' in src, word
# 深度遍历与材质兜底必须整段删掉
assert 'static UIView *LMVGlassSuiteCard(UIWindow *window)' not in src
assert 'LMVGlassSuiteShellKind' not in src
assert 'budget=600' not in src, 'no deep probe should remain'

# ---- 4) dladdr 按 Class 缓存，且只查可疑类名 --------------------------------
assert 'static NSMutableDictionary<NSString *, NSNumber *> *LMVGlassSuiteOwnerCache;' in src
assert 'static BOOL LMVGlassSuiteOwnedByGlassSuiteX(Class cls)' in src
assert 'NSNumber *hit=LMVGlassSuiteOwnerCache[key];' in src
assert 'if(hit)return hit.boolValue;' in src
assert '@[@"Overlay",@"Alert",@"Panel",@"Sheet",@"Present",@"Window"]' in src
# 缓存放不下时整表清空，避免无限增长
assert 'if(LMVGlassSuiteOwnerCache.count>256)[LMVGlassSuiteOwnerCache removeAllObjects];' in src

# ---- 5) 三档轮询 + tolerance -------------------------------------------------
assert 'static NSTimeInterval LMVGlassSuiteInterval(void)' in src
assert 'if(!LMVGlassSuiteEnabled)return 2.0;' in src
assert 'if(LMVGlassSuiteCardRef)return MIN(base,.25);' in src
# 2.39: the waiting gear is the channel's ProbeHz (default 5Hz = 0.2s).
assert 'LMVTuneProbeInterval(@"GS")' in src
assert 'return base;' in src
assert 'return .75;' not in src
assert 'LMVGlassSuiteTimer.tolerance=want*.3;' in src
# 0.1 秒的旧节拍不能再出现
assert 'LMVGlassSuiteEnabled?.1:.5' not in src
# 刷新入口不再提前 retune，命中状态确定后才定档
assert src.count('LMVGlassSuiteRetune();') >= 3

# ---- 6) 挂载位置与模式不变 --------------------------------------------------
assert 'container=card;index=0;target=card.bounds;mode=@"content";' in src
assert 'if([card.superview isKindOfClass:UIVisualEffectView.class])' in src
assert '_UIVisualEffectContentView' in src

# ---- 7) 诊断：窗口类名 + 卡片父链 ------------------------------------------
assert 'chain=%@' in src
assert 'static NSString *LMVGlassSuiteChain(UIView *view)' in src
assert 'componentsJoinedByString:@">"' in src

# ---- 7b) 弹窗出现即触发，而不是等下一次轮询 ----------------------------------
assert 'static void LMVGlassSuiteInstallContainerHook(void)' in src
assert 'NSClassFromString(@"GAXAlertOverlayView")' in src
assert '@selector(didMoveToSuperview)' in src
# 必须先给子类加方法，否则会把 UIView 的 didMoveToSuperview 全局替换掉
assert 'if(class_addMethod(cls,sel,(IMP)LMVGlassSuiteContainerMoved,types))' in src
assert 'LMVGlassSuiteContainerMovedOriginal=method_getImplementation(own);' in src
# 钩子节流可调（默认 50ms），避免动画期间每帧都刷新
assert 'NSTimeInterval limit=LMVTuneDelay(@"GS",@"HookThrottleMs");' in src
# 刷新入口会补装钩子（dylib 可能晚于本插件加载）
assert src.count('LMVGlassSuiteInstallContainerHook();') >= 2

# ---- 8) CI 必须跑本测试 ------------------------------------------------------
assert 'check python3 tests/glasssuite-probe.py' in workflow

print('PASS: GlassSuiteX probe cost - card-level cache (not window), two-level scan '
      'with icon/folder/wallpaper subtrees pruned, per-class dladdr cache, three-gear '
      'timer with tolerance, 0.2s waiting gear, container didMoveToSuperview hook for '
      'instant mount, mount point unchanged, chain diagnostics, CI wired')
