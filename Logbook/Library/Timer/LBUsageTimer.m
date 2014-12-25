//
//  LBTimer.m
//  HelloLogbook
//
//  Copyright (c) 2014 pLucky, Inc.
//

#import "LBUsageTimer.h"

#ifdef LOGBOOK_DEBUG
#define LogbookDebug(...) NSLog(__VA_ARGS__)
#else
#define LogbookDebug(...)
#endif

@interface LBUsageTimer ()
@property (nonatomic, assign) NSTimeInterval seconds;
@property (nonatomic, assign) NSTimeInterval resetSeconds;
@property (nonatomic, assign) id target;
@property (nonatomic, assign) SEL selector;
@property (nonatomic, assign) id userInfo;

@property (nonatomic, retain) NSTimer *timer;
@property (nonatomic, assign) NSTimeInterval timerStarted;
@property (nonatomic, assign) BOOL fired;
@property (nonatomic, assign) NSTimeInterval elapsed;
@property (nonatomic, assign) NSTimeInterval usageTimerStarted;
@end

@implementation LBUsageTimer

+ (instancetype)timerWithTimeInterval:(NSTimeInterval)seconds
                        resetInterval:(NSTimeInterval)resetSeconds
                               target:(id)target
                             selector:(SEL)aSelector
                             userInfo:(id)userInfo {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    LBUsageTimer *instance = [self new];
    instance.seconds = seconds;
    instance.resetSeconds = resetSeconds;
    instance.target = target;
    instance.selector = aSelector;
    instance.userInfo = userInfo;
    instance.fired = NO;
    instance.elapsed = 0;
    instance.usageTimerStarted = now;
    return instance;
}

- (void)dealloc {
    [self.timer invalidate];
    self.timer = nil;
    [super dealloc];
}

-(void)fire:(NSTimer *)timer {
    self.fired = YES;
    LogbookDebug(@"LBUsageTimer fired.");
    [self.target performSelector:self.selector withObject:self];
}

-(void)resume {
    [self.timer invalidate];
    self.timer = nil;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

    if (now - self.usageTimerStarted >= self.resetSeconds) {
        LogbookDebug(@"Usage timer reset");
        self.fired = NO;
        self.elapsed = 0;
        self.usageTimerStarted = now;
    }

    if (!self.fired) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:(self.seconds - self.elapsed)
                                                      target:self
                                                    selector:@selector(fire:)
                                                    userInfo:self.userInfo
                                                     repeats:NO];
        self.timerStarted = now;
    }
}


-(BOOL)pause {
    if (self.timer != nil) {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

        [self.timer invalidate];
        self.timer = nil;

        self.elapsed += now - self.timerStarted;
        return YES;
    } else {
        return NO;
    }
}
@end
