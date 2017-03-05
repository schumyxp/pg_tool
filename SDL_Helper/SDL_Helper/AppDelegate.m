//
//  AppDelegate.m
//  SDL_Helper
//
//  Created by Yiming Lu on 21/02/2017.
//  Copyright © 2017 Yiming Lu. All rights reserved.
//

#import "AppDelegate.h"
#import <WebKit/WebKit.h>
#import "SDLDownloadFile.h"

typedef enum : NSUInteger {
    LOG_LEVEL_ALL = 0,
    LOG_LEVEL_USer = 1,
} LOG_LEVEL;

@interface AppDelegate (){
    NSString *currentUrl;
    NSString *mainUrl;
    NSString *domain;
    NSString *username;
    NSString *pwd;
    NSUInteger download_files_total;
    NSUInteger download_files_done;
    SDLDownloadFile *current_download_task;
    
    LOG_LEVEL my_log_level;
    Boolean is_download_scope;
    NSMutableArray *should_download_files;
}

@property (weak) IBOutlet WebView *webview;
@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextView *logview;
@property (weak) IBOutlet NSMenuItem *downloadScopeMenu;
@property (weak) IBOutlet NSProgressIndicator *pageload_PI;
@property (weak) IBOutlet NSProgressIndicator *download_PI;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    self->should_download_files = [NSMutableArray new];
    self->is_download_scope = false;
    [self.logview setEditable:false];
    [self.downloadScopeMenu setEnabled:false];
    self->download_files_total = 0;
    self->download_files_done = 0;
    self->my_log_level = LOG_LEVEL_USer;//use LOG_LEVEL_ALL for debug
    
    [self loadconfig];
    
    //load webview
    NSString *urlText = [NSString stringWithFormat:@"%@/ws/login?wanted=assignments_projects", self->domain];
    [[self.webview mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlText]]];
}

- (void)loadconfig{    
    //read from plist
    NSDictionary *theDict = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"config" ofType:@"plist"]];
    self->domain = [theDict objectForKey:@"domain"];
    self->username = [theDict objectForKey:@"username"];
    self->pwd = [theDict objectForKey:@"password"];

}


- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}


//webview delegate
- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame{
    [self appendToMyTextView:@"starting loading page..." log_level:LOG_LEVEL_ALL];
    [self pageload_Progress:true];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame{
    [self appendToMyTextView:@"loading page error." log_level:LOG_LEVEL_ALL];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame{
    self->currentUrl = [[[[frame dataSource] request] URL] absoluteString];
    [self appendToMyTextView:[NSString stringWithFormat:@"finish loading %@", self->currentUrl] log_level:LOG_LEVEL_ALL];
    [self pageload_Progress:false];
    
    if([self->currentUrl containsString:@"/ws/login"]){
        //auto login
        [self web_auto_login];
    }
    else if([self->currentUrl containsString:@"/ws/assignments_project_info_scope"]){
        //download file
        [self do_download_file];
    }
    else if([self->currentUrl containsString:@"/ws/assignments_projects?"]){
        self->mainUrl = self->currentUrl;
        //could enable download menu
        [self.downloadScopeMenu setEnabled:true];
        [self appendToMyTextView:@"You can select projects to download now." log_level:LOG_LEVEL_USer];
    }
    else if([self->currentUrl containsString:@"/ws/assignments_tasks?"]){
        //navi to download files
        [self navi_to_download_file];
    }

}

//web inject function
-(void)web_auto_login{
    [self appendToMyTextView:@"auto login..." log_level:LOG_LEVEL_USer];
    DOMDocument *doc = [[self.webview mainFrame] DOMDocument];
    
    DOMHTMLInputElement *username_el = (DOMHTMLInputElement*)[doc getElementById:@"username"];
    [username_el setValue:self->username];

    DOMHTMLInputElement *password_el = (DOMHTMLInputElement*)[doc getElementById:@"password"];
    [password_el setValue:self->pwd];
    
    DOMHTMLFormElement *form = (DOMHTMLFormElement *)[doc getElementById:@"loginForm"];
    [form submit];
}

- (void)get_download_files{
    [self->should_download_files removeAllObjects];//clear
    
    DOMDocument *doc = [[self.webview mainFrame] DOMDocument];
    DOMNodeList *tbodies = [doc getElementsByTagName:@"tbody"];
    for(int i=0; i< [tbodies length]; i++){
        DOMElement *el = (DOMElement*)[tbodies item:i];
        NSString *tbody_id = [el getAttribute:@"id"];
        if([tbody_id containsString:@"_tbody"]){
            if(![tbody_id containsString:@"_message_tbody"]){
                //find it
                
                DOMNodeList *trs = [el getElementsByTagName:@"tr"];
                for(int j=0; j < [trs length];j++){
                    DOMElement *tr = (DOMElement*)[trs item:j];
                    DOMHTMLInputElement *input = (DOMHTMLInputElement*)[tr querySelector:@"input"];
                    if([input checked]){
                        DOMHTMLLinkElement *project_link = (DOMHTMLLinkElement*)[tr querySelector:@"a"];
                        SDLDownloadFile *sdlfile = [SDLDownloadFile new];
                        sdlfile.url = [project_link href];
                        sdlfile.projectName = [project_link innerText];
                        sdlfile.projectID = [input getAttribute:@"value"];
                        [self->should_download_files addObject:sdlfile];
                    }
                }
                
                break;
            }
        }
    }
    
    self->download_files_total = [self->should_download_files count];
    if(self->download_files_total > 0){
        [self download_Progress:(0.5 + self->download_files_done)/self->download_files_total];
        [self start_download_file];
    }
}

//open assignments_tasks page & click "View scoping information" link
-(void)navi_to_download_file{
    [self appendToMyTextView:self->currentUrl log_level:LOG_LEVEL_ALL];
    DOMDocument *doc = [[self.webview mainFrame] DOMDocument];

    DOMNodeList *a_list = [doc getElementsByTagName:@"a"];
    for(int i=0; i< [a_list length]; i++){
        DOMHTMLLinkElement *link = (DOMHTMLLinkElement *)[a_list item:i];
        NSString *href = [link href];
        if([href containsString:@"assignments_project_info_scope"]){
            //open it
            [[self.webview mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:href]]];
            return;
        }
    }
}

//download file
-(void)do_download_file{
    DOMDocument *doc = [[self.webview mainFrame] DOMDocument];
    DOMNodeList *a_list = [doc getElementsByClassName:@"button"];
    DOMHTMLLinkElement *link = (DOMHTMLLinkElement *)[a_list item:0];

    //get download link from onclick
    NSString *onclick = [link getAttribute:@"onclick"];
    NSArray *comp = [onclick componentsSeparatedByString:@"'"];
    NSString *downlink = nil;
    for(NSString *str in comp){
        if([str containsString:@"csv_download"]){
            downlink = str;
            break;
        }
    }
    NSString *urlText = [NSString stringWithFormat:@"%@/ws/%@", self->domain, downlink];
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDownloadTask *dataTask = [session downloadTaskWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlText]]
        completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
            NSString *cd = [[httpResponse allHeaderFields] valueForKey:@"Content-Disposition"];
            NSString *filename = [[cd componentsSeparatedByString:@"''"] lastObject];
            filename = [filename stringByReplacingOccurrencesOfString:@"\"" withString:@""];
            filename = [NSString stringWithFormat:@"%@%@", self->current_download_task.projectID, filename];
            
            NSString *homeDirectory = NSHomeDirectory();
            NSString *destinationFileName = [[homeDirectory stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:filename];
            NSURL *toURL = [NSURL fileURLWithPath:destinationFileName];
        
            NSFileManager *fileManager = [NSFileManager defaultManager];
            [fileManager moveItemAtURL:location toURL:toURL error:&error];
            
            self->download_files_done++;
            [self download_Progress: (self->download_files_done+0.0)/self->download_files_total ];
            [self pageload_Progress:false];
            [self appendToMyTextView: [NSString stringWithFormat:@"success download %@\n", filename] log_level:LOG_LEVEL_USer];

            NSLog(@"File Downloaded Succesfully");
                                                        
            //download another file
            [self start_download_file];
    }];
    [dataTask resume];
}

-(void)start_download_file{
    dispatch_async(dispatch_get_main_queue(), ^{
        SDLDownloadFile *sdlfile = (SDLDownloadFile*)[self->should_download_files firstObject];
        if(sdlfile){
            [self->should_download_files removeObjectAtIndex:0];
            [self appendToMyTextView: [NSString stringWithFormat:@"downloading %@", sdlfile.url] log_level:LOG_LEVEL_ALL];
            [self appendToMyTextView: [NSString stringWithFormat:@"start to download project : %@ %@", sdlfile.projectID ,sdlfile.projectName] log_level:LOG_LEVEL_USer];
            [self pageload_Progress:true];
            self->current_download_task = sdlfile;
            [[self.webview mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:sdlfile.url]]];
        }
        else{
            //return to main page
            [self appendToMyTextView:@"finish all download tasks. return to main page..." log_level:LOG_LEVEL_USer];
            [self download_Progress:1];
            self->is_download_scope = false;
            self->current_download_task = nil;
            [[self.webview mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self->mainUrl]]];
        }
    });
}



-(IBAction)m_download_scope:(id)sender{
    //[self appendToMyTextView:@"download menu clic"];
    NSLog(@"download menu click");
    self->is_download_scope = true;
    [self.downloadScopeMenu setEnabled:false];

    //check url
    if([self->currentUrl containsString:@"/ws/assignments_projects?"]){
        [self get_download_files];
    }
    else{
        self->is_download_scope = false;
    }
}

-(IBAction)m_refresh:(id)sender{
    //[self appendToMyTextView:@"download menu clic"];
    NSLog(@"refresh menu click");
    [[self.webview mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:self->currentUrl]]];
}

- (void)appendToMyTextView:(NSString*)text log_level:(LOG_LEVEL)log_level
{
    NSLog(@"%@", text);
    if(log_level >= self->my_log_level){
        dispatch_async(dispatch_get_main_queue(), ^{
            NSAttributedString* attr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", text]];
            [[self.logview textStorage] appendAttributedString:attr];
            [self.logview scrollRangeToVisible:NSMakeRange([[self.logview string] length], 0)];
        });
    }
}

- (void)pageload_Progress:(Boolean)b_start{
    dispatch_async(dispatch_get_main_queue(), ^{
        if(b_start){
            [self.pageload_PI startAnimation:self];
        }
        else{
            [self.pageload_PI stopAnimation:self];
        }
    });
}

- (void)download_Progress:(double)percent{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.download_PI setDoubleValue:percent];
    });
}


@end
