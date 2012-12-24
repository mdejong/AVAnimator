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

#import "AVAnimatorLayer.h"

#import "AVAnimatorMedia.h"

#import "MovieControlsViewController.h"

#import "MovieControlsAdaptor.h"

#import "AVAppResourceLoader.h"

#import "AVImageFrameDecoder.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

#import "AV7zApng2MvidResourceLoader.h"

#import "AVAsset2MvidResourceLoader.h"

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
@synthesize plainView = m_plainView;
@synthesize animatorLayer = m_animatorLayer;

- (void)dealloc {
  self.window = nil;
  self.viewController = nil;
  self.movieControlsViewController = nil;
  self.animatorView = nil;
  self.movieControlsAdaptor = nil;
  self.plainView = nil;
  self.animatorLayer = nil;
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
  self.plainView = nil;
  self.animatorLayer = nil;
}

- (void) loadIntoMovieControls:(AVAnimatorMedia*)media inPortraitMode:(BOOL)inPortraitMode
{
  // Create Movie Controls and let it manage the AVAnimatorView
  
	self.movieControlsViewController = [MovieControlsViewController movieControlsViewController:self.animatorView];
  
  if (inPortraitMode) {
    // special portrait mode flag must be set before setting mainWindow
    self.movieControlsViewController.portraitMode = TRUE;
  }
  
  // A MovieControlsViewController can only be placed inside a toplevel window!
  // Unlike a normal controller, you can't invoke [window addSubview:movieControlsViewController.view]
  // to place a MovieControlsViewController in a window. Just set the mainWindow property instead.
  
  self.movieControlsViewController.mainWindow = self.window;
  
  self.movieControlsAdaptor = [MovieControlsAdaptor movieControlsAdaptor];
  self.movieControlsAdaptor.animatorView = self.animatorView;
  self.movieControlsAdaptor.movieControlsViewController = self.movieControlsViewController;

  // Media needs to be attached to the view after the view
  // has been added to the window system.
  
  [self.animatorView attachMedia:media];
  
  // This object needs to listen for the AVAnimatorDoneNotification to update the GUI
  // after movie loops are finished playing.
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:self.animatorView.media];  
  
  [self.movieControlsAdaptor startAnimator];
  
  return;  
}

- (void) loadIntoMovieControls:(AVAnimatorMedia*)media
{
  [self loadIntoMovieControls:media inPortraitMode:FALSE];
}

// Util method that loads the animatorView into the outermost window
// and starts off the animation cycle.

- (void) loadIntoWindow:(AVAnimatorMedia*)media
{
  [self.window addSubview:self.animatorView];

  // Media needs to be attached to the view after the view
  // has been added to the window system.
  
  [self.animatorView attachMedia:media];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:self.animatorView.media];  
  
  [self.animatorView.media startAnimator];  
}

// This generic loading util will setup a resource loader and configure a Media
// object to use the proper type of loader. A .mvid will be decompressed
// from a 7zip compressed archive.

- (void) genericResourceLoader:(NSString*)resourcePrefix
                         media:(AVAnimatorMedia*)media
{
  NSString *videoResourceArchiveName;
  NSString *videoResourceEntryName;
  NSString *videoResourceOutName;
  NSString *videoResourceOutPath;
  
  // Extract existing FILENAME.mvid from FILENAME.mvid.7z attached as app resource
  
  videoResourceArchiveName = [NSString stringWithFormat:@"%@.mvid.7z", resourcePrefix];
  videoResourceEntryName = [NSString stringWithFormat:@"%@.mvid", resourcePrefix];
  NSString *resourceTail = [resourcePrefix lastPathComponent];
  videoResourceOutName = [NSString stringWithFormat:@"%@.mvid", resourceTail];
  videoResourceOutPath = [AVFileUtil getTmpDirPath:videoResourceOutName];
  
  AV7zAppResourceLoader *resLoader = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader.archiveFilename = videoResourceArchiveName;
  resLoader.movieFilename = videoResourceEntryName;
  resLoader.outPath = videoResourceOutPath;
  
  media.resourceLoader = resLoader;
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  media.frameDecoder = frameDecoder;
  
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

  // Create Media object and link it to the animatorView
  
	AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will get a filename from an app resource.
  // This resource loader is phony, it becomes a no-op because
  // the AVImageFrameDecoder ignores it.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
	resLoader.movieFilename = @"Counting01.png"; // Phony resource name, becomes no-op  
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVImageFrameDecoder arrayWithNumberedNames:@"Counting"
                                                  rangeStart:1
                                                    rangeEnd:8
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVImageFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  // Decode all PNGs into UIImage objects and save in memory, this takes up a lot
  // of memory but it means that displaying a specific frame is fast because
  // no image decode needs to be done.
  
  AVImageFrameDecoder *frameDecoder = [AVImageFrameDecoder aVImageFrameDecoder:URLs cacheDecodedImages:TRUE];
	media.frameDecoder = frameDecoder;
  
//  media.animatorFrameDuration = 2.0;
//  media.animatorFrameDuration = 1.0 / 15;
  
  // Testing on iPhone 3g indicates that 60 FPS is the the upper limit.
  // This impl likely uses CGImage data cached in the video card.
  
  // Default to 2 frames per second, so that we can see that each
  // frame paints correctly.
  
  if (frameDuration == -1.0) {
    frameDuration = 1.0 / 2.0;
  }
  media.animatorFrameDuration = frameDuration;
  
//	media.animatorRepeatCount = 1;
  media.animatorRepeatCount = 100;
  
  // Add AVAnimatorView directly to main window, or use movie controls

  if (movieControls == FALSE) {
    [self loadIntoWindow:media];
  } else {
    [self loadIntoMovieControls:media inPortraitMode:TRUE];
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
  if (!movieControls) {
    self.animatorView.animatorOrientation = UIImageOrientationLeft;
  }
  
  // Create Media object and link it to the animatorView
  
	AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will get a filename from an app resource.
  // This resource loader is phony, it becomes a no-op because
  // the AVImageFrameDecoder ignores it.
  
  // FIXME: should be able to set loader to nil, or perhaps pass the loader to the render
  // so that the animator code need not know how these are structured.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVImageFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVImageFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  // Decode all PNGs into UIImage objects and save in memory, this takes up a lot
  // of memory but it means that displaying a specific frame is fast because
  // no image decode needs to be done.
  
  AVImageFrameDecoder *frameDecoder = [AVImageFrameDecoder aVImageFrameDecoder:URLs cacheDecodedImages:TRUE];
	media.frameDecoder = frameDecoder;
  
  // Using a rotation and putting it inside an opaque window seems to limit the FPS to about 40.
  // The image is already setup in landscape, so this is likely caused by the fact that the
  // animator view is inside another set of views.
  
  //  self.animatorView.animatorFrameDuration = 2.0;
  //	self.animatorView.animatorFrameDuration = 1.0 / 90;  
  
  if (frameDuration == -1.0) {
    frameDuration = 1.0 / 2.0;
  }
  
  media.animatorFrameDuration = frameDuration;
  
	media.animatorRepeatCount = 100;

  // Add AVAnimatorView directly to main window, or use movie controls
  
  if (movieControls == FALSE) {
    [self loadIntoWindow:media];
  } else {
    [self loadIntoMovieControls:media];
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
  if (!movieControls) {
    self.animatorView.animatorOrientation = UIImageOrientationLeft;
  }
  
  // Create Media object and link it to the animatorView
  
	AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will get a filename from an app resource.
  // This resource loader is phony, it becomes a no-op because
  // the AVImageFrameDecoder ignores it.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"BouncingBalls01.png"; // Phony resource name, becomes no-op
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVImageFrameDecoder arrayWithNumberedNames:@"BouncingBalls"
                                                  rangeStart:1
                                                    rangeEnd:30
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVImageFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVImageFrameDecoder *frameDecoder = [AVImageFrameDecoder aVImageFrameDecoder:URLs cacheDecodedImages:FALSE];
	media.frameDecoder = frameDecoder;
    
  if (frameDuration == -1.0) {
    frameDuration = AVAnimator15FPS;
  }  
  
	media.animatorFrameDuration = frameDuration;
  
	media.animatorRepeatCount = 100;
  
  // Add AVAnimatorView directly to main window, or use movie controls
  
  if (movieControls == FALSE) {
    [self loadIntoWindow:media];
  } else {
    [self loadIntoMovieControls:media];
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
  resourceName = @"Bounce_16BPP_15FPS";
  } else if (bpp == 24) {
   resourceName = @"Bounce_24BPP_15FPS";
  } else if (bpp == 32) {
  resourceName = @"Bounce_32BPP_15FPS";
  } else {
    assert(0);
  }
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  if (!movieControls) {
    self.animatorView.animatorOrientation = UIImageOrientationLeft;
  }  
  
  // Create Media object and link it to the animatorView
  
	AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  [self genericResourceLoader:resourceName media:media];
  
  if (frameDuration == -1.0) {
    frameDuration = AVAnimator30FPS;
  }  
  
	media.animatorFrameDuration = frameDuration;
  
	media.animatorRepeatCount = 100;
  
  // Add AVAnimatorView directly to main window, or use movie controls
  
  if (movieControls == FALSE) {
    [self loadIntoWindow:media];
  } else {
    [self loadIntoMovieControls:media];
  }  
}

// This example demonstrates alpha compositing using a movie of a ghost at
// 32BPP with an alpha channel. The ghost is partially "see through"
// so the color in the background shows through and the ghost
// looks like a mix of white and the background color.
// Note that because a CoreAnimation color cycle is used, the
// FPS will show up as 60 FPS in Instruments as long as the
// color cycle animation is running. Decoding the alpha ghost
// from a .mov file will max out at about 20 FPS on a 3g iPhone.
// The framerate is the same when decoding from a .mvid file because
// the bottleneck is in the time it takes to transfer the image data
// to the graphics card.

- (void) loadAlphaGhostLandscapeAnimation:(float)frameDuration
{  
  NSString *resPrefix = @"AlphaGhost";
  
  // FIXME: Create example without the background animation, because it makes
  // the FPS unusable as a debug tool.
  
  // Animate color shift for window, background shows through the ghost.
  
  if (0) {
  
  self.window.backgroundColor = [UIColor redColor];
  [UIView beginAnimations:nil context:NULL];
  [UIView setAnimationDuration:5.0];
  [UIView setAnimationRepeatCount:3.5];
  [UIView setAnimationRepeatAutoreverses:TRUE];
  self.window.backgroundColor = [UIColor blueColor];
  [UIView commitAnimations];
    
  }
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  
  // Create Media object and link it to the animatorView
  
	AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  [self genericResourceLoader:resPrefix media:media];

  // An alpha 480x320 animation seems to be able to hit about 15 to 20 FPS.
  // Not as good as 24bpp, but the alpha blending and premultiplicaiton
  // on each pixel are more costly in terms of CPU time.
  
  if (frameDuration == -1.0) {
    frameDuration = 1.0 / 2.0;
  }  
  
	media.animatorFrameDuration = frameDuration;
  
	media.animatorRepeatCount = 150;

  [self loadIntoMovieControls:media];
}

// Load alpha ghost animation from a compressed APNG file.

- (void) loadAPNGAlphaGhostLandscapeAnimation:(float)frameDuration
{
  // Animate color shift for window, background shows through the ghost.
  // Note that enabling this color shift makes the FPS output in the
  // CoreAnimation Instrument useless since it always shows 60 FPS.
  
  if (0) {
    
    self.window.backgroundColor = [UIColor redColor];
    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:5.0];
    [UIView setAnimationRepeatCount:3.5];
    [UIView setAnimationRepeatAutoreverses:TRUE];
    self.window.backgroundColor = [UIColor blueColor];
    [UIView commitAnimations];
    
  }
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  
  // Create Media object and link it to the animatorView
  
	AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];

  NSString *archiveFilename = @"AlphaGhost_opt_nc.apng.7z";
  NSString *entryFilename = @"AlphaGhost_opt_nc.apng";
  NSString *outFilename = @"AlphaGhost_opt_nc.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  NSLog(@"outPath = %@", outPath);
    
  AV7zApng2MvidResourceLoader *resLoader = [AV7zApng2MvidResourceLoader aV7zApng2MvidResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
   
  media.frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  // An alpha 480x320 animation seems to be able to hit about 15 to 20 FPS.
  // Not as good as 24bpp, but the alpha blending and premultiplicaiton
  // on each pixel are more costly in terms of CPU time.
  
  if (frameDuration == -1.0) {
    frameDuration = 1.0 / 2.0;
  }  
  
	media.animatorFrameDuration = frameDuration;
  
	media.animatorRepeatCount = 150;
  
  [self loadIntoMovieControls:media];
}

// AlphaGhost_opt_nc.apng.7z

// This landscape animation shows an effect like the one seen
// in "The Matrix". The movie file is not very small (700K),
// but it compresses down to a reasonable 300K. This example
// shows how including a non-trivial movie could be significantly
// easier than developing the "matrix letters falling" logic in
// Objective-C code.

- (void) loadMatrixLettersLandscapeAnimation:(float)frameDuration
{
  NSString *resourcePrefix;
  resourcePrefix = @"Matrix_480_320_10FPS_16BPP";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  
  // Create Media object and link it to the animatorView
  
	AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  [self genericResourceLoader:resourcePrefix media:media];
  
  // Movie is 10FPS  
  // This animation can run smoothly at 30 FPS on a iPhone 3G,
  // but this is about the limit of what the hardware can do.

  if (frameDuration == -1.0) {
    frameDuration = AVAnimator10FPS;
  }  
  
	media.animatorFrameDuration = frameDuration;  
  
	media.animatorRepeatCount = 100;
  
  [self loadIntoMovieControls:media];
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
  
  UIImageView *imageView = [[[UIImageView alloc] initWithImage:image] autorelease];
  NSAssert(imageView, @"imageView is nil");
  
  // Rotate image view!
  [self.class rotateToLandscape:imageView];
  
  CGRect screenRect = CGRectMake(33, 25, 410, 199);
    
  if (0) {
    UIView *animatorView = [[[UIView alloc] initWithFrame:screenRect] autorelease];
    animatorView.backgroundColor = [UIColor blueColor];
    animatorView.clearsContextBeforeDrawing = TRUE;
    [imageView addSubview:animatorView];
    [view addSubview:imageView];
    [self.window addSubview:view];
  } else {
    NSString *resourceName = @"JigsawPuzzle_205_99_10FPS_16BPP.mvid";
    
    AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:screenRect];
    
    // The image is rotated, so the movie shown over the image is not rotated.
    animatorView.animatorOrientation = UIImageOrientationUp;
    
    // Create Media object and link it to the animatorView
    
    AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
    
    // Create loader that will read a movie file from app resources.
    
    AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
    resLoader.movieFilename = resourceName;
    media.resourceLoader = resLoader;
    
    // Create decoder that will generate frames from input .mvid file stored
    // in an app resource file.
    
    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    media.frameDecoder = frameDecoder;
    
    // Movie is 10FPS  
    // This animation can run smoothly at 30 FPS on a iPhone 3G,
    // but this is about the limit of what the hardware can do.
    
    if (frameDuration == -1.0) {
      frameDuration = AVAnimator10FPS;
    }  
    
    media.animatorFrameDuration = frameDuration;  
    
    media.animatorRepeatCount = 10;
     
    [imageView addSubview:animatorView];
    
    [view addSubview:imageView];
    [self.window addSubview:view];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(animatorDoneNotification:) 
                                                 name:AVAnimatorDoneNotification
                                               object:animatorView.media];
    
    [animatorView attachMedia:media];
    
    [media startAnimator];
    
    self.plainView = view;
  }
  
}

// The sweep animation is a bit more computationally intensive, the delta in the image is limited to
// a vertical region that moves to the left and right. This example shows an animation that runs at 15FPS
// and it synced to an audio track. Because the damage region is small, this example can easily run at 60 FPS
// when decoding from a .mov file with the audio disabled.

- (void) loadSweepAnimation:(float)frameDuration
                  withSound:(BOOL)withSound
{
  NSString *videoResourceName = @"Sweep15FPS";
  
  NSString *audioResourceName = @"Sweep15FPS.m4a"; // AAC in a M4AF container
//  NSString *audioResourceName = @"Sweep15FPS.caf"; // AAC in a CAF container
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  [self genericResourceLoader:videoResourceName media:media];
  
  // Grab loader and add sound filename also
  
  AVAppResourceLoader *resLoader = (AVAppResourceLoader*) media.resourceLoader;
  
  if (withSound) {
    resLoader.audioFilename = audioResourceName;
  }
    
  // Movie runs only at 15FPS with sound.
  
  if (withSound) {
    media.animatorFrameDuration = AVAnimator15FPS;
  } else {
    if (frameDuration == -1.0) {
      media.animatorFrameDuration = AVAnimator15FPS;
    } else {
      media.animatorFrameDuration = frameDuration;
    }
  }
  
//	media.animatorRepeatCount = 5;
	media.animatorRepeatCount = 100;
  
  [self loadIntoMovieControls:media];
}

// The Gradient Color wheel is the worst possible 32BPP animation, every pixel changes on
// every frame, so all the frames are marked as keyframes.
// Even though there are only 10 frames in the video, this animation takes up a whopping
// 5 megs of space. Also, every pixel is partially transparent, so the conversion to premultiplied
// alpha takes a lot of CPU because it needs to be done for every pixel.
// This series of frames would be better encoded as a set of PNG files, because there are no common
// pixels so the delta would be the entire frame.
//
// Rendering from .mov will result in about 14 FPS for this worst case
// Rendering from .mvid achives an impressive 30 FPS via keyframe zero copy optimization.

- (void) loadGradientColorWheelAnimation:(float)frameDuration
{
  // The color wheel is partially transparent, so set a blue color on the window
  // to verify that some of the blue is showing through.
  
  self.window.backgroundColor = [UIColor blueColor];
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  self.animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader to read from project resources and render frames. This logic
  // loads a version 0 mvid file where all frames are keyframes. This type of input
  // is able to make better use of mmap to map a file into memory and then send
  // that memory to the video hardware.
  
  [self genericResourceLoader:@"GradientColorWheel_2FPS_32BPP_Keyframes" media:media];
  
  if (frameDuration != -1.0) {
    // Don't set a frame duration, use the 2.0 FPS encoded in the MOV file
    media.animatorFrameDuration = frameDuration;
  }
  
  //	media.animatorRepeatCount = 5;
	media.animatorRepeatCount = 100;
  
  [self loadIntoMovieControls:media];
}

// This example shows some of the more fancy things that one can do
// using Core Animation. The AVAnimatorLayer class links a media
// object to a CALayer which is then added to a view. The
// CALayer can then be animated using any of the standard
// Core Animation methods.

- (void) loadCoreAnimationGhostAnimation:(float)frameDuration
{
  // Create a plain UIView in portrait orientation and add a CALayer
  // in the center of this view.
  
  NSString *resPrefix = @"AlphaGhost";
  
  CGRect frame = CGRectMake(0, 0, 320, 480);
  UIView *mainView = [[[UIView alloc] initWithFrame:frame] autorelease];
  [self.window addSubview:mainView];
  
  mainView.backgroundColor = [UIColor grayColor];
  
  // Get the main CALayer in the UIView
  
  CALayer *mainLayer = mainView.layer;
  
  // Create a CoreAnimation sublayer that the media will render into
  
  CALayer *renderLayer = [[[CALayer alloc] init] autorelease];

  // By default, the backgroundColor for a CALayer is nil, so
  // no background is rendered before the image is painted.
  renderLayer.backgroundColor = [UIColor greenColor].CGColor;
  
  renderLayer.borderColor = [UIColor blackColor].CGColor;
  renderLayer.borderWidth = 1.0;
  // Round the corners of the layer and clip to this bound
  renderLayer.cornerRadius = 20.0;
  renderLayer.masksToBounds = YES;
  
  // Aspect fit landscape image into this portrait window
  
  CGRect rendererFrame = CGRectMake(0, 0, frame.size.height*2/3, frame.size.width*2/3);
  
  renderLayer.frame = rendererFrame;
  
  CGPoint point = CGPointMake(frame.size.width/2.0, frame.size.height/2.0);
  renderLayer.position = point;
  
  [mainLayer addSublayer:renderLayer];
  
  if (0) {
    // Test image
    UIImage *smiley = [UIImage imageNamed:@"smiley.png"];
    NSAssert(smiley, @"smiley");
    renderLayer.contents = (id) smiley.CGImage;
    return;
  }
  
  // Create AVAnimatorLayer and associate it with the
  // existing CALayer that will be rendered into.
  
  AVAnimatorLayer *aVAnimatorLayer = [AVAnimatorLayer aVAnimatorLayer:renderLayer];
    
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  [self genericResourceLoader:resPrefix media:media];
  
  if (frameDuration != -1.0) {
    media.animatorFrameDuration = frameDuration;
  }
  
  //	media.animatorRepeatCount = 5;
	media.animatorRepeatCount = 100;

  // Link media to render layer
  
  [aVAnimatorLayer attachMedia:media];
  
//  media.animatorRepeatCount = 1000;
  media.animatorRepeatCount = 10;

  // Setup callback that will be invoked when animation is done
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:media];  
  
  self.plainView = mainView;
  
  // A ref to the animator layer object needs to be held, not retained as
  // part of the CALayer hierarchy.

  self.animatorLayer = aVAnimatorLayer;
    
  [media startAnimator];
}

// H264 encoded superwalk animation decoded to .mvid and then
// rendered into a CALayer. An H264 is always opaque since
// an alpha channel is not supported.

- (void) loadH264SuperwalkAnimation:(float)frameDuration
{
  // Create a plain UIView in portrait orientation and add a CALayer
  // in the center of this view.
  
  NSString *resFilename = @"superwalk_h264.mov";
  NSString *tmpFilename = @"superwalk.mvid";
  
  CGRect frame = CGRectMake(0, 0, 320, 480);
  UIView *mainView = [[[UIView alloc] initWithFrame:frame] autorelease];
  [self.window addSubview:mainView];
  
  mainView.backgroundColor = [UIColor grayColor];
  
  // Get the main CALayer in the UIView
  
  CALayer *mainLayer = mainView.layer;
  
  // Create a CoreAnimation sublayer that the media will render into
  
  CALayer *renderLayer = [[[CALayer alloc] init] autorelease];
  
  // By default, the backgroundColor for a CALayer is nil, so
  // no background is rendered before the image is painted.
  renderLayer.backgroundColor = [UIColor greenColor].CGColor;
  
  renderLayer.borderColor = [UIColor blackColor].CGColor;
  renderLayer.borderWidth = 1.0;
  // Round the corners of the layer and clip to this bound
  renderLayer.cornerRadius = 20.0;
  renderLayer.masksToBounds = YES;
  
  // Aspect fit landscape image into this portrait window
  
  CGRect rendererFrame = CGRectMake(0, 0, frame.size.height*2/3, frame.size.width*2/3);
  
  renderLayer.frame = rendererFrame;
  
  CGPoint point = CGPointMake(frame.size.width/2.0, frame.size.height/2.0);
  renderLayer.position = point;
  
  [mainLayer addSublayer:renderLayer];
    
  // Create AVAnimatorLayer and associate it with the
  // existing CALayer that will be rendered into.
  
  AVAnimatorLayer *aVAnimatorLayer = [AVAnimatorLayer aVAnimatorLayer:renderLayer];
  
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will load .mvid from H264 .mov
  
  AVAsset2MvidResourceLoader *resLoader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];

  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  resLoader.movieFilename = resFilename;
  resLoader.outPath = tmpPath;
  
  media.resourceLoader = resLoader;
  
  media.frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  if (frameDuration != -1.0) {
    media.animatorFrameDuration = frameDuration;
  }
  
  //	media.animatorRepeatCount = 5;
	media.animatorRepeatCount = 100;
  
  // Link media to render layer
  
  [aVAnimatorLayer attachMedia:media];
  
  //  media.animatorRepeatCount = 1000;
  media.animatorRepeatCount = 10;
  
  // Setup callback that will be invoked when animation is done
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDoneNotification:) 
                                               name:AVAnimatorDoneNotification
                                             object:media];  
  
  self.plainView = mainView;
  
  // A ref to the animator layer object needs to be held, not retained as
  // part of the CALayer hierarchy.
  
  self.animatorLayer = aVAnimatorLayer;
  
  [media startAnimator];
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
    case 16: {
      [self loadGradientColorWheelAnimation:frameDuration];
      break;
    }
    case 17: {
      [self loadCoreAnimationGhostAnimation:frameDuration];
      break;
    }
    case 18: {
      [self loadAPNGAlphaGhostLandscapeAnimation:frameDuration];
      break;
    }
    case 19: {
      [self loadH264SuperwalkAnimation:frameDuration];
      break;
    }
  }
}

// Notification indicates that all animations in a loop are now finished

- (void)animatorDoneNotification:(NSNotification*)notification {
//	NSLog( @"animatorDoneNotification" );
  
  // Unlink all notifications
  
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
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

  [self.plainView removeFromSuperview];
  self.plainView = nil;
  self.animatorLayer = nil;
}

@end


