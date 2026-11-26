#import "RootListController.h"

@implementation RootListController

- (id)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistNamed:@"WiFiBruterPrefs" target:self];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

@end
