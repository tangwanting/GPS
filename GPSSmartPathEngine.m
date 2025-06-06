/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSSmartPathEngine.h"
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

@implementation GPSPathParameters

- (instancetype)init {
    if (self = [super init]) {
        // 设置默认值
        _movementMode = GPSPathMovementModeWalk;
        _baseSpeed = 1.4; // 默认步行速度 1.4 m/s
        _variationFactor = 0.2; // 默认速度变化因子
        _includeAltitude = YES;
        _includeRealisticPauses = NO;
        _pauseProbability = 0.05;
        _customParameters = @{};
    }
    return self;
}

@end

@interface GPSSmartPathEngine()

@property (nonatomic, strong) NSMutableDictionary *cachedPaths;

@end

@implementation GPSSmartPathEngine

+ (instancetype)sharedInstance {
    static GPSSmartPathEngine *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _cachedPaths = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - 路径生成

- (NSArray<GPSLocationModel *> *)generatePathFrom:(CLLocationCoordinate2D)start 
                                              to:(CLLocationCoordinate2D)end 
                                   withParameters:(GPSPathParameters *)params {
    // 创建直线路径
    NSMutableArray<GPSLocationModel *> *path = [NSMutableArray array];
    
    // 计算两点之间的总距离
    CLLocation *startLocation = [[CLLocation alloc] initWithLatitude:start.latitude longitude:start.longitude];
    CLLocation *endLocation = [[CLLocation alloc] initWithLatitude:end.latitude longitude:end.longitude];
    CLLocationDistance totalDistance = [startLocation distanceFromLocation:endLocation];
    
    // 根据移动模式确定点的数量
    NSInteger pointCount = MAX(10, totalDistance / 10); // 每10米一个点，至少10个点
    
    // 创建路径
    for (NSInteger i = 0; i < pointCount; i++) {
        double progress = (double)i / (pointCount - 1);
        
        // 线性插值计算位置
        double lat = start.latitude + progress * (end.latitude - start.latitude);
        double lng = start.longitude + progress * (end.longitude - start.longitude);
        
        // 添加一些随机变化，使路径更自然
        if (i > 0 && i < pointCount - 1) {
            double variation = params.variationFactor * 0.0001; // 约10米的变化
            lat += (((double)arc4random() / UINT32_MAX) - 0.5) * variation;
            lng += (((double)arc4random() / UINT32_MAX) - 0.5) * variation;
        }
        
        GPSLocationModel *point = [[GPSLocationModel alloc] init];
        point.coordinate = CLLocationCoordinate2DMake(lat, lng);
        point.timestamp = [NSDate dateWithTimeIntervalSinceNow:progress * totalDistance / [self speedForMode:params.movementMode baseSpeed:params.baseSpeed]];
        
        // 设置高度数据（如果需要）
        if (params.includeAltitude) {
            // 为高度添加一些随机变化
            double baseAltitude = 20.0; // 基准高度
            double altVariation = 5.0;  // 高度变化范围
            point.altitude = baseAltitude + ((double)arc4random() / UINT32_MAX) * altVariation;
        }
        
        // 添加速度数据
        double baseSpeed = [self speedForMode:params.movementMode baseSpeed:params.baseSpeed];
        double speedVariation = params.variationFactor * baseSpeed;
        point.speed = baseSpeed + (((double)arc4random() / UINT32_MAX) - 0.5) * speedVariation * 2;
        
        // 添加航向数据
        if (i > 0) {
            GPSLocationModel *prevPoint = path[i-1];
            point.course = [self calculateBearingFromCoordinate:prevPoint.coordinate toCoordinate:point.coordinate];
        } else {
            point.course = [self calculateBearingFromCoordinate:start toCoordinate:end];
        }
        
        [path addObject:point];
        
        // 如果需要添加暂停点
        if (params.includeRealisticPauses && i < pointCount - 1) {
            double random = (double)arc4random() / UINT32_MAX;
            if (random < params.pauseProbability) {
                // 复制当前点作为暂停点，但时间戳向后推
                GPSLocationModel *pausePoint = [point copy];
                pausePoint.timestamp = [NSDate dateWithTimeIntervalSince1970:[point.timestamp timeIntervalSince1970] + 30 + random * 60]; // 30-90秒的暂停
                pausePoint.speed = 0; // 速度为0表示暂停
                [path addObject:pausePoint];
            }
        }
    }
    
    return path;
}

#pragma mark - 路径插值

- (NSArray<GPSLocationModel *> *)interpolatePathPoints:(NSArray<GPSLocationModel *> *)points 
                                             withCount:(NSInteger)count 
                                             smoothing:(BOOL)smooth {
    if (points.count < 2 || count <= 0) {
        return points;
    }
    
    NSMutableArray<GPSLocationModel *> *interpolatedPoints = [NSMutableArray arrayWithCapacity:count];
    
    // 计算原始路径的总长度
    double totalDistance = 0;
    NSMutableArray<NSNumber *> *segmentDistances = [NSMutableArray arrayWithCapacity:points.count - 1];
    
    for (NSInteger i = 0; i < points.count - 1; i++) {
        CLLocation *loc1 = [[CLLocation alloc] initWithLatitude:points[i].coordinate.latitude 
                                                      longitude:points[i].coordinate.longitude];
        CLLocation *loc2 = [[CLLocation alloc] initWithLatitude:points[i+1].coordinate.latitude 
                                                      longitude:points[i+1].coordinate.longitude];
        
        CLLocationDistance distance = [loc1 distanceFromLocation:loc2];
        totalDistance += distance;
        [segmentDistances addObject:@(distance)];
    }
    
    // 计算每一段应该分为几个点
    double intervalDistance = totalDistance / (count - 1);
    
    // 创建包含当前位置的新路线
    CLLocationCoordinate2D *routeCoordinates = malloc(sizeof(CLLocationCoordinate2D) * count);
    
    // 使用后释放内存
    if (routeCoordinates) {
        // 添加起点
        routeCoordinates[0] = points.firstObject.coordinate;
        [interpolatedPoints addObject:points.firstObject];
        
        double currentDistance = 0;
        NSInteger currentOriginalIndex = 0;
        
        for (NSInteger i = 1; i < count - 1; i++) {
            double targetDistance = i * intervalDistance;
            
            // 找到目标距离所在的原始点段
            while (currentOriginalIndex < segmentDistances.count && 
                   currentDistance + [segmentDistances[currentOriginalIndex] doubleValue] < targetDistance) {
                currentDistance += [segmentDistances[currentOriginalIndex] doubleValue];
                currentOriginalIndex++;
            }
            
            if (currentOriginalIndex >= segmentDistances.count) {
                break;
            }
            
            // 计算在当前段中的位置比例
            double segmentDistance = [segmentDistances[currentOriginalIndex] doubleValue];
            double segmentProgress = (targetDistance - currentDistance) / segmentDistance;
            
            // 线性插值计算新点的坐标
            GPSLocationModel *startPoint = points[currentOriginalIndex];
            GPSLocationModel *endPoint = points[currentOriginalIndex + 1];
            
            double lat = startPoint.coordinate.latitude + segmentProgress * (endPoint.coordinate.latitude - startPoint.coordinate.latitude);
            double lng = startPoint.coordinate.longitude + segmentProgress * (endPoint.coordinate.longitude - startPoint.coordinate.longitude);
            
            // 如果需要平滑处理
            if (smooth && currentOriginalIndex > 0 && currentOriginalIndex < points.count - 2) {
                // 使用三点插值来平滑路径
                GPSLocationModel *prevPoint = points[currentOriginalIndex - 1];
                GPSLocationModel *nextPoint = points[currentOriginalIndex + 2];
                
                // 简单的Catmull-Rom样条插值
                double t = segmentProgress;
                double t2 = t * t;
                double t3 = t2 * t;
                
                lat = 0.5 * ((2 * startPoint.coordinate.latitude) +
                              (-prevPoint.coordinate.latitude + endPoint.coordinate.latitude) * t +
                              (2 * prevPoint.coordinate.latitude - 5 * startPoint.coordinate.latitude + 4 * endPoint.coordinate.latitude - nextPoint.coordinate.latitude) * t2 +
                              (-prevPoint.coordinate.latitude + 3 * startPoint.coordinate.latitude - 3 * endPoint.coordinate.latitude + nextPoint.coordinate.latitude) * t3);
                
                lng = 0.5 * ((2 * startPoint.coordinate.longitude) +
                              (-prevPoint.coordinate.longitude + endPoint.coordinate.longitude) * t +
                              (2 * prevPoint.coordinate.longitude - 5 * startPoint.coordinate.longitude + 4 * endPoint.coordinate.longitude - nextPoint.coordinate.longitude) * t2 +
                              (-prevPoint.coordinate.longitude + 3 * startPoint.coordinate.longitude - 3 * endPoint.coordinate.longitude + nextPoint.coordinate.longitude) * t3);
            }
            
            routeCoordinates[i] = CLLocationCoordinate2DMake(lat, lng);
            
            GPSLocationModel *newPoint = [[GPSLocationModel alloc] init];
            newPoint.coordinate = routeCoordinates[i];
            
            // 线性插值其他属性
            if (startPoint.timestamp && endPoint.timestamp) {
                NSTimeInterval startTime = [startPoint.timestamp timeIntervalSince1970];
                NSTimeInterval endTime = [endPoint.timestamp timeIntervalSince1970];
                NSTimeInterval newTime = startTime + segmentProgress * (endTime - startTime);
                newPoint.timestamp = [NSDate dateWithTimeIntervalSince1970:newTime];
            }
            
            if (startPoint.altitude >= 0 && endPoint.altitude >= 0) {
                newPoint.altitude = startPoint.altitude + segmentProgress * (endPoint.altitude - startPoint.altitude);
            }
            
            if (startPoint.speed >= 0 && endPoint.speed >= 0) {
                newPoint.speed = startPoint.speed + segmentProgress * (endPoint.speed - startPoint.speed);
            }
            
            // 计算航向
            newPoint.course = [self calculateBearingFromCoordinate:
                              CLLocationCoordinate2DMake(startPoint.coordinate.latitude, startPoint.coordinate.longitude)
                                                    toCoordinate:
                              CLLocationCoordinate2DMake(endPoint.coordinate.latitude, endPoint.coordinate.longitude)];
            
            [interpolatedPoints addObject:newPoint];
        }
        
        // 添加终点
        if (count > 1) {
            routeCoordinates[count-1] = points.lastObject.coordinate;
            [interpolatedPoints addObject:points.lastObject];
        }
        
        // 释放内存
        free(routeCoordinates);
    }
    
    return interpolatedPoints;
}

#pragma mark - 路径优化

- (NSArray<GPSLocationModel *> *)optimizePath:(NSArray<GPSLocationModel *> *)path 
                                        type:(GPSPathOptimizationType)optimizationType {
    if (path.count < 3) {
        return path;
    }
    
    NSMutableArray<GPSLocationModel *> *optimizedPath = [NSMutableArray arrayWithArray:path];
    
    switch (optimizationType) {
        case GPSPathOptimizationTypeDistance: {
            // 简化路径，去除不必要的点
            NSMutableArray<GPSLocationModel *> *simplified = [NSMutableArray array];
            [simplified addObject:path.firstObject];
            
            // 道格拉斯-普克算法简化路径，阈值为5米
            double epsilon = 5.0;
            [self simplifyPath:path startIndex:0 endIndex:path.count - 1 epsilon:epsilon result:simplified];
            
            [simplified addObject:path.lastObject];
            optimizedPath = simplified;
            break;
        }
            
        case GPSPathOptimizationTypeTime: {
            // 调整点的速度和时间戳，使路径总时间更短
            NSDate *startTime = path.firstObject.timestamp;
            NSDate *endTime = path.lastObject.timestamp;
            
            if (startTime && endTime) {
                NSTimeInterval totalTime = [endTime timeIntervalSinceDate:startTime];
                NSTimeInterval optimizedTime = totalTime * 0.8; // 减少20%的时间
                
                for (NSInteger i = 0; i < optimizedPath.count; i++) {
                    double progress = (double)i / (optimizedPath.count - 1);
                    NSTimeInterval newTime = [startTime timeIntervalSince1970] + progress * optimizedTime;
                    optimizedPath[i].timestamp = [NSDate dateWithTimeIntervalSince1970:newTime];
                    
                    // 增加速度
                    if (optimizedPath[i].speed > 0) {
                        optimizedPath[i].speed *= 1.25; // 增加25%的速度
                    }
                }
            }
            break;
        }
            
        case GPSPathOptimizationTypeEnergy: {
            // 能源优化：平滑高度变化，避免急剧的坡度变化
            for (NSInteger i = 1; i < optimizedPath.count - 1; i++) {
                if (optimizedPath[i-1].altitude >= 0 && optimizedPath[i].altitude >= 0 && optimizedPath[i+1].altitude >= 0) {
                    // 平滑高度数据
                    double averageAltitude = (optimizedPath[i-1].altitude + optimizedPath[i+1].altitude) / 2.0;
                    optimizedPath[i].altitude = (optimizedPath[i].altitude + averageAltitude) / 2.0;
                }
            }
            break;
        }
            
        case GPSPathOptimizationTypeSafety: {
            // 安全优化：降低速度，增加点的密度在转弯处
            for (NSInteger i = 1; i < optimizedPath.count - 1; i++) {
                double angle = [self calculateAngleBetweenCoordinates:optimizedPath[i-1].coordinate
                                                        point2:optimizedPath[i].coordinate
                                                        point3:optimizedPath[i+1].coordinate];
                
                // 如果转弯角度较大
                if (angle > 30) {
                    // 减少转弯点的速度
                    double speedReduction = MIN(1.0, angle / 90.0) * 0.3; // 根据角度减少速度，最多减少30%
                    optimizedPath[i].speed *= (1.0 - speedReduction);
                }
            }
            break;
        }
            
        default:
            break;
    }
    
    return optimizedPath;
}

#pragma mark - 实时路径调整

- (GPSLocationModel *)nextLocationOnPath:(NSArray<GPSLocationModel *> *)path 
                            afterLocation:(GPSLocationModel *)currentLocation 
                           withParameters:(GPSPathParameters *)params {
    if (path.count < 2 || !currentLocation) {
        return nil;
    }
    
    // 现在安全了
    CLLocation *curLoc = [[CLLocation alloc] initWithLatitude:currentLocation.coordinate.latitude 
                                                    longitude:currentLocation.coordinate.longitude];
    
    // 找到当前位置在路径上的最近点
    NSInteger closestIndex = 0;
    CLLocationDistance minDistance = DBL_MAX;
    
    for (NSInteger i = 0; i < path.count; i++) {
        CLLocation *pathLoc = [[CLLocation alloc] initWithLatitude:path[i].coordinate.latitude 
                                                         longitude:path[i].coordinate.longitude];
        CLLocationDistance distance = [curLoc distanceFromLocation:pathLoc];
        
        if (distance < minDistance) {
            minDistance = distance;
            closestIndex = i;
        }
    }
    
    // 如果已经是最后一个点，则返回nil
    if (closestIndex >= path.count - 1) {
        return nil;
    }
    
    // 计算下一个点
    NSInteger nextIndex = closestIndex + 1;
    GPSLocationModel *nextLocation = path[nextIndex];
    
    // 根据参数调整下一个位置
    double speed = [self speedForMode:params.movementMode baseSpeed:params.baseSpeed];
    double speedVariation = params.variationFactor * speed;
    double actualSpeed = speed + (((double)arc4random() / UINT32_MAX) - 0.5) * speedVariation * 2;
    
    // 调整下一个位置的速度
    GPSLocationModel *adjustedLocation = [nextLocation copy];
    adjustedLocation.speed = actualSpeed;
    
    // 计算预估到达时间
    CLLocation *nextLoc = [[CLLocation alloc] initWithLatitude:nextLocation.coordinate.latitude 
                                                     longitude:nextLocation.coordinate.longitude];
    CLLocationDistance distance = [curLoc distanceFromLocation:nextLoc];
    NSTimeInterval estimatedTime = distance / actualSpeed;
    
    adjustedLocation.timestamp = [NSDate dateWithTimeIntervalSinceNow:estimatedTime];
    
    return adjustedLocation;
}

#pragma mark - 自动避障系统

- (NSArray<GPSLocationModel *> *)reroutePath:(NSArray<GPSLocationModel *> *)path 
                             avoidingRegions:(NSArray<MKPolyline *> *)regions {
    if (path.count < 2 || regions.count == 0) {
        return path;
    }
    
    // 找出所有与禁区相交的路径段
    NSMutableArray *intersectingSegments = [NSMutableArray array];
    
    for (NSInteger i = 0; i < path.count - 1; i++) {
        MKMapPoint point1 = MKMapPointForCoordinate(path[i].coordinate);
        MKMapPoint point2 = MKMapPointForCoordinate(path[i+1].coordinate);
        
        for (MKPolyline *region in regions) {
            if ([self polyline:region intersectsLineFromPoint:point1 toPoint:point2]) {
                [intersectingSegments addObject:@[@(i), @(i+1)]];
                break;
            }
        }
    }
    
    if (intersectingSegments.count == 0) {
        return path; // 没有交叉，返回原路径
    }
    
    // 创建新路径
    NSMutableArray<GPSLocationModel *> *newPath = [NSMutableArray array];
    NSInteger lastEnd = 0;
    
    for (NSArray *segment in intersectingSegments) {
        NSInteger start = [segment[0] integerValue];
        NSInteger end = [segment[1] integerValue];
        
        // 添加不相交的前面部分
        for (NSInteger i = lastEnd; i <= start; i++) {
            [newPath addObject:path[i]];
        }
        
        // 在相交区域创建绕行路径
        GPSLocationModel *startPoint = path[start];
        GPSLocationModel *endPoint = path[end];
        
        // 计算绕行方向
        double bearing = [self calculateBearingFromCoordinate:startPoint.coordinate toCoordinate:endPoint.coordinate];
        double distance = [self distanceBetweenCoordinates:startPoint.coordinate end:endPoint.coordinate];
        
        // 创建绕行点 (向左或向右偏移约50米)
        double offsetDistance = 0.0005; // 约50米的偏移
        BOOL goLeft = arc4random_uniform(2) == 0;
        double offsetAngle = goLeft ? bearing - 90 : bearing + 90;
        offsetAngle = offsetAngle * M_PI / 180.0; // 转换为弧度
        
        double midLat1 = startPoint.coordinate.latitude + sin(offsetAngle) * offsetDistance;
        double midLon1 = startPoint.coordinate.longitude + cos(offsetAngle) * offsetDistance;
        
        double midLat2 = endPoint.coordinate.latitude + sin(offsetAngle) * offsetDistance;
        double midLon2 = endPoint.coordinate.longitude + cos(offsetAngle) * offsetDistance;
        
        // 创建中间点
        GPSLocationModel *midPoint1 = [[GPSLocationModel alloc] init];
        midPoint1.coordinate = CLLocationCoordinate2DMake(midLat1, midLon1);
        
        GPSLocationModel *midPoint2 = [[GPSLocationModel alloc] init];
        midPoint2.coordinate = CLLocationCoordinate2DMake(midLat2, midLon2);
        
        // 设置中间点属性
        if (startPoint.timestamp && endPoint.timestamp) {
            NSTimeInterval startTime = [startPoint.timestamp timeIntervalSince1970];
            NSTimeInterval endTime = [endPoint.timestamp timeIntervalSince1970];
            midPoint1.timestamp = [NSDate dateWithTimeIntervalSince1970:startTime + (endTime - startTime) * 0.33];
            midPoint2.timestamp = [NSDate dateWithTimeIntervalSince1970:startTime + (endTime - startTime) * 0.66];
        }
        
        if (startPoint.altitude >= 0 && endPoint.altitude >= 0) {
            midPoint1.altitude = (startPoint.altitude * 2 + endPoint.altitude) / 3.0;
            midPoint2.altitude = (startPoint.altitude + endPoint.altitude * 2) / 3.0;
        }
        
        midPoint1.speed = startPoint.speed;
        midPoint2.speed = endPoint.speed;
        
        // 添加绕行点
        [newPath addObject:midPoint1];
        [newPath addObject:midPoint2];
        
        lastEnd = end;
    }
    
    // 添加剩余部分
    for (NSInteger i = lastEnd; i < path.count; i++) {
        [newPath addObject:path[i]];
    }
    
    return newPath;
}

#pragma mark - 辅助方法

- (double)speedForMode:(GPSPathMovementMode)mode baseSpeed:(double)customSpeed {
    if (mode == GPSPathMovementModeCustom && customSpeed > 0) {
        return customSpeed;
    }
    
    switch (mode) {
        case GPSPathMovementModeWalk:
            return 1.4; // 平均步行速度 1.4 m/s (约5 km/h)
        case GPSPathMovementModeRun:
            return 3.0; // 平均跑步速度 3.0 m/s (约10.8 km/h)
        case GPSPathMovementModeCycle:
            return 5.0; // 平均自行车速度 5.0 m/s (约18 km/h)
        case GPSPathMovementModeDrive:
            return 13.9; // 平均驾驶速度 13.9 m/s (约50 km/h)
        default:
            return 1.4;
    }
}

- (double)calculateBearingFromCoordinate:(CLLocationCoordinate2D)startCoord toCoordinate:(CLLocationCoordinate2D)endCoord {
    double lat1 = startCoord.latitude * M_PI / 180.0;
    double lon1 = startCoord.longitude * M_PI / 180.0;
    double lat2 = endCoord.latitude * M_PI / 180.0;
    double lon2 = endCoord.longitude * M_PI / 180.0;
    
    double dLon = lon2 - lon1;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double bearing = atan2(y, x) * 180.0 / M_PI;
    
    return fmod(bearing + 360.0, 360.0);
}

- (double)calculateAngleBetweenCoordinates:(CLLocationCoordinate2D)point1 
                                    point2:(CLLocationCoordinate2D)point2 
                                    point3:(CLLocationCoordinate2D)point3 {
    double bearing1 = [self calculateBearingFromCoordinate:point1 toCoordinate:point2];
    double bearing2 = [self calculateBearingFromCoordinate:point2 toCoordinate:point3];
    
    double angle = fabs(bearing1 - bearing2);
    if (angle > 180) {
        angle = 360 - angle;
    }
    
    return angle;
}

- (double)distanceBetweenCoordinates:(CLLocationCoordinate2D)start end:(CLLocationCoordinate2D)end {
    CLLocation *loc1 = [[CLLocation alloc] initWithLatitude:start.latitude longitude:start.longitude];
    CLLocation *loc2 = [[CLLocation alloc] initWithLatitude:end.latitude longitude:end.longitude];
    return [loc1 distanceFromLocation:loc2];
}

- (void)simplifyPath:(NSArray<GPSLocationModel *> *)points 
          startIndex:(NSInteger)start 
            endIndex:(NSInteger)end 
              epsilon:(double)epsilon 
               result:(NSMutableArray<GPSLocationModel *> *)result {
    
    if (end - start <= 1) {
        return;
    }
    
    double dmax = 0;
    NSInteger index = 0;
    
    CLLocation *startLoc = [[CLLocation alloc] initWithLatitude:points[start].coordinate.latitude 
                                                      longitude:points[start].coordinate.longitude];
    CLLocation *endLoc = [[CLLocation alloc] initWithLatitude:points[end].coordinate.latitude 
                                                    longitude:points[end].coordinate.longitude];
    
    // 计算两点之间的距离
    CLLocationDistance lineLength = [startLoc distanceFromLocation:endLoc];
    
    // 找出距离直线最远的点
    for (NSInteger i = start + 1; i < end; i++) {
        CLLocation *loc = [[CLLocation alloc] initWithLatitude:points[i].coordinate.latitude 
                                                     longitude:points[i].coordinate.longitude];
        
        double distance = [self perpendicularDistance:loc fromLine:startLoc toLine:endLoc lineLength:lineLength];
        
        if (distance > dmax) {
            index = i;
            dmax = distance;
        }
    }
    
    // 如果最大距离大于阈值，则递归简化
    if (dmax > epsilon) {
        [self simplifyPath:points startIndex:start endIndex:index epsilon:epsilon result:result];
        [result addObject:points[index]];
        [self simplifyPath:points startIndex:index endIndex:end epsilon:epsilon result:result];
    }
}

- (double)perpendicularDistance:(CLLocation *)point fromLine:(CLLocation *)lineStart toLine:(CLLocation *)lineEnd lineLength:(double)lineLength {
    if (lineLength == 0) {
        return [point distanceFromLocation:lineStart];
    }
    
    // 计算点到线段的垂直距离
    double t = ((point.coordinate.longitude - lineStart.coordinate.longitude) * (lineEnd.coordinate.longitude - lineStart.coordinate.longitude) +
                (point.coordinate.latitude - lineStart.coordinate.latitude) * (lineEnd.coordinate.latitude - lineStart.coordinate.latitude)) / 
               (lineLength * lineLength);
    
    t = fmax(0, fmin(1, t));
    
    double projectionLat = lineStart.coordinate.latitude + t * (lineEnd.coordinate.latitude - lineStart.coordinate.latitude);
    double projectionLon = lineStart.coordinate.longitude + t * (lineEnd.coordinate.longitude - lineStart.coordinate.longitude);
    
    CLLocation *projection = [[CLLocation alloc] initWithLatitude:projectionLat longitude:projectionLon];
    
    return [point distanceFromLocation:projection];
}

- (BOOL)polyline:(MKPolyline *)polyline intersectsLineFromPoint:(MKMapPoint)p1 toPoint:(MKMapPoint)p2 {
    MKMapPoint *polylinePoints = polyline.points;
    NSUInteger pointCount = polyline.pointCount;
    
    // 检查每个线段是否有交点
    for (NSUInteger i = 0; i < pointCount - 1; i++) {
        if ([self lineSegment:p1 toPoint:p2 intersectsWithSegment:polylinePoints[i] toPoint:polylinePoints[i+1]]) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)lineSegment:(MKMapPoint)line1Start toPoint:(MKMapPoint)line1End 
intersectsWithSegment:(MKMapPoint)line2Start toPoint:(MKMapPoint)line2End {
    // 计算线段的方向向量
    double dx1 = line1End.x - line1Start.x;
    double dy1 = line1End.y - line1Start.y;
    double dx2 = line2End.x - line2Start.x;
    double dy2 = line2End.y - line2Start.y;
    
    // 计算分母
    double denominator = dy2 * dx1 - dx2 * dy1;
    
    // 如果分母为零，则线段平行
    if (fabs(denominator) < 1e-10) {
        return NO;
    }
    
    // 计算线段的参数t1和t2
    double a = line1Start.y - line2Start.y;
    double b = line1Start.x - line2Start.x;
    double numerator1 = dx2 * a - dy2 * b;
    double numerator2 = dx1 * a - dy1 * b;
    
    double t1 = numerator1 / denominator;
    double t2 = numerator2 / denominator;
    
    // 检查t1和t2是否在[0,1]范围内
    return (t1 >= 0 && t1 <= 1 && t2 >= 0 && t2 <= 1);
}

@end