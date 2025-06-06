/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import "GPSLocationModel.h"

@interface GPSDashboardMetric : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic, copy) NSString *iconName;
@property (nonatomic, strong) UIColor *color;
@property (nonatomic, assign) BOOL isWarning;
@property (nonatomic, copy) NSString *trendDirection; // up, down, stable
@end

@protocol GPSDashboardDelegate <NSObject>
- (void)dashboardDidRequestLocationChange:(GPSLocationModel *)newLocation;
- (void)dashboardDidRequestRouteStart;
- (void)dashboardDidRequestRoutePause;
- (void)dashboardDidRequestRouteStop;
@end

@interface GPSDashboardViewController : UIViewController

@property (nonatomic, weak) id<GPSDashboardDelegate> delegate;

// 数据绑定
- (void)updateWithLocationData:(GPSLocationModel *)location;
- (void)updateWithSystemStatus:(NSDictionary *)statusInfo;
- (void)updateWithRouteProgress:(double)progress remainingDistance:(double)distance estimatedTime:(NSTimeInterval)time;

// 自定义指标
- (void)addMetric:(GPSDashboardMetric *)metric;
- (void)updateMetric:(NSString *)metricName withValue:(NSString *)value;
- (void)removeMetric:(NSString *)metricName;
- (void)clearAllMetrics;

// 显示配置
@property (nonatomic, assign) BOOL compactMode;
@property (nonatomic, assign) BOOL darkMode;
@property (nonatomic, assign) BOOL showSpeedometer;
@property (nonatomic, assign) BOOL showAltimeter;
@property (nonatomic, assign) BOOL showCompass;
@property (nonatomic, assign) BOOL showCoordinates;
@property (nonatomic, assign) BOOL showRouteProgress;

// 导出和分享
- (void)exportCurrentDataAsCSV:(void (^)(NSURL *fileURL, NSError *error))completion;
- (void)captureScreenshot:(void (^)(UIImage *image, NSError *error))completion;

@end