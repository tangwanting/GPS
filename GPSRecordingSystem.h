/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import "GPSLocationModel.h"

// 录制状态枚举
typedef NS_ENUM(NSInteger, GPSRecordingState) {
    GPSRecordingStateIdle,       // 空闲状态
    GPSRecordingStateRecording,  // 正在录制
    GPSRecordingStatePaused      // 暂停录制
};

// 回放状态枚举
typedef NS_ENUM(NSInteger, GPSPlaybackState) {
    GPSPlaybackStateIdle,        // 空闲状态
    GPSPlaybackStatePlaying,     // 正在回放
    GPSPlaybackStatePaused       // 暂停回放
};

// 录制模式枚举
typedef NS_ENUM(NSInteger, GPSRecordingMode) {
    GPSRecordingModeBasic,         // 基本模式：只记录位置
    GPSRecordingModeEnhanced,      // 增强模式：记录位置+基本传感器数据
    GPSRecordingModeComprehensive  // 全面模式：记录全部可用数据
};

// 录制元数据
@interface GPSRecordingMetadata : NSObject

@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *recordingDescription;
@property (nonatomic, strong) NSDate *creationDate;
@property (nonatomic, strong) NSDate *modificationDate;
@property (nonatomic, assign) NSInteger pointCount;
@property (nonatomic, assign) double totalDistance;
@property (nonatomic, assign) double totalDuration;
@property (nonatomic, assign) double maxSpeed;
@property (nonatomic, assign) double avgSpeed;
@property (nonatomic, assign) CLLocationCoordinate2D startCoordinate;
@property (nonatomic, assign) CLLocationCoordinate2D endCoordinate;
@property (nonatomic, strong) NSArray *tags;
@property (nonatomic, strong) NSDictionary *customData;
@property (nonatomic, strong) NSDictionary *metadata;

@end

// 在 GPSRecordingSystem 类声明前添加委托协议
@protocol GPSRecordingDelegate;
@protocol GPSPlaybackDelegate;

@interface GPSRecordingSystem : NSObject

+ (instancetype)sharedInstance;

@property (nonatomic, assign, readonly) GPSRecordingState recordingState;
@property (nonatomic, assign, readonly) GPSPlaybackState playbackState;
@property (nonatomic, weak) id<GPSRecordingDelegate> recordingDelegate;
@property (nonatomic, weak) id<GPSPlaybackDelegate> playbackDelegate;

// 配置属性
@property (nonatomic, assign) GPSRecordingMode recordingMode;
@property (nonatomic, assign) NSTimeInterval recordingInterval;
@property (nonatomic, assign) CLLocationDistance minimumDistance;
@property (nonatomic, assign) BOOL filterNoise;
@property (nonatomic, assign, readonly) double playbackSpeed;

// 初始化存储系统 - 添加这个缺失的方法声明
- (void)setupRecordingStorage;

// 录制管理
- (BOOL)startRecordingWithName:(NSString *)name;
- (void)pauseRecording;
- (void)resumeRecording;
- (void)stopRecording;

// 回放控制
- (BOOL)startPlayback:(NSString *)recordingId;
- (void)pausePlayback;
- (void)resumePlayback;
- (void)stopPlayback;

// 录制管理
- (NSArray<NSString *> *)allRecordings;
- (GPSRecordingMetadata *)metadataForRecording:(NSString *)recordingId;
- (NSArray<GPSLocationModel *> *)dataForRecording:(NSString *)recordingId;
- (BOOL)deleteRecording:(NSString *)recordingId;
- (BOOL)renameRecording:(NSString *)recordingId newName:(NSString *)newName;

// 标记和数据点管理
- (void)addMarkerWithName:(NSString *)name;
- (void)addCustomDataPoint:(NSDictionary *)data;

// 导入/导出
- (void)exportRecording:(NSString *)recordingId toGPX:(void (^)(NSURL *fileURL, NSError *error))completion;
- (BOOL)importFromGPX:(NSURL *)fileURL name:(NSString *)name error:(NSError **)error;

@end

@protocol GPSRecordingDelegate <NSObject>
@optional
- (void)recordingDidStart;
- (void)recordingDidPause;
- (void)recordingDidResume;
- (void)recordingDidStop:(NSString *)recordingId;
- (void)recordingFailedWithError:(NSError *)error;
@end

@protocol GPSPlaybackDelegate <NSObject>
@optional
- (void)playbackDidStart:(NSString *)recordingId;
- (void)playbackDidPause;
- (void)playbackDidResume;
- (void)playbackDidStop;
- (void)playbackDidComplete;
- (void)playbackFailedWithError:(NSError *)error;
- (void)playbackDidUpdateToLocation:(GPSLocationModel *)location atIndex:(NSInteger)index ofTotal:(NSInteger)total;
@end