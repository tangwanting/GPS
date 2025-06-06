/*
 * GPS++ 2.0
 * 有问题 联系pxx917144686
 */

#import "GPSExtensions.h"
#import "GPSSystemIntegration.h" 
#import <CoreLocation/CoreLocation.h>

@implementation GPSElevationService

+ (instancetype)sharedInstance {
    static GPSElevationService *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (void)getElevationForLocation:(CLLocationCoordinate2D)coordinate completion:(void(^)(double elevation, NSError *error))completion {
    // 验证坐标有效性
    if (!CLLocationCoordinate2DIsValid(coordinate)) {
        NSError *error = [NSError errorWithDomain:@"GPSElevationServiceErrorDomain" 
                                             code:1001 
                                         userInfo:@{NSLocalizedDescriptionKey: @"无效的坐标"}];
        if (completion) completion(0, error);
        return;
    }
    
    // 检查缓存
    static NSMutableDictionary<NSString *, NSNumber *> *elevationCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        elevationCache = [NSMutableDictionary dictionary];
    });
    
    NSString *cacheKey = [NSString stringWithFormat:@"%.6f,%.6f", coordinate.latitude, coordinate.longitude];
    NSNumber *cachedElevation = elevationCache[cacheKey];
    
    if (cachedElevation) {
        if (completion) completion(cachedElevation.doubleValue, nil);
        return;
    }
    
    // 使用高德地图API获取海拔数据
    NSString *apiKey = @"YOUR_AMAP_API_KEY"; // 需要替换为实际的高德API密钥
    NSString *urlString = [NSString stringWithFormat:@"https://restapi.amap.com/v3/geocode/regeo?key=%@&location=%.6f,%.6f&extensions=all", 
                           apiKey, coordinate.longitude, coordinate.latitude]; // 高德API使用经度在前，纬度在后
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 3.0; // 设置较短的超时时间
    
    // 使用同步请求以保持原函数结构
    NSError *requestError = nil;
    NSHTTPURLResponse *response = nil;
    NSData *data = [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:&requestError];
    
    if (data && !requestError && response.statusCode == 200) {
        NSError *jsonError = nil;
        NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        
        if (!jsonError && [jsonResponse[@"status"] isEqualToString:@"1"]) {
            // 从API结果中提取海拔（注意：需根据实际API返回结构调整）
            NSNumber *elevationValue = nil;
            
            if (jsonResponse[@"regeocode"] && 
                jsonResponse[@"regeocode"][@"addressComponent"] &&
                jsonResponse[@"regeocode"][@"addressComponent"][@"elevation"]) {
                
                elevationValue = jsonResponse[@"regeocode"][@"addressComponent"][@"elevation"];
                
                // 存入缓存并返回结果
                elevationCache[cacheKey] = elevationValue;
                if (completion) {
                    completion(elevationValue.doubleValue, nil);
                }
                return; // 成功获取海拔数据，提前返回
            }
        }
    }
    
    // 如果API调用失败或没有返回海拔数据，将继续执行下面的模拟逻辑
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        double baseElevation = 0;
        
        // 根据纬度估算基础海拔（粗略模拟不同地理区域的海拔特性）
        if (coordinate.latitude > 60 || coordinate.latitude < -60) {
            // 极地地区
            baseElevation = 500 + arc4random_uniform(1500);
        } else if (coordinate.latitude > 23 && coordinate.latitude < 35) {
            // 大致对应许多山脉地区
            baseElevation = 1000 + arc4random_uniform(3000);
        } else {
            // 其他地区
            baseElevation = 20 + arc4random_uniform(300);
        }
        
        // 添加一些随机性以模拟地形变化
        double elevation = baseElevation + (arc4random_uniform(100) - 50);
        
        // 存入缓存
        elevationCache[cacheKey] = @(elevation);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(elevation, nil);
            }
        });
    });
}

@end