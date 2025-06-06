/*
 * GPS++
 * 有问题 联系pxx917144686
 */

#import "GPSRouteManager.h"
#import <libxml/parser.h>
#import <libxml/tree.h>

@implementation GPSRouteManager {
    NSString *_routesDirectory;
}

+ (instancetype)sharedInstance {
    static GPSRouteManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        // 创建路线存储目录
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        _routesDirectory = [paths[0] stringByAppendingPathComponent:@"GPSRoutes"];
        
        if (![fileManager fileExistsAtPath:_routesDirectory]) {
            [fileManager createDirectoryAtPath:_routesDirectory 
                  withIntermediateDirectories:YES 
                                   attributes:nil 
                                        error:nil];
        }
    }
    return self;
}

- (NSArray<GPSLocationModel *> *)importGPXFromPath:(NSString *)filePath error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:filePath options:0 error:error];
    if (!data) {
        return nil;
    }
    
    xmlDocPtr doc = xmlReadMemory([data bytes], (int)[data length], NULL, NULL, 0);
    if (doc == NULL) {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSRouteManager" 
                                         code:1001 
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法解析GPX文件"}];
        }
        return nil;
    }
    
    NSMutableArray<GPSLocationModel *> *points = [NSMutableArray array];
    xmlNodePtr root = xmlDocGetRootElement(doc);
    
    // 处理trkpt和wpt标签
    for (xmlNodePtr node = root->children; node; node = node->next) {
        if (node->type != XML_ELEMENT_NODE) continue;
        
        if (xmlStrcmp(node->name, (const xmlChar *)"trk") == 0) {
            // 处理轨迹段
            for (xmlNodePtr trkSegNode = node->children; trkSegNode; trkSegNode = trkSegNode->next) {
                if (trkSegNode->type != XML_ELEMENT_NODE) continue;
                if (xmlStrcmp(trkSegNode->name, (const xmlChar *)"trkseg") == 0) {
                    [self parseTrackPoints:trkSegNode->children intoArray:points];
                }
            }
        } else if (xmlStrcmp(node->name, (const xmlChar *)"wpt") == 0) {
            // 处理航点
            GPSLocationModel *point = [self parseWayPoint:node];
            if (point) {
                [points addObject:point];
            }
        }
    }
    
    xmlFreeDoc(doc);
    
    return points;
}

- (void)parseTrackPoints:(xmlNodePtr)node intoArray:(NSMutableArray *)points {
    for (; node; node = node->next) {
        if (node->type != XML_ELEMENT_NODE) continue;
        if (xmlStrcmp(node->name, (const xmlChar *)"trkpt") == 0) {
            GPSLocationModel *point = [self parseWayPoint:node];
            if (point) {
                [points addObject:point];
            }
        }
    }
}

- (GPSLocationModel *)parseWayPoint:(xmlNodePtr)node {
    xmlChar *lat = xmlGetProp(node, (const xmlChar *)"lat");
    xmlChar *lon = xmlGetProp(node, (const xmlChar *)"lon");
    
    if (!lat || !lon) return nil;
    
    GPSLocationModel *point = [[GPSLocationModel alloc] init];
    point.latitude = [[NSString stringWithUTF8String:(const char *)lat] doubleValue];
    point.longitude = [[NSString stringWithUTF8String:(const char *)lon] doubleValue];
    point.timestamp = [NSDate date];
    
    // 解析高度、速度、时间等
    for (xmlNodePtr child = node->children; child; child = child->next) {
        if (child->type != XML_ELEMENT_NODE) continue;
        
        if (xmlStrcmp(child->name, (const xmlChar *)"ele") == 0) {
            xmlChar *content = xmlNodeGetContent(child);
            if (content) {
                point.altitude = [[NSString stringWithUTF8String:(const char *)content] doubleValue];
                xmlFree(content);
            }
        } else if (xmlStrcmp(child->name, (const xmlChar *)"time") == 0) {
            xmlChar *content = xmlNodeGetContent(child);
            if (content) {
                NSString *timeStr = [NSString stringWithUTF8String:(const char *)content];
                // 解析时间字符串...
                xmlFree(content);
            }
        } else if (xmlStrcmp(child->name, (const xmlChar *)"name") == 0) {
            xmlChar *content = xmlNodeGetContent(child);
            if (content) {
                point.title = [NSString stringWithUTF8String:(const char *)content];
                xmlFree(content);
            }
        }
    }
    
    xmlFree(lat);
    xmlFree(lon);
    return point;
}

- (BOOL)exportRoute:(NSArray<GPSLocationModel *> *)route toPath:(NSString *)filePath name:(NSString *)name error:(NSError **)error {
    // 创建GPX文档
    xmlDocPtr doc = xmlNewDoc((const xmlChar *)"1.0");
    xmlNodePtr root = xmlNewNode(NULL, (const xmlChar *)"gpx");
    xmlNewProp(root, (const xmlChar *)"version", (const xmlChar *)"1.1");
    xmlNewProp(root, (const xmlChar *)"creator", (const xmlChar *)"GPS++ App");
    xmlNewProp(root, (const xmlChar *)"xmlns", (const xmlChar *)"http://www.topografix.com/GPX/1/1");
    xmlDocSetRootElement(doc, root);
    
    // 添加元数据
    xmlNodePtr metadata = xmlNewChild(root, NULL, (const xmlChar *)"metadata", NULL);
    xmlNodePtr metaName = xmlNewChild(metadata, NULL, (const xmlChar *)"name", (const xmlChar *)[name UTF8String]);
    
    // 创建轨迹
    xmlNodePtr trk = xmlNewChild(root, NULL, (const xmlChar *)"trk", NULL);
    xmlNodePtr trkName = xmlNewChild(trk, NULL, (const xmlChar *)"name", (const xmlChar *)[name UTF8String]);
    xmlNodePtr trkseg = xmlNewChild(trk, NULL, (const xmlChar *)"trkseg", NULL);
    
    // 添加轨迹点
    for (GPSLocationModel *point in route) {
        xmlNodePtr trkpt = xmlNewChild(trkseg, NULL, (const xmlChar *)"trkpt", NULL);
        
        // 设置经纬度
        xmlNewProp(trkpt, (const xmlChar *)"lat", (const xmlChar *)[[NSString stringWithFormat:@"%f", point.latitude] UTF8String]);
        xmlNewProp(trkpt, (const xmlChar *)"lon", (const xmlChar *)[[NSString stringWithFormat:@"%f", point.longitude] UTF8String]);
        
        // 添加高度
        xmlNodePtr ele = xmlNewChild(trkpt, NULL, (const xmlChar *)"ele", 
                                   (const xmlChar *)[[NSString stringWithFormat:@"%f", point.altitude] UTF8String]);
        
        // 添加时间
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        NSString *timeString = [formatter stringFromDate:point.timestamp ?: [NSDate date]];
        xmlNodePtr time = xmlNewChild(trkpt, NULL, (const xmlChar *)"time", (const xmlChar *)[timeString UTF8String]);
    }
    
    // 保存文档
    int result = xmlSaveFormatFileEnc([filePath UTF8String], doc, "UTF-8", 1);
    xmlFreeDoc(doc);
    
    if (result == -1) {
        if (error) {
            *error = [NSError errorWithDomain:@"GPSRouteManager" 
                                         code:1002 
                                     userInfo:@{NSLocalizedDescriptionKey: @"无法保存GPX文件"}];
        }
        return NO;
    }
    
    return YES;
}

- (NSArray<NSString *> *)savedRouteNames {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *fileList = [fileManager contentsOfDirectoryAtPath:_routesDirectory error:&error];
    
    if (error) {
        return @[];
    }
    
    NSMutableArray *routeNames = [NSMutableArray array];
    for (NSString *file in fileList) {
        if ([file.pathExtension isEqualToString:@"gpx"]) {
            [routeNames addObject:[file stringByDeletingPathExtension]];
        }
    }
    
    return routeNames;
}

- (BOOL)saveRoute:(NSArray<GPSLocationModel *> *)route withName:(NSString *)name error:(NSError **)error {
    NSString *filePath = [_routesDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.gpx", name]];
    return [self exportRoute:route toPath:filePath name:name error:error];
}

- (NSArray<GPSLocationModel *> *)loadRouteWithName:(NSString *)name error:(NSError **)error {
    NSString *filePath = [_routesDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.gpx", name]];
    return [self importGPXFromPath:filePath error:error];
}

- (BOOL)deleteRouteWithName:(NSString *)name error:(NSError **)error {
    NSString *filePath = [_routesDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.gpx", name]];
    return [[NSFileManager defaultManager] removeItemAtPath:filePath error:error];
}

- (NSData *)dataForRouteName:(NSString *)routeName {
    NSString *filePath = [_routesDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.gpx", routeName]];
    NSError *error = nil;
    NSData *fileData = [NSData dataWithContentsOfFile:filePath options:0 error:&error];
    
    if (error || !fileData) {
        NSLog(@"读取路线文件失败: %@", error.localizedDescription);
        return nil;
    }
    
    return fileData;
}

@end