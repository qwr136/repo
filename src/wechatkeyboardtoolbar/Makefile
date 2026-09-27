export TARGET = iphone:14.5:14.5

# 微信键盘扩展在 arm64 设备（及部分 arm64e）上运行，编真双架构 fat binary
ARCHS = arm64 arm64e
TARGET_CC = clang
TARGET_CXX = clang++

PACKAGE_NAME = com.xiaofei.wechatkeyboardtoolbar

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WeChatKeyboardToolbar
WeChatKeyboardToolbar_FILES = Tweak.m Tweak.swift
WeChatKeyboardToolbar_CFLAGS = -fobjc-arc
WeChatKeyboardToolbar_SWIFTFLAGS = -Xcc -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
