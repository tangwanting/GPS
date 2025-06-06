/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import "GPSCoordinateUtils.h"
#import <math.h>

#define EARTH_RADIUS 6371000.0 // 地球平均半径(米)

@implementation GPSCoordinateUtils

+ (CLLocationDistance)distanceBetweenCoordinates:(CLLocationCoordinate2D)coord1 andCoord:(CLLocationCoordinate2D)coord2 {
    // 将经纬度转换为弧度
    double lat1 = coord1.latitude * M_PI / 180.0;
    double lon1 = coord1.longitude * M_PI / 180.0;
    double lat2 = coord2.latitude * M_PI / 180.0;
    double lon2 = coord2.longitude * M_PI / 180.0;
    
    // Haversine公式计算球面距离
    double dLat = lat2 - lat1;
    double dLon = lon2 - lon1;
    double a = sin(dLat/2) * sin(dLat/2) + cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2);
    double c = 2 * atan2(sqrt(a), sqrt(1-a));
    return EARTH_RADIUS * c;
}

+ (CLLocationCoordinate2D)destinationCoordinateFromCoordinate:(CLLocationCoordinate2D)startCoord
                                                  withBearing:(CLLocationDirection)bearing
                                                  andDistance:(CLLocationDistance)distance {
    // 将角度转为弧度
    double bearingRad = bearing * M_PI / 180.0;
    double latRad = startCoord.latitude * M_PI / 180.0;
    double lonRad = startCoord.longitude * M_PI / 180.0;
    
    // 计算目标点的弧度坐标
    double distRatio = distance / EARTH_RADIUS;
    double destLatRad = asin(sin(latRad) * cos(distRatio) + 
                            cos(latRad) * sin(distRatio) * cos(bearingRad));
    double destLonRad = lonRad + atan2(sin(bearingRad) * sin(distRatio) * cos(latRad), 
                                     cos(distRatio) - sin(latRad) * sin(destLatRad));
    
    // 弧度转回经纬度
    CLLocationCoordinate2D destCoord;
    destCoord.latitude = destLatRad * 180.0 / M_PI;
    destCoord.longitude = destLonRad * 180.0 / M_PI;
    
    // 修正经度超出范围
    while (destCoord.longitude > 180.0) destCoord.longitude -= 360.0;
    while (destCoord.longitude < -180.0) destCoord.longitude += 360.0;
    
    return destCoord;
}

+ (CLLocationDirection)bearingBetweenCoordinates:(CLLocationCoordinate2D)fromCoord 
                                    toCoordinate:(CLLocationCoordinate2D)toCoord {
    // 将经纬度转为弧度
    double lat1 = fromCoord.latitude * M_PI / 180.0;
    double lon1 = fromCoord.longitude * M_PI / 180.0;
    double lat2 = toCoord.latitude * M_PI / 180.0;
    double lon2 = toCoord.longitude * M_PI / 180.0;
    
    // 计算方位角
    double y = sin(lon2 - lon1) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(lon2 - lon1);
    double bearing = atan2(y, x) * 180.0 / M_PI;
    
    // 转换为0-360度
    return fmod(bearing + 360.0, 360.0);
}

+ (CLLocationCoordinate2D)randomCoordinateAroundCoordinate:(CLLocationCoordinate2D)center
                                               withRadius:(CLLocationDistance)radius {
    // 随机角度和距离
    double angle = ((double)arc4random() / UINT32_MAX) * 2.0 * M_PI;
    double distance = sqrt(((double)arc4random() / UINT32_MAX)) * radius; // 平方根分布更均匀
    
    return [self destinationCoordinateFromCoordinate:center withBearing:angle*180.0/M_PI andDistance:distance];
}

+ (NSArray<CLLocation *> *)interpolateLocationsFromLocations:(NSArray<CLLocation *> *)waypoints
                                          withPointsCount:(NSUInteger)count {
    if (waypoints.count < 2 || count < 2) {
        return waypoints;
    }
    
    NSMutableArray<CLLocation *> *interpolatedLocations = [NSMutableArray arrayWithCapacity:count];
    double totalDistance = 0;
    NSMutableArray<NSNumber *> *distances = [NSMutableArray arrayWithCapacity:waypoints.count-1];
    
    // 计算各段距离及总距离
    for (NSUInteger i = 0; i < waypoints.count - 1; i++) {
        CLLocation *loc1 = waypoints[i];
        CLLocation *loc2 = waypoints[i + 1];
        CLLocationDistance segDistance = [loc1 distanceFromLocation:loc2];
        [distances addObject:@(segDistance)];
        totalDistance += segDistance;
    }
    
    // 创建细分点
    for (NSUInteger i = 0; i < count; i++) {
        double ratio = (double)i / (count - 1);
        double targetDistance = ratio * totalDistance;
        
        double accDistance = 0;
        NSUInteger segIndex = 0;
        
        // 找到目标距离所在的路段
        for (segIndex = 0; segIndex < distances.count; segIndex++) {
            double segDistance = [distances[segIndex] doubleValue];
            if (accDistance + segDistance >= targetDistance) {
                break;
            }
            accDistance += segDistance;
        }
        
        if (segIndex >= waypoints.count - 1) {
            [interpolatedLocations addObject:[waypoints lastObject]];
            continue;
        }
        
        // 计算该路段内的位置比例
        CLLocation *startLoc = waypoints[segIndex];
        CLLocation *endLoc = waypoints[segIndex + 1];
        double segDistance = [distances[segIndex] doubleValue];
        double segRatio = (targetDistance - accDistance) / segDistance;
        
        // 球面线性插值
        CLLocationCoordinate2D startCoord = startLoc.coordinate;
        CLLocationCoordinate2D endCoord = endLoc.coordinate;
        
        // 计算航向角
        CLLocationDirection bearing = [self bearingBetweenCoordinates:startCoord toCoordinate:endCoord];
        
        // 计算插值点
        CLLocationCoordinate2D coord = [self destinationCoordinateFromCoordinate:startCoord 
                                                                    withBearing:bearing 
                                                                    andDistance:segDistance * segRatio];
        
        // 线性插值高度、速度等
        double altitude = startLoc.altitude + (endLoc.altitude - startLoc.altitude) * segRatio;
        double course = bearing;
        double speed = startLoc.speed + (endLoc.speed - startLoc.speed) * segRatio;
        
        CLLocation *newLoc = [[CLLocation alloc] initWithCoordinate:coord
                                                           altitude:altitude
                                                 horizontalAccuracy:5.0
                                                   verticalAccuracy:5.0
                                                          course:course
                                                           speed:speed
                                                       timestamp:[NSDate date]];
        
        [interpolatedLocations addObject:newLoc];
    }
    
    return interpolatedLocations;
}

+ (CLLocation *)locationWithBearing:(CLLocationDirection)bearing 
                           distance:(CLLocationDistance)distance 
                       fromLocation:(CLLocation *)location {
    // 使用已有方法计算新坐标
    CLLocationCoordinate2D newCoord = [self destinationCoordinateFromCoordinate:location.coordinate 
                                                                    withBearing:bearing 
                                                                    andDistance:distance];
    
    // 创建并返回新的CLLocation对象
    if (@available(iOS 13.4, *)) {
        return [[CLLocation alloc] initWithCoordinate:newCoord 
                                            altitude:location.altitude 
                                  horizontalAccuracy:location.horizontalAccuracy 
                                    verticalAccuracy:location.verticalAccuracy 
                                            course:bearing 
                                             speed:location.speed 
                                         timestamp:[NSDate date]];
    } else {
        // 兼容旧版iOS
        return [[CLLocation alloc] initWithCoordinate:newCoord 
                                            altitude:location.altitude 
                                  horizontalAccuracy:location.horizontalAccuracy 
                                    verticalAccuracy:location.verticalAccuracy 
                                           timestamp:[NSDate date]];
    }
}

@end