/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSAnalyticsSystem.h"
#import <UIKit/UIKit.h>
#import "GPSCoordinateUtils.h"

#pragma mark - GPSAnalyticsSummary 实现

@implementation GPSAnalyticsSummary

- (instancetype)init {
    if (self = [super init]) {
        _totalDistance = 0;
        _totalDuration = 0;
        _averageSpeed = 0;
        _maxSpeed = 0;
        _minSpeed = DBL_MAX;
        _averageAltitude = 0;
        _maxAltitude = -DBL_MAX;
        _minAltitude = DBL_MAX;
        _totalAscent = 0;
        _totalDescent = 0;
        _startTime = nil;
        _endTime = nil;
        _pauseCount = 0;
        _pauseDuration = 0;
        _pointCount = 0;
        _customMetrics = @{};
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"总距离: %.2f 米, 总时间: %.2f 秒, 平均速度: %.2f m/s, 最高速度: %.2f m/s, "
            "总上升: %.2f 米, 总下降: %.2f 米, 点数: %ld", 
            self.totalDistance, self.totalDuration, self.averageSpeed, self.maxSpeed, 
            self.totalAscent, self.totalDescent, (long)self.pointCount];
}

@end

#pragma mark - GPSSpeedSegment 实现

@implementation GPSSpeedSegment

- (instancetype)init {
    if (self = [super init]) {
        _startDistance = 0;
        _endDistance = 0;
        _duration = 0;
        _averageSpeed = 0;
        _startPoint = nil;
        _endPoint = nil;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"距离: %.2f-%.2f 米, 时长: %.2f 秒, 平均速度: %.2f m/s", 
            self.startDistance, self.endDistance, self.duration, self.averageSpeed];
}

@end

#pragma mark - GPSElevationSegment 实现

@implementation GPSElevationSegment

- (instancetype)init {
    if (self = [super init]) {
        _startDistance = 0;
        _endDistance = 0;
        _startAltitude = 0;
        _endAltitude = 0;
        _grade = 0;
        _duration = 0;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"距离: %.2f-%.2f 米, 海拔: %.2f-%.2f 米, 坡度: %.2f%%", 
            self.startDistance, self.endDistance, self.startAltitude, self.endAltitude, self.grade];
}

@end

#pragma mark - GPSAnalyticsSystem 扩展声明私有方法

@interface GPSAnalyticsSystem ()

@property (nonatomic, strong) NSMutableDictionary *cachedRecordings;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) dispatch_queue_t analysisQueue;

- (NSArray<GPSLocationModel *> *)loadRecordingWithId:(NSString *)recordingId;
- (NSArray<GPSLocationModel *> *)loadRecordingWithId:(NSString *)recordingId error:(NSError **)error;

- (void)safelyPerformCallback:(void (^)(NSURL *, NSError *))callback 
                      withURL:(NSURL *)url 
                        error:(NSError *)error;

// 私有辅助方法
- (void)safeAsyncCallback:(void (^)(NSURL *, NSError *))callback withURL:(NSURL *)url error:(NSError *)error;
- (NSString *)generateExportFilenameWithPrefix:(NSString *)prefix extension:(NSString *)extension;
- (BOOL)exportSummaryToCSV:(GPSAnalyticsSummary *)summary toURL:(NSURL *)fileURL error:(NSError **)error;
- (BOOL)exportSummaryToJSON:(GPSAnalyticsSummary *)summary toURL:(NSURL *)fileURL error:(NSError **)error;
- (BOOL)exportSummaryToPDF:(GPSAnalyticsSummary *)summary toURL:(NSURL *)fileURL error:(NSError **)error;
- (BOOL)exportRouteToCSV:(NSArray<GPSLocationModel *> *)route toURL:(NSURL *)fileURL error:(NSError **)error;
- (BOOL)exportRouteToJSON:(NSArray<GPSLocationModel *> *)route toURL:(NSURL *)fileURL error:(NSError **)error;
- (BOOL)exportRouteToGPX:(NSArray<GPSLocationModel *> *)route toURL:(NSURL *)fileURL error:(NSError **)error;
- (BOOL)saveData:(id)data toDirectory:(NSString *)directory withFilename:(NSString *)filename error:(NSError **)error;
- (id)loadDataFromDirectory:(NSString *)directory filename:(NSString *)filename error:(NSError **)error;
- (NSURL *)createExportDirectoryWithError:(NSError **)error;

@end

#pragma mark - GPSAnalyticsSystem 实现

@implementation GPSAnalyticsSystem

#pragma mark - 单例实现

+ (instancetype)sharedInstance {
    static GPSAnalyticsSystem *_sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedInstance = [[self alloc] init];
    });
    return _sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _cachedRecordings = [NSMutableDictionary dictionary];
        
        _dateFormatter = [[NSDateFormatter alloc] init];
        _dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        
        _fileManager = [NSFileManager defaultManager];
        
        _analysisQueue = dispatch_queue_create("com.gpsplusplus.analyticsqueue", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

#pragma mark - 路线分析

- (GPSAnalyticsSummary *)analyzeRoute:(NSArray<GPSLocationModel *> *)route {
    if (!route || route.count < 2) {
        return nil;
    }
    
    GPSAnalyticsSummary *summary = [[GPSAnalyticsSummary alloc] init];
    summary.startTime = route.firstObject.timestamp;
    summary.endTime = route.lastObject.timestamp;
    summary.pointCount = route.count;
    
    double totalAltitude = 0;
    double cumulativeDistance = 0;
    double lastValidAltitude = 0;
    BOOL hasLastValidAltitude = NO;
    
    GPSLocationModel *previousLocation = nil;
    GPSLocationModel *lastNonStationaryPoint = nil;
    NSTimeInterval lastPauseTime = 0;
    BOOL isPaused = NO;
    
    for (GPSLocationModel *location in route) {
        // 累计总点数
        
        // 速度统计
        if (location.speed >= 0) {
            summary.maxSpeed = MAX(summary.maxSpeed, location.speed);
            if (location.speed > 0) {
                summary.minSpeed = MIN(summary.minSpeed, location.speed);
            }
        }
        
        // 海拔统计
        if (location.altitude != 0) {
            totalAltitude += location.altitude;
            summary.maxAltitude = MAX(summary.maxAltitude, location.altitude);
            summary.minAltitude = MIN(summary.minAltitude, location.altitude);
            
            if (hasLastValidAltitude && lastValidAltitude != location.altitude) {
                double altitudeDifference = location.altitude - lastValidAltitude;
                if (altitudeDifference > 0) {
                    summary.totalAscent += altitudeDifference;
                } else {
                    summary.totalDescent += fabs(altitudeDifference);
                }
            }
            
            lastValidAltitude = location.altitude;
            hasLastValidAltitude = YES;
        }
        
        // 距离和时间计算
        if (previousLocation) {
            CLLocation *prevCLLocation = [previousLocation toCLLocation];
            CLLocation *currentCLLocation = [location toCLLocation];
            
            CLLocationDistance distance = [prevCLLocation distanceFromLocation:currentCLLocation];
            cumulativeDistance += distance;
            
            NSTimeInterval timeDiff = [location.timestamp timeIntervalSinceDate:previousLocation.timestamp];
            
            // 判断是否处于暂停状态
            if (distance < 2.0 && timeDiff > 10.0) { // 假设移动小于2米且间隔超过10秒为暂停
                if (!isPaused) {
                    isPaused = YES;
                    summary.pauseCount++;
                    lastPauseTime = previousLocation.timestamp.timeIntervalSince1970;
                }
            } else if (isPaused) {
                isPaused = NO;
                summary.pauseDuration += location.timestamp.timeIntervalSince1970 - lastPauseTime;
                lastNonStationaryPoint = location;
            } else {
                lastNonStationaryPoint = location;
            }
        } else {
            lastNonStationaryPoint = location;
        }
        
        previousLocation = location;
    }
    
    // 设置总距离
    summary.totalDistance = cumulativeDistance;
    
    // 总时间（包括暂停）
    if (summary.startTime && summary.endTime) {
        summary.totalDuration = [summary.endTime timeIntervalSinceDate:summary.startTime];
    }
    
    // 计算平均速度（剔除暂停时间）
    NSTimeInterval movingDuration = summary.totalDuration - summary.pauseDuration;
    if (movingDuration > 0) {
        summary.averageSpeed = summary.totalDistance / movingDuration;
    }
    
    // 平均海拔
    if (summary.pointCount > 0) {
        summary.averageAltitude = totalAltitude / summary.pointCount;
    }
    
    // 如果没有检测到有效的最低速度，将其设为0
    if (summary.minSpeed == DBL_MAX) {
        summary.minSpeed = 0;
    }
    
    return summary;
}

- (GPSAnalyticsSummary *)analyzeRecording:(NSString *)recordingId {
    // 从缓存或数据库加载记录
    NSArray<GPSLocationModel *> *route = [self loadRecordingWithId:recordingId];
    if (!route) {
        NSLog(@"无法找到记录 ID: %@", recordingId);
        return nil;
    }
    
    return [self analyzeRoute:route];
}

#pragma mark - 分段分析

- (NSArray<GPSSpeedSegment *> *)speedSegmentsForRoute:(NSArray<GPSLocationModel *> *)route 
                                      withMinLength:(CLLocationDistance)minSegmentLength {
    if (!route || route.count < 2 || minSegmentLength <= 0) {
        return @[];
    }
    
    NSMutableArray<GPSSpeedSegment *> *segments = [NSMutableArray array];
    GPSSpeedSegment *currentSegment = [[GPSSpeedSegment alloc] init];
    currentSegment.startPoint = route.firstObject;
    currentSegment.startDistance = 0;
    
    double cumulativeDistance = 0;
    GPSLocationModel *prevLocation = route.firstObject;
    NSDate *segmentStartTime = prevLocation.timestamp;
    
    for (NSUInteger i = 1; i < route.count; i++) {
        GPSLocationModel *location = route[i];
        
        CLLocation *prevCLLocation = [prevLocation toCLLocation];
        CLLocation *currentCLLocation = [location toCLLocation];
        
        double distance = [prevCLLocation distanceFromLocation:currentCLLocation];
        cumulativeDistance += distance;
        
        // 速度变化超过阈值或距离满足最小分段长度，创建新的分段
        if (cumulativeDistance - currentSegment.startDistance >= minSegmentLength) {
            currentSegment.endPoint = location;
            currentSegment.endDistance = cumulativeDistance;
            currentSegment.duration = [location.timestamp timeIntervalSinceDate:segmentStartTime];
            
            if (currentSegment.duration > 0) {
                double segmentDistance = currentSegment.endDistance - currentSegment.startDistance;
                currentSegment.averageSpeed = segmentDistance / currentSegment.duration;
                [segments addObject:currentSegment];
            }
            
            // 创建新分段
            currentSegment = [[GPSSpeedSegment alloc] init];
            currentSegment.startPoint = location;
            currentSegment.startDistance = cumulativeDistance;
            segmentStartTime = location.timestamp;
        }
        
        prevLocation = location;
    }
    
    // 处理最后一段（如果距离足够长）
    if (cumulativeDistance - currentSegment.startDistance >= minSegmentLength) {
        currentSegment.endPoint = route.lastObject;
        currentSegment.endDistance = cumulativeDistance;
        currentSegment.duration = [route.lastObject.timestamp timeIntervalSinceDate:segmentStartTime];
        
        if (currentSegment.duration > 0) {
            double segmentDistance = currentSegment.endDistance - currentSegment.startDistance;
            currentSegment.averageSpeed = segmentDistance / currentSegment.duration;
            [segments addObject:currentSegment];
        }
    }
    
    return segments;
}

- (NSArray<GPSElevationSegment *> *)elevationSegmentsForRoute:(NSArray<GPSLocationModel *> *)route 
                                             withMinGrade:(double)minGradePercent {
    if (!route || route.count < 2 || minGradePercent < 0) {
        return @[];
    }
    
    NSMutableArray<GPSElevationSegment *> *segments = [NSMutableArray array];
    GPSElevationSegment *currentSegment = nil;
    
    double cumulativeDistance = 0;
    GPSLocationModel *prevLocation = nil;
    NSDate *segmentStartTime = nil;
    double currentGradeDirection = 0; // 正值为上坡，负值为下坡，0为平地
    
    for (GPSLocationModel *location in route) {
        if (!prevLocation) {
            prevLocation = location;
            segmentStartTime = location.timestamp;
            continue;
        }
        
        CLLocation *prevCLLocation = [prevLocation toCLLocation];
        CLLocation *currentCLLocation = [location toCLLocation];
        
        double distance = [prevCLLocation distanceFromLocation:currentCLLocation];
        cumulativeDistance += distance;
        
        if (distance > 0) {
            double altitudeDifference = location.altitude - prevLocation.altitude;
            double gradePercent = (altitudeDifference / distance) * 100.0;
            
            // 判断坡度方向变化或坡度超过阈值
            if (fabs(gradePercent) >= minGradePercent) {
                double newGradeDirection = (gradePercent > 0) ? 1 : ((gradePercent < 0) ? -1 : 0);
                
                // 如果坡度方向改变或没有当前分段，开始新分段
                if (!currentSegment || (currentGradeDirection != newGradeDirection && newGradeDirection != 0)) {
                    // 结束前一段
                    if (currentSegment) {
                        currentSegment.endDistance = cumulativeDistance;
                        currentSegment.endAltitude = prevLocation.altitude;
                        currentSegment.duration = [prevLocation.timestamp timeIntervalSinceDate:segmentStartTime];
                        
                        double segmentDistance = currentSegment.endDistance - currentSegment.startDistance;
                        double elevationChange = currentSegment.endAltitude - currentSegment.startAltitude;
                        if (segmentDistance > 0) {
                            currentSegment.grade = (elevationChange / segmentDistance) * 100.0;
                            
                            // 只有当坡度超过阈值才添加分段
                            if (fabs(currentSegment.grade) >= minGradePercent) {
                                [segments addObject:currentSegment];
                            }
                        }
                    }
                    
                    // 开始新分段
                    currentSegment = [[GPSElevationSegment alloc] init];
                    currentSegment.startDistance = cumulativeDistance - distance;
                    currentSegment.startAltitude = prevLocation.altitude;
                    segmentStartTime = prevLocation.timestamp;
                    currentGradeDirection = newGradeDirection;
                }
            }
        }
        
        prevLocation = location;
    }
    
    // 处理最后一个分段
    if (currentSegment) {
        currentSegment.endDistance = cumulativeDistance;
        currentSegment.endAltitude = prevLocation.altitude;
        currentSegment.duration = [prevLocation.timestamp timeIntervalSinceDate:segmentStartTime];
        
        double segmentDistance = currentSegment.endDistance - currentSegment.startDistance;
        double elevationChange = currentSegment.endAltitude - currentSegment.startAltitude;
        if (segmentDistance > 0) {
            currentSegment.grade = (elevationChange / segmentDistance) * 100.0;
            
            if (fabs(currentSegment.grade) >= minGradePercent) {
                [segments addObject:currentSegment];
            }
        }
    }
    
    return segments;
}

#pragma mark - 高级分析

- (NSDictionary *)heatMapDataForRecordings:(NSArray<NSString *> *)recordingIds {
    NSMutableDictionary *heatmapData = [NSMutableDictionary dictionary];
    NSMutableArray *allPoints = [NSMutableArray array];
    
    for (NSString *recordingId in recordingIds) {
        NSArray<GPSLocationModel *> *route = [self loadRecordingWithId:recordingId];
        if (route) {
            for (GPSLocationModel *location in route) {
                NSString *key = [NSString stringWithFormat:@"%.6f,%.6f", 
                                location.latitude, location.longitude];
                
                // 对每个位置点计数
                NSNumber *count = heatmapData[key] ?: @0;
                heatmapData[key] = @(count.integerValue + 1);
                
                [allPoints addObject:@{
                    @"lat": @(location.latitude),
                    @"lon": @(location.longitude),
                    @"count": @1
                }];
            }
        }
    }
    
    // 返回格式化的热图数据
    return @{
        @"points": allPoints,
        @"pointCounts": heatmapData
    };
}

- (NSDictionary *)activityPatternsByTimeOfDay:(NSTimeInterval)binSize forPeriod:(NSInteger)days {
    // 创建时间段统计
    NSMutableDictionary *timePatterns = [NSMutableDictionary dictionary];
    NSDate *cutoffDate = [NSDate dateWithTimeIntervalSinceNow:-days * 24 * 60 * 60];
    
    // 初始化每个时间段的统计数据
    for (int hour = 0; hour < 24; hour++) {
        for (int minute = 0; minute < 60; minute += binSize / 60) {
            NSString *key = [NSString stringWithFormat:@"%02d:%02d", hour, minute];
            timePatterns[key] = @{
                @"count": @0,
                @"totalDistance": @0.0,
                @"avgSpeed": @0.0,
                @"recordings": @[]
            };
        }
    }
    
    // 获取所有记录ID
    NSArray<NSString *> *allRecordingIds = [self getAllRecordingIds];
    
    for (NSString *recordingId in allRecordingIds) {
        NSArray<GPSLocationModel *> *route = [self loadRecordingWithId:recordingId];
        
        if (!route || route.count == 0) continue;
        
        // 检查记录是否在指定的时间段内
        GPSLocationModel *firstPoint = route.firstObject;
        if ([firstPoint.timestamp compare:cutoffDate] == NSOrderedAscending) {
            continue; // 记录太旧，跳过
        }
        
        // 分析此记录
        GPSAnalyticsSummary *summary = [self analyzeRoute:route];
        
        if (summary && summary.startTime) {
            NSCalendar *calendar = [NSCalendar currentCalendar];
            NSDateComponents *components = [calendar components:(NSCalendarUnitHour | NSCalendarUnitMinute)
                                                      fromDate:summary.startTime];
            
            int hour = (int)components.hour;
            int minute = (int)components.minute;
            
            // 将分钟舍入到最近的bin
            int binMinute = (minute / (int)(binSize / 60)) * (int)(binSize / 60);
            
            NSString *key = [NSString stringWithFormat:@"%02d:%02d", hour, binMinute];
            
            // 更新时间段统计
            NSDictionary *existingData = timePatterns[key];
            NSInteger count = [existingData[@"count"] integerValue] + 1;
            double totalDistance = [existingData[@"totalDistance"] doubleValue] + summary.totalDistance;
            double totalSpeed = [existingData[@"avgSpeed"] doubleValue] * [existingData[@"count"] integerValue] + summary.averageSpeed;
            double avgSpeed = count > 0 ? totalSpeed / count : 0;
            
            NSMutableArray *recordings = [existingData[@"recordings"] mutableCopy];
            [recordings addObject:recordingId];
            
            timePatterns[key] = @{
                @"count": @(count),
                @"totalDistance": @(totalDistance),
                @"avgSpeed": @(avgSpeed),
                @"recordings": recordings
            };
        }
    }
    
    return timePatterns;
}

- (UIImage *)generateElevationProfileForRoute:(NSArray<GPSLocationModel *> *)route size:(CGSize)size {
    if (!route || route.count < 2 || size.width <= 0 || size.height <= 0) {
        return nil;
    }
    
    // 提取海拔数据
    NSMutableArray *distances = [NSMutableArray arrayWithCapacity:route.count];
    NSMutableArray *altitudes = [NSMutableArray arrayWithCapacity:route.count];
    
    double totalDistance = 0;
    GPSLocationModel *prevLocation = nil;
    
    // 计算每个点的累积距离和海拔
    for (GPSLocationModel *location in route) {
        if (prevLocation) {
            CLLocation *prevCLLocation = [prevLocation toCLLocation];
            CLLocation *currentCLLocation = [location toCLLocation];
            totalDistance += [prevCLLocation distanceFromLocation:currentCLLocation];
        }
        
        [distances addObject:@(totalDistance)];
        [altitudes addObject:@(location.altitude)];
        prevLocation = location;
    }
    
    // 找出海拔范围
    double minAltitude = [[altitudes valueForKeyPath:@"@min.doubleValue"] doubleValue];
    double maxAltitude = [[altitudes valueForKeyPath:@"@max.doubleValue"] doubleValue];
    
    // 确保有一定的海拔范围以便图形显示
    if (maxAltitude - minAltitude < 10) {
        minAltitude -= 5;
        maxAltitude += 5;
    }
    
    // 开始绘图
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // 设置绘图区域
    CGFloat padding = 20.0;
    CGRect drawingRect = CGRectMake(padding, padding, size.width - 2 * padding, size.height - 2 * padding);
    
    // 绘制背景
    [[UIColor whiteColor] setFill];
    CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
    
    // 绘制坐标轴
    [[UIColor blackColor] setStroke];
    CGContextSetLineWidth(context, 1.0);
    
    // X轴
    CGContextMoveToPoint(context, drawingRect.origin.x, drawingRect.origin.y + drawingRect.size.height);
    CGContextAddLineToPoint(context, drawingRect.origin.x + drawingRect.size.width, 
                           drawingRect.origin.y + drawingRect.size.height);
    CGContextStrokePath(context);
    
    // Y轴
    CGContextMoveToPoint(context, drawingRect.origin.x, drawingRect.origin.y);
    CGContextAddLineToPoint(context, drawingRect.origin.x, drawingRect.origin.y + drawingRect.size.height);
    CGContextStrokePath(context);
    
    // 绘制海拔曲线
    if (distances.count > 0 && totalDistance > 0) {
        [[UIColor blueColor] setStroke];
        CGContextSetLineWidth(context, 2.0);
        
        CGContextMoveToPoint(context, 
                            drawingRect.origin.x, 
                            drawingRect.origin.y + drawingRect.size.height - ((([altitudes[0] doubleValue] - minAltitude) / (maxAltitude - minAltitude)) * drawingRect.size.height));
        
        for (NSUInteger i = 1; i < distances.count; i++) {
            double x = drawingRect.origin.x + ([distances[i] doubleValue] / totalDistance) * drawingRect.size.width;
            double y = drawingRect.origin.y + drawingRect.size.height - ((([altitudes[i] doubleValue] - minAltitude) / (maxAltitude - minAltitude)) * drawingRect.size.height);
            
            CGContextAddLineToPoint(context, x, y);
        }
        
        CGContextStrokePath(context);
        
        // 填充海拔曲线下方
        [[UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.2] setFill];
        
        CGContextMoveToPoint(context, 
                            drawingRect.origin.x, 
                            drawingRect.origin.y + drawingRect.size.height);
        
        for (NSUInteger i = 0; i < distances.count; i++) {
            double x = drawingRect.origin.x + ([distances[i] doubleValue] / totalDistance) * drawingRect.size.width;
            double y = drawingRect.origin.y + drawingRect.size.height - ((([altitudes[i] doubleValue] - minAltitude) / (maxAltitude - minAltitude)) * drawingRect.size.height);
            
            CGContextAddLineToPoint(context, x, y);
        }
        
        CGContextAddLineToPoint(context, 
                               drawingRect.origin.x + drawingRect.size.width, 
                               drawingRect.origin.y + drawingRect.size.height);
        CGContextAddLineToPoint(context, 
                               drawingRect.origin.x, 
                               drawingRect.origin.y + drawingRect.size.height);
        
        CGContextFillPath(context);
    }
    
    // 绘制刻度和标签
    [[UIColor darkGrayColor] setStroke];
    CGContextSetLineWidth(context, 0.5);
    
    // X轴刻度（距离）
    NSInteger distanceSteps = 5;
    for (NSInteger i = 0; i <= distanceSteps; i++) {
        double distanceValue = totalDistance * i / distanceSteps;
        double x = drawingRect.origin.x + (distanceValue / totalDistance) * drawingRect.size.width;
        
        // 绘制刻度线
        CGContextMoveToPoint(context, x, drawingRect.origin.y + drawingRect.size.height);
        CGContextAddLineToPoint(context, x, drawingRect.origin.y + drawingRect.size.height + 5);
        CGContextStrokePath(context);
        
        // 绘制标签
        NSString *label = [NSString stringWithFormat:@"%.1f km", distanceValue / 1000.0];
        NSDictionary *attributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:10],
            NSForegroundColorAttributeName: [UIColor darkGrayColor]
        };
        
        [label drawAtPoint:CGPointMake(x - 15, drawingRect.origin.y + drawingRect.size.height + 7)
              withAttributes:attributes];
    }
    
    // Y轴刻度（海拔）
    NSInteger altitudeSteps = 5;
    for (NSInteger i = 0; i <= altitudeSteps; i++) {
        double altitudeValue = minAltitude + (maxAltitude - minAltitude) * i / altitudeSteps;
        double y = drawingRect.origin.y + drawingRect.size.height - 
                  ((altitudeValue - minAltitude) / (maxAltitude - minAltitude)) * drawingRect.size.height;
        
        // 绘制刻度线
        CGContextMoveToPoint(context, drawingRect.origin.x, y);
        CGContextAddLineToPoint(context, drawingRect.origin.x - 5, y);
        CGContextStrokePath(context);
        
        // 绘制标签
        NSString *label = [NSString stringWithFormat:@"%.0f m", altitudeValue];
        NSDictionary *attributes = @{
            NSFontAttributeName: [UIFont systemFontOfSize:10],
            NSForegroundColorAttributeName: [UIColor darkGrayColor]
        };
        
        [label drawAtPoint:CGPointMake(drawingRect.origin.x - 30, y - 5) withAttributes:attributes];
    }
    
    // 绘制标题
    NSString *title = @"海拔高度图";
    NSDictionary *titleAttributes = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:14],
        NSForegroundColorAttributeName: [UIColor blackColor]
    };
    
    CGSize titleSize = [title sizeWithAttributes:titleAttributes];
    [title drawAtPoint:CGPointMake((size.width - titleSize.width) / 2, 5) withAttributes:titleAttributes];
    
    // 获取图像
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

- (NSArray<NSDictionary *> *)detectStopPointsInRoute:(NSArray<GPSLocationModel *> *)route 
                                    minDuration:(NSTimeInterval)minSeconds {
    if (!route || route.count < 2 || minSeconds <= 0) {
        return @[];
    }
    
    NSMutableArray<NSDictionary *> *stopPoints = [NSMutableArray array];
    BOOL isInStopPoint = NO;
    NSInteger stopPointStartIndex = 0;
    NSDate *stopPointStartTime = nil;
    CLLocationCoordinate2D stopPointCenter;
    double sumLat = 0, sumLon = 0;
    NSInteger pointCount = 0;
    
    for (NSInteger i = 1; i < route.count; i++) {
        GPSLocationModel *prevLocation = route[i-1];
        GPSLocationModel *location = route[i];
        
        CLLocation *prevCLLocation = [prevLocation toCLLocation];
        CLLocation *currentCLLocation = [location toCLLocation];
        
        double distance = [prevCLLocation distanceFromLocation:currentCLLocation];
        NSTimeInterval timeDiff = [location.timestamp timeIntervalSinceDate:prevLocation.timestamp];
        
        // 检测停留点
        // 条件：移动距离小于某个阈值，时间间隔不太大
        if (distance < 10.0 && timeDiff < 60.0) {
            if (!isInStopPoint) {
                // 开始一个新的停留点
                isInStopPoint = YES;
                stopPointStartIndex = i - 1;
                stopPointStartTime = prevLocation.timestamp;
                
                sumLat = prevLocation.latitude;
                sumLon = prevLocation.longitude;
                pointCount = 1;
            }
            
            // 累加当前点的坐标，用于计算停留点中心
            sumLat += location.latitude;
            sumLon += location.longitude;
            pointCount++;
        } else if (isInStopPoint) {
            // 结束当前停留点
            NSTimeInterval stopDuration = [prevLocation.timestamp timeIntervalSinceDate:stopPointStartTime];
            
            if (stopDuration >= minSeconds) {
                // 计算停留点的中心位置
                stopPointCenter = CLLocationCoordinate2DMake(sumLat / pointCount, sumLon / pointCount);
                
                // 记录这个满足条件的停留点
                [stopPoints addObject:@{
                    @"center": [NSValue valueWithMKCoordinate:stopPointCenter],
                    @"startTime": stopPointStartTime,
                    @"endTime": prevLocation.timestamp,
                    @"duration": @(stopDuration),
                    @"startIndex": @(stopPointStartIndex),
                    @"endIndex": @(i - 1)
                }];
            }
            
            isInStopPoint = NO;
        }
    }
    
    // 处理路线结束时可能仍在停留点的情况
    if (isInStopPoint) {
        NSTimeInterval stopDuration = [route.lastObject.timestamp timeIntervalSinceDate:stopPointStartTime];
        
        if (stopDuration >= minSeconds) {
            // 计算停留点的中心位置
            stopPointCenter = CLLocationCoordinate2DMake(sumLat / pointCount, sumLon / pointCount);
            
            // 记录这个满足条件的停留点
            [stopPoints addObject:@{
                @"center": [NSValue valueWithMKCoordinate:stopPointCenter],
                @"startTime": stopPointStartTime,
                @"endTime": route.lastObject.timestamp,
                @"duration": @(stopDuration),
                @"startIndex": @(stopPointStartIndex),
                @"endIndex": @(route.count - 1)
            }];
        }
    }
    
    return stopPoints;
}

#pragma mark - 导出

- (void)exportAnalytics:(GPSAnalyticsSummary *)summary 
               toFormat:(NSString *)format 
              completion:(void (^)(NSURL *fileURL, NSError *error))completion {
    if (!summary) {
        NSError *error = [NSError errorWithDomain:@"GPSAnalyticsSystemErrorDomain" 
                                            code:100 
                                        userInfo:@{NSLocalizedDescriptionKey: @"无效的统计数据"}];
        [self safeAsyncCallback:completion withURL:nil error:error];
        return;
    }
    
    dispatch_async(self.analysisQueue, ^{
        NSError *error = nil;
        NSURL *exportsURL = [self createExportDirectoryWithError:&error];
        
        if (error) {
            [self safeAsyncCallback:completion withURL:nil error:error];
            return;
        }
        
        NSString *fileName = [self generateExportFilenameWithPrefix:@"analytics" extension:format.lowercaseString];
        NSURL *fileURL = [exportsURL URLByAppendingPathComponent:fileName];
        
        // 基于格式处理
        BOOL success = [self exportContent:summary toURL:fileURL format:format error:&error];
        
        [self safeAsyncCallback:completion withURL:success ? fileURL : nil error:error];
    });
}

- (void)exportRawDataForRoute:(NSArray<GPSLocationModel *> *)route 
                     toFormat:(NSString *)format 
                   completion:(void (^)(NSURL *fileURL, NSError *error))completion {
    if (!route || route.count == 0) {
        NSError *error = [NSError errorWithDomain:@"GPSAnalyticsSystemErrorDomain" 
                                            code:100 
                                        userInfo:@{NSLocalizedDescriptionKey: @"无效的路线数据"}];
        [self safeAsyncCallback:completion withURL:nil error:error];
        return;
    }
    
    dispatch_async(self.analysisQueue, ^{
        NSError *error = nil;
        NSURL *exportsURL = [self createExportDirectoryWithError:&error];
        
        if (error) {
            [self safeAsyncCallback:completion withURL:nil error:error];
            return;
        }
        
        NSString *fileName = [self generateExportFilenameWithPrefix:@"route_data" extension:format.lowercaseString];
        NSURL *fileURL = [exportsURL URLByAppendingPathComponent:fileName];
        
        // 基于格式处理
        BOOL success = [self exportRouteData:route toURL:fileURL format:format error:&error];
        
        [self safeAsyncCallback:completion withURL:success ? fileURL : nil error:error];
    });
}

// 导出统计摘要
- (BOOL)exportContent:(GPSAnalyticsSummary *)summary 
               toURL:(NSURL *)fileURL 
              format:(NSString *)format 
               error:(NSError **)error {
    
    if ([format caseInsensitiveCompare:@"csv"] == NSOrderedSame) {
        return [self exportSummaryToCSV:summary toURL:fileURL error:error];
    } 
    else if ([format caseInsensitiveCompare:@"json"] == NSOrderedSame) {
        return [self exportSummaryToJSON:summary toURL:fileURL error:error];
    } 
    else if ([format caseInsensitiveCompare:@"pdf"] == NSOrderedSame) {
        return [self exportSummaryToPDF:summary toURL:fileURL error:error]; 
    }
    else {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSAnalyticsSystemErrorDomain" 
                                         code:101 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                              [NSString stringWithFormat:@"不支持的导出格式: %@", format]}];
        }
        return NO;
    }
}

// 导出路线数据
- (BOOL)exportRouteData:(NSArray<GPSLocationModel *> *)route 
                  toURL:(NSURL *)fileURL 
                 format:(NSString *)format 
                  error:(NSError **)error {
    
    if ([format caseInsensitiveCompare:@"csv"] == NSOrderedSame) {
        return [self exportRouteToCSV:route toURL:fileURL error:error];
    } 
    else if ([format caseInsensitiveCompare:@"json"] == NSOrderedSame) {
        return [self exportRouteToJSON:route toURL:fileURL error:error];
    } 
    else if ([format caseInsensitiveCompare:@"gpx"] == NSOrderedSame) {
        return [self exportRouteToGPX:route toURL:fileURL error:error];
    }
    else {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSAnalyticsSystemErrorDomain" 
                                         code:101 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                              [NSString stringWithFormat:@"不支持的导出格式: %@", format]}];
        }
        return NO;
    }
}

// 通用导出方法 - 处理通用流程
- (void)exportData:(id)data 
           format:(NSString *)format 
         filePrefix:(NSString *)prefix
        completion:(void (^)(NSURL *fileURL, NSError *error))completion {
    
    // 验证数据
    if (!data) {
        NSError *error = [NSError errorWithDomain:@"GPSAnalyticsSystemErrorDomain" 
                                            code:100 
                                        userInfo:@{NSLocalizedDescriptionKey: @"无效的数据"}];
        [self safelyPerformCallback:completion withURL:nil error:error];
        return;
    }
    
    // 在后台线程处理
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSURL *exportsURL = [self createExportDirectoryWithError:&error];
        
        if (error) {
            [self safelyPerformCallback:completion withURL:nil error:error];
            return;
        }
        
        // 创建文件URL
        NSString *fileName = [self generateFilenameWithPrefix:prefix extension:format.lowercaseString];
        NSURL *fileURL = [exportsURL URLByAppendingPathComponent:fileName];
        
        // 根据格式执行特定的导出
        BOOL success = [self writeData:data toURL:fileURL format:format error:&error];
        
        // 回调结果
        [self safelyPerformCallback:completion 
                            withURL:(success ? fileURL : nil) 
                              error:error];
    });
}

// 根据格式写入数据
- (BOOL)writeData:(id)data toURL:(NSURL *)fileURL format:(NSString *)format error:(NSError **)error {
    // 根据格式选择导出方法
    if ([format caseInsensitiveCompare:@"csv"] == NSOrderedSame) {
        return [self writeCSV:data toURL:fileURL error:error];
    } 
    else if ([format caseInsensitiveCompare:@"json"] == NSOrderedSame) {
        return [self writeJSON:data toURL:fileURL error:error];
    }
    else if ([format caseInsensitiveCompare:@"gpx"] == NSOrderedSame) {
        return [self writeGPX:data toURL:fileURL error:error];
    }
    else if ([format caseInsensitiveCompare:@"pdf"] == NSOrderedSame) {
        return [self writePDF:data toURL:fileURL error:error];
    }
    else {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSAnalyticsSystemErrorDomain" 
                                         code:101 
                                     userInfo:@{NSLocalizedDescriptionKey: 
                                              [NSString stringWithFormat:@"不支持的导出格式: %@", format]}];
        }
        return NO;
    }
}

- (NSArray<NSString *> *)getAllRecordingIds {
    // 返回所有录制ID列表
    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *recordingsDir = [self getURLForDirectory:@"Recordings" filename:@""];
    
    NSError *error = nil;
    NSArray<NSURL *> *files = [fm contentsOfDirectoryAtURL:recordingsDir 
                               includingPropertiesForKeys:nil 
                                                  options:NSDirectoryEnumerationSkipsHiddenFiles 
                                                    error:&error];
    
    if (error) {
        NSLog(@"获取录制ID失败: %@", error);
        return @[];
    }
    
    NSMutableArray<NSString *> *recordingIds = [NSMutableArray array];
    
    for (NSURL *file in files) {
        NSString *filename = [[file lastPathComponent] stringByDeletingPathExtension];
        if ([[[file pathExtension] lowercaseString] isEqualToString:@"plist"]) {
            [recordingIds addObject:filename];
        }
    }
    
    return recordingIds;
}

- (NSArray<NSNumber *> *)calculateCumulativeDistancesForRoute:(NSArray<GPSLocationModel *> *)route {
    NSMutableArray<NSNumber *> *distances = [NSMutableArray arrayWithCapacity:route.count];
    [distances addObject:@(0)]; // 起始点距离为0
    
    double cumulativeDistance = 0;
    GPSLocationModel *prevLocation = route.firstObject;
    
    for (NSUInteger i = 1; i < route.count; i++) {
        GPSLocationModel *location = route[i];
        CLLocation *prevCL = [prevLocation toCLLocation];
        CLLocation *currentCL = [location toCLLocation];
        
        cumulativeDistance += [prevCL distanceFromLocation:currentCL];
        [distances addObject:@(cumulativeDistance)];
        
        prevLocation = location;
    }
    
    return distances;
}

// 获取录制数据存储路径
- (NSURL *)recordingURLForId:(NSString *)recordingId {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory 
                                                                   inDomains:NSUserDomainMask] lastObject];
    NSURL *recordingsURL = [documentsURL URLByAppendingPathComponent:@"Recordings" isDirectory:YES];
    
    // 确保目录存在
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:recordingsURL 
                                withIntermediateDirectories:YES 
                                                 attributes:nil 
                                                      error:&error];
    
    return [recordingsURL URLByAppendingPathComponent:
           [NSString stringWithFormat:@"%@.plist", recordingId]];
}

// 保存记录数据
- (BOOL)saveRecording:(NSArray<GPSLocationModel *> *)route 
            withId:(NSString *)recordingId
             error:(NSError **)error {
    if (!recordingId || !route) return NO;
    
    // 缓存记录
    self.cachedRecordings[recordingId] = route;
    
    // 序列化为可存储格式
    NSMutableArray *serializedRoute = [NSMutableArray arrayWithCapacity:route.count];
    for (GPSLocationModel *location in route) {
        [serializedRoute addObject:[location toDictionary]];
    }
    
    // 保存到文件
    BOOL success = [NSKeyedArchiver archiveRootObject:serializedRoute 
                                              toFile:[[self recordingURLForId:recordingId] path]];
    
    if (!success && error) {
        *error = [NSError errorWithDomain:@"GPSAnalyticsSystemErrorDomain" 
                                     code:102 
                                 userInfo:@{NSLocalizedDescriptionKey: @"无法保存记录"}];
    }
    
    return success;
}

#pragma mark - 文件导出辅助方法

// 创建导出目录并返回URL
- (NSURL *)createExportDirectoryWithError:(NSError **)error {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory 
                                                                 inDomains:NSUserDomainMask] lastObject];
    NSURL *exportsURL = [documentsURL URLByAppendingPathComponent:@"Exports" isDirectory:YES];
    
    [[NSFileManager defaultManager] createDirectoryAtURL:exportsURL 
                           withIntermediateDirectories:YES 
                                            attributes:nil 
                                                 error:error];
    return exportsURL;
}

// 生成格式化的文件名
- (NSString *)generateFilenameWithPrefix:(NSString *)prefix extension:(NSString *)extension {
    NSString *dateString = [NSDateFormatter localizedStringFromDate:[NSDate date] 
                                                      dateStyle:NSDateFormatterShortStyle 
                                                      timeStyle:NSDateFormatterShortStyle];
    NSString *sanitizedDateString = [dateString stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    sanitizedDateString = [sanitizedDateString stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    return [[NSString stringWithFormat:@"%@_%@", prefix, sanitizedDateString] 
            stringByAppendingPathExtension:extension];
}

// 安全地执行异步回调
- (void)safeAsyncCallback:(void (^)(NSURL *, NSError *))callback withURL:(NSURL *)url error:(NSError *)error {
    if (callback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(url, error);
        });
    }
}

// CSV格式导出
- (BOOL)writeCSV:(id)data toURL:(NSURL *)fileURL error:(NSError **)error {
    NSMutableString *csvContent = [NSMutableString string];
    
    if ([data isKindOfClass:[GPSAnalyticsSummary class]]) {
        // 处理分析总结导出
        GPSAnalyticsSummary *summary = (GPSAnalyticsSummary *)data;
        [csvContent appendString:@"指标,数值,单位\n"];
        [csvContent appendFormat:@"总距离,%.2f,米\n", summary.totalDistance];
        [csvContent appendFormat:@"平均速度,%.2f,米/秒\n", summary.averageSpeed];
        // ...其他字段...
    }
    else if ([data isKindOfClass:[NSArray class]] && 
             [[(NSArray *)data firstObject] isKindOfClass:[GPSLocationModel class]]) {
        // 处理位置数据导出
        NSArray<GPSLocationModel *> *locations = (NSArray<GPSLocationModel *> *)data;
        [csvContent appendString:@"纬度,经度,高度,时间戳,速度,精度\n"];
        
        for (GPSLocationModel *location in locations) {
            [csvContent appendFormat:@"%.6f,%.6f,%.2f,%@,%.2f,%.2f\n",
             location.latitude,
             location.longitude,
             location.altitude,
             location.timestamp ? [NSDateFormatter localizedStringFromDate:location.timestamp 
                                                               dateStyle:NSDateFormatterShortStyle 
                                                               timeStyle:NSDateFormatterShortStyle] : @"",
             location.speed,
             location.accuracy];
        }
    }
    
    return [csvContent writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:error];
}

// JSON格式导出 
- (BOOL)writeJSON:(id)data toURL:(NSURL *)fileURL error:(NSError **)error {
    NSMutableDictionary *jsonDict = [NSMutableDictionary dictionary];
    NSData *jsonData = nil;
    
    if ([data isKindOfClass:[GPSAnalyticsSummary class]]) {
        // 将分析总结转换为字典
        GPSAnalyticsSummary *summary = (GPSAnalyticsSummary *)data;
        [jsonDict setObject:@(summary.totalDistance) forKey:@"totalDistance"];
        [jsonDict setObject:@(summary.averageSpeed) forKey:@"averageSpeed"];
        // ...其他字段...
    }
    else if ([data isKindOfClass:[NSArray class]]) {
        // 将位置数组转换为字典数组
        NSMutableArray *locationsArray = [NSMutableArray array];
        for (id location in (NSArray *)data) {
            if ([location isKindOfClass:[GPSLocationModel class]]) {
                GPSLocationModel *loc = (GPSLocationModel *)location;
                [locationsArray addObject:[loc toDictionary]];
            }
        }
        jsonDict[@"locations"] = locationsArray;
    }
    
    // 序列化为JSON
    NSError *jsonError = nil;
    jsonData = [NSJSONSerialization dataWithJSONObject:jsonDict 
                                              options:NSJSONWritingPrettyPrinted 
                                                error:&jsonError];
    if (jsonError) {
        if (error) *error = jsonError;
        return NO;
    }
    
    // 写入文件
    return [jsonData writeToURL:fileURL options:NSDataWritingAtomic error:error];
}

// GPX格式导出
- (BOOL)writeGPX:(id)data toURL:(NSURL *)fileURL error:(NSError **)error {
    // GPX导出实现...
    return YES;
}

// PDF格式导出
- (BOOL)writePDF:(id)data toURL:(NSURL *)fileURL error:(NSError **)error {
    // PDF导出实现...
    return YES;
}

// 计算路线速度
- (NSArray<NSNumber *> *)calculateSpeedsForRoute:(NSArray<GPSLocationModel *> *)route {
    NSMutableArray<NSNumber *> *speeds = [NSMutableArray arrayWithCapacity:route.count];
    [speeds addObject:@(0)]; // 起始点速度默认为0
    
    for (NSUInteger i = 1; i < route.count; i++) {
        GPSLocationModel *prevLocation = route[i-1];
        GPSLocationModel *location = route[i];
        
        CLLocation *prevCL = [[CLLocation alloc] initWithLatitude:prevLocation.latitude longitude:prevLocation.longitude];
        CLLocation *currentCL = [[CLLocation alloc] initWithLatitude:location.latitude longitude:location.longitude];
        
        // 计算两点间距离
        CLLocationDistance distance = [prevCL distanceFromLocation:currentCL];
        
        // 计算时间差
        NSTimeInterval timeDiff = 0;
        if (location.timestamp && prevLocation.timestamp) {
            timeDiff = [location.timestamp timeIntervalSinceDate:prevLocation.timestamp];
        }
        
        // 计算速度 (米/秒)
        double speed = (timeDiff > 0) ? distance / timeDiff : 0;
        [speeds addObject:@(speed)];
    }
    
    return speeds;
}

// 获取路径URL
- (NSURL *)getURLForDirectory:(NSString *)directory filename:(NSString *)filename {
    NSURL *documentsURL = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory 
                                                                  inDomains:NSUserDomainMask] lastObject];
    NSURL *dirURL = [documentsURL URLByAppendingPathComponent:directory isDirectory:YES];
    
    // 确保目录存在
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtURL:dirURL 
                             withIntermediateDirectories:YES 
                                              attributes:nil 
                                                   error:&error];
    
    if (filename.length > 0) {
        return [dirURL URLByAppendingPathComponent:filename];
    }
    return dirURL;
}

// 存储数据
- (BOOL)saveData:(id)data toDirectory:(NSString *)directory withFilename:(NSString *)filename error:(NSError **)error {
    NSURL *fileURL = [self getURLForDirectory:directory filename:filename];
    
    if ([data conformsToProtocol:@protocol(NSCoding)]) {
        return [NSKeyedArchiver archiveRootObject:data toFile:[fileURL path]];
    }
    else if ([data isKindOfClass:[NSString class]]) {
        return [(NSString *)data writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:error];
    }
    else if ([data isKindOfClass:[NSData class]]) {
        return [(NSData *)data writeToURL:fileURL options:NSDataWritingAtomic error:error];
    }
    
    if (error) {
        *error = [NSError errorWithDomain:@"GPSAnalyticsSystemErrorDomain" 
                                     code:102 
                                 userInfo:@{NSLocalizedDescriptionKey: @"不支持的数据类型"}];
    }
    return NO;
}

// 加载数据
- (id)loadDataFromDirectory:(NSString *)directory filename:(NSString *)filename error:(NSError **)error {
    NSURL *fileURL = [self getURLForDirectory:directory filename:filename];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:[fileURL path]]) {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSAnalyticsSystemErrorDomain" 
                                         code:103 
                                     userInfo:@{NSLocalizedDescriptionKey: @"文件不存在"}];
        }
        return nil;
    }
    
    return [NSKeyedUnarchiver unarchiveObjectWithFile:[fileURL path]];
}


// 导出路线原始数据
- (void)exportRouteData:(NSArray<GPSLocationModel *> *)route 
                toFormat:(NSString *)format 
              completion:(void (^)(NSURL *fileURL, NSError *error))completion {
    [self exportData:route format:format filePrefix:@"route_data" completion:completion];
}

// 加载记录
- (NSArray<GPSLocationModel *> *)loadRecordingWithId:(NSString *)recordingId {
    NSError *error = nil;
    return [self loadRecordingWithId:recordingId error:&error];
}

- (void)safelyPerformCallback:(void (^)(NSURL *, NSError *))callback 
                      withURL:(NSURL *)url 
                        error:(NSError *)error {
    if (callback) {
        dispatch_async(dispatch_get_main_queue(), ^{
            callback(url, error);
        });
    }
}

@end