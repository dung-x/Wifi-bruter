include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = WiFiBruterPrefs
WiFiBruterPrefs_FILES = RootListController.m
WiFiBruterPrefs_INSTALL_PATH = /Library/PreferenceBundles
WiFiBruterPrefs_FRAMEWORKS = UIKit
WiFiBruterPrefs_CFLAGS = -fobjc-arc
WiFiBruterPrefs_ARCHS = arm64

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)$(CP) entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/WiFiBruterPrefs.plist$(ECHO_END)
