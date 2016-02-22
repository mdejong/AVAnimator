//
//  AVAnimatorMedia.h
//
//  Created by Moses DeJong on 3/18/09.
//
//  License terms defined in License.txt.
//
//  This file defines the media object that is rendered to a view
//  via AVAnimatorView or AVAnimatorLayer. The media object handles all the details
//  of frame rate, the current frame, and so on. The view provides
//  a way to render the media in the window system.

#import <UIKit/UIKit.h>

#import "AVAnimatorMediaRendererProtocol.h"

#define AVAnimator30FPS (1.0/30)
#define AVAnimator24FPS (1.0/24)
#define AVAnimator15FPS (1.0/15)
#define AVAnimator10FPS (1.0/10)
#define AVAnimator5FPS (1.0/5)

// AVAnimatorFailedToLoadNotification is delivered after the contents of
// loaded resources are found to be invalid. For example, if a decoder
// expected files to be in a certain format, but they were not. Then
// loading the media object can fail with this notification. This fail
// to load notification could also be delivered if a media object could
// not attach to an associated view.

// AVAnimatorPreparedToAnimateNotification is delivered after resources
// have been loaded and the view is ready to animate.

// AVAnimatorDidStartNotification is delivered when an animation starts (once for each loop)
// AVAnimatorDidStopNotification is delivered when an animation stops (once for each loop)

// AVAnimatorDidPauseNotification is deliverd when the animation is paused, for example
// if a call comes in to the iPhone or when the pause button in movie controls is pressed.

// AVAnimatorDidUnpauseNotification is devliered when a pause is undone, so playing agan

// AVAnimatorDoneNotification is invoked when done animating, if a number of loops were
// requested then the done notification is delivered once all the loops have been played.

#define AVAnimatorFailedToLoadNotification @"AVAnimatorFailedToLoadNotification"
#define AVAnimatorPreparedToAnimateNotification @"AVAnimatorPreparedToAnimateNotification"
#define AVAnimatorDidStartNotification @"AVAnimatorDidStartNotification"
#define AVAnimatorDidStopNotification @"AVAnimatorDidStopNotification"
#define AVAnimatorDidPauseNotification @"AVAnimatorDidPauseNotification"
#define AVAnimatorDidUnpauseNotification @"AVAnimatorDidUnpauseNotification"
#define AVAnimatorDoneNotification @"AVAnimatorDoneNotification"

@class AVAudioPlayer;
@class NSURL;
@class AVFrameDecoder;
@class AVResourceLoader;

typedef enum AVAnimatorPlayerState {
	ALLOCATED = 0,
	LOADED,
	FAILED,
	PREPPING,
	READY,
	ANIMATING,
	STOPPED,
	PAUSED
} AVAnimatorPlayerState;

@interface AVAnimatorMedia : NSObject {
@private

#if __has_feature(objc_arc)
  __unsafe_unretained
#else
#endif // objc_arc
	id<AVAnimatorMediaRendererProtocol> m_renderer;
  
	AVResourceLoader *m_resourceLoader;
	AVFrameDecoder *m_frameDecoder;
  
	NSTimeInterval m_animatorFrameDuration;
	NSUInteger m_animatorNumFrames;
	NSUInteger m_animatorRepeatCount;
  
	NSURL *m_animatorAudioURL;	
	AVFrame *m_prevFrame;
	AVFrame *m_nextFrame;
  
	NSTimer *m_animatorPrepTimer;
	NSTimer *m_animatorReadyTimer;
	NSTimer *m_animatorDecodeTimer;
	NSTimer *m_animatorDisplayTimer;
	
	NSInteger m_currentFrame;
	NSUInteger m_repeatedFrameCount;
  
	AVAudioPlayer *m_avAudioPlayer;
	id m_originalAudioDelegate;
	id m_retainedAudioDelegate;
  NSDate *m_audioSimulatedStartTime;
  NSDate *m_audioSimulatedNowTime;
  NSDate *m_audioPlayerFallbackStartTime;
  NSDate *m_audioPlayerFallbackNowTime;
  
	AVAnimatorPlayerState m_state;
  
  // This time stores an offset from the original start time
  // at the moment the pause command is invoked.
  NSTimeInterval m_pauseTimeInterval;
  
	NSTimeInterval m_animatorMaxClockTime;
	NSTimeInterval m_animatorDecodeTimerInterval;
  
//	CGSize m_renderSize;
    
	// Becomes TRUE the first time the state changes to READY
	// and stays TRUE after that. This flag is needed to handle
	// the case where the player is stopped before it becomes
	// ready to animate. A change from STOPPED to ANIMATING
	// is only valid if the state has been READY already.
  
	BOOL m_isReadyToAnimate;
  
	// Set to TRUE if startAnimator is called after the
	// prepare phase is complete.
  
	BOOL m_startAnimatorWhenReady;
  
	// Set to TRUE once the second frame has been decoded

	BOOL m_decodedSecondFrame;

	// Set to TRUE when decodedSecondFrame becomes TRUE,
	// then set to false during the first decode operation.
  
	BOOL m_ignoreRepeatedFirstFrameReport;
  
	// Set to TRUE once the last frame has been decoded
  
	BOOL m_decodedLastFrame;
  
	// Set to TRUE when the audio clock time reports
	// a zero time after frames have been decoded.
	// This happens when the audio that goes along
	// with an animation is as long as the time
	// needed to display the frames. Clock time
	// is reported in terms of the fallback clock
	// in this case.
  
	BOOL reportTimeFromFallbackClock;
  
	BOOL m_reverse;
}

// public properties

@property (nonatomic, retain) AVResourceLoader *resourceLoader;
@property (nonatomic, retain) AVFrameDecoder *frameDecoder;

@property (nonatomic, assign) NSTimeInterval animatorFrameDuration;
@property (nonatomic, assign) NSUInteger animatorNumFrames;

@property (nonatomic, assign) NSUInteger animatorRepeatCount;

// Set this property to TRUE to play the media backwards.
// Note that the decoder must support random access.

@property (nonatomic, assign) BOOL reverse;

// TRUE when the animator has an audio track. This property is not set until the
// resource loaded is done loading and AVAnimatorPreparedToAnimateNotification
// has been delivered.
@property (nonatomic, readonly) BOOL hasAudio;

// TRUE once the media data has successfully loaded and the media is ready to animate.
// Note that this property could be TRUE even if this media has not been attached
// to a specfic renderer.

@property (nonatomic, assign) BOOL isReadyToAnimate;

// static ctor : create media object in autorelease pool
+ (AVAnimatorMedia*) aVAnimatorMedia;

// Start animating at the initial frame
- (void) startAnimator;
// Stop animating, currentFrame indicates the last rendered frame
- (void) stopAnimator;

- (BOOL) isAnimatorRunning;
- (BOOL) isInitializing;
- (void) doneAnimator;

// Pause animator at the current frame
- (void) pause;
// Restart animator at the current frame
- (void) unpause;
// Rewind the current frame
- (void) rewind;

- (void) prepareToAnimate;

// Display the given animator frame, in the range [1 to N]
// where N is the largest frame number. Note that this method
// should only be called when the animator is not running.

- (void) showFrame: (NSInteger) frame;

@end
