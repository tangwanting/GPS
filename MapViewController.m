/*
 * GPS++
 * 有问题 联系pxx917144686
 */

// 基础框架
#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>

// 系统扩展框架
#import <objc/runtime.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <QuartzCore/QuartzCore.h>  // 用于改进动画效果
#import <CoreMotion/CoreMotion.h>  // CoreMotion 框架，解决 CMDeviceMotion 类型问题

// 应用模型层
#import "GPSLocationModel.h"
#import "GPSRouteManager.h"

// 应用工具层
#import "GPSCoordinateUtils.h"

// 应用视图模型层
#import "GPSLocationViewModel.h"

#import "GPSRecordingSystem.h"
#import "GPSAnalyticsSystem.h"
#import "GPSGeofencingSystem.h"
#import "GPSAdvancedLocationSimulator.h" // 模拟器类
#import "GPSAdvancedMapController.h"     // 地图控制器类
#import "GPSDashboardViewController.h"   // 仪表盘控制器
#import "GPSSystemIntegration.h"         // 系统集成
#import "GPSExtensions.h"                // 扩展声明
#import "MapViewController.h"

// 支持iOS 15或更高版本定位框架
#ifdef __IPHONE_15_0
#import <CoreLocationUI/CoreLocationUI.h>
#endif

@interface GPSAdvancedMapController (CoordinateAdditions)
- (void)addPolygonGeofence:(NSArray<NSValue *> *)coordinates identifier:(NSString *)identifier;
@end

@interface MapViewController () <MKMapViewDelegate, UISearchBarDelegate, CLLocationManagerDelegate, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate>

- (void)setupExitButton;
- (void)updateLocationInfoWithCoordinate:(CLLocationCoordinate2D)coordinate title:(NSString *)title;
- (void)showLocationFunctions;
- (void)showRouteFunctions;
- (void)showRecordingFunctions;
- (void)showAnalyticsFunctions;
- (void)showAdvancedMapFunctions;
- (void)showLocationSimulatorSettings;
- (void)showAutomationFunctions;
- (void)showGeofencingFunctions;

@property (strong, nonatomic) MKMapView *mapView;
@property (strong, nonatomic) CLLocationManager *locationManager;
@property (strong, nonatomic) CLGeocoder *geocoder;
@property (strong, nonatomic) UILongPressGestureRecognizer *longPressRecognizer;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (strong, nonatomic) UITableView *suggestionTableView;
@property (strong, nonatomic) NSArray<NSString *> *addressSuggestions;
@property (strong, nonatomic) NSMutableArray<NSDictionary *> *locationHistory;
@property (strong, nonatomic) UISegmentedControl *actionControl;
@property (strong, nonatomic) UIView *infoCardView;
@property (strong, nonatomic, readwrite) UILabel *locationLabel;
@property (strong, nonatomic) UILabel *addressLabel;
@property (strong, nonatomic) UILabel *altitudeLabel;
@property (strong, nonatomic) UIStackView *switchStack;
@property (strong, nonatomic) UISwitch *locationSwitch;
@property (strong, nonatomic) UISwitch *altitudeSwitch;
@property (strong, nonatomic) UIButton *confirmButton;
@property (strong, nonatomic) MKUserTrackingButton *trackingButton;
@property (strong, nonatomic) UIButton *mapTypeButton;
@property (strong, nonatomic) UISegmentedControl *functionTabs;
@property (strong, nonatomic) NSTimer *updateTimer;

@end

@implementation GPSCoordinateUtils (MapViewAdditions)

// WGS84转换为GCJ02
+ (CLLocationCoordinate2D)transformWGS84ToGCJ02:(CLLocationCoordinate2D)wgs84Coord {
    // 判断是否在中国大陆范围内
    if (![self isLocationInChina:wgs84Coord]) {
        return wgs84Coord;
    }
    
    double a = 6378245.0;  // 地球长半轴
    double ee = 0.00669342162296594323;  // 偏心率平方
    
    double dLat = [self transformLatWithX:wgs84Coord.longitude - 105.0 
                                        y:wgs84Coord.latitude - 35.0];
    double dLon = [self transformLonWithX:wgs84Coord.longitude - 105.0 
                                        y:wgs84Coord.latitude - 35.0];
    
    double radLat = wgs84Coord.latitude / 180.0 * M_PI;
    double magic = sin(radLat);
    magic = 1 - ee * magic * magic;
    
    double sqrtMagic = sqrt(magic);
    dLat = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * M_PI);
    dLon = (dLon * 180.0) / (a / sqrtMagic * cos(radLat) * M_PI);
    
    return CLLocationCoordinate2DMake(wgs84Coord.latitude + dLat, wgs84Coord.longitude + dLon);
}

// 判断坐标是否在中国范围内
+ (BOOL)isLocationInChina:(CLLocationCoordinate2D)location {
    // 中国大陆范围判断，排除港澳台地区
    if (location.longitude < 72.004 || location.longitude > 137.8347 ||
        location.latitude < 17.8365 || location.latitude > 53.5579) {
        return NO;
    }
    
    // 排除香港
    if (location.longitude > 113.8 && location.longitude < 114.5 &&
        location.latitude > 22.1 && location.latitude < 22.7) {
        return NO;
    }
    
    // 排除澳门
    if (location.longitude > 113.5 && location.longitude < 113.7 &&
        location.latitude > 22.0 && location.latitude < 22.3) {
        return NO;
    }
    
    // 排除台湾
    if (location.longitude > 120.0 && location.longitude < 122.0 &&
        location.latitude > 21.7 && location.latitude < 25.5) {
        return NO;
    }
    
    return YES;
}

// 纬度转换
+ (double)transformLatWithX:(double)x y:(double)y {
    double result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(fabs(x));
    result += (20.0 * sin(6.0 * x * M_PI) + 20.0 * sin(2.0 * x * M_PI)) * 2.0 / 3.0;
    result += (20.0 * sin(y * M_PI) + 40.0 * sin(y / 3.0 * M_PI)) * 2.0 / 3.0;
    result += (160.0 * sin(y / 12.0 * M_PI) + 320.0 * sin(y * M_PI / 30.0)) * 2.0 / 3.0;
    return result;
}

// 经度转换
+ (double)transformLonWithX:(double)x y:(double)y {
    double result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(fabs(x));
    result += (20.0 * sin(6.0 * x * M_PI) + 20.0 * sin(2.0 * x * M_PI)) * 2.0 / 3.0;
    result += (20.0 * sin(x * M_PI) + 40.0 * sin(x / 3.0 * M_PI)) * 2.0 / 3.0;
    result += (150.0 * sin(x / 12.0 * M_PI) + 300.0 * sin(x / 30.0 * M_PI)) * 2.0 / 3.0;
    return result;
}

// 计算两个坐标点之间的距离（米）
+ (double)calculateDistanceFrom:(CLLocationCoordinate2D)fromCoord to:(CLLocationCoordinate2D)toCoord {
    CLLocation *from = [[CLLocation alloc] initWithLatitude:fromCoord.latitude longitude:fromCoord.longitude];
    CLLocation *to = [[CLLocation alloc] initWithLatitude:toCoord.latitude longitude:toCoord.longitude];
    
    return [from distanceFromLocation:to];
}

// 计算两个坐标点之间的航向角（度）
+ (double)calculateBearingFrom:(CLLocationCoordinate2D)fromCoord to:(CLLocationCoordinate2D)toCoord {
    double lat1 = fromCoord.latitude * M_PI / 180.0;
    double lon1 = fromCoord.longitude * M_PI / 180.0;
    double lat2 = toCoord.latitude * M_PI / 180.0;
    double lon2 = toCoord.longitude * M_PI / 180.0;
    
    double dLon = lon2 - lon1;
    double y = sin(dLon) * cos(lat2);
    double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    double bearing = atan2(y, x) * 180.0 / M_PI;
    
    // 转换为0-360度范围
    bearing = fmod((bearing + 360.0), 360.0);
    
    return bearing;
}

@end

@implementation MapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self initializeData];
    [self setupUIComponents];
    [self setupConstraints];
    [self setupGestures];
    [self setupFunctionTabs];
    [self loadSavedLocations];
    [self setupExitButton];
    
    self.suggestionTableView.backgroundColor = [UIColor systemBackgroundColor]; 
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self checkLocationAuthorization];
    [self updateUIForCurrentInterfaceStyle];
    
    if (self.searchBar.placeholder.length == 0 || ![self.searchBar.placeholder containsString:@"搜索"]) {
        self.searchBar.placeholder = @"搜索地址或地点";
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    // 动态调整渐变层大小
    CAGradientLayer *gradientLayer = objc_getAssociatedObject(self.confirmButton, "gradientLayer");
    if (gradientLayer) {
        gradientLayer.frame = self.confirmButton.bounds;
    }
}

- (void)updateUIForCurrentInterfaceStyle {
    if (@available(iOS 13.0, *)) {
        BOOL isDarkMode = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        self.view.backgroundColor = isDarkMode ? [UIColor systemBackgroundColor] : [UIColor systemGroupedBackgroundColor];
        self.suggestionTableView.backgroundColor = isDarkMode ? [UIColor tertiarySystemBackgroundColor] : [UIColor secondarySystemBackgroundColor];
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    
    if (@available(iOS 13.0, *)) {
        BOOL isDarkMode = self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
        
        // 动态调整颜色
        self.view.backgroundColor = isDarkMode ? [UIColor systemBackgroundColor] : [UIColor systemGroupedBackgroundColor];
        self.suggestionTableView.backgroundColor = isDarkMode ? [UIColor tertiarySystemBackgroundColor] : [UIColor secondarySystemBackgroundColor];
        
        // 调整阴影
        for (UIView *view in @[self.mapView, self.infoCardView, self.confirmButton]) {
            view.layer.shadowOpacity = isDarkMode ? 0.3 : 0.15;
        }
    }
}

- (void)dismissKeyboard {
    [self.view endEditing:YES];  
}

- (void)initializeData {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.locationHistory = [[defaults arrayForKey:@"LocationHistory"] mutableCopy] ?: [NSMutableArray array];
    self.geocoder = [[CLGeocoder alloc] init];
    self.updateTimer = nil;  // 初始化定时器为nil
    self.addressLabel = nil;  // 将在setupInfoCard中创建
}

- (void)loadSavedLocations {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat latitude = [defaults floatForKey:@"latitude"];
    CGFloat longitude = [defaults floatForKey:@"longitude"];
    CGFloat altitude = [defaults floatForKey:@"altitude"];
    
    if (latitude != 0 && longitude != 0) {
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(latitude, longitude);
        [self addAnnotationAtCoordinate:coordinate withTitle:@"已保存的位置"];
    }
}

#pragma mark - UI 组件初始化
- (void)setupUIComponents {
    [self setupSearchBar];
    [self setupMapView];
    [self setupInfoCard];
    [self setupActionControls];
    [self setupSwitchControls];
    [self setupConfirmButton];
    [self setupFloatingActionButton];
    [self setupProgressIndicator];
}

// 浮动操作按钮
- (void)setupFloatingActionButton {
    self.floatingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.floatingButton setImage:[[UIImage systemImageNamed:@"plus.circle.fill"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    self.floatingButton.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.85];
    self.floatingButton.tintColor = [UIColor systemBlueColor];
    self.floatingButton.layer.cornerRadius = 28;
    self.floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatingButton.layer.shadowOffset = CGSizeMake(0, 6);
    self.floatingButton.layer.shadowOpacity = 0.25;
    self.floatingButton.layer.shadowRadius = 10;
    self.floatingButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.floatingButton addTarget:self action:@selector(showQuickActions) forControlEvents:UIControlEventTouchUpInside];
    [self.floatingButton addTarget:self action:@selector(animateButtonPress:) forControlEvents:UIControlEventTouchDown];
    [self.floatingButton addTarget:self action:@selector(animateButtonRelease:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    
    [self.view addSubview:self.floatingButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.floatingButton.widthAnchor constraintEqualToConstant:56],
        [self.floatingButton.heightAnchor constraintEqualToConstant:56],
        [self.floatingButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.floatingButton.bottomAnchor constraintEqualToAnchor:self.switchStack.topAnchor constant:-20]
    ]];
}

// 进度指示器
- (void)setupProgressIndicator {
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.progressTintColor = [UIColor systemBlueColor];
    self.progressView.trackTintColor = [UIColor systemGray5Color];
    self.progressView.alpha = 0;
    self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.progressView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.progressView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:5],
        [self.progressView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.progressView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15]
    ]];
}

- (void)setupSearchBar {
    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索地址或地点";
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.tintColor = [UIColor systemBlueColor];
    self.searchBar.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 现代风格设计
    if (@available(iOS 13.0, *)) {
        self.searchBar.searchTextField.backgroundColor = [[UIColor tertiarySystemBackgroundColor] colorWithAlphaComponent:0.85];
        self.searchBar.searchTextField.layer.cornerRadius = 16;
        self.searchBar.searchTextField.layer.masksToBounds = YES;
        
        // 更现代的阴影效果
        UIView *searchWrapper = [[UIView alloc] init];
        searchWrapper.backgroundColor = [UIColor clearColor];
        searchWrapper.translatesAutoresizingMaskIntoConstraints = NO;
        searchWrapper.layer.shadowColor = [UIColor blackColor].CGColor;
        searchWrapper.layer.shadowOffset = CGSizeMake(0, 2);
        searchWrapper.layer.shadowOpacity = 0.15;
        searchWrapper.layer.shadowRadius = 8;
        
        [self.view addSubview:searchWrapper];
        [searchWrapper addSubview:self.searchBar];
        
        // 修改：调整搜索栏的位置，确保在安全区域内且离顶部有适当距离
        [NSLayoutConstraint activateConstraints:@[
            [searchWrapper.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
            [searchWrapper.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:60], // 留出左侧空间给退出按钮
            [searchWrapper.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-60], // 留出右侧空间
            [searchWrapper.heightAnchor constraintEqualToConstant:50],
            
            [self.searchBar.topAnchor constraintEqualToAnchor:searchWrapper.topAnchor],
            [self.searchBar.leadingAnchor constraintEqualToAnchor:searchWrapper.leadingAnchor],
            [self.searchBar.trailingAnchor constraintEqualToAnchor:searchWrapper.trailingAnchor],
            [self.searchBar.bottomAnchor constraintEqualToAnchor:searchWrapper.bottomAnchor]
        ]];
    } else {
        [self.view addSubview:self.searchBar];
        
        [NSLayoutConstraint activateConstraints:@[
            [self.searchBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
            [self.searchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:60],
            [self.searchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-60],
            [self.searchBar.heightAnchor constraintEqualToConstant:50]
        ]];
    }
    
    // 重新调整建议表格视图的位置
    self.suggestionTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.suggestionTableView.delegate = self;
    self.suggestionTableView.dataSource = self;
    self.suggestionTableView.hidden = YES;
    self.suggestionTableView.layer.cornerRadius = 16;
    self.suggestionTableView.layer.borderWidth = 0.5;
    self.suggestionTableView.layer.borderColor = [UIColor systemGray5Color].CGColor;
    self.suggestionTableView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.suggestionTableView.layer.shadowOffset = CGSizeMake(0, 4);
    self.suggestionTableView.layer.shadowOpacity = 0.15;
    self.suggestionTableView.layer.shadowRadius = 8;
    self.suggestionTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.suggestionTableView.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.9];
    self.suggestionTableView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.view addSubview:self.suggestionTableView];
    [self.view bringSubviewToFront:self.suggestionTableView]; 
    
    // 调整建议表格视图的约束，确保它显示在搜索栏下方
    [NSLayoutConstraint activateConstraints:@[
        [self.suggestionTableView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:5],
        [self.suggestionTableView.leadingAnchor constraintEqualToAnchor:self.searchBar.leadingAnchor],
        [self.suggestionTableView.trailingAnchor constraintEqualToAnchor:self.searchBar.trailingAnchor],
        [self.suggestionTableView.heightAnchor constraintEqualToConstant:200] // 限制高度
    ]];
}

- (void)setupMapView {
    self.mapView = [[MKMapView alloc] init];
    self.mapView.delegate = self;
    self.mapView.layer.cornerRadius = 0; // 全屏地图不需要圆角
    self.mapView.clipsToBounds = YES;
    self.mapView.mapType = MKMapTypeStandard;
    self.mapView.showsUserLocation = YES;
    self.mapView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.view addSubview:self.mapView];
    [self.view sendSubviewToBack:self.mapView]; // 确保地图在最底层
    
    // 增强的控制按钮
    self.trackingButton = [MKUserTrackingButton userTrackingButtonWithMapView:self.mapView];
    [self enhanceButton:self.trackingButton];
    
    self.mapTypeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.mapTypeButton setImage:[UIImage systemImageNamed:@"map.fill"] forState:UIControlStateNormal];
    [self.mapTypeButton addTarget:self action:@selector(toggleMapType) forControlEvents:UIControlEventTouchUpInside];
    [self enhanceButton:self.mapTypeButton];
    
    UIStackView *mapControlsStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.trackingButton, self.mapTypeButton]];
    mapControlsStack.axis = UILayoutConstraintAxisVertical;
    mapControlsStack.spacing = 12;
    mapControlsStack.distribution = UIStackViewDistributionFillEqually;
    mapControlsStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mapControlsStack];
    
    // 设置地图控制按钮的约束
    [NSLayoutConstraint activateConstraints:@[
        [mapControlsStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [mapControlsStack.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-120]
    ]];
}

// 更新信息
- (void)setupInfoCard {
    // 创建更强大的信息卡片
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.layer.cornerRadius = 12;
    blurView.layer.masksToBounds = YES;
    blurView.translatesAutoresizingMaskIntoConstraints = NO;
    
    self.infoCardView = [[UIView alloc] init];
    self.infoCardView.layer.cornerRadius = 12;
    self.infoCardView.layer.shadowColor = [UIColor blackColor].CGColor;
    self.infoCardView.layer.shadowOffset = CGSizeMake(0, 4);
    self.infoCardView.layer.shadowOpacity = 0.15;
    self.infoCardView.layer.shadowRadius = 8;
    self.infoCardView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.infoCardView addSubview:blurView];
    [blurView.topAnchor constraintEqualToAnchor:self.infoCardView.topAnchor].active = YES;
    [blurView.leadingAnchor constraintEqualToAnchor:self.infoCardView.leadingAnchor].active = YES;
    [blurView.trailingAnchor constraintEqualToAnchor:self.infoCardView.trailingAnchor].active = YES;
    [blurView.bottomAnchor constraintEqualToAnchor:self.infoCardView.bottomAnchor].active = YES;
    
    // 位置标签 - 使用更清晰的布局
    self.locationLabel = [[UILabel alloc] init];
    self.locationLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    self.locationLabel.textColor = [UIColor labelColor];
    self.locationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 附加标签：地址信息
    self.addressLabel = [[UILabel alloc] init];
    self.addressLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    self.addressLabel.textColor = [UIColor secondaryLabelColor];
    self.addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.addressLabel.text = @"准备解析地址数据...";
    
    // 海拔标签
    self.altitudeLabel = [[UILabel alloc] init];
    self.altitudeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    self.altitudeLabel.textColor = [UIColor secondaryLabelColor];
    self.altitudeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 状态指示器 - 更明显的视觉反馈
    self.statusIndicator = [[UIView alloc] init];
    self.statusIndicator.backgroundColor = [UIColor systemGreenColor];
    self.statusIndicator.layer.cornerRadius = 4;
    self.statusIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *statusLabel = [[UILabel alloc] init];
    statusLabel.text = @"准备";
    statusLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    statusLabel.textColor = [UIColor whiteColor];
    statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.statusIndicator addSubview:statusLabel];
    
    // 垂直布局信息
    UIStackView *infoStack = [[UIStackView alloc] initWithArrangedSubviews:@[self.locationLabel, self.addressLabel, self.altitudeLabel]];
    infoStack.axis = UILayoutConstraintAxisVertical;
    infoStack.spacing = 4;
    infoStack.distribution = UIStackViewDistributionFillProportionally;
    infoStack.translatesAutoresizingMaskIntoConstraints = NO;
    
    [blurView.contentView addSubview:infoStack];
    [blurView.contentView addSubview:self.statusIndicator];
    [self.view addSubview:self.infoCardView];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.infoCardView.topAnchor constraintEqualToAnchor:self.searchBar.bottomAnchor constant:10],
        [self.infoCardView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:15],
        [self.infoCardView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [self.infoCardView.heightAnchor constraintEqualToConstant:80],
        
        [infoStack.leadingAnchor constraintEqualToAnchor:blurView.contentView.leadingAnchor constant:12],
        [infoStack.trailingAnchor constraintEqualToAnchor:self.statusIndicator.leadingAnchor constant:-8],
        [infoStack.centerYAnchor constraintEqualToAnchor:blurView.contentView.centerYAnchor],
        
        [self.statusIndicator.trailingAnchor constraintEqualToAnchor:blurView.contentView.trailingAnchor constant:-12],
        [self.statusIndicator.centerYAnchor constraintEqualToAnchor:blurView.contentView.centerYAnchor],
        [self.statusIndicator.heightAnchor constraintEqualToConstant:22],
        [self.statusIndicator.widthAnchor constraintEqualToConstant:45],
        
        [statusLabel.centerXAnchor constraintEqualToAnchor:self.statusIndicator.centerXAnchor],
        [statusLabel.centerYAnchor constraintEqualToAnchor:self.statusIndicator.centerYAnchor]
    ]];
}

- (void)setupSwitchControls {
    self.locationSwitch = [[UISwitch alloc] init];
    [self.locationSwitch addTarget:self action:@selector(locationSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    
    self.altitudeSwitch = [[UISwitch alloc] init];
    [self.altitudeSwitch addTarget:self action:@selector(altitudeSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    
    UIView *locationItem = [self createSwitchItemWithIcon:@"location.fill" 
                                             switchControl:self.locationSwitch 
                                                     text:@"位置模拟"];
    UIView *altitudeItem = [self createSwitchItemWithIcon:@"mountain.2.fill" 
                                             switchControl:self.altitudeSwitch 
                                                     text:@"海拔模拟"];
    
    self.switchStack = [[UIStackView alloc] initWithArrangedSubviews:@[locationItem, altitudeItem]];
    self.switchStack.axis = UILayoutConstraintAxisHorizontal;
    self.switchStack.spacing = 20;
    self.switchStack.distribution = UIStackViewDistributionFillEqually;
    self.switchStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.switchStack];
    
    // 从UserDefaults加载开关状态
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [self.locationSwitch setOn:[defaults boolForKey:@"LocationSpoofingEnabled"] animated:NO];
    [self.altitudeSwitch setOn:[defaults boolForKey:@"AltitudeSpoofingEnabled"] animated:NO];
}

- (UIView *)createSwitchItemWithIcon:(NSString *)iconName 
                        switchControl:(UISwitch *)switchControl 
                                text:(NSString *)text {
    UIView *container = [[UIView alloc] init];
    container.backgroundColor = [UIColor secondarySystemBackgroundColor];
    container.layer.cornerRadius = 16;
    container.layer.shadowColor = [UIColor blackColor].CGColor;
    container.layer.shadowOffset = CGSizeMake(0, 2);
    container.layer.shadowOpacity = 0.1;
    container.layer.shadowRadius = 6;
    container.translatesAutoresizingMaskIntoConstraints = NO;
    
    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:iconName]];
    icon.tintColor = [UIColor systemBlueColor];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    label.textColor = [UIColor labelColor];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    
    switchControl.onTintColor = [UIColor systemBlueColor];
    switchControl.translatesAutoresizingMaskIntoConstraints = NO;
    
    [container addSubview:icon];
    [container addSubview:label];
    [container addSubview:switchControl];
    
    [NSLayoutConstraint activateConstraints:@[
        [icon.topAnchor constraintEqualToAnchor:container.topAnchor constant:16],
        [icon.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [icon.widthAnchor constraintEqualToConstant:24],
        [icon.heightAnchor constraintEqualToConstant:24],
        
        [label.topAnchor constraintEqualToAnchor:icon.bottomAnchor constant:8],
        [label.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        
        [switchControl.topAnchor constraintEqualToAnchor:label.bottomAnchor constant:12],
        [switchControl.centerXAnchor constraintEqualToAnchor:container.centerXAnchor],
        [switchControl.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-16],
        
        [container.widthAnchor constraintGreaterThanOrEqualToConstant:120],
        [container.heightAnchor constraintEqualToConstant:120]
    ]];
    
    return container;
}

- (void)setupConfirmButton {
    self.confirmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.confirmButton setTitle:@"📍 确认位置" forState:UIControlStateNormal];
    [self.confirmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.confirmButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    
    // 渐变背景
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.colors = @[(id)[UIColor systemBlueColor].CGColor, 
                           (id)[UIColor systemIndigoColor].CGColor];
    gradientLayer.startPoint = CGPointMake(0, 0);
    gradientLayer.endPoint = CGPointMake(1, 1);
    gradientLayer.cornerRadius = 24;
    
    self.confirmButton.layer.cornerRadius = 24;
    self.confirmButton.layer.masksToBounds = NO;
    self.confirmButton.layer.shadowColor = [UIColor systemBlueColor].CGColor;
    self.confirmButton.layer.shadowOffset = CGSizeMake(0, 6);
    self.confirmButton.layer.shadowOpacity = 0.3;
    self.confirmButton.layer.shadowRadius = 12;
    
    [self.confirmButton addTarget:self action:@selector(confirmLocation) forControlEvents:UIControlEventTouchUpInside];
    [self.confirmButton addTarget:self action:@selector(animateButtonPress:) forControlEvents:UIControlEventTouchDown];
    [self.confirmButton addTarget:self action:@selector(animateButtonRelease:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    
    self.confirmButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.confirmButton];
    
    // 添加渐变层
    [self.confirmButton.layer insertSublayer:gradientLayer atIndex:0];
    objc_setAssociatedObject(self.confirmButton, "gradientLayer", gradientLayer, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)setupConstraints {
    // 设置地图全屏
    [NSLayoutConstraint activateConstraints:@[
        [self.mapView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.mapView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.mapView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.mapView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    // 重构控件约束，修复重叠问题
    [NSLayoutConstraint activateConstraints:@[
        // 操作控制器放在信息卡片下方而不是搜索栏下方
        [self.actionControl.topAnchor constraintEqualToAnchor:self.infoCardView.bottomAnchor constant:10],
        [self.actionControl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.actionControl.widthAnchor constraintEqualToConstant:300],

        // 调整开关控件位置，与屏幕底部保持适当距离
        [self.switchStack.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.switchStack.bottomAnchor constraintEqualToAnchor:self.confirmButton.topAnchor constant:-20],
        
        // 确认按钮位置调整，增加与底部的距离
        [self.confirmButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:30],
        [self.confirmButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-30],
        [self.confirmButton.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-30],
        [self.confirmButton.heightAnchor constraintEqualToConstant:56]
    ]];
}

- (void)setupFunctionTabs {
    NSArray *tabTitles = @[@"位置", @"路径", @"工具", @"设置"];
    
    UISegmentedControl *functionTabs = [[UISegmentedControl alloc] initWithItems:tabTitles];
    functionTabs.selectedSegmentIndex = 0;
    functionTabs.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.9];
    functionTabs.layer.cornerRadius = 8;
    functionTabs.translatesAutoresizingMaskIntoConstraints = NO;
    [functionTabs addTarget:self action:@selector(functionTabChanged:) forControlEvents:UIControlEventValueChanged];
    
    [self.view addSubview:functionTabs];
    self.functionTabs = functionTabs;
    
    [NSLayoutConstraint activateConstraints:@[
        [functionTabs.topAnchor constraintEqualToAnchor:self.actionControl.bottomAnchor constant:10],
        [functionTabs.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [functionTabs.widthAnchor constraintEqualToConstant:300],
        [functionTabs.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (void)functionTabChanged:(UISegmentedControl *)sender {
    switch (sender.selectedSegmentIndex) {
        case 0: // 位置
            [self showLocationFunctions];
            break;
        case 1: // 路径
            [self showRouteFunctions];
            break;
        case 2: // 工具
            [self showCoordinateUtils];
            break;
        case 3: // 设置
            [self showAdvancedSettings];
            break;
    }
}

- (void)setupGestures {
    self.longPressRecognizer = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self.mapView addGestureRecognizer:self.longPressRecognizer];
}

#pragma mark - 交互方法
- (void)segmentAction:(UISegmentedControl *)sender {
    switch (sender.selectedSegmentIndex) {
        case 0:
            [self showHistory];
            break;
        case 1:
            [self showManualInput];
            break;
        case 2:
            [self showManualAltitudeInput];
            break;
    }
    sender.selectedSegmentIndex = -1; 
}

- (void)toggleMapType {
    self.mapView.mapType = (self.mapView.mapType == MKMapTypeStandard) ? MKMapTypeSatellite : MKMapTypeStandard;
    NSString *imageName = (self.mapView.mapType == MKMapTypeStandard) ? @"map" : @"globe";
    [self.mapTypeButton setImage:[UIImage systemImageNamed:imageName] forState:UIControlStateNormal];
}

- (void)buttonTouchDown:(UIButton *)sender {
    [UIView animateWithDuration:0.1 animations:^{
        sender.transform = CGAffineTransformMakeScale(0.96, 0.96);
        sender.alpha = 0.9;
    }];
}

- (void)buttonTouchUp:(UIButton *)sender {
    [UIView animateWithDuration:0.2 animations:^{
        sender.transform = CGAffineTransformIdentity;
        sender.alpha = 1.0;
    }];
}

#pragma mark - 核心功能方法
- (void)confirmLocation {

    if (self.locationSwitch.isOn) {
        [self showAlertWithTitle:@"无法确认位置" 
                        message:@"请先关闭「位置模拟」开关再确认位置"];
        return; 
    }

    if (self.mapView.annotations.count == 0) {
        [self showAlertWithTitle:@"未选择位置" message:@"请在地图上长按选择位置或通过搜索选择位置"];
        return;
    }
    
    id<MKAnnotation> annotation = self.mapView.annotations.firstObject;
    if (![annotation isKindOfClass:[MKPointAnnotation class]]) {
        return;
    }
    
    MKPointAnnotation *pointAnnotation = (MKPointAnnotation *)annotation;
    NSDictionary *locationInfo = @{
        @"address": pointAnnotation.title ?: @"自定义位置",
        @"latitude": @(pointAnnotation.coordinate.latitude),
        @"longitude": @(pointAnnotation.coordinate.longitude)
    };
    
    [self.locationHistory addObject:locationInfo];
    [[NSUserDefaults standardUserDefaults] setObject:self.locationHistory forKey:@"LocationHistory"];
    
    // 保存到UserDefaults
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setDouble:pointAnnotation.coordinate.latitude forKey:@"latitude"];
    [defaults setDouble:pointAnnotation.coordinate.longitude forKey:@"longitude"];
    [defaults synchronize];    
    
    // 发送通知以确保位置信息立即应用
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LocationConfirmed" object:nil userInfo:@{
        @"latitude": @(pointAnnotation.coordinate.latitude),
        @"longitude": @(pointAnnotation.coordinate.longitude)
    }];
    
    [self showAlertWithTitle:@"位置已保存" message:@"已成功保存当前位置，开启位置模拟开关即可使用"];
}


- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) return;
    
    CGPoint touchPoint = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:touchPoint toCoordinateFromView:self.mapView];
    
    [self.mapView removeAnnotations:self.mapView.annotations];
    
    MKPointAnnotation *newAnnotation = [[MKPointAnnotation alloc] init];
    newAnnotation.coordinate = coordinate;
    newAnnotation.title = @"新位置";
    [self.mapView addAnnotation:newAnnotation];
    
    [self.geocoder reverseGeocodeLocation:[[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude] 
                       completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        
        NSString *address = [NSString stringWithFormat:@"%.6f, %.6f", coordinate.latitude, coordinate.longitude];
        if (placemarks.count > 0) {
            CLPlacemark *placemark = placemarks.firstObject;
            address = [NSString stringWithFormat:@"%@, %@", 
                      placemark.name ?: @"", 
                      placemark.locality ?: @""];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            id<MKAnnotation> annotation = self.mapView.annotations.firstObject;
            if ([annotation isKindOfClass:[MKPointAnnotation class]]) {
                MKPointAnnotation *pointAnnotation = (MKPointAnnotation *)annotation;
                pointAnnotation.title = address;
            }
        });
    }];
}

- (void)addAnnotationAtCoordinate:(CLLocationCoordinate2D)coordinate withTitle:(NSString *)title {
    MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
    annotation.coordinate = coordinate;
    annotation.title = title;
    [self.mapView addAnnotation:annotation];
    
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, 500, 500);
    [self.mapView setRegion:region animated:YES];
    
    // 更新详细信息卡片
    [self updateLocationInfoWithCoordinate:coordinate title:title];
}

- (void)showManualInput {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"手动输入位置"
                                                                   message:@"请输入纬度和经度\n（例如：39.9042, 116.4074）"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"纬度（-90 ~ 90）";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"经度（-180 ~ 180）";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UITextField *latField = alert.textFields[0];
        UITextField *lngField = alert.textFields[1];
        
        if (![self isValidCoordinate:latField.text lng:lngField.text]) {
            [self showAlertWithTitle:@"输入无效" message:@"请输入有效的经纬度数值\n纬度范围：-90 ~ 90\n经度范围：-180 ~ 180"];
            return;
        }
        
        CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake([latField.text doubleValue], [lngField.text doubleValue]);
        
        // 清除旧标记并添加新标记
        [self.mapView removeAnnotations:self.mapView.annotations];
        [self addAnnotationAtCoordinate:coordinate withTitle:@"手动输入的位置"];
        
        // 更新信息卡片
        self.locationLabel.text = [NSString stringWithFormat:@"位置: %.4f, %.4f", 
                                  coordinate.latitude, 
                                  coordinate.longitude];
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:cancel];
    [alert addAction:confirm];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showManualAltitudeInput {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"手动输入海拔"
                                                                   message:@"请输入海拔高度（单位：米）"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"海拔（单位：米）";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    UIAlertAction *confirm = [UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *altitudeText = alert.textFields[0].text;
        
        if (![self isValidAltitude:altitudeText]) {
            [self showAlertWithTitle:@"输入无效" message:@"请输入正确的海拔高度（可以是负值）"];
            return;
        }
        
        double altitude = [altitudeText doubleValue];
        
        // 保存海拔
        [[NSUserDefaults standardUserDefaults] setDouble:altitude forKey:@"altitude"];
        [[NSUserDefaults standardUserDefaults] synchronize];
        
        [self showAlertWithTitle:@"海拔已保存" message:@"已成功保存海拔高度，开启海拔模拟开关即可使用"];
    }];
    
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    
    [alert addAction:cancel];
    [alert addAction:confirm];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showHistory {
    if (self.locationHistory.count == 0) {
        [self showAlertWithTitle:@"无历史记录" message:@"您还没有保存过任何位置记录"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"历史位置记录" 
                                                                   message:@"选择要查看的位置" 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    UIAlertAction *clearAction = [UIAlertAction actionWithTitle:@"清除历史记录" 
                                                          style:UIAlertActionStyleDestructive 
                                                        handler:^(UIAlertAction *action) {
        [self.locationHistory removeAllObjects];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"LocationHistory"];
        [self showAlertWithTitle:@"已清除" message:@"所有历史记录已删除"];
    }];
    [alert addAction:clearAction];
    
    for (NSDictionary *location in self.locationHistory) {
        NSString *title = location[@"address"] ?: @"未知位置";
        UIAlertAction *action = [UIAlertAction actionWithTitle:title 
                                                         style:UIAlertActionStyleDefault 
                                                       handler:^(UIAlertAction *action) {
            CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake(
                [location[@"latitude"] doubleValue],
                [location[@"longitude"] doubleValue]
            );
            
            [self.mapView removeAnnotations:self.mapView.annotations];
            [self addAnnotationAtCoordinate:coordinate withTitle:location[@"address"]];
        }];
        [alert addAction:action];
    }
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" 
                                                          style:UIAlertActionStyleCancel 
                                                        handler:nil];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 验证方法
- (BOOL)isValidCoordinate:(NSString *)lat lng:(NSString *)lng {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    NSNumber *latitude = [formatter numberFromString:lat];
    NSNumber *longitude = [formatter numberFromString:lng];
    
    if (!latitude || !longitude) return NO;
    
    CLLocationDegrees latValue = [latitude doubleValue];
    CLLocationDegrees lngValue = [longitude doubleValue];
    
    return (latValue >= -90.0 && latValue <= 90.0) &&
           (lngValue >= -180.0 && lngValue <= 180.0);
}

- (BOOL)isValidAltitude:(NSString *)altitude {
    if (altitude.length == 0) return NO;
    
    NSScanner *scanner = [NSScanner scannerWithString:altitude];
    double value;
    return [scanner scanDouble:&value] && scanner.isAtEnd;
}

#pragma mark - 位置权限
- (void)checkLocationAuthorization {
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = self.locationManager.authorizationStatus;  
    } else {
        
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        status = [CLLocationManager authorizationStatus];
#pragma clang diagnostic pop
    }
    
    if (status == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    } else if (status == kCLAuthorizationStatusDenied) {
        [self showAlertWithTitle:@"位置权限被拒绝" 
                        message:@"请在设置中启用位置权限以使用完整功能"];
    } else {
        [self.locationManager startUpdatingLocation];
    }
}

- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
    if (status == kCLAuthorizationStatusAuthorizedWhenInUse || 
        status == kCLAuthorizationStatusAuthorizedAlways) {
        [manager startUpdatingLocation];
    }
}

#pragma mark - 搜索功能
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    self.suggestionTableView.hidden = YES;
    
    if (searchBar.text.length == 0) return;
    
    [self.geocoder geocodeAddressString:searchBar.text completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        if (error || placemarks.count == 0) {
            [self showAlertWithTitle:@"搜索失败" message:@"未能找到匹配的位置"];
            return;
        }
        
        CLPlacemark *placemark = placemarks.firstObject;
        CLLocationCoordinate2D coordinate = placemark.location.coordinate;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.mapView removeAnnotations:self.mapView.annotations];
            [self addAnnotationAtCoordinate:coordinate withTitle:searchBar.text];
        });
    }];
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.suggestionTableView.hidden = YES;
        self.actionControl.hidden = NO; // 当无搜索内容时显示操作控制器
        self.infoCardView.hidden = NO;  // 当无搜索内容时显示信息卡片
        return;
    }
    
    // 当显示搜索建议时，隐藏操作控制器和信息卡片
    self.actionControl.hidden = YES;
    self.infoCardView.hidden = YES;     // 隐藏信息卡片避免被建议列表覆盖
    
    [self.geocoder geocodeAddressString:searchText completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        if (error || placemarks.count == 0) {
            self.addressSuggestions = @[];
        } else {
            NSMutableArray *suggestions = [NSMutableArray array];
            for (CLPlacemark *placemark in placemarks) {
                [suggestions addObject:placemark.name ?: @""];
            }
            self.addressSuggestions = [suggestions copy];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.suggestionTableView.hidden = self.addressSuggestions.count == 0;
            if (self.suggestionTableView.hidden) {
                self.actionControl.hidden = NO;
                self.infoCardView.hidden = NO;  // 如果没有建议，显示信息卡片
            } else {
                self.actionControl.hidden = YES;
                self.infoCardView.hidden = YES;  // 有建议时保持信息卡片隐藏
            }
            [self.suggestionTableView reloadData];
        });
    }];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    searchBar.placeholder = @"搜索地址或地点";
    
    [searchBar setShowsCancelButton:NO animated:YES];
    [searchBar resignFirstResponder];
    
    if (@available(iOS 13.0, *)) {
        UITextField *searchField = searchBar.searchTextField;
        searchField.rightViewMode = UITextFieldViewModeAlways;
        searchField.layoutMargins = UIEdgeInsetsZero;
        
        // 恢复搜索图标位置
        UIOffset offset = UIOffsetMake(0, 0);
        [searchBar setPositionAdjustment:offset forSearchBarIcon:UISearchBarIconSearch];
    }
    
    self.suggestionTableView.hidden = YES;
    self.actionControl.hidden = NO;     // 显示操作控制器
    self.infoCardView.hidden = NO;      // 显示信息卡片
    self.addressSuggestions = @[];
    [self.suggestionTableView reloadData];
}

#pragma mark - 表格视图
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.addressSuggestions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"suggestionCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"suggestionCell"];
        cell.imageView.tintColor = [UIColor systemBlueColor];
    }
    
    cell.imageView.image = [UIImage systemImageNamed:@"mappin.and.ellipse"];
    cell.textLabel.text = self.addressSuggestions[indexPath.row];
    cell.detailTextLabel.text = @"点击选择位置";
    cell.backgroundColor = [UIColor clearColor];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSString *selectedAddress = self.addressSuggestions[indexPath.row];
    self.searchBar.text = selectedAddress;
    self.suggestionTableView.hidden = YES;
    self.actionControl.hidden = NO;     // 选择后显示操作控制器
    self.infoCardView.hidden = NO;      // 选择后显示信息卡片
    [self.searchBar resignFirstResponder];
    
    [self.geocoder geocodeAddressString:selectedAddress completionHandler:^(NSArray<CLPlacemark *> *placemarks, NSError *error) {
        if (error || placemarks.count == 0) return;
        
        CLPlacemark *placemark = placemarks.firstObject;
        CLLocationCoordinate2D coordinate = placemark.location.coordinate;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.mapView removeAnnotations:self.mapView.annotations];
            [self addAnnotationAtCoordinate:coordinate withTitle:selectedAddress];
        });
    }];
}

#pragma mark - 地图视图代理
- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray<MKAnnotationView *> *)views {
    for (MKAnnotationView *view in views) {
        if ([view.annotation isKindOfClass:[MKPointAnnotation class]]) {
            view.transform = CGAffineTransformMakeScale(0.5, 0.5);
            [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                view.transform = CGAffineTransformIdentity;
            } completion:nil];
        }
    }
}

#pragma mark - 开关控制
- (void)locationSwitchChanged:(UISwitch *)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // 检查是否设置了位置
    CLLocationDegrees latitude = [defaults doubleForKey:@"latitude"];
    CLLocationDegrees longitude = [defaults doubleForKey:@"longitude"];
    
    if (sender.isOn && (latitude == 0 && longitude == 0)) {
        [sender setOn:NO animated:YES];
        [self showAlertWithTitle:@"未设置位置" 
                        message:@"请先在地图上选择位置或手动输入坐标"];
        return;
    }
    
    [defaults setBool:sender.isOn forKey:@"LocationSpoofingEnabled"];
    [defaults synchronize];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"LocationSpoofingChanged" object:nil];
}

- (void)altitudeSwitchChanged:(UISwitch *)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // 检查是否设置了海拔
    if (sender.isOn && ![defaults objectForKey:@"altitude"]) {
        [sender setOn:NO animated:YES];
        [self showAlertWithTitle:@"未设置海拔" 
                        message:@"请先设置海拔高度"];
        return;
    }
    
    [defaults setBool:sender.isOn forKey:@"AltitudeSpoofingEnabled"];
    [defaults synchronize];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"AltitudeSpoofingChanged" object:nil];
}

#pragma mark - 辅助方法
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *ok = [UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:ok];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closeButtonTapped:(id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - 功能菜单
- (void)showQuickActions {
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"GPS++ 功能中心"
                                                                        message:@"选择需要使用的功能"
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];

    // ===== 位置功能组 =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"📍 位置功能"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showLocationFunctions];
    }]];
    
    // ===== 路径功能组 =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"🗺️ 路径功能"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showRouteFunctions];
    }]];
    
    // ===== 移动模式功能组 =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"🚶‍♂️ 移动模式"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showMovementModes];
    }]];
    
    // ===== 记录功能组 - 新集成的功能 =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"🎥 记录与回放"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showRecordingFunctions];
    }]];
    
    // ===== 分析工具功能组 - 集成GPSAnalyticsSystem =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"📊 分析工具"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showAnalyticsFunctions];
    }]];
    
    // ===== 高级地图功能 - 集成GPSAdvancedMapController =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"🌐 高级地图"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showAdvancedMapFunctions];
    }]];
    
    // ===== 模拟器设置 - 集成GPSAdvancedLocationSimulator =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"⚙️ 模拟器设置"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showLocationSimulatorSettings];
    }]];
    
    // ===== 自动化功能 - 集成GPSAutomationSystem =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"🔄 自动化规则"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showAutomationFunctions];
    }]];
    
    // ===== 地理围栏 - 集成GPSGeofencingSystem =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"🔶 地理围栏"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showGeofencingFunctions];
    }]];
    
    // ===== 仪表盘 - 集成GPSDashboardViewController =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"📱 实时仪表盘"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showDashboard];
    }]];
    
    // ===== 系统集成 - 集成GPSSystemIntegration =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"🔌 系统集成"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showSystemIntegrationOptions];
    }]];
    
    // ===== 高级设置 =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"⚙️ 高级设置"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showAdvancedSettings];
    }]];
    
    // ===== 取消按钮 =====
    [actionSheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    
    // iPad 支持
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = self.floatingButton;
        actionSheet.popoverPresentationController.sourceRect = self.floatingButton.bounds;
    }
    
    [self presentViewController:actionSheet animated:YES completion:nil];
}

#pragma mark - 高级功能实现

// 显示高级设置
- (void)showAdvancedSettings {
    GPSAdvancedSettingsViewController *advancedVC = [[GPSAdvancedSettingsViewController alloc] init];
    UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:advancedVC];
    navController.modalPresentationStyle = UIModalPresentationFormSheet;
    [self presentViewController:navController animated:YES completion:nil];
}

// 路线管理
- (void)showRouteManager {
    UIAlertController *routeAlert = [UIAlertController alertControllerWithTitle:@"路线管理"
                                                                       message:@"选择路线操作"
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 查看已保存的路线
    [routeAlert addAction:[UIAlertAction actionWithTitle:@"📋 查看保存的路线"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showSavedRoutes];
    }]];
    
    // 保存当前路径为路线
    [routeAlert addAction:[UIAlertAction actionWithTitle:@"💾 保存当前路径"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self saveCurrentPath];
    }]];
    
    // 创建新路线
    [routeAlert addAction:[UIAlertAction actionWithTitle:@"➕ 创建新路线"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self createNewRoute];
    }]];
    
    [routeAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        routeAlert.popoverPresentationController.sourceView = self.floatingButton;
        routeAlert.popoverPresentationController.sourceRect = self.floatingButton.bounds;
    }
    
    [self presentViewController:routeAlert animated:YES completion:nil];
}

// GPX文件导入
- (void)showGPXImporter {
    if (@available(iOS 14.0, *)) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] 
                                                initForOpeningContentTypes:@[[UTType typeWithIdentifier:@"com.topografix.gpx"]]];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        [self presentViewController:picker animated:YES completion:nil];
    } else {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] 
                                                initWithDocumentTypes:@[@"com.topografix.gpx"]
                                                               inMode:UIDocumentPickerModeImport];
        picker.delegate = self;
        picker.allowsMultipleSelection = NO;
        [self presentViewController:picker animated:YES completion:nil];
    }
}

// 坐标工具
- (void)showCoordinateUtils {
    UIAlertController *coordAlert = [UIAlertController alertControllerWithTitle:@"坐标工具"
                                                                        message:@"选择坐标功能"
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 坐标转换
    [coordAlert addAction:[UIAlertAction actionWithTitle:@"🔄 坐标系转换"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showCoordinateConverter];
    }]];
    
    // 距离计算
    [coordAlert addAction:[UIAlertAction actionWithTitle:@"📏 距离计算"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showDistanceCalculator];
    }]];
    
    // 航向计算
    [coordAlert addAction:[UIAlertAction actionWithTitle:@"🧭 航向计算"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showBearingCalculator];
    }]];
    
    // 路径插值
    [coordAlert addAction:[UIAlertAction actionWithTitle:@"📈 路径插值"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        [self showPathInterpolation];
    }]];
    
    [coordAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        coordAlert.popoverPresentationController.sourceView = self.floatingButton;
        coordAlert.popoverPresentationController.sourceRect = self.floatingButton.bounds;
    }
    
    [self presentViewController:coordAlert animated:YES completion:nil];
}

// 移动模式
- (void)showMovementModes {
    UIAlertController *moveAlert = [UIAlertController alertControllerWithTitle:@"移动模式"
                                                                       message:@"选择移动方式"
                                                                preferredStyle:UIAlertControllerStyleActionSheet];
    
    GPSLocationViewModel *viewModel = [GPSLocationViewModel sharedInstance];
    
    // 静止模式
    [moveAlert addAction:[UIAlertAction actionWithTitle:@"🛑 静止模式"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
        viewModel.movementMode = GPSMovementModeNone;
        [viewModel stopMoving];
        [self showAlertWithTitle:@"已设置" message:@"切换到静止模式"];
    }]];
    
    // 随机漫步
    [moveAlert addAction:[UIAlertAction actionWithTitle:@"🔀 随机漫步"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
        viewModel.movementMode = GPSMovementModeRandom;
        [viewModel startMoving];
        [self showAlertWithTitle:@"已启动" message:@"开始随机漫步模式"];
    }]];
    
    // 直线移动
    [moveAlert addAction:[UIAlertAction actionWithTitle:@"➡️ 直线移动"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
        viewModel.movementMode = GPSMovementModeLinear;
        [viewModel startMoving];
        [self showAlertWithTitle:@"已启动" message:@"开始直线移动模式"];
    }]];
    
    // 路径移动
    [moveAlert addAction:[UIAlertAction actionWithTitle:@"🛤️ 路径移动"
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
        [self selectRouteForMovement];
    }]];
    
    [moveAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                  style:UIAlertActionStyleCancel
                                                handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        moveAlert.popoverPresentationController.sourceView = self.floatingButton;
        moveAlert.popoverPresentationController.sourceRect = self.floatingButton.bounds;
    }
    
    [self presentViewController:moveAlert animated:YES completion:nil];
}

#pragma mark - 具体功能实现

// 查看保存的路线
- (void)showSavedRoutes {
    NSArray *routeNames = [[GPSRouteManager sharedInstance] savedRouteNames];
    
    if (routeNames.count == 0) {
        [self showAlertWithTitle:@"无保存的路线" message:@"您还没有保存任何路线"];
        return;
    }
    
    UIAlertController *routesAlert = [UIAlertController alertControllerWithTitle:@"已保存的路线"
                                                                         message:@"选择要加载的路线"
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString *routeName in routeNames) {
        [routesAlert addAction:[UIAlertAction actionWithTitle:routeName
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction * _Nonnull action) {
            [self loadRoute:routeName];
        }]];
    }
    
    [routesAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                    style:UIAlertActionStyleCancel
                                                  handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        routesAlert.popoverPresentationController.sourceView = self.view;
        routesAlert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:routesAlert animated:YES completion:nil];
}

// 加载路线
- (void)loadRoute:(NSString *)routeName {
    NSError *error;
    NSArray<GPSLocationModel *> *routePoints = [[GPSRouteManager sharedInstance] loadRouteWithName:routeName error:&error];
    
    if (error || !routePoints) {
        [self showAlertWithTitle:@"加载失败" message:@"无法加载路线文件"];
        return;
    }
    
    // 清除现有标注
    [self.mapView removeAnnotations:self.mapView.annotations];
    
    // 添加路线点到地图
    for (GPSLocationModel *point in routePoints) {
        MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
        annotation.coordinate = CLLocationCoordinate2DMake(point.latitude, point.longitude);
        annotation.title = point.title ?: @"路线点";
        [self.mapView addAnnotation:annotation];
    }
    
    // 调整地图视图以显示所有点
    if (routePoints.count > 0) {
        GPSLocationModel *firstPoint = routePoints.firstObject;
        CLLocationCoordinate2D center = CLLocationCoordinate2DMake(firstPoint.latitude, firstPoint.longitude);
        MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(center, 1000, 1000);
        [self.mapView setRegion:region animated:YES];
    }
    
    [self showAlertWithTitle:@"路线已加载" message:[NSString stringWithFormat:@"已加载 %lu 个路线点", (unsigned long)routePoints.count]];
}

// 坐标转换器
- (void)showCoordinateConverter {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"坐标转换"
                                                                   message:@"输入WGS84坐标进行转换"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"纬度";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"经度";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"转换为GCJ02"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        double lat = [alert.textFields[0].text doubleValue];
        double lng = [alert.textFields[1].text doubleValue];
        
        CLLocationCoordinate2D wgs84 = CLLocationCoordinate2DMake(lat, lng);
        CLLocationCoordinate2D gcj02 = [GPSCoordinateUtils transformWGS84ToGCJ02:wgs84];
        
        NSString *result = [NSString stringWithFormat:@"GCJ02坐标:\n纬度: %.6f\n经度: %.6f", gcj02.latitude, gcj02.longitude];
        [self showAlertWithTitle:@"转换结果" message:result];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 距离计算器
- (void)showDistanceCalculator {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"距离计算"
                                                                   message:@"输入两个坐标点"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"起点纬度";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"起点经度";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"终点纬度";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"终点经度";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"计算距离"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        double startLat = [alert.textFields[0].text doubleValue];
        double startLng = [alert.textFields[1].text doubleValue];
        double endLat = [alert.textFields[2].text doubleValue];
        double endLng = [alert.textFields[3].text doubleValue];
        
        CLLocationCoordinate2D startCoord = CLLocationCoordinate2DMake(startLat, startLng);
        CLLocationCoordinate2D endCoord = CLLocationCoordinate2DMake(endLat, endLng);
        
        double distance = [GPSCoordinateUtils calculateDistanceFrom:startCoord to:endCoord];
        [self showAlertWithTitle:@"计算结果" message:[NSString stringWithFormat:@"两点间距离: %.2f 米", distance]];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 航向计算器
- (void)showBearingCalculator {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"航向计算"
                                                                   message:@"输入起点和终点坐标"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"起点纬度";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"起点经度";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"终点纬度";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"终点经度";
        textField.keyboardType = UIKeyboardTypeDecimalPad;
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"计算航向"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        double startLat = [alert.textFields[0].text doubleValue];
        double startLng = [alert.textFields[1].text doubleValue];
        double endLat = [alert.textFields[2].text doubleValue];
        double endLng = [alert.textFields[3].text doubleValue];
        
        CLLocationCoordinate2D startCoord = CLLocationCoordinate2DMake(startLat, startLng);
        CLLocationCoordinate2D endCoord = CLLocationCoordinate2DMake(endLat, endLng);
        
        double bearing = [GPSCoordinateUtils calculateBearingFrom:startCoord to:endCoord];
        [self showAlertWithTitle:@"计算结果" message:[NSString stringWithFormat:@"航向角: %.2f 度", bearing]];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 路径插值
- (void)showPathInterpolation {
    if (self.mapView.annotations.count < 2) {
        [self showAlertWithTitle:@"需要更多点位" message:@"路径插值需要至少2个点位"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"路径插值"
                                                                   message:@"在现有点位间插入中间点"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"插值点数量";
        textField.keyboardType = UIKeyboardTypeNumberPad;
        textField.text = @"5";
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"开始插值"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        NSInteger interpolationCount = [alert.textFields.firstObject.text integerValue];
        if (interpolationCount <= 0 || interpolationCount > 100) {
            [self showAlertWithTitle:@"无效输入" message:@"插值点数量应在1-100之间"];
            return;
        }
        
        [self performPathInterpolationWithCount:interpolationCount];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 执行路径插值
- (void)performPathInterpolationWithCount:(NSInteger)count {
    NSArray *currentAnnotations = [self.mapView.annotations copy];
    NSMutableArray *allPoints = [NSMutableArray array];
    
    // 收集现有点位
    for (id<MKAnnotation> annotation in currentAnnotations) {
        if ([annotation isKindOfClass:[MKPointAnnotation class]]) {
            [allPoints addObject:annotation];
        }
    }
    
    if (allPoints.count < 2) return;
    
    // 清除现有标注
    [self.mapView removeAnnotations:self.mapView.annotations];
    
    // 在每两个连续点之间插值
    for (NSInteger i = 0; i < allPoints.count - 1; i++) {
        MKPointAnnotation *startPoint = allPoints[i];
        MKPointAnnotation *endPoint = allPoints[i + 1];
        
        // 添加起始点
        [self.mapView addAnnotation:startPoint];
        
        // 在两点间插值
        for (NSInteger j = 1; j <= count; j++) {
            double ratio = (double)j / (double)(count + 1);
            double lat = startPoint.coordinate.latitude + (endPoint.coordinate.latitude - startPoint.coordinate.latitude) * ratio;
            double lng = startPoint.coordinate.longitude + (endPoint.coordinate.longitude - startPoint.coordinate.longitude) * ratio;
            
            MKPointAnnotation *interpolatedPoint = [[MKPointAnnotation alloc] init];
            interpolatedPoint.coordinate = CLLocationCoordinate2DMake(lat, lng);
            interpolatedPoint.title = [NSString stringWithFormat:@"插值点_%ld_%ld", (long)i, (long)j];
            [self.mapView addAnnotation:interpolatedPoint];
        }
    }
    
    // 添加最后一个点
    [self.mapView addAnnotation:allPoints.lastObject];
    
    [self showAlertWithTitle:@"插值完成" 
                    message:[NSString stringWithFormat:@"已在路径中插入 %ld 个中间点", (long)(count * (allPoints.count - 1))]];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    // 立即将管理器置为nil，防止任何后续回调
    self.locationManager.delegate = nil;
    
    CLLocation *currentLocation = locations.lastObject;
    if (currentLocation) {
        // 停止位置服务
        [manager stopUpdatingLocation];
        
        // 更新地图和位置信息
        [self.mapView removeAnnotations:self.mapView.annotations];
        [self addAnnotationAtCoordinate:currentLocation.coordinate withTitle:@"当前位置"];
        
        self.locationLabel.text = [NSString stringWithFormat:@"位置: %.4f, %.4f", 
                                  currentLocation.coordinate.latitude, 
                                  currentLocation.coordinate.longitude];
        
        // 只显示一次弹窗
        static BOOL alertShown = NO;
        if (!alertShown) {
            [self showAlertWithTitle:@"位置已获取" message:@"已使用您的当前位置"];
            alertShown = YES;
            
            // 5秒后重置标志位，以便下次能显示
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                alertShown = NO;
            });
        }
        
        // 完全清除位置管理器
        self.locationManager = nil;
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    [self showAlertWithTitle:@"位置获取失败" message:error.localizedDescription];
}

// 动画方法
- (void)animateButtonPress:(UIButton *)sender {
    [UIView animateWithDuration:0.2 
                     animations:^{
                         sender.transform = CGAffineTransformMakeScale(0.92, 0.92);
                         sender.alpha = 0.8;
                     }];
}

- (void)animateButtonRelease:(UIButton *)sender {
    [UIView animateWithDuration:0.3 
                          delay:0 
         usingSpringWithDamping:0.6 
          initialSpringVelocity:0.2 
                        options:UIViewAnimationOptionCurveEaseOut 
                     animations:^{
                         sender.transform = CGAffineTransformIdentity;
                         sender.alpha = 1.0;
                     } 
                     completion:nil];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    [self dismissKeyboard];
}

// 为按钮添加美化效果
- (void)enhanceButton:(UIButton *)button {
    button.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.85];
    button.layer.cornerRadius = 12;
    button.layer.shadowColor = [UIColor blackColor].CGColor;
    button.layer.shadowOffset = CGSizeMake(0, 3);
    button.layer.shadowOpacity = 0.2;
    button.layer.shadowRadius = 5;
    button.tintColor = [UIColor systemBlueColor];
}

// 创建分段控制器
- (void)setupActionControls {
    // 创建分段控制器，用于选择不同的操作
    NSArray *actions = @[@"历史位置", @"手动输入", @"设置海拔"];
    self.actionControl = [[UISegmentedControl alloc] initWithItems:actions];
    self.actionControl.selectedSegmentIndex = -1;
    self.actionControl.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.8];
    self.actionControl.layer.cornerRadius = 8;
    self.actionControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.actionControl addTarget:self action:@selector(segmentAction:) forControlEvents:UIControlEventValueChanged];
    
    [self.view addSubview:self.actionControl];
}

// 预设位置实现
- (void)showPresetLocations {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"预设位置"
                                                                   message:@"选择一个预设位置"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 添加一些常用地标位置
    NSDictionary *landmarks = @{
        @"北京故宫": @{@"lat": @39.9163, @"lng": @116.3972},
        @"上海东方明珠": @{@"lat": @31.2396, @"lng": @121.4998},
        @"广州塔": @{@"lat": @23.1066, @"lng": @113.3214},
        @"深圳世界之窗": @{@"lat": @22.5364, @"lng": @113.9735},
        @"香港维多利亚港": @{@"lat": @22.2783, @"lng": @114.1747},
        @"西安钟楼": @{@"lat": @34.2568, @"lng": @108.9433},
        @"成都春熙路": @{@"lat": @30.6559, @"lng": @104.0836}
    };
    
    [landmarks enumerateKeysAndObjectsUsingBlock:^(NSString *name, NSDictionary *coords, BOOL *stop) {
        [alert addAction:[UIAlertAction actionWithTitle:name
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            CLLocationCoordinate2D coordinate = CLLocationCoordinate2DMake([coords[@"lat"] doubleValue],
                                                                          [coords[@"lng"] doubleValue]);
            [self.mapView removeAnnotations:self.mapView.annotations];
            [self addAnnotationAtCoordinate:coordinate withTitle:name];
        }]];
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    // iPad支持
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = self.view.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 使用当前位置
- (void)useCurrentLocation {
    [self.locationManager requestWhenInUseAuthorization];
    self.locationManager.delegate = self;
    [self.locationManager startUpdatingLocation];
}

// 生成随机位置
- (void)generateRandomLocation {
    // 在当前视图区域内生成一个随机位置
    MKCoordinateRegion region = self.mapView.region;
    double latDelta = region.span.latitudeDelta;
    double lngDelta = region.span.longitudeDelta;
    
    double randomLat = region.center.latitude + (((double)arc4random() / UINT32_MAX) - 0.5) * latDelta;
    double randomLng = region.center.longitude + (((double)arc4random() / UINT32_MAX) - 0.5) * lngDelta;
    
    // 确保范围有效
    randomLat = MAX(-90.0, MIN(90.0, randomLat));
    randomLng = MAX(-180.0, MIN(180.0, randomLng));
    
    CLLocationCoordinate2D randomCoord = CLLocationCoordinate2DMake(randomLat, randomLng);
    
    [self.mapView removeAnnotations:self.mapView.annotations];
    [self addAnnotationAtCoordinate:randomCoord withTitle:@"随机位置"];
    
    self.locationLabel.text = [NSString stringWithFormat:@"位置: %.4f, %.4f", randomLat, randomLng];
}

// 保存当前路径
- (void)saveCurrentPath {
    if (self.mapView.annotations.count < 2) {
        [self showAlertWithTitle:@"点位不足" message:@"需要至少2个点位才能保存路径"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存路径"
                                                                   message:@"请输入路径名称"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"路径名称";
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"保存"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        NSString *routeName = alert.textFields[0].text;
        if (routeName.length == 0) {
            routeName = [NSString stringWithFormat:@"路径_%@", [NSDate date]];
        }
        
        // 收集所有点位
        NSMutableArray *routePoints = [NSMutableArray array];
        for (id<MKAnnotation> annotation in self.mapView.annotations) {
            if ([annotation isKindOfClass:[MKPointAnnotation class]]) {
                GPSLocationModel *point = [[GPSLocationModel alloc] init];
                point.latitude = annotation.coordinate.latitude;
                point.longitude = annotation.coordinate.longitude;
                point.title = annotation.title ?: @"路线点";
                [routePoints addObject:point];
            }
        }
        
        // 保存路径
        NSError *error;
        BOOL success = [[GPSRouteManager sharedInstance] saveRoute:routePoints withName:routeName error:&error];
        
        if (success) {
            [self showAlertWithTitle:@"保存成功" message:@"路径已成功保存"];
        } else {
            [self showAlertWithTitle:@"保存失败" message:error.localizedDescription ?: @"未知错误"];
        }
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 创建新路线
- (void)createNewRoute {
    [self.mapView removeAnnotations:self.mapView.annotations];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"创建路线"
                                                                   message:@"清空了现有点位。长按地图添加新的点位，完成后点击保存路径。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 选择路线进行移动
- (void)selectRouteForMovement {
    NSArray *routeNames = [[GPSRouteManager sharedInstance] savedRouteNames];
    
    if (routeNames.count == 0) {
        [self showAlertWithTitle:@"无保存的路线" message:@"请先创建并保存路线"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择路线"
                                                                   message:@"选择要移动的路线"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString *routeName in routeNames) {
        [alert addAction:[UIAlertAction actionWithTitle:routeName
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            // 加载路线并设置移动模式
            NSError *error;
            NSArray<GPSLocationModel *> *route = [[GPSRouteManager sharedInstance] loadRouteWithName:routeName error:&error];
            
            if (route) {
                GPSLocationViewModel *viewModel = [GPSLocationViewModel sharedInstance];
                viewModel.movementMode = GPSMovementModeRoute;
                
                // 尝试几种不同的方式设置路线
                @try {
                    // 方式1: 使用KVC
                    [viewModel setValue:route forKey:@"route"];
                } 
                @catch (NSException *exception) {
                    // 方式2: 使用关联对象
                    const void *routeKey = &routeKey;
                    objc_setAssociatedObject(viewModel, routeKey, route, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                
                [viewModel startMoving];
                
                [self showAlertWithTitle:@"已启动" message:@"开始路径移动模式"];
            } else {
                [self showAlertWithTitle:@"加载失败" message:error.localizedDescription ?: @"未知错误"];
            }
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.floatingButton;
        alert.popoverPresentationController.sourceRect = self.floatingButton.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 删除录制
- (void)deleteRecording:(NSString *)recordingId {
    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"确认删除"
                                                                         message:@"确定要删除这个录制吗？此操作不可恢复。"
                                                                  preferredStyle:UIAlertControllerStyleAlert];
    
    [confirmAlert addAction:[UIAlertAction actionWithTitle:@"删除"
                                                     style:UIAlertActionStyleDestructive
                                                   handler:^(UIAlertAction * _Nonnull action) {
        BOOL success = [[GPSRecordingSystem sharedInstance] deleteRecording:recordingId];
        [self showAlertWithTitle:success ? @"删除成功" : @"删除失败" 
                        message:success ? @"录制已被删除" : @"无法删除录制"];
    }]];
    
    [confirmAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                     style:UIAlertActionStyleCancel
                                                   handler:nil]];
    
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

// 位置模拟器设置
- (void)showLocationSimulatorSettings {
    UIAlertController *simSheet = [UIAlertController alertControllerWithTitle:@"位置模拟器设置"
                                                                     message:@"配置位置模拟器参数"
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 精度等级
    [simSheet addAction:[UIAlertAction actionWithTitle:@"🎯 设置精度等级"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        [self showAccuracyLevelOptions];
    }]];
    
    // 环境类型
    [simSheet addAction:[UIAlertAction actionWithTitle:@"🏙️ 设置环境类型"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        [self showEnvironmentTypeOptions];
    }]];
    
    // 信号漂移
    GPSAdvancedLocationSimulator *simulator = [GPSAdvancedLocationSimulator sharedInstance];
    NSString *driftTitle = simulator.enableSignalDrift ? @"📴 禁用信号漂移" : @"📲 启用信号漂移";
    
    [simSheet addAction:[UIAlertAction actionWithTitle:driftTitle
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        simulator.enableSignalDrift = !simulator.enableSignalDrift;
        [self showAlertWithTitle:@"设置已更新" 
                        message:simulator.enableSignalDrift ? @"信号漂移已启用" : @"信号漂移已禁用"];
    }]];
    
    // 自动精度调整
    NSString *autoAccTitle = simulator.enableAutoAccuracy ? @"🔓 禁用自动精度调整" : @"🔐 启用自动精度调整";
    
    [simSheet addAction:[UIAlertAction actionWithTitle:autoAccTitle
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        simulator.enableAutoAccuracy = !simulator.enableAutoAccuracy;
        [self showAlertWithTitle:@"设置已更新" 
                        message:simulator.enableAutoAccuracy ? @"自动精度调整已启用" : @"自动精度调整已禁用"];
    }]];
    
    // 校准模拟参数
    [simSheet addAction:[UIAlertAction actionWithTitle:@"🔄 校准模拟参数"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        [simulator calibrateSimulationParameters];
        [self showAlertWithTitle:@"校准完成" message:@"位置模拟参数已优化以提高真实度"];
    }]];
    
    [simSheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        simSheet.popoverPresentationController.sourceView = self.view;
        simSheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:simSheet animated:YES completion:nil];
}

// 精度设置选项
- (void)showAccuracyLevelOptions {
    UIAlertController *accSheet = [UIAlertController alertControllerWithTitle:@"选择精度等级"
                                                                     message:nil
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSArray *accuracyLevels = @[
        @{@"title": @"超高精度", @"level": @(GPSAccuracyLevelUltra), @"description": @"误差极小"},
        @{@"title": @"高精度", @"level": @(GPSAccuracyLevelHigh), @"description": @"适用于精确定位"},
        @{@"title": @"中等精度", @"level": @(GPSAccuracyLevelMedium), @"description": @"适合日常使用"},
        @{@"title": @"低精度", @"level": @(GPSAccuracyLevelLow), @"description": @"模拟普通设备"},
        @{@"title": @"变化精度", @"level": @(GPSAccuracyLevelVariable), @"description": @"自动根据环境变化"}
    ];
    
    for (NSDictionary *level in accuracyLevels) {
        [accSheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ - %@", level[@"title"], level[@"description"]]
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
            GPSAccuracyLevel accuracyLevel = [level[@"level"] intValue];
            [[GPSAdvancedLocationSimulator sharedInstance] setAccuracyLevel:accuracyLevel];
            [self showAlertWithTitle:@"精度已设置" message:[NSString stringWithFormat:@"已将精度等级设为: %@", level[@"title"]]];
        }]];
    }
    
    [accSheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        accSheet.popoverPresentationController.sourceView = self.view;
        accSheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:accSheet animated:YES completion:nil];
}

// 环境类型选项
- (void)showEnvironmentTypeOptions {
    UIAlertController *envSheet = [UIAlertController alertControllerWithTitle:@"选择环境类型"
                                                                     message:nil
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    
    NSArray *environmentTypes = @[
        @{@"title": @"城市", @"type": @(GPSEnvironmentTypeUrban), @"description": @"高楼密集区域"},
        @{@"title": @"郊区", @"type": @(GPSEnvironmentTypeSuburban), @"description": @"城市边缘地区"},
        @{@"title": @"乡村", @"type": @(GPSEnvironmentTypeRural), @"description": @"开阔区域"},
        @{@"title": @"室内", @"type": @(GPSEnvironmentTypeIndoor), @"description": @"建筑物内部"},
        @{@"title": @"地下", @"type": @(GPSEnvironmentTypeUnderground), @"description": @"地下区域"},
        @{@"title": @"峡谷", @"type": @(GPSEnvironmentTypeCanyon), @"description": @"两侧有高墙"}
    ];
    
    for (NSDictionary *env in environmentTypes) {
        [envSheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%@ - %@", env[@"title"], env[@"description"]]
                                                    style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction * _Nonnull action) {
            GPSEnvironmentType envType = [env[@"type"] intValue];
            [[GPSAdvancedLocationSimulator sharedInstance] setEnvironmentType:envType];
            [self showAlertWithTitle:@"环境已设置" message:[NSString stringWithFormat:@"已将环境类型设为: %@", env[@"title"]]];
        }]];
    }
    
    [envSheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                            style:UIAlertActionStyleCancel
                                          handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        envSheet.popoverPresentationController.sourceView = self.view;
        envSheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:envSheet animated:YES completion:nil];
}

// 显示系统集成选项
- (void)showSystemIntegrationOptions {
    UIAlertController *sysSheet = [UIAlertController alertControllerWithTitle:@"系统集成"
                                                                     message:@"管理系统级集成选项"
                                                              preferredStyle:UIAlertControllerStyleActionSheet];
    
    GPSSystemIntegration *integration = [GPSSystemIntegration sharedInstance];
    BOOL systemWideEnabled = [integration isSystemWideIntegrationEnabled];
    
    // 系统级集成开关
    NSString *systemWideTitle = systemWideEnabled ? 
        @"🔴 禁用系统级集成" : @"🟢 启用系统级集成";
    
    [sysSheet addAction:[UIAlertAction actionWithTitle:systemWideTitle
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        GPSIntegrationLevel level = [integration availableIntegrationLevel];
        
        if (!systemWideEnabled && level < GPSIntegrationLevelDeep) {
            [self showAlertWithTitle:@"权限不足" 
                            message:@"启用系统级集成需要至少深度级别的集成权限。请确认您的设备已获得必要的权限。"];
            return;
        }
        
        [integration enableSystemWideIntegration:!systemWideEnabled];
        [self showAlertWithTitle:@"设置已更新" 
                        message:systemWideEnabled ? @"系统级集成已禁用" : @"系统级集成已启用"];
    }]];
    
    // 申请增强权限
    [sysSheet addAction:[UIAlertAction actionWithTitle:@"🔑 申请增强权限"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        [integration requestEnhancedPermissions:^(BOOL granted, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    [self showAlertWithTitle:@"权限已授予" message:@"已获得增强的系统集成权限"];
                } else {
                    [self showAlertWithTitle:@"权限请求失败" message:error.localizedDescription ?: @"无法获取增强权限"];
                }
            });
        }];
    }]];
    
    // 权限说明
    [sysSheet addAction:[UIAlertAction actionWithTitle:@"❓ 权限说明"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        [integration presentPermissionsExplanation];
    }]];
    
    // 性能优化选项
    [sysSheet addAction:[UIAlertAction actionWithTitle:@"🔋 电池优化"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *batteryAlert = [UIAlertController alertControllerWithTitle:@"电池优化"
                                                                             message:@"选择电池优化模式"
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
        
        [batteryAlert addAction:[UIAlertAction actionWithTitle:@"开启电池优化"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
            [integration optimizeBatteryUsage:YES];
            [self showAlertWithTitle:@"已启用" message:@"电池优化已开启"];
        }]];
        
        [batteryAlert addAction:[UIAlertAction actionWithTitle:@"关闭电池优化"
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
            [integration optimizeBatteryUsage:NO];
            [self showAlertWithTitle:@"已禁用" message:@"电池优化已关闭"];
        }]];
        
        [batteryAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                         style:UIAlertActionStyleCancel
                                                       handler:nil]];
        
        [self presentViewController:batteryAlert animated:YES completion:nil];
    }]];
    
    // 内存优化选项
    [sysSheet addAction:[UIAlertAction actionWithTitle:@"💾 内存优化"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *memoryAlert = [UIAlertController alertControllerWithTitle:@"内存优化"
                                                                             message:@"选择内存优化模式"
                                                                      preferredStyle:UIAlertControllerStyleActionSheet];
        
        [memoryAlert addAction:[UIAlertAction actionWithTitle:@"开启内存优化"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction * _Nonnull action) {
            [integration optimizeMemoryUsage:YES];
            [self showAlertWithTitle:@"已启用" message:@"内存优化已开启"];
        }]];
        
        [memoryAlert addAction:[UIAlertAction actionWithTitle:@"关闭内存优化"
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction * _Nonnull action) {
            [integration optimizeMemoryUsage:NO];
            [self showAlertWithTitle:@"已禁用" message:@"内存优化已关闭"];
        }]];
        
        [memoryAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                       style:UIAlertActionStyleCancel
                                                     handler:nil]];
        
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            memoryAlert.popoverPresentationController.sourceView = self.view;
            memoryAlert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
        }
        
        [self presentViewController:memoryAlert animated:YES completion:nil];
    }]];
    
    // 后台模式设置
    [sysSheet addAction:[UIAlertAction actionWithTitle:@"⏱️ 后台模式设置"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *bgAlert = [UIAlertController alertControllerWithTitle:@"后台模式设置"
                                                                        message:@"配置应用在后台时的行为"
                                                                 preferredStyle:UIAlertControllerStyleActionSheet];
        
        [bgAlert addAction:[UIAlertAction actionWithTitle:@"持续运行"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
            [integration enableContinuousBackgroundMode:YES];
            [self showAlertWithTitle:@"已设置" message:@"应用将在后台持续运行"];
        }]];
        
        [bgAlert addAction:[UIAlertAction actionWithTitle:@"省电模式"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
            [integration enableContinuousBackgroundMode:NO];
            [self showAlertWithTitle:@"已设置" message:@"应用将在后台采用省电模式"];
        }]];
        
        [bgAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
        
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
            bgAlert.popoverPresentationController.sourceView = self.view;
            bgAlert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
        }
        
        [self presentViewController:bgAlert animated:YES completion:nil];
    }]];
    
    // 清理缓存数据
    [sysSheet addAction:[UIAlertAction actionWithTitle:@"🧹 清理缓存数据"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:@"确认清理缓存"
                                                                             message:@"这将清除所有临时数据，但不会影响您保存的位置和路线。"
                                                                      preferredStyle:UIAlertControllerStyleAlert];
        
        [confirmAlert addAction:[UIAlertAction actionWithTitle:@"清理"
                                                         style:UIAlertActionStyleDestructive
                                                       handler:^(UIAlertAction * _Nonnull action) {
            [integration clearCachedData];
            [self showAlertWithTitle:@"已清理" message:@"缓存数据已清理完成"];
        }]];
        
        [confirmAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                         style:UIAlertActionStyleCancel
                                                       handler:nil]];
        
        [self presentViewController:confirmAlert animated:YES completion:nil];
    }]];
    
    // 系统诊断
    [sysSheet addAction:[UIAlertAction actionWithTitle:@"🔍 系统诊断"
                                                style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction * _Nonnull action) {
        [self showAlertWithTitle:@"正在诊断" message:@"正在检测系统状态..."];
        
        [integration runSystemDiagnostics:^(NSDictionary *results) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSMutableString *diagnosticReport = [NSMutableString string];
                [diagnosticReport appendFormat:@"系统版本: %@\n", results[@"systemVersion"]];
                [diagnosticReport appendFormat:@"集成状态: %@\n", [results[@"integrationStatus"] boolValue] ? @"正常" : @"异常"];
                [diagnosticReport appendFormat:@"内存使用: %@MB\n", results[@"memoryUsage"]];
                [diagnosticReport appendFormat:@"CPU负载: %@%%\n", results[@"cpuUsage"]];
                [diagnosticReport appendFormat:@"电池状态: %@\n", results[@"batteryStatus"]];
                [diagnosticReport appendFormat:@"存储空间: %@MB可用\n", results[@"availableStorage"]];
                
                [self showAlertWithTitle:@"诊断报告" message:diagnosticReport];
            });
        }];
    }]];
    
    [sysSheet addAction:[UIAlertAction actionWithTitle:@"取消"
                                                style:UIAlertActionStyleCancel
                                              handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        sysSheet.popoverPresentationController.sourceView = self.view;
        sysSheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:sysSheet animated:YES completion:nil];
}

// 显示仪表盘
- (void)showDashboard {
    GPSDashboardViewController *dashboardVC = [[GPSDashboardViewController alloc] init];
    dashboardVC.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:dashboardVC animated:YES completion:nil];
}

// 重命名录制
- (void)renameRecording:(NSString *)recordingId metadata:(GPSRecordingMetadata *)metadata {
    UIAlertController *renameAlert = [UIAlertController alertControllerWithTitle:@"重命名录制"
                                                                        message:@"请输入新名称"
                                                                 preferredStyle:UIAlertControllerStyleAlert];
    
    [renameAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.text = metadata.name;
    }];
    
    [renameAlert addAction:[UIAlertAction actionWithTitle:@"确定"
                                                   style:UIAlertActionStyleDefault
                                                 handler:^(UIAlertAction * _Nonnull action) {
        NSString *newName = renameAlert.textFields.firstObject.text;
        if (newName.length > 0) {
            BOOL success = [[GPSRecordingSystem sharedInstance] renameRecording:recordingId newName:newName];
            [self showAlertWithTitle:success ? @"重命名成功" : @"重命名失败" 
                            message:success ? @"录制名称已更新" : @"无法更新录制名称"];
        }
    }]];
    
    [renameAlert addAction:[UIAlertAction actionWithTitle:@"取消"
                                                   style:UIAlertActionStyleCancel
                                                 handler:nil]];
    
    [self presentViewController:renameAlert animated:YES completion:nil];
}

// 退出按钮设置
- (void)setupExitButton {
    UIButton *exitButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [exitButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    exitButton.tintColor = [UIColor systemGrayColor];
    [exitButton addTarget:self action:@selector(closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self enhanceButton:exitButton];
    exitButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:exitButton];
    [NSLayoutConstraint activateConstraints:@[
        [exitButton.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:10],
        [exitButton.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-15],
        [exitButton.widthAnchor constraintEqualToConstant:44],
        [exitButton.heightAnchor constraintEqualToConstant:44]
    ]];
}

// 退出按钮点击事件
- (void)exitButtonTapped:(id)sender {
    if (self.presentingViewController) {
        [self dismissViewControllerAnimated:YES completion:nil];
    } else if (self.navigationController) {
        [self.navigationController popViewControllerAnimated:YES];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"ReturnToMainPage" object:nil];
    }
}

// 更新位置信息
- (void)updateLocationInfoWithCoordinate:(CLLocationCoordinate2D)coordinate title:(NSString *)title {
    self.locationLabel.text = [NSString stringWithFormat:@"位置: %.6f, %.6f", coordinate.latitude, coordinate.longitude];
    
    // 更新海拔信息
    [self.geocoder reverseGeocodeLocation:[[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude]
                       completionHandler:^(NSArray<CLPlacemark *> * _Nullable placemarks, NSError * _Nullable error) {
        if (placemarks.count > 0) {
            CLPlacemark *placemark = placemarks.firstObject;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.addressLabel.text = placemark.name ?: title;
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.addressLabel.text = title ?: @"未知地点";
            });
        }
    }];
    
    // 尝试获取海拔
    [[GPSElevationService sharedInstance] getElevationForLocation:coordinate completion:^(double elevation, NSError *error) {
        if (!error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.altitudeLabel.text = [NSString stringWithFormat:@"海拔: %.2f米", elevation];
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.altitudeLabel.text = @"海拔: 未知";
            });
        }
    }];
}

// 位置功能菜单
- (void)showLocationFunctions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"位置功能"
                                                                   message:@"选择位置操作"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 查看历史位置" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showHistory];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📍 手动输入坐标" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showManualInput];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🗺️ 预设地标位置" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showPresetLocations];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📱 使用当前位置" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self useCurrentLocation];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🎲 生成随机位置" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self generateRandomLocation];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = self.view.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 路径功能菜单
- (void)showRouteFunctions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"路径功能"
                                                                   message:@"选择路径操作"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🗺️ 管理保存的路线" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showRouteManager];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"➕ 创建新路线" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self createNewRoute];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📥 导入GPX文件" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showGPXImporter];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 录制功能菜单
- (void)showRecordingFunctions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"录制与回放"
                                                                   message:@"选择录制操作"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 获取当前录制状态
    GPSRecordingState recordingState = [[GPSRecordingSystem sharedInstance] recordingState];
    GPSPlaybackState playbackState = [[GPSRecordingSystem sharedInstance] playbackState];
    
    if (recordingState == GPSRecordingStateIdle) {
        [alert addAction:[UIAlertAction actionWithTitle:@"🔴 开始新录制" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            UIAlertController *nameAlert = [UIAlertController alertControllerWithTitle:@"录制名称"
                                                                               message:@"请输入录制名称"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            
            [nameAlert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
                textField.placeholder = @"录制名称";
                NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
                textField.text = [NSString stringWithFormat:@"录制_%@", [formatter stringFromDate:[NSDate date]]];
            }];
            
            [nameAlert addAction:[UIAlertAction actionWithTitle:@"开始" style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
                NSString *name = nameAlert.textFields.firstObject.text;
                BOOL success = [[GPSRecordingSystem sharedInstance] startRecordingWithName:name];
                [self showAlertWithTitle:success ? @"录制已开始" : @"录制失败" 
                                message:success ? @"位置录制已开始" : @"无法开始录制，请检查设置"];
            }]];
            
            [nameAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            
            [self presentViewController:nameAlert animated:YES completion:nil];
        }]];
    } else if (recordingState == GPSRecordingStateRecording) {
        [alert addAction:[UIAlertAction actionWithTitle:@"⏸️ 暂停录制" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [[GPSRecordingSystem sharedInstance] pauseRecording];
            [self showAlertWithTitle:@"录制已暂停" message:@"位置录制已暂停"];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"⏹️ 停止录制" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [[GPSRecordingSystem sharedInstance] stopRecording];
            [self showAlertWithTitle:@"录制已停止" message:@"位置录制已完成"];
        }]];
    } else if (recordingState == GPSRecordingStatePaused) {
        [alert addAction:[UIAlertAction actionWithTitle:@"▶️ 继续录制" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [[GPSRecordingSystem sharedInstance] resumeRecording];
            [self showAlertWithTitle:@"录制已继续" message:@"位置录制已恢复"];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"⏹️ 停止录制" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [[GPSRecordingSystem sharedInstance] stopRecording];
            [self showAlertWithTitle:@"录制已停止" message:@"位置录制已完成"];
        }]];
    }
    
    // 播放控制
    if (playbackState == GPSPlaybackStateIdle) {
        [alert addAction:[UIAlertAction actionWithTitle:@"▶️ 回放录制" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
            [self showRecordingsList];
        }]];
    } else if (playbackState == GPSPlaybackStatePlaying) {
        [alert addAction:[UIAlertAction actionWithTitle:@"⏸️ 暂停回放" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [[GPSRecordingSystem sharedInstance] pausePlayback];
            [self showAlertWithTitle:@"回放已暂停" message:@"位置回放已暂停"];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"⏹️ 停止回放" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [[GPSRecordingSystem sharedInstance] stopPlayback];
            [self showAlertWithTitle:@"回放已停止" message:@"位置回放已结束"];
        }]];
    } else if (playbackState == GPSPlaybackStatePaused) {
        [alert addAction:[UIAlertAction actionWithTitle:@"▶️ 继续回放" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [[GPSRecordingSystem sharedInstance] resumePlayback];
            [self showAlertWithTitle:@"回放已继续" message:@"位置回放已恢复"];
        }]];
        
        [alert addAction:[UIAlertAction actionWithTitle:@"⏹️ 停止回放" style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [[GPSRecordingSystem sharedInstance] stopPlayback];
            [self showAlertWithTitle:@"回放已停止" message:@"位置回放已结束"];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 管理录制" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showRecordingsList];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 分析功能菜单
- (void)showAnalyticsFunctions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"分析工具"
                                                                   message:@"选择分析功能"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📊 分析录制数据" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showAnalyticsOptions];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📈 查看统计报告" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showStatisticsReport];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🗂️ 导出分析数据" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showExportOptions];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 高级地图功能菜单
- (void)showAdvancedMapFunctions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"高级地图"
                                                                   message:@"选择地图功能"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🌐 打开高级地图" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        GPSAdvancedMapController *mapController = [[GPSAdvancedMapController alloc] init];
        UINavigationController *navController = [[UINavigationController alloc] initWithRootViewController:mapController];
        navController.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:navController animated:YES completion:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🔥 显示热力图" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        // 热力图实现...
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📐 测量工具" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        // 测量工具实现...
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"🏔️ 3D地形图" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        // 3D地形图实现...
    }]];
    
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 自动化功能菜单
- (void)showAutomationFunctions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"自动化规则"
                                                                   message:@"管理自动化功能"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"➕ 创建新规则" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showCreateRuleInterface];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 管理现有规则" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showRulesList];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📊 自动化统计" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showAutomationStats];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 地理围栏功能菜单
- (void)showGeofencingFunctions {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"地理围栏"
                                                                   message:@"管理地理围栏功能"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"➕ 添加新围栏" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showAddGeofenceInterface];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📋 管理现有围栏" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showGeofencesList];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📊 围栏活动记录" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showGeofenceEvents];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 以下是额外需要实现的辅助方法（根据需要添加）
- (void)showRecordingsList {
    // 获取所有录制
    NSArray<NSString *> *recordings = [[GPSRecordingSystem sharedInstance] allRecordings];
    
    if (recordings.count == 0) {
        [self showAlertWithTitle:@"无录制" message:@"暂无保存的录制"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"录制列表"
                                                                   message:@"选择要操作的录制"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString *recordingId in recordings) {
        GPSRecordingMetadata *metadata = [[GPSRecordingSystem sharedInstance] metadataForRecording:recordingId];
        NSString *title = metadata.name ?: recordingId;
        
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self showRecordingActions:recordingId metadata:metadata];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showRecordingActions:(NSString *)recordingId metadata:(GPSRecordingMetadata *)metadata {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:metadata.name
                                                                   message:[NSString stringWithFormat:@"创建时间: %@\n点数: %ld\n总距离: %.2f米",
                                                                           metadata.creationDate,
                                                                           (long)metadata.pointCount,
                                                                           metadata.totalDistance]
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"▶️ 回放录制" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        BOOL success = [[GPSRecordingSystem sharedInstance] startPlayback:recordingId];
        [self showAlertWithTitle:success ? @"回放已开始" : @"回放失败"
                        message:success ? @"开始回放录制内容" : @"无法开始回放，请检查录制数据"];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📝 重命名" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self renameRecording:recordingId metadata:metadata];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"📤 导出为GPX" style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self showProgressIndicator];
        [[GPSRecordingSystem sharedInstance] exportRecording:recordingId toGPX:^(NSURL *fileURL, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self hideProgressIndicator];
                if (!error && fileURL) {
                    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
                    [self presentViewController:activityVC animated:YES completion:nil];
                } else {
                    [self showAlertWithTitle:@"导出失败" message:error.localizedDescription ?: @"无法导出录制"];
                }
            });
        }];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"❌ 删除录制" style:UIAlertActionStyleDestructive
                                            handler:^(UIAlertAction * _Nonnull action) {
        [self deleteRecording:recordingId];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 显示/隐藏进度指示器
- (void)showProgressIndicator {
    self.progressView.progress = 0;
    self.progressView.alpha = 1.0;
    
    [UIView animateWithDuration:0.3 animations:^{
        self.progressView.progress = 0.1;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:1.0 animations:^{
            self.progressView.progress = 0.7;
        }];
    }];
}

- (void)hideProgressIndicator {
    [UIView animateWithDuration:0.3 animations:^{
        self.progressView.progress = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:0.2 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.progressView.alpha = 0;
        } completion:nil];
    }];
}

// 分析选项
- (void)showAnalyticsOptions {
    // 获取所有录制
    NSArray<NSString *> *recordings = [[GPSRecordingSystem sharedInstance] allRecordings];
    
    if (recordings.count == 0) {
        [self showAlertWithTitle:@"无录制" message:@"暂无保存的录制可供分析"];
        return;
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择要分析的录制"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    for (NSString *recordingId in recordings) {
        GPSRecordingMetadata *metadata = [[GPSRecordingSystem sharedInstance] metadataForRecording:recordingId];
        NSString *title = metadata.name ?: recordingId;
        
        [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction * _Nonnull action) {
            [self analyzeRecording:recordingId];
        }]];
    }
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = self.view;
        alert.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2, 1, 1);
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)analyzeRecording:(NSString *)recordingId {
    [self showProgressIndicator];
    
    NSArray<GPSLocationModel *> *points = [[GPSRecordingSystem sharedInstance] dataForRecording:recordingId];
    
    if (points.count < 2) {
        [self hideProgressIndicator];
        [self showAlertWithTitle:@"数据不足" message:@"录制中的点数太少，无法进行有效分析"];
        return;
    }
    
    GPSAnalyticsSummary *summary = [[GPSAnalyticsSystem sharedInstance] analyzeRoute:points];
    
    [self hideProgressIndicator];
    
    if (summary) {
        NSMutableString *report = [NSMutableString string];
        [report appendFormat:@"总距离: %.2f 米\n", summary.totalDistance];
        [report appendFormat:@"总时长: %.2f 分钟\n", summary.totalDuration / 60.0];
        [report appendFormat:@"平均速度: %.2f 米/秒\n", summary.averageSpeed];
        [report appendFormat:@"最高速度: %.2f 米/秒\n", summary.maxSpeed];
        [report appendFormat:@"最低速度: %.2f 米/秒\n", summary.minSpeed];
        [report appendFormat:@"总上升: %.2f 米\n", summary.totalAscent];
        [report appendFormat:@"总下降: %.2f 米\n", summary.totalDescent];
        
        [self showAlertWithTitle:@"分析报告" message:report];
    } else {
        [self showAlertWithTitle:@"分析失败" message:@"无法生成分析报告"];
    }
}

- (void)showStatisticsReport {
    // 实际的统计报告实现...
    [self showAlertWithTitle:@"功能开发中" message:@"统计报告功能正在开发中"];
}

- (void)showExportOptions {
    // 实际的导出选项实现...
    [self showAlertWithTitle:@"功能开发中" message:@"导出选项功能正在开发中"];
}

// 创建规则界面
- (void)showCreateRuleInterface {
    // 实际的规则创建界面实现...
    [self showAlertWithTitle:@"功能开发中" message:@"规则创建功能正在开发中"];
}

- (void)showRulesList {
    // 实际的规则列表实现...
    [self showAlertWithTitle:@"功能开发中" message:@"规则列表功能正在开发中"];
}

- (void)showAutomationStats {
    // 实际的自动化统计实现...
    [self showAlertWithTitle:@"功能开发中" message:@"自动化统计功能正在开发中"];
}

// 添加地理围栏
- (void)showAddGeofenceInterface {
    // 实际的添加围栏界面实现...
    [self showAlertWithTitle:@"功能开发中" message:@"添加围栏功能正在开发中"];
}

- (void)showGeofencesList {
    // 实际的围栏列表实现...
    [self showAlertWithTitle:@"功能开发中" message:@"围栏列表功能正在开发中"];
}

- (void)showGeofenceEvents {
    // 实际的围栏事件实现...
    [self showAlertWithTitle:@"功能开发中" message:@"围栏事件功能正在开发中"];
}

@end