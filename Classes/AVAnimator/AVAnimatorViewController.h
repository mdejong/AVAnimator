//
//  AVAnimatorViewController.h
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 3/18/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

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
@class CGFrameBuffer;
@class EasyArchive;
@class MovieArchive;
@class MovieFrameArray;
@class AVFrameDecoder;
@class NSURL;
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

@interface AVAnimatorViewController : UIViewController {

@public

  // FIXME: why would these members be public?
	AVResourceLoader *m_resourceLoader;
	AVFrameDecoder *m_frameDecoder;

	NSTimeInterval animationFrameDuration;

	NSUInteger animationNumFrames;

	NSUInteger animationRepeatCount;

	UIImageOrientation animationOrientation;

	CGRect viewFrame;

@private

	NSURL *m_animationAudioURL;	

	UIImageView *imageView;
	UIImage *prevFrame;
	UIImage *nextFrame;

	NSArray *cgFrameBuffers;

	NSTimer *animationPrepTimer;
	NSTimer *animationReadyTimer;
	NSTimer *animationDecodeTimer;
	NSTimer *animationDisplayTimer;
	
	NSUInteger currentFrame;

	NSUInteger repeatedFrameCount;

	AVAudioPlayer *avAudioPlayer;
	id originalAudioDelegate;
	id retainedAudioDelegate;
  NSDate *m_audioSimulatedStartTime;

	AVAudioPlayerState state;

	NSTimeInterval animationMaxClockTime;
	NSTimeInterval animationDecodeTimerInterval;

	CGSize renderSize;

	// Becomes TRUE the first time the state changes to READY
	// and stays TRUE after that. This flag is needed to handle
	// the case where the player is stopped before it becomes
	// ready to animate. A change from STOPPED to ANIMATING
	// is only valid if the state has been READY already.

	BOOL isReadyToAnimate;

	// Set to TRUE if startAnimating is called before the
	// prepare phase is complete.

	BOOL startAnimatingWhenReady;

	BOOL isViewFrameSet;
}

// public properties

@property (nonatomic, retain) AVResourceLoader *resourceLoader;
@property (nonatomic, retain) AVFrameDecoder *frameDecoder;

@property (nonatomic, assign) NSTimeInterval animationFrameDuration;
@property (nonatomic, readonly) NSUInteger animationNumFrames;
@property (nonatomic, assign) NSUInteger animationRepeatCount;

// User must indicate the orientation of the animation

@property (nonatomic, assign) UIImageOrientation animationOrientation;

// Set viewFrame to define the dimensions of the view that
// will display the animation. By default, this view
// is the size of the whole screen. The dimensions of the
// animation data must match the dimensions of the viewFrame.
// This is tricky because we can't read the dimensions
// from a movie archive file before creating the view,
// so the user has to set the correct view size before
// the view is loaded.

@property (nonatomic, assign) CGRect viewFrame;

// private properties

@property (nonatomic, retain) NSURL *animationAudioURL;

@property (nonatomic, retain) UIImageView *imageView;
@property (nonatomic, retain) UIImage *prevFrame;
@property (nonatomic, retain) UIImage *nextFrame;

@property (nonatomic, assign) NSUInteger currentFrame;

@property (nonatomic, retain) NSTimer *animationPrepTimer;
@property (nonatomic, retain) NSTimer *animationReadyTimer;
@property (nonatomic, retain) NSTimer *animationDecodeTimer;
@property (nonatomic, retain) NSTimer *animationDisplayTimer;

@property (nonatomic, retain) AVAudioPlayer *avAudioPlayer;
@property (nonatomic, retain) NSDate *audioSimulatedStartTime;

@property (nonatomic, copy) NSArray *cgFrameBuffers;

// static ctor
+ (AVAnimatorViewController*) aVAnimatorViewController;

- (void) startAnimating;
- (void) stopAnimating;
- (BOOL) isAnimating;
- (BOOL) isInitializing;
- (void) doneAnimating;

- (void) pause;
- (void) unpause;
- (void) rewind;

- (void) animationShowFrame: (NSInteger) frame;

- (void) rotateToPortrait;

- (void) rotateToLandscape;

- (void) rotateToLandscapeRight;

+ (NSArray*) arrayWithNumberedNames:(NSString*)filenamePrefix
						 rangeStart:(NSInteger)rangeStart
						   rangeEnd:(NSInteger)rangeEnd
					   suffixFormat:(NSString*)suffixFormat;

+ (NSArray*) arrayWithResourcePrefixedURLs:(NSArray*)inNumberedNames;

- (void) prepareToAnimate;

// private methods

- (BOOL) _animationDecodeNextFrame;

- (void) _animationDecodeFrameCallback: (NSTimer *)timer;

- (void) _animationDisplayFrameCallback: (NSTimer *)timer;

-(void) _setAudioSessionCategory;

@end
