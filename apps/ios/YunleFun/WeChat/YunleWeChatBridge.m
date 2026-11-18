#import "YunleWeChatBridge.h"
#import <TargetConditionals.h>

#if !TARGET_OS_SIMULATOR && defined(YUNLE_HAS_WECHAT_SDK)
#import "WXApi.h"

@interface YunleWeChatDelegate : NSObject <WXApiDelegate>
@property (nonatomic, copy, nullable) YunleWeChatResponse response;
@end

@implementation YunleWeChatDelegate
- (void)onResp:(BaseResp *)response {
    if (![response isKindOfClass:SendAuthResp.class]) return;
    SendAuthResp *auth = (SendAuthResp *)response;
    YunleWeChatResponse handler = self.response;
    if (handler) handler(auth.errCode, auth.state, auth.code);
}
@end

// WXApi receives its delegate at URL handling time; keep it alive for an asynchronous reply.
static YunleWeChatDelegate *YunleWeChatSharedDelegate(void) {
    static YunleWeChatDelegate *delegate;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ delegate = [YunleWeChatDelegate new]; });
    return delegate;
}
#endif

@implementation YunleWeChatBridge
+ (BOOL)prepare:(NSString *)appID universalLink:(NSString *)universalLink {
#if !TARGET_OS_SIMULATOR && defined(YUNLE_HAS_WECHAT_SDK)
    return [WXApi registerApp:appID universalLink:universalLink];
#else
    return NO;
#endif
}

+ (BOOL)isLinked {
#if !TARGET_OS_SIMULATOR && defined(YUNLE_HAS_WECHAT_SDK)
    return YES;
#else
    return NO;
#endif
}

+ (void)sendAuth:(NSString *)state completion:(void (^)(BOOL))completion {
#if !TARGET_OS_SIMULATOR && defined(YUNLE_HAS_WECHAT_SDK)
    SendAuthReq *request = [SendAuthReq new];
    request.scope = @"snsapi_userinfo";
    request.state = state;
    request.nonautomatic = YES;
    [WXApi sendReq:request completion:completion];
#else
    completion(NO);
#endif
}

+ (BOOL)handleURL:(NSURL *)url response:(YunleWeChatResponse)response {
#if !TARGET_OS_SIMULATOR && defined(YUNLE_HAS_WECHAT_SDK)
    YunleWeChatDelegate *delegate = YunleWeChatSharedDelegate();
    delegate.response = response;
    return [WXApi handleOpenURL:url delegate:delegate];
#else
    return NO;
#endif
}

+ (BOOL)handleActivity:(NSUserActivity *)activity response:(YunleWeChatResponse)response {
#if !TARGET_OS_SIMULATOR && defined(YUNLE_HAS_WECHAT_SDK)
    YunleWeChatDelegate *delegate = YunleWeChatSharedDelegate();
    delegate.response = response;
    return [WXApi handleOpenUniversalLink:activity delegate:delegate];
#else
    return NO;
#endif
}
@end
