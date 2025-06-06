/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "GPSLocationModel.h"

typedef NS_ENUM(NSInteger, GPSEventType) {
    GPSEventTypeLocationChanged,
    GPSEventTypeRouteStarted,
    GPSEventTypeRoutePaused,
    GPSEventTypeRouteStopped,
    GPSEventTypeRouteCompleted,
    GPSEventTypeGeofenceEnter,
    GPSEventTypeGeofenceExit,
    GPSEventTypeSystemStateChanged,
    GPSEventTypeError
};

@interface GPSEventData : NSObject
@property (nonatomic, assign) GPSEventType type;
@property (nonatomic, strong) id payload;
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, strong) NSDictionary *metadata;
@end

@protocol GPSEventListener <NSObject>
- (void)onEvent:(GPSEventData *)event;
@end

@interface GPSEventSystem : NSObject

+ (instancetype)sharedInstance;

// 事件订阅管理
- (void)addEventListener:(id<GPSEventListener>)listener forEventTypes:(NSArray<NSNumber *> *)eventTypes;
- (void)removeEventListener:(id<GPSEventListener>)listener;
- (void)removeEventListener:(id<GPSEventListener>)listener forEventType:(GPSEventType)eventType;

// 事件发布
- (void)publishEvent:(GPSEventType)type withPayload:(id)payload;
- (void)publishEvent:(GPSEventType)type withPayload:(id)payload metadata:(NSDictionary *)metadata;

// 事件历史
- (NSArray<GPSEventData *> *)recentEventsOfType:(GPSEventType)type limit:(NSInteger)limit;
- (void)clearEventHistory;

@end