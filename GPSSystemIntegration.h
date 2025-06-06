/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h> // CoreLocation 框架

typedef NS_ENUM(NSInteger, GPSIntegrationLevel) {
    GPSIntegrationLevelNormal,    // 基础集成
    GPSIntegrationLevelDeep,      // 深度集成(需权限)
    GPSIntegrationLevelSystem     // 系统级集成(需越狱)
};

typedef NS_ENUM(NSInteger, GPSIntegrationTarget) {
    GPSIntegrationTargetSpecificApp,  // 特定应用
    GPSIntegrationTargetAllApps,      // 所有应用
    GPSIntegrationTargetSystemServices // 系统服务
};

@interface GPSAppIntegrationProfile : NSObject
@property (nonatomic, copy) NSString *bundleId;
@property (nonatomic, copy) NSString *appName;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL useCustomLocation;
@property (nonatomic, assign) CLLocationCoordinate2D customCoordinate;
@property (nonatomic, strong) NSDictionary *customSettings;
@end

/**
 * GPS系统集成类
 * 负责将GPS定位功能集成到其他应用程序以及系统级服务中
 * 支持三种集成级别: 基础、深度和系统级
 */
@interface GPSSystemIntegration : NSObject

// 方法的文档注释
/**
 * 获取共享单例实例
 * @return GPSSystemIntegration 共享实例
 */
+ (instancetype)sharedInstance;

/**
 * 检查当前可用的集成级别
 * @return GPSIntegrationLevel 当前可用的最高级别
 */
@property (nonatomic, assign, readonly) GPSIntegrationLevel availableIntegrationLevel;
- (BOOL)canIntegrateWithTarget:(GPSIntegrationTarget)target;
- (BOOL)isIntegratedWithApp:(NSString *)bundleId;

// 应用集成
- (void)enableIntegrationForApp:(NSString *)bundleId;
- (void)disableIntegrationForApp:(NSString *)bundleId;
- (void)setProfile:(GPSAppIntegrationProfile *)profile forApp:(NSString *)bundleId;
- (GPSAppIntegrationProfile *)profileForApp:(NSString *)bundleId;
- (NSArray<GPSAppIntegrationProfile *> *)allProfiles;
- (void)installLocationHookForApp:(NSString *)bundleId coordinate:(CLLocationCoordinate2D)coordinate;
- (void)applyLocationSpoofingForSingleApp:(NSString *)bundleId withProfile:(GPSAppIntegrationProfile *)profile;
- (void)applySystemWideLocationSpoofing:(GPSAppIntegrationProfile *)profile;

// 系统集成
- (void)enableSystemWideIntegration:(BOOL)enable;
- (BOOL)isSystemWideIntegrationEnabled;
- (void)registerSystemTrigger:(UIGestureRecognizer *)gesture;
- (void)updateStatusBarIndicator:(BOOL)show;

// 性能管理
- (void)optimizeBatteryUsage:(BOOL)optimize;
- (void)optimizeMemoryUsage:(BOOL)optimize;
- (void)setIntegrationPriority:(NSInteger)priority; // 1-5, 5最高

// 权限支持
- (void)requestEnhancedPermissions:(void (^)(BOOL granted, NSError *error))completion;
- (BOOL)hasSystemPrivileges;
- (void)presentPermissionsExplanation;
- (BOOL)attemptToGetEnhancedPermissions; // 添加此方法
- (void)applyIntegrationPrioritySettings; // 添加此方法

@end