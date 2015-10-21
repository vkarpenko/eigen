#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <Specta/Specta.h>
#import "SpectaDSL+Sleep.h"
#import <Expecta/Expecta.h>
#import <Expecta+Snapshots/EXPMatchers+FBSnapshotTest.h>
#import <OHHTTPStubs/OHHTTPStubs.h>
#import <OCMock/OCMock.h>

#import "ARTestContext.h"
#import "ARExpectaExtensions.h"
#import "UIViewController+Testing.h"
#import "OHHTTPStubs+Artsy.h"
#import "MTLModel+JSON.h"
#import "MTLModel+Dictionary.h"

@interface ARTestHelper : NSObject <UIApplicationDelegate>
@end


@interface ARTestViewHostingWindow : UIWindow
+ (void)hostView:(UIView *)view;
@end
