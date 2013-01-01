//
//  AVAssetJoinAlphaResourceLoaderTests.m
//
//  Created by Moses DeJong on 1/1/13.
//
//  License terms defined in License.txt.

#import "RegressionTests.h"

#import "AVAssetConvertCommon.h"

#import "AVAssetJoinAlphaResourceLoader.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

#import "CGFrameBuffer.h"

@interface AVAssetJoinAlphaResourceLoaderTests : NSObject {}
@end

// The methods named test* will be automatically invoked by the RegressionTests harness.

@implementation AVAssetJoinAlphaResourceLoaderTests

// This test case deals with decoding H.264 video as an MVID
// Available in iOS 4.1 and later.

#if defined(HAS_AVASSET_CONVERT_MAXVID)

// Read video data from a single track (only one video track is supported anyway)
// Note that while encoding a 32x32 .mov with H264 is not supported, it is perfectly
// fine to decode a H264 that is smaller than 128x128.

+ (void) testJoinAlphaForExplosionVideo
{
  //NSString *resPath;
  //NSURL *fileURL;
  NSString *tmpFilename;
  NSString *tmpPath;
  
  // Asset filenames
  
  NSString *rgbResourceName = @"ExplosionAdjusted_rgb_CRF_30_24BPP.m4v";
  NSString *alphaResourceName = @"ExplosionAdjusted_alpha_CRF_30_24BPP.m4v";
  
  // Output filename
  
  tmpFilename = @"ExplosionAdjusted.mvid";
  tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];

  // If the decode mov path exists currently, delete it so that this test case always
  // decodes the .mov from the .7z compressed Resource.
  
  if ([AVFileUtil fileExists:tmpPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
    NSAssert(worked, @"could not remove file %@", tmpPath);
  }
  
  AVAssetJoinAlphaResourceLoader *resLoader = [AVAssetJoinAlphaResourceLoader aVAssetJoinAlphaResourceLoader];
  
  resLoader.movieRGBFilename = rgbResourceName;
  resLoader.movieAlphaFilename = alphaResourceName;
  resLoader.outPath = tmpPath;
  resLoader.alwaysGenerateAdler = TRUE;

  // Wait for resource loading to be completed.
  
  [resLoader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader
                                      selector:@selector(isReady)
                                   maxWaitTime:30.0];
  NSAssert(worked, @"worked");
  
  NSLog(@"Wrote : %@", tmpPath);
  
  // Once loading is completed, examine the generated .mvid to check that the expected
  // results match the actual results.
  
  BOOL decodeFrames = TRUE;
  BOOL emitFrames = TRUE;
  
  if (decodeFrames) {
    // Create MVID frame decoder and iterate over the frames in the mvid file.
    // This will validate the emitted data via the adler checksum logic
    // in the decoding process.
    
    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    
    BOOL worked = [frameDecoder openForReading:tmpPath];
    NSAssert(worked, @"worked");
    
    NSAssert([frameDecoder numFrames] == 152, @"numFrames");
    
    worked = [frameDecoder allocateDecodeResources];
    NSAssert(worked, @"worked");
    
    AVFrame *frame;
    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(640, 480);
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

#endif // HAS_AVASSET_CONVERT_MAXVID

@end
