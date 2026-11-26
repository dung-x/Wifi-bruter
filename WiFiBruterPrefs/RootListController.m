#import "RootListController.h"

@implementation RootListController

- (id)specifiers {
    if (!_specifiers) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"WiFiBruterPrefs" ofType:@"plist"];
        _specifiers = [NSArray arrayWithContentsOfFile:path];
    }
    return _specifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

@end
