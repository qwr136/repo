include $(THEOS)/makefiles/common.mk

ARCHS = arm64
BUNDLE_NAME = wetypeprefs
wetypeprefs_FILES = WETypeRootListController.m
wetypeprefs_CFLAGS = -fobjc-arc
wetypeprefs_FRAMEWORKS = UIKit Foundation
wetypeprefs_PRIVATE_FRAMEWORKS = Preferences
wetypeprefs_INSTALL_PATH = /Library/PreferenceBundles
wetypeprefs_INFOPLIST_KEY = NSPrincipalClass;WETypeRootListController

include $(THEOS_MAKE_PATH)/bundle.mk
