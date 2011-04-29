//
//  AVAnimatorViewTests.m
//
//  Created by Moses DeJong on 1/8/11.
//
//  License terms defined in License.txt.

#import "RegressionTests.h"

#import "AVAnimatorView.h"
#include "AVAnimatorViewPrivate.h"

#import "AVAnimatorMedia.h"
#import "AVAnimatorMediaPrivate.h"

#import "AVAppResourceLoader.h"
#import "AV7zAppResourceLoader.h"
#import "AV7zQT2MvidResourceLoader.h"

#import "AVQTAnimationFrameDecoder.h"
#import "AVMvidFrameDecoder.h"

#import "AVImageFrameDecoder.h"

#import "AVFileUtil.h"

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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Use phony res loader, will load PNG frames from resources later
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
	media.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVImageFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVImageFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVImageFrameDecoder *frameDecoder = [AVImageFrameDecoder aVImageFrameDecoder:URLs cacheDecodedImages:TRUE];
	media.frameDecoder = frameDecoder;  

  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  media.animatorFrameDuration = 1.0;

  media.animatorRepeatCount = 2;

  // Check that view is loaded into window
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");  
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 480.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 320.0, @"renderSize.height");
  
  // Wait until initial keyframe of data is loaded.
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  // animator will use simulated time, since no audio clock
  // but it won't be used until startAnimator is invoked.
  
  NSAssert(media.audioSimulatedStartTime == nil, @"audioSimulatedStartTime");
  
  // Now start the animator and then cancel any pending
  // timer callbacks so that we can explicitly deliver
  // timing events with specific timings.
  
  [media startAnimator];
  
  NSAssert(media.state == ANIMATING, @"ANIMATING");
  
  // Check number of frames and total expected animation time
  
  NSAssert(media.animatorNumFrames == 5, @"animatorNumFrames");
  
  NSAssert(media.animatorDecodeTimerInterval == 1.0/4.0, @"animatorDecodeTimerInterval");
  
  // This is the time that the second to last frame will begin to display.
  
  NSAssert(media.animatorMaxClockTime == ((5.0 - 1.0) - 1.0/10), @"animatorDecodeTimerInterval");    
  
  // Cancel decode timer, it would have invoked _delayedStartAnimator
  // but we want to explicitly invoke this method with specific test times.
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  
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
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:-0.1 sinceDate:media.audioSimulatedStartTime];
  
  [media _animatorDecodeInitialFrameCallback:nil];
  
  // Decode timer should have been set again, ignore it again
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");

  // Frame index should not have advanced

  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.decodedSecondFrame == FALSE, @"decodedSecondFrame");
  
  // Report a zero time

  media.audioSimulatedNowTime = [NSDate date];
  media.audioSimulatedStartTime = media.audioSimulatedNowTime;
  [media _animatorDecodeInitialFrameCallback:nil];
  
  // Decode timer should have been set again, ignore it again
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");

  // Frame index should not have advanced
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.decodedSecondFrame == FALSE, @"decodedSecondFrame");
  
  // Generate a time delta that is very close to the initial decode interval (0.5 sec)
  // but just a little small than the interval. Does not advance the frame.

  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.49 sinceDate:media.audioSimulatedStartTime];

  [media _animatorDecodeInitialFrameCallback:nil];
  
  // Decode timer should have been set again, ignore it again
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");
  
  // Frame index should not have advanced
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.decodedSecondFrame == FALSE, @"decodedSecondFrame");
  
  // At this point, report a time of 0.5 so that the first call to
  // _animatorDecodeFrameCallback will be made. This will decode frame 2 (index 1).
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.50 sinceDate:media.audioSimulatedStartTime];
  
  [media _animatorDecodeInitialFrameCallback:nil];  
  
  // Both a decode and a display timer should have been set
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [media.animatorDisplayTimer invalidate];
  media.animatorDisplayTimer = nil;
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.decodedSecondFrame == TRUE, @"decodedSecondFrame");
  
  // Invoke the display timer for the second frame (index 1), this will change the image,
  // the date logic makes the logging output correct.
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:1.0 sinceDate:media.audioSimulatedStartTime];
  
  UIImage *imgBefore = animatorView.image;  
  [media _animatorDisplayFrameCallback:nil];
  UIImage *imgAfter = animatorView.image;
  
  NSAssert(imgBefore != imgAfter, @"image not changed by display callback");  
  
  // Invoke the frame decode logic right at the time it thinks it will be called

  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:1.25 sinceDate:media.audioSimulatedStartTime];
  [media _animatorDecodeFrameCallback:nil];

  // The call above should have decoded the next frame (frame 3) at index 2
  // and scheduled a decode and display callback.
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [media.animatorDisplayTimer invalidate];
  media.animatorDisplayTimer = nil;
  
  NSAssert(media.currentFrame == 1, @"currentFrame");
  
  // Test repeatedFrameCount logic, if the same time is reported more than
  // once then this repeatedFrameCount counter is incremented. The same
  // reported time is used again so that the current frame is repeated.
  
  NSAssert(media.repeatedFrameCount == 0, @"repeatedFrameCount");
  
  [media _animatorDecodeFrameCallback:nil];
  
  NSAssert(media.currentFrame == 1, @"currentFrame");
  NSAssert(media.repeatedFrameCount == 1, @"repeatedFrameCount");
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  
  // Display timer not set when repeated frame is found
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");  
  
  // Report a time of 2.5, which is half way between frames 3 and 4.
  // This will decode frame 4 (index 3) and schedule another pair
  // of callbacks.
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:2.5 sinceDate:media.audioSimulatedStartTime];
  [media _animatorDecodeFrameCallback:nil];
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [media.animatorDisplayTimer invalidate];
  media.animatorDisplayTimer = nil;
  
  NSAssert(media.currentFrame == 2, @"currentFrame");

  // Report a time of 3.25, between frames 4 and 5.
  // This will decode frame 5 (index 4) which is the
  // final frame of the animation. This final frame
  // will display for a second and then the animation
  // will end.
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:3.5 sinceDate:media.audioSimulatedStartTime];
  [media _animatorDecodeFrameCallback:nil];
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [media.animatorDisplayTimer invalidate];
  media.animatorDisplayTimer = nil;
  
  NSAssert(media.currentFrame == 3, @"currentFrame");
  NSAssert(media.decodedLastFrame == TRUE, @"decodedLastFrame");
  
  // stop and then start animation again, then advance to second frame.

  [media stopAnimator];
  [media startAnimator];

  // At this point, report a time of 0.5 so that the first call to
  // _animatorDecodeFrameCallback will be made. This will decode frame 2 (index 1).
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.50 sinceDate:media.audioSimulatedStartTime];
  
  [media _animatorDecodeInitialFrameCallback:nil];  
  
  // Both a decode and a display timer should have been set
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [media.animatorDisplayTimer invalidate];
  media.animatorDisplayTimer = nil;
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.decodedSecondFrame == TRUE, @"decodedSecondFrame");
  
  // Report a time after the max time, so that the last frame
  // will be displayed.
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:5.50 sinceDate:media.audioSimulatedStartTime];
  
  [media _animatorDecodeFrameCallback:nil];
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [media.animatorDisplayTimer invalidate];
  media.animatorDisplayTimer = nil;
  
  NSAssert(media.currentFrame == 3, @"currentFrame");
  NSAssert(media.decodedLastFrame == TRUE, @"decodedLastFrame");  
  
  // Start another animation cycle
  
  [media stopAnimator];
  [media startAnimator];
  
  NSAssert(media.decodedSecondFrame == FALSE, @"decodedSecondFrame");
  NSAssert(media.decodedLastFrame == FALSE, @"decodedLastFrame");
  
  // At this point, report a time of 0.5 so that the first call to
  // _animatorDecodeFrameCallback will be made. This will decode frame 2 (index 1).
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.5 sinceDate:media.audioSimulatedStartTime];
  
  [media _animatorDecodeInitialFrameCallback:nil];  
  
  // Both a decode and a display timer should have been set
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [media.animatorDisplayTimer invalidate];
  media.animatorDisplayTimer = nil;
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.decodedSecondFrame == TRUE, @"decodedSecondFrame");
  
  // Invoke the frame decode logic right at the time it thinks it will be called
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:1.25 sinceDate:media.audioSimulatedStartTime];
  [media _animatorDecodeFrameCallback:nil];
  
  // The call above should have decoded the next frame (frame 3) at index 2
  // and scheduled a decode and display callback.
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [media.animatorDisplayTimer invalidate];
  media.animatorDisplayTimer = nil;
  
  NSAssert(media.currentFrame == 1, @"currentFrame");

  // Report a time of 0.0, this could happen if the clock implementation
  // reports 0.0 once it gets to the end of the audio clip.

  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = media.audioSimulatedStartTime;

  // Once the simulated clock is reporting a zero time, the code will
  // use the fallback clock. Provide an end time so that the fallback
  // clock has a delta to work with.

  media.audioPlayerFallbackStartTime = [NSDate date];
  media.audioPlayerFallbackNowTime = [NSDate dateWithTimeIntervalSinceNow:4.5];
  
  [media _animatorDecodeFrameCallback:nil];
  
  NSAssert(media.decodedLastFrame == TRUE, @"decodedLastFrame");
  
  [media stopAnimator];
  
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Use phony res loader, will load PNG frames from resources later
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
  media.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVImageFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVImageFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVImageFrameDecoder *frameDecoder = [AVImageFrameDecoder aVImageFrameDecoder:URLs cacheDecodedImages:TRUE];
  media.frameDecoder = frameDecoder;  
  
  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  media.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Wait until initial keyframe of data is loaded.
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");

  // Initial keyframe should be displayed
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  // Start the audio clock and then cancel the initial decode callback.

  BOOL isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  [media startAnimator];
  
  isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");

  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");

  // Should be at frame zero, with no repeated frames at this point
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.repeatedFrameCount == 0, @"repeatedFrameCount");

  // Report a series of zero times in the initial frame callback
  
  int count = 0;
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = media.audioSimulatedStartTime;
  [media _animatorDecodeInitialFrameCallback:nil];
  count++;

  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.repeatedFrameCount == 1, @"repeatedFrameCount");
  
  int phony = 0;
  
  isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
  
  for ( ; count < REPEATED_FRAME_DONE_COUNT; count++) {
    if (count == (REPEATED_FRAME_DONE_COUNT - 1)) {
      phony++;
    }
    
    [media _animatorDecodeInitialFrameCallback:nil];
    
    if (count < (REPEATED_FRAME_DONE_COUNT - 1)) {
      isAnimatorRunning = [media isAnimatorRunning];
      NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
    }
  }
  
  // Timers should be canceled by each invocation of _animatorDecodeInitialFrameCallback
  // and then the final invocation of stopAnimator sets them to nil.
  
  NSAssert(media.animatorDecodeTimer == nil, @"animatorDecodeTimer");
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");  
  
  // The last invocation should have stopped the animation
  
  isAnimatorRunning = [media isAnimatorRunning];
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Use phony res loader, will load PNG frames from resources later
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
  media.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVImageFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVImageFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVImageFrameDecoder *frameDecoder = [AVImageFrameDecoder aVImageFrameDecoder:URLs cacheDecodedImages:TRUE];
  media.frameDecoder = frameDecoder;  
  
  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  media.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Wait until initial keyframe of data is loaded.
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // Start the audio clock and then cancel the initial decode callback.
  
  BOOL isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  [media startAnimator];
  
  isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");
  
  // Should be at frame zero, with no repeated frames at this point
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.repeatedFrameCount == 0, @"repeatedFrameCount");
  
  // Report a time that is far enough away that the second frame is decoded.
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.75 sinceDate:media.audioSimulatedStartTime];
  [media _animatorDecodeInitialFrameCallback:nil];
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  [media.animatorDecodeTimer invalidate];
  media.animatorDecodeTimer = nil;
  NSAssert(media.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  [media.animatorDisplayTimer invalidate];
  media.animatorDisplayTimer = nil;
  
  // The _animatorDecodeFrameCallback function has now been invoked
  // and the second frame has been decoded. Note that the
  // animatorView.currentFrame is always set to the frame on the
  // left of the time interval, so it is still zero at this point.
  
  NSAssert(media.decodedSecondFrame == TRUE, @"decodedSecondFrame");  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.repeatedFrameCount == 0, @"repeatedFrameCount");
  
  // Report a series of zero times to the decode callback.
  
  int count = 0;
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = media.audioSimulatedStartTime;
  [media _animatorDecodeFrameCallback:nil];
  count++;
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.repeatedFrameCount == 1, @"repeatedFrameCount");
  
  int phony = 0;
  
  isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
  
  for ( ; count < REPEATED_FRAME_DONE_COUNT; count++) {
    if (count == (REPEATED_FRAME_DONE_COUNT - 1)) {
      phony++;
    }
    
    [media _animatorDecodeFrameCallback:nil];
    
    if (count < (REPEATED_FRAME_DONE_COUNT - 1)) {
      isAnimatorRunning = [media isAnimatorRunning];
      NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
    }
  }
  
  // Timers should be canceled by each invocation of _animatorDecodeInitialFrameCallback
  // and then the final invocation of stopAnimator sets them to nil.
  
  NSAssert(media.animatorDecodeTimer == nil, @"animatorDecodeTimer");
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");  
  
  // The last invocation should have stopped the animation
  
  isAnimatorRunning = [media isAnimatorRunning];
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Use phony res loader, will load PNG frames from resources later
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
  media.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVImageFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVImageFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVImageFrameDecoder *frameDecoder = [AVImageFrameDecoder aVImageFrameDecoder:URLs cacheDecodedImages:TRUE];
  media.frameDecoder = frameDecoder;  
  
  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  media.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Wait until initial keyframe of data is loaded.
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // Start the audio clock and then cancel the initial decode callback.
  
  BOOL isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  [media startAnimator];
  
  isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
    
  // Report a time that is far enough away that the second frame is decoded.
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.5 sinceDate:media.audioSimulatedStartTime];
  
  [media _animatorDecodeInitialFrameCallback:nil];
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  // Now report a time in between the second and third frames.
  
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:1.5 sinceDate:media.audioSimulatedStartTime];
  
  [media _animatorDecodeFrameCallback:nil];
  
  NSAssert(media.currentFrame == 1, @"currentFrame");

  NSAssert(animatorView.image != media.nextFrame, @"nextFrame");
  
  // Invoke pause, this should cancel the next decode and display
  
  [media pause];
  
  NSAssert(media.animatorDecodeTimer == nil, @"animatorDecodeTimer");
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");
  
  NSAssert(media.currentFrame == 1, @"currentFrame");
  
  // The pause operation records the clock time when pause was invoked
  NSAssert(media.pauseTimeInterval == 1.5, @"pauseTimeInterval");
  
  isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  // Another pause when already paused is a no-op
  
  [media pause];  
  
  // Unpause, this invocation will schedule a display callback right away
  // and also schedule the next decode.

  [media unpause];
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  NSAssert(media.animatorDisplayTimer != nil, @"animatorDisplayTimer");
  
  // Another unpause when animating is a no-op
  
  [media unpause];
  
  [media stopAnimator];
  
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Use phony res loader, will load PNG frames from resources later
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
  media.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVImageFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVImageFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVImageFrameDecoder *frameDecoder = [AVImageFrameDecoder aVImageFrameDecoder:URLs cacheDecodedImages:TRUE];
  media.frameDecoder = frameDecoder;  
  
  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  media.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Wait until initial keyframe of data is loaded.
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // Start the audio clock and then cancel the initial decode callback.
  
  BOOL isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  [media startAnimator];
  
  isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == TRUE, @"isAnimatorRunning");
  
  // Report a time that is not far enough from the start time to decode the second frame.
  
  media.audioSimulatedStartTime = [NSDate date];
  media.audioSimulatedNowTime = [NSDate dateWithTimeInterval:0.25 sinceDate:media.audioSimulatedStartTime];
  
  [media _animatorDecodeInitialFrameCallback:nil];
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  NSAssert(media.decodedSecondFrame == FALSE, @"decodedSecondFrame");
  
  // Invoke pause, this should cancel the next decode and display
  
  [media pause];
  
  NSAssert(media.animatorDecodeTimer == nil, @"animatorDecodeTimer");
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  // The pause operation records the clock time when pause was invoked
  NSAssert(media.pauseTimeInterval == 0.25, @"pauseTimeInterval");
  
  isAnimatorRunning = [media isAnimatorRunning];
  NSAssert(isAnimatorRunning == FALSE, @"isAnimatorRunning");
  
  // Unpause, this invocation should notice that decodedSecondFrame is false
  // and it should invoke startAnimator.
  
  [media unpause];
  
  // Started over, so display timer should be nil
  
  NSAssert(media.animatorDecodeTimer != nil, @"animatorDecodeTimer");
  NSAssert(media.animatorDisplayTimer == nil, @"animatorDisplayTimer");
  
  // Go to the event loop so that pending timers have a chance to fire.
  // If we don't get a crash in the decode callback, then everything is okay.
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  [media stopAnimator];
  
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(media.currentFrame == 0, @"currentFrame");

  [media showFrame:1];
  
  // Fake out the animatorView logic that checks the current setting of
  // self.currentFrame by explicitly setting the value.

  media.currentFrame = 0;
  
  UIImage *imageBefore = animatorView.image;
  
  [media showFrame:1];

  UIImage *imageAfter = animatorView.image;

  NSAssert(imageBefore == imageAfter, @"image changed");
  
  NSAssert(media.currentFrame == 1, @"currentFrame");
  
  return;
}

// This test checks the implementation of the attachMedia method
// in the AVAnimatorView class. Only a single media item can be
// attached to a rendering view at a time, and only an attached
// media element has resources like allocated framebuffers.

+ (void) testAttachDetachMedia
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 200, 200);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  NSAssert(media.currentFrame == -1, @"currentFrame");
    
  [animatorView attachMedia:nil];
  
  NSAssert(animatorView.media == nil, @"media");
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // The media was not attached on load, so currentFrame is still -1
  
  NSAssert(media.currentFrame == -1, @"currentFrame");  
  
  // The media is now ready, attaching will display the first keyframe.
  
  [animatorView attachMedia:media];
  
  NSAssert(animatorView.media == media, @"media");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  [animatorView attachMedia:nil];
  
  NSAssert(animatorView.media == nil, @"media");

  // Detech from renderer implicity invoked stopAnimator
  
  NSAssert(media.currentFrame == -1, @"currentFrame");
  
  return;
}

// This test uses two different media objects and attaches
// them to the animator view. When attaching a media element,
// the initial keyframe is displayed. The second attach
// should replace the keyframe set in the first attach.

+ (void) testAttachTwoDifferentMedia
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceOneName = @"2x2_black_blue_16BPP.mov";
  NSString *resourceTwoName = @"2x2_black_blue_24BPP.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 200, 200);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media1 = [AVAnimatorMedia aVAnimatorMedia];
  AVAnimatorMedia *media2 = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader1 = [AVAppResourceLoader aVAppResourceLoader];
  resLoader1.movieFilename = resourceOneName;
	media1.resourceLoader = resLoader1;

	AVAppResourceLoader *resLoader2 = [AVAppResourceLoader aVAppResourceLoader];
  resLoader2.movieFilename = resourceTwoName;
	media2.resourceLoader = resLoader2;  
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder1 = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media1.frameDecoder = frameDecoder1;

  AVQTAnimationFrameDecoder *frameDecoder2 = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media2.frameDecoder = frameDecoder2;
  
  media1.animatorFrameDuration = 1.0;
  media2.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  [media1 prepareToAnimate];
  [media2 prepareToAnimate];
  
  BOOL worked1 = [RegressionTests waitUntilTrue:media1
                                       selector:@selector(isReadyToAnimate)
                                    maxWaitTime:10.0];
  NSAssert(worked1, @"worked");
  
  BOOL worked2 = [RegressionTests waitUntilTrue:media2
                                       selector:@selector(isReadyToAnimate)
                                    maxWaitTime:10.0];
  NSAssert(worked2, @"worked");  
  
  // The media was not attached on load, so currentFrame is still -1
  
  NSAssert(media1.currentFrame == -1, @"currentFrame");
  NSAssert(media2.currentFrame == -1, @"currentFrame");  
  
  // Both frame decoders are in the init state
  
  NSAssert([media1.frameDecoder isResourceUsageLimit] == TRUE, @"isResourceUsageLimit");
  NSAssert([media2.frameDecoder isResourceUsageLimit] == TRUE, @"isResourceUsageLimit");
  
  // The media is now ready, attaching media1 will display the first keyframe in the view.
  
  UIImage *beforeImage;
  UIImage *afterImage;
  
  beforeImage = animatorView.image;
  
  [animatorView attachMedia:media1];
  
  NSAssert(animatorView.media == media1, @"media");
  
  NSAssert([media1.frameDecoder isResourceUsageLimit] == FALSE, @"isResourceUsageLimit");
  NSAssert([media2.frameDecoder isResourceUsageLimit] == TRUE, @"isResourceUsageLimit");  

  afterImage = animatorView.image;
  
  NSAssert(beforeImage != afterImage, @"image");
  
  NSAssert(media1.currentFrame == 0, @"currentFrame");
  
  // Attach the second media object. Resources associated
  // with the first media element are deallocated and
  // those needed for the second would be allocated on demand.
  
  beforeImage = animatorView.image;
  
  [animatorView attachMedia:media2];

  NSAssert([media1.frameDecoder isResourceUsageLimit] == TRUE, @"isResourceUsageLimit");
  NSAssert([media2.frameDecoder isResourceUsageLimit] == FALSE, @"isResourceUsageLimit");
  
  afterImage = animatorView.image;
  
  NSAssert(media1.currentFrame == -1, @"currentFrame");
  NSAssert(media2.currentFrame == 0, @"currentFrame");
  
  NSAssert(beforeImage != afterImage, @"image");
  
  // Invoking showFrame again for frame 0 is a no-op
  
  beforeImage = animatorView.image;
  
  [media2 showFrame:0];
  
  afterImage = animatorView.image;
  
  NSAssert(beforeImage == afterImage, @"image");
  
  NSAssert(media2.currentFrame == 0, @"currentFrame");
  
  // Invoking showFrame for frame 1 works as expected

  beforeImage = animatorView.image;
  
  [media2 showFrame:1];
  
  afterImage = animatorView.image;
  
  NSAssert(beforeImage != afterImage, @"image");  
  
  NSAssert(media2.currentFrame == 1, @"currentFrame");
  
  // The prevFrame field should be set to nil after
  // calling showFrame. There is no reason to hold
  // onto the earlier UIImage like in the normal
  // decode cycle.
  
  NSAssert(media2.prevFrame == nil, @"prevFrame");  
  
  // There are only 2 frames, so doign a show of frame 3
  // does nothing.
  
  beforeImage = animatorView.image;

  [media2 showFrame:2];

  afterImage = animatorView.image;
  
  NSAssert(beforeImage == afterImage, @"image");    
  
  NSAssert(media2.currentFrame == 1, @"currentFrame");
    
  // Attempting to show frame zero now should rewind and
  // then show frame zero.
  
  beforeImage = animatorView.image;
  
  [media2 showFrame:0];
  
  afterImage = animatorView.image;
  
  NSAssert(beforeImage != afterImage, @"image");    
  
  NSAssert(media2.currentFrame == 0, @"currentFrame");
  
  // Detach media and check that both media objects have the resource limit flag set
  
  [animatorView attachMedia:nil];
  
  NSAssert([media1.frameDecoder isResourceUsageLimit] == TRUE, @"isResourceUsageLimit");
  NSAssert([media2.frameDecoder isResourceUsageLimit] == TRUE, @"isResourceUsageLimit");  
  
  // Reattach the first media element to test that the file is getting mapped again
  
  beforeImage = animatorView.image;
  
  [animatorView attachMedia:media1];
  
  NSAssert(animatorView.media == media1, @"media");
  
  NSAssert([media1.frameDecoder isResourceUsageLimit] == FALSE, @"isResourceUsageLimit");
  NSAssert([media2.frameDecoder isResourceUsageLimit] == TRUE, @"isResourceUsageLimit");  
  
  afterImage = animatorView.image;
  
  NSAssert(beforeImage != afterImage, @"image");
  
  NSAssert(media1.currentFrame == 0, @"currentFrame");  
  
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

// Decode .mov attached as a resource

+ (void) test16BPPMov
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
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
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
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

// Decode .mov.7z attached as a resource

+ (void) test16BPPMov7z
{
  BOOL worked;
  
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *archiveFilename = @"Bounce_16BPP_15FPS.mov.7z";
  NSString *entryFilename = @"Bounce_16BPP_15FPS.mov";  
  NSString *outPath = [AVFileUtil getTmpDirPath:entryFilename];  
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Make sure that any already extracted archive file in the /tmp dir is removed
  
  worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
  //NSAssert(worked, @"could not remove tmp file");
  
  // Create loader that will read a movie file from app resources.
  
	AV7zAppResourceLoader *resLoader = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
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
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
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

// Decode .mov.7z from resource and convert to .mvid

+ (void) test16BPPMov7zToMvid
{
  BOOL worked;
  
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *archiveFilename = @"Bounce_16BPP_15FPS.mov.7z";
  NSString *entryFilename = @"Bounce_16BPP_15FPS.mov";
  NSString *outFilename = @"Bounce_16BPP_15FPS.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];  
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Make sure that any already extracted archive file in the /tmp dir is removed
  
  worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
  //NSAssert(worked, @"could not remove tmp file");
  NSLog(@"tmp file %@", outPath);
  
  // Create loader that will read a movie file from app resources.
  
	AV7zQT2MvidResourceLoader *resLoader = [AV7zQT2MvidResourceLoader aV7zQT2MvidResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
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
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
    
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

  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed

  NSAssert(media.currentFrame == 0, @"currentFrame");

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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
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
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
    
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
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
  
  [media showFrame:1];
  
  UIImage *frameAfter = animatorView.image;
  
  NSAssert(frameAfter != nil, @"image");
  NSAssert(frameBefore != frameAfter, @"image");

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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
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
  
  [media showFrame:1];
  
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == TRUE, @"hasAlphaChannel");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
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
  
  [media showFrame:1];
  
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  NSAssert(media.prevFrame == nil, @"prev frame should be nil");
  
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
  
  [media showFrame:1];

  UIImage *imageAfter = animatorView.image;
  
  NSAssert(imageBefore == imageAfter, @"advancing to 2nd frame changed the image");
  
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
  
  [media showFrame:2];
  
  imageAfter = animatorView.image;
  
  NSAssert(imageBefore != imageAfter, @"advancing to 3rd frame changed the image");
  
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
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = videoResourceName;
  resLoader.audioFilename = audioResourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = AVAnimator15FPS;
  
  media.animatorRepeatCount = 2;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 480.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 320.0, @"renderSize.height");
  
  // Wait until initial keyframe of data is loaded.
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");

  {
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.5];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  // Wait for 2 loops to finish
  
  [media startAnimator];
  
  {
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:30.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  NSAssert(media.state == STOPPED, @"STOPPED");
  
  return;
}

// This test case is for the case where the audio is not as long as the
// animation frames. In this case, the frames would run for 5.0 seconds
// while the audio is only 3.0 seconds long. The audio clock will begin
// to report a zero time after the end of the audio is reached, so the
// code needs to use the fallback clock to continue to report time
// until the video is finished.

+ (void) testAudioShorterThanAnimation
{
  id appDelegate = [[UIApplication sharedApplication] delegate];	
  UIWindow *window = [appDelegate window];
  NSAssert(window, @"window");
  
  NSString *audioResourceName = @"Silence3S.wav";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Use phony res loader, will load PNG frames from resources later
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = @"CountingLandscape01.png"; // Phony resource name, becomes no-op
  resLoader.audioFilename = audioResourceName;
  media.resourceLoader = resLoader;    
  
  // Create decoder that will generate frames from PNG files attached as app resources.
  
  NSArray *names = [AVImageFrameDecoder arrayWithNumberedNames:@"CountingLandscape"
                                                  rangeStart:1
                                                    rangeEnd:5
                                                suffixFormat:@"%02i.png"];
  
  NSArray *URLs = [AVImageFrameDecoder arrayWithResourcePrefixedURLs:names];
  
  AVImageFrameDecoder *frameDecoder = [AVImageFrameDecoder aVImageFrameDecoder:URLs cacheDecodedImages:TRUE];
  media.frameDecoder = frameDecoder;  
  
  // Configure frame duration and repeat count, there are 5 frames in this animation
  // so the valid time frame is [0.0, 5.0]
  
  media.animatorFrameDuration = 1.0;
  
  [window addSubview:animatorView];
  
  [animatorView attachMedia:media];
  
  // Wait until initial keyframe of data is loaded.
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // Wait until animation cycle is finished
  
  [media startAnimator];
  
  {
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:10.0];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  // FIXME: Add functionality so that we can tell which frames were displayed
  // during the animation cycle. This would make it possible to test that
  // each frame was decoded by this logic. Might want a more general "frame decode info"
  // that could also record the frame decode times and how the clock sync was
  // going for each decode operation so that this info could be dumped and graphed.
  
  NSAssert(media.state == STOPPED, @"STOPPED");

  NSAssert(media.reportTimeFromFallbackClock == TRUE, @"reportTimeFromFallbackClock");

  // Invoking startAnimator clears the reportTimeFromFallbackClock flag
  
  [media startAnimator];
  
  NSAssert(media.reportTimeFromFallbackClock == FALSE, @"reportTimeFromFallbackClock");
  
  [media stopAnimator];
  
  NSAssert(media.reportTimeFromFallbackClock == FALSE, @"reportTimeFromFallbackClock");
  
  return;  
}

@end
