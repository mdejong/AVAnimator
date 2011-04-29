//
//  AVFrameDecoderTests.m
//
//  Created by Moses DeJong on 4/28/11.
//
// Test frame decoder classes. This logic should validate that
// as frames are skipped, the deltas are still applied. Advancing
// to a keyframe by skipping over deltas should also be verified.

#import <Foundation/Foundation.h>

#import "RegressionTests.h"

#import "AVAnimatorLayer.h"
#include "AVAnimatorLayerPrivate.h"

#import "AVAnimatorMedia.h"
#import "AVAnimatorMediaPrivate.h"

#import "AVAppResourceLoader.h"
#import "AVQTAnimationFrameDecoder.h"

#import "AV7zAppResourceLoader.h"
#import "AV7zQT2MvidResourceLoader.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

@interface AVFrameDecoderTests : NSObject {
}
@end


@implementation AVFrameDecoderTests

+ (void) doSeekTests:(AVFrameDecoder*)frameDecoder
{
  NSAssert([frameDecoder frameIndex] == -1, @"frameIndex");
  NSAssert([frameDecoder numFrames] == 30, @"numFrames");
  
  UIImage* img;
  NSAutoreleasePool *pool;
  
  // Run through all 30 frames in order, to ensure that the
  // frames can be decoded properly.
  
  for (int i=0; i < [frameDecoder numFrames]; i++) {
    pool = [[NSAutoreleasePool alloc] init];
    
    img = [frameDecoder advanceToFrame:i];
    NSAssert(img != nil, @"advanceToFrame");
    
    NSAssert([frameDecoder frameIndex] == i, @"frameIndex");
    
    [pool drain];
  }

  // Rewind and start over
  
  pool = [[NSAutoreleasePool alloc] init];
  
  [frameDecoder rewind];

  img = [frameDecoder advanceToFrame:0];  
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 0, @"frameIndex");
  
  img = [frameDecoder advanceToFrame:1];  
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 1, @"frameIndex");

  img = [frameDecoder advanceToFrame:2];
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 2, @"frameIndex");
  
  [pool drain];

  // Rewind and skip frame 1

  pool = [[NSAutoreleasePool alloc] init];
  
  [frameDecoder rewind];
  
  img = [frameDecoder advanceToFrame:0];  
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 0, @"frameIndex");
    
  img = [frameDecoder advanceToFrame:2];
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 2, @"frameIndex");
  
  [pool drain];  

  // Rewind and skip frame 1 and 2
  
  pool = [[NSAutoreleasePool alloc] init];
  
  [frameDecoder rewind];
  
  img = [frameDecoder advanceToFrame:0];  
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 0, @"frameIndex");
  
  img = [frameDecoder advanceToFrame:3];
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 3, @"frameIndex");
  
  [pool drain];  
  
  // Rewind and skip half the frames in the video

  pool = [[NSAutoreleasePool alloc] init];
  
  [frameDecoder rewind];
  
  img = [frameDecoder advanceToFrame:0];  
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 0, @"frameIndex");
  
  img = [frameDecoder advanceToFrame:15];
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 15, @"frameIndex");

  img = [frameDecoder advanceToFrame:29];
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 29, @"frameIndex");  
  
  [pool drain];  

  // Rewind and skip all the frames in the video
  
  pool = [[NSAutoreleasePool alloc] init];
  
  [frameDecoder rewind];
  
  img = [frameDecoder advanceToFrame:0];  
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 0, @"frameIndex");
    
  img = [frameDecoder advanceToFrame:29];
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 29, @"frameIndex");  
  
  [pool drain];  
  
  return;
}

// This test case will allocate a frame decoder and then invoke a generic test method that will skip around inside the
// frames of the video.

+ (void) testBounce32SeekMov
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"Bounce_32BPP_15FPS.mov";
    
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
      
  // Wait until initial keyframe of data is loaded.
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // No frame is selected
  
  NSAssert(media.currentFrame == -1, @"currentFrame");

  // Invoke logic to seek around in the frames
  
  [self doSeekTests:frameDecoder];
  
  return;
}

// Same seek logic as above, but this test converts to .mvid file first. Seeking in an mvid file
// will validate the adler checksums on each frame change in debug mode.

+ (void) testBounce32SeekMvid
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *archiveFilename = @"Bounce_32BPP_15FPS.mov.7z";
  NSString *entryFilename = @"Bounce_32BPP_15FPS.mov";
  NSString *outFilename = @"Bounce_32BPP_15FPS.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
  
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from app resources.
  
	AV7zQT2MvidResourceLoader *resLoader = [AV7zQT2MvidResourceLoader aV7zQT2MvidResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
  
  resLoader.alwaysGenerateAdler = TRUE;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  // Wait until initial keyframe of data is loaded.
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // No frame is selected
  
  NSAssert(media.currentFrame == -1, @"currentFrame");
  
  // Invoke logic to seek around in the frames
  
  [self doSeekTests:frameDecoder];
  
  return;
}

@end
