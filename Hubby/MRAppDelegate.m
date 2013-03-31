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
#import <NXOAuth2.h>

#pragma mark Notifications

NSString* const MRAccountAuthorised = @"MRAccountAuthorised";
NSString* const MRAccountDeauthorised = @"MRAccountDeauthorised";
NSString* const MRWaitingOnApiRequest = @"MRWaitingOnApiRequest";
NSString* const MRReceivedApiResponse = @"MRReceivedApiResponse";
NSString* const MRUserDidDeauthorise = @"MRUserDidDeauthorise";

#pragma mark Logging

int ddLogLevel = LOG_LEVEL_VERBOSE;

#pragma mark Enumerations

enum {
    MRMajorAndMinorNotifications = 0,
    MRMajorNotifications = 1,
    MRMinorNotifications = 2
};

#pragma mark -

@implementation MRAppDelegate

+ (void)initialize
{
    // omit client_id and secret from repo!
    NSString *clientId = [[[NSProcessInfo processInfo] environment] objectForKey:@"HUBBY_CLIENTID"];
    NSString *secret = [[[NSProcessInfo processInfo] environment] objectForKey:@"HUBBY_SECRET"];
        
    NSDictionary *gitHubConfDict = @{ kNXOAuth2AccountStoreConfigurationClientID: clientId,
                                     kNXOAuth2AccountStoreConfigurationSecret: secret,
                                     kNXOAuth2AccountStoreConfigurationAuthorizeURL: [NSURL URLWithString:@"https://github.com/login/oauth/authorize"],
                                     kNXOAuth2AccountStoreConfigurationTokenURL: [NSURL URLWithString:@"https://github.com/login/oauth/access_token"],
                                     kNXOAuth2AccountStoreConfigurationRedirectURL: [NSURL URLWithString:@"hubbyapp://callback/"],
                                     kNXOAuth2AccountStoreConfigurationTokenType: @"bearer",
                                     kNXOAuth2AccountStoreConfigurationScope: [NSSet setWithObjects:@"user", @"repo", nil]};
    
    [[NXOAuth2AccountStore sharedStore] setConfiguration:gitHubConfDict forAccountType:@"GitHub"];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    // register url handler and observers for github callback
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(handleAppleEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NXOAuth2AccountStoreAccountsDidChangeNotification
                                                      object:[NXOAuth2AccountStore sharedStore]
                                                       queue:nil
                                                  usingBlock:^(NSNotification *notification) {
                                                      // this block may be triggered by events other than account authentication (e.g. account removal)
                                                      // so we must test for the existence of NXOAuth2AccountStoreNewAccountUserInfoKey
                                                      if ([[notification userInfo] objectForKey:@"NXOAuth2AccountStoreNewAccountUserInfoKey"]) {
                                                          [self requestApi];
                                                      }
                                                  }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NXOAuth2AccountStoreDidFailToRequestAccessNotification
                                                      object:[NXOAuth2AccountStore sharedStore]
                                                       queue:nil
                                                  usingBlock:^(NSNotification *aNotification) {
                                                      NSError *error = [aNotification.userInfo objectForKey:NXOAuth2AccountStoreErrorKey];
                                                      DDLogVerbose(@"GitHub authentication failed!");
                                                  }];
    
    // configure loggers
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
    
    // if a stored account is found then we request the github api which will also indicate if we are
    // still authorised to access the service (i.e. it will otherwise fail with a 401-404 http error)
    if ([[[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"] lastObject]) {
        DDLogVerbose(@"stored account found, sending api request");
        [[NSNotificationCenter defaultCenter] postNotificationName:MRWaitingOnApiRequest object:nil];
        [self requestApi];
    }
    
    // observer for user deauthorisation
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(deauthoriseAccount:)
                                                 name:MRUserDidDeauthorise object:nil];
    
    
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
            DDLogError(@"error for api request: %@ (%@ %li)", [apiError domain], [apiError localizedDescription], [apiError code]);
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
            DDLogError(@"error for status request: %@ (%@ %li)", [statusError domain], [statusError localizedDescription], [statusError code]);
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
            DDLogError(@"error for last message request: %@ (%@ %li)", [lastMessageError localizedDescription], [lastMessageError domain], [lastMessageError code]);
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
        
        if ([status isEqualToString:@"good"])
        {
            if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ServiceRestoredNotification"]) {
                NSUserNotification *notification = [[NSUserNotification alloc] init];
                [notification setTitle:@"GitHub Service Restored"];
                [notification setInformativeText:message];
                [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
            }
        }
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

- (IBAction)showAcknowledgements:(id)sender
{
    [[NSWorkspace sharedWorkspace] openFile:[[NSBundle mainBundle] pathForResource:@"Acknowledgements" ofType:@"rtf"]];
}

- (IBAction)showCreateRepository:(id)sender
{
    if (!_gistWindow) {
        _gistWindow = [[MRCreateRepositoryWindowController alloc] initWithWindowNibName:@"MRCreateRepositoryWindow"];
    }
    
    [NSApp activateIgnoringOtherApps: YES];
    [[_gistWindow window] makeKeyAndOrderFront:nil];
}

-(void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://status.github.com"]];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"RemoveNotificationsOnClick"]) {
        [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:notification];
    }
}

- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent: (NSAppleEventDescriptor *)replyEvent
{
    if ([[event description] rangeOfString:@"error"].location == NSNotFound) {
        NSLog(@"%@ %@", [event description], [replyEvent description]);
        [[NSNotificationCenter defaultCenter] postNotificationName:MRWaitingOnApiRequest object:nil];
        
        NSURL *url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
        DDLogVerbose(@"callback received (%@)", url);
        
        [[NXOAuth2AccountStore sharedStore] handleRedirectURL:url];
        NSLog(@"%@,", url);
    }
}

- (void)requestApi
{
    [NXOAuth2Request performMethod:@"GET" onResource:[NSURL URLWithString:@"https://api.github.com/user"] usingParameters:nil withAccount:[[[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"] lastObject] sendProgressHandler:^(unsigned long long bytesSend, unsigned long long bytesTotal) {
        // silent
    } responseHandler:^(NSURLResponse *response, NSData *responseData, NSError *error) {
        NSDictionary *results = [responseData objectFromJSONData];

        if (error) {
            
            if ([error code] >= 401 && [error code] <= 404)
            {
                // user likely revoked our access
                DDLogError(@"401-404 error: no longer authorised, removing accounts");
                
                for (NXOAuth2Account *account in [[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"]) {
                    [[NXOAuth2AccountStore sharedStore] removeAccount:account];
                };
                
                [self deauthoriseAccount:nil];
                
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"Hubby was unable to access GitHub.  Please authenticate again."];
                [alert runModal];
            }
            else {
                 // TODO handle other error types
            }
            
            DDLogError(@"an api request error occured (%li: %@)", [error code], [error description]);
        }
        else {
            DDLogVerbose(@"%@", results);
            [[NSNotificationCenter defaultCenter] postNotificationName:MRAccountAuthorised object:results];
            
            [self requestRepos];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:MRReceivedApiResponse object:nil];
    }];
}

- (void)requestRepos
{
    [NXOAuth2Request performMethod:@"GET" onResource:[NSURL URLWithString:@"https://api.github.com/user/repos"] usingParameters:nil withAccount:[[[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"] lastObject] sendProgressHandler:^(unsigned long long bytesSend, unsigned long long bytesTotal) {
        // silent
    } responseHandler:^(NSURLResponse *response, NSData *responseData, NSError *error) {
        NSArray *results = [responseData objectFromJSONData];
        
        if (error) {
            
            if ([error code] >= 401 && [error code] <= 404)
            {
                // user likely revoked our access
                DDLogError(@"401-404 error: no longer authorised, removing accounts");
                
                for (NXOAuth2Account *account in [[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"]) {
                    [[NXOAuth2AccountStore sharedStore] removeAccount:account];
                };
                
                [self deauthoriseAccount:nil];
                
                NSAlert *alert = [[NSAlert alloc] init];
                [alert setMessageText:@"Hubby was unable to access GitHub.  Please authenticate again."];
                [alert runModal];
            }
            else {
                // TODO handle other error types
            }
            
            DDLogError(@"repos request error occured (%li: %@)", [error code], [error description]);
        }
        else {

            if ([results count] > 0) {
                [[self publicReposMenuItem] setEnabled:YES];
                for (NSDictionary *repo in results) {
                    NSString *repoName = [repo objectForKey:@"full_name"];
                    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:repoName action:@selector(openRepo:) keyEquivalent:@""];
                    [[self publicReposMenu] addItem:menuItem];
                    [menuItem setTarget:self];
                }
            }
        }
    }];
}

- (void)openRepo:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@", [sender title]]]];
}

- (void)deauthoriseAccount:(NSNotification *)notification
{
    // ensure account preference view is up to date
    [[NSNotificationCenter defaultCenter] postNotificationName:MRAccountDeauthorised object:nil];
    [[self publicReposMenu] removeAllItems];
    [[self publicReposMenuItem] setEnabled:NO];
}

@end
