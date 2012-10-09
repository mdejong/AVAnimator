//
//  AVAssetWriterConvertFromMaxvid.m
//
//  Created by Moses DeJong on 7/8/12.
//
//  License terms defined in License.txt.
//
//  See header for module description and usage info.

#import "AVAssetWriterConvertFromMaxvid.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

#include <sys/types.h>
#include <sys/sysctl.h>

#import <AVFoundation/AVFoundation.h>

#import <AVFoundation/AVAsset.h>
#import <AVFoundation/AVAssetWriter.h>
#import <AVFoundation/AVAssetWriterInput.h>

//#import <CoreMedia/CMSampleBuffer.h>

// FIXME: remove CGFrameBuffer include later
#import "CGFrameBuffer.h"

#import "AutoPropertyRelease.h"

#import "AVMvidFrameDecoder.h"

// Notification name constants

NSString * const AVAssetWriterConvertFromMaxvidCompletedNotification = @"AVAssetWriterConvertFromMaxvidCompletedNotification";

// Private API

@interface AVAssetWriterConvertFromMaxvid ()

@property (nonatomic, retain) AVAssetWriter *aVAssetWriter;

- (void) fillPixelBufferFromImage:(UIImage*)image
                           buffer:(CVPixelBufferRef)buffer
                             size:(CGSize)size;

- (AVMvidFrameDecoder*) initMvidDecoder;

@end


//#define LOGGING

@implementation AVAssetWriterConvertFromMaxvid

@synthesize state = m_state;
@synthesize inputPath = m_inputPath;
@synthesize outputPath = m_outputPath;
@synthesize aVAssetWriter = m_aVAssetWriter;

#if defined(REGRESSION_TESTS)
@synthesize frameDecoder = m_frameDecoder;
#endif // REGRESSION_TESTS

+ (AVAssetWriterConvertFromMaxvid*) aVAssetWriterConvertFromMaxvid
{
  AVAssetWriterConvertFromMaxvid *obj = [[AVAssetWriterConvertFromMaxvid alloc] init];
  return [obj autorelease];
}

- (void) dealloc
{
  [AutoPropertyRelease releaseProperties:self thisClass:AVAssetWriterConvertFromMaxvid.class];
  [super dealloc];
}

// ------------------------------------------------------------------------------------
// initMvidDecoder
// 
// In the normal case where a .mvid file will be read from, this method will open
// the file and return a frame decoder. If the file can't be opened, then nil
// will be returned.
// ------------------------------------------------------------------------------------

- (AVMvidFrameDecoder*) initMvidDecoder
{
  BOOL worked;
 
  // Input file is a .mvid video file like "walk.mvid"
  
  NSString *inputPath = self.inputPath;
  NSAssert(inputPath, @"inputPath");
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  NSAssert(frameDecoder, @"frameDecoder");
  
  // FIXME: add support for ".mvid.7z" compressed entries (current a .mvid is required)
  
  worked = [frameDecoder openForReading:inputPath];
  
  if (!worked) {
    NSLog(@"frameDecoder openForReading failed");
    return nil;
  }
  
  return frameDecoder;
}

// Kick off blocking encode operation to convert .mvid to .mov (h264)

- (void) blockingEncode
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL worked;
  
  AVFrameDecoder *frameDecoder = nil;
  
#if defined(REGRESSION_TESTS)
  if (self.frameDecoder == nil) {
    frameDecoder = [self initMvidDecoder];
  } else {
    // Optionally use a custom frame decoder in test mode
    frameDecoder = self.frameDecoder;
  }
#else  // REGRESSION_TESTS
  frameDecoder = [self initMvidDecoder];
#endif // REGRESSION_TESTS
  
  if (frameDecoder == nil) {
    // FIXME: create specific failure flags for input vs output files
    self.state = AVAssetWriterConvertFromMaxvidStateFailed;
    [pool drain];
    return;
  }
  
  worked = [frameDecoder allocateDecodeResources];  
  
  if (!worked) {
    NSLog(@"frameDecoder allocateDecodeResources failed");
    // FIXME: create specific failure flags for input vs output files
    self.state = AVAssetWriterConvertFromMaxvidStateFailed;
    [pool drain];
    return;
  }
  
  NSUInteger width = [frameDecoder width];
  NSUInteger height = [frameDecoder height];  
  CGSize movieSize = CGSizeMake(width, height);
  
#ifdef LOGGING
  NSLog(@"Writing movie with size %d x %d", width, height);
#endif // LOGGING
  
  // Output file is a file name like "out.mov" or "out.m4v"
  
  NSString *outputPath = self.outputPath;
  NSAssert(outputPath, @"outputPath");
  NSURL *outputPathURL = [NSURL fileURLWithPath:outputPath];
  NSAssert(outputPathURL, @"outputPathURL");
  NSError *error = nil;
  
  // Output types:
  // AVFileTypeQuickTimeMovie
  // AVFileTypeMPEG4 (no)
  
  AVAssetWriter *videoWriter = [[[AVAssetWriter alloc] initWithURL:outputPathURL
                                                         fileType:AVFileTypeQuickTimeMovie
                                                            error:&error] autorelease];
  NSAssert(videoWriter, @"videoWriter");
    
  NSNumber *widthNum = [NSNumber numberWithUnsignedInt:width];
  NSNumber *heightNum = [NSNumber numberWithUnsignedInt:height];
  
  NSDictionary *videoSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                 AVVideoCodecH264, AVVideoCodecKey,
                                 widthNum, AVVideoWidthKey,
                                 heightNum, AVVideoHeightKey,
                                 nil];
  NSAssert(videoSettings, @"videoSettings");

  AVAssetWriterInput* videoWriterInput = [AVAssetWriterInput
                                           assetWriterInputWithMediaType:AVMediaTypeVideo
                                           outputSettings:videoSettings];
  
  NSAssert(videoWriterInput, @"videoWriterInput");

  // adaptor handles allocation of a pool of pixel buffers and makes writing a series
  // of images to the videoWriterInput easier.
  
  NSMutableDictionary *adaptorAttributes = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                            [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
                                            widthNum,  kCVPixelBufferWidthKey,
                                            heightNum, kCVPixelBufferHeightKey,
                                            nil];
/*  
  if (movieSize.width < 128) {
    int extraOnRight = 128 - movieSize.width;
    [adaptorAttributes setObject:[NSNumber numberWithInt:extraOnRight] forKey:(NSString*)kCVPixelBufferExtendedPixelsRightKey];
  }
  if (movieSize.height < 128) {
    int extraOnBottom = 128 - movieSize.height;
    [adaptorAttributes setObject:[NSNumber numberWithInt:extraOnBottom] forKey:(NSString*)kCVPixelBufferExtendedPixelsBottomKey];
  }
*/
  
  AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
                                                   assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoWriterInput
                                                   sourcePixelBufferAttributes:adaptorAttributes];

  NSAssert(adaptor, @"assetWriterInputPixelBufferAdaptorWithAssetWriterInput");
    
  // Media data comes from an input file, not real time
  
  videoWriterInput.expectsMediaDataInRealTime = NO;
  
  NSAssert([videoWriter canAddInput:videoWriterInput], @"canAddInput");
  [videoWriter addInput:videoWriterInput];
  
  // Start writing samples to video file
  
  [videoWriter startWriting];
  [videoWriter startSessionAtSourceTime:kCMTimeZero];
  
  // If the pixelBufferPool is nil after the call to startSessionAtSourceTime then something went wrong
  // when creating the pixel buffers. Typically, an error indicates the the size of the video data is
  // not acceptable to the AVAssetWriterInput (like smaller than 128 in either dimension).
  
  if (adaptor.pixelBufferPool == nil) {
#ifdef LOGGING
    NSLog(@"Failed to start exprt session with movie size %d x %d", width, height);
#endif // LOGGING
    
    [videoWriterInput markAsFinished];
    [videoWriter finishWriting];
    
    // Remove output file when H264 compressor is not working
    
    worked = [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
    NSAssert(worked, @"could not remove output file");
    
    self.state = AVAssetWriterConvertFromMaxvidStateFailed;
    [pool drain];
    return;    
  }
 
  CVPixelBufferRef buffer = NULL;
  
  const int numFrames = [frameDecoder numFrames];
  int frameNum;
  for (frameNum = 0; frameNum < numFrames; frameNum++) {
    NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];

#ifdef LOGGING
    NSLog(@"Writing frame %d", frameNum);
#endif // LOGGING
    
    // FIXME: might reconsider logic design in terms of using block pull approach

    // http://stackoverflow.com/questions/11033421/optimization-of-cvpixelbufferref
    // https://developer.apple.com/library/mac/#documentation/AVFoundation/Reference/AVAssetWriterInput_Class/Reference/Reference.html
    
    while (adaptor.assetWriterInput.readyForMoreMediaData == FALSE) {
      // In the case where the input is not ready to accept input yet, wait until it is.
      // This is a little complex in the case of the main thread, because we would
      // need to visit the event loop in order for other processing tasks to happen.
      
#ifdef LOGGING
      NSLog(@"Waiting until writer is ready");
#endif // LOGGING
      
      NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
      [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
    }
    
    // Pull frame of data from MVID file
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameNum];
    UIImage *frameImage = frame.image;

    NSAssert(frame, @"advanceToFrame returned nil frame");
    NSAssert(frameImage, @"advanceToFrame returned frame with nil image");
    if (frame.isDuplicate) {
      // FIXME: (can output frame  duration time be explicitly set to deal with this duplication)
      // Input frame data is the same as the previous one : (keep using previous one)      
    }
    
    CVReturn poolResult = CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
    NSAssert(poolResult == kCVReturnSuccess, @"CVPixelBufferPoolCreatePixelBuffer");
    
#ifdef LOGGING
    NSLog(@"filling pixel buffer");
#endif // LOGGING
    
    // Buffer pool error conditions should have been handled already:
    // kCVReturnInvalidArgument = -6661 (some configuration value is invalid, like adaptor.pixelBufferPool is nil)
    // kCVReturnAllocationFailed = -6662
    
    [self fillPixelBufferFromImage:frameImage buffer:buffer size:movieSize];
    
    NSTimeInterval frameDuration = frameDecoder.frameDuration;
    NSAssert(frameDuration != 0.0, @"frameDuration not set in frameDecoder");
    int numerator = frameNum;
    int denominator = 1.0 / frameDuration;
    CMTime presentationTime = CMTimeMake(numerator, denominator);
    worked = [adaptor appendPixelBuffer:buffer withPresentationTime:presentationTime];
    
    if (worked == FALSE) {
      // Fails on 3G, but works on iphone 4, due to lack of hardware encoder on versions < 4      
      // com.apple.mediaserverd[18] : VTSelectAndCreateVideoEncoderInstance: no video encoder found for 'avc1'
      
      NSAssert(FALSE, @"appendPixelBuffer failed");
      
      // FIXME: Need to break out of loop and free writer elements in this fail case
    }
    
    CVPixelBufferRelease(buffer);
    
    [innerPool drain];
  }
  
  NSAssert(frameNum == numFrames, @"numFrames");
  
#ifdef LOGGING
  NSLog(@"successfully wrote %d frames", numFrames);
#endif // LOGGING
  
  // Done writing video data
  
  [videoWriterInput markAsFinished];
  
  [videoWriter finishWriting];
  
  // Note that [frameDecoder close] is implicitly invoked when the autorelease pool is drained.
  
  self.state = AVAssetWriterConvertFromMaxvidStateSuccess;
  
  [pool drain];
  return;
}

#define EMIT_FRAMES 0

// Given an input image that comes from the MVID file, write the image data out to
// the system pixel buffer.

// FIXME: It should be possible to avoid a render operation for each .mvid frame
// by checking to see if an already rendered framebuffer was created from
// reading the .mvid file.

- (void) fillPixelBufferFromImage:(UIImage*)image
                           buffer:(CVPixelBufferRef)buffer
                             size:(CGSize)size
{
  CVPixelBufferLockBaseAddress(buffer, 0);
  void *pxdata = CVPixelBufferGetBaseAddress(buffer);
  NSParameterAssert(pxdata != NULL);

  NSAssert(size.width == CVPixelBufferGetWidth(buffer), @"CVPixelBufferGetWidth");
  NSAssert(size.height == CVPixelBufferGetHeight(buffer), @"CVPixelBufferGetHeight");
  
  // zero out all pixel buffer memory before rendering an image (buffers are reused in pool)
  
  if (FALSE) {
    size_t bytesPerPBRow = CVPixelBufferGetBytesPerRow(buffer);
    size_t totalNumPBBytes = bytesPerPBRow * CVPixelBufferGetHeight(buffer);
    memset(pxdata, 0, totalNumPBBytes);
  }

  if (TRUE) {
    size_t bufferSize = CVPixelBufferGetDataSize(buffer);
    memset(pxdata, 0, bufferSize);
  }
  
  if (FALSE) {
    size_t bufferSize = CVPixelBufferGetDataSize(buffer);
    
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    
    size_t left, right, top, bottom;
    CVPixelBufferGetExtendedPixels(buffer, &left, &right, &top, &bottom);
    NSLog(@"extended pixels : left %d right %d top %d bottom %d", (int)left, (int)right, (int)top, (int)bottom);
    
    NSLog(@"buffer size = %d (bpr %d), row bytes (%d) * height (%d) = %d", (int)bufferSize, (int)(bufferSize/size.height), (int)bytesPerRow, (int)size.height, (int)(bytesPerRow * size.height));

  }
  
  size_t bitsPerComponent;
  size_t numComponents;
  size_t bitsPerPixel;
  size_t bytesPerRow;
  
  // 24 BPP with no alpha channel
  
  bitsPerComponent = 8;
  numComponents = 4;
  bitsPerPixel = bitsPerComponent * numComponents;
  bytesPerRow = size.width * (bitsPerPixel / 8);
  
	CGBitmapInfo bitmapInfo = 0;
  bitmapInfo |= kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst;
  
	CGColorSpaceRef colorSpace = CGImageGetColorSpace(image.CGImage);
  
	CGContextRef bitmapContext =
    CGBitmapContextCreate(pxdata, size.width, size.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
  
	if (bitmapContext == NULL) {
    NSAssert(FALSE, @"CGBitmapContextCreate() failed");
	}
  
  CGContextDrawImage(bitmapContext, CGRectMake(0, 0, size.width, size.height), image.CGImage);
  
  if (EMIT_FRAMES) {
    static int frameCount = 0;
    UIImage *useImage /*= image*/;
    
    if (FALSE) {
      CGFrameBuffer *cgFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24
                                                                             width:size.width
                                                                            height:size.height];
      cgFrameBuffer.colorspace = colorSpace;
      
      memcpy(cgFrameBuffer.pixels, pxdata, size.width * size.height * sizeof(uint32_t));
      
      CGImageRef imgRef = [cgFrameBuffer createCGImageRef];
      NSAssert(imgRef, @"CGImageRef returned by createCGImageRef is NULL");
    
      UIImage *uiImage = [UIImage imageWithCGImage:imgRef];
      CGImageRelease(imgRef);
      
      useImage = uiImage;
    }

    
    NSString *filename = [NSString stringWithFormat:@"frame%d.png", frameCount++];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    NSData *data = [NSData dataWithData:UIImagePNGRepresentation(useImage)];
    [data writeToFile:path atomically:YES];
    //NSLog(@"wrote %@", path);
  }
  
  CGContextRelease(bitmapContext);
  
  CVPixelBufferFillExtendedPixels(buffer);
  
  CVPixelBufferUnlockBaseAddress(buffer, 0);
    
  return;
}

// This method will send a notification to indicate that a encoding has completed successfully.

- (void) notifyEncodingDoneInMainThread
{
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
 
  NSString *notificationName = AVAssetWriterConvertFromMaxvidCompletedNotification;
  
  [[NSNotificationCenter defaultCenter] postNotificationName:notificationName
                                                      object:self];	
}

// Secondary thread entry point for non blocking encode operation

- (void) nonblockingEncodeEntryPoint {  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  [self blockingEncode];
  
  [self performSelectorOnMainThread:@selector(notifyEncodingDoneInMainThread) withObject:nil waitUntilDone:TRUE];
  
  [pool drain];
  return;
}

// Kick off an async (non-blocking call) encode operation in a secondary
// thread. This method will deliver a Completed notification
// in the main thread when complete.

- (void) nonblockingEncode
{
  if (FALSE) {
    [self nonblockingEncodeEntryPoint];
  }
  [NSThread detachNewThreadSelector:@selector(nonblockingEncodeEntryPoint) toTarget:self withObject:nil];
  return;
}

// Return a string that describes the hardware this code is executing on.

+ (NSString*) platform
{
  size_t size;
  sysctlbyname("hw.machine", NULL, &size, NULL, 0);
  char *machine = malloc(size);
  sysctlbyname("hw.machine", machine, &size, NULL, 0);
  NSString *platform = [NSString stringWithUTF8String:machine];
  free(machine);
  return platform;
}

// Return TRUE if this device contains a hardware H264 encoder.

+ (BOOL) isHardwareEncoderAvailable
{
  BOOL hasEncoder;
  NSString *platform = [self platform];

  if ([platform hasPrefix:@"iPhone"]) {
    NSDictionary *knownModelsWithoutEncoder = [NSDictionary dictionaryWithObjectsAndKeys:
                                               @"", @"iPhone1,1", // iPhone 1G
                                               @"", @"iPhone1,2", // iPhone 3G
                                               nil];

    if ([knownModelsWithoutEncoder objectForKey:platform] != nil) {
      hasEncoder = FALSE;
    } else {
      // Assume that all newer models will contain encoder hardware
      // 
      // "iPhone2,1" // "iPhone 3GS"
      // "iPhone3,1" // "iPhone 4"
      // "iPhone3,3" // "Verizon iPhone 4"
      // "iPhone4,1" // "iPhone 4S"
      hasEncoder = TRUE;      
    }
  } else if ([platform hasPrefix:@"iPod"]) {
    NSDictionary *knownModelsWithoutEncoder = [NSDictionary dictionaryWithObjectsAndKeys:
                                               @"", @"iPod1,1",   // iPod Touch 1G
                                               @"", @"iPod2,1",   // iPod Touch 2G
                                               @"", @"iPod3,1",   // iPod Touch 3G
                                               nil];
    
    if ([knownModelsWithoutEncoder objectForKey:platform] != nil) {
      hasEncoder = FALSE;
    } else {
      // Assume that all newer models will contain encoder hardware
      // 
      // "iPod4,1"   // "iPod Touch 4G"
      hasEncoder = TRUE;      
    }    
  } else if ([platform hasPrefix:@"iPad"]) {
    // All iPad models contain the hardware encoder
    
    hasEncoder = TRUE;
  } else if ([platform isEqualToString:@"i386"] || [platform isEqualToString:@"x86_64"]) {
    // Assume the Simulator supports H264 encoding using platform software codec
    
    hasEncoder = TRUE;
  } else {
    // Unknown model
    
    hasEncoder = FALSE;
  }
  
  return hasEncoder;
}

@end

#endif // HAS_AVASSET_CONVERT_MAXVID
