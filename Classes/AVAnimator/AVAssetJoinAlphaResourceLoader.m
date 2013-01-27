//
//  AVAssetJoinAlphaResourceLoader.m
//
//  Created by Moses DeJong on 1/1/13.
//
//  License terms defined in License.txt.
//

#import "AVAssetJoinAlphaResourceLoader.h"

#import "AVFileUtil.h"

#import "AVAsset2MvidResourceLoader.h"

#import "AVAssetReaderConvertMaxvid.h"

#import "AVAssetFrameDecoder.h"

#import "CGFrameBuffer.h"

#import "movdata.h"

//#define LOGGING

@interface AVAssetJoinAlphaResourceLoader ()

@property (nonatomic, retain) AVAsset2MvidResourceLoader *rgbLoader;
@property (nonatomic, retain) AVAsset2MvidResourceLoader *alphaLoader;

+ (void) combineRGBAndAlphaPixels:(uint32_t)numPixels
                   combinedPixels:(uint32_t*)combinedPixels
                        rgbPixels:(uint32_t*)rgbPixels
                      alphaPixels:(uint32_t*)alphaPixels;

@end

@implementation AVAssetJoinAlphaResourceLoader

@synthesize movieRGBFilename = m_movieRGBFilename;
@synthesize movieAlphaFilename = m_movieAlphaFilename;
@synthesize outPath = m_outPath;
@synthesize alwaysGenerateAdler = m_alwaysGenerateAdler;
@synthesize rgbLoader = m_rgbLoader;
@synthesize alphaLoader = m_alphaLoader;

+ (AVAssetJoinAlphaResourceLoader*) aVAssetJoinAlphaResourceLoader
{
  AVAssetJoinAlphaResourceLoader *obj = [[AVAssetJoinAlphaResourceLoader alloc] init];
  return [obj autorelease];
}

- (void) dealloc
{
  self.movieRGBFilename = nil;
  self.movieAlphaFilename = nil;
  self.outPath = nil;
  self.rgbLoader = nil;
  self.alphaLoader = nil;
  [super dealloc];
}

// Overload suerclass self.movieFilename getter so that standard loading
// process so that the movieRGBFilename property can be set instead
// of the self.movieFilename property.

- (NSString*) movieFilename
{
  return self.movieRGBFilename;
}

// Output movie filename must be redefined

- (NSString*) _getMoviePath
{
  return self.outPath;
}

// Create secondary thread to process operation

- (void) _detachNewThread:(BOOL)phony
             rgbAssetPath:(NSString*)rgbAssetPath
           alphaAssetPath:(NSString*)alphaAssetPath
             phonyOutPath:(NSString*)phonyOutPath
                  outPath:(NSString*)outPath
{
  NSNumber *serialLoadingNum = [NSNumber numberWithBool:self.serialLoading];
  
  uint32_t genAdler = self.alwaysGenerateAdler;
  NSNumber *genAdlerNum = [NSNumber numberWithInt:genAdler];
  NSAssert(genAdlerNum != nil, @"genAdlerNum");
  
  NSArray *arr = [NSArray arrayWithObjects:rgbAssetPath,
                  alphaAssetPath,
                  phonyOutPath, outPath,
                  serialLoadingNum, genAdlerNum, nil];
  NSAssert([arr count] == 6, @"arr count");
  
  [NSThread detachNewThreadSelector:@selector(decodeThreadEntryPoint:) toTarget:self.class withObject:arr];
}

// Define load method here to provide custom implementation that will load
// the needed .mvid files from .m4v (H264) video and then combine these
// two video sources into one single video that contains an alpha channel.
// This load method should be called from the main thread to kick off a
// secondary thread.

- (void) load
{
  // Avoid kicking off mutliple sync load operations. This method should only
  // be invoked from a main thread callback, so there should not be any chance
  // of a race condition involving multiple invocations of this load mehtod.
  
  if (startedLoading) {
    return;
  } else {
    startedLoading = TRUE;
  }
  
  premultiply_init(); // ensure thread safe init of premultiply table
  
  NSAssert(self.movieRGBFilename, @"movieRGBFilename");
  NSAssert(self.movieAlphaFilename, @"movieAlphaFilename");
  NSString *outPath = self.outPath;
  NSAssert(outPath, @"outPath not defined");
  
  NSString *qualRGBPath = [AVFileUtil getQualifiedFilenameOrResource:self.movieRGBFilename];
  NSAssert(qualRGBPath, @"qualRGBPath");

  NSString *qualAlphaPath = [AVFileUtil getQualifiedFilenameOrResource:self.movieAlphaFilename];
  NSAssert(qualAlphaPath, @"qualAlphaPath");
  
  self.movieFilename = @""; // phony assign to disable check in superclass
  
  // Superclass load method asserts that self.movieFilename is not nil
  [super load];
  
  // Create a loader that will run as a detached secondary thread. It is critical
  // that we be able to execute all of the operation logic in the secondary thread.
  
  NSString *phonyOutPath = [NSString stringWithFormat:@"%@.mvid", [AVFileUtil generateUniqueTmpPath]];
  
  [self _detachNewThread:FALSE
             rgbAssetPath:qualRGBPath
          alphaAssetPath:qualAlphaPath
            phonyOutPath:phonyOutPath
                 outPath:outPath];
  
  return;
}

- (BOOL) isReady
{
  return [super isReady];
}

// joinRGBAndAlpha
//
// Implement logic to join pixels from RGB video and Alpha video back into single .mvid
// with an alpha channel.

+ (BOOL) joinRGBAndAlpha:(NSString*)joinedMvidPath
                 rgbPath:(NSString*)rgbPath
               alphaPath:(NSString*)alphaPath
                genAdler:(BOOL)genAdler
{
  // Open both the rgb and alpha mvid files for reading
  
  AVAssetFrameDecoder *frameDecoderRGB = [AVAssetFrameDecoder aVAssetFrameDecoder];
  AVAssetFrameDecoder *frameDecoderAlpha = [AVAssetFrameDecoder aVAssetFrameDecoder];
  
  BOOL worked;
  worked = [frameDecoderRGB openForReading:rgbPath];
  
  if (worked == FALSE) {
    NSLog(@"error: cannot open RGB mvid filename \"%@\"", rgbPath);
    return FALSE;
  }
  
  worked = [frameDecoderAlpha openForReading:alphaPath];
  
  if (worked == FALSE) {
    NSLog(@"error: cannot open ALPHA mvid filename \"%@\"", alphaPath);
    return FALSE;
  }
  
  worked = [frameDecoderRGB allocateDecodeResources];

  if (worked == FALSE) {
    NSLog(@"error: cannot allocate RGB decode resources for filename \"%@\"", rgbPath);
    return FALSE;
  }
  
  worked = [frameDecoderAlpha allocateDecodeResources];

  if (worked == FALSE) {
    NSLog(@"error: cannot allocate ALPHA decode resources for filename \"%@\"", alphaPath);
    return FALSE;
  }
  
  // BPP for decoded asset is always 24 BPP

  // framerate
  
  NSTimeInterval frameRate = frameDecoderRGB.frameDuration;
  NSTimeInterval frameRateAlpha = frameDecoderAlpha.frameDuration;
  if (frameRate != frameRateAlpha) {
    NSLog(@"error: RGB movie fps %.4f does not match alpha movie fps %.4f",
          1.0f/(float)frameRate, 1.0f/(float)frameRateAlpha);
    return FALSE;
  }

  // num frames
  
  NSUInteger numFrames = [frameDecoderRGB numFrames];
  NSUInteger numFramesAlpha = [frameDecoderAlpha numFrames];
  if (numFrames != numFramesAlpha) {
    NSLog(@"error: RGB movie numFrames %d does not match alpha movie numFrames %d", numFrames, numFramesAlpha);
    return FALSE;
  }
  
  // width x height
  
  int width = [frameDecoderRGB width];
  int height = [frameDecoderRGB height];
  NSAssert(width > 0, @"width");
  NSAssert(height > 0, @"height");
  CGSize size = CGSizeMake(width, height);
  
  // Size of Alpha movie must match size of RGB movie
  
  CGSize alphaMovieSize;
  
  alphaMovieSize = CGSizeMake(frameDecoderAlpha.width, frameDecoderAlpha.height);
  if (CGSizeEqualToSize(size, alphaMovieSize) == FALSE) {
    NSLog(@"error: RGB movie size (%d, %d) does not match alpha movie size (%d, %d)",
          (int)width, (int)height,
          (int)alphaMovieSize.width, (int)alphaMovieSize.height);
    return FALSE;
  }
  
  // Create output file writer object
  
  AVMvidFileWriter *fileWriter = [AVMvidFileWriter aVMvidFileWriter];
  NSAssert(fileWriter, @"fileWriter");
  
  fileWriter.mvidPath = joinedMvidPath;
  fileWriter.bpp = 32;
  // Note that we don't know the movie size until the first frame is read
  
  fileWriter.frameDuration = frameRate;
  fileWriter.totalNumFrames = numFrames;
  
  if (genAdler) {
    fileWriter.genAdler = TRUE;
  }
  
  worked = [fileWriter open];
  if (worked == FALSE) {
    NSLog(@"error: Could not open .mvid output file \"%@\"", joinedMvidPath);
    return FALSE;
  }
  
  fileWriter.movieSize = size;
  
  CGFrameBuffer *combinedFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];

  // Pixel dump used to compare exected results to actual results produced by iOS decoder hardware
  //NSString *tmpFilename = [NSString stringWithFormat:@"%@%@", joinedMvidPath, @".adump"];
  //char *utf8Str = (char*) [tmpFilename UTF8String];
  //NSLog(@"Writing %s", utf8Str);
  //FILE *fp = fopen(utf8Str, "w");
  //assert(fp);
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
#ifdef LOGGING
    NSLog(@"reading frame %d", frameIndex);
#endif // LOGGING
    
    AVFrame *frameRGB = [frameDecoderRGB advanceToFrame:frameIndex];
    assert(frameRGB);
    
    AVFrame *frameAlpha = [frameDecoderAlpha advanceToFrame:frameIndex];
    assert(frameAlpha);
    
    if (FALSE) {
      // Dump images for the RGB and ALPHA frames
      
      // Write image as PNG
      
      NSString *tmpDir = NSTemporaryDirectory();
      
      NSString *tmpPNGPath = [tmpDir stringByAppendingFormat:@"JoinAlpha_RGB_Frame%d.png", (frameIndex + 1)];
      
      NSData *data = [NSData dataWithData:UIImagePNGRepresentation(frameRGB.image)];
      [data writeToFile:tmpPNGPath atomically:YES];
      NSLog(@"wrote %@", tmpPNGPath);
      
      tmpPNGPath = [tmpDir stringByAppendingFormat:@"JoinAlpha_ALPHA_Frame%d.png", (frameIndex + 1)];
      
      data = [NSData dataWithData:UIImagePNGRepresentation(frameAlpha.image)];
      [data writeToFile:tmpPNGPath atomically:YES];
      NSLog(@"wrote %@", tmpPNGPath);
    }
    
    // Release the UIImage ref inside the frame since we will operate on the image data directly.
    frameRGB.image = nil;
    frameAlpha.image = nil;
    
    CGFrameBuffer *cgFrameBufferRGB = frameRGB.cgFrameBuffer;
    NSAssert(cgFrameBufferRGB, @"cgFrameBufferRGB");
    
    CGFrameBuffer *cgFrameBufferAlpha = frameAlpha.cgFrameBuffer;
    NSAssert(cgFrameBufferAlpha, @"cgFrameBufferAlpha");
    
    // sRGB
    
    if (frameIndex == 0) {
      combinedFrameBuffer.colorspace = cgFrameBufferRGB.colorspace;
    }
    
    //fprintf(fp, "Frame %d\n", frameIndex);
    //NSLog(@"Frame %d\n", frameIndex);
    
    // Join RGB and ALPHA
    
    uint32_t numPixels = width * height;
    uint32_t *combinedPixels = (uint32_t*)combinedFrameBuffer.pixels;
    uint32_t *rgbPixels = (uint32_t*)cgFrameBufferRGB.pixels;
    uint32_t *alphaPixels = (uint32_t*)cgFrameBufferAlpha.pixels;
    
    [self combineRGBAndAlphaPixels:numPixels
                    combinedPixels:combinedPixels
                         rgbPixels:rgbPixels
                       alphaPixels:alphaPixels];
    
    // Write combined RGBA pixles as a keyframe, we do not attempt to calculate
    // frame diffs when processing on the device as that takes too long.
    
    int numBytesInBuffer = combinedFrameBuffer.numBytes;
        
    worked = [fileWriter writeKeyframe:(char*)combinedPixels bufferSize:numBytesInBuffer];
    
    if (worked == FALSE) {
      NSLog(@"cannot write keyframe data to mvid file \"%@\"", joinedMvidPath);
      return FALSE;
    }
    
    [pool drain];
  }
  
  //fclose(fp);
  
  [fileWriter rewriteHeader];
  [fileWriter close];
  
  NSLog(@"Wrote %@", fileWriter.mvidPath);
  
  return TRUE;
}

// Join the RGB and Alpha components of two input framebuffers
// so that the final output result contains native premultiplied
// 32 BPP pixels.

+ (void) combineRGBAndAlphaPixels:(uint32_t)numPixels
                   combinedPixels:(uint32_t*)combinedPixels
                   rgbPixels:(uint32_t*)rgbPixels
                   alphaPixels:(uint32_t*)alphaPixels
{
  for (uint32_t pixeli = 0; pixeli < numPixels; pixeli++) {
    uint32_t pixelAlpha = alphaPixels[pixeli];
    uint32_t pixelRGB = rgbPixels[pixeli];
    
    // All 3 components of the ALPHA pixel should be the same in grayscale mode.
    // If these are not exactly the same, this is likely caused by limited precision
    // ranges in the hardware color conversion logic.
    
    uint32_t pixelAlphaRed = (pixelAlpha >> 16) & 0xFF;
    uint32_t pixelAlphaGreen = (pixelAlpha >> 8) & 0xFF;
    uint32_t pixelAlphaBlue = (pixelAlpha >> 0) & 0xFF;
    
//    if ((pixeli % 256) == 0) {
//      NSLog(@"processing row %d", (pixeli / 256));
//    }
    
//    if ((pixeli >= (2 * 256)) && (pixeli < (3 * 256))) {
//      // Third row
//      combinedPixels[pixeli] = combinedPixels[pixeli];
//    }
    
    if (pixelAlphaRed != pixelAlphaGreen || pixelAlphaRed != pixelAlphaBlue) {
      //NSLog(@"Input Alpha MVID input movie R G B components (%d %d %d) do not match at pixel %d in frame %d", pixelAlphaRed, pixelAlphaGreen, pixelAlphaBlue, pixeli, frameIndex);
      //return FALSE;
      
      uint32_t sum = pixelAlphaRed + pixelAlphaGreen + pixelAlphaBlue;
      if (sum == 1) {
        // If two values are 0 and the other is 1, then assume the alpha value is zero. The iOS h264
        // decoding hardware seems to emit (R=0 G=0 B=1) even when the input is a grayscale black pixel.
        pixelAlpha = 0;
      } else if (pixelAlphaRed == pixelAlphaBlue) {
        // The R and B pixel values are equal but these two values are not the same as the G pixel.
        // This indicates that the grayscale conversion should have resulted in value between the
        // two numbers.
        //
        // R G B components
        //
        // (3 1 3)       -> 2   <- (2, 2, 2) (sim)
        // (2 0 2)       -> 1   <- (1, 1, 1) (sim)
        // (18 16 18)    -> 17  <- (17, 17, 17) (sim)
        // (219 218 219) -> 218 <- (218, 218, 218) (sim)
        //
        // Note that in some cases the original values (5, 5, 5) get decoded as (5, 4, 5) and that results in 4 as the
        // alpha value. These cases are few and we just ignore them because the alpha is very close.
        
        pixelAlpha = pixelAlphaRed - 1;
        
        //NSLog(@"Input Alpha MVID input movie R G B components (%d %d %d) do not match at pixel %d in frame %d", pixelAlphaRed, pixelAlphaGreen, pixelAlphaBlue, pixeli, frameIndex);
        //NSLog(@"Using RED/BLUE Alpha level %d at pixel %d in frame %d", pixelAlpha, pixeli, frameIndex);
      } else if ((pixelAlphaRed == (pixelAlphaGreen + 1)) && (pixelAlphaRed == (pixelAlphaBlue - 1))) {
        // Common case seen in hardware decoder output, average is the middle value.
        //
        // R G B components
        // (62, 61, 63)    -> 62  <- (62, 62, 62) (sim)
        // (111, 110, 112) -> 111 <- (111, 111, 111) (sim)
        
        pixelAlpha = pixelAlphaRed;
        
        //NSLog(@"Input Alpha MVID input movie R G B components (%d %d %d) do not match at pixel %d in frame %d", pixelAlphaRed, pixelAlphaGreen, pixelAlphaBlue, pixeli, frameIndex);
        //NSLog(@"Using RED (easy ave) Alpha level %d at pixel %d in frame %d", pixelAlpha, pixeli, frameIndex);
      } else {
        // Output did not match one of the know common patterns seen coming from iOS H264 decoder hardware.
        // Since this branch does not seem to ever be executed, just use the red component which is
        // basically the same as the branch above.
        
        //pixelAlpha = sum / 3;
        pixelAlpha = pixelAlphaRed;
        
        //NSLog(@"Input Alpha MVID input movie R G B components (%d %d %d) do not match at pixel %d in frame %d", pixelAlphaRed, pixelAlphaGreen, pixelAlphaBlue, pixeli, frameIndex);
        //NSLog(@"Using AVE Alpha level %d at pixel %d in frame %d", pixelAlpha, pixeli, frameIndex);
      }
    } else {
      // All values are equal, does not matter which channel we use as the alpha value
      
      pixelAlpha = pixelAlphaRed;
    }
    
    // Automatially filter out zero pixel values, because there are just so many
    //if (pixelAlpha != 0) {
    //fprintf(fp, "A[%d][%d] = %d\n", frameIndex, pixeli, pixelAlpha);
    //fprintf(fp, "A[%d][%d] = %d <- (%d, %d, %d)\n", frameIndex, pixeli, pixelAlpha, pixelAlphaRed, pixelAlphaGreen, pixelAlphaBlue);
    //}
    
    // RGB componenets are 24 BPP non pre-multiplied values
    
    uint32_t pixelRed = (pixelRGB >> 16) & 0xFF;
    uint32_t pixelGreen = (pixelRGB >> 8) & 0xFF;
    uint32_t pixelBlue = (pixelRGB >> 0) & 0xFF;
    
    uint32_t combinedPixel = premultiply_bgra_inline(pixelRed, pixelGreen, pixelBlue, pixelAlpha);
    combinedPixels[pixeli] = combinedPixel;
  }
  
  return;
}

// This method is invoked in the secondary thread to decode the contents of the
// two resource asset files and combine them back together into a single
// mvid with an alpha channel.

+ (void) decodeThreadEntryPoint:(NSArray*)arr
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSAssert([arr count] == 6, @"arr count");
  
  // Pass 6 arguments : RGB_ASSET_PATH ALPHA_ASSET_PATH PHONY_OUT_PATH REAL_OUT_PATH SERIAL ADLER

  NSString *rgbAssetPath = [arr objectAtIndex:0];
  NSString *alphaAssetPath = [arr objectAtIndex:1];
  NSString *phonyOutPath = [arr objectAtIndex:2];
  NSString *outPath = [arr objectAtIndex:3];
  NSNumber *serialLoadingNum = [arr objectAtIndex:4];
  NSNumber *alwaysGenerateAdler = [arr objectAtIndex:5];
  
  BOOL genAdler = ([alwaysGenerateAdler intValue] ? TRUE : FALSE);
  
  if ([serialLoadingNum boolValue]) {
    [self grabSerialResourceLoaderLock];
  }
  
  // Check to see if the output file already exists. If the resource exists at this
  // point, then there is no reason to kick off another decode operation. For example,
  // in the serial loading case, a previous load could have loaded the resource.
  
  BOOL fileExists = [AVFileUtil fileExists:outPath];
  
  if (fileExists) {
#ifdef LOGGING
    NSLog(@"no asset decompression needed for %@", [outPath lastPathComponent]);
#endif // LOGGING
  } else {
#ifdef LOGGING
    NSLog(@"start asset decompression %@", [outPath lastPathComponent]);
#endif // LOGGING
    
    BOOL worked;
         
    // Iterate over RGB and ALPHA for each frame in the two movies and join the pixel values
    
    worked = [self joinRGBAndAlpha:phonyOutPath rgbPath:rgbAssetPath alphaPath:alphaAssetPath genAdler:genAdler];
    NSAssert(worked, @"joinRGBAndAlpha");
    
    // Move phony tmp filename to the expected filename once writes are complete
    
    [AVFileUtil renameFile:phonyOutPath toPath:outPath];
    
#ifdef LOGGING
    NSLog(@"wrote %@", outPath);
#endif // LOGGING
  }
  
  if ([serialLoadingNum boolValue]) {
    [self releaseSerialResourceLoaderLock];
  }
  
  [pool drain];
}

@end
