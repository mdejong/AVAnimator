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


// This test case will attempt to decode a 16x16 H264 video and print out
// what the "extended" pixel info is.

+ (void) testDecode16x16H264WithFrameDecoder
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
    
  return;
}

+ (void) testDecode16x17H264WithFrameDecoder
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
  
  return;
}

+ (void) testDecode17x16H264WithFrameDecoder
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
  
  return;
}

+ (void) testDecode17x17H264WithFrameDecoder
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
  
  return;
}

+ (void) testDecode17x18H264WithFrameDecoder
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
  
  return;
}

+ (void) testDecode17x19H264WithFrameDecoder
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
  
  return;
}

+ (void) testDecode18x18H264WithFrameDecoder
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
  
  return;
}

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

// superwalk.mvid () -> superwalk_h264.mov

// Encode and existing .mvid video file as a .m4v video file compressed with H264 codec.

+ (void) testEncodeSuperwalkH264WithTrackWriter
{
  // Verify that "superwalk.mvid" already exists in the tmp dir. This test depends on
  // the output of an earlier test.
  
  NSString *tmpFilename = nil;
  NSString *tmpInputPath = nil;
  NSString *tmpOutputPath = nil;

  tmpFilename = @"superwalk.mvid";
  tmpInputPath = [AVFileUtil getTmpDirPath:tmpFilename];
  tmpFilename = @"superwalk_h264.mov";
  
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

// FIXME: need determine if encoding some other video at like 200x200 works. Still not clear
// if these API calls are really correct. Might just be a problem with the specific video sizes.

#endif // HAS_AVASSET_CONVERT_MAXVID

@end
