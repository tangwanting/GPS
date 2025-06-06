#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>
#import <UIKit/UIKit.h>

@class GPSControlPanelViewController;

NS_ASSUME_NONNULL_BEGIN

@interface GPSManager : NSObject

@property (nonatomic, strong) UIWindow *overlayWindow;
@property (nonatomic, strong) GPSControlPanelViewController *controlPanel;
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *simulatedLocation;
@property (nonatomic, assign) BOOL isSimulating;

+ (instancetype)sharedManager;
- (void)setup;
- (void)showGPSControlPanel;
- (void)hideGPSControlPanel;
- (BOOL)isVisible;
- (void)simulateLocation:(CLLocationCoordinate2D)coordinate;
- (void)stopSimulation;

@end

NS_ASSUME_NONNULL_END