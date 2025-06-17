/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import "GPSLocationModel.h"

typedef NS_ENUM(NSInteger, GPSAccuracyLevel) {
    GPSAccuracyLevelUltra,    // 超精确，误差极小
    GPSAccuracyLevelHigh,     // 高精度
    GPSAccuracyLevelMedium,   // 中等精度
    GPSAccuracyLevelLow,      // 低精度，模拟普通设备
    GPSAccuracyLevelVariable  // 自动根据环境变化
};

typedef NS_ENUM(NSInteger, GPSEnvironmentType) {
    GPSEnvironmentTypeUrban,       // 城市
    GPSEnvironmentTypeSuburban,    // 郊区
    GPSEnvironmentTypeRural,       // 乡村
    GPSEnvironmentTypeIndoor,      // 室内
    GPSEnvironmentTypeUnderground,  // 地下
    GPSEnvironmentTypeCanyon 
};

// 在头文件中添加类型定义
typedef NS_ENUM(NSInteger, GPSSimulatorMode) {
    GPSSimulatorModeSingle,
    GPSSimulatorModeRoute,
    GPSSimulatorModeRandomWalk
};

@interface GPSAdvancedLocationSimulator : NSObject

+ (instancetype)sharedInstance;

// 基本设置
@property (nonatomic, assign) GPSAccuracyLevel accuracyLevel;
@property (nonatomic, assign) GPSEnvironmentType environmentType;
@property (nonatomic, assign) BOOL enableSignalDrift; // 模拟真实GPS信号漂移
@property (nonatomic, assign) BOOL enableAutoAccuracy; // 自动调整精度

@property (nonatomic, strong) dispatch_source_t simulationTimer;

// 位置生成
- (CLLocation *)generateSimulatedLocationWithBase:(GPSLocationModel *)baseLocation;
- (CLLocation *)generateLocationInRadius:(double)radius fromLocation:(GPSLocationModel *)center;
- (CLHeading *)generateSimulatedHeadingWithBase:(double)baseHeading;

// 传感器数据增强
- (CMDeviceMotion *)complementaryMotionDataForLocation:(GPSLocationModel *)fromLoc 
                                            toLocation:(GPSLocationModel *)toLoc;

// 高级功能
- (NSArray<CLLocation *> *)simulateSignalLossAndRecovery:(GPSLocationModel *)lastKnownLocation 
                                               duration:(NSTimeInterval)seconds;
- (CLLocation *)simulateLocationWithInterference:(GPSLocationModel *)baseLocation 
                                interferenceLevel:(double)level;
- (void)calibrateSimulationParameters; // 优化模拟参数以提高真实度
- (void)startSimulationWithInitialLocation:(GPSLocationModel *)location 
                           updateInterval:(NSTimeInterval)interval 
                        completionHandler:(void (^)(GPSLocationModel *newLocation))handler;
- (void)stopSimulation;

// 公开的API方法
- (void)startSimulationWithInitialLocation:(GPSLocationModel *)initialLocation 
                           updateInterval:(NSTimeInterval)interval 
                        completionHandler:(void (^)(GPSLocationModel *))completionBlock;
- (void)stopSimulation;
- (GPSLocationModel *)generateNextLocation;

@end