/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 * 
 * 非越狱模式 - 只在当前应用内模拟位置
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, GPSSimulatorMode) {
    GPSSimulatorModeSingle,    // 单点模式
    GPSSimulatorModeRoute,     // 路线模式
    GPSSimulatorModeRandom     // 随机漫步模式
};

@interface GPSLocationSimulator : NSObject <CLLocationManagerDelegate>

/**
 * 获取共享实例
 */
+ (instancetype)sharedInstance;

/**
 * 初始化设置
 */
- (void)setup;

/**
 * 模拟位置到指定坐标
 * @param coordinate 目标坐标
 */
- (void)simulateLocation:(CLLocationCoordinate2D)coordinate;

/**
 * 模拟位置到指定坐标和高度
 * @param coordinate 目标坐标
 * @param altitude 高度（米）
 * @param accuracy 精度（米）
 */
- (void)simulateLocation:(CLLocationCoordinate2D)coordinate 
                altitude:(CLLocationDistance)altitude 
                accuracy:(CLLocationAccuracy)accuracy;

/**
 * 沿路线行走
 * @param coordinates 坐标数组
 * @param speed 速度（米/秒）
 */
- (void)simulateRouteWithCoordinates:(NSArray<NSValue *> *)coordinates
                               speed:(CLLocationSpeed)speed;

/**
 * 开始随机漫步
 * @param centerCoordinate 中心点坐标
 * @param radius 半径范围（米）
 */
- (void)startRandomWalkFromCoordinate:(CLLocationCoordinate2D)centerCoordinate 
                          withinRadius:(CLLocationDistance)radius;

/**
 * 停止位置模拟
 */
- (void)stopLocationSimulation;

/**
 * 获取当前模拟状态
 * @return 是否正在模拟位置
 */
- (BOOL)isSimulating;

/**
 * 获取当前模拟模式
 */
@property (nonatomic, readonly) GPSSimulatorMode simulationMode;

/**
 * 当前位置管理器
 */
@property (nonatomic, strong) CLLocationManager *locationManager;

/**
 * 最后一次模拟的位置
 */
@property (nonatomic, strong, readonly) CLLocation *lastSimulatedLocation;

@end

NS_ASSUME_NONNULL_END