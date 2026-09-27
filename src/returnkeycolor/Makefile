export TARGET = iphone:14.5:14.5

# 键盘在 App 进程（arm64）和 SpringBoard 锁屏/聚焦搜索（arm64e）都会渲染，编真双架构
ARCHS = arm64 arm64e
TARGET_CC = clang
TARGET_CXX = clang++

PACKAGE_NAME = com.xiaofei.returnkeycolor

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ReturnKeyColor
ReturnKeyColor_FILES = Tweak.m Tweak.swift
ReturnKeyColor_CFLAGS = -fobjc-arc
# 补上 iOS SDK 的 Swift 模块路径，否则 swiftc 找不到 _Concurrency/_StringProcessing 等
# 标准库模块，会触发编译器内部崩溃（The bare ErrorType singleton is already canonical）
ReturnKeyColor_SWIFTFLAGS = -Xcc -fobjc-arc -I$(THEOS_SDK_PATH)/usr/lib/swift -F$(THEOS_SDK_PATH)/System/Library/Frameworks

include $(THEOS_MAKE_PATH)/tweak.mk
