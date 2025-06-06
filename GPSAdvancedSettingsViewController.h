/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import <UIKit/UIKit.h>

@interface GPSAdvancedSettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic, strong, readonly) UITableView *tableView;
@property (nonatomic, strong, readonly) NSArray *sections;
@property (nonatomic, strong, readonly) NSMutableDictionary *settings;

- (void)loadSettings;
- (void)saveSettings;

@end