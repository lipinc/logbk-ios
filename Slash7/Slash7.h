//
// Slash7.h
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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

/*!
 @abstract
 Enum to represent app user id type.
 */
typedef enum {
    S7_USER_ID_TYPE_APP = 0,
    S7_USER_ID_TYPE_FACEBOOK,
    S7_USER_ID_TYPE_TWITTER,
    S7_USER_ID_TYPE_GREE,
    S7_USER_ID_TYPE_MOBAGE,
    S7_USER_ID_TYPE_COOKIE
} S7AppUserIdType;

@interface Slash7TransactionItem : NSObject
@property (nonatomic,copy) NSString *itemId;
@property (nonatomic,copy) NSString *itemName;
@property (nonatomic,assign) NSInteger price;
@property (nonatomic,assign) NSUInteger num;
@property (nonatomic,copy) NSString *category1;
@property (nonatomic,copy) NSString *category2;
@property (nonatomic,copy) NSString *category3;
- (id)initWithId:(NSString *)itemId withPrice:(NSInteger)price;
- (id)initWithId:(NSString *)itemId withName:(NSString *)itemName withPrice:(NSInteger)price withNum:(NSUInteger)num;
@end

@interface Slash7Transaction : NSObject
/*!
 @property
 
 @abstract
 Total price of this transaction.
 
 @discussion
 This property is initialized to sumation of (price * num) by initialization.
 You need to set only when you set different total price for the transaction.
 */
@property (nonatomic, assign) NSInteger totalPrice;
@property(nonatomic,copy) NSString *transactionId;
@property(nonatomic,retain) NSArray *items;
-(id)initWithId:(NSString *)transactionId withItem:(Slash7TransactionItem *)item;
-(id)initWithId:(NSString *)transactionId withItems:(NSArray *)items;
@end

@protocol Slash7Delegate;

/*!
 @class
 Slash7 API.
 
 @abstract
 The primary interface for integrating Slash7 with your app.
 
 @discussion
 Use the Slash7 class to set up your project and track events.
 
 <pre>
 // Initialize the API
 Slash7 *Slash7 = [Slash7 sharedInstanceWithCode:@"YOUR TRACKING CODE"];
 
 // Track an event
 [Slash7 track:@"Button Clicked"];
 </pre>
 */
@interface Slash7 : NSObject

/*!
 @property
 
 @abstract
 The distinct ID of the current user.
 
 @discussion
 A distinct ID is a string that uniquely identifies one of your users.
 Typically, this is the user ID from your database. By default, we'll use a
 hash of the MAC address of the device. To change the current distinct ID,
 use the <code>identify:</code> method.
 */
@property(nonatomic,readonly,copy) NSString *appUserId;

/*!
 @property

 @abstract
 The type of user id.
 */
@property(nonatomic,readonly,copy) NSString *appUserIdType;

/*!
 @property
 
 @abstract
 The base URL used for Slash7 API requests.
 
 @discussion
 Useful if you need to proxy Slash7 requests. Defaults to https://tracker.slash-7.com.
 */
@property(nonatomic,copy) NSString *serverURL;

/*!
 @property
 
 @abstract
 Flush timer's interval.
 
 @discussion
 Setting a flush interval of 0 will turn off the flush timer.
 */
@property(nonatomic,assign) NSUInteger flushInterval;

/*!
 @property

 @abstract
 Control whether the library should flush data to Slash7 when the app
 enters the background.

 @discussion
 Defaults to YES. Only affects apps targeted at iOS 4.0, when background 
 task support was introduced, and later.
 */
@property(nonatomic,assign) BOOL flushOnBackground;

/*!
 @property

 @abstract
 Controls whether to show spinning network activity indicator when flushing
 data to the Slash7 servers.

 @discussion
 Defaults to YES.
 */
@property(nonatomic,assign) BOOL showNetworkActivityIndicator;

/*!
 @property
 
 @abstract
 Controls whether to send device info as parameters.
 
 @discussion
 Defaults to YES.
 */
@property(nonatomic,assign) BOOL sendDeviceInfo;

/*!
 @property
 
 @abstract
 The a Slash7Delegate object that can be used to assert fine-grain control
 over Slash7 network activity.
 
 @discussion
 Using a delegate is optional. See the documentation for Slash7Delegate 
 below for more information.
 */
@property(nonatomic,assign) id<Slash7Delegate> delegate; // allows fine grain control over uploading (optional)

/*!
 @method
 
 @abstract
 Initializes and returns a singleton instance of the API.
 
 @discussion
 If you are only going to send data to a single Slash7 project from your app,
 as is the common case, then this is the easiest way to use the API. This
 method will set up a singleton instance of the <code>Slash7</code> class for
 you using the given project tracking code. When you want to make calls to Slash7
 elsewhere in your code, you can use <code>sharedInstance</code>.
 
 <pre>
 [Slash7 sharedInstance] track:@"Something Happened"]];
 </pre>
 
 If you are going to use this singleton approach,
 <code>sharedInstanceWithCode:</code> <b>must be the first call</b> to the
 <code>Slash7</code> class, since it performs important initializations to
 the API.
 
 @param trackingCode        your project tracking code
 */
+ (instancetype)sharedInstanceWithCode:(NSString *)trackingCode;

/*!
 @method
 
 @abstract
 Returns the previously instantiated singleton instance of the API.
 
 @discussion
 The API must be initialized with <code>sharedInstanceWithCode:</code> before
 calling this class method.
 */
+ (instancetype)sharedInstance;

/*!
 @method
 
 @abstract
 Initializes an instance of the API with the given project tracking code.
 
 @discussion
 Returns the a new API object. This allows you to create more than one instance
 of the API object, which is convenient if you'd like to send data to more than
 one Slash7 project from a single app. If you only need to send data to one
 project, consider using <code>sharedInstanceWithCode:</code>.
 
 @param trackingCode        your project tracking code
 @param startFlushTimer whether to start the background flush timer
 */
- (id)initWithCode:(NSString *)trackingCode andFlushInterval:(NSUInteger)flushInterval;

/*!
 @property

 @abstract
 Sets the distinct ID of the current user.

 @discussion
 S7_USER_ID_TYPE_APP is used for type.

 @param appUserId string that uniquely identifies the current user
 */
- (void)identify:(NSString *)appUserId;

/*!
 @property
 
 @abstract
 Sets the ID of the current user.
 
 @param app_user_id string that uniquely identifies the current user
 @param type the type of app_user_id
 */

- (void)identify:(NSString *)appUserId withType:(S7AppUserIdType)type;

/*!
 @method
 
 @abstract
 Tracks an event.
 
 @param event           event name
 */
- (void)track:(NSString *)event;

/*!
 @method
 
 @abstract
 Tracks an event with properties.
 
 @discussion
 Params will allow you to segment your events in your Slash7 reports.
 Property keys must be <code>NSString</code> objects and values must be
 <code>NSString</code>, <code>NSNumber</code>, <code>NSNull</code>,
 <code>NSDate</code> or <code>NSURL</code> objects.
 
 @param event           event name
 @param params      properties dictionary
 */
- (void)track:(NSString *)event withParams:(NSDictionary *)params;

- (void)track:(NSString *)event withTransaction:(Slash7Transaction *)transaction;

- (void)track:(NSString *)event withTransaction:(Slash7Transaction *)transaction withParams:(NSDictionary *)params;

/*!
 @method
 
 @abstract
 Set user attributes on the current user.
 
 @discussion
 The properties will be set on the current user. The keys must be NSString
 objects and the values should be NSString, NSNumber, NSDate, or
 NSNull objects. We use an NSAssert to enforce this type requirement. In
 release mode, the assert is stripped out and we will silently convert
 incorrect types to strings using [NSString stringWithFormat:@"%@", value].
 If the existing
 user record on the server already has a value for a given property, the old
 value is overwritten. Other existing properties will not be affected.
 
 @param attributes       attributes dictionary
 
 */
- (void)setUserAttributes:(NSDictionary *)attributes;

/*!
 @method
 
 @abstract
 Convenience method for setting a single property in Slash7.
 
 @discussion
 Property keys must be <code>NSString</code> objects and values must be
 <code>NSString</code>, <code>NSNumber</code>, <code>NSNull</code>,
 <code>NSDate</code> or <code>NSURL</code> objects.
 
 @param name        property name
 @param object          property value
 */
- (void)setUserAttribute:(NSString *)attribute to:(id)object;

- (NSDictionary *)currentUnsentUserAttributes;

/*!
 @method
 
 @abstract
 Clears all stored properties and distinct IDs. Useful if your app's user logs out.
 */
- (void)reset;

/*!
 @method
 
 @abstract
 Uploads queued data to the Slash7 server.
 
 @discussion
 By default, queued data is flushed to the Slash7 servers every minute (the
 default for <code>flushInvterval</code>), and on background (since
 <code>flushOnBackground</code> is on by default). You only need to call this
 method manually if you want to force a flush at a particular moment.
 */
- (void)flush;

/*!
 @method

 @abstract
 Writes current project info, including distinct ID, super properties and pending event
 and People record queues to disk.

 @discussion
 This state will be recovered when the app is launched again if the Slash7
 library is initialized with the same project tracking code. <b>You do not need to call
 this method</b>. The library listens for app state changes and handles
 persisting data as needed. It can be useful in some special circumstances,
 though, for example, if you'd like to track app crashes from main.m.
 */
- (void)archive;

@end

/*!
 @protocol
 
 @abstract
 Delegate protocol for controlling the Slash7 API's network behavior.
 
 @discussion
 Creating a delegate for the Slash7 object is entirely optional. It is only
 necessary when you want full control over when data is uploaded to the server,
 beyond simply calling stop: and start: before and after a particular block of
 your code.
 */
@protocol Slash7Delegate <NSObject>
@optional

/*!
 @method
 
 @abstract
 Asks the delegate if data should be uploaded to the server. 
 
 @discussion
 Return YES to upload now, NO to defer until later.
 
 @param Slash7        Slash7 API instance
 */
- (BOOL)slash7WillFlush:(Slash7 *)Slash7;

@end
