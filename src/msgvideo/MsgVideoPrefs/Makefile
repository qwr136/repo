include $(THEOS)/makefiles/common.mk

ARCHS = arm64

BUNDLE_NAME = MsgVideoPrefs
MsgVideoPrefs_FILES = MsgVideoPrefsListController.m MsgVideoMaterialCell.m
MsgVideoPrefs_FRAMEWORKS = UIKit
MsgVideoPrefs_PRIVATE_FRAMEWORKS = Preferences
MsgVideoPrefs_CFLAGS = -fobjc-arc
MsgVideoPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
