ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = roothide
LMV_VERSION = 5.34
PACKAGE_VERSION = $(LMV_VERSION)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockMessageVideo
LockMessageVideo_FILES = Tweak.xm LMVTextColorPicker.m LMVStepperControl.m LMVPanelRowCell.m
LockMessageVideo_CFLAGS = -fobjc-arc
LockMessageVideo_CCFLAGS = -std=gnu++11
LockMessageVideo_LIBRARIES = roothide
LockMessageVideo_FRAMEWORKS = UIKit Foundation AVFoundation CoreImage CoreVideo CoreMedia QuartzCore CoreGraphics ImageIO Photos PhotosUI

BUNDLE_NAME = LockMessageVideoPrefs
LockMessageVideoPrefs_FILES = LMVPanelRowCell.m LockMessageVideoPrefs/LMVPRootListController.m LockMessageVideoPrefs/LMVPSettingCell.m LMVStepperControl.m LockMessageVideoPrefs/LMVGalleryController.m LockMessageVideoPrefs/LMVGalleryPages.m LockMessageVideoPrefs/LMVGalleryKit.m LockMessageVideoPrefs/LMVChannelDetailController.m LockMessageVideoPrefs/LMVMaterialPickerHost.m LockMessageVideoPrefs/LMVTuneController.m LockMessageVideoPrefs/LMVTuneListController.m LMVTextColorPicker.m
LockMessageVideoPrefs_FRAMEWORKS = UIKit Foundation Photos PhotosUI AVFoundation CoreMedia CoreVideo ImageIO QuartzCore
LockMessageVideoPrefs_INSTALL_PATH = /Library/PreferenceBundles
LockMessageVideoPrefs_RESOURCE_FILES = LockMessageVideoPrefs/Info.plist LockMessageVideoPrefs/icon.png LockMessageVideoPrefs/icon@2x.png LockMessageVideoPrefs/icon@3x.png
LockMessageVideoPrefs_CFLAGS = -fobjc-arc -Wno-unused-function
LockMessageVideoPrefs_LIBRARIES = roothide
LockMessageVideoPrefs_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk

# 5.34: Linux Theos writes cpusubtype 0x2 for arm64e while the code it emits is
# already ptrauth ABI v1; dyld then rejects the slice on A12+. Restore the bit
# before packaging. Idempotent, and a no-op on the macOS toolchain.
before-package::
	@python3 tools/fix-arm64e.py \
		"$(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/LockMessageVideo.dylib" \
		"$(THEOS_STAGING_DIR)/Library/PreferenceBundles/LockMessageVideoPrefs.bundle/LockMessageVideoPrefs"
