ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = roothide
LMV_VERSION = 2.82
PACKAGE_VERSION = $(LMV_VERSION)

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockMessageVideo
LockMessageVideo_FILES = Tweak.xm LMVTextColorPicker.m LMVSettingsVideoChannel.m
LockMessageVideo_CFLAGS = -fobjc-arc
LockMessageVideo_CCFLAGS = -std=gnu++11
LockMessageVideo_LIBRARIES = roothide
LockMessageVideo_FRAMEWORKS = UIKit Foundation AVFoundation CoreImage CoreVideo CoreMedia QuartzCore CoreGraphics ImageIO Photos PhotosUI

BUNDLE_NAME = LockMessageVideoPrefs
LockMessageVideoPrefs_FILES = LockMessageVideoPrefs/LMVMenuListController.m LockMessageVideoPrefs/LMVPRootListController.m LockMessageVideoPrefs/LMVSettingsVideoController.m LockMessageVideoPrefs/LMVTuneController.m LockMessageVideoPrefs/LMVTuneListController.m LMVTextColorPicker.m
LockMessageVideoPrefs_FRAMEWORKS = UIKit Foundation Photos PhotosUI AVFoundation CoreMedia CoreVideo ImageIO QuartzCore
LockMessageVideoPrefs_INSTALL_PATH = /Library/PreferenceBundles
LockMessageVideoPrefs_RESOURCE_FILES = LockMessageVideoPrefs/Info.plist LockMessageVideoPrefs/icon.png LockMessageVideoPrefs/icon@2x.png LockMessageVideoPrefs/icon@3x.png
LockMessageVideoPrefs_CFLAGS = -fobjc-arc
LockMessageVideoPrefs_LIBRARIES = roothide
LockMessageVideoPrefs_PRIVATE_FRAMEWORKS = Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
