ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:16.0
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = LockMessageVideoDiagnostic
LockMessageVideoDiagnostic_FILES = Diagnostic.xm
LockMessageVideoDiagnostic_CFLAGS = -fobjc-arc
LockMessageVideoDiagnostic_FRAMEWORKS = UIKit Foundation
include $(THEOS_MAKE_PATH)/tweak.mk

# Deliberately no production bundle, resources, or layout dependency.
