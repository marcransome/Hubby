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

extern int ddLogLevel;

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
@property (weak) IBOutlet NSButton *closeButton;
@property (strong) NSURLConnection *urlConnection;
@property (strong) NSMutableData *responseData;

- (IBAction)createRepository:(id)sender;
- (IBAction)cancelRequest:(id)sender;

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
    
    // populate .gitignore pop-up
    NSURL *gitignoreFile = [[NSBundle mainBundle] URLForResource:@"gitignore" withExtension:@"txt"];
    NSString *fileContents = [[NSString alloc] initWithContentsOfURL:gitignoreFile usedEncoding:nil error:NULL];
    for (NSString *language in [fileContents componentsSeparatedByString:@"\n"]) {
        if ([language length] > 0) {
            [[self gitignorePopUp] addItemWithTitle:language];
        }
    }
    
    // ensure that close window control cancels pending request
    [self setCloseButton:[[self window] standardWindowButton:NSWindowCloseButton]];
    [[self closeButton] setTarget:self];
    [[self closeButton] setAction:@selector(cancelRequest:)];
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
    
    DDLogVerbose(@"%@", [jsonPayload JSONString]);
    
    NXOAuth2Request *request = [[NXOAuth2Request alloc] initWithResource:[NSURL URLWithString:@"https://api.github.com/user/repos"]
                                                                     method:@"POST"
                                                                 parameters:nil];
    
    [request setAccount:[[[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"] lastObject]];
    
    NSMutableURLRequest *signedRequest = [[request signedURLRequest] mutableCopy];
    [signedRequest setHTTPBody:[jsonPayload JSONData]];

    [self setUrlConnection:[NSURLConnection connectionWithRequest:signedRequest delegate:self]];
}

- (IBAction)cancelRequest:(id)sender {
    [[self urlConnection] cancel];
    [[self progressIndicator] stopAnimation:nil];
    [[self progressIndicator] setHidden:YES];
    [[self createButton] setEnabled:YES];
    
    [self close];
}

#pragma mark -
#pragma mark General Support Methods

- (void)showAlertWithTitle:(NSString *)title informativeText:(NSString *)text
{
    [[self progressIndicator] stopAnimation:nil];
    [[self progressIndicator] setHidden:YES];
    [[self createButton] setEnabled:YES];
    
    NSAlert *alert = [NSAlert alertWithMessageText:title defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"%@", text];
    
    [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:nil contextInfo:nil];
}

#pragma mark -
#pragma mark NSURLConnectionDataDelegate Methods

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    _responseData = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [_responseData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [[self progressIndicator] stopAnimation:nil];
    [[self progressIndicator] setHidden:YES];
    [[self createButton] setEnabled:YES];
    
    if ([error code] == NSURLErrorNotConnectedToInternet) {
        [self showAlertWithTitle:@"Network error" informativeText:@"Your Internet connection appears to be offline."];
    }
    else {
        [self showAlertWithTitle:@"Network error" informativeText:@"An unknown network error occured."];
    }
}

- (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse
{
    return nil;
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
    return request;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [[self progressIndicator] stopAnimation:nil];
    [[self progressIndicator] setHidden:YES];
    [[self createButton] setEnabled:YES];

    // POST was successful, but api request may still have failed

    NSDictionary *dataDict = [[self responseData] objectFromJSONData];
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
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"OpenAfterCreateRepo"])
        {
            NSURL *repoURL = [NSURL URLWithString:[[[self responseData] objectFromJSONData] objectForKey:@"html_url"]];
            [[NSWorkspace sharedWorkspace] openURL:repoURL];
        }

        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CopyAfterCreateRepo"])
        {
            NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
            [pasteboard clearContents];

            NSURL *repoURL = [NSURL URLWithString:[[[self responseData] objectFromJSONData] objectForKey:@"html_url"]];
            NSArray *pasteboardArray = @[repoURL];

            [pasteboard writeObjects:pasteboardArray];
        }

        [self close];
    }
}

@end
