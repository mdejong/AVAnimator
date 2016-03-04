//
//  AVAnimatorMediaPrivate.h
//
//  Created by Moses DeJong on 1/8/11.
//
// This file defines the private members of the AVAnimatorMedia.
// These fields would typically be used only by the implementation
// of AVAnimatorMedia, but could be needed for regression tests.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#import <QuartzCore/QuartzCore.h>

#import "AVAnimatorMedia.h"

// private properties declaration for AVAnimatorMedia class

@interface AVAnimatorMedia ()

@property (nonatomic, assign) id<AVAnimatorMediaRendererProtocol> renderer;

@property (nonatomic,   copy) NSURL *animatorAudioURL;

@property (nonatomic, retain) AVFrame *prevFrame;
@property (nonatomic, retain) AVFrame *nextFrame;

@property (nonatomic, retain) NSTimer *animatorPrepTimer;
@property (nonatomic, retain) NSTimer *animatorReadyTimer;
@property (nonatomic, retain) NSTimer *animatorDecodeTimer;
@property (nonatomic, retain) NSTimer *animatorDisplayTimer;

// currentFrame is the frame index for the frame on the left
// of a decode time window. When decoding, the frame just
// before the one to be decoded next will be calculated
// from the time and saved as currentFrame. Basically this
// is the index of the frame being displayed "now". The
// tricky part is that on init or after a stop, the
// current frame is -1 to indicate that no specific
// frame is being displayed.

@property (nonatomic, assign) NSInteger currentFrame;

@property (nonatomic, assign) NSUInteger repeatedFrameCount;

@property (nonatomic, retain) AVAudioPlayer *avAudioPlayer;

// originalAudioDelegate and retainedAudioDelegate are not properties

@property (nonatomic, retain) NSDate *audioSimulatedStartTime;
@property (nonatomic, retain) NSDate *audioSimulatedNowTime;
@property (nonatomic, retain) NSDate *audioPlayerFallbackStartTime;
@property (nonatomic, retain) NSDate *audioPlayerFallbackNowTime;

@property (nonatomic, assign) AVAnimatorPlayerState state;
@property (nonatomic, assign) NSTimeInterval pauseTimeInterval;
@property (nonatomic, assign) NSTimeInterval animatorMaxClockTime;
@property (nonatomic, assign) NSTimeInterval animatorDecodeTimerInterval;

@property (nonatomic, assign) BOOL startAnimatorWhenReady;

@property (nonatomic, assign) BOOL decodedSecondFrame;
@property (nonatomic, assign) BOOL ignoreRepeatedFirstFrameReport;
@property (nonatomic, assign) BOOL decodedLastFrame;
@property (nonatomic, assign) BOOL reportTimeFromFallbackClock;

// private methods

- (BOOL) _animatorDecodeNextFrame;

- (void) _animatorDecodeInitialFrameCallback: (NSTimer *)timer;

- (void) _animatorDecodeFrameCallback: (NSTimer *)timer;

- (void) _animatorDisplayFrameCallback: (NSTimer *)timer;

-(void) _setAudioSessionCategory;

// These next two method should be invoked from a renderer to signal
// when this media item is attached to and detached from a renderer.

- (BOOL) attachToRenderer:(id<AVAnimatorMediaRendererProtocol>)renderer;

- (void) detachFromRenderer:(id<AVAnimatorMediaRendererProtocol>)renderer copyFinalFrame:(BOOL)copyFinalFrame;

@end
