TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = wxkb WetType wxkb_plugin

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WetypeToolbarPlus
WetypeToolbarPlus_FILES = Tweak.x
WetypeToolbarPlus_CFLAGS = -fobjc-arc
WetypeToolbarPlus_FRAMEWORKS = UIKit Foundation
WetypeToolbarPlus_LDFLAGS = -Wl,-undefined,dynamic_lookup

SUBPROJECTS += wetypeprefs

include $(THEOS_MAKE_PATH)/aggregate.mk
include $(THEOS_MAKE_PATH)/tweak.mk
