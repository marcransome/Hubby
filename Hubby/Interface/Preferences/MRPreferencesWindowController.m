//
//  MRPreferencesWindowController.m
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

#import "MRPreferencesWindowController.h"

#pragma mark Constants

static NSString* const MRGeneralPreferencesName = @"MRGeneralPreferencesViewController";
static NSString* const MREventsPreferencesName = @"MREventsPreferencesViewController";
static NSString* const MRUpdatePreferencesName = @"MRUpdatePreferencesViewController";

static NSString* const MRGeneralPreferencesIdentifier = @"general";
static NSString* const MREventsPreferencesIdentifier = @"events";
static NSString* const MRUpdatePreferencesIdentifier = @"update";

static NSString* const MRGeneralPreferencesWindowTitle = @"General";
static NSString* const MREventsPreferencesWindowTitle = @"Events";
static NSString* const MRUpdatePreferencesWindowTitle = @"Update";

@implementation MRPreferencesWindowController

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        [self setViewControllers:[NSMutableDictionary dictionary]];
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

#pragma mark -
#pragma mark View Management Methods

- (void)activateViewController:(NSViewController *)viewController
{
    // obtain current content frame size and view content size for comparison
    NSRect oldContentFrame = [[[self window] contentView] frame];
    NSRect newContentFrame = [[viewController view] frame];
    
    // calculate size difference between old content frame and new view
    CGFloat widthDifference = oldContentFrame.size.width - newContentFrame.size.width;
    CGFloat heightDifference = oldContentFrame.size.height - newContentFrame.size.height;
    
    // construct rectangle with new window dimensions
    NSRect windowFrame = [[self window] frame];
    windowFrame.size.width -= widthDifference;
    windowFrame.size.height -= heightDifference;
    windowFrame.origin.y += heightDifference;
    
    // remove current view
    [[[self currentViewController] view] removeFromSuperview];
    
    // update current view controller with new view
    [self setCurrentViewController:viewController];
    
    // resize the window to accomodate the new view
    [[self window] setFrame:windowFrame display:YES animate:YES];
    
    // add new view to window's content view
    [[[self window] contentView] addSubview:[viewController view]];
}

- (NSViewController *)viewControllerForName:(NSString *)name
{
    // test for existing view controller and return if found
    NSViewController *desiredViewController = [[self viewControllers] objectForKey:name];
    if (desiredViewController)
        return desiredViewController;
    
    // create non-existent view controller
    Class controllerClass = NSClassFromString(name);
    desiredViewController = [[controllerClass alloc] init];
    
    // retain controller reference
    [[self viewControllers] setObject:desiredViewController forKey:name];
    
    return desiredViewController;
}

-(void)setInitialPreference:(NSString *)preferenceName
{
    // construct dictionary of preference names and identifiers
    NSMutableDictionary *preferenceIdentifierDatabase = [NSMutableDictionary dictionary];
    [preferenceIdentifierDatabase setObject:MRGeneralPreferencesIdentifier forKey:MRGeneralPreferencesName];
    [preferenceIdentifierDatabase setObject:MREventsPreferencesIdentifier forKey:MREventsPreferencesName];
    [preferenceIdentifierDatabase setObject:MRUpdatePreferencesIdentifier forKey:MRUpdatePreferencesName];
    
    // construct dictionary of preference names and window titles
    NSMutableDictionary *preferenceWindowTitleDatabase = [NSMutableDictionary dictionary];
    [preferenceWindowTitleDatabase setObject:MRGeneralPreferencesWindowTitle forKey:MRGeneralPreferencesName];
    [preferenceWindowTitleDatabase setObject:MREventsPreferencesWindowTitle forKey:MREventsPreferencesName];
    [preferenceWindowTitleDatabase setObject:MRUpdatePreferencesWindowTitle forKey:MRUpdatePreferencesName];
    
    // setup initial view controller
    NSViewController *initalViewController;
    initalViewController = [self viewControllerForName:preferenceName];
    
    // obtain current content frame size and view content size for comparison
    NSRect oldContentFrame = [[[self window] contentView] frame];
    NSRect newContentFrame = [[initalViewController view] frame];
    
    // calculate size difference between old content frame and new view
    CGFloat widthDifference = oldContentFrame.size.width - newContentFrame.size.width;
    CGFloat heightDifference = oldContentFrame.size.height - newContentFrame.size.height;
    
    // construct rectangle with new window dimensions
    NSRect windowFrame = [[self window] frame];
    windowFrame.size.width -= widthDifference;
    windowFrame.size.height -= heightDifference;
    windowFrame.origin.y += heightDifference;
    
    // update current view controller with new view
    [self setCurrentViewController:initalViewController];
    
    // resize the window to accomodate the new view
    [[self window] setFrame:windowFrame display:NO];
    
    // show the new view
    [[[self window] contentView] addSubview:[initalViewController view]];
    
    // obtain identifier for the received preference name
    NSString *identifier;
    identifier = [preferenceIdentifierDatabase objectForKey:preferenceName];
    
    // select appropriate toolbar icon using identifier
    [[self toolbar] setSelectedItemIdentifier:identifier];
    
    // set window title
    [[self window] setTitle: [preferenceWindowTitleDatabase objectForKey:preferenceName]];
}

#pragma mark -
#pragma mark Action Methods


- (IBAction)changeView:(id)sender
{
    // construct dictionary of preference names and identifiers
    NSMutableDictionary *preferenceControllerDatabase = [NSMutableDictionary dictionary];
    [preferenceControllerDatabase setObject:MRGeneralPreferencesName forKey:MRGeneralPreferencesIdentifier];
    [preferenceControllerDatabase setObject:MREventsPreferencesName forKey:MREventsPreferencesIdentifier];
    [preferenceControllerDatabase setObject:MRUpdatePreferencesName forKey:MRUpdatePreferencesIdentifier];
    
    // construct dictionary of preference names and window titles
    NSMutableDictionary *preferenceWindowTitleDatabase = [NSMutableDictionary dictionary];
    [preferenceWindowTitleDatabase setObject:MRGeneralPreferencesWindowTitle forKey:MRGeneralPreferencesIdentifier];
    [preferenceWindowTitleDatabase setObject:MREventsPreferencesWindowTitle forKey:MREventsPreferencesIdentifier];
    [preferenceWindowTitleDatabase setObject:MRUpdatePreferencesWindowTitle forKey:MRUpdatePreferencesIdentifier];
    
    // get preference controller name and window title
    NSString *windowTitle = [preferenceWindowTitleDatabase objectForKey:[sender itemIdentifier]];
    NSString *controllerName = [preferenceControllerDatabase objectForKey:[sender itemIdentifier]];
    
    // activate view controller
    [self activateViewController:[self viewControllerForName:controllerName]];
    
    // set window title
    [[self window] setTitle:windowTitle];
    
    // update shared user defaults so this becomes our default view on next launch
    [[NSUserDefaults standardUserDefaults] setObject:controllerName forKey:@"DefaultPreferenceViewController"];
}

@end
