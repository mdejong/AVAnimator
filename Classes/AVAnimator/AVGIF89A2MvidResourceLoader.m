//
//  AVGIF89A2MvidResourceLoader.m
//
//  Created by Moses DeJong on 6/5/13.
//
//  License terms defined in License.txt.
//

#import "AVGIF89A2MvidResourceLoader.h"

#ifdef AVANIMATOR_HAS_IMAGEIO_FRAMEWORK

#import <ImageIO/ImageIO.h>

#import "AVFileUtil.h"

#import "AVMvidFileWriter.h"

#import "CGFrameBuffer.h"

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG

// Returned if the filename does not match *.gif or the data is not APNG data.

#define UNSUPPORTED_FILE 1
#define READ_ERROR 2
#define WRITE_ERROR 3
#define MALLOC_ERROR 4

// Private API

@interface AVGIF89A2MvidResourceLoader ()

+ (uint32_t) convertToMaxvid:(NSData*)inGIF89AData
               outMaxvidPath:(NSString*)outMaxvidPath
                    genAdler:(BOOL)genAdler;

@end


@implementation AVGIF89A2MvidResourceLoader

@synthesize outPath = m_outPath;
@synthesize alwaysGenerateAdler = m_alwaysGenerateAdler;

+ (AVGIF89A2MvidResourceLoader*) aVGIF89A2MvidResourceLoader
{
  AVGIF89A2MvidResourceLoader *obj = [[AVGIF89A2MvidResourceLoader alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (void) dealloc
{
  self.outPath = nil;
  
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

// This method is invoked in the secondary thread to decode the contents of the archive entry
// and write it to an output file (typically in the tmp dir).

#define LOGGING

+ (void) decodeThreadEntryPoint:(NSArray*)arr {  
  @autoreleasepool {
  
  NSAssert([arr count] == 5, @"arr count");
  
  // Pass 5 args : RESOURCE_PATH PHONY_TMP_PATH TMP_PATH GEN_ADLER SERIAL
  
  NSString *resPath = [arr objectAtIndex:0];
  NSString *phonyOutPath = [arr objectAtIndex:1];
  NSString *outPath = [arr objectAtIndex:2];
  NSString *genAdlerNum = [arr objectAtIndex:3];
  NSNumber *serialLoadingNum = [arr objectAtIndex:4];
  
  if ([serialLoadingNum boolValue]) {
    [self grabSerialResourceLoaderLock];
  }
  
  // Check to see if the output file already exists. If the resource exists at this
  // point, then there is no reason to kick off another decode operation. For example,
  // in the serial loading case, a previous load could have loaded the resource.
  
  BOOL fileExists = [AVFileUtil fileExists:outPath];
  
  if (fileExists) {
#ifdef LOGGING
    NSLog(@"no .gif -> .mvid conversion needed for %@", [resPath lastPathComponent]);
#endif // LOGGING
  } else {
    
#ifdef LOGGING
    NSLog(@"start .gif -> .mvid conversion \"%@\"", [resPath lastPathComponent]);
#endif // LOGGING
    
    uint32_t retcode;
    
    uint32_t genAdler = 0;
#ifdef EXTRA_CHECKS
    genAdler = 1;
#endif // EXTRA_CHECKS
    if ([genAdlerNum intValue]) {
      genAdler = 1;
    }
    
    // Blocking load of image file data
    
    NSData *imageData = [NSData dataWithContentsOfFile:resPath];
    if (imageData == nil) {
      // Data could not be loaded
      NSAssert(FALSE, @"image data could not be loaded from %@", resPath);
    }

    retcode = [self convertToMaxvid:imageData outMaxvidPath:phonyOutPath genAdler:genAdler];
    
    if (retcode != 0) {
      NSAssert(retcode == 0, @"convertToMaxvid %d", retcode);
    }
    
    // The temp filename holding the maxvid data is now completely written, rename it to "XYZ.mvid"
    
    [AVFileUtil renameFile:phonyOutPath toPath:outPath];
        
#ifdef LOGGING
    NSLog(@"done converting .gif to .mvid \"%@\"", [outPath lastPathComponent]);
#endif // LOGGING    
  }
  
  if ([serialLoadingNum boolValue]) {
    [self releaseSerialResourceLoaderLock];
  }
  
  }
}

- (void) _detachNewThread:(NSString*)resPath
             phonyOutPath:(NSString*)phonyOutPath
                  outPath:(NSString*)outPath
{
  // Use the same paths defined in the superclass, but pass 1 additional temp filename that will contain
  // the intermediate results of the conversion.
  
  uint32_t genAdler = self.alwaysGenerateAdler;
  NSNumber *genAdlerNum = [NSNumber numberWithInt:genAdler];
  NSAssert(genAdlerNum != nil, @"genAdlerNum");
  
  NSNumber *serialLoadingNum = [NSNumber numberWithBool:self.serialLoading];
  
  NSArray *arr = [NSArray arrayWithObjects:resPath, phonyOutPath, outPath, genAdlerNum, serialLoadingNum, nil];
  NSAssert([arr count] == 5, @"arr count");
  
  [NSThread detachNewThreadSelector:@selector(decodeThreadEntryPoint:) toTarget:self.class withObject:arr];  
}

- (void) load
{
  // Avoid kicking off mutliple sync load operations. This method should only
  // be invoked from a main thread callback, so there should not be any chance
  // of a race condition involving multiple invocations of this load mehtod.
  
  if (startedLoading) {
    return;
  } else {
    self->startedLoading = TRUE;    
  }
  
  // Superclass load method asserts that self.movieFilename is not nil
  [super load];
  
  // If movie filename is already fully qualified, then don't qualify it as a resource path
  
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

// Convert an animated GIF image to a maxvid file. This method is invoked in
// a secondary thread and the output is written to a tmp file.

+ (uint32_t) convertToMaxvid:(NSData*)inGIF89AData
               outMaxvidPath:(NSString*)outMaxvidPath
                    genAdler:(BOOL)genAdler
{
  uint32_t retcode = 0;
  
  @autoreleasepool {
  
  CGFrameBuffer *cgFrameBuffer = nil;
  
  CGImageSourceRef srcRef = CGImageSourceCreateWithData(
#if __has_feature(objc_arc)
                                                        (__bridge CFDataRef)inGIF89AData
#else
                                                        (CFDataRef)inGIF89AData
#endif // objc_arc
                                                        , NULL);
    
  assert(srcRef);

  AVMvidFileWriter *aVMvidFileWriter = nil;
  
#undef RETCODE
#define RETCODE(status) \
if (status != 0) { \
retcode = status; \
goto retcode; \
}
  
  // The initial step is to read the image metadata for each subimage and
  // determine the delay from the previous frame to the current one.
  // The shortest delay found will be used as the framerate.
  
  uint32_t const numFrames = (uint32_t) CGImageSourceGetCount(srcRef);
  
  float minDelaySeconds = 10000.0;
  //uint32_t foundHasAlphaFlag = 0;
  
  uint32_t width = 0;
  uint32_t height = 0;
  
  for (int i=0; i < numFrames; i++) {
    CFDictionaryRef imageFrameProperties = CGImageSourceCopyPropertiesAtIndex(srcRef, i, NULL);
    assert(imageFrameProperties);
    
    CFDictionaryRef gifProperties = CFDictionaryGetValue(imageFrameProperties, kCGImagePropertyGIFDictionary);
    assert(gifProperties);

    // kCGImagePropertyGIFDelayTime is rounded up to 0.1 if smaller than 0.1.
    // kCGImagePropertyGIFUnclampedDelayTime is the original value in the GIF file
    
    CFNumberRef delayTime = CFDictionaryGetValue(gifProperties, kCGImagePropertyGIFUnclampedDelayTime);
    assert(delayTime);
    
    NSNumber *delayTimeNum;
    
#if __has_feature(objc_arc)
    delayTimeNum = (__bridge NSNumber*)delayTime;
#else
    delayTimeNum = (NSNumber*)delayTime;
#endif // objc_arc
    
    // ImageIO must return the delay time in seconds
    
    float delayTimeFloat = (float) [delayTimeNum doubleValue];

    // Define a lower limit of about 30 FPS. The clamped value defined by kCGImagePropertyGIFDelayTime
    // is too restrictive since a value of 0.04 corresponds to about 23 fps.
    
    if (delayTimeFloat <= (1.0f/30.0f)) {
      delayTimeFloat = (1.0f/30.0f);
    }
    
    if (delayTimeFloat < minDelaySeconds) {
      minDelaySeconds = delayTimeFloat;
    }
    
    if (width == 0) {
      CFNumberRef pixelWidth = CFDictionaryGetValue(imageFrameProperties, @"PixelWidth");
      CFNumberRef pixelHeight = CFDictionaryGetValue(imageFrameProperties, @"PixelHeight");
      
      NSNumber *pixelWidthNum;
      NSNumber *pixelHeightNum;
      
#if __has_feature(objc_arc)
      pixelWidthNum = (__bridge NSNumber*)pixelWidth;
      pixelHeightNum = (__bridge NSNumber*)pixelHeight;
#else
      pixelWidthNum = (NSNumber*)pixelWidth;
      pixelHeightNum = (NSNumber*)pixelHeight;
#endif // objc_arc
      
      width = [pixelWidthNum unsignedIntValue];
      height = [pixelHeightNum unsignedIntValue];
    }
    
    // Check "HasAlpha" property for each frame, if an earlier frame does not contain
    // a transparent pixel but a later frame does, then all frames need to be treated.
    // This should work, but it actually does not work better than detection since it
    // appears that images that really are 24BPP get detected as 32 BPP. Go with the
    // scanning approach on actual rendered pixels since that works in all cases.
    
//    if (foundHasAlphaFlag == 0) {
//      CFNumberRef hasAlpha = CFDictionaryGetValue(imageFrameProperties, @"HasAlpha");
//      
//      NSNumber *hasAlphaNum = (NSNumber*)hasAlpha;
//      
//      uint32_t hasAlphaValue = [hasAlphaNum intValue];
//      if (hasAlphaValue == 1) {
//        foundHasAlphaFlag = 1;
//      }
//    }

    CFRelease(imageFrameProperties);
  }
  
  float frameDuration = minDelaySeconds;
  
  // If width and height were not detected, unable to process the GIF file
  
  if (width == 0 || height == 0) {
    RETCODE(UNSUPPORTED_FILE);
  }
  
  // FIXME: might want to just pick a default duration like 1 FPS for cases like
  // when no framerate can be detected, or when it is a plain GIF with no animation.
  // In this case, perhaps just 1 frame is okay.
  
  // If fewer than 2 animation frames, then it will not be possible to animate.
  // This could happen when there is only a single frame in a PNG file, for example.
  // It might also happen in a 2 frame .gif where the first frame is marked as hidden.
  
  if (numFrames < 2) {
    RETCODE(UNSUPPORTED_FILE);
  }
  
  // Create .mvid file writer utility object
  
  aVMvidFileWriter = [AVMvidFileWriter aVMvidFileWriter];
  
  aVMvidFileWriter.mvidPath = outMaxvidPath;
  aVMvidFileWriter.frameDuration = frameDuration;
  aVMvidFileWriter.totalNumFrames = numFrames;
  aVMvidFileWriter.movieSize = CGSizeMake(width, height);
  aVMvidFileWriter.genAdler = genAdler;
  
  BOOL worked = [aVMvidFileWriter open];
  
	if (worked == FALSE) {
    RETCODE(WRITE_ERROR);
  }
  
  // Iterate over each frame, extract the image and write the data
  // to the mvid file. Make sure to cleanup the autorelease pool so
  // that not all the image frames are actually loaded into memory.
  
  cgFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];
  uint32_t detectedBpp = 24;
  //if (foundHasAlphaFlag) {
  //  detectedBpp = 32;
  //}
  
  for (int i=0; i < numFrames; i++) @autoreleasepool {
    CGImageRef imgRef = CGImageSourceCreateImageAtIndex(srcRef, i, NULL);
    
    // if scan finds no transparent pixels, then detectedBpp = 24
    
    // Render the image contents into a framebuffer. We don't know what
    // the exact binary layout of the GIF image data might be, though it
    // is likely to be a flat array of 32 BPP pixels.
    
    uint32_t imageWidth  = (uint32_t) CGImageGetWidth(imgRef);
    uint32_t imageHeight = (uint32_t) CGImageGetHeight(imgRef);
    
    assert(imageWidth == width);
    assert(imageHeight == height);
    
    [cgFrameBuffer clear];
    [cgFrameBuffer renderCGImage:imgRef];
    
    // Scan the framebuffer to determine if any transparent pixels appear
    // in the frame. This is not fast, but it works. A better approach
    // would be to inspect the metadata to see if it indicates when
    // transparent pixels appear in the color table.
    
    uint32_t *pixels = (uint32_t*) cgFrameBuffer.pixels;
    
    if (detectedBpp == 24) {
      for (int rowi = 0; rowi < height; rowi++) {
        for (int coli = 0; coli < width; coli++) {
          uint32_t pixel = pixels[(rowi * width) + coli];
          uint8_t alpha = (pixel >> 24) & 0xFF;
          if (alpha != 0xFF) {
            detectedBpp = 32;
            break;
          }
        }
      }
    }
    
    CGImageRelease(imgRef);
    
    // Write the keyframe to the output file
    
    int numBytesInBuffer = (int) cgFrameBuffer.numBytes;
    
    worked = [aVMvidFileWriter writeKeyframe:cgFrameBuffer.pixels bufferSize:numBytesInBuffer];
    
    assert(worked);
  }
  
  // Write .mvid header again, now that info is up to date
  
  aVMvidFileWriter.bpp = detectedBpp;
  
  worked = [aVMvidFileWriter rewriteHeader];
  
	if (worked == FALSE) {
    RETCODE(WRITE_ERROR);
  }
  
retcode:  
  CFRelease(srcRef);
  
  [aVMvidFileWriter close];
  
  }
  
	return retcode;
}

@end

#endif // AVANIMATOR_HAS_IMAGEIO_FRAMEWORK
