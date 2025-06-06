/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "GPSLocationModel.h"
#import <MapKit/MapKit.h>

typedef NS_ENUM(NSInteger, GPSPathMovementMode) {
    GPSPathMovementModeWalk,
    GPSPathMovementModeRun,
    GPSPathMovementModeCycle,
    GPSPathMovementModeDrive,
    GPSPathMovementModeCustom
};

typedef NS_ENUM(NSInteger, GPSPathOptimizationType) {
    GPSPathOptimizationTypeNone,
    GPSPathOptimizationTypeDistance,
    GPSPathOptimizationTypeTime,
    GPSPathOptimizationTypeEnergy,
    GPSPathOptimizationTypeSafety
};

@interface GPSPathParameters : NSObject
@property (nonatomic, assign) GPSPathMovementMode movementMode;
@property (nonatomic, assign) double baseSpeed; // 米/秒
@property (nonatomic, assign) double variationFactor; // 速度变化因子 0.0-1.0
@property (nonatomic, assign) BOOL includeAltitude;
@property (nonatomic, assign) BOOL includeRealisticPauses;
@property (nonatomic, assign) double pauseProbability; // 0.0-1.0
@property (nonatomic, strong) NSDictionary *customParameters;
@end

@interface GPSSmartPathEngine : NSObject

+ (instancetype)sharedInstance;

// 路径生成
- (NSArray<GPSLocationModel *> *)generatePathFrom:(CLLocationCoordinate2D)start 
                                              to:(CLLocationCoordinate2D)end 
                                   withParameters:(GPSPathParameters *)params;

// 高级路径插值
- (NSArray<GPSLocationModel *> *)interpolatePathPoints:(NSArray<GPSLocationModel *> *)points 
                                             withCount:(NSInteger)count 
                                             smoothing:(BOOL)smooth;

// 路径优化
- (NSArray<GPSLocationModel *> *)optimizePath:(NSArray<GPSLocationModel *> *)path 
                                        type:(GPSPathOptimizationType)optimizationType;

// 实时路径调整
- (GPSLocationModel *)nextLocationOnPath:(NSArray<GPSLocationModel *> *)path 
                            afterLocation:(GPSLocationModel *)currentLocation 
                           withParameters:(GPSPathParameters *)params;

// 自动避障系统
- (NSArray<GPSLocationModel *> *)reroutePath:(NSArray<GPSLocationModel *> *)path 
                             avoidingRegions:(NSArray<MKPolyline *> *)regions;

@end