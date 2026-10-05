TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = NetSpeedPrefs
NetSpeedPrefs_FILES = QWRNetSpeedRootListController.m
NetSpeedPrefs_FRAMEWORKS = UIKit Foundation
NetSpeedPrefs_PRIVATE_FRAMEWORKS = Preferences
NetSpeedPrefs_INSTALL_PATH = /Library/PreferenceBundles
NetSpeedPrefs_CFLAGS = -fobjc-arc
NetSpeedPrefs_LDFLAGS = -undefined dynamic_lookup
NetSpeedPrefs_RESOURCE_FILES = Root.plist Info.plist

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp NetSpeedPrefs.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/NetSpeedPrefs.plist$(ECHO_END)
