//
//  AVAssetWriterConvertFromMaxvid.m
//
//  Created by Moses DeJong on 7/8/12.
//
//  License terms defined in License.txt.
//
//  This module implements a MVID to H264 encoder API that can be used to
//  encode the video frames from an MVID file into a H264 video in
//  a Quicktime container. The H264 video format is lossy as compared to
//  a lossless H264, but the space savings can be quite significant.

#import "AVAssetWriterConvertFromMaxvid.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

#import <AVFoundation/AVFoundation.h>

#import <AVFoundation/AVAsset.h>
#import <AVFoundation/AVAssetWriter.h>
#import <AVFoundation/AVAssetWriterInput.h>

//#import <CoreMedia/CMSampleBuffer.h>

//#import "CGFrameBuffer.h"

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

- (void) encodeOutputFile
{
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
    return;
  }
  
  worked = [frameDecoder allocateDecodeResources];  
  
  if (!worked) {
    NSLog(@"frameDecoder allocateDecodeResources failed");
    // FIXME: create specific failure flags for input vs output files
    self.state = AVAssetWriterConvertFromMaxvidStateFailed;
    return;
  }
  
  CGSize movieSize = CGSizeMake([frameDecoder width], [frameDecoder height]);
  
  // Output file is typically something like "out.m4v"
  
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
                                            [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32ARGB], kCVPixelBufferPixelFormatTypeKey,
                                            widthNum,  kCVPixelBufferWidthKey,
                                            heightNum, kCVPixelBufferHeightKey,
                                            nil];
  
  AVAssetWriterInputPixelBufferAdaptor *adaptor = [AVAssetWriterInputPixelBufferAdaptor
                                                   assetWriterInputPixelBufferAdaptorWithAssetWriterInput:videoWriterInput
                                                   sourcePixelBufferAttributes:adaptorAttributes];

  // Media data comes from an input file, not real time
  
  videoWriterInput.expectsMediaDataInRealTime = NO;
  
  NSAssert([videoWriter canAddInput:videoWriterInput], @"canAddInput");
  [videoWriter addInput:videoWriterInput];
  
  // Start writing samples to video file
  
  [videoWriter startWriting];
  [videoWriter startSessionAtSourceTime:kCMTimeZero];
 
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
    
    [self fillPixelBufferFromImage:frameImage buffer:buffer size:movieSize];
    
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
    
    [innerPool drain];
  }
  
  // Done writing video data
  
  [videoWriterInput markAsFinished];
  
  [videoWriter finishWriting];
  
  [frameDecoder close];
  
  self.state = AVAssetWriterConvertFromMaxvidStateSuccess;
  
  return;
}

- (void) fillPixelBufferFromImage:(UIImage*)image
                           buffer:(CVPixelBufferRef)buffer
                             size:(CGSize)size
{
  CVPixelBufferLockBaseAddress(buffer, 0);
  void *pxdata = CVPixelBufferGetBaseAddress(buffer);
  NSParameterAssert(pxdata != NULL);
  
  //CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
  
  // FIXME : is this wrong bitmap info ?
  // kCGImageAlphaNoneSkipFirst
  //CGContextRef context = CGBitmapContextCreate(pxdata, size.width, size.height, 8, 4*size.width, rgbColorSpace, kCGImageAlphaPremultipliedFirst);
  //NSAssert(context, @"context");
  
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
  
  CGColorSpaceRelease(colorSpace);
  CGContextRelease(bitmapContext);
  
  CVPixelBufferUnlockBaseAddress(buffer, 0);

  return;
}

@end

#endif // HAS_AVASSET_CONVERT_MAXVID
