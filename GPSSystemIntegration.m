/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 *
 * GPSIntegrationLevelNormal：基础级别，只能欺骗单个应用
 * GPSIntegrationLevelDeep：深度级别，可以欺骗多个应用
 * GPSIntegrationLevelSystem：系统级别，可以欺骗系统服务
 */

#import "GPSSystemIntegration.h"
#import <CoreLocation/CoreLocation.h>
#import <dlfcn.h> // 添加动态库加载支持

// 添加内存统计所需头文件
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <mach/host_info.h>
#import <mach/task_info.h>
#import <mach/vm_map.h>

#if defined(__IPHONE_OS_VERSION_MIN_REQUIRED)
@interface NSTask : NSObject
- (void)setLaunchPath:(NSString *)path;
- (void)setArguments:(NSArray *)arguments;
- (void)launch;
- (void)waitUntilExit;
- (void)setStandardOutput:(id)output;
- (void)setStandardError:(id)error;
- (void)terminate;
@property (readonly) int terminationStatus;
@end
#else
#import <Foundation/NSTask.h>
#endif

@implementation GPSAppIntegrationProfile

- (instancetype)init {
    if (self = [super init]) {
        _enabled = NO;
        _useCustomLocation = NO;
        // 初始化默认值
    }
    return self;
}

@end

// 在类的私有接口中添加所需的方法声明
@interface GPSSystemIntegration()

// 现有属性
@property (nonatomic, strong) NSMutableDictionary *appProfiles;
@property (nonatomic, assign) BOOL systemWideIntegrationEnabled;
@property (nonatomic, assign) GPSIntegrationLevel currentIntegrationLevel;
@property (nonatomic, strong) UIView *statusBarIndicator;
@property (nonatomic, assign) BOOL batteryOptimizationEnabled;
@property (nonatomic, assign) BOOL memoryOptimizationEnabled;
@property (nonatomic, assign) NSInteger integrationPriority;
@property (nonatomic, assign) NSInteger maxConcurrentApps;
@property (nonatomic, strong) NSMutableArray *activeApps;
@property (nonatomic, strong) NSMutableDictionary *appHooks;

// 添加缺失的方法声明
- (BOOL)isJailbroken;
- (void)applyBatteryOptimizations;
- (void)removeBatteryOptimizations;
- (void)applyMemoryOptimizations;
- (void)removeMemoryOptimizations;
- (void)restartApp:(NSString *)bundleId;
- (GPSAppIntegrationProfile *)systemWideProfile;
- (BOOL)isDopamineJailbreak;

@end

@implementation GPSSystemIntegration

#pragma mark - 单例与初始化

+ (instancetype)sharedInstance {
    static GPSSystemIntegration *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _appProfiles = [NSMutableDictionary dictionary];
        _systemWideIntegrationEnabled = NO;
        _batteryOptimizationEnabled = YES;
        _memoryOptimizationEnabled = YES;
        _integrationPriority = 3;
        _activeApps = [NSMutableArray array];
        _appHooks = [NSMutableDictionary dictionary];
        
        // 强制设置为普通级别，确保安全运行
        _currentIntegrationLevel = GPSIntegrationLevelNormal;
        
        NSLog(@"[GPS++] 初始化为安全兼容模式，不会触发系统崩溃");
        
        // 禁用所有涉及系统修改的功能
        [self disableUnsafeFeaturesInStandardMode];
    }
    return self;
}

- (void)disableUnsafeFeaturesInStandardMode {
    // 禁用所有可能导致崩溃的功能
    self.systemWideIntegrationEnabled = NO;
    
    // 清除可能存在的危险配置
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"JailbreakPrefix"];
    [defaults removeObjectForKey:@"TweakInjectPath"];
    [defaults setBool:NO forKey:@"GPSSystemWideEnabled"];
    [defaults synchronize];
    
    NSLog(@"[GPS++] 已禁用所有可能导致系统不稳定的功能");
}

#pragma mark - 状态检查

- (void)determineAvailableIntegrationLevel {
    // 首先检测是否为越狱环境
    if ([self isJailbroken]) {
        NSLog(@"[GPS++] 检测到越狱环境");
        
        // 尝试获取高级权限
        if ([self attemptToGetEnhancedPermissions]) {
            if ([self isDopamineJailbreak]) {
                // Dopamine越狱环境下，禁用系统级功能
                _currentIntegrationLevel = GPSIntegrationLevelDeep;
                NSLog(@"[GPS++] Dopamine环境下可用最高权限为深度集成级别");
            } else {
                _currentIntegrationLevel = GPSIntegrationLevelSystem;
                NSLog(@"[GPS++] 获取到系统级集成权限");
            }
        } else {
            _currentIntegrationLevel = GPSIntegrationLevelDeep;
            NSLog(@"[GPS++] 获取到深度集成权限");
        }
    } else {
        _currentIntegrationLevel = GPSIntegrationLevelNormal;
        NSLog(@"[GPS++] 使用普通集成权限");
    }
}

- (GPSIntegrationLevel)availableIntegrationLevel {
    return _currentIntegrationLevel;
}

- (BOOL)canIntegrateWithTarget:(GPSIntegrationTarget)target {
    switch (target) {
        case GPSIntegrationTargetSpecificApp:
            // 基本级别就足以与特定应用集成
            return YES;
        case GPSIntegrationTargetAllApps:
            // 需要深度级别
            return self.availableIntegrationLevel >= GPSIntegrationLevelDeep;
        case GPSIntegrationTargetSystemServices:
            // 需要系统级别
            return self.availableIntegrationLevel >= GPSIntegrationLevelSystem;
    }
    return NO;
}

- (BOOL)isIntegratedWithApp:(NSString *)bundleId {
    GPSAppIntegrationProfile *profile = [self profileForApp:bundleId];
    return profile && profile.enabled;
}

#pragma mark - 应用集成

- (void)enableIntegrationForApp:(NSString *)bundleId {
    GPSAppIntegrationProfile *profile = [self profileForApp:bundleId];
    
    if (!profile) {
        profile = [[GPSAppIntegrationProfile alloc] init];
        profile.bundleId = bundleId;
        profile.appName = [self appNameForBundleId:bundleId];
    }
    
    profile.enabled = YES;
    [self setProfile:profile forApp:bundleId];
    
    // 记录操作日志
    NSLog(@"已为应用启用集成: %@", bundleId);
}

- (void)disableIntegrationForApp:(NSString *)bundleId {
    GPSAppIntegrationProfile *profile = [self profileForApp:bundleId];
    
    if (profile) {
        profile.enabled = NO;
        [self setProfile:profile forApp:bundleId];
        
        // 记录操作日志
        NSLog(@"已为应用禁用集成: %@", bundleId);
    }
}

- (void)setProfile:(GPSAppIntegrationProfile *)profile forApp:(NSString *)bundleId {
    if (!bundleId || bundleId.length == 0) {
        return;
    }
    
    self.appProfiles[bundleId] = profile;
    
    // 保存配置到持久存储
    [self saveProfilesToStorage];
    
    // 应用更改（如果应用正在运行）
    [self applyProfileChangesForApp:bundleId];
}

- (GPSAppIntegrationProfile *)profileForApp:(NSString *)bundleId {
    if (!bundleId) {
        return nil;
    }
    
    GPSAppIntegrationProfile *profile = self.appProfiles[bundleId];
    
    if (!profile) {
        // 从持久存储加载
        profile = [self loadProfileFromStorageForApp:bundleId];
        
        if (profile) {
            self.appProfiles[bundleId] = profile;
        }
    }
    
    return profile;
}

- (NSArray<GPSAppIntegrationProfile *> *)allProfiles {
    [self loadAllProfilesFromStorage];
    return [self.appProfiles.allValues copy];
}

#pragma mark - 系统集成

- (void)enableSystemWideIntegration:(BOOL)enable {
    if (enable) {
        NSLog(@"[GPS++] 系统级集成在安全模式下不可用");
    }
    self.systemWideIntegrationEnabled = NO; // 强制禁用
}

- (BOOL)isSystemWideIntegrationEnabled {
    return self.systemWideIntegrationEnabled;
}

- (void)registerSystemTrigger:(UIGestureRecognizer *)gesture {
    if (!gesture) {
        return;
    }
    
    // 获取主窗口
    UIWindow *mainWindow = [UIApplication sharedApplication].keyWindow;
    if (!mainWindow) {
        NSArray *windows = [UIApplication sharedApplication].windows;
        if (windows.count > 0) {
            mainWindow = windows.firstObject;
        }
    }
    
    if (mainWindow) {
        [mainWindow addGestureRecognizer:gesture];
        NSLog(@"系统触发手势已注册");
    } else {
        NSLog(@"注册系统触发手势失败：没有可用窗口");
    }
}

- (void)updateStatusBarIndicator:(BOOL)show {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (show) {
            if (!self.statusBarIndicator) {
                // 创建状态栏指示器
                CGFloat indicatorSize = 10.0;
                CGFloat statusBarHeight = [UIApplication sharedApplication].statusBarFrame.size.height;
                
                self.statusBarIndicator = [[UIView alloc] initWithFrame:CGRectMake(5, statusBarHeight - indicatorSize - 2, indicatorSize, indicatorSize)];
                self.statusBarIndicator.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:0.8];
                self.statusBarIndicator.layer.cornerRadius = indicatorSize / 2.0;
                self.statusBarIndicator.layer.masksToBounds = YES;
                
                // 将指示器添加到状态栏
                UIWindow *window = [UIApplication sharedApplication].keyWindow;
                if (window) {
                    [window addSubview:self.statusBarIndicator];
                    
                    // 使其在最前面
                    [window bringSubviewToFront:self.statusBarIndicator];
                }
            } else {
                self.statusBarIndicator.hidden = NO;
            }
        } else if (self.statusBarIndicator) {
            self.statusBarIndicator.hidden = YES;
        }
    });
}

#pragma mark - 性能管理

- (void)optimizeBatteryUsage:(BOOL)optimize {
    self.batteryOptimizationEnabled = optimize;
    
    if (optimize) {
        // 实施电池优化策略
        [self applyBatteryOptimizations];
    } else {
        // 移除电池优化
        [self removeBatteryOptimizations];
    }
}

- (void)optimizeMemoryUsage:(BOOL)optimize {
    self.memoryOptimizationEnabled = optimize;
    
    if (optimize) {
        // 实施内存优化策略
        [self applyMemoryOptimizations];
    } else {
        // 移除内存优化
        [self removeMemoryOptimizations];
    }
}

- (void)setIntegrationPriority:(NSInteger)priority {
    // 确保优先级在有效范围内
    priority = MAX(1, MIN(priority, 5));
    self.integrationPriority = priority;
    
    // 应用优先级设置
    [self applyIntegrationPrioritySettings];
}

#pragma mark - 权限支持

- (void)requestEnhancedPermissions:(void (^)(BOOL granted, NSError *error))completion {
    if (self.availableIntegrationLevel >= GPSIntegrationLevelDeep) {
        // 已经有高级权限
        if (completion) {
            completion(YES, nil);
        }
        return;
    }
    
    // 尝试获取权限
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // 检查是否可以获取更高级别的权限
        BOOL success = [self attemptToGetEnhancedPermissions];
        
        if (success) {
            self.currentIntegrationLevel = GPSIntegrationLevelDeep;
            if (completion) {
                completion(YES, nil);
            }
        } else {
            // 创建错误对象
            NSError *error = [NSError errorWithDomain:@"com.gps.integration"
                                                code:403
                                            userInfo:@{NSLocalizedDescriptionKey: @"增强权限请求被拒绝"}];
            if (completion) {
                completion(NO, error);
            }
        }
    });
}

- (BOOL)hasSystemPrivileges {
    return self.availableIntegrationLevel == GPSIntegrationLevelSystem;
}

- (void)presentPermissionsExplanation {
    // 创建统一的对话框，内容根据当前权限级别调整
    NSString *message = @"GPS++需要适当权限以提供位置修改功能。\n\n";
    
    if (self.currentIntegrationLevel < GPSIntegrationLevelDeep) {
        message = [message stringByAppendingString:@"当前处于基础级别(Normal)，位置修改仅影响当前应用。\n\n要获取更多功能，需要更高权限级别。"];
    } else if (self.currentIntegrationLevel == GPSIntegrationLevelDeep) {
        message = [message stringByAppendingString:@"当前处于深度级别(Deep)，可修改多个应用的位置信息。"];
    } else {
        message = [message stringByAppendingString:@"当前处于系统级别(System)，可修改系统服务和所有应用的位置信息。"];
    }
    
    UIAlertController *alert = [UIAlertController
                               alertControllerWithTitle:@"权限说明"
                               message:message
                               preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"了解" style:UIAlertActionStyleDefault handler:nil]];
    
    // 显示对话框
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        UIViewController *rootVC = window.rootViewController;
        [rootVC presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - 越狱检测和权限检查

- (BOOL)checkForPrivileges {
    // 检查是否有特权权限的几种方式
    
    // 1. 尝试写入系统目录
    NSError *error = nil;
    NSString *testPath = @"/private/var/test_gps_privileges.txt";
    NSString *testContent = @"test";
    BOOL writeSuccess = [testContent writeToFile:testPath 
                                      atomically:YES 
                                        encoding:NSUTF8StringEncoding 
                                           error:&error];
    
    if (writeSuccess) {
        // 如果能成功写入，则删除测试文件并返回true
        [[NSFileManager defaultManager] removeItemAtPath:testPath error:nil];
        return YES;
    }
    
    // 2. 检查是否能修改系统应用的Info.plist
    NSString *systemAppPath = @"/Applications/MobileSafari.app/Info.plist";
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:systemAppPath error:nil];
    if (attrs && [attrs fileOwnerAccountID] == 0 && 
        [[NSFileManager defaultManager] isWritableFileAtPath:systemAppPath]) {
        return YES;
    }
    
    // 3. 检查无根越狱特定的特征
    NSArray *rootlessJailbreakPaths = @[
        // 多巴胺(Dopamine)无根越狱路径
        @"/var/jb/usr/lib/TweakInject",
        @"/var/jb/Library/MobileSubstrate",
        @"/var/jb/bin/bash",
        @"/var/jb/usr/libexec/substrated",
        @"/var/jb/basebin",
        @"/var/jb/.installed_dopamine",
        
        // TrollStore相关路径
        @"/var/containers/Bundle/Application/*/TrollStore.app",
        @"/var/containers/Bundle/dylibs",
        
        // 其他无根越狱路径
        @"/var/LIB",
        @"/var/lib/apt",
        @"/var/lib/dpkg",
        @"/var/lib/cydia"
    ];
    
    for (NSString *path in rootlessJailbreakPaths) {
        if ([path containsString:@"*"]) {
            // 处理带通配符的路径
            NSString *parentPath = [path stringByDeletingLastPathComponent];
            NSString *lastComponent = [path lastPathComponent];
            NSString *searchPattern = [lastComponent stringByReplacingOccurrencesOfString:@"*" withString:@""];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:parentPath]) {
                NSError *dirError;
                NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:parentPath error:&dirError];
                if (contents && !dirError) {
                    for (NSString *item in contents) {
                        if ([item containsString:searchPattern]) {
                            return YES;
                        }
                    }
                }
            }
        } else if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }
    
    // 4. 检查是否有传统越狱检测文件
    NSArray *privilegedPaths = @[
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/usr/sbin/sshd",
        @"/etc/apt",
        @"/private/var/lib/apt/",
        @"/usr/libexec/cydia",
        @"/Applications/Cydia.app"
    ];
    
    for (NSString *path in privilegedPaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }
    
    // 5. 检查是否装有越狱常用应用
    NSArray *jailbreakAppSchemes = @[
        @"cydia",
        @"sileo",
        @"zbra",
        @"filza",
        @"trollstore",
        @"dopamine",
        @"santander",
        @"newterm",
        @"palera1n"
    ];
    
    for (NSString *scheme in jailbreakAppSchemes) {
        if ([[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@://", scheme]]]) {
            return YES;
        }
    }
    
    // 6. 检查是否能访问private目录
    NSString *privateDir = @"/private/";
    NSArray *privateContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:privateDir error:nil];
    if (privateContents && privateContents.count > 0) {
        return YES;
    }
    
    return NO;
}

- (BOOL)isDeviceJailbroken {
    // 1. 检查常见越狱和无根越狱文件
    NSArray *jailbreakPaths = @[
        // 传统越狱路径
        @"/Applications/Cydia.app",
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/bin/bash",
        @"/usr/sbin/sshd",
        
        // 无根越狱路径 - 多巴胺(Dopamine)
        @"/var/jb/usr/bin",
        @"/var/jb/Library/MobileSubstrate",
        @"/var/jb/Applications/Sileo.app",
        @"/var/jb/.installed_dopamine",
        @"/var/jb/basebin/launchd",
        
        // palera1n无根越狱
        @"/var/jb/basebin/palera1n",
        @"/var/jb/.palecursus_strapped",
        
        // TrollStore和其他
        @"/var/containers/Bundle/tweakinject.dylib",
        @"/var/containers/Bundle/Application/*/TrollStore.app",
        @"/var/Liy/Installed"
    ];
    
    for (NSString *path in jailbreakPaths) {
        if ([path containsString:@"*"]) {
            // 处理通配符路径
            NSString *directoryPath = [path stringByDeletingLastPathComponent];
            NSString *fileName = [[path lastPathComponent] stringByReplacingOccurrencesOfString:@"*" withString:@""];
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:directoryPath]) {
                NSError *error = nil;
                NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directoryPath error:&error];
                
                if (!error && contents) {
                    for (NSString *item in contents) {
                        if ([item containsString:fileName]) {
                            return YES;
                        }
                    }
                }
            }
        } else if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }
    
    // 2. 检查是否可以写入系统位置
    NSString *testPath = @"/private/jailbreak_test.txt";
    NSString *testContent = @"test";
    NSError *error = nil;
    if ([testContent writeToFile:testPath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [[NSFileManager defaultManager] removeItemAtPath:testPath error:nil];
        return YES;
    }
    
    // 3. 检查环境变量
    char *env = getenv("DYLD_INSERT_LIBRARIES");
    if (env && strlen(env) > 0) {
        return YES;
    }
    
    // 4. 检查可疑的符号链接
    NSString *symlink = @"/var/symlink";
    if ([[NSFileManager defaultManager] fileExistsAtPath:symlink]) {
        return YES;
    }
    
    return NO;
}

- (NSString *)appNameForBundleId:(NSString *)bundleId {
    if (!bundleId) return nil;
    
    // 先检查已安装的应用
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://", bundleId]];
    if ([[UIApplication sharedApplication] canOpenURL:url]) {
        // 尝试获取本地应用名称
        return [self localNameForBundleId:bundleId];
    }
    
    // 记录未找到的bundleId，稍后异步从App Store获取
    [self fetchAppNameFromAppStoreForBundleId:bundleId completion:^(NSString *appName) {
        if (appName) {
            // 更新我们的缓存或配置文件
            GPSAppIntegrationProfile *profile = [self profileForApp:bundleId];
            if (profile && (!profile.appName || [profile.appName isEqualToString:bundleId])) {
                profile.appName = appName;
                [self setProfile:profile forApp:bundleId];
            }
        }
    }];
    
    // 暂时返回bundle ID作为名称
    return bundleId;
}

// 获取本地应用名称
- (NSString *)localNameForBundleId:(NSString *)bundleIdentifier {
    if (!bundleIdentifier) return nil;
    
    // 先尝试查找当前安装的应用
    NSString *appPath = nil;
    
    // 通过私有API尝试获取(仅在越狱设备上生效)
    Class LSApplicationWorkspace_class = NSClassFromString(@"LSApplicationWorkspace");
    if (LSApplicationWorkspace_class) {
        id workspace = [LSApplicationWorkspace_class performSelector:@selector(defaultWorkspace)];
        NSArray *applications = [workspace performSelector:@selector(allApplications)];
        
        for (id application in applications) {
            NSString *appId = [application performSelector:@selector(applicationIdentifier)];
            if ([appId isEqualToString:bundleIdentifier]) {
                NSString *appName = [application performSelector:@selector(localizedName)];
                if (appName) {
                    return appName;
                }
            }
        }
    }
    
    return nil; // 如果未找到，返回nil
}

// 添加正确位置的方法
- (void)fetchAppNameFromAppStoreForBundleId:(NSString *)bundleId completion:(void (^)(NSString *appName))completion {
    NSString *urlString = [NSString stringWithFormat:@"https://itunes.apple.com/lookup?bundleId=%@", bundleId];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSError *jsonError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
            
            if (!jsonError && json && [json[@"resultCount"] intValue] > 0) {
                NSArray *results = json[@"results"];
                if (results.count > 0) {
                    NSString *appName = results[0][@"trackName"];
                    if (appName && completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(appName);
                        });
                        return;
                    }
                }
            }
        }
        
        // 失败时仍调用completion
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil);
            });
        }
    }];
    
    [task resume];
}

- (void)saveProfilesToStorage {
    // 将配置文件保存到UserDefaults
    NSMutableDictionary *profilesDict = [NSMutableDictionary dictionary];
    
    for (NSString *bundleId in self.appProfiles) {
        GPSAppIntegrationProfile *profile = self.appProfiles[bundleId];
        
        NSMutableDictionary *profileDict = [NSMutableDictionary dictionary];
        profileDict[@"bundleId"] = profile.bundleId;
        profileDict[@"appName"] = profile.appName;
        profileDict[@"enabled"] = @(profile.enabled);
        profileDict[@"useCustomLocation"] = @(profile.useCustomLocation);
        
        if (CLLocationCoordinate2DIsValid(profile.customCoordinate)) {
            profileDict[@"customLatitude"] = @(profile.customCoordinate.latitude);
            profileDict[@"customLongitude"] = @(profile.customCoordinate.longitude);
        }
        
        if (profile.customSettings) {
            profileDict[@"customSettings"] = profile.customSettings;
        }
        
        profilesDict[bundleId] = profileDict;
    }
    
    [[NSUserDefaults standardUserDefaults] setObject:profilesDict forKey:@"GPSAppProfiles"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (GPSAppIntegrationProfile *)loadProfileFromStorageForApp:(NSString *)bundleId {
    NSDictionary *allProfiles = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"GPSAppProfiles"];
    NSDictionary *profileDict = allProfiles[bundleId];
    
    if (!profileDict) {
        return nil;
    }
    
    GPSAppIntegrationProfile *profile = [[GPSAppIntegrationProfile alloc] init];
    profile.bundleId = profileDict[@"bundleId"];
    profile.appName = profileDict[@"appName"];
    profile.enabled = [profileDict[@"enabled"] boolValue];
    profile.useCustomLocation = [profileDict[@"useCustomLocation"] boolValue];
    
    if (profileDict[@"customLatitude"] && profileDict[@"customLongitude"]) {
        double lat = [profileDict[@"customLatitude"] doubleValue];
        double lng = [profileDict[@"customLongitude"] doubleValue];
        profile.customCoordinate = CLLocationCoordinate2DMake(lat, lng);
    }
    
    if (profileDict[@"customSettings"]) {
        profile.customSettings = profileDict[@"customSettings"];
    }
    
    return profile;
}

- (void)loadAllProfilesFromStorage {
    NSDictionary *allProfiles = [[NSUserDefaults standardUserDefaults] dictionaryForKey:@"GPSAppProfiles"];
    
    if (!allProfiles) {
        return;
    }
    
    for (NSString *bundleId in allProfiles) {
        // 只有当内存中没有这个配置文件时才加载
        if (!self.appProfiles[bundleId]) {
            GPSAppIntegrationProfile *profile = [self loadProfileFromStorageForApp:bundleId];
            if (profile) {
                self.appProfiles[bundleId] = profile;
            }
        }
    }
}

#pragma mark - 添加位置欺骗功能实现

- (void)applyProfileChangesForApp:(NSString *)bundleId {
    // 获取应用的配置
    GPSAppIntegrationProfile *profile = [self profileForApp:bundleId];
    
    if (!profile || !profile.enabled) {
        NSLog(@"应用未启用配置: %@", bundleId);
        return;
    }
    
    if (!profile.useCustomLocation) {
        NSLog(@"未设置自定义位置: %@", bundleId);
        return;
    }
    
    // 根据不同的集成级别应用位置修改
    switch (self.availableIntegrationLevel) {
        case GPSIntegrationLevelNormal:
            [self applyLocationSpoofingForSingleApp:bundleId withProfile:profile];
            break;
            
        case GPSIntegrationLevelDeep:
        case GPSIntegrationLevelSystem:
            [self applySystemWideLocationSpoofing:profile];
            break;
    }
}

// 实现单应用位置欺骗
- (void)applyLocationSpoofingForSingleApp:(NSString *)bundleId withProfile:(GPSAppIntegrationProfile *)profile {
    if (!CLLocationCoordinate2DIsValid(profile.customCoordinate)) {
        NSLog(@"无效的坐标设置: %@", bundleId);
        return;
    }
    
    // 应用特定的配置
    if (self.availableIntegrationLevel >= GPSIntegrationLevelDeep) {
        // 在越狱设备上可以使用高级方法
        [self installLocationHookForApp:bundleId coordinate:profile.customCoordinate];
    } else {
        // 基础模式 - 使用开发者API
        NSLog(@"使用开发者API为应用模拟位置: %@", bundleId);
        // 保存配置，依靠应用内的CLLocationManager模拟
    }
}

// 系统级位置欺骗实现
- (void)applySystemWideLocationSpoofing:(GPSAppIntegrationProfile *)profile {
    if (!CLLocationCoordinate2DIsValid(profile.customCoordinate)) {
        NSLog(@"系统级位置模拟的坐标无效");
        return;
    }
    
    if (self.availableIntegrationLevel < GPSIntegrationLevelSystem) {
        NSLog(@"系统级位置模拟需要系统级集成权限");
        return;
    }
    
    NSString *jbPrefix = [[NSUserDefaults standardUserDefaults] objectForKey:@"JailbreakPrefix"] ?: @"";
    
    // 创建并执行系统位置修改命令
    NSString *scriptPath = [jbPrefix stringByAppendingString:@"/usr/bin/gpsfix"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = scriptPath;
        task.arguments = @[
            @"--lat", [NSString stringWithFormat:@"%f", profile.customCoordinate.latitude],
            @"--lon", [NSString stringWithFormat:@"%f", profile.customCoordinate.longitude],
            @"--enable"
        ];
        
        [task launch];
        NSLog(@"系统级位置模拟已应用");
    } else {
        NSLog(@"未找到位置模拟工具: %@", scriptPath);
    }
}

- (void)installLocationHookForApp:(NSString *)bundleId coordinate:(CLLocationCoordinate2D)coordinate {
    if (self.availableIntegrationLevel < GPSIntegrationLevelDeep) {
        NSLog(@"权限不足，无法安装应用特定Hook");
        return;
    }
    
    NSString *tweakInjectPath = [[NSUserDefaults standardUserDefaults] objectForKey:@"TweakInjectPath"];
    if (!tweakInjectPath) {
        // 使用默认路径
        if ([self isDopamineJailbreak]) {
            tweakInjectPath = @"/var/jb/usr/lib/TweakInject";
        } else {
            tweakInjectPath = @"/Library/MobileSubstrate/DynamicLibraries";
        }
    }
    
    // 确保目录存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:tweakInjectPath]) {
        NSLog(@"注入目录不存在: %@", tweakInjectPath);
        return;
    }
    
    // 创建plist文件内容
    NSDictionary *plistDict = @{
        @"Filter": @{
            @"Bundles": @[bundleId],
            @"Executables": @[]
        },
        @"GPSCoordinate": @{
            @"Latitude": @(coordinate.latitude),
            @"Longitude": @(coordinate.longitude)
        },
        @"GPSEnabled": @YES
    };
    
    // 保存plist文件
    NSString *plistPath = [tweakInjectPath stringByAppendingPathComponent:[NSString stringWithFormat:@"GPS_%@.plist", bundleId]];
    [plistDict writeToFile:plistPath atomically:YES];
    
    NSLog(@"已为应用 %@ 安装位置Hook: (%f, %f)", bundleId, coordinate.latitude, coordinate.longitude);
    
    // 尝试重启目标应用（如果可能）
    [self restartApp:bundleId];
}

- (void)applyAllProfiles {
    for (NSString *bundleId in self.appProfiles) {
        GPSAppIntegrationProfile *profile = self.appProfiles[bundleId];
        if (profile && profile.enabled && profile.useCustomLocation) {
            [self applyProfileChangesForApp:bundleId];
        }
    }
    
    // 如果启用了系统级集成，也应用系统级配置
    if (self.isSystemWideIntegrationEnabled) {
        GPSAppIntegrationProfile *systemProfile = [self systemWideProfile];
        if (systemProfile) {
            [self applySystemWideLocationSpoofing:systemProfile];
        }
    }
}

// 修复权限不足的重启应用方法
- (void)restartApp:(NSString *)bundleId {
    if (self.currentIntegrationLevel < GPSIntegrationLevelDeep) {
        NSLog(@"权限不足，无法重启应用");
        return;
    }
    
    if ([self isDopamineJailbreak]) {
        // 使用NSTask替代system
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:@"/var/jb/usr/bin/killall"];
        [task setArguments:@[bundleId]];
        [task launch];
    } else {
        // 使用NSTask替代system
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:@"/usr/bin/killall"];
        [task setArguments:@[bundleId]];
        [task launch];
    }
}

// 修复所有使用了错误属性名称的地方
- (GPSAppIntegrationProfile *)systemWideProfile {
    GPSAppIntegrationProfile *profile = [[GPSAppIntegrationProfile alloc] init];
    profile.bundleId = @"com.apple.locationd";
    profile.appName = @"System Location Services";
    profile.enabled = self.isSystemWideIntegrationEnabled;
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    double latitude = [defaults doubleForKey:@"SystemLatitude"];
    double longitude = [defaults doubleForKey:@"SystemLongitude"];
    
    if (latitude != 0 && longitude != 0) {
        profile.customCoordinate = CLLocationCoordinate2DMake(latitude, longitude);
        profile.useCustomLocation = YES;
    } else {
        profile.useCustomLocation = NO;
    }
    
    return profile;
}

- (BOOL)isDopamineJailbreak {
    // 检查Dopamine越狱的特定路径
    NSArray *dopaminePaths = @[
        @"/var/jb/usr/lib/TweakInject",
        @"/var/jb/basebin",
        @"/var/jb/.installed_dopamine"
    ];
    
    for (NSString *path in dopaminePaths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }
    
    // 额外检查路径特征
    NSString *checkPath = @"/var/jb";
    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:checkPath isDirectory:&isDirectory] && isDirectory) {
        return YES;
    }
    
    return NO;
}

@end