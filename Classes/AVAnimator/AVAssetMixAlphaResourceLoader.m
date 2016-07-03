//
//  AVAssetMixAlphaResourceLoader.m
//
//  Created by Moses DeJong on 1/1/13.
//
//  License terms defined in License.txt.
//

#import "AVAssetMixAlphaResourceLoader.h"

#import "AVFileUtil.h"

#import "AVAssetJoinAlphaResourceLoader.h"

#import "AVMvidFileWriter.h"

#import "AVFrame.h"

#import "AVAssetFrameDecoder.h"

#import "CGFrameBuffer.h"

#import "movdata.h"

//#define LOGGING

@interface AVAssetMixAlphaResourceLoader ()

@property (nonatomic, retain) AVAsset2MvidResourceLoader *mixLoader;

@property (nonatomic, assign) BOOL startedLoading;

@end

// Static API

@interface AVAssetJoinAlphaResourceLoader ()

+ (void) combineRGBAndAlphaPixels:(uint32_t)numPixels
                   combinedPixels:(uint32_t*)combinedPixels
                        rgbPixels:(uint32_t*)rgbPixels
                      alphaPixels:(uint32_t*)alphaPixels;

@end


@implementation AVAssetMixAlphaResourceLoader

@synthesize outPath = m_outPath;
@synthesize alwaysGenerateAdler = m_alwaysGenerateAdler;
@synthesize mixLoader = m_mixLoader;

+ (AVAssetMixAlphaResourceLoader*) aVAssetMixAlphaResourceLoader
{
  AVAssetMixAlphaResourceLoader *obj = [[AVAssetMixAlphaResourceLoader alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (void) dealloc
{
  self.movieFilename = nil;
  self.outPath = nil;
  self.mixLoader = nil;
  
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
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
  
  if (self.startedLoading) {
    return;
  } else {
    self.startedLoading = TRUE;
  }
  
  premultiply_init(); // ensure thread safe init of premultiply table
  
  // Superclass load method asserts that self.movieFilename is not nil
  [super load];
  
  NSString *qualPath = [AVFileUtil getQualifiedFilenameOrResource:self.movieFilename];
  NSAssert(qualPath, @"qualPath");
  
  NSString *outPath = self.outPath;
  NSAssert(outPath, @"outPath not defined");
  
  // Generate phony tmp path that data will be written to as it is extracted.
  // This avoids thread race conditions and partial writes. Note that the filename is
  // generated in this method, and this method should only be invoked from the main thread.
  
  NSString *phonyOutPath = [AVFileUtil generateUniqueTmpPath];
  
  [self _detachNewThread:qualPath phonyOutPath:phonyOutPath outPath:outPath];
  
  return;
}

/*

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

*/

// unmixRGBAndAlpha
//
// Implement logic to "unmix" pixels from RGB video and Alpha video back into single .mvid
// with an alpha channel.

+ (BOOL) unmixRGBAndAlpha:(NSString*)joinedMvidPath
                  mixPath:(NSString*)mixPath
                 genAdler:(BOOL)genAdler
{
  // Open both the rgb and alpha mvid files for reading
  
  AVAssetFrameDecoder *frameDecoder = [AVAssetFrameDecoder aVAssetFrameDecoder];
  
  frameDecoder.dropFrames = FALSE;
  
  BOOL worked;
  worked = [frameDecoder openForReading:mixPath];
  
  if (worked == FALSE) {
    NSLog(@"error: cannot open RGB+Alpha mixed asset filename \"%@\"", mixPath);
    return FALSE;
  }
  
  worked = [frameDecoder allocateDecodeResources];

  if (worked == FALSE) {
    NSLog(@"error: cannot allocate RGB+Alpha mixed decode resources for filename \"%@\"", mixPath);
    return FALSE;
  }
  
#ifdef LOGGING
  NSLog(@"log num frames for \"%@\" %d", mixPath, (int)frameDecoder.numFrames);
#endif // LOGGING
  
  // BPP for decoded asset is always 24 BPP

  // framerate
  
  NSTimeInterval frameRate = frameDecoder.frameDuration;

//  if (frameRate != frameRateAlpha) {
//    NSLog(@"error: RGB movie fps %.4f does not match alpha movie fps %.4f",
//          1.0f/(float)frameRate, 1.0f/(float)frameRateAlpha);
//    return FALSE;
//  }

  // num frames
  
  NSUInteger numFrames = [frameDecoder numFrames];
  
  if ((numFrames % 2) != 0) {
    NSLog(@"error: movie numFrames %d is not even", (int)numFrames);
    return FALSE;
  }
  
  // width x height
  
  int width  = (int) [frameDecoder width];
  int height = (int) [frameDecoder height];
  NSAssert(width > 0, @"width");
  NSAssert(height > 0, @"height");
  CGSize size = CGSizeMake(width, height);
  
  // Create output file writer object
  
  AVMvidFileWriter *fileWriter = [AVMvidFileWriter aVMvidFileWriter];
  NSAssert(fileWriter, @"fileWriter");
  
  fileWriter.genV3 = TRUE;
  
  fileWriter.mvidPath = joinedMvidPath;
  fileWriter.bpp = 32;
  // Note that we don't know the movie size until the first frame is read
  
  fileWriter.frameDuration = frameRate;
  fileWriter.totalNumFrames = (int) (numFrames / 2);
  
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
  
  CGFrameBuffer *copyFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];

  // Pixel dump used to compare exected results to actual results produced by iOS decoder hardware
  //NSString *tmpFilename = [NSString stringWithFormat:@"%@%@", joinedMvidPath, @".adump"];
  //char *utf8Str = (char*) [tmpFilename UTF8String];
  //NSLog(@"Writing %s", utf8Str);
  //FILE *fp = fopen(utf8Str, "w");
  //assert(fp);
  
  for (NSUInteger frameIndex = 0; frameIndex < numFrames; frameIndex += 2) @autoreleasepool {
#ifdef LOGGING
    NSLog(@"reading frames %d,%d", (int)frameIndex, (int)frameIndex+1);
#endif // LOGGING
    
    // FIXME: if the alpha frame is first then it would be possible to reduce the grayscale
    // data down to grayscale bytes before reading the second frame of RGB data. That would
    // reduce the memory usage of the decode process by 4x for the large frame case.
    
    // Note that the AVAssetFrameDecoder decodes to just 1 CGFrameBuffer at a time
    
    AVFrame *frame;
    
    frame = [frameDecoder advanceToFrame:frameIndex];
    assert(frame);
    
    if (FALSE) @autoreleasepool {
      // Write image as PNG
      
      NSString *tmpDir = NSTemporaryDirectory();
      
      NSString *tmpPNGPath = [tmpDir stringByAppendingFormat:@"MixAlpha_RGB_Frame%d.png", (int)(frameIndex)];
      
      NSData *data = [NSData dataWithData:UIImagePNGRepresentation(frame.image)];
      [data writeToFile:tmpPNGPath atomically:YES];
      NSLog(@"wrote %@", tmpPNGPath);
    }
    
    // Release the UIImage ref inside the frame since we will operate on the image data directly.
    frame.image = nil;
    
    CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
    NSAssert(cgFrameBuffer, @"cgFrameBuffer for RGB");
    
    // sRGB colorspace
    
    if (frameIndex == 0) {
      combinedFrameBuffer.colorspace = cgFrameBuffer.colorspace;
    }
    
    // Need to make a copy of the RGB framebuffer at this point, since the AVAssetFrameDecoder
    // logic maintains only a single framebuffer.
    
    [copyFrameBuffer copyPixels:cgFrameBuffer];
    
    cgFrameBuffer = nil;
    frame = nil;
    
    // RGB data now copied out of framebuffer, decode Alpha frame
    
    frame = [frameDecoder advanceToFrame:frameIndex+1];
    assert(frame);
    
    if (FALSE) @autoreleasepool {
      // Write image as PNG
      
      NSString *tmpDir = NSTemporaryDirectory();
      
      NSString *tmpPNGPath = [tmpDir stringByAppendingFormat:@"MixAlpha_ALPHA_Frame%d.png", (int)(frameIndex + 1)];
      
      NSData *data = [NSData dataWithData:UIImagePNGRepresentation(frame.image)];
      [data writeToFile:tmpPNGPath atomically:YES];
      NSLog(@"wrote %@", tmpPNGPath);
    }
    
    // Release the UIImage ref inside the frame since we will operate on the image data directly.
    frame.image = nil;
    
    cgFrameBuffer = frame.cgFrameBuffer;
    NSAssert(cgFrameBuffer, @"cgFrameBuffer for Alpha");
    
    //fprintf(fp, "Frame %d\n", frameIndex);
    //NSLog(@"Frame %d\n", frameIndex);
    
    // Join RGB and ALPHA
    
    uint32_t numPixels = width * height;
    uint32_t *combinedPixels = (uint32_t*)combinedFrameBuffer.pixels;
    uint32_t *rgbPixels = (uint32_t*)copyFrameBuffer.pixels;
    uint32_t *alphaPixels = (uint32_t*)cgFrameBuffer.pixels;
    
    [AVAssetJoinAlphaResourceLoader combineRGBAndAlphaPixels:numPixels
                                              combinedPixels:combinedPixels
                                                   rgbPixels:rgbPixels
                                                 alphaPixels:alphaPixels];
    
    // Write combined RGBA pixles as a keyframe, we do not attempt to calculate
    // frame diffs when processing on the device as that takes too long.
    
    int numBytesInBuffer = (int) combinedFrameBuffer.numBytes;
        
    worked = [fileWriter writeKeyframe:(char*)combinedPixels bufferSize:numBytesInBuffer];
    
    if (worked == FALSE) {
      NSLog(@"cannot write keyframe data to mvid file \"%@\"", joinedMvidPath);
      return FALSE;
    }
  }
  
  //fclose(fp);
  
  [fileWriter rewriteHeader];
  [fileWriter close];
  
  NSLog(@"Wrote %@", fileWriter.mvidPath);
  
  return TRUE;
}

// This method is invoked in the secondary thread to decode the contents of the archive entry
// and write it to an output file (typically in the tmp dir).

+ (void) decodeThreadEntryPoint:(NSArray*)arr {
  @autoreleasepool {
    
    NSAssert([arr count] == 5, @"arr count");
    
    // Pass 5 arguments : ASSET_PATH PHONY_PATH TMP_PATH SERIAL ADLER
    
    NSString *assetPath = [arr objectAtIndex:0];
    NSString *phonyOutPath = [arr objectAtIndex:1];
    NSString *outPath = [arr objectAtIndex:2];
    NSNumber *serialLoadingNum = [arr objectAtIndex:3];
    NSNumber *alwaysGenerateAdler = [arr objectAtIndex:4];
    
    if ([serialLoadingNum boolValue]) {
      [self grabSerialResourceLoaderLock];
    }
    
    uint32_t genAdler = [alwaysGenerateAdler boolValue];
    
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
      
      // Iterate over RGB and ALPHA for each frame in the two movies and join the pixel values
      
      BOOL worked;
      
      worked = [self unmixRGBAndAlpha:phonyOutPath mixPath:assetPath genAdler:genAdler];
      NSAssert(worked, @"mixAssetPath");
      
      // Move phony tmp filename to the expected filename once writes are complete
      
      [AVFileUtil renameFile:phonyOutPath toPath:outPath];
      
#ifdef LOGGING
      NSLog(@"wrote %@", outPath);
#endif // LOGGING
    }
    
    if ([serialLoadingNum boolValue]) {
      [self releaseSerialResourceLoaderLock];
    }
    
  }
}

- (void) _detachNewThread:(NSString*)assetPath
             phonyOutPath:(NSString*)phonyOutPath
                  outPath:(NSString*)outPath
{
  NSNumber *serialLoadingNum = [NSNumber numberWithBool:self.serialLoading];
  
  uint32_t genAdler = self.alwaysGenerateAdler;
  NSNumber *genAdlerNum = [NSNumber numberWithInt:genAdler];
  NSAssert(genAdlerNum != nil, @"genAdlerNum");
  
  NSArray *arr = [NSArray arrayWithObjects:assetPath, phonyOutPath, outPath, serialLoadingNum, genAdlerNum, nil];
  NSAssert([arr count] == 5, @"arr count");
  
  [NSThread detachNewThreadSelector:@selector(decodeThreadEntryPoint:) toTarget:self.class withObject:arr];
}

@end
