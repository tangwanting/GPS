/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "GPSLocationModel.h"

// 触发条件类型
typedef NS_ENUM(NSInteger, GPSTriggerType) {
    GPSTriggerTypeTime,                // 特定时间触发
    GPSTriggerTypeLocation,            // 到达特定位置触发
    GPSTriggerTypeDistance,            // 移动特定距离触发
    GPSTriggerTypeProximity,           // 接近特定点位触发
    GPSTriggerTypeGeofence,            // 进出地理围栏触发
    GPSTriggerTypeSpeed,               // 速度达到阈值触发
    GPSTriggerTypeApplication,         // 应用状态变化触发
    GPSTriggerTypeDeviceState,         // 设备状态变化触发
    GPSTriggerTypeManual               // 手动触发
};

// 动作类型
typedef NS_ENUM(NSInteger, GPSActionType) {
    GPSActionTypeChangeLocation,       // 改变位置
    GPSActionTypeStartRoute,           // 开始路线
    GPSActionTypeStopRoute,            // 停止路线
    GPSActionTypeSaveLocation,         // 保存位置
    GPSActionTypeExportData,           // 导出数据
    GPSActionTypeNotification,         // 发送通知
    GPSActionTypeChangeSettings,       // 修改设置
    GPSActionTypeRunScript,            // 运行自定义脚本
    GPSActionTypeCallWebhook           // 调用webhook
};

@interface GPSTriggerCondition : NSObject
@property (nonatomic, assign) GPSTriggerType type;
@property (nonatomic, strong) NSDictionary *parameters;
- (BOOL)evaluateWithContext:(NSDictionary *)context;
@end

@interface GPSAction : NSObject
@property (nonatomic, assign) GPSActionType type;
@property (nonatomic, strong) NSDictionary *parameters;
- (BOOL)executeWithContext:(NSDictionary *)context error:(NSError **)error;
@end

@interface GPSAutomationRule : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *description;
@property (nonatomic, strong) GPSTriggerCondition *condition;
@property (nonatomic, strong) NSArray<GPSAction *> *actions;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL oneTime; // 触发一次后自动禁用
@property (nonatomic, strong) NSDate *createdAt;
@property (nonatomic, strong) NSDate *lastTriggeredAt;
@property (nonatomic, assign) NSUInteger triggerCount;
@end

@interface GPSAutomationSystem : NSObject

+ (instancetype)sharedInstance;

// 规则管理
- (NSString *)addRule:(GPSAutomationRule *)rule;
- (BOOL)updateRule:(GPSAutomationRule *)rule;
- (BOOL)removeRuleWithIdentifier:(NSString *)identifier;
- (void)enableRuleWithIdentifier:(NSString *)identifier;
- (void)disableRuleWithIdentifier:(NSString *)identifier;
- (NSArray<GPSAutomationRule *> *)allRules;
- (GPSAutomationRule *)ruleWithIdentifier:(NSString *)identifier;

// 规则执行
- (void)evaluateRulesWithContext:(NSDictionary *)context;
- (void)manuallyTriggerRuleWithIdentifier:(NSString *)identifier;
- (void)scheduleRuleEvaluation:(NSTimeInterval)interval;

// 导入/导出
- (NSData *)exportRulesAsJSON;
- (BOOL)importRulesFromJSON:(NSData *)jsonData error:(NSError **)error;

@end