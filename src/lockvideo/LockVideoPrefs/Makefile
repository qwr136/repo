include $(THEOS)/makefiles/common.mk

# 用 arm64 编译（Linux 工具链编 arm64e 的 PAC ABI 不对会崩），
# 编完后由上层脚本把 cputype 伪装成 arm64e 过 dyld 校验
ARCHS = arm64

BUNDLE_NAME = LockVideoPrefs
LockVideoPrefs_FILES = LockVideoPrefsListController.m LockVideoMaterialCell.m
LockVideoPrefs_FRAMEWORKS = UIKit
LockVideoPrefs_PRIVATE_FRAMEWORKS = Preferences
LockVideoPrefs_CFLAGS = -fobjc-arc
LockVideoPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
