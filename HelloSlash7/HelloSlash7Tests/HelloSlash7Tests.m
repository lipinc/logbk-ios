//
//  HelloSlash7Tests.m
//  HelloSlash7Tests
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

#import "HelloSlash7Tests.h"

#import "Slash7.h"
#import "S7CJSONSerializer.h"

#define TEST_TOKEN @"abc123"

@interface Slash7 (Test)

// get access to private members
@property(nonatomic,retain) NSMutableArray *eventsQueue;
@property(nonatomic,retain) NSTimer *timer;
@property(nonatomic,retain) NSDateFormatter *dateFormatter;

+ (NSData *)JSONSerializeObject:(id)obj;
- (NSString *)defaultAppUserId;
- (NSString *)defaultAppUserIdType;
- (void)archive;
- (NSString *)eventsFilePath;
- (NSString *)propertiesFilePath;

@end

@interface Slash7TransactionItem (Test)
-(NSDictionary *)properties;
@end

@interface HelloSlash7Tests ()  <Slash7Delegate>

@property(nonatomic,retain) Slash7 *slash7;

@end

@implementation HelloSlash7Tests

- (void)setUp
{
    [super setUp];
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    [self.slash7 reset];
}

- (void)tearDown
{
    [super tearDown];
    self.slash7 = nil;
}

- (BOOL)slash7WillFlush:(Slash7 *)slash7
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

    NSNull *null = [NSNull null];
    NSURL *url = [NSURL URLWithString:@"https://slash-7.com/"];

    return [NSDictionary dictionaryWithObjectsAndKeys:
            @"yello",   @"string",
            number,     @"number",
            date,       @"date",
            null,       @"null",
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
    STAssertEqualObjects(json, @"[{\"float\":1.3,\"null\":null,\"date\":\"2012-09-29T02:14:36\",\"number\":3,\"url\":\"https:\\/\\/slash-7.com\\/\",\"string\":\"yello\"}]", @"json serialization failed");

    test = [NSDictionary dictionaryWithObject:@"non-string key" forKey:@3];
    data = [Slash7 JSONSerializeObject:[NSArray arrayWithObject:test]];
    json = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    STAssertEqualObjects(json, @"[{\"3\":\"non-string key\"}]", @"json serialization failed");
}

- (void)testItemProperty {
    Slash7TransactionItem *item1 = [[[Slash7TransactionItem alloc] initWithId:@"item1" withName:@"Iron sword" withPrice:90 withNum:2] autorelease];
    NSDictionary *p1 = [item1 properties];
    STAssertEqualObjects([p1 objectForKey:@"_item_id"], @"item1", @"_item_id should be set");
    STAssertEqualObjects([p1 objectForKey:@"_name"], @"Iron sword", @"_name should be set");
    STAssertEqualObjects([p1 objectForKey:@"_price"], [NSNumber numberWithInt:90], @"_price should be set");
    STAssertEqualObjects([p1 objectForKey:@"_num"],[NSNumber numberWithInt:2], @"_num should be set");
    STAssertNil([p1 objectForKey:@"_category1"], @"category1 should not be set");
    STAssertNil([p1 objectForKey:@"_category2"], @"category1 should not be set");
    STAssertNil([p1 objectForKey:@"_category3"], @"category1 should not be set");
}

- (void)testItemPropertyWithCategory {
    Slash7TransactionItem *item1 = [[[Slash7TransactionItem alloc] initWithId:@"item1" withName:@"Iron sword" withPrice:90 withNum:2] autorelease];
    item1.category1 = @"Category 1";
    item1.category2 = @"Category 2";
    item1.category3 = @"Category 3";
    
    NSDictionary *p1 = [item1 properties];
    STAssertEqualObjects([p1 objectForKey:@"_item_id"], @"item1", @"_item_id should be set");
    STAssertEqualObjects([p1 objectForKey:@"_name"], @"Iron sword", @"_name should be set");
    STAssertEqualObjects([p1 objectForKey:@"_price"], [NSNumber numberWithInt:90], @"_price should be set");
    STAssertEqualObjects([p1 objectForKey:@"_num"],[NSNumber numberWithInt:2], @"_num should be set");
    STAssertEqualObjects([p1 objectForKey:@"_category1"], @"Category 1", @"category1 should be set");
    STAssertEqualObjects([p1 objectForKey:@"_category2"], @"Category 2", @"category2 should be set");
    STAssertEqualObjects([p1 objectForKey:@"_category3"], @"Category 3", @"category3 should be set");
}

-(void)testItemPropertyNil {
    Slash7TransactionItem *item1 = [[[Slash7TransactionItem alloc] initWithId:nil withName:nil withPrice:0 withNum:0] autorelease];
    NSDictionary *p1 = [item1 properties];
    STAssertEqualObjects([p1 objectForKey:@"_item_id"], @"_empty", @"_item_id should be set");
    STAssertEqualObjects([p1 objectForKey:@"_name"], @"_empty", @"_name should be set");
    STAssertEqualObjects([p1 objectForKey:@"_price"], [NSNumber numberWithInt:0], @"_price should be set");
    STAssertEqualObjects([p1 objectForKey:@"_num"],[NSNumber numberWithInt:0], @"_num should be set");
    STAssertNil([p1 objectForKey:@"_category1"], @"category1 should not be set");
    STAssertNil([p1 objectForKey:@"_category2"], @"category1 should not be set");
    STAssertNil([p1 objectForKey:@"_category3"], @"category1 should not be set");
}

- (void)testIdentify
{
    for (int i = 0; i < 2; i++) { // run this twice to test reset works correctly wrt to distinct ids

        NSString *distinctId = @"d1";
        // try this for IFA, ODIN and nil
        STAssertEqualObjects(self.slash7.appUserId, self.slash7.defaultAppUserId, @"identify failed to set default user id");
        STAssertEqualObjects(self.slash7.appUserIdType, self.slash7.defaultAppUserIdType, @"identify failed to set default user id type");
        [self.slash7 identify:distinctId withType:S7_USER_ID_TYPE_APP];
        STAssertEqualObjects(self.slash7.appUserId, distinctId, @"identify failed to set distinct id");
        [self.slash7 reset];
    }
}

- (void)testTrack
{
    [self.slash7 track:@"Something Happened"];
    STAssertTrue(self.slash7.eventsQueue.count == 1, @"event not queued");
    NSDictionary *e = self.slash7.eventsQueue.lastObject;
    STAssertEquals([e objectForKey:@"_event_name"], @"Something Happened", @"incorrect event name");
    STAssertNotNil([e objectForKey:@"_app_user_id_type"], @"_app_user_id_type not set");
    STAssertNotNil([e objectForKey:@"_app_user_id"], @"_app_user_id not set");
    STAssertNotNil([e objectForKey:@"_time"], @"_time not set");

    NSDictionary *p = [e objectForKey:@"_event_params"];
    STAssertTrue(p.count == 12, @"incorrect number of properties");

    STAssertNotNil([p objectForKey:@"$app_version"], @"$app_version not set");
    STAssertNotNil([p objectForKey:@"$app_release"], @"$app_release not set");
    STAssertNotNil([p objectForKey:@"$lib_version"], @"$lib_version not set");
    STAssertEqualObjects([p objectForKey:@"$manufacturer"], @"Apple", @"incorrect $manufacturer");
    STAssertNotNil([p objectForKey:@"$model"], @"$model not set");
    STAssertNotNil([p objectForKey:@"$os"], @"$os not set");
    STAssertNotNil([p objectForKey:@"$os_version"], @"$os_version not set");
    STAssertNotNil([p objectForKey:@"$screen_height"], @"$screen_height not set");
    STAssertNotNil([p objectForKey:@"$screen_width"], @"$screen_width not set");
    STAssertEqualObjects([p objectForKey:@"$lib"], @"iphone", @"incorrect mp_lib");
    STAssertNotNil([p objectForKey:@"$ios_ifa"], @"$ios_ifa not set");
}

- (void)testTrackProperties
{
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"yello",                   @"string",
                       [NSNumber numberWithInt:3], @"number",
                       [NSDate date],              @"date",
                       @"override",                @"$app_version",
                       nil];
    [self.slash7 track:@"Something Happened" withParams:p];
    STAssertTrue(self.slash7.eventsQueue.count == 1, @"event not queued");
    NSDictionary *e = self.slash7.eventsQueue.lastObject;
    STAssertEquals([e objectForKey:@"_event_name"], @"Something Happened", @"incorrect event name");
    p = [e objectForKey:@"_event_params"];
    STAssertTrue(p.count == 15, @"incorrect number of properties");
    STAssertEqualObjects([p objectForKey:@"$app_version"], @"override", @"reserved property override failed");
}

- (void)testTrackWithCustomDistinctIdAndToken
{
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"t1",                      @"token",
                       @"d1",                      @"distinct_id",
                       nil];
    [self.slash7 track:@"e1" withParams:p];
    NSString *trackToken = [[self.slash7.eventsQueue.lastObject objectForKey:@"_event_params"] objectForKey:@"token"];
    NSString *trackDistinctId = [[self.slash7.eventsQueue.lastObject objectForKey:@"_event_params"] objectForKey:@"distinct_id"];
    STAssertEqualObjects(trackToken, @"t1", @"user-defined distinct id not used in track. got: %@", trackToken);
    STAssertEqualObjects(trackDistinctId, @"d1", @"user-defined distinct id not used in track. got: %@", trackDistinctId);
}

- (void)testUserAttributes
{
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"a",                       @"p1",
                       [NSNumber numberWithInt:3], @"p2",
                       [NSDate date],              @"p2",
                       nil];

    [self.slash7 setUserAttributes:p];
    STAssertEqualObjects([self.slash7 currentUnsentUserAttributes], p, @"register super properties failed");
    p = [NSDictionary dictionaryWithObject:@"b" forKey:@"p1"];
    [self.slash7 setUserAttributes:p];
    STAssertEqualObjects([[self.slash7 currentUnsentUserAttributes] objectForKey:@"p1"], @"b",
                         @"register super properties failed to overwrite existing value");
    [self.slash7 track:@"Some event"];
    STAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"Unsent user attributes should be cleared after track");
}

- (void)testAssertPropertyTypes
{
    NSDictionary *p = [NSDictionary dictionaryWithObject:[NSData data] forKey:@"data"];
    STAssertThrows([self.slash7 track:@"e1" withParams:p], @"property type should not be allowed");
    STAssertThrows([self.slash7 setUserAttributes:p], @"property type should not be allowed");
    p = [self allPropertyTypes];
    STAssertNoThrow([self.slash7 track:@"e1" withParams:p], @"property type should be allowed");
    STAssertNoThrow([self.slash7 setUserAttributes:p], @"property type should be allowed");
}

- (void)testReset
{
    NSDictionary *p = [NSDictionary dictionaryWithObject:@"a" forKey:@"p1"];
    [self.slash7 identify:@"d1"];
    [self.slash7 setUserAttributes:p];
    [self.slash7 track:@"e1"];
    [self.slash7 archive];

    [self.slash7 reset];
    STAssertEqualObjects(self.slash7.appUserId, [self.slash7 defaultAppUserId], @"distinct id failed to reset");
    STAssertEqualObjects(self.slash7.appUserIdType, [self.slash7 defaultAppUserIdType], @"distinct id type failed to reset");
    STAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"super properties failed to reset");
    STAssertTrue(self.slash7.eventsQueue.count == 0, @"events queue failed to reset");
    
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    STAssertEqualObjects(self.slash7.appUserId, [self.slash7 defaultAppUserId], @"distinct id failed to reset after archive");
    STAssertEqualObjects(self.slash7.appUserIdType, [self.slash7 defaultAppUserIdType], @"distinct id type failed to reset after archive");
    STAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"super properties failed to reset after archive");
    STAssertTrue(self.slash7.eventsQueue.count == 0, @"events queue failed to reset after archive");
}

- (void)testFlushTimer
{
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    STAssertNil(self.slash7.timer, @"intializing with a flush interval of 0 still started timer");
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:60] autorelease];
    STAssertNotNil(self.slash7.timer, @"intializing with a flush interval of 60 did not start timer");
}

- (void)testArchive
{
    [self.slash7 archive];
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];

    STAssertEqualObjects(self.slash7.appUserId, [self.slash7 defaultAppUserId], @"default distinct id archive failed");
    STAssertEqualObjects(self.slash7.appUserIdType, [self.slash7 defaultAppUserIdType], @"default app user id type archive failed");
    STAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"default super properties archive failed");
    STAssertTrue(self.slash7.eventsQueue.count == 0, @"default events queue archive failed");

    NSDictionary *p = [NSDictionary dictionaryWithObject:@"a" forKey:@"p1"];
    [self.slash7 identify:@"d1"];
    [self.slash7 setUserAttributes:p];
    [self.slash7 track:@"e1"];

    [self.slash7 archive];
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];

    STAssertEqualObjects(self.slash7.appUserId, @"d1", @"custom distinct archive failed");
    STAssertEqualObjects(self.slash7.appUserIdType, @"app", @"app user id type archive failed");
    STAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"custom super properties archive failed");
    STAssertTrue(self.slash7.eventsQueue.count == 1, @"pending events queue archive failed");

    NSFileManager *fileManager = [NSFileManager defaultManager];

    STAssertTrue([fileManager fileExistsAtPath:[self.slash7 eventsFilePath]], @"events archive file not found");
    STAssertTrue([fileManager fileExistsAtPath:[self.slash7 propertiesFilePath]], @"properties archive file not found");

    // no existing file

    [fileManager removeItemAtPath:[self.slash7 eventsFilePath] error:NULL];
    [fileManager removeItemAtPath:[self.slash7 propertiesFilePath] error:NULL];

    STAssertFalse([fileManager fileExistsAtPath:[self.slash7 eventsFilePath]], @"events archive file not removed");
    STAssertFalse([fileManager fileExistsAtPath:[self.slash7 propertiesFilePath]], @"properties archive file not removed");

    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    STAssertEqualObjects(self.slash7.appUserId, [self.slash7 defaultAppUserId], @"default distinct id from no file failed");
    STAssertEqualObjects(self.slash7.appUserIdType, [self.slash7 defaultAppUserIdType], @"default app user id type archive failed");
    STAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"default super properties from no file failed");
    STAssertNotNil(self.slash7.eventsQueue, @"default events queue from no file is nil");
    STAssertTrue(self.slash7.eventsQueue.count == 0, @"default events queue from no file not empty");

    // corrupt file

    NSData *garbage = [@"garbage" dataUsingEncoding:NSUTF8StringEncoding];
    [garbage writeToFile:[self.slash7 eventsFilePath] atomically:NO];
    [garbage writeToFile:[self.slash7 propertiesFilePath] atomically:NO];

    STAssertTrue([fileManager fileExistsAtPath:[self.slash7 eventsFilePath]], @"garbage events archive file not found");
    STAssertTrue([fileManager fileExistsAtPath:[self.slash7 propertiesFilePath]], @"garbage properties archive file not found");

    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    STAssertEqualObjects(self.slash7.appUserId, [self.slash7 defaultAppUserId], @"default distinct id from garbage failed");
    STAssertEqualObjects(self.slash7.appUserIdType, [self.slash7 defaultAppUserIdType], @"default app user id type archive failed");
    STAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"default super properties from garbage failed");
    STAssertNotNil(self.slash7.eventsQueue, @"default events queue from garbage is nil");
    STAssertTrue(self.slash7.eventsQueue.count == 0, @"default events queue from garbage not empty");
}

- (void)testSlash7Delegate
{
    self.slash7.delegate = self;
    [self.slash7 identify:@"d1"];
    [self.slash7 track:@"e1"];
    [self.slash7 flush];
    STAssertTrue(self.slash7.eventsQueue.count == 1, @"delegate should have stopped flush");
}

- (void)testNilArguments
{
    [self.slash7 identify:nil];
    [self.slash7 track:nil];
    [self.slash7 track:nil withParams:nil];
    [self.slash7 setUserAttributes:nil];

    // legacy behavior
    STAssertTrue(self.slash7.eventsQueue.count == 2, @"track with nil should create mp_event event");
    STAssertEqualObjects([self.slash7.eventsQueue.lastObject objectForKey:@"_event_name"], @"_empty", @"track with nil should create _empty event");
    STAssertNotNil([self.slash7 currentUnsentUserAttributes], @"setting super properties to nil should have no effect");
    STAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"setting super properties to nil should have no effect");

    [self.slash7 identify:nil];
}

- (void)testDateFormatter
{
    NSDate *d1 = [NSDate dateWithTimeIntervalSince1970:0];
    STAssertEqualObjects([self.slash7.dateFormatter stringFromDate:d1], @"1970-01-01T00:00:00Z", @"dateFormatter should format in ISO8601");
    
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss zzz"];
    NSDate *d2 = [dateFormatter dateFromString:@"2012-09-28 19:14:36 PDT"];
    STAssertEqualObjects([self.slash7.dateFormatter stringFromDate:d2], @"2012-09-29T02:14:36Z", @"dateFormatter should format in UTC");
}

- (void)testSendDeviceInfo
{
    self.slash7.sendDeviceInfo = NO;
    [self.slash7 track:@"Something Happened"];
    NSDictionary *e1 = self.slash7.eventsQueue.lastObject;
    STAssertEquals([e1 objectForKey:@"_event_name"], @"Something Happened", @"incorrect event name");
    STAssertNotNil([e1 objectForKey:@"_app_user_id_type"], @"_app_user_id_type not set");
    STAssertNotNil([e1 objectForKey:@"_app_user_id"], @"_app_user_id not set");
    STAssertNotNil([e1 objectForKey:@"_time"], @"_time not set");
    NSDictionary *p1 = [e1 objectForKey:@"_event_params"];
    STAssertTrue(p1.count == 0, @"incorrect number of properties");

    NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:@"v1", @"k1", @"v2", @"k2", nil];
    [self.slash7 track:@"Something Happened" withParams:params];
    NSDictionary *e2 = self.slash7.eventsQueue.lastObject;
    STAssertEquals([e2 objectForKey:@"_event_name"], @"Something Happened", @"incorrect event name");
    STAssertNotNil([e2 objectForKey:@"_app_user_id_type"], @"_app_user_id_type not set");
    STAssertNotNil([e2 objectForKey:@"_app_user_id"], @"_app_user_id not set");
    STAssertNotNil([e2 objectForKey:@"_time"], @"_time not set");
    NSDictionary *p2 = [e2 objectForKey:@"_event_params"];
    STAssertTrue(p2.count == 2, @"incorrect number of properties");
}

- (void)testTransaction
{
    NSArray *items = [NSArray arrayWithObjects:
                      [[[Slash7TransactionItem alloc] initWithId:@"item1" withName:@"Item 1" withPrice:100 withNum:3] autorelease],
                      [[[Slash7TransactionItem alloc] initWithId:@"item2" withName:@"Item 2" withPrice:50 withNum:1] autorelease],
                      [[[Slash7TransactionItem alloc] initWithId:@"item3" withName:@"Item 3" withPrice:98 withNum:1] autorelease],
                      nil];
    Slash7Transaction *tx = [[[Slash7Transaction alloc] initWithId:@"tx1" withItems:items] autorelease];
    STAssertTrue(tx.totalPrice == 448, @"total price should be calculated automatically");
    
    tx.totalPrice = 400;
    STAssertTrue(tx.totalPrice == 400, @"total price should be set");
    
    Slash7TransactionItem *item = [tx.items objectAtIndex:2];
    STAssertEqualObjects(item.itemId, @"item3", @"id should be kept");
    STAssertEqualObjects(item.itemName, @"Item 3", @"name should be kept");
    STAssertTrue(item.price == 98, @"price should be kept");
    STAssertTrue(item.num == 1, @"num should be kept");
}

@end
