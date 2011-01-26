//
//  AVAnimatorViewTests.m
//
//  Created by Moses DeJong on 1/8/11.
//
//  License terms defined in License.txt.

#import "RegressionTests.h"

#import "AVAnimatorView.h"
#include "AVAnimatorViewPrivate.h"

#import "AVAppResourceLoader.h"
#import "AVQTAnimationFrameDecoder.h"

#import "AVPNGFrameDecoder.h"

@interface AVAnimatorViewTests : NSObject {}
@end

#define REPEATED_FRAME_WARN_COUNT 10
#define REPEATED_FRAME_DONE_COUNT 20

// The methods named test* will be automatically invoked by the RegressionTests harness.

@implementation AVAnimatorViewTests

// This test checks various clock related issues.

+ (void) testClockReports
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Use phony res loader, will load PNG frames from resources later
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
	animatorView.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVPNGFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVPNGFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs cacheDecodedImages:TRUE];
	animatorView.frameDecoder = frameDecoder;  

  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  animatorView.animatorFrameDuration = 1.0;

  animatorView.animatorRepeatCount = 2;

  // Check that view is loaded into window
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");  
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 480.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 320.0, @"renderSize.height");
  
  // Wait until initial keyframe of data is loaded.
  
  NSAssert(animatorView.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  // animator will use simulated time, since no audio clock
  // but it won't be used until startAnimator is invoked.
  
  NSAssert(animatorView.audioSimulatedStartTime == nil, @"audioSimulatedStartTime");
  
  // Now start the animator and then cancel any pending
  // timer callbacks so that we can explicitly deliver
  // timing events with specific timings.
  
  [animatorView startAnimator];
  
  NSAssert(animatorView.state == ANIMATING, @"ANIMATING");
  
  // Check number of frames and total expected animation time
  
  NSAssert(animatorView.animatorNumFrames == 5, @"animatorNumFrames");
  
  NSAssert(animatorView.animatorDecodeTimerInterval == 1.0/4.0, @"animatorDecodeTimerInterval");
  
  // This is the time that the second to last frame will begin to display.
  
  NSAssert(animatorView.animatorMaxClockTime == ((5.0 - 1.0) - 1.0/10), @"animatorDecodeTimerInterval");    
  
  // Cancel decode timer, it would have invoked _delayedStartAnimator
  // but we want to explicitly invoke this method with specific test times.
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  
  /*
  
  // Time, 5 frames
  
  frame = 1
  index = 0
  0.0 -> 1.0
   
  frame = 2
  index = 1
  1.0 -> 2.0

  frame = 3
  index = 2
  2.0 -> 3.0

  frame = 4
  index = 3
  3.0 -> 4.0
   
  frame = 5
  index = 4
  4.0 -> 5.0
  
  maxTime = (5.0 - 1.0) - (1.0/10) = 3.9
  
  */

  // Simulate a zero or possibly negative time, reports time as 0.0 and frame zero
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:-0.1 sinceDate:animatorView.audioSimulatedStartTime];
  
  [animatorView _animatorDecodeInitialFrameCallback:nil];
  
  // Decode timer should have been set again, ignore it again
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer == nil, @"animatorDisplayTimer");

  // Frame index should not have advanced

  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.decodedSecondFrame == FALSE, @"decodedSecondFrame");
  
  // Report a zero time

  animatorView.audioSimulatedNowTime = [NSDate date];
  animatorView.audioSimulatedStartTime = animatorView.audioSimulatedNowTime;
  [animatorView _animatorDecodeInitialFrameCallback:nil];
  
  // Decode timer should have been set again, ignore it again
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer == nil, @"animatorDisplayTimer");

  // Frame index should not have advanced
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.decodedSecondFrame == FALSE, @"decodedSecondFrame");
  
  // Generate a time delta that is very close to the initial decode interval (0.5 sec)
  // but just a little small than the interval. Does not advance the frame.

  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.49 sinceDate:animatorView.audioSimulatedStartTime];

  [animatorView _animatorDecodeInitialFrameCallback:nil];
  
  // Decode timer should have been set again, ignore it again
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer == nil, @"animatorDisplayTimer");
  
  // Frame index should not have advanced
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.decodedSecondFrame == FALSE, @"decodedSecondFrame");
  
  // At this point, report a time of 0.5 so that the first call to
  // _animatorDecodeFrameCallback will be made. This will decode frame 2 (index 1).
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.50 sinceDate:animatorView.audioSimulatedStartTime];
  
  [animatorView _animatorDecodeInitialFrameCallback:nil];  
  
  // Both a decode and a display timer should have been set
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [animatorView.animatorDisplayTimer invalidate];
  animatorView.animatorDisplayTimer = nil;
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.decodedSecondFrame == TRUE, @"decodedSecondFrame");
  
  // Invoke the display timer for the second frame (index 1), this will change the image,
  // the date logic makes the logging output correct.
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:1.0 sinceDate:animatorView.audioSimulatedStartTime];
  
  UIImage *imgBefore = animatorView.image;  
  [animatorView _animatorDisplayFrameCallback:nil];
  UIImage *imgAfter = animatorView.image;
  
  NSAssert(imgBefore != imgAfter, @"image not changed by display callback");  
  
  // Invoke the frame decode logic right at the time it thinks it will be called

  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:1.25 sinceDate:animatorView.audioSimulatedStartTime];
  [animatorView _animatorDecodeFrameCallback:nil];

  // The call above should have decoded the next frame (frame 3) at index 2
  // and scheduled a decode and display callback.
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [animatorView.animatorDisplayTimer invalidate];
  animatorView.animatorDisplayTimer = nil;
  
  NSAssert(animatorView.currentFrame == 1, @"currentFrame");
  
  // Test repeatedFrameCount logic, if the same time is reported more than
  // once then this repeatedFrameCount counter is incremented. The same
  // reported time is used again so that the current frame is repeated.
  
  NSAssert(animatorView.repeatedFrameCount == 0, @"repeatedFrameCount");
  
  [animatorView _animatorDecodeFrameCallback:nil];
  
  NSAssert(animatorView.currentFrame == 1, @"currentFrame");
  NSAssert(animatorView.repeatedFrameCount == 1, @"repeatedFrameCount");
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  
  // Display timer not set when repeated frame is found
  NSAssert(animatorView.animatorDisplayTimer == nil, @"animatorDisplayTimer");  
  
  // Report a time of 2.5, which is half way between frames 3 and 4.
  // This will decode frame 4 (index 3) and schedule another pair
  // of callbacks.
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:2.5 sinceDate:animatorView.audioSimulatedStartTime];
  [animatorView _animatorDecodeFrameCallback:nil];
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [animatorView.animatorDisplayTimer invalidate];
  animatorView.animatorDisplayTimer = nil;
  
  NSAssert(animatorView.currentFrame == 2, @"currentFrame");

  // Report a time of 3.25, between frames 4 and 5.
  // This will decode frame 5 (index 4) which is the
  // final frame of the animation. This final frame
  // will display for a second and then the animation
  // will end.
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:3.5 sinceDate:animatorView.audioSimulatedStartTime];
  [animatorView _animatorDecodeFrameCallback:nil];
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [animatorView.animatorDisplayTimer invalidate];
  animatorView.animatorDisplayTimer = nil;
  
  NSAssert(animatorView.currentFrame == 3, @"currentFrame");
  NSAssert(animatorView.decodedLastFrame == TRUE, @"decodedLastFrame");
  
  // stop and then start animation again, then advance to second frame.

  [animatorView stopAnimator];
  [animatorView startAnimator];

  // At this point, report a time of 0.5 so that the first call to
  // _animatorDecodeFrameCallback will be made. This will decode frame 2 (index 1).
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.50 sinceDate:animatorView.audioSimulatedStartTime];
  
  [animatorView _animatorDecodeInitialFrameCallback:nil];  
  
  // Both a decode and a display timer should have been set
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [animatorView.animatorDisplayTimer invalidate];
  animatorView.animatorDisplayTimer = nil;
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.decodedSecondFrame == TRUE, @"decodedSecondFrame");
  
  // Report a time after the max time, so that the last frame
  // will be displayed.
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:5.50 sinceDate:animatorView.audioSimulatedStartTime];
  
  [animatorView _animatorDecodeFrameCallback:nil];
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [animatorView.animatorDisplayTimer invalidate];
  animatorView.animatorDisplayTimer = nil;
  
  NSAssert(animatorView.currentFrame == 3, @"currentFrame");
  NSAssert(animatorView.decodedLastFrame == TRUE, @"decodedLastFrame");  
  
  // Start another animation cycle
  
  [animatorView stopAnimator];
  [animatorView startAnimator];
  
  NSAssert(animatorView.decodedSecondFrame == FALSE, @"decodedSecondFrame");
  NSAssert(animatorView.decodedLastFrame == FALSE, @"decodedLastFrame");
  
  // At this point, report a time of 0.5 so that the first call to
  // _animatorDecodeFrameCallback will be made. This will decode frame 2 (index 1).
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.5 sinceDate:animatorView.audioSimulatedStartTime];
  
  [animatorView _animatorDecodeInitialFrameCallback:nil];  
  
  // Both a decode and a display timer should have been set
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [animatorView.animatorDisplayTimer invalidate];
  animatorView.animatorDisplayTimer = nil;
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.decodedSecondFrame == TRUE, @"decodedSecondFrame");
  
  // Invoke the frame decode logic right at the time it thinks it will be called
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:1.25 sinceDate:animatorView.audioSimulatedStartTime];
  [animatorView _animatorDecodeFrameCallback:nil];
  
  // The call above should have decoded the next frame (frame 3) at index 2
  // and scheduled a decode and display callback.
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [animatorView.animatorDisplayTimer invalidate];
  animatorView.animatorDisplayTimer = nil;
  
  NSAssert(animatorView.currentFrame == 1, @"currentFrame");

  // Report a time of 0.0, this could happen if the clock implementation
  // reports 0.0 once it gets to the end of the audio clip.

  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = animatorView.audioSimulatedStartTime;
  [animatorView _animatorDecodeFrameCallback:nil];  
  
  NSAssert(animatorView.decodedLastFrame == TRUE, @"decodedLastFrame");
  
  [animatorView stopAnimator];
  
  return;
}

// This test case checks a weird condition where the audio clock starts
// but then never begins to report a non-zero time. If this were to
// happen, the animation would be stopped after a number of retries.

+ (void) testClockInitialTimeDoesNotStart
{
  id appDelegate = [[UIApplication sharedApplication] delegate];	
  UIWindow *window = [appDelegate window];
  NSAssert(window, @"window");  
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Use phony res loader, will load PNG frames from resources later
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
  animatorView.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVPNGFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVPNGFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs cacheDecodedImages:TRUE];
  animatorView.frameDecoder = frameDecoder;  
  
  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  animatorView.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  // Wait until initial keyframe of data is loaded.
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // Start the audio clock and then cancel the initial decode callback.

  BOOL isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  [animatorView startAnimator];
  
  isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");

  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer == nil, @"animatorDisplayTimer");

  // Should be at frame zero, with no repeated frames at this point
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.repeatedFrameCount == 0, @"repeatedFrameCount");

  // Report a series of zero times in the initial frame callback
  
  int count = 0;
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = animatorView.audioSimulatedStartTime;
  [animatorView _animatorDecodeInitialFrameCallback:nil];
  count++;

  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.repeatedFrameCount == 1, @"repeatedFrameCount");
  
  int phony = 0;
  
  isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
  
  for ( ; count < REPEATED_FRAME_DONE_COUNT; count++) {
    if (count == (REPEATED_FRAME_DONE_COUNT - 1)) {
      phony = 1;
    }
    
    [animatorView _animatorDecodeInitialFrameCallback:nil];
    
    if (count < (REPEATED_FRAME_DONE_COUNT - 1)) {
      isAnimatorRunning = [animatorView isAnimatorRunning];
      NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
    }
  }
  
  // Timers should be canceled by each invocation of _animatorDecodeInitialFrameCallback
  // and then the final invocation of stopAnimator sets them to nil.
  
  NSAssert(animatorView.animatorDecodeTimer == nil, @"animatorDecodeTimer");
  NSAssert(animatorView.animatorDisplayTimer == nil, @"animatorDisplayTimer");  
  
  // The last invocation should have stopped the animation
  
  isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  return;
}

// This test case checks a condition when the audio clock starts to
// report a zero time after the initial playback has begun. This
// can happen when the audio clip is shorter than the video clip,
// for example.

+ (void) testClockStartsAndThenReportsZeroTime
{
  id appDelegate = [[UIApplication sharedApplication] delegate];	
  UIWindow *window = [appDelegate window];
  NSAssert(window, @"window");  
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Use phony res loader, will load PNG frames from resources later
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
  animatorView.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVPNGFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVPNGFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs cacheDecodedImages:TRUE];
  animatorView.frameDecoder = frameDecoder;  
  
  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  animatorView.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  // Wait until initial keyframe of data is loaded.
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // Start the audio clock and then cancel the initial decode callback.
  
  BOOL isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  [animatorView startAnimator];
  
  isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer == nil, @"animatorDisplayTimer");
  
  // Should be at frame zero, with no repeated frames at this point
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.repeatedFrameCount == 0, @"repeatedFrameCount");
  
  // Report a time that is far enough away that the second frame is decoded.
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.75 sinceDate:animatorView.audioSimulatedStartTime];
  [animatorView _animatorDecodeInitialFrameCallback:nil];
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [animatorView.animatorDecodeTimer invalidate];
  animatorView.animatorDecodeTimer = nil;
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [animatorView.animatorDisplayTimer invalidate];
  animatorView.animatorDisplayTimer = nil;
  
  // The _animatorDecodeFrameCallback function has now been invoked
  // and the second frame has been decoded. Note that the
  // animatorView.currentFrame is always set to the frame on the
  // left of the time interval, so it is still zero at this point.
  
  NSAssert(animatorView.decodedSecondFrame == TRUE, @"decodedSecondFrame");  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.repeatedFrameCount == 0, @"repeatedFrameCount");
  
  // Report a series of zero times to the decode callback.
  
  int count = 0;
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = animatorView.audioSimulatedStartTime;
  [animatorView _animatorDecodeFrameCallback:nil];
  count++;
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.repeatedFrameCount == 1, @"repeatedFrameCount");
  
  int phony = 0;
  
  isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
  
  for ( ; count < REPEATED_FRAME_DONE_COUNT; count++) {
    if (count == (REPEATED_FRAME_DONE_COUNT - 1)) {
      phony = 1;
    }
    
    [animatorView _animatorDecodeFrameCallback:nil];
    
    if (count < (REPEATED_FRAME_DONE_COUNT - 1)) {
      isAnimatorRunning = [animatorView isAnimatorRunning];
      NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
    }
  }
  
  // Timers should be canceled by each invocation of _animatorDecodeInitialFrameCallback
  // and then the final invocation of stopAnimator sets them to nil.
  
  NSAssert(animatorView.animatorDecodeTimer == nil, @"animatorDecodeTimer");
  NSAssert(animatorView.animatorDisplayTimer == nil, @"animatorDisplayTimer");  
  
  // The last invocation should have stopped the animation
  
  isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  return;
}

// This test case starts the clock, decodes the first frame,
// then invokes pause followed by unpause. The unpause
// logic should restart animation where it left off.

+ (void) testPauseThenUnpause
{
  id appDelegate = [[UIApplication sharedApplication] delegate];	
  UIWindow *window = [appDelegate window];
  NSAssert(window, @"window");  
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Use phony res loader, will load PNG frames from resources later
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
  animatorView.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVPNGFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVPNGFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs cacheDecodedImages:TRUE];
  animatorView.frameDecoder = frameDecoder;  
  
  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  animatorView.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  // Wait until initial keyframe of data is loaded.
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // Start the audio clock and then cancel the initial decode callback.
  
  BOOL isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  [animatorView startAnimator];
  
  isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
    
  // Report a time that is far enough away that the second frame is decoded.
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.5 sinceDate:animatorView.audioSimulatedStartTime];
  
  [animatorView _animatorDecodeInitialFrameCallback:nil];
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  // Now report a time in between the second and third frames.
  
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:1.5 sinceDate:animatorView.audioSimulatedStartTime];
  
  [animatorView _animatorDecodeFrameCallback:nil];
  
  NSAssert(animatorView.currentFrame == 1, @"currentFrame");

  NSAssert(animatorView.image != animatorView.nextFrame, @"nextFrame");
  
  // Invoke pause, this should cancel the next decode and display
  
  [animatorView pause];
  
  NSAssert(animatorView.animatorDecodeTimer == nil, @"animatorDecodeTimer");
  NSAssert(animatorView.animatorDisplayTimer == nil, @"animatorDisplayTimer");
  
  NSAssert(animatorView.currentFrame == 1, @"currentFrame");
  
  isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  // Another pause when already paused is a no-op
  
  [animatorView pause];  
  
  // Unpause, this invocation will schedule a display callback right away
  // and also schedule the next decode.

  [animatorView unpause];
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  
  // Another unpause when animating is a no-op
  
  [animatorView unpause];
  
  [animatorView stopAnimator];
  
  return;
}

// This test case invokes pause before the second frame is decoded. In this
// case an unpause action should just start invoke startAnimator instead
// of scheduling a decode and display operation.

+ (void) testPauseThenUnpauseBeforeSecondFrameDecode
{
  id appDelegate = [[UIApplication sharedApplication] delegate];	
  UIWindow *window = [appDelegate window];
  NSAssert(window, @"window");  
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Use phony res loader, will load PNG frames from resources later
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
  animatorView.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVPNGFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVPNGFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVPNGFrameDecoder *frameDecoder = [AVPNGFrameDecoder aVPNGFrameDecoder:URLs cacheDecodedImages:TRUE];
  animatorView.frameDecoder = frameDecoder;  
  
  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  animatorView.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  // Wait until initial keyframe of data is loaded.
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // Start the audio clock and then cancel the initial decode callback.
  
  BOOL isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  [animatorView startAnimator];
  
  isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
  
  // Report a time that is not far enough from the start time to decode the second frame.
  
  animatorView.audioSimulatedStartTime = [NSDate date];
  animatorView.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.25 sinceDate:animatorView.audioSimulatedStartTime];
  
  [animatorView _animatorDecodeInitialFrameCallback:nil];
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  NSAssert(animatorView.decodedSecondFrame == FALSE, @"decodedSecondFrame");
  
  // Invoke pause, this should cancel the next decode and display
  
  [animatorView pause];
  
  NSAssert(animatorView.animatorDecodeTimer == nil, @"animatorDecodeTimer");
  NSAssert(animatorView.animatorDisplayTimer == nil, @"animatorDisplayTimer");
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  isAnimatorRunning = [animatorView isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  // Unpause, this invocation should notice that decodedSecondFrame is false
  // and it should invoke startAnimator.
  
  [animatorView unpause];
  
  NSAssert(animatorView.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  NSAssert(animatorView.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  
  // Go to the event loop so that pending timers have a chance to fire.
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  [animatorView stopAnimator];
  
  return;
}

// This test case invokes advanceToFrame on a MOV frame decoder twice with the
// same index. The second invocation must be a no-op.

+ (void) testAdvanceToSameFrame
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");

  [animatorView showFrame:1];
  
  // Fake out the animatorView logic that checks the current setting of
  // self.currentFrame by explicitly setting the value.

  animatorView.currentFrame = 0;
  
  UIImage *imageBefore = animatorView.image;
  
  [animatorView showFrame:1];

  UIImage *imageAfter = animatorView.image;

  NSAssert(imageBefore == imageAfter, @"image changed");
  
  NSAssert(animatorView.currentFrame == 1, @"currentFrame");
  
  return;
}

// Get a pixel value from an image

+ (void) getPixels16BPP:(CGImageRef)image
                     offset:(int)offset
                    nPixels:(int)nPixels
                  pixelPtr:(void*)pixelPtr
{
  // Query pixel data at a specific pixel offset
  
  CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(image));  
  CFDataGetBytes(pixelData, CFRangeMake(offset, sizeof(uint16_t) * nPixels), (UInt8*)pixelPtr);
  CFRelease(pixelData);
}

+ (void) getPixels32BPP:(CGImageRef)image
                 offset:(int)offset
                nPixels:(int)nPixels
               pixelPtr:(void*)pixelPtr
{
  // Query pixel data at a specific pixel offset
  
  CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(image));
  CFDataGetBytes(pixelData, CFRangeMake(offset, sizeof(uint32_t) * nPixels), (UInt8*)pixelPtr);
  CFRelease(pixelData);
}

// This test checks state transitions related to the first time a view
// is mapped into a window.

+ (void) testAVAnimatorViewMoveToWindow
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  

  // Note that no movie or audio will be loaded since this movie is never played.
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [animatorView willMoveToWindow:nil];

  // A nil window argument should not invoke loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  return;
}  

+ (void) test16BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"Bounce_16BPP_15FPS.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 480.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 320.0, @"renderSize.height");
  
  /*
   // No transform should be defined, but default transform depends on
   // the platform because iOS has a translate and negate transform by default.
   CATransform3D transform = animatorView.layer.transform;
   UIView *defaultView = [[[UIView alloc] initWithFrame:frame] autorelease];
   CATransform3D defaultTransform = defaultView.layer.transform;
   
   //  NSAssert(CATransform3DIsIdentity(transform), @"not identity transform");
   NSAssert(CATransform3DEqualToTransform(transform, defaultTransform), @"not default transform");
   */
  
  // Wait until initial keyframe of data is loaded.
  
  NSAssert(animatorView.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  // Query pixel data at a specific pixel offset
  
  uint16_t pixel;
  
  [self getPixels16BPP:animatorView.image.CGImage
                offset:0
               nPixels:1
              pixelPtr:&pixel];
  
  NSAssert(pixel == 0x0, @"pixel");
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:5.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  return;
}

+ (void) test24BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"Bounce_24BPP_15FPS.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
    
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 480.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 320.0, @"renderSize.height");
  
  /*
  // No transform should be defined, but default transform depends on
  // the platform because iOS has a translate and negate transform by default.
  CATransform3D transform = animatorView.layer.transform;
  UIView *defaultView = [[[UIView alloc] initWithFrame:frame] autorelease];
  CATransform3D defaultTransform = defaultView.layer.transform;

//  NSAssert(CATransform3DIsIdentity(transform), @"not identity transform");
  NSAssert(CATransform3DEqualToTransform(transform, defaultTransform), @"not default transform");
  */
  
  // Wait until initial keyframe of data is loaded.

  NSAssert(animatorView.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed

  NSAssert(animatorView.currentFrame == 0, @"currentFrame");

  NSAssert(animatorView.image != nil, @"image");
  
  // Query pixel data at a specific pixel offset
  
  uint32_t pixel;

  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:1
              pixelPtr:&pixel];
  
  NSAssert(pixel == 0x0, @"pixel");
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:5.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  return;
}

+ (void) test32BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"Bounce_32BPP_15FPS.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 480.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 320.0, @"renderSize.height");
  
  /*
   // No transform should be defined, but default transform depends on
   // the platform because iOS has a translate and negate transform by default.
   CATransform3D transform = animatorView.layer.transform;
   UIView *defaultView = [[[UIView alloc] initWithFrame:frame] autorelease];
   CATransform3D defaultTransform = defaultView.layer.transform;
   
   //  NSAssert(CATransform3DIsIdentity(transform), @"not identity transform");
   NSAssert(CATransform3DEqualToTransform(transform, defaultTransform), @"not default transform");
   */
  
  // Wait until initial keyframe of data is loaded.
  
  NSAssert(animatorView.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  // Query pixel data at a specific pixel offset
  
  uint32_t pixel;
  
  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:1
              pixelPtr:&pixel];
  
  NSAssert(pixel == 0xFF000000, @"pixel");
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:5.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  return;
}

+ (void) testBlackBlue2x2_16BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
    
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  NSAssert(animatorView.prevFrame == nil, @"prev frame not set properly");
  
  uint16_t pixel[4];

  // First frame is all black pixels
  
  [self getPixels16BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x0, @"pixel");  
  NSAssert(pixel[1] == 0x0, @"pixel");  
  NSAssert(pixel[2] == 0x0, @"pixel");  
  NSAssert(pixel[3] == 0x0, @"pixel");
  
  // Second frame is all blue pixels
  
  UIImage *frameBefore = animatorView.image;
  
  [animatorView showFrame:1];
  
  UIImage *frameAfter = animatorView.image;
  
  NSAssert(frameAfter != nil, @"image");
  NSAssert(frameBefore != frameAfter, @"image");
  NSAssert(animatorView.prevFrame == frameBefore, @"prev frame not set properly");

  [self getPixels16BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x1F, @"pixel");  
  NSAssert(pixel[1] == 0x1F, @"pixel");  
  NSAssert(pixel[2] == 0x1F, @"pixel");  
  NSAssert(pixel[3] == 0x1F, @"pixel");  
  
  return;
}

+ (void) testBlackBlue2x2_24BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_24BPP.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x0, @"pixel");  
  NSAssert(pixel[1] == 0x0, @"pixel");  
  NSAssert(pixel[2] == 0x0, @"pixel");  
  NSAssert(pixel[3] == 0x0, @"pixel");
  
  // Second frame is all blue pixels
  
  [animatorView showFrame:1];
  
  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x000000FF, @"pixel");  
  NSAssert(pixel[1] == 0x000000FF, @"pixel");  
  NSAssert(pixel[2] == 0x000000FF, @"pixel");  
  NSAssert(pixel[3] == 0x000000FF, @"pixel");  
  
  return;
}

+ (void) testBlackBlue2x2_32BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_32BPP.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == TRUE, @"hasAlphaChannel");
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0xFF000000, @"pixel");  
  NSAssert(pixel[1] == 0xFF000000, @"pixel");  
  NSAssert(pixel[2] == 0xFF000000, @"pixel");  
  NSAssert(pixel[3] == 0xFF000000, @"pixel");
  
  // Second frame is all blue pixels
  
  [animatorView showFrame:1];
  
  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0xFF0000FF, @"pixel");  
  NSAssert(pixel[1] == 0xFF0000FF, @"pixel");  
  NSAssert(pixel[2] == 0xFF0000FF, @"pixel");  
  NSAssert(pixel[3] == 0xFF0000FF, @"pixel");  
  
  return;
}

// This test case contains 3 frames of 2x2 16 BPP data. The first two frames
// are all black pixels. The 3rd is all blue pixels. The second frame is a no-op
// since the pixels are all the same as the pixels in the first frame.

+ (void) testNopFrame
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_nop.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  NSAssert(animatorView.prevFrame == nil, @"prev frame should be nil");
  
  uint16_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels16BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x0000, @"pixel");  
  NSAssert(pixel[1] == 0x0000, @"pixel");  
  NSAssert(pixel[2] == 0x0000, @"pixel");  
  NSAssert(pixel[3] == 0x0000, @"pixel");
  
  // Second frame is all black pixels, advancing to the second
  // frame is a no-op since no pixels changed as compared to
  // the first frame.

  UIImage *imageBefore = animatorView.image;
  
  [animatorView showFrame:1];

  UIImage *imageAfter = animatorView.image;
  
  NSAssert(imageBefore == imageAfter, @"advancing to 2nd frame changed the image");
  
  NSAssert(animatorView.prevFrame == nil, @"prev frame should be nil");
  
  [self getPixels16BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x0000, @"pixel");  
  NSAssert(pixel[1] == 0x0000, @"pixel");  
  NSAssert(pixel[2] == 0x0000, @"pixel");  
  NSAssert(pixel[3] == 0x0000, @"pixel");

  // Advance to 3rd frame, changes to all blue pixels
  
  imageBefore = animatorView.image;
  
  [animatorView showFrame:2];
  
  imageAfter = animatorView.image;
  
  NSAssert(imageBefore != imageAfter, @"advancing to 3rd frame changed the image");
  
  NSAssert(animatorView.prevFrame == imageBefore, @"prev frame not set");
  
  [self getPixels16BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x1F, @"pixel");  
  NSAssert(pixel[1] == 0x1F, @"pixel");  
  NSAssert(pixel[2] == 0x1F, @"pixel");  
  NSAssert(pixel[3] == 0x1F, @"pixel");  
  
  return;
}

// FIXME: add 32BPP test case where ALPHA pixels are decoded!
// Also, some black and some totally see through.

// Load sweep animation and audio, then run the animation once.

+ (void) testSweepWithAudio
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  NSString *videoResourceName = @"Sweep15FPS_ANI.mov";
  NSString *audioResourceName = @"Sweep15FPS.m4a";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = videoResourceName;
  resLoader.audioFilename = audioResourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = AVAnimator15FPS;
  
  animatorView.animatorRepeatCount = 2;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 480.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 320.0, @"renderSize.height");
  
  // Wait until initial keyframe of data is loaded.
  
  NSAssert(animatorView.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");

  {
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.5];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  // Wait for 2 loops to finish
  
  [animatorView startAnimator];
  
  {
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:30.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  NSAssert(animatorView.state == STOPPED, @"STOPPED");
  
  return;
}

@end
