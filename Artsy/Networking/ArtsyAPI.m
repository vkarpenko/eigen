#import "ArtsyAPI.h"
#import "ArtsyAPI+Private.h"

#import "ARAppConstants.h"
#import "ARDefaults.h"
#import "ARDispatchManager.h"
#import "ARRouter.h"
#import "ARNetworkErrorManager.h"
#import "ARLogger.h"

#import "MTLModel+JSON.h"
#import "AFHTTPRequestOperation+JSON.h"

#import <ISO8601DateFormatter/ISO8601DateFormatter.h>
#import <UICKeyChainStore/UICKeyChainStore.h>

@implementation ArtsyAPI

+ (AFHTTPRequestOperation *)performRequest:(NSURLRequest *)request success:(void (^)(id))success failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error))failure
{
    NSParameterAssert(success);
    return [self.sharedAPI performRequest:request success:success failure:failure];
}

+ (AFHTTPRequestOperation *)getRequest:(NSURLRequest *)request parseIntoAClass:(Class)klass success:(void (^)(id))success failure:(void (^)(NSError *error))failure
{
    return [self getRequest:request parseIntoAClass:klass withKey:nil success:success failure:failure];
}

+ (AFHTTPRequestOperation *)getRequest:(NSURLRequest *)request parseIntoAnArrayOfClass:(Class)klass success:(void (^)(NSArray *))success failure:(void (^)(NSError *error))failure
{
    return [self getRequest:request parseIntoAnArrayOfClass:klass withKey:nil success:success failure:failure];
}

+ (AFHTTPRequestOperation *)getRequest:(NSURLRequest *)request parseIntoAClass:(Class)klass withKey:(NSString *)key success:(void (^)(id))success failure:(void (^)(NSError *error))failure
{
    return [self.sharedAPI getRequest:request parseIntoAClass:klass withKey:key success:success failure:failure];
}

+ (AFHTTPRequestOperation *)getRequest:(NSURLRequest *)request parseIntoAnArrayOfClass:(Class)klass withKey:(NSString *)key success:(void (^)(NSArray *))success failure:(void (^)(NSError *error))failure
{
    NSParameterAssert(success);
    return [self.sharedAPI getRequest:request parseIntoAnArrayOfClass:klass withKey:key success:success failure:failure];
}

+ (AFHTTPRequestOperation *)getRequest:(NSURLRequest *)request parseIntoAnArrayOfClass:(Class)klass fromDictionaryWithKey:(NSString *)key success:(void (^)(NSArray *))success failure:(void (^)(NSError *error))failure
{
    NSParameterAssert(success);
    return [self.sharedAPI getRequest:request parseIntoAnArrayOfClass:klass fromDictionaryWithKey:key success:success failure:failure];
}

+ (void)getRequests:(NSArray *)requests success:(void (^)(NSArray *operations))completed
{
    [self.sharedAPI getRequests:requests success:completed];
}

- (void)getRequests:(NSArray *)requests success:(void (^)(NSArray *operations))completed
{
    NSArray *operations = [requests map:^id(NSURLRequest *request) {
        return [self requestOperation:request success:nil failure:nil];
    }];

    NSArray *newOps = [AFURLConnectionOperation batchOfRequestOperations:operations progressBlock:nil completionBlock:completed];

    [[NSOperationQueue mainQueue] addOperations:newOps waitUntilFinished:NO];

}

#pragma mark -
#pragma mark Xapp tokens

+ (void)getXappTokenWithCompletion:(void (^)(NSString *xappToken, NSDate *expirationDate))callback
{
    [self getXappTokenWithCompletion:callback failure:nil];
}

+ (void)getXappTokenWithCompletion:(void (^)(NSString *xappToken, NSDate *expirationDate))callback failure:(void (^)(NSError *error))failure
{
    [self.sharedAPI getXappTokenWithCompletion:callback failure:failure];
}

/**
 *  Reset XAPP token on an access denied.
 *
 *  @param error AFNetworking error.
 */
+ (void)handleXappTokenError:(NSError *)error
{
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)error.userInfo[AFNetworkingOperationFailingURLResponseErrorKey];
    if (response.statusCode == 401) {
        NSData *data = error.userInfo[AFNetworkingOperationFailingURLResponseDataErrorKey];
        NSDictionary *recoverySuggestion = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        
        if ([recoverySuggestion[@"error"] isEqualToString:@"Unauthorized"] && [recoverySuggestion[@"text"] isEqualToString:@"The XAPP token is invalid or has expired."]) {
            ARActionLog(@"Resetting XAPP token after error: %@", error.localizedDescription);
            [UICKeyChainStore removeItemForKey:ARXAppTokenDefault];
            [ARRouter setXappToken:nil];
        }
    }
}

+ (ArtsyAPI *)sharedAPI
{
    static ArtsyAPI *_sharedController = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        Class klass = NSClassFromString(@"ArtsyOHHTTPAPI") ?: self;
        _sharedController = [[klass alloc] init];
    });

    return _sharedController;
}

- (AFHTTPRequestOperation *)requestOperation:(NSURLRequest *)request success:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, id JSON))success failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON))failure
{
    return [AFHTTPRequestOperation JSONRequestOperationWithRequest:request success:success failure:failure];
}

- (AFHTTPRequestOperation *)performRequest:(NSURLRequest *)request success:(void (^)(id))success failure:(void (^)(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error))failure
{
    __weak AFHTTPRequestOperation *performOperation = nil;
    performOperation = [self requestOperation:request success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        success(JSON);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        if (failure) {
            [ArtsyAPI handleXappTokenError:error];
            failure(request, response, error);
        }
    }];

    [performOperation start];
    return performOperation;
}

- (void)getXappTokenWithCompletion:(void (^)(NSString *xappToken, NSDate *expirationDate))callback failure:(void (^)(NSError *error))failure;
{
    // Check if we already have a token for xapp or oauth and run the block

    NSDate *date = [[NSUserDefaults standardUserDefaults] objectForKey:ARXAppTokenExpiryDateDefault];
    NSString *xappToken = [UICKeyChainStore stringForKey:ARXAppTokenDefault];
    NSString *oauthToken = [UICKeyChainStore stringForKey:AROAuthTokenDefault];

    if (date && (xappToken || oauthToken)) {
        if (callback) {
            callback(xappToken ?: oauthToken, date);
        }
        return;
    }

    NSURLRequest *tokenRequest = [ARRouter newXAppTokenRequest];
    AFHTTPRequestOperation *op = [self requestOperation:tokenRequest success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {

        NSString *token = JSON[ARXAppToken];
        NSString *date = JSON[AROExpiryDateKey];

        ISO8601DateFormatter *dateFormatter = [[ISO8601DateFormatter alloc] init];
        NSDate *expiryDate = [dateFormatter dateFromString:date];

        NSString *oldxToken = [UICKeyChainStore stringForKey:ARXAppTokenDefault];
        if (oldxToken) {
            if (callback) {
                callback(token, expiryDate);
            }
            return ;
        }

        [ARRouter setXappToken:token];
        [UICKeyChainStore setString:token forKey:ARXAppTokenDefault];
        [[NSUserDefaults standardUserDefaults] setObject:expiryDate forKey:ARXAppTokenExpiryDateDefault];
        [[NSUserDefaults standardUserDefaults] synchronize];

        if (callback) {
            callback(token, expiryDate);
        }

    }
    failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {

        //TODO: handle this less stupid
        ARErrorLog(@"Couldn't get an Xapp token.");

        NSError *cleanError = [NSError errorWithDomain:@"Auth" code:404 userInfo:@{ NSLocalizedDescriptionKey: @"Can’t reach Artsy." }];
        [ARNetworkErrorManager presentActiveError:cleanError];

        if (failure) { failure(error); }
    }];

    [op start];
}

- (AFHTTPRequestOperation *)getRequest:(NSURLRequest *)request parseIntoAClass:(Class)klass withKey:(NSString *)key success:(void (^)(id))success failure:(void (^)(NSError *error))failure;
{
    __weak AFHTTPRequestOperation *getOperation = nil;
    getOperation = [self requestOperation:request success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {

        NSDictionary *jsonDictionary = JSON;
        id object = nil;
        if (key) {
            if (jsonDictionary[key]) {
                object = [klass modelWithJSON:jsonDictionary[key] error:nil];
            }
        } else {
            object = [klass modelWithJSON:jsonDictionary error:nil];
        }
        if (success) {
            ar_dispatch_main_queue(^{
                success(object);
            });
        }
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [ArtsyAPI handleXappTokenError:error];
        if (failure) {
            ar_dispatch_main_queue(^{
                failure(error);
            });
        }
    }];

    // Use a background queue so JSON results are parsed off the UI thread. We'll dispatch back to main queue on success.
    getOperation.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [getOperation start];
    return getOperation;
}


- (AFHTTPRequestOperation *)getRequest:(NSURLRequest *)request parseIntoAnArrayOfClass:(Class)klass fromDictionaryWithKey:(NSString *)key success:(void (^)(NSArray *))success failure:(void (^)(NSError *error))failure;
{
    __weak AFHTTPRequestOperation *getOperation = nil;
    getOperation = [self requestOperation:request success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {

        NSArray *jsonDictionaries = JSON[key];
        if (![jsonDictionaries isKindOfClass:NSArray.class]) {
            NSLog(@"Expected a hash JSON repsonse - got an array");
            failure(nil);
        }

        if (success) {
            ar_dispatch_main_queue(^{
                success([jsonDictionaries map:^id(id dictionary) {
                    return [klass modelWithJSON:dictionary error:nil];
                }]);
            });
        }
    }
    failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [ArtsyAPI handleXappTokenError:error];
        ar_dispatch_main_queue(^{
            if (failure) {
                failure(error);
            }
        });
    }];
    getOperation.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [getOperation start];
    return getOperation;
}

- (AFHTTPRequestOperation *)getRequest:(NSURLRequest *)request parseIntoAnArrayOfClass:(Class)klass withKey:(NSString *)key success:(void (^)(NSArray *))success failure:(void (^)(NSError *error))failure
{
    __weak AFHTTPRequestOperation *getOperation = nil;
    getOperation = [self requestOperation:request success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        NSArray *jsonDictionaries = JSON;
        NSMutableArray *returnArray = [NSMutableArray array];

        for (NSDictionary *dictionary in jsonDictionaries) {
            id object = nil;
            if (![dictionary isKindOfClass:[NSDictionary class]]) {
                DDLogDebug(@"skipping %@", dictionary);
                continue;
            }

            if (key) {
                if ([dictionary.allKeys containsObject:key]) {
                    object = [klass modelWithJSON:dictionary[key] error:nil];
                }
            } else {
                object = [klass modelWithJSON:dictionary error:nil];
            }

            if (object) {
                [returnArray addObject:object];
            }
        }
        
        ar_dispatch_main_queue(^{
            success(returnArray);
        });
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [ArtsyAPI handleXappTokenError:error];
        ar_dispatch_main_queue(^{
            if (failure) {
                failure(error);
            }
        });
    }];
    
    // Use a background queue so JSON results are parsed off the UI thread. We'll dispatch back to main queue on success.
    getOperation.completionQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    [getOperation start];
    return getOperation;
}

@end
