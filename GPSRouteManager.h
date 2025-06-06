/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "GPSLocationModel.h"

@interface GPSRouteManager : NSObject

+ (instancetype)sharedInstance;

// 导入GPX路线文件
- (NSArray<GPSLocationModel *> *)importGPXFromPath:(NSString *)filePath error:(NSError **)error;

// 导出路线为GPX格式
- (BOOL)exportRoute:(NSArray<GPSLocationModel *> *)route toPath:(NSString *)filePath name:(NSString *)name error:(NSError **)error;

// 获取存储的路线列表
- (NSArray<NSString *> *)savedRouteNames;

// 保存路线
- (BOOL)saveRoute:(NSArray<GPSLocationModel *> *)route withName:(NSString *)name error:(NSError **)error;

// 加载指定名称的路线
- (NSArray<GPSLocationModel *> *)loadRouteWithName:(NSString *)name error:(NSError **)error;

// 删除路线
- (BOOL)deleteRouteWithName:(NSString *)name error:(NSError **)error;

// 获取指定路线名称的数据
- (NSData *)dataForRouteName:(NSString *)routeName;

@end