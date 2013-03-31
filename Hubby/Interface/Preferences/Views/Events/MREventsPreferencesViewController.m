//
//  MREventsPreferencesViewController.m
//  Hubby
//
//  Created by Marc Ransome on 15/03/2013.
//  Copyright (c) 2013 fidgetbox. All rights reserved.
//

#import "MREventsPreferencesViewController.h"

@interface MREventsPreferencesViewController ()

@property (weak) IBOutlet NSTextField *checkFrequencyLabel;
@property (weak) IBOutlet NSTextField *checkMinutesLabel;

- (IBAction)repeatIntervalChanged:(id)sender;
- (IBAction)notificationsEnabledChanged:(id)sender;

@end

@implementation MREventsPreferencesViewController

- (NSString *)nibName
{
    return @"MREventsPreferencesView";
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (IBAction)repeatIntervalChanged:(id)sender
{
    NSNotification *repeatIntervalChanged = [NSNotification notificationWithName:@"RepeatIntervalChanged" object:nil];
    [[NSNotificationCenter defaultCenter] postNotification:repeatIntervalChanged];
}

- (IBAction)notificationsEnabledChanged:(id)sender
{
    if ([sender state] == NSOnState) {
        [[self checkFrequencyLabel] setTextColor:[NSColor controlTextColor]];
        [[self checkMinutesLabel] setTextColor:[NSColor controlTextColor]];
    }
    else {
        [[self checkFrequencyLabel] setTextColor:[NSColor disabledControlTextColor]];
        [[self checkMinutesLabel] setTextColor:[NSColor disabledControlTextColor]];
    }
}

@end
