//
//  QTFileParserAppAppDelegate.m
//  QTFileParserApp
//
//  Created by Moses DeJong on 12/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "QTFileParserAppAppDelegate.h"
#import "QTFileParserAppViewController.h"

#import "AVAnimatorView.h"

#import "MovieControlsViewController.h"

#import "MovieControlsAdaptor.h"

#import "AVAppResourceLoader.h"

#import "AVQTAnimationFrameDecoder.h"

#import "AVPNGFrameDecoder.h"

@implementation QTFileParserAppAppDelegate

@synthesize window = m_window;
@synthesize viewController = m_viewController;
@synthesize animatorView = m_animatorView;
@synthesize movieControlsViewController = m_movieControlsViewController;
@synthesize movieControlsAdaptor = m_movieControlsAdaptor;

- (void)dealloc {
  self.window = nil;
  self.viewController = nil;
  self.movieControlsViewController = nil;
  self.animatorView = nil;
  self.movieControlsAdaptor = nil;
  [super dealloc];
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  // Override point for customization after app launch    
  [self.window addSubview:self.viewController.view];
  [self.window makeKeyAndVisible];
  
	[self startAnimator];
  
  return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
  /*
   Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
   Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
   */
}


- (void)applicationDidEnterBackground:(UIApplication *)application {    /*
                                                                         Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to
                                                                         restore your application to its current state in case it is terminated later. 
                                                                         If your application supports background execution, called instead of applicationWillTerminate: when the user quits.
                                                                         */
}


- (void)applicationWillEnterForeground:(UIApplication *)application {
  /*
   Called as part of  transition from the background to the inactive state: here you can undo many of the changes made on entering t
   he background.
   */
}


- (void)applicationDidBecomeActive:(UIApplication *)application {
  /*
   Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in 
   the background, optionally refresh the user interface.
   */
}

- (void)applicationWillTerminate:(UIApplication *)application {
	// Application shutting down, return to home screen
  
	if (self.movieControlsAdaptor != nil) {
		[self stopAnimator];
  }
  
	self.animatorView = nil;
}

- (void) loadBouncePNGs
{  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  self.animatorView.animatorOrientation = UIImageOrientationUp;
  
  // Create loader that will get a filename from an app resource.
  // This resource loader is phony, it becomes a no-op because
  // the AVPNGFrameDecoder ignores it.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"BouncingBalls01.png"; // Phony resource name, becomes no-op
	self.animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVPNGFrameDecoder arrayWithNumberedNames:@"BouncingBalls"
                                                            rangeStart:1
                                                              rangeEnd:30
                                                          suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVPNGFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs];
	self.animatorView.frameDecoder = frameDecoder;
  
	self.animatorView.animatorFrameDuration = 0.25;
  
	self.animatorView.animatorRepeatCount = 10;
}

- (void) loadDemoArchive
{
	// Init animator data
  
	NSString *resourceName = @"QuickTimeLogo.mov";
  
  if (1) {
    resourceName = @"Sweep30FPS_ANI16BPP.mov";
  }
  if (0) {
    resourceName = @"Bounce15FPS.mov";
  }
  if (0) {
    resourceName = @"Vertigo30FPS.mov";
  }
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  self.animatorView.animatorOrientation = UIImageOrientationUp;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	self.animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	self.animatorView.frameDecoder = frameDecoder;

	//self.animatorView.animatorFrameDuration = 1.0;
	self.animatorView.animatorFrameDuration = AVAnimator15FPS;
  //self.animatorView.animatorFrameDuration = AVAnimator30FPS;
  //self.animatorView.animatorFrameDuration = 1.0 / 30;
  
  //	self.animatorView.animatorRepeatCount = 100;
	self.animatorView.animatorRepeatCount = 60;
  
  //	self.animatorView.animatorRepeatCount = 1000;
  
  return;
}

- (void) startAnimator
{
	[self.viewController.view removeFromSuperview];
  
  //[self loadBouncePNGs];
	[self loadDemoArchive];

	// Create Movie Controls and manage AVAnimatorView inside it
  
	self.movieControlsViewController = [MovieControlsViewController movieControlsViewController];
  
	self.movieControlsViewController.overView = self.animatorView;
  
	[self.movieControlsViewController addNavigationControlerAsSubviewOf:self.window];
  
  self.movieControlsAdaptor = [MovieControlsAdaptor movieControlsAdaptor];
  self.movieControlsAdaptor.animatorView = self.animatorView;
  self.movieControlsAdaptor.movieControlsViewController = self.movieControlsViewController;
  
  // This object needs to listen for the AVAnimatorDoneNotification to update the GUI
  // after movie loops are finished playing.

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:self.animatorView];  

  [self.movieControlsAdaptor startAnimator];
  
  return;
}

// Notification indicates that all animations in a loop are now finished

- (void)animatorDoneNotification:(NSNotification*)notification {
	NSLog( @"animatorDoneNotification" );
  
  // Unlink the notification
  
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorDoneNotification
                                                object:self.animatorView];  
  
	[self stopAnimator];  
}

- (void) stopAnimator
{
  NSAssert(self.movieControlsAdaptor, @"movieControlsAdaptor is nil");
  
  [self.movieControlsAdaptor stopAnimator];
  self.movieControlsAdaptor = nil;

  //	[self.animatorView.view removeFromSuperview];
	[self.movieControlsViewController removeNavigationControlerAsSubviewOf:self.window];	
  
	self.animatorView = nil;
	self.movieControlsViewController = nil;
  
	[self.window addSubview:self.viewController.view];
}

@end


