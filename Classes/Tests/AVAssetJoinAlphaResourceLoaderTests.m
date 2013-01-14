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

#import <QuartzCore/QuartzCore.h>

#import "AVAssetFrameDecoder.h"

#import "movdata.h"

#define MAX_WAIT 600

// Private API

@interface AVAssetJoinAlphaResourceLoader ()

@property (nonatomic, retain) AVAsset2MvidResourceLoader *rgbLoader;
@property (nonatomic, retain) AVAsset2MvidResourceLoader *alphaLoader;

+ (void) combineRGBAndAlphaPixels:(uint32_t)numPixels
                   combinedPixels:(uint32_t*)combinedPixels
                        rgbPixels:(uint32_t*)rgbPixels
                      alphaPixels:(uint32_t*)alphaPixels;

@end

// class AVAssetJoinAlphaResourceLoaderTests

@interface AVAssetJoinAlphaResourceLoaderTests : NSObject {}
@end

// The methods named test* will be automatically invoked by the RegressionTests harness.

@implementation AVAssetJoinAlphaResourceLoaderTests

// This test case deals with decoding H.264 video as an MVID
// Available in iOS 4.1 and later.

#if defined(HAS_AVASSET_CONVERT_MAXVID)

// This test method generates a PNG image that contains an alpha gradient
// that is 256x256. The alpha gradient is a grayscale with the values
// going from 0 to 255 vertically down.

+ (void) DISABLED_testEmitAlphaGrayscale
{
  int width = 256;
  int height = 256;
  
  CGFrameBuffer *framebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  
  uint32_t *pixelPtr = (uint32_t*)framebuffer.pixels;
  
  for (uint32_t rowi = 0; rowi < height; rowi++) {
    for (uint32_t coli = 0; coli < width; coli++) {
      uint32_t pixel = (0xFF << 24) | (rowi << 16) | (rowi << 8) | rowi;
      *pixelPtr++ = pixel;
    }
  }
  
  CGImageRef imageRef = [framebuffer createCGImageRef];
  
  UIImage *uiImageRef = [UIImage imageWithCGImage:imageRef];
  
  assert(uiImageRef);
  
  CGImageRelease(imageRef);
  
  NSString *tmpDir = NSTemporaryDirectory();
  
  NSString *tmpPNGPath = [tmpDir stringByAppendingFormat:@"Grayscale256x256.png"];
  
  NSData *data = [NSData dataWithData:UIImagePNGRepresentation(uiImageRef)];
  [data writeToFile:tmpPNGPath atomically:YES];
  NSLog(@"wrote %@", tmpPNGPath);
  
  return;
}

+ (NSString *) util_pixelToRGBAStr:(uint32_t)pixel
{
  uint32_t alpha = (pixel >> 24) & 0xFF;
  uint32_t red = (pixel >> 16) & 0xFF;
  uint32_t green = (pixel >> 8) & 0xFF;
  uint32_t blue = (pixel >> 0) & 0xFF;
  return [NSString stringWithFormat:@"(%d, %d, %d, %d)", red, green, blue, alpha];
}

// Test alpha channel decode logic in combineRGBAndAlphaPixels using lossless
// PNG input. The input data is known to be consistent with this input,
// so testing of the joined results will work as expected.

+ (void) testDecodeAlphaGradientFromPNG
{
  UIImage *img = [UIImage imageNamed:@"Grayscale256x256"];
  NSAssert(img, @"img");
  
  int width = 256;
  int height = 256;
  CGSize expectedSize = CGSizeMake(width, height);
  int numPixels = width * height;
    
  NSAssert(CGSizeEqualToSize(img.size, expectedSize), @"expectedSize");
  
  // Allocate framebuffer and copy pixels from PNG into the framebuffer
  
  CGFrameBuffer *framebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  
  [framebuffer renderCGImage:img.CGImage];
  
  // Allocate output buffer and phony RGB buffer with all white pixels
  
  uint32_t *rgbPixels = malloc(numPixels * sizeof(uint32_t));
  memset(rgbPixels, 0xff, numPixels * sizeof(uint32_t));
  
  uint32_t *combinedPixels = malloc(numPixels * sizeof(uint32_t));
  memset(combinedPixels, 0x0, numPixels * sizeof(uint32_t));
  
  uint32_t *alphaPixels = (uint32_t*) framebuffer.pixels;
  assert(framebuffer.numBytes == (numPixels * sizeof(uint32_t)));
  
  [AVAssetJoinAlphaResourceLoader combineRGBAndAlphaPixels:numPixels
                                            combinedPixels:combinedPixels
                                                 rgbPixels:rgbPixels
                                               alphaPixels:alphaPixels];
  
  // Alpha = 0 -> (0, 0, 0, 0)
  // Alpha = 1 -> (1, 1, 1, 1)
  // Alpha = 255 -> (255, 255, 255, 255)
  
  for (int rowi = 0; rowi < height; rowi++) {
    for (int coli = 0; coli < width; coli++) {
      uint32_t pixel = combinedPixels[(rowi * width) + coli];
      NSString *results = [self util_pixelToRGBAStr:pixel];
      NSString *expectedResults = [NSString stringWithFormat:@"(%d, %d, %d, %d)", rowi, rowi, rowi, rowi];
      NSAssert([results isEqualToString:expectedResults], @"pixel");
    }
  }
  
  return;
}

// This test is basically the same as the one above except that instead of all white
// pixels in the RGB buffer, the values increase from 0 to 255 as the columns increase.
// This results in a test pattern that will premultiply every possible value
// in the grayscale range.

+ (void) testDecodeAlphaGradientFromPNGWithAllPremult
{
  UIImage *img = [UIImage imageNamed:@"Grayscale256x256"];
  NSAssert(img, @"img");
  
  int width = 256;
  int height = 256;
  CGSize expectedSize = CGSizeMake(width, height);
  int numPixels = width * height;
  
  NSAssert(CGSizeEqualToSize(img.size, expectedSize), @"expectedSize");
  
  // Allocate framebuffer and copy pixels from PNG into the framebuffer
  
  CGFrameBuffer *framebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  
  [framebuffer renderCGImage:img.CGImage];
  
  // Allocate output buffer and phony RGB buffer with all white pixels
  
  uint32_t *rgbPixels = malloc(numPixels * sizeof(uint32_t));
  uint32_t *rgbPixelsWritePtr = rgbPixels;
  
  for (int rowi = 0; rowi < height; rowi++) {
    for (int coli = 0; coli < width; coli++) {
      uint32_t pixel = (0xFF << 24) | (coli << 16) | (coli << 8) | coli;
      *rgbPixelsWritePtr++ = pixel;
    }
  }
  
  uint32_t *combinedPixels = malloc(numPixels * sizeof(uint32_t));
  memset(combinedPixels, 0x0, numPixels * sizeof(uint32_t));
  
  uint32_t *alphaPixels = (uint32_t*) framebuffer.pixels;
  assert(framebuffer.numBytes == (numPixels * sizeof(uint32_t)));
  
  [AVAssetJoinAlphaResourceLoader combineRGBAndAlphaPixels:numPixels
                                            combinedPixels:combinedPixels
                                                 rgbPixels:rgbPixels
                                               alphaPixels:alphaPixels];  
  
  for (int rowi = 0; rowi < height; rowi++) {
    for (int coli = 0; coli < width; coli++) {
      uint32_t pixel = combinedPixels[(rowi * width) + coli];
      NSString *results = [self util_pixelToRGBAStr:pixel];
      int alpha = rowi;
      int gray = coli;
      {
        uint32_t premult = premultiply_bgra_inline(gray, gray, gray, alpha);
        gray = premult & 0xFF;
      }
      NSString *expectedResults = [NSString stringWithFormat:@"(%d, %d, %d, %d)", gray, gray, gray, alpha];
      NSAssert([results isEqualToString:expectedResults], @"pixel");
    }
  }
  
  return;
}

// Test alpha channel decode logic in combineRGBAndAlphaPixels. This logic needs to
// convert oddly decoded alpha values and decode to known results.

+ (void) testDecodeAlphaGradientFromH264Asset
{
  NSString *resourceName = @"Grayscale256x256.m4v";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  
  // Create frame decoder that will read 1 frame at a time from an asset file.
  // This type of frame decoder is constrained as compared to a MVID frame
  // decoder. It can only decode 1 frame at a time as only 1 frame can be
  // in memory at a time. Also, it only works for sequential frames, so
  // this frame decoder cannot be used in a media object.
  
  AVAssetFrameDecoder *frameDecoder = [AVAssetFrameDecoder aVAssetFrameDecoder];
  
  BOOL worked = [frameDecoder openForReading:resPath];
  NSAssert(worked, @"worked");
  
  NSAssert([frameDecoder numFrames] == 2, @"numFrames");
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  worked = [frameDecoder allocateDecodeResources];
  NSAssert(worked, @"worked");
    
  AVFrame *frame;
  UIImage *img;
  
  int width = 256;
  int height = 256;
  CGSize expectedSize = CGSizeMake(width, height);
  int numPixels = width * height;
  
  // Decode frame 1
  
  frame = [frameDecoder advanceToFrame:0];
  NSAssert(frame, @"frame 0");
  img = frame.image;
    
  NSAssert(CGSizeEqualToSize(img.size, expectedSize), @"expectedSize");
  
  BOOL emitFrames = FALSE;
  
  if (emitFrames) {
    NSString *path;
    NSData *data;
    path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"frame0.png"];
    data = [NSData dataWithData:UIImagePNGRepresentation(img)];
    [data writeToFile:path atomically:YES];
    NSLog(@"wrote %@", path);
  }
  
  // Allocate output buffer and phony RGB buffer with all white pixels
  
  uint32_t *rgbPixels = malloc(numPixels * sizeof(uint32_t));
  memset(rgbPixels, 0xff, numPixels * sizeof(uint32_t));

  uint32_t *combinedPixels = malloc(numPixels * sizeof(uint32_t));
  memset(combinedPixels, 0x0, numPixels * sizeof(uint32_t));
  
  uint32_t *alphaPixels = (uint32_t*) frame.cgFrameBuffer.pixels;
  assert(frame.cgFrameBuffer.numBytes == (numPixels * sizeof(uint32_t)));
  
  [AVAssetJoinAlphaResourceLoader combineRGBAndAlphaPixels:numPixels
                                            combinedPixels:combinedPixels
                                                 rgbPixels:rgbPixels
                                               alphaPixels:alphaPixels];
  
  
  // Alpha = 0 -> (0, 0, 0, 0)
  // Alpha = 1 -> (1, 1, 1, 1)
  // Alpha = 255 -> (255, 255, 255, 255)
  
  for (int rowi = 0; rowi < height; rowi++) {
    for (int coli = 0; coli < width; coli++) {
      uint32_t pixel = combinedPixels[(rowi * width) + coli];
      NSString *results = [self util_pixelToRGBAStr:pixel];
      NSString *expectedResults = [NSString stringWithFormat:@"(%d, %d, %d, %d)", rowi, rowi, rowi, rowi];
      
      NSString *oneUp = [NSString stringWithFormat:@"(%d, %d, %d, %d)", rowi+1, rowi+1, rowi+1, rowi+1];
      NSString *oneDown = [NSString stringWithFormat:@"(%d, %d, %d, %d)", rowi-1, rowi-1, rowi-1, rowi-1];
      
      // The H264 lossy encoding could be off by 1 step, so make the test a bit fuzzy.
      // It would be a lot better if the input could be refined to make sure it is
      // lossless, but this is the best we can do for now. The output would be as
      // much as 1 step off, but that is not much. As long as the completely transparent
      // and completely opaque values are exacly correct, this is close enough.
      
      if (rowi == 0 || rowi == 255) {
        NSAssert([results isEqualToString:expectedResults], @"pixel");
      } else {
        
        NSAssert([results isEqualToString:expectedResults] ||
                 [results isEqualToString:oneUp] ||
                 [results isEqualToString:oneDown]
                 , @"pixel");
        
      }
    }
  }
  
  return;
}

// Read video data from a single track (only one video track is supported anyway)
// Note that while encoding a 32x32 .mov with H264 is not supported, it is perfectly
// fine to decode a H264 that is smaller than 128x128.

// Current iPad2 timing results: (note that loggin statements are enabled in these test results)
//
// Old impl, that would write 2 mvid files and then read and write a 3rd: 55 seconds
// New impl, reading frames directly from 2 asset files : 15 -> 22 seconds (big win)
//
// Optimized run w no adler generation : 10 seconds

+ (void) testJoinAlphaForExplosionVideo
{
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
  
  // Do not generate adler since this operation computationally expensive and we want to
  // test the execution time when emitting joined alpha frames.
  //resLoader.alwaysGenerateAdler = TRUE;

  // Wait for resource loading to be completed.
  
  [resLoader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader
                                      selector:@selector(isReady)
                                   maxWaitTime:MAX_WAIT];
  NSAssert(worked, @"worked");
  
  NSLog(@"Wrote : %@", tmpPath);
  
  // Once loading is completed, examine the generated .mvid to check that the expected
  // results match the actual results.
  
  BOOL decodeFrames = FALSE;
  BOOL emitFrames = FALSE;
  
  if (decodeFrames) {
    // Create MVID frame decoder and iterate over the frames in the mvid file.
    // This will validate the emitted data via the adler checksum logic
    // in the decoding process.
    
    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    
    BOOL worked = [frameDecoder openForReading:tmpPath];
    NSAssert(worked, @"worked");
    
    NSAssert([frameDecoder numFrames] == 152, @"numFrames");
    NSAssert([frameDecoder hasAlphaChannel] == TRUE, @"hasAlphaChannel");
    
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
    
    // The first framebuffer should have at least one non-black pixel. All pixels
    // were coming out black in a previous buggy version that did not read from
    // the zero copy pixels when inspecting buffer contents.
    
    uint32_t *pixelPtr = (uint32_t*)frame.cgFrameBuffer.pixels;
    uint32_t numPixels = frame.cgFrameBuffer.width * frame.cgFrameBuffer.height;
    BOOL has_non_zero_pixel = FALSE;
    
    for (int pixeli = 0; pixeli < numPixels; pixeli++) {
      uint32_t pixel = pixelPtr[pixeli];
      pixel &= 0xFFFF;
      if (pixel != 0x0) {
        has_non_zero_pixel = TRUE;
      }
    }
    NSAssert(has_non_zero_pixel, @"has_non_zero_pixel");
    
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
    
    // Check "all keyframes" flag
    
    BOOL isAllKeyframes = [frameDecoder isAllKeyframes];
    NSAssert(isAllKeyframes == TRUE, @"isAllKeyframes");
  }
  
  // remove large output file once done with test!
  
  if (TRUE) {
    worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:NULL];
    NSAssert(worked, @"rm %@", tmpPath);
  }
  
  return;
}

// Test a split version of the Alpha channel ghost video, this is actually of limited
// value because the simple animation compresses to 11 KB even at lossless settings,
// so H264 split encoding is actually about 2 times larger and takes longer to load.
// Thsi is only useful to test the decoder logic.

+ (void) testJoinAlphaGhost
{
  NSString *tmpFilename;
  NSString *tmpPath;
  
  // Asset filenames
  
  NSString *rgbResourceName = @"AlphaGhost_alpha_CRF_30_24BPP.m4v";
  NSString *alphaResourceName = @"AlphaGhost_rgb_CRF_30_24BPP.m4v";
  
  // Output filename
  
  tmpFilename = @"AlphaGhost_join_h264.mvid";
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
                                   maxWaitTime:MAX_WAIT];
  NSAssert(worked, @"worked");
  
  NSLog(@"Wrote : %@", tmpPath);
  
  // Once loading is completed, examine the generated .mvid to check that the expected
  // results match the actual results.
  
  BOOL decodeFrames = FALSE;
  BOOL emitFrames = TRUE;
  
  if (decodeFrames) {
    // Create MVID frame decoder and iterate over the frames in the mvid file.
    // This will validate the emitted data via the adler checksum logic
    // in the decoding process.
    
    AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
    
    BOOL worked = [frameDecoder openForReading:tmpPath];
    NSAssert(worked, @"worked");
    
    NSAssert([frameDecoder numFrames] == 7, @"numFrames");
    NSAssert([frameDecoder hasAlphaChannel] == TRUE, @"hasAlphaChannel");
    
    worked = [frameDecoder allocateDecodeResources];
    NSAssert(worked, @"worked");
    
    AVFrame *frame;
    UIImage *img;
    NSData *data;
    NSString *path;
    
    CGSize expectedSize = CGSizeMake(480, 320);
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
    
    // Check "all keyframes" flag
    
    BOOL isAllKeyframes = [frameDecoder isAllKeyframes];
    NSAssert(isAllKeyframes == TRUE, @"isAllKeyframes");
  }
  
  // remove large output file once done with test!
  
  if (TRUE) {
    worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:NULL];
    NSAssert(worked, @"rm %@", tmpPath);
  }
  
  return;
}

//+ (void) DISABLED_testJoinAlphaForExplosionVideo2
//{
//  [self testJoinAlphaForExplosionVideo];
//  [self testJoinAlphaForExplosionVideo];
//  [self testJoinAlphaForExplosionVideo];
//  [self testJoinAlphaForExplosionVideo];
//  [self testJoinAlphaForExplosionVideo];
//}

#endif // HAS_AVASSET_CONVERT_MAXVID

@end
