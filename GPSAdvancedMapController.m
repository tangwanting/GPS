/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSAdvancedMapController.h"
#import "GPSLocationModel.h"

// 自定义注释和覆盖物类
@interface GPSLocationAnnotation : MKPointAnnotation
@property (nonatomic, strong) GPSLocationModel *locationModel;
@end

@implementation GPSLocationAnnotation
@end

@interface GPSHeatmapOverlay : NSObject <MKOverlay>
@property (nonatomic, assign) CLLocationCoordinate2D coordinate;
@property (nonatomic, assign) MKMapRect boundingMapRect;
@property (nonatomic, strong) NSArray<CLLocation *> *points;
@property (nonatomic, assign) CGFloat radius;
@end

@implementation GPSHeatmapOverlay
- (instancetype)initWithPoints:(NSArray<CLLocation *> *)points radius:(CGFloat)radius {
    if (self = [super init]) {
        _points = points;
        _radius = radius;
        
        // 计算边界矩形和中心点
        if (points.count > 0) {
            MKMapPoint northEast = MKMapPointForCoordinate(CLLocationCoordinate2DMake(-90, -180));
            MKMapPoint southWest = MKMapPointForCoordinate(CLLocationCoordinate2DMake(90, 180));
            
            double totalLat = 0;
            double totalLon = 0;
            
            for (CLLocation *location in points) {
                CLLocationCoordinate2D coord = location.coordinate;
                MKMapPoint point = MKMapPointForCoordinate(coord);
                
                northEast.x = MAX(northEast.x, point.x);
                northEast.y = MAX(northEast.y, point.y);
                southWest.x = MIN(southWest.x, point.x);
                southWest.y = MIN(southWest.y, point.y);
                
                totalLat += coord.latitude;
                totalLon += coord.longitude;
            }
            
            // 确保边界矩形包含半径
            double paddingDistance = radius * 2;
            double mapPointPadding = paddingDistance / MKMapPointsPerMeterAtLatitude(points[0].coordinate.latitude);
            
            _boundingMapRect = MKMapRectMake(southWest.x - mapPointPadding,
                                            southWest.y - mapPointPadding,
                                            (northEast.x - southWest.x) + mapPointPadding * 2,
                                            (northEast.y - southWest.y) + mapPointPadding * 2);
            
            // 计算中心点
            _coordinate = CLLocationCoordinate2DMake(totalLat / points.count, totalLon / points.count);
        } else {
            _boundingMapRect = MKMapRectNull;
            _coordinate = CLLocationCoordinate2DMake(0, 0);
        }
    }
    return self;
}
@end

@interface GPSHeatmapRenderer : MKOverlayRenderer
@property (nonatomic, strong) GPSHeatmapOverlay *heatmapOverlay;
@end

@implementation GPSHeatmapRenderer
- (instancetype)initWithOverlay:(id<MKOverlay>)overlay {
    if (self = [super initWithOverlay:overlay]) {
        if ([overlay isKindOfClass:[GPSHeatmapOverlay class]]) {
            _heatmapOverlay = (GPSHeatmapOverlay *)overlay;
        }
    }
    return self;
}

- (void)drawMapRect:(MKMapRect)mapRect zoomScale:(MKZoomScale)zoomScale inContext:(CGContextRef)context {
    if (!self.heatmapOverlay.points.count) return;
    
    CGRect rect = [self rectForMapRect:mapRect];
    
    // 创建热图绘制上下文
    UIGraphicsBeginImageContextWithOptions(rect.size, NO, 0.0);
    CGContextRef heatmapContext = UIGraphicsGetCurrentContext();
    
    // 初始背景透明
    CGContextClearRect(heatmapContext, CGRectMake(0, 0, rect.size.width, rect.size.height));
    
    // 绘制热度点
    for (CLLocation *location in self.heatmapOverlay.points) {
        MKMapPoint point = MKMapPointForCoordinate(location.coordinate);
        CGPoint cgPoint = [self pointForMapPoint:point];
        
        // 转换到当前mapRect的坐标系
        cgPoint.x -= rect.origin.x;
        cgPoint.y -= rect.origin.y;
        
        // 绘制热度点
        CGFloat radius = self.heatmapOverlay.radius / zoomScale;
        
        // 创建径向渐变
        CGFloat locations[] = {0.0, 0.5, 1.0};
        CGFloat colors[] = {
            1.0, 0.0, 0.0, 0.8,  // 红色中心，高透明度
            1.0, 0.5, 0.0, 0.4,  // 橙色中间，中等透明度
            0.0, 0.0, 1.0, 0.0   // 蓝色边缘，完全透明
        };
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
        CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, locations, 3);
        
        CGContextDrawRadialGradient(heatmapContext, gradient, cgPoint, 0, cgPoint, radius, kCGGradientDrawsBeforeStartLocation);
        
        CGGradientRelease(gradient);
        CGColorSpaceRelease(colorSpace);
    }
    
    UIImage *heatmapImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    // 将热图绘制到地图上下文
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, rect.origin.x, rect.origin.y);
    CGContextScaleCTM(context, 1.0, 1.0);
    CGContextDrawImage(context, CGRectMake(0, 0, rect.size.width, rect.size.height), heatmapImage.CGImage);
    CGContextRestoreGState(context);
}
@end

// 路线覆盖物类型
@interface GPSRouteOverlay : MKPolyline
@property (nonatomic, strong) UIColor *routeColor;
@end

@implementation GPSRouteOverlay
@end

@interface GPSAdvancedMapController () <MKMapViewDelegate, UISearchBarDelegate, UISearchResultsUpdating>

// 私有属性
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) NSMutableArray<GPSLocationAnnotation *> *locationAnnotations;
@property (nonatomic, strong) NSMutableArray<GPSRouteOverlay *> *routes;
@property (nonatomic, strong) NSMutableArray<MKCircle *> *geofenceCircles;
@property (nonatomic, strong) NSMutableArray<MKPolygon *> *geofencePolygons;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *geofenceIdentifiers;

@end

@implementation GPSAdvancedMapController

#pragma mark - 生命周期方法

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 初始化数据结构
    _locationAnnotations = [NSMutableArray array];
    _routes = [NSMutableArray array];
    _geofenceCircles = [NSMutableArray array];
    _geofencePolygons = [NSMutableArray array];
    _geofenceIdentifiers = [NSMutableDictionary dictionary];
    
    // 设置地图视图
    [self setupMapView];
    
    // 设置搜索控制器
    [self setupSearchController];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // 确保导航栏配置正确
    if (self.searchEnabled) {
        self.navigationItem.searchController = self.searchController;
    }
}

#pragma mark - 初始化和设置方法

- (void)setupMapView {
    _mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    _mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _mapView.delegate = self;
    _mapView.showsUserLocation = YES;
    
    // 设置默认值
    _mapMode = GPSMapModeStandard;
    _showTraffic = NO;
    _showPointsOfInterest = YES;
    _showCompass = YES;
    _userTrackingMode = MKUserTrackingModeNone;
    
    // 应用默认设置
    [self updateMapViewSettings];
    
    [self.view addSubview:_mapView];
}

- (void)setupSearchController {
    _searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater = self;
    _searchController.obscuresBackgroundDuringPresentation = NO;
    _searchController.searchBar.delegate = self;
    _searchController.searchBar.placeholder = @"搜索地点...";
    
    // iOS 11+
    if (@available(iOS 11.0, *)) {
        self.navigationItem.searchController = _searchController;
        self.navigationItem.hidesSearchBarWhenScrolling = NO;
    } else {
        // iOS 10及更早版本
        self.navigationItem.titleView = _searchController.searchBar;
    }
    
    // 默认不启用搜索
    _searchEnabled = NO;
}

- (void)updateMapViewSettings {
    // 更新地图类型
    switch (_mapMode) {
        case GPSMapModeStandard:
            _mapView.mapType = MKMapTypeStandard;
            break;
        case GPSMapModeSatellite:
            _mapView.mapType = MKMapTypeSatellite;
            break;
        case GPSMapModeHybrid:
            _mapView.mapType = MKMapTypeHybrid;
            break;
        case GPSMapModeTerrain:
            if (@available(iOS 11.0, *)) {
                _mapView.mapType = MKMapTypeMutedStandard;
            } else {
                _mapView.mapType = MKMapTypeStandard;
            }
            break;
        case GPSMapMode3D:
            _mapView.mapType = MKMapTypeStandard;
            // 设置3D效果（通过摄像头角度）
            MKMapCamera *camera = [_mapView.camera copy];
            camera.pitch = 45.0; // 45度角俯视
            [_mapView setCamera:camera animated:YES];
            break;
    }
    
    // 更新交通显示
    _mapView.showsTraffic = _showTraffic;
    
    // 更新指南针显示
    _mapView.showsCompass = _showCompass;
    
    // 更新用户跟踪模式
    _mapView.userTrackingMode = _userTrackingMode;
    
    // 更新兴趣点显示（仅在标准和混合地图模式下可用）
    if (_mapView.mapType == MKMapTypeStandard || _mapView.mapType == MKMapTypeHybrid) {
        _mapView.pointOfInterestFilter = _showPointsOfInterest ? nil : [MKPointOfInterestFilter filterIncludingAllCategories];
    }
}

#pragma mark - 属性设置器

- (void)setMapMode:(GPSMapMode)mapMode {
    if (_mapMode != mapMode) {
        _mapMode = mapMode;
        [self updateMapViewSettings];
    }
}

- (void)setShowTraffic:(BOOL)showTraffic {
    if (_showTraffic != showTraffic) {
        _showTraffic = showTraffic;
        _mapView.showsTraffic = showTraffic;
    }
}

- (void)setShowPointsOfInterest:(BOOL)showPointsOfInterest {
    if (_showPointsOfInterest != showPointsOfInterest) {
        _showPointsOfInterest = showPointsOfInterest;
        [self updateMapViewSettings];
    }
}

- (void)setShowCompass:(BOOL)showCompass {
    if (_showCompass != showCompass) {
        _showCompass = showCompass;
        _mapView.showsCompass = showCompass;
    }
}

- (void)setUserTrackingMode:(MKUserTrackingMode)userTrackingMode {
    if (_userTrackingMode != userTrackingMode) {
        _userTrackingMode = userTrackingMode;
        [_mapView setUserTrackingMode:userTrackingMode animated:YES];
    }
}

- (void)setSearchEnabled:(BOOL)searchEnabled {
    if (_searchEnabled != searchEnabled) {
        _searchEnabled = searchEnabled;
        
        if (@available(iOS 11.0, *)) {
            self.navigationItem.searchController = searchEnabled ? self.searchController : nil;
        } else {
            self.navigationItem.titleView = searchEnabled ? self.searchController.searchBar : nil;
        }
    }
}

#pragma mark - 标记管理

- (void)addLocationMarker:(GPSLocationModel *)location {
    // 检查是否已存在该位置的标记
    for (GPSLocationAnnotation *annotation in self.locationAnnotations) {
        if ([annotation.locationModel isEqual:location]) {
            return; // 已存在，不重复添加
        }
    }
    
    // 创建新注释
    GPSLocationAnnotation *annotation = [[GPSLocationAnnotation alloc] init];
    annotation.coordinate = CLLocationCoordinate2DMake(location.latitude, location.longitude);
    annotation.title = location.title ?: @"位置标记";
    annotation.subtitle = [NSString stringWithFormat:@"%.6f, %.6f", location.latitude, location.longitude];
    annotation.locationModel = location;
    
    // 添加到地图和数组
    [self.locationAnnotations addObject:annotation];
    [self.mapView addAnnotation:annotation];
}

- (void)removeLocationMarker:(GPSLocationModel *)location {
    NSMutableArray *annotationsToRemove = [NSMutableArray array];
    
    // 查找匹配的标记
    for (GPSLocationAnnotation *annotation in self.locationAnnotations) {
        if ([annotation.locationModel isEqual:location]) {
            [annotationsToRemove addObject:annotation];
        }
    }
    
    // 移除找到的标记
    [self.mapView removeAnnotations:annotationsToRemove];
    [self.locationAnnotations removeObjectsInArray:annotationsToRemove];
}

- (void)clearAllMarkers {
    [self.mapView removeAnnotations:self.locationAnnotations];
    [self.locationAnnotations removeAllObjects];
}

- (void)selectMarker:(GPSLocationModel *)location {
    for (GPSLocationAnnotation *annotation in self.locationAnnotations) {
        if ([annotation.locationModel isEqual:location]) {
            [self.mapView selectAnnotation:annotation animated:YES];
            break;
        }
    }
}

#pragma mark - 路线显示

- (void)showRoute:(NSArray<GPSLocationModel *> *)routePoints {
    [self showRoute:routePoints withColor:[UIColor blueColor]];
}

- (void)showRoute:(NSArray<GPSLocationModel *> *)routePoints withColor:(UIColor *)color {
    if (routePoints.count < 2) return;
    
    // 创建坐标点数组
    CLLocationCoordinate2D coordinates[routePoints.count];
    for (NSInteger i = 0; i < routePoints.count; i++) {
        GPSLocationModel *location = routePoints[i];
        coordinates[i] = CLLocationCoordinate2DMake(location.latitude, location.longitude);
    }
    
    // 创建路线
    GPSRouteOverlay *routeOverlay = [GPSRouteOverlay polylineWithCoordinates:coordinates count:routePoints.count];
    routeOverlay.routeColor = color;
    
    [self.routes addObject:routeOverlay];
    [self.mapView addOverlay:routeOverlay];
    
    // 可选：自动缩放以显示整条路线
    [self zoomToShowRoute:routeOverlay];
}

- (void)zoomToShowRoute:(MKPolyline *)route {
    [self.mapView setVisibleMapRect:[route boundingMapRect] edgePadding:UIEdgeInsetsMake(50, 50, 50, 50) animated:YES];
}

- (void)clearRoutes {
    for (GPSRouteOverlay *route in self.routes) {
        [self.mapView removeOverlay:route];
    }
    [self.routes removeAllObjects];
}

- (void)updateActiveRouteWithCurrentPosition:(GPSLocationModel *)position {
    // 这个方法用于更新当前活动路线，例如突出显示已经行驶的部分
    // 实现策略：移除旧路线，然后绘制两条新路线 - 已行驶部分（高亮）和未行驶部分
    
    // 这里简化实现为，如果有至少一条路线，更新其起点为当前位置
    if (self.routes.count > 0) {
        GPSRouteOverlay *currentRoute = [self.routes firstObject];
        [self.mapView removeOverlay:currentRoute];
        
        // 获取路线的坐标点
        MKPolyline *polyline = currentRoute;
        NSUInteger pointCount = polyline.pointCount;
        
        if (pointCount > 1) {
            // 创建包含当前位置的新路线
            CLLocationCoordinate2D *routeCoordinates = malloc(sizeof(CLLocationCoordinate2D) * pointCount);
            [polyline getCoordinates:routeCoordinates range:NSMakeRange(0, pointCount)];
            
            // 更新第一个点为当前位置
            routeCoordinates[0] = CLLocationCoordinate2DMake(position.latitude, position.longitude);
            
            // 创建新路线
            GPSRouteOverlay *updatedRoute = [GPSRouteOverlay polylineWithCoordinates:routeCoordinates count:pointCount];
            updatedRoute.routeColor = currentRoute.routeColor;
            
            // 替换旧路线
            [self.routes replaceObjectAtIndex:0 withObject:updatedRoute];
            [self.mapView addOverlay:updatedRoute];
            
            // 释放内存
            free(routeCoordinates);
        }
    }
}

#pragma mark - 区域和可视化控制

- (void)setVisibleRegion:(MKCoordinateRegion)region animated:(BOOL)animated {
    [self.mapView setRegion:region animated:animated];
}

- (void)setVisibleMapRect:(MKMapRect)mapRect edgePadding:(UIEdgeInsets)padding animated:(BOOL)animated {
    [self.mapView setVisibleMapRect:mapRect edgePadding:padding animated:animated];
}

- (void)zoomToLocation:(CLLocationCoordinate2D)coordinate withRadius:(CLLocationDistance)radius animated:(BOOL)animated {
    MKCoordinateRegion region = MKCoordinateRegionMakeWithDistance(coordinate, radius * 2, radius * 2);
    [self.mapView setRegion:region animated:animated];
}

- (void)zoomToFitAllMarkers {
    if (self.locationAnnotations.count == 0) return;
    
    // 正确初始化边界坐标
    CLLocationCoordinate2D topLeftCoord = CLLocationCoordinate2DMake(90, -180);
    CLLocationCoordinate2D bottomRightCoord = CLLocationCoordinate2DMake(-90, 180);
    
    // 计算所有标记的包围盒
    for (GPSLocationAnnotation *annotation in self.locationAnnotations) {
        topLeftCoord.latitude = fmin(topLeftCoord.latitude, annotation.coordinate.latitude);
        topLeftCoord.longitude = fmax(topLeftCoord.longitude, annotation.coordinate.longitude);
        bottomRightCoord.latitude = fmax(bottomRightCoord.latitude, annotation.coordinate.latitude);
        bottomRightCoord.longitude = fmin(bottomRightCoord.longitude, annotation.coordinate.longitude);
    }
    
    // 创建矩形区域
    MKCoordinateRegion region;
    region.center.latitude = (topLeftCoord.latitude + bottomRightCoord.latitude) * 0.5;
    region.center.longitude = (topLeftCoord.longitude + bottomRightCoord.longitude) * 0.5;
    region.span.latitudeDelta = fabs(bottomRightCoord.latitude - topLeftCoord.latitude) * 1.2; // 添加边距
    region.span.longitudeDelta = fabs(bottomRightCoord.longitude - topLeftCoord.longitude) * 1.2;
    
    // 设置地图区域
    [self.mapView setRegion:region animated:YES];
}

#pragma mark - 高级特性

- (void)addHeatMap:(NSArray<CLLocation *> *)points withRadius:(CGFloat)radius {
    // 创建热图覆盖物
    GPSHeatmapOverlay *heatmapOverlay = [[GPSHeatmapOverlay alloc] initWithPoints:points radius:radius];
    [self.mapView addOverlay:heatmapOverlay level:MKOverlayLevelAboveLabels];
    
    // 缩放到显示整个热图
    [self.mapView setVisibleMapRect:heatmapOverlay.boundingMapRect animated:YES];
}

- (void)addGeofenceOverlay:(CLLocationCoordinate2D)center radius:(CLLocationDistance)radius identifier:(NSString *)identifier {
    // 创建圆形地理围栏
    MKCircle *circle = [MKCircle circleWithCenterCoordinate:center radius:radius];
    
    // 保存标识符
    if (identifier) {
        self.geofenceIdentifiers[@([circle hash])] = identifier;
    }
    
    [self.geofenceCircles addObject:circle];
    [self.mapView addOverlay:circle];
}

- (void)addPolygonGeofence:(NSArray<NSValue *> *)coordinates identifier:(NSString *)identifier {
    if (coordinates.count < 3) return;
    
    // 创建坐标数组
    CLLocationCoordinate2D coords[coordinates.count];
    for (NSInteger i = 0; i < coordinates.count; i++) {
        // 从NSValue中获取CLLocationCoordinate2D结构体
        coords[i] = [coordinates[i] MKCoordinateValue];
    }
    
    // 创建多边形地理围栏
    MKPolygon *polygon = [MKPolygon polygonWithCoordinates:coords count:coordinates.count];
    
    // 保存标识符
    if (identifier) {
        self.geofenceIdentifiers[@([polygon hash])] = identifier;
    }
    
    [self.geofencePolygons addObject:polygon];
    [self.mapView addOverlay:polygon];
}

- (void)showElevationProfile:(NSArray<GPSLocationModel *> *)points {
    if (points.count < 2) return;
    
    // 从点提取海拔数据
    NSMutableArray *elevations = [NSMutableArray array];
    double minElevation = MAXFLOAT;
    double maxElevation = -MAXFLOAT;
    
    for (GPSLocationModel *point in points) {
        [elevations addObject:@(point.altitude)];
        minElevation = MIN(minElevation, point.altitude);
        maxElevation = MAX(maxElevation, point.altitude);
    }
    
    // 创建简单的高程视图
    UIView *profileView = [[UIView alloc] initWithFrame:CGRectMake(20, 20, 280, 120)];
    profileView.backgroundColor = [UIColor whiteColor];
    profileView.layer.cornerRadius = 8.0;
    profileView.layer.shadowColor = [UIColor blackColor].CGColor;
    profileView.layer.shadowOffset = CGSizeMake(0, 2);
    profileView.layer.shadowOpacity = 0.3;
    
    // 添加标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 5, 260, 20)];
    titleLabel.text = [NSString stringWithFormat:@"高程: %.1f - %.1f米", minElevation, maxElevation];
    titleLabel.font = [UIFont systemFontOfSize:12];
    [profileView addSubview:titleLabel];
    
    // 将视图添加到地图的叠加层
    [self.mapView addSubview:profileView];
}

#pragma mark - MKMapViewDelegate

- (void)mapView:(MKMapView *)mapView didSelectAnnotationView:(MKAnnotationView *)view {
    if ([view.annotation isKindOfClass:[GPSLocationAnnotation class]]) {
        GPSLocationAnnotation *annotation = (GPSLocationAnnotation *)view.annotation;
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(mapDidSelectLocation:)]) {
            [self.delegate mapDidSelectLocation:annotation.coordinate];
        }
    }
}

- (void)mapView:(MKMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    if (self.delegate && [self.delegate respondsToSelector:@selector(mapDidUpdateVisibleRegion:)]) {
        [self.delegate mapDidUpdateVisibleRegion:mapView.region];
    }
}

- (MKAnnotationView *)mapView:(MKMapView *)mapView viewForAnnotation:(id<MKAnnotation>)annotation {
    // 不要为用户位置自定义注释视图
    if ([annotation isKindOfClass:[MKUserLocation class]]) {
        return nil;
    }
    
    if ([annotation isKindOfClass:[GPSLocationAnnotation class]]) {
        GPSLocationAnnotation *locationAnnotation = (GPSLocationAnnotation *)annotation;
        static NSString *identifier = @"GPSLocationPin";
        
        MKMarkerAnnotationView *markerView = (MKMarkerAnnotationView *)[mapView dequeueReusableAnnotationViewWithIdentifier:identifier];
        if (!markerView) {
            markerView = [[MKMarkerAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:identifier];
            markerView.canShowCallout = YES;
            markerView.rightCalloutAccessoryView = [UIButton buttonWithType:UIButtonTypeDetailDisclosure];
        }
        
        // 可以根据位置模型的属性自定义注释样式
        markerView.markerTintColor = [UIColor blueColor]; // 默认为蓝色
        markerView.glyphImage = [UIImage systemImageNamed:@"mappin"];
        
        return markerView;
    }
    
    return nil;
}

- (MKOverlayRenderer *)mapView:(MKMapView *)mapView rendererForOverlay:(id<MKOverlay>)overlay {
    // 路线渲染
    if ([overlay isKindOfClass:[GPSRouteOverlay class]]) {
        GPSRouteOverlay *routeOverlay = (GPSRouteOverlay *)overlay;
        MKPolylineRenderer *renderer = [[MKPolylineRenderer alloc] initWithPolyline:routeOverlay];
        renderer.strokeColor = routeOverlay.routeColor ?: [UIColor blueColor];
        renderer.lineWidth = 4.0;
        return renderer;
    }
    
    // 热图渲染
    if ([overlay isKindOfClass:[GPSHeatmapOverlay class]]) {
        GPSHeatmapOverlay *heatmapOverlay = (GPSHeatmapOverlay *)overlay;
        GPSHeatmapRenderer *renderer = [[GPSHeatmapRenderer alloc] initWithOverlay:heatmapOverlay];
        return renderer;
    }
    
    // 圆形地理围栏渲染
    if ([overlay isKindOfClass:[MKCircle class]]) {
        MKCircleRenderer *renderer = [[MKCircleRenderer alloc] initWithCircle:(MKCircle *)overlay];
        renderer.strokeColor = [UIColor redColor];
        renderer.fillColor = [[UIColor redColor] colorWithAlphaComponent:0.2];
        renderer.lineWidth = 2.0;
        return renderer;
    }
    
    // 多边形地理围栏渲染
    if ([overlay isKindOfClass:[MKPolygon class]]) {
        MKPolygonRenderer *renderer = [[MKPolygonRenderer alloc] initWithPolygon:(MKPolygon *)overlay];
        renderer.strokeColor = [UIColor purpleColor];
        renderer.fillColor = [[UIColor purpleColor] colorWithAlphaComponent:0.2];
        renderer.lineWidth = 2.0;
        return renderer;
    }
    
    return nil;
}

- (void)mapView:(MKMapView *)mapView annotationView:(MKAnnotationView *)view calloutAccessoryControlTapped:(UIControl *)control {
    if ([view.annotation isKindOfClass:[GPSLocationAnnotation class]]) {
        GPSLocationAnnotation *annotation = (GPSLocationAnnotation *)view.annotation;
        NSLog(@"详细信息按钮被点击：%@", annotation.title);
        
        // 创建详细信息视图
        UIViewController *detailVC = [[UIViewController alloc] init];
        detailVC.title = annotation.title;
        detailVC.view.backgroundColor = [UIColor whiteColor];
        
        // 添加位置信息标签
        UILabel *locationLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, detailVC.view.bounds.size.width - 40, 30)];
        locationLabel.text = [NSString stringWithFormat:@"坐标: %.6f, %.6f", 
                             annotation.coordinate.latitude, annotation.coordinate.longitude];
        locationLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [detailVC.view addSubview:locationLabel];
        
        // 如果有额外信息，添加到详细视图
        UILabel *infoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 60, detailVC.view.bounds.size.width - 40, 100)];
        infoLabel.numberOfLines = 0;
        infoLabel.text = [NSString stringWithFormat:@"%@\n%@", 
                         annotation.subtitle ?: @"",
                         annotation.locationModel.description ?: @""];
        infoLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [detailVC.view addSubview:infoLabel];
        
        // 显示详细视图
        [self.navigationController pushViewController:detailVC animated:YES];
        
        // 通知代理
        if (self.delegate && [self.delegate respondsToSelector:@selector(mapDidShowDetailForLocation:)]) {
            [self.delegate performSelector:@selector(mapDidShowDetailForLocation:) 
                    withObject:annotation.locationModel];
        }
    }
}

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    
    NSString *searchText = searchBar.text;
    if (searchText.length > 0) {
        // 通知代理执行搜索
        if (self.delegate && [self.delegate respondsToSelector:@selector(mapRequiresSearchForQuery:)]) {
            [self.delegate mapRequiresSearchForQuery:searchText];
        } else {
            // 如果没有代理处理，可以在这里直接执行搜索
            [self performLocalSearch:searchText];
        }
    }
}

#pragma mark - UISearchResultsUpdating

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    // 可以在这里实现搜索结果的实时更新
    // 例如，显示搜索建议
}

#pragma mark - 辅助方法

- (void)performLocalSearch:(NSString *)query {
    MKLocalSearchRequest *request = [[MKLocalSearchRequest alloc] init];
    request.naturalLanguageQuery = query;
    request.region = self.mapView.region;
    
    MKLocalSearch *search = [[MKLocalSearch alloc] initWithRequest:request];
    [search startWithCompletionHandler:^(MKLocalSearchResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            NSLog(@"搜索错误：%@", error.localizedDescription);
            return;
        }
        
        if (response.mapItems.count > 0) {
            // 清除之前的搜索结果标记
            NSMutableArray *searchResultAnnotations = [NSMutableArray array];
            for (id<MKAnnotation> annotation in self.mapView.annotations) {
                if ([annotation isKindOfClass:[MKPointAnnotation class]] && ![annotation isKindOfClass:[MKUserLocation class]]) {
                    [searchResultAnnotations addObject:annotation];
                }
            }
            [self.mapView removeAnnotations:searchResultAnnotations];
            
            // 添加新的搜索结果标记
            NSMutableArray *newAnnotations = [NSMutableArray array];
            for (MKMapItem *item in response.mapItems) {
                MKPointAnnotation *annotation = [[MKPointAnnotation alloc] init];
                annotation.coordinate = item.placemark.coordinate;
                annotation.title = item.name;
                annotation.subtitle = item.placemark.title;
                [newAnnotations addObject:annotation];
            }
            
            [self.mapView addAnnotations:newAnnotations];
            
            // 调整地图视图以显示所有搜索结果
            if (newAnnotations.count > 0) {
                [self zoomToShowAnnotations:newAnnotations];
            }
        }
    }];
}

- (void)zoomToShowAnnotations:(NSArray<id<MKAnnotation>> *)annotations {
    if (annotations.count == 0) return;
    
    MKMapRect zoomRect = MKMapRectNull;
    
    for (id<MKAnnotation> annotation in annotations) {
        MKMapPoint annotationPoint = MKMapPointForCoordinate(annotation.coordinate);
        MKMapRect pointRect = MKMapRectMake(annotationPoint.x, annotationPoint.y, 0.1, 0.1);
        zoomRect = MKMapRectUnion(zoomRect, pointRect);
    }
    
    // 添加一些边距
    zoomRect = [self mapRectByAddingEdgePadding:UIEdgeInsetsMake(50, 50, 50, 50) toRect:zoomRect];
    
    [self.mapView setVisibleMapRect:zoomRect animated:YES];
}

- (MKMapRect)mapRectByAddingEdgePadding:(UIEdgeInsets)padding toRect:(MKMapRect)rect {
    // 计算四个角的坐标点
    CGPoint nePointView = CGPointMake(self.mapView.bounds.size.width - padding.right, padding.top);
    CGPoint swPointView = CGPointMake(padding.left, self.mapView.bounds.size.height - padding.bottom);
    
    // 将视图点转换为地图坐标
    CLLocationCoordinate2D neCoord = [self.mapView convertPoint:nePointView toCoordinateFromView:self.mapView];
    CLLocationCoordinate2D swCoord = [self.mapView convertPoint:swPointView toCoordinateFromView:self.mapView];
    
    // 转换为地图点
    MKMapPoint neMapPoint = MKMapPointForCoordinate(neCoord);
    MKMapPoint swMapPoint = MKMapPointForCoordinate(swCoord);
    
    // 计算缩放比例
    double widthRatio = (double)(self.mapView.bounds.size.width) / (neMapPoint.x - swMapPoint.x);
    double heightRatio = (double)(self.mapView.bounds.size.height) / (swMapPoint.y - neMapPoint.y);
    
    // 应用缩放
    MKMapRect result = rect;
    result.size.width *= widthRatio;
    result.size.height *= heightRatio;
    result.origin.x -= (result.size.width - rect.size.width) / 2;
    result.origin.y -= (result.size.height - rect.size.height) / 2;
    
    return result;
}

@end