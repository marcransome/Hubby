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
#import "MRCreateRepositoryWindowController.h"
#import <JSONKit.h>
#import <DDLog.h>
#import <DDASLLogger.h>
#import <DDTTYLogger.h>
#import <NXOAuth2.h>
#import <Reachability.h>

#pragma mark Notifications

NSString* const MRAccountAuthorised = @"MRAccountAuthorised";
NSString* const MRAccountDeauthorised = @"MRAccountDeauthorised";
NSString* const MRWaitingOnApiRequest = @"MRWaitingOnApiRequest";
NSString* const MRUserDidDeauthorise = @"MRUserDidDeauthorise";
NSString* const MRNotificationsEnabledChanged = @"MRNotificationsEnabledChanged";
NSString* const MRHubbyIsOffline = @"MRHubbyIsOffline";
NSString* const MRAccountAccessFailed = @"MRAccountAccessFailed";
NSString* const MRRepeatIntervalChanged = @"RepeatIntervalChanged";

static BOOL hubbyIsAuthorised = NO;
static BOOL firstTimeAuthorisation = YES;
static BOOL accessRevoked = NO;

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
    [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];

    // allocate a reachability object
    [self setReachability:[Reachability reachabilityForInternetConnection]];
    
    // observer for reachability
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(reachabilityChanged:)
                                                 name:kReachabilityChangedNotification
                                               object:nil];
    [[self reachability] startNotifier];
    
    // register url handler and observers for github callback
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(handleAppleEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NXOAuth2AccountStoreAccountsDidChangeNotification
                                                      object:[NXOAuth2AccountStore sharedStore]
                                                       queue:nil
                                                  usingBlock:^(NSNotification *notification) {
                                                      // this block may be triggered by events other than account authentication (e.g. account removal)
                                                      // so we must test for the existence of NXOAuth2AccountStoreNewAccountUserInfoKey
                                                      if ([[notification userInfo] objectForKey:@"NXOAuth2AccountStoreNewAccountUserInfoKey"]) {
                                                          hubbyIsAuthorised = YES;
                                                          firstTimeAuthorisation = YES;
                                                          accessRevoked = NO;
                                                          [self startApiTimer];
                                                          [self startRepoTimer];
                                                      }
                                                  }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NXOAuth2AccountStoreDidFailToRequestAccessNotification
                                                      object:[NXOAuth2AccountStore sharedStore]
                                                       queue:nil
                                                  usingBlock:^(NSNotification *aNotification) {
                                                      NSError *error = [aNotification.userInfo objectForKey:NXOAuth2AccountStoreErrorKey];
                                                      DDLogVerbose(@"GitHub authentication failed! (%@)", [error description]);
                                                      [[NSNotificationCenter defaultCenter] postNotificationName:MRAccountAccessFailed object:nil];
                                                      hubbyIsAuthorised = NO;
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
    
    // clear old notications
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"RemoveOldNotifications"]) {
        [[NSUserNotificationCenter defaultUserNotificationCenter] removeAllDeliveredNotifications];
    }
    
    // create preference controller
    _prefWindowController = [[MRPreferencesWindowController alloc] initWithWindowNibName:@"MRPreferencesWindow"];
    
    // set initial preference view by using user defaults
    [_prefWindowController setInitialPreference:[[NSUserDefaults standardUserDefaults] stringForKey:@"DefaultPreferenceViewController"]];
    
    // if a stored account is found then we request the github api which will also indicate if we are
    // still authorised to access the service (i.e. it will otherwise fail with a 401/403 http error)
    if ([[[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"] lastObject]) {
        if ([[self reachability] isReachable]) {
            DDLogVerbose(@"stored account found and reachable, sending api request");
            [[NSNotificationCenter defaultCenter] postNotificationName:MRWaitingOnApiRequest object:nil];
            [self startApiTimer];
            [self startRepoTimer];
        }
        else {
            DDLogVerbose(@"stored account found but unreachable, using offline data");
            [[NSNotificationCenter defaultCenter] postNotificationName:MRHubbyIsOffline object:nil];
        }
    }
    
    if ([[self reachability] isReachable])
        [self notificationsEnabledChanged:nil]; // trigger status timer startup (dependent on user defaults)
    
    // observer for user deauthorisation
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(accountAuthorisedChanged:)
                                                 name:MRUserDidDeauthorise object:nil];
    
    // menu item setup
    _hubbyMenuItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    
    NSImage *menuItemImage;
    
    if ([[self reachability] isReachable])
        menuItemImage = [NSImage imageNamed:@"menu_icon.tiff"];
    else
        menuItemImage = [NSImage imageNamed:@"menu_offline.tiff"];
    
    [menuItemImage setSize:NSMakeSize(18, 18)];
    
    NSImage *menuItemHighlight = [NSImage imageNamed:@"menu_highlight.tiff"];
    [menuItemHighlight setSize:NSMakeSize(18, 18)];
    
    [_hubbyMenuItem setImage:menuItemImage];
    [_hubbyMenuItem setAlternateImage:menuItemHighlight];
    [_hubbyMenuItem setHighlightMode:YES];
    [_hubbyMenuItem setMenu:_hubbyMenu];
    
    _waitingOnLastRequest = NO;

    // observer for repeat interval and notifications preferences
    [[NSNotificationCenter defaultCenter] addObserver:self
                                         selector:@selector(timerIntervalChanged:)
                                             name:MRRepeatIntervalChanged
                                           object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(notificationsEnabledChanged:)
                                                 name:MRNotificationsEnabledChanged
                                               object:nil];
}

#pragma mark -
#pragma mark Status Polling

- (void)updateStatus:(id)sender
{
    if (!_waitingOnLastRequest) {
        _waitingOnLastRequest = YES;
        [self performSelectorInBackground:@selector(pollGithub) withObject:nil];
    }
}

- (void)pollGithub
{
    // json request for status api
    NSURL *statusApiUrl = [NSURL URLWithString:@"https://status.github.com/api.json"];
    NSURLRequest *statusApiRequest = [NSURLRequest requestWithURL:statusApiUrl];
    NSError *statusApiError = nil;
    NSHTTPURLResponse *statusApiResponse = nil;
    NSData* statusApiJsonData = [NSURLConnection sendSynchronousRequest:statusApiRequest returningResponse:&statusApiResponse error:&statusApiError];
    
    if (statusApiJsonData == nil || [statusApiResponse statusCode] != 200)
    {
        if (statusApiError) {
            if ([statusApiError code] == NSURLErrorNotConnectedToInternet)
                DDLogError(@"error for status api request (offline)");
            else
                DDLogError(@"error for status api request: %@ (%@ %li)", [statusApiError domain], [statusApiError localizedDescription], [statusApiError code]);
        }
        else
            DDLogError(@"no data received or http error for status api request (status code is %li)", [statusApiResponse statusCode]);
        
        [self performSelectorOnMainThread:@selector(pollErrored) withObject:nil waitUntilDone:NO];
        
        return;
    }
    
    NSDictionary *apiResultsDictionary = [statusApiJsonData objectFromJSONData];
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
    _waitingOnLastRequest = NO;
    
    [_hubbyStatusItem setTitle:[NSString stringWithFormat:@"Last check: %@", [resultsDictionary objectForKey:@"time"]]];
    
    NSString *status = [resultsDictionary objectForKey:@"status"];
    
    if (!_currentStatus) {
        _currentStatus = status;
        DDLogVerbose(@"first status recorded (%@)", status);
        
        if ([status isEqualToString:@"good"])
            return;
    }
    else if (![status isEqualToString:_currentStatus]) {
        _currentStatus = status;
        DDLogVerbose(@"status change detected (%@)", status);
    }
    else
    {
        DDLogVerbose(@"no status change detected");
        return;
    }
    
    // either status change was detected or first status indicated minor/major disruption
    
    NSInteger notificationType = [[NSUserDefaults standardUserDefaults] integerForKey:@"NotificationsFor"];
    NSString *message = [resultsDictionary objectForKey:@"message"];
    
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
            [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
        }
    }
}

- (void)pollErrored
{
    [_hubbyStatusItem setTitle:[NSString stringWithFormat:@"Last check: error occured"]];
    
    _waitingOnLastRequest = NO;
}

#pragma mark -
#pragma mark Menubar Item Actions

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

- (IBAction)showAcknowledgements:(id)sender
{
    [[NSWorkspace sharedWorkspace] openFile:[[NSBundle mainBundle] pathForResource:@"Acknowledgements" ofType:@"rtf"]];
}

- (IBAction)showCreateRepository:(id)sender
{
    if (!_createRepoWindow) {
        _createRepoWindow = [[MRCreateRepositoryWindowController alloc] initWithWindowNibName:@"MRCreateRepositoryWindow"];
    }
    
    [NSApp activateIgnoringOtherApps: YES];
    [[_createRepoWindow window] makeKeyAndOrderFront:nil];
}

- (void)openRepo:(id)sender
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithFormat:@"https://github.com/%@", [sender title]]]];
}

#pragma mark -
#pragma mark API Support Methods

- (void)startApiTimer
{
    DDLogVerbose(@"starting api timer");
    
    [self setApiTimer:[NSTimer scheduledTimerWithTimeInterval:60.0
                                                       target:self
                                                     selector:@selector(requestApi)
                                                     userInfo:nil
                                                      repeats:YES]];
    [[self apiTimer] fire];
}

- (void)requestApi
{
    DDLogVerbose(@"performing api request");
    
    [NXOAuth2Request performMethod:@"GET" onResource:[NSURL URLWithString:@"https://api.github.com/user"] usingParameters:nil withAccount:[[[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"] lastObject] sendProgressHandler:^(unsigned long long bytesSend, unsigned long long bytesTotal) {
        // silent
    } responseHandler:^(NSURLResponse *response, NSData *responseData, NSError *error) {
        NSDictionary *results = [responseData objectFromJSONData];

        if (error) {
            // if the first api request after authorisation fails then we
            // are unable to retrieve new user data, and none will exist locally,
            // so we deauthorise, invalidate active timers and inform the user
            if (firstTimeAuthorisation) {
                firstTimeAuthorisation = NO;
                [self userDidRevokeAccess];
                return;
            }
            else if ([error code] == 401 || [error code] == 403) {
                [self userDidRevokeAccess];
                return;
            }
            else if ([error code] == NSURLErrorNotConnectedToInternet) {
                DDLogError(@"error for api request (offline)");
                return;
            }
            else {
                DDLogError(@"error for api request: %@ (%@ %li)", [error domain], [error localizedDescription], [error code]);
                return;
            }

        }
        else {
            hubbyIsAuthorised = YES;
            firstTimeAuthorisation = NO;
            
            [[NSNotificationCenter defaultCenter] postNotificationName:MRAccountAuthorised object:results];
        }
    }];
}

- (void)startRepoTimer
{
    DDLogVerbose(@"starting public repos timer");
    
    [self setPublicRepoTimer:[NSTimer scheduledTimerWithTimeInterval:60.0
                                                       target:self
                                                     selector:@selector(requestRepos)
                                                     userInfo:nil
                                                      repeats:YES]];
    [[self publicRepoTimer] fire];
}

- (void)requestRepos
{
    DDLogVerbose(@"requesting public repos");
    
    [NXOAuth2Request performMethod:@"GET" onResource:[NSURL URLWithString:@"https://api.github.com/user/repos"] usingParameters:nil withAccount:[[[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"] lastObject] sendProgressHandler:^(unsigned long long bytesSend, unsigned long long bytesTotal) {
        // silent
    } responseHandler:^(NSURLResponse *response, NSData *responseData, NSError *error) {
        NSArray *results = [responseData objectFromJSONData];
        
        if (error) {
            if ([error code] == 401 || [error code] == 403) {
                [self userDidRevokeAccess];
                return;
            }
            else if ([error code] == NSURLErrorNotConnectedToInternet) {
                DDLogError(@"error for repos request (offline)");
                return;
            }
            else {
                DDLogError(@"error for repos request: %@ (%@ %li)", [error domain], [error localizedDescription], [error code]);
                return;
            }
        }
        else {
            [[self publicReposMenu] removeAllItems];
            
            if ([results count] > 0) {
                [[self publicReposMenuItem] setEnabled:YES];
                for (NSDictionary *repo in results) {
                    NSString *repoName = [repo objectForKey:@"full_name"];
                    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:repoName action:@selector(openRepo:) keyEquivalent:@""];
                    [[self publicReposMenu] addItem:menuItem];
                    [menuItem setTarget:self];
                }
            }
            else {
                [[self publicReposMenuItem] setEnabled:NO];
            }
        }
    }];
}

- (void)userDidRevokeAccess
{
    // if multiple requests fail in succession (e.g. api request and public repo request)
    // due to access revocation then this method will be triggered multiple times, we protect
    // against multiple calls by recording revocation status (and reset this when authorising)
    if (accessRevoked)
        return;
    
    accessRevoked = YES;
    
    DDLogError(@"401/403 error: no longer authorised, removing accounts");
    
    for (NXOAuth2Account *account in [[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"]) {
        [[NXOAuth2AccountStore sharedStore] removeAccount:account];
    };
    
    [self accountAuthorisedChanged:nil];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:MRAccountDeauthorised object:nil];
    
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:@"Hubby was unable to access GitHub.  Please authorise again."];
    [alert runModal];
}

#pragma mark -
#pragma mark General Support Methods

- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent: (NSAppleEventDescriptor *)replyEvent
{
    // ignore repeated callbacks while authorised or attempting authorisation
    if (hubbyIsAuthorised == NO) {
        if ([[event description] rangeOfString:@"error"].location == NSNotFound) {
            [[NSNotificationCenter defaultCenter] postNotificationName:MRWaitingOnApiRequest object:nil];
            
            NSURL *url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];
            DDLogVerbose(@"callback received (%@)", url);
            
            [[NXOAuth2AccountStore sharedStore] handleRedirectURL:url];
        }
    }
}

+ (NSURL *)hubbySupportDir
{
    // locate the application support directory in the user's home directory
    NSURL *applicationSupportDir = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] lastObject];
    
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    NSURL *hubbySupportFolder = nil;
    
    // if no application support folder exists, create one
    if (applicationSupportDir) {
        hubbySupportFolder = [applicationSupportDir URLByAppendingPathComponent:bundleID];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtURL:hubbySupportFolder withIntermediateDirectories:YES attributes:nil error:&error]) {
            // TODO handle errors
            DDLogError(@"error creating support folder (%@)", [error description]);
            return nil;
        }
    }
    
    return hubbySupportFolder;
}

#pragma mark -
#pragma mark Notifications

- (void)timerIntervalChanged:(NSNotification *)notification
{
    if (![[self reachability] isReachable])
    {
        DDLogVerbose(@"ignoring timer interval change while unreachable");
        return;
    }
    
    [_statusTimer invalidate];
    
    NSInteger repeatIntervalInSeconds = [[NSUserDefaults standardUserDefaults] integerForKey:@"RepeatInterval"] * 60;
    _statusTimer = [NSTimer scheduledTimerWithTimeInterval:(repeatIntervalInSeconds)
                                                    target:self
                                                  selector:@selector(updateStatus:)
                                                  userInfo:nil
                                                   repeats:YES];
    
    DDLogVerbose(@"adjusted timer interval (%lis)", (long)repeatIntervalInSeconds);
}

- (void)notificationsEnabledChanged:(NSNotification *)notification
{
    if (![[self reachability] isReachable])
    {
        DDLogVerbose(@"ignoring notifications pref change while unreachable");
        return;
    }
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"EnableNotifications"]) {
        NSTimeInterval repeatIntervalInSeconds = [[NSUserDefaults standardUserDefaults] integerForKey:@"RepeatInterval"] * 60.0;
        
        DDLogVerbose(@"starting status timer with interval %.2fs", repeatIntervalInSeconds);
        
        _statusTimer = [NSTimer scheduledTimerWithTimeInterval:(repeatIntervalInSeconds <= 60.0 ? 60.0 : repeatIntervalInSeconds)
                                                        target:self
                                                      selector:@selector(updateStatus:)
                                                      userInfo:nil
                                                       repeats:YES];
        
        [_statusTimer fire];
    }
    else { // unreachable
        _currentStatus = nil;
        if (_statusTimer) {
            DDLogVerbose(@"stopping status timer");
            [_statusTimer invalidate];
            _statusTimer = nil;
        }
    }
}

- (void)reachabilityChanged:(NSNotification *)notification
{
    NetworkStatus status = [(Reachability *)[notification object] currentReachabilityStatus];
    
    if (status == NotReachable) {
        DDLogVerbose(@"no longer reachable, invalidating timers");
        [[self apiTimer] invalidate];
        [[self statusTimer] invalidate];
        [[self publicRepoTimer] invalidate];
        
        // TODO change status menu icon to indicate unreachable status        
        NSImage *offlineMenuIcon = [[NSBundle mainBundle] imageForResource:@"menu_offline.tiff"];
        [offlineMenuIcon setSize:NSMakeSize(18, 18)];
        
        [_hubbyMenuItem setImage:offlineMenuIcon];
    }
    else {
        // restart api and repo timers
        if ([[[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"] lastObject]) {
            [self startApiTimer];
            [self startRepoTimer];
        }
        
        // restart status timer
        [self notificationsEnabledChanged:nil];
        
        // TODO reset status menu icon to indicate reachable status
        NSImage *offlineMenuIcon = [[NSBundle mainBundle] imageForResource:@"menu_icon.tiff"];
        [offlineMenuIcon setSize:NSMakeSize(18, 18)];
        
        [_hubbyMenuItem setImage:offlineMenuIcon];
    }
}

- (void)accountAuthorisedChanged:(NSNotification *)notification
{
    DDLogVerbose(@"deauthorising");
    
    hubbyIsAuthorised = NO;
    
    // update public repos menu item
    [[self publicReposMenu] removeAllItems];
    [[self publicReposMenuItem] setEnabled:NO];
    [[self publicRepoTimer] invalidate];
    
    DDLogVerbose(@"stopped public repos timer");
    
    [[self apiTimer] invalidate];
    
    DDLogVerbose(@"stopped api timer");
    
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager removeItemAtURL:[[MRAppDelegate hubbySupportDir] URLByAppendingPathComponent:@"user.json"] error:nil];
    [manager removeItemAtURL:[[MRAppDelegate hubbySupportDir] URLByAppendingPathComponent:@"avatar.tiff"] error:nil];
    
    DDLogVerbose(@"removed local user data");
}

#pragma mark -
#pragma mark NSUserNotificationCenterDelegate

-(void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://status.github.com"]];
    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"RemoveNotificationsOnClick"]) {
        [[NSUserNotificationCenter defaultUserNotificationCenter] removeDeliveredNotification:notification];
    }
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification
{
    return YES;
}

#pragma mark -
#pragma mark Menu Item Validation

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(showPreferences:))
        return YES;
    if ([item action] == @selector(showAbout:))
        return YES;
    if ([item action] == @selector(showAcknowledgements:))
        return YES;
    if ([item action] == @selector(openGitHubStatusPage:))
        return YES;
    if ([item action] == @selector(openRepo:))
        return YES;
    
    // enable these items based on current reachability status
    if ([[self reachability] isReachable] && hubbyIsAuthorised) {
        if ([item action] == @selector(showCreateRepository:))
            return YES;
    }
    
    return NO;
}

@end
