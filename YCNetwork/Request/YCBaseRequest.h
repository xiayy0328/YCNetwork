//
//  YCBaseRequest.h
//  YCNetworkDemo
//
//  Created by xiayingying on 2019/9/29.
//  Copyright © 2019 xyy. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "YCNetworkResponse.h"
#import "YCNetworkCache.h"

NS_ASSUME_NONNULL_BEGIN

@interface YCBaseRequest : NSObject
#pragma - 网络请求数据

/** 请求方法类型 */
@property (nonatomic, assign) YCRequestMethod requestMethod;

/** 请求访问路径 (例如：/detail/list) */
@property (nonatomic, copy) NSString *requestURI;

/** 请求参数 */
@property (nonatomic, copy, nullable) NSDictionary *requestParameter;

/** 请求头参数 */
@property (nonatomic, copy, nullable) NSDictionary *requestHeaderParameter;

/** 请求超时时间 */
@property (nonatomic, assign) NSTimeInterval requestTimeoutInterval;

/** 请求上传文件包 */
@property (nonatomic, copy, nullable) void(^requestConstructingBody)(id<AFMultipartFormData> formData);

/** 下载路径 */
@property (nonatomic, copy) NSString *downloadPath;

#pragma - 发起网络请求

/** 发起网络请求 */
- (void)start;

/** 发起网络请求带回调 */
- (void)startWithSuccess:(nullable YCRequestSuccessBlock)success
                 failure:(nullable YCRequestFailureBlock)failure;

- (void)startWithCache:(nullable YCRequestCacheBlock)cache
               success:(nullable YCRequestSuccessBlock)success
               failure:(nullable YCRequestFailureBlock)failure;

- (void)startWithUploadProgress:(nullable YCRequestProgressBlock)uploadProgress
               downloadProgress:(nullable YCRequestProgressBlock)downloadProgress
                          cache:(nullable YCRequestCacheBlock)cache
                        success:(nullable YCRequestSuccessBlock)success
                        failure:(nullable YCRequestFailureBlock)failure;

/** 取消网络请求 */
- (void)cancel;

#pragma - 相关回调代理

/** 请求结果回调代理 */
@property (nonatomic, weak) id<YCResponseDelegate> delegate;

#pragma - 缓存

/** 缓存处理器 */
@property (nonatomic, strong, readonly) YCNetworkCache *cacheHandler;

#pragma - 其它

/** 网络请求释放策略 (默认 YCNetworkReleaseStrategyHoldRequest) */
@property (nonatomic, assign) YCNetworkReleaseStrategy releaseStrategy;

/** 重复网络请求处理策略 (默认 YCNetworkRepeatStrategyAllAllowed) */
@property (nonatomic, assign) YCNetworkRepeatStrategy repeatStrategy;

/** 是否正在网络请求 */
- (BOOL)isExecuting;

/** 请求标识，可以查看完整的请求路径和参数 */
- (NSString *)requestIdentifier;

/** 清空所有请求回调闭包 */
- (void)clearRequestBlocks;

#pragma - 网络请求公共配置 (以子类化方式实现: 针对不同的接口团队设计不同的公共配置)

/**
 事务管理器 (通常情况下不需设置) 。注意：
 1、其 requestSerializer 和 responseSerializer 属性会被下面两个同名属性覆盖。
 2、其 completionQueue 属性会被框架内部覆盖。
 */
@property (nonatomic, strong, nullable) AFHTTPSessionManager *sessionManager;

/** 请求序列化器 */
@property (nonatomic, strong) AFHTTPRequestSerializer *requestSerializer;

/** 响应序列化器 */
@property (nonatomic, strong) AFHTTPResponseSerializer *responseSerializer;

/** 服务器地址及公共路径 (例如：https://www.baidu.com) */
@property (nonatomic, copy) NSString *baseURI;

@end


/// 预处理请求数据 (重写分类方法)
@interface YCBaseRequest (PreprocessRequest)

/** 预处理请求头参数, 返回处理后的请求头参数 */
- (nullable NSDictionary *)yc_preprocessHeaderParameter:(nullable NSDictionary *)parameter;

/** 预处理请求参数, 返回处理后的请求参数 */
- (nullable NSDictionary *)yc_preprocessParameter:(nullable NSDictionary *)parameter;

/** 预处理拼接后的完整 URL 字符串, 返回处理后的 URL 字符串 */
- (NSString *)yc_preprocessURLString:(NSString *)URLString;

@end


/// 预处理响应数据 (重写分类方法)
@interface YCBaseRequest (PreprocessResponse)

/**
 网络请求回调重定向，方法在子线程回调，并会再下面几个预处理方法之前调用。
 需要特别注意 YCRequestRedirectionStop 会停止后续操作，如果业务使用闭包回调，这个闭包不会被清空，可能会造成循环引用，所以这种场景务必保证回调被正确处理，一般有以下两种方式：
 1、Stop 过后执行特定逻辑，然后重新 start 发起网络请求，之前的回调闭包就能继续正常处理了。
 2、直接调用 clearRequestBlocks 清空回调闭包。
 */
- (void)yc_redirection:(void(^)(YCRequestRedirection))redirection response:(YCNetworkResponse *)response;

/** 预处理请求成功数据 (子线程执行, 若数据来自缓存在主线程执行) */
- (void)yc_preprocessSuccessInChildThreadWithResponse:(YCNetworkResponse *)response;

/** 预处理请求成功数据 */
- (void)yc_preprocessSuccessInMainThreadWithResponse:(YCNetworkResponse *)response;

/** 预处理请求失败数据 (子线程执行) */
- (void)yc_preprocessFailureInChildThreadWithResponse:(YCNetworkResponse *)response;

/** 预处理请求失败数据 */
- (void)yc_preprocessFailureInMainThreadWithResponse:(YCNetworkResponse *)response;

@end

NS_ASSUME_NONNULL_END
