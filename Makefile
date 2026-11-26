include $(THEOS)/makefiles/common.mk

SUBPROJECTS = WiFiBruter WiFiBruterPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk

package:: stage
	@echo "Building package with prefix: $(THEOS_PACKAGE_INSTALL_PREFIX)"
