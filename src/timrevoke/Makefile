export TARGET = iphone:14.5:14.5

# TIM 是 App Store 应用，实际架构为 arm64（第三方 App 一般不带 arm64e ABI），
# 只编 arm64 最稳，避免 arm64e 指针校验（PAC）导致的注入后闪退。
ARCHS = arm64
TARGET_CC = clang
TARGET_CXX = clang++

PACKAGE_NAME = com.xiaofei.timantirevoke

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = TIMAntiRevoke
TIMAntiRevoke_FILES = Tweak.x
TIMAntiRevoke_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function

include $(THEOS_MAKE_PATH)/tweak.mk
