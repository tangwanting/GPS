/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import "GPSLocationModel.h"

@implementation GPSLocationModel

#pragma mark - 工厂方法

+ (GPSLocationModel *)modelWithLocation:(CLLocation *)location {
    if (!location) return nil;
    
    GPSLocationModel *model = [[GPSLocationModel alloc] init];
    model.latitude = location.coordinate.latitude;
    model.longitude = location.coordinate.longitude;
    model.altitude = location.altitude;
    model.speed = location.speed;
    model.course = location.course;
    model.accuracy = location.horizontalAccuracy;
    model.timestamp = location.timestamp;
    
    return model;
}

#pragma mark - 转换方法

- (CLLocation *)toCLLocation {
    CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(self.latitude, self.longitude);
    
    if (@available(iOS 13.4, *)) {
        return [[CLLocation alloc] initWithCoordinate:coordinate
                                             altitude:self.altitude
                                   horizontalAccuracy:self.accuracy
                                     verticalAccuracy:5.0
                                             course:self.course
                                              speed:self.speed
                                          timestamp:self.timestamp ?: [NSDate date]];
    } else {
        // 兼容旧版iOS
        return [[CLLocation alloc] initWithCoordinate:coordinate
                                             altitude:self.altitude
                                   horizontalAccuracy:self.accuracy
                                     verticalAccuracy:5.0
                                            timestamp:self.timestamp ?: [NSDate date]];
    }
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    [dict setObject:@(self.latitude) forKey:@"latitude"];
    [dict setObject:@(self.longitude) forKey:@"longitude"];
    [dict setObject:@(self.altitude) forKey:@"altitude"];
    
    if (self.speed >= 0) {
        [dict setObject:@(self.speed) forKey:@"speed"];
    }
    
    if (self.course >= 0) {
        [dict setObject:@(self.course) forKey:@"course"];
    }
    
    [dict setObject:@(self.accuracy) forKey:@"accuracy"];
    
    if (self.title) {
        [dict setObject:self.title forKey:@"title"];
    }
    
    if (self.timestamp) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        NSString *timeString = [formatter stringFromDate:self.timestamp];
        [dict setObject:timeString forKey:@"timestamp"];
    }
    
    return dict;
}

+ (GPSLocationModel *)modelWithDictionary:(NSDictionary *)dict {
    if (!dict) return nil;
    
    GPSLocationModel *model = [[GPSLocationModel alloc] init];
    
    model.latitude = [dict[@"latitude"] doubleValue];
    model.longitude = [dict[@"longitude"] doubleValue];
    model.altitude = [dict[@"altitude"] doubleValue];
    model.speed = [dict[@"speed"] doubleValue];
    model.course = [dict[@"course"] doubleValue];
    model.accuracy = [dict[@"accuracy"] doubleValue];
    model.title = dict[@"title"];
    
    if (dict[@"timestamp"]) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        model.timestamp = [formatter dateFromString:dict[@"timestamp"]];
    } else {
        model.timestamp = [NSDate date];
    }
    
    return model;
}

#pragma mark - 初始化方法

- (instancetype)init {
    if (self = [super init]) {
        // 设置默认值
        self.altitude = 0;
        self.speed = 0;
        self.course = 0;
        self.accuracy = 5.0;
        self.timestamp = [NSDate date];
        // 确保设置 coordinate 属性
        self.coordinate = CLLocationCoordinate2DMake(self.latitude, self.longitude);
    }
    return self;
}

// 添加 setter 方法以自动同步坐标属性
- (void)setLatitude:(double)latitude {
    _latitude = latitude;
    _coordinate = CLLocationCoordinate2DMake(latitude, _longitude);
}

- (void)setLongitude:(double)longitude {
    _longitude = longitude;
    _coordinate = CLLocationCoordinate2DMake(_latitude, longitude);
}

- (void)setCoordinate:(CLLocationCoordinate2D)coordinate {
    _coordinate = coordinate;
    _latitude = coordinate.latitude;
    _longitude = coordinate.longitude;
}

@end