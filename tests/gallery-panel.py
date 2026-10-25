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

for name in ("LMVGalleryKit.h", "LMVGalleryController.m", "LMVChannelDetailController.m"):
    check((PREFS / name).exists(), f"missing {name}")

# Bundle wiring
check("LMVGalleryController.m" in makefile and "LMVChannelDetailController.m" in makefile,
      "gallery sources not in LockMessageVideoPrefs_FILES")
check("LMVGalleryController.m" in makefile.split("LockMessageVideoPrefs_FILES =", 1)[-1].split("\n", 1)[0],
      "gallery controller outside the prefs bundle file list")

# Version agreement (the receipt compares these three)
check("LMV_VERSION = 4.3.0" in makefile, "Makefile version not 4.3.0")
check(re.search(r"^Version: 4\.3\.0$", control, re.M) is not None, "control version not 4.3.0")
check(plist.count("<string>4.3.0</string>") == 2, "Info.plist versions not 4.3.0")

# Entry: the classic list stays intact and the gallery opens exactly once per visit
check("@implementation LMVPRootListController" in root, "classic root controller removed")
check("pushViewController:[LMVGalleryController new]" in root, "gallery entry missing")
check("openedGallery" in root, "gallery latch missing")
check(root.count("pushViewController:[LMVGalleryController new]") == 1,
      "gallery pushed from more than one place")
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
check("LMVEnsureThumbnail" in kit, "covers do not reuse the thumbnail cache")
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
