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

#import "AV7zAppResourceLoader.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

#import "CGFrameBuffer.h"

@interface AVFrameDecoderTests : NSObject {
}
@end


@implementation AVFrameDecoderTests

+ (void) doSeekTests:(AVFrameDecoder*)frameDecoder
{
  NSAssert([frameDecoder frameIndex] == -1, @"frameIndex");
  NSAssert([frameDecoder numFrames] == 30, @"numFrames");
  
  // Explicitly allocate decode resources as media is not attached to a view
  
  BOOL worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked, @"worked");
  
  AVFrame *frame;
  UIImage* img;
  NSAutoreleasePool *pool;
  
  // Run through all 30 frames in order, to ensure that the
  // frames can be decoded properly.
  
  for (int i=0; i < [frameDecoder numFrames]; i++) {
    pool = [[NSAutoreleasePool alloc] init];
    
    frame = [frameDecoder advanceToFrame:i];
    img = frame.image;
    NSAssert(img != nil, @"advanceToFrame");
    
    NSAssert([frameDecoder frameIndex] == i, @"frameIndex");
    
    [pool drain];
  }

  // Rewind and start over
  
  pool = [[NSAutoreleasePool alloc] init];
  
  [frameDecoder rewind];

  frame = [frameDecoder advanceToFrame:0];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 0, @"frameIndex");

  frame = [frameDecoder advanceToFrame:1];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 1, @"frameIndex");

  frame = [frameDecoder advanceToFrame:2];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 2, @"frameIndex");
  
  [pool drain];

  // Rewind and skip frame 1

  pool = [[NSAutoreleasePool alloc] init];
  
  [frameDecoder rewind];
  
  frame = [frameDecoder advanceToFrame:0];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 0, @"frameIndex");
  
  frame = [frameDecoder advanceToFrame:2];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 2, @"frameIndex");
  
  [pool drain];  

  // Rewind and skip frame 1 and 2
  
  pool = [[NSAutoreleasePool alloc] init];
  
  [frameDecoder rewind];
  
  frame = [frameDecoder advanceToFrame:0];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 0, @"frameIndex");

  frame = [frameDecoder advanceToFrame:3];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 3, @"frameIndex");
  
  [pool drain];  
  
  // Rewind and skip half the frames in the video

  pool = [[NSAutoreleasePool alloc] init];
  
  [frameDecoder rewind];
  
  frame = [frameDecoder advanceToFrame:0];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 0, @"frameIndex");
  
  frame = [frameDecoder advanceToFrame:15];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 15, @"frameIndex");

  frame = [frameDecoder advanceToFrame:29];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 29, @"frameIndex");  
  
  [pool drain];  

  // Rewind and skip all the frames in the video
  
  pool = [[NSAutoreleasePool alloc] init];
  
  [frameDecoder rewind];
  
  frame = [frameDecoder advanceToFrame:0];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 0, @"frameIndex");

  frame = [frameDecoder advanceToFrame:29];
  img = frame.image;
  NSAssert(img != nil, @"advanceToFrame");
  NSAssert([frameDecoder frameIndex] == 29, @"frameIndex");  
  
  [pool drain];  
  
  return;
}

// This test case will allocate a frame decoder and then invoke a generic test method that will skip around inside the
// frames of the video.

+ (void) testBounce32SeekMvid
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *archiveFilename = @"Bounce_32BPP_15FPS.mvid.7z";
  NSString *entryFilename = @"Bounce_32BPP_15FPS.mvid";
  NSString *outFilename = @"Bounce_32BPP_15FPS.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from 7z app resources.
  
  AV7zAppResourceLoader *resLoader = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
  
  media.resourceLoader = resLoader;
  
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

// Same seek logic as above, but this test converts to .mvid file first. Seeking in an mvid file
// will validate the adler checksums on each frame change in debug mode.

+ (void) testBounce32SeekMvid7z
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *archiveFilename = @"Bounce_32BPP_15FPS.mvid.7z";
  NSString *entryFilename = @"Bounce_32BPP_15FPS.mvid";
  NSString *outFilename = @"Bounce_32BPP_15FPS.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
  
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will read a movie file from 7z app resources.
    
	AV7zAppResourceLoader *resLoader = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
  
	media.resourceLoader = resLoader;
  
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
  
  // Check "all keyframes" flag
  
  BOOL isAllKeyframes = [frameDecoder isAllKeyframes];
  NSAssert(isAllKeyframes == FALSE, @"isAllKeyframes");
  
  // Invoke logic to seek around in the frames
  
  [self doSeekTests:frameDecoder];
  
  return;
}

// This test case checks for the case where a resource is ready (meaning the file could be decoded)
// but the decoder could not decode frames because a resource was not available. This could happen
// when the decoder fails to map all the memory for a given file.

+ (void) testMovDecoderSimulateMapFailure
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";

  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
  
  // The resource loader should be "ready" at this point because the decoded
  // file should be available in the app resources.
  
  BOOL isReady = [resLoader isReady];
  NSAssert(isReady, @"isReady");
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
	NSArray *resourcePathsArr = [resLoader getResources];  
	NSAssert([resourcePathsArr count] == 1, @"expected 1 resource paths");
	NSString *videoPath = [resourcePathsArr objectAtIndex:0];
  
  BOOL worked = [frameDecoder openForReading:videoPath];
	NSAssert(worked, @"frameDecoder openForReading failed");

  // By default, usage limit is TRUE
  
  NSAssert([frameDecoder isResourceUsageLimit] == TRUE, @"initial isResourceUsageLimit");

  worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked, @"allocateDecodeResources");

  NSAssert([frameDecoder isResourceUsageLimit] == FALSE, @"isResourceUsageLimit");
  
  // At this point the frame decoder has read the header, but it has not
  // yet attempted to map the whole file into memory.
  
  AVFrame *frame;
  UIImage *image;
  
  frame = [frameDecoder advanceToFrame:0];
  image = frame.image;
  NSAssert(image, @"image");
  
  // The file would be mapped at this point. Unmap it.
  
  [frameDecoder releaseDecodeResources];
  
  NSAssert([frameDecoder isResourceUsageLimit] == TRUE, @"isResourceUsageLimit");
  
  // Now simulate a map failure by setting a special flag only avalable in test mode
  
  frameDecoder.simulateMemoryMapFailure = TRUE;
  
  // Test the FALSE return value when allocation of decode resources (mmap memory) fails
  
  worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked == FALSE, @"allocateDecodeResources should have failed");
  
  // Release allocated resources, this basically checks that deallocation is still
  // done without error even when the memory map failed.
  
  [frameDecoder releaseDecodeResources];
  
  return;
}

// This test case checks for the case where a resource is ready (meaning the file could be decoded)
// but the decoder could not decode frames because a resource was not available. This could happen
// when the decoder fails to map all the memory for a given file.

+ (void) testMvidDecoderSimulateMapFailure
{
	id appDelegate = [[UIApplication sharedApplication] delegate];
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
  
  // The resource loader should be "ready" at this point because the decoded
  // file should be available in the app resources.
  
  BOOL isReady = [resLoader isReady];
  NSAssert(isReady, @"isReady");
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
	NSArray *resourcePathsArr = [resLoader getResources];  
	NSAssert([resourcePathsArr count] == 1, @"expected 1 resource paths");
	NSString *videoPath = [resourcePathsArr objectAtIndex:0];

  BOOL worked;
  
  // Test that openForReading fails if filename does not end in ".mvid"
  
  NSString *phonyVideoPath = [videoPath stringByReplacingOccurrencesOfString:@".mvid" withString:@".moo"];
  
  worked = [frameDecoder openForReading:phonyVideoPath];
	NSAssert(worked == FALSE, @"frameDecoder openForReading should have failed");
  
  // Now use the real filename that ends in ".mvid", this should work
  
  worked = [frameDecoder openForReading:videoPath];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  // By default, usage limit is TRUE
  
  NSAssert([frameDecoder isResourceUsageLimit] == TRUE, @"initial isResourceUsageLimit");
  
  worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked, @"allocateDecodeResources");
  
  NSAssert([frameDecoder isResourceUsageLimit] == FALSE, @"isResourceUsageLimit");
  
  // At this point the frame decoder has read the header, but it has not
  // yet attempted to map the whole file into memory.
  
  AVFrame *frame;
  UIImage *img;
  
  frame = [frameDecoder advanceToFrame:0];
  NSAssert(frame, @"frame");
  img = frame.image;
  NSAssert(img, @"image");
  
  // Check "all keyframes" flag, it should be TRUE
  
  BOOL isAllKeyframes = [frameDecoder isAllKeyframes];
  NSAssert(isAllKeyframes == TRUE, @"isAllKeyframes");
  
  //NSAssert([frameDecoder isAllKeyframes] == TRUE, @"isAllKeyframes");
  
  // The file would be mapped at this point. Unmap it.
  
  [frameDecoder releaseDecodeResources];
  
  NSAssert([frameDecoder isResourceUsageLimit] == TRUE, @"isResourceUsageLimit");
  
  // Now simulate a map failure by setting a special flag only avalable in test mode
  
  frameDecoder.simulateMemoryMapFailure = TRUE;
  
  // Test the FALSE return value when allocation of decode resources (mmap memory) fails
  
  worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked == FALSE, @"allocateDecodeResources should have failed");
  
  // Release allocated resources, this basically checks that deallocation is still
  // done without error even when the memory map failed.
  
  [frameDecoder releaseDecodeResources];
  
  return;
}

// This test case simulates a memory mapping failure in the mvid frame decoder
// during the first frame decode. It is possible that no previous frame would
// have returned successfully, so if the first frame decode fails then a nil
// image would be returned in the AVFrame object.

+ (void) testMvidDecoderSimulateMapFailureOnFirstFrameDecode
{  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
  
  // The resource loader should be "ready" at this point because the decoded
  // file should be available in the app resources.
  
  BOOL isReady = [resLoader isReady];
  NSAssert(isReady, @"isReady");
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
	NSArray *resourcePathsArr = [resLoader getResources];  
	NSAssert([resourcePathsArr count] == 1, @"expected 1 resource paths");
	NSString *videoPath = [resourcePathsArr objectAtIndex:0];
  
  BOOL worked;
  
  worked = [frameDecoder openForReading:videoPath];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  // By default, usage limit is TRUE
  
  NSAssert([frameDecoder isResourceUsageLimit] == TRUE, @"initial isResourceUsageLimit");
  
  worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked, @"allocateDecodeResources");
  
  NSAssert([frameDecoder isResourceUsageLimit] == FALSE, @"isResourceUsageLimit");
  
  // At this point the frame decoder has read the header, but it has not
  // yet attempted to map the file into memory.
  
  AVFrame *frame;
  UIImage *image;
  
  frameDecoder.simulateMemoryMapFailure = TRUE;
  
  frame = [frameDecoder advanceToFrame:0];
  NSAssert(frame, @"advanceToFrame returned nil");
  
  // Note that the getter for the frame.image property should not automatically
  // create an image if the frame buffer is set but the image is nil. If that
  // were the implementation, then we could not detect the case where the image
  // is actually nil.
  
  image = frame.image;
  NSAssert(image == nil, @"image is nil");
  
  NSAssert(frame.isDuplicate == TRUE, @"isDuplicate");
    
  return;
}

// This test case simulates a memory mapping failure in the mvid frame decoder
// during a frame decode operation. When a segmented mapping model is used
// it becomes possible that decoding a specific frame could fail due to a
// failed mapping pages into memory.

+ (void) testMvidDecoderSimulateMapFailureOnSecondFrameDecode
{
	id appDelegate = [[UIApplication sharedApplication] delegate];
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
  
  // The resource loader should be "ready" at this point because the decoded
  // file should be available in the app resources.
  
  BOOL isReady = [resLoader isReady];
  NSAssert(isReady, @"isReady");
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
	NSArray *resourcePathsArr = [resLoader getResources];  
	NSAssert([resourcePathsArr count] == 1, @"expected 1 resource paths");
	NSString *videoPath = [resourcePathsArr objectAtIndex:0];
  
  BOOL worked;
    
  worked = [frameDecoder openForReading:videoPath];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  // By default, usage limit is TRUE
  
  NSAssert([frameDecoder isResourceUsageLimit] == TRUE, @"initial isResourceUsageLimit");
  
  worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked, @"allocateDecodeResources");
  
  NSAssert([frameDecoder isResourceUsageLimit] == FALSE, @"isResourceUsageLimit");
  
  // At this point the frame decoder has read the header, but it has not
  // yet attempted to map the whole file into memory.
  
  AVFrame *frame;
  UIImage *image;
  
  frame = [frameDecoder advanceToFrame:0];
  NSAssert(frame, @"advanceToFrame returned nil");
  image = frame.image;
  NSAssert(image, @"advanceToFrame returned frame with nil image");
  
  NSAssert(frame.isDuplicate == FALSE, @"isDuplicate");
  
  // Verify that the file has been mapped into memory by
  // checking to see if the mappedData ref is nil.

  NSAssert(frameDecoder.mappedData != nil, @"mappedData");

  // Now simulate a map failure by setting a special flag only avalable in test mode.
  // Note that this applies only to the frame decode operation since the overall file
  // mapping was created already without the simulate mapping failure flag set.
  
  frameDecoder.simulateMemoryMapFailure = TRUE;
  
  frame = [frameDecoder advanceToFrame:1];
  NSAssert(frame, @"advanceToFrame returned nil");
  image = frame.image;
  NSAssert(image, @"advanceToFrame returned frame with nil image");
  
  // Frame should be marked as a duplicate, a failed mapping will return the
  // last successfully decoded image as a no-op delta.
  
  NSAssert(frame.isDuplicate == TRUE, @"isDuplicate");

  NSAssert(frameDecoder.frameIndex == 0, @"decoder frame index should not have changed");
  
  // Disable the memory mapping failure and decode frame 1 normally

  frameDecoder.simulateMemoryMapFailure = FALSE;
  
  frame = [frameDecoder advanceToFrame:1];
  NSAssert(frame, @"advanceToFrame returned nil");
  image = frame.image;
  NSAssert(image, @"advanceToFrame returned frame with nil image");

  NSAssert(frame != nil, @"should return decoded second frame");
  
  NSAssert(frame.isDuplicate == FALSE, @"isDuplicate");
  
  NSAssert(frameDecoder.frameIndex == 1, @"decoder frame index should be 1");
  
  return;
}

// This test case will create a media object from a file that has a magic number
// that does not match the expected .mvid magic number.

+ (void) testMvidFailToOpenInvalidFile
{
	id appDelegate = [[UIApplication sharedApplication] delegate];
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];  
  NSData *knownGoodData = [NSData dataWithContentsOfFile:resPath];
  
  NSMutableData *mData = [NSMutableData dataWithData:knownGoodData];

  char bytes[] = { '\x4', '\x5', '\x6', '\x7' };
  
  NSRange range = NSMakeRange(0, 4);
  [mData replaceBytesInRange:range withBytes:bytes];
  
  // Get tmp dir path and create an empty file with the .mvid extension
  
  NSString *tmpFilename = @"Invalid.mvid";
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingPathComponent:tmpFilename];
  
  [mData writeToFile:tmpPath options:NSDataWritingAtomic error:nil];
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = tmpPath;
  
  // The resource loader should be "ready" at this point because the decoded
  // file should be available in the app resources.
  
  BOOL isReady = [resLoader isReady];
  NSAssert(isReady, @"isReady");
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
	NSArray *resourcePathsArr = [resLoader getResources];  
	NSAssert([resourcePathsArr count] == 1, @"expected 1 resource paths");
	NSString *videoPath = [resourcePathsArr objectAtIndex:0];
  
  BOOL worked;
  
  worked = [frameDecoder openForReading:videoPath];
	NSAssert(worked == FALSE, @"frameDecoder openForReading should have failed");
      
  return;
}

// This test case checks a specific detail of the AVFrame implementation.
// An AVFrame contains a ref to an image, and an image holds on to a ref
// to the CGFrameBuffer that implements the image. While the UIImage is
// valid, we expect that the CGFrameBuffer will not change and that
// it will not again be referenced by another image source pointing to
// the same buffer. In the case where the ref to the image in the AVFrame
// object is dropped, the CGFrameBuffer should be marked as no longer
// being used by the UIImage object.

+ (void) testFrameDropRefToImage
{
  BOOL worked;
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];  
    
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  frameDecoder.filePath = resPath;
  
  worked = [frameDecoder openForReading:resPath];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  // Get the first frame from the decoder
  
  worked = [frameDecoder allocateDecodeResources];
	NSAssert(worked, @"allocateDecodeResources failed");
  
  AVFrame *frame = [frameDecoder advanceToFrame:0];
  NSAssert(frame, @"frame"); 
  
  UIImage *image = frame.image;
  CGFrameBuffer *frameBuffer = frame.cgFrameBuffer;

  NSAssert(image, @"image"); 
  
  NSAssert(frameBuffer.isLockedByDataProvider == TRUE, @"isLockedByDataProvider"); 
  
  // Drop ref to UIImage, this must drop the ref to CGFrameBuffer data
  
  frame.image = nil;

  NSAssert(frameBuffer.isLockedByDataProvider == FALSE, @"isLockedByDataProvider"); 
  
  return;
}

// This test case checks an edge case in the frame decoder where the exact
// same frame index is decoded twice in a row. This decoder should return
// the exact same AVFrame object in this case. This could happen if the audio
// clock reported the same time over and over.

+ (void) testDuplicateAdvanceToSameOffset
{
  BOOL worked;
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];  
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  frameDecoder.filePath = resPath;
  
  worked = [frameDecoder openForReading:resPath];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  // Get the first frame from the decoder
  
  worked = [frameDecoder allocateDecodeResources];
	NSAssert(worked, @"allocateDecodeResources failed");
  
  AVFrame *frame1 = [frameDecoder advanceToFrame:0];
  NSAssert(frame1, @"frame1"); 

  AVFrame *frame2 = [frameDecoder advanceToFrame:0];
  NSAssert(frame2, @"frame2"); 
  
  NSAssert(frame1 == frame2, @"same frame expected"); 
  
  return;
}

// FIXME:
// In the case where multiple frames need to be decoded in one call, it could
// be possible that the first would work and the second would fail. Just
// need to determine if a partial good result is returned. Meaning that
// the decodes that did work are returned as an image, but then the
// frame index is still at the location where the next delta would be applied.

@end
