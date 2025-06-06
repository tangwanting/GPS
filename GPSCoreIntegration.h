/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>

@protocol GPSEventListener;

@interface GPSCoreIntegration : NSObject <GPSEventListener>

/**
 * 获取共享实例
 * @return GPSCoreIntegration单例
 */
+ (instancetype)sharedInstance;

/**
 * 初始化所有GPS功能模块
 */
- (void)setupAllModules;

/**
 * 启动所有模块
 */
- (void)startAllModules;

/**
 * 暂停所有非关键模块，用于应用进入后台时节省资源
 */
- (void)pauseAllModules;

/**
 * 关闭并清理所有模块，用于应用终止时
 */
- (void)tearDownAllModules;

@end