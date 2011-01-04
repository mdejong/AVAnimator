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
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  self.animatorView.animationOrientation = UIImageOrientationUp;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	self.animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	self.animatorView.frameDecoder = frameDecoder;

	self.animatorView.animationFrameDuration = 1.0;
	//self.animatorView.animationFrameDuration = AVAnimator15FPS;
  //self.animatorView.animationFrameDuration = AVAnimator30FPS;
  //self.animatorView.animationFrameDuration = 1.0 / 30;
  
  //	self.animatorView.animationRepeatCount = 100;
	self.animatorView.animationRepeatCount = 60;
  
  //	self.animatorView.animationRepeatCount = 1000;
  
  return;
}

- (void) startAnimator
{
	[self.viewController.view removeFromSuperview];
  
	[self loadDemoArchive];
	//	[self loadSweepArchive];
	//	[self loadVertigoArchive];

	// Create Movie Controls and make the view in the AVAnimatorViewController
	// the managed view of the Movie Controls controller.
  
	self.movieControlsViewController = [MovieControlsViewController movieControlsViewController];

//  movieControlsViewController.overView = viewController.view;
  
	self.movieControlsViewController.overView = self.animatorView;
  
	[self.movieControlsViewController addNavigationControlerAsSubviewOf:self.window];
  
  self.movieControlsAdaptor = [MovieControlsAdaptor movieControlsAdaptor];
  self.movieControlsAdaptor.animatorView = self.animatorView;
  self.movieControlsAdaptor.movieControlsViewController = self.movieControlsViewController;
  
  // This object needs to listen for the AVAnimatorDoneNotification to update the GUI
  // after movie loops are finished playing.

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animationDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:self.animatorView];  

  [self.movieControlsAdaptor startAnimating];
  
  return;
}

// Notification indicates that all animations in a loop are now finished

- (void)animationDoneNotification:(NSNotification*)notification {
	NSLog( @"animationDoneNotification" );
  
  // Unlink the notification
  
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorDoneNotification
                                                object:self.animatorView];  
  
	[self stopAnimator];  
}

- (void) testAnimator
{
  /*
	[viewController.view removeFromSuperview];
  
	[NSThread sleepForTimeInterval:0.5];
  
  // --------------------------------------------------------
	
	// Test 1: state ALLOCATED -> LOADED
  
	self.animatorViewController = [[AVAnimatorViewController alloc] init];
	[animatorViewController release];
  
	[self loadDemoArchive];
  
	assert(animatorViewController->state == ALLOCATED);
	
	// Show animator view, the first frame of the animation is displayed
  
	[window addSubview:animatorViewController.view];
  
	assert(animatorViewController->state == LOADED);
  
	[animatorViewController.view removeFromSuperview];
  
	self.animatorViewController = nil;
  
  // --------------------------------------------------------
  
	// Test 2: state ALLOCATED -> PREPPING -> READY
	// Note that the state can't go back to LOADED once it has reached
	// the READY state.
  
	self.animatorViewController = [[AVAnimatorViewController alloc] init];
	[animatorViewController release];
	
	[self loadDemoArchive];
  
	assert(animatorViewController->state == ALLOCATED);
  
	[animatorViewController prepareToAnimate];
  
	// state should be PREPPING after prepareToAnimate,
	// must not be LOADED!
  
	assert(animatorViewController->state == PREPPING);
  
	// Process events from the event loop until the
	// state of the animator has changed to READY.
  
	while (animatorViewController->state == PREPPING) {
		NSRunLoop *current = [NSRunLoop currentRunLoop];
		[current acceptInputForMode:NSDefaultRunLoopMode
                     beforeDate:[current limitDateForMode:NSDefaultRunLoopMode]];
	}
  
	// Now add the view, this should not change the state
	// from READY to LOADED.
  
	[window addSubview:animatorViewController.view];
  
	assert(animatorViewController->state == READY);
  
	[animatorViewController.view removeFromSuperview];
	
	self.animatorViewController = nil;	
  
  
  // --------------------------------------------------------
  
	// Test 3: state READY -> ANIMATING -> STOPPED
  
	self.animatorViewController = [[AVAnimatorViewController alloc] init];
	[animatorViewController release];
	
	[self loadDemoArchive];
  
	[animatorViewController prepareToAnimate];
  
	// state should be PREPPING after prepareToAnimate,
	// must not be LOADED!
  
	assert(animatorViewController->state == PREPPING);
	
	// Process events from the event loop until the
	// state of the animator has changed to READY.
	
	while (animatorViewController->state == PREPPING) {
		NSRunLoop *current = [NSRunLoop currentRunLoop];
		[current acceptInputForMode:NSDefaultRunLoopMode
                     beforeDate:[current limitDateForMode:NSDefaultRunLoopMode]];
	}
  
	[window addSubview:animatorViewController.view];
  
	assert(animatorViewController->state == READY);
  
	[animatorViewController startAnimating];
  
	assert(animatorViewController->state == ANIMATING);
  
	[animatorViewController stopAnimating];
  
	assert(animatorViewController->state == STOPPED);
  
	[animatorViewController.view removeFromSuperview];
	
	self.animatorViewController = nil;	
  
	
  
  // --------------------------------------------------------
  
	// Test 4: state PREPPING -> STOPPED
	// Invoking stopAnimating with pending prep events in queue
	// must cancel those callbacks and put the animator into
	// a state where it can be cleaned up safely.
  
	self.animatorViewController = [[AVAnimatorViewController alloc] init];
	[animatorViewController release];
  
	[self loadDemoArchive];
  
	[animatorViewController prepareToAnimate];
  
	assert(animatorViewController->state == PREPPING);
	assert(animatorViewController->animationPrepTimer != nil);
	assert(animatorViewController->animationReadyTimer != nil);
	
	// Note that we don't process event here before calling stopAnimating
  
	[animatorViewController stopAnimating];
  
	assert(animatorViewController->state == STOPPED);
	assert(animatorViewController->isReadyToAnimate == FALSE);
	assert(animatorViewController->animationPrepTimer == nil);
	assert(animatorViewController->animationReadyTimer == nil);
  
	// Now call startAnimating to check that prepareToAnimate will
	// be invoked because the animator has not been fully prepared.
  
	[animatorViewController startAnimating];
  
	assert(animatorViewController->state == PREPPING);
	assert(animatorViewController->isReadyToAnimate == FALSE);
	assert(animatorViewController->animationPrepTimer != nil);
	assert(animatorViewController->animationReadyTimer != nil);
	assert(animatorViewController->startAnimatingWhenReady == TRUE);
  
  //	[animatorViewController.view removeFromSuperview];
	
	[animatorViewController stopAnimating];
  
	self.animatorViewController = nil;
  
  
  
  // --------------------------------------------------------
	
	// Test 5: state PAUSED -> STOPPED
	
	self.animatorViewController = [[AVAnimatorViewController alloc] init];
	[animatorViewController release];
	
	[self loadDemoArchive];
  
	[animatorViewController startAnimating];
  
	[window addSubview:animatorViewController.view];
  
	// Process events from the event loop until the
	// state of the animator has started playing
  
	while (animatorViewController->state != ANIMATING) {
		NSRunLoop *current = [NSRunLoop currentRunLoop];
		[current acceptInputForMode:NSDefaultRunLoopMode
                     beforeDate:[current limitDateForMode:NSDefaultRunLoopMode]];
	}
  
	[NSThread sleepForTimeInterval:0.5];
  
	// Now pause the playback, should hear audio for a split second.
  
	[animatorViewController pause];
  
	assert(animatorViewController->state == PAUSED);
	assert(animatorViewController->animationDecodeTimer == nil);
	assert(animatorViewController->animationDisplayTimer == nil);
  
	// Invoke stopAnimating while in the PAUSED state
	
	[animatorViewController stopAnimating];
  
	assert(animatorViewController->state == STOPPED);
  
	// start playing again from the begining
	
	[animatorViewController startAnimating];
	assert(animatorViewController->state == ANIMATING);
	[animatorViewController pause];
	assert(animatorViewController->state == PAUSED);
	[animatorViewController unpause];
	assert(animatorViewController->state == ANIMATING);
  
	[animatorViewController stopAnimating];
	assert(animatorViewController->state == STOPPED);
  
	self.animatorViewController = nil;
  
  
	
	// Reset buttons and return from tests
  
	[window addSubview:viewController.view];
   
   */
}

- (void) stopAnimator
{
  NSAssert(self.movieControlsAdaptor, @"movieControlsAdaptor is nil");
  
  [self.movieControlsAdaptor stopAnimating];
  self.movieControlsAdaptor = nil;

  //	[self.animatorViewController.view removeFromSuperview];
	[self.movieControlsViewController removeNavigationControlerAsSubviewOf:self.window];	
  
	self.animatorView = nil;
	self.movieControlsViewController = nil;
  
	[self.window addSubview:self.viewController.view];
}

@end


