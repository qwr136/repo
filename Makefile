ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockMessageVideo
LockMessageVideo_FILES = Tweak.xm
LockMessageVideo_CFLAGS = -fobjc-arc
LockMessageVideo_FRAMEWORKS = UIKit Foundation AVFoundation Photos
LockMessageVideo_PRIVATE_FRAMEWORKS = Preferences

BUNDLE_NAME = LockMessageVideoPrefs
LockMessageVideoPrefs_FILES = LockMessageVideoPrefs/LMVPRootListController.m LockMessageVideoPrefs/LMVPVideoPickerController.m
LockMessageVideoPrefs_FRAMEWORKS = UIKit Foundation Photos
LockMessageVideoPrefs_PRIVATE_FRAMEWORKS = Preferences
LockMessageVideoPrefs_INSTALL_PATH = /Library/PreferenceBundles
LockMessageVideoPrefs_CFLAGS = -fobjc-arc

SUBPROJECTS += LockMessageVideoPrefs

include $(THEOS_MAKE_PATH)/aggregate.mk
include $(THEOS_MAKE_PATH)/tweak.mk
