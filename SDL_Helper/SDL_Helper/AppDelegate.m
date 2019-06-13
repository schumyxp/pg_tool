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
    NSString *mainUrl;
    NSString *domain;
    NSString *username;
    NSString *pwd;
    NSUInteger download_files_total;
    
    LOG_LEVEL my_log_level;
    NSMutableDictionary *webviews;
    NSMutableDictionary *pagePIs;

    NSMutableDictionary *conditions;
    NSMutableDictionary *threadStatus;
}

@property (weak) IBOutlet WebView *webview1;
@property (weak) IBOutlet WebView *webview2;
@property (weak) IBOutlet WebView *webview3;

@property (weak) IBOutlet NSWindow *window;
@property (weak) IBOutlet NSTextView *logview;
@property (weak) IBOutlet NSMenuItem *downloadScopeMenu;
@property (weak) IBOutlet NSMenuItem *downloadAssetsMenu;
@property (weak) IBOutlet NSProgressIndicator *pageload_PI1;
@property (weak) IBOutlet NSProgressIndicator *pageload_PI2;
@property (weak) IBOutlet NSProgressIndicator *pageload_PI3;
@property (weak) IBOutlet NSProgressIndicator *pageload_PI4;

@property (weak) IBOutlet NSProgressIndicator *download_PI;

@property (atomic) NSMutableArray *downloadTasks;
@property (atomic) NSMutableDictionary *currentTasks;
@property (atomic) NSUInteger download_files_done;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // Insert code here to initialize your application
    [self.logview setEditable:false];
    [self.downloadScopeMenu setEnabled:false];
    self->download_files_total = 0;
    self.download_files_done = 0;
    self->my_log_level = LOG_LEVEL_USer;//use LOG_LEVEL_ALL for debug
    self.downloadTasks = [NSMutableArray array];
    self.currentTasks = [NSMutableDictionary dictionary];
    
    [self loadconfig];

    self.webview1.identifier = @"w1";
    self.webview2.identifier = @"w2";
    self.webview3.identifier = @"w3";
    self->webviews = [NSMutableDictionary dictionaryWithObjectsAndKeys:self.webview1, self.webview1.identifier,
                      self.webview2, self.webview2.identifier,
                      self.webview3, self.webview3.identifier,nil];
    self->pagePIs = [NSMutableDictionary dictionaryWithObjectsAndKeys:self.pageload_PI1, self.webview1.identifier,
                      self.pageload_PI2, self.webview2.identifier,
                      self.pageload_PI3, self.webview3.identifier, nil];

    
    //thread
    self->conditions = [NSMutableDictionary dictionaryWithObjectsAndKeys:[NSCondition new], self.webview1.identifier,
                        [NSCondition new], self.webview2.identifier,
                        [NSCondition new], self.webview3.identifier,nil];
    
    //load webview
    NSString *urlText = [NSString stringWithFormat:@"%@/ws-legacy/login", self->domain];
    [[self.webview1 mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlText]]];
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

//thread control
- (void)do_downloadTask_thread:(NSString *)key{
    NSLog(@"in thread %@", key);
    NSCondition *condition = (NSCondition*)[self->conditions objectForKey:key];

    while (true) {
        [condition lock];
        
        Boolean runningStatus = [self->threadStatus[key] boolValue];
        while(runningStatus){
            NSLog(@"thread %@ wait for signal", key);
            [condition wait];
        }
        
        SDLDownloadFile *task;
        //get a task, and do it
        @synchronized (self.downloadTasks) {
            if (self.downloadTasks.count == 0) {
                break;
            }
            task = (SDLDownloadFile *)[self.downloadTasks objectAtIndex:0];
            [self.downloadTasks removeObjectAtIndex:0];
        }
        
        self->threadStatus[key] = @YES;
        [condition unlock];

        [self start_download_file:key task:task];
    }
    NSLog(@"exit thread %@", key);
}

- (void)do_download_by_mainwebview:(NSString *)key{
    NSLog(@"in do_download_by_mainwebview thread %@", key);
    
    if(self.downloadTasks.count > 0) {
        SDLDownloadFile *task = (SDLDownloadFile *)[self.downloadTasks objectAtIndex:0];
        [self.downloadTasks removeObjectAtIndex:0];
        [self start_download_file:key task:task];
    }
    else{
        [self download_Progress:0];
        self.download_files_done = 0.0;
        self->download_files_total = 0.0;
    }
    NSLog(@"exit thread %@", key);
}

//webview delegate
- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame{
    [self appendToMyTextView:@"starting loading page..." log_level:LOG_LEVEL_ALL];
    [self pageload_Progress:true key:sender.identifier];
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame{
    [self appendToMyTextView:@"loading page error." log_level:LOG_LEVEL_ALL];
    
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame{
    NSString *currentUrl = [[[[frame dataSource] request] URL] absoluteString];
    [self appendToMyTextView:[NSString stringWithFormat:@"%@ finish loading %@", sender.identifier, currentUrl] log_level:LOG_LEVEL_ALL];
    [self appendToMyTextView:sender.identifier log_level:LOG_LEVEL_USer];

    [self pageload_Progress:false key:sender.identifier];
    
    if([currentUrl containsString:@"/ws-legacy/login"] && [sender.identifier isEqual: @"w1"]){
        //auto login to home by w1
        [self web_auto_login];
    }
    else if([currentUrl containsString:@"/ws-legacy/home?"]){
        //from home navi to assignments page
        [self navi_to_assignments_page:sender];
    }
    else if([currentUrl containsString:@"/ws-legacy/assignments?"]){
        //from assignments navi to assignments_projects page
        [self navi_to_assignments_projects_page:sender];
    }
    else if([currentUrl containsString:@"/ws-legacy/assignments_projects?"]){
        self->mainUrl = currentUrl;
        //could enable download menu
        [self.downloadScopeMenu setEnabled:true];
        [self appendToMyTextView:@"You can select projects to download now." log_level:LOG_LEVEL_USer];
    }
    else if([currentUrl containsString:@"/ws-legacy/assignments_tasks?"]){
        if([sender.identifier containsString:@"w2"]){
            //from assignments_tasks navi to download page
            [self navi_to_download_file:sender];
        }
        else{
            //download source
            [self navi_to_download_source:sender];
        }
    }
    else if([currentUrl containsString:@"/ws-legacy/assignments_project_info_scope"]){
        //download file
        [self do_download_file:sender];
    }
    else if([currentUrl containsString:@"/ws-legacy/download_assets"]){
        //Download Task Assets
        [self do_download_assets:sender];
    }
}

//web inject function
//from login to home
-(void)web_auto_login{
    [self appendToMyTextView:@"auto loading..." log_level:LOG_LEVEL_USer];
    DOMDocument *doc = [[self.webview1 mainFrame] DOMDocument];
    
    DOMHTMLInputElement *username_el = (DOMHTMLInputElement*)[doc getElementById:@"username"];
    [username_el setValue:self->username];

    DOMHTMLInputElement *password_el = (DOMHTMLInputElement*)[doc getElementById:@"password"];
    [password_el setValue:self->pwd];
    
    DOMHTMLFormElement *form = (DOMHTMLFormElement *)[doc getElementById:@"loginForm"];
    [form submit];
}

//from home to assignments
-(void)navi_to_assignments_page:(WebView *)a_webview{
    [self appendToMyTextView:@"auto loading..." log_level:LOG_LEVEL_USer];
    DOMDocument *doc = [[self.webview1 mainFrame] DOMDocument];
    
    DOMHTMLLinkElement *idAssignments = (DOMHTMLLinkElement*)[doc getElementById:@"idAssignments"];
    [idAssignments click];
}

//from assignments to assignments_projects
-(void)navi_to_assignments_projects_page:(WebView *)a_webview{
    [self appendToMyTextView:@"auto loading..." log_level:LOG_LEVEL_USer];
    DOMDocument *doc = [[self.webview1 mainFrame] DOMDocument];
    
    //find projects link
    DOMNodeList *links = [doc getElementsByTagName:@"a"];
    for(int i=0; i< [links length]; i++){
        DOMElement *el = (DOMElement*)[links item:i];
        NSString *href = [el getAttribute:@"href"];
        if([href containsString:@"assignments_projects"]){
            DOMHTMLLinkElement* assignments_projects = (DOMHTMLLinkElement*)el;
            [assignments_projects click];
            return;
        }
    }
}

//open assignments_tasks page & click "View scoping information" link
-(void)navi_to_download_file:(WebView *)a_webview{
    [self appendToMyTextView:[NSString stringWithFormat:@"%@ auto loading...", a_webview.identifier] log_level:LOG_LEVEL_ALL];
    DOMDocument *doc = [[a_webview mainFrame] DOMDocument];
    
    DOMNodeList *a_list = [doc getElementsByTagName:@"a"];
    for(int i=0; i< [a_list length]; i++){
        DOMHTMLLinkElement *link = (DOMHTMLLinkElement *)[a_list item:i];
        NSString *href = [link href];
        if([href containsString:@"assignments_project_info_scope"]){
            //open it
            [[a_webview mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:href]]];
            return;
        }
    }
}

//open Download Task Assets
-(void)navi_to_download_source:(WebView *)a_webview{
    [self appendToMyTextView:[NSString stringWithFormat:@"%@ auto loading...", a_webview.identifier] log_level:LOG_LEVEL_ALL];
    DOMDocument *doc = [[a_webview mainFrame] DOMDocument];
    
    DOMNodeList *checkBoxs = [doc getElementsByName:@"checkAllBox"];
    DOMHTMLInputElement *checkAllBox = (DOMHTMLInputElement *)[checkBoxs item:0];
    [checkAllBox click];
    
    DOMNodeList *forms = [doc getElementsByTagName:@"form"];
    DOMHTMLFormElement *form = (DOMHTMLFormElement *)[forms item:0];
    [form setTarget:@"_self"];
    [form submit];
}


- (void)get_download_files{
    [self.downloadTasks removeAllObjects];//clear
    
    DOMDocument *doc = [[self.webview1 mainFrame] DOMDocument];
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
                        NSString* projectID = [input getAttribute:@"value"];
                        /*
                        if([self check_file_exist:projectID]){
                            continue;
                        }
                        */
                        SDLDownloadFile *sdlfile = [SDLDownloadFile new];
                        sdlfile.url = [project_link href];
                        sdlfile.projectName = [project_link innerText];
                        sdlfile.projectID = projectID;
                        [self.downloadTasks addObject:sdlfile];
                    }
                }
                break;
            }
        }
    }
    
    self->download_files_total = [self.downloadTasks count];
    if(self->download_files_total > 0){
        //reset thread status
        self->threadStatus = [NSMutableDictionary dictionaryWithObjectsAndKeys: @NO, self.webview1.identifier,
                              @NO,self.webview2.identifier,
                              @NO,self.webview3.identifier, nil];
        
        //[NSThread detachNewThreadSelector:@selector(do_downloadTask_thread:) toTarget:self withObject:self.webview1.identifier];
        //[NSThread detachNewThreadSelector:@selector(do_downloadTask_thread:) toTarget:self withObject:self.webview2.identifier];
        //[NSThread detachNewThreadSelector:@selector(do_downloadTask_thread:) toTarget:self withObject:self.webview3.identifier];
        //[NSThread detachNewThreadSelector:@selector(do_downloadTask_thread:) toTarget:self withObject:self.webview4.identifier];
        
        [NSThread detachNewThreadSelector:@selector(do_download_by_mainwebview:) toTarget:self withObject:self.webview2.identifier];
    }
    else{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.downloadScopeMenu setEnabled:true];
        });
    }
}

- (BOOL)check_file_exist:(NSString *)projectID{
    NSString *destinationDir = [self get_file_save_dir];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    
    NSError *error;
    NSArray *fileList = [fileManager contentsOfDirectoryAtPath:destinationDir error:&error];
    if (error) {
        NSLog(@"getFileListInFolderWithPathFailed, errorInfo:%@",error);
    }
    for(NSString *file in fileList){
        NSRange range =[file rangeOfString:projectID];
        if(range.location == 0){
            //start with project ID, find it.
            return YES;
        }
    }
    return NO;
}

- (NSString*)get_file_save_dir{
    NSString *homeDirectory = NSHomeDirectory();
    NSString *destinationDir = [[homeDirectory stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"SDL"];
    
    NSFileManager* fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath:destinationDir]){
        NSError *errorDirectory = nil;
        [fileManager createDirectoryAtPath:destinationDir withIntermediateDirectories:YES attributes:nil error:&errorDirectory];
    }
    return destinationDir;
}


//download file
-(void)do_download_file:(WebView *)a_webview {
    DOMDocument *doc = [[a_webview mainFrame] DOMDocument];
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
    NSString *urlText = [NSString stringWithFormat:@"%@/ws-legacy/%@", self->domain, downlink];
    NSString *taskID = a_webview.identifier;
    
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDownloadTask *dataTask = [session downloadTaskWithRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:urlText]]
        completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {

            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse*)response;
            NSString *cd = [[httpResponse allHeaderFields] valueForKey:@"Content-Disposition"];
            NSString *filename = [[cd componentsSeparatedByString:@"''"] lastObject];
            SDLDownloadFile *task = (SDLDownloadFile*)[self.currentTasks objectForKey:taskID];
            filename = [filename stringByReplacingOccurrencesOfString:@"\"" withString:@""];
            filename = [NSString stringWithFormat:@"%@%@", task.projectID, filename];
            
            NSString *destinationDir = [self get_file_save_dir];
            NSString *destinationFileName = [destinationDir stringByAppendingPathComponent:filename];
            NSURL *toURL = [NSURL fileURLWithPath:destinationFileName];
        
            NSFileManager *fileManager = [NSFileManager defaultManager];
            [fileManager moveItemAtURL:location toURL:toURL error:&error];
            
            self.download_files_done++;
            [self download_Progress: (self.download_files_done+0.0)/self->download_files_total ];
            [self pageload_Progress:false key:taskID];
            [self appendToMyTextView: [NSString stringWithFormat:@"success download %@\n", filename] log_level:LOG_LEVEL_USer];

            
            //reset thread signal
            NSCondition *condition = (NSCondition*)[self->conditions objectForKey:taskID];
            [condition lock];
            self->threadStatus[taskID] = @NO;
            [condition signal];
            [condition unlock];
            
            NSLog(@"[thread %@] send signal because file downloaded succesfully", taskID);
            
            //download by main webview
            [NSThread detachNewThreadSelector:@selector(do_download_by_mainwebview:) toTarget:self withObject:taskID];
    }];
    [dataTask resume];
}

-(void)start_download_file:(NSString *)key task:(SDLDownloadFile *)sdlfile{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.currentTasks setObject:sdlfile forKey:key];
        [self appendToMyTextView: [NSString stringWithFormat:@"downloading %@", sdlfile.url] log_level:LOG_LEVEL_ALL];
        [self appendToMyTextView: [NSString stringWithFormat:@"start to download project by %@: %@ %@", key, sdlfile.projectID ,sdlfile.projectName] log_level:LOG_LEVEL_USer];
        [self pageload_Progress:true key:key];
        WebView *a_webview = (WebView*)[self->webviews objectForKey:key];
        [[a_webview mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:sdlfile.url]]];
    });
}


//download assets
-(void)do_download_assets:(WebView *)a_webview {
    DOMDocument *doc = [[a_webview mainFrame] DOMDocument];
    DOMHTMLInputElement *download_btn = (DOMHTMLInputElement *)[[doc getElementsByName:@"formAction"] item:0];
    
    //make a post request
    NSString *urlString = [NSString stringWithFormat:@"https://intuit.idiomworldserver.com/ws-legacy/%@", [download_btn value]];
    NSMutableURLRequest *request = [NSMutableURLRequest new];
    [request setURL:[NSURL URLWithString:urlString]];
    [request setHTTPMethod:@"POST"];

    NSString *contentType = [NSString stringWithFormat:@"text/html;charset=utf-8"];
    [request addValue:contentType forHTTPHeaderField: @"Content-Type"];
    
    //make body
    NSMutableData *postBody = [NSMutableData data];
    [postBody appendData:[[NSString stringWithFormat:@"source=1&methodUsed=POST&submittedBy=download&formAction=%@", [download_btn value]] dataUsingEncoding:NSUTF8StringEncoding]];
    DOMNodeList *cb_list = [doc getElementsByName:@"checkbox"];
    for(int i=0; i< [cb_list length]; i++){
        DOMHTMLInputElement *cb = (DOMHTMLInputElement*)[cb_list item:i];
        [postBody appendData:[[NSString stringWithFormat:@"&checkbox=%@", [cb value]] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    [request setHTTPBody:postBody];
    
    NSString *taskID = a_webview.identifier;
    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDownloadTask *dataTask = [session downloadTaskWithRequest:request
                                                        completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                                                            
                                                            SDLDownloadFile *task = (SDLDownloadFile*)[self.currentTasks objectForKey:taskID];
                                                            NSString *filename = [NSString stringWithFormat:@"%@.zip", task.projectID];
                                                            
                                                            NSString *destinationDir = [self get_file_save_dir];
                                                            NSString *destinationFileName = [destinationDir stringByAppendingPathComponent:filename];
                                                            NSURL *toURL = [NSURL fileURLWithPath:destinationFileName];
                                                            
                                                            NSFileManager *fileManager = [NSFileManager defaultManager];
                                                            [fileManager moveItemAtURL:location toURL:toURL error:&error];
                                                            
                                                            self.download_files_done++;
                                                            [self download_Progress: (self.download_files_done+0.0)/self->download_files_total ];
                                                            [self pageload_Progress:false key:taskID];
                                                            [self appendToMyTextView: [NSString stringWithFormat:@"success download %@\n", filename] log_level:LOG_LEVEL_USer];
                                                            
                                                            
                                                            //reset thread signal
                                                            NSCondition *condition = (NSCondition*)[self->conditions objectForKey:taskID];
                                                            [condition lock];
                                                            self->threadStatus[taskID] = @NO;
                                                            [condition signal];
                                                            [condition unlock];
                                                            
                                                            NSLog(@"[thread %@] send signal because file downloaded succesfully", taskID);
                                                            
                                                            //download by main webview
                                                            [NSThread detachNewThreadSelector:@selector(do_download_by_mainwebview:) toTarget:self withObject:taskID];
                                                        }];
    [dataTask resume];
}

-(IBAction)m_download_scope:(id)sender{
    //[self appendToMyTextView:@"download menu clic"];
    NSLog(@"download scope menu click");
    [self.downloadScopeMenu setEnabled:false];
    [self get_download_files];
}

-(IBAction)m_download_assets:(id)sender{
    NSLog(@"download assets menu click");
    [self.downloadAssetsMenu setEnabled:false];
    [self get_download_files];
}

-(IBAction)m_refresh:(id)sender{
    //[self appendToMyTextView:@"download menu clic"];
    NSLog(@"refresh menu click");
    [self.webview1 reload:sender];
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

- (void)pageload_Progress:(Boolean)b_start key:(NSString *)key{
    NSProgressIndicator *pi = (NSProgressIndicator *)[self->pagePIs objectForKey:key];
    dispatch_async(dispatch_get_main_queue(), ^{
        if(b_start){
            [pi startAnimation:self];
        }
        else{
            [pi stopAnimation:self];
        }
    });
}

- (void)download_Progress:(double)percent{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.download_PI setDoubleValue:percent];
        if(percent > 0.99){
            [self.downloadScopeMenu setEnabled:true];
        }
    });
}


@end
