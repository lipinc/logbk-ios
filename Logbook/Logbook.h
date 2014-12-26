//
// Logbook.h
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

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@protocol LogbookDelegate;

/*!
 @class
 Logbook API.
 
 @abstract
 The primary interface for integrating Logbook with your app.
 
 @discussion
 Use the Logbook class to set up your project and track events.
 
 <pre>
 // Initialize the API
 Logbook *logbook = [Logbook sharedInstanceWithCode:@"YOUR TRACKING CODE"];
 
 // Track an event
 [logbook track:@"Button Clicked"];
 </pre>
 */
@interface Logbook : NSObject

/*!
 @property
 
 @abstract
 The ramdomly generated ID of the current user.
 
 @discussion
 A ramdomly generated ID is a string that uniquely identifies one of your users.
 */
@property(nonatomic,readonly,copy) NSString *randUser;

@property(nonatomic,readonly,copy) NSString *user;

/*!
 @property
 
 @abstract
 The base URL used for API requests.
 
 @discussion
 Useful if you need to proxy requests. Defaults to https://tracker.logbk.net.
 */
@property(nonatomic,copy) NSString *serverURL;

/*!
 @property

 @abstract
 The endpoint of tracking.

 @discussion
 Defaults to /v1/track
 */
@property(nonatomic,copy) NSString *trackEndpoint;

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
 Control whether the library should flush data to the server when the app
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
 data to the servers.

 @discussion
 Defaults to YES.
 */
@property(nonatomic,assign) BOOL showNetworkActivityIndicator;

/*!
 @property
 
 @abstract
 Controls whether to send device info as parameters.
 
 @discussion
 Defaults to NO.
 */
@property(nonatomic,assign) BOOL sendDeviceInfo;

/*!
 @property
 
 @abstract
 The a LogbookDelegate object that can be used to assert fine-grain control
 over the network activity.
 
 @discussion
 Using a delegate is optional. See the documentation for LogbookDelegate
 below for more information.
 */
@property(nonatomic,assign) id<LogbookDelegate> delegate; // allows fine grain control over uploading (optional)

/*!
 @method
 
 @abstract
 Initializes and returns a singleton instance of the API.
 
 @discussion
 If you are only going to send data to a single project from your app,
 as is the common case, then this is the easiest way to use the API. This
 method will set up a singleton instance of the <code>Logbook</code> class for
 you using the given project tracking code. When you want to make calls to Logbook
 elsewhere in your code, you can use <code>sharedInstance</code>.
 
 <pre>
 [[Logbook sharedInstance] track:@"SomethingHappened"];
 </pre>
 
 If you are going to use this singleton approach,
 <code>sharedInstanceWithCode:</code> <b>must be the first call</b> to the
 <code>Logbook</code> class, since it performs important initializations to
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
 one Logbook project from a single app. If you only need to send data to one
 project, consider using <code>sharedInstanceWithCode:</code>.
 
 @param trackingCode        your project tracking code
 @param startFlushTimer whether to start the background flush timer
 */
- (id)initWithCode:(NSString *)trackingCode andFlushInterval:(NSUInteger)flushInterval;

/*!
 @property

 @abstract
 Sets the current user.

 @param appUserId string that uniquely identifies the current user
 */
- (void)identify:(NSString *)appUserId;

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
 Clears all stored properties and distinct IDs. Useful if your app's user logs out.
 */
- (void)reset;

/*!
 @method
 
 @abstract
 Uploads queued data to the Logbook server.
 
 @discussion
 By default, queued data is flushed to the Logbook servers every minute (the
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
 This state will be recovered when the app is launched again if the Logbook
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
 Delegate protocol for controlling the Logbook API's network behavior.
 
 @discussion
 Creating a delegate for the Logbook object is entirely optional. It is only
 necessary when you want full control over when data is uploaded to the server,
 beyond simply calling stop: and start: before and after a particular block of
 your code.
 */
@protocol LogbookDelegate <NSObject>
@optional

/*!
 @method
 
 @abstract
 Asks the delegate if data should be uploaded to the server. 
 
 @discussion
 Return YES to upload now, NO to defer until later.
 
 @param Logbook        Logbook API instance
 */
- (BOOL)logbookWillFlush:(Logbook *)Logbook;

@end
