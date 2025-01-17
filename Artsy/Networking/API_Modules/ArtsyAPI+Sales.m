#import "ArtsyAPI+Private.h"


@implementation ArtsyAPI (Sales)

+ (void)getSalesWithArtwork:(NSString *)artworkID
                    success:(void (^)(NSArray *sales))success
                    failure:(void (^)(NSError *error))failure
{
    NSURLRequest *request = [ARRouter salesWithArtworkRequest:artworkID];
    [self getRequest:request parseIntoAnArrayOfClass:[Sale class] success:success failure:failure];
}

+ (AFHTTPRequestOperation *)getArtworksForSale:(NSString *)saleID
                                       success:(void (^)(NSArray *))success
                                       failure:(void (^)(NSError *))failure
{
    NSURLRequest *request = [ARRouter artworksForSaleRequest:saleID];
    return [self getRequest:request parseIntoAnArrayOfClass:[Artwork class] withKey:@"artwork" success:success failure:failure];
}

+ (void)getSaleWithID:(NSString *)saleID
              success:(void (^)(Sale *sale))success
              failure:(void (^)(NSError *error))failure
{
    NSURLRequest *request = [ARRouter requestForSaleID:saleID];
    [self getRequest:request parseIntoAClass:[Sale class] success:success failure:failure];
}

@end
