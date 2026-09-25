export THEOS_DEVICE_IP = localhost
export TARGET = iphone:14.5:14.5
# 只用 arm64：SpringBoard 注入稳定。
# 设置面板改为纯 plist（PreferenceLoader entry），不再编译任何 arm64e 二进制，
# 从根上避开 Linux 工具链 arm64e ABI 不兼容导致的闪退。
ARCHS = arm64
TARGET_CC = clang
TARGET_CXX = clang++
PACKAGE_NAME = com.xiaofei.notifybgvideo

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = LockVideo
LockVideo_FILES = Tweak.x
LockVideo_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
LockVideo_FRAMEWORKS = UIKit AVFoundation

SUBPROJECTS += LockVideoPrefs
include $(THEOS)/makefiles/aggregate.mk

include $(THEOS_MAKE_PATH)/tweak.mk
