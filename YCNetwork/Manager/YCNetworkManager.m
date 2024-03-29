//
//  YCNetworkManager.m
//  YCNetworkDemo
//
//  Created by xiayingying on 2019/9/29.
//  Copyright © 2019 xyy. All rights reserved.
//

#import "YCNetworkManager.h"
#import "YCBaseRequest+Internal.h"
#import <pthread/pthread.h>

#define YCNM_TASKRECORD_LOCK(...) \
pthread_mutex_lock(&self->_lock); \
__VA_ARGS__ \
pthread_mutex_unlock(&self->_lock);

@interface YCNetworkManager ()
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSURLSessionTask *> *taskRecord;
@end

@implementation YCNetworkManager {
    pthread_mutex_t _lock;
}

#pragma mark - life cycle

- (void)dealloc {
    pthread_mutex_destroy(&_lock);
}

+ (instancetype)sharedManager {
    static YCNetworkManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[YCNetworkManager alloc] initSpecially];
    });
    return manager;
}

- (instancetype)initSpecially {
    self = [super init];
    if (self) {
        pthread_mutex_init(&_lock, NULL);
    }
    return self;
}

#pragma mark - private

- (void)cancelTaskWithIdentifier:(NSNumber *)identifier {
    YCNM_TASKRECORD_LOCK(NSURLSessionTask *task = self.taskRecord[identifier];)
    if (task) {
        [task cancel];
        YCNM_TASKRECORD_LOCK([self.taskRecord removeObjectForKey:identifier];)
    }
}

- (void)cancelAllTask {
    YCNM_TASKRECORD_LOCK(
        for (NSURLSessionTask *task in self.taskRecord) {
            [task cancel];
        }
        [self.taskRecord removeAllObjects];
    )
}

- (NSNumber *)startDownloadTaskWithManager:(AFHTTPSessionManager *)manager URLRequest:(NSURLRequest *)URLRequest downloadPath:(NSString *)downloadPath  downloadProgress:(nullable YCRequestProgressBlock)downloadProgress completion:(YCRequestCompletionBlock)completion {
    
    // 保证下载路径是文件而不是目录
    NSString *validDownloadPath = downloadPath.copy;
    BOOL isDirectory;
    if(![[NSFileManager defaultManager] fileExistsAtPath:validDownloadPath isDirectory:&isDirectory]) {
        isDirectory = NO;
    }
    if (isDirectory) {
        validDownloadPath = [NSString pathWithComponents:@[validDownloadPath, URLRequest.URL.lastPathComponent]];
    }
    
    // 若存在文件则移除
    if ([[NSFileManager defaultManager] fileExistsAtPath:validDownloadPath]) {
        [[NSFileManager defaultManager] removeItemAtPath:validDownloadPath error:nil];
    }
    
    __block NSURLSessionDownloadTask *task = [manager downloadTaskWithRequest:URLRequest progress:downloadProgress destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        return [NSURL fileURLWithPath:validDownloadPath isDirectory:NO];
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        YCNM_TASKRECORD_LOCK([self.taskRecord removeObjectForKey:@(task.taskIdentifier)];)
        if (completion) {
            completion([YCNetworkResponse responseWithSessionTask:task responseObject:filePath error:error]);
        }
    }];
    
    NSNumber *taskIdentifier = @(task.taskIdentifier);
    YCNM_TASKRECORD_LOCK(self.taskRecord[taskIdentifier] = task;)
    [task resume];
    return taskIdentifier;
}

- (NSNumber *)startDataTaskWithManager:(AFHTTPSessionManager *)manager URLRequest:(NSURLRequest *)URLRequest uploadProgress:(nullable YCRequestProgressBlock)uploadProgress downloadProgress:(nullable YCRequestProgressBlock)downloadProgress completion:(YCRequestCompletionBlock)completion {
    
    __block NSURLSessionDataTask *task = [manager dataTaskWithRequest:URLRequest uploadProgress:^(NSProgress * _Nonnull _uploadProgress) {
        if (uploadProgress) {
            uploadProgress(_uploadProgress);
        }
    } downloadProgress:^(NSProgress * _Nonnull _downloadProgress) {
        if (downloadProgress) {
            downloadProgress(_downloadProgress);
        }
    } completionHandler:^(NSURLResponse * _Nonnull response, id  _Nullable responseObject, NSError * _Nullable error) {
        YCNM_TASKRECORD_LOCK([self.taskRecord removeObjectForKey:@(task.taskIdentifier)];)
        if (completion) {
            completion([YCNetworkResponse responseWithSessionTask:task responseObject:responseObject error:error]);
        }
    }];
    
    NSNumber *taskIdentifier = @(task.taskIdentifier);
    YCNM_TASKRECORD_LOCK(self.taskRecord[taskIdentifier] = task;)
    [task resume];
    return taskIdentifier;
}

#pragma mark - public

- (void)cancelNetworkingWithSet:(NSSet<NSNumber *> *)set {
    YCNM_TASKRECORD_LOCK(
        for (NSNumber *identifier in set) {
            NSURLSessionTask *task = self.taskRecord[identifier];
            if (task) {
                [task cancel];
                [self.taskRecord removeObjectForKey:identifier];
            }
        }
    )
}

- (NSNumber *)startNetworkingWithRequest:(YCBaseRequest *)request uploadProgress:(nullable YCRequestProgressBlock)uploadProgress downloadProgress:(nullable YCRequestProgressBlock)downloadProgress completion:(nullable YCRequestCompletionBlock)completion {
    
    // 构建网络请求数据
    NSString *method = [request requestMethodString];
    AFHTTPRequestSerializer *serializer = [self requestSerializerForRequest:request];
    NSString *URLString = [request validRequestURLString];
    id parameter = [request validRequestParameter];
    id headerParameter = [request validRequestHeaderParameter];
    // 构建 URLRequest
    NSError *error = nil;
    NSMutableURLRequest *URLRequest = nil;
    if (request.requestConstructingBody) {
        URLRequest = [serializer multipartFormRequestWithMethod:@"POST" URLString:URLString parameters:parameter constructingBodyWithBlock:request.requestConstructingBody error:&error];
    } else {
        URLRequest = [serializer requestWithMethod:method URLString:URLString parameters:parameter error:&error];
    }
    if (headerParameter) {
        [headerParameter enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString *  _Nonnull obj, BOOL * _Nonnull stop) {
            [URLRequest addValue:obj forHTTPHeaderField:key];
        }];
    }
    if (error) {
        if (completion) completion([YCNetworkResponse responseWithSessionTask:nil responseObject:nil error:error]);
        return nil;
    }
    
    // 发起网络请求
    AFHTTPSessionManager *manager = [self sessionManagerForRequest:request];
    if (request.downloadPath.length > 0) {
        return [self startDownloadTaskWithManager:manager URLRequest:URLRequest downloadPath:request.downloadPath downloadProgress:downloadProgress completion:completion];
    } else {
        return [self startDataTaskWithManager:manager URLRequest:URLRequest uploadProgress:uploadProgress downloadProgress:downloadProgress completion:completion];
    }
}

#pragma mark - read info from request

- (AFHTTPRequestSerializer *)requestSerializerForRequest:(YCBaseRequest *)request {
    AFHTTPRequestSerializer *serializer = request.requestSerializer ?: [AFJSONRequestSerializer serializer];
    if (request.requestTimeoutInterval > 0) {
        serializer.timeoutInterval = request.requestTimeoutInterval;
    }
    return serializer;
}

- (AFHTTPSessionManager *)sessionManagerForRequest:(YCBaseRequest *)request {
    AFHTTPSessionManager *manager = request.sessionManager;
    if (!manager) {
        static AFHTTPSessionManager *defaultManager = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            defaultManager = [AFHTTPSessionManager new];
        });
        manager = defaultManager;
    }
    manager.completionQueue = dispatch_queue_create("com.ycnetwork.completionqueue", DISPATCH_QUEUE_CONCURRENT);
    AFHTTPResponseSerializer *customSerializer = request.responseSerializer;
    if (customSerializer) manager.responseSerializer = customSerializer;
    return manager;
}

#pragma mark - getter

- (NSMutableDictionary<NSNumber *,NSURLSessionTask *> *)taskRecord {
    if (!_taskRecord) {
        _taskRecord = [NSMutableDictionary dictionary];
    }
    return _taskRecord;
}

@end
