#import "ARTestHelper.h"
#import "SaleArtwork+Extensions.h"
#import "MTLModel+Dictionary.h"


@implementation SaleArtwork (Extensions)
+ (SaleArtwork *)saleArtworkWithHighBid:(Bid *)bid AndReserveStatus:(ARReserveStatus)status
{
    return [SaleArtwork modelFromDictionary:@{
        @"artworkNumPositions" : @(5),
        @"saleHighestBid" : bid,
        @"minimumNextBidCents" : @(11000000),
        @"reserveStatus" : @(status)
    }];
}
@end
