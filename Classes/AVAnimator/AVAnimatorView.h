//
//  AVAnimatorView.h
//
//  Created by Moses DeJong on 3/18/09.
//
//  License terms defined in License.txt.

#import <UIKit/UIKit.h>

#define AVAnimator30FPS (1.0/30)
#define AVAnimator24FPS (1.0/24)
#define AVAnimator15FPS (1.0/15)
#define AVAnimator10FPS (1.0/10)
#define AVAnimator5FPS (1.0/5)

// AVAnimatorPreparedToAnimateNotification is delivered after resources
// have been loaded and the view is ready to animate.

// AVAnimatorDidStartNotification is delivered when an animation starts (once for each loop)
// AVAnimatorDidStopNotification is delivered when an animation stops (once for each loop)

// AVAnimatorDidPauseNotification is deliverd when the animation is paused, for example
// if a call comes in to the iPhone or when the pause button in movie controls is pressed.

// AVAnimatorDidUnpauseNotification is devliered when a pause is undone, so playing agan

// AVAnimatorDoneNotification is invoked when done animating, if a number of loops were
// requested then the done notification is delivered once all the loops have been played.

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
	LOADED = 1,
	PREPPING = 2,
	READY = 3,
	ANIMATING = 4,
	STOPPED = 5,
	PAUSED = 6
} AVAudioPlayerState;

@interface AVAnimatorView : UIImageView {
@public
  
	AVResourceLoader *m_resourceLoader;
	AVFrameDecoder *m_frameDecoder;
  
	NSTimeInterval m_animatorFrameDuration;
	NSUInteger m_animatorNumFrames;
	NSUInteger m_animatorRepeatCount;
	UIImageOrientation m_animatorOrientation;
  
@private
  
	NSURL *m_animatorAudioURL;	
	UIImage *m_prevFrame;
	UIImage *m_nextFrame;
  
	NSTimer *m_animatorPrepTimer;
	NSTimer *m_animatorReadyTimer;
	NSTimer *m_animatorDecodeTimer;
	NSTimer *m_animatorDisplayTimer;
	
	NSUInteger m_currentFrame;
	NSUInteger m_repeatedFrameCount;
  
	AVAudioPlayer *m_avAudioPlayer;
	id m_originalAudioDelegate;
	id m_retainedAudioDelegate;
  NSDate *m_audioSimulatedStartTime;
  NSDate *m_audioSimulatedNowTime;
  
	AVAudioPlayerState m_state;
  
	NSTimeInterval m_animatorMaxClockTime;
	NSTimeInterval m_animatorDecodeTimerInterval;
  
	CGSize m_renderSize;
  
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
  
	// Set to TRUE once the last frame has been decoded
  
	BOOL m_decodedLastFrame;
}

// public properties

@property (nonatomic, retain) AVResourceLoader *resourceLoader;
@property (nonatomic, retain) AVFrameDecoder *frameDecoder;

@property (nonatomic, assign) NSTimeInterval animatorFrameDuration;
@property (nonatomic, assign) NSUInteger animatorNumFrames;
// Be careful not to use animationRepeatCount from the UIImageView super class!
@property (nonatomic, assign) NSUInteger animatorRepeatCount;

// UIImageOrientationUp, UIImageOrientationDown, UIImageOrientationLeft, UIImageOrientationRight
// defaults to UIImageOrientationUp
@property (nonatomic, assign) UIImageOrientation animatorOrientation;

// TRUE when the animator has an audio track. This property is not set until the
// resource loaded is done loading and AVAnimatorPreparedToAnimateNotification
// has been delivered.
@property (nonatomic, readonly) BOOL hasAudio;

// static ctor : create view that has the screen dimensions
+ (AVAnimatorView*) aVAnimatorView;
// static ctor : create view with the given dimensions
+ (AVAnimatorView*) aVAnimatorViewWithFrame:(CGRect)viewFrame;

// Be careful not to invoke startAnimation or startAnimation from the UIImageView super class!
- (void) startAnimator;
- (void) stopAnimator;

- (BOOL) isAnimatorRunning;
- (BOOL) isInitializing;
- (void) doneAnimator;

- (void) pause;
- (void) unpause;
- (void) rewind;

- (void) prepareToAnimate;

// Display the given animator frame, in the range [1 to N]
// where N is the largest frame number. Note that this method
// should only be called when the animator is not running.

- (void) showFrame: (NSInteger) frame;

@end
