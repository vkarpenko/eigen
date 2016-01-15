#import "ARNetworkConstants.h"
#import "ARRouter.h"
#import "ARRouter+Private.h"
#import "ARUserManager.h"
#import "ARAppStatus.h"
#import <UICKeyChainStore/UICKeyChainStore.h>
#import <Keys/ArtsyKeys.h>

static AFHTTPSessionManager *staticHTTPClient = nil;
static NSSet *artsyHosts = nil;


@implementation ARRouter

+ (void)setup
{
    artsyHosts = [NSSet setWithObjects:@"art.sy", @"artsyapi.com", @"artsy.net", @"m.artsy.net", @"staging.artsy.net", @"m-staging.artsy.net", nil];

    [ARRouter setupWithBaseApiURL:[ARRouter baseApiURL]];

    [self setupUserAgent];
}

+ (NSSet *)artsyHosts
{
    return artsyHosts;
}

+ (NSURL *)baseApiURL
{
    if ([AROptions boolForOption:ARUseStagingDefault]) {
        return [NSURL URLWithString:ARStagingBaseApiURL];
    } else {
        return [NSURL URLWithString:ARBaseApiURL];
    }
}

+ (NSURL *)baseWebURL
{
    return [UIDevice isPad] ? [self baseDesktopWebURL] : [self baseMobileWebURL];
}

+ (NSURL *)baseDesktopWebURL
{
    return [NSURL URLWithString:[AROptions boolForOption:ARUseStagingDefault] ? ARStagingBaseWebURL : ARBaseDesktopWebURL];
}

+ (NSURL *)baseMobileWebURL
{
    return [NSURL URLWithString:[AROptions boolForOption:ARUseStagingDefault] ? ARStagingBaseMobileWebURL : ARBaseMobileWebURL];
}

+ (void)setupWithBaseApiURL:(NSURL *)baseApiURL
{
    staticHTTPClient = [[AFHTTPSessionManager alloc] initWithBaseURL:baseApiURL];
    [staticHTTPClient.reachabilityManager setReachabilityStatusChangeBlock:^(AFNetworkReachabilityStatus status) {
            switch (status) {
                case AFNetworkReachabilityStatusUnknown:
                    break; // do nothing
                case AFNetworkReachabilityStatusNotReachable:
                    [[NSNotificationCenter defaultCenter] postNotificationName:ARNetworkUnavailableNotification object:nil];
                    break;
                default:
                    [[NSNotificationCenter defaultCenter] postNotificationName:ARNetworkAvailableNotification object:nil];
                    break;
            }
    }];

    // Ensure the keychain is empty incase you've uninstalled and cleared user data
    // but make sure that this is not a slip-up due to background fetch downloading

    UIApplicationState state = [[UIApplication sharedApplication] applicationState];
    if (![[ARUserManager sharedManager] hasExistingAccount] && state != UIApplicationStateBackground) {
        [UICKeyChainStore removeItemForKey:AROAuthTokenDefault];
        [UICKeyChainStore removeItemForKey:ARXAppTokenKeychainKey];
    }

    NSString *token = [UICKeyChainStore stringForKey:AROAuthTokenDefault];
    if (token) {
        ARActionLog(@"Found OAuth token in keychain");
        [ARRouter setAuthToken:token];

    } else {
        ARActionLog(@"Found trial XApp token in keychain");
        NSString *xapp = [UICKeyChainStore stringForKey:ARXAppTokenKeychainKey];
        [ARRouter setXappToken:xapp];
    }
}

+ (void)setupUserAgent
{
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    NSString *build = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];

    // Take the default from AFNetworking, and extend them all to include:
    // * code names
    // * version information
    // * include big browser engine names so that scripts like that of fast.fonts.net WKWebView will load

    AFHTTPRequestSerializer *serializer = [[AFHTTPRequestSerializer alloc] init];
    NSString *userAgent = serializer.HTTPRequestHeaders[@"User-Agent"];
    NSString *agentString = [NSString stringWithFormat:@"Mozilla/5.0 Artsy-Mobile/%@ Eigen/%@", version, build];
    userAgent = [userAgent stringByReplacingOccurrencesOfString:@"Artsy" withString:agentString];
    userAgent = [userAgent stringByAppendingString:@" AppleWebKit/601.1.46 (KHTML, like Gecko)"];

    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"UserAgent" : userAgent }];
    [self setHTTPHeader:@"User-Agent" value:userAgent];
}

+ (void)setHTTPHeader:(NSString *)header value:(NSString *)value
{
    [staticHTTPClient.requestSerializer setValue:value forHTTPHeaderField:header];
}

+ (BOOL)isWebURL:(NSURL *)url
{
    return (!url.scheme || ([url.scheme isEqual:@"http"] || [url.scheme isEqual:@"https"]));
}

/// TODO: don't allow Special Apple URLs? iTMS / maps.apple?

+ (BOOL)isInternalURL:(NSURL *)url
{
    // Is it a touch link?
    if ([url.scheme isEqual:@"applewebdata"] || [url.scheme isEqual:@"artsy"]) {
        return YES;
    }

    if (![self isWebURL:url]) {
        return NO;
    }

    NSString *host = url.host;
    if ([host hasPrefix:@"www"]) {
        host = [host substringFromIndex:4];
    }

    //if there's no host, we'll assume it's relative
    return (!host || (host && [artsyHosts containsObject:host]));
}

+ (NSURLRequest *)requestForURL:(NSURL *)url
{
    NSMutableURLRequest *request = [self requestWithMethod:@"GET" URLString:url.absoluteString parameters:nil];
    if (![ARRouter isInternalURL:url]) {
        [request setValue:nil forHTTPHeaderField:ARAuthHeader];
        [request setValue:nil forHTTPHeaderField:ARXappHeader];
    }

    return request;
}

+ (AFHTTPSessionManager *)httpClient
{
    return staticHTTPClient;
}

#pragma mark -
#pragma mark OAuth

+ (void)setAuthToken:(NSString *)token
{
    [self setHTTPHeader:ARAuthHeader value:token];
}

+ (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path
{
    return [self requestWithMethod:method path:path parameters:nil];
}

+ (NSMutableURLRequest *)requestWithMethod:(NSString *)method path:(NSString *)path parameters:(NSDictionary *)params
{
    NSString *fullPath = [[staticHTTPClient.baseURL URLByAppendingPathComponent:path] absoluteString];
    return [self requestWithMethod:method URLString:fullPath parameters:params];
}

+ (NSMutableURLRequest *)requestWithMethod:(NSString *)method URLString:(NSString *)urlString parameters:(NSDictionary *)params
{
    NSMutableURLRequest *request = [staticHTTPClient.requestSerializer requestWithMethod:method URLString:urlString parameters:params error:nil];
    return request;
}


+ (NSURLRequest *)newOAuthRequestWithUsername:(NSString *)username password:(NSString *)password
{
    NSDictionary *params = @{
        @"email" : username,
        @"password" : password,
        @"client_id" : [ArtsyKeys new].artsyAPIClientKey,
        @"client_secret" : [ArtsyKeys new].artsyAPIClientSecret,
        @"grant_type" : @"credentials",
        @"scope" : @"offline_access"
    };
    return [self requestWithMethod:@"GET" path:AROAuthURL parameters:params];
}

+ (NSURLRequest *)newFacebookOAuthRequestWithToken:(NSString *)token
{
    NSDictionary *params = @{
        @"oauth_provider" : @"facebook",
        @"oauth_token" : token,
        @"client_id" : [ArtsyKeys new].artsyAPIClientKey,
        @"client_secret" : [ArtsyKeys new].artsyAPIClientSecret,
        @"grant_type" : @"oauth_token",
        @"scope" : @"offline_access"
    };
    return [self requestWithMethod:@"GET" path:AROAuthURL parameters:params];
}

+ (NSURLRequest *)newTwitterOAuthRequestWithToken:(NSString *)token andSecret:(NSString *)secret
{
    NSDictionary *params = @{
        @"oauth_provider" : @"twitter",
        @"oauth_token" : token,
        @"oauth_token_secret" : secret,
        @"client_id" : [ArtsyKeys new].artsyAPIClientKey,
        @"client_secret" : [ArtsyKeys new].artsyAPIClientSecret,
        @"grant_type" : @"oauth_token",
        @"scope" : @"offline_access"
    };
    return [self requestWithMethod:@"GET" path:AROAuthURL parameters:params];
}


#pragma mark -
#pragma mark XApp

+ (void)setXappToken:(NSString *)token
{
    [self setHTTPHeader:ARXappHeader value:token];
}

+ (NSURLRequest *)newXAppTokenRequest
{
    NSDictionary *params = @{
        @"client_id" : [ArtsyKeys new].artsyAPIClientKey,
        @"client_secret" : [ArtsyKeys new].artsyAPIClientSecret,
    };
    return [self requestWithMethod:@"GET" path:ARXappURL parameters:params];
}

#pragma mark -
#pragma mark User creation

+ (NSURLRequest *)newCreateUserRequestWithName:(NSString *)name
                                         email:(NSString *)email
                                      password:(NSString *)password
{
    NSDictionary *params = @{
        @"email" : email,
        @"password" : password,
        @"name" : name
    };
    return [self requestWithMethod:@"POST" path:ARCreateUserURL parameters:params];
}

+ (NSURLRequest *)newCreateUserViaFacebookRequestWithToken:(NSString *)token email:(NSString *)email name:(NSString *)name
{
    NSDictionary *params = @{
        @"provider" : @"facebook",
        @"oauth_token" : token,
        @"email" : email,
        @"name" : name
    };

    return [self requestWithMethod:@"POST" path:ARCreateUserURL parameters:params];
}

+ (NSURLRequest *)newCreateUserViaTwitterRequestWithToken:(NSString *)token secret:(NSString *)secret email:(NSString *)email name:(NSString *)name
{
    NSDictionary *params = @{
        @"provider" : @"twitter",
        @"oauth_token" : token,
        @"oauth_token_secret" : secret,
        @"email" : email,
        @"name" : name
    };

    return [self requestWithMethod:@"POST" path:ARCreateUserURL parameters:params];
}

#pragma mark -
#pragma mark User

+ (NSURLRequest *)newUserInfoRequest
{
    return [self requestWithMethod:@"GET" path:ARMyInfoURL parameters:nil];
}

+ (NSURLRequest *)newUserEditRequestWithParams:(NSDictionary *)params
{
    return [self requestWithMethod:@"PUT" path:ARMyInfoURL parameters:params];
}

+ (NSURLRequest *)newCheckFollowingProfileHeadRequest:(NSString *)profileID
{
    NSString *path = NSStringWithFormat(ARFollowingProfileURLFormat, profileID);
    return [self requestWithMethod:@"GET" path:path parameters:nil];
}

+ (NSURLRequest *)newMyFollowProfileRequest:(NSString *)profileID
{
    return [self requestWithMethod:@"POST" path:ARFollowProfileURL parameters:@{ @"profile_id" : profileID }];
}

+ (NSURLRequest *)newMyUnfollowProfileRequest:(NSString *)profileID
{
    NSString *path = NSStringWithFormat(ARUnfollowProfileURLFormat, profileID);
    return [self requestWithMethod:@"DELETE" path:path parameters:@{ @"profile_id" : profileID }];
}

+ (NSURLRequest *)newFollowingProfilesRequestWithFair:(Fair *)fair
{
    return [self requestWithMethod:@"GET" path:ARFollowProfilesURL parameters:@{ @"fair_id" : fair.fairID }];
}

#pragma mark -
#pragma mark Feed

+ (NSURLRequest *)newFeedRequestWithCursor:(NSString *)cursor pageSize:(NSInteger)size
{
    if (!cursor) {
        cursor = @"";
    }
    return [self requestWithMethod:@"GET" path:ARMyFeedURL parameters:@{ @"cursor" : cursor,
                                                                         @"size" : @(size) }];
}

+ (NSURLRequest *)newShowFeedRequestWithCursor:(NSString *)cursor pageSize:(NSInteger)size
{
    NSMutableDictionary *params = [@{
        @"size" : @(size),
        @"feed" : @"shows"
    } mutableCopy];

    if (cursor) [params setObject:cursor forKey:@"cursor"];

    return [self requestWithMethod:@"GET" path:ARShowFeedURL parameters:params];
}

+ (NSURLRequest *)newFairShowFeedRequestWithFair:(Fair *)fair partnerID:(NSString *)partnerID cursor:(NSString *)cursor pageSize:(NSInteger)size
{
    NSMutableDictionary *params = [@{ @"size" : @(size) } mutableCopy];
    if (cursor) [params setObject:cursor forKey:@"cursor"];
    if (partnerID) [params setObject:partnerID forKey:@"partner"];

    NSString *path = NSStringWithFormat(ARNewFairShowsURLFormat, fair.fairID);
    return [self requestWithMethod:@"GET" path:path parameters:params];
}

+ (NSURLRequest *)newPostsRequestForProfileID:(NSString *)profileID WithCursor:(NSString *)cursor pageSize:(NSInteger)size
{
    NSString *url = [NSString stringWithFormat:ARProfileFeedURLFormat, profileID];
    NSMutableDictionary *params = [@{ @"size" : @(size) } mutableCopy];
    if (cursor) [params setObject:cursor forKey:@"cursor"];
    return [self requestWithMethod:@"GET" path:url parameters:params];
}

+ (NSURLRequest *)newPostsRequestForProfile:(Profile *)profile WithCursor:(NSString *)cursor pageSize:(NSInteger)size
{
    return [ARRouter newPostsRequestForProfileID:profile.profileID WithCursor:cursor pageSize:size];
}

+ (NSURLRequest *)newPostsRequestForFairOrganizer:(FairOrganizer *)fairOrganizer WithCursor:(NSString *)cursor pageSize:(NSInteger)size
{
    return [ARRouter newPostsRequestForProfileID:fairOrganizer.profileID WithCursor:cursor pageSize:size];
}

#pragma mark -
#pragma mark Artworks

+ (NSURLRequest *)newArtworkInfoRequestForArtworkID:(NSString *)artworkID
{
    NSString *address = [NSString stringWithFormat:ARNewArtworkInfoURLFormat, artworkID];
    return [self requestWithMethod:@"GET" path:address parameters:nil];
}

+ (NSURLRequest *)newArtworksRelatedToArtworkRequest:(Artwork *)artwork
{
    NSDictionary *params = @{ @"artwork" : @[ artwork.artworkID ] };
    NSString *address = [NSString stringWithFormat:ARNewRelatedArtworksURLFormat, @"synthetic", @"main"];
    return [self requestWithMethod:@"GET" path:address parameters:params];
}

+ (NSURLRequest *)newArtworksRelatedToArtwork:(Artwork *)artwork inFairRequest:(Fair *)fair
{
    NSDictionary *params = @{ @"artwork" : @[ artwork.artworkID ] };
    NSString *address = [NSString stringWithFormat:ARNewRelatedArtworksURLFormat, @"fair", fair.fairID];
    return [self requestWithMethod:@"GET" path:address parameters:params];
}

+ (NSURLRequest *)newPostsRelatedToArtwork:(Artwork *)artwork
{
    NSDictionary *params = @{ @"artwork" : @[ artwork.artworkID ] };
    return [self requestWithMethod:@"GET" path:ARNewRelatedPostsURL parameters:params];
}

+ (NSURLRequest *)newPostsRelatedToArtist:(Artist *)artist
{
    NSDictionary *params = @{ @"artist" : @[ artist.artistID ] };
    return [self requestWithMethod:@"GET" path:ARNewRelatedPostsURL parameters:params];
}

+ (NSURLRequest *)newArtworkComparablesRequest:(Artwork *)artwork
{
    NSString *address = [NSString stringWithFormat:ARArtworkComparablesURLFormat, artwork.artworkID];
    return [self requestWithMethod:@"GET" path:address parameters:nil];
}

+ (NSURLRequest *)newAdditionalImagesRequestForArtworkWithID:(NSString *)artworkID
{
    NSString *url = [NSString stringWithFormat:ARAdditionalImagesURLFormat, artworkID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

+ (NSURLRequest *)newNewArtworksRequestWithParams:(NSDictionary *)params
{
    return [self requestWithMethod:@"GET" path:ARNewArtworksURL parameters:params];
}

+ (NSURLRequest *)newArtistArtworksRequestWithParams:(NSDictionary *)params andArtistID:(NSString *)artistID
{
    NSString *url = [NSString stringWithFormat:ARArtistArtworksURLFormat, artistID];
    return [self requestWithMethod:@"GET" path:url parameters:params];
}

+ (NSURLRequest *)createBidderPositionsForSaleID:(NSString *)saleID artworkID:(NSString *)artworkID maxBidAmountCents:(NSInteger)maxBidAmountCents
{
    NSDictionary *params = @{ @"sale_id" : saleID,
                              @"artwork_id" : artworkID,
                              @"max_bid_amount_cents" : @(maxBidAmountCents) };
    return [self requestWithMethod:@"POST" path:ARBidderPositionsForSaleAndArtworkURL parameters:params];
}

#pragma mark -
#pragma mark Artwork Favorites (items in the saved-artwork collection)

+ (NSURLRequest *)newArtworkFavoritesRequestWithFair:(Fair *)fair
{
    NSDictionary *params = @{
        @"fair_id" : fair.fairID,
        @"user_id" : [User currentUser].userID ?: @"",
        @"private" : @YES
    };

    NSMutableURLRequest *request = [self requestWithMethod:@"GET" path:ARFavoritesURL parameters:params];

    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;

    return request;
}

+ (NSURLRequest *)newSetArtworkFavoriteRequestForArtwork:(Artwork *)artwork status:(BOOL)status
{
    NSString *method = status ? @"POST" : @"DELETE";
    NSString *url = [NSString stringWithFormat:ARAddArtworkToFavoritesURLFormat, artwork.artworkID];
    return [self requestWithMethod:method
                              path:url
                        parameters:@{ @"user_id" : [User currentUser].userID ?: @"" }];
}


+ (NSURLRequest *)newArtworksFromUsersFavoritesRequestWithID:(NSString *)userID page:(NSInteger)page
{
    NSDictionary *params = @{
        @"size" : @15,
        @"page" : @(page),
        @"sort" : @"-position",
        @"total_count" : @1,
        @"user_id" : userID ?: @"",
        @"private" : ARIsRunningInDemoMode ? @"false" : @"true"
    };

    return [self requestWithMethod:@"GET" path:ARFavoritesURL parameters:params];
}

+ (NSURLRequest *)newCheckFavoriteStatusRequestForArtwork:(Artwork *)artwork
{
    return [self newCheckFavoriteStatusRequestForArtworks:@[ artwork ]];
}

+ (NSURLRequest *)newCheckFavoriteStatusRequestForArtworks:(NSArray *)artworks
{
    NSArray *slugs = [artworks map:^(Artwork *artwork) {
        return artwork.artworkID;
    }];

    NSDictionary *params = @{
        @"artworks" : slugs,
        @"user_id" : [User currentUser].userID ?: @"",
        @"private" : @"true"
    };
    return [self requestWithMethod:@"GET" path:ARFavoritesURL parameters:params];
}

+ (NSURLRequest *)newFairsRequestForArtwork:(Artwork *)artwork
{
    NSDictionary *params = @{ @"artwork" : @[ artwork.artworkID ] };
    return [self requestWithMethod:@"GET" path:ARArtworkFairsURLFormat parameters:params];
}

+ (NSURLRequest *)newShowsRequestForArtworkID:(NSString *)artworkID andFairID:(NSString *)fairID
{
    NSDictionary *params = fairID ? @{ @"artwork" : @[ artworkID ],
                                       @"fair_id" : fairID } :
                                    @{ @"artwork" : @[ artworkID ] };
    return [self requestWithMethod:@"GET" path:ARRelatedShowsURL parameters:params];
}

#pragma mark -
#pragma mark Artist

+ (NSURLRequest *)newArtistsFromSampleAtPage:(NSInteger)page
{
    return [self requestWithMethod:@"GET" path:ARSampleArtistsURL parameters:@{ @"page" : @(page) }];
}


+ (NSURLRequest *)newArtistsFromPersonalCollectionAtPage:(NSInteger)page
{
    return [self requestWithMethod:@"GET" path:ARFollowArtistsURL parameters:@{ @"page" : @(page) }];
}

+ (NSURLRequest *)newArtistCountFromPersonalCollectionRequest;
{
    return [self requestWithMethod:@"GET" path:ARFollowArtistsURL parameters:@{
        @"total_count" : @1
    }];
}

+ (NSURLRequest *)newArtistInfoRequestWithID:(NSString *)artistID
{
    NSString *url = [NSString stringWithFormat:ARArtistInformationURLFormat, artistID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

+ (NSURLRequest *)newFollowArtistRequest:(Artist *)artist
{
    return [self requestWithMethod:@"POST"
                              path:ARFollowArtistURL
                        parameters:@{ @"artist_id" : artist.artistID }];
}

+ (NSURLRequest *)newUnfollowArtistRequest:(Artist *)artist
{
    NSString *url = [NSString stringWithFormat:ARUnfollowArtistURLFormat, artist.artistID];
    return [self requestWithMethod:@"DELETE" path:url parameters:nil];
}

+ (NSURLRequest *)newFollowingRequestForArtist:(Artist *)artists
{
    return [self newFollowingRequestForArtists:@[ artists ]];
}

+ (NSURLRequest *)newFollowingRequestForArtists:(NSArray *)artists
{
    NSArray *slugs = [artists map:^(Artist *artist) {
        return artist.artistID;
    }];

    return [self requestWithMethod:@"GET" path:ARFollowArtistsURL parameters:@{ @"artists" : slugs }];
}

+ (NSURLRequest *)newFollowingArtistsRequestWithFair:(Fair *)fair
{
    return [self requestWithMethod:@"GET" path:ARFollowArtistsURL parameters:@{ @"fair_id" : fair.fairID }];
}

+ (NSURLRequest *)newArtistsRelatedToArtistRequest:(Artist *)artist
{
    NSDictionary *params = @{ @"artist" : @[ artist.artistID ] };
    return [self requestWithMethod:@"GET" path:ARRelatedArtistsURL parameters:params];
}

+ (NSURLRequest *)newShowsRequestForArtist:(NSString *)artistID
{
    NSDictionary *params = @{ @"artist" : @[ artistID ] };
    return [self requestWithMethod:@"GET" path:ARRelatedShowsURL parameters:params];
}

+ (NSURLRequest *)newShowsRequestForArtistID:(NSString *)artistID inFairID:(NSString *)fairID
{
    NSDictionary *params = @{ @"artist" : artistID };
    return [self requestWithMethod:@"GET" path:NSStringWithFormat(ARShowsFeaturingArtistsURLFormat, fairID) parameters:params];
}

+ (NSURLRequest *)newShowsListingRequest
{
    return [self requestWithMethod:@"GET" path:ARShowsURL parameters:nil];
}

+ (NSURLRequest *)newRunningShowsListingRequestForLongitude:(CGFloat)longitude latitude:(CGFloat)latitude
{
    NSString *near = [NSString stringWithFormat:@"%@,%@", @(latitude), @(longitude)];
    return [self requestWithMethod:@"GET" path:ARShowsURL parameters:@{
        @"near" : near,
        @"max_distance" : @1000,
        @"status" : @"running"
    }];
}

#pragma mark - Genes

+ (NSURLRequest *)newGeneCountFromPersonalCollectionRequest
{
    return [self requestWithMethod:@"GET" path:ARFollowGenesURL parameters:@{ @"total_count" : @1 }];
}

+ (NSURLRequest *)newGenesFromPersonalCollectionAtPage:(NSInteger)page
{
    return [self requestWithMethod:@"GET" path:ARFollowGenesURL parameters:@{ @"page" : @(page) }];
}

+ (NSURLRequest *)newGeneInfoRequestWithID:(NSString *)geneID
{
    NSString *url = [NSString stringWithFormat:ARGeneInformationURLFormat, geneID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

+ (NSURLRequest *)newFollowingRequestForGene:(Gene *)gene
{
    return [self newFollowingRequestForGenes:@[ gene ]];
}

+ (NSURLRequest *)newFollowGeneRequest:(Gene *)gene
{
    return [self requestWithMethod:@"POST" path:ARFollowGeneURL parameters:@{ @"gene_id" : gene.geneID }];
}

+ (NSURLRequest *)newUnfollowGeneRequest:(Gene *)gene
{
    NSString *url = [NSString stringWithFormat:ARUnfollowGeneURLFormat, gene.geneID];
    return [self requestWithMethod:@"DELETE" path:url parameters:nil];
}

+ (NSURLRequest *)newFollowingRequestForGenes:(NSArray *)genes
{
    NSArray *slugs = [genes map:^(Gene *gene) { return gene.geneID;
    }];
    return [self requestWithMethod:@"GET" path:ARFollowGenesURL parameters:@{ @"genes" : slugs }];
}

#pragma mark - Shows

+ (NSURLRequest *)newShowInfoRequestWithID:(NSString *)showID
{
    NSString *url = [NSString stringWithFormat:ARShowInformationURLFormat, showID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

#pragma mark - Models

+ (NSURLRequest *)newPostInfoRequestWithID:(NSString *)postID
{
    NSString *url = [NSString stringWithFormat:ARPostInformationURLFormat, postID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

+ (NSURLRequest *)newProfileInfoRequestWithID:(NSString *)profileID
{
    NSString *url = [NSString stringWithFormat:ARProfileInformationURLFormat, profileID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

+ (NSURLRequest *)newArtworkInfoRequestWithID:(NSString *)artworkID
{
    NSString *url = [NSString stringWithFormat:ARArtworkInformationURLFormat, artworkID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

#pragma mark -
#pragma mark Search

+ (NSURLRequest *)newSearchRequestWithQuery:(NSString *)query
{
    return [self requestWithMethod:@"GET" path:ARNewSearchURL parameters:@{ @"term" : query }];
}

+ (NSURLRequest *)newSearchRequestWithFairID:(NSString *)fairID andQuery:(NSString *)query
{
    return [self requestWithMethod:@"GET" path:ARNewSearchURL parameters:@{ @"term" : query,
                                                                            @"fair_id" : fairID }];
}

+ (NSURLRequest *)newArtistSearchRequestWithQuery:(NSString *)query
{
    return [self requestWithMethod:@"GET" path:ARNewArtistSearchURL parameters:@{ @"term" : query }];
}

+ (NSURLRequest *)directImageRequestForModel:(Class)model andSlug:(NSString *)slug
{
    // Note: should these be moved to network constants?

    NSDictionary *paths = @{
        @"Artwork" : @"/api/v1/artwork/%@/default_image.jpg",
        @"Artist" : @"/api/v1/artist/%@/image",
        @"Gene" : @"/api/v1/gene/%@/image",
        @"Tag" : @"/api/v1/tag/%@/image",
        @"Profile" : @"/api/v1/profile/%@/image",
        @"SiteFeature" : @"/api/v1/feature/%@/image",
        @"PartnerShow" : @"/api/v1/partner_show/%@/default_image.jpg",
    };

    NSString *key = NSStringFromClass(model);
    NSString *path = [NSString stringWithFormat:paths[key], slug];
    return [self requestWithMethod:@"GET" path:path parameters:nil];
}

#pragma mark -
#pragma mark Fairs

+ (NSURLRequest *)newFairInfoRequestWithID:(NSString *)fairID
{
    NSString *url = [NSString stringWithFormat:ARNewFairInfoURLFormat, fairID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

+ (NSURLRequest *)newFairShowsRequestWithFair:(Fair *)fair
{
    NSString *url = [NSString stringWithFormat:ARNewFairShowsURLFormat, fair.fairID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

+ (NSURLRequest *)newFairMapRequestWithFair:(Fair *)fair
{
    return [self requestWithMethod:@"GET" path:ARNewFairMapURL parameters:@{ @"fair_id" : fair.fairID }];
}

+ (NSURLRequest *)newFollowArtistRequest
{
    return [self requestWithMethod:@"GET" path:ARFollowArtistsURL parameters:nil];
}

+ (NSURLRequest *)newFollowArtistRequestWithFair:(Fair *)fair
{
    return [self requestWithMethod:@"GET" path:ARFollowArtistsURL parameters:@{ @"fair_id" : fair.fairID }];
}

#pragma mark - Recommendations

+ (NSURLRequest *)suggestedHomepageArtworksRequest
{
    return [self requestWithMethod:@"GET" path:ARSuggestedHomepageArtworks parameters:nil];
}

+ (NSURLRequest *)worksForYouRequest
{
    return [ARRouter requestWithMethod:@"GET" path:ARNotificationsURL parameters:@{
        @"page" : @1,
        @"type" : @"ArtworkPublished",
        @"user_id" : [User currentUser].userID,
        @"size" : @(10)
    }];
}

+ (NSURLRequest *)worksForYouCountRequest;
{
    return [ARRouter requestWithMethod:@"GET" path:ARNotificationsURL parameters:@{
        @"page" : @1,
        @"type" : @"ArtworkPublished",
        @"user_id" : [User currentUser].userID,
        @"size" : @(1), // This endpoint only works if at least 1 artwork is requested
        @"total_count" : @1,
        @"unread" : @"true"
    }];
}

#pragma mark -
#pragma mark Misc Site

+ (NSURLRequest *)newSiteHeroUnitsRequest
{
    return [self requestWithMethod:@"GET" path:ARSiteHeroUnitsURL parameters:@{ @"mobile" : @"true",
                                                                                @"enabled" : @"true" }];
}

+ (NSURLRequest *)newOnDutyRepresentativeRequest
{
    return [self requestWithMethod:@"GET" path:AROnDutyRepresentativesURL parameters:nil];
}

+ (NSURLRequest *)newArtworkInquiryRequestForArtwork:(Artwork *)artwork
                                                name:(NSString *)name
                                               email:(NSString *)email
                                             message:(NSString *)message
                                 analyticsDictionary:(NSDictionary *)analyticsDictionary
                                shouldContactGallery:(BOOL)contactGallery
{
    NSParameterAssert(artwork);
    NSParameterAssert(message);

    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:@{
        @"artwork" : artwork.artworkID,
        @"message" : message,
        @"contact_gallery" : @(contactGallery)
    }];

    [analyticsDictionary enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([key isEqualToString:ArtsyAPIInquiryAnalyticsInquiryURL]) {
            params[@"inquiry_url"] = obj;
        } else if ([key isEqualToString:ArtsyAPIInquiryAnalyticsReferralURL]) {
            params[@"referring_url"] = obj;
        } else if ([key isEqualToString:ArtsyAPIInquiryAnalyticsLandingURL]) {
            params[@"landing_url"] = obj;
        }
    }];

    if ([User isTrialUser]) {
        NSParameterAssert(name);
        NSParameterAssert(email);
        [params setValue:name forKey:@"name"];
        [params setValue:email forKey:@"email"];
        [params setValue:[ARUserManager sharedManager].trialUserUUID forKey:@"session_id"];
    } else {
        NSParameterAssert(!name);
        NSParameterAssert(!email);
    }

    return [self requestWithMethod:@"POST" path:ARArtworkInquiryRequestURL parameters:params];
}

+ (NSURLRequest *)newArtworksFromShowRequest:(PartnerShow *)show atPage:(NSInteger)page
{
    NSString *url = [NSString stringWithFormat:ARShowArtworksURLFormat, show.partner.partnerID, show.showID];
    return [self requestWithMethod:@"GET" path:url parameters:@{
        @"page" : @(page),
        @"published" : @YES,
        @"size" : @10
    }];
}

+ (NSURLRequest *)newImagesFromShowRequest:(PartnerShow *)show atPage:(NSInteger)page
{
    NSString *url = [NSString stringWithFormat:ARShowImagesURLFormat, show.showID];
    return [self requestWithMethod:@"GET" path:url parameters:@{
        @"default" : @(NO),
        @"page" : @(page),
        @"size" : @10
    }];
}

+ (NSURLRequest *)newArtworksFromGeneRequest:(NSString *)gene atPage:(NSInteger)page
{
    NSDictionary *params = @{
        @"page" : @(page),
        @"gene_id" : gene
    };
    return [self requestWithMethod:@"GET" path:ARGeneArtworksURL parameters:params];
}

+ (NSURLRequest *)newForgotPasswordRequestWithEmail:(NSString *)email
{
    NSDictionary *params = @{ @"email" : email };
    return [self requestWithMethod:@"POST" path:ARForgotPasswordURL parameters:params];
}

+ (NSURLRequest *)newSiteFeaturesRequest
{
    return [self requestWithMethod:@"GET" path:ARSiteFeaturesURL parameters:nil];
}

+ (NSURLRequest *)newSetDeviceAPNTokenRequest:(NSString *)token forDevice:(NSString *)device
{
    NSString *bundleID = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];

    NSDictionary *params = @{
        @"name" : device,
        @"token" : token,
        @"app_id" : bundleID,
        @"production" : ARAppStatus.isBetaOrDev ? @"false" : @"true"
    };
    return [self requestWithMethod:@"POST" path:ARNewDeviceURL parameters:params];
}

+ (NSURLRequest *)newUptimeURLRequest
{
    return [self requestWithMethod:@"GET" path:ARSiteUpURL parameters:nil];
}

+ (NSURLRequest *)salesWithArtworkRequest:(NSString *)artworkID
{
    NSDictionary *params = @{ @"artwork[]" : artworkID };
    return [self requestWithMethod:@"GET" path:ARSalesForArtworkURL parameters:params];
}

+ (NSURLRequest *)artworksForSaleRequest:(NSString *)saleID
{
    NSString *url = [NSString stringWithFormat:ARSaleArtworksURLFormat, saleID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

+ (NSURLRequest *)biddersRequest
{
    return [self requestWithMethod:@"GET" path:ARMyBiddersURL parameters:nil];
}

+ (NSURLRequest *)bidderPositionsRequestForSaleID:(NSString *)saleID artworkID:(NSString *)artworkID
{
    NSDictionary *params = @{ @"sale_id" : saleID,
                              @"artwork_id" : artworkID };
    return [self requestWithMethod:@"GET" path:ARBidderPositionsForSaleAndArtworkURL parameters:params];
}

+ (NSURLRequest *)saleArtworkRequestForSaleID:(NSString *)saleID artworkID:(NSString *)artworkID
{
    NSString *path = [NSString stringWithFormat:ARSaleArtworkForSaleAndArtworkURLFormat, saleID, artworkID];
    NSMutableURLRequest *req = [self requestWithMethod:@"GET" path:path parameters:nil];
    req.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    return req;
}

+ (NSURLRequest *)requestForSaleID:(NSString *)saleID
{
    NSString *path = [NSString stringWithFormat:ARSaleURLFormat, saleID];
    NSMutableURLRequest *req = [self requestWithMethod:@"GET" path:path parameters:nil];
    req.cachePolicy = NSURLRequestReloadIgnoringCacheData;
    return req;
}

+ (NSURLRequest *)orderedSetsWithOwnerType:(NSString *)ownerType andID:(NSString *)ownerID
{
    ownerType = ownerType ?: @"";
    NSDictionary *params = @{ @"owner_type" : ownerType,
                              @"owner_id" : ownerID,
                              @"sort" : @"key",
                              @"mobile" : @"true",
                              @"published" : @"true" };
    return [self requestWithMethod:@"GET" path:AROrderedSetsURL parameters:params];
}

+ (NSURLRequest *)orderedSetsWithKey:(NSString *)key
{
    NSDictionary *params = @{ @"key" : key,
                              @"sort" : @"key",
                              @"mobile" : @"true",
                              @"published" : @"true" };
    return [self requestWithMethod:@"GET" path:AROrderedSetsURL parameters:params];
}

+ (NSURLRequest *)orderedSetItems:(NSString *)orderedSetID
{
    NSString *url = [NSString stringWithFormat:AROrderedSetItemsURLFormat, orderedSetID];
    return [self requestWithMethod:@"GET" path:url parameters:nil];
}

+ (NSURLRequest *)orderedSetItems:(NSString *)orderedSetID atPage:(NSInteger)page
{
    NSString *url = [NSString stringWithFormat:AROrderedSetItemsURLFormat, orderedSetID];
    return [self requestWithMethod:@"GET" path:url parameters:@{ @"page" : @(page),
                                                                 @"size" : @10 }];
}

+ (NSURLRequest *)newSystemTimeRequest
{
    return [self requestWithMethod:@"GET" path:ARSystemTimeURL parameters:nil];
}

+ (NSURLRequest *)newPendingOrderWithArtworkID:(NSString *)artworkID editionSetID:(NSString *)editionSetID
{
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithDictionary:@{
        @"artwork_id" : artworkID,
        @"replace_order" : @YES,
        @"session_id" : [[NSUUID UUID] UUIDString] // TODO: preserve across session?
    }];
    if (editionSetID != nil) {
        [params addEntriesFromDictionary:@{ @"edition_set_id" : editionSetID }];
    }

    return [self requestWithMethod:@"POST" path:ARCreatePendingOrderURL parameters:params];
}

+ (NSURLRequest *)newRequestOutbidNotificationRequest
{
    NSAssert(FALSE, @"STUB");
    return [self requestWithMethod:@"GET" path:@"/api/v1/" parameters:nil];
}

+ (NSURLRequest *)newRequestForBlankPage
{
    NSURL *pageURL = [[ARRouter baseWebURL] URLByAppendingPathComponent:@"/dev/blank"];
    return [NSURLRequest requestWithURL:pageURL];
}


@end
