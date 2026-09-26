export THEOS_DEVICE_IP = localhost
export TARGET = iphone:14.5:14.5
ARCHS = arm64
TARGET_CC = clang
TARGET_CXX = clang++
PACKAGE_NAME = com.xiaofei.msgbgvideo

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MsgVideo
MsgVideo_FILES = Tweak.x
MsgVideo_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
MsgVideo_FRAMEWORKS = UIKit AVFoundation

SUBPROJECTS += MsgVideoPrefs
include $(THEOS)/makefiles/aggregate.mk

include $(THEOS_MAKE_PATH)/tweak.mk
