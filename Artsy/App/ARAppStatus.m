#import "ARAppStatus.h"


@implementation ARAppStatus

// http://stackoverflow.com/questions/26081543/how-to-tell-at-runtime-whether-an-ios-app-is-running-through-a-testflight-beta-i

+ (BOOL)isBetaOrDev
{
#if TARGET_IPHONE_SIMULATOR
    return YES;
#endif

    static BOOL isBetaOrDev = NO;
    static dispatch_once_t onceToken = 0;
    dispatch_once(&onceToken, ^{
        NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
        NSString *receiptURLString = [receiptURL path];
        isBetaOrDev = [receiptURLString rangeOfString:@"sandboxReceipt"].location != NSNotFound;
    });
    return isBetaOrDev;
}

+ (BOOL)isDemo
{
    return ARIsRunningInDemoMode;
}

@end
