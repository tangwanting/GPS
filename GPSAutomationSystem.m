/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSAutomationSystem.h"
#import <UserNotifications/UserNotifications.h>

#pragma mark - GPSTriggerCondition Implementation

@implementation GPSTriggerCondition

- (instancetype)init {
    if (self = [super init]) {
        _type = GPSTriggerTypeManual;
        _parameters = @{};
    }
    return self;
}

- (BOOL)evaluateWithContext:(NSDictionary *)context {
    if (!context) return NO;
    
    switch (self.type) {
        case GPSTriggerTypeTime: {
            // 检查是否到达指定时间
            NSDate *targetTime = self.parameters[@"time"];
            NSDate *currentTime = [NSDate date];
            
            if ([self.parameters[@"repeating"] boolValue]) {
                NSDateComponents *targetComponents = [[NSCalendar currentCalendar] 
                                                    components:(NSCalendarUnitHour | NSCalendarUnitMinute) 
                                                    fromDate:targetTime];
                NSDateComponents *currentComponents = [[NSCalendar currentCalendar] 
                                                     components:(NSCalendarUnitHour | NSCalendarUnitMinute) 
                                                     fromDate:currentTime];
                
                return (targetComponents.hour == currentComponents.hour && 
                        targetComponents.minute == currentComponents.minute);
            } else {
                return ([currentTime timeIntervalSinceDate:targetTime] >= 0);
            }
        }
            
        case GPSTriggerTypeLocation: {
            // 检查是否达到特定位置
            CLLocation *targetLocation = [[CLLocation alloc] 
                                         initWithLatitude:[self.parameters[@"latitude"] doubleValue] 
                                         longitude:[self.parameters[@"longitude"] doubleValue]];
            
            CLLocation *currentLocation = context[@"currentLocation"];
            if (!currentLocation) return NO;
            
            double threshold = [self.parameters[@"threshold"] doubleValue];
            if (threshold <= 0) threshold = 100.0; // 默认100米
            
            return [currentLocation distanceFromLocation:targetLocation] <= threshold;
        }
            
        case GPSTriggerTypeDistance: {
            // 检查是否移动了指定距离
            NSNumber *startDistance = context[@"startDistance"];
            NSNumber *currentDistance = context[@"currentDistance"];
            double targetDistance = [self.parameters[@"distance"] doubleValue];
            
            if (!startDistance || !currentDistance) return NO;
            
            return ([currentDistance doubleValue] - [startDistance doubleValue]) >= targetDistance;
        }
            
        case GPSTriggerTypeProximity: {
            // 检查是否接近指定的点
            NSArray<NSDictionary *> *points = self.parameters[@"points"];
            CLLocation *currentLocation = context[@"currentLocation"];
            double threshold = [self.parameters[@"threshold"] doubleValue];
            
            if (!points || !currentLocation || points.count == 0) return NO;
            if (threshold <= 0) threshold = 50.0; // 默认50米
            
            for (NSDictionary *point in points) {
                CLLocation *pointLocation = [[CLLocation alloc] 
                                           initWithLatitude:[point[@"latitude"] doubleValue] 
                                           longitude:[point[@"longitude"] doubleValue]];
                
                if ([currentLocation distanceFromLocation:pointLocation] <= threshold) {
                    return YES;
                }
            }
            return NO;
        }
            
        case GPSTriggerTypeGeofence: {
            // 检查是否进入/离开地理围栏
            NSString *geofenceId = self.parameters[@"geofenceId"];
            NSString *eventType = self.parameters[@"eventType"]; // "enter" 或 "exit"
            
            NSDictionary *geofenceEvent = context[@"geofenceEvent"];
            if (!geofenceEvent) return NO;
            
            BOOL matchId = [geofenceEvent[@"geofenceId"] isEqualToString:geofenceId];
            BOOL matchEvent = [geofenceEvent[@"eventType"] isEqualToString:eventType];
            
            return (matchId && matchEvent);
        }
            
        case GPSTriggerTypeSpeed: {
            // 检查速度是否达到阈值
            CLLocation *currentLocation = context[@"currentLocation"];
            if (!currentLocation) return NO;
            
            double minSpeed = [self.parameters[@"minSpeed"] doubleValue];
            double maxSpeed = [self.parameters[@"maxSpeed"] doubleValue];
            
            double currentSpeed = currentLocation.speed;
            
            // 处理无效速度值
            if (currentSpeed < 0) return NO;
            
            // 检查速度是否在指定范围内
            if (minSpeed > 0 && maxSpeed > 0) {
                return (currentSpeed >= minSpeed && currentSpeed <= maxSpeed);
            } else if (minSpeed > 0) {
                return (currentSpeed >= minSpeed);
            } else if (maxSpeed > 0) {
                return (currentSpeed <= maxSpeed);
            }
            
            return NO;
        }
            
        case GPSTriggerTypeApplication: {
            // 检查应用状态变化
            NSString *targetState = self.parameters[@"state"];
            NSString *currentState = context[@"appState"];
            
            if (!targetState || !currentState) return NO;
            
            return [targetState isEqualToString:currentState];
        }
            
        case GPSTriggerTypeDeviceState: {
            // 检查设备状态
            NSDictionary *deviceStates = self.parameters[@"states"];
            NSDictionary *currentDeviceState = context[@"deviceState"];
            
            if (!deviceStates || !currentDeviceState) return NO;
            
            for (NSString *key in deviceStates) {
                if (![deviceStates[key] isEqual:currentDeviceState[key]]) {
                    return NO;
                }
            }
            
            return YES;
        }
            
        case GPSTriggerTypeManual:
            // 手动触发
            return [context[@"manualTrigger"] boolValue] && 
                   [context[@"triggerId"] isEqualToString:self.parameters[@"id"]];
            
        default:
            return NO;
    }
}

@end

#pragma mark - GPSAction Implementation

@implementation GPSAction

- (instancetype)init {
    if (self = [super init]) {
        _type = GPSActionTypeNotification;
        _parameters = @{};
    }
    return self;
}

- (BOOL)executeWithContext:(NSDictionary *)context error:(NSError **)error {
    if (!context) {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSAutomationDomain" 
                                        code:100 
                                    userInfo:@{NSLocalizedDescriptionKey: @"无效的上下文"}];
        }
        return NO;
    }
    
    switch (self.type) {
        case GPSActionTypeChangeLocation: {
            // 改变位置
            double latitude = [self.parameters[@"latitude"] doubleValue];
            double longitude = [self.parameters[@"longitude"] doubleValue];
            
            // 使用通知中心发送位置更改通知
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:@"GPSLocationChangeRequested"
                            object:nil 
                          userInfo:@{@"latitude": @(latitude), @"longitude": @(longitude)}];
            return YES;
        }
            
        case GPSActionTypeStartRoute: {
            // 开始路线
            NSString *routeId = self.parameters[@"routeId"];
            if (!routeId) {
                if (error) {
                    *error = [NSError errorWithDomain:@"GPSAutomationDomain" 
                                                code:101 
                                            userInfo:@{NSLocalizedDescriptionKey: @"未指定路线ID"}];
                }
                return NO;
            }
            
            // 使用通知中心发送开始路线通知
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:@"GPSStartRouteRequested" 
                            object:nil 
                          userInfo:@{@"routeId": routeId}];
            return YES;
        }
            
        case GPSActionTypeStopRoute: {
            // 停止路线
            // 使用通知中心发送停止路线通知
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:@"GPSStopRouteRequested" 
                            object:nil];
            return YES;
        }
            
        case GPSActionTypeSaveLocation: {
            // 保存位置
            CLLocation *currentLocation = context[@"currentLocation"];
            if (!currentLocation) {
                if (error) {
                    *error = [NSError errorWithDomain:@"GPSAutomationDomain" 
                                                code:102 
                                            userInfo:@{NSLocalizedDescriptionKey: @"无法获取当前位置"}];
                }
                return NO;
            }
            
            NSString *title = self.parameters[@"title"] ?: @"自动保存的位置";
            NSString *desc = self.parameters[@"description"] ?: @"";
            
            NSDictionary *locationData = @{
                @"latitude": @(currentLocation.coordinate.latitude),
                @"longitude": @(currentLocation.coordinate.longitude),
                @"title": title,
                @"description": desc,
                @"timestamp": [NSDate date]
            };
            
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:@"GPSSaveLocationRequested" 
                            object:nil 
                          userInfo:locationData];
            return YES;
        }
            
        case GPSActionTypeExportData: {
            // 导出数据
            NSString *format = self.parameters[@"format"] ?: @"csv";
            NSString *type = self.parameters[@"type"] ?: @"route";
            
            NSDictionary *exportData = @{
                @"format": format,
                @"type": type,
                @"options": self.parameters[@"options"] ?: @{}
            };
            
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:@"GPSExportDataRequested" 
                            object:nil 
                          userInfo:exportData];
            return YES;
        }
            
        case GPSActionTypeNotification: {
            // 发送通知
            NSString *title = self.parameters[@"title"] ?: @"GPS++ 通知";
            NSString *body = self.parameters[@"body"] ?: @"自动化规则已触发";
            
            UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
            content.title = title;
            content.body = body;
            content.sound = [UNNotificationSound defaultSound];
            
            UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger 
                                                        triggerWithTimeInterval:1 
                                                                      repeats:NO];
            
            NSString *requestId = [[NSUUID UUID] UUIDString];
            UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:requestId
                                                                                content:content 
                                                                                trigger:trigger];
            
            [[UNUserNotificationCenter currentNotificationCenter] 
                addNotificationRequest:request 
                 withCompletionHandler:^(NSError *err) {
                    if (err) {
                        NSLog(@"发送通知失败: %@", err);
                    }
                }];
            return YES;
        }
            
        case GPSActionTypeChangeSettings: {
            // 修改设置
            NSDictionary *settings = self.parameters[@"settings"];
            if (!settings) {
                if (error) {
                    *error = [NSError errorWithDomain:@"GPSAutomationDomain" 
                                                code:103 
                                            userInfo:@{NSLocalizedDescriptionKey: @"没有指定要更改的设置"}];
                }
                return NO;
            }
            
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:@"GPSChangeSettingsRequested" 
                            object:nil 
                          userInfo:@{@"settings": settings}];
            return YES;
        }
            
        case GPSActionTypeRunScript: {
            // 运行自定义脚本
            NSString *scriptId = self.parameters[@"scriptId"];
            if (!scriptId) {
                if (error) {
                    *error = [NSError errorWithDomain:@"GPSAutomationDomain" 
                                                code:104 
                                            userInfo:@{NSLocalizedDescriptionKey: @"未指定脚本ID"}];
                }
                return NO;
            }
            
            NSDictionary *parameters = self.parameters[@"parameters"] ?: @{};
            NSDictionary *scriptData = @{
                @"scriptId": scriptId,
                @"parameters": parameters,
                @"context": context
            };
            
            [[NSNotificationCenter defaultCenter] 
                postNotificationName:@"GPSRunScriptRequested" 
                            object:nil 
                          userInfo:scriptData];
            return YES;
        }
            
        case GPSActionTypeCallWebhook: {
            // 调用webhook
            NSURL *url = [NSURL URLWithString:self.parameters[@"url"]];
            if (!url) {
                if (error) {
                    *error = [NSError errorWithDomain:@"GPSAutomationDomain" 
                                                code:105 
                                            userInfo:@{NSLocalizedDescriptionKey: @"无效的URL"}];
                }
                return NO;
            }
            
            NSString *method = self.parameters[@"method"] ?: @"POST";
            NSDictionary *payload = self.parameters[@"payload"] ?: @{};
            
            // 创建请求
            NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
            [request setHTTPMethod:method];
            [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
            
            NSError *jsonError;
            NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload 
                                                             options:0 
                                                               error:&jsonError];
            if (jsonError) {
                if (error) {
                    *error = jsonError;
                }
                return NO;
            }
            
            [request setHTTPBody:jsonData];
            
            NSURLSession *session = [NSURLSession sharedSession];
            NSURLSessionDataTask *task = [session dataTaskWithRequest:request 
                                                   completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
                if (err) {
                    NSLog(@"Webhook调用失败: %@", err);
                }
            }];
            
            [task resume];
            return YES;
        }
            
        default:
            if (error) {
                *error = [NSError errorWithDomain:@"GPSAutomationDomain" 
                                            code:106 
                                        userInfo:@{NSLocalizedDescriptionKey: @"不支持的动作类型"}];
            }
            return NO;
    }
}

@end

#pragma mark - GPSAutomationRule Implementation

@interface GPSAutomationRule ()
@end

@implementation GPSAutomationRule

- (instancetype)init {
    if (self = [super init]) {
        _identifier = [[NSUUID UUID] UUIDString];
        _name = @"新规则";
        self.description = @"";
        _condition = [[GPSTriggerCondition alloc] init];
        _actions = @[];
        _enabled = YES;
        _oneTime = NO;
        _createdAt = [NSDate date];
        _lastTriggeredAt = nil;
        _triggerCount = 0;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"Rule: %@ (id: %@, enabled: %@, triggered: %lu times)", 
            self.name, self.identifier, self.enabled ? @"YES" : @"NO", (unsigned long)self.triggerCount];
}

@end

#pragma mark - GPSAutomationSystem Implementation

@interface GPSAutomationSystem ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, GPSAutomationRule *> *rules;
@property (nonatomic, strong) NSTimer *evaluationTimer;
@property (nonatomic, strong) dispatch_queue_t ruleQueue;
@end

@implementation GPSAutomationSystem

#pragma mark - Singleton Implementation

+ (instancetype)sharedInstance {
    static GPSAutomationSystem *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _rules = [NSMutableDictionary dictionary];
        _ruleQueue = dispatch_queue_create("com.gps.automation.ruleQueue", DISPATCH_QUEUE_SERIAL);
        
        [self loadRules];
        
        // 注册观察位置更新的通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(handleLocationUpdate:)
                                                   name:@"GPSLocationDidUpdate" 
                                                 object:nil];
        
        // 注册观察应用状态变化的通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                               selector:@selector(handleAppStateChange:)
                                                   name:@"GPSAppStateDidChange" 
                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.evaluationTimer invalidate];
}

#pragma mark - Rule Management

- (NSString *)addRule:(GPSAutomationRule *)rule {
    if (!rule) return nil;
    
    if (!rule.identifier) {
        rule.identifier = [[NSUUID UUID] UUIDString];
    }
    
    dispatch_sync(self.ruleQueue, ^{
        self.rules[rule.identifier] = rule;
    });
    
    [self saveRules];
    
    return rule.identifier;
}

- (BOOL)updateRule:(GPSAutomationRule *)rule {
    if (!rule || !rule.identifier) return NO;
    
    __block BOOL exists = NO;
    
    dispatch_sync(self.ruleQueue, ^{
        exists = (self.rules[rule.identifier] != nil);
        if (exists) {
            self.rules[rule.identifier] = rule;
        }
    });
    
    if (exists) {
        [self saveRules];
    }
    
    return exists;
}

- (BOOL)removeRuleWithIdentifier:(NSString *)identifier {
    if (!identifier) return NO;
    
    __block BOOL exists = NO;
    
    dispatch_sync(self.ruleQueue, ^{
        exists = (self.rules[identifier] != nil);
        if (exists) {
            [self.rules removeObjectForKey:identifier];
        }
    });
    
    if (exists) {
        [self saveRules];
    }
    
    return exists;
}

- (void)enableRuleWithIdentifier:(NSString *)identifier {
    if (!identifier) return;
    
    dispatch_sync(self.ruleQueue, ^{
        GPSAutomationRule *rule = self.rules[identifier];
        if (rule) {
            rule.enabled = YES;
        }
    });
    
    [self saveRules];
}

- (void)disableRuleWithIdentifier:(NSString *)identifier {
    if (!identifier) return;
    
    dispatch_sync(self.ruleQueue, ^{
        GPSAutomationRule *rule = self.rules[identifier];
        if (rule) {
            rule.enabled = NO;
        }
    });
    
    [self saveRules];
}

- (NSArray<GPSAutomationRule *> *)allRules {
    __block NSArray *allRules = nil;
    
    dispatch_sync(self.ruleQueue, ^{
        allRules = [self.rules.allValues copy];
    });
    
    return allRules;
}

- (GPSAutomationRule *)ruleWithIdentifier:(NSString *)identifier {
    if (!identifier) return nil;
    
    __block GPSAutomationRule *rule = nil;
    
    dispatch_sync(self.ruleQueue, ^{
        rule = self.rules[identifier];
    });
    
    return rule;
}

#pragma mark - Rule Execution

- (void)evaluateRulesWithContext:(NSDictionary *)context {
    if (!context) return;
    
    dispatch_async(self.ruleQueue, ^{
        for (GPSAutomationRule *rule in self.rules.allValues) {
            if (!rule.enabled) continue;
            
            // 评估规则条件
            if ([rule.condition evaluateWithContext:context]) {
                // 条件满足，执行动作
                [self executeActionsForRule:rule withContext:context];
                
                // 更新规则触发信息
                rule.lastTriggeredAt = [NSDate date];
                rule.triggerCount++;
                
                // 如果是一次性规则，禁用它
                if (rule.oneTime) {
                    rule.enabled = NO;
                }
            }
        }
        
        [self saveRules];
    });
}

- (void)executeActionsForRule:(GPSAutomationRule *)rule withContext:(NSDictionary *)context {
    for (GPSAction *action in rule.actions) {
        NSError *error = nil;
        BOOL success = [action executeWithContext:context error:&error];
        
        if (!success && error) {
            NSLog(@"执行规则'%@'的动作失败: %@", rule.name, error);
        }
    }
}

- (void)manuallyTriggerRuleWithIdentifier:(NSString *)identifier {
    if (!identifier) return;
    
    GPSAutomationRule *rule = [self ruleWithIdentifier:identifier];
    if (!rule || !rule.enabled) return;
    
    NSDictionary *context = @{
        @"manualTrigger": @YES,
        @"triggerId": identifier,
        @"timestamp": [NSDate date]
    };
    
    dispatch_async(self.ruleQueue, ^{
        [self executeActionsForRule:rule withContext:context];
        
        // 更新规则触发信息
        rule.lastTriggeredAt = [NSDate date];
        rule.triggerCount++;
        
        // 如果是一次性规则，禁用它
        if (rule.oneTime) {
            rule.enabled = NO;
        }
        
        [self saveRules];
    });
}

- (void)scheduleRuleEvaluation:(NSTimeInterval)interval {
    [self.evaluationTimer invalidate];
    
    if (interval <= 0) return;
    
    self.evaluationTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                          target:self
                                                        selector:@selector(timerEvaluateRules)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)timerEvaluateRules {
    NSDictionary *context = @{
        @"timestamp": [NSDate date],
        @"source": @"timer"
    };
    
    [self evaluateRulesWithContext:context];
}

#pragma mark - Import/Export

- (NSData *)exportRulesAsJSON {
    __block NSArray *ruleDicts = @[];
    
    dispatch_sync(self.ruleQueue, ^{
        NSMutableArray *tempArray = [NSMutableArray array];
        
        for (GPSAutomationRule *rule in self.rules.allValues) {
            NSMutableDictionary *ruleDict = [NSMutableDictionary dictionary];
            
            // 基本信息
            ruleDict[@"identifier"] = rule.identifier;
            ruleDict[@"name"] = rule.name;
            ruleDict[@"description"] = rule.description;
            ruleDict[@"enabled"] = @(rule.enabled);
            ruleDict[@"oneTime"] = @(rule.oneTime);
            ruleDict[@"triggerCount"] = @(rule.triggerCount);
            
            // 日期
            NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
            formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
            
            if (rule.createdAt) {
                ruleDict[@"createdAt"] = [formatter stringFromDate:rule.createdAt];
            }
            
            if (rule.lastTriggeredAt) {
                ruleDict[@"lastTriggeredAt"] = [formatter stringFromDate:rule.lastTriggeredAt];
            }
            
            // 条件
            if (rule.condition) {
                ruleDict[@"condition"] = @{
                    @"type": @(rule.condition.type),
                    @"parameters": rule.condition.parameters ?: @{}
                };
            }
            
            // 动作
            if (rule.actions.count > 0) {
                NSMutableArray *actionDicts = [NSMutableArray array];
                for (GPSAction *action in rule.actions) {
                    [actionDicts addObject:@{
                        @"type": @(action.type),
                        @"parameters": action.parameters ?: @{}
                    }];
                }
                ruleDict[@"actions"] = actionDicts;
            }
            
            [tempArray addObject:ruleDict];
        }
        
        ruleDicts = [tempArray copy];
    });
    
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:ruleDicts options:NSJSONWritingPrettyPrinted error:&error];
    
    if (error) {
        NSLog(@"规则导出为JSON失败: %@", error);
        return nil;
    }
    
    return jsonData;
}

- (BOOL)importRulesFromJSON:(NSData *)jsonData error:(NSError **)error {
    if (!jsonData) {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSAutomationDomain" 
                                        code:200 
                                    userInfo:@{NSLocalizedDescriptionKey: @"无效的JSON数据"}];
        }
        return NO;
    }
    
    NSError *parseError = nil;
    NSArray *ruleDicts = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&parseError];
    
    if (parseError) {
        if (error) {
            *error = parseError;
        }
        return NO;
    }
    
    if (![ruleDicts isKindOfClass:[NSArray class]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSAutomationDomain" 
                                        code:201 
                                    userInfo:@{NSLocalizedDescriptionKey: @"无效的JSON格式，应为数组"}];
        }
        return NO;
    }
    
    NSMutableDictionary *importedRules = [NSMutableDictionary dictionary];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    
    for (NSDictionary *ruleDict in ruleDicts) {
        GPSAutomationRule *rule = [[GPSAutomationRule alloc] init];
        
        // 基本信息
        rule.identifier = ruleDict[@"identifier"] ?: [[NSUUID UUID] UUIDString];
        rule.name = ruleDict[@"name"] ?: @"导入的规则";
        rule.description = ruleDict[@"description"] ?: @"";
        rule.enabled = [ruleDict[@"enabled"] boolValue];
        rule.oneTime = [ruleDict[@"oneTime"] boolValue];
        rule.triggerCount = [ruleDict[@"triggerCount"] unsignedIntegerValue];
        
        // 日期
        NSString *createdAtStr = ruleDict[@"createdAt"];
        if (createdAtStr) {
            rule.createdAt = [formatter dateFromString:createdAtStr] ?: [NSDate date];
        }
        
        NSString *lastTriggeredAtStr = ruleDict[@"lastTriggeredAt"];
        if (lastTriggeredAtStr) {
            rule.lastTriggeredAt = [formatter dateFromString:lastTriggeredAtStr];
        }
        
        // 条件
        NSDictionary *conditionDict = ruleDict[@"condition"];
        if (conditionDict) {
            GPSTriggerCondition *condition = [[GPSTriggerCondition alloc] init];
            condition.type = [conditionDict[@"type"] integerValue];
            condition.parameters = conditionDict[@"parameters"] ?: @{};
            rule.condition = condition;
        }
        
        // 动作
        NSArray *actionDicts = ruleDict[@"actions"];
        if (actionDicts.count > 0) {
            NSMutableArray *actions = [NSMutableArray array];
            for (NSDictionary *actionDict in actionDicts) {
                GPSAction *action = [[GPSAction alloc] init];
                action.type = [actionDict[@"type"] integerValue];
                action.parameters = actionDict[@"parameters"] ?: @{};
                [actions addObject:action];
            }
            rule.actions = actions;
        }
        
        importedRules[rule.identifier] = rule;
    }
    
    dispatch_sync(self.ruleQueue, ^{
        // 将导入的规则与现有规则合并
        [self.rules addEntriesFromDictionary:importedRules];
    });
    
    [self saveRules];
    return YES;
}

#pragma mark - Persistence

- (void)loadRules {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSData *rulesData = [defaults objectForKey:@"GPSAutomationRules"];
    
    if (rulesData) {
        NSError *error = nil;
        [self importRulesFromJSON:rulesData error:&error];
        
        if (error) {
            NSLog(@"加载规则失败: %@", error);
        }
    }
}

- (void)saveRules {
    NSData *rulesData = [self exportRulesAsJSON];
    if (rulesData) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setObject:rulesData forKey:@"GPSAutomationRules"];
        [defaults synchronize];
    }
}

#pragma mark - Notification Handlers

- (void)handleLocationUpdate:(NSNotification *)notification {
    CLLocation *location = notification.userInfo[@"location"];
    if (!location) return;
    
    NSDictionary *context = @{
        @"currentLocation": location,
        @"timestamp": [NSDate date],
        @"source": @"locationUpdate"
    };
    
    [self evaluateRulesWithContext:context];
}

- (void)handleAppStateChange:(NSNotification *)notification {
    NSString *appState = notification.userInfo[@"state"];
    if (!appState) return;
    
    NSDictionary *context = @{
        @"appState": appState,
        @"timestamp": [NSDate date],
        @"source": @"appStateChange"
    };
    
    [self evaluateRulesWithContext:context];
}

@end