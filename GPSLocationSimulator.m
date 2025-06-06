#import "GPSLocationSimulator.h"
#import <MapKit/MapKit.h>

@interface GPSLocationSimulator ()

@property (nonatomic, strong) NSTimer *routeTimer;
@property (nonatomic, strong) NSArray<NSValue *> *routeCoordinates;
@property (nonatomic, assign) NSInteger currentRouteIndex;
@property (nonatomic, assign) CLLocationSpeed currentSpeed;
@property (nonatomic, assign) GPSSimulatorMode simulationMode;
@property (nonatomic, strong) CLLocation *lastSimulatedLocation;
@property (nonatomic, assign) BOOL isSimulating;
@property (nonatomic, assign) CLLocationCoordinate2D randomWalkCenter;
@property (nonatomic, assign) CLLocationDistance randomWalkRadius;

@end

@implementation GPSLocationSimulator

+ (instancetype)sharedInstance {
    static GPSLocationSimulator *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _isSimulating = NO;
        _simulationMode = GPSSimulatorModeSingle;
    }
    return self;
}

- (void)setup {
    // 请求位置权限
    if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    }
    
    // 设置高精度
    self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
    
    // 启动更新位置
    [self.locationManager startUpdatingLocation];
    
    NSLog(@"[GPS++] 位置模拟器已初始化");
}

- (void)simulateLocation:(CLLocationCoordinate2D)coordinate {
    [self simulateLocation:coordinate altitude:0 accuracy:10.0];
}

- (void)simulateLocation:(CLLocationCoordinate2D)coordinate 
                altitude:(CLLocationDistance)altitude 
                accuracy:(CLLocationAccuracy)accuracy {
    // 停止任何现有的模拟
    [self stopLocationSimulation];
    
    // 设置模式
    self.simulationMode = GPSSimulatorModeSingle;
    self.isSimulating = YES;
    
    // 创建新的位置对象
    CLLocation *location = [[CLLocation alloc] 
                           initWithCoordinate:coordinate
                                     altitude:altitude
                           horizontalAccuracy:accuracy
                             verticalAccuracy:30.0
                                       course:0.0
                                        speed:0.0
                                    timestamp:[NSDate date]];
    
    // 保存最后模拟的位置
    self.lastSimulatedLocation = location;
    
    // 使用适当的API进行模拟
    [self applyLocationSimulation:location];
    
    NSLog(@"[GPS++] 位置已模拟: %.6f, %.6f", coordinate.latitude, coordinate.longitude);
}

- (void)applyLocationSimulation:(CLLocation *)location {
    // 检查iOS版本和可用API
    if (@available(iOS 15.0, *)) {
        // iOS 15及更高版本使用新API
        CLLocationSourceInformation *sourceInfo = nil;
        
        // 使用正确的初始化方法 - 修正方法名称
        if ([CLLocationSourceInformation instancesRespondToSelector:@selector(initWithSimulationDeviceInfo:)]) {
            // 尝试使用正确的方法
            sourceInfo = [[CLLocationSourceInformation alloc] 
                         performSelector:@selector(initWithSimulationDeviceInfo:) 
                         withObject:@"GPS++"];
        } else {
            // 回退到基本初始化
            sourceInfo = [[CLLocationSourceInformation alloc] init];
        }
        
        // 使用私有API模拟位置
        SEL selector = NSSelectorFromString(@"setLocation:sourceInformation:");
        if ([self.locationManager respondsToSelector:selector]) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
                [[self.locationManager class] instanceMethodSignatureForSelector:selector]];
            [invocation setSelector:selector];
            [invocation setTarget:self.locationManager];
            [invocation setArgument:&location atIndex:2];
            [invocation setArgument:&sourceInfo atIndex:3];
            [invocation invoke];
        }
    } else {
        // iOS 14及更低版本尝试使用其他方法
        SEL selector = NSSelectorFromString(@"_setLocationOverride:");
        if ([self.locationManager respondsToSelector:selector]) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:
                [[self.locationManager class] instanceMethodSignatureForSelector:selector]];
            [invocation setSelector:selector];
            [invocation setTarget:self.locationManager];
            [invocation setArgument:&location atIndex:2];
            [invocation invoke];
        }
    }
    
    // 通知代理
    if ([self.locationManager.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [self.locationManager.delegate locationManager:self.locationManager
                                    didUpdateLocations:@[location]];
    }
}

- (void)simulateRouteWithCoordinates:(NSArray<NSValue *> *)coordinates speed:(CLLocationSpeed)speed {
    if (!coordinates || coordinates.count < 2) {
        NSLog(@"[GPS++] 无效的路线坐标");
        return;
    }
    
    self.routeCoordinates = coordinates;
    self.currentRouteIndex = 0;
    self.currentSpeed = speed;
    self.simulationMode = GPSSimulatorModeRoute;
    self.isSimulating = YES;
    
    // 移除之前的定时器
    [self.routeTimer invalidate];
    
    // 初始位置 - 修正MKCoordinateValue调用
    CLLocationCoordinate2D startCoord;
    // 修正为正确的方法获取坐标
    [coordinates[0] getValue:&startCoord];
    [self simulateLocation:startCoord];
    
    // 设置定时器进行路线模拟
    __weak typeof(self) weakSelf = self;
    self.routeTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf moveAlongRoute];
    }];
}

- (void)moveAlongRoute {
    if (self.currentRouteIndex >= self.routeCoordinates.count - 1) {
        // 路线结束，停止模拟
        [self stopLocationSimulation];
        return;
    }
    
    // 获取当前和下一个坐标点 - 修正MKCoordinateValue调用
    CLLocationCoordinate2D currentCoord;
    CLLocationCoordinate2D nextCoord;
    
    // 修正为正确的方法获取坐标
    [self.routeCoordinates[self.currentRouteIndex] getValue:&currentCoord];
    [self.routeCoordinates[self.currentRouteIndex + 1] getValue:&nextCoord];
    
    // 计算位置
    CLLocation *current = [[CLLocation alloc] initWithLatitude:currentCoord.latitude longitude:currentCoord.longitude];
    CLLocation *next = [[CLLocation alloc] initWithLatitude:nextCoord.latitude longitude:nextCoord.longitude];
    
    // 计算距离和所需时间
    CLLocationDistance distance = [current distanceFromLocation:next];
    NSTimeInterval time = distance / self.currentSpeed;
    
    if (time <= 1.0) {
        // 距离不远，直接移动到下一点
        self.currentRouteIndex++;
        [self simulateLocation:nextCoord];
    } else {
        // 计算插值点
        double fraction = self.currentSpeed / distance;
        double lat = currentCoord.latitude + (nextCoord.latitude - currentCoord.latitude) * fraction;
        double lng = currentCoord.longitude + (nextCoord.longitude - currentCoord.longitude) * fraction;
        CLLocationCoordinate2D interpolated = CLLocationCoordinate2DMake(lat, lng);
        [self simulateLocation:interpolated];
    }
}

- (void)startRandomWalkFromCoordinate:(CLLocationCoordinate2D)centerCoordinate withinRadius:(CLLocationDistance)radius {
    self.randomWalkCenter = centerCoordinate;
    self.randomWalkRadius = radius;
    self.simulationMode = GPSSimulatorModeRandom;
    self.isSimulating = YES;
    
    // 初始位置
    [self simulateLocation:centerCoordinate];
    
    // 移除之前的定时器
    [self.routeTimer invalidate];
    
    // 设置定时器进行随机漫步
    __weak typeof(self) weakSelf = self;
    self.routeTimer = [NSTimer scheduledTimerWithTimeInterval:3.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
        [weakSelf moveRandomly];
    }];
}

- (void)moveRandomly {
    // 生成随机方向和距离
    double angle = ((double)arc4random() / UINT32_MAX) * M_PI * 2;
    double distance = ((double)arc4random() / UINT32_MAX) * self.randomWalkRadius;
    
    // 计算新坐标
    CLLocation *center = [[CLLocation alloc] initWithLatitude:self.randomWalkCenter.latitude 
                                                   longitude:self.randomWalkCenter.longitude];
    
    // 使用地球曲率计算偏移
    double latRadians = self.randomWalkCenter.latitude * M_PI / 180.0;
    double lonRadians = self.randomWalkCenter.longitude * M_PI / 180.0;
    
    // 地球半径(米)
    const double earthRadius = 6371000.0;
    
    // 计算新的经纬度坐标
    double newLat = asin(sin(latRadians) * cos(distance/earthRadius) + 
                        cos(latRadians) * sin(distance/earthRadius) * cos(angle));
    
    double newLon = lonRadians + atan2(sin(angle) * sin(distance/earthRadius) * cos(latRadians),
                                      cos(distance/earthRadius) - sin(latRadians) * sin(newLat));
    
    // 转换回度数
    double newLatDegrees = newLat * 180.0 / M_PI;
    double newLonDegrees = newLon * 180.0 / M_PI;
    
    CLLocationCoordinate2D newCoord = CLLocationCoordinate2DMake(newLatDegrees, newLonDegrees);
    [self simulateLocation:newCoord];
}

- (void)stopLocationSimulation {
    [self.routeTimer invalidate];
    self.routeTimer = nil;
    self.isSimulating = NO;
    
    // [self.locationManager startUpdatingLocation];
}

- (BOOL)isSimulating {
    return _isSimulating;
}

@end