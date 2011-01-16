//
//  QTFileParserAppAppDelegate.m
//  QTFileParserApp
//
//  Created by Moses DeJong on 12/17/10.
//
//  License terms defined in License.txt.

#import "QTFileParserAppAppDelegate.h"
#import "QTFileParserAppViewController.h"

#import "AVAnimatorView.h"

#import "MovieControlsViewController.h"

#import "MovieControlsAdaptor.h"

#import "AVAppResourceLoader.h"

#import "AVQTAnimationFrameDecoder.h"

#import "AVPNGFrameDecoder.h"

#import <QuartzCore/QuartzCore.h>

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
  
#if defined(REGRESSION_TESTS)
  // Execute regression tests when app is launched
  [RegressionTests testApp];
#else
  NSAssert(self.viewController, @"viewController is nil");
  [self.window addSubview:self.viewController.view];
  [self.window makeKeyAndVisible];
  
//  [self startAnimator];
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
  // Create Movie Controls and let it manage the AVAnimatorView
  
	self.movieControlsViewController = [MovieControlsViewController movieControlsViewController];
  
  // note that overView must be set before mainWindow is defined!
  
	self.movieControlsViewController.overView = self.animatorView;
  self.movieControlsViewController.mainWindow = self.window;
  
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

// This example is a portrait animation with a few frames of mostly black
// with white text. PNG images are read from the app resources and the
// decoded image data is stored in memory. This is useful for testing the max
// framerate possible on the device, since no read from disk or frame decode
// operation is done when switching animation frames. If the movieControls
// flag is TRUE then the animator is placed in a movie controls widget.

- (void) loadCachedCountPortraitPNGs:(float)frameDuration
                          upsideDown:(BOOL)upsideDown
                       movieControls:(BOOL)movieControls
{
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 320, 480);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  if (upsideDown == FALSE) {
    // This orientation means that the AVAnimatorView will have no transforms
    self.animatorView.animatorOrientation = UIImageOrientationUp;
  } else {
    // This orientation has a rotation transform applied, useful to test
    // that a transform does not slow down the max frame rate.
    self.animatorView.animatorOrientation = UIImageOrientationDown;
  }
  
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
//  self.animatorView.animatorFrameDuration = 1.0 / 90;
  
  // Default to 2 frames per second, so that we can see that each
  // frame paints correctly.
  
  if (frameDuration == -1.0) {
    frameDuration = 1.0 / 2.0;
  }
  self.animatorView.animatorFrameDuration = frameDuration;
  
//	self.animatorView.animatorRepeatCount = 1;
  self.animatorView.animatorRepeatCount = 100;
  
  // Add AVAnimatorView directly to main window, or use movie controls

  if (movieControls == FALSE) {
    [self.window addSubview:self.animatorView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(animatorDoneNotification:) 
                                                 name:AVAnimatorDoneNotification
                                               object:self.animatorView];  
    
    [self.animatorView startAnimator];
  } else {
    [self loadIntoMovieControls];
  }
}

// This example shows a landscape count animation, PNG images are
// read into cached mem and rendered without a read/decode step.

- (void) loadCachedCountLandscapePNGs:(float)frameDuration
                        movieControls:(BOOL)movieControls
{
  // Setup the AnimatorView in landscape mode so that it matches the
  // orientation of the MovieControls.
  CGRect landscapeFrame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:landscapeFrame];
  self.animatorView.animatorOrientation = UIImageOrientationLeft;
  
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
  //	self.animatorView.animatorFrameDuration = 1.0 / 90;  
  
  if (frameDuration == -1.0) {
    frameDuration = 1.0 / 2.0;
  }
  
  self.animatorView.animatorFrameDuration = frameDuration;
  
	self.animatorView.animatorRepeatCount = 100;

  // Add AVAnimatorView directly to main window, or use movie controls
  
  if (movieControls == FALSE) {
    [self.window addSubview:self.animatorView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(animatorDoneNotification:) 
                                                 name:AVAnimatorDoneNotification
                                               object:self.animatorView];  
    
    [self.animatorView startAnimator];
  } else {
    [self loadIntoMovieControls];
  }  
}

// This animation is a series of 30 PNGs in landscape mode.
// The image files are read into memory, but the decoded
// image data is not cached. There is no IO between frames
// but the images do need to be decoded into memory.
// This test basically checks how quickly the PNG decoding
// logic can run, it is typically around 15FPS on an
// iPhone 3G for a 480x320 image.

- (void) loadBounceLandscapePNGs:(float)frameDuration
                   movieControls:(BOOL)movieControls
{  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  self.animatorView.animatorOrientation = UIImageOrientationLeft;
  
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
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs cacheDecodedImages:FALSE];
	self.animatorView.frameDecoder = frameDecoder;
    
  if (frameDuration == -1.0) {
    frameDuration = AVAnimator15FPS;
  }  
  
	self.animatorView.animatorFrameDuration = frameDuration;
  
	self.animatorView.animatorRepeatCount = 100;
  
  // Add AVAnimatorView directly to main window, or use movie controls
  
  if (movieControls == FALSE) {
    [self.window addSubview:self.animatorView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(animatorDoneNotification:) 
                                                 name:AVAnimatorDoneNotification
                                               object:self.animatorView];  
    
    [self.animatorView startAnimator];
  } else {
    [self loadIntoMovieControls];
  }  
  
}

// The same Bounce animation loaded above, except these frames are
// read from a MOV file instead of PNGs. Reading deltas from
// a MOV file is significant more efficient than decoding the
// entire PNG for each frame. A 16 or 24 bpp decode of this 480x320
// movie will at about 30 FPS on a iPhone 3G with no problems.
// Decoding a 32bpp movie with a possible alpha channel is
// less efficient and will execute more slowly.

- (void) loadBounceLandscapeAnimation:(float)frameDuration
                                  bpp:(int)bpp
                        movieControls:(BOOL)movieControls
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
  
  if (frameDuration == -1.0) {
    frameDuration = AVAnimator30FPS;
  }  
  
	self.animatorView.animatorFrameDuration = frameDuration;
  
	self.animatorView.animatorRepeatCount = 100;
  
  // Add AVAnimatorView directly to main window, or use movie controls
  
  if (movieControls == FALSE) {
    [self.window addSubview:self.animatorView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(animatorDoneNotification:) 
                                                 name:AVAnimatorDoneNotification
                                               object:self.animatorView];  
    
    [self.animatorView startAnimator];
  } else {
    [self loadIntoMovieControls];
  }  
}

// This example shows alpha compositing, the ghost is in a movie
// with an alpha channel. The ghost is partially "see through"
// so the color in the background shows through and the ghost
// looks like a mix of white and the background color.
// Note that because a CoreAnimation color cycle is used, the
// FPS will show up as 60 FPS in Instruments as long as the
// color cycle animation is running.

- (void) loadAlphaGhostLandscapeAnimation:(float)frameDuration
{
  NSString *resourceName;
  resourceName = @"AlphaGhost.mov";
  
  // Animate color shift for window, background shows through the ghost.
  
  self.window.backgroundColor = [UIColor redColor];
  [UIView beginAnimations:nil context:NULL];
  [UIView setAnimationDuration:5.0];
  [UIView setAnimationRepeatCount:3.5];
  [UIView setAnimationRepeatAutoreverses:TRUE];
  self.window.backgroundColor = [UIColor blueColor];
  [UIView commitAnimations];
  
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
  
  // An alpha 480x320 animation seems to be able to hit about 15 to 20 FPS.
  // Not as good as 24bpp, but the alpha blending and premultiplicaiton
  // on each pixel are more costly in terms of CPU time.
  
  if (frameDuration == -1.0) {
    frameDuration = 1.0 / 2.0;
  }  
  
	self.animatorView.animatorFrameDuration = frameDuration;
  
	self.animatorView.animatorRepeatCount = 150;

  [self loadIntoMovieControls];
}

// This landscape animation shows an effect like the one seen
// in "The Matrix". The movie file is not very small (700K),
// but it compresses down to a reasonable 300K. This example
// shows how including a non-trivial movie could be significantly
// easier than developing the "matrix letters falling" logic in
// Objective-C code.

- (void) loadMatrixLettersLandscapeAnimation:(float)frameDuration
{
  NSString *resourceName;
  resourceName = @"Matrix_480_320_10FPS_16BPP.mov";
  
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
  
  // Movie is 10FPS  
  // This animation can run smoothly at 30 FPS on a iPhone 3G,
  // but this is about the limit of what the hardware can do.

  if (frameDuration == -1.0) {
    frameDuration = AVAnimator10FPS;
  }  
  
	self.animatorView.animatorFrameDuration = frameDuration;  
  
	self.animatorView.animatorRepeatCount = 100;
  
  [self.window addSubview:self.animatorView];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:self.animatorView];
  
  [self.animatorView startAnimator];
}

+ (void) rotateToLandscape:(UIView*)aView
{
	// Change the center of the nav view to be the center of the
	// window in portrait mode.
  
	UIView *viewToRotate = aView;
  
  float width = 480.0;
  float height = 320.0;
  
	float hw = width / 2.0;
	float hh = height / 2.0;
	
	float container_hw = height / 2.0;
	float container_hh = width / 2.0;
	
	float xoff = hw - container_hw;
	float yoff = hh - container_hh;	
  
	CGRect frame = CGRectMake(-xoff, -yoff, width, height);
	viewToRotate.frame = frame;
  
	float angle = M_PI / 2;  //rotate CCW 90°, or π/2 radians
  
	viewToRotate.layer.transform = CATransform3DMakeRotation(angle, 0, 0.0, 1.0);
}

// This example shows mixing of video content with a still image. The video is a screen capture
// showing an iPhone app running in the simulator. The screen cap video was created at a very
// small size, so it looks a little fuzzy, but this is just an example.
//
// LCD dimensions:
//
// 480x320
//
// Screen: 33,25
// WxH: 410,199

- (void) loadScreenCaptureAnimation:(float)frameDuration
{
  CGRect rect = CGRectMake(0, 0, 480, 320);
  UIView *view = [[[UIView alloc] initWithFrame:rect] autorelease];
  NSAssert(view, @"view is nil");
  
  NSBundle* appBundle = [NSBundle mainBundle];
  NSString* resPath = [appBundle pathForResource:@"LCD.jpg" ofType:nil];
  NSAssert(resPath, @"invalid resource");
  UIImage *image = [UIImage imageWithContentsOfFile:resPath];
  NSAssert(image, @"image is nil");
  
//  imageView.image = [[UIImageView alloc] initWithImage:image];
  UIImageView *imageView = [[[UIImageView alloc] initWithImage:image] autorelease];
  NSAssert(imageView, @"imageView is nil");
  
  //image.imageOrientation = UIImageOrientationLeft;
  // Rotate image view!
  [self.class rotateToLandscape:imageView];
  
  CGRect screenRect = CGRectMake(33, 25, 410, 199);
    
  if (0) {
    UIView *animatorView = [[[UIView alloc] initWithFrame:screenRect] autorelease];
    animatorView.backgroundColor = [UIColor blueColor];
    animatorView.clearsContextBeforeDrawing = TRUE;
    [imageView addSubview:animatorView];
  } else {
    NSString *resourceName = @"JigsawPuzzle_205_99_10FPS_16BPP.mov";
    
    AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:screenRect];
    
    // The image is rotated, so the movie shown over the image is not rotated.
    animatorView.animatorOrientation = UIImageOrientationUp;
    
    // Create loader that will read a movie file from app resources.
    
    AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
    resLoader.movieFilename = resourceName;
    animatorView.resourceLoader = resLoader;
    
    // Create decoder that will generate frames from Quicktime Animation encoded data
    
    AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
    animatorView.frameDecoder = frameDecoder;
    
    // Movie is 10FPS  
    // This animation can run smoothly at 30 FPS on a iPhone 3G,
    // but this is about the limit of what the hardware can do.
    
    if (frameDuration == -1.0) {
      frameDuration = AVAnimator10FPS;
    }  
    
    animatorView.animatorFrameDuration = frameDuration;  
    
    self.animatorView.animatorRepeatCount = 10;

    [imageView addSubview:animatorView];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(animatorDoneNotification:) 
                                                 name:AVAnimatorDoneNotification
                                               object:animatorView];
    
    [animatorView startAnimator];
    
    self.animatorView = (AVAnimatorView*) view; // phony toplevel, does not crash because it is just removed from parent
  }
  
  [view addSubview:imageView];
  [self.window addSubview:view];
}

// The sweep animation is a bit more computationally intensive, as it contains changes in each row
// in each frame. This example shows an animation that runs at 15FPS and it synced to an audio track.
// Because of the audio sync, this example only runs at 15FPS.

- (void) loadSweepAnimation:(float)frameDuration
                  withSound:(BOOL)withSound
{
  NSString *videoResourceName = @"Sweep15FPS_ANI.mov";
  
  NSString *audioResourceName = @"Sweep15FPS.m4a"; // AAC in a M4AF container
//  NSString *audioResourceName = @"Sweep15FPS.caf"; // AAC in a CAF container
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  self.animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = videoResourceName;
  if (withSound) {
    resLoader.audioFilename = audioResourceName;
  }
	self.animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	self.animatorView.frameDecoder = frameDecoder;
  
  // Movie runs only at 15FPS with sound.
  
  if (withSound) {
    self.animatorView.animatorFrameDuration = AVAnimator15FPS;
  } else {
    if (frameDuration == -1.0) {
      self.animatorView.animatorFrameDuration = AVAnimator15FPS;      
    }
  }
  
//	self.animatorView.animatorRepeatCount = 5;
	self.animatorView.animatorRepeatCount = 100;
  
  [self loadIntoMovieControls];
}

// Given an example index, load a specific example with
// an indicated FPS. The fps is -1 if not set, otherwise
// it is 10, 20, 30, or 60.

- (void) loadIndexedExample:(NSUInteger)index
                        fps:(NSInteger)fps
{
  // Cleanup after any previous example
  self.window.backgroundColor = nil;
  // Remove app view controller from main window
  NSAssert(self.viewController, @"viewController is nil");
	[self.viewController.view removeFromSuperview];
  // Spin even loop so that view controller is removed from window
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.2];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  // Make sure view was removed from main window
  NSArray *subviews = self.window.subviews;
  NSAssert(subviews, @"subviews is nil");
  int subviewCount = [subviews count];
  // If the num subviews if not zero, then this loadIndexedExample callback
  // might have been called by two different button callbacks in the XIB
  NSAssert(subviewCount == 0, @"expected no subviews inside main window");
  
  // Calc frame duration if fps is not -1
  
  float frameDuration = -1;
  if (fps == 10) {
    frameDuration = AVAnimator10FPS;
  } else if (fps == 15) {
    frameDuration = AVAnimator15FPS;
  } else if (fps == 24) {
    frameDuration = AVAnimator24FPS;
  } else if (fps == 30) {
    frameDuration = AVAnimator30FPS;
  } else if (fps == 60) {
    frameDuration = 1.0 / 60.0;
  }
  
  switch (index) {
    case 1: {
      [self loadCachedCountPortraitPNGs:frameDuration upsideDown:FALSE movieControls:FALSE];
      break;
    }
    case 2: {
      [self loadCachedCountPortraitPNGs:frameDuration upsideDown:TRUE movieControls:FALSE];
      break;
    }
    case 3: {
      [self loadCachedCountPortraitPNGs:frameDuration upsideDown:FALSE movieControls:TRUE];
      break;
    }
    case 4: {
      [self loadCachedCountLandscapePNGs:frameDuration movieControls:FALSE];
      break;
    }
    case 5: {
      [self loadCachedCountLandscapePNGs:frameDuration movieControls:TRUE];
      break;
    }
    case 6: {
      [self loadBounceLandscapePNGs:frameDuration movieControls:TRUE];
      break;
    }
    case 7: {
      [self loadBounceLandscapeAnimation:frameDuration bpp:16 movieControls:FALSE];
      break;
    }
    case 8: {
      [self loadBounceLandscapeAnimation:frameDuration bpp:16 movieControls:TRUE];
      break;
    }
    case 9: {
      [self loadBounceLandscapeAnimation:frameDuration bpp:24 movieControls:TRUE];
      break;
    }
    case 10: {
      [self loadBounceLandscapeAnimation:frameDuration bpp:32 movieControls:TRUE];
      break;
    }
    case 11: {
      [self loadAlphaGhostLandscapeAnimation:frameDuration];
      break;
    }
    case 12: {
      [self loadMatrixLettersLandscapeAnimation:frameDuration];
      break;
    }
    case 13: {
      [self loadScreenCaptureAnimation:frameDuration];
      break;
    }
    case 14: {
      [self loadSweepAnimation:frameDuration withSound:TRUE];
      break;
    }
    case 15: {
      [self loadSweepAnimation:frameDuration withSound:FALSE];
      break;
    }      
  }
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
  if (self.movieControlsAdaptor != nil) {
    [self.movieControlsAdaptor stopAnimator];
    self.movieControlsAdaptor = nil;
    self.movieControlsViewController.mainWindow = nil;
  }
  
  [self.animatorView removeFromSuperview];    
	self.animatorView = nil;
  
	self.movieControlsViewController = nil;
  
	[self.window addSubview:self.viewController.view];
}

@end


