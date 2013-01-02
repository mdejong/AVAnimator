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

#import "AVMvidFrameDecoder.h"

#import "CGFrameBuffer.h"

// Defined in movdata.c since alpha table is in that module

void premultiply_init();

uint32_t premultiply_bgra(uint32_t unpremultPixelBGRA);

@interface AVAssetJoinAlphaResourceLoader ()

@property (nonatomic, retain) AVAsset2MvidResourceLoader *rgbLoader;
@property (nonatomic, retain) AVAsset2MvidResourceLoader *alphaLoader;

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

// Output movie filename must be redefined

- (NSString*) _getMoviePath
{
  return self.outPath;
}

// Create secondary thread to process operation

- (void) _detachNewThread:(BOOL)phony
             rgbAssetPath:(NSString*)rgbAssetPath
          phonyRgbOutPath:(NSString*)phonyRgbOutPath
           alphaAssetPath:(NSString*)alphaAssetPath
        phonyAlphaOutPath:(NSString*)phonyAlphaOutPath
             phonyOutPath:(NSString*)phonyOutPath
                  outPath:(NSString*)outPath
{
  NSNumber *serialLoadingNum = [NSNumber numberWithBool:self.serialLoading];
  
  uint32_t genAdler = self.alwaysGenerateAdler;
  NSNumber *genAdlerNum = [NSNumber numberWithInt:genAdler];
  NSAssert(genAdlerNum != nil, @"genAdlerNum");
  
  NSArray *arr = [NSArray arrayWithObjects:rgbAssetPath, phonyRgbOutPath,
                  alphaAssetPath, phonyAlphaOutPath,
                  phonyOutPath, outPath,
                  serialLoadingNum, genAdlerNum, nil];
  NSAssert([arr count] == 8, @"arr count");
  
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
  
  premultiply_init(); // ensure thread safe init of premultiply logic
  
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
  
  NSString *phonyRGBOutPath = [NSString stringWithFormat:@"%@_rgb.mvid", [AVFileUtil generateUniqueTmpPath]];
  NSString *phonyAlphaOutPath = [NSString stringWithFormat:@"%@_alpha.mvid", [AVFileUtil generateUniqueTmpPath]];
  NSString *phonyOutPath = [NSString stringWithFormat:@"%@.mvid", [AVFileUtil generateUniqueTmpPath]];
  
  [self _detachNewThread:FALSE
             rgbAssetPath:qualRGBPath
         phonyRgbOutPath:phonyRGBOutPath
          alphaAssetPath:qualAlphaPath
       phonyAlphaOutPath:phonyAlphaOutPath
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
{
  // Open both the rgb and alpha mvid files for reading
  
  AVMvidFrameDecoder *frameDecoderRGB = [AVMvidFrameDecoder aVMvidFrameDecoder];
  AVMvidFrameDecoder *frameDecoderAlpha = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
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
  
  [frameDecoderRGB allocateDecodeResources];
  [frameDecoderAlpha allocateDecodeResources];
  
  // BPP
  
  int foundBPP;
  
  foundBPP = [frameDecoderRGB header]->bpp;
  if (foundBPP != 24) {
    NSLog(@"error: RGB mvid file must be 24BPP, found %dBPP", foundBPP);
    return FALSE;
  }
  
  foundBPP = [frameDecoderAlpha header]->bpp;
  if (foundBPP != 24) {
    NSLog(@"error: ALPHA mvid file must be 24BPP, found %dBPP", foundBPP);
    return FALSE;
  }

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
  
  //fileWriter.genAdler = TRUE;
  
  worked = [fileWriter open];
  if (worked == FALSE) {
    NSLog(@"error: Could not open .mvid output file \"%@\"", joinedMvidPath);
    return FALSE;
  }
  
  fileWriter.movieSize = size;
  
  CGFrameBuffer *combinedFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];

  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex++) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
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
    
    // Join RGB and ALPHA
    
    NSUInteger numPixels = width * height;
    uint32_t *combinedPixels = (uint32_t*)combinedFrameBuffer.pixels;
    uint32_t *rgbPixels = (uint32_t*)cgFrameBufferRGB.pixels;
    uint32_t *alphaPixels = (uint32_t*)cgFrameBufferAlpha.pixels;
    
    for (NSUInteger pixeli = 0; pixeli < numPixels; pixeli++) {
      uint32_t pixelAlpha = alphaPixels[pixeli];
      
      // All 3 components of the ALPHA pixel need to be the same in grayscale mode.
      
      uint32_t pixelAlphaRed = (pixelAlpha >> 16) & 0xFF;
      uint32_t pixelAlphaGreen = (pixelAlpha >> 8) & 0xFF;
      uint32_t pixelAlphaBlue = (pixelAlpha >> 0) & 0xFF;
      
      if (pixelAlphaRed != pixelAlphaGreen || pixelAlphaRed != pixelAlphaBlue) {
        NSLog(@"Input Alpha MVID input movie R G B components do not match at pixel %d in frame %d", pixeli, frameIndex);
        return FALSE;
      }
      
      pixelAlpha = pixelAlphaRed;
      
      // RGB componenets are 24 BPP non pre multiplied values
      
      uint32_t pixelRGB = rgbPixels[pixeli];
      
      pixelRGB = pixelRGB & 0xFFFFFF;
      
      // Create BGRA pixel that is not premultiplied
      
      uint32_t combinedPixel = (pixelAlpha << 24) | pixelRGB;
      
      // Now pre multiple the pixel values to ensure that alpha values
      // are defined by the values in the alpha channel movie.
      
      // FIXME: additional optimizations possible in this premultiply op.
      
      combinedPixel = premultiply_bgra(combinedPixel);
      
      combinedPixels[pixeli] = combinedPixel;
    }
    
    // Write combined RGBA pixles as a keyframe, we do not attempt to calculate
    // frame diffs when processing on the device as that takes too long.
    
    char *buffer = combinedFrameBuffer.pixels;
    int numBytesInBuffer = combinedFrameBuffer.numBytes;
    
    worked = [fileWriter writeKeyframe:buffer bufferSize:numBytesInBuffer];
    
    if (worked == FALSE) {
      NSLog(@"cannot write keyframe data to mvid file \"%@\"", joinedMvidPath);
      return FALSE;
    }
    
    [pool drain];
  }
  
  [fileWriter rewriteHeader];
  [fileWriter close];
  
  NSLog(@"Wrote %@", fileWriter.mvidPath);
  
  return TRUE;
}

// This method is invoked in the secondary thread to decode the contents of the
// two resource asset files and combine them back together into a single
// mvid with an alpha channel.

+ (void) decodeThreadEntryPoint:(NSArray*)arr
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSAssert([arr count] == 8, @"arr count");
  
  // Pass 8 arguments : RGB_ASSET_PATH RGB_TMP_PATH ALPHA_ASSET_PATH ALPHA_TMP_PATH PHONY_OUT_PATH REAL_OUT_PATH SERIAL ADLER

  NSString *rgbAssetPath = [arr objectAtIndex:0];
  NSString *phonyRgbOutPath = [arr objectAtIndex:1];

  NSString *alphaAssetPath = [arr objectAtIndex:2];
  NSString *phonyAlphaOutPath = [arr objectAtIndex:3];
  
  NSString *phonyOutPath = [arr objectAtIndex:4];
  NSString *outPath = [arr objectAtIndex:5];
  
  NSNumber *serialLoadingNum = [arr objectAtIndex:6];
  NSNumber *alwaysGenerateAdler = [arr objectAtIndex:7];
  
  if ([serialLoadingNum boolValue]) {
    [self grabSerialResourceLoaderLock];
  }
  
  // Check to see if the output file already exists. If the resource exists at this
  // point, then there is no reason to kick off another decode operation. For example,
  // in the serial loading case, a previous load could have loaded the resource.
  
  BOOL fileExists = [AVFileUtil fileExists:outPath];
  
  if (fileExists) {
#ifdef LOGGING
    NSLog(@"no asset decompression needed for %@", [assetPath lastPathComponent]);
#endif // LOGGING
  } else {
#ifdef LOGGING
    NSLog(@"start asset decompression %@", [assetPath lastPathComponent]);
#endif // LOGGING
    
    BOOL worked;
    
    // RGB
    
    AVAssetReaderConvertMaxvid *rgbConverter = [AVAssetReaderConvertMaxvid aVAssetReaderConvertMaxvid];
    NSURL *rgbAssetURL = [NSURL fileURLWithPath:rgbAssetPath];
    rgbConverter.assetURL = rgbAssetURL;
    rgbConverter.mvidPath = phonyRgbOutPath;
    
    if ([alwaysGenerateAdler intValue]) {
      rgbConverter.genAdler = TRUE;
    }
    
    worked = [rgbConverter blockingDecode];
    NSAssert(worked, @"blockingDecode");
    
#ifdef LOGGING
    NSLog(@"done rgb asset decompression %@", [rgbAssetPath lastPathComponent]);
#endif // LOGGING
    
    // Alpha

    AVAssetReaderConvertMaxvid *alphaConverter = [AVAssetReaderConvertMaxvid aVAssetReaderConvertMaxvid];
    NSURL *alphaAssetURL = [NSURL fileURLWithPath:alphaAssetPath];
    alphaConverter.assetURL = alphaAssetURL;
    alphaConverter.mvidPath = phonyAlphaOutPath;
    
    if ([alwaysGenerateAdler intValue]) {
      alphaConverter.genAdler = TRUE;
    }
    
    worked = [alphaConverter blockingDecode];
    NSAssert(worked, @"blockingDecode");
    
#ifdef LOGGING
    NSLog(@"done alpha asset decompression %@", [alphaAssetPath lastPathComponent]);
#endif // LOGGING
    
    // Iterate over RGB and ALPHA for each frame in the two movies and join the pixel values
    
    worked = [self joinRGBAndAlpha:phonyOutPath rgbPath:phonyRgbOutPath alphaPath:phonyAlphaOutPath];
    NSAssert(worked, @"joinRGBAndAlpha");
    
    // Delete RGB and Alpha intermediate .mvid files since they are very large
    
    worked = [[NSFileManager defaultManager] removeItemAtPath:phonyRgbOutPath error:NULL];
    NSAssert(worked, @"rm %@", phonyRgbOutPath);
    worked = [[NSFileManager defaultManager] removeItemAtPath:phonyAlphaOutPath error:NULL];
    NSAssert(worked, @"rm %@", phonyAlphaOutPath);
    
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
