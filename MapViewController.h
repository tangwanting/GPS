/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import <UIKit/UIKit.h>
#import <MapKit/MapKit.h>
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>
#import "GPSAdvancedSettingsViewController.h"
#import "GPSRouteManager.h"
#import "GPSLocationModel.h"
#import "GPSCoordinateUtils.h"
#import "GPSLocationViewModel.h"

@protocol MapViewControllerDelegate <NSObject>
- (void)didSelectLocationWithLatitude:(double)latitude longitude:(double)longitude;
@end

@interface MapViewController : UIViewController
@property (nonatomic, weak) id<MapViewControllerDelegate> delegate;
@property (nonatomic, strong, readonly) UILabel *locationLabel;

@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UIView *statusIndicator;

@end