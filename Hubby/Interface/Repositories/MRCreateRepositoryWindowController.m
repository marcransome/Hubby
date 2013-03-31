//
//  MRGistWindowController.m
//  Hubby
//
//  Created by Marc Ransome on 25/03/2013.
//  Copyright (c) 2013 fidgetbox. All rights reserved.
//

#import "MRCreateRepositoryWindowController.h"
#import <NXOAuth2.h>
#import <JSONKit.h>
#import <DDLog.h>

extern NSString* ddLogLevel;

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

- (IBAction)createRepository:(id)sender;

@end

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
}

- (IBAction)createRepository:(id)sender
{
    [_progressIndicator setHidden:NO];
    [_progressIndicator startAnimation:nil];

    NSMutableDictionary *jsonPayload = [NSMutableDictionary dictionary];
    
    // required parameters
    [jsonPayload setObject:[[self name] stringValue] forKey:@"name"];
    
    // validity tests
    if ([[[self homepage] stringValue] length] > 0) {
        if (![NSURL URLWithString:[[self homepage] stringValue]]) {
            NSAlert *alert = [NSAlert alertWithMessageText:@"Invalid URL" defaultButton:nil alternateButton:nil otherButton:nil informativeTextWithFormat:@"The Homepage URL you provided is not valid."];
            
            [alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:nil contextInfo:nil];
            return;
        }
    }
    
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
    if ([[self initialiseRepository] state] == NSOnState)
        [jsonPayload setObject:[NSNumber numberWithBool:YES] forKey:@"auto_init"];
    
    NSLog(@"%@", [jsonPayload JSONString]);

    
    NXOAuth2Request *request = [[NXOAuth2Request alloc] initWithResource:[NSURL URLWithString:@"https://api.github.com/user/repos"]
                                                                     method:@"POST"
                                                                 parameters:nil];
    
    [request setAccount:[[[NXOAuth2AccountStore sharedStore] accountsWithAccountType:@"GitHub"] lastObject]];
    
    NSMutableURLRequest *signedRequest = [[request signedURLRequest] mutableCopy];
    [signedRequest setHTTPBody:[jsonPayload JSONData]];

    [NSURLConnection sendAsynchronousRequest:signedRequest queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        
        NSLog(@"wooo %d", [NSThread isMainThread]);
        
        [[self progressIndicator] stopAnimation:nil];
        [[self progressIndicator] setHidden:YES];
        
        // POST was successful, but api request may still have failed
        
//        NSString *dataString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
//        NSDictionary *dataDict = [dataString objectFromJSONString];
//        NSDictionary *errorsDict = [dataDict objectForKey:@"errors"];
//        
//        if (errorsArray) {
//            if (errorsArray obj) {
//                <#statements#>
//            }
//        }
//        
//        DDLogVerbose("%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        
        
        
        
        NSLog(@"%@", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
        
        // ONLY if successful
        
        
        
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"openAfterCreateRepo"])
        {
            NSURL *repoURL = [NSURL URLWithString:[[data objectFromJSONData] objectForKey:@"html_url"]];
            
            NSLog(@"%@", repoURL);
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
    }];

    

}
    
@end
