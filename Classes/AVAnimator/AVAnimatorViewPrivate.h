//
//  AVAnimatorViewPrivate.h
//
//  Created by Moses DeJong on 1/8/11.
//
// This file defines the private members of the AVAnimatorView.
// These fields would typically be used only by the implementation
// of AVAnimatorView, but could be needed for regression tests.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#import <QuartzCore/QuartzCore.h>

#import "AVAnimatorView.h"

// private properties declaration for AVAnimatorView class

@interface AVAnimatorView ()

@property (nonatomic, retain) NSURL *animatorAudioURL;

@property (nonatomic, retain) UIImage *prevFrame;
@property (nonatomic, retain) UIImage *nextFrame;

@property (nonatomic, retain) NSTimer *animatorPrepTimer;
@property (nonatomic, retain) NSTimer *animatorReadyTimer;
@property (nonatomic, retain) NSTimer *animatorDecodeTimer;
@property (nonatomic, retain) NSTimer *animatorDisplayTimer;

// currentFrame is the frame index for the frame on the left
// of a decode time window. When decoding, the frame just
// before the one to be decoded next will be calculated
// from the time and saved as currentFrame. Basically this
// is the index of the frame being displayed "now".
@property (nonatomic, assign) NSUInteger currentFrame;

@property (nonatomic, assign) NSUInteger repeatedFrameCount;

@property (nonatomic, retain) AVAudioPlayer *avAudioPlayer;

// originalAudioDelegate and retainedAudioDelegate are not properties

@property (nonatomic, retain) NSDate *audioSimulatedStartTime;
@property (nonatomic, retain) NSDate *audioSimulatedNowTime;

@property (nonatomic, assign) AVAudioPlayerState state;
@property (nonatomic, assign) NSTimeInterval animatorMaxClockTime;
@property (nonatomic, assign) NSTimeInterval animatorDecodeTimerInterval;
@property (nonatomic, assign) CGSize renderSize;

@property (nonatomic, assign) BOOL isReadyToAnimate;
@property (nonatomic, assign) BOOL startAnimatorWhenReady;

@property (nonatomic, assign) BOOL decodedSecondFrame;
@property (nonatomic, assign) BOOL decodedLastFrame;

// private methods

- (BOOL) _animatorDecodeNextFrame;

- (void) _animatorDecodeInitialFrameCallback: (NSTimer *)timer;

- (void) _animatorDecodeFrameCallback: (NSTimer *)timer;

- (void) _animatorDisplayFrameCallback: (NSTimer *)timer;

-(void) _setAudioSessionCategory;

- (void) rotateToPortrait;

- (void) rotateToLandscape;

- (void) rotateToLandscapeRight;

- (void) rotateToUpsidedown;

@end
