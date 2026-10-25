#!/usr/bin/env python3
"""4.3.0 gallery settings page: source contracts.

Verifies the new page derives from the channel table, writes the same per-channel
keys as the classic list, never posts the global notification, and stays wired
into the bundle and CI. It does not (and cannot) prove how it looks on a device.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PREFS = ROOT / "LockMessageVideoPrefs"
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


def read(path):
    return path.read_text(encoding="utf-8")


kit = read(PREFS / "LMVGalleryKit.h")
gallery = read(PREFS / "LMVGalleryController.m")
detail = read(PREFS / "LMVChannelDetailController.m")
root = read(PREFS / "LMVPRootListController.m")
makefile = read(ROOT / "Makefile")
control = read(ROOT / "control")
plist = read(PREFS / "Info.plist")
workflow = read(ROOT / ".github/workflows/build.yml")

for name in ("LMVGalleryKit.h", "LMVGalleryKit.m", "LMVGalleryController.m",
             "LMVChannelDetailController.m", "LMVGalleryPages.m"):
    check((PREFS / name).exists(), f"missing {name}")

# Bundle wiring
check(all(name in makefile for name in ("LMVGalleryController.m", "LMVGalleryPages.m",
                                        "LMVGalleryKit.m", "LMVChannelDetailController.m")),
      "gallery sources not in LockMessageVideoPrefs_FILES")
check("LMVGalleryController.m" in makefile.split("LockMessageVideoPrefs_FILES =", 1)[-1].split("\n", 1)[0],
      "gallery controller outside the prefs bundle file list")

# Version agreement (the receipt compares these three)
check("LMV_VERSION = 4.3.6" in makefile, "Makefile version not 4.3.6")
check(re.search(r"^Version: 4\.3\.6$", control, re.M) is not None, "control version not 4.3.6")
check(plist.count("<string>4.3.6</string>") == 2, "Info.plist versions not 4.3.6")

# Entry: the classic list stays intact and the gallery opens exactly once per visit
check("@implementation LMVPRootListController" in root, "classic root controller removed")
# 4.3.6: embedded as a child, not pushed - pushing showed the classic list first.
check("addChildViewController:gallery" in root, "gallery is not embedded")
check("pushViewController:[LMVGalleryController new]" not in root, "gallery still pushed")
check("self.table.hidden = YES" in root, "classic table not hidden behind the gallery")
check("onRequestClassicList" in root and "showClassicList" in root, "classic-list switch missing")
check("containsObject:self" in root, "pane-level reset missing")

# Table-driven: no hand-written channel ids in the new pages
for page, text in (("gallery", gallery), ("detail", detail)):
    check("LMVSectionChannelIDs" in gallery or "LMVChannelTable" in kit,
          "gallery does not derive scenes from the channel table")
    check(re.search(r'@"(Message|Options|Clear|LockScreen|Desktop|HomeMenu|SquidPanel|AT|CV|Myrtle|PA|GS|CCBorder|CopyLogX)BackgroundEnabled"', text) is None,
          f"{page} hardcodes a channel preference key")

# Same keys as the classic list, written per channel
check('stringByAppendingString:@"BackgroundEnabled"' in detail, "enable key not derived from channel id")
check('stringByAppendingString:@"Video"' in detail, "material key not derived from channel id")
check('stringByAppendingString:@"SoundEnabled"' in detail, "sound key not derived from channel id")
check('stringByAppendingString:@"Volume"' in detail, "volume key not derived from channel id")
check("LMVGNotifyChannel" in detail, "detail page does not post per-channel notification")

# Per-channel notifications only: the new files must not build the global name
for page, text in (("gallery", gallery), ("detail", detail)):
    check("preferencesChanged.%@\"" not in text,
          f"{page} posts an ad-hoc notification name")
    check("CFNotificationCenterPostNotification" not in text,
          f"{page} posts notifications directly instead of LMVGNotifyChannel")

# Material catalogue is reused, not re-listed
check("LMVReadMaterialNames" in kit and "LMVMaterialDisplayName" in kit,
      "gallery does not reuse the material catalogue")
check("LMVEnsureThumbnail" in read(PREFS / "LMVGalleryKit.m"), "thumbnail fallback missing")
check("LMVMaterialQueue" in kit, "catalogue scan is not on the shared serial queue")

# Text colour routes through the existing picker and per-channel keys
check("LMVTextColorPicker" in detail, "text colour picker not reused")
check("LMVTextColorKey" in kit and "textColor" in kit, "text colour key not from the channel table")

# Dual-slice build stays in place
check("ARCHS = arm64 arm64e" in makefile, "Makefile is no longer dual-arch")
check('ARCHS="arm64 arm64e"' in workflow, "CI no longer builds both slices")
check("gallery-panel.py" in workflow, "CI does not run this regression test")

# The picker header carries its @implementation; exactly one TU may include it.
includers = [path.name for path in PREFS.glob("*.m") if '#import "LMVMaterialPicker.h"' in read(path)]
check(includers == ["LMVMaterialPickerHost.m"], f"material picker included by {includers}")
check((PREFS / "LMVMaterialPickerAPI.h").exists(), "picker declaration-only header missing")
check("LMVCreateMaterialPicker" in read(PREFS / "LMVMaterialPickerHost.m"), "picker factory missing")

# 4.3.6 pages and motion
pages = read(PREFS / "LMVGalleryPages.m")
check("@implementation LMVMaterialLibraryController" in pages, "material library page missing")
check("pushViewController:[LMVMaterialLibraryController new]" in gallery, "material tab does not open the library")
check("LMVGAddPressFeedback" in pages and "LMVGAddPressFeedback" in gallery, "press feedback not wired")
kitm = read(PREFS / "LMVGalleryKit.m")
check(kitm.count("void LMVGAddPressFeedback(UIView *view)") == 1, "press feedback defined more than once")
check("UIViewAnimationOptionTransitionCrossDissolve" in gallery, "covers do not cross-fade")
# 4.3.6: covers decoded at draw size (not the 144px list thumbnail) and one serial queue.
kit_impl = read(PREFS / "LMVGalleryKit.m")
check("AVAssetImageGenerator" in kit_impl and "maximumSize = CGSizeMake(maxPixel, maxPixel)" in kit_impl,
      "covers are not decoded at their display size")
check("DISPATCH_QUEUE_SERIAL" in kit_impl, "cover decoding is not serialised")
check("NSCache" in kit_impl, "covers have no memory cache")
check("LMVGLoadThumb" in read(PREFS / "LMVChannelDetailController.m"), "detail strip does not use small thumbs")
check("shouldRecognizeSimultaneouslyWithGestureRecognizer" in kit_impl,
      "press feedback can still swallow taps")

# 4.3.6 (C2): refresh after a material change, scene subtitles, tab selection,
# parallax, safe-area back button, import failure alert, reduce-motion support.
check("accessibilityValue isEqualToString:relative" in gallery, "home does not refresh a changed cover")
check("coverRelative" in detail, "detail does not refresh a changed cover")
check("material.tag = 1006" in gallery, "scene cards have no material subtitle")
check("LMVGLightHaptic" in gallery and "LMVGLightHaptic" in detail, "no haptic feedback")
check("LMVGReduceMotion" in gallery and "LMVGReduceMotion" in detail, "reduce-motion not honoured")
check("CGAffineTransformMakeScale(1.08, 1.08)" in gallery, "hero parallax missing")
check("imported == 0" in pages, "import failure has no alert")
check("UIColor.systemBlueColor" in gallery and "tab.tag = index" in gallery, "tab has no selected state")

# 4.3.6: hero plays, panels merged into scenes, direct material switch, 1500px covers.
check("buildPanelSection" not in gallery, "home still has the separate panel strip")
check("arrayByAddingObjectsFromArray:_panels" in gallery, "panels not merged into the scene grid")
check("cycleMaterial" in detail and "changeMaterialFromLongPress" in detail, "material button does not switch directly")
check("1500.0" in kit_impl, "hero covers are not 1500px")

# 4.3.6
check("LMVPanelGridController" not in pages and "LMVPanelGridController" not in read(PREFS / "LMVGalleryController.h"),
      "panel grid page still exists")
check("editingMaterials" in pages, "material editor missing")
check("deleteMaterialTapped" in pages and "renameMaterialTapped" in pages, "in-place delete/rename missing")
check("LMVCreateMaterialPicker" not in pages, "manage still opens the picker")
check('actionWithTitle:@"素材库"' not in gallery, "settings still lists 素材库")
check("显示场景与图片旋转" in gallery and "onRequestDisplaySettings" in gallery,
      "display settings entry missing from the sheet")
check("LMVEasterImageSettings" not in gallery, "gallery includes a header-only implementation")

# Unique implementations
check(len(re.findall(r"@implementation LMVChannelDetailController\b", detail)) == 1,
      "detail controller implemented more than once")
check(len(re.findall(r"@implementation LMVGalleryController\b", gallery)) == 1,
      "gallery controller implemented more than once")

if failures:
    for failure in failures:
        print("FAIL:", failure)
    sys.exit(1)
print("PASS: gallery page derives from the channel table, writes per-channel keys "
      "and notifications, keeps the classic list as fallback, and CI still builds "
      "arm64 + arm64e; device appearance not tested")
