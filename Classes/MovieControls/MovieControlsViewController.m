//
//  MovieControlsViewController.m
//  MovieControlsDemo
//
//  Created by Moses DeJong on 4/8/09.
//  Copyright __MyCompanyName__ 2009. All rights reserved.
//

#import "MovieControlsViewController.h"

#import "MovieControlsView.h"

#import <MediaPlayer/MPVolumeView.h>

#import <QuartzCore/QuartzCore.h>

#define LOGGING

#define EVENT_DELTA_OFFSET (0.5)

@implementation MovieControlsViewController

@synthesize movieControlsView, overView;
@synthesize navController, doneButton;
@synthesize controlsSubview, controlsImageView, controlsBackgroundImage;
@synthesize volumeSubview, volumeView;
@synthesize playPauseButton;
@synthesize rewindButton = m_rewindButton;
@synthesize playImage, pauseImage;
@synthesize rewindImage = m_rewindImage;
@synthesize hideControlsTimer, hideControlsFromPlayTimer;

// static ctor
+ (MovieControlsViewController*) movieControlsViewController
{
  MovieControlsViewController *obj = [[MovieControlsViewController alloc] init];
  [obj autorelease];
  return obj;
}

- (void) _releaseHideControlsTimer
{
#ifdef LOGGING
	NSLog(@"_releaseHideControlsTimer");
#endif

	if (hideControlsTimer != nil)
		[hideControlsTimer invalidate];
	
	self.hideControlsTimer = nil;
	
	if (hideControlsFromPlayTimer != nil)
		[hideControlsFromPlayTimer invalidate];
	
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
	[movieControlsView release];
	[overView release];

	[navController release];
	[doneButton release];

	[controlsSubview release];
	[controlsImageView release];
	[controlsBackgroundImage release];
	[volumeSubview release];
	[volumeView release];

	[playPauseButton removeTarget:self
						action:@selector(pressPlayPause:)
			  forControlEvents:UIControlEventTouchUpInside];

	[playPauseButton release];
	self.rewindButton = nil;

	[playImage release];
	[pauseImage release];
  self.rewindImage = nil;

	[self _releaseHideControlsTimer];

    [super dealloc];
}

- (void) _rotateToLandscape
{
	// Change the center of the nav view to be the center of the
	// window in portrait mode.

	UIView *viewToRotate = navController.view;

	int hw = 480/2;
	int hh = 320/2;
	
	int container_hw = 320/2;
	int container_hh = 480/2;
	
	int xoff = hw - container_hw;
	int yoff = hh - container_hh;	

	CGRect frame = CGRectMake(-xoff, -yoff, 480, 320);
	viewToRotate.frame = frame;
 
	float angle = M_PI / 2;  //rotate CCW 90°, or π/2 radians

	viewToRotate.layer.transform = CATransform3DMakeRotation(angle, 0, 0.0, 1.0);
 }

// This method is invoked to load a new navigation controller
// in the movie controls window. The navigation controller
// just displays a done button.

- (void) _loadNavigationController
{
	// movie controls view contains a navigation bar with a "Done" button

	self.navController = [[UINavigationController alloc] initWithRootViewController:self];
	[navController release];

	[self _rotateToLandscape];

	navController.navigationBar.barStyle = UIBarStyleBlackTranslucent;

	UIBarButtonItem *doneItemButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
																					target:self
																					action:@selector(pressDone:)];
  [doneItemButton autorelease];

	self.navigationItem.leftBarButtonItem = doneItemButton;

	[self.view addSubview:navController.navigationBar];
}

- (void) addNavigationControlerAsSubviewOf:(UIWindow*)window
{
	// Force self.view to load

	UIView *v = self.view;
	NSAssert(v, @"self.view");

	// Load navController if needed, needs to be loaded after
	// self.view has been loaded.

	if (navController.view == nil) {
		[self _loadNavigationController];
  }

	[window addSubview:navController.view];
}

- (void) _removeContainedViews
{
	// The nav controller "contains" the views that it manages, but UIKit
	// needs to be eplicitly told that the managed subviews have been
	// removed from the view hierarchy before removing the nav view.
	// Otherwise, when these views think they are still in the view
	// heirarchy even after the view objects have been deallocated.

	[self.view removeFromSuperview];
}

- (void) removeNavigationControlerAsSubviewOf:(UIWindow*)window
{
	[self _removeContainedViews];

	NSAssert(navController.view.window == window, @"view not contained in window");
	[navController.view removeFromSuperview];
}

- (void) disableUserInteraction
{
	navController.view.userInteractionEnabled = FALSE;
}

- (void) enableUserInteraction
{
	navController.view.userInteractionEnabled = TRUE;
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
  
	self.rewindImage = [UIImage imageWithContentsOfFile:resPath];  
  
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

	self.volumeSubview = [[[UIView alloc] initWithFrame:frame] autorelease];

	// Set the location of the center of the volume view widget

	int centerVolumeOffset = 27;

	CGPoint center;
	center.x = CGRectGetWidth(self.controlsImageView.frame) / 2;
	center.y = CGRectGetHeight(self.controlsImageView.frame) / 2;
	center.y += centerVolumeOffset;
	volumeSubview.center = center;

	self.volumeView = [[[MPVolumeView alloc] initWithFrame:volumeSubview.bounds] autorelease];

	[volumeView sizeToFit];

	[volumeSubview addSubview:volumeView];

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

	NSAssert(controlsBackgroundImage.size.width <= 320, @"invalid image width");

	CGRect frame = CGRectMake(0, 0, 320, image_height + spacer);

	UIView *controlsSubviewObj = [[UIView alloc] initWithFrame:frame];
  [controlsSubviewObj autorelease];

	self.controlsImageView = [[[UIImageView alloc] initWithImage:controlsBackgroundImage] autorelease];

	self.controlsSubview = controlsSubviewObj;

	[controlsSubview addSubview:controlsImageView];

	controlsImageView.userInteractionEnabled = TRUE;
	controlsSubview.userInteractionEnabled = TRUE;

	// Center the image view inside the parent window

	CGPoint center = self.controlsImageView.center;
	center.x = CGRectGetWidth(self.controlsSubview.frame) / 2;
	self.controlsImageView.center = center;

	[self _loadControlsButtons];
	[self _loadControlsVolumeView];

	// Define a background color for debugging

	if (FALSE) {
		[controlsSubview setBackgroundColor:[UIColor greenColor]];
	}

	// Add the controls view as a child of the main view

	[self.view addSubview:controlsSubview];
}

// Adjust the Y offset for the controls window, this method is invoked
// when the height of the window changes, for example when rotated
// from portrait to landscape.

- (void)_layoutControlsView
{
	int container_height = 320;
	int container_width = 480;

	CGRect controlsFrame = self.controlsSubview.frame;

	// X position (middle of frame)

	int controls_width = CGRectGetWidth(controlsFrame);

	int half_container_width = container_width / 2;
	int half_controls_width = controls_width / 2;

	controlsFrame.origin.x = half_container_width - half_controls_width;

	// Y position

	int controls_height = CGRectGetHeight(controlsFrame);

	int y = container_height - controls_height;

	controlsFrame.origin.y = y;

	self.controlsSubview.frame = controlsFrame;
}

// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  // Return YES for supported orientations
  return (interfaceOrientation == UIInterfaceOrientationPortrait);
  // return (interfaceOrientation == UIInterfaceOrientationLandscapeRight);
}

// This method is invoked when the view for this view controller is allocated,
// it will create the navigation controller and its view which contain
// all the other views. This class uses no .nib file.

- (void)loadView {
	CGRect frame = [UIScreen mainScreen].applicationFrame;

	// MovieControls can only be displayed in landscape mode

	if (frame.size.width != 320 || frame.size.height != 480) {
		NSAssert(FALSE, @"movie controls can only be displayed at full screen resolution of 320x480");
	}

	// Create the main view in landscape orientation

	frame = CGRectMake(0, 0, 480, 320);

	self.movieControlsView = [[[MovieControlsView alloc] initWithFrame:frame] autorelease];
  NSAssert(self.movieControlsView, @"could not allocate MovieControlsView");

	movieControlsView.viewController = self;

	self.view = movieControlsView;

	// Verify that overView member was set by caller, this is the
	// view that will be displayed below the movie controls.

	NSAssert(overView, @"overView must be set");

    [self.view insertSubview:overView atIndex:0];
	overView.userInteractionEnabled = FALSE;

	// Set dimension for overView

	overView.frame = frame;

	// Create movie transport controls subview

	[self _loadControlsView];
	
	// Reset layout position for controls
	
	[self _layoutControlsView];
 
  // FIXME: does opaque need to be set here? Is this for the containing window, or is opaque on
  // the contained window?
	self.view.backgroundColor = [UIColor clearColor];
	self.view.opaque = FALSE;
	self.view.alpha = 1.0;
	self.view.userInteractionEnabled = TRUE;

	// Set initial state
	
	NSAssert(isPlaying == FALSE, @"isPlaying should be false");
	self->isPlaying = TRUE;
	self->isPaused = FALSE;

	[playPauseButton setImage:pauseImage forState:UIControlStateNormal];
  
	[self showControls];

	// Save initial event time, this logic ensures that a button
	// press will not be delivered until a little time has passed

	self->lastEventTime = CFAbsoluteTimeGetCurrent();

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

	if (hideControlsFromPlayTimer != nil)
		[hideControlsFromPlayTimer invalidate];

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
  if (isPaused) {
    // When paused, switch to play state and put controls away.
    
    isPaused = FALSE;
    
		[playPauseButton setImage:pauseImage forState:UIControlStateNormal];
    
		[self _scheuleHideControlsFromPlayTimer];
		
		// Send notification to object(s) that regestered interest in play action
		
		[[NSNotificationCenter defaultCenter] postNotificationName:MovieControlsPlayNotification
                                                        object:self];    
  } else {
    // Not paused, so it must be playing currently. Switch to the pause state.
    
    isPaused = TRUE;
    
		[playPauseButton setImage:playImage forState:UIControlStateNormal];
    
		// Send notification to object(s) that regestered interest in pause action
		
		[[NSNotificationCenter defaultCenter] postNotificationName:MovieControlsPauseNotification
                                                        object:self];    
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

- (void) pressRewind:(id)sender;
{
#ifdef LOGGING
	NSLog(@"pressRewind");
#endif  
  
	// Allow 1 Done button press event per second. This logic
	// ignores a second button press in a row.
  
	CFAbsoluteTime offset = CFAbsoluteTimeGetCurrent() - lastEventTime;
	if (offset < EVENT_DELTA_OFFSET) {
#ifdef LOGGING
		NSLog(@"rewind event too close to previous event");
#endif
    
		return;
	}
	self->lastEventTime = CFAbsoluteTimeGetCurrent();
  
  if (isPaused) {
    [self _pressPlayPauseImpl];
  }

  // The rewind button sends out a notification that will restart the animator
  
  [[NSNotificationCenter defaultCenter] postNotificationName:MovieControlsRewindNotification
                                                      object:self];
  
  [self _scheuleHideControlsFromPlayTimer];
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

	UIView *hitView = [movieControlsView hitTestSuper:location withEvent:event];

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
	} else if (hitView == overView) {
		NSLog(@"hit in overView");	
	} else if (hitView == controlsSubview) {
		NSLog(@"hit in controlsSubview");
	} else if (hitView == controlsImageView) {
		NSLog(@"hit in controlsImageView");
	} else if (hitView == volumeSubview) {
		NSLog(@"hit in volumeSubview");
	} else if (hitView == volumeView) {
		NSLog(@"hit in volumeView");
	} else if (hitView == playPauseButton) {
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
		touchBeganInSelfView = TRUE;	
	} else {
		// When controls are visible, allow
		// hiding the controls only when the
		// touch begins outside the controls

		touchBeganInSelfView = (hitView == self.view);

		// It should not be possible for the idle
		// timer to fire in between a touch start
		// and touch end event.

		[self _releaseHideControlsTimer];
	}

	if (tapCount > 1) {
		// Ignore repeated touch events
		touchBeganInSelfView = FALSE;
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

	if (controlsVisable)
		[self _requeueHideControlsTimer];

	if (touchBeganInSelfView) {
		UIView *hitView = [self _viewThatContainsTouch:touches withEvent:event];

		if ((!controlsVisable) || (hitView == self.view)) {
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

	self->controlsVisable = TRUE;

	// Show controls by making all the subviews
	// in the container visible

	for (UIView *subview in [self.view subviews]) {
		if (subview == overView) {
			// no-op
		} else {
			subview.hidden = FALSE;
		}
	}

	// Create idle timer, if nothing happends for
	// a few seconds the hide the controls.

	[self _requeueHideControlsTimer];
}

- (void) hideControls
{
	self->controlsVisable = FALSE;

	// Hide controls by making all the layers
	// except overView hidden.

// FIXME: If this timer for _hideControlsTimer fires before the view has been created for the first time,
// what would happen here? The access of self.view will create the view and load it, but is that what we want?
  
	for (UIView *subview in [self.view subviews]) {
		if (subview == overView) {
			// no-op
		} else {
			subview.hidden = TRUE;
		}
	}

	[self _releaseHideControlsTimer];
}

@end
