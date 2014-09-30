//
//  AVAssetFrameDecoder.m
//
//  Created by Moses DeJong on 1/4/13.
//
//  License terms defined in License.txt.

#import "AVAssetFrameDecoder.h"

#if __has_feature(objc_arc)
#else
#import "AutoPropertyRelease.h"
#endif // objc_arc

#import "CGFrameBuffer.h"

#import "AVFrame.h"

#import <AVFoundation/AVFoundation.h>

#import <AVFoundation/AVAsset.h>
#import <AVFoundation/AVAssetReader.h>
#import <AVFoundation/AVAssetReaderOutput.h>

#import <CoreMedia/CMSampleBuffer.h>

#import "AVMvidFileWriter.h" // for countTrailingNopFrames

#if defined(HAS_AVASSET_CONVERT_MAXVID)

//#define LOGGING

typedef enum
{
  // Attempted to read from asset, but data was not available, retry. Note that this
  // code could be returned in the case where a sample buffer is read a nil. The
  // caller is expected to check that status flags on the asset reader in order
  // to determine if the asset reader is finished reading frames.
  FrameReadStatusNotReady,
  
  // Read the next frame from the asset successfully
  FrameReadStatusNextFrame,
  
  // Did not read the next frame because the previous frame data is duplicated
  // as a "nop frame"
  FrameReadStatusDup,
  
  // Reading a frame was successful, but the indicated display time is so early
  // that is too early to be decoded as the "next" frame. Ignore an odd frame
  // like this and continue to decode the next frame.
  FrameReadStatusTooEarly,
  
  // Done reading frames from the asset. Note that it is possible that frames
  // could have all been read but the final frame has a long "implicit" duration.
  FrameReadStatusDone
} FrameReadStatus;

// Private API

@interface AVAssetFrameDecoder ()

@property (nonatomic, copy) NSURL         *assetURL;

@property (nonatomic, retain) AVAssetReader *aVAssetReader;

@property (nonatomic, retain) AVAssetReaderOutput *aVAssetReaderOutput;

@property (nonatomic, retain) CGFrameBuffer *currentFrameBuffer;

// This is the last AVFrame object returned via a call to advanceToFrame

@property (nonatomic, retain) AVFrame *lastFrame;

- (BOOL) renderIntoFramebuffer:(CMSampleBufferRef)sampleBuffer frameBuffer:(CGFrameBuffer**)frameBufferPtr;

@end


@implementation AVAssetFrameDecoder

@synthesize assetURL = m_assetURL;

@synthesize aVAssetReader = m_aVAssetReader;

@synthesize aVAssetReaderOutput = m_aVAssetReaderOutput;

@synthesize currentFrameBuffer = m_currentFrameBuffer;

@synthesize lastFrame = m_lastFrame;

@synthesize produceCoreVideoPixelBuffers = m_produceCoreVideoPixelBuffers;

- (void) dealloc
{
#if __has_feature(objc_arc)
#else
  [AutoPropertyRelease releaseProperties:self thisClass:AVAssetFrameDecoder.class];
  [super dealloc];
#endif // objc_arc
}

+ (AVAssetFrameDecoder*) aVAssetFrameDecoder
{
  AVAssetFrameDecoder *obj = [[AVAssetFrameDecoder alloc] init];
  obj->frameIndex = -1;
  
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

// This utility method will setup the asset so that it is opened and ready
// to decode frames of video data.

- (BOOL) setupAsset
{
  NSAssert(self.assetURL, @"assetURL");
  
  NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                                      forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
  
  AVURLAsset *avUrlAsset = [[AVURLAsset alloc] initWithURL:self.assetURL options:options];
#if __has_feature(objc_arc)
#else
  avUrlAsset = [avUrlAsset autorelease];
#endif // objc_arc
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
  
  // Query the width x height of the track now, otherwise this info would
  // not be available until the first frame is decoded. But, that would
  // be too late since it would mean we could not allocate an output
  // buffer of a known width and height until the first frame had been
  // decoded.
  
  CGSize naturalSize = videoTrack.naturalSize;
  
#ifdef LOGGING
  float naturalWidth = naturalSize.width;
  float naturalHeight = naturalSize.height;
  NSLog(@"video track naturalSize w x h : %d x %d", (int)naturalWidth, (int)naturalHeight);
#endif // LOGGING
  
  detectedMovieSize = naturalSize;
  
  // playback framerate
  
  CMTimeRange timeRange = videoTrack.timeRange;
  
  float duration = (float)CMTimeGetSeconds(timeRange.duration);
  
  float nominalFrameRate = videoTrack.nominalFrameRate;
  
  float frameDuration = 1.0 / nominalFrameRate;
  self->m_frameDuration = (NSTimeInterval)frameDuration;
  
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
  
  self->m_numFrames = numFrames;
  
  AVAssetReaderTrackOutput *aVAssetReaderOutput = [[AVAssetReaderTrackOutput alloc]
                                                    initWithTrack:videoTrack outputSettings:videoSettings];
#if __has_feature(objc_arc)
#else
  aVAssetReaderOutput = [aVAssetReaderOutput autorelease];
#endif // objc_arc
  
  NSAssert(aVAssetReaderOutput, @"AVAssetReaderVideoCompositionOutput failed");

  // Optimize CoreVideo buffer usage by indicating that a framebuffer copy is not needed and that the
  // generated framebuffer will be treated as a readonly buffer. This reduces the mediaserverd CPU usage
  // from 30% to 20% on an iPad 2.
  
  aVAssetReaderOutput.alwaysCopiesSampleData = FALSE;
  
  // FIXME: If a frame decoder should decode only for a specific interval (segmented ranges)
  // then the following property could be used to limit the decoded frames range to a specific
  // set of frames.
  //
  //aVAssetReaderOutput.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(mSeekFrame / mFPS, 1), kCMTimePositiveInfinity);
  
  // Read video data from the inidicated tracks of video data
  
  [self.aVAssetReader addOutput:aVAssetReaderOutput];
  
  self.aVAssetReaderOutput = aVAssetReaderOutput;
  
  return TRUE;
}

// Return TRUE if starting to read from the asset file is successful, FALSE otherwise.
// Normally, reading from a H264 asset is successful as long as the file exists and it
// contains properly formatted H264 data.

- (BOOL) startReadingAsset
{
  BOOL worked;
  AVAssetReader *aVAssetReader = self.aVAssetReader;
  NSAssert(aVAssetReader, @"aVAssetReader");
  
  worked = [aVAssetReader startReading];
  
  if (worked == FALSE) {
    AVAssetReaderStatus status = aVAssetReader.status;
    NSError *error = aVAssetReader.error;
    
    NSLog(@"status = %d", (int)status);
    NSLog(@"error = %@", [error description]);
    
    return FALSE;
  } else {
    return TRUE;
  }
}

// Restart the decoder. Sadly, the asset reader API only seems to want to read data once.
// As soon as it is finished playing, it is dead.

- (BOOL) restart
{
#ifdef LOGGING
  NSLog(@"restart");
#endif // LOGGING

  [self close];
  
  BOOL worked;

  worked = [self openForReading:[self.assetURL path]];

  if (worked == FALSE) {
    return FALSE;
  }
  
  return TRUE;
}

// Verify width/height of frame being read from asset

- (void) blockingDecodeVerifySize:(CGFrameBuffer*)frameBuffer
{
  size_t width = frameBuffer.width;
  size_t height = frameBuffer.height;
  
  NSAssert(width > 0, @"width");
  NSAssert(height > 0, @"height");
  
  if (detectedMovieSize.width == 0) {
    detectedMovieSize = CGSizeMake(width, height);
  } else {
    NSAssert(CGSizeEqualToSize(detectedMovieSize, CGSizeMake(width, height)), @"size");
  }
}

// Attempt to read next frame and return a status code to inidcate what
// happened.

- (FrameReadStatus) blockingDecodeReadFrame:(CGFrameBuffer**)frameBufferPtr
                             cvBufferRefPtr:(CVImageBufferRef*)cvBufferRefPtr
{
  BOOL worked;
  
  AVAssetReader *aVAssetReader = self.aVAssetReader;
  
//  AVAssetReaderStatus status = aVAssetReader.status;
//  
//  if ((status == AVAssetReaderStatusCompleted) && (frameIndex == -1)) {
//    // Previous round of decoding got to the end of the asset, it should be
//    // possible to start asset decoding over now.
//    
//#ifdef LOGGING
//    NSLog(@"RESTART condition found with frameIndex %d", self.frameIndex);
//#endif // LOGGING
//    
//    [self restart];
//  }
  
  float frameDurationTooEarly = (self.frameDuration * 0.90);
  
  int frameNum = (int)self.frameIndex + 1;
  
#ifdef LOGGING
  NSLog(@"READING frame %d", frameNum);
#endif // LOGGING
  
  // This logic supports "reading" nop frames that appear after an actual frame.
  
  if (numTrailingNopFrames) {
    numTrailingNopFrames--;
    return FrameReadStatusDup;
  }
  
  // This logic used to be stop the frame reading loop as soon as the asset
  // was no longer in a reading state. Commented out because it no longer
  // appears to be needed, but left here just in case.
  
  //if ([aVAssetReader status] != AVAssetReaderStatusReading) {
  //  return FrameReadStatusDone;
  //}
  
  CMSampleBufferRef sampleBuffer = NULL;
  sampleBuffer = [self.aVAssetReaderOutput copyNextSampleBuffer];
  
  if (sampleBuffer) {
    if (self.produceCoreVideoPixelBuffers) {
      assert(cvBufferRefPtr);
      
      // Extract CoreVideo generic buffere ref (it is typically a CVPixelBufferRef)
      CVImageBufferRef imageBufferRef = CMSampleBufferGetImageBuffer(sampleBuffer);
      assert(imageBufferRef);
      // This code must retain a ref to the CVImageBufferRef (actually a CVPixelBuffer)
      // so that it can be returned to the caller.
      CFRetain(imageBufferRef);
      *cvBufferRefPtr = imageBufferRef;
    } else {
      worked = [self renderIntoFramebuffer:sampleBuffer frameBuffer:frameBufferPtr];
      NSAssert(worked, @"renderIntoFramebuffer worked");
    }
    
    // If the delay between the previous frame and the current frame is more
    // than would be needed for one frame, then emit nop frames.
    
    // If a sample would be displayed for one frame, then the next one should
    // be displayed right away. But, in the case where a sample duration is
    // longer than one frame, emit repeated frames as no-op frames.
    
    CMTime presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    CFRelease(sampleBuffer);
    
    float frameDisplayTime = (float) CMTimeGetSeconds(presentationTimeStamp);
    
    float expectedFrameDisplayTime = frameNum * self.frameDuration;
    
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
      // The actual presentation time has drifted too far from the expected presentation time
      
#ifdef LOGGING
      NSLog(@"frame presentation drifted too early = %0.4f", frameDisplayEarly);
#endif // LOGGING
      
      // Drop the frame, meaning we do not write it to the .mvid file. Instead, let
      // processing continue with the next frame which will display at about the
      // right expected time. The frame number stays the same since no output
      // buffer was written. Note that we need to reset the prevFrameDisplayTime so
      // that no trailing nop frame is emitted in the normal case.
      
      prevFrameDisplayTime = expectedFrameDisplayTime;
      return FrameReadStatusTooEarly;
    }
    
    float delta = frameDisplayTime - prevFrameDisplayTime;
    
#ifdef LOGGING
    NSLog(@"frame display delta %0.4f", delta);
#endif // LOGGING
    
    prevFrameDisplayTime = frameDisplayTime;
    
    // Store the number of trailing frames that appear after this frame
    
    Class cl = AVMvidFileWriter.class;
    numTrailingNopFrames = [cl countTrailingNopFrames:delta frameDuration:self.frameDuration];
    
#ifdef LOGGING
    if (numTrailingNopFrames > 0) {
      NSLog(@"Found %d trailing NOP frames after frame %d", numTrailingNopFrames, (frameNum - 1));
    }
#endif // LOGGING
    
#ifdef LOGGING
    NSLog(@"DONE READING frame %d", frameNum);
#endif // LOGGING
    
    // Note that the frameBuffer object is explicitly retained so that it can
    // be used in each loop iteration.
    
    if (self.produceCoreVideoPixelBuffers == FALSE) {
      [self blockingDecodeVerifySize:*frameBufferPtr];
    }
    
    return FrameReadStatusNextFrame;
  } else if ([aVAssetReader status] == AVAssetReaderStatusReading) {
    AVAssetReaderStatus status = aVAssetReader.status;
    NSError *error = aVAssetReader.error;
    
    NSLog(@"AVAssetReaderStatusReading");
    NSLog(@"status = %d", (int)status);
    NSLog(@"error = %@", [error description]);
  } else {
    // The copyNextSampleBuffer returned nil, so we seem to be done reading from
    // the asset. Check for the special case where a previous frame was displayed
    // at a specific time, but now there are no more frames after that frame.
    // Need to detect the case where 1 to N trailing nop frames appear after
    // the last frame we decoded. There does not apear to be a way to detect the
    // duration of a frame until the next one is decoded, so this is needed
    // to properly handle assets that end with nop frames. Also, it is unclear how
    // a H264 video that include a dup frame like this can be generated, so
    // this code appears to be untested.
    
    float finalFrameExpectedTime = self.numFrames * self.frameDuration;
    float delta = finalFrameExpectedTime - prevFrameDisplayTime;
    
    // Store the number of trailing frames that appear after this frame
    
    Class cl = AVMvidFileWriter.class;
    numTrailingNopFrames = [cl countTrailingNopFrames:delta frameDuration:self.frameDuration];

    if (numTrailingNopFrames > 0) {
      return FrameReadStatusDup;
    }
   
    // FIXME: should [self close] be called in this case ? Or can we at least mark the asset reader with cancelReading ?
    
    return FrameReadStatusDone;
  }
  
  return FrameReadStatusNotReady;
}

// Render sample buffer into flat CGFrameBuffer. We can't read the samples
// directly out of the CVImageBufferRef because the rows of the image
// have some funky padding going on, likely "planar" data from YUV colorspace.
// The caller of this method should provide a location where a single
// frameBuffer can be stored so that multiple calls to this render function
// will make use of the same buffer. Note that the returned frameBuffer
// object is placed in the autorelease pool implicitly.

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
    frameBuffer = [[CGFrameBuffer alloc] initWithBppDimensions:24 width:width height:height];
#if __has_feature(objc_arc)
#else
    frameBuffer = [frameBuffer autorelease];
#endif // objc_arc
    NSAssert(frameBuffer, @"frameBuffer");
    *frameBufferPtr = frameBuffer;

    // Also save allocated framebuffer as a property in the object
    self.currentFrameBuffer = frameBuffer;
    
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
  
  // FIXME: This render operation to flatten the input framebuffer into a known
  // framebuffer layout is 98% of the alpha frame decode time, so optimization
  // would need to start here. Simply not having to copy the buffer or invoke
  // a CG render rountine would likely save most of the execution time. Need
  // to validate the input pixel layout vs the expected layout to determine
  // if we could just memcopy directly and if that would be faster than
  // addressing the data with CG render logic.
  
  [frameBuffer renderCGImage:cgImageRef];
  
  CGImageRelease(cgImageRef);
  
  CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
  
  return TRUE;
}

// Implementing the methods defined in AVFrameDecoder

// This openForReading method provides a standard API for openeing an asset
// given a file path.

- (BOOL) openForReading:(NSString*)assetPath
{
  BOOL worked;
  
  if (self->m_isOpen) {
    return FALSE;
  }
  
  NSAssert(self.aVAssetReader == nil, @"aVAssetReader must be nil");
  
  self.assetURL = [NSURL fileURLWithPath:assetPath];
    
  worked = [self setupAsset];
  if (worked == FALSE) {
    return FALSE;
  }
  
  // Start reading as soon as asset is opened.
  NSAssert(m_isReading == FALSE, @"m_isReading");
  
  if (TRUE) {
    // Start reading from asset, this is only done when the first frame is read.
    // FIXME: it might be better to move this logic into the allocateDecodeResources method
    
    
    worked = [self startReadingAsset];
    if (worked == FALSE) {
      return FALSE;
    }
    
    prevFrameDisplayTime = 0.0;
    
    m_isReading = TRUE;
  }
  
  self->m_isOpen = TRUE;
  self->m_readingFinished = FALSE;
  return TRUE;
}

- (void) close
{
  AVAssetReader *aVAssetReader = self.aVAssetReader;
  // Note that this aVAssetReader can be nil
  [aVAssetReader cancelReading];
  self.aVAssetReaderOutput = nil;
  self.aVAssetReader = nil;
  
  self->frameIndex = -1;
  self.currentFrameBuffer = nil;
  self.lastFrame = nil;
  
  self->m_isOpen = FALSE;
  self->m_isReading = FALSE;
  self->m_readingFinished = TRUE;
  
	return;
}

- (void) rewind
{
  if (!self->m_isOpen) {
    return;
  }
  
  self->frameIndex = -1;
  self.currentFrameBuffer = nil;
  self.lastFrame = nil;
  
  [self restart];
}

- (AVFrame*) advanceToFrame:(NSUInteger)newFrameIndex
{
#ifdef LOGGING
  NSLog(@"advanceToFrame : from %d to %d", frameIndex, newFrameIndex);
#endif // LOGGING
  
  // Check for case of restarting the decoder after it decoded all frames (looping)

#ifdef LOGGING
  AVAssetReaderStatus status = self.aVAssetReader.status;
  switch (status) {
    case AVAssetReaderStatusUnknown:
      NSLog(@"AVAssetReaderStatusUnknown");
      break;
    case AVAssetReaderStatusReading:
      NSLog(@"AVAssetReaderStatusReading");
      break;
    case AVAssetReaderStatusCompleted:
      NSLog(@"AVAssetReaderStatusCompleted");
      break;
    case AVAssetReaderStatusFailed:
      NSLog(@"AVAssetReaderStatusFailed");
      break;
    case AVAssetReaderStatusCancelled:
      NSLog(@"AVAssetReaderStatusCancelled");
      break;
    default:
      break;
  }
#endif // LOGGING

#ifdef LOGGING
  NSLog(@"testing restart condition, frameIndex %d, readingFinished %d", frameIndex, m_readingFinished);
#endif // LOGGING
  
  //if ((status == AVAssetReaderStatusCompleted) && (frameIndex == -1))

  if ((frameIndex == -1) && self->m_readingFinished) {
    // Previous round of decoding got to the end of the asset, it should be
    // possible to start asset decoding over now.
    
#ifdef LOGGING
    NSLog(@"RESTART condition when reading was finished found with frameIndex %d", self.frameIndex);
#endif // LOGGING
    
    [self restart];
  }
  
  // Query the asset reader object again because it could have been changed
  // by a restart above.
  
  AVAssetReader *aVAssetReader = self.aVAssetReader;
  NSAssert(aVAssetReader, @"asset should be open already");

  NSAssert(m_isReading == TRUE, @"asset should be reading already");
  
//  NSLog(@"advanceToFrame : current %d, new %d", (frameIndex + 1), newFrameIndex);
  
  // Examine the frame number we should advance to. Currently, the implementation
  // is limited to advancing to the next frame only.
  
  if ((frameIndex != -1) && (newFrameIndex == frameIndex)) {
    NSAssert(FALSE, @"cannot advance to same frame");
  } else if ((frameIndex != -1) && (newFrameIndex < frameIndex)) {
    // movie frame index can only go forward via advanceToFrame
    NSAssert(FALSE, @"%@: %d -> %d",
             @"can't advance to frame before current frameIndex",
             frameIndex,
             (int)newFrameIndex);
  }
  
  BOOL skippingAhead = (frameIndex + 1) < newFrameIndex;
  int skippingOverNumFrames = (int)(newFrameIndex - (frameIndex + 1));
  if (skippingAhead) {
#ifdef LOGGING
    NSLog(@"skipping ahead : current %d, new %d, skip %d", (frameIndex + 1), newFrameIndex, skippingOverNumFrames);
#endif
  }
  
  // Make sure we do not advance past the last frame
  
  int numFrames = (int) [self numFrames];
  
  if (newFrameIndex >= numFrames) {
    NSAssert(FALSE, @"%@: %d", @"can't advance past last frame", (int)newFrameIndex);
  }
  
  // Decode the frame into a framebuffer.
  
  BOOL changeFrameData = FALSE;
  //BOOL writeFailed = FALSE;
  BOOL doneReadingFrames = FALSE;
  
  //const int newFrameIndexSigned = (int) newFrameIndex;
  
  // Note that this asset frame decoder assumes that only one framebuffer
  // will be in use at any one time, so this logic always drops the ref
  // to the previous frame object which should drop the ref to the image.
  // Also note that this logic does not drop a ref to a cvBuffer ref
  // because it is possible that the optimized execution path could
  // result in an OpenGL renderer that is holding on to a texture
  // via the cvBufferRef.
  
  self.lastFrame.image = nil;
  self.lastFrame.cgFrameBuffer = nil;
  //self.lastFrame.cvBufferRef = NULL;
  self.lastFrame = nil;
  
  // This framebuffer object will be the destination of a render operation
  // for a given frame. Multiple frames must always be the same size,
  // so a common render buffer will be allocated.
  
  CGFrameBuffer *frameBuffer;
  CVImageBufferRef cvBufferRef = NULL;
  
  if (self.produceCoreVideoPixelBuffers) {
    frameBuffer = nil;
  } else {
    frameBuffer = self.currentFrameBuffer;
  }
  
  CVImageBufferRef skipAheadLastGoodBufferRef = NULL;
  
  while (doneReadingFrames == FALSE) @autoreleasepool {
    FrameReadStatus frameReadStatus;
    
    if (cvBufferRef) {
      // Previous loop returned a buffer ref, release it before decoding the next one
      CFRelease(cvBufferRef);
      cvBufferRef = NULL;
    }
    frameReadStatus = [self blockingDecodeReadFrame:&frameBuffer cvBufferRefPtr:&cvBufferRef];
    
    if (frameReadStatus == FrameReadStatusNextFrame) {
      // Read the next frame of data, return as
      
#ifdef LOGGING
      NSLog(@"FrameReadStatusNextFrame");
#endif // LOGGING
      
      if (self.produceCoreVideoPixelBuffers) {
        NSAssert(cvBufferRef, @"cvBufferRef must be returned with FrameReadStatusNextFrame status");
      }
      
      frameIndex++;
      changeFrameData = TRUE;
      doneReadingFrames = TRUE;
      
      if (skippingAhead) {
        // Skipping over frames means that the frame is decoded but then we
        // ignore it. The asset frame decoder does not provide a way to advance
        // to a specific time, so this kind of hackey way to skip ahead is
        // required.
        
#ifdef LOGGING
        NSLog(@"skip over frame condition found for frame %d", frameIndex);
#endif // LOGGING
        
        // A really weird case comes up with skip ahead where the decoder tries to
        // skip ahead but then the last frame comes back as done. In this edge case
        // the decoder needs to hold on to the previous buffer in case skipping
        // ahead returns done.

        if (skipAheadLastGoodBufferRef) {
          CFRelease(skipAheadLastGoodBufferRef);
          skipAheadLastGoodBufferRef = NULL;
        }
        if (skippingAhead) {
          skipAheadLastGoodBufferRef = cvBufferRef;
          CFRetain(skipAheadLastGoodBufferRef);
        }
        
        doneReadingFrames = FALSE;
        
        skippingOverNumFrames -= 1;
        if (skippingOverNumFrames == 0) {
          skippingAhead = FALSE;
        }
      }
    } else if (frameReadStatus == FrameReadStatusDup) {
#ifdef LOGGING
      NSLog(@"FrameReadStatusDup");
#endif // LOGGING
      
      frameIndex++;
      changeFrameData = FALSE;
      doneReadingFrames = TRUE;
    } else if (frameReadStatus == FrameReadStatusTooEarly) {
      // Skip writing of frame that would be displayed too early
      
#ifdef LOGGING
      NSLog(@"FrameReadStatusTooEarly");
#endif // LOGGING
    } else if (frameReadStatus == FrameReadStatusNotReady) {
      // Input was not ready at this point, continue to read
      
#ifdef LOGGING
      NSLog(@"FrameReadStatusNotReady");
#endif // LOGGING
    } else if (frameReadStatus == FrameReadStatusDone) {
      // Reader has returned a status code indicating that no more
      // frames are available.
#ifdef LOGGING
      NSLog(@"FrameReadStatusDone");
#endif // LOGGING
      
      doneReadingFrames = TRUE;
      m_readingFinished = TRUE;
      
#ifdef LOGGING
      NSLog(@"done status : %p : %p", skipAheadLastGoodBufferRef, cvBufferRef);
#endif // LOGGING
      
      if (skipAheadLastGoodBufferRef && (cvBufferRef == nil)) {
        // Skipped over a frame, but then the next frame returned DONE
        cvBufferRef = skipAheadLastGoodBufferRef;
        skipAheadLastGoodBufferRef = NULL;
      }
    } else {
      NSAssert(FALSE, @"unmatched frame status %d", frameReadStatus);
    }
  }
  
  if (m_readingFinished == FALSE) {
    NSAssert(frameIndex == newFrameIndex, @"frameIndex != newFrameIndex, %d != %d", frameIndex, (int)newFrameIndex);
  }
  
  if ((m_readingFinished == FALSE) && (newFrameIndex == (numFrames - 1))) {
#ifdef LOGGING
    NSLog(@"advanced normally to last frame %d", (numFrames - 1));
#endif // LOGGING

    self->m_readingFinished = TRUE;
  }
  
  if (skipAheadLastGoodBufferRef) {
#ifdef LOGGING
    NSLog(@"cleaned up skipAheadLastGoodBufferRef from skip ahead case");
#endif // LOGGING
    
    CFRelease(skipAheadLastGoodBufferRef);
    skipAheadLastGoodBufferRef = NULL;
  }
  
  // Note that we do not release the frameBuffer because it is held as
  // the self.currentFrameBuffer property

  AVFrame *retFrame = nil;
  
  if (!changeFrameData) {
#ifdef LOGGING
    NSLog(@"no change in frame data");
#endif // LOGGING
    
    // When no change from previous frame is found, return a new AVFrame object
    // but make sure to return the same image object as was returned in the last frame.
    
    retFrame = [AVFrame aVFrame];
    NSAssert(retFrame, @"AVFrame is nil");
    
    // The image from the previous rendered frame is returned. Note that it is possible
    // that memory resources could not be mapped and in that case the previous frame
    // could be nil. Return either the last image or nil in this case.
    
    if (self.produceCoreVideoPixelBuffers) {
      // In the case of a duplicate frame in the optimized path, report the dup with
      // an AVFrame object but there is no ref to a CoreVideo path. The optimal path
      // should simply return instead of rendering into the view in this case so that
      // the previous contents of the view would continue to be shown.
    } else {
      // Copy image and cgFrameBuffer from prev frame
      id lastFrameImage = self.lastFrame.image;
      retFrame.image = lastFrameImage;
      
      CGFrameBuffer *cgFrameBuffer = self.currentFrameBuffer;
      retFrame.cgFrameBuffer = cgFrameBuffer;
    }
    
    retFrame.isDuplicate = TRUE;
  } else {
#ifdef LOGGING
    NSLog(@"change in frame data, sending updated AVFame");
#endif // LOGGING
    
    // Delete ref to previous frame to be sure that image ref to framebuffer
    // is dropped before a new one is created.
    
    self.lastFrame = nil;
    
    retFrame = [AVFrame aVFrame];
    NSAssert(retFrame, @"AVFrame is nil");
    
    if (self.produceCoreVideoPixelBuffers) {
      NSAssert(cvBufferRef, @"cvBufferRef is NULL");
      retFrame.cvBufferRef = cvBufferRef;
    } else {
      // Return a CGImage wrapped in a AVFrame
      CGFrameBuffer *cgFrameBuffer = self.currentFrameBuffer;
      retFrame.cgFrameBuffer = cgFrameBuffer;
      [retFrame makeImageFromFramebuffer];
    }
    
    self.lastFrame = retFrame;
  }
  
  if (cvBufferRef) {
    CFRelease(cvBufferRef);
  }
  
  // It should not be possible for both cgFrameBuffer and cvBufferRef to be nil
  
  if (retFrame.isDuplicate == FALSE) {
    if ((retFrame.cgFrameBuffer == nil) && (retFrame.cvBufferRef == NULL)) {
      NSAssert(FALSE, @"both buffer refs are nil");
    }
  }
  
  return retFrame;
}

// nop, since opening the asset allocates resources

- (BOOL) allocateDecodeResources
{
	return TRUE;
}

// nop

- (void) releaseDecodeResources
{
	return;
}

// Return FALSE to indicate that resources are not "limited"

- (BOOL) isResourceUsageLimit
{
	return FALSE;
}

// The duplicateCurrentFrame method can be invoked as part of the normal usage
// where the view is disconnected from the media playback layer but the visual
// representation should remain in the view. For example, when the app is put
// into the background with an animation.

- (AVFrame*) duplicateCurrentFrame
{
  AVFrame *frame = [AVFrame aVFrame];
  frame.cvBufferRef = self.lastFrame.cvBufferRef;
  return frame;
}

// Properties

- (NSUInteger) width
{
  return detectedMovieSize.width;
}

- (NSUInteger) height
{
  return detectedMovieSize.height;
}

- (BOOL) isOpen
{
  return self->m_isOpen;
}

// Total frame count

- (NSUInteger) numFrames
{
  return self->m_numFrames;
}

- (NSInteger) frameIndex
{
  return self->frameIndex;
}

// Gettter for self.frameDuration property

- (NSTimeInterval) frameDuration
{
  float frameDuration = self->m_frameDuration;
  return frameDuration;
}

// Currently, no asset that can be decoded can support an alpha channel

- (BOOL) hasAlphaChannel
{
	return FALSE;
}

// Asset decoding returns only keyframes, but note that currently only 1
// frame can be loaded into memory at a time.

- (BOOL) isAllKeyframes
{
	return TRUE;
}

@end

#endif // HAS_AVASSET_CONVERT_MAXVID
