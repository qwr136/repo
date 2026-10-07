ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockMessageVideoMessageDiagnostic
LockMessageVideoMessageDiagnostic_FILES = MessageDiagnostic.xm
LockMessageVideoMessageDiagnostic_CFLAGS = -fobjc-arc
LockMessageVideoMessageDiagnostic_FRAMEWORKS = UIKit Foundation QuartzCore

BUNDLE_NAME = LockMessageVideoMessageDiagnosticPrefs
LockMessageVideoMessageDiagnosticPrefs_FILES = DiagnosticPrefs/DiagnosticRootListController.m
LockMessageVideoMessageDiagnosticPrefs_FRAMEWORKS = UIKit Foundation
LockMessageVideoMessageDiagnosticPrefs_INSTALL_PATH = /Library/PreferenceBundles
LockMessageVideoMessageDiagnosticPrefs_RESOURCE_FILES = DiagnosticPrefs/Info.plist DiagnosticPrefs/Root.plist
LockMessageVideoMessageDiagnosticPrefs_CFLAGS = -fobjc-arc
LockMessageVideoMessageDiagnosticPrefs_LDFLAGS = -F$(THEOS_PROJECT_DIR)/Frameworks -framework Preferences

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
