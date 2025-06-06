/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import "GPSLocationModel.h"

NS_ASSUME_NONNULL_BEGIN

// 分析结果摘要
@interface GPSAnalyticsSummary : NSObject

@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, strong) NSDate *endTime;
@property (nonatomic, assign) NSInteger pointCount;
@property (nonatomic, assign) double totalDistance;
@property (nonatomic, assign) double totalDuration;
@property (nonatomic, assign) double averageSpeed;
@property (nonatomic, assign) double maxSpeed;
@property (nonatomic, assign) double minSpeed;
@property (nonatomic, assign) double averageAltitude;
@property (nonatomic, assign) double maxAltitude;
@property (nonatomic, assign) double minAltitude;
@property (nonatomic, assign) double totalAscent;
@property (nonatomic, assign) double totalDescent;
@property (nonatomic, assign) NSInteger pauseCount;
@property (nonatomic, assign) double pauseDuration;
@property (nonatomic, strong) NSMutableDictionary *customMetrics;

@end

// 速度分段类 - 添加缺失的类声明
@interface GPSSpeedSegment : NSObject

@property (nonatomic, assign) double startDistance;
@property (nonatomic, assign) double endDistance;
@property (nonatomic, assign) NSTimeInterval duration;
@property (nonatomic, assign) double averageSpeed;
@property (nonatomic, strong) GPSLocationModel *startPoint;
@property (nonatomic, strong) GPSLocationModel *endPoint;

@end

// 海拔分段类 - 添加缺失的类声明
@interface GPSElevationSegment : NSObject

@property (nonatomic, assign) double startDistance;
@property (nonatomic, assign) double endDistance;
@property (nonatomic, assign) double startAltitude;
@property (nonatomic, assign) double endAltitude;
@property (nonatomic, assign) double grade;
@property (nonatomic, assign) NSTimeInterval duration;

@end

@interface GPSAnalyticsSystem : NSObject

+ (instancetype)sharedInstance;

// 初始化方法
- (void)initialize;

// 路线分析
- (GPSAnalyticsSummary *)analyzeRoute:(NSArray<GPSLocationModel *> *)route;
- (NSDictionary *)analyzeSpeedTrends:(NSArray<GPSLocationModel *> *)points;
- (NSDictionary *)analyzeAltitudeTrends:(NSArray<GPSLocationModel *> *)points;
- (NSDictionary *)analyzeMovementPatterns:(NSArray<GPSLocationModel *> *)points;
- (NSDictionary *)analyzeStopPoints:(NSArray<GPSLocationModel *> *)points minimumStopDuration:(NSTimeInterval)duration;
- (NSDictionary *)analyzeTimeUsage:(NSArray<GPSLocationModel *> *)points;

// 数据导出
- (void)exportAnalysis:(GPSAnalyticsSummary *)analysis 
              toFormat:(NSString *)format 
            completion:(void (^)(NSURL *fileURL, NSError *error))completion;
- (void)exportRouteData:(NSArray<GPSLocationModel *> *)route 
               toFormat:(NSString *)format 
             completion:(void (^)(NSURL *fileURL, NSError *error))completion;

// 高级分析
- (NSDictionary *)analyzeDailyActivityPatterns:(NSTimeInterval)timeWindow;
- (NSDictionary *)analyzeWeeklyPatterns;
- (NSDictionary *)analyzeFrequentLocations:(NSArray<GPSLocationModel *> *)points radius:(CLLocationDistance)radius;
- (NSDictionary *)analyzePaceConsistency:(NSArray<GPSLocationModel *> *)points;

// 辅助方法
- (NSArray<GPSLocationModel *> *)loadRecordingWithId:(NSString *)recordingId error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END