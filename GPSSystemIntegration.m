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

@interface GPSSystemIntegration()

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

- (BOOL)isDopamineJailbreak;
- (void)setupForDopamineEnvironment;
- (void)determineAvailableIntegrationLevel;
- (void)setupForSpecificJailbreak;

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
    // 强制使用基本级别，避免尝试越狱检测
    _currentIntegrationLevel = GPSIntegrationLevelNormal;
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
    
    // 创建特定应用的plist
    NSString *plistName = [NSString stringWithFormat:@"GPSSpoofer_%@.plist", [bundleId stringByReplacingOccurrencesOfString:@"." withString:@"_"]];
    NSString *plistPath = [tweakInjectPath stringByAppendingPathComponent:plistName];
    
    NSDictionary *plistDict = @{
        @"Filter": @{
            @"Bundles": @[bundleId]
        },
        @"Location": @{
            @"Latitude": @(coordinate.latitude),
            @"Longitude": @(coordinate.longitude)
        }
    };
    
    BOOL success = [plistDict writeToFile:plistPath atomically:YES];
    
    if (success) {
        NSLog(@"成功为应用安装Hook: %@", bundleId);
    } else {
        NSLog(@"为应用创建Hook失败: %@", bundleId);
    }
}

#pragma mark - 越狱环境配置与系统Hook

- (void)setupForSpecificJailbreak {
    // 检测Dopamine越狱
    if ([self isDopamineJailbreak]) {
        NSLog(@"检测到Dopamine越狱，正在应用专用设置");
        [self setupForDopamineEnvironment];
    } else if ([self isTrollStoreInstalled]) {
        NSLog(@"检测到TrollStore环境，正在应用相应设置");
        [self setupForTrollStoreEnvironment];
    } else if ([self isPalera1nJailbreak]) {
        NSLog(@"检测到palera1n越狱，正在应用专用设置");
        [self setupForPalera1nEnvironment];
    } else if ([self isLegacyJailbreak]) {
        NSLog(@"检测到传统越狱环境，正在应用标准设置");
        [self setupForLegacyJailbreakEnvironment];
    }
}

- (BOOL)isDopamineJailbreak {
    @try {
        // 添加更稳定的检测逻辑
        NSFileManager *fm = [NSFileManager defaultManager];
        
        // 如果偏好设置已标记，直接返回
        NSString *savedType = [[NSUserDefaults standardUserDefaults] stringForKey:@"JailbreakType"];
        if ([savedType isEqualToString:@"dopamine"]) {
            return YES;
        }
        
        // 检测核心文件
        if ([fm fileExistsAtPath:@"/var/jb/.installed_dopamine"]) {
            return YES;
        }
        
        // 轻量级检测，避免过多访问文件系统
        NSArray *quickCheckPaths = @[
            @"/var/jb/basebin/launchd", 
            @"/var/jb/usr/lib/TweakInject"
        ];
        
        for (NSString *path in quickCheckPaths) {
            if ([fm fileExistsAtPath:path]) {
                return YES;
            }
        }
        
        return NO;
    } @catch (NSException *exception) {
        NSLog(@"[GPS++] 越狱检测异常: %@", exception);
        return NO;
    }
}

- (BOOL)isTrollStoreInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/containers/Bundle/dylibs"] ||
           [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:@"trollstore://"]];
}

- (BOOL)isPalera1nJailbreak {
    NSArray *paths = @[
        @"/var/jb/basebin/palera1n",
        @"/var/jb/.palecursus_strapped"
    ];
    
    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isLegacyJailbreak {
    NSArray *paths = @[
        @"/Library/MobileSubstrate/MobileSubstrate.dylib",
        @"/Applications/Cydia.app"
    ];
    
    for (NSString *path in paths) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            return YES;
        }
    }
    return NO;
}

- (void)setupForDopamineEnvironment {
    @try {
        NSLog(@"[GPS++] 正在安全配置Dopamine越狱环境");
        
        // 保存基本配置
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        
        // 路径前缀 - 标记但不尝试访问
        NSString *jbPrefix = @"/var/jb";
        
        // 安全设置TweakInject路径，不尝试创建文件
        NSString *tweakInjectPath = @"/var/jb/usr/lib/TweakInject";
        if (![[NSFileManager defaultManager] fileExistsAtPath:tweakInjectPath]) {
            tweakInjectPath = @"/var/jb/Library/MobileSubstrate/DynamicLibraries";
        }
        
        // 保存配置
        [defaults setObject:jbPrefix forKey:@"JailbreakPrefix"];
        [defaults setObject:tweakInjectPath forKey:@"TweakInjectPath"];
        [defaults setObject:@"/var/jb/usr/bin" forKey:@"BinaryPath"];
        [defaults setObject:@"dopamine" forKey:@"JailbreakType"];
        [defaults synchronize];
        
        // 避免系统级钩子，设置级别为Deep而不是System
        self.currentIntegrationLevel = GPSIntegrationLevelDeep;
        
        NSLog(@"[GPS++] Dopamine环境已安全配置");
    } @catch (NSException *exception) {
        NSLog(@"[GPS++] Dopamine环境配置异常: %@", exception);
    }
}

- (void)setupForTrollStoreEnvironment {
    // 设置TrollStore特定路径和配置
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"" forKey:@"JailbreakPrefix"];
    [defaults setObject:@"/var/containers/Bundle/dylibs" forKey:@"TweakInjectPath"];
    [defaults setObject:@"/var/containers/Bundle/Application/TrollStore.app/TS_BinPack" forKey:@"BinaryPath"];
    [defaults setObject:@"trollstore" forKey:@"JailbreakType"];
    [defaults synchronize];
    
    // TrollStore环境中使用更安全的设置
    self.currentIntegrationLevel = GPSIntegrationLevelNormal;
}

- (void)setupForPalera1nEnvironment {
    // 设置palera1n特定路径和配置
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"/var/jb" forKey:@"JailbreakPrefix"];
    [defaults setObject:@"/var/jb/usr/lib/TweakInject" forKey:@"TweakInjectPath"];
    [defaults setObject:@"/var/jb/usr/bin" forKey:@"BinaryPath"];
    [defaults setObject:@"palera1n" forKey:@"JailbreakType"];
    [defaults synchronize];
}

- (void)setupForLegacyJailbreakEnvironment {
    // 设置传统越狱的路径和配置
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@"" forKey:@"JailbreakPrefix"];
    [defaults setObject:@"/Library/MobileSubstrate/DynamicLibraries" forKey:@"TweakInjectPath"];
    [defaults setObject:@"/usr/bin" forKey:@"BinaryPath"];
    [defaults setObject:@"legacy" forKey:@"JailbreakType"];
    [defaults synchronize];
}

- (void)installSystemHooks {
    // 检测到Dopamine环境时，禁用系统钩子安装
    if ([self isDopamineJailbreak]) {
        NSLog(@"[GPS++] 在Dopamine环境中禁用系统钩子安装以防止崩溃");
        return;
    }
    
    @try {
        NSLog(@"[GPS++] 开始安装系统钩子");
        
        // 权限检查
        if (self.availableIntegrationLevel < GPSIntegrationLevelDeep) {
            NSLog(@"[GPS++] 权限不足，无法安装系统钩子");
            return;
        }
        
        // 检查文件系统权限，使用更安全的方法
        NSString *testFile = @"/var/mobile/gps_test_file";
        NSError *writeError = nil;
        if (![@"test" writeToFile:testFile atomically:YES encoding:NSUTF8StringEncoding error:&writeError]) {
            NSLog(@"[GPS++] 文件系统权限不足，跳过系统钩子安装: %@", writeError);
            return;
        } else {
            [[NSFileManager defaultManager] removeItemAtPath:testFile error:nil];
        }
        
        // 使用配置文件方法而非直接文件操作
        NSString *jbPrefix = [[NSUserDefaults standardUserDefaults] stringForKey:@"JailbreakPrefix"] ?: @"/var/jb";
        
        // 仅在非Dopamine越狱下继续执行敏感操作
        if (![self isDopamineJailbreak]) {
            // 安全实现...
        }
    } @catch (NSException *exception) {
        NSLog(@"[GPS++] 安装钩子异常: %@", exception);
    }
}

- (void)removeSystemHooks {
    // 优化可能导致崩溃的清理工作
    if ([self isDopamineJailbreak]) {
        NSLog(@"[GPS++] Dopamine环境中，使用安全方式移除系统钩子");
        
        // 只移除我们自己的文件，不触碰系统服务
        NSString *tweakInjectPath = [[NSUserDefaults standardUserDefaults] objectForKey:@"TweakInjectPath"];
        if (tweakInjectPath) {
            NSError *error = nil;
            NSString *plistPath = [tweakInjectPath stringByAppendingPathComponent:@"GPSSystemSpoof.plist"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:plistPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:plistPath error:&error];
                if (error) {
                    NSLog(@"[GPS++] 安全移除配置文件失败: %@", error);
                }
            }
        }
        
        // 不重启系统服务
        return;
    }
    
    // 获取必要路径变量
    NSString *tweakInjectPath = [[NSUserDefaults standardUserDefaults] objectForKey:@"TweakInjectPath"];
    NSString *jbPrefix = [[NSUserDefaults standardUserDefaults] objectForKey:@"JailbreakPrefix"] ?: @"";
    
    if (!tweakInjectPath) {
        // 使用默认路径
        if ([self isDopamineJailbreak]) {
            tweakInjectPath = @"/var/jb/usr/lib/TweakInject";
        } else {
            tweakInjectPath = @"/Library/MobileSubstrate/DynamicLibraries";
        }
    }
    
    // 移除动态库
    NSString *dylibPath = [tweakInjectPath stringByAppendingPathComponent:@"GPSSystemSpoof.dylib"];
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:dylibPath error:&error];
    
    if (!success || error) {
        NSLog(@"移除动态库失败: %@", error);
    }
    
    // 移除plist配置文件
    NSString *plistPath = [tweakInjectPath stringByAppendingPathComponent:@"GPSSystemSpoof.plist"];
    error = nil;
    success = [[NSFileManager defaultManager] removeItemAtPath:plistPath error:&error];
    
    if (!success || error) {
        NSLog(@"移除配置文件失败: %@", error);
    }
    
    NSLog(@"Hook移除成功");
    
    // 重新加载系统服务
    NSString *binPath = [[NSUserDefaults standardUserDefaults] objectForKey:@"BinaryPath"] ?: @"/usr/bin";
    NSString *launchctlPath = [NSString stringWithFormat:@"%@%@", jbPrefix, binPath];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:[launchctlPath stringByAppendingPathComponent:@"launchctl"]]) {
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:[launchctlPath stringByAppendingPathComponent:@"launchctl"]];
        [task setArguments:@[@"unload", @"/System/Library/LaunchDaemons/com.apple.locationd.plist"]];
        [task launch];
        
        // 等待一小段时间后重新加载
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSTask *loadTask = [[NSTask alloc] init];
            [loadTask setLaunchPath:[launchctlPath stringByAppendingPathComponent:@"launchctl"]];
            [loadTask setArguments:@[@"load", @"/System/Library/LaunchDaemons/com.apple.locationd.plist"]];
            [loadTask launch];
        });
    }
}

- (void)removeLocationHookForApp:(NSString *)bundleId {
    // 移除特定应用的位置Hook
    if (self.availableIntegrationLevel < GPSIntegrationLevelDeep) {
        NSLog(@"权限不足，无法移除应用特定Hook");
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
    
    // 删除特定应用的plist
    NSString *plistName = [NSString stringWithFormat:@"GPSSpoofer_%@.plist", [bundleId stringByReplacingOccurrencesOfString:@"." withString:@"_"]];
    NSString *plistPath = [tweakInjectPath stringByAppendingPathComponent:plistName];
    
    NSError *error = nil;
    [[NSFileManager defaultManager] removeItemAtPath:plistPath error:&error];
    
    if (error) {
        NSLog(@"移除应用Hook失败: %@, 错误: %@", bundleId, error);
    } else {
        NSLog(@"成功移除应用Hook: %@", bundleId);
    }
}

- (void)installSystemWideLocationHook {
    // 对于Dopamine环境，完全禁用此功能
    if ([self isDopamineJailbreak]) {
        NSLog(@"[GPS++] 在Dopamine环境中禁用系统级位置钩子以防止崩溃");
        
        // 通知用户
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController 
                alertControllerWithTitle:@"功能受限"
                message:@"在Dopamine环境下，系统级位置模拟功能已被禁用以确保系统稳定。您仍可以使用应用级位置模拟功能。"
                preferredStyle:UIAlertControllerStyleAlert];
                
            [alert addAction:[UIAlertAction actionWithTitle:@"了解" style:UIAlertActionStyleDefault handler:nil]];
            
            UIWindow *window = [UIApplication sharedApplication].keyWindow;
            [window.rootViewController presentViewController:alert animated:YES completion:nil];
        });
        
        return;
    }
    
    // 获取配置信息
    NSString *jbPrefix = [[NSUserDefaults standardUserDefaults] stringForKey:@"JailbreakPrefix"] ?: @"";
    NSString *binPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"BinaryPath"] ?: @"/usr/bin";
    
    // 创建系统级别位置服务Hook
    NSString *scriptPath = [NSString stringWithFormat:@"%@%@/gpshook", jbPrefix, binPath];
    NSMutableString *scriptContent = [NSMutableString string];
    [scriptContent appendString:@"#!/bin/bash\n"];
    [scriptContent appendString:@"# GPS系统Hook by GPSSystemIntegration\n\n"];
    [scriptContent appendString:@"PLIST_PATH=\"/var/mobile/Library/Preferences/com.gps.integration.plist\"\n"];
    [scriptContent appendString:@"DAEMON_PLIST=\"/System/Library/LaunchDaemons/com.apple.locationd.plist\"\n\n"];
    [scriptContent appendString:@"# 检查是否启用位置修改\n"];
    [scriptContent appendString:@"if defaults read \"$PLIST_PATH\" GPSSystemWideEnabled &>/dev/null; then\n"];
    [scriptContent appendString:@"  ENABLED=$(defaults read \"$PLIST_PATH\" GPSSystemWideEnabled)\n"];
    [scriptContent appendString:@"  if [ \"$ENABLED\" -eq 1 ]; then\n"];
    [scriptContent appendString:@"    LAT=$(defaults read \"$PLIST_PATH\" GPSLatitude)\n"];
    [scriptContent appendString:@"    LON=$(defaults read \"$PLIST_PATH\" GPSLongitude)\n"];
    [scriptContent appendString:@"    # 应用位置修改\n"];
    [scriptContent appendString:@"    DYLD_INSERT_LIBRARIES=/usr/lib/GPSSystemHook.dylib locationd\n"];
    [scriptContent appendString:@"  else\n"];
    [scriptContent appendString:@"    # 正常运行locationd\n"];
    [scriptContent appendString:@"    exec /usr/libexec/locationd\n"];
    [scriptContent appendString:@"  fi\n"];
    [scriptContent appendString:@"else\n"];
    [scriptContent appendString:@"  # 配置不存在，正常运行locationd\n"];
    [scriptContent appendString:@"  exec /usr/libexec/locationd\n"];
    [scriptContent appendString:@"fi\n"];
    
    // 写入脚本文件
    BOOL success = [scriptContent writeToFile:scriptPath 
                                   atomically:YES 
                                     encoding:NSUTF8StringEncoding 
                                        error:nil];
    
    if (success) {
        // 设置执行权限
        NSString *chmodPath = [NSString stringWithFormat:@"%@%@/chmod", jbPrefix, binPath];
        NSTask *chmodTask = [[NSTask alloc] init];
        [chmodTask setLaunchPath:chmodPath];
        [chmodTask setArguments:@[@"755", scriptPath]];
        [chmodTask launch];
        
        // 保存配置
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:@"GPSSystemWideEnabled"];
        [defaults synchronize];
        
        NSLog(@"系统级位置Hook已安装");
    } else {
        NSLog(@"系统级位置Hook安装失败: 无法创建脚本");
    }
}

- (void)removeSystemWideLocationHook {
    if (self.availableIntegrationLevel < GPSIntegrationLevelSystem) {
        NSLog(@"无法移除系统级位置Hook: 权限不足");
        return;
    }
    
    // 获取配置信息
    NSString *jbPrefix = [[NSUserDefaults standardUserDefaults] stringForKey:@"JailbreakPrefix"] ?: @"";
    NSString *binPath = [[NSUserDefaults standardUserDefaults] stringForKey:@"BinaryPath"] ?: @"/usr/bin";
    
    // 删除系统级别位置服务Hook
    NSString *scriptPath = [NSString stringWithFormat:@"%@%@/gpshook", jbPrefix, binPath];
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] removeItemAtPath:scriptPath error:&error];
    
    if (success || ![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
        // 更新配置
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:NO forKey:@"GPSSystemWideEnabled"];
        [defaults synchronize];
        
        NSLog(@"系统级位置Hook已移除");
    } else {
        NSLog(@"系统级位置Hook移除失败: %@", error);
    }
    
    // 重启位置服务
    NSString *launchctl = [NSString stringWithFormat:@"%@%@/launchctl", jbPrefix, binPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:launchctl]) {
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:launchctl];
        [task setArguments:@[@"restart", @"com.apple.locationd"]];
        [task launch];
    }
}

#pragma mark - 完善电池和内存优化实现

- (void)applyBatteryOptimizations {
    NSLog(@"正在应用电池优化");
    
    // 调整位置更新频率
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:5 forKey:@"GPSUpdateIntervalSeconds"]; // 5秒更新一次
    
    // 减少后台活动
    [defaults setBool:YES forKey:@"GPSReduceBackgroundActivity"];
    
    // 调低位置精度
    [defaults setInteger:100 forKey:@"GPSAccuracyInMeters"]; // 100米精度
    
    [defaults synchronize];
    
    // 通知所有活跃的GPS组件应用新设置
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GPSOptimizationSettingsChanged" object:nil];
}

- (void)removeBatteryOptimizations {
    NSLog(@"正在移除电池优化");
    
    // 恢复默认设置
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:1 forKey:@"GPSUpdateIntervalSeconds"]; // 1秒更新一次
    [defaults setBool:NO forKey:@"GPSReduceBackgroundActivity"];
    [defaults setInteger:10 forKey:@"GPSAccuracyInMeters"]; // 10米精度
    [defaults synchronize];
    
    // 通知所有活跃的GPS组件应用新设置
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GPSOptimizationSettingsChanged" object:nil];
}

- (void)applyMemoryOptimizations {
    NSLog(@"正在应用内存优化");
    
    // 清理缓存
    [self clearLocationCache];
    
    // 减少保存的历史记录数量
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:10 forKey:@"GPSMaxHistoryItems"]; // 只保留10条历史记录
    [defaults setBool:YES forKey:@"GPSDisableDetailedLogs"]; // 禁用详细日志
    [defaults synchronize];
    
    // 限制同时处理的应用数量
    self.maxConcurrentApps = 3;
}

- (void)removeMemoryOptimizations {
    NSLog(@"正在移除内存优化");
    
    // 恢复默认设置
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:50 forKey:@"GPSMaxHistoryItems"]; // 恢复为50条历史记录
    [defaults setBool:NO forKey:@"GPSDisableDetailedLogs"]; // 启用详细日志
    [defaults synchronize];
    
    // 恢复并发应用数量限制
    self.maxConcurrentApps = 10;
}

- (void)clearLocationCache {
    // 清理保存的位置数据缓存
    NSString *cachePath = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject
                          stringByAppendingPathComponent:@"GPSLocationCache"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:cachePath error:&error];
        
        if (error) {
            NSLog(@"清理位置缓存失败: %@", error);
        }
    }
}

#pragma mark - 权限获取实现

- (BOOL)attemptToGetEnhancedPermissions {
    NSLog(@"正在尝试获取增强权限...");
    
    // 先检查已有权限
    if ([self checkForPrivileges]) {
        NSLog(@"设备已有必要权限");
        return YES;
    }
    
    // 检测当前越狱环境并尝试获取权限
    BOOL privilegesObtained = NO;
    NSString *jailbreakType = [[NSUserDefaults standardUserDefaults] stringForKey:@"JailbreakType"];
    
    if ([jailbreakType isEqualToString:@"dopamine"]) {
        privilegesObtained = [self getDopaminePermissions];
    } else if ([jailbreakType isEqualToString:@"palera1n"]) {
        privilegesObtained = [self getPalera1nPermissions];
    } else if ([jailbreakType isEqualToString:@"trollstore"]) {
        privilegesObtained = [self getTrollStorePermissions];
    } else {
        privilegesObtained = [self getLegacyJailbreakPermissions];
    }
    
    // 尝试通用权限获取方法
    if (!privilegesObtained) {
        privilegesObtained = [self attemptGenericPrivilegeEscalation];
    }
    
    // 如果成功获取权限，更新系统状态
    if (privilegesObtained) {
        NSLog(@"成功获取增强权限");
        if (self.currentIntegrationLevel < GPSIntegrationLevelDeep) {
            self.currentIntegrationLevel = GPSIntegrationLevelDeep;
        }
        
        // 创建必要的文件和目录
        [self createRequiredDirectories];
        
        // 保存权限状态
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"HasEnhancedPermissions"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    } else {
        NSLog(@"获取增强权限失败");
        
        // 显示权限失败通知，提示用户手动操作
        dispatch_async(dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController 
                alertControllerWithTitle:@"权限获取失败"
                message:@"无法自动获取增强权限。请确保设备已越狱并安装了必要的组件。"
                preferredStyle:UIAlertControllerStyleAlert];
                
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            
            UIWindow *window = [UIApplication sharedApplication].keyWindow;
            [window.rootViewController presentViewController:alert animated:YES completion:nil];
        });
    }
    
    return privilegesObtained;
}

- (BOOL)getDopaminePermissions {
    @try {
        // 对于Dopamine，采用最低权限模式，不尝试获取额外权限
        NSLog(@"[GPS++] Dopamine环境下采用安全权限模式");
        
        // 简单检查基本权限（非系统级）
        NSString *testPath = @"/var/mobile/gps_basic_check.txt";
        if ([@"test" writeToFile:testPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
            [[NSFileManager defaultManager] removeItemAtPath:testPath error:nil];
            return YES;
        }
        
        // 不尝试使用权限工具
        return NO;
    } @catch (NSException *exception) {
        NSLog(@"[GPS++] 权限检查异常: %@", exception);
        return NO;
    }
}

// 添加备选权限获取方法
- (BOOL)tryAlternativeDopaminePermMethod {
    @try {
        NSString *jbPrefix = @"/var/jb";
        NSString *bashPath = [NSString stringWithFormat:@"%@/bin/bash", jbPrefix];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:bashPath]) {
            bashPath = [NSString stringWithFormat:@"%@/usr/bin/bash", jbPrefix];
            if (![[NSFileManager defaultManager] fileExistsAtPath:bashPath]) {
                return NO;
            }
        }
        
        // 尝试使用特定的越狱扩展功能
        NSString *testPath = @"/private/var/gps_perm_test.txt";
        NSString *testContent = @"test";
        
        NSTask *task = [[NSTask alloc] init];
        [task setLaunchPath:bashPath];
        [task setArguments:@[@"-c", [NSString stringWithFormat:@"echo '%@' > %@", testContent, testPath]]];
        
        @try {
            [task launch];
            [task waitUntilExit];
            
            // 检查文件是否创建成功
            if ([[NSFileManager defaultManager] fileExistsAtPath:testPath]) {
                [[NSFileManager defaultManager] removeItemAtPath:testPath error:nil];
                return YES;
            }
        } @catch (NSException *exception) {
            NSLog(@"[GPS++] 备选权限方法异常: %@", exception);
        }
        
        return NO;
    } @catch (NSException *exception) {
        NSLog(@"[GPS++] 备选权限方法异常: %@", exception);
        return NO;
    }
}

- (BOOL)safeExecuteCommandInDopamine:(NSString *)command {
    // 在Dopamine环境中，禁用某些可能导致崩溃的命令
    if ([command containsString:@"launchd"] || 
        [command containsString:@"locationd"] || 
        [command containsString:@"/System/Library"]) {
        NSLog(@"[GPS++] 已阻止可能不安全的命令: %@", command);
        return NO;
    }
    
    @try {
        NSString *jbPrefix = [[NSUserDefaults standardUserDefaults] stringForKey:@"JailbreakPrefix"] ?: @"/var/jb";
        NSString *bashPath = [NSString stringWithFormat:@"%@/bin/bash", jbPrefix];
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:bashPath]) {
            bashPath = [NSString stringWithFormat:@"%@/usr/bin/bash", jbPrefix];
            if (![[NSFileManager defaultManager] fileExistsAtPath:bashPath]) {
                NSLog(@"[GPS++] 无法找到bash路径，命令执行失败");
                return NO;
            }
        }
        
        // 安全的命令执行
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = bashPath;
        task.arguments = @[@"-c", command];
        
        NSPipe *outputPipe = [NSPipe pipe];
        [task setStandardOutput:outputPipe];
        [task setStandardError:outputPipe];
        
        // 设置超时保护
        NSDate *startTime = [NSDate date];
        __block BOOL completed = NO;
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @try {
                [task launch];
                [task waitUntilExit];
                completed = YES;
            } @catch (NSException *e) {
                NSLog(@"[GPS++] 命令执行异常: %@", e);
            }
        });
        
        // 等待最多3秒
        while (!completed && [[NSDate date] timeIntervalSinceDate:startTime] < 3) {
            [NSThread sleepForTimeInterval:0.1];
        }
        
        if (!completed) {
            NSLog(@"[GPS++] 命令执行超时");
            // 尝试终止任务
            [task terminate];
            return NO;
        }
        
        return (task.terminationStatus == 0);
    } @catch (NSException *exception) {
        NSLog(@"[GPS++] 执行命令异常: %@", exception);
        return NO;
    }
}

- (BOOL)getPalera1nPermissions {
    NSLog(@"尝试获取palera1n越狱环境权限");
    
    // 检查palera1n特定文件
    if (![[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb/basebin/palera1n"]) {
        return NO;
    }
    
    // 尝试使用palera1n权限辅助工具
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/var/jb/usr/bin/sudo"];
    [task setArguments:@[@"-E", @"touch", @"/private/var/mobile/.gps_integration_authorized"]];
    
    @try {
        [task launch];
        [task waitUntilExit];
        
        // 验证是否成功创建了授权文件
        if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/mobile/.gps_integration_authorized"]) {
            return YES;
        }
    } @catch (NSException *exception) {
        NSLog(@"获取palera1n权限异常: %@", exception);
    }
    
    return NO;
}

- (BOOL)getTrollStorePermissions {
    NSLog(@"尝试获取TrollStore环境权限");
    
    // TrollStore环境下有限制，尝试使用可用的权限
    BOOL canAccessContainer = NO;
    
    // 检查是否能访问应用容器目录
    NSString *containerPath = @"/var/containers/Bundle/Application";
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if ([fileManager isReadableFileAtPath:containerPath]) {
        NSError *error = nil;
        NSArray *contents = [fileManager contentsOfDirectoryAtPath:containerPath error:&error];
        
        if (contents && !error) {
            canAccessContainer = YES;
        }
    }
    
    // 如果能访问容器目录，尝试在允许的位置创建辅助文件
    if (canAccessContainer) {
        NSString *helperPath = @"/var/containers/Bundle/dylibs/gps_helper.plist";
        NSDictionary *helperDict = @{
            @"BundleID": [[NSBundle mainBundle] bundleIdentifier],
            @"AllowLocationSpoofing": @YES,
            @"AllowBackgroundAccess": @YES
        };
        
        if ([helperDict writeToFile:helperPath atomically:YES]) {
            return YES;
        }
    }
    
    return NO;
}

- (BOOL)getLegacyJailbreakPermissions {
    NSLog(@"尝试获取传统越狱环境权限");
    
    // 尝试几种常见的传统越狱权限获取方法
    NSArray *helperTools = @[
        @"/usr/bin/su",
        @"/usr/bin/sudo",
        @"/usr/sbin/chown"
    ];
    
    for (NSString *tool in helperTools) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:tool]) {
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:tool];
            
            if ([tool hasSuffix:@"su"]) {
                [task setArguments:@[@"mobile", @"-c", @"touch /private/var/mobile/.gps_authorized"]];
            } else if ([tool hasSuffix:@"sudo"]) {
                [task setArguments:@[@"touch", @"/private/var/mobile/.gps_authorized"]];
            } else if ([tool hasSuffix:@"chown"]) {
                [task setArguments:@[@"mobile:mobile", @"/private/var/mobile"]];
            }
            
            @try {
                [task launch];
                [task waitUntilExit];
                
                // 检查权限操作是否成功
                if ([[NSFileManager defaultManager] fileExistsAtPath:@"/private/var/mobile/.gps_authorized"]) {
                    return YES;
                }
            } @catch (NSException *exception) {
                NSLog(@"执行权限工具异常: %@", exception);
                continue;
            }
        }
    }
    
    return NO;
}

- (BOOL)attemptGenericPrivilegeEscalation {
    NSLog(@"尝试通用权限提升方法");
    
    // 1. 尝试加载权限辅助模块
    NSString *dylibPath = [[NSBundle mainBundle] pathForResource:@"GPSPrivilegeHelper" ofType:@"dylib"];
    if (dylibPath && [[NSFileManager defaultManager] fileExistsAtPath:dylibPath]) {
        // 添加必要的常量定义，如果系统头文件中不存在
        #ifndef RTLD_NOW
        #define RTLD_NOW 0x2
        #endif
        
        // 使用适当的类型转换，避免编译器警告
        void *handle = dlopen([dylibPath UTF8String], RTLD_NOW);
        if (handle) {
            // 使用正确的函数指针声明语法
            typedef BOOL (*privilege_func_t)(void);
            privilege_func_t privilege_func = (privilege_func_t)dlsym(handle, "requestPrivileges");
            
            if (privilege_func) {
                BOOL result = privilege_func();
                dlclose(handle);
                
                if (result) {
                    return YES;
                }
            }
            dlclose(handle);
        }
    }
    
    // 2. 检查已知的权限辅助应用是否安装
    NSArray *helperApps = @[
        @"com.saurik.Cydia",
        @"org.coolstar.SileoStore",
        @"xyz.willy.Zebra",
        @"ru.rejail.filza",
        @"com.pixelomer.trollstorehelper"
    ];
    
    for (NSString *appId in helperApps) {
        NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@://request_permission", appId]];
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            
            // 权限请求已发送，稍后检查
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self checkForPrivileges];
            });
            
            return YES;
        }
    }
    
    // 3. 尝试创建测试文件确认权限
    NSArray *testPaths = @[
        @"/private/var/mobile/GPS_Integration_Test",
        @"/var/mobile/GPS_Integration_Test",
        @"/Library/GPS_Integration_Test"
    ];
    
    for (NSString *path in testPaths) {
        if ([@"test" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            return YES;
        }
    }
    
    return NO;
}

- (void)createRequiredDirectories {
    // 创建应用所需的权限目录
    NSArray *directories = @[
        @"/var/mobile/Library/GPS++",
        @"/var/mobile/Library/GPS++/Profiles",
        @"/var/mobile/Library/GPS++/Cache"
    ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *dir in directories) {
        if (![fileManager fileExistsAtPath:dir]) {
            NSError *error = nil;
            [fileManager createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&error];
            
            if (error) {
                NSLog(@"创建目录失败 %@: %@", dir, error);
            }
        }
    }
}

- (void)applyIntegrationPrioritySettings {
    switch (self.integrationPriority) {
        case 5: // 最高优先级
            self.maxConcurrentApps = 10;
            break;
        case 4:
            self.maxConcurrentApps = 8;
            break;
        case 3: // 默认
            self.maxConcurrentApps = 5;
            break;
        case 2:
            self.maxConcurrentApps = 3;
            break;
        case 1: // 最低优先级
            self.maxConcurrentApps = 1;
            break;
        default:
            self.maxConcurrentApps = 3;
            break;
    }
    
    NSLog(@"应用集成优先级已设置为 %ld，最大并发应用数: %ld", 
          (long)self.integrationPriority, (long)self.maxConcurrentApps);
}
@end