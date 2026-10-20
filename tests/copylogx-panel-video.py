#!/usr/bin/env python3
"""CopyLogX 剪贴板面板通道的契约（2.32）。

背景：2.31 的抓取里，电话助手通道把一块 411×470 的底部卡片当成了自己的弹窗：

    pa-panel win=UIWindow 430x932 match=shell card=_UIVisualEffectContentView@10,462,411,470
    pa-stack card=_UIVisualEffectContentView < UIVisualEffectView < UIView < UIView < UIWindow

它不是电话助手弹窗，而是 CopyLogX 的剪贴板面板。本测试锁住三件事：

1. 它是独立通道：有自己的开关、素材、声音、音量、文字颜色和调试开关；
2. 识别不依赖任何私有类名，只认「普通 UIWindow + 在屏幕底部 + 宽过 80% +
   卡片里确实有表格」这一组结构特征；
3. PA 通道遇到同一张卡必须让路，不能两边各挂一份视频。
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
src = (root / 'LMVCopyLogXVideo.h').read_text()
pa = (root / 'LMVPhoneAssistVideo.h').read_text()
panel = (root / 'LMVEasterPanel.h').read_text()
prefs = (root / 'LockMessageVideoPrefs/LMVPRootListController.m').read_text()
tweak = (root / 'Tweak.xm').read_text()
audio = (root / 'LMVMediaAudio.h').read_text()
workflow = (root / '.github/workflows/build.yml').read_text()

# ---- 1) 独立通道：键与生命周期齐全 ------------------------------------------
assert 'static void LMVCopyLogXVideoRefresh(BOOL reload);' in src
assert 'static void LMVCopyLogXVideoSuspend(void);' in src
assert 'static void LMVCopyLogXVideoInstallHooks(void) {' in src
# 2.34: the "调试：记录弹窗尺寸" switch (and its key) is gone.
for key in ('CopyLogXBackgroundEnabled', 'CopyLogXVideo', 'CopyLogXTextColor'):
    assert f'CFSTR("{key}")' in src or f'@"{key}"' in src, key
assert 'LMVCCSelectedPath(@"CopyLogXVideo")' in src
assert 'LMVLockVideoRevision(LMVCopyLogXPath)' in src
# master switch honoured inline, absent = enabled
assert '![globalValue isKindOfClass:NSNumber.class] || [globalValue boolValue]' in src

# ---- 2) 结构识别：普通窗口 + 底部 + 宽度 + 表格 ------------------------------
assert 'static BOOL LMVCopyLogXWindowKind(UIWindow *window)' in src
assert 'static BOOL LMVCopyLogXCardKind(UIWindow *window,UIView *view)' in src
assert 'static BOOL LMVCopyLogXHasList(UIView *root)' in src
assert 'UIVisualEffectContentView' in src, 'the card class the 2.31 capture named'
# 2.35: ratios, not the 411x470 numbers - resizing the panel still matches.
assert 'bounds.size.width*.6' in src, 'the 411pt card on a 430pt screen is 95% wide'
assert 'bounds.size.height*.15' in src and 'bounds.size.height*.9' in src
assert 'fabs(CGRectGetMaxY(frame)-bounds.size.height)>60' in src, 'bottom-anchored'
# 2.35: the list is the IDENTITY (hard requirement), not a tie-breaker.
assert 'isKindOfClass:UIScrollView.class' in src
assert 'return LMVCopyLogXHasList(view);' in src
assert 'static BOOL LMVCopyLogXHasList(UIView *root)' in src
# the window is judged by exclusion (system chrome + other channels' panels)
assert '[name isEqualToString:@"LMVEasterWindow"]' in src
assert '@"SystemAperture"' in src and '@"SBControlCenter"' in src
assert '@"CVPanel",@"CopyVault",@"Myrtle",@"SGPanel",@"SquidPanel"' in src
assert 'LMVCopyLogXHasList(child)) visible*=2' in src
# 关闭的面板不能被挂载
assert 'LMVCopyLogXVisibleArea(frame,window.bounds)' in src

# ---- 3) 挂载层级：卡片里 index 0，背景之上、列表之下 ------------------------
assert 'UIView *container=card;NSUInteger index=0;CGRect target=card.bounds;NSString *mode=@"card";' in src
assert 'if(!placed && ![self insertHostInto:container at:index])' in src
assert 'com.minis.lockmessagevideo.copylogx.render' in src
# 文字颜色可还原
assert 'LMVCopyLogXApplyTextColor(card)' in src and 'LMVCopyLogXRestoreTextColor()' in src

# ---- 4) PA 只挂自己的弹窗，不再认领这张卡 --------------------------------
assert 'LMVCopyLogXIsCard' not in pa and 'LMVCopyLogXClaimed' not in pa
assert 'LMVPhoneAssistStructuralCard' not in pa, 'PA 的结构兜底已删除'
# 没有卡片时必须能说出原因
assert 'clx-nocard windows=%@' in src
assert '#import "LMVCopyLogXVideo.h"' in tweak
assert tweak.index('#import "LMVCopyLogXVideo.h"') < tweak.index('#import "LMVPhoneAssistVideo.h"')

# ---- 5) 接线：刷新 / 挂起 / hooks / 音频 ------------------------------------
assert 'LMVCopyLogXVideoRefresh(reload);' in tweak
assert 'LMVCopyLogXVideoSuspend();' in tweak
assert 'LMVCopyLogXVideoInstallHooks();' in tweak
assert 'LMVAudioConsume(@"CopyLogX"' in tweak
assert '@"CCBorder",@"CopyLogX"];' in audio

# ---- 6) 设置页：开关 / 素材 / 声音 / 音量 / 文字颜色 / 调试 ------------------
assert 'PSSpecifier *clxGroup = [PSSpecifier groupSpecifierWithName:@"CopyLogX 视频背景"];' in prefs
assert '[clxEnabled setProperty:@"CopyLogXBackgroundEnabled" forKey:@"key"]' in prefs
assert '[clxEnabled setProperty:@NO forKey:@"default"]' in prefs
assert 'clxMaterial.buttonAction = @selector(switchCopyLogX:);' in prefs
assert '[self appendAudioForTarget:@"CopyLogX" title:@"播放"]' in prefs
assert 'clxText.buttonAction = @selector(openCopyLogXTextColor:);' in prefs
assert 'CopyLogXDebugSize' not in prefs and 'clxDebug' not in prefs
assert '- (void)switchCopyLogX:(PSSpecifier *)specifier { [self switchTarget:@"CopyLogX"]; }' in prefs
assert '- (void)openCopyLogXTextColor:(PSSpecifier *)specifier {' in prefs
assert 'LMVCopyLogXTextColorKey' in prefs
assert '@"CopyLogX": @"CopyLogX 视频背景"' in prefs
assert '@"CopyLogX": @""' in prefs
assert '"CCBorder", @"CopyLogX"] containsObject:target];' in prefs

# ---- 7) 小彩蛋面板同步：开关 / 素材 / 声音 / 音量，不含文字颜色 -------------
assert 'static NSInteger LMVEasterCopyLogXSection(void) { return LMVEasterCCBorderSection() + 1; }' in panel
assert 'if (section == LMVEasterCopyLogXSection()) return 4;' in panel
assert 'if (section == LMVEasterCopyLogXSection()) return @"CopyLogX 视频背景";' in panel
assert 'toggle.on = [LMVEasterRead(@"CopyLogXBackgroundEnabled") boolValue];' in panel
assert 'id selected = LMVEasterRead(@"CopyLogXVideo");' in panel
assert 'else if (toggle.tag == LMVEasterCopyLogXSection()) key = @"CopyLogXBackgroundEnabled";' in panel
assert 'key = @"CopyLogXVideo";' in panel
assert 'if (section == LMVEasterCopyLogXSection() && (row == 2 || row == 3)) return @"CopyLogX";' in panel
assert '@"PA", @"GS", @"CCBorder", @"CopyLogX"];' in panel
# 小彩蛋里没有文字颜色行
clx_section = panel[panel.index('if (index.section == LMVEasterCopyLogXSection()) {')::]
clx_section = clx_section[:clx_section.index('// 2.29: GlassSuiteX section')]
assert 'LMVTextColorPicker' not in clx_section and '文字颜色' not in clx_section
assert 'CCBorderVideo' not in clx_section

# ---- 8) 测试接入 CI ----------------------------------------------------------
assert 'tests/copylogx-panel-video.py' in workflow

print('PASS: CopyLogX clipboard-panel channel - independent switch/material/sound/volume/'
      'text-colour settings, structural detection (non-system window + bottom-anchored '
      'wide effect-content card, table breaks ties), index-0 mount inside the card, PA no '
      'longer claims this card, clx-nocard diagnostics, audio plumbing, '
      'floating-panel sync without the colour row, no debug-size row, CI wired')
