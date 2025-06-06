/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSGeofencingSystem.h"
#import <MapKit/MapKit.h>

#pragma mark - NSValue MKMapPoint Extensions

@interface NSValue (MKMapPointAdditions)
+ (NSValue *)valueWithMKMapPoint:(MKMapPoint)mapPoint;
- (MKMapPoint)MKMapPointValue;
@end

@implementation NSValue (MKMapPointAdditions)
+ (NSValue *)valueWithMKMapPoint:(MKMapPoint)mapPoint {
    return [NSValue valueWithBytes:&mapPoint objCType:@encode(MKMapPoint)];
}

- (MKMapPoint)MKMapPointValue {
    MKMapPoint point;
    [self getValue:&point];
    return point;
}
@end

#pragma mark - MKCircle Category for containsCoordinate

@interface MKCircle (Containment)
- (BOOL)containsCoordinate:(CLLocationCoordinate2D)coordinate;
@end

@implementation MKCircle (Containment)
- (BOOL)containsCoordinate:(CLLocationCoordinate2D)coordinate {
    CLLocation *center = [[CLLocation alloc] initWithLatitude:self.coordinate.latitude longitude:self.coordinate.longitude];
    CLLocation *point = [[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
    CLLocationDistance distance = [center distanceFromLocation:point];
    return distance <= self.radius;
}
@end

#pragma mark - MKPolygon Category for containsCoordinate

@interface MKPolygon (Containment)
- (BOOL)containsCoordinate:(CLLocationCoordinate2D)coordinate;
@end

@implementation MKPolygon (Containment)
- (BOOL)containsCoordinate:(CLLocationCoordinate2D)coordinate {
    MKMapPoint point = MKMapPointForCoordinate(coordinate);
    
    CGMutablePathRef path = CGPathCreateMutable();
    
    MKMapPoint *points = self.points;
    CGPathMoveToPoint(path, NULL, points[0].x, points[0].y);
    
    for (NSInteger i = 1; i < self.pointCount; i++) {
        CGPathAddLineToPoint(path, NULL, points[i].x, points[i].y);
    }
    
    CGPathCloseSubpath(path);
    
    BOOL contains = CGPathContainsPoint(path, NULL, CGPointMake(point.x, point.y), NO);
    CGPathRelease(path);
    
    return contains;
}
@end

#pragma mark - MKPolyline Category for buffer

@interface MKPolyline (Buffer)
- (MKPolygon *)polygonWithBuffer:(CLLocationDistance)distance;
@end

@implementation MKPolyline (Buffer)
- (MKPolygon *)polygonWithBuffer:(CLLocationDistance)distance {
    NSInteger pointCount = self.pointCount;
    if (pointCount < 2) return nil;
    
    MKMapPoint *originalPoints = self.points;
    NSMutableArray *leftPoints = [NSMutableArray array];
    NSMutableArray *rightPoints = [NSMutableArray array];
    
    // 为路径创建缓冲区
    for (int i = 0; i < pointCount - 1; i++) {
        MKMapPoint p1 = originalPoints[i];
        MKMapPoint p2 = originalPoints[i+1];
        
        // 计算线段方向向量
        double dx = p2.x - p1.x;
        double dy = p2.y - p1.y;
        double length = sqrt(dx*dx + dy*dy);
        
        if (length == 0) continue;
        
        // 标准化
        double unitX = dx / length;
        double unitY = dy / length;
        
        // 计算垂直向量 (-unitY, unitX) 和 (unitY, -unitX)
        double offsetX = unitY * distance / MKMapPointsPerMeterAtLatitude(MKCoordinateForMapPoint(p1).latitude);
        double offsetY = -unitX * distance / MKMapPointsPerMeterAtLatitude(MKCoordinateForMapPoint(p1).latitude);
        
        // 左右偏移点
        MKMapPoint leftPoint1 = MKMapPointMake(p1.x + offsetX, p1.y + offsetY);
        MKMapPoint rightPoint1 = MKMapPointMake(p1.x - offsetX, p1.y - offsetY);
        
        [leftPoints addObject:[NSValue valueWithMKMapPoint:leftPoint1]];
        [rightPoints insertObject:[NSValue valueWithMKMapPoint:rightPoint1] atIndex:0]; // 反向添加右侧点
        
        // 最后一个点
        if (i == pointCount - 2) {
            MKMapPoint leftPoint2 = MKMapPointMake(p2.x + offsetX, p2.y + offsetY);
            MKMapPoint rightPoint2 = MKMapPointMake(p2.x - offsetX, p2.y - offsetY);
            
            [leftPoints addObject:[NSValue valueWithMKMapPoint:leftPoint2]];
            [rightPoints insertObject:[NSValue valueWithMKMapPoint:rightPoint2] atIndex:0];
        }
    }
    
    // 合并左右点形成封闭多边形
    NSMutableArray *allPoints = [NSMutableArray arrayWithArray:leftPoints];
    [allPoints addObjectsFromArray:rightPoints];
    
    // 创建MKMapPoint数组
    MKMapPoint *polygonPoints = malloc(sizeof(MKMapPoint) * allPoints.count);
    for (NSUInteger i = 0; i < allPoints.count; i++) {
        polygonPoints[i] = [[allPoints objectAtIndex:i] MKMapPointValue];
    }
    
    MKPolygon *polygon = [MKPolygon polygonWithPoints:polygonPoints count:allPoints.count];
    free(polygonPoints);
    
    return polygon;
}
@end

#pragma mark - GPSGeofenceRegion Implementation

@interface GPSGeofenceRegion ()
@property (nonatomic, strong) id<MKOverlay> cachedOverlay;
@end

@implementation GPSGeofenceRegion

- (instancetype)init {
    if (self = [super init]) {
        // 设置默认值
        _identifier = [[NSUUID UUID] UUIDString];
        _active = YES;
        _notifyOnEntry = YES;
        _notifyOnExit = YES;
        _notifyOnDwell = NO;
        _dwellTime = 60.0; // 默认停留时间为60秒
        _color = [UIColor blueColor];
    }
    return self;
}

- (id<MKOverlay>)mapOverlay {
    if (_cachedOverlay) {
        return _cachedOverlay;
    }
    
    switch (_type) {
        case GPSGeofenceTypeCircular: {
            _cachedOverlay = [MKCircle circleWithCenterCoordinate:_center radius:_radius];
            break;
        }
        case GPSGeofenceTypePolygon: {
            NSInteger count = _coordinates.count;
            if (count < 3) return nil; // 多边形至少需要3个点
            
            CLLocationCoordinate2D *points = malloc(sizeof(CLLocationCoordinate2D) * count);
            for (NSInteger i = 0; i < count; i++) {
                points[i] = [_coordinates[i] MKCoordinateValue];
            }
            
            _cachedOverlay = [MKPolygon polygonWithCoordinates:points count:count];
            free(points);
            break;
        }
        case GPSGeofenceTypePath: {
            NSInteger count = _pathPoints.count;
            if (count < 2) return nil; // 路径至少需要2个点
            
            // 创建路线
            CLLocationCoordinate2D *points = malloc(sizeof(CLLocationCoordinate2D) * count);
            for (NSInteger i = 0; i < count; i++) {
                points[i] = _pathPoints[i].coordinate;
            }
            
            MKPolyline *polyline = [MKPolyline polylineWithCoordinates:points count:count];
            free(points);
            
            // 创建缓冲区多边形
            _cachedOverlay = [polyline polygonWithBuffer:_pathWidth];
            break;
        }
    }
    
    return _cachedOverlay;
}

- (BOOL)containsCoordinate:(CLLocationCoordinate2D)coordinate {
    switch (_type) {
        case GPSGeofenceTypeCircular: {
            CLLocation *center = [[CLLocation alloc] initWithLatitude:_center.latitude longitude:_center.longitude];
            CLLocation *point = [[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
            return [center distanceFromLocation:point] <= _radius;
        }
        case GPSGeofenceTypePolygon: {
            MKPolygon *polygon = (MKPolygon *)[self mapOverlay];
            return [polygon containsCoordinate:coordinate];
        }
        case GPSGeofenceTypePath: {
            MKPolygon *bufferPolygon = (MKPolygon *)[self mapOverlay];
            return [bufferPolygon containsCoordinate:coordinate];
        }
    }
    return NO;
}

- (NSString *)description {
    NSString *typeString;
    switch (_type) {
        case GPSGeofenceTypeCircular:
            typeString = @"Circular";
            break;
        case GPSGeofenceTypePolygon:
            typeString = @"Polygon";
            break;
        case GPSGeofenceTypePath:
            typeString = @"Path";
            break;
    }
    
    return [NSString stringWithFormat:@"Geofence %@ (ID: %@) - Type: %@, Active: %@", 
            _name, _identifier, typeString, _active ? @"YES" : @"NO"];
}

- (void)invalidateCache {
    _cachedOverlay = nil;
}

@end

#pragma mark - GPSGeofencingSystem Private Interface

@interface GPSGeofencingSystem () <CLLocationManagerDelegate>

@property (nonatomic, strong) NSMutableDictionary<NSString *, GPSGeofenceRegion *> *geofences;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) BOOL monitoring;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDate *> *dwellStartTimes;
@property (nonatomic, strong) NSMutableSet<NSString *> *currentlyInsideRegions;
@property (nonatomic, strong) dispatch_queue_t geofenceQueue;

@end

#pragma mark - GPSGeofencingSystem Implementation

@implementation GPSGeofencingSystem

#pragma mark - Initialization

+ (instancetype)sharedInstance {
    static GPSGeofencingSystem *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _geofences = [NSMutableDictionary dictionary];
        _monitoring = NO;
        _dwellStartTimes = [NSMutableDictionary dictionary];
        _currentlyInsideRegions = [NSMutableSet set];
        _geofenceQueue = dispatch_queue_create("com.gps.geofencing.queue", DISPATCH_QUEUE_SERIAL);
        
        // 初始化位置管理器
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        _locationManager.distanceFilter = 10.0; // 10米更新一次
    }
    return self;
}

#pragma mark - Geofence Management Methods

- (NSString *)addCircularGeofence:(CLLocationCoordinate2D)center radius:(CLLocationDistance)radius name:(NSString *)name {
    GPSGeofenceRegion *region = [[GPSGeofenceRegion alloc] init];
    region.type = GPSGeofenceTypeCircular;
    region.name = name;
    region.center = center;
    region.radius = radius;
    
    dispatch_async(_geofenceQueue, ^{
        self.geofences[region.identifier] = region;
        
        if (self.monitoring && region.active) {
            [self startMonitoringRegion:region];
        }
    });
    
    return region.identifier;
}

- (NSString *)addPolygonGeofence:(NSArray<NSValue *> *)coordinates name:(NSString *)name {
    if (coordinates.count < 3) {
        NSLog(@"多边形围栏至少需要3个点");
        return nil;
    }
    
    GPSGeofenceRegion *region = [[GPSGeofenceRegion alloc] init];
    region.type = GPSGeofenceTypePolygon;
    region.name = name;
    region.coordinates = coordinates;
    
    dispatch_async(_geofenceQueue, ^{
        self.geofences[region.identifier] = region;
        
        if (self.monitoring && region.active) {
            [self startMonitoringRegion:region];
        }
    });
    
    return region.identifier;
}

- (NSString *)addPathGeofence:(NSArray<CLLocation *> *)path width:(CLLocationDistance)width name:(NSString *)name {
    if (path.count < 2) {
        NSLog(@"路径围栏至少需要2个点");
        return nil;
    }
    
    GPSGeofenceRegion *region = [[GPSGeofenceRegion alloc] init];
    region.type = GPSGeofenceTypePath;
    region.name = name;
    region.pathPoints = path;
    region.pathWidth = width;
    
    dispatch_async(_geofenceQueue, ^{
        self.geofences[region.identifier] = region;
        
        if (self.monitoring && region.active) {
            [self startMonitoringRegion:region];
        }
    });
    
    return region.identifier;
}

- (BOOL)updateGeofence:(GPSGeofenceRegion *)region {
    if (!region.identifier) {
        return NO;
    }
    
    __block BOOL success = NO;
    dispatch_sync(_geofenceQueue, ^{
        if (self.geofences[region.identifier]) {
            // 如果是正在监控的围栏，先停止监控
            if (self.monitoring && self.geofences[region.identifier].active) {
                [self stopMonitoringRegion:self.geofences[region.identifier]];
            }
            
            // 更新围栏
            [region invalidateCache]; // 清除缓存的覆盖物
            self.geofences[region.identifier] = region;
            
            // 如果需要，重新开始监控
            if (self.monitoring && region.active) {
                [self startMonitoringRegion:region];
            }
            
            success = YES;
        }
    });
    
    return success;
}

- (BOOL)removeGeofenceWithIdentifier:(NSString *)identifier {
    if (!identifier) {
        return NO;
    }
    
    __block BOOL success = NO;
    dispatch_sync(_geofenceQueue, ^{
        GPSGeofenceRegion *region = self.geofences[identifier];
        if (region) {
            if (self.monitoring && region.active) {
                [self stopMonitoringRegion:region];
            }
            
            [self.geofences removeObjectForKey:identifier];
            [self.dwellStartTimes removeObjectForKey:identifier];
            [self.currentlyInsideRegions removeObject:identifier];
            
            success = YES;
        }
    });
    
    return success;
}

- (void)activateGeofence:(NSString *)identifier {
    dispatch_async(_geofenceQueue, ^{
        GPSGeofenceRegion *region = self.geofences[identifier];
        if (region && !region.active) {
            region.active = YES;
            
            if (self.monitoring) {
                [self startMonitoringRegion:region];
            }
        }
    });
}

- (void)deactivateGeofence:(NSString *)identifier {
    dispatch_async(_geofenceQueue, ^{
        GPSGeofenceRegion *region = self.geofences[identifier];
        if (region && region.active) {
            region.active = NO;
            
            if (self.monitoring) {
                [self stopMonitoringRegion:region];
            }
            
            [self.dwellStartTimes removeObjectForKey:identifier];
            [self.currentlyInsideRegions removeObject:identifier];
        }
    });
}

- (GPSGeofenceRegion *)geofenceWithIdentifier:(NSString *)identifier {
    __block GPSGeofenceRegion *region = nil;
    dispatch_sync(_geofenceQueue, ^{
        region = self.geofences[identifier];
    });
    
    return region;
}

- (NSArray<GPSGeofenceRegion *> *)allGeofences {
    __block NSArray *regions = nil;
    dispatch_sync(_geofenceQueue, ^{
        regions = [self.geofences.allValues copy];
    });
    
    return regions;
}

- (NSArray<GPSGeofenceRegion *> *)activeGeofences {
    __block NSMutableArray *activeRegions = [NSMutableArray array];
    dispatch_sync(_geofenceQueue, ^{
        for (GPSGeofenceRegion *region in self.geofences.allValues) {
            if (region.active) {
                [activeRegions addObject:region];
            }
        }
    });
    
    return activeRegions;
}

#pragma mark - Monitoring Methods

- (void)startMonitoring {
    dispatch_async(_geofenceQueue, ^{
        if (!self.monitoring) {
            self.monitoring = YES;
            
            // 检查权限
            if ([CLLocationManager authorizationStatus] != kCLAuthorizationStatusAuthorizedAlways &&
                [CLLocationManager authorizationStatus] != kCLAuthorizationStatusAuthorizedWhenInUse) {
                [self.locationManager requestWhenInUseAuthorization];
            }
            
            // 开始更新位置
            [self.locationManager startUpdatingLocation];
            
            // 启用所有活跃的围栏
            for (GPSGeofenceRegion *region in self.geofences.allValues) {
                if (region.active) {
                    [self startMonitoringRegion:region];
                }
            }
        }
    });
}

- (void)stopMonitoring {
    dispatch_async(_geofenceQueue, ^{
        if (self.monitoring) {
            self.monitoring = NO;
            
            // 停止更新位置
            [self.locationManager stopUpdatingLocation];
            
            // 停止所有活跃的围栏
            for (GPSGeofenceRegion *region in self.geofences.allValues) {
                if (region.active) {
                    [self stopMonitoringRegion:region];
                }
            }
            
            // 清除状态
            [self.dwellStartTimes removeAllObjects];
            [self.currentlyInsideRegions removeAllObjects];
        }
    });
}

- (void)checkLocationAgainstGeofences:(CLLocation *)location {
    dispatch_async(_geofenceQueue, ^{
        if (!self.monitoring) return;
        
        NSMutableSet *insideRegionIds = [NSMutableSet set];
        NSDate *now = [NSDate date];
        
        // 检查每个活跃的围栏
        for (GPSGeofenceRegion *region in self.geofences.allValues) {
            if (!region.active) continue;
            
            BOOL inside = [region containsCoordinate:location.coordinate];
            NSString *regionId = region.identifier;
            
            if (inside) {
                [insideRegionIds addObject:regionId];
                
                // 检查进入事件
                if (![self.currentlyInsideRegions containsObject:regionId]) {
                    // 新进入区域
                    [self.currentlyInsideRegions addObject:regionId];
                    
                    if (region.notifyOnEntry) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if ([self.delegate respondsToSelector:@selector(didEnterGeofenceRegion:)]) {
                                [self.delegate didEnterGeofenceRegion:region];
                            }
                        });
                    }
                    
                    // 如果需要停留通知，记录进入时间
                    if (region.notifyOnDwell) {
                        self.dwellStartTimes[regionId] = now;
                    }
                } else if (region.notifyOnDwell) {
                    // 已经在区域内，检查停留时间
                    NSDate *entryTime = self.dwellStartTimes[regionId];
                    if (entryTime && [now timeIntervalSinceDate:entryTime] >= region.dwellTime) {
                        // 已停留足够长时间
                        [self.dwellStartTimes removeObjectForKey:regionId]; // 防止重复通知
                        
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // 这里可以添加停留通知的回调方法
                            NSLog(@"用户已在围栏 %@ 停留超过 %f 秒", region.name, region.dwellTime);
                        });
                    }
                }
            }
        }
        
        // 检查离开事件
        NSMutableSet *exitedRegionIds = [NSMutableSet setWithSet:self.currentlyInsideRegions];
        [exitedRegionIds minusSet:insideRegionIds];
        
        for (NSString *exitedId in exitedRegionIds) {
            GPSGeofenceRegion *region = self.geofences[exitedId];
            if (region && region.notifyOnExit) {
                [self.currentlyInsideRegions removeObject:exitedId];
                [self.dwellStartTimes removeObjectForKey:exitedId];
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(didExitGeofenceRegion:)]) {
                        [self.delegate didExitGeofenceRegion:region];
                    }
                });
            }
        }
    });
}

#pragma mark - Private Methods

- (void)startMonitoringRegion:(GPSGeofenceRegion *)region {
    // 原生圆形围栏可以使用CoreLocation的区域监控
    if (region.type == GPSGeofenceTypeCircular) {
        // 检查设备是否支持区域监控
        if ([CLLocationManager isMonitoringAvailableForClass:[CLCircularRegion class]]) {
            CLCircularRegion *clRegion = [[CLCircularRegion alloc] 
                                          initWithCenter:region.center 
                                          radius:region.radius 
                                          identifier:region.identifier];
            
            clRegion.notifyOnEntry = region.notifyOnEntry;
            clRegion.notifyOnExit = region.notifyOnExit;
            
            [self.locationManager startMonitoringForRegion:clRegion];
        }
    }
    // 其他类型的围栏使用自定义检测
}

- (void)stopMonitoringRegion:(GPSGeofenceRegion *)region {
    if (region.type == GPSGeofenceTypeCircular) {
        for (CLRegion *clRegion in self.locationManager.monitoredRegions) {
            if ([clRegion.identifier isEqualToString:region.identifier]) {
                [self.locationManager stopMonitoringForRegion:clRegion];
                break;
            }
        }
    }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (locations.count > 0) {
        CLLocation *location = [locations lastObject];
        [self checkLocationAgainstGeofences:location];
    }
}

- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    dispatch_async(_geofenceQueue, ^{
        GPSGeofenceRegion *geofence = self.geofences[region.identifier];
        if (geofence && geofence.active) {
            [self.currentlyInsideRegions addObject:region.identifier];
            
            if (geofence.notifyOnDwell) {
                self.dwellStartTimes[region.identifier] = [NSDate date];
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(didEnterGeofenceRegion:)]) {
                    [self.delegate didEnterGeofenceRegion:geofence];
                }
            });
        }
    });
}

- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    dispatch_async(_geofenceQueue, ^{
        GPSGeofenceRegion *geofence = self.geofences[region.identifier];
        if (geofence && geofence.active) {
            [self.currentlyInsideRegions removeObject:region.identifier];
            [self.dwellStartTimes removeObjectForKey:region.identifier];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(didExitGeofenceRegion:)]) {
                    [self.delegate didExitGeofenceRegion:geofence];
                }
            });
        }
    });
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error {
    dispatch_async(_geofenceQueue, ^{
        GPSGeofenceRegion *geofence = self.geofences[region.identifier];
        if (geofence) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([self.delegate respondsToSelector:@selector(monitoringFailedForRegion:withError:)]) {
                    [self.delegate monitoringFailedForRegion:geofence withError:error];
                }
            });
        }
    });
}

#pragma mark - Import/Export Methods

- (NSData *)exportGeofencesAsGeoJSON {
    __block NSData *jsonData = nil;
    dispatch_sync(_geofenceQueue, ^{
        NSMutableDictionary *geoJSON = @{
            @"type": @"FeatureCollection",
            @"features": [NSMutableArray array]
        }.mutableCopy;
        
        NSMutableArray *features = geoJSON[@"features"];
        
        // 添加每个围栏作为一个Feature
        for (GPSGeofenceRegion *region in self.geofences.allValues) {
            NSMutableDictionary *feature = @{
                @"type": @"Feature",
                @"properties": @{
                    @"id": region.identifier ?: @"",
                    @"name": region.name ?: @"",
                    @"active": @(region.active),
                    @"notifyOnEntry": @(region.notifyOnEntry),
                    @"notifyOnExit": @(region.notifyOnExit),
                    @"notifyOnDwell": @(region.notifyOnDwell),
                    @"dwellTime": @(region.dwellTime),
                    @"geofenceType": @(region.type)
                }.mutableCopy,
                @"geometry": [NSMutableDictionary dictionary]
            }.mutableCopy;
            
            // 添加元数据
            if (region.metadata) {
                [feature[@"properties"] addEntriesFromDictionary:region.metadata];
            }
            
            NSMutableDictionary *geometry = feature[@"geometry"];
            
            switch (region.type) {
                case GPSGeofenceTypeCircular: {
                    geometry[@"type"] = @"Point";
                    geometry[@"coordinates"] = @[@(region.center.longitude), @(region.center.latitude)];
                    feature[@"properties"][@"radius"] = @(region.radius);
                    break;
                }
                case GPSGeofenceTypePolygon: {
                    geometry[@"type"] = @"Polygon";
                    NSMutableArray *coordinates = [NSMutableArray array];
                    NSMutableArray *ring = [NSMutableArray array];
                    
                    for (NSValue *value in region.coordinates) {
                        CLLocationCoordinate2D coord = [value MKCoordinateValue];
                        [ring addObject:@[@(coord.longitude), @(coord.latitude)]];
                    }
                    
                    // 确保多边形闭合
                    if (region.coordinates.count > 0) {
                        CLLocationCoordinate2D firstCoord = [region.coordinates.firstObject MKCoordinateValue];
                        [ring addObject:@[@(firstCoord.longitude), @(firstCoord.latitude)]];
                    }
                    
                    [coordinates addObject:ring];
                    geometry[@"coordinates"] = coordinates;
                    break;
                }
                case GPSGeofenceTypePath: {
                    geometry[@"type"] = @"LineString";
                    NSMutableArray *coordinates = [NSMutableArray array];
                    
                    for (CLLocation *location in region.pathPoints) {
                        [coordinates addObject:@[@(location.coordinate.longitude), @(location.coordinate.latitude)]];
                    }
                    
                    geometry[@"coordinates"] = coordinates;
                    feature[@"properties"][@"pathWidth"] = @(region.pathWidth);
                    break;
                }
            }
            
            [features addObject:feature];
        }
        
        NSError *error = nil;
        jsonData = [NSJSONSerialization dataWithJSONObject:geoJSON options:NSJSONWritingPrettyPrinted error:&error];
        
        if (error) {
            NSLog(@"导出GeoJSON时出错: %@", error.localizedDescription);
        }
    });
    
    return jsonData;
}

- (BOOL)importGeofencesFromGeoJSON:(NSData *)data error:(NSError **)error {
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSGeofencingDomain" code:100 userInfo:@{NSLocalizedDescriptionKey: @"数据为空"}];
        }
        return NO;
    }
    
    NSError *jsonError = nil;
    NSDictionary *geoJSON = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    
    if (jsonError) {
        if (error) *error = jsonError;
        return NO;
    }
    
    if (![geoJSON isKindOfClass:[NSDictionary class]] || ![geoJSON[@"type"] isEqualToString:@"FeatureCollection"]) {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSGeofencingDomain" code:101 userInfo:@{NSLocalizedDescriptionKey: @"无效的GeoJSON格式"}];
        }
        return NO;
    }
    
    NSArray *features = geoJSON[@"features"];
    if (![features isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSGeofencingDomain" code:102 userInfo:@{NSLocalizedDescriptionKey: @"无效的features数组"}];
        }
        return NO;
    }
    
    __block BOOL success = YES;
    
    dispatch_sync(_geofenceQueue, ^{
        for (NSDictionary *feature in features) {
            if (![feature isKindOfClass:[NSDictionary class]] || ![feature[@"type"] isEqualToString:@"Feature"]) continue;
            
            NSDictionary *properties = feature[@"properties"];
            NSDictionary *geometry = feature[@"geometry"];
            
            if (!properties || !geometry) continue;
            
            GPSGeofenceRegion *region = [[GPSGeofenceRegion alloc] init];
            
            // 设置基本属性
            if (properties[@"id"] && [properties[@"id"] isKindOfClass:[NSString class]]) {
                region.identifier = properties[@"id"];
            }
            
            if (properties[@"name"] && [properties[@"name"] isKindOfClass:[NSString class]]) {
                region.name = properties[@"name"];
            }
            
            if (properties[@"active"] && [properties[@"active"] isKindOfClass:[NSNumber class]]) {
                region.active = [properties[@"active"] boolValue];
            }
            
            if (properties[@"notifyOnEntry"] && [properties[@"notifyOnEntry"] isKindOfClass:[NSNumber class]]) {
                region.notifyOnEntry = [properties[@"notifyOnEntry"] boolValue];
            }
            
            if (properties[@"notifyOnExit"] && [properties[@"notifyOnExit"] isKindOfClass:[NSNumber class]]) {
                region.notifyOnExit = [properties[@"notifyOnExit"] boolValue];
            }
            
            if (properties[@"notifyOnDwell"] && [properties[@"notifyOnDwell"] isKindOfClass:[NSNumber class]]) {
                region.notifyOnDwell = [properties[@"notifyOnDwell"] boolValue];
            }
            
            if (properties[@"dwellTime"] && [properties[@"dwellTime"] isKindOfClass:[NSNumber class]]) {
                region.dwellTime = [properties[@"dwellTime"] doubleValue];
            }
            
            // 设置几何形状和类型特定属性
            NSString *geometryType = geometry[@"type"];
            NSArray *coordinates = geometry[@"coordinates"];
            
            if ([geometryType isEqualToString:@"Point"] && coordinates.count == 2) {
                region.type = GPSGeofenceTypeCircular;
                region.center = CLLocationCoordinate2DMake([coordinates[1] doubleValue], [coordinates[0] doubleValue]);
                
                if (properties[@"radius"] && [properties[@"radius"] isKindOfClass:[NSNumber class]]) {
                    region.radius = [properties[@"radius"] doubleValue];
                } else {
                    region.radius = 100.0; // 默认半径
                }
            } 
            else if ([geometryType isEqualToString:@"Polygon"] && [coordinates isKindOfClass:[NSArray class]] && coordinates.count > 0) {
                region.type = GPSGeofenceTypePolygon;
                NSArray *ring = coordinates[0]; // 使用第一个环
                
                NSMutableArray *coords = [NSMutableArray array];
                for (NSArray *point in ring) {
                    if (point.count >= 2) {
                        CLLocationCoordinate2D coord = CLLocationCoordinate2DMake([point[1] doubleValue], [point[0] doubleValue]);
                        [coords addObject:[NSValue valueWithMKCoordinate:coord]];
                    }
                }
                
                // 移除最后一个点如果它是闭合点
                if (coords.count > 1) {
                    CLLocationCoordinate2D first = [coords.firstObject MKCoordinateValue];
                    CLLocationCoordinate2D last = [coords.lastObject MKCoordinateValue];
                    
                    if (first.latitude == last.latitude && first.longitude == last.longitude) {
                        [coords removeLastObject];
                    }
                }
                
                region.coordinates = coords;
            }
            else if ([geometryType isEqualToString:@"LineString"] && [coordinates isKindOfClass:[NSArray class]]) {
                region.type = GPSGeofenceTypePath;
                
                NSMutableArray *pathPoints = [NSMutableArray array];
                for (NSArray *point in coordinates) {
                    if (point.count >= 2) {
                        CLLocationDegrees lat = [point[1] doubleValue];
                        CLLocationDegrees lng = [point[0] doubleValue];
                        CLLocation *location = [[CLLocation alloc] initWithLatitude:lat longitude:lng];
                        [pathPoints addObject:location];
                    }
                }
                
                region.pathPoints = pathPoints;
                
                if (properties[@"pathWidth"] && [properties[@"pathWidth"] isKindOfClass:[NSNumber class]]) {
                    region.pathWidth = [properties[@"pathWidth"] doubleValue];
                } else {
                    region.pathWidth = 50.0; // 默认路径宽度
                }
            }
            else {
                // 无效的几何类型或坐标
                continue;
            }
            
            // 提取自定义元数据
            NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
            for (NSString *key in properties) {
                // 跳过我们已经处理的标准属性
                if (![key isEqualToString:@"id"] &&
                    ![key isEqualToString:@"name"] &&
                    ![key isEqualToString:@"active"] &&
                    ![key isEqualToString:@"notifyOnEntry"] &&
                    ![key isEqualToString:@"notifyOnExit"] &&
                    ![key isEqualToString:@"notifyOnDwell"] &&
                    ![key isEqualToString:@"dwellTime"] &&
                    ![key isEqualToString:@"geofenceType"] &&
                    ![key isEqualToString:@"radius"] &&
                    ![key isEqualToString:@"pathWidth"]) {
                    
                    metadata[key] = properties[key];
                }
            }
            
            if (metadata.count > 0) {
                region.metadata = metadata;
            }
            
            // 添加围栏
            self.geofences[region.identifier] = region;
            
            if (self.monitoring && region.active) {
                [self startMonitoringRegion:region];
            }
        }
    });
    
    return success;
}

@end