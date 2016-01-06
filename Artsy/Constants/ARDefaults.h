extern NSString *const ARUserIdentifierDefault;
extern NSString *const ARUseStagingDefault;

extern NSString *const AROAuthTokenDefault;
extern NSString *const AROAuthTokenExpiryDateDefault;

extern NSString *const ARXAppTokenKeychainKey;
extern NSString *const ARXAppTokenExpiryDateDefault;

#pragma mark -
#pragma mark onboarding

extern NSString *const AROnboardingSkipPersonalizeDefault;
extern NSString *const AROnboardingSkipCollectorLevelDefault;
extern NSString *const AROnboardingSkipPriceRangeDefault;
extern NSString *const AROnboardingPromptThresholdDefault;

#pragma mark -
#pragma mark Things we wanna trigger server-side

extern NSString *const ARShowAuctionResultsButtonDefault;


@interface ARDefaults : NSObject
/// Registers the standard eigen defaults on sharedDefaults
+ (void)setup;
/// Registers the standard eigen on the passed in defaults
+ (void)setup:(NSUserDefaults *)defaults;

/// Resets the sharedDefaults
+ (void)resetDefaults;
/// Resets the passed in defaults
+ (void)resetDefaults:(NSUserDefaults *)defaults;
@end
