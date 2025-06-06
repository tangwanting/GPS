/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSAdvancedLocationSimulator.h"
#import <CoreLocation/CoreLocation.h>
#import "GPSLocationModel.h"
#import "GPSCoordinateUtils.h"
#import <CoreMotion/CoreMotion.h>

@interface GPSAdvancedLocationSimulator ()

@property (nonatomic, strong) NSTimer *simulationTimer;
@property (nonatomic, strong) GPSLocationModel *currentLocation;
@property (nonatomic, strong) NSMutableArray<GPSLocationModel *> *simulatedPath;
@property (nonatomic, assign) NSTimeInterval simulationInterval;
@property (nonatomic, assign) double currentSpeed;
@property (nonatomic, assign) double currentAccuracy;
@property (nonatomic, assign) double baseNoise;
@property (nonatomic, strong) NSMutableDictionary *environmentFactors;
@property (nonatomic, assign) BOOL simulateDeviceMotion;
@property (nonatomic, copy) void (^locationUpdateHandler)(GPSLocationModel *location);
@property (nonatomic, assign) NSInteger pathIndex;

@end

@implementation GPSAdvancedLocationSimulator

#pragma mark - 初始化方法

+ (instancetype)sharedInstance {
    static GPSAdvancedLocationSimulator *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _simulatedPath = [NSMutableArray array];
        _accuracyLevel = GPSAccuracyLevelMedium;
        _environmentType = GPSEnvironmentTypeSuburban;
        _simulationInterval = 1.0; // 默认1秒更新一次
        _currentSpeed = 1.0; // 默认1米/秒
        _baseNoise = 0.0;
        _simulateDeviceMotion = NO;
        [self setupEnvironmentFactors];
    }
    return self;
}

- (void)setupEnvironmentFactors {
    // 为不同环境设置参数
    _environmentFactors = [NSMutableDictionary dictionary];
    
    // 城市
    _environmentFactors[@(GPSEnvironmentTypeUrban)] = @{
        @"accuracyMultiplier": @(1.5),      // 城市中信号较差
        @"noiseLevel": @(3.0),              // 高噪声水平
        @"signalBlockageFrequency": @(0.15), // 信号阻断频率
        @"signalReflectionFactor": @(2.0)   // 信号反射影响
    };
    
    // 郊区
    _environmentFactors[@(GPSEnvironmentTypeSuburban)] = @{
        @"accuracyMultiplier": @(1.0),      // 标准准确度
        @"noiseLevel": @(1.5),              // 中等噪声
        @"signalBlockageFrequency": @(0.05), // 较少信号阻断
        @"signalReflectionFactor": @(1.0)   // 标准反射影响
    };
    
    // 乡村
    _environmentFactors[@(GPSEnvironmentTypeRural)] = @{
        @"accuracyMultiplier": @(0.7),      // 更好的准确度
        @"noiseLevel": @(0.8),              // 低噪声
        @"signalBlockageFrequency": @(0.02), // 极少信号阻断
        @"signalReflectionFactor": @(0.5)   // 较小反射影响
    };
    
    // 隧道
    _environmentFactors[@(GPSEnvironmentTypeCanyon)] = @{
        @"accuracyMultiplier": @(3.0),      // 准确度很差
        @"noiseLevel": @(5.0),              // 高噪声
        @"signalBlockageFrequency": @(0.4),  // 频繁信号阻断
        @"signalReflectionFactor": @(3.0)   // 强信号反射
    };
    
    // 室内
    _environmentFactors[@(GPSEnvironmentTypeIndoor)] = @{
        @"accuracyMultiplier": @(2.5),      // 准确度差
        @"noiseLevel": @(4.0),              // 高噪声
        @"signalBlockageFrequency": @(0.3),  // 频繁信号阻断
        @"signalReflectionFactor": @(2.5)   // 强信号反射
    };
}

#pragma mark - 公共方法

- (void)startSimulationWithInitialLocation:(GPSLocationModel *)location 
                         updateInterval:(NSTimeInterval)interval 
                         completionHandler:(void (^)(GPSLocationModel *location))handler {
    self.currentLocation = location;
    self.simulationInterval = interval;
    self.locationUpdateHandler = handler;
    
    // 停止之前可能存在的模拟
    [self stopSimulation];
    
    // 初始化并调用更新
    [self updateCurrentAccuracy];
    [self fireInitialUpdate];
    
    // 开始定时更新
    self.simulationTimer = [NSTimer scheduledTimerWithTimeInterval:self.simulationInterval 
                                                           target:self 
                                                         selector:@selector(simulationTimerFired) 
                                                         userInfo:nil 
                                                          repeats:YES];
}

- (void)stopSimulation {
    [self.simulationTimer invalidate];
    self.simulationTimer = nil;
    self.locationUpdateHandler = nil;
}

- (void)setPath:(NSArray<GPSLocationModel *> *)path {
    if (path && path.count > 0) {
        [self.simulatedPath removeAllObjects];
        [self.simulatedPath addObjectsFromArray:path];
        // 如果正在模拟，使用新路径的第一个点重设当前位置
        if (self.simulationTimer) {
            self.currentLocation = [path firstObject];
            [self fireInitialUpdate];
        }
    }
}

- (void)setAccuracyLevel:(GPSAccuracyLevel)level {
    _accuracyLevel = level;
    [self updateCurrentAccuracy];
    
    // 如果当前在模拟中，立即应用新设置
    if (self.simulationTimer) {
        [self fireInitialUpdate];
    }
}

- (void)setEnvironmentType:(GPSEnvironmentType)type {
    _environmentType = type;
    [self updateCurrentAccuracy];
    
    // 如果当前在模拟中，立即应用新设置
    if (self.simulationTimer) {
        [self fireInitialUpdate];
    }
}

- (void)setSimulateDeviceMotion:(BOOL)simulate {
    _simulateDeviceMotion = simulate;
}

- (void)adjustSpeed:(double)speedMetersPerSecond {
    self.currentSpeed = speedMetersPerSecond;
}

#pragma mark - 私有方法

- (void)simulationTimerFired {
    // 如果有设定的路径，沿着路径移动
    if (self.simulatedPath.count > 1) {
        [self moveAlongPath];
    } else {
        // 否则，进行简单的随机漂移
        [self applyRandomDrift];
    }
    
    // 应用环境噪声
    [self applyEnvironmentalNoise];
    
    // 回调更新的位置
    if (self.locationUpdateHandler) {
        self.locationUpdateHandler(self.currentLocation);
    }
}

- (void)fireInitialUpdate {
    // 发送初始位置更新
    if (self.locationUpdateHandler) {
        self.locationUpdateHandler(self.currentLocation);
    }
}

- (void)moveAlongPath {
    // 确保索引在有效范围内
    if (self.pathIndex >= self.simulatedPath.count - 1) {
        self.pathIndex = 0; // 循环路径
    }
    
    // 获取当前和下一个路径点
    GPSLocationModel *currentPathPoint = self.simulatedPath[self.pathIndex];
    GPSLocationModel *nextPathPoint = self.simulatedPath[self.pathIndex + 1];
    
    // 计算两点间距离
    CLLocation *currentLoc = [currentPathPoint toCLLocation];
    CLLocation *nextLoc = [nextPathPoint toCLLocation];
    CLLocationDistance distance = [currentLoc distanceFromLocation:nextLoc];
    
    // 计算本次更新应该移动的距离
    double moveDistance = self.currentSpeed * self.simulationInterval;
    
    // 如果这一步可以到达下一个点
    if (moveDistance >= distance) {
        self.currentLocation = nextPathPoint;
        self.pathIndex++;
    } else {
        // 进行路径插值
        double ratio = moveDistance / distance;
        GPSLocationModel *interpolatedLocation = [self interpolateFromLocation:currentPathPoint
                                                                   toLocation:nextPathPoint
                                                                       ratio:ratio];
        self.currentLocation = interpolatedLocation;
    }
}

- (GPSLocationModel *)interpolateFromLocation:(GPSLocationModel *)start
                                   toLocation:(GPSLocationModel *)end
                                       ratio:(double)ratio {
    GPSLocationModel *result = [[GPSLocationModel alloc] init];
    
    // 线性插值经纬度
    result.latitude = start.latitude + (end.latitude - start.latitude) * ratio;
    result.longitude = start.longitude + (end.longitude - start.longitude) * ratio;
    
    // 插值高度
    result.altitude = start.altitude + (end.altitude - start.altitude) * ratio;
    
    // 保持方向一致
    result.course = [GPSCoordinateUtils calculateBearingFrom:CLLocationCoordinate2DMake(start.latitude, start.longitude)
                                                         to:CLLocationCoordinate2DMake(end.latitude, end.longitude)];
    
    // 速度可能会有轻微变化
    result.speed = self.currentSpeed * (0.95 + 0.1 * ((double)arc4random() / UINT32_MAX));
    
    // 时间戳
    result.timestamp = [NSDate date];
    
    // 精度
    result.accuracy = self.currentAccuracy;
    
    return result;
}

- (void)applyRandomDrift {
    // 随机漂移，模拟站立时GPS的自然漂移
    double driftRadius = self.currentAccuracy * 0.2; // 漂移半径与精确度相关
    double angle = [self randomDoubleValue] * M_PI * 2; // 随机角度
    
    // 计算漂移量
    double latChange = sin(angle) * driftRadius / 111000.0; // 约111km每纬度
    double lonChange = cos(angle) * driftRadius / (111000.0 * cos(self.currentLocation.latitude * M_PI / 180.0));
    
    // 应用漂移
    self.currentLocation.latitude += latChange;
    self.currentLocation.longitude += lonChange;
    
    // 更新时间戳
    self.currentLocation.timestamp = [NSDate date];
}

- (void)applyEnvironmentalNoise {
    // 获取当前环境设定
    NSDictionary *envFactors = self.environmentFactors[@(self.environmentType)];
    double noiseLevel = [envFactors[@"noiseLevel"] doubleValue];
    
    // 计算信号阻断概率
    double blockageProb = [envFactors[@"signalBlockageFrequency"] doubleValue];
    BOOL signalBlocked = [self randomDoubleValue] < blockageProb;
    
    if (signalBlocked) {
        // 模拟信号阻断 - 大幅增加精度值
        self.currentLocation.accuracy *= 3.0;
    } else {
        // 应用正常环境噪声
        double noiseFactor = [self randomDoubleValue] * noiseLevel;
        
        // 应用于位置
        self.currentLocation.latitude += (((double)arc4random() / UINT32_MAX) - 0.5) * noiseFactor / 50000.0;
        self.currentLocation.longitude += (((double)arc4random() / UINT32_MAX) - 0.5) * noiseFactor / 50000.0;
        
        // 应用于速度
        if (self.currentLocation.speed > 0) {
            double speedNoise = (((double)arc4random() / UINT32_MAX) - 0.5) * noiseFactor * 0.2;
            self.currentLocation.speed = fmax(0, self.currentLocation.speed + speedNoise);
        }
        
        // 应用于方向
        if (self.currentLocation.course >= 0) {
            double courseNoise = (((double)arc4random() / UINT32_MAX) - 0.5) * noiseFactor * 5.0;
            self.currentLocation.course = fmod(self.currentLocation.course + courseNoise + 360.0, 360.0);
        }
    }
}

- (void)updateCurrentAccuracy {
    // 基于精度级别设定基础精确度值
    switch (_accuracyLevel) {
        case GPSAccuracyLevelUltra:
            self.currentAccuracy = 1.0; // 极高精度
            break;
        case GPSAccuracyLevelHigh:
            self.currentAccuracy = 3.0; // 高精度
            break;
        case GPSAccuracyLevelMedium:
            self.currentAccuracy = 5.0; // 中等精度
            break;
        case GPSAccuracyLevelLow:
            self.currentAccuracy = 10.0; // 低精度
            break;
        case GPSAccuracyLevelVariable:
            // 变化性精度根据环境和随机因素计算
            self.currentAccuracy = 3.0 + [self randomDoubleValue] * 7.0;
            break;
    }
    
    // 应用环境因素调整精度
    NSDictionary *envFactors = self.environmentFactors[@(self.environmentType)];
    double accuracyMultiplier = [envFactors[@"accuracyMultiplier"] doubleValue];
    self.currentAccuracy *= accuracyMultiplier;
}

- (double)randomDoubleValue {
    return ((double)arc4random() / UINT32_MAX);
}

- (void)dealloc {
    [self stopSimulation];
}

- (void)updateSimulationWithNewSettings {
    [self updateCurrentAccuracy];
    if (self.simulationTimer) {
        [self fireInitialUpdate];
    }
}

@end