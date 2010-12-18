//
//  AVAnimatorViewController.m
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 3/18/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "AVAnimatorViewController.h"

#import <QuartzCore/QuartzCore.h>

#import <AVFoundation/AVAudioPlayer.h>

#import <AudioToolbox/AudioFile.h>
#import "AudioToolbox/AudioServices.h"

#import "CGFrameBuffer.h"

#import "EasyArchive.h"

#import "NSDataExtensions.h"

#import "FlatMovieFile.h"

#import "AVResourceLoader.h"

//#define DEBUG_OUTPUT

// util class AVAnimatorViewControllerAudioPlayerDelegate declaration

@interface AVAnimatorViewControllerAudioPlayerDelegate : NSObject <AVAudioPlayerDelegate> {	
@public
	AVAnimatorViewController *animator;
}

- (id) initWithAnimator:(AVAnimatorViewController*)inAnimator;

@end // class AVAnimatorViewControllerAudioPlayerDelegate declaration

@implementation AVAnimatorViewControllerAudioPlayerDelegate

- (id) initWithAnimator:(AVAnimatorViewController*)inAnimator {
	self = [super init];
	if (self == nil)
		return nil;
	// Note that we don't retain a ref here, since the AVAnimatorViewController is
	// the only object that can ref this object, holding a ref would create
	// a circular reference and the view would never be deallocated.
	self->animator = inAnimator;
	return self;
}

// Invoked when audio player was interrupted, for example by
// an incoming phone call.

- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player
{
	// FIXME: pass reason for stop (loop, interrupt)

	[animator pause];
}

- (void)audioPlayerEndInterruption:(AVAudioPlayer *)player
{
	// Resume playback of audio

// FIXME: Should we unpause right away or should we leave the player in the
// paused state and let the user start it again? Perhaps just make sure
// that it is paused and that the controls are visible.

//	[player play];

	[animator unpause];
}

- (void)audioPlayerDecodeErrorDidOccur:(AVAudioPlayer *)player error:(NSError *)error
{
	// The audio must not contain improperly formatted data
	assert(FALSE);
}

- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag
{
	// The audio must not contain improperly formatted data
	assert(flag);
}

@end // class AVAnimatorViewControllerAudioPlayerDelegate implementation


// class AVAnimatorViewController implementation

@implementation AVAnimatorViewController

@synthesize resourceLoader, animationArchiveURL, animationAudioURL;
@synthesize animationFrameDuration, animationNumFrames, animationRepeatCount;
@synthesize imageView, animationOrientation;
@synthesize avAudioPlayer;
@synthesize prevFrame, nextFrame, currentFrame;
@synthesize animationPrepTimer, animationReadyTimer;
@synthesize animationDecodeTimer, animationDisplayTimer;
@synthesize cgFrameBuffers;
@synthesize flatMovieFile;
@synthesize viewFrame;

// Note: there is no init method since this class makes use of the default
// init method in the superclass.

// Return the final path component for either file or URL strings.

- (NSString*) _getLastPathComponent:(NSString*)path
{
	// Find the last '/' in the string, then use everything after that as the entry name
	NSString *lastPath;
	NSRange lastSlash = [path rangeOfString:@"/" options:NSBackwardsSearch];
	NSRange restOfPathRange;
	restOfPathRange.location = lastSlash.location + 1;
	restOfPathRange.length = [path length] - restOfPathRange.location;
	lastPath = [path substringWithRange:restOfPathRange];
	return lastPath;
}

// Trim .bz2 off the end of the filename.

- (NSString*) _getFilenameWithoutExtension:(NSString*)filename extension:(NSString*)extension
{
	NSRange lastDot = [filename rangeOfString:extension options:NSBackwardsSearch];
	
	if (lastDot.location == NSNotFound) {
		return nil;
	} else {
		NSRange beforeDotRange;
		beforeDotRange.location = 0;
		beforeDotRange.length = lastDot.location;
		return [filename substringWithRange:beforeDotRange];
	}
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
  // Return YES for supported orientations
  return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

// Implement loadView to create a view hierarchy programmatically, without using a nib.

- (void)loadView {
	if (isViewFrameSet == FALSE) {
		self.viewFrame = [UIScreen mainScreen].applicationFrame;
  }

	self.view = [[[UIView alloc] initWithFrame:viewFrame] autorelease];

	BOOL isRotatedToLandscape = FALSE;
	size_t renderWidth, renderHeight;

	if (animationOrientation == UIImageOrientationUp) {
		isRotatedToLandscape = FALSE;
	} else if (animationOrientation == UIImageOrientationLeft) {
		// 90 deg CCW for Landscape Orientation
		isRotatedToLandscape = TRUE;
	} else if (animationOrientation == UIImageOrientationRight) {
		// 90 deg CW for Landscape Right Orientation
		isRotatedToLandscape = TRUE;
	} else {
		NSAssert(FALSE,@"Unsupported animationOrientation");
	}
	
	if (!isRotatedToLandscape) {
		// no-op
	} else  {
		if (animationOrientation == UIImageOrientationLeft)
			[self rotateToLandscape];
		else
			[self rotateToLandscapeRight];
	}

	if (isRotatedToLandscape) {
		renderWidth = viewFrame.size.height;
		renderHeight = viewFrame.size.width;
	} else {
		renderWidth = viewFrame.size.width;
		renderHeight = viewFrame.size.height;
	}

	//	renderWidth = applicationFrame.size.width;
	//	renderHeight = applicationFrame.size.height;

	CGSize rs;
	rs.width = renderWidth;
	rs.height = renderHeight;
	self->renderSize = rs;

	self.imageView = [[[UIImageView alloc] initWithFrame:self.view.frame] autorelease];

	// This view layer does no alpha blending
	
	imageView.opaque = TRUE;

	// User events to this layer are ignored

	imageView.userInteractionEnabled = FALSE;

	[imageView setBackgroundColor:[UIColor blackColor]];
	
	[self.view addSubview:imageView];

	NSAssert(resourceLoader, @"resourceLoader must be defined");
	NSAssert(animationArchiveURL == nil, @"animationArchiveURL must be nil");
	NSAssert(animationAudioURL == nil, @"animationAudioURL must be nil");

	NSAssert(animationFrameDuration != 0.0, @"animationFrameDuration was not defined");

	// Note that we don't load any data from the movie archive or from the
	// audio files at load time. Resource loading is done only as a result
	// of a call to prepareToAnimate. Only a state change of
	// ALLOCATED -> LOADED is possible here.

	if (state == ALLOCATED) {
		self->state = LOADED;
	}
}

- (void) _createAudioPlayer
{
	NSError *error;
	NSError **errorPtr = &error;
	AVAudioPlayer *avPlayer = nil;

	NSAssert(animationAudioURL, @"animationAudioURL not set");
	NSURL *audioURL = animationAudioURL;

	NSString *audioURLPath = [audioURL path];
	NSString *audioURLTail = [self _getLastPathComponent:audioURLPath];
	char *audioURLTailStr = (char*) [audioURLTail UTF8String];
	NSAssert(audioURLTailStr != NULL, @"audioURLTailStr is NULL");
	NSAssert(audioURLTail != nil, @"audioURLTail is nil");

	avPlayer = [AVAudioPlayer alloc];
	avPlayer = [avPlayer initWithContentsOfURL:audioURL error:errorPtr];
  [avPlayer autorelease];

	if (error.code == kAudioFileUnsupportedFileTypeError) {
		NSAssert(FALSE, @"unsupported audio file format");
	}

	NSAssert(avPlayer, @"AVAudioPlayer could not be allocated");

	self.avAudioPlayer = avPlayer;

	AVAnimatorViewControllerAudioPlayerDelegate *audioDelegate;

	audioDelegate = [[AVAnimatorViewControllerAudioPlayerDelegate alloc] initWithAnimator:self];

	// Note that in OS 3.0, the delegate does not seem to be retained though it
	// was retained in OS 2.0. Explicitly retain it as a separate ref. Save
	// the original delegate value and reset it before dropping the ref to the
	// audio player just to be safe.

	self->originalAudioDelegate = avAudioPlayer.delegate;
	avAudioPlayer.delegate = audioDelegate;
	self->retainedAudioDelegate = audioDelegate;

	NSLog(@"%@", [NSString stringWithFormat:@"default avPlayer volume was %f", avPlayer.volume]);

	// Get the audio player ready by pre-loading buffers from disk

	[avAudioPlayer prepareToPlay];
}

- (void) _allocFrameBuffers
{
	// create buffers used for loading image data

  if (self.cgFrameBuffers != nil) {
    // Already allocated the frame buffers
    return;
  }
  
	int renderWidth = self->renderSize.width;
	int renderHeight = self->renderSize.height;
  
  NSAssert(renderWidth > 0 && renderHeight > 0, @"renderWidth or renderHeight is zero");

	CGFrameBuffer *cgFrameBuffer1 = [[CGFrameBuffer alloc] initWithDimensions:renderWidth :renderHeight];
	CGFrameBuffer *cgFrameBuffer2 = [[CGFrameBuffer alloc] initWithDimensions:renderWidth :renderHeight];
	CGFrameBuffer *cgFrameBuffer3 = [[CGFrameBuffer alloc] initWithDimensions:renderWidth :renderHeight];

	self.cgFrameBuffers = [NSArray arrayWithObjects:cgFrameBuffer1, cgFrameBuffer2, cgFrameBuffer3, nil];

	[cgFrameBuffer1 release];
	[cgFrameBuffer2 release];
	[cgFrameBuffer3 release];

	/*
	 
	 CGFrameBuffer *cgFrameBuffer1 = [[CGFrameBuffer alloc] initWithDimensions:renderWidth :renderHeight];
	 CGFrameBuffer *cgFrameBuffer2 = [[CGFrameBuffer alloc] initWithDimensions:renderWidth :renderHeight];
	 
	 self.cgFrameBuffers = [NSArray arrayWithObjects:cgFrameBuffer1, cgFrameBuffer2, nil];
	 
	 [cgFrameBuffer1 release];
	 [cgFrameBuffer2 release];

	 */	
}

// This method is invoked in the prep state via a timer callback
// while the widget is preparing to animate. This method will
// load resources once we know the files exist in the tmp dir.

- (BOOL) _loadResources
{
	NSLog(@"Started _loadResources");

	BOOL isReady = [resourceLoader isReady];
  if (!isReady) {
    NSLog(@"Not Yet Ready in _loadResources");
    return FALSE;
  }

	NSLog(@"Ready _loadResources");

	NSArray *resourcePathsArr = [resourceLoader getResources];

	// First path is the movie file, second is the audio

	NSAssert([resourcePathsArr count] == 2, @"expected 2 resource paths");
	
	NSString *flatPath = [resourcePathsArr objectAtIndex:0];
	NSString *audioPath = [resourcePathsArr objectAtIndex:1];

	// Create the flat movie file object to read video frames from disk

	FlatMovieFile *flatMovieFileObj = [[FlatMovieFile alloc] init];
  [flatMovieFileObj autorelease];
	self.flatMovieFile = flatMovieFileObj;

	BOOL worked = [flatMovieFile openForReading:flatPath];
	NSAssert(worked, @"flat movie file openForReading failed");

	NSLog(@"%@", [NSString stringWithFormat:@"FlatMovieFile openForReading \"%@\"", [flatPath lastPathComponent]]);
  
	if (TRUE)
	{
		// Get RLE data for the initial keyframe
		
		BOOL changed = [flatMovieFile advanceToFrame:0];
		assert(changed);
		
		// Load initial keyframe data into image
		
		NSUInteger currentFrameRLEDataNumBytes = 0;
		char *currentFrameRLEData = [flatMovieFile currentFrameBytes:&currentFrameRLEDataNumBytes];
		assert(currentFrameRLEData);

		NSAssert(cgFrameBuffers != nil, @"cgFrameBuffers is nil");
		CGFrameBuffer *cgFrameBuffer1 = [cgFrameBuffers objectAtIndex:0];
		assert(!cgFrameBuffer1.isLockedByDataProvider);
		
		[cgFrameBuffer1 runLengthDecodeBytes:currentFrameRLEData
							 numEncodedBytes:currentFrameRLEDataNumBytes];
		
		CGImageRef imgRef = [cgFrameBuffer1 createCGImageRef];
		NSAssert(imgRef, @"CGImageRef returned by createCGImageRef is NULL");
		
		UIImage *keyframeImage = [UIImage imageWithCGImage:imgRef];
		
		CGImageRelease(imgRef);
				
		imageView.image = keyframeImage;
	}

	// Create AVAudioPlayer that plays audio from the file on disk

	NSURL *url = [NSURL fileURLWithPath:audioPath];

 	self.animationAudioURL = url;

	return TRUE;
}

- (void) _cleanupReadyToAnimate
{
	[animationReadyTimer invalidate];
	self.animationReadyTimer = nil;
  
  NSLog(@"AVAnimatorViewController: _cleanupReadyToAnimate");
}

// When a movie archive needs to be decompressed and turned into a flat
// movie file, this method is invoked to do the long render operation.

- (void) _loadResourcesCallback:(NSTimer *)timer
{
	NSAssert(state == PREPPING, @"expected to be in PREPPING state");
  
  // Ensure that the view is loaded at this point (by invoking view getter)
  
  UIView *thisView = self.view;
  NSAssert(thisView != nil, @"view is nil");

  // The resources have to be fully loaded before this method can be
  // executed.

	[self _allocFrameBuffers];
  
	// Prepare movie and audio, if needed

	BOOL ready = [self _loadResources];
  if (!ready) {
    // Note that the prep timer is not invalidated in this case
    return;
  }

	// Finish up init state
  
	[animationPrepTimer invalidate];
	self.animationPrepTimer = nil;  
  
	// Init audio data
	
	[self _createAudioPlayer];
	
	self.currentFrame = 0;

	self->animationNumFrames = flatMovieFile.numFrames;

	assert(animationNumFrames > 0);

	self->state = READY;
	self->isReadyToAnimate = TRUE;

  // Send out a notification that indicates that the movie is now fully loaded
  // and is ready to play.
  
  [self _cleanupReadyToAnimate];
  
  // Send notification to object(s) that regestered interest in prepared action
  
  [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorPreparedToAnimateNotification
                                                      object:self];
  
  if (startAnimatingWhenReady) {
    [self startAnimating];
  }  
  
	return;
}

// Create an array of file/resource names with the given filename prefix,
// the file names will have an integer appended in the range indicated
// by the rangeStart and rangeEnd arguments. The suffixFormat argument
// is a format string like "%02i.png", it must format an integer value
// into a string that is appended to the file/resource string.
//
// For example: [createNumberedNames:@"Image" rangeStart:1 rangeEnd:3 rangeFormat:@"%02i.png"]
//
// returns: {"Image01.png", "Image02.png", "Image03.png"}

+ (NSArray*) arrayWithNumberedNames:(NSString*)filenamePrefix
						 rangeStart:(NSInteger)rangeStart
						   rangeEnd:(NSInteger)rangeEnd
					   suffixFormat:(NSString*)suffixFormat
{
	NSMutableArray *numberedNames = [[NSMutableArray alloc] initWithCapacity:40];
	
	for (int i = rangeStart; i <= rangeEnd; i++) {
		NSString *suffix = [NSString stringWithFormat:suffixFormat, i];
		NSString *filename = [NSString stringWithFormat:@"%@%@", filenamePrefix, suffix];
		
		[numberedNames addObject:filename];
	}
	
	NSArray *newArray = [NSArray arrayWithArray:numberedNames];
	[numberedNames release];
	return newArray;
}

// Given an array of resource names (as returned by arrayWithNumberedNames)
// create a new array that contains these resource names prefixed as
// resource paths and wrapped in a NSURL object.

+ (NSArray*) arrayWithResourcePrefixedURLs:(NSArray*)inNumberedNames
{
	NSMutableArray *URLs = [NSMutableArray arrayWithCapacity:[inNumberedNames count]];
	NSBundle* appBundle = [NSBundle mainBundle];
	
	for ( NSString* path in inNumberedNames ) {
		NSString* resPath = [appBundle pathForResource:path ofType:nil];
		NSURL* aURL = [NSURL fileURLWithPath:resPath];
		
		[URLs addObject:aURL];
	}
	
	NSArray *newArray = [NSArray arrayWithArray:URLs];
	return newArray;
}

- (void) rotateToPortrait
{
	self.view.layer.transform = CATransform3DIdentity;
}

- (void) rotateToLandscape
{
	float angle = M_PI / 2;  //rotate CCW 90°, or π/2 radians
	self.view.layer.transform = CATransform3DMakeRotation(angle, 0, 0.0, 1.0);
}

- (void) rotateToLandscapeRight
{
	float angle = -1 * (M_PI / 2);  //rotate CW 90°, or -π/2 radians
	self.view.layer.transform = CATransform3DMakeRotation(angle, 0, 0.0, 1.0);
}

// Invoke this method to prepare the video and audio data so that it can be played
// as soon as startAnimating is invoked. If this method is invoked twice, it
// does nothing on the second invocation. An activity indicator is shown on screen
// while the data is getting ready to animate.

- (void) prepareToAnimate
{
	if (isReadyToAnimate) {
		return;
	} else if (state == PREPPING) {
		return;
	} else if (state == STOPPED && !isReadyToAnimate) {
		// Edge case where an earlier prepare was canceled and
		// the animator never became ready to animate.
		self->state = PREPPING;
	} else if (state > PREPPING) {
		return;
	} else {
		// Must be ALLOCATED or LOADED
		assert(state < PREPPING);
		self->state = PREPPING;
	}

	// Lookup window this view is in to force animator and
	// busy indicator to be allocated when the event loop
	// is next entered. This code exists because of some
	// strange edge case where this view does not get
	// added to the containing window before the blocking load.

//	if (self.view.window == nil) {
//		NSAssert(FALSE, @"animator view is not inside a window");
//	}

	// Schedule a callback that will do the prep operation

	self.animationPrepTimer = [NSTimer timerWithTimeInterval: 0.10
													  target: self
													selector: @selector(_loadResourcesCallback:)
													userInfo: NULL
													 repeats: TRUE];

	[[NSRunLoop currentRunLoop] addTimer: animationPrepTimer forMode: NSDefaultRunLoopMode];
}

// Invoke this method to start the animation, if the animation is not yet
// ready to play then this method will return right away and the animation
// will be started when it is ready.

- (void) startAnimating
{
	[self prepareToAnimate];

	// If still preparing, just set a flag so that the animation
	// will start when the prep operation is finished.

	if (state < READY) {
		self->startAnimatingWhenReady = TRUE;
		return;
	}

	// No-op when already animating

	if (state == ANIMATING) {
		return;
	}

	// Can only transition from PAUSED to ANIMATING via unpause

	assert(state != PAUSED);

	assert(state == READY || state == STOPPED);

	self->state = ANIMATING;

	// Animation is broken up into two stages. Assume there are two frames that
	// should be displayed at times T1 and T2. At time T1 + animationFrameDuration/4
	// check the audio clock offset and use that time to schedule a callback to
	// be fired at time T2. The callback at T2 will simply display the image.
	// The second thread will be supplying us with rendered buffers in the
	// background.
	
	self.currentFrame = 0;

	// Amount of time that will elapse between the expected time that a frame
	// will be displayed and the time when the next frame decode operation
	// will be invoked.

	self->animationDecodeTimerInterval = animationFrameDuration / 4.0;

	// Calculate upper limit for time values that can be reported by
	// the system clock.

	NSUInteger lastFrameIndex = animationNumFrames - 1;

	self->animationMaxClockTime = (lastFrameIndex * animationFrameDuration) -
		(animationFrameDuration / 10);

	// Create initial callback that is invoked until the audio clock
	// has started running.

	self.animationDecodeTimer = [NSTimer timerWithTimeInterval: animationFrameDuration / 2.0
														target: self
													  selector: @selector(_animationDecodeInitialFrameCallback:)
													  userInfo: NULL
													   repeats: FALSE];

    [[NSRunLoop currentRunLoop] addTimer: animationDecodeTimer forMode: NSDefaultRunLoopMode];

	[avAudioPlayer play];

	[self _setAudioSessionCategory];

    // Turn off the event idle timer so that the screen is not dimmed while playing
	
	UIApplication *thisApplication = [UIApplication sharedApplication];	
    thisApplication.idleTimerDisabled = YES;
	
	// Send notification to object(s) that regestered interest in start action

	[[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDidStartNotification
														object:self];	
}

-(void)_setAudioSessionCategory {
	// Define audio session as MediaPlayback, so that audio output is not silenced
	// when the silent switch is set. This is a non-mixing mode, so any audio
	// being played is silenced.

	UInt32 sessionCategory = kAudioSessionCategory_MediaPlayback;
	OSStatus result =
	AudioSessionSetProperty(kAudioSessionProperty_AudioCategory, sizeof(sessionCategory), &sessionCategory);
	if (result != 0) {
		NSLog(@"%@", [NSString stringWithFormat:@"AudioSessionSetProperty(kAudioSessionProperty_AudioCategory,kAudioSessionCategory_MediaPlayback) error : %d", result]);
	}
}

// Invoke this method to stop the animation and cancel all callbacks.

- (void) stopAnimating
{
	if (state == STOPPED) {
		// When already stopped, don't generate another AVAnimatorDidStopNotification
		return;
	}

	// stopAnimating can be invoked in any state, it needs to cleanup
	// any pending callbacks and stop audio playback.

	self->state = STOPPED;
	
	[animationPrepTimer invalidate];
	self.animationPrepTimer = nil;

	[self _cleanupReadyToAnimate];

	[animationDecodeTimer invalidate];
	self.animationDecodeTimer = nil;

	[animationDisplayTimer invalidate];
	self.animationDisplayTimer = nil;

	[avAudioPlayer stop];
	avAudioPlayer.currentTime = 0.0;

	self->repeatedFrameCount = 0;

	self.prevFrame = nil;
	self.nextFrame = nil;

	[flatMovieFile rewind];

	// Reset idle timer
	
	UIApplication *thisApplication = [UIApplication sharedApplication];	
    thisApplication.idleTimerDisabled = NO;

	// Send notification to object(s) that regestered interest in the stop action

	[[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDidStopNotification
														object:self];

	return;
}

- (BOOL) isAnimating
{
	return (state == ANIMATING);
}

- (BOOL) isInitializing
{
	return (state < ANIMATING);
}

- (void) pause
{
  // FIXME: What state could this be in other than animating? Could be some tricky race conditions
  // here related to where the event comes from. Also note that an interruption can cause a pause
  // action, it can't be ignored from an interruption since that has to work!
  
//	NSAssert(state == ANIMATING, @"pause only valid while animating");

  if (state != ANIMATING) {
    // Ignore since an odd race condition could happen when window is put away or when
    // incoming call triggers this method.
    return;
  }
  
	[animationDecodeTimer invalidate];
	self.animationDecodeTimer = nil;

	[animationDisplayTimer invalidate];
	self.animationDisplayTimer = nil;

	[avAudioPlayer pause];

	self->repeatedFrameCount = 0;

	state = PAUSED;

	// Send notification to object(s) that regestered interest in the pause action

	[[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDidPauseNotification
														object:self];
}

- (void) unpause
{
	//NSAssert(state == PAUSED, @"unpause when not paused");
  if (state != PAUSED) {
    return;
  }

	state = ANIMATING;

	[avAudioPlayer play];

	// Resume decoding callbacks

	self.animationDecodeTimer = [NSTimer timerWithTimeInterval: animationDecodeTimerInterval
														target: self
													  selector: @selector(_animationDecodeFrameCallback:)
													  userInfo: NULL
													   repeats: FALSE];

	[[NSRunLoop currentRunLoop] addTimer: animationDecodeTimer forMode: NSDefaultRunLoopMode];

	// Send notification to object(s) that regestered interest in the unpause action

	[[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDidUnpauseNotification
														object:self];	
}

- (void) rewind
{
	[self stopAnimating];
  [self startAnimating];
}

- (void) doneAnimating
{
	[self stopAnimating];

	// Send notification to object(s) that regestered interest in the unpause action

	[[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDoneNotification
														object:self];	
}

// Util function that will query the clock time and enforce an upper
// bound on the current time 

- (void) _queryCurrentClockTimeAndCalcFrameNow:(NSTimeInterval*)currentTimePtr
								   frameNowPtr:(NSUInteger*)frameNowPtr
{
	// Query audio clock time right now

	NSTimeInterval currentTime = avAudioPlayer.currentTime;

	// Calculate the frame to the left of the time interval
	// (time/window) based on the current clock time. In the
	// simple case, the calculated frame will be the same
	// as the one currently being displayed. This logic
	// truncates the (time/window) result so that frameNow + 1
	// will be the index of the next frame. A reported time
	// that is less than zero will be returned as zero.
	// The frameNow value has the range [0, SIZE-2] since
	// it must always be one less than the largest frame.

	NSUInteger frameNow;

	if (currentTime <= 0.0) {
		currentTime = 0.0;
		frameNow = 0;
	} else if (currentTime <= animationFrameDuration) {
		frameNow = 0;
	} else if (currentTime > animationMaxClockTime) {
		currentTime = animationMaxClockTime;
		frameNow = animationNumFrames - 1 - 1;
	} else {
		frameNow = (NSUInteger) (currentTime / animationFrameDuration);

		// Check for the very tricky case where the currentTime
		// is very close to the frame interval time. A floating
		// point value that is very close to the frame interval
		// should not be truncated.

		NSTimeInterval plusOneTime = (frameNow + 1) * animationFrameDuration;
		NSAssert(currentTime <= plusOneTime, @"currentTime can't be larger than plusOneTime");
		NSTimeInterval plusOneDelta = (plusOneTime - currentTime);

		if (plusOneDelta < (animationFrameDuration / 100)) {
			frameNow++;
		}

// for testing crash dumps
//NSAssert(TRUE, @"fake failure");

		NSAssert(frameNow <= animationNumFrames - 1 - 1, @"frameNow large than second to last frame");
	}

	// The frameNow value must be within the bounds [0, SIZE-1] but in
	// this case we want to limit the range to [0, SIZE-2] since the
	// decode next frame step always decodes the next frame.

//	NSUInteger secondToLastFrameIndex = animationNumFrames - 1 - 1;

//	if (frameNow > secondToLastFrameIndex) {
//		frameNow = secondToLastFrameIndex;
//	}

	// It should not be possible for (frameNow + 1) to be smaller
	// than the reported currentTime.

// FIXME: calculated above, remove this later
	
	NSAssert(currentTime < ((frameNow + 1) * animationFrameDuration),
			 @"maximum reportable currentTime exceeded");

	*frameNowPtr = frameNow;
	*currentTimePtr = currentTime;
}

// This callback is invoked as the animation begins. The first
// frame or two need to sync to the audio clock before recurring
// callbacks can be scheduled to decode and paint.

- (void) _animationDecodeInitialFrameCallback: (NSTimer *)timer {
	assert(state == ANIMATING);

	// Audio clock time right now

	NSTimeInterval currentTime = avAudioPlayer.currentTime;

#ifdef DEBUG_OUTPUT
	if (TRUE) {
		NSString *formatted = [NSString stringWithFormat:@"%@%@%f",
							   @"_animationDecodeInitialFrameCallback: ",
							   @"\tcurrentTime: ", currentTime];
		NSLog(formatted);
	}
#endif	

	if (currentTime < (animationFrameDuration / 2.0)) {
		// Ignore reported times until they are at least half way to the
		// first frame time. The audio could take a moment to start and it
		// could report a number of zero or less than zero times. Keep
		// scheduling a non-repeating call to _animationDecodeFrameCallback
		// until the audio clock is actually running.

		if (animationDecodeTimer != nil) {
			[animationDecodeTimer invalidate];
			//self.animationDecodeTimer = nil;
		}

		self.animationDecodeTimer = [NSTimer timerWithTimeInterval: animationDecodeTimerInterval
															target: self
														  selector: @selector(_animationDecodeInitialFrameCallback:)
														  userInfo: NULL
														   repeats: FALSE];

		[[NSRunLoop currentRunLoop] addTimer: animationDecodeTimer forMode: NSDefaultRunLoopMode];
	} else {
		// Reported time is now at least half way to the first frame, so
		// we are ready to schedule recurring callbacks. Invoking the
		// decode frame callback will setup the next frame and
		// schedule the callbacks.

		[self _animationDecodeFrameCallback:nil];

		NSAssert(animationDecodeTimer != nil, @"should have scheduled a decode callback");
	}
}

// Invoked at a time between two frame display times.
// This callback will queue the next display operation
// and it will queue the next frame decode operation.
// This method takes are of the case where the decode
// logic is too slow because the next trip to the event
// loop will display the next frame as soon as possible.

- (void) _animationDecodeFrameCallback: (NSTimer *)timer {
	assert(state == ANIMATING);

	NSTimeInterval currentTime;
	NSUInteger frameNow;

	[self _queryCurrentClockTimeAndCalcFrameNow:&currentTime frameNowPtr:&frameNow];	
	
#ifdef DEBUG_OUTPUT
	if (TRUE) {
		NSUInteger secondToLastFrameIndex = animationNumFrames - 1 - 1;

		NSTimeInterval timeExpected = (frameNow * animationFrameDuration) +
			animationDecodeTimerInterval;
		NSTimeInterval timeDelta = currentTime - timeExpected;
		NSString *formatted = [NSString stringWithFormat:@"%@%@%d%@%d%@%d%@%@%f%@%f",
							   @"_animationDecodeFrameCallback: ",
							   @"\tanimationFrameNum: ", currentFrame,
							   @"\tframeNow: ", frameNow,
							   @" (", secondToLastFrameIndex, @")",
							   @"\tcurrentTime: ", currentTime,
							   @"\tdelta: ", timeDelta
							   ];
		NSLog(formatted);
	}
#endif

	// If the audio clock is reporting nonsense results like time going
	// backwards, just treat it like the clock is stuck. If a number
	// of stuck clock callbacks are found then animation will be stopped.

	if (frameNow < currentFrame) {
		NSString *msg = [NSString stringWithFormat:@"frameNow %d can't be less than currentFrame %d",
						 frameNow, currentFrame];
		NSLog(@"%@", msg);

		frameNow = currentFrame;
	}

	if (frameNow == currentFrame) {
		self->repeatedFrameCount++;
	} else {
		self->repeatedFrameCount = 0;
	}

	if (repeatedFrameCount > 10) {
		// Audio clock has stopped reporting progression of time
		NSLog(@"%@", [NSString stringWithFormat:@"audio time not progressing: %f", currentTime]);
	}
	if (repeatedFrameCount > 20) {
		NSLog(@"%@", [NSString stringWithFormat:@"doneAnimating because audio time not progressing"]);

		[self doneAnimating];
		return;
	}

	// Figure out which callbacks should be scheduled

	BOOL isAudioClockStuck = FALSE;
	BOOL shouldScheduleDisplayCallback = TRUE;
	BOOL shouldScheduleDecodeCallback = TRUE;
	BOOL shouldScheduleLastFrameCallback = FALSE;

	if (frameNow == currentFrame) {
		// The audio clock must be stuck, because there is no change in
		// the frame to display. This is basically a no-op, schedule
		// another frame decode operation but don't schedule a
		// frame display operation. Because the clock is stuck, we
		// don't know exactly when to schedule the callback for
		// based on frameNow, so schedule it one frame duration from now.

		isAudioClockStuck = TRUE;
		shouldScheduleDisplayCallback = FALSE;
	}

	// Schedule the next frame display callback. In the case where the decode
	// operation takes longer than the time until the frame interval, the
	// display operation will be done as soon as the decode is over.	

	NSUInteger nextFrameIndex;
	NSTimeInterval nextFrameExpectedTime;
	NSTimeInterval delta;

	if (shouldScheduleDisplayCallback) {
		assert(isAudioClockStuck == FALSE);

		nextFrameIndex = frameNow + 1;
		nextFrameExpectedTime = (nextFrameIndex * animationFrameDuration);
		delta = nextFrameExpectedTime - currentTime;
		assert(delta > 0.0);

		if (animationDisplayTimer != nil) {
			[animationDisplayTimer invalidate];
			//self.animationDisplayTimer = nil;
		}

		self.animationDisplayTimer = [NSTimer timerWithTimeInterval: delta
															 target: self
														   selector: @selector(_animationDisplayFrameCallback:)
														   userInfo: NULL
															repeats: FALSE];

		[[NSRunLoop currentRunLoop] addTimer: animationDisplayTimer forMode: NSDefaultRunLoopMode];			
	}

	// Schedule the next frame decode operation. Figure out when the
	// decode event should be invoked based on the clock time. This
	// logic will automatically sync the decode operation to the
	// audio clock each time this method is invoked. If the clock
	// is stuck, just take care of this in the next callback.

	if (!isAudioClockStuck) {
		NSUInteger secondToLastFrameIndex = animationNumFrames - 1 - 1;

		if (frameNow == secondToLastFrameIndex) {
			// When on the second to last frame, we should schedule
			// an event that puts away the last frame at the end
			// of the frame display interval.

			shouldScheduleDecodeCallback = FALSE;
			shouldScheduleLastFrameCallback = TRUE;
		}			
	}

	if (shouldScheduleDecodeCallback || shouldScheduleLastFrameCallback) {
		if (isAudioClockStuck) {
			delta = animationFrameDuration;
		} else if (shouldScheduleLastFrameCallback) {
			// nextFrameIndex was set earlier in this function

			nextFrameExpectedTime = ((nextFrameIndex + 1) * animationFrameDuration);
			delta = nextFrameExpectedTime - currentTime;
		} else {
			// nextFrameIndex was set earlier in this function

			nextFrameExpectedTime = (nextFrameIndex * animationFrameDuration) + animationDecodeTimerInterval;
			delta = nextFrameExpectedTime - currentTime;
		}
		assert(delta > 0.0);

		if (animationDecodeTimer != nil) {
			[animationDecodeTimer invalidate];
			//self.animationDecodeTimer = nil;
		}

		SEL aSelector = @selector(_animationDecodeFrameCallback:);

		if (shouldScheduleLastFrameCallback) {
			aSelector = @selector(_animationDoneLastFrameCallback:);
		}

		self.animationDecodeTimer = [NSTimer timerWithTimeInterval: delta
															target: self
														  selector: aSelector
														  userInfo: NULL
														   repeats: FALSE];

		[[NSRunLoop currentRunLoop] addTimer: animationDecodeTimer forMode: NSDefaultRunLoopMode];		
	}

	// Decode the next frame, this operation could take some time, so it needs to
	// be done after callbacks have been scheduled. If the decode time takes longer
	// than the amount of time before the display callback, then the display
	// callback will be invoked right after the decode operation is finidhed.

	if (isAudioClockStuck) {
		// no-op
	} else {
		self.currentFrame = frameNow;

		BOOL wasFrameDecoded = [self _animationDecodeNextFrame];

		if (!wasFrameDecoded) {
			// Cancel the frame display callback at the end of this interval

			if (animationDisplayTimer != nil) {
				[animationDisplayTimer invalidate];
				self.animationDisplayTimer = nil;
			}	
		}
	}
}

// Invoked after the final animation frame is shown on screen, this callback
// will stop the animation and set it off on another loop iteration if
// required.

- (void) _animationDoneLastFrameCallback: (NSTimer *)timer {
#ifdef DEBUG_OUTPUT
	NSLog([NSString stringWithFormat:@"_animationDoneLastFrameCallback"]);
#endif
	[self stopAnimating];
	
	// Continue to loop animation until loop counter reaches 0

	if (animationRepeatCount > 0) {
		self.animationRepeatCount = animationRepeatCount - 1;
		[self startAnimating];
	} else {
		[self doneAnimating];
	}
}

// Invoked at a time as close to the actual display time
// as possible. This method is designed to have low latency,
// it just changes the frame that is displayed in the imageView

- (void) _animationDisplayFrameCallback: (NSTimer *)timer {
	assert(state == ANIMATING);

#ifdef DEBUG_OUTPUT
	NSTimeInterval currentTime;
	NSUInteger frameNow;
	
	[self _queryCurrentClockTimeAndCalcFrameNow:&currentTime frameNowPtr:&frameNow];		

	if (TRUE) {
		NSTimeInterval timeExpected = (frameNow * animationFrameDuration);

		NSTimeInterval timeDelta = currentTime - timeExpected;

		NSString *formatted = [NSString stringWithFormat:@"%@%@%d%@%d%@%f%@%f",
							   @"_animationDisplayFrameCallback: ",
							   @"\tanimationFrameNum: ", currentFrame,
							   @"\tframeNow: ", frameNow,
							   @"\tcurrentTime: ", currentTime,
							   @"\tdelta: ", timeDelta
		];
		NSLog(formatted);
	 }
#endif // DEBUG_OUTPUT

	// Display the "next" frame image, this logic does
	// the minimium amount of work to paint the display
	// with the contents of a UIImage. No objects are
	// allocated in this callback and no objects
	// are released. In the case of a duplicate
	// frame, where the next frame is the exact same
	// data as the previous frame, the render callback
	// will not change the value of nextFrame so
	// this method can just avoid updating the display.

	UIImage *currentImage = imageView.image;

	self.prevFrame = currentImage;

	if (currentImage != nextFrame) {
		imageView.image = nextFrame;
//		[imageView setNeedsDisplay];
	}

// Test release of frame now, instead of in next decode callback. Seems
// that holding until the next decode does not actually release sometimes.

//	self.prevFrame = nil;

	return;
}

// Display the given animation frame, in the range [1 to N]
// where N is the largest frame number.

- (void) animationShowFrame: (NSInteger) frame {
	if ((frame >= animationNumFrames) || (frame < 0))
		return;
	
	self.currentFrame = frame - 1;
	[self _animationDecodeNextFrame];
	[self _animationDisplayFrameCallback:nil];
	self.currentFrame = frame;
}

// This method is invoked to decode the next frame
// of data and prepare the data to be rendered
// in the image view. In the normal case, the
// next frame is rendered and TRUE is returned.
// If the next frame is an exact duplicate of the
// previous frame, then FALSE is returned to indicate
// that no update is needed for the next frame.

- (BOOL) _animationDecodeNextFrame {
	NSUInteger nextFrameNum = currentFrame + 1;
	NSAssert(nextFrameNum >= 0 && nextFrameNum < animationNumFrames, @"nextFrameNum is invalid");

	// Deallocate UIImage object for the frame before
	// the currently displayed one. This will drop the
	// provider ref if it is holding the last ref.
	// Note that this should also clear the data
	// provider flag on an associated CGFrameBuffer
	// so that it can be used again.

//	int refCount;

	UIImage *prevFrameImage = self.prevFrame;

	if (prevFrameImage != nil) {
		if (prevFrameImage != self.nextFrame) {
			NSAssert(prevFrameImage != imageView.image,
					 @"self.prevFrame is not the same as imageView.image");
		}

//		refCount = [prevFrameImage retainCount];
//		NSLog([NSString stringWithFormat:@"refCount before %d", refCount]);

		self.prevFrame = nil;

//		if (refCount > 1) {
//			refCount = [prevFrameImage retainCount];
//			NSLog([NSString stringWithFormat:@"refCount after %d", refCount]);
//		} else {
//			NSLog([NSString stringWithFormat:@"should have been freed"]);			
//		}
	}

	// Lookup UIImage for next frame

	CGFrameBuffer *cgFrameBuffer = nil;
	for (CGFrameBuffer *aBuffer in cgFrameBuffers) {
		if (!aBuffer.isLockedByDataProvider) {
			cgFrameBuffer = aBuffer;
			break;
		}
	}
	if (cgFrameBuffer == nil) {
		NSAssert(FALSE, @"no cgFrameBuffer is available");
	}

	// Advance the "current frame" in the movie frames
	// by applying patches. The current frame is advanced
	// until it is the same as nextFrameNum by applying
	// patches to the frame's RLE data. In the case
	// where the next frame is exactly the same as the
	// previous frame, FALSE will be returned. Otherwise
	// TRUE is returned to indicate that the frame data
	// has changed.
	
	BOOL changedFrameData = [flatMovieFile advanceToFrame:nextFrameNum];

// FIXME: decode every frame
//	changedFrameData = TRUE;
	
	if (!changedFrameData)
		return FALSE;

	char *currentFrameRLEData;
	NSUInteger currentFrameRLEDataNumBytes;
	
	currentFrameRLEData = [flatMovieFile currentFrameBytes:&currentFrameRLEDataNumBytes];
	
	[cgFrameBuffer runLengthDecodeBytes:currentFrameRLEData numEncodedBytes:currentFrameRLEDataNumBytes];
	
	CGImageRef imgRef = [cgFrameBuffer createCGImageRef];
	NSAssert(imgRef, @"CGImageRef returned by createCGImageRef is NULL");
	self.nextFrame = [UIImage imageWithCGImage:imgRef];
	CGImageRelease(imgRef);

	return TRUE;
}

// Release anything that's not essential, such as cached data

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning]; // Releases the view if it doesn't have a superview

	NSLog(@"AVAnimatorViewController didReceiveMemoryWarning");
}

- (void) dealloc {
	// This object can't be deallocated while animating, this could
	// only happen if user code incorrectly dropped the last ref.

//	NSLog(@"AVAnimatorViewController dealloc");

	NSAssert(state != PAUSED, @"dealloc while paused");
	NSAssert(state != ANIMATING, @"dealloc while animating");

	[resourceLoader release];
	[animationArchiveURL release];
	[animationAudioURL release];

/*
	CGImageRef imgRef1 = imageView.image.CGImage;
	CGImageRef imgRef2 = prevFrame.CGImage;
	CGImageRef imgRef3 = nextFrame.CGImage;
*/

	// Explicitly release image inside the imageView, the
	// goal here is to get the imageView to drop the
	// ref to the CoreGraphics image and avoid a memory
	// leak. This should not be needed, but it is.

	imageView.image = nil;

	[imageView release];
	[prevFrame release];
	[nextFrame release];

/*
	for (CGFrameBuffer *aBuffer in cgFrameBuffers) {
		int count = [aBuffer retainCount];
		count = count;

		if (aBuffer.isLockedByDataProvider) {
			NSString *msg = [NSString stringWithFormat:@"%@, count %d",
							 @"CGFrameBuffer is still locked by UIKit", count];
			NSLog(msg);

			if ([aBuffer isLockedByImageRef:imgRef1]) {
				NSLog(@"locked by imgRef1");
			} else if ([aBuffer isLockedByImageRef:imgRef2]) {
				NSLog(@"locked by imgRef2");
			} else if ([aBuffer isLockedByImageRef:imgRef3]) {
				NSLog(@"locked by imgRef3");
			} else {
				NSLog(@"locked by unknown image ref");				
			}
		}
	}
*/

	[cgFrameBuffers release];

	[animationPrepTimer release];
	[animationReadyTimer release];
	[animationDecodeTimer release];
	[animationDisplayTimer release];

	// Reset the delegate state for the audio player object
	// and release the delegate. The avAudioPlayer object
	// can still exist on the event queue after it has been
	// released here, so resetting the delegate avoids a
	// crash invoking delegate method on a now invalid ref.

	avAudioPlayer.delegate = originalAudioDelegate;
	[retainedAudioDelegate release];
  self.avAudioPlayer = nil;

	[flatMovieFile release];

    [super dealloc];
}

- (void) setViewFrame:(CGRect)inSize
{
	assert(isViewFrameSet == FALSE);
	self->isViewFrameSet = TRUE;
	self->viewFrame = inSize;
}

@end
