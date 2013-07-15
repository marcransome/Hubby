//
//  MRAppDelegate.h
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

#import <Cocoa/Cocoa.h>

@class MRPreferencesWindowController;
@class MRCreateRepositoryWindowController;
@class Reachability;

@interface MRAppDelegate : NSObject <NSApplicationDelegate, NSUserNotificationCenterDelegate>

@property (strong) NSStatusItem* hubbyMenuItem;
@property (weak) IBOutlet NSMenu *hubbyMenu;
@property (weak) IBOutlet NSMenuItem *hubbyStatusItem;
@property (weak) IBOutlet NSMenuItem *createRepoMenuItem;
@property (weak) IBOutlet NSMenuItem *publicReposMenuItem;
@property (weak) IBOutlet NSMenu *publicReposMenu;
@property (strong) NSTimer *apiTimer;
@property (strong) NSTimer *statusTimer;
@property (strong) NSTimer *publicRepoTimer;
@property (assign) BOOL waitingOnLastRequest;
@property (strong) MRPreferencesWindowController *prefWindowController;
@property (strong) NSString *currentStatus;
@property (strong) MRCreateRepositoryWindowController *createRepoWindowController;
@property (strong) Reachability *reachability;

/* status polling */
- (void)updateStatus:(id)sender;
- (void)pollGithub;
- (void)pollFinished:(NSDictionary *)resultsDictionary;
- (void)pollErrored;

/* menubar item actions */
- (IBAction)openGitHubStatusPage:(id)sender;
- (IBAction)showPreferences:(id)sender;
- (IBAction)showAbout:(id)sender;
- (IBAction)showAcknowledgements:(id)sender;
- (IBAction)showCreateRepository:(id)sender;
- (IBAction)openRepo:(id)sender;

/* api support methods */
- (void)startApiTimer;
- (void)startRepoTimer;
- (void)requestApi;
- (void)requestRepos;
- (void)userDidRevokeAccess;

/* general support methods  */
+ (NSURL *)hubbySupportDir;
- (void)handleAppleEvent:(NSAppleEventDescriptor *)event withReplyEvent: (NSAppleEventDescriptor *)replyEvent;

/* notifications */
- (void)timerIntervalChanged:(NSNotification *)notification;
- (void)notificationsEnabledChanged:(NSNotification *)notification;
- (void)reachabilityChanged:(NSNotification *)notification;
- (void)accountAuthorisedChanged:(NSNotification *)notification;

@end
