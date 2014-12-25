//
//  LBTimer.h
//  HelloLogbook
//
//  Copyright (c) 2014 pLucky, Inc.
//

#import <Foundation/Foundation.h>

@interface LBUsageTimer : NSObject
+ (instancetype)timerWithTimeInterval:(NSTimeInterval)seconds
                        resetInterval:(NSTimeInterval)resetSeconds
                               target:(id)target
                             selector:(SEL)aSelector
                             userInfo:(id)userInfo;
-(void)resume;
-(BOOL)pause;
@end
