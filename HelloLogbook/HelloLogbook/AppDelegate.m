//
// AppDelegate.m
// HelloSlash7
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

#import "Logbook.h"

#import "AppDelegate.h"

#import "ViewController.h"

// IMPORTANT!!! replace with your tracking code
#define TRACKING_CODE @"YOUR_TRACKING_CODE"

@implementation AppDelegate

- (void)dealloc
{
    [_startTime release];
    [_window release];
    [_viewController release];
    [super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    
    // Override point for customization after application launch.
    
    // Initialize the SLASH-7 object
    self.slash7 = [Slash7 sharedInstanceWithCode:TRACKING_CODE];

    // Set the upload interval to 20 seconds for demonstration purposes. This would be overkill for most applications.
    self.slash7.flushInterval = 20; // defaults to 60 seconds

    // Set some user attributes
    [self.slash7 setUserAttributes:[NSDictionary dictionaryWithObjectsAndKeys:@"Premium", @"Plan", nil]];
    
    self.viewController = [[[ViewController alloc] initWithNibName:@"ViewController" bundle:nil] autorelease];
    self.window.rootViewController = self.viewController;
    [self.window makeKeyAndVisible];
    
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound | UIRemoteNotificationTypeAlert)];
    
    return YES;
}

#pragma mark * Push notifications

- (void)application:(UIApplication *)app didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)devToken {
}

- (void)application:(UIApplication *)app didFailToRegisterForRemoteNotificationsWithError:(NSError *)err {
#if TARGET_IPHONE_SIMULATOR
    NSLog(@"%@ push registration error is expected on simulator", self);
#else
    NSLog(@"%@ push registration error: %@", self, err);
#endif
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo
{
    // Show alert for push notifications recevied while the app is running
    NSString *message = [[userInfo objectForKey:@"aps"] objectForKey:@"alert"];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
                                                    message:message
                                                   delegate:nil
                                          cancelButtonTitle:@"OK"
                                          otherButtonTitles:nil];
    [alert show];
    [alert release];
}

#pragma mark * Session timing example

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    self.startTime = [NSDate date];
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    NSLog(@"%@ will resign active", self);
    NSNumber *seconds = [NSNumber numberWithDouble:[[NSDate date] timeIntervalSinceDate:self.startTime]];
    [[Slash7 sharedInstance] track:@"Session" withParams:[NSDictionary dictionaryWithObject:seconds forKey:@"Length"]];
}

#pragma mark * Background task tracking test

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    self.bgTask = [application beginBackgroundTaskWithExpirationHandler:^{

        NSLog(@"%@ background task %u cut short", self, self.bgTask);

        [application endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    }];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        NSLog(@"%@ starting background task %u", self, self.bgTask);

        // track some events and set some user attributes
        Slash7 *slash7 = [Slash7 sharedInstance];
        [slash7 setUserAttributes:[NSDictionary dictionaryWithObject:@"Hi!" forKey:@"Background user attributes"]];
        [slash7 track:@"Background Event"];

        NSLog(@"%@ ending background task %u", self, self.bgTask);
        [application endBackgroundTask:self.bgTask];
        self.bgTask = UIBackgroundTaskInvalid;
    });

    NSLog(@"%@ dispatched background task %u", self, self.bgTask);

}

@end
