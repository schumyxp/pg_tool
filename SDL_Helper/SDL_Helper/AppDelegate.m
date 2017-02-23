//
//  AppDelegate.m
//  SDL_Helper
//
//  Created by Yiming Lu on 21/02/2017.
//  Copyright © 2017 Yiming Lu. All rights reserved.
//

#import "AppDelegate.h"
#import <WebKit/WebKit.h>

@interface AppDelegate ()

@property (weak) IBOutlet WebView *webview;
@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextView *logview;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    //load webview
    NSString *urlText = @"https://intuit.idiomworldserver.com/ws/assignments_projects";
    [[self.webview mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlText]]];
    
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

//web inject function
-(void)web_auto_login{
    DOMDocument *doc = [[self.webview mainFrame] DOMDocument];


}

//webview delegate
- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame{
    [self appendToMyTextView:@"starting loading page..."];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame{
    [self appendToMyTextView:@"loading page error."];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame{
    [self appendToMyTextView:@"finish loading."];
    
    //auto login
    [self web_auto_login];
}


-(IBAction)m_download:(id)sender{
    //[self appendToMyTextView:@"download menu clic"];
    NSLog(@"download menu click");
}

-(IBAction)m_refresh:(id)sender{
    //[self appendToMyTextView:@"download menu clic"];
    NSLog(@"refresh menu click");
}

- (void)appendToMyTextView:(NSString*)text
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAttributedString* attr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", text]];
        [[self.logview textStorage] appendAttributedString:attr];
        [self.logview scrollRangeToVisible:NSMakeRange([[self.logview string] length], 0)];
    });
}


@end
