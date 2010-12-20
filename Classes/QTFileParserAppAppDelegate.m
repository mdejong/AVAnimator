//
//  QTFileParserAppAppDelegate.m
//  QTFileParserApp
//
//  Created by Moses DeJong on 12/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "QTFileParserAppAppDelegate.h"
#import "QTFileParserAppViewController.h"

#import "AVAnimatorViewController.h"

#import "MovieControlsViewController.h"

#import "AVAppResourceLoader.h"

@implementation QTFileParserAppAppDelegate

@synthesize window;
@synthesize viewController;
@synthesize animatorViewController;
@synthesize movieControlsViewController;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  // Override point for customization after app launch    
  [window addSubview:viewController.view];
  [window makeKeyAndVisible];
  
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
  
	if (self.animatorViewController != nil) {
		[self stopAnimator];
  }
  
	self.animatorViewController = nil;
}

// Invoked when the Done button in the movie controls is pressed.
// This action will stop playback and halt any looping operation.
// This action will inform the animator that it should be done
// animating, then the animator will kick off a notification
// indicating that the animation is done.

- (void)movieControlsDoneNotification:(NSNotification*)notification {
	NSLog( @"movieControlsDoneNotification" );
  
	NSAssert(![animatorViewController isInitializing], @"animatorViewController isInitializing");
  
	[animatorViewController doneAnimating];
}

- (void)movieControlsPauseNotification:(NSNotification*)notification {
	NSLog( @"movieControlsPauseNotification" );
  
	NSAssert(![animatorViewController isInitializing], @"animatorViewController isInitializing");
  
	[animatorViewController pause];
}

- (void)movieControlsPlayNotification:(NSNotification*)notification {
	NSLog( @"movieControlsPlayNotification" );
  
	NSAssert(![animatorViewController isInitializing], @"animatorViewController isInitializing");
  
	[animatorViewController unpause];
}

// Notification indicates that all animations in a loop are now finished

- (void)animationDoneNotification:(NSNotification*)notification {
	NSLog( @"animationDoneNotification" );
  
	[self stopAnimator];
}

// Invoked when the animation is ready to begin, meaning all
// resources have been initialized.

- (void)animationPreparedNotification:(NSNotification*)notification {
	NSLog( @"animationPreparedNotification" );
  
	[movieControlsViewController enableUserInteraction];
  
	[animatorViewController startAnimating];
}

// Invoked when an animation starts, note that this method
// can be invoked multiple times for an animation that loops.

- (void)animationDidStartNotification:(NSNotification*)notification {
	NSLog( @"animationDidStartNotification" );
}

// Invoked when an animation ends, note that this method
// can be invoked multiple times for an animation that loops.

- (void)animationDidStopNotification:(NSNotification*)notification {
	NSLog( @"animationDidStopNotification" );	
}

- (void) loadDemoArchive
{
	// Init animator data
  
	NSString *resourceName = @"QuickTimeLogo.mov";
  
  if (0) {
    resourceName = @"Sweep30FPS_ANI16BPP.mov";
  }
  
	AVAppResourceLoader *resLoader = [[AVAppResourceLoader alloc] init];
  [resLoader autorelease];
	animatorViewController.resourceLoader = resLoader;
  
	resLoader.movieFilename = resourceName;

  
  //	animatorViewController.animationOrientation = UIImageOrientationLeft; // Rotate 90 deg CCW
  
	animatorViewController.animationOrientation = UIImageOrientationUp;
	animatorViewController.viewFrame = CGRectMake(0, 0, 480, 320);
  
	//  animatorViewController.animationFrameDuration = AVAnimator15FPS;
  animatorViewController.animationFrameDuration = AVAnimator30FPS;
  //animatorViewController.animationFrameDuration = 1.0 / 90;
  
  //	animatorViewController.animationRepeatCount = 100;
	animatorViewController.animationRepeatCount = 20;
  
  //	animatorViewController.animationRepeatCount = 1000;
}

- (void) startAnimator
{
	[viewController.view removeFromSuperview];
  
	AVAnimatorViewController *animatorObj = [[AVAnimatorViewController alloc] init];
	self.animatorViewController = animatorObj;
	[animatorObj release];
  
	[self loadDemoArchive];
	//	[self loadSweepArchive];
	//	[self loadVertigoArchive];

	// Create Movie Controls and make the view in the AVAnimatorViewController
	// the managed view of the Movie Controls controller.
  
	MovieControlsViewController *movieControlsObj = [[MovieControlsViewController alloc] init];
	self.movieControlsViewController = movieControlsObj;
	[movieControlsObj release];
  
//  movieControlsViewController.overView = viewController.view;
  
	movieControlsViewController.overView = animatorViewController.view;
  
	[movieControlsViewController addNavigationControlerAsSubviewOf:window];
  
	// Put movie controls away (this needs to happen when the
	// loading is done)
  
	[movieControlsViewController hideControls];
  
	// Invoke movieControlsDoneNotification via the Done button
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(movieControlsDoneNotification:) 
                                               name:MovieControlsDoneNotification 
                                             object:movieControlsViewController];	
  
	// Invoke pause or play action from movie controls
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(movieControlsPauseNotification:) 
                                               name:MovieControlsPauseNotification 
                                             object:movieControlsViewController];	
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(movieControlsPlayNotification:) 
                                               name:MovieControlsPlayNotification 
                                             object:movieControlsViewController];
  
	// Register callbacks to be invoked when the animator changes from
	// states between start/stop/done. The start/stop notification
	// is done at the start and end of each loop. When all loops are
	// finished the done notification is sent.
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animationPreparedNotification:) 
                                               name:AVAnimatorPreparedToAnimateNotification 
                                             object:animatorViewController];
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animationDidStartNotification:) 
                                               name:AVAnimatorDidStartNotification 
                                             object:animatorViewController];	
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animationDidStopNotification:) 
                                               name:AVAnimatorDidStopNotification 
                                             object:animatorViewController];
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animationDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:animatorViewController];
  
	// Kick off loading operation and disable user touch events until
	// finished loading.
  
	[movieControlsViewController disableUserInteraction];

	[animatorViewController prepareToAnimate];
  
  [animatorViewController startAnimating];
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
	// Remove notifications from movie controls
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MovieControlsDoneNotification
                                                object:movieControlsViewController];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MovieControlsPauseNotification
                                                object:movieControlsViewController];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MovieControlsPlayNotification
                                                object:movieControlsViewController];	
  
	// Remove notifications from animator
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorPreparedToAnimateNotification
                                                object:animatorViewController];	
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorDidStartNotification
                                                object:animatorViewController];
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorDidStopNotification
                                                object:animatorViewController];
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorDoneNotification
                                                object:animatorViewController];
  
	// Remove MovieControls and contained views, if the animator was just stopped
	// because all the loops were played then stopAnimating is a no-op.
  
	[animatorViewController stopAnimating];		
  
  //	[animatorViewController.view removeFromSuperview];
	[movieControlsViewController removeNavigationControlerAsSubviewOf:window];	
  
	self.animatorViewController = nil;
	self.movieControlsViewController = nil;
  
	[window addSubview:viewController.view];
}

- (void)dealloc {
  [viewController release];
	[movieControlsViewController release];
  [animatorViewController release];
  [window release];
  [super dealloc];
}

@end


