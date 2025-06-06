/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreLocation/CoreLocation.h>
#import "GPSSystemIntegration.h"

// 声明GPSElevationService类
@interface GPSElevationService : NSObject
+ (instancetype)sharedInstance;
- (void)getElevationForLocation:(CLLocationCoordinate2D)coordinate completion:(void(^)(double elevation, NSError *error))completion;
@end

// 声明GPSSmartPathEngine类
@interface GPSSmartPathEngine : NSObject
+ (instancetype)sharedInstance;
@end

// 声明扩展方法接口
@interface GPSSystemIntegration (AdditionalMethods)
- (void)enableContinuousBackgroundMode:(BOOL)enable;
- (void)clearCachedData;
- (void)runSystemDiagnostics:(void (^)(NSDictionary *results))completionHandler;

// 辅助方法
- (unsigned long long)getFreeMem;
- (float)getCPUUsage;

// 越狱检测方法声明
- (BOOL)isDeviceJailbroken;
- (BOOL)checkForPrivileges;
@end