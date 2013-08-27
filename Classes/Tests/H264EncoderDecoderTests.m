//
//  H264EncoderDecoderTests.m
//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.

#import "RegressionTests.h"

#import "AVAnimatorLayer.h"
#include "AVAnimatorLayerPrivate.h"

#import "AVAnimatorMedia.h"
#import "AVAnimatorMediaPrivate.h"

#import "AVAppResourceLoader.h"
#import "AV7zAppResourceLoader.h"

#import "AVApng2MvidResourceLoader.h"
#import "AV7zApng2MvidResourceLoader.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

#import "AVAssetReaderConvertMaxvid.h"

#import "AVAsset2MvidResourceLoader.h"

#import "AVAssetWriterConvertFromMaxvid.h"

#import "CGFrameBuffer.h"

#import "AVImageFrameDecoder.h"

#import "AVAssetFrameDecoder.h"

#import "AVFrame.h"

// Util class for use in testing decoder

@interface AVAssetReaderConvertMaxvid_NotificationUtil : NSObject {
  BOOL m_wasDelivered;
}

@property (nonatomic, assign) BOOL wasDelivered;

+ (AVAssetReaderConvertMaxvid_NotificationUtil*) notificationUtil;

- (void) setupNotification:(AVAssetReaderConvertMaxvid*)obj;

@end

// This utility object will register to receive a AVAnimatorFailedToLoadNotification and set
// a boolean flag to indicate if the notification is delivered.

@implementation AVAssetReaderConvertMaxvid_NotificationUtil

@synthesize wasDelivered = m_wasDelivered;

+ (AVAssetReaderConvertMaxvid_NotificationUtil*) notificationUtil
{
  AVAssetReaderConvertMaxvid_NotificationUtil *obj = [[[AVAssetReaderConvertMaxvid_NotificationUtil alloc] init] autorelease];
  return obj;
}

- (void) dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

- (void) setupNotification:(AVAssetReaderConvertMaxvid*)obj
{  
  // AVAssetReaderConvertMaxvidCompletedNotification
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(completedLoadNotification:) 
                                               name:AVAssetReaderConvertMaxvidCompletedNotification
                                             object:obj];
}

- (void) completedLoadNotification:(NSNotification*)notification
{
  // Note that this wasDelivered flag is only set in the main thread
  // after the notification has been delivered. So, there is no danger
  // of a threaded race condition related to a BOOL being set and then
  // read from two different threads.
  
  self.wasDelivered = TRUE;
  
  // The wasSuccessful property is either TRUE or FALSE
  
  AVAssetReaderConvertMaxvid *obj = [notification object];
  
  NSAssert(obj, @"notification source object");
  
  BOOL wasSuccessful = obj.wasSuccessful;
  NSAssert(wasSuccessful == TRUE, @"wasSuccessful");
}

@end // AVAssetReaderConvertMaxvid_NotificationUtil



// Util class for use in testing encoder

@interface AVAssetWriterConvertFromMaxvid_NotificationUtil : NSObject {
  BOOL m_wasDelivered;
}

@property (nonatomic, assign) BOOL wasDelivered;

+ (AVAssetWriterConvertFromMaxvid_NotificationUtil*) notificationUtil;

- (void) setupNotification:(AVAssetWriterConvertFromMaxvid*)obj;

@end

// This utility object will register to receive a AVAnimatorFailedToLoadNotification and set
// a boolean flag to indicate if the notification is delivered.

@implementation AVAssetWriterConvertFromMaxvid_NotificationUtil

@synthesize wasDelivered = m_wasDelivered;

+ (AVAssetWriterConvertFromMaxvid_NotificationUtil*) notificationUtil
{
  AVAssetWriterConvertFromMaxvid_NotificationUtil *obj = [[AVAssetWriterConvertFromMaxvid_NotificationUtil alloc] init];
  return [obj autorelease];
}

- (void) dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

- (void) setupNotification:(AVAssetWriterConvertFromMaxvid*)obj
{  
  // AVAssetWriterConvertFromMaxvidCompletedNotification

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(completedLoadNotification:) 
                                               name:AVAssetWriterConvertFromMaxvidCompletedNotification
                                             object:obj];
}

- (void) completedLoadNotification:(NSNotification*)notification
{
  // Note that this wasDelivered flag is only set in the main thread
  // after the notification has been delivered. So, there is no danger
  // of a threaded race condition related to a BOOL being set and then
  // read from two different threads.
  
  self.wasDelivered = TRUE;

  // The state is either AVAssetWriterConvertFromMaxvidStateSuccess or
  // AVAssetWriterConvertFromMaxvidStateFailed, but it can't be
  // AVAssetWriterConvertFromMaxvidStateInit.
  
  AVAssetWriterConvertFromMaxvid *obj = [notification object];
  
  NSAssert(obj, @"notification source object");

  AVAssetWriterConvertFromMaxvidState state = obj.state;
  
  NSAssert((state == AVAssetWriterConvertFromMaxvidStateSuccess ||
            state == AVAssetWriterConvertFromMaxvidStateFailed), @"converter state");
}

@end // AVAssetWriterConvertFromMaxvid_NotificationUtil



@interface H264EncoderDecoderTests : NSObject {}
@end

// The methods named test* will be automatically invoked by the RegressionTests harness.

@implementation H264EncoderDecoderTests

// This test case deals with decoding H.264 video as an MVID
// Available in iOS 4.1 and later.

#if defined(HAS_AVASSET_CONVERT_MAXVID)

// Test hardware available detection logic

+ (void) testIsHardwareDecoderAvailable
{
  BOOL isHardwareEncoderAvailable;
  isHardwareEncoderAvailable = [AVAssetWriterConvertFromMaxvid isHardwareEncoderAvailable];
  NSAssert(isHardwareEncoderAvailable == TRUE || isHardwareEncoderAvailable == FALSE, @"isHardwareEncoderAvailable");
}

// Read video data from a single track (only one video track is supported anyway)
// Note that while encoding a 32x32 .mov with H264 is not supported, it is perfectly
// fine to decode a H264 that is smaller than 128x128.

+ (void) testDecodeH264WithTrackReader
{
  NSString *resourceName = @"32x32_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"32x32_black_blue_h264.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAssetReaderConvertMaxvid *obj = [AVAssetReaderConvertMaxvid aVAssetReaderConvertMaxvid];
  obj.assetURL = fileURL;
  obj.mvidPath = tmpPath;
  obj.genAdler = TRUE;
  
  BOOL worked = [obj blockingDecode];
  NSAssert(worked, @"blockingDecode");
  
  BOOL decodeFrames = TRUE;
  BOOL emitFrames = TRUE;
  
  if (decodeFrames) {
    // Create MVID frame decoder and iterate over the frames in the mvid file.
    // This will validate the emitted data via the adler checksum logic
    // in the decoding process.

    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    
    BOOL worked = [frameDecoder openForReading:tmpPath];
    NSAssert(worked, @"worked");
    
    NSAssert([frameDecoder numFrames] == 2, @"numFrames");
    
    worked = [frameDecoder allocateDecodeResources];
    NSAssert(worked, @"worked");

    AVFrame *frame;
    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(32, 32);
    CGSize imgSize;
    
    frame = [frameDecoder advanceToFrame:0];
    NSAssert(frame, @"frame 0");
    img = frame.image;

    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
    path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
    data = [NSData dataWithData:UIImagePNGRepresentation(img)];
    [data writeToFile:path atomically:YES];
    NSLog(@"wrote %@", path);
    }
    
    frame = [frameDecoder advanceToFrame:1];
    NSAssert(frame, @"frame 1");
    img = frame.image;

    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
    path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame1.png"];
    data = [NSData dataWithData:UIImagePNGRepresentation(img)];
    [data writeToFile:path atomically:YES];
    NSLog(@"wrote %@", path);
    }
    
    // Check "all keyframes" flag
    
    BOOL isAllKeyframes = [frameDecoder isAllKeyframes];
    NSAssert(isAllKeyframes == TRUE, @"isAllKeyframes");
  }
  
  return;
}

// Decode superwalk_h264.mov contanining H264 video

+ (void) testDecodeSuperwalkH264WithTrackReader
{
  NSString *resourceName = @"superwalk_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"superwalk.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAssetReaderConvertMaxvid *obj = [AVAssetReaderConvertMaxvid aVAssetReaderConvertMaxvid];
  obj.assetURL = fileURL;
  obj.mvidPath = tmpPath;
  obj.genAdler = TRUE;
  
  BOOL worked = [obj blockingDecode];
  NSAssert(worked, @"blockingDecode");
  
  BOOL decodeFrames = TRUE;
  BOOL emitFrames = TRUE;
  
  if (decodeFrames) {
    // Create MVID frame decoder and iterate over the frames in the mvid file.
    // This will validate the emitted data via the adler checksum logic
    // in the decoding process.
    
    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    
    BOOL worked = [frameDecoder openForReading:tmpPath];
    NSAssert(worked, @"worked");
    
    NSAssert([frameDecoder numFrames] == 6, @"numFrames");
    
    worked = [frameDecoder allocateDecodeResources];
    NSAssert(worked, @"worked");
    
    AVFrame *frame;
    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(86, 114);
    CGSize imgSize;
    
    frame = [frameDecoder advanceToFrame:0];
    NSAssert(frame, @"frame 0");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    frame = [frameDecoder advanceToFrame:1];
    NSAssert(frame, @"frame 1");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame1.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    frame = [frameDecoder advanceToFrame:2];
    NSAssert(frame, @"frame 2");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame2.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
  }
  
  return;
}

// Decode stutterwalk_h264.mov contanining H264 video

+ (void) testDecodeStutterwalkH264WithTrackReader
{
  NSString *resourceName = @"stutterwalk_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"stutterwalk.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAssetReaderConvertMaxvid *obj = [AVAssetReaderConvertMaxvid aVAssetReaderConvertMaxvid];
  obj.assetURL = fileURL;
  obj.mvidPath = tmpPath;
  obj.genAdler = TRUE;
  
  BOOL worked = [obj blockingDecode];
  NSAssert(worked, @"blockingDecode");
  
  BOOL decodeFrames = TRUE;
  BOOL emitFrames = TRUE;
  
  if (decodeFrames) {
    // Create MVID frame decoder and iterate over the frames in the mvid file.
    // This will validate the emitted data via the adler checksum logic
    // in the decoding process.
    
    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    
    BOOL worked = [frameDecoder openForReading:tmpPath];
    NSAssert(worked, @"worked");
    
    NSAssert([frameDecoder numFrames] == 9, @"numFrames");
    
    worked = [frameDecoder allocateDecodeResources];
    NSAssert(worked, @"worked");
    
    AVFrame *frame;
    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(86, 114);
    CGSize imgSize;
    
    frame = [frameDecoder advanceToFrame:0];
    NSAssert(frame, @"frame 0");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    frame = [frameDecoder advanceToFrame:1];
    NSAssert(frame, @"frame 1");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame1.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    frame = [frameDecoder advanceToFrame:2];
    NSAssert(frame, @"frame 2");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame2.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
  }
  
  return;
}

// Decode stutterwalk_h264.mov contanining H264 video with nonblocking API

+ (void) testDecodeStutterwalkH264WithTrackReaderNonBlocking
{
  NSString *resourceName = @"stutterwalk_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"stutterwalk.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAssetReaderConvertMaxvid *obj = [AVAssetReaderConvertMaxvid aVAssetReaderConvertMaxvid];
  obj.assetURL = fileURL;
  obj.mvidPath = tmpPath;
  obj.genAdler = TRUE;
  
  // This util object gets a notification, it is useful for testing purposes. In real code the view controller
  // or some other object would process the notification in the module.
  
  AVAssetReaderConvertMaxvid_NotificationUtil *notificationUtil = [AVAssetReaderConvertMaxvid_NotificationUtil notificationUtil];
  
  [notificationUtil setupNotification:obj];
  
  [obj nonblockingDecode];
  
  // Wait in loop until Notification is delivered. Note that this wasDelivered flag is set only
  // in the main thread, so there is no danger of a threaded race condition.
  
  while (TRUE) {
    if (notificationUtil.wasDelivered) {
      break;
    }
    
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }

  BOOL worked = obj.wasSuccessful;
  NSAssert(worked, @"wasSuccessful");
  
  NSLog(@"wrote %@", obj.mvidPath);

  // Check decoded frame data
  
  BOOL decodeFrames = TRUE;
  BOOL emitFrames = TRUE;
  
  if (decodeFrames) {
    // Create MVID frame decoder and iterate over the frames in the mvid file.
    // This will validate the emitted data via the adler checksum logic
    // in the decoding process.
    
    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    
    BOOL worked = [frameDecoder openForReading:tmpPath];
    NSAssert(worked, @"worked");
    
    NSAssert([frameDecoder numFrames] == 9, @"numFrames");
    
    worked = [frameDecoder allocateDecodeResources];
    NSAssert(worked, @"worked");
    
    AVFrame *frame;
    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(86, 114);
    CGSize imgSize;
    
    frame = [frameDecoder advanceToFrame:0];
    NSAssert(frame, @"frame 0");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    frame = [frameDecoder advanceToFrame:1];
    NSAssert(frame, @"frame 1");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame1.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    frame = [frameDecoder advanceToFrame:2];
    NSAssert(frame, @"frame 2");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame2.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
  }
  
  return;
}

// Use AVAsset2MvidResourceLoader to decoder H.264 is secondary thread 

+ (void) testDecodeSuperwalkH264WithFrameDecoder
{
  NSString *resourceName = @"superwalk_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"superwalk.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAsset2MvidResourceLoader *loader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];
  loader.movieFilename = [fileURL path];
  loader.outPath = tmpPath;

  [loader load];

  BOOL worked = [RegressionTests waitUntilTrue:loader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  BOOL decodeFrames = TRUE;
  BOOL emitFrames = TRUE;
  
  if (decodeFrames) {
    // Create MVID frame decoder and iterate over the frames in the mvid file.
    // This will validate the emitted data via the adler checksum logic
    // in the decoding process.
    
    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    
    BOOL worked = [frameDecoder openForReading:tmpPath];
    NSAssert(worked, @"worked");

    NSAssert([frameDecoder numFrames] == 6, @"numFrames");
    
    worked = [frameDecoder allocateDecodeResources];
    NSAssert(worked, @"worked");
    
    AVFrame *frame;
    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(86, 114);
    CGSize imgSize;
    
    frame = [frameDecoder advanceToFrame:0];
    NSAssert(frame, @"frame 0");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    frame = [frameDecoder advanceToFrame:1];
    NSAssert(frame, @"frame 1");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame1.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    frame = [frameDecoder advanceToFrame:2];
    NSAssert(frame, @"frame 2");
    img = frame.image;
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame2.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
  }
  
  return;
}

// The test case reads the movie data in Waterfall_tiny_h264.mov, the movie duration is an exact multiplier
// of the frame rate, but we end up with too many frames when all frames are extracted from the asset.

+ (void) testDecodeWaterfallH264WithFrameDecoder
{
  NSString *resourceName = @"Waterfall_tiny_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"Waterfall_tiny.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAsset2MvidResourceLoader *loader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];
  loader.movieFilename = [fileURL path];
  loader.outPath = tmpPath;
  
  [loader load];
  
// Max time must be at least a couple of munites to allow decoding to complete on slow devices.
#define MAX_WATERFALL_WAIT 120.0
//#define MAX_WATERFALL_WAIT 1000.0
  
  BOOL worked = [RegressionTests waitUntilTrue:loader
                                      selector:@selector(isReady)
                                   maxWaitTime:MAX_WATERFALL_WAIT];
  NSAssert(worked, @"worked");
  
  BOOL decodeFrames = TRUE;
  
  if (decodeFrames) {
    // Open the .mvid file and verify that the number of frames written is 575. This video
    // suffers from a very weird clock drift problem where the actual display time of
    // the frame falls too far behind the expected time to the point where an extra frame
    // would have been introduced. The converter logic deals with the inconsistency by
    // dropping frame 526. This keeps the total number of frames correct and means that
    // the final frame of the video is displayed as expected. It is better to drop one
    // frame during the video than to drop the final frame or have the video duration
    // get longer because of a weird edge case in the H264 decoder. This issues is likely
    // caused by a floating point accumulation error that is not dealt with in the decoder.
    
    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    
    BOOL worked = [frameDecoder openForReading:tmpPath];
    NSAssert(worked, @"worked");
  
    int numFrames = [frameDecoder numFrames];
    
    NSAssert(numFrames == 575, @"numFrames");    
  }
  
  return;
}

// The test case reads H264 encoded data with 3 all black frames at 64x64. This is intended to test
// decoder logic so that repeated identical frames are handled as special case "nop" frames.
// This optimization is very important for performance reasons, but it is quite tricky to test.

// FIXME: note that after more testing, the Quicktime H264 encoder seems to emit flat frames
// that are 1 second long even though the input files are exactly the same. So this test does
// not actually hit the nop logic in the frame reader.

+ (void) testDecode3FrameNop
{
  NSString *resourceName = @"64x64_nop_3frames_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"64x64_nop_3frames.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAsset2MvidResourceLoader *loader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];
  loader.movieFilename = [fileURL path];
  loader.outPath = tmpPath;
  
  [loader load];
  
#define MAX_WAIT_TIME 20.0
  
  BOOL worked = [RegressionTests waitUntilTrue:loader
                                      selector:@selector(isReady)
                                   maxWaitTime:MAX_WAIT_TIME];
  NSAssert(worked, @"worked");
  
  BOOL decodeFrames = TRUE;
  
  if (decodeFrames) {
    // Should be 3 frames, though this file does not actually make use of the nop optimizations
    
    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    
    BOOL worked = [frameDecoder openForReading:tmpPath];
    NSAssert(worked, @"worked");
    
    int numFrames = [frameDecoder numFrames];
    
    NSAssert(numFrames == 3, @"numFrames");
  }
  
  return;
}

// encode .mvid to .h264 as a blocking operation

+ (void) util_encodeMvidAsH264:(NSString*)mvidTmpPath
                   h264TmpPath:(NSString*)h264TmpPath
{
  if ([AVFileUtil fileExists:h264TmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:h264TmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  // Define input .mvid file as the video data source
  
  AVAssetWriterConvertFromMaxvid *obj = [AVAssetWriterConvertFromMaxvid aVAssetWriterConvertFromMaxvid];
  
  NSAssert([obj retainCount] == 1, @"retainCount");
  
  obj.inputPath = mvidTmpPath;
  obj.outputPath = h264TmpPath;
  
  [obj blockingEncode];
  
  // FIXME: success must wait until other thread is done once threading is enabled.
  
  NSAssert(obj.state == AVAssetWriterConvertFromMaxvidStateSuccess, @"success");
  
  NSLog(@"wrote %@", obj.outputPath);
}

// 124x124 (just a touch smaller than the known to work 128x128 size)
// This does not encode properly on an iPhone 4 (writes corrupted data)
// This fails to encode in an iPad 2

+ (void) DISABLED_testDecodeAndEncode124x124H264WithFrameDecoder
{
  NSString *resourceName = @"124x124_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"124x124_black_blue.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAsset2MvidResourceLoader *loader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];
  loader.movieFilename = [fileURL path];
  loader.outPath = tmpPath;
  
  [loader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:loader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  if (TRUE) {
    // Now that .h264 has been decoded to .mvid, encode the same movie to .h264 again
    
    NSString *tmpEncodedFilename = @"124x124_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

// A 128x128 video with 2 frames will encode correctly on an iPhone 4 and a iPad 2

+ (void) testDecodeAndEncode128x128H264WithFrameDecoder
{
  NSString *resourceName = @"128x128_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"128x128_black_blue.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAsset2MvidResourceLoader *loader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];
  loader.movieFilename = [fileURL path];
  loader.outPath = tmpPath;
  
  [loader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:loader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  if (TRUE) {
    // Now that .h264 has been decoded to .mvid, encode the same movie to .h264 again
    
    NSString *tmpEncodedFilename = @"128x128_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

// A 129x128 size is just a touch larger than the min size of 128x128
// and it does not match a known aspect ratio. This causes a software
// fault when encoding with the H264 codec in the Simulator. The output
// is also corrupted on iPad 2 though the encoder does not signal an error.

+ (void) testDecodeAndEncode129x128H264WithFrameDecoder
{
  NSString *resourceName = @"129x128_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"129x128_black_blue.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAsset2MvidResourceLoader *loader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];
  loader.movieFilename = [fileURL path];
  loader.outPath = tmpPath;
  
  [loader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:loader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  if (TRUE) {
    // Now that .h264 has been decoded to .mvid, encode the same movie to .h264 again
    
    NSString *tmpEncodedFilename = @"129x128_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

// A 132x128 video has a width that is a multiple of 4, but the aspect ratio
// is not a commonly used value. This test basically checks to see if a width
// that is still a multiple of 4 will encode correctly.

+ (void) testDecodeAndEncode132x128H264WithFrameDecoder
{
  NSString *resourceName = @"132x128_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"132x128_black_blue.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAsset2MvidResourceLoader *loader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];
  loader.movieFilename = [fileURL path];
  loader.outPath = tmpPath;
  
  [loader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:loader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  if (TRUE) {
    // Now that .h264 has been decoded to .mvid, encode the same movie to .h264 again
    
    NSString *tmpEncodedFilename = @"132x128_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

// 3:2 aspect ratio with 128 as min dimension
// success with iPad 2

+ (void) testDecodeAndEncode192x128H264WithFrameDecoder
{
  NSString *resourceName = @"192x128_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"192x128_black_blue.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAsset2MvidResourceLoader *loader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];
  loader.movieFilename = [fileURL path];
  loader.outPath = tmpPath;
  
  [loader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:loader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  if (TRUE) {
    // Now that .h264 has been decoded to .mvid, encode the same movie to .h264 again
    
    NSString *tmpEncodedFilename = @"192x128_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

// 3:2 aspect ratio at 240x160

+ (void) testDecodeAndEncode240x160H264WithFrameDecoder
{
  NSString *resourceName = @"240x160_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"240x160_black_blue.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAsset2MvidResourceLoader *loader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];
  loader.movieFilename = [fileURL path];
  loader.outPath = tmpPath;
  
  [loader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:loader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  if (TRUE) {
    // Now that .h264 has been decoded to .mvid, encode the same movie to .h264 again
    
    NSString *tmpEncodedFilename = @"240x160_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

// This utility method will make sure that the "AlphaGhost.mvid" file
// has been decoded in the tmp directory.

+ (NSString*) ensureDecodeOfAlphaGhostMvid
{
  NSString *archiveFilename = @"AlphaGhost.mvid.7z";
  NSString *entryFilename = @"AlphaGhost.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:entryFilename];

  // Create loader that will read a movie file from app resources.
  
  AV7zAppResourceLoader *resLoader = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;

  [resLoader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");

  return outPath;
}

// FIXME: disabled because the writer gets stuck in output loop on iPad 2

// encode AlphaGhost.mvid (480 x 320) -> AlphaGhost_encoded_h264.mov

+ (void) testEncodeAlphaGhostH264WithTrackWriter
{  
  NSString *tmpFilename = nil;
  NSString *tmpInputPath = nil;
  NSString *tmpOutputPath = nil;
    
  tmpInputPath = [self ensureDecodeOfAlphaGhostMvid];
  tmpFilename = @"AlphaGhost_encoded_h264.mov";
  
  // Make sure output file does not exists before running test
  
  NSString *tmpDir = NSTemporaryDirectory();
  tmpOutputPath = [tmpDir stringByAppendingPathComponent:tmpFilename];
  BOOL fileExists = [AVFileUtil fileExists:tmpOutputPath];
  
  if (fileExists) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpOutputPath error:nil];
    NSAssert(worked, @"could not remove tmp file");    
  }
  
  // Define input .mvid file as the video data source
  
  AVAssetWriterConvertFromMaxvid *obj = [AVAssetWriterConvertFromMaxvid aVAssetWriterConvertFromMaxvid];
  
  NSAssert([obj retainCount] == 1, @"retainCount");
  
  obj.inputPath = tmpInputPath;
  obj.outputPath = tmpOutputPath;
  
  [obj blockingEncode];
  
  // FIXME: success must wait until other thread is done once threading is enabled.
  
  NSAssert(obj.state == AVAssetWriterConvertFromMaxvidStateSuccess, @"success");
  
  NSLog(@"wrote %@", obj.outputPath);
  
  return;
}

// Non-blocking encode of same video from previous test

+ (void) testEncodeAlphaGhostH264WithTrackWriterNonBlocking
{  
  NSString *tmpFilename = nil;
  NSString *tmpInputPath = nil;
  NSString *tmpOutputPath = nil;
  
  tmpInputPath = [self ensureDecodeOfAlphaGhostMvid];
  tmpFilename = @"AlphaGhost_encoded_h264.mov";
  
  // Make sure output file does not exists before running test
  
  NSString *tmpDir = NSTemporaryDirectory();
  tmpOutputPath = [tmpDir stringByAppendingPathComponent:tmpFilename];
  BOOL fileExists = [AVFileUtil fileExists:tmpOutputPath];
  
  if (fileExists) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpOutputPath error:nil];
    NSAssert(worked, @"could not remove tmp file");    
  }
  
  // Define input .mvid file as the video data source
  
  AVAssetWriterConvertFromMaxvid *obj = [AVAssetWriterConvertFromMaxvid aVAssetWriterConvertFromMaxvid];
  
  NSAssert([obj retainCount] == 1, @"retainCount");
  
  obj.inputPath = tmpInputPath;
  obj.outputPath = tmpOutputPath;
  
  // This util object gets a notification, it is useful for testing purposes. In real code the view controller
  // or some other object would process the notification in the module.
  
  AVAssetWriterConvertFromMaxvid_NotificationUtil *notificationUtil = [AVAssetWriterConvertFromMaxvid_NotificationUtil notificationUtil];
  
  [notificationUtil setupNotification:obj];
  
  [obj nonblockingEncode];
  
  // Wait in loop until Notification is delivered. Note that this wasDelivered flag is set only
  // in the main thread, so there is no danger of a threaded race condition.
  
  while (TRUE) {
    if (notificationUtil.wasDelivered) {
      break;
    }
    
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  NSLog(@"wrote %@", obj.outputPath);
  
  return;
}

// FIXME: Test disabled since it currently depends on test ordering to generate the
// .mvid in the tmp file in another test.

// superwalk.mvid () -> superwalk_h264.mov

// Encode and existing .mvid video file as a .m4v video file compressed with H264 codec.

+ (void) DISABLED_testDecodeAndEncodeSuperwalkH264WithFrameDecoder
{
  NSString *resourceName = @"superwalk_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"superwalk_h264.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  AVAsset2MvidResourceLoader *loader = [AVAsset2MvidResourceLoader aVAsset2MvidResourceLoader];
  loader.movieFilename = [fileURL path];
  loader.outPath = tmpPath;
  
  [loader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:loader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  if (TRUE) {
    // Now that .h264 has been decoded to .mvid, encode the same movie to .h264 again
    
    NSString *tmpEncodedFilename = @"superwalk_h264_encoded.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

// FIXME: add a working emit test where the named file already exists on the filesystem.
// The output logic should remove an existing file with the given name if it exists.

// Aspect Ratio Info
//128
// http://clipstream.com/help/video3/aspect_ratios.shtml

// FIXME: need determine if encoding some other video at like 200x200 works. Still not clear
// if these API calls are really correct. Might just be a problem with the specific video sizes.


// Iterate over a series of movie dimensions and determine if a 2 frame animation is
// encoding properly. This test case will encode a 2 frame animation over and over to
// determine if the H.264 encoding for a specific width x height.

+ (BOOL) util_encodeTwoFrameBlackBlueAsH264:(CGSize)size
                                h264TmpPath:(NSString*)h264TmpPath
{
  if ([AVFileUtil fileExists:h264TmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:h264TmpPath error:nil];
    NSAssert(worked, @"rm failed");
  }
  
  // Define input .mvid file as the video data source
  
  AVAssetWriterConvertFromMaxvid *obj = [AVAssetWriterConvertFromMaxvid aVAssetWriterConvertFromMaxvid];
  
  NSAssert([obj retainCount] == 1, @"retainCount");
  
  CGFrameBuffer *buffer0 = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:size.width height:size.height];
  CGFrameBuffer *buffer1 = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:size.width height:size.height];
  
  CGImageRef imgRef0 = [buffer0 createCGImageRef];
  UIImage *image0 = [UIImage imageWithCGImage:imgRef0];
  CGImageRelease(imgRef0);
  
  // Fill all pixels with a blue pixel value
  
  {
    uint32_t bluePixel = 0xFF0000FF; // BGRA
    
    uint32_t numPixels = (buffer1.width * buffer1.height);
    uint32_t *pixels = (uint32_t*) buffer1.pixels;
    
    for (int i=0; i < numPixels; i++) {
      pixels[i] = bluePixel;
    }
  }
  
  // FIXME: fill buffer1 with blue pixels!
  
  CGImageRef imgRef1 = [buffer1 createCGImageRef];
  UIImage *image1 = [UIImage imageWithCGImage:imgRef1];
  CGImageRelease(imgRef1);

  // Save as 2 PNG files in the tmp dir

  NSString *tmpPath0 = [AVFileUtil getTmpDirPath:@"tmp1.png"];
  NSString *tmpPath1 = [AVFileUtil getTmpDirPath:@"tmp2.png"];
  
  NSData *data0 = [NSData dataWithData:UIImagePNGRepresentation(image0)];
  [data0 writeToFile:tmpPath0 atomically:YES];

  NSData *data1 = [NSData dataWithData:UIImagePNGRepresentation(image1)];
  [data1 writeToFile:tmpPath1 atomically:YES];
  
  NSURL *url0 = [NSURL fileURLWithPath:tmpPath0];
  NSURL *url1 = [NSURL fileURLWithPath:tmpPath1];
  
  // Create frame loader from 2 tmp files
  
  NSArray *urls = [NSArray arrayWithObjects:url0, url1, nil];

  AVImageFrameDecoder *frameDecoder = [AVImageFrameDecoder aVImageFrameDecoder:urls cacheDecodedImages:FALSE];
  
  [frameDecoder setFrameDuration:0.5]; // 2 FPS
  
  obj.frameDecoder = frameDecoder;

  obj.outputPath = h264TmpPath;

  // Encode as H264 with a blocking operation
  
  [obj blockingEncode];
  
  //NSAssert(obj.state == AVAssetWriterConvertFromMaxvidStateSuccess, @"success");  
  //NSLog(@"wrote %@", obj.outputPath);
  
  if (obj.state == AVAssetWriterConvertFromMaxvidStateSuccess) {
    return TRUE;
  } else {
    return FALSE;
  }  
}

// Get all pixels values from an image as 32 bpp values

+ (void) getPixels32BPP:(UIImage*)image
                 offset:(int)offset
                nPixels:(int)nPixels
               pixelPtr:(void*)pixelPtr
{
  // Query pixel data at a specific pixel offset
  CGImageRef imgRef = image.CGImage;
  CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(imgRef));
  CFDataGetBytes(pixelData, CFRangeMake(offset, sizeof(uint32_t) * nPixels), (UInt8*)pixelPtr);
  CFRelease(pixelData);
}

// Convert a 32 bpp color value in BGRA native format to a string #RRGGBBAA

+ (NSString*) pixelToString:(uint32_t)pixel
{
  uint32_t alpha = (pixel >> 24) & 0xFF;
  uint32_t red = (pixel >> 16) & 0xFF;
  uint32_t green = (pixel >> 8) & 0xFF;
  uint32_t blue = (pixel >> 0) & 0xFF;  
  NSString *pixelString = [NSString stringWithFormat:@"#%0.2X%0.2X%0.2X%0.2X", red, green, blue, alpha];
  return pixelString;
}

// Convert a 32 bpp color value in BGRA native format to a string #RGBA where
// each value is divided by 8 to provide a rough estimate of the pixel value.

+ (NSString*) pixelToString8:(uint32_t)pixel
{
  uint32_t alpha = (pixel >> 24) & 0xFF;
  uint32_t red = (pixel >> 16) & 0xFF;
  uint32_t green = (pixel >> 8) & 0xFF;
  uint32_t blue = (pixel >> 0) & 0xFF;
  red /= 16;
  green /= 16;
  blue /= 16;
  alpha /= 16;
  NSString *pixelString = [NSString stringWithFormat:@"#%0.1X%0.1X%0.1X%0.1X", red, green, blue, alpha];
  return pixelString;
}

// Get all pixels values from an image as 32 bpp values

+ (NSArray*) getPixelsAsArray32BPP:(UIImage*)image
{
  NSMutableArray *mArr = [NSMutableArray array];
  
  int width = image.size.width;
  int height = image.size.height;
  uint32_t *pixels = malloc(sizeof(uint32_t) * width * height);
  if (pixels == NULL) {
    return nil;
  }

  memset(pixels, 0, sizeof(uint32_t) * width * height);
  [self getPixels32BPP:image offset:0 nPixels:(width * height) pixelPtr:pixels];
  
  for (int i=0; i < (width * height); i++) {
    uint32_t pixel = pixels[i];
    NSString *pixelString;
    if (FALSE) {
      pixelString = [self pixelToString:pixel];
    } else {
      pixelString = [self pixelToString8:pixel];      
    }
    [mArr addObject:pixelString];
  }
  
  free(pixels);
  return [NSArray arrayWithArray:mArr];
}

// Iterate over a series of movie dimensions and determine if a 2 frame animation is
// encoding properly. This test case will encode a 2 frame animation over and over to
// determine if the H.264 encoding for a specific width x height.

+ (BOOL) util_checkTwoFrameBlackBlueAsH264:(CGSize)size
                               h264TmpPath:(NSString*)h264TmpPath
{
  if ([AVFileUtil fileExists:h264TmpPath] == FALSE) {
    NSAssert(FALSE, @"!fileExists");
  }
  
  NSString *tmpDecodedFilename = @"decoded_from_h264.mvid";
  NSString *tmpDecodedFilenamePath = [AVFileUtil getTmpDirPath:tmpDecodedFilename];
  
  NSURL *inFileURL = [NSURL fileURLWithPath:h264TmpPath];
  //NSURL *outFileURL = [NSURL fileURLWithPath:tmpDecodedFilenamePath];
  
  AVAssetReaderConvertMaxvid *obj = [AVAssetReaderConvertMaxvid aVAssetReaderConvertMaxvid];
  obj.assetURL = inFileURL;
  obj.mvidPath = tmpDecodedFilenamePath;
  obj.genAdler = TRUE;

  // Blocking decode from .mov to .mvid
  
  BOOL worked = [obj blockingDecode];
  NSAssert(worked, @"blockingDecode");
  
  // Open decoded .mvid and examine file headers
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:obj.mvidPath];
  NSAssert(worked, @"worked");
  
  NSAssert([frameDecoder numFrames] == 2, @"numFrames");
  
  NSAssert([frameDecoder frameDuration] == 0.5, @"frameDuration");
  
  worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked, @"worked");
  
  AVFrame *frame;
  UIImage *img;  
  CGSize expectedSize = size;
  CGSize imgSize;
  NSArray *pixelsArr;
  NSString *expectedApproxPixel;
  
  NSString *frame0TmpFilename = @"frame0.png";
  NSString *frame1TmpFilename = @"frame1.png";
  NSString *tmpPNGFilenamePath;
  
  if (TRUE) {
    tmpPNGFilenamePath = [AVFileUtil getTmpDirPath:frame0TmpFilename];
    [[NSFileManager defaultManager] removeItemAtPath:tmpPNGFilenamePath error:nil];
    tmpPNGFilenamePath = [AVFileUtil getTmpDirPath:frame1TmpFilename];    
    [[NSFileManager defaultManager] removeItemAtPath:tmpPNGFilenamePath error:nil];
  }
  
  frame = [frameDecoder advanceToFrame:0];
  NSAssert(frame, @"frame 0");
  img = frame.image;
  
  imgSize = img.size;
  if (CGSizeEqualToSize(imgSize, expectedSize) == FALSE) {
    // It is possible that an odd width value could be returned as a larger even value
    // after being rounded up during the encoding process.
    
    //NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    return FALSE;
  }
  
  if (FALSE) {
    // Dump frame 0 to tmp PNG file
    
    tmpPNGFilenamePath = [AVFileUtil getTmpDirPath:frame0TmpFilename];
   
    NSData *data = [NSData dataWithData:UIImagePNGRepresentation(img)];
    [data writeToFile:tmpPNGFilenamePath atomically:YES];
    NSLog(@"wrote %@", tmpPNGFilenamePath);
  }
  
  // All pixels should be black in color (just needs to be close)
  
  pixelsArr = [self getPixelsAsArray32BPP:img];
  expectedApproxPixel = @"#000F";
  
  for (NSString *pixel in pixelsArr) {
    BOOL same = [pixel isEqualToString:expectedApproxPixel];

    if (!same) {
      return FALSE;      
    }
  }
  
  // Frame 1 is all blue pixels
  
  frame = [frameDecoder advanceToFrame:1];
  NSAssert(frame, @"frame 1");
  img = frame.image;
  
  imgSize = img.size;
  NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
  
  if (FALSE) {
    // Dump frame 1 to tmp PNG file
    
    tmpPNGFilenamePath = [AVFileUtil getTmpDirPath:frame1TmpFilename];
    
    NSData *data = [NSData dataWithData:UIImagePNGRepresentation(img)];
    [data writeToFile:tmpPNGFilenamePath atomically:YES];
    NSLog(@"wrote %@", tmpPNGFilenamePath);
  }
  
  // All pixels should be blue in color (just needs to be close)
  
  pixelsArr = [self getPixelsAsArray32BPP:img];
  expectedApproxPixel = @"#00FF";
  
  for (NSString *pixel in pixelsArr) {
    BOOL same = [pixel isEqualToString:expectedApproxPixel];
    
    if (!same) {
      return FALSE;      
    }
  }
  
  return TRUE;
}

// Encode and check a 2 frame animation. First the frames are generated, then
// they are encoded as H264. Finally, the frames are decoded from H264
// and then the color values of each pixel are checked.

+ (BOOL) util_encodeAndCheckTwoFrameBlackBlueAsH264:(CGSize)size
                                        h264TmpPath:(NSString*)h264TmpPath
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL worked;
  
  worked = [self util_encodeTwoFrameBlackBlueAsH264:size h264TmpPath:h264TmpPath];
  if (worked) {
    worked = [self util_checkTwoFrameBlackBlueAsH264:size h264TmpPath:h264TmpPath];
  }
  
  [pool drain];
  
  if (worked) {
    NSLog(@"encoding successful :\t%d\tx\t%d", (int)size.width, (int)size.height); 
  } else {
    //NSLog(@"encoding %d x %d buffers failed", (int)size.width, (int)size.height);   
  }
  
  return worked;
}

// This test checks the encoding logic at different sizes. This test boils down the different
// poosible results to a BOOL indicating the status of an encode.

+ (void) testEncodeH264VideoOfDifferentWidthHeight
{
  NSString *tmpEncodedFilename = @"encode_h264.mov";
  NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
  
  BOOL worked;
  
  worked = [self util_encodeAndCheckTwoFrameBlackBlueAsH264:CGSizeMake(128, 128) h264TmpPath:tmpEncodedFilenamePath];
  NSAssert(worked == TRUE || worked == FALSE, @"worked"); // just do disable static analyzer warning
  
  worked = [self util_encodeAndCheckTwoFrameBlackBlueAsH264:CGSizeMake(129, 128) h264TmpPath:tmpEncodedFilenamePath];
  NSAssert(worked == TRUE || worked == FALSE, @"worked"); // just do disable static analyzer warning
  
  return;
}

// This test checks the encoding logic at different sizes. This test boils down the different
// poosible results to a BOOL indicating the status of an encode.

+ (void) DISABLED_testEncodeH264Extensive
{
  NSString *tmpEncodedFilename = @"encode_h264.mov";
  NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
  
  BOOL worked;
  int width;
  int height;
  int maxWidth;
  int maxHeight;

  // Test every encoding size from 16x16 to 512x512
  
  width = 16;
  height = 16;
  maxWidth = 512;
  maxHeight = 512;
  
  // iPhone => 480 x 320 (960 x 640 pixels)
  // iPad 1 and 2 => 1024 x 768
  // iPas 3 => 2048 x 1536
 
  // h.264 support
  // iPhone3 => 640x480 (playback only, no encoder)
  // iPhone4 => 720p (1280x720) at 16:9
  // iPhone4S => 1080p (1920 × 1080) at 16:9
  
  // Max H264 dimensions on iPhone 640 x 480 pixels
  
  while (TRUE) {
    // max width 512
    // max height 512
        
    //NSLog(@"testing %d x %d", width, height);
    
    if (width > maxWidth) {
      width = 16;
      height++;
    }

    if (height > maxHeight) {
      break;
    }

    BOOL skip = FALSE;
    
    if ((width % 2) != 0) {
      // Ignore odd width
      skip = TRUE;
    }
    if ((height % 2) != 0) {
      // Ignore odd height
      skip = TRUE;
    }
    
    if (skip == FALSE) {
      worked = [self util_encodeAndCheckTwoFrameBlackBlueAsH264:CGSizeMake(width, height) h264TmpPath:tmpEncodedFilenamePath];
      NSAssert(worked == TRUE || worked == FALSE, @"worked"); // just do disable static analyzer warning
    }
    
    width++;
  }
    
  return;
}

// Test H264 frame decoder in isolation

+ (void) testDecodeH264FramesAt64x64
{
  NSString *resourceName = @"64x64_nop_3frames_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];

  // Create frame decoder that will read 1 frame at a time from an asset file.
  // This type of frame decoder is constrained as compared to a MVID frame
  // decoder. It can only decode 1 frame at a time as only 1 frame can be
  // in memory at a time. Also, it only works for sequential frames, so
  // this frame decoder cannot be used in a media object.
  
  AVAssetFrameDecoder *frameDecoder = [AVAssetFrameDecoder aVAssetFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:resPath];
  NSAssert(worked, @"worked");
  
  NSAssert([frameDecoder numFrames] == 3, @"numFrames");
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked, @"worked");
  
  BOOL emitFrames = TRUE;
  
  AVFrame *frame;
  UIImage *img;
  NSData *data;
  NSString *path;
  
  CGSize expectedSize = CGSizeMake(64, 64);
  CGSize imgSize;
  
  // Dump frame 1
  
  frame = [frameDecoder advanceToFrame:0];
  NSAssert(frame, @"frame 0");
  img = frame.image;
  
  imgSize = img.size;
  NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
  
  if (emitFrames) {
    path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
    data = [NSData dataWithData:UIImagePNGRepresentation(img)];
    [data writeToFile:path atomically:YES];
    NSLog(@"wrote %@", path);
  }
  
  // Dump frame 2
  
  frame = [frameDecoder advanceToFrame:1];
  NSAssert(frame, @"frame 1");
  img = frame.image;
  
  imgSize = img.size;
  NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
  
  if (emitFrames) {
    path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame1.png"];
    data = [NSData dataWithData:UIImagePNGRepresentation(img)];
    [data writeToFile:path atomically:YES];
    NSLog(@"wrote %@", path);
  }

  // Dump frame 3
  
  frame = [frameDecoder advanceToFrame:2];
  NSAssert(frame, @"frame 2");
  img = frame.image;
  
  imgSize = img.size;
  NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
  
  if (emitFrames) {
    path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame2.png"];
    data = [NSData dataWithData:UIImagePNGRepresentation(img)];
    [data writeToFile:path atomically:YES];
    NSLog(@"wrote %@", path);
  }
  
  // Check "all keyframes" flag
    
  BOOL isAllKeyframes = [frameDecoder isAllKeyframes];
  NSAssert(isAllKeyframes == TRUE, @"isAllKeyframes");
  
  return;
}

#endif // HAS_AVASSET_CONVERT_MAXVID

@end
