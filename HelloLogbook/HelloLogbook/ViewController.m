//
// ViewController.m
// HelloSlash7
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

#import "Logbook.h"

#import "ViewController.h"

@interface ViewController ()

@property(nonatomic, retain) IBOutlet UISegmentedControl *genderControl;
@property(nonatomic, retain) IBOutlet UISegmentedControl *weaponControl;
@property(nonatomic, retain) IBOutlet UISwitch *transactionControl;

- (IBAction)trackEvent:(id)sender;

@end

@implementation ViewController

- (void)dealloc
{
    self.genderControl = nil;
    self.weaponControl = nil;
    [super dealloc];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithPatternImage: [UIImage imageNamed:@"grid.png"]];
    UIScrollView *tempScrollView = (UIScrollView *)self.view;
    tempScrollView.contentSize = CGSizeMake(320, 342);
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return YES;
}

- (IBAction)trackEvent:(id)sender
{
    Logbook *logbook = [Logbook sharedInstance];
    [logbook track:@"Player Create"];
}

@end
