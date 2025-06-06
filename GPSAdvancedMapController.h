/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import "GPSLocationModel.h"

typedef NS_ENUM(NSInteger, GPSMapMode) {
    GPSMapModeStandard,
    GPSMapModeSatellite,
    GPSMapModeHybrid,
    GPSMapModeTerrain,
    GPSMapMode3D
};

@protocol GPSMapControlDelegate <NSObject>
- (void)mapDidSelectLocation:(CLLocationCoordinate2D)coordinate;
- (void)mapDidUpdateVisibleRegion:(MKCoordinateRegion)region;
- (void)mapRequiresSearchForQuery:(NSString *)query;
@end

@interface GPSAdvancedMapController : UIViewController

@property (nonatomic, weak) id<GPSMapControlDelegate> delegate;

// 地图视图
@property (nonatomic, strong, readonly) MKMapView *mapView;

// 搜索控制
@property (nonatomic, strong, readonly) UISearchController *searchController;
@property (nonatomic, assign) BOOL searchEnabled;

// 地图设置
@property (nonatomic, assign) GPSMapMode mapMode;
@property (nonatomic, assign) BOOL showTraffic;
@property (nonatomic, assign) BOOL showPointsOfInterest;
@property (nonatomic, assign) BOOL showCompass;
@property (nonatomic, assign) MKUserTrackingMode userTrackingMode;

// 标记管理
- (void)addLocationMarker:(GPSLocationModel *)location;
- (void)removeLocationMarker:(GPSLocationModel *)location;
- (void)clearAllMarkers;
- (void)selectMarker:(GPSLocationModel *)location;

// 路线显示
- (void)showRoute:(NSArray<GPSLocationModel *> *)routePoints;
- (void)showRoute:(NSArray<GPSLocationModel *> *)routePoints withColor:(UIColor *)color;
- (void)clearRoutes;
- (void)updateActiveRouteWithCurrentPosition:(GPSLocationModel *)position;

// 区域和可视化
- (void)setVisibleRegion:(MKCoordinateRegion)region animated:(BOOL)animated;
- (void)setVisibleMapRect:(MKMapRect)mapRect edgePadding:(UIEdgeInsets)padding animated:(BOOL)animated;
- (void)zoomToLocation:(CLLocationCoordinate2D)coordinate withRadius:(CLLocationDistance)radius animated:(BOOL)animated;
- (void)zoomToFitAllMarkers;

// 高级特性
- (void)addHeatMap:(NSArray<CLLocation *> *)points withRadius:(CGFloat)radius;
- (void)addGeofenceOverlay:(CLLocationCoordinate2D)center radius:(CLLocationDistance)radius identifier:(NSString *)identifier;
- (void)addPolygonGeofence:(NSArray<NSValue *> *)coordinates identifier:(NSString *)identifier;
- (void)showElevationProfile:(NSArray<GPSLocationModel *> *)points;

@end