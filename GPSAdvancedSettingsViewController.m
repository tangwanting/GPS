/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import "GPSAdvancedSettingsViewController.h"
#import "GPSLocationViewModel.h"
#import "GPSRouteManager.h"

@interface GPSAdvancedSettingsViewController () <UIDocumentPickerDelegate, UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong, readwrite) NSMutableDictionary *settings;
@property (nonatomic, strong, readwrite) NSArray *sections;
@property (nonatomic, strong, readwrite) UITableView *tableView;
@end

@implementation GPSAdvancedSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"高级设置";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemSave
                                                                                         target:self
                                                                                         action:@selector(saveButtonTapped)];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel
                                                                                        target:self
                                                                                        action:@selector(cancelButtonTapped)];
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
    
    // 初始化设置字典
    self.settings = [NSMutableDictionary dictionary];
    
    [self loadSettings];
}

- (void)loadSettings {
    // 使用视图模型加载设置
    GPSLocationViewModel *viewModel = [GPSLocationViewModel sharedInstance];
    
    // 确保 settings 是可变字典
    if (!self.settings) {
        self.settings = [NSMutableDictionary dictionary];
    }
    
    // 设置字典
    self.settings[@"movingSpeed"] = @(viewModel.movingSpeed);
    self.settings[@"randomRadius"] = @(viewModel.randomRadius);
    self.settings[@"stepDistance"] = @(viewModel.stepDistance);
    self.settings[@"movementMode"] = @(viewModel.movementMode);
    self.settings[@"course"] = @(0.0); // 默认值
    
    // 设置组织
    self.sections = @[
        @"移动设置", 
        @"随机模式设置", 
        @"路线设置", 
        @"其他设置"
    ];
    
    [self.tableView reloadData];
}

- (void)saveButtonTapped {
    // 保存设置到视图模型
    GPSLocationViewModel *viewModel = [GPSLocationViewModel sharedInstance];
    viewModel.movingSpeed = [self.settings[@"movingSpeed"] doubleValue];
    viewModel.randomRadius = [self.settings[@"randomRadius"] doubleValue];
    viewModel.stepDistance = [self.settings[@"stepDistance"] doubleValue];
    viewModel.movementMode = [self.settings[@"movementMode"] intValue];
    
    // 保存设置
    [viewModel saveSettings];
    
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancelButtonTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

// 导入GPX文件
- (void)importGPXFile {
    UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] 
                                                    initWithDocumentTypes:@[@"com.topografix.gpx"] 
                                                    inMode:UIDocumentPickerModeImport];
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = NO;
    [self presentViewController:documentPicker animated:YES completion:nil];
}

// 实现UIDocumentPickerDelegate方法
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *selectedFile = urls.firstObject;
    if (!selectedFile) return;
    
    // 处理GPX文件 - 修改为使用可用的导入方法
    NSString *filePath = [selectedFile path];
    NSError *importError = nil;
    NSArray *routePoints = [[GPSRouteManager sharedInstance] importGPXFromPath:filePath error:&importError];
    
    if (importError || !routePoints) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlertWithTitle:@"导入失败" message:importError.localizedDescription ?: @"未知错误"];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self showAlertWithTitle:@"导入成功" message:[NSString stringWithFormat:@"已成功导入 %lu 个路线点", (unsigned long)routePoints.count]];
        });
    }
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
}

#pragma mark - TableView Delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    // 显示编辑器
    [self showEditorForSettingAtIndexPath:indexPath];
}

- (void)showEditorForSettingAtIndexPath:(NSIndexPath *)indexPath {
    NSString *key;
    NSString *title;
    double currentValue = 0.0;
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            key = @"movingSpeed";
            title = @"设置移动速度";
            currentValue = [self.settings[key] doubleValue];
        } else {
            key = @"stepDistance";
            title = @"设置步进距离";
            currentValue = [self.settings[key] doubleValue];
        }
    } else if (indexPath.section == 1) {
        key = @"randomRadius";
        title = @"设置随机半径";
        currentValue = [self.settings[key] doubleValue];
    } else {
        key = @"course";
        title = @"设置方向角度";
        currentValue = [self.settings[key] doubleValue];
    }
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                  message:nil
                                                           preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.keyboardType = UIKeyboardTypeDecimalPad;
        textField.text = [NSString stringWithFormat:@"%.1f", currentValue];
    }];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textField = alert.textFields.firstObject;
        double newValue = [textField.text doubleValue];
        self.settings[key] = @(newValue);
        [self.tableView reloadData];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消"
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - TableView Data Source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return self.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 2; // 移动设置
    if (section == 1) return 1; // 随机设置
    return 1; // 其他设置
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.sections[section];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier];
    }
    
    // 配置单元格
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"移动速度";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f m/s", [self.settings[@"movingSpeed"] doubleValue]];
        } else {
            cell.textLabel.text = @"步进距离";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f m", [self.settings[@"stepDistance"] doubleValue]];
        }
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @"随机半径";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f m", [self.settings[@"randomRadius"] doubleValue]];
    } else if (indexPath.section == 2) {
        cell.textLabel.text = @"导入GPX文件";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.detailTextLabel.text = @"";
    } else {
        cell.textLabel.text = @"方向角度";
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%.1f°", [self.settings[@"course"] doubleValue]];
    }
    
    return cell;
}

// 添加显示警告的辅助方法
- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"确定"
                                             style:UIAlertActionStyleDefault
                                           handler:nil]];
    
    [self presentViewController:alert animated:YES completion:nil];
}
@end