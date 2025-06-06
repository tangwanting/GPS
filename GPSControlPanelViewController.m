#import "GPSControlPanelViewController.h"
#import <MapKit/MapKit.h>
#import "GPSManager.h"

@interface GPSControlPanelViewController () <MKMapViewDelegate>

@property (nonatomic, strong) UIView *controlPanel;
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *simulateButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UILabel *coordLabel;
@property (nonatomic, strong) UIPanGestureRecognizer *dragGesture;
@property (nonatomic, strong) MKPointAnnotation *pinAnnotation;
@property (nonatomic, assign) CLLocationCoordinate2D selectedCoordinate;

@end

@implementation GPSControlPanelViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor clearColor];
    
    // 创建控制面板容器
    self.controlPanel = [[UIView alloc] initWithFrame:CGRectMake(20, 100, 280, 400)];
    self.controlPanel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.8];
    self.controlPanel.layer.cornerRadius = 16;
    self.controlPanel.clipsToBounds = YES;
    [self.view addSubview:self.controlPanel];
    
    // 添加拖动手势
    self.dragGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleDrag:)];
    [self.controlPanel addGestureRecognizer:self.dragGesture];
    
    // 标题栏
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, 280, 30)];
    titleLabel.text = @"GPS 位置模拟";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    [self.controlPanel addSubview:titleLabel];
    
    // 关闭按钮
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(240, 10, 30, 30);
    [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.closeButton addTarget:self action:@selector(closePanel) forControlEvents:UIControlEventTouchUpInside];
    [self.controlPanel addSubview:self.closeButton];
    
    // 地图视图
    self.mapView = [[MKMapView alloc] initWithFrame:CGRectMake(10, 50, 260, 250)];
    self.mapView.delegate = self;
    [self.controlPanel addSubview:self.mapView];
    
    // 长按手势
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] 
                                               initWithTarget:self 
                                               action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [self.mapView addGestureRecognizer:longPress];
    
    // 坐标标签
    self.coordLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 310, 260, 40)];
    self.coordLabel.textColor = [UIColor whiteColor];
    self.coordLabel.numberOfLines = 2;
    self.coordLabel.textAlignment = NSTextAlignmentCenter;
    self.coordLabel.font = [UIFont systemFontOfSize:12];
    self.coordLabel.text = @"长按地图选择位置";
    [self.controlPanel addSubview:self.coordLabel];
    
    // 模拟按钮
    self.simulateButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.simulateButton.frame = CGRectMake(10, 350, 125, 40);
    self.simulateButton.backgroundColor = [UIColor systemBlueColor];
    self.simulateButton.layer.cornerRadius = 8;
    [self.simulateButton setTitle:@"开始模拟" forState:UIControlStateNormal];
    [self.simulateButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.simulateButton addTarget:self action:@selector(startSimulation) forControlEvents:UIControlEventTouchUpInside];
    [self.controlPanel addSubview:self.simulateButton];
    
    // 停止按钮
    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stopButton.frame = CGRectMake(145, 350, 125, 40);
    self.stopButton.backgroundColor = [UIColor systemRedColor];
    self.stopButton.layer.cornerRadius = 8;
    [self.stopButton setTitle:@"停止模拟" forState:UIControlStateNormal];
    [self.stopButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [self.stopButton addTarget:self action:@selector(stopSimulation) forControlEvents:UIControlEventTouchUpInside];
    [self.controlPanel addSubview:self.stopButton];
    
    // 初始化大头针
    self.pinAnnotation = [[MKPointAnnotation alloc] init];
}

- (void)handleDrag:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.view];
    
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGRect frame = self.controlPanel.frame;
        frame.origin.x += translation.x;
        frame.origin.y += translation.y;
        
        // 保持在屏幕内
        frame.origin.x = MAX(0, MIN(frame.origin.x, self.view.bounds.size.width - frame.size.width));
        frame.origin.y = MAX(20, MIN(frame.origin.y, self.view.bounds.size.height - frame.size.height));
        
        self.controlPanel.frame = frame;
    }
    
    [gesture setTranslation:CGPointZero inView:self.view];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan) {
        return;
    }
    
    // 获取坐标
    CGPoint touchPoint = [gesture locationInView:self.mapView];
    CLLocationCoordinate2D coordinate = [self.mapView convertPoint:touchPoint toCoordinateFromView:self.mapView];
    
    // 更新选中坐标
    self.selectedCoordinate = coordinate;
    
    // 更新标签
    self.coordLabel.text = [NSString stringWithFormat:@"纬度: %.6f\n经度: %.6f", 
                           coordinate.latitude, coordinate.longitude];
    
    // 添加大头针
    [self.mapView removeAnnotation:self.pinAnnotation];
    self.pinAnnotation.coordinate = coordinate;
    self.pinAnnotation.title = @"模拟位置";
    [self.mapView addAnnotation:self.pinAnnotation];
}

- (void)startSimulation {
    if (!CLLocationCoordinate2DIsValid(self.selectedCoordinate)) {
        // 如果没有选择位置，显示提示
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" 
                                                                      message:@"请先长按地图选择位置" 
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // 开始模拟
    [[GPSManager sharedManager] simulateLocation:self.selectedCoordinate];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"位置模拟已启动" 
                                                                 message:@"当前应用中的位置已被修改" 
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)stopSimulation {
    [[GPSManager sharedManager] stopSimulation];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"位置模拟已停止" 
                                                                  message:nil 
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)closePanel {
    [[GPSManager sharedManager] hideGPSControlPanel];
}

@end