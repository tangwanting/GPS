/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import "MapViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>
#import "GPSAdvancedSettingsViewController.h"
#import "GPSCoordinateUtils.h"
#import "GPSLocationModel.h"
#import "GPSLocationViewModel.h"
#import "GPSRouteManager.h"

// 全局常量定义
#define kUserDefaultsDomain                @"com.gps.locationspoofer"
#define kLocationSpoofingEnabledKey        @"LocationSpoofingEnabled"
#define kAltitudeSpoofingEnabledKey        @"AltitudeSpoofingEnabled"
#define kLatitudeKey                       @"latitude"
#define kLongitudeKey                      @"longitude"
#define kAltitudeKey                       @"altitude"
#define kSpeedKey                          @"speed"
#define kCourseKey                         @"course"
#define kAccuracyKey                       @"accuracy"
#define kLocationHistoryKey                @"LocationHistory"
#define kPresetLocationsKey                @"PresetLocations"
#define kMovingModeEnabledKey              @"MovingModeEnabled"
#define kMovingPathKey                     @"MovingPath"
#define kMovingSpeedKey                    @"MovingSpeed"
#define kRandomizeKey                      @"RandomizeEnabled"
#define kRandomizeRadiusKey                @"RandomizeRadius"
#define kAutoStepKey                       @"AutoStepEnabled"
#define kAutoStepDistanceKey               @"AutoStepDistance"

// 通知常量 
NSString *const kLocationSpoofingChangedNotification = @"LocationSpoofingChanged";
NSString *const kAltitudeSpoofingChangedNotification = @"AltitudeSpoofingChanged";
NSString *const kMovingModeChangedNotification = @"MovingModeChanged";
NSString *const kShowGPSSettingsNotification = @"ShowGPSSettings";

// 位置模拟管理器 - 统一管理模拟位置逻辑
@interface GPSLocationManager : NSObject

+ (instancetype)sharedManager;

@property (nonatomic, assign) BOOL isLocationSpoofingEnabled;
@property (nonatomic, assign) BOOL isAltitudeSpoofingEnabled;
@property (nonatomic, assign) BOOL isMovingModeEnabled;
@property (nonatomic, assign) BOOL isRandomizeEnabled;
@property (nonatomic, assign) BOOL isAutoStepEnabled;

@property (nonatomic, strong) NSMutableArray<CLLocation *> *movingPath;
@property (nonatomic, assign) NSUInteger currentPathIndex;
@property (nonatomic, assign) double movingSpeed;
@property (nonatomic, assign) double autoStepDistance;
@property (nonatomic, assign) double randomizeRadius;

@property (nonatomic, strong) CLLocation *cachedFakeLocation;
@property (nonatomic, strong) NSDate *lastLocationUpdate;

- (void)loadSettings;
- (void)saveSettings;
- (CLLocation *)nextFakeLocation;
- (CLLocation *)createFakeLocationWithLatitude:(double)latitude longitude:(double)longitude altitude:(double)altitude;
- (CLLocation *)randomLocationAroundCurrentLocation;
- (NSArray<CLLocation *> *)generatePathFromLocation:(CLLocation *)startLoc toLocation:(CLLocation *)endLoc withSteps:(NSUInteger)steps;
- (void)startAutomatedMovement;
- (void)stopAutomatedMovement;
@end

@implementation GPSLocationManager

+ (instancetype)sharedManager {
    static GPSLocationManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GPSLocationManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        [self loadSettings];
        _movingPath = [NSMutableArray array];
        _currentPathIndex = 0;
        
        // 监听设置变更通知
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                selector:@selector(handleLocationSpoofingChanged:) 
                                                    name:kLocationSpoofingChangedNotification 
                                                  object:nil];
    }
    return self;
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    _isLocationSpoofingEnabled = [defaults boolForKey:kLocationSpoofingEnabledKey];
    _isAltitudeSpoofingEnabled = [defaults boolForKey:kAltitudeSpoofingEnabledKey];
    _isMovingModeEnabled = [defaults boolForKey:kMovingModeEnabledKey];
    _isRandomizeEnabled = [defaults boolForKey:kRandomizeKey];
    _isAutoStepEnabled = [defaults boolForKey:kAutoStepKey];
    
    _movingSpeed = [defaults doubleForKey:kMovingSpeedKey] ?: 5.0; // 默认5m/s
    _autoStepDistance = [defaults doubleForKey:kAutoStepDistanceKey] ?: 10.0; // 默认10m
    _randomizeRadius = [defaults doubleForKey:kRandomizeRadiusKey] ?: 50.0; // 默认50m半径
    
    // 恢复路径数据（如果有）
    NSArray *pathData = [defaults objectForKey:kMovingPathKey];
    if (pathData && pathData.count > 0) {
        _movingPath = [NSMutableArray array];
        for (NSDictionary *locationDict in pathData) {
            double lat = [locationDict[@"latitude"] doubleValue];
            double lng = [locationDict[@"longitude"] doubleValue];
            double alt = [locationDict[@"altitude"] doubleValue];
            CLLocation *location = [[CLLocation alloc] initWithCoordinate:CLLocationCoordinate2DMake(lat, lng)
                                                               altitude:alt
                                                     horizontalAccuracy:5.0
                                                       verticalAccuracy:5.0
                                                              timestamp:[NSDate date]];
            [_movingPath addObject:location];
        }
    }
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:_isLocationSpoofingEnabled forKey:kLocationSpoofingEnabledKey];
    [defaults setBool:_isAltitudeSpoofingEnabled forKey:kAltitudeSpoofingEnabledKey];
    [defaults setBool:_isMovingModeEnabled forKey:kMovingModeEnabledKey];
    [defaults setBool:_isRandomizeEnabled forKey:kRandomizeKey];
    [defaults setBool:_isAutoStepEnabled forKey:kAutoStepKey];
    
    [defaults setDouble:_movingSpeed forKey:kMovingSpeedKey];
    [defaults setDouble:_autoStepDistance forKey:kAutoStepDistanceKey];
    [defaults setDouble:_randomizeRadius forKey:kRandomizeRadiusKey];
    
    // 保存路径数据
    if (_movingPath && _movingPath.count > 0) {
        NSMutableArray *pathData = [NSMutableArray array];
        for (CLLocation *location in _movingPath) {
            [pathData addObject:@{
                @"latitude": @(location.coordinate.latitude),
                @"longitude": @(location.coordinate.longitude),
                @"altitude": @(location.altitude)
            }];
        }
        [defaults setObject:pathData forKey:kMovingPathKey];
    }
    
    [defaults synchronize];
}

- (CLLocation *)nextFakeLocation {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // 如果启用了移动模式且有路径数据
    if (_isMovingModeEnabled && _movingPath.count > 0) {
        CLLocation *nextLocation = _movingPath[_currentPathIndex];
        _currentPathIndex = (_currentPathIndex + 1) % _movingPath.count;
        return [self createEnhancedLocation:nextLocation];
    }
    
    // 如果启用了随机化
    if (_isRandomizeEnabled) {
        return [self randomLocationAroundCurrentLocation];
    }
    
    // 基础模式 - 固定位置
    // 检查是否需要刷新缓存的位置
    if (!_cachedFakeLocation || [[NSDate date] timeIntervalSinceDate:_lastLocationUpdate] > 10.0) {
        double latitude = [defaults doubleForKey:kLatitudeKey] ?: 0.0;
        double longitude = [defaults doubleForKey:kLongitudeKey] ?: 0.0;
        double altitude = [defaults doubleForKey:kAltitudeKey] ?: 0.0;
        
        // 添加微小随机偏移，提高真实性
        if (!_isAutoStepEnabled) { // 自动移动模式下不添加随机偏移
            double latOffset = ((double)arc4random() / UINT32_MAX - 0.5) * 0.0001;
            double lngOffset = ((double)arc4random() / UINT32_MAX - 0.5) * 0.0001;
            latitude += latOffset;
            longitude += lngOffset;
        }
        
        _cachedFakeLocation = [self createFakeLocationWithLatitude:latitude 
                                                         longitude:longitude 
                                                          altitude:altitude];
        _lastLocationUpdate = [NSDate date];
    }
    
    // 如果启用了自动移动
    if (_isAutoStepEnabled && _cachedFakeLocation) {
        return [self stepFromLocation:_cachedFakeLocation];
    }
    
    return _cachedFakeLocation;
}

- (CLLocation *)createFakeLocationWithLatitude:(double)latitude longitude:(double)longitude altitude:(double)altitude {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    double speed = [defaults doubleForKey:kSpeedKey] ?: 0.0;
    double course = [defaults doubleForKey:kCourseKey] ?: 0.0;
    double horizontalAccuracy = [defaults doubleForKey:kAccuracyKey] ?: 5.0;
    
    return [[CLLocation alloc] 
            initWithCoordinate:CLLocationCoordinate2DMake(latitude, longitude)
            altitude:altitude
            horizontalAccuracy:horizontalAccuracy
            verticalAccuracy:3.0
            course:course
            speed:speed 
            timestamp:[NSDate date]];
}

// 增强位置数据，添加额外信息
- (CLLocation *)createEnhancedLocation:(CLLocation *)baseLocation {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    double speed = [defaults doubleForKey:kSpeedKey] ?: _movingSpeed;
    double course = [defaults doubleForKey:kCourseKey] ?: 0.0;
    
    // 如果在路径上移动，计算航向角
    if (_isMovingModeEnabled && _movingPath.count > 1 && _currentPathIndex > 0) {
        NSUInteger prevIndex = (_currentPathIndex - 1) % _movingPath.count;
        CLLocation *prevLocation = _movingPath[prevIndex];
        
        // 计算两点之间的方位角
        double y = sin(baseLocation.coordinate.longitude - prevLocation.coordinate.longitude) * cos(baseLocation.coordinate.latitude);
        double x = cos(prevLocation.coordinate.latitude) * sin(baseLocation.coordinate.latitude) -
                sin(prevLocation.coordinate.latitude) * cos(baseLocation.coordinate.latitude) * 
                cos(baseLocation.coordinate.longitude - prevLocation.coordinate.longitude);
        course = fmod(atan2(y, x) * 180.0 / M_PI + 360.0, 360.0);
    }
    
    // 创建新的位置对象，保留原始坐标但更新其他属性
    return [[CLLocation alloc] 
            initWithCoordinate:baseLocation.coordinate
            altitude:baseLocation.altitude
            horizontalAccuracy:baseLocation.horizontalAccuracy
            verticalAccuracy:baseLocation.verticalAccuracy
            course:course
            speed:speed 
            timestamp:[NSDate date]];
}

- (CLLocation *)randomLocationAroundCurrentLocation {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    double baseLat = [defaults doubleForKey:kLatitudeKey] ?: 0.0;
    double baseLng = [defaults doubleForKey:kLongitudeKey] ?: 0.0;
    double baseAlt = [defaults doubleForKey:kAltitudeKey] ?: 0.0;
    
    // 地球半径（米）
    const double EARTH_RADIUS = 6378137.0;
    
    // 随机角度
    double angle = ((double)arc4random() / UINT32_MAX) * 2.0 * M_PI;
    
    // 随机距离（在设定半径内）
    double distance = ((double)arc4random() / UINT32_MAX) * _randomizeRadius;
    
    // 转换为经纬度变化
    double latChange = (distance * cos(angle)) / EARTH_RADIUS * 180.0 / M_PI;
    double lngChange = (distance * sin(angle)) / (EARTH_RADIUS * cos(baseLat * M_PI / 180.0)) * 180.0 / M_PI;
    
    double newLat = baseLat + latChange;
    double newLng = baseLng + lngChange;
    
    // 确保维度在合法范围内 (-90 到 90)
    newLat = fmax(-90.0, fmin(90.0, newLat));
    
    // 修正经度以确保在 -180 到 180 范围内
    while (newLng > 180.0) newLng -= 360.0;
    while (newLng < -180.0) newLng += 360.0;
    
    // 随机化海拔（±5米）
    double altVariation = ((double)arc4random() / UINT32_MAX - 0.5) * 10.0;
    double newAlt = baseAlt + altVariation;
    
    return [self createFakeLocationWithLatitude:newLat longitude:newLng altitude:newAlt];
}

- (CLLocation *)stepFromLocation:(CLLocation *)location {
    // 自动移动模式 - 朝当前航向方向移动一小步
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    double course = [defaults doubleForKey:kCourseKey] ?: 0.0; // 默认朝北
    
    // 将航向角转换为弧度
    double courseRadians = course * M_PI / 180.0;
    
    // 地球半径（米）
    const double EARTH_RADIUS = 6378137.0;
    
    // 计算目标点
    double distance = _autoStepDistance; // 每次移动的距离（米）
    
    // 将距离转换为经纬度变化
    double latChange = (distance * cos(courseRadians)) / EARTH_RADIUS * 180.0 / M_PI;
    double lngChange = (distance * sin(courseRadians)) / (EARTH_RADIUS * cos(location.coordinate.latitude * M_PI / 180.0)) * 180.0 / M_PI;
    
    double newLat = location.coordinate.latitude + latChange;
    double newLng = location.coordinate.longitude + lngChange;
    
    // 更新缓存位置
    _cachedFakeLocation = [self createFakeLocationWithLatitude:newLat longitude:newLng altitude:location.altitude];
    _lastLocationUpdate = [NSDate date];
    
    return _cachedFakeLocation;
}

- (NSArray<CLLocation *> *)generatePathFromLocation:(CLLocation *)startLoc toLocation:(CLLocation *)endLoc withSteps:(NSUInteger)steps {
    if (steps < 2) steps = 2; // 至少需要起点和终点
    
    NSMutableArray<CLLocation *> *path = [NSMutableArray arrayWithCapacity:steps];
    
    // 计算每一步的增量
    double latStep = (endLoc.coordinate.latitude - startLoc.coordinate.latitude) / (steps - 1);
    double lngStep = (endLoc.coordinate.longitude - startLoc.coordinate.longitude) / (steps - 1);
    double altStep = (endLoc.altitude - startLoc.altitude) / (steps - 1);
    
    for (NSUInteger i = 0; i < steps; i++) {
        double lat = startLoc.coordinate.latitude + latStep * i;
        double lng = startLoc.coordinate.longitude + lngStep * i;
        double alt = startLoc.altitude + altStep * i;
        
        CLLocation *point = [self createFakeLocationWithLatitude:lat longitude:lng altitude:alt];
        [path addObject:point];
    }
    
    return path;
}

- (void)startAutomatedMovement {
    // 停止可能存在的旧定时器
    [self stopAutomatedMovement];
    
    // 确保有可用的路径
    if (_movingPath.count < 2) {
        NSLog(@"[GPS++] 自动移动需要至少2个路径点");
        return;
    }
    
    // 创建一个定时器来驱动自动移动
    NSTimeInterval updateInterval = 1.0;  // 默认1秒更新一次
    
    // 根据移动速度计算更新频率
    if (_movingSpeed > 0) {
        // 速度越快，更新频率越高
        updateInterval = 1.0 / (_movingSpeed * 0.2);
        // 限制在合理范围内
        updateInterval = fmax(0.1, fmin(updateInterval, 2.0));
    }
    
    // 创建并保存定时器
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, 
                           dispatch_time(DISPATCH_TIME_NOW, updateInterval * NSEC_PER_SEC), 
                           updateInterval * NSEC_PER_SEC, 
                           0.1 * NSEC_PER_SEC);
    
    // 定时器执行的操作
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(timer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.movingPath.count > 0) {
            // 更新位置索引
            strongSelf.currentPathIndex = (strongSelf.currentPathIndex + 1) % strongSelf.movingPath.count;
            
            // 更新缓存的位置
            strongSelf.cachedFakeLocation = [strongSelf createEnhancedLocation:strongSelf.movingPath[strongSelf.currentPathIndex]];
            strongSelf.lastLocationUpdate = [NSDate date];
            
            // 记录路径移动
            NSLog(@"[GPS++] 自动移动到路径点 %lu/%lu", 
                (unsigned long)strongSelf.currentPathIndex + 1, 
                (unsigned long)strongSelf.movingPath.count);
        }
    });
    
    // 启动定时器
    dispatch_resume(timer);
    
    // 保存定时器引用
    objc_setAssociatedObject(self, "automatedMovementTimer", timer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    NSLog(@"[GPS++] 自动移动已启动，每 %.1f 秒更新一次位置", updateInterval);
}

- (void)stopAutomatedMovement {
    // 获取并释放定时器
    dispatch_source_t timer = objc_getAssociatedObject(self, "automatedMovementTimer");
    if (timer) {
        dispatch_source_cancel(timer);
        objc_setAssociatedObject(self, "automatedMovementTimer", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSLog(@"[GPS++] 自动移动已停止");
    }
}

- (void)handleLocationSpoofingChanged:(NSNotification *)notification {
    // 重置位置缓存
    self.cachedFakeLocation = nil;
    self.lastLocationUpdate = nil;
    
    // 如果禁用了位置模拟，同时也禁用移动模式
    if (!self.isLocationSpoofingEnabled) {
        self.isMovingModeEnabled = NO;
        self.isRandomizeEnabled = NO;
        self.isAutoStepEnabled = NO;
        [self saveSettings];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

// SpringBoard 头文件扩展
@interface SpringBoard : UIApplication
- (void)addGPSIconToStatusBar;
- (UIViewController *)_topViewController;
- (void)openGPSSettings;
- (void)openGPSAdvancedSettings;
- (void)handleLocationSpoofingChanged:(NSNotification *)notification;
- (void)handleAltitudeSpoofingChanged:(NSNotification *)notification;
- (void)setupAdvancedGestures;
- (void)showGPSQuickOptions;
- (void)showToastWithMessage:(NSString *)message;
- (void)toggleRandomWalk;
@end

// CLLocationManager 自定义方法
@interface CLLocationManager (GPS)
- (void)sendFakeLocationUpdate;
@end

// CLHeading 自定义方法
@interface CLHeading (Custom)
+ (CLHeading *)fakeHeadingWithMagnetic:(double)magnetic trueHeading:(double)trueHeading accuracy:(double)accuracy timestamp:(NSDate *)timestamp;
@end

// 开始实现钩子组
%group GPSSpoofingTweak

%hook SpringBoard

%new
- (void)showGPSQuickOptions {
    NSLog(@"[GPS++] SpringBoard显示GPS选项");
    
    // 发出通知让GPSTriggerManager处理
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kShowGPSSettingsNotification object:nil];
    });
}

%end

// 钩住CLLocationManager
%hook CLLocationManager

// 伪造位置的方法实现
%new
- (void)sendFakeLocationUpdate {
    GPSLocationViewModel *viewModel = [GPSLocationViewModel sharedInstance];
    if (viewModel.isLocationSpoofingEnabled) {
        CLLocationCoordinate2D coordinate = viewModel.currentLocation.coordinate;
        
        if (CLLocationCoordinate2DIsValid(coordinate)) {
            // 创建一个准确的CLLocation对象
            double accuracy = viewModel.currentLocation.accuracy > 0 ? viewModel.currentLocation.accuracy : 5.0;
            double altitude = viewModel.currentLocation.altitude;
            double speed = viewModel.currentLocation.speed;
            double course = viewModel.currentLocation.course;
            
            NSDate *timestamp = [NSDate date];
            
            // 创建完整的CLLocation对象，确保所有属性都有值
            CLLocation *fakeLocation = [[CLLocation alloc] 
                initWithCoordinate:coordinate
                altitude:altitude
                horizontalAccuracy:accuracy
                verticalAccuracy:accuracy
                course:course
                speed:speed
                timestamp:timestamp];
            
            // 确保代理方法存在后再调用
            if (self.delegate && [self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate locationManager:self didUpdateLocations:@[fakeLocation]];
                });
            }
            
            // 确保回调块也被调用 - 使用更兼容的方式
            if (@available(iOS 14.0, *)) {
                SEL handlerSelector = NSSelectorFromString(@"locationUpdateHandler");
                if ([self respondsToSelector:handlerSelector]) {
                    id handler = [self valueForKey:@"locationUpdateHandler"];
                    if (handler && [handler isKindOfClass:NSClassFromString(@"NSBlock")]) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // 使用performSelector调用block
                            typedef void (^LocationUpdateHandlerBlock)(CLLocationManager *, NSArray *, NSError *);
                            LocationUpdateHandlerBlock block = handler;
                            block(self, @[fakeLocation], nil);
                        });
                    }
                }
            }
        }
    }
}

- (void)startUpdatingLocation {
    GPSLocationViewModel *viewModel = [GPSLocationViewModel sharedInstance];
    if (viewModel.isLocationSpoofingEnabled) {
        // 拦截标准方法，启动自己的模拟器
        NSLog(@"[GPS++] 拦截并替换位置更新 - 使用模拟位置");
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(sendFakeLocationUpdate) object:nil];
        [self performSelector:@selector(sendFakeLocationUpdate) withObject:nil afterDelay:0.1];
        
        // 设置定时器持续发送虚拟位置
        static dispatch_source_t timer;
        if (timer) {
            dispatch_source_cancel(timer);
            timer = nil;
        }
        
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, 
                                 dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), 
                                 0.5 * NSEC_PER_SEC,  // 每0.5秒更新一次
                                 0.1 * NSEC_PER_SEC);
        
        __weak typeof(self) weakSelf = self;
        dispatch_source_set_event_handler(timer, ^{
            [weakSelf sendFakeLocationUpdate];
        });
        
        dispatch_resume(timer);
    } else {
        // 如果没有启用模拟，使用原始方法
        %orig;
    }
}

- (void)stopUpdatingLocation {
    BOOL isEnabled = [GPSLocationManager sharedManager].isLocationSpoofingEnabled;
    
    if (!isEnabled) {
        %orig;
    } else {
        // 停止定时器
        dispatch_source_t timer = objc_getAssociatedObject(self, "fakeLocationTimer");
        if (timer) {
            dispatch_source_cancel(timer);
            objc_setAssociatedObject(self, "fakeLocationTimer", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
}

// 模拟方向数据
- (void)startUpdatingHeading {
    BOOL isEnabled = [GPSLocationManager sharedManager].isLocationSpoofingEnabled;
    
    if (!isEnabled) {
        %orig;
    } else {
        if (self.delegate && [self.delegate respondsToSelector:@selector(locationManager:didUpdateHeading:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
                double heading = [defaults doubleForKey:kCourseKey] ?: 0.0;
                
                // 添加轻微随机偏差，增加真实感
                double headingJitter = ((double)arc4random() / UINT32_MAX - 0.5) * 2.0;
                heading += headingJitter;
                
                // 确保在0-360度范围内
                heading = fmod(heading + 360.0, 360.0);
                
                CLHeading *fakeHeading = [CLHeading fakeHeadingWithMagnetic:heading
                                                               trueHeading:heading
                                                                  accuracy:3.0 + ((double)arc4random() / UINT32_MAX) * 2.0
                                                                 timestamp:[NSDate date]];
                
                [self.delegate locationManager:self didUpdateHeading:fakeHeading];
            });
        }
    }
}

// 模拟授权状态
- (BOOL)locationServicesEnabled {
    if ([GPSLocationManager sharedManager].isLocationSpoofingEnabled) {
        return YES;
    }
    return %orig;
}

- (CLAuthorizationStatus)authorizationStatus {
    if ([GPSLocationManager sharedManager].isLocationSpoofingEnabled) {
        return kCLAuthorizationStatusAuthorizedWhenInUse;
    }
    return %orig;
}

- (CLAuthorizationStatus)_authorizationStatus {
    if ([GPSLocationManager sharedManager].isLocationSpoofingEnabled) {
        return kCLAuthorizationStatusAuthorizedWhenInUse;
    }
    return %orig;
}

%end

// 钩住CLLocation以提供伪造的位置信息
%hook CLLocation

- (CLLocationCoordinate2D)coordinate {
    if ([GPSLocationManager sharedManager].isLocationSpoofingEnabled) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        double latitude = [defaults doubleForKey:kLatitudeKey] ?: 0.0;
        double longitude = [defaults doubleForKey:kLongitudeKey] ?: 0.0;
        
        // 如果有缓存位置，优先使用缓存的坐标
        if ([GPSLocationManager sharedManager].cachedFakeLocation) {
            latitude = [GPSLocationManager sharedManager].cachedFakeLocation.coordinate.latitude;
            longitude = [GPSLocationManager sharedManager].cachedFakeLocation.coordinate.longitude;
        }
        
        return CLLocationCoordinate2DMake(latitude, longitude);
    }
    return %orig;
}

- (CLLocationAccuracy)horizontalAccuracy {
    if ([GPSLocationManager sharedManager].isLocationSpoofingEnabled) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        double baseAccuracy = [defaults doubleForKey:kAccuracyKey] ?: 5.0;
        double jitter = ((double)arc4random() / UINT32_MAX) * 2.0;
        return baseAccuracy + jitter;
    }
    return %orig;
}

- (CLLocationDistance)altitude {
    if ([GPSLocationManager sharedManager].isAltitudeSpoofingEnabled) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        double altitude = [defaults doubleForKey:kAltitudeKey] ?: 0.0;
        
        // 如果有缓存位置，使用缓存的海拔
        if ([GPSLocationManager sharedManager].cachedFakeLocation) {
            altitude = [GPSLocationManager sharedManager].cachedFakeLocation.altitude;
        }
        
        // 添加微小随机变化
        double jitter = ((double)arc4random() / UINT32_MAX - 0.5) * 0.5;
        return altitude + jitter;
    }
    return %orig;
}

- (CLLocationAccuracy)verticalAccuracy {
    if ([GPSLocationManager sharedManager].isAltitudeSpoofingEnabled) {
        return 3.0 + ((double)arc4random() / UINT32_MAX) * 1.5;
    }
    return %orig;
}

- (CLLocationSpeed)speed {
    if ([GPSLocationManager sharedManager].isLocationSpoofingEnabled) {
        if ([GPSLocationManager sharedManager].isMovingModeEnabled) {
            // 移动模式下的速度
            return [GPSLocationManager sharedManager].movingSpeed;
        } else {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            double speed = [defaults doubleForKey:kSpeedKey] ?: 0.0;
            
            // 添加轻微抖动
            double jitter = ((double)arc4random() / UINT32_MAX - 0.5) * 0.2 * speed;
            return fmax(0, speed + jitter); // 保证速度不为负
        }
    }
    return %orig;
}

- (CLLocationDirection)course {
    if ([GPSLocationManager sharedManager].isLocationSpoofingEnabled) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        double course = [defaults doubleForKey:kCourseKey] ?: 0.0;
        
        // 如果是在移动模式下，使用路径计算的方向
        if ([GPSLocationManager sharedManager].isMovingModeEnabled && 
            [GPSLocationManager sharedManager].cachedFakeLocation) {
            course = [GPSLocationManager sharedManager].cachedFakeLocation.course;
        }
        
        return course;
    }
    return %orig;
}

%end

// 实现CLHeading的自定义创建方法
%hook CLHeading

%new
+ (CLHeading *)fakeHeadingWithMagnetic:(double)magnetic trueHeading:(double)trueHeading accuracy:(double)accuracy timestamp:(NSDate *)timestamp {
    CLHeading *heading = [[CLHeading alloc] init];
    
    // 使用KVC设置私有属性
    [heading setValue:@(magnetic) forKey:@"magneticHeading"];
    [heading setValue:@(trueHeading) forKey:@"trueHeading"];
    [heading setValue:@(accuracy) forKey:@"headingAccuracy"];
    [heading setValue:timestamp forKey:@"timestamp"];
    
    return heading;
}

%end

@interface GPSTriggerManager : NSObject

@property (nonatomic, strong) UITapGestureRecognizer *threeFingersGesture; // 改为轻拍手势
@property (nonatomic, strong) NSMutableSet *registeredWindows;
@property (nonatomic, assign) BOOL preventAutoDisplay;

+ (instancetype)sharedManager;
- (void)setupGestureRecognizers;
- (void)updateWindowsWithVisibility:(BOOL)makeVisible;
- (void)handleThreeFingerTap:(UIGestureRecognizer *)gesture;
- (void)showGPSInterface;

@end

// 触发机制
@implementation GPSTriggerManager

- (void)setupGestureRecognizersWithAutoDisplay:(BOOL)allowAutoDisplay {
    // 保存设置，控制是否允许自动显示
    self.preventAutoDisplay = !allowAutoDisplay;
    
    // 注册系统通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(applicationDidBecomeActive)
                                                name:UIApplicationDidBecomeActiveNotification
                                              object:nil];
    
    // 立即添加到当前所有窗口
    [self updateWindowsWithVisibility:YES];
    
    // 监听新窗口创建
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(windowDidBecomeKey:)
                                                name:UIWindowDidBecomeKeyNotification
                                              object:nil];
    
    // 还需要监听应用切换前台
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(applicationWillResignActive)
                                                name:UIApplicationWillResignActiveNotification
                                              object:nil];
    
    NSLog(@"[GPS++] 双指轻拍手势已设置，自动显示=%@", allowAutoDisplay ? @"启用" : @"禁用");
}

+ (instancetype)sharedManager {
    static GPSTriggerManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[GPSTriggerManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        self.registeredWindows = [NSMutableSet new];
        
        // 使用双指轻拍
        self.threeFingersGesture = [[UITapGestureRecognizer alloc] 
                                  initWithTarget:self 
                                  action:@selector(handleThreeFingerTap:)];
        self.threeFingersGesture.numberOfTouchesRequired = 2;
        
        // 关键设置：允许触摸在视图间移动
        self.threeFingersGesture.cancelsTouchesInView = NO;
        self.threeFingersGesture.delaysTouchesBegan = NO;
        self.threeFingersGesture.delaysTouchesEnded = NO;
        
        // 增加额外设置以提高可靠性
        self.threeFingersGesture.numberOfTapsRequired = 1;
    }
    return self;
}

- (void)setupGestureRecognizers {
    // 注册系统通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(applicationDidBecomeActive)
                                                name:UIApplicationDidBecomeActiveNotification
                                              object:nil];
    
    // 立即添加到当前所有窗口
    [self updateWindowsWithVisibility:YES];
    
    // 监听新窗口创建
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(windowDidBecomeKey:)
                                                name:UIWindowDidBecomeKeyNotification
                                              object:nil];
    
    // 还需要监听应用切换前台
    [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(applicationWillResignActive)
                                                name:UIApplicationWillResignActiveNotification
                                              object:nil];
    
    NSLog(@"[GPS++] 双指轻拍手势已设置");
}

- (void)applicationDidBecomeActive {
    NSLog(@"[GPS++] 应用激活，重新注册手势");
    // 延迟一小段时间再添加手势，避免与系统手势冲突
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateWindowsWithVisibility:YES];
    });
}

- (void)applicationWillResignActive {
    NSLog(@"[GPS++] 应用切换到后台，临时移除手势");
    [self updateWindowsWithVisibility:NO];
}

- (void)windowDidBecomeKey:(NSNotification *)notification {
    UIWindow *window = notification.object;
    // 确保是有效窗口
    if (![window isKindOfClass:[UIWindow class]]) {
        return;
    }
    
    if (![self.registeredWindows containsObject:window]) {
        // 添加手势并记录
        [window addGestureRecognizer:self.threeFingersGesture];
        [self.registeredWindows addObject:window];
        NSLog(@"[GPS++] 添加手势到新窗口: %@", window);
    }
}

- (void)updateWindowsWithVisibility:(BOOL)makeVisible {
    NSLog(@"[GPS++] %@所有窗口的手势", makeVisible ? @"添加" : @"移除");
    
    // 获取所有窗口（包括私有API窗口）
    NSArray *allWindows = [UIApplication sharedApplication].windows;
    
    for (UIWindow *window in allWindows) {
        // 排除特定类型的窗口（如键盘窗口）
        if ([NSStringFromClass([window class]) containsString:@"Keyboard"]) {
            continue;
        }
        
        if (makeVisible) {
            if (![self.registeredWindows containsObject:window]) {
                [window addGestureRecognizer:self.threeFingersGesture];
                [self.registeredWindows addObject:window];
                NSLog(@"[GPS++] 添加手势到窗口: %@", window);
            }
        } else {
            if ([self.registeredWindows containsObject:window]) {
                [window removeGestureRecognizer:self.threeFingersGesture];
                [self.registeredWindows removeObject:window];
            }
        }
    }
}

- (void)handleThreeFingerTap:(UIGestureRecognizer *)gesture {
    // 只处理一次手势状态
    if (gesture.state == UIGestureRecognizerStateRecognized) {
        NSLog(@"[GPS++] 检测到双指轻拍手势，正在触发界面...");
        
        // 添加触觉反馈 (类似FLEX的触觉反馈)
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [generator prepare];
            [generator impactOccurred];
        } else {
            AudioServicesPlaySystemSound(1519);
        }
        
        // 显示GPS界面
        [self showGPSInterface];
    }
}

- (void)showGPSInterface {
    // 添加检查，如果设置了阻止自动显示，则检查是否由手势触发
    if (self.preventAutoDisplay) {
        // 这里假设只有通过手势才会调用此方法
        NSLog(@"[GPS++] 手势触发显示GPS界面");
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"[GPS++] 正在直接显示GPS设置界面...");
        
        MapViewController *mapVC = [[MapViewController alloc] init];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:mapVC];
        
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        UIViewController *rootVC = keyWindow.rootViewController;
        UIViewController *topVC = [self topViewControllerWithRootViewController:rootVC];
        
        if (topVC) {
            navController.modalPresentationStyle = UIModalPresentationFullScreen;
            [topVC presentViewController:navController animated:YES completion:nil];
        }
    });
}

// 递归查找顶层控制器
- (UIViewController *)topViewControllerWithRootViewController:(UIViewController *)rootViewController {
    if ([rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = (UINavigationController *)rootViewController;
        return [self topViewControllerWithRootViewController:navigationController.visibleViewController];
    }
    
    if ([rootViewController isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tabController = (UITabBarController *)rootViewController;
        return [self topViewControllerWithRootViewController:tabController.selectedViewController];
    }
    
    if (rootViewController.presentedViewController) {
        return [self topViewControllerWithRootViewController:rootViewController.presentedViewController];
    }
    
    return rootViewController;
}

// 显示提示信息
- (void)showToastWithMessage:(NSString *)message {
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    UIView *toastView = [[UIView alloc] init];
    toastView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    toastView.layer.cornerRadius = 10;
    toastView.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *label = [[UILabel alloc] init];
    label.text = message;
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    
    [toastView addSubview:label];
    [window addSubview:toastView];
    
    // 设置约束
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:toastView.leadingAnchor constant:15],
        [label.trailingAnchor constraintEqualToAnchor:toastView.trailingAnchor constant:-15],
        [label.topAnchor constraintEqualToAnchor:toastView.topAnchor constant:10],
        [label.bottomAnchor constraintEqualToAnchor:toastView.bottomAnchor constant:-10],
        
        [toastView.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [toastView.bottomAnchor constraintEqualToAnchor:window.bottomAnchor constant:-100]
    ]];
    
    // 显示动画
    toastView.alpha = 0;
    [UIView animateWithDuration:0.3 animations:^{
        toastView.alpha = 1;
    } completion:^(BOOL finished) {
        // 2秒后淡出
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toastView.alpha = 0;
            } completion:^(BOOL finished) {
                [toastView removeFromSuperview];
            }];
        });
    }];
}

// 打开GPS设置
- (void)openGPSSettings {
    dispatch_async(dispatch_get_main_queue(), ^{
        MapViewController *mapVC = [[MapViewController alloc] init];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:mapVC];
        
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        UIViewController *rootVC = keyWindow.rootViewController;
        UIViewController *topVC = [self topViewControllerWithRootViewController:rootVC];
        
        if (topVC) {
            navController.modalPresentationStyle = UIModalPresentationFullScreen;
            [topVC presentViewController:navController animated:YES completion:nil];
        }
    });
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self updateWindowsWithVisibility:NO];
}
@end

// 位置重置回调
static void LocationResetCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    // 重置位置数据
    GPSLocationManager *manager = [GPSLocationManager sharedManager];
    manager.cachedFakeLocation = nil;
    manager.lastLocationUpdate = nil;
}

// 显示菜单回调
static void ShowMenuCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SpringBoard *sb = (SpringBoard *)[UIApplication sharedApplication];
        if ([sb respondsToSelector:@selector(showGPSQuickOptions)]) {
            [sb showGPSQuickOptions];
            NSLog(@"[GPS++] 成功调用showGPSQuickOptions方法");
        } else {
            NSLog(@"[GPS++] 错误: SpringBoard钩子未初始化或方法不存在");
            // 尝试使用备用方法显示简单提示
            UIAlertController *alert = [UIAlertController 
                                      alertControllerWithTitle:@"GPS++"
                                      message:@"请使用设置应用打开GPS设置"
                                      preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            
            UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
    });
}

%end

%ctor {
    // 初始化
    NSLog(@"[GPS++] 开始初始化触发机制，当前进程: %@", [NSProcessInfo processInfo].processName);
    
    // 判断是否为证书签名环境
    BOOL isCertificateSigned = NO;
    
    // 检测证书签名环境的方法（通过检查进程路径）
    NSString *processPath = [NSProcessInfo processInfo].processName;
    if ([processPath containsString:@"Application"] && ![processPath containsString:@"SpringBoard"]) {
        isCertificateSigned = YES;
        NSLog(@"[GPS++] 检测到证书签名环境，启用特殊初始化模式");
    }
    
    // 优先初始化GPSLocationManager
    [GPSLocationManager sharedManager];

    // 根据环境选择不同初始化方式
    if (isCertificateSigned) {
        // 证书签名环境下，仅设置手势，不自动显示
        GPSTriggerManager *manager = [GPSTriggerManager sharedManager];
        manager.preventAutoDisplay = YES; // 防止自动显示
        [manager setupGestureRecognizers]; // 只调用基本设置方法
    } else {
        // 越狱环境下的正常初始化
        [[GPSTriggerManager sharedManager] setupGestureRecognizers];
    }
    
    // 初始化钩子组
    %init(GPSSpoofingTweak);
    
    // 监听通知
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), 
                                  NULL, 
                                  LocationResetCallback,
                                  CFSTR("com.gps.locationreset"), 
                                  NULL, 
                                  CFNotificationSuspensionBehaviorDeliverImmediately);
    
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                  NULL,
                                  ShowMenuCallback,
                                  CFSTR("com.gps.showmenu"),
                                  NULL,
                                  CFNotificationSuspensionBehaviorDeliverImmediately);
                                  
    NSLog(@"[GPS++] 初始化完成，手势触发已配置");
}