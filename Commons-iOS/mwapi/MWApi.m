//
//  MWApi.m
//  MWApi-iOS
//
//  Created by Brion on 11/5/12.
//  Copyright (c) 2012 Wikimedia Foundation. All rights reserved.
//

#import "MWApi.h"
#import "Http.h"
#import "NSURLRequest+DictionaryRequest.h"
#import "MWApiMultipartRequestBuilder.h"

id delegate;

@implementation MWApi

@synthesize apiURL = apiURL_;
@synthesize userID = userID_;
@synthesize userName = userName_;
@synthesize includeAuthCookie = includeAuthCookie_;
@synthesize isLoggedIn = isLoggedIn_;

- (id)initWithApiUrl: (NSURL*)url {
    self = [super init];
    if(self){
        apiURL_ = url;
        includeAuthCookie_ = YES;
        [self clearAuthCookie]; // Clearing previous authCookies from the shared cookie storage
    }
    return self;
}

- (id)delegate {
    return delegate;
}

- (void)setDelegate:(id)newDelegate {
    delegate = newDelegate;
}

- (MWApiRequestBuilder *) action:(NSString *)action {
    MWApiRequestBuilder *builder = [[MWApiRequestBuilder alloc]initWithApi:self];
    [builder param:@"action" :action];
    return builder;
}
    	
- (NSArray *) authCookie {
    return authCookie_;
}

- (void) setAuthCookie:(NSArray *)newAuthCookie{
    authCookie_ = newAuthCookie;
    [[ NSHTTPCookieStorage sharedHTTPCookieStorage] setCookies: authCookie_ forURL: apiURL_ mainDocumentURL: nil ];
}

- (void) setAuthCookieFromResult:(MWApiResult *)result {
    authCookie_ = [ NSHTTPCookie cookiesWithResponseHeaderFields:[(NSHTTPURLResponse *)result.response allHeaderFields] forURL:apiURL_];
    [[ NSHTTPCookieStorage sharedHTTPCookieStorage] setCookies: authCookie_ forURL: apiURL_ mainDocumentURL: nil ];
}

-(void)clearAuthCookie{
    authCookie_ = nil;
    NSArray *previousCookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:apiURL_];
    for (NSHTTPCookie *each in previousCookies)
        [[NSHTTPCookieStorage sharedHTTPCookieStorage] deleteCookie:each];
}

- (void) validateLogin:(void(^)(BOOL))block
{
    MWApiRequestBuilder *builder = [[self action:@"query"] param:@"meta" :@"userinfo"];
    [self makeRequest:[builder buildRequest:@"GET"] onCompletion:^(MWApiResult *result) {
        userID_ = [result.data[@"query"][@"userinfo"][@"id"] copy];
        userName_ = [result.data[@"query"][@"userinfo"][@"name"] copy];
        block(![userID_ isEqualToString:@"0"]);
    }];
}

- (void)loginWithUsername:(NSString *)username andPassword:(NSString *)password withCookiePersistence:(BOOL) doCookiePersist onCompletion:(void(^)(MWApiResult *))block
{
    MWApiRequestBuilder *builder = [self action:@"login"];
    [builder params: @{
        @"lgname": username,
        @"lgpassword": password
    }];
    [self makeRequest:[builder buildRequest:@"POST"] onCompletion:^(MWApiResult *result) {
        void (^complete)(MWApiResult *) = ^(MWApiResult *completeResult) {
            if ([completeResult.data[@"login"][@"result"] isEqualToString:@"Success"]) {
                isLoggedIn_ = YES;
                if(doCookiePersist){
                    [self setAuthCookieFromResult:completeResult];
                }
            }
            block(completeResult);
        };
        if([result.data[@"login"][@"result"] isEqualToString:@"NeedToken"]){
            NSString *token = result.data[@"login"][@"token"];
            [builder param:@"lgtoken" :token];
            [self makeRequest:[builder buildRequest:@"POST"] onCompletion:complete];
        } else {
            complete(result);
        }
    }];
}

- (void)loginWithUsername:(NSString *)username andPassword:(NSString *)password onCompletion:(void(^)(MWApiResult *))block {
    [self loginWithUsername:username andPassword:password withCookiePersistence:NO onCompletion:block];
}

- (void) logout:onCompletion:(void(^)(MWApiResult *))block {
    MWApiRequestBuilder *builder = [self action:@"logout"];
    [self makeRequest:[builder buildRequest:@"POST"] onCompletion:^(MWApiResult *result) {
        [self clearAuthCookie];
        isLoggedIn_ = NO;
        block(result);
    }];
}

- (void)uploadFile:(NSString *)filename withFileData:(NSData *)data text:(NSString *)text comment:(NSString *)comment onCompletion:(void(^)(MWApiResult *))completionBlock onProgress:(void(^)(NSInteger,NSInteger))progressBlock
{
    [self editToken: ^(NSString *editToken) {
        MWApiMultipartRequestBuilder *builder = [[MWApiMultipartRequestBuilder alloc] initWithApi:self];
        [builder params: @{
             @"action": @"upload",
             @"token": editToken,
             @"filename": filename,
             @"ignorewarnings": @"1",
             @"comment": comment,
             @"text": (text != nil) ? text : @"",
             @"format": @"json"
        }];
        
        NSURLRequest *uploadRequest = [builder buildRequest:@"POST" withFilename:filename withFileData:data];
        [builder.api makeRequest:uploadRequest onCompletion:completionBlock onProgress: progressBlock];
    }];
}

- (void)editToken:(void(^)(NSString *))block {
    MWApiRequestBuilder *builder = [[self action:@"tokens"] param:@"type" :@"edit"];
    [self makeRequest:[builder buildRequest:@"GET"] onCompletion:^(MWApiResult *result) {
        block([result.data[@"tokens"][@"edittoken"] copy]);
    }];
}

- (void)makeRequest:(NSMutableURLRequest *)request onCompletion:(void(^)(MWApiResult *))completionBlock onProgress:(void(^)(NSInteger,NSInteger))progressBlock
{
    if(!includeAuthCookie_){
        [self clearAuthCookie];
    }
    [Http retrieveResponse:request onCompletion:completionBlock onProgress:progressBlock];
}

- (void)makeRequest:(NSMutableURLRequest *)request onCompletion:(void(^)(MWApiResult *))block
{
    [self makeRequest: request onCompletion:block onProgress:nil];
}

@end
