//
//  MRCreateRepositoryWindowController.m
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

#import "MRCreateRepositoryWindowController.h"
#import <NXOAuth2.h>
#import <JSONKit.h>
#import <DDLog.h>

#pragma mark Externs

extern NSString* ddLogLevel;

#pragma mark -
#pragma mark Interface

@interface MRCreateRepositoryWindowController ()

@property (weak) IBOutlet NSTextField *name;
@property (weak) IBOutlet NSButton *private;
@property (weak) IBOutlet NSTextField *description;
@property (weak) IBOutlet NSTextField *homepage;
@property (weak) IBOutlet NSButton *enableIssueTracking;
@property (weak) IBOutlet NSButton *enableDownloads;
@property (weak) IBOutlet NSButton *enableWiki;
@property (weak) IBOutlet NSButton *initialiseRepository;
@property (weak) IBOutlet NSProgressIndicator *progressIndicator;
@property (weak) IBOutlet NSButton *createButton;
@property (weak) IBOutlet NSPopUpButton *gitignorePopUp;

- (IBAction)createRepository:(id)sender;
- (void)showAlertWithTitle:(NSString *)title informativeText:(NSString *)text;

@end

#pragma mark -
#pragma mark Initialisation

@implementation MRCreateRepositoryWindowController

- (NSString *)nibName
{
    return @"MRCreateRepositoryWindow";
}

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
    NSString *gitignoreFile = [[NSBundle mainBundle] pathForResource:@"gitignore" ofType:@"txt"];

    NSStringEncoding encoding;
    NSError *error;
    NSString *fileContents = [[NSString alloc] initWithContentsOfFile:gitignoreFile
                                                          usedEncoding:&encoding
                                                                 error:&error];
    
    // TODO error checks
    
    for (NSString *language in [fileContents componentsSeparatedByString:@"\n"]) {
        if ([language length] > 0) {
            [[self gitignorePopUp] addItemWithTitle:language];
        }
    }
}

#pragma mark -
#pragma mark Action Methods

- (IBAction)createRepository:(id)sender
{
    [[self progressIndicator] setHidden:NO];
    [[self progressIndicator] startAnimation:nil];
    [[self createButton] setEnabled:NO];

    NSMutableDictionary *jsonPayload = [NSMutableDictionary dictionary];

    // validity tests
    if (![[[self name] stringValue] length] > 0) {
        [self showAlertWithTitle:@"Invalid name" informativeText:@"You must provide a name to create a new repository."];
        return;
    }
    
    if ([[[self homepage] stringValue] length] > 0) {
        if (![NSURL URLWithString:[[self homepage] stringValue]]) {
            [self showAlertWithTitle:@"Invalid URL" informativeText:@"The Homepage URL you provided is not valid."];
            return;
        }
    }
    
    // required parameters
    [jsonPayload setObject:[[self name] stringValue] forKey:@"name"];
    
    // optional parameters
    if ([[self private] state] == NSOnState)
        [jsonPayload setObject:[NSNumber numberWithBool:YES] forKey:@"private"];
    if ([[[self description] stringValue] length] > 0)
        [jsonPayload setObject:[[self description] stringValue] forKey:@"description"];
    if ([[[self homepage] stringValue] length] > 0)
        [jsonPayload setObject:[[self homepage] stringValue] forKey:@"homepage"];
    if ([[self enableIssueTracking] state] == NSOnState)
        [jsonPayload setObject:[NSNumber numberWithBool:YES] forKey:@"has_issues"];
    if ([[self enableWiki] state] == NSOnState)
        [jsonPayload setObject:[NSNumber numberWithBool:YES] forKey:@"has_wiki"];
    if ([[self enableDownloads] state] == NSOnState)
        [jsonPayload setObject:[NSNumber numberWithBool:YES] forKey:@"has_downloads"];
    if ([[self initialiseRepository] state] == NSOnState) {
        [jsonPayload setObject:[NSNumber numberWithBool:YES] forKey:@"auto_init"];
        if (![[[[self gitignorePopUp] selectedItem] title] isEqualToString:@"None"]) {
            [jsonPayload setObject:[[[self gitignorePopUp] selectedItem] title] forKey:@"gitignore_template"];
        }
    }
    
    NSLog(@"%@", [jsonPayload JSONString]);
    
    NXOAuth2Request *request = [[NXOAuth2Request alloc] initWithResource:[NSURL URLWithString:@"https://api.github.com/user/repos"]
                                                                     method:@"POST"
                                                                 parameters:nil];
    
    [request setAccount:[[[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"] lastObject]];
    
    NSMutableURLRequest *signedRequest = [[request signedURLRequest] mutableCopy];
    [signedRequest setHTTPBody:[jsonPayload JSONData]];

    [NSURLConnection sendAsynchronousRequest:signedRequest queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        
        [[self progressIndicator] stopAnimation:nil];
        [[self progressIndicator] setHidden:YES];
        [[self createButton] setEnabled:YES];
        
        if ([data length] > 0 && error == nil) {
            // POST was successful, but api request may still have failed
            
            NSDictionary *dataDict = [data objectFromJSONData];
            NSArray *errorsArray = [dataDict objectForKey:@"errors"];
            
            if (errorsArray) {
                
                NSString *errorString = @"The following error(s) occured:";
                
                for (NSDictionary *errorDict in errorsArray) {
                    errorString = [errorString stringByAppendingString:[NSString stringWithFormat:@"\n\u2022 %@", [errorDict objectForKey:@"message"]]];
                }

                [self showAlertWithTitle:@"Creation failed" informativeText:errorString];
                return;
            }
            else {
                NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

                if ([[NSUserDefaults standardUserDefaults] boolForKey:@"openAfterCreateRepo"])
                {
                    NSURL *repoURL = [NSURL URLWithString:[[data objectFromJSONData] objectForKey:@"html_url"]];
                    [[NSWorkspace sharedWorkspace] openURL:repoURL];
                }
                
                if ([[NSUserDefaults standardUserDefaults] boolForKey:@"copyAfterCreateRepo"])
                {
                    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
                    [pasteboard clearContents];
                 
                    NSURL *repoURL = [NSURL URLWithString:[[data objectFromJSONData] objectForKey:@"html_url"]];
                    NSArray *pasteboardArray = @[repoURL];
                    
                    [pasteboard writeObjects:pasteboardArray];
                }
                
                [self close];
            }
        }
    }];
}

#pragma mark -
#pragma mark General Support Methods

- (void)showAlertWithTitle:(NSString *)title informativeText:(NSString *)text
{
    NSAlert *alert = [NSAlert alertWithMessageText:title defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"%@", text];
    
    [[self progressIndicator] stopAnimation:nil];
    [[self progressIndicator] setHidden:YES];
    [[self createButton] setEnabled:YES];
    
    [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

@end
