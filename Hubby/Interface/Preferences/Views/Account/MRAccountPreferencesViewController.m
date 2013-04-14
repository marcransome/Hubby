//
//  MRAccountPreferencesViewController.m
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

#import "MRAccountPreferencesViewController.h"
#import "MRAppDelegate.h"
#import <NXOAuth2AccountStore.h>
#import <DDLog.h>
#import <JSONKit.h>

#pragma mark Externals

extern NSString* const MRAccountAuthorised;
extern NSString* const MRAccountDeauthorised;
extern NSString* const MRWaitingOnApiRequest;
extern NSString* const MRUserDidDeauthorise;
extern NSString* const MRHubbyIsOffline;

extern int ddLogLevel;

#pragma mark -
#pragma mark Interface

@interface MRAccountPreferencesViewController ()

@property (weak) IBOutlet NSButton *authoriseButton;
@property (strong) IBOutlet NSView *userAuthenticateView;
@property (strong) IBOutlet NSView *userInfoView;
@property (weak) IBOutlet NSTextField *userInfoName;
@property (weak) IBOutlet NSTextField *userInfoLocation;
@property (weak) IBOutlet NSImageView *userAvatar;
@property (weak) IBOutlet NSProgressIndicator *progressIndicator;

- (IBAction)authoriseAccount:(id)sender;
- (IBAction)deauthoriseAccount:(id)sender;
- (void)showProgress:(NSNotification *)notification;
- (void)accountWasAuthorised:(NSNotification *)notification;
- (void)accountWasPreviouslyAuthorised:(NSNotification *)notification;
- (void)accountWasDeauthorised:(NSNotification *)notification;
- (void)showUserInfoView;

@end

#pragma mark -
#pragma mark Initialisation

@implementation MRAccountPreferencesViewController

- (NSString *)nibName
{
    return @"MRAccountPreferencesView";
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(accountWasAuthorised:)
                                                     name:MRAccountAuthorised object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(accountWasPreviouslyAuthorised:)
                                                     name:MRHubbyIsOffline object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(accountWasDeauthorised:)
                                                     name:MRAccountDeauthorised object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(showProgress:)
                                                     name:MRWaitingOnApiRequest object:nil];
        
        [[self view] addSubview:[self userAuthenticateView]];
    }
    
    return self;
}

#pragma mark -
#pragma mark Action Methods

- (IBAction)authoriseAccount:(id)sender
{
    [[NXOAuth2AccountStore sharedStore] requestAccessToAccountWithType:@"GitHub"];
}

- (IBAction)deauthoriseAccount:(id)sender
{
    for (NXOAuth2Account *account in [[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"]) {
        [[NXOAuth2AccountStore sharedStore] removeAccount:account];
    };
    
    [[self userInfoView] removeFromSuperview];
    [[self view] addSubview:[self userAuthenticateView]];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:MRUserDidDeauthorise object:nil];
}

#pragma mark -
#pragma mark Notifications

- (void)accountWasAuthorised:(NSNotification *)notification
{
    NSDictionary *userInfo = [notification object];
    
    if ([userInfo objectForKey:@"name"])
        [[self userInfoName] setStringValue:[NSString stringWithFormat:@"Name: %@", [userInfo objectForKey:@"name"]]];
    else
        [[self userInfoName] setStringValue:[NSString stringWithFormat:@"Name: none"]];
    
    if ([userInfo objectForKey:@"location"])
        [[self userInfoLocation] setStringValue:[NSString stringWithFormat:@"Location: %@", [userInfo objectForKey:@"location"]]];
    else
        [[self userInfoLocation] setStringValue:[NSString stringWithFormat:@"Location: none"]];
  
    // save user data to disk for offline accesss
    NSData *userInfoData = [userInfo JSONData];
    if(![userInfoData writeToURL:[[MRAppDelegate hubbySupportDir] URLByAppendingPathComponent:@"user.json"] atomically:YES]) {
        DDLogError(@"error writing api request data to disk");
    }
    
    NSString *gravatarId = [userInfo objectForKey:@"gravatar_id"];
    
    if (gravatarId) { // user has an avatar
        NSURL *gravatarURL = [NSURL URLWithString:[NSString stringWithFormat:@"http://www.gravatar.com/avatar/%@?s=210", gravatarId]];

        NSURLRequest *request = [NSURLRequest requestWithURL:gravatarURL];
        
        [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
            
            if ([data length] > 0 && error == nil) {
                NSImage *userAvatarImage = [[NSImage alloc] initWithData:data];
                [[self userAvatar] setImage:userAvatarImage];
                
                // save user avatar image to disk for offline accesss
                if (![[userAvatarImage TIFFRepresentation] writeToURL:[[MRAppDelegate hubbySupportDir] URLByAppendingPathComponent:@"avatar.tiff"] atomically:YES]) {
                    DDLogError(@"error writing avatar image to disk");
                }
            }
            else {
                // a failed request occured so test for an existing loaded image first
                // and fallback to using a local image or dummy image if necessary
                if ([[self userAvatar] image] == nil) {
                    DDLogError(@"failed avatar image request, attempting to load from disk");
                    
                    NSData *avatarImageData = [NSData dataWithContentsOfURL:[[MRAppDelegate hubbySupportDir] URLByAppendingPathComponent:@"avatar.tiff"]];
                    
                    if (avatarImageData) {
                        NSImage *userAvatarImage = [[NSImage alloc] initWithData:avatarImageData];
                        [[self userAvatar] setImage:userAvatarImage];
                    }
                    else {
                        DDLogError(@"no local avatar image, using dummy instead");
                        // TODO set dummy image
                    }
                }
            }
            
            [self showUserInfoView];
        }];
    }
    else { // user has no avatar
        // TODO insert dummy user image into image well
        [self showUserInfoView];
    }
}

- (void)accountWasPreviouslyAuthorised:(NSNotification *)notification
{
    NSImage *userAvatarImage = [[NSImage alloc] initWithContentsOfURL:[[MRAppDelegate hubbySupportDir] URLByAppendingPathComponent:@"avatar.tiff"]];
    
    if (userAvatarImage)
        [[self userAvatar] setImage:userAvatarImage];
    //else
    // TODO set dummy avatar image (no image is saved if user has none)
    
    NSData *userInfoData = [NSData dataWithContentsOfURL:[[MRAppDelegate hubbySupportDir] URLByAppendingPathComponent:@"user.json"]];
    
    if (userInfoData) {
        NSDictionary *userInfo = [userInfoData objectFromJSONData];
        
        if ([userInfo objectForKey:@"name"])
            [[self userInfoName] setStringValue:[NSString stringWithFormat:@"Name: %@", [userInfo objectForKey:@"name"]]];
        else
            [[self userInfoName] setStringValue:[NSString stringWithFormat:@"Name: none"]];
        
        if ([userInfo objectForKey:@"location"])
            [[self userInfoLocation] setStringValue:[NSString stringWithFormat:@"Location: %@", [userInfo objectForKey:@"location"]]];
        else
            [[self userInfoLocation] setStringValue:[NSString stringWithFormat:@"Location: none"]];
        
        [[self userAuthenticateView] removeFromSuperview];
        [[self view] addSubview:[self userInfoView]];
    }
    else {
        // reading user.json failed, this could mean that the user removed
        // the file or application support directory, or the previous
        // attempt at saving failed
        
        // TODO deauthorise hubby, as we have no previously saved user data!
    }
}

- (void)accountWasDeauthorised:(NSNotification *)notification
{ 
    [[self authoriseButton] setEnabled:YES];
    [[self progressIndicator] stopAnimation:nil];
    [[self progressIndicator] setHidden:YES];

    [[self userInfoView] removeFromSuperview];
    [[self view] addSubview:[self userAuthenticateView]];
}

- (void)showProgress:(NSNotification *)notification
{
    [[self authoriseButton] setEnabled:NO];
    [[self progressIndicator] setHidden:NO];
    [[self progressIndicator] startAnimation:nil];
}

- (void)showUserInfoView
{
    [[self userAuthenticateView] removeFromSuperview];
    [[self view] addSubview:[self userInfoView]];
    
    [[self authoriseButton] setEnabled:YES];
    [[self progressIndicator] stopAnimation:nil];
    [[self progressIndicator] setHidden:YES];
}

@end
