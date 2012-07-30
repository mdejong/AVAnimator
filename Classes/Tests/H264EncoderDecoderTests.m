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

#import "CGFrameBuffer.h"

#import "AVImageFrameDecoder.h"

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


// Iterate over a series of movie dimensions and determine if a 2 frame animation is
// encoding properly. This test case will encode a 2 frame animation over and over to
// determine if the H.264 encoding for a specific width x height.

+ (void) util_encodeTwoFrameBlackBlueAsH264:(CGSize)size
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
  
  NSAssert(obj.state == AVAssetWriterConvertFromMaxvidStateSuccess, @"success");
  
  NSLog(@"wrote %@", obj.outputPath);
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
  
  BOOL worked = [obj decodeAssetURL];
  NSAssert(worked, @"decodeAssetURL");
  
  // Open decoded .mvid and examine file headers
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:obj.mvidPath];
  NSAssert(worked, @"worked");
  
  NSAssert([frameDecoder numFrames] == 2, @"numFrames");
  
  NSAssert([frameDecoder frameDuration] == 0.5, @"frameDuration");
  
  worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked, @"worked");
  
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
  
  img = [frameDecoder advanceToFrame:0];
  NSAssert(img, @"frame 0");
  
  imgSize = img.size;
  if (CGSizeEqualToSize(imgSize, expectedSize) == FALSE) {
    // It is possible that an odd width value could be returned as a larger even value
    // after being rounded up during the encoding process.
    
    //NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
    return FALSE;
  }
  
  if (TRUE) {
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
  
  img = [frameDecoder advanceToFrame:1];
  NSAssert(img, @"frame 1");
  
  imgSize = img.size;
  NSAssert(CGSizeEqualToSize(imgSize, expectedSize), @"size");
  
  if (TRUE) {
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
  
  [self util_encodeTwoFrameBlackBlueAsH264:size h264TmpPath:h264TmpPath];
  BOOL same = [self util_checkTwoFrameBlackBlueAsH264:size h264TmpPath:h264TmpPath];
  
  [pool drain];
  
  if (same) {
    NSLog(@"encoding %d x %d buffers was successful", (int)size.width, (int)size.height); 
  } else {
    NSLog(@"encoding %d x %d buffers failed", (int)size.width, (int)size.height);   
  }
  
  return same;
}

+ (void) testEncodeH264VideoOfDifferentWidthHeight
{
  NSString *tmpEncodedFilename = @"encode_h264.mov";
  NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
  
  BOOL worked;
  
  worked = [self util_encodeAndCheckTwoFrameBlackBlueAsH264:CGSizeMake(128, 128) h264TmpPath:tmpEncodedFilenamePath];
  
  worked = [self util_encodeAndCheckTwoFrameBlackBlueAsH264:CGSizeMake(129, 128) h264TmpPath:tmpEncodedFilenamePath];
  
  return;
}

#endif // HAS_AVASSET_CONVERT_MAXVID

@end
