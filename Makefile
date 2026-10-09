ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockMessageVideo
LockMessageVideo_FILES = Tweak.xm
LockMessageVideo_CFLAGS = -fobjc-arc
LockMessageVideo_FRAMEWORKS = UIKit Foundation AVFoundation CoreImage CoreVideo CoreMedia QuartzCore CoreGraphics ImageIO Photos PhotosUI

BUNDLE_NAME = LockMessageVideoPrefs
LockMessageVideoPrefs_FILES = LockMessageVideoPrefs/LMVPRootListController.m
LockMessageVideoPrefs_FRAMEWORKS = UIKit Foundation Photos PhotosUI AVFoundation CoreMedia CoreVideo ImageIO
LockMessageVideoPrefs_INSTALL_PATH = /Library/PreferenceBundles
LockMessageVideoPrefs_RESOURCE_FILES = LockMessageVideoPrefs/Info.plist
LockMessageVideoPrefs_CFLAGS = -fobjc-arc
LockMessageVideoPrefs_LDFLAGS = -F$(CURDIR)/Frameworks -framework Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
