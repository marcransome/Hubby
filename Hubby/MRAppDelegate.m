//
//  MRAppDelegate.m
//  Hubby
//
//  Copyright (c) 2013, Marc Ransome <marc.ransome@fidgetbox.co.uk>
//
//  This file is part of Hubby.
//
//  Hubby is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  Hubby is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with Hubby.  If not, see <http://www.gnu.org/licenses/>.
//

#import "MRAppDelegate.h"
#import "MRPreferencesWindowController.h"
#import <JSONKit.h>
#import <DDLog.h>
#import <DDASLLogger.h>
#import <DDTTYLogger.h>

static int ddLogLevel = LOG_LEVEL_VERBOSE;

enum {
    MRMajorAndMinorNotifications = 0,
    MRMajorNotifications = 1,
    MRMinorNotifications = 2
};

@implementation MRAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    
    NSNumber *logLevel = [[NSUserDefaults standardUserDefaults] objectForKey:@"prefsLogLevel"];
    if (logLevel)
        ddLogLevel = [logLevel intValue];
    
    // register sane preference defaults from plist file
    NSString *defaultsPath = [[NSBundle mainBundle] pathForResource:@"Defaults" ofType:@"plist"];
    NSDictionary *defaultsDict = [NSDictionary dictionaryWithContentsOfFile:defaultsPath];
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultsDict];
    
    // create preference controller
    _prefWindowController = [[MRPreferencesWindowController alloc] initWithWindowNibName:@"MRPreferencesWindow"];
    
    // set initial preference view by using user defaults
    [_prefWindowController setInitialPreference:[[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultPreferenceViewController"]];
    
    // menu item setup
    _hubbyMenuItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    
    NSImage *menuItemImage = [NSImage imageNamed:@"menu_icon.tiff"];
    [menuItemImage setSize:NSMakeSize(18, 18)];
    
    NSImage *menuItemHighlight = [NSImage imageNamed:@"menu_highlight.tiff"];
    [menuItemHighlight setSize:NSMakeSize(18, 18)];
    
    [_hubbyMenuItem setImage:menuItemImage];
    [_hubbyMenuItem setAlternateImage:menuItemHighlight];
    [_hubbyMenuItem setHighlightMode:YES];
    [_hubbyMenuItem setMenu:_hubbyMenu];
    
    _waitingOnLastRequest = NO;

    // observer for repeat interval preference
    [[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(adjustTimerInterval:)
                                             name:@"RepeatIntervalChanged"
                                           object:nil];
    
    // refresh timer setup
    NSTimeInterval repeatIntervalInSeconds = [[NSUserDefaults standardUserDefaults] integerForKey:@"RepeatInterval"] * 60.0;
    
    DDLogVerbose(@"repeat interval on startup is %.2fs", repeatIntervalInSeconds);
    
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:(repeatIntervalInSeconds <= 60.0 ? 60.0 : repeatIntervalInSeconds)
                                                target:self
                                              selector:@selector(updateHubby:)
                                              userInfo:nil
                                               repeats:YES];

    [_statusTimer fire];
}

- (IBAction)updateHubby:(id)sender
{
    if (!_waitingOnLastRequest) {
        _waitingOnLastRequest = YES;
        [self performSelectorInBackground:@selector(pollGithub) withObject:nil];
    }
}

- (void)pollGithub
{
    // json request for status api
    NSURL *apiUrl = [NSURL URLWithString:@"https://status.github.com/api.json"];
    NSURLRequest *apiRequest = [NSURLRequest requestWithURL:apiUrl];
    NSError *apiError = nil;
    NSHTTPURLResponse *apiResponse = nil;
    NSData* apiJsonData = [NSURLConnection sendSynchronousRequest:apiRequest returningResponse:&apiResponse error:&apiError];
    
    if (apiJsonData == nil || [apiResponse statusCode] != 200)
    {
        if (apiError)
            DDLogError(@"error for api request: %@", [apiError localizedDescription]);
        else
            DDLogError(@"no data received or http error for api request (status code is %li)", [apiResponse statusCode]);
        
        [self performSelectorOnMainThread:@selector(pollErrored) withObject:nil waitUntilDone:NO];
        
        return;
    }
    
    NSDictionary *apiResultsDictionary = [apiJsonData objectFromJSONData];
    NSURL *statusUrl = [NSURL URLWithString:[apiResultsDictionary objectForKey:@"status_url"]];
    NSURL *lastMessageUrl = [NSURL URLWithString:[apiResultsDictionary objectForKey:@"last_message_url"]];
        
    if (apiResultsDictionary == nil || statusUrl == nil || lastMessageUrl == nil) {
        DDLogError(@"malformed json response");
        
        [self performSelectorOnMainThread:@selector(pollErrored) withObject:nil waitUntilDone:NO];
        
        return;
    }
    
    // json request for status
    NSURLRequest *statusRequest = [NSURLRequest requestWithURL:statusUrl];
    NSError *statusError = nil;
    NSHTTPURLResponse *statusResponse = nil;
    NSData *statusJsonData = [NSURLConnection sendSynchronousRequest:statusRequest returningResponse:&statusResponse error:&statusError];
    
    if (statusJsonData == nil || [statusResponse statusCode] != 200)
    {
        if (statusError)
            DDLogError(@"error for status request: %@", [statusError localizedDescription]);
        else
            DDLogError(@"no data received or http error for status request (status code is %li)", [statusResponse statusCode]);
        
        [self performSelectorOnMainThread:@selector(pollErrored) withObject:nil waitUntilDone:NO];
        
        return;
    }
    
    NSDictionary *statusResultsDictionary = [statusJsonData objectFromJSONData];
    
    if (statusResultsDictionary == nil) {
        DDLogError(@"malformed json response for status request");
        
        [self performSelectorOnMainThread:@selector(pollErrored) withObject:nil waitUntilDone:NO];
        
        return;
    }
    
    // parse status
    NSString *statusString = [statusResultsDictionary objectForKey:@"status"];
    
    // json request for last message
    NSURLRequest *lastMessageRequest = [NSURLRequest requestWithURL:lastMessageUrl];
    NSError *lastMessageError = nil;
    NSHTTPURLResponse *lastMessageResponse = nil;
    NSData *lastMessageJsonData = [NSURLConnection sendSynchronousRequest:lastMessageRequest returningResponse:&lastMessageResponse error:&lastMessageError];
    
    // error checks
    if (lastMessageJsonData == nil || [lastMessageResponse statusCode] != 200)
    {
        if (lastMessageError)
            DDLogError(@"error for last message request: %@", [lastMessageError localizedDescription]);
        else
            DDLogError(@"no data received or http error for last message request (status code is %li)", [lastMessageResponse statusCode]);
        
        [self performSelectorOnMainThread:@selector(pollErrored) withObject:nil waitUntilDone:NO];
        
        return;
    }
    
    NSDictionary *lastMessageResultsDictionary = [lastMessageJsonData objectFromJSONData];
    
    // parse last message and record time of check
    NSString *lastMessageString = [lastMessageResultsDictionary objectForKey:@"body"];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"HH:mm:ss"];
    NSString *currentTime = [dateFormatter stringFromDate:[NSDate date]];
    
    // assemble desired results
    NSMutableDictionary *pollResultsDictionary = [NSMutableDictionary dictionary];
    [pollResultsDictionary setObject:currentTime forKey:@"time"];
    [pollResultsDictionary setObject:statusString forKey:@"status"];
    [pollResultsDictionary setObject:lastMessageString forKey:@"message"];
    
    [self performSelectorOnMainThread:@selector(pollFinished:) withObject:pollResultsDictionary waitUntilDone:NO];
}

- (void)pollFinished:(NSDictionary *)resultsDictionary
{
    [_hubbyStatusItem setTitle:[NSString stringWithFormat:@"Last check: %@", [resultsDictionary objectForKey:@"time"]]];
    
    NSString *status = [resultsDictionary objectForKey:@"status"];
    NSString *message = [resultsDictionary objectForKey:@"message"];
    
    if (!_currentStatus) {
        _currentStatus = status;
        DDLogVerbose(@"first status recorded (%@)", status);
    }
    else if (![status isEqualToString:_currentStatus]) {
        
        DDLogVerbose(@"status change detected (%@)", status);
        
        NSInteger notificationType = [[NSUserDefaults standardUserDefaults] integerForKey:@"NotificationsFor"];
        
        if ([status isEqualToString:@"major"]) {
            if (notificationType == MRMajorAndMinorNotifications || notificationType == MRMajorNotifications)
            {
                NSUserNotification *notification = [[NSUserNotification alloc] init];
                [notification setTitle:@"GitHub Major Disruption"];
                [notification setInformativeText:message];
                [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
            }
        }
        else if ([status isEqualToString:@"minor"]) {
            if (notificationType == MRMajorAndMinorNotifications || notificationType == MRMinorNotifications)
            {
                NSUserNotification *notification = [[NSUserNotification alloc] init];
                [notification setTitle:@"GitHub Minor Disruption"];
                [notification setInformativeText:message];
                [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
                [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
            }
        }
        
        _currentStatus = status;
    }
    else
    {
        DDLogVerbose(@"no status change detected");
    }

    _waitingOnLastRequest = NO;
}

- (void)pollErrored
{
    [_hubbyStatusItem setTitle:[NSString stringWithFormat:@"Last check: error occured"]];
    
    _waitingOnLastRequest = NO;
}

- (IBAction)openGitHubStatusPage:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://status.github.com"]];
}

- (IBAction)showPreferences:(id)sender
{
    [NSApp activateIgnoringOtherApps: YES];
    [[_prefWindowController window] makeKeyAndOrderFront:self];
}

- (IBAction)showAbout:(id)sender
{
    [NSApp activateIgnoringOtherApps: YES];
    [NSApp orderFrontStandardAboutPanel:nil];
}

- (void)adjustTimerInterval:(NSNotification *)notification
{
    [_statusTimer invalidate];
    
    NSInteger repeatIntervalInSeconds = [[NSUserDefaults standardUserDefaults] integerForKey:@"RepeatInterval"] * 60;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:(repeatIntervalInSeconds)
                                                    target:self
                                                  selector:@selector(updateHubby:)
                                                  userInfo:nil
                                                   repeats:YES];
    
    DDLogVerbose(@"adjusted timer interval (%lis)", (long)repeatIntervalInSeconds);
}

- (IBAction)showAcknowledgements:(id)sender {
    [[NSWorkspace sharedWorkspace] openFile:[[NSBundle mainBundle] pathForResource:@"Acknowledgements" ofType:@"rtf"]];
}

-(void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://status.github.com"]];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"RemoveNotificationsOnClick"]) {
        [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:notification];
    }
}

@end
