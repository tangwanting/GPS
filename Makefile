# 插件：显示编译成功，显示的信息
PACKAGE_IDENTIFIER = com.pxx917144686.gps
PACKAGE_NAME = GPS++
PACKAGE_VERSION = 0.3
PACKAGE_ARCHITECTURE = iphoneos-arm64 iphoneos-arm64e
PACKAGE_REVISION = 1
PACKAGE_SECTION = Tweaks
PACKAGE_DEPENDS = firmware (>= 14.0), mobilesubstrate
PACKAGE_DESCRIPTION = 功能强大的iOS位置工具

# 插件：编译时，引用的信息
define Package/GPS++
  Package: com.pxx917144686.gps
  Name: GPS++
  Version: 0.3
  Architecture: iphoneos-arm64 iphoneos-arm64e
  Author: pxx917144686
  Section: Tweaks
  Depends: firmware (>= 14.0), mobilesubstrate
endef

# 直接输出到根路径
export THEOS_PACKAGE_DIR = $(CURDIR)

# TARGET
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

# 关闭严格错误检查和警告
export DEBUG = 0
export THEOS_STRICT_LOGOS = 0
export ERROR_ON_WARNINGS = 0
export LOGOS_DEFAULT_GENERATOR = internal

# Rootless 插件配置
export THEOS_PACKAGE_SCHEME = rootless
THEOS_PACKAGE_INSTALL_PREFIX = /var/jb

# 系统库
INSTALL_TARGET_PROCESSES = SpringBoard locationd backboardd thermalmonitord mediaserverd syncdefaultsd ReportCrash aggregated com.apple.Maps Weather

# 引入 Theos 的通用设置
include $(THEOS)/makefiles/common.mk

# 插件名称
TWEAK_NAME = GPS++

# 源代码文件
GPS++_FILES = Tweak.x MapViewController.m GPSAdvancedSettingsViewController.m GPSLocationModel.m \
              GPSLocationViewModel.m GPSCoordinateUtils.m GPSRouteManager.m \
              GPSAnalyticsSystem.m GPSAutomationSystem.m GPSGeofencingSystem.m GPSEventSystem.m \
              GPSAdvancedLocationSimulator.m GPSAdvancedMapController.m GPSModuleManager.m \
              GPSRecordingSystem.m GPSDashboardViewController.m GPSSystemIntegration.m \
              GPSCoreIntegration.m GPSSmartPathEngine.m GPSElevationService.m GPSExtensions.m \
              GPSLocationSimulator.m GPSManager.m GPSControlPanelViewController.m

# 编译标志
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -w

# 使用全局C++
CXXFLAGS += -std=c++11
CCFLAGS += -std=c++11

# 保留内部生成器选项
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal

# 框架
$(TWEAK_NAME)_FRAMEWORKS = UIKit CoreLocation MapKit QuartzCore CoreGraphics Foundation CoreMotion
$(TWEAK_NAME)_WEAK_FRAMEWORKS = UniformTypeIdentifiers CoreLocationUI

# 编译标志
$(TWEAK_NAME)_CFLAGS += -Wno-everything  # 禁用所有警告
$(TWEAK_NAME)_CFLAGS += -Wno-incomplete-implementation  # 禁用特定警告
$(TWEAK_NAME)_CFLAGS += -Wno-protocol  # 禁用协议警告

# 预处理变量
$(TWEAK_NAME)_CFLAGS += -DDOKIT_FULL_BUILD=1
$(TWEAK_NAME)_CFLAGS += -DDORAEMON_FULL_BUILD=1

include $(THEOS_MAKE_PATH)/tweak.mk