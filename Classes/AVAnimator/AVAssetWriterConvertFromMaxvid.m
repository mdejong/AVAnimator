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

// Private API

@interface AVAssetWriterConvertFromMaxvid ()

@property (nonatomic, retain) AVAssetWriter *aVAssetWriter;

@property (nonatomic, retain) UIImage *lastFrameImage;

- (void) fillPixelBufferFromImage:(UIImage*)image
                           buffer:(CVPixelBufferRef)buffer
                             size:(CGSize)size;

@end


@implementation AVAssetWriterConvertFromMaxvid

@synthesize state = m_state;
@synthesize inputPath = m_inputPath;
@synthesize outputPath = m_outputPath;
@synthesize aVAssetWriter = m_aVAssetWriter;
@synthesize lastFrameImage = m_lastFrameImage;

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

// Kick off blocking encode operation to convert .mvid to .mov (h264)

- (void) blockingEncode
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  BOOL worked;
  
  // Input file is a .mvid video file like "walk.mvid"

  NSString *inputPath = self.inputPath;
  NSAssert(inputPath, @"inputPath");
  
  // FIXME: add support for ".mvid.7z" compressed entries (current a .mvid is required)
  
  // FIXME: ensure that decode is closed in any failure path from this function.
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  NSAssert(frameDecoder, @"frameDecoder");
  
  worked = [frameDecoder openForReading:inputPath];
  
  if (!worked) {
    NSLog(@"frameDecoder openForReading failed");
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
  
  CGSize movieSize = CGSizeMake([frameDecoder width], [frameDecoder height]);
  
  // Output file is a file name like "out.mov" or "out.m4v"
  
  NSString *outputPath = self.outputPath;
  NSAssert(outputPath, @"outputPath");
  NSURL *outputPathURL = [NSURL fileURLWithPath:outputPath];
  NSAssert(outputPathURL, @"outputPathURL");
  NSError *error = nil;
  
  // Output types:
  // AVFileTypeQuickTimeMovie
  // AVFileTypeMPEG4 (no)
  
  AVAssetWriter *videoWriter = [[AVAssetWriter alloc] initWithURL:outputPathURL
                                                         fileType:AVFileTypeQuickTimeMovie
                                                            error:&error];
  NSAssert(videoWriter, @"videoWriter");
    
  NSNumber *widthNum = [NSNumber numberWithUnsignedInt:movieSize.width];
  NSNumber *heightNum = [NSNumber numberWithUnsignedInt:movieSize.height];
  
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
  
  for (int frameNum=0; frameNum < numFrames; frameNum++) {
    NSAutoreleasePool *innerPool = [[NSAutoreleasePool alloc] init];
    // FIXME: might want to put a release loop around each iteration to avoid
    // running out of memory.
    
    UIImage *frameImage = [frameDecoder advanceToFrame:frameNum];
    
    if (frameImage == nil) {
      // FIXME: (can output frame  duration time be explicitly set to deal with this duplication)
      // Input frame data is the same as the previous one : (keep using previous one)
      frameImage = self.lastFrameImage;
      NSAssert(frameImage, @"self.lastFrameImage");
    } else {
      self.lastFrameImage = frameImage;
    }
    
    CVReturn poolResult = CVPixelBufferPoolCreatePixelBuffer(NULL, adaptor.pixelBufferPool, &buffer);
    NSAssert(poolResult == kCVReturnSuccess, @"CVPixelBufferPoolCreatePixelBuffer");
    
    // Buffer pool error conditions should have been handled already:
    // kCVReturnInvalidArgument = -6661 (some configuration value is invalid, like adaptor.pixelBufferPool is nil)
    // kCVReturnAllocationFailed = -6662
    
    [self fillPixelBufferFromImage:frameImage buffer:buffer size:movieSize];
    
    // FIXME: this while loop can sometimes go into an infinite loop. Unclear about timing from one encode to another
    // http://stackoverflow.com/questions/11033421/optimization-of-cvpixelbufferref (see input loop block usage)
    
    while (adaptor.assetWriterInput.readyForMoreMediaData == FALSE) {
      // FIXME : Wait until assetWriter is ready to accept additional input data
      NSLog(@"sleep until writer is ready");
      
      [NSThread sleepForTimeInterval:0.1];
    }
    
    int numerator = frameNum;
    int denominator = 1 / frameDecoder.frameDuration;
    CMTime presentationTime = CMTimeMake(numerator, denominator);
    worked = [adaptor appendPixelBuffer:buffer withPresentationTime:presentationTime];
    
    if (worked == FALSE) {
      // Fails on 3G, but works on iphone 4, due to lack of hardware encoder on 3G and earlier
      
      // com.apple.mediaserverd[18] : VTSelectAndCreateVideoEncoderInstance: no video encoder found for 'avc1'
      
      NSLog(@"failed to append buffer");
      NSAssert(FALSE, @"appendPixelBuffer failed");
    }
    
    CVPixelBufferRelease(buffer);
    
    [innerPool drain];
  }
  
  // Done writing video data
  
  [videoWriterInput markAsFinished];
  
  [videoWriter finishWriting];
  
  // Note that [frameDecoder close] is implicitly invoked when the autorelease pool is drained.
  
  if (FALSE) {
    // Give hardware time to shut down (issue on iPad 2)
    [NSThread sleepForTimeInterval:0.1];
  }
  
  self.state = AVAssetWriterConvertFromMaxvidStateSuccess;
  
  [pool drain];
  return;
}

#define EMIT_FRAMES 0

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
  
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  
	CGContextRef bitmapContext =
    CGBitmapContextCreate(pxdata, size.width, size.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
  
	CGColorSpaceRelease(colorSpace);
  
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
    NSLog(@"wrote %@", path);
  }
  
  CGContextRelease(bitmapContext);
  
  CVPixelBufferFillExtendedPixels(buffer);
  
  CVPixelBufferUnlockBaseAddress(buffer, 0);
    
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
                                               @"", @"iPhone2,1", // iPhone 3GS
                                               nil];

    if ([knownModelsWithoutEncoder objectForKey:platform] != nil) {
      hasEncoder = FALSE;
    } else {
      // Assume that all newer models will contain encoder hardware
      // 
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
