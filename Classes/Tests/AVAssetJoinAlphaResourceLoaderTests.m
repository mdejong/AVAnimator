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

@interface AVMvidFrameDecoder ()

@property (nonatomic, assign) MVFrame *mvFrames;

@end

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

int testJoinAlphaForExplosionVideoCheckAdler_simulator_expectedAdler[] = {
	0xe5b36272,
	0x37d6464,
	0x4c74fa70,
	0xd99ca62e,
	0x9e872ce5,
	0x4c7030f1,
	0x560c962d,
	0xc98a3482,
	0x50a35f94,
	0x19b7ce20,
	0x27b8b6e5,
	0x88cac28c,
	0x6a072aaf,
	0xc7058bbc,
	0x90a90f10,
	0x61db1263,
	0x37f35f9b,
	0xc450be95,
	0xfc8664da,
	0x2bbef514,
	0x6894896b,
	0xbdf7b7e0,
	0xc1e44be,
	0x7bba3d4a,
	0xa71b52b6,
	0x1150da10,
	0xa2b4b69b,
	0x76df7aad,
	0x771832b8,
	0x6da2cfa6,
	0xa897a995,
	0x3ab6b0f3,
	0x1a6848fa,
	0x788b6697,
	0x618cc407,
	0xb305e3a9,
	0x99517929,
	0x89e78016,
	0x70613f59,
	0xaa44d9ee,
	0x3f577f9c,
	0xfc97b818,
	0x9744c892,
	0xf39dc14,
	0x95735ee0,
	0x712f1894,
	0x8bca576e,
	0xfbef12b4,
	0x6568bd53,
	0x8c66003a,
	0xea17fbaf,
	0xfbd9c65d,
	0x4d64505e,
	0x46dac30,
	0x86d1f373,
	0xc6d70c3f,
	0x85dc6a36,
	0xb938c6af,
	0x82f98f59,
	0x23c2eab6,
	0x960732ee,
	0xeff8a765,
	0x9cbf5294,
	0x7facebc6,
	0x999b70e6,
	0xde387517,
	0x2a1c54a3,
	0x2449eda1,
	0x808507ec,
	0x8af3cdb1,
	0x37da8c15,
	0x3e07312b,
	0x462cc92a,
	0x32253e72,
	0x59fbe6ea,
	0xc2872d2b,
	0x9889a542,
	0x5bb3155f,
	0x525bccb9,
	0xecfa6c1e,
	0x32519cdc,
	0x2e132fa6,
	0xac942779,
	0xc6356da9,
	0xb639a988,
	0xfac74772,
	0x6cbf4427,
	0x64fa3858,
	0x6a03120a,
	0x943d3837,
	0x65423435,
	0x9d90dab2,
	0x5837829b,
	0xa5c35e67,
	0x2b852cba,
	0x84789f55,
	0x7173c575,
	0x6ec3cd37,
	0xe1dae9da,
	0x1230f049,
	0x26550bc,
	0x3ef70961,
	0x184f121c,
	0x776d3976,
	0x1150fd23,
	0x38a90692,
	0xffb4d363,
	0x3ce53660,
	0xc0b73fc8,
	0x596d4ff4,
	0xa15236a2,
	0xe2f9ca5f,
	0x7c84a8f8,
	0xe5fb0e89,
	0xeb1024bc,
	0xd274da98,
	0x3da089b7,
	0x6c13233,
	0x8bf85fd0,
	0xbf0c6f0d,
	0xc942693c,
	0x9746826c,
	0xbbfec57a,
	0x9493a770,
	0x29fc8c3f,
	0x661079f9,
	0xcbe7ec13,
	0xd31142cf,
	0xea0fd378,
	0x1abc6f3a,
	0xa7bc1b2a,
	0x5b778898,
	0xe8241c43,
	0x9ab03f44,
	0x87b299e2,
	0x3774829d,
	0x74dcc179,
	0x8e8743c,
	0xb61c9c16,
	0xeeb0bf73,
	0x7580580e,
	0x4decee16,
	0x75805c2d,
	0x4dd5ac0f,
	0xee1ef03,
	0x15e7d47f,
	0xf99ca8be,
	0x10656314,
	0xc383f2ce,
	0xbaa5aed0,
	0xb2d56ca8,
	0x6e575d8d
};

int testJoinAlphaForExplosionVideoCheckAdler_device_expectedAdler[] = {
	0x3d2d6289,
	0x34176478,
	0x420bfa8b,
	0xb0a4a658,
	0xb3202cb7,
	0x71f6303e,
	0x79c796b4,
	0x678c351e,
	0x190361f3,
	0xfe64d263,
	0xf818bbed,
	0x301c91a,
	0x775c33d4,
	0x9e7b9698,
	0xef681d14,
	0xa9762356,
	0xf181725a,
	0x21dfd2ff,
	0xb10b7987,
	0x29120c18,
	0x2611a19f,
	0x1483cdb0,
	0x4cff590e,
	0x62ac5210,
	0x10726374,
	0x52fceab2,
	0xb000c716,
	0x9ec886f5,
	0x3ec33c52,
	0x5abed84c,
	0x86e0af26,
	0x4e36b579,
	0x90104a33,
	0x100d656e,
	0x385fbe7c,
	0x525dd8cb,
	0x4c8a6b9a,
	0x26226e61,
	0x9cc02a8f,
	0x8225c221,
	0xf17b6742,
	0x8cf89fd4,
	0xa313af44,
	0xebf5c20f,
	0x32f04341,
	0x335ffaf2,
	0x11ae3b19,
	0xd736f5aa,
	0x94479e3e,
	0xfc11e201,
	0x2a17db51,
	0x6306a894,
	0x9d4c339b,
	0x6a36906d,
	0x6daad6f7,
	0x5133eaf6,
	0xe45346c9,
	0x6461a134,
	0x87fc6558,
	0x6c6abefd,
	0xb9700749,
	0x60cb7b78,
	0x5091242f,
	0x2994b98f,
	0xd0793bf6,
	0x4f5f4001,
	0xc0bb2062,
	0x482fb688,
	0x74ced2e2,
	0x67849624,
	0xe16d52d0,
	0x5810fa42,
	0x25a997f4,
	0x50dd0c4a,
	0xc639b33e,
	0x9029fc44,
	0x6d767260,
	0x7b79de58,
	0x44729b55,
	0x2d82384d,
	0x90c670d,
	0x8f4bf8a5,
	0x5fbaf307,
	0x91c73900,
	0xe7a475f2,
	0x6f991523,
	0xe39b1609,
	0xaefa0933,
	0x196fe530,
	0x5c0f07d6,
	0x60010506,
	0x8798a72a,
	0xd74a4e29,
	0xe5282a7e,
	0xb2aef5ae,
	0x22966b2c,
	0xbe679354,
	0x9c149a9e,
	0x7eeebd8b,
	0xdc6d4aa,
	0x88083a59,
	0xf355f4a7,
	0xf1eeff0d,
	0x105227b5,
	0xca34e670,
	0xff54f093,
	0xaa5ac602,
	0x380824a3,
	0xfc0b2c2a,
	0x719b42d8,
	0xdd7b2ca3,
	0x5202c19c,
	0xa3c99ced,
	0xaa490646,
	0xea521d3e,
	0x65a1cf99,
	0x3d177ce,
	0x2292a1d,
	0x847257ba,
	0x754f6691,
	0x884f6021,
	0xdc0c7669,
	0x77d5be17,
	0x10409b29,
	0xe6038818,
	0x64c97a7e,
	0x6996ec21,
	0x82ba3e60,
	0xd0f9d4e8,
	0x4e586bb3,
	0xbc8a195f,
	0xc3728ca0,
	0xaf261e28,
	0x27734032,
	0xb1499f35,
	0x11e185bb,
	0xd093c45d,
	0x1dc575f3,
	0xa95f9eef,
	0x67aac0c8,
	0x1efa5a73,
	0x7e77efc5,
	0xc793630b,
	0x9f4dae66,
	0x8d28f2ab,
	0xbb93d457,
	0xc97da8c8,
	0x14d4630f,
	0xad4bf181,
	0x3ac3acca,
	0xb46ab8,
	0x5b95cbd
};

// Note that the expected adlers differ just slightly on the device because the H264
// decoder hardware does not decode losslessly, alpha pixel values can be off by 1.

+ (void) testJoinAlphaForExplosionVideoCheckAdler
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
  resLoader.alwaysGenerateAdler = TRUE;
  
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
    
  if (TRUE) {
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
    
    // Decode and verify each frame adler
    
    MVFrame *frames = frameDecoder.mvFrames;
    
    BOOL emitArray = FALSE;
    NSMutableString *emitStr = [NSMutableString string];
    
    [emitStr appendFormat:@"int expectedAdler[] = {\n"];
    
    for (int frameIndex = 0; frameIndex < [frameDecoder numFrames]; frameIndex++) {      
      MVFrame *frame = maxvid_file_frame(frames, frameIndex);
      int adler = frame->adler;
      
      if (emitArray) {
        [emitStr appendFormat:@"\t0x%x,\n", adler];
      } else {
        // Check the statically defined array of adlers vs the one we just generated
        
        int expectedAdler;
        if (TARGET_IPHONE_SIMULATOR) {
          expectedAdler = testJoinAlphaForExplosionVideoCheckAdler_simulator_expectedAdler[frameIndex];
        } else {
          expectedAdler = testJoinAlphaForExplosionVideoCheckAdler_device_expectedAdler[frameIndex];
        }
        assert(adler == expectedAdler);
      }
      
      //NSLog(@"adler[%d] = %d", frameIndex, adler);
    }
    
    if (emitArray) {
      NSRange range = NSMakeRange([emitStr length] - 2, 2);
      [emitStr deleteCharactersInRange:range];
      
      [emitStr appendFormat:@"\n}\n"];
      NSLog(@"emitStr:\n%@", emitStr);
    }
  }
  
  // remove large output file once done with test!
  
  if (TRUE) {
    worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:NULL];
    NSAssert(worked, @"rm %@", tmpPath);
  }
    
  return;
}

// Same as above but do not generate and adler checksum, since this takes quite
// a bit of CPU and memory access time.

+ (void) testJoinAlphaForExplosionVideoNoAdler
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
  
  BOOL decodeFrames = TRUE;
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

// This test does many iterations of the "alpha combine" operation using
// predefined alpha values that are not all the same.

+ (void) testExecutionTimeForManyCombineOperations
{
  int width = 256;
  int height = 256;
  int numPixels = width * height;

  // Alpha
  
  uint32_t *alphaPixels = malloc(numPixels * sizeof(uint32_t));
  uint32_t *alphaPixelsWritePtr = alphaPixels;
  
  for (int rowi = 0; rowi < height; rowi++) {
    for (int coli = 0; coli < width; coli++) {
      uint32_t pixel;
      
      // 1: all 3 same (optimized)
      // 2: (0, 0, 1)
      // 3: (3 1 3) or (2 0 2) -> (2) or (1)
      
      int rem = (coli % 4);
      
      if (rem == 0 || rem == 1) {
        // Twice as many of these
        pixel = (0xFF << 24) | (coli << 16) | (coli << 8) | coli;
      } else if (rem == 2) {
        pixel = (0xFF << 24) | (0 << 16) | (0 << 8) | 1;
      } else if (rem == 3) {
        pixel = (0xFF << 24) | (3 << 16) | (1 << 8) | 3;
      }

      *alphaPixelsWritePtr++ = pixel;
    }
  }
  
  // RGB
  
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

  NSLog(@"combine loop");
  
  const int count = 5000;
  for (int counti = 0; counti < count; counti++) {
    [AVAssetJoinAlphaResourceLoader combineRGBAndAlphaPixels:numPixels
                                              combinedPixels:combinedPixels
                                                   rgbPixels:rgbPixels
                                                 alphaPixels:alphaPixels];
    
  }
  
  NSLog(@"done combine loop");
  
  return;
}

// Check logic related to the movie filename, the is ready logic
// needs to be run before the load method can be invoked.

+ (void) testJoinAlphaForExplosionVideoIsReady
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
  
  // Invoke isReady to make sure it does not assert due to movie filename being nil
  
  BOOL isReady = [resLoader isReady];

  NSAssert(isReady == FALSE, @"isReady");
  
  NSAssert([resLoader.movieFilename isEqualToString:resLoader.movieRGBFilename], @"movieFilename");
  
  return;
}

#endif // HAS_AVASSET_CONVERT_MAXVID

@end
