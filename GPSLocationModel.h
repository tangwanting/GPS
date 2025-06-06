/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

@interface GPSLocationModel : NSObject

@property (nonatomic, assign) double latitude;
@property (nonatomic, assign) double longitude;
@property (nonatomic, assign) double altitude;
@property (nonatomic, assign) double speed;
@property (nonatomic, assign) double course;
@property (nonatomic, assign) double accuracy;
@property (nonatomic, strong) NSString *title;
@property (nonatomic, strong) NSDate *timestamp;

@property (nonatomic, assign) CLLocationCoordinate2D coordinate;  
@property (nonatomic, strong) NSDictionary *metadata;
@property (nonatomic, assign) double horizontalAccuracy;
@property (nonatomic, assign) double verticalAccuracy;
@property (nonatomic, strong) NSDictionary *sensorData;

+ (GPSLocationModel *)modelWithLocation:(CLLocation *)location;
- (CLLocation *)toCLLocation;
- (NSDictionary *)toDictionary;
+ (GPSLocationModel *)modelWithDictionary:(NSDictionary *)dict;

@end