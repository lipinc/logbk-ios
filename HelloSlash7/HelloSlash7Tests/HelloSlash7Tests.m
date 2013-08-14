//
//  HelloSlash7Tests.m
//  HelloSlash7Tests
//
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

#import "HelloSlash7Tests.h"

#import "Slash7.h"
#import "S7CJSONSerializer.h"

#define TEST_TOKEN @"abc123"

@interface Slash7 (Test)

// get access to private members
@property(nonatomic,retain) NSMutableArray *eventsQueue;
@property(nonatomic,retain) NSTimer *timer;

+ (NSData *)JSONSerializeObject:(id)obj;
- (NSString *)defaultDistinctId;
- (void)archive;
- (NSString *)eventsFilePath;
- (NSString *)peopleFilePath;
- (NSString *)propertiesFilePath;

@end

@interface HelloSlash7Tests ()  <Slash7Delegate>

@property(nonatomic,retain) Slash7 *mixpanel;

@end

@implementation HelloSlash7Tests

- (void)setUp
{
    [super setUp];
    self.mixpanel = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    [self.mixpanel reset];
}

- (void)tearDown
{
    [super tearDown];
    self.mixpanel = nil;
}

- (BOOL)mixpanelWillFlush:(Slash7 *)mixpanel
{
    return NO;
}

- (NSDictionary *)allPropertyTypes
{
    NSNumber *number = [NSNumber numberWithInt:3];

    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss zzz"];
    NSDate *date = [dateFormatter dateFromString:@"2012-09-28 19:14:36 PDT"];
    [dateFormatter release];

    NSDictionary *dictionary = [NSDictionary dictionaryWithObject:@"v" forKey:@"k"];
    NSArray *array = [NSArray arrayWithObject:@"1"];
    NSNull *null = [NSNull null];

    NSDictionary *nested = [NSDictionary dictionaryWithObject:
                            [NSDictionary dictionaryWithObject:
                             [NSArray arrayWithObject:
                              [NSDictionary dictionaryWithObject:
                               [NSArray arrayWithObject:@"bottom"]
                                                          forKey:@"p3"]]
                                                        forKey:@"p2"]
                                                       forKey:@"p1"];
    NSURL *url = [NSURL URLWithString:@"https://mixpanel.com/"];

    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"yello",   @"string",
            number,     @"number",
            date,       @"date",
            dictionary, @"dictionary",
            array,      @"array",
            null,       @"null",
            nested,     @"nested",
            url,        @"url",
            @1.3,       @"float",
            nil];
}

- (void)assertDefaultPeopleProperties:(NSDictionary *)p
{
    STAssertNotNil([p objectForKey:@"$ios_device_model"], @"missing $ios_device_model property");
    STAssertNotNil([p objectForKey:@"$ios_version"], @"missing $ios_version property");
    STAssertNotNil([p objectForKey:@"$ios_app_version"], @"missing $ios_app_version property");
    STAssertNotNil([p objectForKey:@"$ios_app_release"], @"missing $ios_app_release property");
    STAssertNotNil([p objectForKey:@"$ios_ifa"], @"missing $ios_ifa property");

}

- (void)testJSONSerializeObject {
    NSDictionary *test = [self allPropertyTypes];
    NSData *data = [Slash7 JSONSerializeObject:[NSArray arrayWithObject:test]];
    NSString *json = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    STAssertEqualObjects(json, @"[{\"float\":1.3,\"string\":\"yello\",\"url\":\"https:\\/\\/mixpanel.com\\/\",\"nested\":{\"p1\":{\"p2\":[{\"p3\":[\"bottom\"]}]}},\"array\":[\"1\"],\"date\":\"2012-09-29T02:14:36\",\"dictionary\":{\"k\":\"v\"},\"null\":null,\"number\":3}]", @"json serialization failed");

    test = [NSDictionary dictionaryWithObject:@"non-string key" forKey:@3];
    data = [Slash7 JSONSerializeObject:[NSArray arrayWithObject:test]];
    json = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    STAssertEqualObjects(json, @"[{\"3\":\"non-string key\"}]", @"json serialization failed");
}

- (void)testIdentify
{
    for (int i = 0; i < 2; i++) { // run this twice to test reset works correctly wrt to distinct ids

        NSString *distinctId = @"d1";
        // try this for IFA, ODIN and nil
        STAssertEqualObjects(self.mixpanel.distinctId, self.mixpanel.defaultDistinctId, @"mixpanel identify failed to set default distinct id");
        [self.mixpanel track:@"e1"];
        STAssertTrue(self.mixpanel.eventsQueue.count == 1, @"events should be sent right away with default distinct id");
        STAssertEqualObjects(self.mixpanel.eventsQueue.lastObject[@"properties"][@"distinct_id"], self.mixpanel.defaultDistinctId, @"events should use default distinct id if none set");

        [self.mixpanel identify:distinctId];
        STAssertEqualObjects(self.mixpanel.distinctId, distinctId, @"mixpanel identify failed to set distinct id");
        [self.mixpanel track:@"e2"];
        STAssertEquals(self.mixpanel.eventsQueue.lastObject[@"properties"][@"distinct_id"], distinctId, @"events should use new distinct id after identify:");
        [self.mixpanel reset];
    }
}

- (void)testTrack
{
    [self.mixpanel track:@"Something Happened"];
    STAssertTrue(self.mixpanel.eventsQueue.count == 1, @"event not queued");
    NSDictionary *e = self.mixpanel.eventsQueue.lastObject;
    STAssertEquals([e objectForKey:@"event"], @"Something Happened", @"incorrect event name");
    NSDictionary *p = [e objectForKey:@"properties"];
    STAssertTrue(p.count == 16, @"incorrect number of properties");

    STAssertNotNil([p objectForKey:@"$app_version"], @"$app_version not set");
    STAssertNotNil([p objectForKey:@"$app_release"], @"$app_release not set");
    STAssertNotNil([p objectForKey:@"$lib_version"], @"$lib_version not set");
    STAssertEqualObjects([p objectForKey:@"$manufacturer"], @"Apple", @"incorrect $manufacturer");
    STAssertNotNil([p objectForKey:@"$model"], @"$model not set");
    STAssertNotNil([p objectForKey:@"$os"], @"$os not set");
    STAssertNotNil([p objectForKey:@"$os_version"], @"$os_version not set");
    STAssertNotNil([p objectForKey:@"$screen_height"], @"$screen_height not set");
    STAssertNotNil([p objectForKey:@"$screen_width"], @"$screen_width not set");
    STAssertNotNil([p objectForKey:@"distinct_id"], @"distinct_id not set");
    STAssertNotNil([p objectForKey:@"mp_device_model"], @"mp_device_model not set");
    STAssertEqualObjects([p objectForKey:@"mp_lib"], @"iphone", @"incorrect mp_lib");
    STAssertNotNil([p objectForKey:@"time"], @"time not set");
    STAssertNotNil([p objectForKey:@"$ios_ifa"], @"$ios_ifa not set");
    STAssertEqualObjects([p objectForKey:@"token"], TEST_TOKEN, @"incorrect token");
}

- (void)testTrackProperties
{
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"yello",                   @"string",
                       [NSNumber numberWithInt:3], @"number",
                       [NSDate date],              @"date",
                       @"override",                @"$app_version",
                       nil];
    [self.mixpanel track:@"Something Happened" withParams:p];
    STAssertTrue(self.mixpanel.eventsQueue.count == 1, @"event not queued");
    NSDictionary *e = self.mixpanel.eventsQueue.lastObject;
    STAssertEquals([e objectForKey:@"event"], @"Something Happened", @"incorrect event name");
    p = [e objectForKey:@"properties"];
    STAssertTrue(p.count == 19, @"incorrect number of properties");
    STAssertEqualObjects([p objectForKey:@"$app_version"], @"override", @"reserved property override failed");
}

- (void)testTrackWithCustomDistinctIdAndToken
{
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"t1",                      @"token",
                       @"d1",                      @"distinct_id",
                       nil];
    [self.mixpanel track:@"e1" withParams:p];
    NSString *trackToken = [[self.mixpanel.eventsQueue.lastObject objectForKey:@"properties"] objectForKey:@"token"];
    NSString *trackDistinctId = [[self.mixpanel.eventsQueue.lastObject objectForKey:@"properties"] objectForKey:@"distinct_id"];
    STAssertEqualObjects(trackToken, @"t1", @"user-defined distinct id not used in track. got: %@", trackToken);
    STAssertEqualObjects(trackDistinctId, @"d1", @"user-defined distinct id not used in track. got: %@", trackDistinctId);
}

- (void)testSuperProperties
{
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"a",                       @"p1",
                       [NSNumber numberWithInt:3], @"p2",
                       [NSDate date],              @"p2",
                       nil];

    [self.mixpanel setUserAttributes:p];
    STAssertEqualObjects([self.mixpanel currentSuperProperties], p, @"register super properties failed");
    p = [NSDictionary dictionaryWithObject:@"b" forKey:@"p1"];
    [self.mixpanel setUserAttributes:p];
    STAssertEqualObjects([[self.mixpanel currentSuperProperties] objectForKey:@"p1"], @"b",
                         @"register super properties failed to overwrite existing value");
}

- (void)testAssertPropertyTypes
{
    NSDictionary *p = [NSDictionary dictionaryWithObject:[NSData data] forKey:@"data"];
    STAssertThrows([self.mixpanel track:@"e1" withParams:p], @"property type should not be allowed");
    STAssertThrows([self.mixpanel setUserAttributes:p], @"property type should not be allowed");
    p = [self allPropertyTypes];
    STAssertNoThrow([self.mixpanel track:@"e1" withParams:p], @"property type should be allowed");
    STAssertNoThrow([self.mixpanel setUserAttributes:p], @"property type should be allowed");
}

- (void)testReset
{
    NSDictionary *p = [NSDictionary dictionaryWithObject:@"a" forKey:@"p1"];
    [self.mixpanel identify:@"d1"];
    [self.mixpanel setUserAttributes:p];
    [self.mixpanel track:@"e1"];
    [self.mixpanel archive];

    [self.mixpanel reset];
    STAssertEqualObjects(self.mixpanel.distinctId, [self.mixpanel defaultDistinctId], @"distinct id failed to reset");
    STAssertTrue([[self.mixpanel currentSuperProperties] count] == 0, @"super properties failed to reset");
    STAssertTrue(self.mixpanel.eventsQueue.count == 0, @"events queue failed to reset");
    
    self.mixpanel = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    STAssertEqualObjects(self.mixpanel.distinctId, [self.mixpanel defaultDistinctId], @"distinct id failed to reset after archive");
    STAssertTrue([[self.mixpanel currentSuperProperties] count] == 0, @"super properties failed to reset after archive");
    STAssertTrue(self.mixpanel.eventsQueue.count == 0, @"events queue failed to reset after archive");
}

- (void)testFlushTimer
{
    self.mixpanel = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    STAssertNil(self.mixpanel.timer, @"intializing with a flush interval of 0 still started timer");
    self.mixpanel = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:60] autorelease];
    STAssertNotNil(self.mixpanel.timer, @"intializing with a flush interval of 60 did not start timer");
}

- (void)testArchive
{
    [self.mixpanel archive];
    self.mixpanel = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];

    STAssertEqualObjects(self.mixpanel.distinctId, [self.mixpanel defaultDistinctId], @"default distinct id archive failed");
    STAssertTrue([[self.mixpanel currentSuperProperties] count] == 0, @"default super properties archive failed");
    STAssertTrue(self.mixpanel.eventsQueue.count == 0, @"default events queue archive failed");

    NSDictionary *p = [NSDictionary dictionaryWithObject:@"a" forKey:@"p1"];
    [self.mixpanel identify:@"d1"];
    [self.mixpanel setUserAttributes:p];
    [self.mixpanel track:@"e1"];

    [self.mixpanel archive];
    self.mixpanel = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];

    STAssertEqualObjects(self.mixpanel.distinctId, @"d1", @"custom distinct archive failed");
    STAssertTrue([[self.mixpanel currentSuperProperties] count] == 1, @"custom super properties archive failed");
    STAssertTrue(self.mixpanel.eventsQueue.count == 1, @"pending events queue archive failed");

    NSFileManager *fileManager = [NSFileManager defaultManager];

    STAssertTrue([fileManager fileExistsAtPath:[self.mixpanel eventsFilePath]], @"events archive file not found");
    STAssertTrue([fileManager fileExistsAtPath:[self.mixpanel peopleFilePath]], @"people archive file not found");
    STAssertTrue([fileManager fileExistsAtPath:[self.mixpanel propertiesFilePath]], @"properties archive file not found");

    // no existing file

    [fileManager removeItemAtPath:[self.mixpanel eventsFilePath] error:NULL];
    [fileManager removeItemAtPath:[self.mixpanel peopleFilePath] error:NULL];
    [fileManager removeItemAtPath:[self.mixpanel propertiesFilePath] error:NULL];

    STAssertFalse([fileManager fileExistsAtPath:[self.mixpanel eventsFilePath]], @"events archive file not removed");
    STAssertFalse([fileManager fileExistsAtPath:[self.mixpanel peopleFilePath]], @"people archive file not removed");
    STAssertFalse([fileManager fileExistsAtPath:[self.mixpanel propertiesFilePath]], @"properties archive file not removed");

    self.mixpanel = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    STAssertEqualObjects(self.mixpanel.distinctId, [self.mixpanel defaultDistinctId], @"default distinct id from no file failed");
    STAssertTrue([[self.mixpanel currentSuperProperties] count] == 0, @"default super properties from no file failed");
    STAssertNotNil(self.mixpanel.eventsQueue, @"default events queue from no file is nil");
    STAssertTrue(self.mixpanel.eventsQueue.count == 0, @"default events queue from no file not empty");

    // corrupt file

    NSData *garbage = [@"garbage" dataUsingEncoding:NSUTF8StringEncoding];
    [garbage writeToFile:[self.mixpanel eventsFilePath] atomically:NO];
    [garbage writeToFile:[self.mixpanel peopleFilePath] atomically:NO];
    [garbage writeToFile:[self.mixpanel propertiesFilePath] atomically:NO];

    STAssertTrue([fileManager fileExistsAtPath:[self.mixpanel eventsFilePath]], @"garbage events archive file not found");
    STAssertTrue([fileManager fileExistsAtPath:[self.mixpanel peopleFilePath]], @"garbage people archive file not found");
    STAssertTrue([fileManager fileExistsAtPath:[self.mixpanel propertiesFilePath]], @"garbage properties archive file not found");

    self.mixpanel = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    STAssertEqualObjects(self.mixpanel.distinctId, [self.mixpanel defaultDistinctId], @"default distinct id from garbage failed");
    STAssertTrue([[self.mixpanel currentSuperProperties] count] == 0, @"default super properties from garbage failed");
    STAssertNotNil(self.mixpanel.eventsQueue, @"default events queue from garbage is nil");
    STAssertTrue(self.mixpanel.eventsQueue.count == 0, @"default events queue from garbage not empty");
}

- (void)testMixpanelDelegate
{
    self.mixpanel.delegate = self;
    [self.mixpanel identify:@"d1"];
    [self.mixpanel track:@"e1"];
    [self.mixpanel flush];
    STAssertTrue(self.mixpanel.eventsQueue.count == 1, @"delegate should have stopped flush");
}

- (void)testNilArguments
{
    [self.mixpanel identify:nil];
    [self.mixpanel track:nil];
    [self.mixpanel track:nil withParams:nil];
    [self.mixpanel setUserAttributes:nil];

    // legacy behavior
    STAssertTrue(self.mixpanel.eventsQueue.count == 2, @"track with nil should create mp_event event");
    STAssertEqualObjects([self.mixpanel.eventsQueue.lastObject objectForKey:@"event"], @"mp_event", @"track with nil should create mp_event event");
    STAssertNotNil([self.mixpanel currentSuperProperties], @"setting super properties to nil should have no effect");
    STAssertTrue([[self.mixpanel currentSuperProperties] count] == 0, @"setting super properties to nil should have no effect");

    [self.mixpanel identify:nil];
}

@end
