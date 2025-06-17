/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "GPSLocationModel.h"

typedef NS_ENUM(NSInteger, GPSMovementMode) {
    GPSMovementModeNone = 0,
    GPSMovementModeRandom,
    GPSMovementModeLinear,
    GPSMovementModePath,
    GPSMovementModeRoute
};

@interface GPSLocationViewModel : NSObject

// 现有属性
@property (nonatomic, assign) BOOL isLocationSpoofingEnabled;
@property (nonatomic, assign) BOOL isAltitudeSpoofingEnabled;
@property (nonatomic, strong) GPSLocationModel *currentLocation;

// 添加缺失的属性
@property (nonatomic, assign) BOOL isMovingModeEnabled;
@property (nonatomic, assign) NSInteger movementMode;
@property (nonatomic, assign) double movingSpeed;
@property (nonatomic, assign) double randomRadius;
@property (nonatomic, assign) double stepDistance;

// 现有方法
- (void)loadSettings;
- (void)saveSettings;
+ (instancetype)sharedInstance;

- (void)startMoving;
- (void)stopMoving;

@end