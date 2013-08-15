//
// Slash7.m
// Slash7
//
// Copyright 2013 pLucky, Inc.
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

#import <AdSupport/ASIdentifierManager.h>
#import <CommonCrypto/CommonDigest.h>
#import <CoreTelephony/CTCarrier.h>
#import <CoreTelephony/CTTelephonyNetworkInfo.h>
#import <SystemConfiguration/SystemConfiguration.h>

#import "S7CJSONDataSerializer.h"
#import "Slash7.h"
#import "NSData+S7Base64.h"
#import "S7ODIN.h"

#define VERSION @"0.1.0"

#ifndef IFT_ETHER
#define IFT_ETHER 0x6 // ethernet CSMACD
#endif

#ifdef SLASH7_LOG
#define Slash7Log(...) NSLog(__VA_ARGS__)
#else
#define Slash7Log(...)
#endif

#ifdef SLASH7_DEBUG
#define Slash7Debug(...) NSLog(__VA_ARGS__)
#else
#define Slash7Debug(...)
#endif

static NSString * const S7_EVENT_NAME_KEY = @"_event_name";
static NSString * const S7_EVENT_PARAMS_KEY = @"_event_params";
static NSString * const S7_APP_USER_ID_KEY = @"_app_user_id";
static NSString * const S7_APP_USER_ID_TYPE_KEY = @"_app_user_id_type";
static NSString * const S7_TIME_KEY = @"_time";

@interface Slash7 ()

// re-declare internally as readwrite
@property(nonatomic,copy) NSString *appUserId;
@property(nonatomic,copy) NSString *appUserIdType;
@property(nonatomic,copy)   NSString *apiToken;
@property(nonatomic,retain) NSMutableDictionary *superProperties;
@property(nonatomic,retain) NSTimer *timer;
@property(nonatomic,retain) NSMutableArray *eventsQueue;
@property(nonatomic,retain) NSArray *eventsBatch;
@property(nonatomic,retain) NSArray *peopleBatch;
@property(nonatomic,retain) NSURLConnection *eventsConnection;
@property(nonatomic,retain) NSURLConnection *peopleConnection;
@property(nonatomic,retain) NSMutableData *eventsResponseData;
@property(nonatomic,retain) NSMutableData *peopleResponseData;
@property(nonatomic,retain) NSDateFormatter *dateFormatter;

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 40000
@property(nonatomic,assign) UIBackgroundTaskIdentifier taskId;
#endif

@end

@implementation Slash7

static Slash7 *sharedInstance = nil;

#pragma mark * AppUserIdType

+ (NSString *)appUserIdTypeString:(S7AppUserIdType)type
{
    switch (type) {
        case S7_USER_ID_TYPE_APP:
            return @"app";
        case S7_USER_ID_TYPE_FACEBOOK:
            return @"facebook";
        case S7_USER_ID_TYPE_TWITTER:
            return @"twitter";
        case S7_USER_ID_TYPE_GREE:
            return @"gree";
        case S7_USER_ID_TYPE_MOBAGE:
            return @"mobage";
        case S7_USER_ID_TYPE_COOKIE:
            return @"cookie";
        default:
            NSAssert(false, @"Unknown S7AppUserIdType: %d", type);
            return nil;
    }
}


#pragma mark * Device info

+ (NSDictionary *)deviceInfoProperties
{
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];

    UIDevice *device = [UIDevice currentDevice];

    [properties setValue:@"iphone" forKey:@"$lib"];
    [properties setValue:VERSION forKey:@"$lib_version"];

    [properties setValue:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"] forKey:@"$app_version"];
    [properties setValue:[[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"] forKey:@"$app_release"];

    [properties setValue:@"Apple" forKey:@"$manufacturer"];
    [properties setValue:[device systemName] forKey:@"$os"];
    [properties setValue:[device systemVersion] forKey:@"$os_version"];
    [properties setValue:[Slash7 deviceModel] forKey:@"$model"];

    CGSize size = [UIScreen mainScreen].bounds.size;
    [properties setValue:[NSNumber numberWithInt:(int)size.height] forKey:@"$screen_height"];
    [properties setValue:[NSNumber numberWithInt:(int)size.width] forKey:@"$screen_width"];

    [properties setValue:[NSNumber numberWithBool:[Slash7 wifiAvailable]] forKey:@"$wifi"];

    CTTelephonyNetworkInfo *networkInfo = [[CTTelephonyNetworkInfo alloc] init];
    CTCarrier *carrier = [networkInfo subscriberCellularProvider];
    [networkInfo release];

    if (carrier.carrierName.length) {
        [properties setValue:carrier.carrierName forKey:@"$carrier"];
    }

    if (NSClassFromString(@"ASIdentifierManager")) {
        [properties setValue:ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString forKey:@"$ios_ifa"];
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
        Slash7Debug(@"%@ unable to fetch the network reachablity flags", self);
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
        Slash7Debug(@"%@ in background", self);
    }
    return inBg;
}

#pragma mark * Encoding/decoding utilities

+ (NSData *)JSONSerializeObject:(id)obj
{
    id coercedObj = [Slash7 JSONSerializableObjectForObject:obj];

    S7CJSONDataSerializer *serializer = [S7CJSONDataSerializer serializer];
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
            [a addObject:[Slash7 JSONSerializableObjectForObject:i]];
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
            id v = [Slash7 JSONSerializableObjectForObject:[obj objectForKey:key]];
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
    NSData *data = [Slash7 JSONSerializeObject:array];
    if (data) {
        b64String = [data s7_base64EncodedString];
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
                 [[properties objectForKey:k] isKindOfClass:[NSArray class]] ||
                 [[properties objectForKey:k] isKindOfClass:[NSDictionary class]] ||
                 [[properties objectForKey:k] isKindOfClass:[NSDate class]] ||
                 [[properties objectForKey:k] isKindOfClass:[NSURL class]],
                 @"%@ property values must be NSString, NSNumber, NSNull, NSArray, NSDictionary, NSDate or NSURL. got: %@ %@", self, [[properties objectForKey:k] class], [properties objectForKey:k]);
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
        self.sendDeviceInfo = YES;
        self.serverURL = @"https://tracker.slash-7.com";
        
        self.appUserId = [self defaultAppUserId];
        self.appUserIdType = [self defaultAppUserIdType];
        self.superProperties = [NSMutableDictionary dictionary];

        self.eventsQueue = [NSMutableArray array];
        
        [self addApplicationObservers];
        
        [self unarchive];

    }
    return self;
}

#pragma mark * Identity

- (void)identify:(NSString *)appUserId
{
    [self identify:appUserId withType:S7_USER_ID_TYPE_APP];
}


- (void)identify:(NSString *)appUserId withType:(S7AppUserIdType)type
{
    @synchronized(self) {
        self.appUserId = appUserId;
        self.appUserIdType = [Slash7 appUserIdTypeString:type];
        if ([Slash7 inBackground]) {
            [self archiveProperties];
        }
    }
}


#pragma mark * Tracking

- (NSString *)defaultAppUserId
{
    NSString *appUserId = nil;
    if (NSClassFromString(@"ASIdentifierManager")) {
        appUserId = ASIdentifierManager.sharedManager.advertisingIdentifier.UUIDString;
    }
    if (!appUserId) {
        appUserId = S7ODIN1();
    }
    if (!appUserId) {
        NSLog(@"%@ error getting default app user id: both iOS IFA and ODIN1 failed", self);
    }
    return appUserId;
}

- (NSString *)defaultAppUserIdType
{
    return [Slash7 appUserIdTypeString:S7_USER_ID_TYPE_COOKIE];
}

- (void)track:(NSString *)event
{
    [self track:event withParams:nil];
}

- (void)track:(NSString *)event withParams:(NSDictionary *)params
{
    @synchronized(self) {
        NSDate *now = [NSDate date];
        if (event == nil || [event length] == 0) {
            NSLog(@"%@ track called with empty event parameter. using '_empty'", self);
            event = @"_empty";
        }
        NSMutableDictionary *p = [NSMutableDictionary dictionary];
        if (self.sendDeviceInfo) {
            [p addEntriesFromDictionary:[Slash7 deviceInfoProperties]];
        }
        [p addEntriesFromDictionary:self.superProperties];
        if (params) {
            [p addEntriesFromDictionary:params];
        }

        [Slash7 assertPropertyTypes:params];

        NSDictionary *e = [NSDictionary dictionaryWithObjectsAndKeys:
                           event, S7_EVENT_NAME_KEY,
                           [self.dateFormatter stringFromDate:now], S7_TIME_KEY,
                           [NSDictionary dictionaryWithDictionary:p], S7_EVENT_PARAMS_KEY,
                           self.appUserIdType, S7_APP_USER_ID_TYPE_KEY,
                           self.appUserId, S7_APP_USER_ID_KEY,
                           nil];
        Slash7Log(@"%@ queueing event: %@", self, e);
        [self.eventsQueue addObject:e];
        if ([Slash7 inBackground]) {
            [self archiveEvents];
        }
    }
}

#pragma mark * Super property methods

- (void)setUserAttributes:(NSDictionary *)properties
{
    [Slash7 assertPropertyTypes:properties];
    @synchronized(self) {
        [self.superProperties addEntriesFromDictionary:properties];
        if ([Slash7 inBackground]) {
            [self archiveProperties];
        }
    }
}

- (void)registerSuperPropertiesOnce:(NSDictionary *)properties
{
    [Slash7 assertPropertyTypes:properties];
    @synchronized(self) {
        for (NSString *key in properties) {
            if ([self.superProperties objectForKey:key] == nil) {
                [self.superProperties setObject:[properties objectForKey:key] forKey:key];
            }
        }
        if ([Slash7 inBackground]) {
            [self archiveProperties];
        }
    }
}

- (void)registerSuperPropertiesOnce:(NSDictionary *)properties defaultValue:(id)defaultValue
{
    [Slash7 assertPropertyTypes:properties];
    @synchronized(self) {
        for (NSString *key in properties) {
            id value = [self.superProperties objectForKey:key];
            if (value == nil || [value isEqual:defaultValue]) {
                [self.superProperties setObject:[properties objectForKey:key] forKey:key];
            }
        }
        if ([Slash7 inBackground]) {
            [self archiveProperties];
        }
    }
}

- (void)unregisterSuperProperty:(NSString *)propertyName
{
    @synchronized(self) {
        if ([self.superProperties objectForKey:propertyName] != nil) {
            [self.superProperties removeObjectForKey:propertyName];
            if ([Slash7 inBackground]) {
                [self archiveProperties];
            }
        }
    }
}

- (void)clearSuperProperties
{
    @synchronized(self) {
        [self.superProperties removeAllObjects];
        if ([Slash7 inBackground]) {
            [self archiveProperties];
        }
    }
}

- (NSDictionary *)currentSuperProperties
{
    @synchronized(self) {
        return [[self.superProperties copy] autorelease];
    }
}

- (void)reset
{
    @synchronized(self) {
        self.appUserId = [self defaultAppUserId];
        self.appUserIdType = [self defaultAppUserIdType];
        self.superProperties = [NSMutableDictionary dictionary];

        self.eventsQueue = [NSMutableArray array];

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
            Slash7Debug(@"%@ started flush timer: %@", self, self.timer);
        }
    }
}

- (void)stopFlushTimer
{
    @synchronized(self) {
        if (self.timer) {
            [self.timer invalidate];
            Slash7Debug(@"%@ stopped flush timer: %@", self, self.timer);
        }
        self.timer = nil;
    }
}

- (void)flush
{
    // If the app is currently in the background but Mixpanel has not requested
    // to run a background task, the flush will be cut short. This can happen
    // when the app forces a flush from within its own background task.
    if ([Slash7 inBackground] && self.taskId == UIBackgroundTaskInvalid) {
        [self flushInBackgroundTask];
        return;
    }

    @synchronized(self) {
        if ([self.delegate respondsToSelector:@selector(slash7WillFlush:)]) {
            if (![self.delegate slash7WillFlush:self]) {
                Slash7Debug(@"%@ delegate deferred flush", self);
                return;
            }
        }
        Slash7Debug(@"%@ flushing data to %@", self, self.serverURL);
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
                Slash7Debug(@"%@ flush background task %u cut short", self, self.taskId);
                [self cancelFlush];
                [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
                self.taskId = UIBackgroundTaskInvalid;
            }];

            Slash7Debug(@"%@ starting flush background task %u", self, self.taskId);
            [self flush];

            // connection callbacks end this task by calling endBackgroundTaskIfComplete
        }
    }
#endif
}

- (void)flushEvents
{
    if ([self.eventsQueue count] == 0) {
        Slash7Debug(@"%@ no events to flush", self);
        return;
    } else if (self.eventsConnection != nil) {
        Slash7Debug(@"%@ events connection already open", self);
        return;
    } else if ([self.eventsQueue count] > 50) {
        self.eventsBatch = [self.eventsQueue subarrayWithRange:NSMakeRange(0, 50)];
    } else {
        self.eventsBatch = [NSArray arrayWithArray:self.eventsQueue];
    }
    
    NSString *data = [Slash7 encodeAPIData:self.eventsBatch];
    NSString *postBody = [NSString stringWithFormat:@"ip=1&data=%@", data];
    
    Slash7Debug(@"%@ flushing %u of %u queued events: %@", self, self.eventsBatch.count, self.eventsQueue.count, self.eventsQueue);

    NSString *endpoint = [@"/track/" stringByAppendingString:self.apiToken];
    self.eventsConnection = [self apiConnectionWithEndpoint:endpoint andBody:postBody];

    [self updateNetworkActivityIndicator];
}

- (void)cancelFlush
{
    if (self.eventsConnection == nil) {
        Slash7Debug(@"%@ no events connection to cancel", self);
    } else {
        Slash7Debug(@"%@ cancelling events connection", self);
        [self.eventsConnection cancel];
        self.eventsConnection = nil;
    }
    if (self.peopleConnection == nil) {
        Slash7Debug(@"%@ no people connection to cancel", self);
    } else {
        Slash7Debug(@"%@ cancelling people connection", self);
        [self.peopleConnection cancel];
        self.peopleConnection = nil;
    }
}

- (void)updateNetworkActivityIndicator
{
    @synchronized(self) {
        BOOL visible = self.showNetworkActivityIndicator && (self.eventsConnection || self.peopleConnection);
        [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:visible];
    }
}

#pragma mark * Persistence

- (NSString *)filePathForData:(NSString *)data
{
    NSString *filename = [NSString stringWithFormat:@"slash7-%@-%@.plist", self.apiToken, data];
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
        Slash7Debug(@"%@ archiving events data to %@: %@", self, filePath, self.eventsQueue);
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
        [properties setValue:self.appUserId forKey:@"appUserId"];
        [properties setValue:self.appUserIdType forKey:@"appUserIdType"];
        [properties setValue:self.superProperties forKey:@"superProperties"];
        Slash7Debug(@"%@ archiving properties data to %@: %@", self, filePath, properties);
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
        Slash7Debug(@"%@ unarchived events data: %@", self, self.eventsQueue);
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
        Slash7Debug(@"%@ unarchived properties data: %@", self, properties);
    }
    @catch (NSException *exception) {
        NSLog(@"%@ unable to unarchive properties data, starting fresh", self);
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    }
    if (properties) {
        self.appUserId = [properties objectForKey:@"appUserId"];
        self.appUserIdType = [properties objectForKey:@"appUserIdType"];
        self.superProperties = [properties objectForKey:@"superProperties"];
    }
}

#pragma mark * Application lifecycle events

- (void)addApplicationObservers
{
    Slash7Debug(@"%@ adding application observers", self);
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
    Slash7Debug(@"%@ removing application observers", self);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification
{
    Slash7Debug(@"%@ application did become active", self);
    @synchronized(self) {
        [self startFlushTimer];
    }
}

- (void)applicationWillResignActive:(NSNotification *)notification
{
    Slash7Debug(@"%@ application will resign active", self);
    @synchronized(self) {
        [self stopFlushTimer];
    }
}

- (void)applicationDidEnterBackground:(NSNotificationCenter *)notification
{
    Slash7Debug(@"%@ did enter background", self);

    @synchronized(self) {
        if (self.flushOnBackground) {
            [self flushInBackgroundTask];
        }
    }
}

- (void)applicationWillEnterForeground:(NSNotificationCenter *)notification
{
    Slash7Debug(@"%@ will enter foreground", self);
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
    Slash7Debug(@"%@ application will terminate", self);
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
            self.taskId != UIBackgroundTaskInvalid && self.eventsConnection == nil && self.peopleConnection == nil) {
            Slash7Debug(@"%@ ending flush background task %u", self, self.taskId);
            [[UIApplication sharedApplication] endBackgroundTask:self.taskId];
            self.taskId = UIBackgroundTaskInvalid;
        }
    }
#endif
}

#pragma mark * NSURLConnection callbacks

- (NSURLConnection *)apiConnectionWithEndpoint:(NSString *)endpoint andBody:(NSString *)body
{
    NSURL *url = [NSURL URLWithString:[self.serverURL stringByAppendingString:endpoint]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setValue:@"gzip" forHTTPHeaderField:@"Accept-Encoding"];
    [request setHTTPMethod:@"POST"];
    [request setHTTPBody:[body dataUsingEncoding:NSUTF8StringEncoding]];
    Slash7Debug(@"%@ http request: %@?%@", self, [self.serverURL stringByAppendingString:endpoint], body);
    return [NSURLConnection connectionWithRequest:request delegate:self];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response
{
    Slash7Debug(@"%@ http status code: %d", self, [response statusCode]);
    if ([response statusCode] != 200) {
        NSLog(@"%@ http error: %@", self, [NSHTTPURLResponse localizedStringForStatusCode:[response statusCode]]);
    } else if (connection == self.eventsConnection) {
        self.eventsResponseData = [NSMutableData data];
    } else if (connection == self.peopleConnection) {
        self.peopleResponseData = [NSMutableData data];
    }
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    if (connection == self.eventsConnection) {
        [self.eventsResponseData appendData:data];
    } else if (connection == self.peopleConnection) {
        [self.peopleResponseData appendData:data];
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
        } else if (connection == self.peopleConnection) {
            self.peopleBatch = nil;
            self.peopleResponseData = nil;
            self.peopleConnection = nil;
        }

        [self updateNetworkActivityIndicator];
        
        [self endBackgroundTaskIfComplete];
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    @synchronized(self) {
        Slash7Debug(@"%@ http response finished loading", self);
        if (connection == self.eventsConnection) {
            NSString *response = [[NSString alloc] initWithData:self.eventsResponseData encoding:NSUTF8StringEncoding];
            if ([response intValue] == 0) {
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
    return [NSString stringWithFormat:@"<Slash7: %p %@>", self, self.apiToken];
}

- (void)dealloc
{
    [self stopFlushTimer];
    [self removeApplicationObservers];
    
    self.appUserId = nil;
    self.serverURL = nil;
    self.delegate = nil;
    
    self.apiToken = nil;
    self.superProperties = nil;
    self.timer = nil;
    self.eventsQueue = nil;
    self.eventsBatch = nil;
    self.peopleBatch = nil;
    self.eventsConnection = nil;
    self.peopleConnection = nil;
    self.eventsResponseData = nil;
    self.peopleResponseData = nil;
    
    [super dealloc];
}

@end
