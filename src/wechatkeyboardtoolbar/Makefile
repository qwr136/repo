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

# 真·PreferenceBundle（编译版）：bundle 内含可执行的 ListController
# （参照 KeyboardCustomizerPrefs.bundle 的结构：Info.plist + Root.plist + 可执行二进制）
# 注意：BUNDLE_NAME 必须显式声明，Theos 靠 *_NAME 登记 instance，否则整个 target 会被跳过
BUNDLE_NAME = WeChatKeyboardToolbarPrefs
WeChatKeyboardToolbarPrefs_FILES = Prefs/WeChatKeyboardToolbarPrefsRootListController.m
WeChatKeyboardToolbarPrefs_INSTALL_PATH = /Library/PreferenceBundles
WeChatKeyboardToolbarPrefs_FRAMEWORKS = UIKit
# CI 用的是 Xcode 的 iPhoneOS SDK（公开 SDK 不含私有框架），链接 -framework Preferences
# 会报 "framework 'Preferences' not found"。改为运行时解析符号：Preferences 在设置 App
# 进程内本就加载，ListController 的符号届时自然可用。
WeChatKeyboardToolbarPrefs_LDFLAGS = -undefined dynamic_lookup
WeChatKeyboardToolbarPrefs_CFLAGS = -fobjc-arc
include $(THEOS_MAKE_PATH)/bundle.mk
