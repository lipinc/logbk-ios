//
//  HelloLogbookTests.m
//  HelloLogbookTests
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

#import "HelloLogbookTests.h"

#import "Logbook.h"
#import "S7CJSONSerializer.h"

#define TEST_TOKEN @"abc123"

@interface Logbook (Test)

// get access to private members
@property(nonatomic,retain) NSMutableArray *eventsQueue;
@property(nonatomic,retain) NSTimer *timer;
@property(nonatomic,retain) NSDateFormatter *dateFormatter;
@property(nonatomic,assign) BOOL projectDeleted;

+ (BOOL)isValidEventName: (NSString *)name;
+ (BOOL)isValidSystemEventName: (NSString *)name;
+ (NSData *)JSONSerializeObject:(id)obj;
- (NSString *)randomAppUserId;
- (NSString *)defaultAppUserIdType;
- (void)archive;
- (NSString *)eventsFilePath;
- (NSString *)propertiesFilePath;

@end


@interface HelloLogbookTests ()  <LogbookDelegate>

@property(nonatomic,retain) Logbook *logbook;

@end

@implementation HelloLogbookTests

- (void)setUp
{
    [super setUp];
    self.logbook = [[[Logbook alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    [self.logbook reset];
}

- (void)tearDown
{
    [super tearDown];
    self.logbook = nil;
}

- (BOOL)logbookWillFlush:(Logbook *)logbook
{
    return NO;
}

-(void)removeArchiveFiles
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:[self.logbook eventsFilePath] error:NULL];
    [fileManager removeItemAtPath:[self.logbook propertiesFilePath] error:NULL];
}

+ (NSString *)getJSON:(id)obj {
    NSData *data = [Logbook JSONSerializeObject:obj];
    return [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
}

- (void)testJSONSerializeObject {
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss zzz"];
    NSDate *date = [dateFormatter dateFromString:@"2012-09-28 19:14:36 PDT"];
    [dateFormatter release];
    
    NSNull *null = [NSNull null];
    NSURL *url = [NSURL URLWithString:@"http://example.com/"];
    
    XCTAssertEqualObjects([HelloLogbookTests getJSON: @{@"string": @"yellow"}],
                          @"{\"string\":\"yellow\"}");
    XCTAssertEqualObjects([HelloLogbookTests getJSON:@{@"number": @3}],
                          @"{\"number\":3}");
    XCTAssertEqualObjects([HelloLogbookTests getJSON:@{@"date": date}],
                          @"{\"date\":\"2012-09-29T02:14:36\"}");
    XCTAssertEqualObjects([HelloLogbookTests getJSON:@{@"null": null}],
                          @"{\"null\":null}");
    XCTAssertEqualObjects([HelloLogbookTests getJSON:@{@"url": url}],
                          @"{\"url\":\"http:\\/\\/example.com\\/\"}");
    XCTAssertEqualObjects([HelloLogbookTests getJSON:@{@"float": @1.3}],
                          @"{\"float\":1.3}");
    XCTAssertEqualObjects([HelloLogbookTests getJSON: @[@{@"string": @"yellow"}]],
                          @"[{\"string\":\"yellow\"}]");
    XCTAssertEqualObjects([HelloLogbookTests getJSON:@{@3: @"non-string key"}],
                          @"{\"3\":\"non-string key\"}", @"json serialization failed");
}

- (void)testIsValidEventName {
    XCTAssertTrue([Logbook isValidEventName:@"ev1"]);
    XCTAssertTrue([Logbook isValidEventName:@"Access"]);
    XCTAssertTrue([Logbook isValidEventName:@"NotContainSpace"]);
    XCTAssertTrue([Logbook isValidEventName:@"l2345678901234567890123456789012"]);
    XCTAssertTrue([Logbook isValidEventName:@"snake_case"]);
    XCTAssertTrue([Logbook isValidEventName:@"dash-separated"]);
    XCTAssertTrue([Logbook isValidEventName:@"dot.separated"]);

    XCTAssertFalse([Logbook isValidEventName:nil]);
    XCTAssertFalse([Logbook isValidEventName:@"_access"]);
    XCTAssertFalse([Logbook isValidEventName:@"0a"]);
    XCTAssertFalse([Logbook isValidEventName:@""]);
    XCTAssertFalse([Logbook isValidEventName:@"Access%"]);
    XCTAssertFalse([Logbook isValidEventName:@" access"]);
    XCTAssertFalse([Logbook isValidEventName:@"access "]);
    XCTAssertFalse([Logbook isValidEventName:@"contains space"]);
    XCTAssertFalse([Logbook isValidEventName:@"contains　zenkaku　space"]);
    XCTAssertFalse([Logbook isValidEventName:@"アルファベット以外"]);
    XCTAssertFalse([Logbook isValidEventName:@"l23456789012345678901234567890123"]);
}

- (void)testIsValidSystemEventName {
    XCTAssertTrue([Logbook isValidSystemEventName:@"_access"]);
    XCTAssertTrue([Logbook isValidSystemEventName:@"_referral"]);
    XCTAssertTrue([Logbook isValidSystemEventName:@"_l345678901234567890123456789012"]);

    XCTAssertFalse([Logbook isValidSystemEventName:nil]);
    XCTAssertFalse([Logbook isValidSystemEventName:@"ev1"]);
    XCTAssertFalse([Logbook isValidSystemEventName:@" _access"]);
    XCTAssertFalse([Logbook isValidSystemEventName:@"_access "]);
    XCTAssertFalse([Logbook isValidSystemEventName:@"Access"]);
    XCTAssertFalse([Logbook isValidSystemEventName:@"NotContainSpace"]);
    XCTAssertFalse([Logbook isValidSystemEventName:@"l2345678901234567890123456789012"]);
    XCTAssertFalse([Logbook isValidSystemEventName:@"snake_case"]);
    XCTAssertFalse([Logbook isValidSystemEventName:@"dash-separated"]);
    XCTAssertFalse([Logbook isValidSystemEventName:@"dot.separated"]);
    XCTAssertFalse([Logbook isValidSystemEventName:@"_2345678901234567890123456789012"]);
    XCTAssertFalse([Logbook isValidSystemEventName:@"_l3456789012345678901234567890123"]);
}

- (void)testIdentify
{
    for (int i = 0; i < 2; i++) { // run this twice to test reset works correctly wrt to distinct ids
        NSString *distinctId = @"d1";
        // try this for IFA, ODIN and nil
        XCTAssertNotNil(self.logbook.randUser, @"failed to set default randUser");
        [self.logbook identify:distinctId];
        XCTAssertEqualObjects(self.logbook.user, distinctId, @"identify failed to set distinct id");
        [self.logbook reset];
    }
}

- (void)testRandomUserId
{
    [self removeArchiveFiles];
    self.logbook = [[[Logbook alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    NSString *prev = self.logbook.randUser;
    self.logbook = [[[Logbook alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertEqualObjects(self.logbook.randUser, prev, @"randomly generated user id should be kept");
}

- (void)testTrack
{
    [self.logbook track:@"SomethingHappened"];
    XCTAssertTrue(self.logbook.eventsQueue.count == 1, @"event not queued");
    NSDictionary *e = self.logbook.eventsQueue.lastObject;
    XCTAssertEqual([e objectForKey:@"event"], @"SomethingHappened", @"incorrect event name");
    XCTAssertNotNil([e objectForKey:@"randUser"], @"randUser not set");
    XCTAssertNotNil([e objectForKey:@"time"], @"time not set");
    XCTAssertNotNil([e objectForKey:@"libVersion"], @"lib_version not set");
    XCTAssertEqualObjects([e objectForKey:@"libName"], @"logbk-ios", @"incorrect lib");
}

- (void)testTrackDeviceInfo
{
    self.logbook.sendDeviceInfo = YES;
    [self.logbook track:@"SomethingHappened"];
    XCTAssertTrue(self.logbook.eventsQueue.count == 1, @"event not queued");
    NSDictionary *e = self.logbook.eventsQueue.lastObject;

    XCTAssertEqual([e objectForKey:@"event"], @"SomethingHappened", @"incorrect event name");
    XCTAssertNotNil([e objectForKey:@"randUser"], @"randUser not set");
    XCTAssertNotNil([e objectForKey:@"time"], @"time not set");
    
    XCTAssertNotNil([e objectForKey:@"app_version"], @"app_version not set");
    XCTAssertNotNil([e objectForKey:@"app_release"], @"app_release not set");
    XCTAssertEqualObjects([e objectForKey:@"manufacturer"], @"Apple", @"incorrect manufacturer");
    XCTAssertNotNil([e objectForKey:@"model"], @"model not set");
    XCTAssertNotNil([e objectForKey:@"os"], @"os not set");
    XCTAssertNotNil([e objectForKey:@"os_version"], @"os_version not set");
    XCTAssertNotNil([e objectForKey:@"screen_height"], @"screen_height not set");
    XCTAssertNotNil([e objectForKey:@"screen_width"], @"screen_width not set");
    XCTAssertNotNil([e objectForKey:@"wifi"], @"wifi not set");
}

- (void)testTrackWithDeletedProject
{
    self.logbook.projectDeleted = YES;
    [self.logbook track:@"Something Happened"];
    XCTAssertTrue(self.logbook.eventsQueue.count == 0, @"event should not queued");
}


- (void)testReset
{
    [self.logbook identify:@"d1"];
    [self.logbook track:@"e1"];
    self.logbook.projectDeleted = YES;
    [self.logbook archive];

    [self.logbook reset];
    NSString *randUserAfterReset = self.logbook.randUser;
    XCTAssertNotNil(self.logbook.randUser, @"default distinct id from no file failed");
    XCTAssertFalse([self.logbook.user isEqualToString:@"d1"], @"default distinct id from no file failed");
    XCTAssertTrue(self.logbook.eventsQueue.count == 0, @"events queue failed to reset");
    XCTAssertFalse(self.logbook.projectDeleted, @"project deleted failed to reset");
    
    self.logbook = [[[Logbook alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertEqualObjects(self.logbook.randUser, randUserAfterReset, @"distinct id failed to reset after archive");
    XCTAssertTrue(self.logbook.eventsQueue.count == 0, @"events queue failed to reset after archive");
    XCTAssertFalse(self.logbook.projectDeleted, @"project deleted failed to reset");
}

- (void)testFlushTimer
{
    self.logbook = [[[Logbook alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertNil(self.logbook.timer, @"intializing with a flush interval of 0 still started timer");
    self.logbook = [[[Logbook alloc] initWithCode:TEST_TOKEN andFlushInterval:60] autorelease];
    XCTAssertNotNil(self.logbook.timer, @"intializing with a flush interval of 60 did not start timer");
}

- (void)testArchive
{
    NSString *origRandUser = self.logbook.randUser;
    [self.logbook archive];
    self.logbook = [[[Logbook alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertEqualObjects(self.logbook.randUser, origRandUser, @"default distinct id archive failed");
    XCTAssertTrue(self.logbook.eventsQueue.count == 0, @"default events queue archive failed");
    XCTAssertFalse(self.logbook.projectDeleted, @"default project deleted archive failed");

    [self.logbook identify:@"d1"];
    [self.logbook track:@"e1"];
    self.logbook.projectDeleted = YES;

    [self.logbook archive];
    self.logbook = [[[Logbook alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];

    XCTAssertEqualObjects(self.logbook.user, @"d1", @"custom distinct archive failed");
    XCTAssertTrue(self.logbook.eventsQueue.count == 1, @"pending events queue archive failed");
    XCTAssertTrue(self.logbook.projectDeleted, @"project deleted archive failed");

    NSFileManager *fileManager = [NSFileManager defaultManager];

    XCTAssertTrue([fileManager fileExistsAtPath:[self.logbook eventsFilePath]], @"events archive file not found");
    XCTAssertTrue([fileManager fileExistsAtPath:[self.logbook propertiesFilePath]], @"properties archive file not found");

    // no existing file
    [self removeArchiveFiles];

    XCTAssertFalse([fileManager fileExistsAtPath:[self.logbook eventsFilePath]], @"events archive file not removed");
    XCTAssertFalse([fileManager fileExistsAtPath:[self.logbook propertiesFilePath]], @"properties archive file not removed");

    self.logbook = [[[Logbook alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertNotNil(self.logbook.randUser, @"default distinct id from no file failed");
    XCTAssertFalse([self.logbook.randUser isEqualToString:origRandUser], @"default distinct id from no file failed");
    XCTAssertNotNil(self.logbook.eventsQueue, @"default events queue from no file is nil");
    XCTAssertTrue(self.logbook.eventsQueue.count == 0, @"default events queue from no file not empty");
    XCTAssertFalse(self.logbook.projectDeleted, @"default project deleted archive failed");

    // corrupt file

    NSData *garbage = [@"garbage" dataUsingEncoding:NSUTF8StringEncoding];
    [garbage writeToFile:[self.logbook eventsFilePath] atomically:NO];
    [garbage writeToFile:[self.logbook propertiesFilePath] atomically:NO];

    XCTAssertTrue([fileManager fileExistsAtPath:[self.logbook eventsFilePath]], @"garbage events archive file not found");
    XCTAssertTrue([fileManager fileExistsAtPath:[self.logbook propertiesFilePath]], @"garbage properties archive file not found");

    self.logbook = [[[Logbook alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertNotNil(self.logbook.randUser, @"default distinct id from no file failed");
    XCTAssertFalse([self.logbook.randUser isEqualToString:origRandUser], @"default distinct id from no file failed");
    XCTAssertNotNil(self.logbook.eventsQueue, @"default events queue from garbage is nil");
    XCTAssertTrue(self.logbook.eventsQueue.count == 0, @"default events queue from garbage not empty");
    XCTAssertFalse(self.logbook.projectDeleted, @"default project deleted archive failed");
}

- (void)testLogbookDelegate
{
    self.logbook.delegate = self;
    [self.logbook identify:@"d1"];
    [self.logbook track:@"e1"];
    [self.logbook flush];
    XCTAssertTrue(self.logbook.eventsQueue.count == 1, @"delegate should have stopped flush");
}

- (void)testNilArguments
{
    [self.logbook track:nil];
    // legacy behavior
    XCTAssertTrue(self.logbook.eventsQueue.count == 0, @"track with nil should not create mp_event event");
}

- (void)testDateFormatter
{
    NSDate *d1 = [NSDate dateWithTimeIntervalSince1970:0];
    XCTAssertEqualObjects([self.logbook.dateFormatter stringFromDate:d1], @"1970-01-01T00:00:00Z", @"dateFormatter should format in ISO8601");
    
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss zzz"];
    NSDate *d2 = [dateFormatter dateFromString:@"2012-09-28 19:14:36 PDT"];
    XCTAssertEqualObjects([self.logbook.dateFormatter stringFromDate:d2], @"2012-09-29T02:14:36Z", @"dateFormatter should format in UTC");
}

- (void)testSendDeviceInfo
{
    self.logbook.sendDeviceInfo = NO;
    [self.logbook track:@"SomethingHappened"];
    NSDictionary *e1 = self.logbook.eventsQueue.lastObject;
    XCTAssertEqual([e1 objectForKey:@"event"], @"SomethingHappened", @"incorrect event name");
    XCTAssertNotNil([e1 objectForKey:@"randUser"], @"randUser not set");
    XCTAssertNotNil([e1 objectForKey:@"time"], @"time not set");
}

@end
