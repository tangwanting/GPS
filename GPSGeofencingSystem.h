/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

@class GPSGeofenceRegion;

// 地理围栏委托
@protocol GPSGeofencingDelegate <NSObject>
@optional
- (void)didEnterGeofenceRegion:(GPSGeofenceRegion *)region;
- (void)didExitGeofenceRegion:(GPSGeofenceRegion *)region;
- (void)monitoringFailedForRegion:(GPSGeofenceRegion *)region withError:(NSError *)error;
@end

typedef NS_ENUM(NSInteger, GPSGeofenceType) {
    GPSGeofenceTypeCircular,      // 圆形区域
    GPSGeofenceTypePolygon,       // 多边形区域
    GPSGeofenceTypePath           // 路径缓冲区
};

@interface GPSGeofenceRegion : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) GPSGeofenceType type;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) BOOL active;
@property (nonatomic, assign) BOOL notifyOnEntry;
@property (nonatomic, assign) BOOL notifyOnExit;
@property (nonatomic, assign) BOOL notifyOnDwell;
@property (nonatomic, assign) NSTimeInterval dwellTime; // 停留触发时间
@property (nonatomic, strong) NSDictionary *metadata;   // 自定义数据

// 圆形区域专用属性
@property (nonatomic, assign) CLLocationCoordinate2D center;
@property (nonatomic, assign) CLLocationDistance radius;

// 多边形区域专用属性
@property (nonatomic, strong) NSArray<NSValue *> *coordinates; // CLLocationCoordinate2D array

// 路径区域专用属性
@property (nonatomic, strong) NSArray<CLLocation *> *pathPoints;
@property (nonatomic, assign) CLLocationDistance pathWidth;

// 生成对应的MapKit覆盖物
- (id<MKOverlay>)mapOverlay;

// 检查点是否在区域内
- (BOOL)containsCoordinate:(CLLocationCoordinate2D)coordinate;

@end

@interface GPSGeofencingSystem : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, weak) id<GPSGeofencingDelegate> delegate;

// 围栏管理
- (NSString *)addCircularGeofence:(CLLocationCoordinate2D)center 
                          radius:(CLLocationDistance)radius 
                            name:(NSString *)name;

- (NSString *)addPolygonGeofence:(NSArray<NSValue *> *)coordinates 
                           name:(NSString *)name;

- (NSString *)addPathGeofence:(NSArray<CLLocation *> *)path 
                      width:(CLLocationDistance)width 
                       name:(NSString *)name;

- (BOOL)updateGeofence:(GPSGeofenceRegion *)region;

- (BOOL)removeGeofenceWithIdentifier:(NSString *)identifier;

- (void)activateGeofence:(NSString *)identifier;

- (void)deactivateGeofence:(NSString *)identifier;

- (GPSGeofenceRegion *)geofenceWithIdentifier:(NSString *)identifier;

- (NSArray<GPSGeofenceRegion *> *)allGeofences;

- (NSArray<GPSGeofenceRegion *> *)activeGeofences;

// 监测功能
- (void)startMonitoring;

- (void)stopMonitoring;

- (void)checkLocationAgainstGeofences:(CLLocation *)location;

// 导入/导出
- (NSData *)exportGeofencesAsGeoJSON;

- (BOOL)importGeofencesFromGeoJSON:(NSData *)data error:(NSError **)error;

@end