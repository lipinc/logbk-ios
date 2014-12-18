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

#import "HelloLogbookTests.h"

#import "Logbook.h"
#import "S7CJSONSerializer.h"

#define TEST_TOKEN @"abc123"

@interface Slash7 (Test)

// get access to private members
@property(nonatomic,retain) NSMutableArray *eventsQueue;
@property(nonatomic,retain) NSTimer *timer;
@property(nonatomic,retain) NSDateFormatter *dateFormatter;
@property(nonatomic,assign) BOOL projectDeleted;

+ (NSData *)JSONSerializeObject:(id)obj;
- (NSString *)randomAppUserId;
- (NSString *)defaultAppUserIdType;
- (void)archive;
- (NSString *)eventsFilePath;
- (NSString *)propertiesFilePath;

@end

@interface Slash7TransactionItem (Test)
-(NSDictionary *)properties;
@end

@interface Slash7Transaction (Test)
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

-(void)removeArchiveFiles
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    [fileManager removeItemAtPath:[self.slash7 eventsFilePath] error:NULL];
    [fileManager removeItemAtPath:[self.slash7 propertiesFilePath] error:NULL];
}

- (void)testJSONSerializeObject {
    NSDictionary *test = [self allPropertyTypes];
    NSData *data = [Slash7 JSONSerializeObject:[NSArray arrayWithObject:test]];
    NSString *json = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    XCTAssertEqualObjects(json, @"[{\"float\":1.3,\"null\":null,\"date\":\"2012-09-29T02:14:36\",\"number\":3,\"url\":\"https:\\/\\/slash-7.com\\/\",\"string\":\"yello\"}]", @"json serialization failed");

    test = [NSDictionary dictionaryWithObject:@"non-string key" forKey:@3];
    data = [Slash7 JSONSerializeObject:[NSArray arrayWithObject:test]];
    json = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    XCTAssertEqualObjects(json, @"[{\"3\":\"non-string key\"}]", @"json serialization failed");
}

- (void)testItemProperty {
    Slash7TransactionItem *item1 = [[[Slash7TransactionItem alloc] initWithId:@"item1" withName:@"Iron sword" withPrice:90 withNum:2] autorelease];
    NSDictionary *p1 = [item1 properties];
    XCTAssertEqualObjects([p1 objectForKey:@"_item_id"], @"item1", @"_item_id should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_name"], @"Iron sword", @"_name should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_price"], [NSNumber numberWithInt:90], @"_price should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_num"],[NSNumber numberWithInt:2], @"_num should be set");
    XCTAssertNil([p1 objectForKey:@"_category1"], @"category1 should not be set");
    XCTAssertNil([p1 objectForKey:@"_category2"], @"category1 should not be set");
    XCTAssertNil([p1 objectForKey:@"_category3"], @"category1 should not be set");
    
    Slash7TransactionItem *item2 = [[[Slash7TransactionItem alloc] initWithId:@"item2" withPrice:100] autorelease];
    NSDictionary *p2 = [item2 properties];
    XCTAssertEqualObjects([p2 objectForKey:@"_item_id"], @"item2", @"_item_id should be set");
    XCTAssertEqualObjects([p2 objectForKey:@"_name"], @"item2", @"_name should be set");
    XCTAssertEqualObjects([p2 objectForKey:@"_price"], [NSNumber numberWithInt:100], @"_price should be set");
    XCTAssertEqualObjects([p2 objectForKey:@"_num"],[NSNumber numberWithInt:1], @"_num should be set");
    XCTAssertNil([p2 objectForKey:@"_category1"], @"category1 should not be set");
    XCTAssertNil([p2 objectForKey:@"_category2"], @"category1 should not be set");
    XCTAssertNil([p2 objectForKey:@"_category3"], @"category1 should not be set");
}

- (void)testItemPropertyWithCategory {
    Slash7TransactionItem *item1 = [[[Slash7TransactionItem alloc] initWithId:@"item1" withName:@"Iron sword" withPrice:90 withNum:2] autorelease];
    item1.category1 = @"Category 1";
    item1.category2 = @"Category 2";
    item1.category3 = @"Category 3";
    
    NSDictionary *p1 = [item1 properties];
    XCTAssertEqualObjects([p1 objectForKey:@"_item_id"], @"item1", @"_item_id should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_name"], @"Iron sword", @"_name should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_price"], [NSNumber numberWithInt:90], @"_price should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_num"],[NSNumber numberWithInt:2], @"_num should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_category1"], @"Category 1", @"category1 should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_category2"], @"Category 2", @"category2 should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_category3"], @"Category 3", @"category3 should be set");
}

- (void)testTransaction
{
    NSArray *items = [NSArray arrayWithObjects:
                      [[[Slash7TransactionItem alloc] initWithId:@"item1" withName:@"Item 1" withPrice:100 withNum:3] autorelease],
                      [[[Slash7TransactionItem alloc] initWithId:@"item2" withName:@"Item 2" withPrice:50 withNum:1] autorelease],
                      [[[Slash7TransactionItem alloc] initWithId:@"item3" withName:@"Item 3" withPrice:98 withNum:1] autorelease],
                      nil];
    Slash7Transaction *tx = [[[Slash7Transaction alloc] initWithId:@"tx1" withItems:items] autorelease];
    XCTAssertTrue(tx.totalPrice == 448, @"total price should be calculated automatically");
    
    tx.totalPrice = 400;
    XCTAssertTrue(tx.totalPrice == 400, @"total price should be set");
    
    Slash7TransactionItem *item = [tx.items objectAtIndex:2];
    XCTAssertEqualObjects(item.itemId, @"item3", @"id should be kept");
    XCTAssertEqualObjects(item.itemName, @"Item 3", @"name should be kept");
    XCTAssertTrue(item.price == 98, @"price should be kept");
    XCTAssertTrue(item.num == 1, @"num should be kept");
}

-(void)testTransactionProperties
{
    NSArray *items = [NSArray arrayWithObjects:
                      [[[Slash7TransactionItem alloc] initWithId:@"item1" withName:@"Item 1" withPrice:100 withNum:3] autorelease],
                      [[[Slash7TransactionItem alloc] initWithId:@"item2" withName:@"Item 2" withPrice:50 withNum:1] autorelease],
                      [[[Slash7TransactionItem alloc] initWithId:@"item3" withName:@"Item 3" withPrice:98 withNum:1] autorelease],
                      nil];
    Slash7Transaction *tx = [[[Slash7Transaction alloc] initWithId:@"tx1" withItems:items] autorelease];
    NSDictionary *p = [tx properties];
    XCTAssertEqualObjects([p objectForKey:@"_transact_id"], @"tx1", @"id should be set");
    XCTAssertEqualObjects([p objectForKey:@"_total_price"], @448, @"total price should be set");
    XCTAssertNotNil([p objectForKey:@"_items"], @"items should be set");
    XCTAssertTrue([[p objectForKey:@"_items"] count] == 3, @"items should have length 3");
}

-(void)testTransactionPropertiesNil
{
    Slash7Transaction *tx1 = [[[Slash7Transaction alloc] initWithId:@"tx1" withItems:nil] autorelease];
    XCTAssertTrue([[tx1 properties] count] == 0, @"it should return empty dictionary with nil items");

    Slash7Transaction *tx2 = [[[Slash7Transaction alloc] initWithId:@"tx2" withItems:[NSArray array]] autorelease];
    XCTAssertTrue([[tx2 properties] count] == 0, @"it should return empty dictionary with empty items");
    
    Slash7Transaction *tx3 = [[[Slash7Transaction alloc] initWithId:@"tx3" withItem:nil] autorelease];
    XCTAssertTrue([[tx3 properties] count] == 0, @"it should return empty dictionary with empty items");

    Slash7Transaction *tx4 = [[[Slash7Transaction alloc] initWithId:nil withItem:nil] autorelease];
    XCTAssertTrue([[tx4 properties] count] == 0, @"it should return empty dictionary with empty items");

    Slash7TransactionItem *item1 = [[[Slash7TransactionItem alloc] initWithId:@"item1" withPrice:100] autorelease];
    Slash7Transaction *tx5 = [[[Slash7Transaction alloc] initWithId:nil withItem:item1] autorelease];
    NSDictionary *p5 = [tx5 properties];
    XCTAssertNotNil([p5 objectForKey:@"_transact_id"], @"id should be set");
    XCTAssertNotNil([p5 objectForKey:@"_items"], @"items should be set");
    XCTAssertEqualObjects([p5 objectForKey:@"_total_price"], @100, @"price should be set");
}

-(void)testItemPropertyNil {
    Slash7TransactionItem *item1 = [[[Slash7TransactionItem alloc] initWithId:nil withName:nil withPrice:0 withNum:0] autorelease];
    NSDictionary *p1 = [item1 properties];
    XCTAssertEqualObjects([p1 objectForKey:@"_item_id"], @"_empty", @"_item_id should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_name"], @"_empty", @"_name should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_price"], [NSNumber numberWithInt:0], @"_price should be set");
    XCTAssertEqualObjects([p1 objectForKey:@"_num"],[NSNumber numberWithInt:0], @"_num should be set");
    XCTAssertNil([p1 objectForKey:@"_category1"], @"category1 should not be set");
    XCTAssertNil([p1 objectForKey:@"_category2"], @"category1 should not be set");
    XCTAssertNil([p1 objectForKey:@"_category3"], @"category1 should not be set");
}

- (void)testIdentify
{
    for (int i = 0; i < 2; i++) { // run this twice to test reset works correctly wrt to distinct ids

        NSString *distinctId = @"d1";
        // try this for IFA, ODIN and nil
        XCTAssertNotNil(self.slash7.appUserId, @"identify failed to set default user id");
        XCTAssertEqualObjects(self.slash7.appUserIdType, self.slash7.defaultAppUserIdType, @"identify failed to set default user id type");
        [self.slash7 identify:distinctId withType:S7_USER_ID_TYPE_APP];
        XCTAssertEqualObjects(self.slash7.appUserId, distinctId, @"identify failed to set distinct id");
        [self.slash7 reset];
    }
}

- (void)testRandomUserId
{
    [self removeArchiveFiles];
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    NSString *prev = self.slash7.appUserId;
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertEqualObjects(self.slash7.appUserIdType, @"cookie", @"incorrect app user id type");
    XCTAssertEqualObjects(self.slash7.appUserId, prev, @"randomly generated user id should be kept");
}

- (void)testTrack
{
    [self.slash7 setUserAttribute:@"gender" to:@"Female"];
    [self.slash7 setUserAttribute:@"age" to:@30];
    [self.slash7 track:@"Something Happened"];
    XCTAssertTrue(self.slash7.eventsQueue.count == 1, @"event not queued");
    NSDictionary *e = self.slash7.eventsQueue.lastObject;
    XCTAssertTrue(e.count == 7, @"incorrect number of event keys");
    XCTAssertEqual([e objectForKey:@"_event_name"], @"Something Happened", @"incorrect event name");
    XCTAssertNotNil([e objectForKey:@"_app_user_id_type"], @"_app_user_id_type not set");
    XCTAssertNotNil([e objectForKey:@"_app_user_id"], @"_app_user_id not set");
    XCTAssertNotNil([e objectForKey:@"_time"], @"_time not set");
    NSDictionary *p = [e objectForKey:@"_event_params"];
    XCTAssertTrue(p.count == 0, @"incorrect number of properties");
    XCTAssertEqualObjects([e objectForKey:@"gender"], @"Female", @"gender not set");
    XCTAssertEqualObjects([e objectForKey:@"age"], @30, @"age not set");
}

- (void)testTrackDeviceInfo
{
    self.slash7.sendDeviceInfo = YES;
    [self.slash7 setUserAttribute:@"gender" to:@"Female"];
    // Manufacturer can't be overridden
    [self.slash7 setUserAttribute:@"manufacturer" to:@"pLucky"];
    [self.slash7 track:@"Something Happened"];
    XCTAssertTrue(self.slash7.eventsQueue.count == 1, @"event not queued");
    NSDictionary *e = self.slash7.eventsQueue.lastObject;

    // e.count depends on whether career is available
    XCTAssertTrue(e.count == 17 || e.count == 18, @"incorrect number of event keys");
    
    XCTAssertEqual([e objectForKey:@"_event_name"], @"Something Happened", @"incorrect event name");
    XCTAssertNotNil([e objectForKey:@"_app_user_id_type"], @"_app_user_id_type not set");
    XCTAssertNotNil([e objectForKey:@"_app_user_id"], @"_app_user_id not set");
    XCTAssertNotNil([e objectForKey:@"_time"], @"_time not set");
    
    XCTAssertEqualObjects([e objectForKey:@"gender"], @"Female", @"gender not set");
    
    XCTAssertNotNil([e objectForKey:@"app_version"], @"app_version not set");
    XCTAssertNotNil([e objectForKey:@"app_release"], @"app_release not set");
    XCTAssertNotNil([e objectForKey:@"lib_version"], @"lib_version not set");
    XCTAssertEqualObjects([e objectForKey:@"manufacturer"], @"Apple", @"incorrect manufacturer");
    XCTAssertNotNil([e objectForKey:@"model"], @"model not set");
    XCTAssertNotNil([e objectForKey:@"os"], @"os not set");
    XCTAssertNotNil([e objectForKey:@"os_version"], @"os_version not set");
    XCTAssertNotNil([e objectForKey:@"screen_height"], @"screen_height not set");
    XCTAssertNotNil([e objectForKey:@"screen_width"], @"screen_width not set");
    XCTAssertEqualObjects([e objectForKey:@"lib"], @"iOS", @"incorrect lib");
    XCTAssertNotNil([e objectForKey:@"wifi"], @"wifi not set");
    
    NSDictionary *p = [e objectForKey:@"_event_params"];
    XCTAssertTrue(p.count == 0, @"incorrect number of properties");
    
}

- (void)testTrackProperties
{
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"yello",                   @"string",
                       [NSNumber numberWithInt:3], @"number",
                       [NSDate date],              @"date",
                       nil];
    [self.slash7 track:@"Something Happened" withParams:p];
    XCTAssertTrue(self.slash7.eventsQueue.count == 1, @"event not queued");
    NSDictionary *e = self.slash7.eventsQueue.lastObject;
    XCTAssertEqual([e objectForKey:@"_event_name"], @"Something Happened", @"incorrect event name");
    p = [e objectForKey:@"_event_params"];
    XCTAssertTrue(p.count == 3, @"incorrect number of properties");
}

-(void)testTrackTransaction
{
    NSArray *items = [NSArray arrayWithObjects:
                      [[[Slash7TransactionItem alloc] initWithId:@"item1" withName:@"Item 1" withPrice:100 withNum:3] autorelease],
                      [[[Slash7TransactionItem alloc] initWithId:@"item2" withName:@"Item 2" withPrice:50 withNum:1] autorelease],
                      [[[Slash7TransactionItem alloc] initWithId:@"item3" withName:@"Item 3" withPrice:98 withNum:1] autorelease],
                      nil];
    Slash7Transaction *tx = [[[Slash7Transaction alloc] initWithId:@"tx1" withItems:items] autorelease];
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"yello",                   @"string",
                       [NSNumber numberWithInt:3], @"number",
                       [NSDate date],              @"date",
                       nil];
    [self.slash7 track:@"Something Happened" withTransaction:tx withParams:p];
    XCTAssertTrue(self.slash7.eventsQueue.count == 1, @"event not queued");
    NSDictionary *e = self.slash7.eventsQueue.lastObject;
    XCTAssertEqual([e objectForKey:@"_event_name"], @"Something Happened", @"incorrect event name");
    XCTAssertNotNil([e objectForKey:@"_app_user_id_type"], @"_app_user_id_type not set");
    XCTAssertNotNil([e objectForKey:@"_app_user_id"], @"_app_user_id not set");
    XCTAssertNotNil([e objectForKey:@"_time"], @"_time not set");
    XCTAssertNotNil([e objectForKey:@"_transact_id"], @"_transact_id not set");
    XCTAssertNotNil([e objectForKey:@"_items"], @"_items not set");
    XCTAssertNotNil([e objectForKey:@"_total_price"], @"_total_price not set");
    
    p = [e objectForKey:@"_event_params"];
    XCTAssertTrue(p.count == 3, @"incorrect number of properties");
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
    XCTAssertEqualObjects(trackToken, @"t1", @"user-defined distinct id not used in track. got: %@", trackToken);
    XCTAssertEqualObjects(trackDistinctId, @"d1", @"user-defined distinct id not used in track. got: %@", trackDistinctId);
}

- (void)testTrackWithDeletedProject
{
    self.slash7.projectDeleted = YES;
    [self.slash7 track:@"Something Happened"];
    XCTAssertTrue(self.slash7.eventsQueue.count == 0, @"event should not queued");
}

- (void)testUserAttributes
{
    NSDictionary *p = [NSDictionary dictionaryWithObjectsAndKeys:
                       @"a",                       @"p1",
                       [NSNumber numberWithInt:3], @"p2",
                       [NSDate date],              @"p2",
                       nil];

    [self.slash7 setUserAttributes:p];
    XCTAssertEqualObjects([self.slash7 currentUnsentUserAttributes], p, @"register super properties failed");
    p = [NSDictionary dictionaryWithObject:@"b" forKey:@"p1"];
    [self.slash7 setUserAttributes:p];
    XCTAssertEqualObjects([[self.slash7 currentUnsentUserAttributes] objectForKey:@"p1"], @"b",
                         @"register super properties failed to overwrite existing value");
    [self.slash7 track:@"Some event"];
    XCTAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"Unsent user attributes should be cleared after track");
}

- (void)testAssertPropertyTypes
{
    NSDictionary *p = [NSDictionary dictionaryWithObject:[NSData data] forKey:@"data"];
    XCTAssertThrows([self.slash7 track:@"e1" withParams:p], @"property type should not be allowed");
    XCTAssertThrows([self.slash7 setUserAttributes:p], @"property type should not be allowed");
    p = [self allPropertyTypes];
    XCTAssertNoThrow([self.slash7 track:@"e1" withParams:p], @"property type should be allowed");
    XCTAssertNoThrow([self.slash7 setUserAttributes:p], @"property type should be allowed");
}

- (void)testReset
{
    NSDictionary *p = [NSDictionary dictionaryWithObject:@"a" forKey:@"p1"];
    [self.slash7 identify:@"d1"];
    [self.slash7 setUserAttributes:p];
    [self.slash7 track:@"e1"];
    self.slash7.projectDeleted = YES;
    [self.slash7 archive];

    [self.slash7 reset];
    NSString *appUserIdAfterReset = self.slash7.appUserId;
    XCTAssertNotNil(self.slash7.appUserId, @"default distinct id from no file failed");
    XCTAssertFalse([self.slash7.appUserId isEqualToString:@"d1"], @"default distinct id from no file failed");
    XCTAssertEqualObjects(self.slash7.appUserIdType, [self.slash7 defaultAppUserIdType], @"distinct id type failed to reset");
    XCTAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"super properties failed to reset");
    XCTAssertTrue(self.slash7.eventsQueue.count == 0, @"events queue failed to reset");
    XCTAssertFalse(self.slash7.projectDeleted, @"project deleted failed to reset");
    
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertEqualObjects(self.slash7.appUserId, appUserIdAfterReset, @"distinct id failed to reset after archive");
    XCTAssertEqualObjects(self.slash7.appUserIdType, [self.slash7 defaultAppUserIdType], @"distinct id type failed to reset after archive");
    XCTAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"super properties failed to reset after archive");
    XCTAssertTrue(self.slash7.eventsQueue.count == 0, @"events queue failed to reset after archive");
    XCTAssertFalse(self.slash7.projectDeleted, @"project deleted failed to reset");
}

- (void)testFlushTimer
{
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertNil(self.slash7.timer, @"intializing with a flush interval of 0 still started timer");
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:60] autorelease];
    XCTAssertNotNil(self.slash7.timer, @"intializing with a flush interval of 60 did not start timer");
}

- (void)testArchive
{
    NSString *origAppUserId = self.slash7.appUserId;
    [self.slash7 archive];
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertEqualObjects(self.slash7.appUserId, origAppUserId, @"default distinct id archive failed");
    XCTAssertEqualObjects(self.slash7.appUserIdType, [self.slash7 defaultAppUserIdType], @"default app user id type archive failed");
    XCTAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"default super properties archive failed");
    XCTAssertTrue(self.slash7.eventsQueue.count == 0, @"default events queue archive failed");
    XCTAssertFalse(self.slash7.projectDeleted, @"default project deleted archive failed");

    NSDictionary *p = [NSDictionary dictionaryWithObject:@"a" forKey:@"p1"];
    [self.slash7 identify:@"d1"];
    [self.slash7 setUserAttributes:p];
    [self.slash7 track:@"e1"];
    self.slash7.projectDeleted = YES;

    [self.slash7 archive];
    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];

    XCTAssertEqualObjects(self.slash7.appUserId, @"d1", @"custom distinct archive failed");
    XCTAssertEqualObjects(self.slash7.appUserIdType, @"app", @"app user id type archive failed");
    XCTAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"custom super properties archive failed");
    XCTAssertTrue(self.slash7.eventsQueue.count == 1, @"pending events queue archive failed");
    XCTAssertTrue(self.slash7.projectDeleted, @"project deleted archive failed");

    NSFileManager *fileManager = [NSFileManager defaultManager];

    XCTAssertTrue([fileManager fileExistsAtPath:[self.slash7 eventsFilePath]], @"events archive file not found");
    XCTAssertTrue([fileManager fileExistsAtPath:[self.slash7 propertiesFilePath]], @"properties archive file not found");

    // no existing file
    [self removeArchiveFiles];

    XCTAssertFalse([fileManager fileExistsAtPath:[self.slash7 eventsFilePath]], @"events archive file not removed");
    XCTAssertFalse([fileManager fileExistsAtPath:[self.slash7 propertiesFilePath]], @"properties archive file not removed");

    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertNotNil(self.slash7.appUserId, @"default distinct id from no file failed");
    XCTAssertFalse([self.slash7.appUserId isEqualToString:origAppUserId], @"default distinct id from no file failed");
    XCTAssertEqualObjects(self.slash7.appUserIdType, [self.slash7 defaultAppUserIdType], @"default app user id type archive failed");
    XCTAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"default super properties from no file failed");
    XCTAssertNotNil(self.slash7.eventsQueue, @"default events queue from no file is nil");
    XCTAssertTrue(self.slash7.eventsQueue.count == 0, @"default events queue from no file not empty");
    XCTAssertFalse(self.slash7.projectDeleted, @"default project deleted archive failed");

    // corrupt file

    NSData *garbage = [@"garbage" dataUsingEncoding:NSUTF8StringEncoding];
    [garbage writeToFile:[self.slash7 eventsFilePath] atomically:NO];
    [garbage writeToFile:[self.slash7 propertiesFilePath] atomically:NO];

    XCTAssertTrue([fileManager fileExistsAtPath:[self.slash7 eventsFilePath]], @"garbage events archive file not found");
    XCTAssertTrue([fileManager fileExistsAtPath:[self.slash7 propertiesFilePath]], @"garbage properties archive file not found");

    self.slash7 = [[[Slash7 alloc] initWithCode:TEST_TOKEN andFlushInterval:0] autorelease];
    XCTAssertNotNil(self.slash7.appUserId, @"default distinct id from no file failed");
    XCTAssertFalse([self.slash7.appUserId isEqualToString:origAppUserId], @"default distinct id from no file failed");
    XCTAssertEqualObjects(self.slash7.appUserIdType, [self.slash7 defaultAppUserIdType], @"default app user id type archive failed");
    XCTAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"default super properties from garbage failed");
    XCTAssertNotNil(self.slash7.eventsQueue, @"default events queue from garbage is nil");
    XCTAssertTrue(self.slash7.eventsQueue.count == 0, @"default events queue from garbage not empty");
    XCTAssertFalse(self.slash7.projectDeleted, @"default project deleted archive failed");
}

- (void)testSlash7Delegate
{
    self.slash7.delegate = self;
    [self.slash7 identify:@"d1"];
    [self.slash7 track:@"e1"];
    [self.slash7 flush];
    XCTAssertTrue(self.slash7.eventsQueue.count == 1, @"delegate should have stopped flush");
}

- (void)testNilArguments
{
    [self.slash7 identify:nil];
    [self.slash7 track:nil];
    [self.slash7 track:nil withParams:nil];
    [self.slash7 setUserAttributes:nil];

    // legacy behavior
    XCTAssertTrue(self.slash7.eventsQueue.count == 2, @"track with nil should create mp_event event");
    XCTAssertEqualObjects([self.slash7.eventsQueue.lastObject objectForKey:@"_event_name"], @"_empty", @"track with nil should create _empty event");
    XCTAssertNotNil([self.slash7 currentUnsentUserAttributes], @"setting super properties to nil should have no effect");
    XCTAssertTrue([[self.slash7 currentUnsentUserAttributes] count] == 0, @"setting super properties to nil should have no effect");

    [self.slash7 identify:nil];
}

- (void)testDateFormatter
{
    NSDate *d1 = [NSDate dateWithTimeIntervalSince1970:0];
    XCTAssertEqualObjects([self.slash7.dateFormatter stringFromDate:d1], @"1970-01-01T00:00:00Z", @"dateFormatter should format in ISO8601");
    
    NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init] autorelease];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss zzz"];
    NSDate *d2 = [dateFormatter dateFromString:@"2012-09-28 19:14:36 PDT"];
    XCTAssertEqualObjects([self.slash7.dateFormatter stringFromDate:d2], @"2012-09-29T02:14:36Z", @"dateFormatter should format in UTC");
}

- (void)testSendDeviceInfo
{
    self.slash7.sendDeviceInfo = NO;
    [self.slash7 track:@"Something Happened"];
    NSDictionary *e1 = self.slash7.eventsQueue.lastObject;
    XCTAssertEqual([e1 objectForKey:@"_event_name"], @"Something Happened", @"incorrect event name");
    XCTAssertNotNil([e1 objectForKey:@"_app_user_id_type"], @"_app_user_id_type not set");
    XCTAssertNotNil([e1 objectForKey:@"_app_user_id"], @"_app_user_id not set");
    XCTAssertNotNil([e1 objectForKey:@"_time"], @"_time not set");
    NSDictionary *p1 = [e1 objectForKey:@"_event_params"];
    XCTAssertTrue(p1.count == 0, @"incorrect number of properties");

    NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:@"v1", @"k1", @"v2", @"k2", nil];
    [self.slash7 track:@"Something Happened" withParams:params];
    NSDictionary *e2 = self.slash7.eventsQueue.lastObject;
    XCTAssertEqual([e2 objectForKey:@"_event_name"], @"Something Happened", @"incorrect event name");
    XCTAssertNotNil([e2 objectForKey:@"_app_user_id_type"], @"_app_user_id_type not set");
    XCTAssertNotNil([e2 objectForKey:@"_app_user_id"], @"_app_user_id not set");
    XCTAssertNotNil([e2 objectForKey:@"_time"], @"_time not set");
    NSDictionary *p2 = [e2 objectForKey:@"_event_params"];
    XCTAssertTrue(p2.count == 2, @"incorrect number of properties");
}

@end
