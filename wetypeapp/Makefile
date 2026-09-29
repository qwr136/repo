APPLICATION_NAME = WetypeCustomApp

WetypeCustomApp_FILES = src/main.m src/AppDelegate.m src/SettingsViewController.m
WetypeCustomApp_FRAMEWORKS = UIKit Foundation
WetypeCustomApp_INSTALL_PATH = /Applications
# 与 Tweak 一致的部署目标/架构（iOS 14+, 仅 arm64）
ARCHS = arm64
TARGET = iphone:clang:latest:14.0
# 签名在子项目目录内执行，用相对路径最稳妥（父项目 before-all 与独立构建都正确）
WetypeCustomApp_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/application.mk
