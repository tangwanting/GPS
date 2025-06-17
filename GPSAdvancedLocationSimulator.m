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

@property (nonatomic, strong) GPSLocationModel *initialLocation;
@property (nonatomic, strong) CLLocation *lastSimulatedLocation;
@property (nonatomic, copy) void (^completionHandler)(GPSLocationModel *);
@property (nonatomic, assign) GPSSimulatorMode simulationMode;

@end

@implementation GPSAdvancedLocationSimulator

#pragma mark - 初始化方法

+ (instancetype)sharedInstance {
    static GPSAdvancedLocationSimulator *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _simulationMode = GPSSimulatorModeSingle;
    }
    return self;
}

- (void)startSimulationWithInitialLocation:(GPSLocationModel *)initialLocation 
                               updateInterval:(NSTimeInterval)interval 
                            completionHandler:(void (^)(GPSLocationModel *))completionBlock {
    // 停止现有模拟
    [self stopSimulation];
    
    // 存储初始数据
    self.initialLocation = initialLocation;
    self.lastSimulatedLocation = [self convertModelToLocation:initialLocation];
    self.completionHandler = completionBlock;
    self.simulationMode = GPSSimulatorModeSingle;
    
    // 创建更新定时器
    self.simulationTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    
    uint64_t intervalNanoseconds = (uint64_t)(interval * NSEC_PER_SEC);
    dispatch_source_set_timer(self.simulationTimer, 
                             dispatch_time(DISPATCH_TIME_NOW, 0), 
                             intervalNanoseconds, 
                             intervalNanoseconds / 10);
    
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(self.simulationTimer, ^{
        [weakSelf updateSimulatedLocation];
    });
    
    // 启动定时器
    if (self.simulationTimer) {
        dispatch_resume(self.simulationTimer);
        
        // 初始状态通知
        NSLog(@"GPS位置模拟开始 - 初始位置: %f, %f", 
             initialLocation.coordinate.latitude, 
             initialLocation.coordinate.longitude);
        
        // 立即回调一次初始位置
        if (self.completionHandler) {
            self.completionHandler(initialLocation);
        }
    }
}

// 更新模拟位置
- (void)updateSimulatedLocation {
    GPSLocationModel *updatedLocation = [self generateNextLocation];
    
    if (updatedLocation && self.completionHandler) {
        self.lastSimulatedLocation = [self convertModelToLocation:updatedLocation];
        self.completionHandler(updatedLocation);
    }
}

// 生成下一个位置
- (GPSLocationModel *)generateNextLocation {
    if (!self.initialLocation) return nil;
    
    GPSLocationModel *nextLocation = [[GPSLocationModel alloc] init];
    nextLocation.coordinate = self.initialLocation.coordinate;
    nextLocation.altitude = self.initialLocation.altitude;
    nextLocation.speed = self.initialLocation.speed;
    nextLocation.course = self.initialLocation.course;
    nextLocation.accuracy = self.initialLocation.accuracy;
    
    // 在单点模式下添加微小噪声以模拟真实GPS
    nextLocation.coordinate = CLLocationCoordinate2DMake(
        nextLocation.coordinate.latitude + ((double)arc4random() / UINT32_MAX - 0.5) * 0.00002,
        nextLocation.coordinate.longitude + ((double)arc4random() / UINT32_MAX - 0.5) * 0.00002
    );
    
    return nextLocation;
}

// 将GPSLocationModel转换为CLLocation
- (CLLocation *)convertModelToLocation:(GPSLocationModel *)model {
    if (!model) return nil;
    
    return [[CLLocation alloc] initWithCoordinate:model.coordinate
                                         altitude:model.altitude
                               horizontalAccuracy:model.accuracy
                                 verticalAccuracy:model.accuracy
                                           course:model.course
                                            speed:model.speed
                                        timestamp:[NSDate date]];
}

// 停止模拟
- (void)stopSimulation {
    if (self.simulationTimer) {
        dispatch_source_cancel(self.simulationTimer);
        self.simulationTimer = nil;
    }
    NSLog(@"GPS位置模拟已停止");
}

@end