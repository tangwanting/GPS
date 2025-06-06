/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, GPSModuleType) {
    GPSModuleTypeCore,           // 核心位置模拟
    GPSModuleTypeRouting,        // 路径管理
    GPSModuleTypeNavigation,     // 导航功能
    GPSModuleTypeAutomation,     // 自动化功能
    GPSModuleTypeGeofencing,     // 地理围栏
    GPSModuleTypeAnalytics       // 数据分析
};

@protocol GPSModuleProtocol <NSObject>
- (void)initialize;
- (void)start;
- (void)stop;
- (NSDictionary *)currentStatus;
@end

@interface GPSModuleManager : NSObject

+ (instancetype)sharedInstance;

// 模块管理
- (void)registerModule:(id<GPSModuleProtocol>)module forType:(GPSModuleType)type;
- (id<GPSModuleProtocol>)moduleForType:(GPSModuleType)type;
- (void)startAllModules;
- (void)stopAllModules;
- (void)startModuleOfType:(GPSModuleType)type;
- (void)stopModuleOfType:(GPSModuleType)type;

// 配置项
@property (nonatomic, assign) BOOL debugMode;
@property (nonatomic, assign) BOOL powerSavingMode;

@end