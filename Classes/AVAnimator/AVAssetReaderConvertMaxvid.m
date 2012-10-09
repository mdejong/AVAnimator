//
//  AVAssetReaderConvertMaxvid.m
//
//  Created by Moses DeJong on 2/4/12.
//
//  License terms defined in License.txt.
//
//  This module implements a H264 to MVID decoder that can be used to
//  save the raw bits of a H264 video into a file.

#import "AVAssetReaderConvertMaxvid.h"

#import "maxvid_file.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

#import <AVFoundation/AVFoundation.h>

#import <AVFoundation/AVAsset.h>
#import <AVFoundation/AVAssetReader.h>
#import <AVFoundation/AVAssetReaderOutput.h>

#import <CoreMedia/CMSampleBuffer.h>

#import "CGFrameBuffer.h"

#define LOGGING

NSString * const AVAssetReaderConvertMaxvidCompletedNotification = @"AVAssetReaderConvertMaxvidCompletedNotification";

// Private API

@interface AVAssetReaderConvertMaxvid ()

@property (nonatomic, retain) AVAssetReader *aVAssetReader;
@property (nonatomic, retain) AVAssetReaderOutput *aVAssetReaderOutput;

- (BOOL) renderIntoFramebuffer:(CMSampleBufferRef)sampleBuffer frameBuffer:(CGFrameBuffer**)frameBufferPtr;

@end


@implementation AVAssetReaderConvertMaxvid

@synthesize assetURL = m_assetURL;
@synthesize aVAssetReader = m_aVAssetReader;
@synthesize aVAssetReaderOutput = m_aVAssetReaderOutput;
@synthesize wasSuccessful = m_wasSuccessful;

- (void) dealloc
{  
  self.assetURL = nil;
  self.aVAssetReader = nil;
  self.aVAssetReaderOutput = nil;
  [super dealloc];
}

+ (AVAssetReaderConvertMaxvid*) aVAssetReaderConvertMaxvid
{
  return [[[AVAssetReaderConvertMaxvid alloc] init] autorelease];
}

// This utility method will setup the asset so that it is opened and ready
// to decode frames of video data.

- (BOOL) setupAsset
{
  NSAssert(self.assetURL, @"assetURL");
  NSAssert(self.mvidPath, @"mvidPath");
  
  NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                                      forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
  
  AVURLAsset *avUrlAsset = [[[AVURLAsset alloc] initWithURL:self.assetURL options:options] autorelease];
  NSAssert(avUrlAsset, @"AVURLAsset");
  
  // FIXME: return false error code if something goes wrong
  
  // Check for DRM protected content
  
  if (avUrlAsset.hasProtectedContent) {
    NSAssert(FALSE, @"DRM");
  }
  
  if ([avUrlAsset tracks] == 0) {
    NSAssert(FALSE, @"not tracks");
  }
  
  NSError *assetError = nil;
  self.aVAssetReader = [AVAssetReader assetReaderWithAsset:avUrlAsset error:&assetError];
  
  NSAssert(self.aVAssetReader, @"aVAssetReader");
  
  if (assetError) {
    NSAssert(FALSE, @"AVAssetReader");
  }
  
  // This video setting indicates that native 32 bit endian pixels with a leading
  // ignored alpha channel will be emitted by the decoding process.
  
  NSDictionary *videoSettings;
  videoSettings = [NSDictionary dictionaryWithObject:
                   [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
  
  NSArray *videoTracks = [avUrlAsset tracksWithMediaType:AVMediaTypeVideo];
  
  NSAssert([videoTracks count] == 1, @"only 1 video track can be decoded");
  
  AVAssetTrack *videoTrack = [videoTracks objectAtIndex:0];
  
#ifdef LOGGING
  NSArray *availableMetadataFormats = videoTrack.availableMetadataFormats;
  NSLog(@"availableMetadataFormats %@", availableMetadataFormats);
#endif // LOGGING
  
  // track must be self contained
  
  NSAssert(videoTrack.isSelfContained, @"isSelfContained");
  
  // playback framerate
  
  CMTimeRange timeRange = videoTrack.timeRange;
  
  float duration = (float)CMTimeGetSeconds(timeRange.duration);
  
  float nominalFrameRate = videoTrack.nominalFrameRate;
  
  float frameDuration = 1.0 / nominalFrameRate;
  self.frameDuration = frameDuration;

  float numFramesFloat = duration / frameDuration;
  int numFrames = round( numFramesFloat );
  float durationForNumFrames = numFrames * frameDuration;
  float durationRemainder = duration - durationForNumFrames;
  float durationTenPercent = frameDuration * 0.10;
  
#ifdef LOGGING
  NSLog(@"frame rate = %0.2f FPS", nominalFrameRate);
  NSLog(@"frame duration = %0.4f FPS", frameDuration);
  NSLog(@"duration = %0.2f S", duration);
  NSLog(@"numFrames = %0.4f -> %d", numFramesFloat, numFrames);
  NSLog(@"durationRemainder = %0.4f", durationRemainder);
  NSLog(@"durationTenPercent = %0.4f", durationTenPercent);
#endif // LOGGING
  
  if (durationRemainder >= durationTenPercent) {
    NSLog(@"durationRemainder is larger than durationTenPercent");
    numFrames += 1;
  }
  
  self.totalNumFrames = numFrames;
  
  AVAssetReaderTrackOutput *aVAssetReaderOutput = [[[AVAssetReaderTrackOutput alloc]
                                                    initWithTrack:videoTrack outputSettings:videoSettings] autorelease];
  
  NSAssert(aVAssetReaderOutput, @"AVAssetReaderVideoCompositionOutput failed");
  
  // Read video data from the inidicated tracks of video data
  
  [self.aVAssetReader addOutput:aVAssetReaderOutput];
  
  self.aVAssetReaderOutput = aVAssetReaderOutput;
  
  return TRUE;
}

// Read video data from a single track (only one video track is supported anyway)

- (BOOL) blockingDecode
{
  BOOL worked;
  BOOL retstatus = FALSE;
  
  self.wasSuccessful = FALSE;
  
  AVAssetReader *aVAssetReader = nil;
  
  worked = [self setupAsset];
  if (worked == FALSE) {
    goto retcode;
  }
    
  CMSampleBufferRef sampleBuffer = NULL;
  
  self.bpp = 24;
  
  // Note that by default, the device RGB colorspace on iOS is sRGB. So, explicitly mark
  // the .mvid file as being encoded in the sRGB colorspace. When not running on iOS,
  // the target framebuffer must be set to the sRGB colorspace in order for the output
  // pixels to be converted to sRGB.
  
  self.isSRGB = TRUE;
    
  worked = [self open];
  
  if (worked == FALSE) {
    goto retcode;
  }
  
  // Start reading from asset
  
  aVAssetReader = self.aVAssetReader;
  
  worked = [self.aVAssetReader startReading];
  
  if (!worked) {
    AVAssetReaderStatus status = aVAssetReader.status;
    NSError *error = aVAssetReader.error;
    
    NSLog(@"status = %d", status);
    NSLog(@"error = %@", [error description]);
  }
  
  size_t movieWidth = 0;
  size_t movieHeight = 0;  
  
  BOOL writeFailed = FALSE;
  
  // This framebuffer object will be the destination of a render operation
  // for a given frame. Multiple frames must always be the same size,
  // so a common render buffer will be allocated.
  
  CGFrameBuffer *frameBuffer = nil;
  
  float prevFrameDisplayTime = 0.0;
  
  float frameDurationTooEarly = (self.frameDuration * 0.90);
  
  while ((writeFailed == FALSE) && ([aVAssetReader status] == AVAssetReaderStatusReading))
  {
    NSAutoreleasePool *inner_pool = [[NSAutoreleasePool alloc] init];
    
#ifdef LOGGING
    NSLog(@"READING frame %d", self.frameNum);
#endif // LOGGING
    
    sampleBuffer = [self.aVAssetReaderOutput copyNextSampleBuffer];
    
    if (sampleBuffer) {
      worked = [self renderIntoFramebuffer:sampleBuffer frameBuffer:&frameBuffer];
      NSAssert(worked, @"worked");
      
      // If the delay between the previous frame and the current frame is more
      // than would be needed for one frame, then emit nop frames.

      // If a sample would be displayed for one frame, then the next one should
      // be displayed right away. But, in the case where a sample duration is
      // longer than one frame, emit repeated frames as no-op frames.
      
      CMTime presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
      
      float frameDisplayTime = (float) CMTimeGetSeconds(presentationTimeStamp);
      
      float expectedFrameDisplayTime = self.frameNum * self.frameDuration;
      
#ifdef LOGGING
      NSLog(@"frame presentation time = %0.4f", frameDisplayTime);
      NSLog(@"expected frame presentation time = %0.4f", expectedFrameDisplayTime);
      NSLog(@"prev frame presentation time = %0.4f", prevFrameDisplayTime);
#endif // LOGGING
      
      // Check for display time clock drift. This is caused by a frame that has
      // a frame display time that is so early that it is almost a whole frame
      // early. The decoder can't deal with this case because we have to maintain
      // an absolute display delta between frames. To fix the problem, we have
      // to drop a frame to let actual display time catch up to the expected
      // frame display time. We have already calculated the total number of frames
      // based on the reported duration of the whole movie, so this logic has the
      // effect of keeping the total duration consistent once the data is stored
      // in equally spaced frames.
      
      float frameDisplayEarly = 0.0;
      if (frameDisplayTime < expectedFrameDisplayTime) {
        frameDisplayEarly = expectedFrameDisplayTime - frameDisplayTime;
      }
      if (frameDisplayEarly > frameDurationTooEarly) {
        // The actual presentation time has drifted from the expected presentation time
        
#ifdef LOGGING
        NSLog(@"frame presentation drifted too early = %0.4f", frameDisplayEarly);
#endif // LOGGING
        
        // Drop the frame, meaning we do not write it to the .mvid file. Instead, let
        // processing continue with the next frame which will display at about the
        // right expected time. The frame number stays the same since no output
        // buffer was written. Note that we need to reset the prevFrameDisplayTime so
        // that no trailing nop frame is emitted in the normal case.
        
        prevFrameDisplayTime = expectedFrameDisplayTime;
        CFRelease(sampleBuffer);
        [inner_pool drain];
        continue;
      }
            
      float delta = frameDisplayTime - prevFrameDisplayTime;
      
      prevFrameDisplayTime = frameDisplayTime;
      
      [self writeTrailingNopFrames:delta];
            
#ifdef LOGGING
      NSLog(@"WRITTING frame %d", self.frameNum);
#endif // LOGGING
      
      // Note that the frameBuffer object is explicitly retained so that it can
      // be used in each loop iteration.
            
      // Get and verify buffer width and height.
      
      size_t width = frameBuffer.width;
      size_t height = frameBuffer.height;

      NSAssert(width > 0, @"width");
      NSAssert(height > 0, @"height");
      
      if (movieWidth == 0) {
        movieWidth = width;
        movieHeight = height;
        
        self.movieSize = CGSizeMake(movieWidth, movieHeight);
      } else {
        NSAssert(movieWidth == width, @"movieWidth");
        NSAssert(movieHeight == height, @"movieHeight");
      }
      
      // Calculate how many bytes make up the image via (bytesPerRow * height). The
      // numBytes value may be padded out to fit to an OS page bound.
      
      int bufferSize = movieWidth * movieHeight * frameBuffer.bytesPerPixel;
      int expectedBufferSize = (movieWidth * movieHeight * sizeof(uint32_t));
      NSAssert(bufferSize == expectedBufferSize, @"framebuffer size");
      
      // write entire buffer of raw 32bit pixels to the file.
      // bitmap info is native (kCGImageAlphaNoneSkipFirst|kCGBitmapByteOrder32Little)
      
      worked = [self writeKeyframe:frameBuffer.pixels bufferSize:bufferSize];
      
      if (worked == FALSE) {
        writeFailed = TRUE;
      }
            
      CFRelease(sampleBuffer);
    } else if ([aVAssetReader status] == AVAssetReaderStatusReading) {
      AVAssetReaderStatus status = aVAssetReader.status;
      NSError *error = aVAssetReader.error;
      
      NSLog(@"status = %d", status);
      NSLog(@"error = %@", [error description]);
    }
    
    [inner_pool drain];
  }

  // Double check that we did not write too few frames.
  
  NSAssert(self.frameNum == self.totalNumFrames, @"frameNum == totalNumFrames");
  
  // Explicitly release the retained frameBuffer
  
  [frameBuffer release];

  worked = [self rewriteHeader];
  
  [self close];
  
  if (worked == FALSE) {
    goto retcode;
  }
  
  retstatus = TRUE;
  
retcode:
  
  [aVAssetReader cancelReading];
    
  if (retstatus) {
#ifdef LOGGING
    NSLog(@"wrote %@", self.mvidPath);
#endif // LOGGING
  } else {
#ifdef LOGGING
    NSLog(@"failed to write %@", self.mvidPath);
#endif // LOGGING
  }
  
  if (retstatus) {
    self.wasSuccessful = TRUE;
  } else {
    self.wasSuccessful = FALSE;
  }
  return retstatus;
}

// Render sample buffer into flat CGFrameBuffer. We can't read the samples
// directly out of the CVImageBufferRef because the rows of the image
// have some funky padding going on, likely "planar" data from YUV colorspace.
// The caller of this method should provide a location where a single
// frameBuffer can be stored so that multiple calls to this render function
// will make use of the same buffer.

- (BOOL) renderIntoFramebuffer:(CMSampleBufferRef)sampleBuffer frameBuffer:(CGFrameBuffer**)frameBufferPtr
{
  CGFrameBuffer *frameBuffer = *frameBufferPtr;
  
  CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  
  CVPixelBufferLockBaseAddress(imageBuffer,0);
  
  size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
  
  size_t width = CVPixelBufferGetWidth(imageBuffer);
  
  size_t height = CVPixelBufferGetHeight(imageBuffer);
    
  void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
  
  size_t bufferSize = CVPixelBufferGetDataSize(imageBuffer);
  
  if (FALSE) {
    size_t left, right, top, bottom;
    CVPixelBufferGetExtendedPixels(imageBuffer, &left, &right, &top, &bottom);
    NSLog(@"extended pixels : left %d right %d top %d bottom %d", (int)left, (int)right, (int)top, (int)bottom);

    NSLog(@"buffer size = %d (bpr %d), row bytes (%d) * height (%d) = %d", (int)bufferSize, (int)(bufferSize/height), (int)bytesPerRow, (int)height, (int)(bytesPerRow * height));
  }
  
  // Under iOS, the output pixels are implicitly treated as sRGB when using the device
  // colorspace. Under MacOSX, explicitly set the output colorspace to sRGB.
  
  CGColorSpaceRef colorSpace = NULL;
#if TARGET_OS_IPHONE
  colorSpace = CGColorSpaceCreateDeviceRGB();
#else
  // MacOSX
  
  //colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
  colorSpace = CVImageBufferGetColorSpace(imageBuffer);
#endif // TARGET_OS_IPHONE
  NSAssert(colorSpace, @"colorSpace");  

  // Create a Quartz direct-access data provider that uses data we supply.
  
  CGDataProviderRef dataProvider =
    CGDataProviderCreateWithData(NULL, baseAddress, bufferSize, NULL);
  
  CGImageRef cgImageRef = CGImageCreate(width, height, 8, 32, bytesPerRow,
                colorSpace, kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst,
                dataProvider, NULL, true, kCGRenderingIntentDefault);
  
	CGColorSpaceRelease(colorSpace);
  CGDataProviderRelease(dataProvider);

  // Render CoreGraphics image into a flat bitmap framebuffer. Note that this object is
  // not autoreleased, instead the caller must explicitly release the ref.
  
  if (frameBuffer == NULL) {
    *frameBufferPtr = [[CGFrameBuffer alloc] initWithBppDimensions:24 width:width height:height];
    frameBuffer = *frameBufferPtr;
    NSAssert(frameBuffer, @"frameBuffer");
    
    // Use sRGB by default on iOS. Explicitly set sRGB as colorspace on MacOSX.
    
#if TARGET_OS_IPHONE
    // No-op
#else
    // MacOSX
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    frameBuffer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
#endif // TARGET_OS_IPHONE
  }
  
  [frameBuffer renderCGImage:cgImageRef];
                                
  CGImageRelease(cgImageRef);
                                
  CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
  
  return TRUE;
}

// This method will send a notification to indicate that op has completed successfully.

- (void) notifyDecodingDoneInMainThread
{
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
  
  NSString *notificationName = AVAssetReaderConvertMaxvidCompletedNotification;
  
  [[NSNotificationCenter defaultCenter] postNotificationName:notificationName
                                                      object:self];	
}

// Secondary thread entry point for non blocking operation

- (void) nonblockingDecodeEntryPoint {  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  [self blockingDecode];
  
  if (FALSE) {
    [self notifyDecodingDoneInMainThread];
  }
  
  [self performSelectorOnMainThread:@selector(notifyDecodingDoneInMainThread) withObject:nil waitUntilDone:TRUE];
  
  [pool drain];
  return;
}

// Kick off an async (non-blocking call) decode operation in a secondary
// thread. This method will deliver a Completed notification
// in the main thread when complete.

- (void) nonblockingDecode
{
  if (FALSE) {
    [self nonblockingDecodeEntryPoint];
  }
  [NSThread detachNewThreadSelector:@selector(nonblockingDecodeEntryPoint) toTarget:self withObject:nil];
  return;
}

@end

#endif // HAS_AVASSET_CONVERT_MAXVID
