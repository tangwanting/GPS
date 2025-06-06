#import "GPSManager.h"
#import "GPSControlPanelViewController.h"
#import <AudioToolbox/AudioToolbox.h>
#import <objc/runtime.h>

@interface GPSManager () <CLLocationManagerDelegate>
@property (nonatomic, strong) NSTimer *locationUpdateTimer;
@end

@implementation GPSManager

+ (instancetype)sharedManager {
    static GPSManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _isSimulating = NO;
        
        [[NSNotificationCenter defaultCenter] addObserver:self 
                                                 selector:@selector(applicationDidBecomeActive:) 
                                                     name:UIApplicationDidBecomeActiveNotification 
                                                   object:nil];
    }
    return self;
}

- (void)setup {
    // 请求位置权限
    if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    }
    
    // 初始化触发器
    [self setupGPSTrigger];
    
    NSLog(@"[GPS] 系统初始化完成，正在安全模式下运行");
}

- (void)setupGPSTrigger {
    Class triggerClass = NSClassFromString(@"GPSTrigger");
    if (triggerClass) {
        if ([triggerClass respondsToSelector:@selector(sharedInstance)]) {
            id trigger = [triggerClass performSelector:@selector(sharedInstance)];
            NSLog(@"[GPS] 触发器已初始化: %@", trigger);
        }
    }
    
    NSLog(@"[GPS] 已委托手势管理给 GPSTrigger");
}

- (void)showGPSControlPanel {
    if (!self.overlayWindow) {
        self.overlayWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        self.overlayWindow.windowLevel = UIWindowLevelStatusBar - 1;
        self.overlayWindow.hidden = NO;
        self.overlayWindow.alpha = 1.0;
        self.overlayWindow.backgroundColor = [UIColor clearColor];
        
        // 懒加载控制面板
        if (!self.controlPanel) {
            self.controlPanel = [[GPSControlPanelViewController alloc] init];
        }
        
        self.overlayWindow.rootViewController = self.controlPanel;
    }
    
    self.overlayWindow.hidden = NO;
    
    // 触觉反馈通知用户
    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [generator prepare];
        [generator impactOccurred];
    }
    
    NSLog(@"[GPS] 控制面板已显示");
}

- (void)hideGPSControlPanel {
    self.overlayWindow.hidden = YES;
}

- (BOOL)isVisible {
    return self.overlayWindow && !self.overlayWindow.hidden;
}

- (void)simulateLocation:(CLLocationCoordinate2D)coordinate {
    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        NSLog(@"[GPS] 无效的坐标");
        return;
    }
    
    self.isSimulating = YES;
    
    // 创建模拟位置
    self.simulatedLocation = [[CLLocation alloc] 
                             initWithCoordinate:coordinate
                             altitude:100.0
                             horizontalAccuracy:10.0
                             verticalAccuracy:10.0
                             course:0.0
                             speed:0.0
                             timestamp:[NSDate date]];
    
    // 开始定期更新
    [self startLocationUpdateTimer];
    
    NSLog(@"[GPS] 开始模拟位置: %.6f, %.6f", coordinate.latitude, coordinate.longitude);
}

- (void)startLocationUpdateTimer {
    // 清除旧定时器
    [self.locationUpdateTimer invalidate];
    
    // 创建新定时器，每秒更新一次位置
    self.locationUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                               target:self
                                                             selector:@selector(updateLocation)
                                                             userInfo:nil
                                                              repeats:YES];
}

- (void)updateLocation {
    if (!self.isSimulating || !self.simulatedLocation) return;
    
    // 当前时间的新位置
    CLLocation *updatedLocation = [[CLLocation alloc]
                                  initWithCoordinate:self.simulatedLocation.coordinate
                                  altitude:self.simulatedLocation.altitude
                                  horizontalAccuracy:self.simulatedLocation.horizontalAccuracy
                                  verticalAccuracy:self.simulatedLocation.verticalAccuracy
                                  course:self.simulatedLocation.course
                                  speed:self.simulatedLocation.speed
                                  timestamp:[NSDate date]];
    
    // 更新位置
    if ([self.locationManager.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [self.locationManager.delegate locationManager:self.locationManager 
                                     didUpdateLocations:@[updatedLocation]];
    }
}

- (void)stopSimulation {
    self.isSimulating = NO;
    self.simulatedLocation = nil;
    
    // 停止定时器
    [self.locationUpdateTimer invalidate];
    self.locationUpdateTimer = nil;
    
    NSLog(@"[GPS] 停止位置模拟");
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    // 应用回到前台时更新手势注册
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    if (!window) return;
    
    UIGestureRecognizer *gesture = objc_getAssociatedObject(self, "fourFingerTapGesture");
    if (gesture && ![window.gestureRecognizers containsObject:gesture]) {
        [window addGestureRecognizer:gesture];
    }
    
    // 如果正在模拟，重新启动定时器
    if (self.isSimulating && !self.locationUpdateTimer.isValid) {
        [self startLocationUpdateTimer];
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.locationUpdateTimer invalidate];
}

@end