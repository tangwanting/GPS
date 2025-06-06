/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSDashboardViewController.h"

#pragma mark - GPSDashboardMetric Implementation

@implementation GPSDashboardMetric

- (instancetype)init {
    if (self = [super init]) {
        _name = @"";
        _value = @"0";
        _unit = @"";
        _iconName = @"";
        _color = [UIColor blackColor];
        _isWarning = NO;
        _trendDirection = @"stable";
    }
    return self;
}

+ (instancetype)metricWithName:(NSString *)name value:(NSString *)value unit:(NSString *)unit {
    GPSDashboardMetric *metric = [[GPSDashboardMetric alloc] init];
    metric.name = name;
    metric.value = value;
    metric.unit = unit;
    return metric;
}

@end

#pragma mark - GPSDashboardViewController Interface Extension

@interface GPSDashboardViewController () <MKMapViewDelegate>

// UI元素
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) MKMapView *miniMapView;
@property (nonatomic, strong) UICollectionView *metricsCollectionView;
@property (nonatomic, strong) UIView *controlPanel;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UIView *speedometerView;
@property (nonatomic, strong) UIView *altimeterView;
@property (nonatomic, strong) UIView *compassView;
@property (nonatomic, strong) UILabel *coordinatesLabel;
@property (nonatomic, strong) UIProgressView *routeProgressBar;
@property (nonatomic, strong) UILabel *routeProgressLabel;
@property (nonatomic, strong) UIView *statusBarView;

// 数据
@property (nonatomic, strong) NSMutableArray<GPSDashboardMetric *> *metrics;
@property (nonatomic, strong) GPSLocationModel *currentLocation;
@property (nonatomic, strong) NSDictionary *systemStatus;
@property (nonatomic, assign) double routeProgress;
@property (nonatomic, assign) double remainingDistance;
@property (nonatomic, assign) NSTimeInterval estimatedTime;
@property (nonatomic, strong) NSNumberFormatter *numberFormatter;
@property (nonatomic, strong) NSDateComponentsFormatter *timeFormatter;

@end

#pragma mark - GPSDashboardViewController Implementation

@implementation GPSDashboardViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 初始化属性
    _metrics = [NSMutableArray array];
    _compactMode = NO;
    _darkMode = NO;
    _showSpeedometer = YES;
    _showAltimeter = YES;
    _showCompass = YES;
    _showCoordinates = YES;
    _showRouteProgress = YES;
    
    // 初始化格式化器
    _numberFormatter = [[NSNumberFormatter alloc] init];
    _numberFormatter.numberStyle = NSNumberFormatterDecimalStyle;
    _numberFormatter.maximumFractionDigits = 2;
    
    _timeFormatter = [[NSDateComponentsFormatter alloc] init];
    _timeFormatter.allowedUnits = NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond;
    _timeFormatter.zeroFormattingBehavior = NSDateComponentsFormatterZeroFormattingBehaviorPad;
    _timeFormatter.unitsStyle = NSDateComponentsFormatterUnitsStylePositional;
    
    // 设置界面
    [self setupUI];
    [self updateUIForDisplayMode];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutDashboardElements];
}

#pragma mark - UI Setup

- (void)setupUI {
    // 背景色
    self.view.backgroundColor = [UIColor whiteColor];
    
    // 设置标题视图
    [self setupHeaderView];
    
    // 设置Mini地图
    [self setupMiniMap];
    
    // 设置指标集合视图
    [self setupMetricsCollectionView];
    
    // 设置控制面板
    [self setupControlPanel];
    
    // 设置仪表视图（速度计、高度计、指南针）
    [self setupInstrumentViews];
    
    // 设置坐标标签
    [self setupCoordinatesLabel];
    
    // 设置路线进度条
    [self setupRouteProgressView];
    
    // 设置状态栏
    [self setupStatusBar];
    
    // 添加到主视图
    [self.view addSubview:self.headerView];
    [self.view addSubview:self.miniMapView];
    [self.view addSubview:self.metricsCollectionView];
    [self.view addSubview:self.controlPanel];
    [self.view addSubview:self.speedometerView];
    [self.view addSubview:self.altimeterView];
    [self.view addSubview:self.compassView];
    [self.view addSubview:self.coordinatesLabel];
    [self.view addSubview:self.routeProgressBar];
    [self.view addSubview:self.routeProgressLabel];
    [self.view addSubview:self.statusBarView];
}

- (void)setupHeaderView {
    self.headerView = [[UIView alloc] init];
    
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @"实时仪表盘";
    self.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    
    UIButton *settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [settingsButton setImage:[UIImage systemImageNamed:@"gear"] forState:UIControlStateNormal];
    [settingsButton addTarget:self action:@selector(settingsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.headerView addSubview:self.titleLabel];
    [self.headerView addSubview:settingsButton];
    
    // 这里可使用Auto Layout设置约束
    // 为简洁起见，我们将在layoutDashboardElements方法中进行布局
}

- (void)setupMiniMap {
    self.miniMapView = [[MKMapView alloc] init];
    self.miniMapView.delegate = self;
    self.miniMapView.showsUserLocation = YES;
    self.miniMapView.mapType = MKMapTypeStandard;
    self.miniMapView.layer.cornerRadius = 8.0;
    self.miniMapView.clipsToBounds = YES;
}

- (void)setupMetricsCollectionView {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.scrollDirection = UICollectionViewScrollDirectionVertical;
    layout.minimumInteritemSpacing = 10.0;
    layout.minimumLineSpacing = 10.0;
    
    self.metricsCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    self.metricsCollectionView.backgroundColor = [UIColor clearColor];
    self.metricsCollectionView.delegate = (id<UICollectionViewDelegate>)self;
    self.metricsCollectionView.dataSource = (id<UICollectionViewDataSource>)self;
    
    [self.metricsCollectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"MetricCell"];
}

- (void)setupControlPanel {
    self.controlPanel = [[UIView alloc] init];
    self.controlPanel.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.controlPanel.layer.cornerRadius = 10.0;
    
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:@"开始" forState:UIControlStateNormal];
    [self.startButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    [self.startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    self.pauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pauseButton setTitle:@"暂停" forState:UIControlStateNormal];
    [self.pauseButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
    [self.pauseButton addTarget:self action:@selector(pauseButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.stopButton setTitle:@"停止" forState:UIControlStateNormal];
    [self.stopButton setImage:[UIImage systemImageNamed:@"stop.fill"] forState:UIControlStateNormal];
    [self.stopButton addTarget:self action:@selector(stopButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.controlPanel addSubview:self.startButton];
    [self.controlPanel addSubview:self.pauseButton];
    [self.controlPanel addSubview:self.stopButton];
}

- (void)setupInstrumentViews {
    // 速度计
    self.speedometerView = [[UIView alloc] init];
    self.speedometerView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.speedometerView.layer.cornerRadius = 10.0;
    
    // 高度计
    self.altimeterView = [[UIView alloc] init];
    self.altimeterView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.altimeterView.layer.cornerRadius = 10.0;
    
    // 指南针
    self.compassView = [[UIView alloc] init];
    self.compassView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.compassView.layer.cornerRadius = 10.0;
    
    // 这里可以添加速度计、高度计和指南针的具体UI元素
    // 为简洁起见，此处省略详细实现
}

- (void)setupCoordinatesLabel {
    self.coordinatesLabel = [[UILabel alloc] init];
    self.coordinatesLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.coordinatesLabel.textAlignment = NSTextAlignmentCenter;
    self.coordinatesLabel.text = @"纬度: 0.000000° 经度: 0.000000°";
}

- (void)setupRouteProgressView {
    self.routeProgressBar = [[UIProgressView alloc] init];
    self.routeProgressBar.progressViewStyle = UIProgressViewStyleDefault;
    self.routeProgressBar.progress = 0.0;
    
    self.routeProgressLabel = [[UILabel alloc] init];
    self.routeProgressLabel.font = [UIFont systemFontOfSize:12];
    self.routeProgressLabel.textAlignment = NSTextAlignmentCenter;
    self.routeProgressLabel.text = @"0% 完成 | 剩余 0m | 预计还需 00:00";
}

- (void)setupStatusBar {
    self.statusBarView = [[UIView alloc] init];
    self.statusBarView.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
    self.statusBarView.layer.cornerRadius = 5.0;
    
    // 这里可以添加状态信息的具体UI元素
    // 如GPS信号强度、电池状态等
}

- (void)layoutDashboardElements {
    CGFloat padding = 10.0;
    CGFloat headerHeight = 50.0;
    CGFloat miniMapHeight = 150.0;
    CGFloat controlPanelHeight = 60.0;
    CGFloat instrumentHeight = 100.0;
    CGFloat coordinatesHeight = 20.0;
    CGFloat progressBarHeight = 40.0;
    CGFloat statusBarHeight = 30.0;
    
    // 根据compactMode调整布局
    if (self.compactMode) {
        miniMapHeight = 100.0;
        instrumentHeight = 80.0;
    }
    
    // 布局调整
    CGFloat currentY = padding;
    CGRect bounds = self.view.bounds;
    
    // 头部视图
    self.headerView.frame = CGRectMake(padding, currentY, bounds.size.width - 2 * padding, headerHeight);
    self.titleLabel.frame = CGRectMake(0, 0, self.headerView.bounds.size.width, headerHeight);
    currentY += headerHeight + padding;
    
    // 迷你地图
    self.miniMapView.frame = CGRectMake(padding, currentY, bounds.size.width - 2 * padding, miniMapHeight);
    currentY += miniMapHeight + padding;
    
    // 控制面板
    self.controlPanel.frame = CGRectMake(padding, currentY, bounds.size.width - 2 * padding, controlPanelHeight);
    
    CGFloat buttonWidth = (self.controlPanel.bounds.size.width - 4 * padding) / 3;
    self.startButton.frame = CGRectMake(padding, 10, buttonWidth, controlPanelHeight - 20);
    self.pauseButton.frame = CGRectMake(padding * 2 + buttonWidth, 10, buttonWidth, controlPanelHeight - 20);
    self.stopButton.frame = CGRectMake(padding * 3 + buttonWidth * 2, 10, buttonWidth, controlPanelHeight - 20);
    
    currentY += controlPanelHeight + padding;
    
    // 仪表视图
    if (self.showSpeedometer || self.showAltimeter || self.showCompass) {
        CGFloat instrumentWidth = (bounds.size.width - 4 * padding) / 3;
        
        if (self.showSpeedometer) {
            self.speedometerView.frame = CGRectMake(padding, currentY, instrumentWidth, instrumentHeight);
            self.speedometerView.hidden = NO;
        } else {
            self.speedometerView.hidden = YES;
        }
        
        if (self.showAltimeter) {
            if (self.showSpeedometer) {
                self.altimeterView.frame = CGRectMake(padding * 2 + instrumentWidth, currentY, instrumentWidth, instrumentHeight);
            } else {
                self.altimeterView.frame = CGRectMake(padding, currentY, instrumentWidth, instrumentHeight);
            }
            self.altimeterView.hidden = NO;
        } else {
            self.altimeterView.hidden = YES;
        }
        
        if (self.showCompass) {
            if (self.showSpeedometer && self.showAltimeter) {
                self.compassView.frame = CGRectMake(padding * 3 + instrumentWidth * 2, currentY, instrumentWidth, instrumentHeight);
            } else if (self.showSpeedometer || self.showAltimeter) {
                self.compassView.frame = CGRectMake(padding * 2 + instrumentWidth, currentY, instrumentWidth, instrumentHeight);
            } else {
                self.compassView.frame = CGRectMake(padding, currentY, instrumentWidth, instrumentHeight);
            }
            self.compassView.hidden = NO;
        } else {
            self.compassView.hidden = YES;
        }
        
        currentY += instrumentHeight + padding;
    } else {
        self.speedometerView.hidden = YES;
        self.altimeterView.hidden = YES;
        self.compassView.hidden = YES;
    }
    
    // 坐标标签
    if (self.showCoordinates) {
        self.coordinatesLabel.frame = CGRectMake(padding, currentY, bounds.size.width - 2 * padding, coordinatesHeight);
        self.coordinatesLabel.hidden = NO;
        currentY += coordinatesHeight + padding;
    } else {
        self.coordinatesLabel.hidden = YES;
    }
    
    // 路线进度
    if (self.showRouteProgress) {
        self.routeProgressBar.frame = CGRectMake(padding, currentY, bounds.size.width - 2 * padding, 10);
        self.routeProgressLabel.frame = CGRectMake(padding, currentY + 10, bounds.size.width - 2 * padding, progressBarHeight - 10);
        self.routeProgressBar.hidden = NO;
        self.routeProgressLabel.hidden = NO;
        currentY += progressBarHeight + padding;
    } else {
        self.routeProgressBar.hidden = YES;
        self.routeProgressLabel.hidden = YES;
    }
    
    // 指标集合视图
    CGFloat metricsHeight = bounds.size.height - currentY - statusBarHeight - padding * 2;
    self.metricsCollectionView.frame = CGRectMake(padding, currentY, bounds.size.width - 2 * padding, metricsHeight);
    currentY += metricsHeight + padding;
    
    // 状态栏
    self.statusBarView.frame = CGRectMake(padding, currentY, bounds.size.width - 2 * padding, statusBarHeight);
}

- (void)updateUIForDisplayMode {
    UIColor *backgroundColor = self.darkMode ? [UIColor colorWithWhite:0.1 alpha:1.0] : [UIColor whiteColor];
    UIColor *textColor = self.darkMode ? [UIColor whiteColor] : [UIColor blackColor];
    UIColor *panelColor = self.darkMode ? [UIColor colorWithWhite:0.2 alpha:1.0] : [UIColor colorWithWhite:0.95 alpha:1.0];
    
    self.view.backgroundColor = backgroundColor;
    self.titleLabel.textColor = textColor;
    self.coordinatesLabel.textColor = textColor;
    self.routeProgressLabel.textColor = textColor;
    
    self.controlPanel.backgroundColor = panelColor;
    self.speedometerView.backgroundColor = panelColor;
    self.altimeterView.backgroundColor = panelColor;
    self.compassView.backgroundColor = panelColor;
    self.statusBarView.backgroundColor = panelColor;
    
    // 重新加载指标集合视图
    [self.metricsCollectionView reloadData];
}

#pragma mark - Public Methods

- (void)updateWithLocationData:(GPSLocationModel *)location {
    self.currentLocation = location;
    
    // 更新坐标标签
    self.coordinatesLabel.text = [NSString stringWithFormat:@"纬度: %.6f° 经度: %.6f°", 
                                 location.latitude, location.longitude];
    
    // 更新速度计
    [self updateSpeedometerWithSpeed:location.speed];
    
    // 更新高度计
    [self updateAltimeterWithAltitude:location.altitude];
    
    // 更新指南针
    [self updateCompassWithHeading:location.course];
    
    // 更新地图位置
    [self updateMapWithLocation:location];
}

- (void)updateWithSystemStatus:(NSDictionary *)statusInfo {
    self.systemStatus = statusInfo;
    
    // 根据系统状态更新UI
    [self updateStatusBar];
}

- (void)updateWithRouteProgress:(double)progress remainingDistance:(double)distance estimatedTime:(NSTimeInterval)time {
    self.routeProgress = progress;
    self.remainingDistance = distance;
    self.estimatedTime = time;
    
    // 更新进度条
    self.routeProgressBar.progress = (float)progress;
    
    // 更新进度标签
    NSString *distanceStr;
    if (distance >= 1000) {
        distanceStr = [NSString stringWithFormat:@"%.2f km", distance / 1000.0];
    } else {
        distanceStr = [NSString stringWithFormat:@"%d m", (int)distance];
    }
    
    NSString *timeStr = [self.timeFormatter stringFromTimeInterval:time];
    
    self.routeProgressLabel.text = [NSString stringWithFormat:@"%.0f%% 完成 | 剩余 %@ | 预计还需 %@", 
                                  progress * 100, distanceStr, timeStr];
}

- (void)addMetric:(GPSDashboardMetric *)metric {
    [self.metrics addObject:metric];
    [self.metricsCollectionView reloadData];
}

- (void)updateMetric:(NSString *)metricName withValue:(NSString *)value {
    for (GPSDashboardMetric *metric in self.metrics) {
        if ([metric.name isEqualToString:metricName]) {
            metric.value = value;
            break;
        }
    }
    [self.metricsCollectionView reloadData];
}

- (void)removeMetric:(NSString *)metricName {
    for (NSInteger i = 0; i < self.metrics.count; i++) {
        if ([self.metrics[i].name isEqualToString:metricName]) {
            [self.metrics removeObjectAtIndex:i];
            break;
        }
    }
    [self.metricsCollectionView reloadData];
}

- (void)clearAllMetrics {
    [self.metrics removeAllObjects];
    [self.metricsCollectionView reloadData];
}

#pragma mark - Private Helper Methods

- (void)updateSpeedometerWithSpeed:(double)speed {
    // 更新速度计视图
    // 为简洁起见，这里仅添加一个示例标签
    // 实际应用中可能会有更复杂的图形绘制
    for (UIView *view in self.speedometerView.subviews) {
        [view removeFromSuperview];
    }
    
    UILabel *speedLabel = [[UILabel alloc] initWithFrame:self.speedometerView.bounds];
    speedLabel.textAlignment = NSTextAlignmentCenter;
    speedLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    
    if (speed < 0) {
        speedLabel.text = @"-- km/h";
    } else {
        // 转换为km/h
        double speedKmh = speed * 3.6;
        speedLabel.text = [NSString stringWithFormat:@"%.1f km/h", speedKmh];
    }
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, self.speedometerView.bounds.size.width, 20)];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:12];
    titleLabel.text = @"速度";
    
    [self.speedometerView addSubview:titleLabel];
    [self.speedometerView addSubview:speedLabel];
}

- (void)updateAltimeterWithAltitude:(double)altitude {
    // 更新高度计视图
    for (UIView *view in self.altimeterView.subviews) {
        [view removeFromSuperview];
    }
    
    UILabel *altitudeLabel = [[UILabel alloc] initWithFrame:self.altimeterView.bounds];
    altitudeLabel.textAlignment = NSTextAlignmentCenter;
    altitudeLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    altitudeLabel.text = [NSString stringWithFormat:@"%.1f m", altitude];
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, self.altimeterView.bounds.size.width, 20)];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:12];
    titleLabel.text = @"海拔";
    
    [self.altimeterView addSubview:titleLabel];
    [self.altimeterView addSubview:altitudeLabel];
}

- (void)updateCompassWithHeading:(double)heading {
    // 更新指南针视图
    for (UIView *view in self.compassView.subviews) {
        [view removeFromSuperview];
    }
    
    UILabel *headingLabel = [[UILabel alloc] initWithFrame:self.compassView.bounds];
    headingLabel.textAlignment = NSTextAlignmentCenter;
    headingLabel.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    
    if (heading < 0) {
        headingLabel.text = @"--°";
    } else {
        headingLabel.text = [NSString stringWithFormat:@"%.0f°", heading];
        
        // 添加方向指示
        NSString *direction = @"";
        if (heading >= 337.5 || heading < 22.5) {
            direction = @"北";
        } else if (heading >= 22.5 && heading < 67.5) {
            direction = @"东北";
        } else if (heading >= 67.5 && heading < 112.5) {
            direction = @"东";
        } else if (heading >= 112.5 && heading < 157.5) {
            direction = @"东南";
        } else if (heading >= 157.5 && heading < 202.5) {
            direction = @"南";
        } else if (heading >= 202.5 && heading < 247.5) {
            direction = @"西南";
        } else if (heading >= 247.5 && heading < 292.5) {
            direction = @"西";
        } else if (heading >= 292.5 && heading < 337.5) {
            direction = @"西北";
        }
        
        headingLabel.text = [NSString stringWithFormat:@"%@ %.0f°", direction, heading];
    }
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, self.compassView.bounds.size.width, 20)];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:12];
    titleLabel.text = @"方向";
    
    [self.compassView addSubview:titleLabel];
    [self.compassView addSubview:headingLabel];
}

- (void)updateMapWithLocation:(GPSLocationModel *)location {
    if (!location) return;
    
    CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(location.latitude, location.longitude);
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 300, 300);
    [self.miniMapView setRegion:region animated:YES];
}

- (void)updateStatusBar {
    // 更新状态栏信息
    for (UIView *view in self.statusBarView.subviews) {
        [view removeFromSuperview];
    }
    
    // GPS状态
    NSString *gpsStatus = self.systemStatus[@"gpsStatus"] ?: @"未知";
    UILabel *gpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 100, 20)];
    gpsLabel.font = [UIFont systemFontOfSize:10];
    gpsLabel.text = [NSString stringWithFormat:@"GPS: %@", gpsStatus];
    
    // 电池状态
    NSNumber *batteryLevel = self.systemStatus[@"batteryLevel"];
    UILabel *batteryLabel = [[UILabel alloc] initWithFrame:CGRectMake(120, 5, 100, 20)];
    batteryLabel.font = [UIFont systemFontOfSize:10];
    
    if (batteryLevel) {
        batteryLabel.text = [NSString stringWithFormat:@"电量: %.0f%%", [batteryLevel floatValue] * 100];
    } else {
        batteryLabel.text = @"电量: 未知";
    }
    
    // 记录状态
    NSString *recordingStatus = self.systemStatus[@"recordingStatus"] ?: @"未记录";
    UILabel *recordingLabel = [[UILabel alloc] initWithFrame:CGRectMake(230, 5, 100, 20)];
    recordingLabel.font = [UIFont systemFontOfSize:10];
    recordingLabel.text = [NSString stringWithFormat:@"状态: %@", recordingStatus];
    
    [self.statusBarView addSubview:gpsLabel];
    [self.statusBarView addSubview:batteryLabel];
    [self.statusBarView addSubview:recordingLabel];
    
    // 根据状态调整颜色
    if ([gpsStatus isEqualToString:@"良好"]) {
        gpsLabel.textColor = [UIColor systemGreenColor];
    } else if ([gpsStatus isEqualToString:@"一般"]) {
        gpsLabel.textColor = [UIColor systemYellowColor];
    } else {
        gpsLabel.textColor = [UIColor systemRedColor];
    }
    
    if (batteryLevel && [batteryLevel floatValue] < 0.2) {
        batteryLabel.textColor = [UIColor systemRedColor];
    } else {
        batteryLabel.textColor = self.darkMode ? [UIColor whiteColor] : [UIColor blackColor];
    }
    
    if ([recordingStatus isEqualToString:@"记录中"]) {
        recordingLabel.textColor = [UIColor systemGreenColor];
    } else {
        recordingLabel.textColor = self.darkMode ? [UIColor whiteColor] : [UIColor blackColor];
    }
}

#pragma mark - Button Actions

- (void)startButtonTapped:(UIButton *)sender {
    if ([self.delegate respondsToSelector:@selector(dashboardDidRequestRouteStart)]) {
        [self.delegate dashboardDidRequestRouteStart];
    }
}

- (void)pauseButtonTapped:(UIButton *)sender {
    if ([self.delegate respondsToSelector:@selector(dashboardDidRequestRoutePause)]) {
        [self.delegate dashboardDidRequestRoutePause];
    }
}

- (void)stopButtonTapped:(UIButton *)sender {
    if ([self.delegate respondsToSelector:@selector(dashboardDidRequestRouteStop)]) {
        [self.delegate dashboardDidRequestRouteStop];
    }
}

- (void)settingsButtonTapped:(UIButton *)sender {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"仪表盘设置"
                                                                message:nil
                                                         preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:self.compactMode ? @"标准模式" : @"紧凑模式"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction * _Nonnull action) {
        self.compactMode = !self.compactMode;
        [self layoutDashboardElements];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:self.darkMode ? @"浅色模式" : @"深色模式"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction * _Nonnull action) {
        self.darkMode = !self.darkMode;
        [self updateUIForDisplayMode];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"导出数据"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction * _Nonnull action) {
        [self exportCurrentDataAsCSV:^(NSURL *fileURL, NSError *error) {
            if (error) {
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"导出失败"
                                                                                message:error.localizedDescription
                                                                         preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
            } else {
                UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
                [self presentViewController:activityVC animated:YES completion:nil];
            }
        }];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"截图"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction * _Nonnull action) {
        [self captureScreenshot:^(UIImage *image, NSError *error) {
            if (error) {
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"截图失败"
                                                                                message:error.localizedDescription
                                                                         preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
            } else {
                UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[image] applicationActivities:nil];
                [self presentViewController:activityVC animated:YES completion:nil];
            }
        }];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Export and Share

- (void)exportCurrentDataAsCSV:(void (^)(NSURL *fileURL, NSError *error))completion {
    // 创建CSV内容
    NSMutableString *csvContent = [NSMutableString string];
    [csvContent appendString:@"指标名称,值,单位\n"];
    
    // 添加基本数据
    if (self.currentLocation) {
        [csvContent appendFormat:@"纬度,%.6f,°\n", self.currentLocation.latitude];
        [csvContent appendFormat:@"经度,%.6f,°\n", self.currentLocation.longitude];
        [csvContent appendFormat:@"海拔,%.1f,m\n", self.currentLocation.altitude];
        [csvContent appendFormat:@"速度,%.2f,m/s\n", self.currentLocation.speed];
        [csvContent appendFormat:@"方向,%.1f,°\n", self.currentLocation.course];
    }
    
    // 添加自定义指标
    for (GPSDashboardMetric *metric in self.metrics) {
        [csvContent appendFormat:@"%@,%@,%@\n", metric.name, metric.value, metric.unit];
    }
    
    // 添加路线进度
    [csvContent appendFormat:@"路线进度,%.2f,%%\n", self.routeProgress * 100];
    [csvContent appendFormat:@"剩余距离,%.2f,m\n", self.remainingDistance];
    [csvContent appendFormat:@"预计剩余时间,%.2f,秒\n", self.estimatedTime];
    
    // 创建临时文件
    NSString *fileName = [NSString stringWithFormat:@"dashboard_export_%@.csv", 
                        [NSDateFormatter localizedStringFromDate:[NSDate date] 
                                                     dateStyle:NSDateFormatterShortStyle 
                                                     timeStyle:NSDateFormatterShortStyle]];
    
    fileName = [fileName stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
    fileName = [fileName stringByReplacingOccurrencesOfString:@":" withString:@"-"];
    
    NSURL *tempDir = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    NSURL *fileURL = [tempDir URLByAppendingPathComponent:fileName];
    
    NSError *error = nil;
    [csvContent writeToURL:fileURL atomically:YES encoding:NSUTF8StringEncoding error:&error];
    
    if (completion) {
        completion(error ? nil : fileURL, error);
    }
}

- (void)captureScreenshot:(void (^)(UIImage *image, NSError *error))completion {
    UIGraphicsBeginImageContextWithOptions(self.view.bounds.size, YES, [UIScreen mainScreen].scale);
    [self.view drawViewHierarchyInRect:self.view.bounds afterScreenUpdates:YES];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    if (image) {
        if (completion) {
            completion(image, nil);
        }
    } else {
        NSError *error = [NSError errorWithDomain:@"GPSDashboardErrorDomain" 
                                            code:1 
                                        userInfo:@{NSLocalizedDescriptionKey: @"截图失败"}];
        if (completion) {
            completion(nil, error);
        }
    }
}

#pragma mark - UICollectionView DataSource & Delegate

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.metrics.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"MetricCell" forIndexPath:indexPath];
    
    // 清除旧视图
    for (UIView *view in cell.contentView.subviews) {
        [view removeFromSuperview];
    }
    
    // 配置单元格
    cell.contentView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    cell.contentView.layer.cornerRadius = 8.0;
    cell.contentView.clipsToBounds = YES;
    
    GPSDashboardMetric *metric = self.metrics[indexPath.item];
    
    // 创建指标名称标签
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, cell.contentView.bounds.size.width - 20, 20)];
    nameLabel.font = [UIFont systemFontOfSize:12];
    nameLabel.text = metric.name;
    
    // 创建指标值标签
    UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 25, cell.contentView.bounds.size.width - 20, 30)];
    valueLabel.font = [UIFont boldSystemFontOfSize:22];
    valueLabel.text = [NSString stringWithFormat:@"%@%@", metric.value, metric.unit.length > 0 ? [NSString stringWithFormat:@" %@", metric.unit] : @""];
    
    // 创建趋势图标
    if (metric.trendDirection.length > 0) {
        UIImageView *trendIcon = [[UIImageView alloc] initWithFrame:CGRectMake(cell.contentView.bounds.size.width - 30, 5, 20, 20)];
        
        if ([metric.trendDirection isEqualToString:@"up"]) {
            trendIcon.image = [UIImage systemImageNamed:@"arrow.up"];
            trendIcon.tintColor = [UIColor systemGreenColor];
        } else if ([metric.trendDirection isEqualToString:@"down"]) {
            trendIcon.image = [UIImage systemImageNamed:@"arrow.down"];
            trendIcon.tintColor = [UIColor systemRedColor];
        } else {
            trendIcon.image = [UIImage systemImageNamed:@"arrow.right"];
            trendIcon.tintColor = [UIColor systemGrayColor];
        }
        
        [cell.contentView addSubview:trendIcon];
    }
    
    // 设置颜色
    if (metric.color) {
        valueLabel.textColor = metric.color;
    } else if (metric.isWarning) {
        valueLabel.textColor = [UIColor systemRedColor];
    } else {
        valueLabel.textColor = self.darkMode ? [UIColor whiteColor] : [UIColor blackColor];
    }
    nameLabel.textColor = self.darkMode ? [UIColor lightGrayColor] : [UIColor darkGrayColor];
    
    // 添加图标（如果有）
    if (metric.iconName.length > 0) {
        UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(cell.contentView.bounds.size.width - 30, cell.contentView.bounds.size.height - 30, 25, 25)];
        iconView.image = [UIImage systemImageNamed:metric.iconName];
        iconView.tintColor = [UIColor grayColor];
        [cell.contentView addSubview:iconView];
    }
    
    [cell.contentView addSubview:nameLabel];
    [cell.contentView addSubview:valueLabel];
    
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat width = (collectionView.bounds.size.width - 20) / 2;
    return CGSizeMake(width, 70);
}

#pragma mark - MKMapViewDelegate

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    if ([annotation isKindOfClass:[MKUserLocation class]]) {
        MKAnnotationView *annotationView = [mapView dequeueReusableAnnotationViewWithIdentifier:@"UserLocation"];
        if (!annotationView) {
            annotationView = [[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:@"UserLocation"];
            annotationView.image = [UIImage systemImageNamed:@"location.fill"];
            annotationView.centerOffset = CGPointMake(0, -10);
        }
        return annotationView;
    }
    return nil;
}

#pragma mark - Property Setters

- (void)setCompactMode:(BOOL)compactMode {
    if (_compactMode != compactMode) {
        _compactMode = compactMode;
        [self layoutDashboardElements];
    }
}

- (void)setDarkMode:(BOOL)darkMode {
    if (_darkMode != darkMode) {
        _darkMode = darkMode;
        [self updateUIForDisplayMode];
    }
}

- (void)setShowSpeedometer:(BOOL)showSpeedometer {
    _showSpeedometer = showSpeedometer;
    [self layoutDashboardElements];
}

- (void)setShowAltimeter:(BOOL)showAltimeter {
    _showAltimeter = showAltimeter;
    [self layoutDashboardElements];
}

- (void)setShowCompass:(BOOL)showCompass {
    _showCompass = showCompass;
    [self layoutDashboardElements];
}

- (void)setShowCoordinates:(BOOL)showCoordinates {
    _showCoordinates = showCoordinates;
    [self layoutDashboardElements];
}

- (void)setShowRouteProgress:(BOOL)showRouteProgress {
    _showRouteProgress = showRouteProgress;
    [self layoutDashboardElements];
}

@end