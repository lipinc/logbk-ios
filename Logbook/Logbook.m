//
// Logbook.m
// Logbook
//
// Copyright 2013-2014 pLucky, Inc.
// Copyright 2012 Mixpanel
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <arpa/inet.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <sys/socket.h>
#include <sys/sysctl.h>

#import <CommonCrypto/CommonDigest.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import "LBCJSONDataSerializer.h"
#import "Logbook.h"
#import "NSData+LBBase64.h"

#define VERSION @"1.0.0"

#ifndef IFT_ETHER
#define IFT_ETHER 0x6 // ethernet CSMACD
#endif

#ifdef LOGBOOK_LOG
#define LogbookLog(...) NSLog(__VA_ARGS__)
#else
#define LogbookLog(...)
#endif

#ifdef LOGBOOK_DEBUG
#define LogbookDebug(...) NSLog(__VA_ARGS__)
#else
#define LogbookDebug(...)
#endif

static NSString * const LB_TIME_KEY = @"time";
static NSString * const LB_EVENT_KEY = @"event";
static NSString * const LB_RAND_USER_KEY = @"randUser";
static NSString * const LB_USER_KEY = @"user";
static NSString * const LB_LIB_NAME = @"libName";
static NSString * const LB_LIB_VERSION = @"libVersion";
static int const MAX_EVENT_NAME = 32;
// Followings are better to be configured.
static NSString * const TIME_SPENT_EVENT = @"_timeSpent";
static NSTimeInterval const USAGE_TIMER_INTERVAL = 10;

@interface Logbook ()

// re-declare internally as readwrite
@property(nonatomic,copy) NSString *randUser;
@property(nonatomic,copy) NSString *user;
@property(nonatomic,copy)   NSString *apiToken;
@property(nonatomic,retain) NSTimer *timer;
@property(nonatomic,retain) NSMutableArray *eventsQueue;
@property(nonatomic,retain) NSArray *eventsBatch;
@property(nonatomic,retain) NSURLConnection *eventsConnection;
@property(nonatomic,retain) NSMutableData *eventsResponseData;
@property(nonatomic,retain) NSDateFormatter *dateFormatter;
@property(nonatomic,assign) BOOL projectDeleted;
@property(nonatomic,retain) NSTimer *usageTimer;

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 40000
@property(nonatomic,assign) UIBackgroundTaskIdentifier taskId;
#endif

- (void)trackAccess;
@end

@implementation Logbook

static Logbook *sharedInstance = nil;

#pragma mark * Utility

+ (NSString *)randomAppUserId
{
    return [[NSUUID UUID] UUIDString];
}

+ (BOOL)isMatch:(NSString *)name regex:(NSRegularExpression *)regex inSize:(NSUInteger)maxLength {
    if (name == nil) {
        return NO;
    }
    
    NSTextCheckingResult *match = [regex firstMatchInString:name options:0 range:NSMakeRange(0, name.length)];
    if (match.numberOfRanges == 1) {
        return name.length > 0 && name.length <= maxLength;
    } else {
        return NO;
    }
}

+ (BOOL)isValidEventName: (NSString *)name {
    static NSRegularExpression *regex = nil;
    @synchronized(self) {
        if (regex == nil) {
            NSError *error = nil;
            regex = [[NSRegularExpression regularExpressionWithPattern:@"^[A-Z][A-Z0-9._-]+$"
                                                               options:NSRegularExpressionCaseInsensitive
                                                                 error:&error] retain];
            if (error != nil) {
                NSLog(@"Error compiling regex: %@", [error localizedDescription]);
            }
        }
    }
    return [self isMatch:name regex:regex inSize:MAX_EVENT_NAME];
}

+ (BOOL)isValidSystemEventName: (NSString *)name {
    static NSRegularExpression *regex = nil;
    @synchronized(self) {
        if (regex == nil) {
            NSError *error = nil;
            regex = [[NSRegularExpression regularExpressionWithPattern:@"^_[A-Z][A-Z0-9._-]+$"
                                                               options:NSRegularExpressionCaseInsensitive
                                                                 error:&error] retain];
            if (error != nil) {
                NSLog(@"Error compiling regex: %@", [error localizedDescription]);
            }
        }
    }
    return [self isMatch:name regex:regex inSize:MAX_EVENT_NAME];
}

#pragma mark * Device info

+ (NSDictionary *)deviceInfoProperties
{
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];

    UIDevice *device = [UIDevice currentDevice];

    [properties setValue:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] forKey:@"app_version"];
    [properties setValue:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] forKey:@"app_release"];

    [properties setValue:@"Apple" forKey:@"manufacturer"];
    [properties setValue:[device systemName] forKey:@"os"];
    [properties setValue:[device systemVersion] forKey:@"os_version"];
    [properties setValue:[Logbook deviceModel] forKey:@"model"];

    CGSize size = [UIScreen mainScreen].bounds.size;
    [properties setValue:[NSNumber numberWithInt:(int)size.height] forKey:@"screen_height"];
    [properties setValue:[NSNumber numberWithInt:(int)size.width] forKey:@"screen_width"];

    [properties setValue:[NSNumber numberWithBool:[Logbook wifiAvailable]] forKey:@"wifi"];

    CTTelephonyNetworkInfo *networkInfo = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = [networkInfo subscriberCellularProvider];
    [networkInfo release];

    if (carrier.carrierName.length) {
        [properties setValue:carrier.carrierName forKey:@"carrier"];
    }

    return [NSDictionary dictionaryWithDictionary:properties];
}

+ (NSString *)deviceModel
{
    size_t size;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    
    char *answer = malloc(size);
    sysctlbyname("hw.machine", answer, &size, NULL, 0);
    
    NSString *results = [NSString stringWithCString:answer encoding:NSUTF8StringEncoding];
    
    free(answer);
    return results;
}

+ (BOOL)wifiAvailable
{
    struct sockaddr_in sockAddr;
    bzero(&sockAddr, sizeof(sockAddr));
    sockAddr.sin_len = sizeof(sockAddr);
    sockAddr.sin_family = AF_INET;

    SCNetworkReachabilityRef nrRef = SCNetworkReachabilityCreateWithAddress(NULL, (struct sockaddr *)&sockAddr);
    SCNetworkReachabilityFlags flags;
    BOOL didRetrieveFlags = SCNetworkReachabilityGetFlags(nrRef, &flags);
    if (!didRetrieveFlags) {
        LogbookDebug(@"%@ unable to fetch the network reachablity flags", self);
    }

    CFRelease(nrRef);

    if (!didRetrieveFlags || (flags & kSCNetworkReachabilityFlagsReachable) != kSCNetworkReachabilityFlagsReachable) {
        // unable to connect to a network (no signal or airplane mode activated)
        return NO;
    }

    if ((flags & kSCNetworkReachabilityFlagsIsWWAN) == kSCNetworkReachabilityFlagsIsWWAN) {
        // only a cellular network connection is available.
        return NO;
    }

    return YES;
}

+ (BOOL)inBackground
{
    BOOL inBg = NO;
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 40000
    inBg = [[UIApplication sharedApplication] applicationState] == UIApplicationStateBackground;
#endif
    if (inBg) {
        LogbookDebug(@"%@ in background", self);
    }
    return inBg;
}

#pragma mark * Encoding/decoding utilities

+ (NSData *)JSONSerializeObject:(id)obj
{
    id coercedObj = [Logbook JSONSerializableObjectForObject:obj];

    LBCJSONDataSerializer *serializer = [LBCJSONDataSerializer serializer];
    NSError *error = nil;
    NSData *data = nil;
    @try {
        data = [serializer serializeObject:coercedObj error:&error];
    }
    @catch (NSException *exception) {
        NSLog(@"%@ exception encoding api data: %@", self, exception);
    }
    if (error) {
        NSLog(@"%@ error encoding api data: %@", self, error);
    }
    return data;
}

+ (id)JSONSerializableObjectForObject:(id)obj
{
    // valid json types
    if ([obj isKindOfClass:[NSString class]] ||
        [obj isKindOfClass:[NSNumber class]] ||
        [obj isKindOfClass:[NSNull class]]) {
        return obj;
    }

    // recurse on containers
    if ([obj isKindOfClass:[NSArray class]]) {
        NSMutableArray *a = [NSMutableArray array];
        for (id i in obj) {
            [a addObject:[Logbook JSONSerializableObjectForObject:i]];
        }
        return [NSArray arrayWithArray:a];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *d = [NSMutableDictionary dictionary];
        for (id key in obj) {
            NSString *stringKey;
            if (![key isKindOfClass:[NSString class]]) {
                stringKey = [key description];
                NSLog(@"%@ warning: property keys should be strings. got: %@. coercing to: %@", self, [key class], stringKey);
            } else {
                stringKey = [NSString stringWithString:key];
            }
            id v = [Logbook JSONSerializableObjectForObject:[obj objectForKey:key]];
            [d setObject:v forKey:stringKey];
        }
        return [NSDictionary dictionaryWithDictionary:d];
    }

    // some common cases
    if ([obj isKindOfClass:[NSDate class]]) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss"];
        [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
        NSString *s = [formatter stringFromDate:obj];
        [formatter release];
        return s;
    } else if ([obj isKindOfClass:[NSURL class]]) {
        return [obj absoluteString];
    }

    // default to sending the object's description
    NSString *s = [obj description];
    NSLog(@"%@ warning: property values should be valid json types. got: %@. coercing to: %@", self, [obj class], s);
    return s;
}

+ (NSString *)encodeAPIData:(NSArray *)array
{
    NSString *b64String = @"";
    NSData *data = [Logbook JSONSerializeObject:array];
    if (data) {
        b64String = [data lb_base64EncodedString];
        b64String = (id)CFURLCreateStringByAddingPercentEscapes(kCFAllocatorDefault,
                                                                (CFStringRef)b64String,
                                                                NULL,
                                                                CFSTR("!*'();:@&=+$,/?%#[]"),
                                                                kCFStringEncodingUTF8);
    }
    return [b64String autorelease];
}

+ (void)assertPropertyTypes:(NSDictionary *)properties
{
    for (id k in properties) {
        NSAssert([k isKindOfClass: [NSString class]], @"%@ property keys must be NSString. got: %@ %@", self, [k class], k);
        // would be convenient to do: id v = [properties objectForKey:k]; ..but, when the NSAssert's are stripped out in release, it becomes an unused variable error
        NSAssert([[properties objectForKey:k] isKindOfClass:[NSString class]] ||
                 [[properties objectForKey:k] isKindOfClass:[NSNumber class]] ||
                 [[properties objectForKey:k] isKindOfClass:[NSNull class]] ||
                 [[properties objectForKey:k] isKindOfClass:[NSDate class]] ||
                 [[properties objectForKey:k] isKindOfClass:[NSURL class]],
                 @"%@ property values must be NSString, NSNumber, NSNull, NSDate or NSURL. got: %@ %@", self, [[properties objectForKey:k] class], [properties objectForKey:k]);
    }
}

#pragma mark * Initializiation

+ (instancetype)sharedInstanceWithCode:(NSString *)apiToken
{
    @synchronized(self) {
        if (sharedInstance == nil) {
            sharedInstance = [[super alloc] initWithCode:apiToken andFlushInterval:60];
        }
        return sharedInstance;
    }
}

+ (instancetype)sharedInstance
{
    @synchronized(self) {
        if (sharedInstance == nil) {
            NSLog(@"%@ warning sharedInstance called before sharedInstanceWithCode:", self);
        }
        return sharedInstance;
    }
}

- (id)initWithCode:(NSString *)apiToken andFlushInterval:(NSUInteger)flushInterval
{
    if (apiToken == nil) {
        apiToken = @"";
    }
    if ([apiToken length] == 0) {
        NSLog(@"%@ warning empty api token", self);
    }
    if (self = [self init]) {
        self.dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
        [self.dateFormatter  setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
        self.dateFormatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
        self.apiToken = apiToken;
        self.flushInterval = flushInterval;
        self.flushOnBackground = YES;
        self.showNetworkActivityIndicator = YES;
        self.sendDeviceInfo = NO;
        self.serverURL = @"https://tracker.logbk.net";
        
        self.projectDeleted = NO;

        self.eventsQueue = [NSMutableArray array];
        
        [self addApplicationObservers];
        
        [self unarchive];
        
        if (self.randUser == nil || [self.randUser length] == 0) {
            self.randUser = [Logbook randomAppUserId];
            LogbookLog(@"Assigned randomly generated app user id %@", self.randUser);
            [self archiveProperties];
        }
    }
    return self;
}

#pragma mark * Identity

- (void)identify:(NSString *)appUserId
{
    @synchronized(self) {
        self.user = appUserId;
        if ([Logbook inBackground]) {
            [self archiveEvents];
        }
    }
}

#pragma mark * Tracking

- (void)trackInternal:(NSString *)event
{
    @synchronized(self) {
        if (self.projectDeleted) {
            LogbookLog(@"%@ project has been deleted. skipped.", self);
            return;
        }
        
        NSDate *now = [NSDate date];
        NSMutableDictionary *e = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     @"logbk-ios", LB_LIB_NAME,
                                     VERSION, LB_LIB_VERSION,
                                     event, LB_EVENT_KEY,
                                     [self.dateFormatter stringFromDate:now], LB_TIME_KEY,
                                     self.randUser, LB_RAND_USER_KEY,
                                     nil];
        // user can't be set by dictionaryWithObjectsAndKeys: because it's nil-able.
        if (self.user != nil) {
            [e setObject:self.user forKey:LB_USER_KEY];
        }
        if (self.sendDeviceInfo) {
            [e addEntriesFromDictionary:[Logbook deviceInfoProperties]];
        }
        
        LogbookLog(@"%@ queueing event: %@", self, e);
        [self.eventsQueue addObject:e];
        if ([Logbook inBackground]) {
            [self archiveEvents];
        }
    }
}

/**
 * Track a system event.
 * Internal API.
 */
- (void)trackSystem:(NSString *)event {
    if (![Logbook isValidSystemEventName:event]) {
        NSLog(@"%@ track called with an invalid system event parameter %@. Skipping.", self, event);
        return;
    }
    [self trackInternal:event];
}

- (void)track:(NSString *)event {
    if (![Logbook isValidEventName:event]) {
        NSLog(@"%@ track called with an invalid event parameter %@. Skipping.", self, event);
        return;
    }
    [self trackInternal:event];
}

- (void)trackAccess {
    [self trackSystem:@"_access"];
}

- (void)reset
{
    @synchronized(self) {
        self.randUser = [Logbook randomAppUserId];
        self.user = nil;
        self.eventsQueue = [NSMutableArray array];
        self.projectDeleted = NO;
        [self archive];
    }
}

#pragma mark * Network control

- (void)setFlushInterval:(NSUInteger)interval
{
    @synchronized(self) {
        _flushInterval = interval;
        [self startFlushTimer];
    }
}

- (void)startFlushTimer
{
    @synchronized(self) {
        [self stopFlushTimer];
        if (self.flushInterval > 0) {
            self.timer = [NSTimer scheduledTimerWithTimeInterval:self.flushInterval
                                                          target:self
                                                        selector:@selector(flush)
                                                        userInfo:nil
                                                         repeats:YES];
            LogbookDebug(@"%@ started flush timer: %@", self, self.timer);
        }
    }
}

- (void)stopFlushTimer
{
    @synchronized(self) {
        if (self.timer) {
            [self.timer invalidate];
            LogbookDebug(@"%@ stopped flush timer: %@", self, self.timer);
        }
        self.timer = nil;
    }
}

- (void)flush
{
    // If the app is currently in the background but Mixpanel has not requested
    // to run a background task, the flush will be cut short. This can happen
    // when the app forces a flush from within its own background task.
    if ([Logbook inBackground] && self.taskId == UIBackgroundTaskInvalid) {
        [self flushInBackgroundTask];
        return;
    }

    @synchronized(self) {
        if ([self.delegate respondsToSelector:@selector(logbookWillFlush:)]) {
            if (![self.delegate logbookWillFlush:self]) {
                LogbookDebug(@"%@ delegate deferred flush", self);
                return;
            }
        }
        LogbookDebug(@"%@ flushing data to %@", self, self.serverURL);
        [self flushEvents];
    }
}

- (void)flushInBackgroundTask
{
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 40000
    @synchronized(self) {
        if ([[UIApplication sharedApplication] respondsToSelector:@selector(beginBackgroundTaskWithExpirationHandler:)] &&
            [[UIApplication sharedApplication] respondsToSelector:@selector(endBackgroundTask:)]) {

            self.taskId = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
                LogbookDebug(@"%@ flush background task %lu cut short", self, (unsigned long)self.taskId);
                [self cancelFlush];
                [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
                self.taskId = UIBackgroundTaskInvalid;
            }];

            LogbookDebug(@"%@ starting flush background task %lu", self, (unsigned long)self.taskId);
            [self flush];

            // connection callbacks end this task by calling endBackgroundTaskIfComplete
        }
    }
#endif
}

- (void)flushEvents
{
    if ([self.eventsQueue count] == 0) {
        LogbookDebug(@"%@ no events to flush", self);
        return;
    } else if (self.eventsConnection != nil) {
        LogbookDebug(@"%@ events connection already open", self);
        return;
    } else if ([self.eventsQueue count] > 50) {
        self.eventsBatch = [self.eventsQueue subarrayWithRange:NSMakeRange(0, 50)];
    } else {
        self.eventsBatch = [NSArray arrayWithArray:self.eventsQueue];
    }
    
    NSString *data = [Logbook encodeAPIData:self.eventsBatch];
    NSString *postBody = [NSString stringWithFormat:@"data=%@", data];
    
    LogbookDebug(@"%@ flushing %lu of %lu queued events: %@", self, (unsigned long)self.eventsBatch.count, (unsigned long)self.eventsQueue.count, self.eventsQueue);

    NSString *endpoint = [@"/track/" stringByAppendingString:self.apiToken];
    self.eventsConnection = [self apiConnectionWithEndpoint:endpoint andBody:postBody];

    [self updateNetworkActivityIndicator];
}

- (void)cancelFlush
{
    if (self.eventsConnection == nil) {
        LogbookDebug(@"%@ no events connection to cancel", self);
    } else {
        LogbookDebug(@"%@ cancelling events connection", self);
        [self.eventsConnection cancel];
        self.eventsConnection = nil;
    }
}

- (void)updateNetworkActivityIndicator
{
    @synchronized(self) {
        BOOL visible = self.showNetworkActivityIndicator && self.eventsConnection;
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:visible];
    }
}

#pragma mark * Persistence

- (NSString *)filePathForData:(NSString *)data
{
    NSString *filename = [NSString stringWithFormat:@"logbook-%@-%@.plist", self.apiToken, data];
    return [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) lastObject]
            stringByAppendingPathComponent:filename];
}

- (NSString *)eventsFilePath
{
    return [self filePathForData:@"events"];
}

- (NSString *)propertiesFilePath
{
    return [self filePathForData:@"properties"];
}

- (void)archive
{
    @synchronized(self) {
        [self archiveEvents];
        [self archiveProperties];
    }
}

- (void)archiveEvents
{
    @synchronized(self) {
        NSString *filePath = [self eventsFilePath];
        LogbookDebug(@"%@ archiving events data to %@: %@", self, filePath, self.eventsQueue);
        if (![NSKeyedArchiver archiveRootObject:self.eventsQueue toFile:filePath]) {
            NSLog(@"%@ unable to archive events data", self);
        }
    }
}

- (void)archiveProperties
{
    @synchronized(self) {
        NSString *filePath = [self propertiesFilePath];
        NSMutableDictionary *properties = [NSMutableDictionary dictionary];
        [properties setValue:self.randUser forKey:@"randUser"];
        [properties setValue:self.user forKey:@"user"];
        [properties setValue:[NSNumber numberWithBool:self.projectDeleted] forKey:@"projectDeleted"];
        LogbookDebug(@"%@ archiving properties data to %@: %@", self, filePath, properties);
        if (![NSKeyedArchiver archiveRootObject:properties toFile:filePath]) {
            NSLog(@"%@ unable to archive properties data", self);
        }
    }
}

- (void)unarchive
{
    @synchronized(self) {
        [self unarchiveEvents];
        [self unarchiveProperties];
    }
}

- (void)unarchiveEvents
{
    NSString *filePath = [self eventsFilePath];
    @try {
        self.eventsQueue = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
        LogbookDebug(@"%@ unarchived events data: %@", self, self.eventsQueue);
    }
    @catch (NSException *exception) {
        NSLog(@"%@ unable to unarchive events data, starting fresh", self);
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
        self.eventsQueue = nil;
    }
    if (!self.eventsQueue) {
        self.eventsQueue = [NSMutableArray array];
    }
}

- (void)unarchiveProperties
{
    NSString *filePath = [self propertiesFilePath];
    NSDictionary *properties = nil;
    @try {
        properties = [NSKeyedUnarchiver unarchiveObjectWithFile:filePath];
        LogbookDebug(@"%@ unarchived properties data: %@", self, properties);
    }
    @catch (NSException *exception) {
        NSLog(@"%@ unable to unarchive properties data, starting fresh", self);
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    }
    if (properties) {
        self.randUser = [properties objectForKey:@"randUser"];
        self.user = [properties objectForKey:@"user"];
        self.projectDeleted = [(NSNumber *)[properties objectForKey:@"projectDeleted"] boolValue];
    }
}

#pragma mark * Application lifecycle events

- (void)addApplicationObservers
{
    LogbookDebug(@"%@ adding application observers", self);
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillTerminate:)
                               name:UIApplicationWillTerminateNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationWillResignActive:)
                               name:UIApplicationWillResignActiveNotification
                             object:nil];
    [notificationCenter addObserver:self
                           selector:@selector(applicationDidBecomeActive:)
                               name:UIApplicationDidBecomeActiveNotification
                             object:nil];
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 40000
    if ([[UIDevice currentDevice] respondsToSelector:@selector(isMultitaskingSupported)] && &UIBackgroundTaskInvalid) {
        self.taskId = UIBackgroundTaskInvalid;
        if (&UIApplicationDidEnterBackgroundNotification) {
            [notificationCenter addObserver:self
                                   selector:@selector(applicationDidEnterBackground:)
                                       name:UIApplicationDidEnterBackgroundNotification
                                     object:nil];
        }
        if (&UIApplicationWillEnterForegroundNotification) {
            [notificationCenter addObserver:self
                                   selector:@selector(applicationWillEnterForeground:)
                                       name:UIApplicationWillEnterForegroundNotification
                                     object:nil];
        }
    }
#endif
}

- (void)removeApplicationObservers
{
    LogbookDebug(@"%@ removing application observers", self);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    LogbookDebug(@"%@ application did become active", self);
    @synchronized(self) {
        [self startFlushTimer];
        [self trackAccess];
        self.usageTimer = [NSTimer scheduledTimerWithTimeInterval:USAGE_TIMER_INTERVAL
                                                           target:self
                                                         selector:@selector(usageTimerFired:)
                                                         userInfo:nil
                                                          repeats:NO];
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    LogbookDebug(@"%@ application will resign active", self);
    @synchronized(self) {
        [self stopFlushTimer];
        [self.usageTimer invalidate];
        self.usageTimer = nil;
    }
}

- (void)applicationDidEnterBackground:(NSNotificationCenter *)notification
{
    LogbookDebug(@"%@ did enter background", self);

    @synchronized(self) {
        if (self.flushOnBackground) {
            [self flushInBackgroundTask];
        }
    }
}

- (void)applicationWillEnterForeground:(NSNotificationCenter *)notification
{
    LogbookDebug(@"%@ will enter foreground", self);
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 40000
    @synchronized(self) {

        if (&UIBackgroundTaskInvalid) {
            if (self.taskId != UIBackgroundTaskInvalid) {
                [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
            }
            self.taskId = UIBackgroundTaskInvalid;
        }
        [self cancelFlush];
        [self updateNetworkActivityIndicator];
    }
#endif
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    LogbookDebug(@"%@ application will terminate", self);
    @synchronized(self) {
        [self archive];
    }
}

- (void)endBackgroundTaskIfComplete
{
#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 40000
    // if the os version allows background tasks, the app supports them, and we're in one, end it
    @synchronized(self) {

        if (&UIBackgroundTaskInvalid && [[UIApplication sharedApplication] respondsToSelector:@selector(endBackgroundTask:)] &&
            self.taskId != UIBackgroundTaskInvalid && self.eventsConnection == nil) {
            LogbookDebug(@"%@ ending flush background task %lu", self, (unsigned long)self.taskId);
            [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
            self.taskId = UIBackgroundTaskInvalid;
        }
    }
#endif
}


#pragma mark * Usage timer callback

- (void)usageTimerFired:(NSTimer *)timer {
    LogbookDebug(@"Usage timer fired");
    [self trackSystem:TIME_SPENT_EVENT];
}

#pragma mark * NSURLConnection callbacks

- (NSURLConnection *)apiConnectionWithEndpoint:(NSString *)endpoint andBody:(NSString *)body
{
    NSURL *url = [NSURL URLWithString:[self.serverURL stringByAppendingString:endpoint]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    LogbookDebug(@"%@ http request: %@?%@", self, [self.serverURL stringByAppendingString:endpoint], body);
    return [NSURLConnection connectionWithRequest:request delegate:self];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response
{
    LogbookDebug(@"%@ http status code: %ld", self, (long)[response statusCode]);
    if ([response statusCode] != 200) {
        NSLog(@"%@ http error: %@", self, [NSHTTPURLResponse localizedStringForStatusCode:[response statusCode]]);
    } else if (connection == self.eventsConnection) {
        self.eventsResponseData = [NSMutableData data];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (connection == self.eventsConnection) {
        [self.eventsResponseData appendData:data];
    }
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    @synchronized(self) {
        NSLog(@"%@ network failure: %@", self, error);
        if (connection == self.eventsConnection) {
            self.eventsBatch = nil;
            self.eventsResponseData = nil;
            self.eventsConnection = nil;
            [self archiveEvents];
        }

        [self updateNetworkActivityIndicator];
        
        [self endBackgroundTaskIfComplete];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    @synchronized(self) {
        LogbookDebug(@"%@ http response finished loading", self);
        if (connection == self.eventsConnection) {
            NSString *response = [[NSString alloc] initWithData:self.eventsResponseData encoding:NSUTF8StringEncoding];
            if ([response isEqualToString:@"__DELETED__"]) {
                LogbookLog(@"Project is deleted. %@", self);
                self.projectDeleted = YES;
                [self archiveProperties];
            } else if ([response intValue] == 0) {
                NSLog(@"%@ track api error: %@", self, response);
            }
            [response release];

            [self.eventsQueue removeObjectsInArray:self.eventsBatch];
            [self archiveEvents];

            self.eventsBatch = nil;
            self.eventsResponseData = nil;
            self.eventsConnection = nil;

        }
        
        [self updateNetworkActivityIndicator];
        
        [self endBackgroundTaskIfComplete];
    }
}

#pragma mark * NSObject

- (NSString *)description
{
    return [NSString stringWithFormat:@"<Logbook: %p %@>", self, self.apiToken];
}

- (void)dealloc
{
    [self stopFlushTimer];
    [self removeApplicationObservers];
    
    self.randUser = nil;
    self.user = nil;
    self.serverURL = nil;
    self.delegate = nil;
    
    self.apiToken = nil;
    self.timer = nil;
    self.eventsQueue = nil;
    self.eventsBatch = nil;
    self.eventsConnection = nil;
    self.eventsResponseData = nil;
    self.usageTimer = nil;
    
    [super dealloc];
}

@end
