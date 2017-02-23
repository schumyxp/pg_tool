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

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet WebView *webview;
@property (weak) IBOutlet NSTextView *logview;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    
    //load config file
}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


-(IBAction)m_download:(id)sender{
    [self appendToMyTextView:@"download menu clic"];
    //NSLog(@"download menu click");
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
