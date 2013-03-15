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

@implementation MRAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
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
    
    NSImage *statusImage = [NSImage imageNamed:@"good.tiff"];
    [statusImage setSize:NSMakeSize(18, 18)];
    
    [_hubbyMenuItem setImage:statusImage];
    [_hubbyMenuItem setHighlightMode:YES];
    [_hubbyMenuItem setMenu:_hubbyMenu];
    
    _waitingOnLastRequest = NO;

    // refresh timer setup
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:(60.0)
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
    NSError *apiError;
    
    NSData* apiJsonData = [NSURLConnection sendSynchronousRequest:apiRequest returningResponse:nil error:&apiError];
    
    NSDictionary *apiResultsDictionary = [apiJsonData objectFromJSONData];
    
    NSURL *statusUrl = [NSURL URLWithString:[apiResultsDictionary objectForKey:@"status_url"]];
    
    // json request for status code
    NSURLRequest *statusRequest = [NSURLRequest requestWithURL:statusUrl];
    NSError *statusError;
    NSData *statusJsonData = [NSURLConnection sendSynchronousRequest:statusRequest returningResponse:nil error:&statusError];
    NSDictionary *statusResultsDictionary = [statusJsonData objectFromJSONData];
    
    // parse status from json reponse
    NSString *lastCheckedString = [statusResultsDictionary objectForKey:@"last_updated"];
    NSUInteger timeStart = [lastCheckedString rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"T"]].location + 1;
    NSUInteger timeLength = [lastCheckedString length] - timeStart - 1;
    NSRange timeRange = NSMakeRange(timeStart, timeLength);
    NSString *timeString = [lastCheckedString substringWithRange:timeRange];
    
    NSString *statusString = [statusResultsDictionary objectForKey:@"status"];
    
    NSMutableDictionary *pollResultsDictionary = [NSMutableDictionary dictionary];
    [pollResultsDictionary setObject:timeString forKey:@"time"];
    [pollResultsDictionary setObject:statusString forKey:@"status"];
    
    [self performSelectorOnMainThread:@selector(pollFinished:) withObject:pollResultsDictionary waitUntilDone:NO];
}

- (void)pollFinished:(NSDictionary *)resultsDictionary
{
    [_hubbyStatusItem setTitle:[NSString stringWithFormat:@"Last check: %@", [resultsDictionary objectForKey:@"time"]]];
    
    NSString *status = [resultsDictionary objectForKey:@"status"];

//    if ([status isEqualToString:@"good"]) {
//        
//    }
//    else if ([status isEqualToString:@"minor"]) {
//        
//    }
//    else if ([status isEqualToString:@"major"]) {
//
//    }
    
    if (!_currentStatus) {
        NSLog(@"new status recorded");
        _currentStatus = status;
    }
    else if (![status isEqualToString:_currentStatus]) {
        NSLog(@"status change detected");
        NSUserNotification *notification = [[NSUserNotification alloc] init];
        [notification setTitle:@"GitHub Status Update"];
        [notification setInformativeText:@"blah blah blah"];
        
        [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
        
        _currentStatus = status;
    }

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

@end
