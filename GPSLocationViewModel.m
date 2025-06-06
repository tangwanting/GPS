/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import "GPSLocationViewModel.h"
#import "GPSCoordinateUtils.h"
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
#define kMovingModeEnabledKey              @"MovingModeEnabled"
#define kMovingPathKey                     @"MovingPath"
#define kMovingSpeedKey                    @"MovingSpeed"
#define kRandomRadiusKey                   @"RandomRadius"
#define kStepDistanceKey                   @"StepDistance" 
#define kMovementModeKey                   @"MovementMode"

@interface GPSLocationViewModel ()

@property (nonatomic, strong) GPSLocationModel *currentLocationModel;
@property (nonatomic, strong) NSTimer *movementTimer;
@property (nonatomic, strong) NSMutableArray<GPSLocationModel *> *pathPoints;
@property (nonatomic, assign) NSUInteger currentPathIndex;
@property (nonatomic, strong) NSMutableArray<GPSLocationModel *> *locationHistoryArray;
@property (nonatomic, strong) NSDate *lastUpdateTime;
@property (nonatomic, strong) NSString *currentRouteName;

@end

@implementation GPSLocationViewModel

#pragma mark - 单例

+ (instancetype)sharedInstance {
    static GPSLocationViewModel *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

#pragma mark - 初始化

- (instancetype)init {
    if (self = [super init]) {
        [self loadSettings];
        _locationHistoryArray = [NSMutableArray array];
        _pathPoints = [NSMutableArray array];
        _currentPathIndex = 0;
        _lastUpdateTime = [NSDate date];
        
        // 加载历史记录
        [self loadLocationHistory];
    }
    return self;
}

#pragma mark - 位置管理

- (GPSLocationModel *)currentLocation {
    if (!_currentLocationModel) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        double latitude = [defaults doubleForKey:kLatitudeKey];
        double longitude = [defaults doubleForKey:kLongitudeKey];
        double altitude = [defaults doubleForKey:kAltitudeKey];
        double speed = [defaults doubleForKey:kSpeedKey];
        double course = [defaults doubleForKey:kCourseKey];
        double accuracy = [defaults doubleForKey:kAccuracyKey];
        
        if (latitude != 0 && longitude != 0) {
            _currentLocationModel = [[GPSLocationModel alloc] init];
            _currentLocationModel.latitude = latitude;
            _currentLocationModel.longitude = longitude;
            _currentLocationModel.altitude = altitude;
            _currentLocationModel.speed = speed;
            _currentLocationModel.course = course;
            _currentLocationModel.accuracy = accuracy;
            _currentLocationModel.timestamp = [NSDate date];
        }
    }
    return _currentLocationModel;
}

- (void)setCurrentLocation:(GPSLocationModel *)location {
    _currentLocationModel = location;
    
    // 保存到用户默认设置
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:location.latitude forKey:kLatitudeKey];
    [defaults setDouble:location.longitude forKey:kLongitudeKey];
    [defaults setDouble:location.altitude forKey:kAltitudeKey];
    [defaults setDouble:location.speed forKey:kSpeedKey];
    [defaults setDouble:location.course forKey:kCourseKey];
    [defaults setDouble:location.accuracy forKey:kAccuracyKey];
    [defaults synchronize];
}

- (void)saveLocation:(GPSLocationModel *)location withTitle:(NSString *)title {
    if (!location) return;
    
    GPSLocationModel *newLocation = [[GPSLocationModel alloc] init];
    newLocation.latitude = location.latitude;
    newLocation.longitude = location.longitude;
    newLocation.altitude = location.altitude;
    newLocation.speed = location.speed;
    newLocation.course = location.course;
    newLocation.accuracy = location.accuracy;
    newLocation.title = title ?: @"保存的位置";
    newLocation.timestamp = [NSDate date];
    
    [self.locationHistoryArray addObject:newLocation];
    
    // 保存更新后的历史记录
    [self saveLocationHistory];
}

- (void)clearHistory {
    [self.locationHistoryArray removeAllObjects];
    [self saveLocationHistory];
}

#pragma mark - 历史记录管理

- (NSArray<GPSLocationModel *> *)locationHistory {
    return [self.locationHistoryArray copy];
}

- (void)loadLocationHistory {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *historyArray = [defaults objectForKey:kLocationHistoryKey];
    
    if (historyArray) {
        [self.locationHistoryArray removeAllObjects];
        for (NSDictionary *dict in historyArray) {
            GPSLocationModel *model = [GPSLocationModel modelWithDictionary:dict];
            if (model) {
                [self.locationHistoryArray addObject:model];
            }
        }
    }
}

- (void)saveLocationHistory {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    NSMutableArray *historyDicts = [NSMutableArray arrayWithCapacity:self.locationHistoryArray.count];
    for (GPSLocationModel *model in self.locationHistoryArray) {
        [historyDicts addObject:[model toDictionary]];
    }
    
    [defaults setObject:historyDicts forKey:kLocationHistoryKey];
    [defaults synchronize];
}

#pragma mark - 移动控制

- (void)startMoving {
    if (self.movementTimer) {
        [self stopMoving];
    }
    
    // 根据移动速度设置更新间隔
    NSTimeInterval interval = 1.0; // 默认1秒更新一次
    if (self.movingSpeed > 0) {
        interval = MAX(0.1, MIN(5.0, 1.0 / self.movingSpeed));
    }
    
    self.movementTimer = [NSTimer scheduledTimerWithTimeInterval:interval 
                                                         target:self 
                                                       selector:@selector(updateFakeLocation) 
                                                       userInfo:nil 
                                                        repeats:YES];
}

- (void)stopMoving {
    [self.movementTimer invalidate];
    self.movementTimer = nil;
}

- (void)updateFakeLocation {
    CLLocation *nextLocation = [self nextFakeLocation];
    if (nextLocation) {
        self.currentLocationModel = [GPSLocationModel modelWithLocation:nextLocation];
    }
}

#pragma mark - 位置计算

- (CLLocation *)nextFakeLocation {
    if (!self.currentLocationModel) {
        return nil;
    }
    
    CLLocation *currentLocation = [self.currentLocationModel toCLLocation];
    CLLocation *nextLocation = nil;
    
    // 计算时间间隔
    NSTimeInterval timeDiff = [[NSDate date] timeIntervalSinceDate:self.lastUpdateTime];
    self.lastUpdateTime = [NSDate date];
    
    switch (self.movementMode) {
        case GPSMovementModeRandom: {
            // 随机范围内移动
            nextLocation = [self randomLocationAroundLocation:currentLocation withinRadius:self.randomRadius];
            break;
        }
        case GPSMovementModeLinear: {
            // 线性移动 - 按照当前航向继续移动
            double distance = self.movingSpeed * timeDiff; // 按速度和时间计算移动距离
            nextLocation = [GPSCoordinateUtils locationWithBearing:currentLocation.course 
                                                         distance:distance 
                                                  fromLocation:currentLocation];
            break;
        }
        case GPSMovementModePath: {
            // 路径移动 - 在两点之间移动
            if (self.pathPoints.count < 2 || self.currentPathIndex >= self.pathPoints.count - 1) {
                self.currentPathIndex = 0; // 循环路径
            }
            
            GPSLocationModel *start = self.pathPoints[self.currentPathIndex];
            GPSLocationModel *end = self.pathPoints[self.currentPathIndex + 1];
            
            // 创建位置对象
            CLLocation *startLoc = [start toCLLocation];
            CLLocation *endLoc = [end toCLLocation];
            
            // 计算总距离
            CLLocationDistance totalDistance = [startLoc distanceFromLocation:endLoc];
            double moveDistance = self.movingSpeed * timeDiff;
            
            // 检查是否需要移动到下一段
            if (moveDistance >= totalDistance) {
                self.currentPathIndex++;
                nextLocation = endLoc;
            } else {
                // 在当前段内移动
                double ratio = moveDistance / totalDistance;
                double newLat = start.latitude + ratio * (end.latitude - start.latitude);
                double newLon = start.longitude + ratio * (end.longitude - start.longitude);
                double newAlt = start.altitude + ratio * (end.altitude - start.altitude);
                
                CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(newLat, newLon);
                nextLocation = [[CLLocation alloc] initWithCoordinate:coord
                                                            altitude:newAlt
                                                  horizontalAccuracy:5.0
                                                    verticalAccuracy:5.0
                                                           timestamp:[NSDate date]];
            }
            break;
        }
        case GPSMovementModeRoute: {
            // 路线移动 - 基于GPX路线
            if (self.pathPoints.count == 0) {
                // 如果没有加载路线，尝试加载
                if (self.currentRouteName) {
                    NSError *error;
                    NSArray *routePoints = [[GPSRouteManager sharedInstance] loadRouteWithName:self.currentRouteName error:&error];
                    if (routePoints && !error) {
                        self.pathPoints = [routePoints mutableCopy];
                    }
                }
                
                if (self.pathPoints.count == 0) {
                    return nil;
                }
            }
            
            // 使用与Path模式相同的逻辑
            if (self.pathPoints.count < 2 || self.currentPathIndex >= self.pathPoints.count - 1) {
                self.currentPathIndex = 0;
            }
            
            GPSLocationModel *start = self.pathPoints[self.currentPathIndex];
            GPSLocationModel *end = self.pathPoints[self.currentPathIndex + 1];
            
            CLLocation *startLoc = [start toCLLocation];
            CLLocation *endLoc = [end toCLLocation];
            
            CLLocationDistance totalDistance = [startLoc distanceFromLocation:endLoc];
            double moveDistance = self.movingSpeed * timeDiff;
            
            if (moveDistance >= totalDistance) {
                self.currentPathIndex++;
                nextLocation = endLoc;
            } else {
                double ratio = moveDistance / totalDistance;
                double newLat = start.latitude + ratio * (end.latitude - start.latitude);
                double newLon = start.longitude + ratio * (end.longitude - start.longitude);
                double newAlt = start.altitude + ratio * (end.altitude - start.altitude);
                
                CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(newLat, newLon);
                nextLocation = [[CLLocation alloc] initWithCoordinate:coord
                                                            altitude:newAlt
                                                  horizontalAccuracy:5.0
                                                    verticalAccuracy:5.0
                                                           timestamp:[NSDate date]];
            }
            break;
        }
        default:
            // 不移动
            nextLocation = currentLocation;
            break;
    }
    
    return nextLocation;
}

- (CLLocation *)randomLocationAroundLocation:(CLLocation *)location withinRadius:(double)radius {
    // 生成随机角度和随机距离
    double angle = (double)arc4random() / UINT32_MAX * 360.0;
    double distance = (double)arc4random() / UINT32_MAX * radius;
    
    return [GPSCoordinateUtils locationWithBearing:angle distance:distance fromLocation:location];
}

#pragma mark - 路线管理

- (void)loadRouteWithName:(NSString *)routeName {
    self.currentRouteName = routeName;
    NSError *error;
    NSArray *routePoints = [[GPSRouteManager sharedInstance] loadRouteWithName:routeName error:&error];
    if (routePoints && !error) {
        self.pathPoints = [routePoints mutableCopy];
        self.currentPathIndex = 0;
    }
}

#pragma mark - 设置管理

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    self.isLocationSpoofingEnabled = [defaults boolForKey:kLocationSpoofingEnabledKey];
    self.isAltitudeSpoofingEnabled = [defaults boolForKey:kAltitudeSpoofingEnabledKey];
    self.movingSpeed = [defaults doubleForKey:kMovingSpeedKey] ?: 5.0; // 默认速度5米/秒
    self.randomRadius = [defaults doubleForKey:kRandomRadiusKey] ?: 50.0; // 默认随机半径50米
    self.stepDistance = [defaults doubleForKey:kStepDistanceKey] ?: 10.0; // 默认步进10米
    self.movementMode = [defaults integerForKey:kMovementModeKey] ?: GPSMovementModeNone;
    
    // 尝试加载保存的路径
    NSArray *pathArray = [defaults objectForKey:kMovingPathKey];
    if (pathArray.count > 0) {
        [self.pathPoints removeAllObjects];
        for (NSDictionary *pointDict in pathArray) {
            GPSLocationModel *point = [GPSLocationModel modelWithDictionary:pointDict];
            if (point) {
                [self.pathPoints addObject:point];
            }
        }
    }
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    [defaults setBool:self.isLocationSpoofingEnabled forKey:kLocationSpoofingEnabledKey];
    [defaults setBool:self.isAltitudeSpoofingEnabled forKey:kAltitudeSpoofingEnabledKey];
    [defaults setDouble:self.movingSpeed forKey:kMovingSpeedKey];
    [defaults setDouble:self.randomRadius forKey:kRandomRadiusKey];
    [defaults setDouble:self.stepDistance forKey:kStepDistanceKey];
    [defaults setInteger:self.movementMode forKey:kMovementModeKey];
    
    // 保存路径
    if (self.pathPoints.count > 0) {
        NSMutableArray *pathArray = [NSMutableArray arrayWithCapacity:self.pathPoints.count];
        for (GPSLocationModel *point in self.pathPoints) {
            [pathArray addObject:[point toDictionary]];
        }
        [defaults setObject:pathArray forKey:kMovingPathKey];
    }
    
    [defaults synchronize];
}

@end