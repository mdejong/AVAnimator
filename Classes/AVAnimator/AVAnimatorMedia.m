//
//  AVAnimatorMedia.m
//
//  Created by Moses DeJong on 3/18/09.
//
//  License terms defined in License.txt.

#import "AVAnimatorMedia.h"

#import <QuartzCore/QuartzCore.h>

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#import "CGFrameBuffer.h"
#import "AVResourceLoader.h"
#import "AVFrame.h"
#import "AVFrameDecoder.h"

#import "AVAppResourceLoader.h"

// Uncomment to enable debug output, note that this kill FPS performance of decoder!
//#define DEBUG_OUTPUT

#define REPEATED_FRAME_WARN_COUNT 10
#define REPEATED_FRAME_DONE_COUNT 20

// util class AVAnimatorMediaAudioPlayerDelegate declaration

@interface AVAnimatorMediaAudioPlayerDelegate : NSObject <AVAudioPlayerDelegate> {	
@public
	AVAnimatorMedia *media;
}

- (id) initWithMedia:(AVAnimatorMedia*)inMedia;

@end // class AVAnimatorMediaAudioPlayerDelegate declaration

@implementation AVAnimatorMediaAudioPlayerDelegate

- (id) initWithMedia:(AVAnimatorMedia*)inMedia {
	self = [super init];
	if (self) {
    // Note that we don't retain a ref here, as AVAnimatorView/AVAnimatorLayer is
    // the only object that can ref this object, holding a ref would create
    // a circular reference and the view would never be deallocated.
    self->media = inMedia;
  }
	return self;
}

// Invoked when audio player was interrupted, for example by
// an incoming phone call.

- (void)audioPlayerBeginInterruption:(AVAudioPlayer *)player
{
	// FIXME: pass reason for stop (loop, interrupt)
  
	[media pause];
}

- (void)audioPlayerEndInterruption:(AVAudioPlayer *)player
{
	// Resume playback of audio
  
	[media unpause];
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

@end // class AVAnimatorMediaAudioPlayerDelegate implementation

// private properties declaration for AVAnimatorMedia class

#include "AVAnimatorMediaPrivate.h"

// class AVAnimatorMedia

@implementation AVAnimatorMedia

// public properties

@synthesize renderer = m_renderer;
@synthesize resourceLoader = m_resourceLoader;
@synthesize frameDecoder = m_frameDecoder;
@synthesize animatorFrameDuration = m_animatorFrameDuration;
@synthesize animatorNumFrames = m_animatorNumFrames;
@synthesize animatorRepeatCount = m_animatorRepeatCount;

// private properties

@synthesize animatorAudioURL = m_animatorAudioURL;
@synthesize prevFrame = m_prevFrame;
@synthesize nextFrame = m_nextFrame;
@synthesize animatorPrepTimer = m_animatorPrepTimer;
@synthesize animatorReadyTimer = m_animatorReadyTimer;
@synthesize animatorDecodeTimer = m_animatorDecodeTimer;
@synthesize animatorDisplayTimer = m_animatorDisplayTimer;
@synthesize currentFrame = m_currentFrame;
@synthesize repeatedFrameCount = m_repeatedFrameCount;
@synthesize avAudioPlayer = m_avAudioPlayer;
@synthesize audioSimulatedStartTime = m_audioSimulatedStartTime;
@synthesize audioSimulatedNowTime = m_audioSimulatedNowTime;
@synthesize audioPlayerFallbackStartTime = m_audioPlayerFallbackStartTime;
@synthesize audioPlayerFallbackNowTime = m_audioPlayerFallbackNowTime;
@synthesize state = m_state;
@synthesize pauseTimeInterval = m_pauseTimeInterval;
@synthesize animatorMaxClockTime = m_animatorMaxClockTime;
@synthesize animatorDecodeTimerInterval = m_animatorDecodeTimerInterval;
@synthesize isReadyToAnimate = m_isReadyToAnimate;
@synthesize startAnimatorWhenReady = m_startAnimatorWhenReady;
@synthesize decodedSecondFrame = m_decodedSecondFrame;
@synthesize ignoreRepeatedFirstFrameReport = m_ignoreRepeatedFirstFrameReport;
@synthesize decodedLastFrame = m_decodedLastFrame;
@synthesize reportTimeFromFallbackClock;
@synthesize reverse = m_reverse;

- (void) dealloc {
	// This object can't be deallocated while animating, this could
	// only happen if user code incorrectly dropped the last ref.
  
  //	NSLog(@"AVAnimatorMedia dealloc");
  
	NSAssert(self.state != PAUSED, @"dealloc while paused");
	NSAssert(self.state != ANIMATING, @"dealloc while animating");
    
	self.animatorAudioURL = nil;
  
	self.prevFrame = nil;
	self.nextFrame = nil;
  
  // Release resource loader and frame decoder
  // after image related objects, in case the image
  // objects held a ref to frame buffers in the
  // decoder class.
  
  self.renderer = nil;
	self.resourceLoader = nil;
  self.frameDecoder = nil;
  
  // FIXME: better to just use AutoTimer here
  
  [self.animatorPrepTimer invalidate];
  self.animatorPrepTimer = nil;
  [self.animatorReadyTimer invalidate];
  self.animatorReadyTimer = nil;
  [self.animatorDecodeTimer invalidate];
  self.animatorDecodeTimer = nil;
  [self.animatorDisplayTimer invalidate];
  self.animatorDisplayTimer = nil;
  
	// Reset the delegate state for the audio player object
	// and release the delegate. The avAudioPlayer object
	// can still exist on the event queue after it has been
	// released here, so resetting the delegate avoids a
	// crash invoking delegate method on a now invalid ref.
  
  if (self.avAudioPlayer) {
    self.avAudioPlayer.delegate = self->m_originalAudioDelegate;
#if __has_feature(objc_arc)
#else
    [self->m_retainedAudioDelegate release];
#endif // objc_arc
    self.avAudioPlayer = nil;
  }
  self.audioSimulatedStartTime = nil;
  self.audioSimulatedNowTime = nil;
  self.audioPlayerFallbackStartTime = nil;
  self.audioPlayerFallbackNowTime = nil;
  
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

// static ctor

+ (AVAnimatorMedia*) aVAnimatorMedia
{
  AVAnimatorMedia *obj = [[AVAnimatorMedia alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (id) init
{
  if ((self = [super init])) {
    self.state = ALLOCATED;
    self.currentFrame = -1;
  }
  return self;
}

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

- (void) _createAudioPlayer
{
	NSError *error;
	AVAudioPlayer *avPlayer = nil;
  
  if (self.animatorAudioURL == nil) {
    return;
  }
	NSURL *audioURL = self.animatorAudioURL;
  
	NSString *audioURLPath = [audioURL path];
	NSString *audioURLTail = [self _getLastPathComponent:audioURLPath];
	char *audioURLTailStr = (char*) [audioURLTail UTF8String];
	NSAssert(audioURLTailStr != NULL, @"audioURLTailStr is NULL");
	NSAssert(audioURLTail != nil, @"audioURLTail is nil");
  
	avPlayer = [AVAudioPlayer alloc];
	avPlayer = [avPlayer initWithContentsOfURL:audioURL error:&error];
  
#if __has_feature(objc_arc)
#else
	avPlayer = [avPlayer autorelease];
#endif // objc_arc
  
	if (error.code == kAudioFileUnsupportedFileTypeError) {
		NSAssert(FALSE, @"unsupported audio file format");
	}
  
	NSAssert(avPlayer, @"AVAudioPlayer could not be allocated");
  
	self.avAudioPlayer = avPlayer;
  
	AVAnimatorMediaAudioPlayerDelegate *audioDelegate;
  
	audioDelegate = [[AVAnimatorMediaAudioPlayerDelegate alloc] initWithMedia:self];
  
	// Note that in OS 3.0, the delegate does not seem to be retained though it
	// was retained in OS 2.0. Explicitly retain it as a separate ref. Save
	// the original delegate value and reset it before dropping the ref to the
	// audio player just to be safe.
  
	self->m_originalAudioDelegate = self.avAudioPlayer.delegate;
	self.avAudioPlayer.delegate = audioDelegate;
	self->m_retainedAudioDelegate = audioDelegate;
  
	NSLog(@"%@", [NSString stringWithFormat:@"default avPlayer volume was %f", avPlayer.volume]);
  
	// Get the audio player ready by pre-loading buffers from disk
  
	[self.avAudioPlayer prepareToPlay];
}

// This method is invoked in the prep state via a timer callback
// while the widget is preparing to animate. In the case where
// all resources are ready, this method will init the frame decoder
// with the resource paths returned by the resource loader.
// The first time this method is called, this code will invoke
// the load method on the resource loader that the could kick off
// an async loading operation. In any case, the resource loader
// will notice multiple calls to load and ignore all but the first.

- (BOOL) _loadResources
{
	//NSLog(@"Started _loadResources");
  
  NSAssert(self.resourceLoader, @"resourceLoader");
	BOOL isReady = [self.resourceLoader isReady];
  if (!isReady) {
    //NSLog(@"Not Yet Ready in _loadResources");
    [self.resourceLoader load];
    return FALSE;
  }
  
	//NSLog(@"Ready _loadResources");
  
	NSArray *resourcePathsArr = [self.resourceLoader getResources];
  
	// First path is the movie file, second is the audio
  
	NSAssert([resourcePathsArr count] == 1 || [resourcePathsArr count] == 2, @"expected 1 or 2 resource paths");
  
	NSString *videoPath = nil;
	NSString *audioPath = nil;
  
	videoPath = [resourcePathsArr objectAtIndex:0];
  if ([resourcePathsArr count] == 2) {
    audioPath = [resourcePathsArr objectAtIndex:1];
  }
  
  NSAssert(self.frameDecoder, @"frameDecoder");

  NSLog(@"%@", [NSString stringWithFormat:@"frameDecoder openForReading \"%@\"", [videoPath lastPathComponent]]);
  
  BOOL worked = [self.frameDecoder openForReading:videoPath];
  
  if (!worked) {
    NSLog(@"frameDecoder openForReading failed");
    self.state = FAILED;
    return TRUE;
  }
    
  // Read frame duration from movie by default. If user explicitly indicated a frame duration
  // the use it instead of what appears in the movie.
  
  if (self.animatorFrameDuration == 0.0) {
    AVFrameDecoder *decoder = self.frameDecoder;
    NSTimeInterval duration = [decoder frameDuration];
    NSAssert(duration != 0.0, @"frame duration can't be zero");
    self.animatorFrameDuration = duration;
  }

  // Record how many frame there are in the animation
  
	self.animatorNumFrames = [self.frameDecoder numFrames];
	assert(self.animatorNumFrames >= 2);
  
  NSAssert(self.currentFrame == -1, @"currentFrame");
    
	// Set url that will be the source for audio played in the app
  
  if (audioPath) {
    NSURL *url = [NSURL fileURLWithPath:audioPath];
    self.animatorAudioURL = url;
  }
  
	return TRUE;
}

- (void) _cleanupReadyToAnimate
{
	[self.animatorReadyTimer invalidate];
	self.animatorReadyTimer = nil;
  
  //NSLog(@"AVAnimatorMedia: _cleanupReadyToAnimate");
}

// When a media item is ready to load resources needed for audio/video
// playback, this method is invoked.

- (void) _loadResourcesCallback:(NSTimer *)timer
{
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
#ifdef DEBUG_OUTPUT
  NSLog(@"AVAnimatorMedia: _loadResourcesCallback");
#endif
  
	NSAssert(self.state == PREPPING, @"expected to be in PREPPING state");
  NSAssert(self.resourceLoader, @"resourceLoader must be defined");
	NSAssert(self.frameDecoder, @"frameDecoder must be defined");
  
	// Note that we don't load any data from the movie archive or from the
	// audio files at widget load time. Resource loading is done only as a
	// result of a call to prepareToAnimate. Only a state change of
	// ALLOCATED -> LOADED is possible here.
  
	if (self.state == ALLOCATED) {
		self.state = LOADED;
	}

  // Test to see if the all resources have been loaded. If they have, then
  // stop invoking the load callback and get ready to play.
  
  BOOL ready = [self _loadResources];
  if (!ready) {
    // Not ready yet, continue with callbacks. Note that we don't cancel
    // the prep timer, so this method is invoked again after a delay.
    return;
  }
    
	// Finish up init state
  
	[self.animatorPrepTimer invalidate];
	self.animatorPrepTimer = nil;  
  
  // If loading failed at this point, then the file data must be invalid.
  
  if (self.state == FAILED) {
    [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorFailedToLoadNotification
                                                        object:self];
    
    return;
  }
  
  // Media should now be ready to attach to the video renderer. If there is no renderer at this
  // point then it could still be attached later.
  
	self.state = READY;
	self.isReadyToAnimate = TRUE;
  
  if (self.renderer) {
    
    BOOL worked = [self attachToRenderer:self.renderer];

    if (worked == FALSE) {
      // If attaching to the renderer failed, then the whole loading process fails
      
      self.state = FAILED;
      self.isReadyToAnimate = FALSE;
      
      [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorFailedToLoadNotification
                                                          object:self];
      
      return;
    }
  }
  
	// Init audio data
	
	[self _createAudioPlayer];
  
  // Send out a notification that indicates that the movie is now fully loaded
  // and is ready to play.
  
  [self _cleanupReadyToAnimate];
  
  // Send notification to object(s) that regestered interest in prepared action
  
  [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorPreparedToAnimateNotification
                                                      object:self];
  
  if (self.startAnimatorWhenReady) {
    [self startAnimator];
  }
  
	return;
}

// Invoke this method to prepare the video and audio data so that it can be played
// as soon as startAnimator is invoked. If this method is invoked twice, it
// does nothing on the second invocation. An activity indicator is shown on screen
// while the data is getting ready to animate.

- (void) prepareToAnimate
{
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
	if (self.isReadyToAnimate) {
		return;
	} else if (self.state == PREPPING) {
		return;
	} else if (self.state == FAILED) {
		return;
	} else if (self.state == STOPPED && !self.isReadyToAnimate) {
		// Edge case where an earlier prepare was canceled and
		// the animator never became ready to animate.
		self.state = PREPPING;
	} else if (self.state > PREPPING) {
		return;
	} else {
		// Must be ALLOCATED or LOADED
		assert(self.state < PREPPING);
		self.state = PREPPING;
	}
  
	// Lookup window this view is in to force animator and
	// busy indicator to be allocated when the event loop
	// is next entered. This code exists because of some
	// strange edge case where this view does not get
	// added to the containing window before the blocking load.
  
//  if (self.window == nil) {
//  		NSAssert(FALSE, @"animator view is not inside a window");
//  }
  
	// Schedule a callback that will do the prep operation
  
	NSAssert(self.animatorPrepTimer == nil, @"animatorPrepTimer");
  
	self.animatorPrepTimer = [NSTimer timerWithTimeInterval: 0.10
                                                    target: self
                                                  selector: @selector(_loadResourcesCallback:)
                                                  userInfo: NULL
                                                   repeats: TRUE];
  
	[[NSRunLoop currentRunLoop] addTimer: self.animatorPrepTimer forMode: NSDefaultRunLoopMode];
}

// This callback is invoked as a result of a timer just after the startAnimator
// method is invoked. This logic is needed because of an odd race condition in
// AVAudioPlayer between calls to [self.avAudioPlayer stop] and [self.avAudioPlayer play]
// where the audio will not start playing a second time unless the event loop is entered
// after the call to stop.

- (void) _delayedStartAnimator:(NSTimer *)timer
{
  // Would always be invoked just after a call to startAnimator
  
  if (self.state != ANIMATING) {
    return;
  }
  
  // Create initial callback that is invoked until the audio clock
  // has started running.
  
  [self.animatorDecodeTimer invalidate];
  
  self.animatorDecodeTimer = [NSTimer timerWithTimeInterval: self.animatorFrameDuration / 2.0
                                                     target: self
                                                   selector: @selector(_animatorDecodeInitialFrameCallback:)
                                                   userInfo: NULL
                                                    repeats: FALSE];
  
  [[NSRunLoop currentRunLoop] addTimer:self.animatorDecodeTimer forMode:NSDefaultRunLoopMode];
  
  // Start playing audio or record the start time if using simulated audio clock
  
  if (self.avAudioPlayer) {
    [self.avAudioPlayer prepareToPlay];
    [self.avAudioPlayer play];
    [self _setAudioSessionCategory];
    
    // Fallback start time is saved in case avAudioPlayer runs short
    // and begins to report a zero time while there are still
    // animation frames that need to be displayed.

    NSDate *startTimeRightNow = [NSDate date];
    self.audioPlayerFallbackStartTime = startTimeRightNow;
    self.audioSimulatedStartTime = nil;
    self.audioSimulatedNowTime = nil;
//    NSLog(@"assigned start time : %@" , [startTimeRightNow description]);
  } else {
    NSDate *startTimeRightNow = [NSDate date];
    self.audioPlayerFallbackStartTime = startTimeRightNow;
    self.audioSimulatedStartTime = startTimeRightNow;
    self.audioSimulatedNowTime = nil;
//    NSLog(@"assigned start time : %@" , [startTimeRightNow description]);
  }

  // Turn off the event idle timer so that the screen is not dimmed while playing
	
  UIApplication *thisApplication = [UIApplication sharedApplication];	
  thisApplication.idleTimerDisabled = YES;
	
  // Send notification to object(s) that regestered interest in start action
  
  [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDidStartNotification object:self];
}

// Invoke this method to start the animator, if the animator is not yet
// ready to play then this method will return right away and the animator
// will be started when it is ready.

- (void) startAnimator
{
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
#ifdef DEBUG_OUTPUT
	if (TRUE) {
		NSLog(@"startAnimator: ");
	}
#endif
  
	[self prepareToAnimate];
  
	// If still preparing, just set a flag so that the animator
	// will start when the prep operation is finished.

	if (self.state == FAILED) {
		return;
	} else if (self.state < READY) {
		self.startAnimatorWhenReady = TRUE;
		return;
	}
  
	// No-op when already animating
  
	if (self.state == ANIMATING) {
		return;
	}
  
  // Media object must be attached to a renderer otherwise it is not possible to
  // start animating
  
  if (self.renderer == nil) {
    NSAssert(FALSE, @"renderer not defined for media object, attachMedia must be invoked before startAnimator");
  }
  
  // Implicitly rewind before playing, this basically just deallocates any previous
  // play resources in the frame decoder.
  
  BOOL wasNeverStarted = FALSE;
  
  if (self.state <= READY) {
    // Play was never started successfully
    wasNeverStarted = TRUE;
  }
  
  if (wasNeverStarted) {
    // No reason to rewind if not actually started yet
  } else {
    [self rewind];
  }
  
	// Can only transition from PAUSED to ANIMATING via unpause
  
	assert(self.state != PAUSED);
  
	assert(self.state == READY || self.state == STOPPED);
  
	self.state = ANIMATING;
    
	// Animation is broken up into two stages. Assume there are two frames that
	// should be displayed at times T1 and T2. At time T1 + animatorFrameDuration/4
	// check the audio clock offset and use that time to schedule a callback to
	// be fired at time T2. The callback at T2 will simply display the image.
  
  self.decodedSecondFrame = FALSE;
  self.decodedLastFrame = FALSE;
  self.reportTimeFromFallbackClock = FALSE;
  
	// Amount of time that will elapse between the expected time that a frame
	// will be displayed and the time when the next frame decode operation
	// will be invoked.

	self.animatorDecodeTimerInterval = self.animatorFrameDuration / 4.0;
//	self.animatorDecodeTimerInterval = self.animatorFrameDuration / 10.0;
  
	// Calculate upper limit for time that maps to specific frames.
  
	self.animatorMaxClockTime = ((self.animatorNumFrames - 1) * self.animatorFrameDuration) -
    (self.animatorFrameDuration / 10);
  
  self.repeatedFrameCount = 0;
    
  // There should be no display timer at this point
  NSAssert(self.animatorDisplayTimer == nil, @"animatorDisplayTimer");
  
  // If the reverse flag is set, verify that the deoder supports
  // random access.
  
  if (self.reverse) {
    NSAssert(self.frameDecoder.isAllKeyframes == true, @"media.reverse flag set for decoder that does not support random frame access");
  }
  
  // Display the initial frame right away. The initial frame callback logic
  // will decode the second frame when the clock starts running, but the
  // first frames needs to be shown until that callback is invoked.
  // Note that the frame decode could take some time, because the initial
  // keyframe could take some time to decode, so be sure to fully decode
  // the initial frame before kicking off the audio playback or calculating
  // the simulated start time.
  
  [self showFrame:0];
  NSAssert(self.currentFrame == 0, @"currentFrame must be zero");  
  
  // Schedule delayed start callback to start audio playback and kick
  // off decode callback cycle.
  
  [self.animatorDecodeTimer invalidate];
  
	self.animatorDecodeTimer = [NSTimer timerWithTimeInterval: 0.01
                                                     target: self
                                                   selector: @selector(_delayedStartAnimator:)
                                                   userInfo: NULL
                                                    repeats: FALSE];

  [[NSRunLoop currentRunLoop] addTimer:self.animatorDecodeTimer forMode:NSDefaultRunLoopMode];

  return;
}

- (void) _setAudioSessionCategory {
  NSError *audioSessionError = nil;
  
  // Define audio session as AVAudioSessionCategoryPlayback, so that audio output is not silenced
  // when the silent switch is set. This is a non-mixing mode, so any audio
  // being played is silenced.
  
  NSString *theCategory = AVAudioSessionCategoryPlayback;
  [[AVAudioSession sharedInstance] setCategory:theCategory error:&audioSessionError];
  
  if (audioSessionError) {
    NSLog(@"%@", [NSString stringWithFormat:@"AVAudioSession.setCategory(%@) error : %ld : %@", theCategory, (long)audioSessionError.code, audioSessionError.localizedDescription]);
  }
}

// Invoke this method to stop the animator and cancel all callbacks.

- (void) stopAnimator
{
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
#ifdef DEBUG_OUTPUT
	if (TRUE) {
		NSLog(@"stopAnimator: ");
	}
#endif

	BOOL wasNeverStarted = FALSE;
  
	if (self.state == STOPPED) {
		// When already stopped, don't generate another AVAnimatorDidStopNotification
		return;
	} else if (self.state == FAILED) {
		return;
	} else if (self.state <= READY) {
		// Play was never started successfully
		wasNeverStarted = TRUE;
	}
  
	// stopAnimator can be invoked in any state, it needs to cleanup
	// any pending callbacks and stop audio playback.
  
	self.state = STOPPED;
	
	[self.animatorPrepTimer invalidate];
	self.animatorPrepTimer = nil;
  
	[self _cleanupReadyToAnimate];
  
	[self.animatorDecodeTimer invalidate];
	self.animatorDecodeTimer = nil;
  
	[self.animatorDisplayTimer invalidate];
	self.animatorDisplayTimer = nil;
  
  if (self.avAudioPlayer) {
    [self.avAudioPlayer stop];
    self.avAudioPlayer.currentTime = 0.0;
  }
  
	self.repeatedFrameCount = 0;
  
	self.prevFrame = nil;
	self.nextFrame = nil;
  
  if (wasNeverStarted == FALSE) {
    // Reset idle timer and delivering the stop notification should only
    // be done if the player was actually started previously.
    
    UIApplication *thisApplication = [UIApplication sharedApplication];
    thisApplication.idleTimerDisabled = NO;
    
    // Send notification to object(s) that regestered interest in the stop action.
    // Note that this stop callback could attach a renderer and call startAnimator,
    // so it is important that this stop notification is only delivered when the
    // media is actually playing.
    
    [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDidStopNotification
                                                        object:self];
  }
  
  // Note that invoking stopAnimator leaves the current frame at the same value,
  // the frame and frame decoder do not automatically rewind.
  
	return;
}

- (BOOL) isAnimatorRunning
{
	return (self.state == ANIMATING);
}

- (BOOL) isInitializing
{
	return (self.state < ANIMATING);
}

- (void) pause
{
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
  if (self.state != ANIMATING) {
    // Ignore since an odd race condition could happen when window is put away or when
    // incoming call triggers this method.
    return;
  }

  // The next decode and display operations need to be canceled so that no additional
  // screen updates happen once pause has been invoked. This is important when the
  // system audio interrupt is the source of the pause action.
  
	[self.animatorDecodeTimer invalidate];
	self.animatorDecodeTimer = nil;
  
	[self.animatorDisplayTimer invalidate];
	self.animatorDisplayTimer = nil;
  
  if (self.avAudioPlayer) {
    [self.avAudioPlayer pause];
  } else {
    // Save the simulated clock time interval when paused
    NSTimeInterval offset;
    if (self.audioSimulatedNowTime == nil) {
      offset = [self.audioSimulatedStartTime timeIntervalSinceNow] * -1.0;
    } else {
      offset = [self.audioSimulatedStartTime timeIntervalSinceDate:self.audioSimulatedNowTime] * -1.0;
    }
    self.pauseTimeInterval = offset;    
  }
  
	self.repeatedFrameCount = 0;
  
	self.state = PAUSED;
  
	// Send notification to object(s) that regestered interest in the pause action
  
	[[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDidPauseNotification
                                                      object:self];
}

- (void) unpause
{
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
  if (self.state != PAUSED) {
    return;
  }
  
	self.state = ANIMATING;
  
  // Reset the start time so that simulated start time = (now - pauseTimeInterval)
  
  if (self.avAudioPlayer) {
    NSTimeInterval offset = self.avAudioPlayer.currentTime;
    self.audioPlayerFallbackStartTime = [NSDate dateWithTimeIntervalSinceNow:-offset];
  } else {
    NSTimeInterval offset = self.pauseTimeInterval;
    NSDate *startBefore = [NSDate dateWithTimeIntervalSinceNow:-offset];
    self.audioPlayerFallbackStartTime = startBefore;
    self.audioSimulatedStartTime = startBefore;
    self.pauseTimeInterval = 0.0;
  }
  
  if (self.decodedSecondFrame == FALSE) {
    // Pause was invoked before the clock started reporting valid times. Unpause and then start over.
    
    [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDidUnpauseNotification
                                                        object:self];

    [self stopAnimator];
    [self startAnimator];
  } else {
    // Schedule a display callback right away, the pause could have have been delivered between a decode
    // and a display operation, so a pending display needs to be done ASAP. If there was no pending
    // display, then the display operation will do nothing.
    
    NSAssert(self.animatorDisplayTimer == nil, @"animatorDisplayTimer not nil");
    
    NSTimeInterval displayDelta = 0.001;
    
    self.animatorDisplayTimer = [NSTimer timerWithTimeInterval: displayDelta
                                                        target: self
                                                      selector: @selector(_animatorDisplayFrameCallback:)
                                                      userInfo: NULL
                                                       repeats: FALSE];
    
    [[NSRunLoop currentRunLoop] addTimer: self.animatorDisplayTimer forMode: NSDefaultRunLoopMode];  
    
    // Schedule a decode operation
    
    NSAssert(self.animatorDecodeTimer == nil, @"animatorDecodeTimer not nil");
    
    self.animatorDecodeTimer = [NSTimer timerWithTimeInterval: self.animatorDecodeTimerInterval
                                                       target: self
                                                     selector: @selector(_animatorDecodeFrameCallback:)
                                                     userInfo: NULL
                                                      repeats: FALSE];
    
    [[NSRunLoop currentRunLoop] addTimer: self.animatorDecodeTimer forMode: NSDefaultRunLoopMode];
    
    // Kick off the audio clock
    
    if (self.avAudioPlayer) {
      [self.avAudioPlayer prepareToPlay];
      [self.avAudioPlayer play];
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDidUnpauseNotification
                                                        object:self];
  }
}

- (void) rewind
{
	[self stopAnimator];
  self.currentFrame = -1;
  [self.frameDecoder rewind];
}

- (void) doneAnimator
{
	[self stopAnimator];
  
	// Send notification to object(s) that regestered interest in the done animating action
  
	[[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDoneNotification
                                                      object:self];	
}

// Util function that will query the clock time and map that time to a frame
// index. The frame index has an upper bound, it will be reported as
// (self.animatorNumFrames - 2) if the clock time reported is larger
// than the number of valid frames.

- (void) _queryCurrentClockTimeAndCalcFrameNow:(NSTimeInterval*)currentTimePtr
                                   frameNowPtr:(NSUInteger*)frameNowPtr
{
	// Query audio clock time right now
  
	NSTimeInterval currentTime;
  
  if (self->m_avAudioPlayer == nil) {
    // Note that audioSimulatedStartTime could be nil when testing and the [self showFrame]
    // method is invoked to display the initial keyframe. In this case, it is fine to
    // just report 0.0 as the current time.

    if (reportTimeFromFallbackClock) {
      NSAssert(self.audioPlayerFallbackStartTime, @"audioPlayerFallbackStartTime");
      if (self.audioPlayerFallbackNowTime == nil) {
        currentTime = [self.audioPlayerFallbackStartTime timeIntervalSinceNow] * -1.0;
      } else {
        currentTime = [self.audioPlayerFallbackStartTime timeIntervalSinceDate:self.audioPlayerFallbackNowTime] * -1.0;
      }
    } else if (self.audioSimulatedNowTime == nil) {
      currentTime = [self.audioSimulatedStartTime timeIntervalSinceNow] * -1.0;
    } else {
      NSAssert(self.audioSimulatedStartTime, @"audioSimulatedStartTime");
      currentTime = [self.audioSimulatedStartTime timeIntervalSinceDate:self.audioSimulatedNowTime] * -1.0;
    }
  } else {
    if (reportTimeFromFallbackClock) {
      NSAssert(self.audioPlayerFallbackStartTime, @"audioPlayerFallbackStartTime");
      currentTime = [self.audioPlayerFallbackStartTime timeIntervalSinceNow] * -1.0;
    } else {
      currentTime = self.avAudioPlayer.currentTime;
    }
  }
  
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
  
  if (isnan(currentTime)) {
    assert(0);
  }
  
	if (currentTime <= 0.0) {
		currentTime = 0.0;
		frameNow = 0;
	} else if (currentTime <= self.animatorFrameDuration) {
		frameNow = 0;
	} else if (currentTime > self.animatorMaxClockTime) {
		frameNow = self.animatorNumFrames - 1 - 1;
	} else {
		frameNow = (NSUInteger) (currentTime / self.animatorFrameDuration);
    
		// Check for the very tricky case where the currentTime
		// is very close to the frame interval time. A floating
		// point value that is very close to the frame interval
		// should not be truncated.
    
		NSTimeInterval plusOneTime = (frameNow + 1) * self.animatorFrameDuration;
		NSAssert(currentTime <= plusOneTime, @"currentTime can't be larger than plusOneTime");
		NSTimeInterval plusOneDelta = (plusOneTime - currentTime);
    
		if (plusOneDelta < (self.animatorFrameDuration / 100.0)) {
			frameNow++;
		}
    
		NSAssert(frameNow <= (self.animatorNumFrames - 1 - 1), @"frameNow larger than second to last frame");
	}
  
	*frameNowPtr = frameNow;
	*currentTimePtr = currentTime;
}

// This callback is invoked as the animator begins. The first
// frame or two need to sync to the audio clock before recurring
// callbacks can be scheduled to decode and paint.

- (void) _animatorDecodeInitialFrameCallback: (NSTimer *)timer {
	assert(self.state == ANIMATING);
  
	// Audio clock time right now
  
	NSTimeInterval currentTime;
	NSUInteger frameNow;
  
	[self _queryCurrentClockTimeAndCalcFrameNow:&currentTime frameNowPtr:&frameNow];	
  
#ifdef DEBUG_OUTPUT
	if (TRUE) {
		NSLog(@"%@%@%f", @"_animatorDecodeInitialFrameCallback: ",
          @"\tcurrentTime: ", currentTime);
	}
#endif	
    
  float aboutHalf = (self.animatorFrameDuration / 2.0);
  aboutHalf -= aboutHalf / 20.0f;
  
	if (currentTime < aboutHalf) {
		// Ignore reported times until they are at least half way to the
		// first frame time. The audio could take a moment to start and it
		// could report a number of zero or less than zero times. Keep
		// scheduling a non-repeating call to _animatorDecodeFrameCallback
		// until the audio clock is actually running. Keep track of how
    // many times this method has been invoked to avoid getting stuck
    // in a loop if the clock never reports non-zero times.
    
    self.repeatedFrameCount = self.repeatedFrameCount + 1;
    
    if (self.repeatedFrameCount >= REPEATED_FRAME_DONE_COUNT) {
      NSLog(@"%@", [NSString stringWithFormat:@"doneAnimator because audio time not progressing in initial frame"]);
      
      [self doneAnimator];
      return;
    } else if (self.repeatedFrameCount >= REPEATED_FRAME_WARN_COUNT) {
      // Audio clock has stopped reporting progression of time
      NSLog(@"%@", [NSString stringWithFormat:@"audio time not progressing: %f", currentTime]);
    }
    
		if (self.animatorDecodeTimer != nil) {
			[self.animatorDecodeTimer invalidate];
			//self.animatorDecodeTimer = nil;
		}
    
		self.animatorDecodeTimer = [NSTimer timerWithTimeInterval: self.animatorDecodeTimerInterval
                                                        target: self
                                                      selector: @selector(_animatorDecodeInitialFrameCallback:)
                                                      userInfo: NULL
                                                       repeats: FALSE];
    
		[[NSRunLoop currentRunLoop] addTimer: self.animatorDecodeTimer forMode: NSDefaultRunLoopMode];
	} else {
		// Reported time is now at least half way to the second frame, so
		// we are ready to schedule recurring callbacks. Invoking the
		// decode frame callback will setup the next frame and
		// schedule the callbacks.
    
    self.decodedSecondFrame = TRUE;
    self.ignoreRepeatedFirstFrameReport = TRUE;    
    self.repeatedFrameCount = 0;
    
    // Sync the fallback clock time to the audio clock time.
    
    if (self.avAudioPlayer != nil) {
      NSTimeInterval offset = currentTime * -1.0;
      NSDate *adjStartTime = [NSDate dateWithTimeIntervalSinceNow:offset];
      self.audioPlayerFallbackStartTime = adjStartTime;
//      NSTimeInterval estTime = [self->m_audioSimulatedStartTime timeIntervalSinceNow] * -1.0;
    }
    
		[self _animatorDecodeFrameCallback:nil];
    
		NSAssert(self.animatorDecodeTimer != nil, @"should have scheduled a decode callback");
	}
}

// Invoked at a time between two frame display times.
// This callback will queue the next display operation
// and it will do the next frame decode operation.
// This method takes care of the case where the decode
// logic is too slow because the next trip to the event
// loop will display the next frame as soon as possible.

- (void) _animatorDecodeFrameCallback: (NSTimer *)timer {
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
  if (self.state != ANIMATING) {
    NSAssert(FALSE, @"state is not ANIMATING in _animatorDecodeFrameCallback : %@", [self description]);
  }
  
	NSTimeInterval currentTime;
	NSUInteger frameNow;
  
	[self _queryCurrentClockTimeAndCalcFrameNow:&currentTime frameNowPtr:&frameNow];	
	
#ifdef DEBUG_OUTPUT
	if (TRUE) {
		NSUInteger secondToLastFrameIndex = self.animatorNumFrames - 1 - 1;
    
		NSTimeInterval timeExpected = (frameNow * self.animatorFrameDuration) +
      self.animatorDecodeTimerInterval;
		NSTimeInterval timeDelta = currentTime - timeExpected;
		NSString *formatted = [NSString stringWithFormat:@"%@%@%d%@%d%@%d%@%@%.4f%@%.4f",
                           @"_animatorDecodeFrameCallback: ",
                           @"\tanimator current frame: ", self.currentFrame,
                           @"\tframeNow: ", frameNow,
                           @" (", secondToLastFrameIndex, @")",
                           @"\tcurrentTime: ", currentTime,
                           @"\tdelta: ", timeDelta
                           ];
		NSLog(@"%@", formatted);
	}
#endif

  // Check that initial time report check has passed by the time we get into decode callbacks.
  
  BOOL decodedSecondFrame = self.decodedSecondFrame;
  NSAssert(decodedSecondFrame, @"decodedSecondFrame");
  
	// If the audio clock is reporting nonsense results, like a
  // zero time after the decode callback has started,
  // then switch over to the fallback clock.
  // This can happen when the recorded audio clip is shorter
  // than the time it takes to display all the frames.
  
	if (frameNow < self.currentFrame) {
    reportTimeFromFallbackClock = TRUE;
    [self _queryCurrentClockTimeAndCalcFrameNow:&currentTime frameNowPtr:&frameNow];
	}
  
	NSUInteger nextFrameIndex = frameNow + 1;
  
	// Figure out which callbacks should be scheduled
  
	BOOL isAudioClockStuck = FALSE;
	BOOL shouldScheduleDisplayCallback = TRUE;
	BOOL shouldScheduleDecodeCallback = TRUE;
	BOOL shouldScheduleLastFrameCallback = FALSE;
  
  if ((self.ignoreRepeatedFirstFrameReport == FALSE) && (frameNow == self.currentFrame)) {
    // The audio clock must be stuck, because there is no change in
		// the frame to display. This is basically a no-op, schedule
		// another frame decode operation but don't schedule a
		// frame display operation. Because the clock is stuck, we
		// don't know exactly when to schedule the callback for
		// based on frameNow, so schedule it one frame duration from now.
    // In the case where this is the first decode callback after the
    // initial frame was shown, record one repeat but don't consider
    // the clock stuck. This repeatedFrameCount will be reset to
    // zero in the next decode callback if time is progressing normally.
    
    isAudioClockStuck = TRUE;
    shouldScheduleDisplayCallback = FALSE;
    self.repeatedFrameCount = self.repeatedFrameCount + 1;
  } else {
    self.repeatedFrameCount = 0;
  }
  
  // The decode callback should ignore the repeated initial frame once.
  
  self.ignoreRepeatedFirstFrameReport = FALSE;    
  
  self.currentFrame = frameNow;
  
  if (self.repeatedFrameCount >= REPEATED_FRAME_DONE_COUNT) {
    NSLog(@"%@", [NSString stringWithFormat:@"doneAnimator because audio time not progressing"]);
    
    [self doneAnimator];
    return;
  } else if (self.repeatedFrameCount >= REPEATED_FRAME_WARN_COUNT) {
    // Audio clock has stopped reporting progression of time
    NSLog(@"%@", [NSString stringWithFormat:@"audio time not progressing: %f", currentTime]);
  }
  
	// Schedule the next frame display callback. In the case where the decode
	// operation takes longer than the time until the frame interval, the
	// display operation will be done as soon as the decode is over.	
  
	NSTimeInterval nextFrameExpectedTime;
	NSTimeInterval delta;
  
	if (shouldScheduleDisplayCallback) {
    if (isAudioClockStuck != FALSE) {
      NSAssert(FALSE, @"isAudioClockStuck is FALSE");
    }
    
		nextFrameExpectedTime = (nextFrameIndex * self.animatorFrameDuration);
		delta = nextFrameExpectedTime - currentTime;
    //if (delta <= 0.0) {
    //  NSAssert(FALSE, @"display delta is not a positive number");
    //}
    if (delta < 0.001) {
      // Display frame right away when running behind schedule.
      delta = 0.001;
    }
    
		if (self.animatorDisplayTimer != nil) {
			[self.animatorDisplayTimer invalidate];
			//self.animatorDisplayTimer = nil;
		}
    
		self.animatorDisplayTimer = [NSTimer timerWithTimeInterval: delta
                                                         target: self
                                                       selector: @selector(_animatorDisplayFrameCallback:)
                                                       userInfo: NULL
                                                        repeats: FALSE];
    
		[[NSRunLoop currentRunLoop] addTimer: self.animatorDisplayTimer forMode: NSDefaultRunLoopMode];			
	}
  
	// Schedule the next frame decode operation. Figure out when the
	// decode event should be invoked based on the clock time. This
	// logic will automatically sync the decode operation to the
	// audio clock each time this method is invoked. If the clock
	// is stuck, just take care of this in the next callback.
  
	if (/*!isAudioClockStuck*/ 1) {
		NSUInteger secondToLastFrameIndex = self.animatorNumFrames - 1 - 1;
    
		if (frameNow == secondToLastFrameIndex) {
			// When on the second to last frame, we should schedule
			// an event that puts away the last frame at the end
			// of the frame display interval.
      
			shouldScheduleDecodeCallback = FALSE;
			shouldScheduleLastFrameCallback = TRUE;

      self.decodedLastFrame = TRUE;
		}			
	}
  
	if (shouldScheduleDecodeCallback || shouldScheduleLastFrameCallback) {
		if (isAudioClockStuck) {
			delta = self.animatorFrameDuration;
		} else if (shouldScheduleLastFrameCallback) {
			nextFrameExpectedTime = ((nextFrameIndex + 1) * self.animatorFrameDuration);
			delta = nextFrameExpectedTime - currentTime;
		} else {
			nextFrameExpectedTime = (nextFrameIndex * self.animatorFrameDuration) + self.animatorDecodeTimerInterval;
			delta = nextFrameExpectedTime - currentTime;
		}
    //if (delta <= 0.0) {
    //  NSAssert(FALSE, @"decode delta is not a positive number");
    //}
    if (delta < 0.002) {
      // Decode next frame right away when running behind schedule.
      delta = 0.002;
    }    
    
		if (self.animatorDecodeTimer != nil) {
			[self.animatorDecodeTimer invalidate];
			//self.animatorDecodeTimer = nil;
		}
    
		SEL aSelector = @selector(_animatorDecodeFrameCallback:);
    
		if (shouldScheduleLastFrameCallback) {
			aSelector = @selector(_animatorDoneLastFrameCallback:);
		}
    
		self.animatorDecodeTimer = [NSTimer timerWithTimeInterval: delta
                                                        target: self
                                                      selector: aSelector
                                                      userInfo: NULL
                                                       repeats: FALSE];
    
		[[NSRunLoop currentRunLoop] addTimer: self.animatorDecodeTimer forMode: NSDefaultRunLoopMode];		
	}
  
	// Decode the next frame, this operation could take some time, so it needs to
	// be done after callbacks have been scheduled. If the decode time takes longer
	// than the amount of time before the display callback, then the display
	// callback will be invoked right after the decode operation is finidhed.
  
	if (isAudioClockStuck) {
		// no-op
	} else {
		BOOL wasFrameDecoded = [self _animatorDecodeNextFrame];
    
		if (!wasFrameDecoded) {
			// Cancel the frame display callback at the end of this interval
      
			if (self.animatorDisplayTimer != nil) {
				[self.animatorDisplayTimer invalidate];
				self.animatorDisplayTimer = nil;
			}	
		}
	}
}

// Invoked after the final animator frame is shown on screen, this callback
// will stop the animator and set it off on another loop iteration if
// required. Note that this method is invoked at the exact time the
// last frame in the animation would have stopped displaying. If the
// animation loops and the first frame is shown again right away, then
// it will be displayed as close to the exact time as possible.

- (void) _animatorDoneLastFrameCallback: (NSTimer *)timer {
#ifdef DEBUG_OUTPUT
	NSTimeInterval currentTime;
	NSUInteger frameNow;
  
  [self _queryCurrentClockTimeAndCalcFrameNow:&currentTime frameNowPtr:&frameNow];
  
  NSTimeInterval timeExpected = ((self.currentFrame+2) * self.animatorFrameDuration);
  
  NSTimeInterval timeDelta = currentTime - timeExpected;  
  
  NSLog(@"_animatorDoneLastFrameCallback currentTime: %.4f delta: %.4f", currentTime, timeDelta);
#endif
	[self stopAnimator];
	
  // Done displaying frames, explicitly set self.currentFrame to the last frame

  self.currentFrame = self.animatorNumFrames - 1;    
  
	// Continue to loop animator until loop counter reaches 0
  
	if (self.animatorRepeatCount > 0) {
		self.animatorRepeatCount = self.animatorRepeatCount - 1;
		[self startAnimator];
	} else {
		[self doneAnimator];
	}
}

// Invoked at a time as close to the actual display time
// as possible. This method is designed to have as low a
// latency as possible. This method changes the UIImage
// inside the UIImageView. It does not deallocate the
// currently displayed image or do any other possibly
// resource intensive operations. The run loop is returned
// to as soon as possible so that the frame will be rendered
// as soon as possible.

- (void) _animatorDisplayFrameCallback: (NSTimer *)timer {
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
  if (self->m_state != ANIMATING) {
    NSAssert(FALSE, @"state is not ANIMATING in _animatorDisplayFrameCallback : %@", [self description]);
  }
  
#ifdef DEBUG_OUTPUT
	NSTimeInterval currentTime;
	NSUInteger frameNow;
	
	[self _queryCurrentClockTimeAndCalcFrameNow:&currentTime frameNowPtr:&frameNow];		
  
	if (TRUE) {
		NSTimeInterval timeExpected = ((self.currentFrame+1) * self.animatorFrameDuration);
    
		NSTimeInterval timeDelta = currentTime - timeExpected;
    
		NSString *formatted = [NSString stringWithFormat:@"%@%@%d%@%.4f%@%.4f",
                           @"_animatorDisplayFrameCallback: ",
                           @"\tdisplayFrame: ", self.currentFrame+1,
                           @"\tcurrentTime: ", currentTime,
                           @"\tdelta: ", timeDelta
                           ];
		NSLog(@"%@", formatted);
  }
#endif // DEBUG_OUTPUT
  
	// Display the "next" frame by sending the AVFrame
	// object to the render target. When a duplicate
	// frame is found, the render target should take
	// care to not actually repaint the display.
  
	AVFrame *nextFrame = self.nextFrame;
	NSAssert(nextFrame, @"nextFrame");
  
	id<AVAnimatorMediaRendererProtocol> renderer = self.renderer;
	AVFrame *currentFrame = renderer.AVFrame;
    
	self.prevFrame = currentFrame;
#if defined(__GNUC__) && !defined(__clang__)
	[renderer setAVFrame:nextFrame];
#else
	renderer.AVFrame = nextFrame;
#endif
  
  // Test release of frame now, instead of in next decode callback. Seems
  // that holding until the next decode does not actually release sometimes.
  
  //self.prevFrame = nil;
  
  // FIXME: why hold onto the ref to a frame into the next decode cycle?
  // Could this be causing the need for 3 framebuffers instead of 2?
  
	return;
}

// Display the given animator frame, in the range [0 to N-1]
// where N is the largest frame number. Note that this method
// should only be called when the animator is not running.

- (void) showFrame: (NSInteger) frame {
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
	if ((frame >= self.animatorNumFrames) || (frame < 0) || frame == self.currentFrame)
		return;
	
  // In the case where the frame decoder can only go forwards, but
  // the frame is smaller than the last decoded frame, we need to
  // rewind the frame decoder before advancing
  
  NSInteger lastDecodedFrame = [self.frameDecoder frameIndex];
  if (frame < lastDecodedFrame) {
    [self.frameDecoder rewind];
  }  
  
	self.currentFrame = frame - 1;
	BOOL decodedFrame = [self _animatorDecodeNextFrame];
	// The first frame is always a keyframe, so assume that the
	// decode always works for the first frame.
	if (frame == 0) {
	  NSAssert(decodedFrame == TRUE, @"_animatorDecodeNextFrame did not decode initial frame");
	}
  // _animatorDisplayFrameCallback expects currentFrame
  // to be set to the frame index just before the one
  // to be displayed, so invoke and then set currentFrame.
  // Note that state must be switched to ANIMATING to
  // avoid an error check in _animatorDisplayFrameCallback.
  AVAnimatorPlayerState state = self.state;
	self.state = ANIMATING;
	[self _animatorDisplayFrameCallback:nil];
  self.state = state;
  self.currentFrame = frame;
  self.prevFrame = nil;
}

// This method is invoked to decode the next frame
// of data and prepare the data to be rendered
// in the image view. In the normal case, the
// next frame is rendered and TRUE is returned.
// If the next frame is an exact duplicate of the
// previous frame, then FALSE is returned to indicate
// that no update is needed for the next frame.

- (BOOL) _animatorDecodeNextFrame {
	NSInteger nextFrameNum = self.currentFrame + 1;
	NSAssert(nextFrameNum >= 0 && nextFrameNum < self.animatorNumFrames, @"nextFrameNum is invalid");
  
	// Deallocate AVFrame/UIImage object for the frame before
	// the currently displayed one. This will drop the
	// provider ref if it is holding the last ref.
	// Note that this should also clear the data
	// provider flag on an associated CGFrameBuffer
	// so that it can be used again.
  
	AVFrame *prevFrame = self.prevFrame;
  
	if (prevFrame != nil) {
/*
		if (prevFrameImage != self.nextFrame) {
			NSAssert(prevFrameImage != self.renderer.image,
               @"self.prevFrame is not the same as current image");
		}
*/
    
    //	int refCount;
    //		refCount = [prevFrameImage retainCount];
    //		NSLog([NSString stringWithFormat:@"refCount before %d", refCount]);
    
		self.prevFrame = nil;
    
    //		if (refCount > 1) {
    //			refCount = [prevFrameImage retainCount];
    //			NSLog([NSString stringWithFormat:@"refCount after %d", refCount]);
    //		} else {
    //			NSLog([NSString stringWithFormat:@"should have been freed"]);			
    //		}
        prevFrame = nil;
	}
  
  // Advance the "current frame" in the movie. In the case where
  // the next frame is exactly the same as the previous frame,
  // then the isDuplicate flag is TRUE.
  
  BOOL wasChanged = FALSE;
  
  @autoreleasepool {
  
  AVFrameDecoder *decoder = self.frameDecoder;
  
  int actualFrameNum = (int) nextFrameNum;
  if (self.reverse) {
    actualFrameNum = (int)self.frameDecoder.numFrames - 1 - (int)nextFrameNum;
    //NSLog(@"reverse : nextFrameNum %d : actualFrameNum %d", (int)nextFrameNum, (int)actualFrameNum);
    
    [decoder rewind];
  } else {
    //NSLog(@"nextFrameNum %d : actualFrameNum %d", (int)nextFrameNum, (int)actualFrameNum);
  }
  
  AVFrame *frame = [decoder advanceToFrame:actualFrameNum];
      
  //NSLog(@"decoded frame %@", frame);
  
  self.nextFrame = frame;
      
  if (frame.isDuplicate == TRUE) {
    wasChanged = FALSE;
  } else {
    wasChanged = TRUE;
  }
  }
  return wasChanged;
}

- (BOOL) hasAudio
{
  return (self.avAudioPlayer != nil);
}

// A media item can only be attached to a renderer that has been
// added to the window system and is ready to animate. So, as
// soon as a renderer is attached, the media item should display
// the initial keyframe. This attach method is invoked from
// a render module or from this module.

- (BOOL) attachToRenderer:(id<AVAnimatorMediaRendererProtocol>)renderer
{
  NSAssert(renderer, @"renderer can't be nil");
  self.renderer = renderer;
  
  // If media load failed previously, then a renderer can't be attached now
  
  if (self.state == FAILED) {
    [self.renderer mediaAttached:FALSE];
    self.renderer = nil;
    return FALSE;
  }
  
  // If the media is still loading, then we are not ready to attach
  // to the renderer just yet. This method will be invoked again
  // when the loading process is complete.
  
  if (self.isReadyToAnimate == FALSE) {
    return TRUE;
  }
  
  // Attempt to allocate decode resources, if these resources
  // can't be allocated then the attach will not be successful.
  
  BOOL worked = [self.frameDecoder allocateDecodeResources];
  
  if (worked) {
    // Allocated resources and ready to begin playback, signal the
    // renderer that the media was loaded successfully. In the
    // case where attach is called while loading, the loading process
    // will fail if this attach fails.
    
    [self.renderer mediaAttached:TRUE];
    [self showFrame:0];
    NSAssert(self.currentFrame == 0, @"currentFrame");
  } else {
    [self.renderer mediaAttached:FALSE];
    self.renderer = nil;
  }
  
  return worked;
}

- (void) detachFromRenderer:(id<AVAnimatorMediaRendererProtocol>)renderer copyFinalFrame:(BOOL)copyFinalFrame
{
  NSAssert(renderer, @"renderer can't be nil");

  [self stopAnimator];

  // If copyFinalFrame is true, then the media object is being detached and it will not be
  // replaced with another media object right away. The OS might be putting the app into
  // the background and the view will need to retain the same visual data so that the
  // animations will look correct. Make a copy of the buffer to ensure that the original
  // frame buffer is released. In the case where the original frame buffer is part of
  // a large memory mapped region, this logic will make sure that the large memory map
  // will be released while the app is in the background.
  // Note that duplicateCurrentFrame could return nil.

  AVFrame *resultFrame = nil;
  
  if (copyFinalFrame) {
    resultFrame = [self.frameDecoder duplicateCurrentFrame];
  }
#if defined(__GNUC__) && !defined(__clang__)
  [self.renderer setAVFrame:resultFrame];
#else
  self.renderer.AVFrame = resultFrame;
#endif
  
  self.renderer = nil;
  
  self.prevFrame = nil;
  self.nextFrame = nil;
  
  // implicitly rewind the state of this media object after it is detached from the renderer.

  [self rewind];
  
  // The view and the media objects should have dropped all references to frame buffer objects now.
  
  [self.frameDecoder releaseDecodeResources];
}

- (NSString*) description
{
  NSString *stateStr;
  
  AVAnimatorPlayerState state = self.state;
  switch (state) {
    case ALLOCATED:
      stateStr = @"ALLOCATED";
      break;
    case LOADED:
      stateStr = @"LOADED";
      break;
    case FAILED:
      stateStr = @"FAILED";
      break;
    case PREPPING:
      stateStr = @"PREPPING";
      break;
    case READY:
      stateStr = @"READY";
      break;
    case ANIMATING:
      stateStr = @"ANIMATING";
      break;
    case STOPPED:
      stateStr = @"STOPPED";
      break;
    case PAUSED:
      stateStr = @"PAUSED";
      break;
    default:
      NSAssert(FALSE, @"unmatched state %d", state);
  }
  
  return [NSString stringWithFormat:@"AVAnimatorMedia %p, state %@, loader %@, decoder %@",
          self,
          stateStr,
          self.resourceLoader, self.frameDecoder];
}

@end
