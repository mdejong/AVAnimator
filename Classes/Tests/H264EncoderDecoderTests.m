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
#import "AVQTAnimationFrameDecoder.h"

#import "AV7zAppResourceLoader.h"
#import "AV7zQT2MvidResourceLoader.h"

#import "AVApng2MvidResourceLoader.h"
#import "AV7zApng2MvidResourceLoader.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

#import "AVAssetReaderConvertMaxvid.h"

#import "AVAsset2MvidResourceLoader.h"

#import "AVAssetWriterConvertFromMaxvid.h"


// Util class for use in testing

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
  // AVAssetWriterConvertFromMaxvidFailedNotification

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(completedLoadNotification:) 
                                               name:AVAssetWriterConvertFromMaxvidCompletedNotification
                                             object:obj];    

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(failedToLoadNotification:) 
                                               name:AVAssetWriterConvertFromMaxvidFailedNotification
                                             object:obj];  
}

- (void) completedLoadNotification:(NSNotification*)notification
{
  self.wasDelivered = TRUE;
}

- (void) failedToLoadNotification:(NSNotification*)notification
{
  self.wasDelivered = TRUE;
}

@end // NotificationUtil



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
  
  BOOL worked = [obj decodeAssetURL];
  NSAssert(worked, @"decodeAssetURL");
  
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

    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(32, 32);
    CGSize imgSize;
    
    img = [frameDecoder advanceToFrame:0];
    NSAssert(img, @"frame 0");

    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
    path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
    data = [NSData dataWithData:UIImagePNGRepresentation(img)];
    [data writeToFile:path atomically:YES];
    NSLog(@"wrote %@", path);
    }
    
    img = [frameDecoder advanceToFrame:1];
    NSAssert(img, @"frame 1");

    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
    path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame1.png"];
    data = [NSData dataWithData:UIImagePNGRepresentation(img)];
    [data writeToFile:path atomically:YES];
    NSLog(@"wrote %@", path);
    }
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
  
  BOOL worked = [obj decodeAssetURL];
  NSAssert(worked, @"decodeAssetURL");
  
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
    
    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(86, 114);
    CGSize imgSize;
    
    img = [frameDecoder advanceToFrame:0];
    NSAssert(img, @"frame 0");
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    img = [frameDecoder advanceToFrame:1];
    NSAssert(img, @"frame 1");
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame1.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    img = [frameDecoder advanceToFrame:2];
    NSAssert(img, @"frame 2");
    
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
  
  BOOL worked = [obj decodeAssetURL];
  NSAssert(worked, @"decodeAssetURL");
  
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
    
    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(86, 114);
    CGSize imgSize;
    
    img = [frameDecoder advanceToFrame:0];
    NSAssert(img, @"frame 0");
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    img = [frameDecoder advanceToFrame:1];
    NSAssert(img, @"frame 1");
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame1.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    img = [frameDecoder advanceToFrame:2];
    NSAssert(img, @"frame 2");
    
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
    
    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(86, 114);
    CGSize imgSize;
    
    img = [frameDecoder advanceToFrame:0];
    NSAssert(img, @"frame 0");
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    img = [frameDecoder advanceToFrame:1];
    NSAssert(img, @"frame 1");
    
    imgSize = img.size;
    NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    
    if (emitFrames) {
      path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame1.png"];
      data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:path atomically:YES];
      NSLog(@"wrote %@", path);
    }
    
    img = [frameDecoder advanceToFrame:2];
    NSAssert(img, @"frame 2");
    
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

// FIXME: disabled because the writer gets stuck in output loop on iPad 2

// AlphaGhost_ANI.mvid (480 x 320) -> AlphaGhost_encoded_h264.mov

+ (void) testEncodeAlphaGhostH264WithTrackWriter
{  
  NSString *tmpFilename = nil;
  NSString *tmpInputPath = nil;
  NSString *tmpOutputPath = nil;
  
  tmpFilename = @"AlphaGhost_ANI.mvid";
  tmpInputPath = [AVFileUtil getResourcePath:tmpFilename];
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
  
  tmpFilename = @"AlphaGhost_ANI.mvid";
  tmpInputPath = [AVFileUtil getResourcePath:tmpFilename];
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
  
  // Wait in loop until Notification is delivered.
  
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

#endif // HAS_AVASSET_CONVERT_MAXVID

@end
