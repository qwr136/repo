export TARGET = iphone:14.5:14.5

ARCHS = arm64 arm64e
TARGET_CC  = clang
TARGET_CXX = clang++

PACKAGE_NAME = com.xiaofei.wxkeyboardtoolbar
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WXKeyboardToolbar
WXKeyboardToolbar_FILES = Tweak.xm
WXKeyboardToolbar_CFLAGS = -fobjc-arc
WXKeyboardToolbar_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = WXKeyboardToolbarPrefs
WXKeyboardToolbarPrefs_FILES = Prefs/WXKeyboardToolbarPrefsRootListController.m
WXKeyboardToolbarPrefs_INSTALL_PATH = /Library/PreferenceBundles
WXKeyboardToolbarPrefs_FRAMEWORKS = UIKit
WXKeyboardToolbarPrefs_LDFLAGS = -undefined dynamic_lookup
WXKeyboardToolbarPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
