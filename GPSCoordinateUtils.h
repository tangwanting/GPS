/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <MapKit/MapKit.h>

@interface GPSCoordinateUtils : NSObject

// 使用Haversine公式计算两点间距离
+ (CLLocationDistance)distanceBetweenCoordinates:(CLLocationCoordinate2D)coord1 
                                         andCoord:(CLLocationCoordinate2D)coord2;

// 根据起点、方向和距离计算目标点
+ (CLLocationCoordinate2D)destinationCoordinateFromCoordinate:(CLLocationCoordinate2D)startCoord
                                                     withBearing:(CLLocationDirection)bearing
                                                      andDistance:(CLLocationDistance)distance;

// 计算两点之间的航向角
+ (CLLocationDirection)bearingBetweenCoordinates:(CLLocationCoordinate2D)fromCoord 
                                        toCoordinate:(CLLocationCoordinate2D)toCoord;

// 在指定半径内生成随机坐标
+ (CLLocationCoordinate2D)randomCoordinateAroundCoordinate:(CLLocationCoordinate2D)center
                                                withRadius:(CLLocationDistance)radius;

// 沿路线平滑插值
+ (NSArray<CLLocation *> *)interpolateLocationsFromLocations:(NSArray<CLLocation *> *)waypoints
                                            withPointsCount:(NSUInteger)count;

// 根据方位角和距离从一个位置创建新位置
+ (CLLocation *)locationWithBearing:(CLLocationDirection)bearing 
                           distance:(CLLocationDistance)distance 
                       fromLocation:(CLLocation *)location;

// 现有方法
+ (double)calculateBearingFrom:(CLLocationCoordinate2D)from to:(CLLocationCoordinate2D)to;
+ (double)calculateDistanceFrom:(CLLocationCoordinate2D)from to:(CLLocationCoordinate2D)to;

// 新增方法
+ (double)calculateAngleBetweenCoordinates:(CLLocationCoordinate2D)point1 point2:(CLLocationCoordinate2D)point2 point3:(CLLocationCoordinate2D)point3;
+ (double)perpendicularDistance:(CLLocation *)point fromLine:(CLLocation *)lineStart toLine:(CLLocation *)lineEnd lineLength:(double)lineLength;
+ (BOOL)lineSegment:(MKMapPoint)line1Start toPoint:(MKMapPoint)line1End intersectsWithSegment:(MKMapPoint)line2Start toPoint:(MKMapPoint)line2End;

@end