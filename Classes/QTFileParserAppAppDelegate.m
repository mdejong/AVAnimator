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

#if defined(REGRESSION_TESTS)
#import "RegressionTests.h"
#endif

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
  
#if defined(REGRESSION_TESTS)
  // Execute regression tests when app is launched
  [RegressionTests testApp];
#else
  [self startAnimator];
#endif // REGRESSION_TESTS    

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

- (void) loadIntoMovieControls
{
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
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs cacheDecodedImages:TRUE];
	self.animatorView.frameDecoder = frameDecoder;
  
	//self.animatorView.animatorFrameDuration = 0.25;
	self.animatorView.animatorFrameDuration = 1.0 / 15;
  
	self.animatorView.animatorRepeatCount = 10;

  [self loadIntoMovieControls];
}

- (void) loadCachedCountPNGs
{
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 320, 480);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  self.animatorView.animatorOrientation = UIImageOrientationUp;
  
  // Create loader that will get a filename from an app resource.
  // This resource loader is phony, it becomes a no-op because
  // the AVPNGFrameDecoder ignores it.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"Counting01.png"; // Phony resource name, becomes no-op
	self.animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVPNGFrameDecoder arrayWithNumberedNames:@"Counting"
                                                  rangeStart:1
                                                    rangeEnd:8
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVPNGFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  // Decode all PNGs into UIImage objects and save in memory, this takes up a lot
  // of memory but it means that displaying a specific frame is fast because
  // no image decode needs to be done.
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs cacheDecodedImages:TRUE];
	self.animatorView.frameDecoder = frameDecoder;
  
//  self.animatorView.animatorFrameDuration = 2.0;
//  self.animatorView.animatorFrameDuration = 1.0 / 15;
//  self.animatorView.animatorFrameDuration = 1.0 / 30;
//	self.animatorView.animatorFrameDuration = 1.0 / 60;
  
  // Testing on iPhone 3g indicates that 60 FPS is the the upper limit.
  // This impl likely uses CGImage data cached in the video card.
  self.animatorView.animatorFrameDuration = 1.0 / 90;
  
//	self.animatorView.animatorRepeatCount = 1;
	self.animatorView.animatorRepeatCount = 400;
  
  [self.window addSubview:self.animatorView];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:self.animatorView];  
  
  [self.animatorView startAnimator];
}

- (void) loadCachedCountPNGsUpsidedown
{
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 320, 480);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  self.animatorView.animatorOrientation = UIImageOrientationDown;
  
  // Create loader that will get a filename from an app resource.
  // This resource loader is phony, it becomes a no-op because
  // the AVPNGFrameDecoder ignores it.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"Counting01.png"; // Phony resource name, becomes no-op
	self.animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVPNGFrameDecoder arrayWithNumberedNames:@"Counting"
                                                  rangeStart:1
                                                    rangeEnd:8
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVPNGFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  // Decode all PNGs into UIImage objects and save in memory, this takes up a lot
  // of memory but it means that displaying a specific frame is fast because
  // no image decode needs to be done.
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs cacheDecodedImages:TRUE];
	self.animatorView.frameDecoder = frameDecoder;
  
  //  self.animatorView.animatorFrameDuration = 2.0;
  //  self.animatorView.animatorFrameDuration = 1.0 / 15;
  //  self.animatorView.animatorFrameDuration = 1.0 / 30;
  //	self.animatorView.animatorFrameDuration = 1.0 / 60;
  
  // Passing view through one transformation matrix seems to have little
  // effect on FPS, seeing consistent 60 FPS with this example.
  self.animatorView.animatorFrameDuration = 1.0 / 90;
  
  //	self.animatorView.animatorRepeatCount = 1;
	self.animatorView.animatorRepeatCount = 400;
  
  [self.window addSubview:self.animatorView];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:self.animatorView];  
  
  [self.animatorView startAnimator];
}

- (void) loadCachedCountLandscape
{
  CGRect landscapeFrame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:landscapeFrame];
  
  // Create loader that will get a filename from an app resource.
  // This resource loader is phony, it becomes a no-op because
  // the AVPNGFrameDecoder ignores it.
  
  // FIXME: should be able to set loader to nil, or perhaps pass the loader to the render
  // so that the animator code need not know how these are structured.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
	self.animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVPNGFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVPNGFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  // Decode all PNGs into UIImage objects and save in memory, this takes up a lot
  // of memory but it means that displaying a specific frame is fast because
  // no image decode needs to be done.
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs cacheDecodedImages:TRUE];
	self.animatorView.frameDecoder = frameDecoder;
  
  // Using a rotation and putting it inside an opaque window seems to limit the FPS to about 40.
  // The image is already setup in landscape, so this is likely caused by the fact that the
  // animator view is inside another set of views.
  
//  self.animatorView.animatorFrameDuration = 2.0;
	self.animatorView.animatorFrameDuration = 1.0 / 90;
  
	self.animatorView.animatorRepeatCount = 1000;

  [self loadIntoMovieControls];
}

- (void) loadBounceLandscapeAnimation:(int)bpp
{
  NSString *resourceName;
  if (bpp == 16) {
  resourceName = @"Bounce_16BPP_15FPS.mov";
  } else if (bpp == 24) {
   resourceName = @"Bounce_24BPP_15FPS.mov";
  } else if (bpp == 32) {
  resourceName = @"Bounce_32BPP_15FPS.mov";
  } else {
    assert(0);
  }

  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  self.animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	self.animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	self.animatorView.frameDecoder = frameDecoder;
  
	//self.animatorView.animatorFrameDuration = 1.0;
	//self.animatorView.animatorFrameDuration = AVAnimator15FPS;
  //self.animatorView.animatorFrameDuration = AVAnimator30FPS;
  self.animatorView.animatorFrameDuration = 1.0 / 60;
  
	self.animatorView.animatorRepeatCount = 400;
  
  [self.window addSubview:self.animatorView];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:self.animatorView];
  
  [self.animatorView startAnimator];
}

- (void) loadDemoArchive
{
	// Init animator data
  
	NSString *resourceName = @"QuickTimeLogo.mov";
  
  if (1) {
    resourceName = @"Sweep30FPS_ANI16BPP.mov";
  }
  if (0) {
    resourceName = @"Bounce_16BPP_15FPS.mov";
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
	//self.animatorView.animatorFrameDuration = AVAnimator15FPS;
  //self.animatorView.animatorFrameDuration = AVAnimator30FPS;
  self.animatorView.animatorFrameDuration = 1.0 / 60;
  
  //	self.animatorView.animatorRepeatCount = 100;
	self.animatorView.animatorRepeatCount = 60;
  
  //	self.animatorView.animatorRepeatCount = 1000;
  
  [self loadIntoMovieControls];
  
  return;
}

- (void) startAnimator
{
	[self.viewController.view removeFromSuperview];
  
  //[self loadBouncePNGs];
  //[self loadCachedCountPNGs];
  //[self loadCachedCountPNGsUpsidedown];
  //[self loadCachedCountLandscape];
  // FIXME: add a test case for a 16bpp animation in a plain window, not in the controls! (to test FPS)
  
  // About 30 FPS possible when only a single animator view is in the main window.
  //[self loadBounceLandscapeAnimation:16];
  
  // 24bpp framebuffers are 2 times larger, about 17 FPS limit on 3g. memcpy() bounded
  [self loadBounceLandscapeAnimation:24];

  // 32bpp is about 15FPS. A little more time taken to premultiply ?? But, nothing
  // compared to the memcpy().
  //[self loadBounceLandscapeAnimation:32];
  
	//[self loadDemoArchive];
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
  if (self.movieControlsAdaptor == nil) {
    [self.animatorView removeFromSuperview];    
  } else {
    [self.movieControlsAdaptor stopAnimator];
    self.movieControlsAdaptor = nil;

    [self.movieControlsViewController removeNavigationControlerAsSubviewOf:self.window];	
  }
  
	self.animatorView = nil;
	self.movieControlsViewController = nil;
  
	[self.window addSubview:self.viewController.view];
}

@end


