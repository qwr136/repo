export TARGET = iphone:14.5:14.5

# 键盘在 App 进程（arm64）和 SpringBoard 锁屏/聚焦搜索（arm64e）都会渲染，编真双架构
ARCHS = arm64 arm64e
TARGET_CC = clang
TARGET_CXX = clang++

PACKAGE_NAME = com.xiaofei.returnkeycolor

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ReturnKeyColor
ReturnKeyColor_FILES = Tweak.x
ReturnKeyColor_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function

include $(THEOS_MAKE_PATH)/tweak.mk
