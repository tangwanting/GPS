/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSEventSystem.h"

#pragma mark - GPSEventData Implementation

@implementation GPSEventData

- (instancetype)init {
    if (self = [super init]) {
        _timestamp = [NSDate date];
        _metadata = @{};
    }
    return self;
}

- (instancetype)initWithType:(GPSEventType)type payload:(id)payload {
    if (self = [self init]) {
        _type = type;
        _payload = payload;
    }
    return self;
}

- (instancetype)initWithType:(GPSEventType)type payload:(id)payload metadata:(NSDictionary *)metadata {
    if (self = [self initWithType:type payload:payload]) {
        if (metadata) {
            _metadata = [metadata copy];
        }
    }
    return self;
}

- (NSString *)description {
    NSString *typeString;
    switch (_type) {
        case GPSEventTypeLocationChanged: typeString = @"LocationChanged"; break;
        case GPSEventTypeRouteStarted: typeString = @"RouteStarted"; break;
        case GPSEventTypeRoutePaused: typeString = @"RoutePaused"; break;
        case GPSEventTypeRouteStopped: typeString = @"RouteStopped"; break;
        case GPSEventTypeRouteCompleted: typeString = @"RouteCompleted"; break;
        case GPSEventTypeGeofenceEnter: typeString = @"GeofenceEnter"; break;
        case GPSEventTypeGeofenceExit: typeString = @"GeofenceExit"; break;
        case GPSEventTypeSystemStateChanged: typeString = @"SystemStateChanged"; break;
        case GPSEventTypeError: typeString = @"Error"; break;
        default: typeString = @"Unknown"; break;
    }
    
    return [NSString stringWithFormat:@"GPSEvent [%@] at %@ - payload: %@, metadata: %@",
            typeString, _timestamp, _payload, _metadata];
}

@end

#pragma mark - GPSEventSystem Private Interface

@interface GPSEventSystem ()

// 事件监听者映射表，key为事件类型，value为监听者数组
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSHashTable<id<GPSEventListener>> *> *listeners;

// 事件历史记录，key为事件类型，value为事件数据数组
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableArray<GPSEventData *> *> *eventHistory;

// 用于线程安全的队列
@property (nonatomic, strong) dispatch_queue_t eventQueue;

// 历史记录大小限制
@property (nonatomic, assign) NSInteger maxHistorySize;

@end

#pragma mark - GPSEventSystem Implementation

@implementation GPSEventSystem

#pragma mark - Initialization

+ (instancetype)sharedInstance {
    static GPSEventSystem *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _listeners = [NSMutableDictionary dictionary];
        _eventHistory = [NSMutableDictionary dictionary];
        _eventQueue = dispatch_queue_create("com.gps.eventsystem.queue", DISPATCH_QUEUE_SERIAL);
        _maxHistorySize = 100; // 默认每种事件类型保存最多100条历史记录
        
        // 初始化所有事件类型的监听者集合
        for (int i = 0; i <= GPSEventTypeError; i++) {
            _listeners[@(i)] = [NSHashTable weakObjectsHashTable];
            _eventHistory[@(i)] = [NSMutableArray array];
        }
    }
    return self;
}

#pragma mark - Event Subscription Management

- (void)addEventListener:(id<GPSEventListener>)listener forEventTypes:(NSArray<NSNumber *> *)eventTypes {
    if (!listener || !eventTypes || eventTypes.count == 0) {
        return;
    }
    
    dispatch_async(self.eventQueue, ^{
        for (NSNumber *eventType in eventTypes) {
            if (eventType.integerValue >= 0 && eventType.integerValue <= GPSEventTypeError) {
                NSHashTable *listenersForType = self.listeners[eventType];
                if (![listenersForType containsObject:listener]) {
                    [listenersForType addObject:listener];
                }
            }
        }
    });
}

- (void)removeEventListener:(id<GPSEventListener>)listener {
    if (!listener) {
        return;
    }
    
    dispatch_async(self.eventQueue, ^{
        for (NSNumber *eventType in self.listeners.allKeys) {
            NSHashTable *listenersForType = self.listeners[eventType];
            if ([listenersForType containsObject:listener]) {
                [listenersForType removeObject:listener];
            }
        }
    });
}

- (void)removeEventListener:(id<GPSEventListener>)listener forEventType:(GPSEventType)eventType {
    if (!listener || eventType < 0 || eventType > GPSEventTypeError) {
        return;
    }
    
    dispatch_async(self.eventQueue, ^{
        NSHashTable *listenersForType = self.listeners[@(eventType)];
        if ([listenersForType containsObject:listener]) {
            [listenersForType removeObject:listener];
        }
    });
}

#pragma mark - Event Publishing

- (void)publishEvent:(GPSEventType)type withPayload:(id)payload {
    [self publishEvent:type withPayload:payload metadata:nil];
}

- (void)publishEvent:(GPSEventType)type withPayload:(id)payload metadata:(NSDictionary *)metadata {
    if (type < 0 || type > GPSEventTypeError) {
        NSLog(@"尝试发布无效的事件类型: %ld", (long)type);
        return;
    }
    
    GPSEventData *event = [[GPSEventData alloc] initWithType:type payload:payload metadata:metadata];
    
    dispatch_async(self.eventQueue, ^{
        // 存储事件到历史记录
        NSMutableArray *historyForType = self.eventHistory[@(type)];
        [historyForType addObject:event];
        
        // 如果超过最大历史记录数，移除最早的记录
        if (historyForType.count > self.maxHistorySize) {
            [historyForType removeObjectAtIndex:0];
        }
        
        // 通知所有监听此类型事件的监听者
        NSHashTable *listenersForType = [self.listeners[@(type)] copy];
        
        // 在主线程通知监听者
        dispatch_async(dispatch_get_main_queue(), ^{
            for (id<GPSEventListener> listener in listenersForType) {
                if ([listener respondsToSelector:@selector(onEvent:)]) {
                    [listener onEvent:event];
                }
            }
        });
    });
}

#pragma mark - Event History

- (NSArray<GPSEventData *> *)recentEventsOfType:(GPSEventType)type limit:(NSInteger)limit {
    if (type < 0 || type > GPSEventTypeError) {
        return @[];
    }
    
    __block NSArray *result;
    dispatch_sync(self.eventQueue, ^{
        NSMutableArray *historyForType = self.eventHistory[@(type)];
        
        // 如果请求的限制大于历史记录，返回所有记录
        NSInteger effectiveLimit = MIN(limit, historyForType.count);
        if (effectiveLimit <= 0) {
            effectiveLimit = historyForType.count;
        }
        
        // 返回最近的N条记录
        if (effectiveLimit == historyForType.count) {
            result = [historyForType copy];
        } else {
            NSRange range = NSMakeRange(historyForType.count - effectiveLimit, effectiveLimit);
            result = [historyForType subarrayWithRange:range];
        }
    });
    
    return result;
}

- (void)clearEventHistory {
    dispatch_async(self.eventQueue, ^{
        for (NSNumber *eventType in self.eventHistory.allKeys) {
            [self.eventHistory[eventType] removeAllObjects];
        }
    });
}

#pragma mark - Utility Methods

- (void)setMaxHistorySize:(NSInteger)size {
    if (size > 0) {
        dispatch_async(self.eventQueue, ^{
            self.maxHistorySize = size;
            
            // 调整现有历史记录大小
            for (NSNumber *eventType in self.eventHistory.allKeys) {
                NSMutableArray *historyForType = self.eventHistory[eventType];
                while (historyForType.count > size) {
                    [historyForType removeObjectAtIndex:0];
                }
            }
        });
    }
}

- (NSInteger)listenerCountForEventType:(GPSEventType)type {
    if (type < 0 || type > GPSEventTypeError) {
        return 0;
    }
    
    __block NSInteger count = 0;
    dispatch_sync(self.eventQueue, ^{
        count = [self.listeners[@(type)] count];
    });
    
    return count;
}

- (NSInteger)totalEventCount {
    __block NSInteger count = 0;
    dispatch_sync(self.eventQueue, ^{
        for (NSNumber *eventType in self.eventHistory.allKeys) {
            count += [self.eventHistory[eventType] count];
        }
    });
    
    return count;
}

- (NSDictionary<NSNumber *, NSNumber *> *)eventCountsByType {
    __block NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    dispatch_sync(self.eventQueue, ^{
        for (NSNumber *eventType in self.eventHistory.allKeys) {
            counts[eventType] = @([self.eventHistory[eventType] count]);
        }
    });
    
    return counts;
}

#pragma mark - Debug and Testing

- (NSString *)debugDescription {
    __block NSMutableString *description = [NSMutableString string];
    
    dispatch_sync(self.eventQueue, ^{
        [description appendString:@"GPS Event System Status:\n"];
        [description appendFormat:@"Max History Size: %ld\n", (long)self.maxHistorySize];
        [description appendString:@"Listener Counts:\n"];
        
        for (int i = 0; i <= GPSEventTypeError; i++) {
            NSString *eventName;
            switch (i) {
                case GPSEventTypeLocationChanged: eventName = @"LocationChanged"; break;
                case GPSEventTypeRouteStarted: eventName = @"RouteStarted"; break;
                case GPSEventTypeRoutePaused: eventName = @"RoutePaused"; break;
                case GPSEventTypeRouteStopped: eventName = @"RouteStopped"; break;
                case GPSEventTypeRouteCompleted: eventName = @"RouteCompleted"; break;
                case GPSEventTypeGeofenceEnter: eventName = @"GeofenceEnter"; break;
                case GPSEventTypeGeofenceExit: eventName = @"GeofenceExit"; break;
                case GPSEventTypeSystemStateChanged: eventName = @"SystemStateChanged"; break;
                case GPSEventTypeError: eventName = @"Error"; break;
                default: eventName = @"Unknown"; break;
            }
            
            [description appendFormat:@"  %@: %ld listeners, %ld events\n", 
                eventName, 
                (long)[self.listeners[@(i)] count],
                (long)[self.eventHistory[@(i)] count]];
        }
    });
    
    return description;
}

@end