//
//  MovieControlsViewController.m
//  MovieControlsDemo
//
//  Created by Moses DeJong on 4/8/09.
//
//  License terms defined in License.txt.

#import "MovieControlsViewController.h"

#import <MediaPlayer/MPVolumeView.h>

#import <QuartzCore/QuartzCore.h>

#import "AutoPropertyRelease.h"

//#define LOGGING

#define EVENT_DELTA_OFFSET (0.5)

@implementation MovieControlsViewController

@synthesize mainWindow = m_mainWindow;
@synthesize overlaySubview = m_overlaySubview;
@synthesize doneButton = m_doneButton;
@synthesize controlsSubview, controlsImageView, controlsBackgroundImage;
@synthesize volumeSubview, volumeView;
@synthesize playPauseButton;
@synthesize rewindButton = m_rewindButton;
@synthesize fastForwardButton = m_fastForwardButton;
@synthesize playImage, pauseImage;
@synthesize rewindImage = m_rewindImage;
@synthesize fastForwardImage = m_fastForwardImage;
@synthesize hideControlsTimer, hideControlsFromPlayTimer;
@synthesize showVolumeControls;
@synthesize portraitMode;

// static ctor
+ (MovieControlsViewController*) movieControlsViewController:(UIView*)overView
{
  MovieControlsViewController *obj = [[MovieControlsViewController alloc] init];
  NSAssert(overView, @"overView is nil");
  
#if __has_feature(objc_arc)
#else
  obj = [obj autorelease];
#endif // objc_arc
  
  obj.view = overView;
  return obj;
}

- (void) _releaseHideControlsTimer
{
#ifdef LOGGING
	NSLog(@"_releaseHideControlsTimer");
#endif

	if (self.hideControlsTimer != nil) {
		[self.hideControlsTimer invalidate];
  }
	
	self.hideControlsTimer = nil;
	
	if (self.hideControlsFromPlayTimer != nil) {
		[self.hideControlsFromPlayTimer invalidate];
  }
	
	self.hideControlsFromPlayTimer = nil;	
}

- (void) _requeueHideControlsTimer
{
#ifdef LOGGING
	NSLog(@"_requeueHideControlsTimer");
#endif

	[self _releaseHideControlsTimer];

	self.hideControlsTimer = [NSTimer timerWithTimeInterval: 5.0+3
													 target: self
												   selector: @selector(_hideControlsTimer:)
												   userInfo: NULL
													repeats: FALSE];

	[[NSRunLoop currentRunLoop] addTimer:hideControlsTimer forMode: NSDefaultRunLoopMode];	
}

- (void) _hideControlsTimer:(NSTimer*)timer
{
#ifdef LOGGING
	NSLog(@"_hideControlsTimer");
#endif

	[self hideControls];
}

- (void)dealloc {  
	[self _releaseHideControlsTimer];
	[self.playPauseButton removeTarget:self
                         action:@selector(pressPlayPause:)
               forControlEvents:UIControlEventTouchUpInside];
	[self.rewindButton removeTarget:self
                              action:@selector(pressRewind:)
                    forControlEvents:UIControlEventTouchUpInside];
	[self.fastForwardButton removeTarget:self
                           action:@selector(pressFastForward:)
                 forControlEvents:UIControlEventTouchUpInside];
  
#if __has_feature(objc_arc)
#else
  [AutoPropertyRelease releaseProperties:self thisClass:MovieControlsViewController.class];
  [super dealloc];
#endif // objc_arc
}

- (CGSize) _containerSize
{
  CGSize containerSize;
    
  CGRect mainScreenFrame = [UIScreen mainScreen].applicationFrame;
  
  if ( UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad ) {
    if (portraitMode) {
      containerSize = mainScreenFrame.size;
    } else {
      containerSize.width = mainScreenFrame.size.height;
      containerSize.height = mainScreenFrame.size.width;
    }
  } else if (mainScreenFrame.size.height == 568) {
      if (portraitMode) {
          containerSize.width = 320.0;
          containerSize.height = 568.0;
      } else {
          containerSize.width = 568.0;
          containerSize.height = 320.0;
      }
  } else {
      if (portraitMode) {
          containerSize.width = 320.0;
          containerSize.height = 480.0;
      } else {
          containerSize.width = 480.0;
          containerSize.height = 320.0;
      }
  }
  
  return containerSize;
}

- (void) _rotateToLandscape:(UIView*)aView
{
	// Change the center of the nav view to be the center of the
	// window in portrait mode.
  
	UIView *viewToRotate = aView;

  CGSize containerSize = [self _containerSize];
  
	float hw = containerSize.width / 2.0;
	float hh = containerSize.height / 2.0;
	
	float container_hw = containerSize.height / 2.0;
	float container_hh = containerSize.width / 2.0;
	
	float xoff = hw - container_hw;
	float yoff = hh - container_hh;	

	CGRect frame = CGRectMake(-xoff, -yoff, containerSize.width, containerSize.height);
	viewToRotate.frame = frame;
  
	float angle = M_PI / 2;  //rotate CCW 90°, or π/2 radians
  
	viewToRotate.layer.transform = CATransform3DMakeRotation(angle, 0, 0.0, 1.0);  
}

- (void) _rotateToPortrait:(UIView*)aView
{
	// Change the center of the nav view to be the center of the
	// window in portrait mode.
  
	UIView *viewToRotate = aView;

	viewToRotate.layer.transform = self->portraitTransform;
  
  NSAssert(CGRectGetWidth(self->portraitFrame) > 0, @"portraitFrame not set");
  viewToRotate.frame = self->portraitFrame;
}

// This method is invoked to load a new navigation bar
// that displays a Done button

- (void) _loadNavigationBar
{
  // FIXME: add property for self.navigationBar ?
  
  CGSize containerSize = [self _containerSize];
  
  CGRect frame = CGRectMake(0.0f, 0.0f, containerSize.width, 40.0f);
  UINavigationBar *navigationBar = [[UINavigationBar alloc] initWithFrame:frame];
  
#if __has_feature(objc_arc)
#else
  navigationBar = [navigationBar autorelease];
#endif // objc_arc

	navigationBar.barStyle = UIBarStyleBlackTranslucent;
  

	UIBarButtonItem *doneItemButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
																					target:self
																					action:@selector(pressDone:)];
#if __has_feature(objc_arc)
#else
  doneItemButton = [doneItemButton autorelease];
#endif // objc_arc
  
  UINavigationItem *navigationItem = [[UINavigationItem alloc] initWithTitle:@""];
#if __has_feature(objc_arc)
#else
  navigationItem = [navigationItem autorelease];
#endif // objc_arc

  [navigationBar pushNavigationItem:navigationItem animated:FALSE];
  
  navigationItem.leftBarButtonItem = doneItemButton;
  
  [self.overlaySubview addSubview:navigationBar];
}

- (void) setMainWindow:(UIWindow*)mainWindow
{
  if (mainWindow == nil) {
    // Done showing movie controls and animator
    
    if (self.mainWindow == nil) {
      return;
    }

    if (self->controlsVisable) {
      [self hideControls];
    }    
    
    [self.view removeFromSuperview];
    
    [self _releaseHideControlsTimer];
    
    // Note that we don't retain a ref to mainWindow
    
    self->m_mainWindow = nil;
    
    return;
  }
  
  self->m_mainWindow = mainWindow;

  NSAssert(self.mainWindow != nil, @"self.mainWindow not set");
  
  // Add the overView to the main view controlled by the
  // movie controls widget, and then add the movie
  // controls view to the main window.
  
  NSArray *subviews = [self.mainWindow subviews];
  NSAssert(subviews != nil, @"subviews is nil");
  int subviewCount = (int) [subviews count];
  NSAssert(subviewCount == 0, @"mainWindow must contain no subviews");
      
  // force loading of the view controller and its contained views
  
	UIView *selfView = self.view;
	NSAssert(selfView, @"self.view");
  
  [self loadViewImpl];
  
  [self.mainWindow addSubview:selfView];
  
  // main view needs to be in portrait mode when added to main window
  
  self->portraitFrame = self.view.frame;
  self->portraitTransform = self.view.layer.transform;

  if (!portraitMode) {
    [self _rotateToLandscape:selfView];
  }
  
  // Hide controls by default
  
  self->controlsVisable = FALSE;
  
  [self.overlaySubview removeFromSuperview];
}

- (void) disableUserInteraction
{
  self.view.userInteractionEnabled = FALSE;
}

- (void) enableUserInteraction
{
  self.view.userInteractionEnabled = TRUE;
}

// Load buttons in the controls view

- (void)_loadControlsButtons
{
	// Load button image resources

	NSString *imageFilename;
	NSString *resPath;

	imageFilename = @"play.png";
	resPath = [[NSBundle mainBundle] pathForResource:imageFilename ofType:nil];
	NSAssert(resPath, @"play.png resource not found");

	self.playImage = [UIImage imageWithContentsOfFile:resPath];

	imageFilename = @"pause.png";
	resPath = [[NSBundle mainBundle] pathForResource:imageFilename ofType:nil];
	NSAssert(resPath, @"pause.png resource not found");

	self.pauseImage = [UIImage imageWithContentsOfFile:resPath];

	imageFilename = @"prevtrack.png";
	resPath = [[NSBundle mainBundle] pathForResource:imageFilename ofType:nil];
	NSAssert(resPath, @"prevtrack.png resource not found");

  // Not clear what to do about the system alpha image that the buttons go on
  
	self.rewindImage = [UIImage imageWithContentsOfFile:resPath];  

  imageFilename = @"nexttrack.png";
	resPath = [[NSBundle mainBundle] pathForResource:imageFilename ofType:nil];
	NSAssert(resPath, @"nexttrack.png resource not found");
  
	self.fastForwardImage = [UIImage imageWithContentsOfFile:resPath];
  
	// Define size of button in terms of image, it is critical
	// that the size be odd for this image to avoid scaling issues.

	int width = pauseImage.size.width + 40 + 5;
	int height = pauseImage.size.height + 30 + 5;

	CGRect frame = CGRectMake(0, 0, width, height);

	// Create custom button and set the "normal" image

	self.playPauseButton = [UIButton buttonWithType:UIButtonTypeCustom];

	playPauseButton.frame = frame;

	[playPauseButton setImage:pauseImage forState:UIControlStateNormal];

	if (FALSE) {
		playPauseButton.backgroundColor = [UIColor redColor];
	}

	// Bind button press action to callback

	[playPauseButton addTarget:self
						action:@selector(pressPlayPause:)
			  forControlEvents:UIControlEventTouchUpInside];

	playPauseButton.enabled = TRUE;
	playPauseButton.userInteractionEnabled = TRUE;
	playPauseButton.showsTouchWhenHighlighted = TRUE;

	// Set the location of the center of the button

	int offsetYCenterline = 6;

	CGPoint center = playPauseButton.center;
	center.x = CGRectGetWidth(self.controlsImageView.frame) / 2;
	center.y = CGRectGetHeight(self.controlsImageView.frame) / 2;
	center.y -= (playImage.size.height / 2);
	center.y -= offsetYCenterline;
	playPauseButton.center = center;	

	[controlsImageView addSubview:playPauseButton];

	// Create custom button for the rewind function
  
	self.rewindButton = [UIButton buttonWithType:UIButtonTypeCustom];
  
	self.rewindButton.frame = frame;
  
	[self.rewindButton setImage:self.rewindImage forState:UIControlStateNormal];
  
	if (FALSE) {
		self.rewindButton.backgroundColor = [UIColor redColor];
	}
  
	center.x = CGRectGetWidth(self.controlsImageView.frame) / 2;
	center.y = CGRectGetHeight(self.controlsImageView.frame) / 2;
	center.y -= (self.rewindImage.size.height / 2);
	center.y -= offsetYCenterline;
  center.y -= 2;
  center.x -= 83;
	self.rewindButton.center = center;	
  
	[controlsImageView addSubview:self.rewindButton];

	// Bind button press action to callback
  
	[self.rewindButton addTarget:self
                      action:@selector(pressRewind:)
            forControlEvents:UIControlEventTouchUpInside];
  
	self.rewindButton.enabled = TRUE;
	self.rewindButton.userInteractionEnabled = TRUE;
	self.rewindButton.showsTouchWhenHighlighted = TRUE;

	// Create custom button for the fast forward function
  
	self.fastForwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
  
	self.fastForwardButton.frame = frame;
  
	[self.fastForwardButton setImage:self.fastForwardImage forState:UIControlStateNormal];
  
	if (FALSE) {
		self.fastForwardButton.backgroundColor = [UIColor redColor];
	}
  
	center.x = CGRectGetWidth(self.controlsImageView.frame) / 2;
	center.y = CGRectGetHeight(self.controlsImageView.frame) / 2;
	center.y -= (self.fastForwardImage.size.height / 2);
	center.y -= offsetYCenterline;
  center.y -= 2;
  center.x += 83;
	self.fastForwardButton.center = center;	
  
	[controlsImageView addSubview:self.fastForwardButton];
  
	// Bind button press action to callback
  
	[self.fastForwardButton addTarget:self
                        action:@selector(pressFastForward:)
              forControlEvents:UIControlEventTouchUpInside];
  
	self.fastForwardButton.enabled = TRUE;
	self.fastForwardButton.userInteractionEnabled = TRUE;
	self.fastForwardButton.showsTouchWhenHighlighted = TRUE;  
  
  // Need to add flags so that "rewind", "fastforward", and volume controls
  // are optional in the display! These can be BOOL flags that are set in the
  // object.
  
  return;
}

- (UIImage*) _loadResourceImage:(NSString*)resName
{
	NSString *resPath = [[NSBundle mainBundle] pathForResource:resName ofType:nil];
	
	if (resPath == nil) {
		NSString *msg = [NSString stringWithFormat:@"resource file %@ does not exist", resName];
		NSAssert(FALSE, msg);
	}
	
	UIImage *image = [UIImage imageWithContentsOfFile:resPath];
	return image;
}

// Load volume view in the controls view

- (void)_loadControlsVolumeView
{
	CGRect frame = CGRectMake(0, 0, 280, 33);

  UIView *volumeSubviewObj = [[UIView alloc] initWithFrame:frame];
  
#if __has_feature(objc_arc)
#else
  volumeSubviewObj = [volumeSubviewObj autorelease];
#endif // objc_arc
  
	self.volumeSubview = volumeSubviewObj;
  
	// Set the location of the center of the volume view widget

	int centerVolumeOffset = 27;

	CGPoint center;
	center.x = CGRectGetWidth(self.controlsImageView.frame) / 2;
	center.y = CGRectGetHeight(self.controlsImageView.frame) / 2;
	center.y += centerVolumeOffset;
	volumeSubview.center = center;

  MPVolumeView *volumeViewObj = [[MPVolumeView alloc] initWithFrame:volumeSubview.bounds];
  
#if __has_feature(objc_arc)
#else
  volumeViewObj = [volumeViewObj autorelease];
#endif // objc_arc
  
	self.volumeView = volumeViewObj;

	[volumeViewObj sizeToFit];

	[volumeSubview addSubview:volumeViewObj];

	[controlsImageView addSubview:volumeSubview];

	// Find UISlider inside the volume view and use slider images that
	// are taller. This make it significantly easier to actually change
	// the volume because you can hit above and below the slider.

	UISlider *volumeViewSlider = nil;

	for (UIView *view in [volumeView subviews]) {
		if ([[[view class] description] isEqualToString:@"MPVolumeSlider"]) {
			volumeViewSlider = (UISlider*) view;
		}
	}
	NSAssert(volumeViewSlider, @"volumeViewSlider");

	UIImage *leftSliderImage = [self _loadResourceImage:@"VolumeLeftTall.png"];
	UIImage *rightSliderImage = [self _loadResourceImage:@"VolumeRightTall.png"];

	UIImage *leftStretchImage = [leftSliderImage stretchableImageWithLeftCapWidth:4 topCapHeight:0];
	UIImage *rightStretchImage = [rightSliderImage stretchableImageWithLeftCapWidth:4 topCapHeight:0];

	[volumeViewSlider setMinimumTrackImage:leftStretchImage forState:UIControlStateNormal];
	[volumeViewSlider setMaximumTrackImage:rightStretchImage forState:UIControlStateNormal];
}

// Load a view that implements movie transport controls as assign to self.controlsSubview

- (void)_loadControlsView
{
	NSString *imageFilename = @"MovieTransportBackground.png";
	NSString *resPath = [[NSBundle mainBundle] pathForResource:imageFilename ofType:nil];
	NSAssert(resPath, @"MovieTransportBackground.png resource not found");
	self.controlsBackgroundImage = [UIImage imageWithContentsOfFile:resPath];

	int image_height = controlsBackgroundImage.size.height;
	int spacer = 19;
  
  CGSize containerSize = [self _containerSize];

	NSAssert(controlsBackgroundImage.size.width <= containerSize.height, @"invalid image width");

	CGRect frame = CGRectMake(0, 0, containerSize.height, image_height + spacer);

	UIView *controlsSubviewObj = [[UIView alloc] initWithFrame:frame];
#if __has_feature(objc_arc)
#else
  controlsSubviewObj = [controlsSubviewObj autorelease];
#endif // objc_arc
  
	self.controlsSubview = controlsSubviewObj;
  
  UIImageView *controlsImageViewObj = [[UIImageView alloc] initWithImage:controlsBackgroundImage];
#if __has_feature(objc_arc)
#else
  controlsImageViewObj = [controlsImageViewObj autorelease];
#endif // objc_arc
	self.controlsImageView = controlsImageViewObj;

	[self.controlsSubview addSubview:controlsImageViewObj];

	controlsImageView.userInteractionEnabled = TRUE;
	self.controlsSubview.userInteractionEnabled = TRUE;

	// Center the image view inside the parent window

	CGPoint center = self.controlsImageView.center;
	center.x = CGRectGetWidth(self.controlsSubview.frame) / 2;
	self.controlsImageView.center = center;

	[self _loadControlsButtons];
	[self _loadControlsVolumeView];

  // Set transparency properties for this subview

	self.controlsSubview.opaque = FALSE;
	self.controlsSubview.backgroundColor = [UIColor clearColor];
	self.controlsSubview.alpha = 1.0;
	self.controlsSubview.userInteractionEnabled = TRUE;  
  
	// Define a background color for debugging

	if (FALSE) {
		[self.controlsSubview setBackgroundColor:[UIColor greenColor]];
	}
}

// Adjust the Y offset for the controls window, this method is invoked
// when the height of the window changes, for example when rotated
// from portrait to landscape.

- (void)_layoutControlsView
{
  CGSize containerSize = [self _containerSize];

	CGRect controlsFrame = self.controlsSubview.frame;

	// X position (middle of frame)

	float controls_width = CGRectGetWidth(controlsFrame);

	float half_container_width = containerSize.width / 2;
	float half_controls_width = controls_width / 2;

	controlsFrame.origin.x = half_container_width - half_controls_width;

	// Y position

	float controls_height = CGRectGetHeight(controlsFrame);

	float y = containerSize.height - controls_height;

  // Move control up just a bit in portrait mode
  
  if (portraitMode) {
    y -= containerSize.height * 0.05;
  }
  
	controlsFrame.origin.y = y;

	self.controlsSubview.frame = controlsFrame;
}

// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  // Return YES for supported orientations
  return (interfaceOrientation == UIInterfaceOrientationPortrait);
  // return (interfaceOrientation == UIInterfaceOrientationLandscapeRight);
}

- (void)loadView {
  NSAssert(FALSE, @"loadView should not be invoked");
}

// This method is invoked when the movie controls view is connected to
// a main window.

- (void)loadViewImpl {
	CGRect frame = [UIScreen mainScreen].applicationFrame;

	// MovieControls defaults to full screen landscape mode. If the special portraitMode
  // flag is set before the window is set, then the controls are show in portrait mode.
  // This logic checks that the main view is the entire size of the screen.
  
  CGSize containerSize = [self _containerSize];
  
  if (portraitMode) {
    if (frame.size.width != containerSize.width || frame.size.height != containerSize.height) {
      NSAssert(FALSE, @"movie controls can only be displayed at full screen resolution");
    }    
  } else {
    if (frame.size.width != containerSize.height || frame.size.height != containerSize.width) {
      NSAssert(FALSE, @"movie controls can only be displayed at full screen resolution");
    }    
  }

	// Create controls overlay with landscape dimensions

	frame = CGRectMake(0, 0, containerSize.width, containerSize.height);

  // overlaySubview completely covers self.view and contains
  // all the movie control widgets.
  
  UIView *overlaySubviewObj = [[UIView alloc] initWithFrame:frame];
  
#if __has_feature(objc_arc)
#else
  overlaySubviewObj = [overlaySubviewObj autorelease];
#endif // objc_arc
  
  self.overlaySubview = overlaySubviewObj;
  
  [self.view addSubview:self.overlaySubview];
  
  [self _loadNavigationBar];

	[self _loadControlsView];

  [self.overlaySubview addSubview:self.controlsSubview];
  
	// Reset layout position for controls
	
	[self _layoutControlsView];

  // Set main view properties
  
	self.overlaySubview.opaque = FALSE;
	self.overlaySubview.backgroundColor = [UIColor clearColor];
	self.overlaySubview.userInteractionEnabled = TRUE;
  
	// Set initial state
	
	NSAssert(isPlaying == FALSE, @"isPlaying should be false");
	self->isPlaying = TRUE;
	self->isPaused = FALSE;

	[playPauseButton setImage:pauseImage forState:UIControlStateNormal];
  
	// Save initial event time, this logic ensures that a button
	// press will not be delivered until a little time has passed

	self->lastEventTime = CFAbsoluteTimeGetCurrent();
  
  [self.view addSubview:self.overlaySubview];

	return;	
}
 
// Invoked when the controls are hidden as a result of
// pressing the play button. The controls need to display
// on screen for just a moment before being hidden.

- (void) _scheuleHideControlsFromPlayTimer
{
#ifdef LOGGING
	NSLog(@"_scheuleHideControlsFromPlayTimer");
#endif

	if (hideControlsFromPlayTimer != nil) {
		[hideControlsFromPlayTimer invalidate];
  }

	self.hideControlsFromPlayTimer = [NSTimer timerWithTimeInterval: 0.25
															 target: self
														   selector: @selector(_hideControlsFromPlayTimer:)
														   userInfo: NULL
															repeats: FALSE];

	[[NSRunLoop currentRunLoop] addTimer:hideControlsFromPlayTimer forMode: NSDefaultRunLoopMode];	
}

// Invoked when the controls are hidden as a result of
// pressing the play button. The controls need to display
// on screen for just a moment before being hidden.

- (void) _hideControlsFromPlayTimer:(NSTimer*)timer
{
#ifdef LOGGING
	NSLog(@"_hideControlsFromPlayTimer");
#endif

	[self hideControls];
}

- (void) _pressPlayPauseImpl
{
#ifdef LOGGING
	NSLog(@"_pressPlayPauseImpl");
#endif  
  
  if (isPaused) {
    // When paused, switch to play state and put controls away.
    
    isPaused = FALSE;
    
		[playPauseButton setImage:pauseImage forState:UIControlStateNormal];
    
		[self _scheuleHideControlsFromPlayTimer];
		
		// Send notification to object(s) that regestered interest in play action
		
		[[NSNotificationCenter defaultCenter] postNotificationName:MovieControlsPlayNotification
                                                        object:self];
    
#ifdef LOGGING
    NSLog(@"sending MovieControlsPlayNotification");
#endif      
  } else {
    // Not paused, so it must be playing currently. Switch to the pause state.
    
    isPaused = TRUE;
    
		[playPauseButton setImage:playImage forState:UIControlStateNormal];
    
		// Send notification to object(s) that regestered interest in pause action
		
		[[NSNotificationCenter defaultCenter] postNotificationName:MovieControlsPauseNotification
                                                        object:self];
    
#ifdef LOGGING
    NSLog(@"sending MovieControlsPauseNotification");
#endif    
  }
  
	self->isPlaying = !isPlaying;
}

- (void) pressPlayPause:(id)sender
{
#ifdef LOGGING
	NSLog(@"pressPlayPause");
#endif

// FIXME: If there is a startup race condition, would this logic change the isPlaying
// state while the view is being loaded? We might need to ensure that the view is
// loaded before any events are processed to set the state of the object.
  
	// Allow 1 button press event per second. This logic
	// ignores a second button press in a row.

	CFAbsoluteTime offset = CFAbsoluteTimeGetCurrent() - lastEventTime;
	if (offset < EVENT_DELTA_OFFSET) {
#ifdef LOGGING
		NSLog(@"play/pause event too close to previous event");
#endif

		return;
	}
	self->lastEventTime = CFAbsoluteTimeGetCurrent();	

  [self _pressPlayPauseImpl];
}

- (void) pressDone:(id)sender
{
#ifdef LOGGING
	NSLog(@"pressDone");
#endif

	// Allow 1 Done button press event per second. This logic
	// ignores a second button press in a row.

	CFAbsoluteTime offset = CFAbsoluteTimeGetCurrent() - lastEventTime;
	if (offset < EVENT_DELTA_OFFSET) {
#ifdef LOGGING
		NSLog(@"done event too close to previous event");
#endif

		return;
	}
	self->lastEventTime = CFAbsoluteTimeGetCurrent();

	// Update image on done button and send notification

	self->isPlaying = FALSE;
  self->isPaused = FALSE;
	[playPauseButton setImage:playImage forState:UIControlStateNormal];

	// Send notification to object(s) that regestered interest in done action, note
	// that we don't send a notification for a switch from play to pause.

	[[NSNotificationCenter defaultCenter] postNotificationName:MovieControlsDoneNotification
														object:self];	
}

// FIXME: When press and hold the rewind or fast forward button, it becomes a seek
// ahead or back function. Perhaps "rewind" should be when pressed with no hold,
// while "seek backwards" could be the other one.

- (void) pressRewindOrFastForwardImpl:(BOOL)isRewind
{
#ifdef LOGGING
	NSLog(@"pressRewindOrFastForwardImpl %d", isRewind);
#endif  
  
	// Allow 1 button press event per second. This logic
	// ignores a second button press in a row.
  
	CFAbsoluteTime offset = CFAbsoluteTimeGetCurrent() - lastEventTime;
	if (offset < EVENT_DELTA_OFFSET) {
#ifdef LOGGING
		NSLog(@"rewind/ffwd event too close to previous event");
#endif
    
		return;
	}
	self->lastEventTime = CFAbsoluteTimeGetCurrent();
  
  if (isPaused) {
    [self _pressPlayPauseImpl];
  }
  
  // The rewind button sends out a notification that will restart the animator
  
  if (isRewind) {
    [[NSNotificationCenter defaultCenter] postNotificationName:MovieControlsRewindNotification
                                                        object:self];
  } else {
    [[NSNotificationCenter defaultCenter] postNotificationName:MovieControlsFastForwardNotification
                                                        object:self];
  }
    
  [self _scheuleHideControlsFromPlayTimer];
}

- (void) pressRewind:(id)sender;
{
  [self pressRewindOrFastForwardImpl:TRUE];
}

- (void) pressFastForward:(id)sender;
{
  [self pressRewindOrFastForwardImpl:FALSE];
}

// Find the UIView that contains this touch event, this logic
// looks up a UIView based on the X,Y location of the touch
// inside the parent object.

- (UIView*)_viewThatContainsTouch:(NSSet*)touches withEvent:(UIEvent*)event
{
	UITouch *touch = [touches anyObject];

    CGPoint location = [touch locationInView:self.view];

	// Lookup the view the event was over using hit
	// logic in MovieControlsView object. This is needed
	// because the subclass does special touch event processing.

	UIView *hitView = [self.view hitTest:location withEvent:event];

	return hitView;
}

- (void)touchesBegan:(NSSet *)touches 
		   withEvent:(UIEvent *)event
{
	UITouch *touch = [touches anyObject];
	NSUInteger tapCount = [touch tapCount];

#ifdef LOGGING
	NSLog(@"touchesBegan with tap count %d", tapCount);
#endif

	UIView *hitView = [self _viewThatContainsTouch:touches withEvent:event];

#ifdef LOGGING
	if (hitView == self.view) {
		NSLog(@"hit in self.view");
	} else if (hitView == self.overlaySubview) {
		NSLog(@"hit in overlaySubview");	
	} else if (hitView == self.controlsSubview) {
		NSLog(@"hit in controlsSubview");
	} else if (hitView == self.controlsImageView) {
		NSLog(@"hit in controlsImageView");
	} else if (hitView == self.volumeSubview) {
		NSLog(@"hit in volumeSubview");
	} else if (hitView == self.volumeView) {
		NSLog(@"hit in volumeView");
	} else if (hitView == self.playPauseButton) {
		NSLog(@"hit in playPauseButton");
	} else {
		NSLog(@"hit in unknown view");
	}
#endif

	if (!controlsVisable) {
		// When controls are hidden, a touch
		// anywhere on screen will bring up
		// the controls.

#ifdef LOGGING
		NSLog(@"controls not visible, allow any hit");
#endif
		touchBeganOutsideControls = TRUE;	
	} else {
		// When controls are visible, allow
		// hiding the controls only when the
		// touch begins outside the controls

		touchBeganOutsideControls = (hitView == self.view) || (hitView == self.overlaySubview);

		// It should not be possible for the idle
		// timer to fire in between a touch start
		// and touch end event.

		[self _releaseHideControlsTimer];
	}

	if (tapCount > 1) {
		// Ignore repeated touch events
		touchBeganOutsideControls = FALSE;
	}

	// Propagate event to next responder

	[self.nextResponder touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
	UITouch *touch = [touches anyObject];
	NSUInteger tapCount = [touch tapCount];

#ifdef LOGGING
	NSLog(@"touchesEnded with tap count %d", tapCount);
#else
	tapCount = tapCount; // avoid compiler warning 
#endif

	if (controlsVisable) {
		[self _requeueHideControlsTimer];
  }

	if (touchBeganOutsideControls) {
		UIView *hitView = [self _viewThatContainsTouch:touches withEvent:event];

    BOOL touchEndedOutsideControls = (hitView == self.view) || (hitView == self.overlaySubview);
    
		if ((!controlsVisable) || touchEndedOutsideControls) {
			// Invoke pressOutsideControls when hit begins and
			// ends outside the controls. Short circut the
			// case where the controls are currently hidden.

			[self pressOutsideControls:nil];
		}
	}

	// Propagate event to next responder

	[self.nextResponder touchesEnded:touches withEvent:event];
}

// This method is invoked by MovieControlsView when any
// button press event is detected. This event will reset
// the hide controls timer even if the event is handled
// by the button or the slider. There does not appear to
// be a way to manage event more intellegently.

- (void)touchesAnyEvent
{
#ifdef LOGGING
	NSLog(@"touchesAnyEvent");
#endif

	[self _requeueHideControlsTimer];

	return;
}

- (void) pressOutsideControls:(id)sender
{
	// Invoked when a touch event is found over the managed window.
	// If the window controls are visible, then hide them. If
	// the window controls are not visible, then show them.

#ifdef LOGGING
	NSLog(@"pressOutsideControls");
#endif
	
	if (controlsVisable) {
		[self hideControls];
	} else {
		[self showControls];		
	}
}

- (void) showControls
{
#ifdef LOGGING
	NSLog(@"showControls");
#endif

  if (self->controlsVisable == TRUE) {
    return;
  } else {
    self->controlsVisable = TRUE;
  }

	// Show controls by adding controls to the main window.

  NSArray *subviews = [self.mainWindow subviews];
  NSAssert([subviews count] == 1, @"mainWindow must contain 1 subviews");
  NSAssert([subviews objectAtIndex:0] == self.view, @"main view must be only subview of mainWindow");
    
  [self.view addSubview:self.overlaySubview];
   
	// Create idle timer, if nothing happends for
	// a few seconds, then hide the controls.

	[self _requeueHideControlsTimer];
}

- (void) hideControls
{
  if (self->controlsVisable == FALSE) {
    return;
  } else {
    self->controlsVisable = FALSE;
  }
  
  // Hide controls by removing nav controller, putting the
  // main view back in the main window, and hiding the controls
  // subview.
  
  NSArray *subviews = [self.mainWindow subviews];
  int subviewCount = (int) [subviews count];
  NSAssert(subviewCount == 1, @"mainWindow must contain 1 subviews");
  NSAssert([subviews objectAtIndex:0] == self.view, @"self.view must be only subview of mainWindow");
  
  [self.overlaySubview removeFromSuperview];
   
	[self _releaseHideControlsTimer];
}

- (void) setShowVolumeControls:(BOOL)state
{
  if (state == FALSE) {
    [self.volumeSubview removeFromSuperview];
  } else {
    [self.controlsImageView addSubview:self.volumeSubview];
  }
}

@end
