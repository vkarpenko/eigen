#import "ARMenuAwareViewController.h"

#import <FODFormKit/FODFormViewController.h>

@class User;

@interface ARUserSettingsViewController : FODFormViewController <ARMenuAwareViewController>

- (instancetype)initWithUser:(User *)user;

@end
