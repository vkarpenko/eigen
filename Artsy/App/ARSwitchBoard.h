/**
 The Switchboard is the internal API for loading different native views
  it does this mostly by using either an internal Sinatra like-router
*/

NS_ASSUME_NONNULL_BEGIN


@interface ARSwitchBoard : NSObject

/// A shared instance object
+ (instancetype)sharedInstance;

/// Allows other objects to hook into the switchboard
- (void)registerPathCallbackAtPath:(NSString *)path callback:(id _Nullable (^)(NSDictionary *_Nullable parameters))callback;

/// Load a path relative to the baseURL through the router
- (UIViewController *)loadPath:(NSString *)path;

///  Load a path relative to the baseURL with an optional fair object
- (UIViewController *)loadPath:(NSString *)path fair:(Fair *_Nullable)fair;

/// Send an URL through the router
- (UIViewController *)loadURL:(NSURL *)url;

/// Send an URL through the router with an optional fair object
- (UIViewController *)loadURL:(NSURL *)url fair:(Fair *_Nullable)fair;

/// Can the Switchboard handle a URL?
- (BOOL)canRouteURL:(NSURL *)url;

/// Converts a path into a full URL based on staging/prod + device
- (NSURL *)resolveRelativeUrl:(NSString *)path;

/// Shows the View Controller in Eigen
- (void)presentViewController:(UIViewController *)controller;

@end

NS_ASSUME_NONNULL_END
