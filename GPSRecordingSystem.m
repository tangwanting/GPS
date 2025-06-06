/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSRecordingSystem.h"
#import <CoreMotion/CoreMotion.h>

// 文件存储常量
static NSString * const kRecordingsFolderName = @"GPSRecordings";
static NSString * const kMetadataFileName = @"metadata.plist";
static NSString * const kLocationDataFileName = @"locationData.dat";

@implementation GPSRecordingMetadata

- (instancetype)init {
    self = [super init];
    if (self) {
        _creationDate = [NSDate date];
        _modificationDate = [NSDate date];
        _recordingDescription = @"";
        _tags = @[];
        _customData = @{};
    }
    return self;
}

- (instancetype)initWithDictionary:(NSDictionary *)dict {
    self = [super init];
    if (self) {
        _name = dict[@"name"];
        _recordingDescription = dict[@"description"];
        _creationDate = dict[@"creationDate"];
        _modificationDate = dict[@"modificationDate"];
        _pointCount = [dict[@"pointCount"] integerValue];
        _totalDistance = [dict[@"totalDistance"] doubleValue];
        _totalDuration = [dict[@"totalDuration"] doubleValue];
        
        NSDictionary *startCoord = dict[@"startCoordinate"];
        _startCoordinate = CLLocationCoordinate2DMake(
            [startCoord[@"latitude"] doubleValue],
            [startCoord[@"longitude"] doubleValue]
        );
        
        NSDictionary *endCoord = dict[@"endCoordinate"];
        _endCoordinate = CLLocationCoordinate2DMake(
            [endCoord[@"latitude"] doubleValue],
            [endCoord[@"longitude"] doubleValue]
        );
        
        _tags = dict[@"tags"] ?: @[];
        _customData = dict[@"customData"] ?: @{};
    }
    return self;
}

- (NSDictionary *)dictionaryRepresentation {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    
    dict[@"name"] = self.name ?: @"";
    dict[@"description"] = self.recordingDescription ?: @""; // 修改这一行
    dict[@"creationDate"] = self.creationDate;
    dict[@"modificationDate"] = self.modificationDate ?: [NSDate date];
    dict[@"pointCount"] = @(self.pointCount);
    dict[@"totalDistance"] = @(self.totalDistance);
    dict[@"totalDuration"] = @(self.totalDuration);
    
    dict[@"startCoordinate"] = @{
        @"latitude": @(self.startCoordinate.latitude),
        @"longitude": @(self.startCoordinate.longitude)
    };
    
    dict[@"endCoordinate"] = @{
        @"latitude": @(self.endCoordinate.latitude),
        @"longitude": @(self.endCoordinate.longitude)
    };
    
    dict[@"tags"] = self.tags ?: @[];
    dict[@"customData"] = self.customData ?: @{};
    
    return dict;
}

@end

@interface GPSRecordingSystem () <CLLocationManagerDelegate>

// 位置管理器
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CMMotionManager *motionManager;

// 录制状态相关
@property (nonatomic, assign, readwrite) GPSRecordingState recordingState;
@property (nonatomic, assign, readwrite) GPSPlaybackState playbackState;
@property (nonatomic, assign, readwrite) double playbackSpeed; // 使用 readwrite 修饰符
@property (nonatomic, copy) NSString *currentRecordingId;
@property (nonatomic, strong) NSMutableArray<GPSLocationModel *> *currentRecordingData;
@property (nonatomic, strong) GPSRecordingMetadata *currentMetadata;
@property (nonatomic, strong) NSDate *recordingStartTime;
@property (nonatomic, strong) NSDate *lastPauseTime;
@property (nonatomic, assign) NSTimeInterval accumulatedPauseTime;

// 回放相关
@property (nonatomic, strong) NSArray<GPSLocationModel *> *playbackData;
@property (nonatomic, copy) NSString *currentPlaybackId;
@property (nonatomic, assign) NSInteger currentPlaybackIndex;
@property (nonatomic, strong) NSTimer *playbackTimer;

@end

@implementation GPSRecordingSystem

#pragma mark - 初始化与单例

+ (instancetype)sharedInstance {
    static GPSRecordingSystem *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 初始化状态
        _recordingState = GPSRecordingStateIdle;
        _playbackState = GPSPlaybackStateIdle;
        
        // 初始化设置默认值
        _recordingMode = GPSRecordingModeBasic;
        _recordingInterval = 1.0;  // 默认1秒一次
        _minimumDistance = 5.0;    // 默认5米
        _filterNoise = YES;
        _playbackSpeed = 1.0;
        
        // 初始化位置管理器
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        _locationManager.distanceFilter = _minimumDistance;
        
        // 初始化动作管理器
        _motionManager = [[CMMotionManager alloc] init];
        
        // 创建必要文件夹
        [self createRecordingsDirectoryIfNeeded];
    }
    return self;
}

#pragma mark - 文件系统管理

- (NSURL *)recordingsFolderURL {
    NSURL *documentDir = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory
                                                                inDomains:NSUserDomainMask].firstObject;
    return [documentDir URLByAppendingPathComponent:kRecordingsFolderName isDirectory:YES];
}

- (void)createRecordingsDirectoryIfNeeded {
    NSURL *folderURL = [self recordingsFolderURL];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:folderURL.path]) {
        NSError *error = nil;
        [[NSFileManager defaultManager] createDirectoryAtURL:folderURL
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&error];
        if (error) {
            NSLog(@"创建录制数据目录失败: %@", error.localizedDescription);
        }
    }
}

- (NSURL *)folderURLForRecording:(NSString *)recordingId {
    return [[self recordingsFolderURL] URLByAppendingPathComponent:recordingId isDirectory:YES];
}

- (BOOL)createFolderForRecording:(NSString *)recordingId {
    NSURL *folderURL = [self folderURLForRecording:recordingId];
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtURL:folderURL
                                            withIntermediateDirectories:YES
                                                             attributes:nil
                                                                  error:&error];
    if (!success) {
        NSLog(@"为录制 %@ 创建文件夹失败: %@", recordingId, error.localizedDescription);
    }
    return success;
}

- (BOOL)saveMetadata:(GPSRecordingMetadata *)metadata forRecordingId:(NSString *)recordingId {
    NSURL *folderURL = [self folderURLForRecording:recordingId];
    NSURL *metadataURL = [folderURL URLByAppendingPathComponent:kMetadataFileName];
    
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[metadata dictionaryRepresentation]
                                         requiringSecureCoding:NO
                                                         error:&error];
    
    if (error || !data) {
        NSLog(@"序列化元数据失败: %@", error.localizedDescription);
        return NO;
    }
    
    BOOL success = [data writeToURL:metadataURL options:NSDataWritingAtomic error:&error];
    if (!success) {
        NSLog(@"保存元数据失败: %@", error.localizedDescription);
    }
    return success;
}

- (BOOL)saveLocationData:(NSArray<GPSLocationModel *> *)locationData forRecordingId:(NSString *)recordingId {
    NSURL *folderURL = [self folderURLForRecording:recordingId];
    NSURL *dataURL = [folderURL URLByAppendingPathComponent:kLocationDataFileName];
    
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:locationData
                                         requiringSecureCoding:NO
                                                         error:&error];
    
    if (error || !data) {
        NSLog(@"序列化位置数据失败: %@", error.localizedDescription);
        return NO;
    }
    
    BOOL success = [data writeToURL:dataURL options:NSDataWritingAtomic error:&error];
    if (!success) {
        NSLog(@"保存位置数据失败: %@", error.localizedDescription);
    }
    return success;
}

- (GPSRecordingMetadata *)loadMetadataForRecording:(NSString *)recordingId {
    NSURL *folderURL = [self folderURLForRecording:recordingId];
    NSURL *metadataURL = [folderURL URLByAppendingPathComponent:kMetadataFileName];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:metadataURL.path]) {
        return nil;
    }
    
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:metadataURL options:0 error:&error];
    
    if (!data || error) {
        NSLog(@"读取元数据失败: %@", error.localizedDescription);
        return nil;
    }
    
    NSDictionary *dict = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSDictionary class]
                                                           fromData:data
                                                              error:&error];
    
    if (!dict || error) {
        NSLog(@"解析元数据失败: %@", error.localizedDescription);
        return nil;
    }
    
    return [[GPSRecordingMetadata alloc] initWithDictionary:dict];
}

- (NSArray<GPSLocationModel *> *)loadLocationDataForRecording:(NSString *)recordingId {
    NSURL *folderURL = [self folderURLForRecording:recordingId];
    NSURL *dataURL = [folderURL URLByAppendingPathComponent:kLocationDataFileName];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:dataURL.path]) {
        return @[];
    }
    
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:dataURL options:0 error:&error];
    
    if (!data || error) {
        NSLog(@"读取位置数据失败: %@", error.localizedDescription);
        return @[];
    }
    
    NSArray *locationData = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSArray class]
                                                              fromData:data
                                                                 error:&error];
    
    if (!locationData || error) {
        NSLog(@"解析位置数据失败: %@", error.localizedDescription);
        return @[];
    }
    
    return locationData;
}

#pragma mark - 录制控制

- (void)startRecordingWithName:(NSString *)name {
    // 如果当前正在录制，先停止
    if (self.recordingState != GPSRecordingStateIdle) {
        [self stopRecording];
    }
    
    // 创建新录制ID (时间戳+随机字符串)
    self.currentRecordingId = [NSString stringWithFormat:@"%@_%@",
                              @(([[NSDate date] timeIntervalSince1970] * 1000)),
                              [[NSUUID UUID] UUIDString]];
    
    // 创建文件夹
    if (![self createFolderForRecording:self.currentRecordingId]) {
        if ([self.recordingDelegate respondsToSelector:@selector(recordingFailedWithError:)]) {
            NSError *error = [NSError errorWithDomain:@"com.gpsplusplus.recording"
                                                 code:1001
                                             userInfo:@{NSLocalizedDescriptionKey: @"创建录制文件夹失败"}];
            [self.recordingDelegate recordingFailedWithError:error];
        }
        return;
    }
    
    // 初始化录制数据
    self.currentRecordingData = [NSMutableArray array];
    
    // 初始化元数据
    self.currentMetadata = [[GPSRecordingMetadata alloc] init];
    self.currentMetadata.name = name ?: [NSString stringWithFormat:@"录制 %@", [NSDate date]];
    
    // 记录开始时间
    self.recordingStartTime = [NSDate date];
    self.accumulatedPauseTime = 0;
    
    // 配置位置管理器
    self.locationManager.distanceFilter = self.minimumDistance;
    
    if (self.recordingMode == GPSRecordingModeEnhanced || 
        self.recordingMode == GPSRecordingModeComprehensive) {
        // 启动传感器
        [self startSensors];
    }
    
    // 开始位置更新
    [self.locationManager startUpdatingLocation];
    
    // 更新状态
    self.recordingState = GPSRecordingStateRecording;
    
    // 通知代理
    if ([self.recordingDelegate respondsToSelector:@selector(recordingDidStart)]) {
        [self.recordingDelegate recordingDidStart];
    }
}

- (void)pauseRecording {
    if (self.recordingState != GPSRecordingStateRecording) {
        return;
    }
    
    // 记录暂停时间
    self.lastPauseTime = [NSDate date];
    
    // 停止位置更新
    [self.locationManager stopUpdatingLocation];
    
    // 停止传感器
    if (self.recordingMode != GPSRecordingModeBasic) {
        [self stopSensors];
    }
    
    // 更新状态
    self.recordingState = GPSRecordingStatePaused;
    
    // 通知代理
    if ([self.recordingDelegate respondsToSelector:@selector(recordingDidPause)]) {
        [self.recordingDelegate recordingDidPause];
    }
}

- (void)resumeRecording {
    if (self.recordingState != GPSRecordingStatePaused) {
        return;
    }
    
    // 计算累计暂停时间
    if (self.lastPauseTime) {
        self.accumulatedPauseTime += [[NSDate date] timeIntervalSinceDate:self.lastPauseTime];
    }
    
    // 重新开始位置更新
    [self.locationManager startUpdatingLocation];
    
    // 重新开始传感器
    if (self.recordingMode != GPSRecordingModeBasic) {
        [self startSensors];
    }
    
    // 更新状态
    self.recordingState = GPSRecordingStateRecording;
    
    // 通知代理
    if ([self.recordingDelegate respondsToSelector:@selector(recordingDidResume)]) {
        [self.recordingDelegate recordingDidResume];
    }
}

- (void)stopRecording {
    if (self.recordingState == GPSRecordingStateIdle) {
        return;
    }
    
    // 停止位置更新
    [self.locationManager stopUpdatingLocation];
    
    // 停止传感器
    if (self.recordingMode != GPSRecordingModeBasic) {
        [self stopSensors];
    }
    
    // 完成元数据
    NSTimeInterval duration;
    if (self.recordingState == GPSRecordingStatePaused) {
        duration = [self.lastPauseTime timeIntervalSinceDate:self.recordingStartTime] - self.accumulatedPauseTime;
    } else {
        duration = [[NSDate date] timeIntervalSinceDate:self.recordingStartTime] - self.accumulatedPauseTime;
    }
    
    self.currentMetadata.totalDuration = duration;
    self.currentMetadata.pointCount = self.currentRecordingData.count;
    
    // 计算总距离
    CLLocationDistance totalDistance = 0;
    for (NSInteger i = 1; i < self.currentRecordingData.count; i++) {
        GPSLocationModel *prevLocation = self.currentRecordingData[i-1];
        GPSLocationModel *currLocation = self.currentRecordingData[i];
        
        CLLocation *prev = [[CLLocation alloc] initWithLatitude:prevLocation.coordinate.latitude 
                                                      longitude:prevLocation.coordinate.longitude];
        CLLocation *curr = [[CLLocation alloc] initWithLatitude:currLocation.coordinate.latitude 
                                                      longitude:currLocation.coordinate.longitude];
        
        totalDistance += [prev distanceFromLocation:curr];
    }
    self.currentMetadata.totalDistance = totalDistance;
    
    // 设置开始和结束坐标
    if (self.currentRecordingData.count > 0) {
        self.currentMetadata.startCoordinate = self.currentRecordingData.firstObject.coordinate;
        self.currentMetadata.endCoordinate = self.currentRecordingData.lastObject.coordinate;
    }
    
    // 保存数据
    NSString *recordingId = self.currentRecordingId;
    BOOL saveSuccess = [self saveMetadata:self.currentMetadata forRecordingId:recordingId] &&
                      [self saveLocationData:self.currentRecordingData forRecordingId:recordingId];
    
    // 清除当前录制数据
    self.currentRecordingId = nil;
    self.currentRecordingData = nil;
    self.currentMetadata = nil;
    self.recordingStartTime = nil;
    self.lastPauseTime = nil;
    
    // 更新状态
    self.recordingState = GPSRecordingStateIdle;
    
    // 通知代理
    if ([self.recordingDelegate respondsToSelector:@selector(recordingDidStop:)]) {
        if (saveSuccess) {
            [self.recordingDelegate recordingDidStop:recordingId];
        } else {
            NSError *error = [NSError errorWithDomain:@"com.gpsplusplus.recording"
                                                 code:1002
                                             userInfo:@{NSLocalizedDescriptionKey: @"保存录制数据失败"}];
            [self.recordingDelegate recordingFailedWithError:error];
        }
    }
}

- (void)cancelRecording {
    if (self.recordingState == GPSRecordingStateIdle) {
        return;
    }
    
    // 停止位置更新
    [self.locationManager stopUpdatingLocation];
    
    // 停止传感器
    if (self.recordingMode != GPSRecordingModeBasic) {
        [self stopSensors];
    }
    
    // 删除已创建的文件夹
    if (self.currentRecordingId) {
        NSURL *folderURL = [self folderURLForRecording:self.currentRecordingId];
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtURL:folderURL error:&error];
        if (error) {
            NSLog(@"删除取消的录制数据失败: %@", error.localizedDescription);
        }
    }
    
    // 清除当前录制数据
    self.currentRecordingId = nil;
    self.currentRecordingData = nil;
    self.currentMetadata = nil;
    self.recordingStartTime = nil;
    self.lastPauseTime = nil;
    
    // 更新状态
    self.recordingState = GPSRecordingStateIdle;
}

- (void)addMarkerWithName:(NSString *)name {
    if (self.recordingState != GPSRecordingStateRecording || !self.currentRecordingData.count) {
        return;
    }
    
    // 获取最新位置
    GPSLocationModel *lastLocation = [self.currentRecordingData lastObject];
    
    // 添加标记信息
    NSMutableDictionary *markers = [NSMutableDictionary dictionaryWithDictionary:lastLocation.metadata ?: @{}];
    markers[@"isMarker"] = @YES;
    markers[@"markerName"] = name ?: @"标记点";
    markers[@"markerTime"] = [NSDate date];
    
    lastLocation.metadata = markers;
}

- (void)addCustomDataPoint:(NSDictionary *)data {
    if (self.recordingState != GPSRecordingStateRecording || !self.currentRecordingData.count) {
        return;
    }
    
    // 获取最新位置
    GPSLocationModel *lastLocation = [self.currentRecordingData lastObject];
    
    // 合并自定义数据
    NSMutableDictionary *metadata = [NSMutableDictionary dictionaryWithDictionary:lastLocation.metadata ?: @{}];
    [metadata addEntriesFromDictionary:data ?: @{}];
    
    lastLocation.metadata = metadata;
}

#pragma mark - 传感器管理

- (void)startSensors {
    if (self.motionManager.isDeviceMotionAvailable) {
        [self.motionManager startDeviceMotionUpdatesToQueue:[NSOperationQueue mainQueue]
                                               withHandler:^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error) {
            // 处理传感器数据 (在 CLLocationManagerDelegate 中结合位置数据一起处理)
        }];
    }
}

- (void)stopSensors {
    if (self.motionManager.isDeviceMotionActive) {
        [self.motionManager stopDeviceMotionUpdates];
    }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    if (self.recordingState != GPSRecordingStateRecording) {
        return;
    }
    
    for (CLLocation *location in locations) {
        // 过滤质量不佳的数据
        if (self.filterNoise && location.horizontalAccuracy < 0) {
            continue;
        }
        
        GPSLocationModel *locationModel = [[GPSLocationModel alloc] init];
        locationModel.coordinate = location.coordinate;
        locationModel.altitude = location.altitude;
        locationModel.timestamp = location.timestamp;
        locationModel.speed = location.speed;
        locationModel.course = location.course;
        locationModel.horizontalAccuracy = location.horizontalAccuracy;
        locationModel.verticalAccuracy = location.verticalAccuracy;
        
        // 如果是增强模式，添加传感器数据
        if (self.recordingMode != GPSRecordingModeBasic && self.motionManager.isDeviceMotionActive) {
            CMDeviceMotion *motion = self.motionManager.deviceMotion;
            
            if (motion) {
                NSMutableDictionary *sensorData = [NSMutableDictionary dictionary];
                
                // 加入基本传感器数据
                sensorData[@"attitude"] = @{
                    @"pitch": @(motion.attitude.pitch),
                    @"roll": @(motion.attitude.roll),
                    @"yaw": @(motion.attitude.yaw)
                };
                
                sensorData[@"gravity"] = @{
                    @"x": @(motion.gravity.x),
                    @"y": @(motion.gravity.y),
                    @"z": @(motion.gravity.z)
                };
                
                // 如果是全面模式，添加更多数据
                if (self.recordingMode == GPSRecordingModeComprehensive) {
                    sensorData[@"acceleration"] = @{
                        @"x": @(motion.userAcceleration.x),
                        @"y": @(motion.userAcceleration.y),
                        @"z": @(motion.userAcceleration.z)
                    };
                    
                    sensorData[@"rotation"] = @{
                        @"x": @(motion.rotationRate.x),
                        @"y": @(motion.rotationRate.y),
                        @"z": @(motion.rotationRate.z)
                    };
                    
                    sensorData[@"magneticField"] = @{
                        @"accuracy": @(motion.magneticField.accuracy),
                        @"x": @(motion.magneticField.field.x),
                        @"y": @(motion.magneticField.field.y),
                        @"z": @(motion.magneticField.field.z)
                    };
                }
                
                locationModel.sensorData = sensorData;
            }
        }
        
        [self.currentRecordingData addObject:locationModel];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    NSLog(@"位置更新错误: %@", error.localizedDescription);
    
    if ([self.recordingDelegate respondsToSelector:@selector(recordingFailedWithError:)]) {
        [self.recordingDelegate recordingFailedWithError:error];
    }
}

#pragma mark - 回放控制

- (void)startPlayback:(NSString *)recordingId {
    if (self.playbackState != GPSPlaybackStateIdle) {
        [self stopPlayback];
    }
    
    // 加载回放数据
    self.playbackData = [self loadLocationDataForRecording:recordingId];
    
    if (self.playbackData.count == 0) {
        if ([self.playbackDelegate respondsToSelector:@selector(playbackFailedWithError:)]) {
            NSError *error = [NSError errorWithDomain:@"com.gpsplusplus.playback"
                                                 code:2001
                                             userInfo:@{NSLocalizedDescriptionKey: @"未找到录制数据"}];
            [self.playbackDelegate playbackFailedWithError:error];
        }
        return;
    }
    
    self.currentPlaybackId = recordingId;
    self.currentPlaybackIndex = 0;
    
    // 设置播放速度
    if (self.playbackSpeed <= 0) {
        self.playbackSpeed = 1.0;
    }
    
    // 启动回放定时器
    [self startPlaybackTimer];
    
    // 更新状态
    self.playbackState = GPSPlaybackStatePlaying;
    
    // 通知代理
    if ([self.playbackDelegate respondsToSelector:@selector(playbackDidStart:)]) {
        [self.playbackDelegate playbackDidStart:recordingId];
    }
    
    // 更新第一个位置
    [self updatePlaybackPositionToCurrentIndex];
}

- (void)pausePlayback {
    if (self.playbackState != GPSPlaybackStatePlaying) {
        return;
    }
    
    // 停止定时器
    [self stopPlaybackTimer];
    
    // 更新状态
    self.playbackState = GPSPlaybackStatePaused;
    
    // 通知代理
    if ([self.playbackDelegate respondsToSelector:@selector(playbackDidPause)]) {
        [self.playbackDelegate playbackDidPause];
    }
}

- (void)resumePlayback {
    if (self.playbackState != GPSPlaybackStatePaused) {
        return;
    }
    
    // 重新启动定时器
    [self startPlaybackTimer];
    
    // 更新状态
    self.playbackState = GPSPlaybackStatePlaying;
    
    // 通知代理
    if ([self.playbackDelegate respondsToSelector:@selector(playbackDidResume)]) {
        [self.playbackDelegate playbackDidResume];
    }
}

- (void)stopPlayback {
    if (self.playbackState == GPSPlaybackStateIdle) {
        return;
    }
    
    // 停止定时器
    [self stopPlaybackTimer];
    
    // 清理数据
    self.playbackData = nil;
    self.currentPlaybackId = nil;
    
    // 更新状态
    self.playbackState = GPSPlaybackStateIdle;
    
    // 通知代理
    if ([self.playbackDelegate respondsToSelector:@selector(playbackDidStop)]) {
        [self.playbackDelegate playbackDidStop];
    }
}

- (void)seekToPosition:(double)progress {
    if (self.playbackState == GPSPlaybackStateIdle || !self.playbackData.count) {
        return;
    }
    
    // 验证进度值有效
    progress = MAX(0.0, MIN(1.0, progress));
    
    // 计算新索引
    NSInteger newIndex = (NSInteger)round(progress * (self.playbackData.count - 1));
    self.currentPlaybackIndex = newIndex;
    
    // 更新位置
    [self updatePlaybackPositionToCurrentIndex];
}

- (void)setPlaybackSpeed:(double)speed {
    // 确保速度在有效范围内
    speed = MAX(0.25, MIN(4.0, speed));
    
    _playbackSpeed = speed;
    
    // 如果当前正在回放，需要重启定时器以应用新速度
    if (self.playbackState == GPSPlaybackStatePlaying) {
        [self stopPlaybackTimer];
        [self startPlaybackTimer];
    }
}

- (void)startPlaybackTimer {
    [self.playbackTimer invalidate];
    
    // 计算平均时间间隔
    NSTimeInterval interval = 1.0 / self.playbackSpeed;
    
    self.playbackTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                         target:self
                                                       selector:@selector(playbackTimerFired:)
                                                       userInfo:nil
                                                        repeats:YES];
}

- (void)stopPlaybackTimer {
    [self.playbackTimer invalidate];
    self.playbackTimer = nil;
}

- (void)playbackTimerFired:(NSTimer *)timer {
    // 前进到下一个索引
    self.currentPlaybackIndex++;
    
    // 检查是否完成
    if (self.currentPlaybackIndex >= self.playbackData.count) {
        // 回放完成
        [self stopPlaybackTimer];
        self.playbackState = GPSPlaybackStateIdle;
        
        if ([self.playbackDelegate respondsToSelector:@selector(playbackDidComplete)]) {
            [self.playbackDelegate playbackDidComplete];
        }
        
        return;
    }
    
    [self updatePlaybackPositionToCurrentIndex];
}

- (void)updatePlaybackPositionToCurrentIndex {
    if (!self.playbackData.count || self.currentPlaybackIndex >= self.playbackData.count) {
        return;
    }
    
    GPSLocationModel *location = self.playbackData[self.currentPlaybackIndex];
    
    if ([self.playbackDelegate respondsToSelector:@selector(playbackDidUpdateToLocation:atIndex:ofTotal:)]) {
        [self.playbackDelegate playbackDidUpdateToLocation:location
                                                  atIndex:self.currentPlaybackIndex
                                                 ofTotal:self.playbackData.count];
    }
}

#pragma mark - 录制管理

- (NSArray<NSString *> *)allRecordings {
    NSURL *folderURL = [self recordingsFolderURL];
    
    NSError *error = nil;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:folderURL
                                                      includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                                                                         options:0
                                                                           error:&error];
    if (error) {
        NSLog(@"获取录制列表失败: %@", error.localizedDescription);
        return @[];
    }
    
    NSMutableArray *recordings = [NSMutableArray array];
    
    for (NSURL *itemURL in contents) {
        NSNumber *isDirectory = nil;
        [itemURL getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        
        if ([isDirectory boolValue]) {
            [recordings addObject:[itemURL lastPathComponent]];
        }
    }
    
    return recordings;
}

- (GPSRecordingMetadata *)metadataForRecording:(NSString *)recordingId {
    return [self loadMetadataForRecording:recordingId];
}

- (NSArray<GPSLocationModel *> *)dataForRecording:(NSString *)recordingId {
    return [self loadLocationDataForRecording:recordingId];
}

- (BOOL)deleteRecording:(NSString *)recordingId {
    NSURL *folderURL = [self folderURLForRecording:recordingId];
    
    NSError *error = nil;
    BOOL success = [[NSFileManager defaultManager] removeItemAtURL:folderURL error:&error];
    
    if (!success) {
        NSLog(@"删除录制 %@ 失败: %@", recordingId, error.localizedDescription);
    }
    
    return success;
}

- (BOOL)renameRecording:(NSString *)recordingId newName:(NSString *)newName {
    GPSRecordingMetadata *metadata = [self metadataForRecording:recordingId];
    
    if (!metadata) {
        return NO;
    }
    
    metadata.name = newName;
    metadata.modificationDate = [NSDate date];
    
    return [self saveMetadata:metadata forRecordingId:recordingId];
}

- (BOOL)updateMetadata:(GPSRecordingMetadata *)metadata forRecording:(NSString *)recordingId {
    if (!metadata) {
        return NO;
    }
    
    metadata.modificationDate = [NSDate date];
    return [self saveMetadata:metadata forRecordingId:recordingId];
}

#pragma mark - 导入导出

- (void)exportRecording:(NSString *)recordingId toGPX:(void (^)(NSURL * _Nonnull, NSError * _Nullable))completion {
    [self exportRecording:recordingId toFormat:@"gpx" completion:completion];
}

- (void)exportRecording:(NSString *)recordingId toFormat:(NSString *)format completion:(void (^)(NSURL * _Nonnull, NSError * _Nullable))completion {
    // 获取录制数据
    GPSRecordingMetadata *metadata = [self metadataForRecording:recordingId];
    NSArray<GPSLocationModel *> *locationData = [self dataForRecording:recordingId];
    
    if (!metadata || locationData.count == 0) {
        NSError *error = [NSError errorWithDomain:@"com.gpsplusplus.export"
                                             code:3001
                                         userInfo:@{NSLocalizedDescriptionKey: @"未找到录制数据或数据为空"}];
        if (completion) {
            completion(nil, error);
        }
        return;
    }
    
    // 暂时仅支持GPX格式
    if ([format.lowercaseString isEqualToString:@"gpx"]) {
        [self exportToGPX:recordingId metadata:metadata locationData:locationData completion:completion];
    } else {
        NSError *error = [NSError errorWithDomain:@"com.gpsplusplus.export"
                                             code:3002
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"不支持的导出格式: %@", format]}];
        if (completion) {
            completion(nil, error);
        }
    }
}

- (void)exportToGPX:(NSString *)recordingId 
           metadata:(GPSRecordingMetadata *)metadata 
       locationData:(NSArray<GPSLocationModel *> *)locationData 
         completion:(void (^)(NSURL *, NSError *))completion {
    
    // 创建GPX格式文件
    NSMutableString *gpxContent = [NSMutableString string];
    
    // GPX头
    [gpxContent appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [gpxContent appendString:@"<gpx version=\"1.1\" creator=\"GPS++ 2.0\" xmlns=\"http://www.topografix.com/GPX/1/1\">\n"];
    
    // 元数据
    [gpxContent appendString:@"  <metadata>\n"];
    [gpxContent appendFormat:@"    <name>%@</name>\n", metadata.name ?: @""];
    [gpxContent appendFormat:@"    <desc>%@</desc>\n", metadata.description ?: @""];
    [gpxContent appendFormat:@"    <time>%@</time>\n", [self formatDateForGPX:metadata.creationDate]];
    [gpxContent appendString:@"  </metadata>\n"];
    
    // 轨迹
    [gpxContent appendString:@"  <trk>\n"];
    [gpxContent appendFormat:@"    <name>%@</name>\n", metadata.name ?: @""];
    [gpxContent appendString:@"    <trkseg>\n"];
    
    // 添加轨迹点
    for (GPSLocationModel *location in locationData) {
        [gpxContent appendString:@"      <trkpt"];
        [gpxContent appendFormat:@" lat=\"%f\" lon=\"%f\">\n", location.coordinate.latitude, location.coordinate.longitude];
        [gpxContent appendFormat:@"        <ele>%f</ele>\n", location.altitude];
        [gpxContent appendFormat:@"        <time>%@</time>\n", [self formatDateForGPX:location.timestamp]];
        
        if (location.speed >= 0) {
            [gpxContent appendFormat:@"        <speed>%f</speed>\n", location.speed];
        }
        
        if (location.course >= 0) {
            [gpxContent appendFormat:@"        <course>%f</course>\n", location.course];
        }
        
        // 处理标记点
        if (location.metadata && location.metadata[@"isMarker"]) {
            [gpxContent appendString:@"        <extensions>\n"];
            [gpxContent appendFormat:@"          <marker>%@</marker>\n", location.metadata[@"markerName"] ?: @"Marker"];
            [gpxContent appendString:@"        </extensions>\n"];
        }
        
        [gpxContent appendString:@"      </trkpt>\n"];
    }
    
    // 结束标签
    [gpxContent appendString:@"    </trkseg>\n"];
    [gpxContent appendString:@"  </trk>\n"];
    [gpxContent appendString:@"</gpx>\n"];
    
    // 创建导出文件路径
    NSString *fileName = [NSString stringWithFormat:@"%@.gpx", metadata.name ?: recordingId];
    fileName = [fileName stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    fileName = [fileName stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    
    NSURL *documentsURL = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory 
                                                                 inDomains:NSUserDomainMask].firstObject;
    NSURL *exportURL = [documentsURL URLByAppendingPathComponent:fileName];
    
    // 写入文件
    NSError *error = nil;
    [gpxContent writeToURL:exportURL atomically:YES encoding:NSUTF8StringEncoding error:&error];
    
    if (completion) {
        completion(error ? nil : exportURL, error);
    }
}

- (NSString *)formatDateForGPX:(NSDate *)date {
    if (!date) {
        return @"";
    }
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
    return [formatter stringFromDate:date];
}

- (void)importFromGPX:(NSURL *)fileURL completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    [self importFromFormat:@"gpx" fileURL:fileURL completion:completion];
}

- (void)importFromFormat:(NSString *)format fileURL:(NSURL *)fileURL completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    // 检查文件是否存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path]) {
        NSError *error = [NSError errorWithDomain:@"com.gpsplusplus.import"
                                             code:4001
                                         userInfo:@{NSLocalizedDescriptionKey: @"导入文件不存在"}];
        if (completion) {
            completion(nil, error);
        }
        return;
    }
    
    // 暂时仅支持GPX格式
    if ([format.lowercaseString isEqualToString:@"gpx"]) {
        [self importFromGPXFile:fileURL completion:completion];
    } else {
        NSError *error = [NSError errorWithDomain:@"com.gpsplusplus.import"
                                             code:4002
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"不支持的导入格式: %@", format]}];
        if (completion) {
            completion(nil, error);
        }
    }
}

- (void)importFromGPXFile:(NSURL *)fileURL completion:(void (^)(NSString * _Nullable, NSError * _Nullable))completion {
    // 暂时采用简单实现，在实际应用中应使用XML解析器
    // 此处仅为示例框架
    
    NSError *error = nil;
    NSString *gpxContent = [NSString stringWithContentsOfURL:fileURL encoding:NSUTF8StringEncoding error:&error];
    
    if (error) {
        if (completion) {
            completion(nil, error);
        }
        return;
    }
    
    // 创建新录制ID
    NSString *recordingId = [NSString stringWithFormat:@"import_%@_%@",
                            @(([[NSDate date] timeIntervalSince1970] * 1000)),
                            [[NSUUID UUID] UUIDString]];
    
    // 创建文件夹
    if (![self createFolderForRecording:recordingId]) {
        NSError *folderError = [NSError errorWithDomain:@"com.gpsplusplus.import"
                                                   code:4003
                                               userInfo:@{NSLocalizedDescriptionKey: @"创建导入数据文件夹失败"}];
        if (completion) {
            completion(nil, folderError);
        }
        return;
    }
    
    // TODO: 解析GPX文件，提取位置数据和元数据
    // 这里需要完整的XML解析逻辑，示例代码略
    
    // 临时模拟导入成功
    GPSRecordingMetadata *metadata = [[GPSRecordingMetadata alloc] init];
    metadata.name = [fileURL.lastPathComponent stringByDeletingPathExtension];
    metadata.recordingDescription = @"从GPX文件导入";
    metadata.creationDate = [NSDate date];
    
    // 解析GPX的逻辑应放在此处
    // ...
    
    // 保存元数据
    BOOL saveSuccess = [self saveMetadata:metadata forRecordingId:recordingId];
    
    if (saveSuccess) {
        if (completion) {
            completion(recordingId, nil);
        }
    } else {
        NSError *saveError = [NSError errorWithDomain:@"com.gpsplusplus.import"
                                                 code:4004
                                             userInfo:@{NSLocalizedDescriptionKey: @"保存导入数据失败"}];
        if (completion) {
            completion(nil, saveError);
        }
    }
}

@end