//
// ViewController.m
// HelloLogbook
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

- (IBAction)trackEvent:(id)sender;
@property (strong, nonatomic) IBOutlet UITextField *textField;

@end

@implementation ViewController


- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithPatternImage: [UIImage imageNamed:@"grid.png"]];
    UIScrollView *tempScrollView = (UIScrollView *)self.view;
    tempScrollView.contentSize = CGSizeMake(320, 342);
}

- (IBAction)trackEvent:(id)sender
{
    Logbook *logbook = [Logbook sharedInstance];
    [logbook track:self.textField.text];
}

@end
