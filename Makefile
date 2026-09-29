ARCHS = arm64
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = wxkb WetType wxkb_plugin

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WetypeToolbarPlus
WetypeToolbarPlus_FILES = Tweak.x
WetypeToolbarPlus_CFLAGS = -fobjc-arc
WetypeToolbarPlus_FRAMEWORKS = UIKit Foundation
WetypeToolbarPlus_LDFLAGS = -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
