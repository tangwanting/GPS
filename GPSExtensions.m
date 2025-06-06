/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSExtensions.h"
#import "GPSSystemIntegration.h"
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <sys/sysctl.h>

@implementation GPSSystemIntegration (AdditionalMethods)

- (void)enableContinuousBackgroundMode:(BOOL)enable {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:enable forKey:@"GPSContinuousBackgroundMode"];
    [defaults synchronize];
    
    NSLog(@"连续后台模式已%@", enable ? @"启用" : @"禁用");
}

- (void)clearCachedData {
    // 清理缓存目录
    NSArray *cachePaths = @[
        [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject 
         stringByAppendingPathComponent:@"GPSLocationCache"],
        [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject 
         stringByAppendingPathComponent:@"GPSSimulationCache"]
    ];
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *path in cachePaths) {
        if ([fileManager fileExistsAtPath:path]) {
            NSError *error;
            [fileManager removeItemAtPath:path error:&error];
            if (error) {
                NSLog(@"清理缓存失败: %@", error);
            }
        }
    }
    
    NSLog(@"已清理所有缓存数据");
}

- (void)runSystemDiagnostics:(void (^)(NSDictionary *results))completionHandler {
    // 创建诊断结果字典
    NSMutableDictionary *results = [NSMutableDictionary dictionary];
    
    // 获取系统版本
    results[@"systemVersion"] = [UIDevice currentDevice].systemVersion;
    
    // 检查集成状态
    results[@"integrationStatus"] = @([self isDeviceJailbroken] || [self checkForPrivileges]);
    
    // 内存使用
    unsigned long long freeMemory = [self getFreeMem];
    double memoryInMB = freeMemory / (1024.0 * 1024.0);
    results[@"memoryUsage"] = [NSString stringWithFormat:@"%.2f", memoryInMB];
    
    // CPU使用
    results[@"cpuUsage"] = [NSString stringWithFormat:@"%.1f", [self getCPUUsage]];
    
    // 电池状态
    UIDevice *device = [UIDevice currentDevice];
    device.batteryMonitoringEnabled = YES;
    
    NSString *batteryStatus;
    switch (device.batteryState) {
        case UIDeviceBatteryStateUnknown:
            batteryStatus = @"未知";
            break;
        case UIDeviceBatteryStateUnplugged:
            batteryStatus = [NSString stringWithFormat:@"未充电 (%d%%)", (int)(device.batteryLevel * 100)];
            break;
        case UIDeviceBatteryStateCharging:
            batteryStatus = [NSString stringWithFormat:@"充电中 (%d%%)", (int)(device.batteryLevel * 100)];
            break;
        case UIDeviceBatteryStateFull:
            batteryStatus = @"已充满";
            break;
    }
    
    results[@"batteryStatus"] = batteryStatus;
    device.batteryMonitoringEnabled = NO;
    
    // 存储空间
    NSDictionary *fileSystemAttrs = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    unsigned long long totalSpace = [[fileSystemAttrs objectForKey:NSFileSystemSize] unsignedLongLongValue];
    unsigned long long freeSpace = [[fileSystemAttrs objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
    double freeSpaceInMB = freeSpace / (1024.0 * 1024.0);
    
    results[@"availableStorage"] = [NSString stringWithFormat:@"%.2f", freeSpaceInMB];
    
    if (completionHandler) {
        completionHandler(results);
    }
}

#pragma mark - 辅助方法

// 获取可用内存
- (unsigned long long)getFreeMem {
    vm_statistics_data_t vmStats;
    mach_msg_type_number_t infoCount = HOST_VM_INFO_COUNT;
    kern_return_t kernReturn = host_statistics(mach_host_self(), HOST_VM_INFO, (host_info_t)&vmStats, &infoCount);
    
    if (kernReturn != KERN_SUCCESS) {
        return 0;
    }
    
    return vm_page_size * (vmStats.free_count + vmStats.inactive_count);
}

// 获取CPU使用率
- (float)getCPUUsage {
    kern_return_t kr;
    task_info_data_t tinfo;
    mach_msg_type_number_t task_info_count;
    
    task_info_count = TASK_INFO_MAX;
    kr = task_info(mach_task_self(), TASK_BASIC_INFO, (task_info_t)tinfo, &task_info_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    task_basic_info_t basic_info;
    thread_array_t thread_list;
    mach_msg_type_number_t thread_count;
    
    thread_info_data_t thinfo;
    mach_msg_type_number_t thread_info_count;
    
    basic_info = (task_basic_info_t)tinfo;
    
    // 获取线程列表
    kr = task_threads(mach_task_self(), &thread_list, &thread_count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }
    
    long total_time = 0;
    long total_userTime = 0;
    long total_systemTime = 0;
    
    // 遍历所有线程
    for (int i = 0; i < thread_count; i++) {
        thread_info_count = THREAD_INFO_MAX;
        kr = thread_info(thread_list[i], THREAD_BASIC_INFO, (thread_info_t)thinfo, &thread_info_count);
        if (kr != KERN_SUCCESS) {
            continue;
        }
        
        thread_basic_info_t basic_info_th = (thread_basic_info_t)thinfo;
        
        if (!(basic_info_th->flags & TH_FLAGS_IDLE)) {
            total_time += basic_info_th->user_time.seconds + basic_info_th->system_time.seconds;
        }
    }
    
    // 清理内存
    vm_deallocate(mach_task_self(), (vm_offset_t)thread_list, thread_count * sizeof(thread_t));
    
    // 返回CPU使用率百分比
    return MIN(total_time * 10.0, 100.0); // 简化实现，避免复杂的系统调用
}

@end