/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSModuleManager.h"
#import <UIKit/UIKit.h>

@interface GPSModuleManager ()

// 存储不同类型模块的字典
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, id<GPSModuleProtocol>> *modules;
// 跟踪模块启动状态
@property (nonatomic, strong) NSMutableSet *runningModules;
// 系统状态
@property (nonatomic, assign) BOOL isInBackground;
// 统计日志
@property (nonatomic, strong) NSMutableDictionary *modulePerformanceStats;

@end

@implementation GPSModuleManager

#pragma mark - 单例实现

+ (instancetype)sharedInstance {
    static GPSModuleManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _modules = [NSMutableDictionary dictionary];
        _runningModules = [NSMutableSet set];
        _modulePerformanceStats = [NSMutableDictionary dictionary];
        _debugMode = NO;
        _powerSavingMode = NO;
        _isInBackground = NO;
        
        [self setupNotifications];
        [self loadSettings];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // 确保所有模块在销毁前停止
    [self stopAllModules];
}

#pragma mark - 设置管理

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // 从用户默认设置加载配置
    self.debugMode = [defaults boolForKey:@"GPSModuleManagerDebugMode"];
    self.powerSavingMode = [defaults boolForKey:@"GPSModuleManagerPowerSavingMode"];
    
    if (self.debugMode) {
        NSLog(@"GPS模块管理器: 从设置加载配置 (调试模式: %@, 省电模式: %@)", 
              self.debugMode ? @"开启" : @"关闭", 
              self.powerSavingMode ? @"开启" : @"关闭");
    }
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // 保存当前配置到用户默认设置
    [defaults setBool:self.debugMode forKey:@"GPSModuleManagerDebugMode"];
    [defaults setBool:self.powerSavingMode forKey:@"GPSModuleManagerPowerSavingMode"];
    [defaults synchronize];
    
    if (self.debugMode) {
        NSLog(@"GPS模块管理器: 保存配置到设置");
    }
}

#pragma mark - 通知设置

- (void)setupNotifications {
    // 注册应用状态变化的通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidEnterBackground:)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillEnterForeground:)
                                                 name:UIApplicationWillEnterForegroundNotification
                                               object:nil];
    
    // 注册低电量模式变化通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(powerModeChanged:)
                                                 name:NSProcessInfoPowerStateDidChangeNotification
                                               object:nil];
    
    // 注册内存警告通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didReceiveMemoryWarning:)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
    
    // 注册GPS优化设置变化通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(optimizationSettingsChanged:)
                                                 name:@"GPSOptimizationSettingsChanged"
                                               object:nil];
}

#pragma mark - 应用状态管理

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    NSLog(@"GPS模块管理器: 应用进入后台，正在调整模块运行状态");
    
    self.isInBackground = YES;
    
    if (self.powerSavingMode) {
        // 在后台且节电模式，停止部分非必要模块
        [self pauseNonEssentialModules];
    } else {
        // 非节电模式下也要降低后台活动
        [self reduceBackgroundActivity];
    }
    
    // 通知所有模块应用进入后台
    [self notifyModulesOfStateChange:@"applicationDidEnterBackground"];
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    NSLog(@"GPS模块管理器: 应用进入前台，恢复模块运行状态");
    
    self.isInBackground = NO;
    
    // 应用返回前台，恢复被暂停的模块
    [self resumePausedModules];
    
    // 通知所有模块应用进入前台
    [self notifyModulesOfStateChange:@"applicationWillEnterForeground"];
}

- (void)powerModeChanged:(NSNotification *)notification {
    BOOL lowPowerMode = [NSProcessInfo processInfo].lowPowerModeEnabled;
    NSLog(@"GPS模块管理器: 系统电量模式变化，低电量模式: %@", lowPowerMode ? @"开启" : @"关闭");
    
    // 自动开启省电模式
    if (lowPowerMode) {
        self.powerSavingMode = YES;
        [self applyPowerSavingSettings];
    } else if (self.powerSavingMode) {
        // 仅在之前是由系统低电量触发省电模式时才自动关闭省电模式
        // 用户手动开启的省电模式不自动关闭
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        BOOL wasAutomaticallyEnabled = [defaults boolForKey:@"GPSModuleManagerAutoEnabledPowerSaving"];
        
        if (wasAutomaticallyEnabled) {
            self.powerSavingMode = NO;
            [self removePowerSavingSettings];
            [defaults setBool:NO forKey:@"GPSModuleManagerAutoEnabledPowerSaving"];
            [defaults synchronize];
        }
    }
}

- (void)didReceiveMemoryWarning:(NSNotification *)notification {
    NSLog(@"GPS模块管理器: 收到内存警告，正在释放资源");
    
    // 通知所有模块进行内存优化
    [self notifyModulesOfStateChange:@"memoryWarning"];
    
    // 额外内存释放措施
    [self freeMemoryResources];
}

- (void)optimizationSettingsChanged:(NSNotification *)notification {
    NSLog(@"GPS模块管理器: 系统优化设置已更改，应用新设置");
    
    // 读取最新设置
    [self loadSettings];
    
    // 应用更新后的设置
    if (self.powerSavingMode) {
        [self applyPowerSavingSettings];
    } else {
        [self removePowerSavingSettings];
    }
}

#pragma mark - 模块管理

- (void)registerModule:(id<GPSModuleProtocol>)module forType:(GPSModuleType)type {
    if (!module) {
        NSLog(@"GPS模块管理器: 错误: 尝试注册空模块");
        return;
    }
    
    @synchronized (self.modules) {
        NSNumber *typeKey = @(type);
        
        // 如果已有同类型模块，先停止旧的
        id<GPSModuleProtocol> existingModule = self.modules[typeKey];
        if (existingModule) {
            [existingModule stop];
            [self.runningModules removeObject:typeKey];
            NSLog(@"GPS模块管理器: 替换已有模块: %@", NSStringFromClass([existingModule class]));
        }
        
        // 注册新模块
        self.modules[typeKey] = module;
        
        // 初始化性能统计
        self.modulePerformanceStats[typeKey] = @{
            @"startCount": @0,
            @"stopCount": @0,
            @"totalRunTime": @0,
            @"lastStartTime": [NSDate date]
        };
        
        // 初始化新模块
        [module initialize];
        NSLog(@"GPS模块管理器: 成功注册模块: %@", NSStringFromClass([module class]));
    }
}

- (id<GPSModuleProtocol>)moduleForType:(GPSModuleType)type {
    @synchronized (self.modules) {
        return self.modules[@(type)];
    }
}

- (void)startAllModules {
    NSLog(@"GPS模块管理器: 启动所有模块...");
    
    @synchronized (self.modules) {
        for (NSNumber *typeKey in self.modules) {
            [self startModuleOfType:[typeKey integerValue]];
        }
    }
    
    NSLog(@"GPS模块管理器: 所有模块已启动");
}

- (void)stopAllModules {
    NSLog(@"GPS模块管理器: 停止所有模块...");
    
    @synchronized (self.modules) {
        for (NSNumber *typeKey in self.modules) {
            [self stopModuleOfType:[typeKey integerValue]];
        }
    }
    
    NSLog(@"GPS模块管理器: 所有模块已停止");
}

- (void)startModuleOfType:(GPSModuleType)type {
    @synchronized (self.modules) {
        NSNumber *typeKey = @(type);
        id<GPSModuleProtocol> module = self.modules[typeKey];
        
        if (!module) {
            NSLog(@"GPS模块管理器: 警告: 尝试启动未注册的模块类型: %@", [self stringForModuleType:type]);
            return;
        }
        
        if ([self.runningModules containsObject:typeKey]) {
            if (self.debugMode) {
                NSLog(@"GPS模块管理器: 模块已经在运行中: %@", [self stringForModuleType:type]);
            }
            return;
        }
        
        // 记录启动时间用于性能统计
        NSMutableDictionary *stats = [self.modulePerformanceStats[typeKey] mutableCopy];
        stats[@"lastStartTime"] = [NSDate date];
        stats[@"startCount"] = @([stats[@"startCount"] integerValue] + 1);
        self.modulePerformanceStats[typeKey] = stats;
        
        // 启动模块
        [module start];
        [self.runningModules addObject:typeKey];
        
        if (self.debugMode) {
            NSLog(@"GPS模块管理器: 模块已启动: %@ (类型: %@)", 
                  NSStringFromClass([module class]), 
                  [self stringForModuleType:type]);
        }
    }
}

- (void)stopModuleOfType:(GPSModuleType)type {
    @synchronized (self.modules) {
        NSNumber *typeKey = @(type);
        id<GPSModuleProtocol> module = self.modules[typeKey];
        
        if (!module) {
            NSLog(@"GPS模块管理器: 警告: 尝试停止未注册的模块类型: %@", [self stringForModuleType:type]);
            return;
        }
        
        if (![self.runningModules containsObject:typeKey]) {
            if (self.debugMode) {
                NSLog(@"GPS模块管理器: 模块已经停止: %@", [self stringForModuleType:type]);
            }
            return;
        }
        
        // 更新性能统计
        NSDate *lastStartTime = self.modulePerformanceStats[typeKey][@"lastStartTime"];
        NSTimeInterval runTime = [[NSDate date] timeIntervalSinceDate:lastStartTime];
        
        NSMutableDictionary *stats = [self.modulePerformanceStats[typeKey] mutableCopy];
        stats[@"stopCount"] = @([stats[@"stopCount"] integerValue] + 1);
        stats[@"totalRunTime"] = @([stats[@"totalRunTime"] doubleValue] + runTime);
        self.modulePerformanceStats[typeKey] = stats;
        
        // 停止模块
        [module stop];
        [self.runningModules removeObject:typeKey];
        
        if (self.debugMode) {
            NSLog(@"GPS模块管理器: 模块已停止: %@ (类型: %@, 运行时间: %.2f秒)", 
                  NSStringFromClass([module class]), 
                  [self stringForModuleType:type], 
                  runTime);
        }
    }
}

#pragma mark - 配置管理

- (void)setDebugMode:(BOOL)debugMode {
    if (_debugMode != debugMode) {
        _debugMode = debugMode;
        NSLog(@"GPS模块管理器: 调试模式已%@", debugMode ? @"开启" : @"关闭");
        [self saveSettings];
        
        // 如果开启调试模式，打印当前模块状态
        if (debugMode) {
            [self logAllModulesStatus];
        }
    }
}

- (void)setPowerSavingMode:(BOOL)powerSavingMode {
    if (_powerSavingMode != powerSavingMode) {
        _powerSavingMode = powerSavingMode;
        NSLog(@"GPS模块管理器: 省电模式已%@", powerSavingMode ? @"开启" : @"关闭");
        [self saveSettings];
        
        if (powerSavingMode) {
            // 记录是否为系统低电量模式自动触发
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setBool:[NSProcessInfo processInfo].lowPowerModeEnabled 
                       forKey:@"GPSModuleManagerAutoEnabledPowerSaving"];
            [defaults synchronize];
            
            [self applyPowerSavingSettings];
        } else {
            [self removePowerSavingSettings];
        }
    }
}

#pragma mark - 辅助方法

- (NSString *)stringForModuleType:(GPSModuleType)type {
    switch (type) {
        case GPSModuleTypeCore:
            return @"核心位置模拟";
        case GPSModuleTypeRouting:
            return @"路径管理";
        case GPSModuleTypeNavigation:
            return @"导航功能";
        case GPSModuleTypeAutomation:
            return @"自动化功能";
        case GPSModuleTypeGeofencing:
            return @"地理围栏";
        case GPSModuleTypeAnalytics:
            return @"数据分析";
        default:
            return @"未知模块";
    }
}

- (void)logAllModulesStatus {
    NSLog(@"======= GPS模块管理器: 当前所有模块状态 =======");
    
    @synchronized (self.modules) {
        for (NSNumber *typeKey in self.modules) {
            GPSModuleType type = [typeKey integerValue];
            id<GPSModuleProtocol> module = self.modules[typeKey];
            NSDictionary *status = [module currentStatus];
            BOOL isRunning = [self.runningModules containsObject:typeKey];
            
            NSLog(@"%@模块: %@ [%@]", 
                  [self stringForModuleType:type], 
                  status, 
                  isRunning ? @"运行中" : @"已停止");
            
            // 打印性能统计
            if (self.modulePerformanceStats[typeKey]) {
                NSDictionary *stats = self.modulePerformanceStats[typeKey];
                NSLog(@"  性能统计: 启动次数=%@, 停止次数=%@, 总运行时间=%.2f秒", 
                      stats[@"startCount"], 
                      stats[@"stopCount"], 
                      [stats[@"totalRunTime"] doubleValue]);
            }
        }
    }
    
    NSLog(@"==========================================");
}

- (void)pauseNonEssentialModules {
    @synchronized (self.modules) {
        // 优先级排序: 核心模块 > 路径模块 > 其他模块
        
        // 确保核心模块继续运行
        id<GPSModuleProtocol> coreModule = self.modules[@(GPSModuleTypeCore)];
        if (coreModule) {
            [self startModuleOfType:GPSModuleTypeCore];
        }
        
        // 路径模块在后台有限保持
        id<GPSModuleProtocol> routingModule = self.modules[@(GPSModuleTypeRouting)];
        if (routingModule) {
            // 如果处于深度省电模式或内存紧张，也要停止路径模块
            BOOL shouldKeepRouting = !([NSProcessInfo processInfo].lowPowerModeEnabled && self.isInBackground);
            
            if (shouldKeepRouting) {
                [self startModuleOfType:GPSModuleTypeRouting];
            } else {
                [self stopModuleOfType:GPSModuleTypeRouting];
            }
        }
        
        // 停止非必要模块
        NSArray *nonEssentialModules = @[
            @(GPSModuleTypeNavigation),
            @(GPSModuleTypeAutomation),
            @(GPSModuleTypeGeofencing),
            @(GPSModuleTypeAnalytics)
        ];
        
        for (NSNumber *typeNum in nonEssentialModules) {
            GPSModuleType type = [typeNum integerValue];
            if (self.modules[@(type)]) {
                [self stopModuleOfType:type];
                
                if (self.debugMode) {
                    NSLog(@"GPS模块管理器: 暂停非核心模块: %@", [self stringForModuleType:type]);
                }
            }
        }
    }
}

- (void)resumePausedModules {
    @synchronized (self.modules) {
        // 如果在省电模式下，只恢复必要模块
        if (self.powerSavingMode) {
            // 在省电模式下只启动核心和路径模块
            [self startModuleOfType:GPSModuleTypeCore];
            [self startModuleOfType:GPSModuleTypeRouting];
            
            // 地理围栏在省电模式下可选择性启动
            BOOL enableGeofencingInPowerSave = [[NSUserDefaults standardUserDefaults] 
                                              boolForKey:@"GPSEnableGeofencingInPowerSave"];
            if (enableGeofencingInPowerSave) {
                [self startModuleOfType:GPSModuleTypeGeofencing];
            }
        } else {
            // 正常模式下启动所有模块
            [self startAllModules];
        }
    }
}

- (void)reduceBackgroundActivity {
    // 在后台时减少活动，但不像省电模式那样激进
    
    // 停止数据分析模块（非必要）
    [self stopModuleOfType:GPSModuleTypeAnalytics];
    
    // 降低更新频率
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GPSReduceUpdateFrequency" 
                                                        object:nil];
}

- (void)notifyModulesOfStateChange:(NSString *)state {
    @synchronized (self.modules) {
        for (NSNumber *typeKey in self.modules) {
            id<GPSModuleProtocol> module = self.modules[typeKey];
            
            // 使用KVC检查模块是否实现了对应的状态变更方法
            SEL stateChangeSelector = NSSelectorFromString(state);
            if ([module respondsToSelector:stateChangeSelector]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                [module performSelector:stateChangeSelector];
                #pragma clang diagnostic pop
            }
        }
    }
}

- (void)freeMemoryResources {
    // 清理所有模块的缓存数据
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GPSClearMemoryCaches" 
                                                        object:nil];
    
    // 只保留必要模块运行
    [self pauseNonEssentialModules];
    
    // 强制进行垃圾回收（在iOS中我们能做的有限）
    @autoreleasepool {
        // 清理自动释放池
    }
}

- (void)applyPowerSavingSettings {
    NSLog(@"GPS模块管理器: 应用省电设置");
    
    // 1. 停止非必要模块
    [self pauseNonEssentialModules];
    
    // 2. 减少更新频率
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GPSModulePowerSavingEnabled" 
                                                        object:nil];
    
    // 3. 调整位置精度
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:100 forKey:@"GPSAccuracyInMeters"]; // 100米精度
    [defaults setBool:YES forKey:@"GPSReduceLocationAccuracy"];
    [defaults synchronize];
}

- (void)removePowerSavingSettings {
    NSLog(@"GPS模块管理器: 移除省电设置");
    
    // 恢复所有模块运行
    [self resumePausedModules];
    
    // 恢复正常更新频率
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GPSModulePowerSavingDisabled" 
                                                        object:nil];
    
    // 恢复位置精度
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:10 forKey:@"GPSAccuracyInMeters"]; // 10米精度
    [defaults setBool:NO forKey:@"GPSReduceLocationAccuracy"];
    [defaults synchronize];
}

@end