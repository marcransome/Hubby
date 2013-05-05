//
//  MREventsPreferencesViewController.m
//  Hubby
//
//  Created by Marc Ransome on 15/03/2013.
//  Copyright (c) 2013 fidgetbox. All rights reserved.
//

#import "MREventsPreferencesViewController.h"

#pragma mark Externals
extern NSString* const MRNotificationsEnabledChanged;
extern NSString* const MRRepeatIntervalChanged;

#pragma mark -
#pragma mark Interface

@interface MREventsPreferencesViewController ()

@property (weak) IBOutlet NSTextField *checkFrequencyLabel;
@property (weak) IBOutlet NSTextField *checkMinutesLabel;

- (IBAction)repeatIntervalChanged:(id)sender;
- (IBAction)notificationsEnabledChanged:(id)sender;

@end

#pragma mark -
#pragma mark Initialisation

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

#pragma mark -
#pragma mark Action Methods

- (IBAction)repeatIntervalChanged:(id)sender
{
    NSNotification *repeatIntervalChanged = [NSNotification notificationWithName:MRRepeatIntervalChanged object:nil];
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
    
    [[NSNotificationCenter defaultCenter] postNotificationName:MRNotificationsEnabledChanged object:nil];
}

@end
