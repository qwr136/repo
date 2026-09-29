ARCHS = arm64
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = wxkb WetType wxkb_plugin

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WetypeToolbarPlus
WetypeToolbarPlus_FILES = Tweak.x
WetypeToolbarPlus_CFLAGS = -fobjc-arc
WetypeToolbarPlus_FRAMEWORKS = UIKit Foundation
WetypeToolbarPlus_LDFLAGS = -Wl,-undefined,dynamic_lookup

# 独立设置 App（微信输入法自定义）作为越狱应用打包进同一个 deb：
# before-all 在 stage 拷贝 layout 之前，把 App 编好并拷到 layout/Applications，
# rootless 方案会自动重映射到 /var/jb/Applications。
before-all::
	@bash "$(THEOS_PROJECT_DIR)/build_app.sh" build

clean::
	@bash "$(THEOS_PROJECT_DIR)/build_app.sh" clean

include $(THEOS_MAKE_PATH)/tweak.mk
