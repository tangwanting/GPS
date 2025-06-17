/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import "GPSModuleManager.h"
#import "GPSRecordingSystem.h"
#import "GPSSystemIntegration.h"
#import "GPSSmartPathEngine.h"
#import "GPSGeofencingSystem.h"
#import "GPSEventSystem.h"
#import "GPSAutomationSystem.h"
#import "GPSAnalyticsSystem.h"
#import "GPSAdvancedLocationSimulator.h"
#import "GPSLocationViewModel.h"
#import "GPSLocationModel.h"
#import "GPSRouteManager.h"
#import "GPSSmartPathEngine.h"

// 添加常量定义
// 全局常量定义
#define kUserDefaultsDomain                @"com.gps.locationspoofer"
#define kLocationSpoofingEnabledKey        @"LocationSpoofingEnabled"
#define kAltitudeSpoofingEnabledKey        @"AltitudeSpoofingEnabled"
#define kLatitudeKey                       @"latitude"
#define kLongitudeKey                      @"longitude"
#define kAltitudeKey                       @"altitude"
#define kSpeedKey                          @"speed" 
#define kCourseKey                         @"course"
#define kAccuracyKey                       @"accuracy"
#define kLocationHistoryKey                @"LocationHistory"
#define kMovingModeEnabledKey              @"MovingModeEnabled"
#define kMovingPathKey                     @"MovingPath"
#define kMovingSpeedKey                    @"MovingSpeed"
#define kRandomRadiusKey                   @"RandomRadius"
#define kStepDistanceKey                   @"StepDistance" 
#define kMovementModeKey                   @"MovementMode"

// 模块前向声明 - 移到这里，在使用之前声明
@interface GPSCoreLocationModule : NSObject <GPSModuleProtocol>
@property (nonatomic, strong) GPSAdvancedLocationSimulator *simulator;
@property (nonatomic, strong) GPSLocationViewModel *viewModel;
@end

@interface GPSRoutingModule : NSObject <GPSModuleProtocol>
@property (nonatomic, strong) GPSSmartPathEngine *pathEngine;
@property (nonatomic, strong) GPSRouteManager *routeManager;
@end

@interface GPSNavigationModule : NSObject <GPSModuleProtocol>
@end

@interface GPSAutomationModule : NSObject <GPSModuleProtocol>
@property (nonatomic, strong) GPSAutomationSystem *automationSystem;
@end

@interface GPSGeofencingModule : NSObject <GPSModuleProtocol, GPSGeofencingDelegate>
@property (nonatomic, strong) GPSGeofencingSystem *geofencingSystem;
@end

@interface GPSAnalyticsModule : NSObject <GPSModuleProtocol>
@property (nonatomic, strong) GPSAnalyticsSystem *analyticsSystem;
@property (nonatomic, strong) GPSRecordingSystem *recordingSystem;
@end

// 扩展GPSSystemIntegration声明缺失的方法
@interface GPSSystemIntegration (CoreIntegrationExtension)
- (void)applyAllProfiles;
@end

@interface GPSCoreIntegration : NSObject <GPSEventListener>

+ (instancetype)sharedInstance;
- (void)setupAllModules;
- (void)tearDownAllModules;
- (void)startAllModules;
- (void)pauseAllModules;

@end

@implementation GPSCoreIntegration

+ (instancetype)sharedInstance {
    static GPSCoreIntegration *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 注册为事件监听者
        [[GPSEventSystem sharedInstance] addEventListener:self forEventTypes:@[
            @(GPSEventTypeSystemStateChanged),
            @(GPSEventTypeError)
        ]];
    }
    return self;
}

- (void)setupAllModules {
    NSLog(@"GPS++ 正在初始化所有功能模块...");
    
    // 模块管理器
    GPSModuleManager *moduleManager = [GPSModuleManager sharedInstance];
    
    // 1. 注册核心位置模拟模块 (自定义实现，非类文件)
    [self registerCoreLocationModule];
    
    // 2. 注册路径管理模块
    [self registerRoutingModule];
    
    // 3. 注册导航功能模块
    [self registerNavigationModule];
    
    // 4. 注册自动化功能模块
    [self registerAutomationModule];
    
    // 5. 注册地理围栏模块
    [self registerGeofencingModule];
    
    // 6. 注册数据分析模块
    [self registerAnalyticsModule];
    
    NSLog(@"GPS++ 所有功能模块已完成初始化");
}

- (void)registerCoreLocationModule {
    // 创建位置模拟核心模块
    id<GPSModuleProtocol> coreModule = [[GPSCoreLocationModule alloc] init];
    [[GPSModuleManager sharedInstance] registerModule:coreModule forType:GPSModuleTypeCore];
}

- (void)registerRoutingModule {
    // 创建路径管理模块
    id<GPSModuleProtocol> routingModule = [[GPSRoutingModule alloc] init];
    [[GPSModuleManager sharedInstance] registerModule:routingModule forType:GPSModuleTypeRouting];
}

- (void)registerNavigationModule {
    // 创建导航模块
    id<GPSModuleProtocol> navigationModule = [[GPSNavigationModule alloc] init];
    [[GPSModuleManager sharedInstance] registerModule:navigationModule forType:GPSModuleTypeNavigation];
}

- (void)registerAutomationModule {
    // 创建自动化模块
    id<GPSModuleProtocol> automationModule = [[GPSAutomationModule alloc] init];
    [[GPSModuleManager sharedInstance] registerModule:automationModule forType:GPSModuleTypeAutomation];
}

- (void)registerGeofencingModule {
    // 创建地理围栏模块
    id<GPSModuleProtocol> geofencingModule = [[GPSGeofencingModule alloc] init];
    [[GPSModuleManager sharedInstance] registerModule:geofencingModule forType:GPSModuleTypeGeofencing];
}

- (void)registerAnalyticsModule {
    // 创建数据分析模块
    id<GPSModuleProtocol> analyticsModule = [[GPSAnalyticsModule alloc] init];
    [[GPSModuleManager sharedInstance] registerModule:analyticsModule forType:GPSModuleTypeAnalytics];
}

- (void)startAllModules {
    [[GPSModuleManager sharedInstance] startAllModules];
}

- (void)pauseAllModules {
    // 模块暂停，但不彻底关闭
    GPSModuleManager *manager = [GPSModuleManager sharedInstance];
    [manager stopModuleOfType:GPSModuleTypeAnalytics];
    [manager stopModuleOfType:GPSModuleTypeGeofencing];
    [manager stopModuleOfType:GPSModuleTypeAutomation];
}

- (void)tearDownAllModules {
    [[GPSModuleManager sharedInstance] stopAllModules];
    
    // 清理其他资源
    [[GPSEventSystem sharedInstance] removeEventListener:self];
}

#pragma mark - GPSEventListener
- (void)onEvent:(GPSEventData *)event {
    if (event.type == GPSEventTypeError) {
        NSLog(@"GPS++ 系统错误: %@", event.payload);
    } else if (event.type == GPSEventTypeSystemStateChanged) {
        NSLog(@"GPS++ 系统状态变更: %@", event.payload);
    }
}

@end

#pragma mark - 模块实现

@implementation GPSCoreLocationModule

- (instancetype)init {
    if (self = [super init]) {
        _simulator = [GPSAdvancedLocationSimulator sharedInstance];
        _viewModel = [GPSLocationViewModel sharedInstance];
    }
    return self;
}

- (void)start {
    // 如果已启用位置伪装，启动模拟器
    if (self.viewModel.isLocationSpoofingEnabled) {
        GPSLocationModel *location = [self.viewModel currentLocation];
        if (location) {
            __weak typeof(self) weakSelf = self;
            [self.simulator startSimulationWithInitialLocation:location 
                                           updateInterval:0.5  // 增加更新频率 
                                        completionHandler:^(GPSLocationModel *newLocation) {
                if (newLocation) {
                    [weakSelf.viewModel setCurrentLocation:newLocation];
                    
                    // 发布位置变更事件
                    [[GPSEventSystem sharedInstance] publishEvent:GPSEventTypeLocationChanged 
                                                 withPayload:newLocation];
                                                 
                    // 应用所有的配置文件更改
                    [[GPSSystemIntegration sharedInstance] applyAllProfiles];
                }
            }];
            
            // 通知系统GPS已启动
            [[NSNotificationCenter defaultCenter] postNotificationName:@"GPSSimulationStarted" object:nil];
        } else {
            NSLog(@"无法启动模拟：当前位置为空");
        }
    }
    
    NSLog(@"GPS++ 核心位置模拟模块已启动");
}

- (void)stop {
    [self.simulator stopSimulation];
    NSLog(@"GPS++ 核心位置模拟模块已停止");
}

- (void)reset {
    [self stop];
    // 重置所有设置但保留当前位置
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    double latitude = [defaults doubleForKey:kLatitudeKey];
    double longitude = [defaults doubleForKey:kLongitudeKey];
    
    // 清除所有设置
    NSArray *keysToRemove = @[
        kLocationSpoofingEnabledKey,
        kAltitudeSpoofingEnabledKey,
        kSpeedKey,
        kCourseKey,
        kAccuracyKey,
        kMovingModeEnabledKey,
        kMovementModeKey,
        kMovingSpeedKey,
        kRandomRadiusKey,
        kStepDistanceKey
    ];
    
    for (NSString *key in keysToRemove) {
        [defaults removeObjectForKey:key];
    }
    
    // 保留位置信息
    [defaults setDouble:latitude forKey:kLatitudeKey];
    [defaults setDouble:longitude forKey:kLongitudeKey];
    [defaults setDouble:50.0 forKey:kAltitudeKey];
    [defaults synchronize];
    
    // 重新加载设置
    [self.viewModel loadSettings];
}

@end

@implementation GPSRoutingModule

- (void)initialize {
    self.pathEngine = [GPSSmartPathEngine sharedInstance];
    self.routeManager = [GPSRouteManager sharedInstance];
    NSLog(@"GPS++ 路径管理模块已初始化");
}

- (void)start {
    NSLog(@"GPS++ 路径管理模块已启动");
}

- (void)stop {
    NSLog(@"GPS++ 路径管理模块已停止");
}

- (NSDictionary *)currentStatus {
    return @{
        @"availableRoutes": [self.routeManager savedRouteNames] ?: @[]
    };
}

@end

@implementation GPSNavigationModule

- (void)initialize {
    NSLog(@"GPS++ 导航功能模块已初始化");
}

- (void)start {
    NSLog(@"GPS++ 导航功能模块已启动");
}

- (void)stop {
    NSLog(@"GPS++ 导航功能模块已停止");
}

- (NSDictionary *)currentStatus {
    return @{
        @"active": @NO,
        @"status": @"就绪"
    };
}

@end


@implementation GPSAutomationModule

- (void)initialize {
    self.automationSystem = [GPSAutomationSystem sharedInstance];
    NSLog(@"GPS++ 自动化功能模块已初始化");
}

- (void)start {
    [self.automationSystem scheduleRuleEvaluation:60.0]; // 每分钟检查一次规则
    NSLog(@"GPS++ 自动化功能模块已启动");
}

- (void)stop {
    [self.automationSystem scheduleRuleEvaluation:0]; // 停止检查
    NSLog(@"GPS++ 自动化功能模块已停止");
}

- (NSDictionary *)currentStatus {
    return @{
        @"ruleCount": @([[self.automationSystem allRules] count])
    };
}

@end

@implementation GPSGeofencingModule

- (void)initialize {
    self.geofencingSystem = [GPSGeofencingSystem sharedInstance];
    self.geofencingSystem.delegate = self;
    NSLog(@"GPS++ 地理围栏模块已初始化");
}

- (void)start {
    [self.geofencingSystem startMonitoring];
    NSLog(@"GPS++ 地理围栏模块已启动");
}

- (void)stop {
    [self.geofencingSystem stopMonitoring];
    NSLog(@"GPS++ 地理围栏模块已停止");
}

- (NSDictionary *)currentStatus {
    return @{
        @"geofenceCount": @([[self.geofencingSystem activeGeofences] count])
    };
}

#pragma mark - GPSGeofencingDelegate

- (void)didEnterGeofenceRegion:(GPSGeofenceRegion *)region {
    // 发布地理围栏进入事件
    [[GPSEventSystem sharedInstance] publishEvent:GPSEventTypeGeofenceEnter withPayload:region];
}

- (void)didExitGeofenceRegion:(GPSGeofenceRegion *)region {
    // 发布地理围栏退出事件
    [[GPSEventSystem sharedInstance] publishEvent:GPSEventTypeGeofenceExit withPayload:region];
}

- (void)monitoringFailedForRegion:(GPSGeofenceRegion *)region withError:(NSError *)error {
    // 发布错误事件
    [[GPSEventSystem sharedInstance] publishEvent:GPSEventTypeError 
                                      withPayload:error 
                                         metadata:@{@"region": region.name ?: @"unknown"}];
}

@end

@implementation GPSAnalyticsModule

- (void)initialize {
    self.analyticsSystem = [GPSAnalyticsSystem sharedInstance];
    self.recordingSystem = [GPSRecordingSystem sharedInstance];
    NSLog(@"GPS++ 数据分析模块已初始化");
}

- (void)start {
    NSLog(@"GPS++ 数据分析模块已启动");
}

- (void)stop {
    NSLog(@"GPS++ 数据分析模块已停止");
}

- (NSDictionary *)currentStatus {
    return @{
        @"recordingState": @(self.recordingSystem.recordingState),
        @"playbackState": @(self.recordingSystem.playbackState)
    };
}

@end