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

@property (nonatomic, assign) BOOL isLocationSpoofingEnabled;
@property (nonatomic, assign) BOOL isAltitudeSpoofingEnabled;
@property (nonatomic, assign) GPSMovementMode movementMode;
@property (nonatomic, assign) double movingSpeed;
@property (nonatomic, assign) double randomRadius;
@property (nonatomic, assign) double stepDistance;
@property (nonatomic, strong, readonly) NSArray<GPSLocationModel *> *locationHistory;

+ (instancetype)sharedInstance;

- (GPSLocationModel *)currentLocation;
- (void)setCurrentLocation:(GPSLocationModel *)location;
- (void)saveLocation:(GPSLocationModel *)location withTitle:(NSString *)title;
- (void)clearHistory;
- (void)startMoving;
- (void)stopMoving;
- (CLLocation *)nextFakeLocation;
- (void)loadSettings;
- (void)saveSettings;

@end