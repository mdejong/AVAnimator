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

@interface H264EncoderDecoderTests : NSObject {}
@end

// The methods named test* will be automatically invoked by the RegressionTests harness.

@implementation H264EncoderDecoderTests

// This test case deals with decoding H.264 video as an MVID
// Available in iOS 4.1 and later.

#if defined(HAS_AVASSET_CONVERT_MAXVID)

// Read video data from a single track (only one video track is supported anyway)

+ (void) DISABLED_testDecodeH264WithTrackReader
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

+ (void) DISABLED_testDecodeSuperwalkH264WithTrackReader
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

+ (void) DISABLED_testDecodeStutterwalkH264WithTrackReader
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

+ (void) DISABLED_testDecodeSuperwalkH264WithFrameDecoder
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
  
  [obj encodeOutputFile];
  
  // FIXME: success must wait until other thread is done once threading is enabled.
  
  NSAssert(obj.state == AVAssetWriterConvertFromMaxvidStateSuccess, @"success");
  
  NSLog(@"wrote %@", obj.outputPath);
}

// This test case will attempt to decode a 16x16 H264 video and print out
// what the "extended" pixel info is.

+ (void) DISABLED_testDecode16x16H264WithFrameDecoder
{
  NSString *resourceName = @"16x16_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"16x16_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"16x16_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

+ (void) DISABLED_testDecode16x17H264WithFrameDecoder
{
  NSString *resourceName = @"16x17_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"16x17_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"16x17_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

+ (void) DISABLED_testDecode17x16H264WithFrameDecoder
{
  NSString *resourceName = @"17x16_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"17x16_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"17x16_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

+ (void) DISABLED_testDecode17x17H264WithFrameDecoder
{
  NSString *resourceName = @"17x17_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"17x17_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"17x17_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

+ (void) DISABLED_testDecode17x18H264WithFrameDecoder
{
  NSString *resourceName = @"17x18_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"17x18_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"17x18_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

+ (void) DISABLED_testDecode17x19H264WithFrameDecoder
{
  NSString *resourceName = @"17x19_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"17x19_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"17x19_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

+ (void) DISABLED_testDecode18x18H264WithFrameDecoder
{
  NSString *resourceName = @"18x18_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"18x18_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"18x18_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

+ (void) DISABLED_testDecodeAndEncode32x32H264WithFrameDecoder
{
  NSString *resourceName = @"32x32_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"32x32_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"32x32_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

// This 64x64 encode will fail on an iPhone 4 and on an iPad 2.

+ (void) DISABLED_testDecodeAndEncode64x64H264WithFrameDecoder
{
  NSString *resourceName = @"64x64_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"64x64_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"64x64_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
}

// This encode will fail on an iPad 2.

+ (void) DISABLED_testDecodeAndEncode96x96H264WithFrameDecoder
{
  NSString *resourceName = @"96x96_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"96x96_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"96x96_black_blue_encoded_h264.mov";
    NSString *tmpEncodedFilenamePath = [AVFileUtil getTmpDirPath:tmpEncodedFilename];
    
    [self util_encodeMvidAsH264:tmpPath h264TmpPath:tmpEncodedFilenamePath];
  }
  
  return;
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

// 3:2 aspect ration but smaller dimension that the 128 min size.
// This does not encode properly on an iPhone 4 (writes corrupted data)
// This fails to encode in an iPad 2

+ (void) DISABLED_testDecodeAndEncode120x80H264WithFrameDecoder
{
  NSString *resourceName = @"120x80_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"120x80_black_blue.mvid";
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
    
    NSString *tmpEncodedFilename = @"120x80_black_blue_encoded_h264.mov";
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

+ (void) DISABLED_testEncodeAlphaGhostH264WithTrackWriter
{
  // Verify that "superwalk.mvid" already exists in the tmp dir. This test depends on
  // the output of an earlier test.
  
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
  
  [obj encodeOutputFile];
  
  // FIXME: success must wait until other thread is done once threading is enabled.
  
  NSAssert(obj.state == AVAssetWriterConvertFromMaxvidStateSuccess, @"success");
  
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

// Aspect Ratio Info
//128
// http://clipstream.com/help/video3/aspect_ratios.shtml

// FIXME: need determine if encoding some other video at like 200x200 works. Still not clear
// if these API calls are really correct. Might just be a problem with the specific video sizes.

#endif // HAS_AVASSET_CONVERT_MAXVID

@end
